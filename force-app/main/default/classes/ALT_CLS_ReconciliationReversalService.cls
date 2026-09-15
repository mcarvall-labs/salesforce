/**
 * @description AXF-141: reversal of a single confirmed allocation with a recorded reason. The
 * compensation is the immutable REVERSAL allocation of AXF-25 (ALT_CLS_RealizationService.reverse),
 * linked to the original; nothing confirmed is edited or deleted. Replay by operation key returns
 * the prior compensation; a divergent payload (allocation, version, reason) conflicts. The derived
 * net contribution of plan and source is re-read after the command. Reversing an ACTUAL_ONLY
 * realization never invents forecast debt: the plan keeps its role and its residual stays zero.
 * Boundary: obligation adjustments / recurring-reference recomputation (AXF-104) are not part of
 * this slice — schedule-linked targets are flagged, never adjusted here.
 */
public with sharing class ALT_CLS_ReconciliationReversalService {
  public static final String POLICY_VERSION = 'AXF-REVERSAL@1.0.0';
  public static final String CP_REVERSE = 'AXF_CanReverseReconciliation';
  public static final List<String> REASONS = new List<String>{
    'USER_ERROR',
    'DUPLICATE_LINK',
    'WRONG_TARGET',
    'SOURCE_CHANGED',
    'OTHER'
  };
  public static final Integer DEFAULT_PAGE = 25;
  public static final Integer MAX_PAGE = 50;
  public static final String BOUNDARY_AXF104 = 'AXF104_OBLIGATION_ADJUSTMENT_PENDING';

  public class ReversalException extends Exception {
  }

  public class Input {
    public Id allocationId;
    public Decimal expectedVersion;
    public String reasonCode;
    public String reasonNote;
    public String operationKey;
  }

  public class AllocationView {
    @AuraEnabled
    public Id allocationId;
    @AuraEnabled
    public String kind;
    @AuraEnabled
    public Id targetId;
    @AuraEnabled
    public String targetDescription;
    @AuraEnabled
    public String planKind;
    @AuraEnabled
    public Decimal targetVersion;
    @AuraEnabled
    public Boolean scheduleLinked = false;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public String currencyIso;
    @AuraEnabled
    public Date recognitionDate;
    @AuraEnabled
    public String sourceKind;
    @AuraEnabled
    public Id sourceId;
    @AuraEnabled
    public String fxState;
    @AuraEnabled
    public Id reversalId;
    @AuraEnabled
    public String reversalReason;
    @AuraEnabled
    public Datetime createdAt;
  }

  public class ListQuery {
    public Id accountId;
    public Integer pageNumber;
    public Integer pageSize;
  }

  public class AllocationPage {
    @AuraEnabled
    public String policyVersion = POLICY_VERSION;
    @AuraEnabled
    public Integer pageNumber;
    @AuraEnabled
    public Integer pageSize;
    @AuraEnabled
    public Boolean hasMore = false;
    @AuraEnabled
    public List<AllocationView> items = new List<AllocationView>();
  }

  public class Result {
    @AuraEnabled
    public String policyVersion = POLICY_VERSION;
    @AuraEnabled
    public Id reversalId;
    @AuraEnabled
    public Id originalId;
    @AuraEnabled
    public Boolean replayed = false;
    @AuraEnabled
    public String reasonCode;
    @AuraEnabled
    public Id targetId;
    @AuraEnabled
    public String planKind;
    @AuraEnabled
    public Boolean actualOnly = false;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public String currencyIso;
    @AuraEnabled
    public Decimal plannedAfter;
    @AuraEnabled
    public Decimal realizedAfter;
    @AuraEnabled
    public Decimal residualAfter;
    @AuraEnabled
    public String stateAfter;
    @AuraEnabled
    public Decimal targetVersionAfter;
    @AuraEnabled
    public String sourceKind;
    @AuraEnabled
    public Id sourceId;
    @AuraEnabled
    public Decimal sourceAmount;
    @AuraEnabled
    public Decimal sourceResidualAfter;
    @AuraEnabled
    public List<String> boundaries = new List<String>();
  }

  /** @description Capability plus the AXF-25 capability; neither grants record access. */
  public static void requireAccess() {
    if (
      !FeatureManagement.checkPermission(CP_REVERSE) ||
      !FeatureManagement.checkPermission('AXF_CanRealize')
    ) {
      throw new ReversalException('UNAVAILABLE');
    }
  }

  private static void check(Boolean valid, String code) {
    if (!valid) {
      throw new ReversalException(code);
    }
  }

  private static Set<Id> authorizedAccounts() {
    Set<Id> result = new Set<Id>();
    for (
      AXF_CLS_AuthorizedContextService.ContextView context : AXF_CLS_AuthorizedContextService.listAuthorizedContexts()
    ) {
      result.add(context.accountId);
    }
    return result;
  }

  private static String sourceKind(AXF_OBJ_ReconciliationAllocation__c row) {
    return row.AXF_RA_LKP_BankTransaction__c != null
      ? 'BANK'
      : row.AXF_RA_LKP_CardTransaction__c != null ? 'CARD' : 'CASH';
  }

  private static Id sourceId(AXF_OBJ_ReconciliationAllocation__c row) {
    return row.AXF_RA_LKP_BankTransaction__c != null
      ? row.AXF_RA_LKP_BankTransaction__c
      : row.AXF_RA_LKP_CardTransaction__c != null
          ? row.AXF_RA_LKP_CardTransaction__c
          : row.AXF_RA_LKP_ManualTransaction__c;
  }

  private static AllocationView view(AXF_OBJ_ReconciliationAllocation__c row) {
    AllocationView v = new AllocationView();
    v.allocationId = row.Id;
    v.kind = row.AXF_RA_PKL_Kind__c;
    v.targetId = row.AXF_RA_LKP_FinancialTransaction__c;
    v.targetDescription = row.AXF_RA_LKP_FinancialTransaction__r
      ?.AXF_FTX_TXT_Description__c;
    v.planKind = row.AXF_RA_LKP_FinancialTransaction__r
      ?.AXF_FTX_PKL_PlanKind__c;
    v.targetVersion = row.AXF_RA_LKP_FinancialTransaction__r
        ?.AXF_FTX_NUM_Version__c == null
      ? 0
      : row.AXF_RA_LKP_FinancialTransaction__r.AXF_FTX_NUM_Version__c;
    v.scheduleLinked =
      row.AXF_RA_LKP_FinancialTransaction__r?.AXF_FTX_LKP_Schedule__c != null;
    v.amount = row.AXF_RA_NUM_Magnitude__c;
    v.currencyIso = row.AXF_RA_TXT_CurrencyIsoCode__c;
    v.recognitionDate = row.AXF_RA_DAT_RecognitionDate__c;
    v.sourceKind = sourceKind(row);
    v.sourceId = sourceId(row);
    v.fxState = row.AXF_RA_PKL_FxState__c;
    v.createdAt = row.CreatedDate;
    return v;
  }

  private static final String VIEW_FIELDS =
    'Id, CreatedDate, AXF_RA_PKL_Kind__c, AXF_RA_LKP_FinancialTransaction__c,' +
    ' AXF_RA_LKP_FinancialTransaction__r.AXF_FTX_TXT_Description__c,' +
    ' AXF_RA_LKP_FinancialTransaction__r.AXF_FTX_PKL_PlanKind__c,' +
    ' AXF_RA_LKP_FinancialTransaction__r.AXF_FTX_NUM_Version__c,' +
    ' AXF_RA_LKP_FinancialTransaction__r.AXF_FTX_LKP_Schedule__c,' +
    ' AXF_RA_LKP_FinancialTransaction__r.AXF_FTX_LKP_Account__c,' +
    ' AXF_RA_NUM_Magnitude__c, AXF_RA_TXT_CurrencyIsoCode__c, AXF_RA_DAT_RecognitionDate__c,' +
    ' AXF_RA_LKP_BankTransaction__c, AXF_RA_LKP_CardTransaction__c, AXF_RA_LKP_ManualTransaction__c,' +
    ' AXF_RA_PKL_FxState__c, AXF_RA_LKP_OriginalAllocation__c, AXF_RA_EXI_AllocationKey__c,' +
    ' AXF_RA_PKL_ReversalReason__c, AXF_RA_TXT_ReversalNote__c';

  /** @description Confirmed applications of one authorized holder, newest first, with their reversal when one exists. */
  public AllocationPage listAllocations(ListQuery query) {
    requireAccess();
    check(query != null && query.accountId != null, 'INVALID');
    AllocationPage result = new AllocationPage();
    result.pageNumber = query.pageNumber == null ||
      query.pageNumber < 1
      ? 1
      : query.pageNumber;
    result.pageSize = query.pageSize == null ||
      query.pageSize < 1
      ? DEFAULT_PAGE
      : Math.min(query.pageSize, MAX_PAGE);
    check(authorizedAccounts().contains(query.accountId), 'UNAVAILABLE');
    Integer skip = (result.pageNumber - 1) * result.pageSize;
    Integer take = result.pageSize + 1;
    List<AXF_OBJ_ReconciliationAllocation__c> rows = (List<AXF_OBJ_ReconciliationAllocation__c>) Database.queryWithBinds(
      'SELECT ' +
        VIEW_FIELDS +
        ' FROM AXF_OBJ_ReconciliationAllocation__c' +
        ' WHERE AXF_RA_PKL_Kind__c = \'APPLICATION\'' +
        ' AND AXF_RA_LKP_FinancialTransaction__r.AXF_FTX_LKP_Account__c = :accountId' +
        ' ORDER BY CreatedDate DESC, Id DESC LIMIT :take OFFSET :skip',
      new Map<String, Object>{
        'accountId' => query.accountId,
        'take' => take,
        'skip' => skip
      },
      AccessLevel.USER_MODE
    );
    if (rows.size() > result.pageSize) {
      result.hasMore = true;
      rows.remove(rows.size() - 1);
    }
    Map<Id, AllocationView> byId = new Map<Id, AllocationView>();
    for (AXF_OBJ_ReconciliationAllocation__c row : rows) {
      AllocationView v = view(row);
      byId.put(v.allocationId, v);
      result.items.add(v);
    }
    if (!byId.isEmpty()) {
      for (AXF_OBJ_ReconciliationAllocation__c reversal : [
        SELECT
          Id,
          AXF_RA_LKP_OriginalAllocation__c,
          AXF_RA_PKL_ReversalReason__c
        FROM AXF_OBJ_ReconciliationAllocation__c
        WHERE
          AXF_RA_PKL_Kind__c = 'REVERSAL'
          AND AXF_RA_LKP_OriginalAllocation__c IN :byId.keySet()
        WITH USER_MODE
      ]) {
        AllocationView v = byId.get(reversal.AXF_RA_LKP_OriginalAllocation__c);
        v.reversalId = reversal.Id;
        v.reversalReason = reversal.AXF_RA_PKL_ReversalReason__c;
      }
    }
    return result;
  }

  private AXF_OBJ_ReconciliationAllocation__c allocation(Id allocationId) {
    List<AXF_OBJ_ReconciliationAllocation__c> rows = (List<AXF_OBJ_ReconciliationAllocation__c>) Database.queryWithBinds(
      'SELECT ' +
        VIEW_FIELDS +
        ' FROM AXF_OBJ_ReconciliationAllocation__c WHERE Id = :allocationId',
      new Map<String, Object>{ 'allocationId' => allocationId },
      AccessLevel.USER_MODE
    );
    check(rows.size() == 1, 'UNAVAILABLE');
    check(
      authorizedAccounts()
        .contains(
          rows[0].AXF_RA_LKP_FinancialTransaction__r?.AXF_FTX_LKP_Account__c
        ),
      'UNAVAILABLE'
    );
    return rows[0];
  }

  /** @description Reverses one confirmed application with a reason; replay-safe, nothing edited. */
  public Result reverse(Input input) {
    requireAccess();
    check(
      input != null &&
        input.allocationId != null &&
        !String.isBlank(input.operationKey) &&
        input.operationKey.length() <= 80,
      'INVALID'
    );
    check(
      input.reasonCode != null && REASONS.contains(input.reasonCode),
      'INVALID_REASON'
    );
    check(
      input.reasonNote == null || input.reasonNote.length() <= 255,
      'INVALID'
    );
    String note = String.isBlank(input.reasonNote)
      ? null
      : input.reasonNote.trim();
    AXF_OBJ_ReconciliationAllocation__c original = allocation(
      input.allocationId
    );
    check(original.AXF_RA_PKL_Kind__c == 'APPLICATION', 'INVALID_TARGET');
    String key = AXF_CLS_IdentityFraming.key(
      new List<Object>{ 'AXF25', input.operationKey }
    );
    Result result = new Result();
    result.originalId = original.Id;
    List<AXF_OBJ_ReconciliationAllocation__c> prior = [
      SELECT Id, AXF_RA_EXI_AllocationKey__c
      FROM AXF_OBJ_ReconciliationAllocation__c
      WHERE
        AXF_RA_PKL_Kind__c = 'REVERSAL'
        AND AXF_RA_LKP_OriginalAllocation__c = :original.Id
      WITH USER_MODE
      LIMIT 1
    ];
    // Already reversed under another command: the prior compensation is the answer
    // (read it through priorReversal); no second compensation is ever appended.
    Boolean replay = !prior.isEmpty();
    check(
      !replay || prior[0].AXF_RA_EXI_AllocationKey__c == key,
      'ALREADY_REVERSED'
    );
    Id reversalId;
    try {
      // AXF-25 compares the payload fingerprint (allocation, version, reason) on replay.
      reversalId = new ALT_CLS_RealizationService()
        .reverse(
          original.Id,
          input.expectedVersion,
          input.operationKey,
          input.reasonCode,
          note
        );
    } catch (ALT_CLS_RealizationService.RealizationException failure) {
      throw new ReversalException(failure.getMessage());
    }
    result.replayed = replay;
    result.reversalId = reversalId;
    result.reasonCode = input.reasonCode;
    describe(result, original);
    return result;
  }

  /** @description Prior compensation for an allocation already reversed under another command, or null. */
  public Result priorReversal(Id allocationId) {
    requireAccess();
    AXF_OBJ_ReconciliationAllocation__c original = allocation(allocationId);
    List<AXF_OBJ_ReconciliationAllocation__c> rows = [
      SELECT Id, AXF_RA_PKL_ReversalReason__c
      FROM AXF_OBJ_ReconciliationAllocation__c
      WHERE
        AXF_RA_PKL_Kind__c = 'REVERSAL'
        AND AXF_RA_LKP_OriginalAllocation__c = :original.Id
      WITH USER_MODE
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      return null;
    }
    Result result = new Result();
    result.originalId = original.Id;
    result.reversalId = rows[0].Id;
    result.reasonCode = rows[0].AXF_RA_PKL_ReversalReason__c;
    result.replayed = true;
    describe(result, original);
    return result;
  }

  /** Derived state after the command: plan totals from AXF-25, source residual from visible effects. */
  private void describe(
    Result result,
    AXF_OBJ_ReconciliationAllocation__c original
  ) {
    result.targetId = original.AXF_RA_LKP_FinancialTransaction__c;
    result.amount = original.AXF_RA_NUM_Magnitude__c;
    result.currencyIso = original.AXF_RA_TXT_CurrencyIsoCode__c;
    result.sourceKind = sourceKind(original);
    result.sourceId = sourceId(original);
    ALT_CLS_RealizationService.View plan;
    try {
      plan = new ALT_CLS_RealizationService().read(result.targetId);
    } catch (ALT_CLS_RealizationService.RealizationException failure) {
      throw new ReversalException(failure.getMessage());
    }
    result.planKind = plan.planKind;
    result.actualOnly = plan.planKind == 'ACTUAL_ONLY';
    result.plannedAfter = plan.planned;
    result.realizedAfter = plan.realized;
    result.residualAfter = plan.residual;
    result.stateAfter = plan.state;
    result.targetVersionAfter = plan.version;
    if (
      original.AXF_RA_LKP_FinancialTransaction__r?.AXF_FTX_LKP_Schedule__c !=
      null
    ) {
      // Obligation adjustment / recurring reference recomputation belongs to AXF-104.
      result.boundaries.add(BOUNDARY_AXF104);
    }
    describeSource(result);
  }

  private void describeSource(Result result) {
    String prefix = result.sourceKind == 'BANK'
      ? 'BAT'
      : result.sourceKind == 'CARD' ? 'CCT' : 'FTX';
    String objectName = result.sourceKind == 'BANK'
      ? 'AXF_OBJ_BankAccountTransaction__c'
      : result.sourceKind == 'CARD'
          ? 'AXF_OBJ_CreditCardTransaction__c'
          : 'AXF_OBJ_FinancialTransaction__c';
    List<SObject> rows = Database.queryWithBinds(
      'SELECT AXF_' +
        prefix +
        '_NUM_Magnitude__c FROM ' +
        objectName +
        ' WHERE Id = :sourceId',
      new Map<String, Object>{ 'sourceId' => result.sourceId },
      AccessLevel.USER_MODE
    );
    check(rows.size() == 1, 'UNAVAILABLE');
    result.sourceAmount = (Decimal) rows[0]
      .get('AXF_' + prefix + '_NUM_Magnitude__c');
    Decimal net = 0;
    Id sourceId = result.sourceId;
    for (AXF_OBJ_ReconciliationAllocation__c row : [
      SELECT AXF_RA_PKL_Kind__c, AXF_RA_NUM_Magnitude__c
      FROM AXF_OBJ_ReconciliationAllocation__c
      WHERE
        AXF_RA_LKP_BankTransaction__c = :sourceId
        OR AXF_RA_LKP_CardTransaction__c = :sourceId
        OR AXF_RA_LKP_ManualTransaction__c = :sourceId
      WITH USER_MODE
      LIMIT 2000
    ]) {
      net +=
        (row.AXF_RA_PKL_Kind__c == 'REVERSAL' ? -1 : 1) *
        row.AXF_RA_NUM_Magnitude__c;
    }
    result.sourceResidualAfter = result.sourceAmount == null
      ? null
      : result.sourceAmount - net;
  }
}
