/**
 * @description AXF-142: orchestrates the composite reversal of every confirmed `APPLICATION`
 * allocation of one composite `AXF_OBJ_Reconciliation__c`/RCN. It coordinates N sequential calls to
 * the already-tested single-allocation primitive (`ALT_CLS_ReconciliationReversalService.reverse`,
 * AXF-141) under one Savepoint of its own, taken before the first call: any failure among the N
 * calls rolls back every reversal already applied in this same operation (not the internal
 * Savepoint of `reverse()`), so the RCN never rests with a partial compensation. `CONFIRMED ->
 * REVERSING` is applied before the first call; `REVERSING -> REVERSED` only once all N calls
 * succeed. Nothing about the per-line compensation logic (AXF-25/AXF-141) is duplicated here.
 */
public with sharing class ALT_CLS_CompositeReversalService {
  public static final String POLICY_VERSION = 'AXF-COMPOSITE-REVERSAL@1.0.0';
  public static final String STATE_CONFIRMED = ALT_CLS_ReconciliationService.STATE_CONFIRMED;
  public static final String STATE_REVERSING = 'REVERSING';
  public static final String STATE_REVERSED = 'REVERSED';

  public class CompositeReversalException extends Exception {
  }

  public class Input {
    public Id reconciliationId;
    public Decimal expectedVersion;
    public String reasonCode;
    public String reasonNote;
    public String operationKey;
  }

  public class LineResult {
    @AuraEnabled
    public Id allocationId;
    @AuraEnabled
    public Id reversalId;
    @AuraEnabled
    public Boolean replayed = false;
  }

  public class Result {
    @AuraEnabled
    public String policyVersion = POLICY_VERSION;
    @AuraEnabled
    public Id reconciliationId;
    @AuraEnabled
    public String state;
    @AuraEnabled
    public Decimal version;
    @AuraEnabled
    public Boolean replayed = false;
    @AuraEnabled
    public List<LineResult> lines = new List<LineResult>();
  }

  public class RcnView {
    @AuraEnabled
    public Id reconciliationId;
    @AuraEnabled
    public String state;
    @AuraEnabled
    public Decimal version;
    @AuraEnabled
    public List<ALT_CLS_ReconciliationReversalService.AllocationView> allocations = new List<ALT_CLS_ReconciliationReversalService.AllocationView>();
  }

  private static void check(Boolean valid, String code) {
    if (!valid) {
      throw new CompositeReversalException(code);
    }
  }

  /** @description Same access gate as AXF-141: neither capability grants record access alone. */
  public static void requireAccess() {
    ALT_CLS_ReconciliationReversalService.requireAccess();
  }

  private static final String VIEW_FIELDS =
    'Id, CreatedDate, AXF_RA_PKL_Kind__c, AXF_RA_LKP_FinancialTransaction__c,' +
    ' AXF_RA_LKP_FinancialTransaction__r.AXF_FTX_TXT_Description__c,' +
    ' AXF_RA_LKP_FinancialTransaction__r.AXF_FTX_PKL_PlanKind__c,' +
    ' AXF_RA_LKP_FinancialTransaction__r.AXF_FTX_NUM_Version__c,' +
    ' AXF_RA_LKP_FinancialTransaction__r.AXF_FTX_LKP_Schedule__c,' +
    ' AXF_RA_NUM_Magnitude__c, AXF_RA_TXT_CurrencyIsoCode__c, AXF_RA_DAT_RecognitionDate__c,' +
    ' AXF_RA_LKP_BankTransaction__c, AXF_RA_LKP_CardTransaction__c, AXF_RA_LKP_ManualTransaction__c,' +
    ' AXF_RA_LKP_BankTransaction__r.AXF_BAT_TXT_Description__c, AXF_RA_LKP_BankTransaction__r.AXF_BAT_DAT_Date__c,' +
    ' AXF_RA_LKP_CardTransaction__r.AXF_CCT_TXT_Description__c, AXF_RA_LKP_CardTransaction__r.AXF_CCT_DAT_Date__c,' +
    ' AXF_RA_LKP_ManualTransaction__r.AXF_FTX_TXT_Description__c, AXF_RA_LKP_ManualTransaction__r.AXF_FTX_DAT_PurchaseDate__c,' +
    ' AXF_RA_PKL_FxState__c, AXF_RA_LKP_OriginalAllocation__c, AXF_RA_EXI_AllocationKey__c,' +
    ' AXF_RA_PKL_ReversalReason__c, AXF_RA_TXT_ReversalNote__c';

  private static String sourceKind(AXF_OBJ_ReconciliationAllocation__c row) {
    return row.AXF_RA_LKP_BankTransaction__c != null
      ? 'BANK'
      : row.AXF_RA_LKP_CardTransaction__c != null ? 'CARD' : 'MANUAL';
  }

  private static Id sourceId(AXF_OBJ_ReconciliationAllocation__c row) {
    return row.AXF_RA_LKP_BankTransaction__c != null
      ? row.AXF_RA_LKP_BankTransaction__c
      : row.AXF_RA_LKP_CardTransaction__c != null
          ? row.AXF_RA_LKP_CardTransaction__c
          : row.AXF_RA_LKP_ManualTransaction__c;
  }

  /** @description Mirrors the shape of AXF-141's picker view; independently maintained here since
   * AXF-141's own mapping is private and unreachable from this class. */
  private static ALT_CLS_ReconciliationReversalService.AllocationView view(
    AXF_OBJ_ReconciliationAllocation__c row
  ) {
    ALT_CLS_ReconciliationReversalService.AllocationView v = new ALT_CLS_ReconciliationReversalService.AllocationView();
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
    if (row.AXF_RA_LKP_BankTransaction__c != null) {
      v.sourceDescription = row.AXF_RA_LKP_BankTransaction__r
        ?.AXF_BAT_TXT_Description__c;
      v.sourceDate = row.AXF_RA_LKP_BankTransaction__r?.AXF_BAT_DAT_Date__c;
    } else if (row.AXF_RA_LKP_CardTransaction__c != null) {
      v.sourceDescription = row.AXF_RA_LKP_CardTransaction__r
        ?.AXF_CCT_TXT_Description__c;
      v.sourceDate = row.AXF_RA_LKP_CardTransaction__r?.AXF_CCT_DAT_Date__c;
    } else {
      v.sourceDescription = row.AXF_RA_LKP_ManualTransaction__r
        ?.AXF_FTX_TXT_Description__c;
      v.sourceDate = row.AXF_RA_LKP_ManualTransaction__r
        ?.AXF_FTX_DAT_PurchaseDate__c;
    }
    return v;
  }

  private AXF_OBJ_Reconciliation__c rcn(
    Id reconciliationId,
    Boolean forUpdate
  ) {
    List<AXF_OBJ_Reconciliation__c> rows = Database.queryWithBinds(
      'SELECT Id, AXF_RCN_PKL_State__c, AXF_RCN_NUM_Version__c' +
        ' FROM AXF_OBJ_Reconciliation__c WHERE Id = :reconciliationId' +
        (forUpdate ? ' FOR UPDATE' : ''),
      new Map<String, Object>{ 'reconciliationId' => reconciliationId },
      AccessLevel.USER_MODE
    );
    check(rows.size() == 1, 'NOT_ACCESSIBLE');
    return rows[0];
  }

  private List<AXF_OBJ_ReconciliationAllocation__c> applications(
    Id reconciliationId
  ) {
    return (List<AXF_OBJ_ReconciliationAllocation__c>) Database.queryWithBinds(
      'SELECT ' +
        VIEW_FIELDS +
        ' FROM AXF_OBJ_ReconciliationAllocation__c' +
        ' WHERE AXF_RA_LKP_Reconciliation__c = :reconciliationId' +
        ' AND AXF_RA_PKL_Kind__c = \'APPLICATION\'' +
        ' ORDER BY Id',
      new Map<String, Object>{ 'reconciliationId' => reconciliationId },
      AccessLevel.USER_MODE
    );
  }

  public class RcnSummary {
    @AuraEnabled
    public Id reconciliationId;
    @AuraEnabled
    public String state;
    @AuraEnabled
    public Decimal version;
    @AuraEnabled
    public Integer allocationCount;
  }

  /** @description Confirmed or already-reversed aggregates of one authorized holder, for the picker. */
  public List<RcnSummary> listReconciliations(Id accountId) {
    requireAccess();
    check(accountId != null, 'INVALID');
    Map<Id, Integer> byRcn = new Map<Id, Integer>();
    for (AggregateResult row : [
      SELECT AXF_RA_LKP_Reconciliation__c rcnId, COUNT(Id) total
      FROM AXF_OBJ_ReconciliationAllocation__c
      WHERE
        AXF_RA_LKP_FinancialTransaction__r.AXF_FTX_LKP_Account__c = :accountId
        AND AXF_RA_PKL_Kind__c = 'APPLICATION'
        AND AXF_RA_LKP_Reconciliation__c != NULL
      WITH USER_MODE
      GROUP BY AXF_RA_LKP_Reconciliation__c
    ]) {
      byRcn.put((Id) row.get('rcnId'), (Integer) row.get('total'));
    }
    List<RcnSummary> result = new List<RcnSummary>();
    if (byRcn.isEmpty()) {
      return result;
    }
    for (AXF_OBJ_Reconciliation__c row : [
      SELECT Id, AXF_RCN_PKL_State__c, AXF_RCN_NUM_Version__c
      FROM AXF_OBJ_Reconciliation__c
      WHERE
        Id IN :byRcn.keySet()
        AND AXF_RCN_PKL_State__c IN ('CONFIRMED', 'REVERSING', 'REVERSED')
      WITH USER_MODE
      ORDER BY CreatedDate DESC
    ]) {
      RcnSummary summary = new RcnSummary();
      summary.reconciliationId = row.Id;
      summary.state = row.AXF_RCN_PKL_State__c;
      summary.version = row.AXF_RCN_NUM_Version__c == null
        ? 0
        : row.AXF_RCN_NUM_Version__c;
      summary.allocationCount = byRcn.get(row.Id);
      result.add(summary);
    }
    return result;
  }

  /** @description Every confirmed application of one composite RCN, for the reversal picker. */
  public RcnView listAllocations(Id reconciliationId) {
    requireAccess();
    check(reconciliationId != null, 'INVALID');
    AXF_OBJ_Reconciliation__c aggregate = rcn(reconciliationId, false);
    RcnView result = new RcnView();
    result.reconciliationId = aggregate.Id;
    result.state = aggregate.AXF_RCN_PKL_State__c;
    result.version = aggregate.AXF_RCN_NUM_Version__c == null
      ? 0
      : aggregate.AXF_RCN_NUM_Version__c;
    for (
      AXF_OBJ_ReconciliationAllocation__c row : applications(reconciliationId)
    ) {
      result.allocations.add(view(row));
    }
    return result;
  }

  private static Decimal targetVersionOf(Id targetId) {
    List<AXF_OBJ_FinancialTransaction__c> rows = [
      SELECT AXF_FTX_NUM_Version__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE Id = :targetId
      WITH USER_MODE
      LIMIT 1
    ];
    check(!rows.isEmpty(), 'NOT_ACCESSIBLE');
    return rows[0].AXF_FTX_NUM_Version__c == null
      ? 0
      : rows[0].AXF_FTX_NUM_Version__c;
  }

  /**
   * @description Reverses every `APPLICATION` of a composite RCN atomically: N sequential calls to
   * the AXF-141 primitive, under one Savepoint of the orchestrator's own. `CONFIRMED -> REVERSING`
   * before the first call, `-> REVERSED` only once all N succeed; any failure rolls back every
   * reversal already applied in this same operation, so the RCN is never left partially reverted.
   * Replay of an already-`REVERSED` RCN re-runs the same per-line calls (each one individually
   * idempotent by its own derived `operationKey`, AXF-141) without moving the RCN state again.
   */
  public Result reverse(Input input) {
    requireAccess();
    check(
      input != null &&
        input.reconciliationId != null &&
        input.expectedVersion != null &&
        String.isNotBlank(input.reasonCode) &&
        ALT_CLS_ReconciliationReversalService.REASONS.contains(
          input.reasonCode
        ) &&
        String.isNotBlank(input.operationKey) &&
        input.operationKey.length() <= 80,
      'INVALID'
    );
    // Trim first, then bound: a note that fits once trimmed is accepted (same as AXF-141).
    String note = String.isBlank(input.reasonNote)
      ? null
      : input.reasonNote.trim();
    check(note == null || note.length() <= 255, 'INVALID');
    AXF_OBJ_Reconciliation__c aggregate = rcn(input.reconciliationId, true);
    List<AXF_OBJ_ReconciliationAllocation__c> apps = applications(
      input.reconciliationId
    );
    check(!apps.isEmpty(), 'INVALID_TARGET');
    check(apps.size() <= ALT_CLS_ReconciliationService.MAX_LINES, 'INVALID');
    Boolean replay = STATE_REVERSED.equals(aggregate.AXF_RCN_PKL_State__c);
    // Never: BLOCKED/PARTIAL/FAILED (and a stuck REVERSING left by a crash without rollback) are
    // never touched here — the retry stays refused until an authoritative resolution, same
    // discipline as GF-75.
    check(
      replay || STATE_CONFIRMED.equals(aggregate.AXF_RCN_PKL_State__c),
      'CONFLICT'
    );
    if (!replay) {
      check(
        input.expectedVersion ==
        (aggregate.AXF_RCN_NUM_Version__c == null
          ? 0
          : aggregate.AXF_RCN_NUM_Version__c),
        'CONFLICT'
      );
    }
    // One Savepoint around the whole composite operation: a failure on any of the N calls unwinds
    // every reversal already applied in this same operation, never the internal Savepoint of
    // ALT_CLS_ReconciliationReversalService.reverse().
    Savepoint sp = Database.setSavepoint();
    try {
      if (!replay) {
        aggregate.AXF_RCN_PKL_State__c = STATE_REVERSING;
        aggregate.AXF_RCN_NUM_Version__c =
          (aggregate.AXF_RCN_NUM_Version__c == null
            ? 0
            : aggregate.AXF_RCN_NUM_Version__c) + 1;
        Database.update(aggregate, AccessLevel.USER_MODE);
      }
      Result result = new Result();
      result.reconciliationId = aggregate.Id;
      ALT_CLS_ReconciliationReversalService reversal = new ALT_CLS_ReconciliationReversalService();
      for (AXF_OBJ_ReconciliationAllocation__c app : apps) {
        LineResult lr = new LineResult();
        lr.allocationId = app.Id;
        if (replay) {
          // The RCN is already REVERSED: AXF-141's own version-checked payload fingerprint means
          // a second `reverse()` call with a freshly-read (already-bumped) target version would
          // never match the original payload hash and would answer CONFLICT instead of replaying.
          // The durable compensation is the answer, read back exactly as AXF-141 already exposes
          // it for a "reversed under another command" allocation — nothing is recomputed.
          ALT_CLS_ReconciliationReversalService.Result prior = reversal.priorReversal(
            app.Id
          );
          check(prior != null, 'CONFLICT');
          lr.reversalId = prior.reversalId;
          lr.replayed = true;
        } else {
          ALT_CLS_ReconciliationReversalService.Input line = new ALT_CLS_ReconciliationReversalService.Input();
          line.allocationId = app.Id;
          line.expectedVersion = targetVersionOf(
            app.AXF_RA_LKP_FinancialTransaction__c
          );
          line.reasonCode = input.reasonCode;
          line.reasonNote = note;
          // Fixed-length hash: concatenating and truncating input.operationKey + ':' + app.Id
          // would collide across lines whenever the caller's key is near the 80-char ceiling.
          line.operationKey = AXF_CLS_IdentityFraming.key(
            new List<Object>{ input.operationKey, app.Id }
          );
          ALT_CLS_ReconciliationReversalService.Result lineResult;
          try {
            lineResult = reversal.reverse(line);
          } catch (ALT_CLS_ReconciliationReversalService.ReversalException failure) {
            throw new CompositeReversalException(failure.getMessage());
          }
          lr.reversalId = lineResult.reversalId;
          lr.replayed = lineResult.replayed;
        }
        result.lines.add(lr);
      }
      if (!replay) {
        aggregate.AXF_RCN_PKL_State__c = STATE_REVERSED;
        aggregate.AXF_RCN_NUM_Version__c =
          (aggregate.AXF_RCN_NUM_Version__c == null
            ? 0
            : aggregate.AXF_RCN_NUM_Version__c) + 1;
        Database.update(aggregate, AccessLevel.USER_MODE);
      }
      result.state = aggregate.AXF_RCN_PKL_State__c;
      result.version = aggregate.AXF_RCN_NUM_Version__c;
      result.replayed = replay;
      return result;
    } catch (CompositeReversalException failure) {
      Database.rollback(sp);
      throw failure;
    } catch (Exception failure) {
      Database.rollback(sp);
      throw new CompositeReversalException('UNAVAILABLE');
    }
  }
}
