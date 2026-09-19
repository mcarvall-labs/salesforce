/**
 * @description AXF-32: suggest, confirm and reverse the link between the two legs (debit/credit)
 * of one internal transfer between bank accounts of the same holder. Both
 * AXF_OBJ_BankAccountTransaction__c legs stay independent, immutable facts; only the link
 * (AXF_OBJ_InternalTransfer__c / ITR) is created or transitioned here. The principal is
 * neutralized in the consolidated view only by the existence of a CONFIRMED row -- reading that
 * signal into an actual consolidated total is a downstream concern outside this service (AXF-32
 * does not depend on AXF-30/31/142). Confirmation never happens automatically, even on an exact
 * value/date match: a human must confirm the AXF_OBJ_ReviewItem__c TRANSFER_SUGGESTION first.
 * Reversal always appends a new REVERSED row pointing to the original (never edited), same
 * pattern as ALT_CLS_RealizationService.reverse / ALT_CLS_ReconciliationReversalService.
 */
public with sharing class ALT_CLS_InternalTransferService {
  public static final String POLICY_VERSION = 'AXF32-INTERNAL-TRANSFER@1.0.0';
  public static final String CP_CONFIRM = 'AXF_CanConfirmTransfer';
  public static final List<String> REASONS = new List<String>{
    'USER_ERROR',
    'DUPLICATE_LINK',
    'WRONG_TARGET',
    'SOURCE_CHANGED',
    'OTHER'
  };
  private static final String STATE_CANDIDATE = 'CANDIDATE';
  private static final String STATE_UNILATERAL = 'UNILATERAL';
  private static final String STATE_CONFIRMED = 'CONFIRMED';
  private static final String STATE_REVERSED = 'REVERSED';

  public class TransferException extends Exception {
  }

  public class SuggestInput {
    public Id debitTransactionId;
    public Id creditTransactionId;
  }

  public class ConfirmInput {
    public Id internalTransferId;
    public Decimal expectedVersion;
    public String operationKey;
  }

  public class ReverseInput {
    public Id internalTransferId;
    public Decimal expectedVersion;
    public String reasonCode;
    public String reasonNote;
    public String operationKey;
  }

  public class LegView {
    @AuraEnabled
    public Id transactionId;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public String direction;
    @AuraEnabled
    public String currencyIso;
    @AuraEnabled
    public Date onDate;
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String accountName;
  }

  public class TransferView {
    @AuraEnabled
    public String policyVersion = POLICY_VERSION;
    @AuraEnabled
    public Id internalTransferId;
    @AuraEnabled
    public String state;
    @AuraEnabled
    public Decimal version;
    @AuraEnabled
    public LegView debit;
    @AuraEnabled
    public LegView credit;
    @AuraEnabled
    public Datetime confirmedAt;
    @AuraEnabled
    public Datetime reversedAt;
    @AuraEnabled
    public Id originalTransferId;
    @AuraEnabled
    public Id reviewItemId;
    @AuraEnabled
    public Boolean replayed = false;
    @AuraEnabled
    public String reasonCode;
    @AuraEnabled
    public String reasonNote;
  }

  /** @description Capability only; grants no record access. */
  public static void requireAccess() {
    if (!FeatureManagement.checkPermission(CP_CONFIRM)) {
      throw new TransferException('UNAVAILABLE');
    }
  }

  private static void check(Boolean valid, String code) {
    if (!valid) {
      throw new TransferException(code);
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

  private static final String LEG_FIELDS =
    'Id, AXF_BAT_NUM_Magnitude__c, AXF_BAT_PKL_Direction__c, AXF_BAT_TXT_CurrencyIsoCode__c,' +
    ' AXF_BAT_DAT_Date__c, AXF_BAT_TXT_Description__c, AXF_BAT_NUM_Version__c,' +
    ' AXF_BAT_MDR_BankAccount__r.AXF_BA_LKP_Account__c,' +
    ' AXF_BAT_MDR_BankAccount__r.AXF_BA_LKP_Account__r.Name,' +
    ' AXF_BAT_MDR_BankAccount__r.AXF_BA_LKP_Account__r.OwnerId';

  private Map<Id, AXF_OBJ_BankAccountTransaction__c> legs(Set<Id> ids) {
    Map<Id, AXF_OBJ_BankAccountTransaction__c> result = new Map<Id, AXF_OBJ_BankAccountTransaction__c>();
    for (
      AXF_OBJ_BankAccountTransaction__c row : (List<AXF_OBJ_BankAccountTransaction__c>) Database.queryWithBinds(
        'SELECT ' +
          LEG_FIELDS +
          ' FROM AXF_OBJ_BankAccountTransaction__c WHERE Id IN :ids',
        new Map<String, Object>{ 'ids' => ids },
        AccessLevel.USER_MODE
      )
    ) {
      result.put(row.Id, row);
    }
    return result;
  }

  private static LegView view(AXF_OBJ_BankAccountTransaction__c row) {
    LegView v = new LegView();
    v.transactionId = row.Id;
    v.description = row.AXF_BAT_TXT_Description__c;
    v.amount = row.AXF_BAT_NUM_Magnitude__c;
    v.direction = row.AXF_BAT_PKL_Direction__c;
    v.currencyIso = row.AXF_BAT_TXT_CurrencyIsoCode__c;
    v.onDate = row.AXF_BAT_DAT_Date__c;
    v.accountId = row.AXF_BAT_MDR_BankAccount__r?.AXF_BA_LKP_Account__c;
    v.accountName = row.AXF_BAT_MDR_BankAccount__r?.AXF_BA_LKP_Account__r?.Name;
    return v;
  }

  /**
   * @description Proposes a candidate pair: creates the ITR in CANDIDATE plus a
   * TRANSFER_SUGGESTION AXF_OBJ_ReviewItem__c, never linking without human confirmation. Idempotent
   * by NeutralityKey: replaying the same pair returns the existing CANDIDATE, never duplicates. No
   * value/date tolerance is invented here: the two legs must already carry an exact opposite
   * direction and equal magnitude/currency (the caller decides the pair; this service never scans
   * for matches on its own).
   */
  public Id suggest(SuggestInput input) {
    check(
      input != null &&
        input.debitTransactionId != null &&
        input.creditTransactionId != null &&
        input.debitTransactionId != input.creditTransactionId,
      'INVALID'
    );
    Map<Id, AXF_OBJ_BankAccountTransaction__c> byId = legs(
      new Set<Id>{ input.debitTransactionId, input.creditTransactionId }
    );
    check(byId.size() == 2, 'UNAVAILABLE');
    AXF_OBJ_BankAccountTransaction__c debit = byId.get(
      input.debitTransactionId
    );
    AXF_OBJ_BankAccountTransaction__c credit = byId.get(
      input.creditTransactionId
    );
    Id holderId = debit.AXF_BAT_MDR_BankAccount__r?.AXF_BA_LKP_Account__c;
    check(
      holderId != null &&
        holderId == credit.AXF_BAT_MDR_BankAccount__r?.AXF_BA_LKP_Account__c,
      'INVALID'
    );
    check(authorizedAccounts().contains(holderId), 'UNAVAILABLE');
    check(debit.AXF_BAT_PKL_Direction__c == 'DEBIT', 'INVALID');
    check(credit.AXF_BAT_PKL_Direction__c == 'CREDIT', 'INVALID');
    check(
      debit.AXF_BAT_TXT_CurrencyIsoCode__c ==
      credit.AXF_BAT_TXT_CurrencyIsoCode__c,
      'INVALID'
    );
    check(
      debit.AXF_BAT_NUM_Magnitude__c == credit.AXF_BAT_NUM_Magnitude__c,
      'INVALID'
    );
    String key = AXF_CLS_IdentityFraming.key(
      new List<Object>{
        'ITR',
        input.debitTransactionId,
        input.creditTransactionId
      }
    );
    List<AXF_OBJ_InternalTransfer__c> prior = [
      SELECT Id
      FROM AXF_OBJ_InternalTransfer__c
      WHERE AXF_ITR_EXI_NeutralityKey__c = :key
      WITH USER_MODE
      LIMIT 1
    ];
    if (!prior.isEmpty()) {
      return prior[0].Id;
    }
    check(
      [
        SELECT COUNT()
        FROM AXF_OBJ_InternalTransfer__c
        WHERE
          (AXF_ITR_LKP_DebitTransaction__c IN :byId.keySet()
          OR AXF_ITR_LKP_CreditTransaction__c IN :byId.keySet())
          AND AXF_ITR_PKL_State__c IN ('CANDIDATE', 'CONFIRMED', 'UNILATERAL')
        WITH USER_MODE
      ] == 0,
      'LEG_ALREADY_LINKED'
    );
    Savepoint sp = Database.setSavepoint();
    try {
      AXF_OBJ_InternalTransfer__c itr = new AXF_OBJ_InternalTransfer__c(
        AXF_ITR_LKP_DebitTransaction__c = input.debitTransactionId,
        AXF_ITR_LKP_CreditTransaction__c = input.creditTransactionId,
        AXF_ITR_PKL_State__c = STATE_CANDIDATE,
        AXF_ITR_EXI_NeutralityKey__c = key,
        AXF_ITR_NUM_Version__c = 0,
        OwnerId = debit.AXF_BAT_MDR_BankAccount__r.AXF_BA_LKP_Account__r.OwnerId
      );
      Database.insert(itr, AccessLevel.USER_MODE);
      ALT_CLS_ReviewQueueService.CreateInputDTO reviewInput = new ALT_CLS_ReviewQueueService.CreateInputDTO();
      reviewInput.type = 'TRANSFER_SUGGESTION';
      reviewInput.reviewKey = key;
      reviewInput.internalTransferId = itr.Id;
      reviewInput.accountId = holderId;
      reviewInput.bankAccountTransactionId = input.debitTransactionId;
      ALT_CLS_ReviewQueueService.ResultDTO reviewResult = new ALT_CLS_ReviewQueueService()
        .createItem(reviewInput);
      check(reviewResult.success, 'UNAVAILABLE');
      return itr.Id;
    } catch (Exception failure) {
      Database.rollback(sp);
      if (failure instanceof TransferException) {
        throw failure;
      }
      List<AXF_OBJ_InternalTransfer__c> concurrent = [
        SELECT Id
        FROM AXF_OBJ_InternalTransfer__c
        WHERE AXF_ITR_EXI_NeutralityKey__c = :key
        WITH USER_MODE
        LIMIT 1
      ];
      if (!concurrent.isEmpty()) {
        return concurrent[0].Id;
      }
      throw new TransferException('UNAVAILABLE');
    }
  }

  private AXF_OBJ_InternalTransfer__c fetch(Id internalTransferId) {
    List<AXF_OBJ_InternalTransfer__c> rows = [
      SELECT
        Id,
        AXF_ITR_PKL_State__c,
        AXF_ITR_NUM_Version__c,
        AXF_ITR_EXI_NeutralityKey__c,
        AXF_ITR_LKP_DebitTransaction__c,
        AXF_ITR_LKP_CreditTransaction__c,
        AXF_ITR_LKP_OriginalTransfer__c,
        AXF_ITR_TXT_OperationKey__c,
        AXF_ITR_TXT_PayloadHash__c,
        AXF_ITR_DT_ConfirmedAt__c,
        AXF_ITR_DT_ReversedAt__c,
        OwnerId
      FROM AXF_OBJ_InternalTransfer__c
      WHERE Id = :internalTransferId
      WITH USER_MODE
      LIMIT 1
    ];
    check(!rows.isEmpty(), 'UNAVAILABLE');
    AXF_OBJ_InternalTransfer__c row = rows[0];
    Map<Id, AXF_OBJ_BankAccountTransaction__c> byId = legs(
      new Set<Id>{
        row.AXF_ITR_LKP_DebitTransaction__c,
        row.AXF_ITR_LKP_CreditTransaction__c
      }
    );
    check(byId.size() == 2, 'UNAVAILABLE');
    Id holderId = byId.get(row.AXF_ITR_LKP_DebitTransaction__c)
      .AXF_BAT_MDR_BankAccount__r
      ?.AXF_BA_LKP_Account__c;
    check(
      holderId != null && authorizedAccounts().contains(holderId),
      'UNAVAILABLE'
    );
    return row;
  }

  private TransferView view(
    AXF_OBJ_InternalTransfer__c row,
    Map<Id, AXF_OBJ_BankAccountTransaction__c> byId
  ) {
    TransferView v = new TransferView();
    v.internalTransferId = row.Id;
    v.state = row.AXF_ITR_PKL_State__c;
    v.version = row.AXF_ITR_NUM_Version__c;
    v.debit = view(byId.get(row.AXF_ITR_LKP_DebitTransaction__c));
    v.credit = view(byId.get(row.AXF_ITR_LKP_CreditTransaction__c));
    v.confirmedAt = row.AXF_ITR_DT_ConfirmedAt__c;
    v.reversedAt = row.AXF_ITR_DT_ReversedAt__c;
    v.originalTransferId = row.AXF_ITR_LKP_OriginalTransfer__c;
    return v;
  }

  /** @description Redacted read of one transfer; access to both legs is re-validated. */
  public TransferView read(Id internalTransferId) {
    requireAccess();
    AXF_OBJ_InternalTransfer__c row = fetch(internalTransferId);
    Map<Id, AXF_OBJ_BankAccountTransaction__c> byId = legs(
      new Set<Id>{
        row.AXF_ITR_LKP_DebitTransaction__c,
        row.AXF_ITR_LKP_CreditTransaction__c
      }
    );
    return view(row, byId);
  }

  /**
   * @description Confirms a CANDIDATE pair. If a leg is now missing, incompatible, or only
   * partly authorized, the row moves to UNILATERAL instead -- nothing is neutralized and no
   * private existence is revealed beyond the sanitized state. Idempotent by operationKey; a
   * divergent payload under the same key conflicts.
   */
  public TransferView confirm(ConfirmInput input) {
    requireAccess();
    check(
      input != null &&
        input.internalTransferId != null &&
        !String.isBlank(input.operationKey) &&
        input.operationKey.length() <= 80,
      'INVALID'
    );
    check(input.expectedVersion != null, 'INVALID');
    AXF_OBJ_InternalTransfer__c row = fetch(input.internalTransferId);
    check(row.AXF_ITR_LKP_OriginalTransfer__c == null, 'INVALID_TARGET');
    String payload = AXF_CLS_IdentityFraming.key(
      new List<Object>{
        'ITR-CONFIRM',
        input.internalTransferId,
        input.expectedVersion
      }
    );
    // CONFIRMED is a hard terminal here: confirming again is only ever the same replay.
    if (row.AXF_ITR_PKL_State__c == STATE_CONFIRMED) {
      check(
        row.AXF_ITR_TXT_OperationKey__c == input.operationKey,
        'ALREADY_DECIDED'
      );
      check(row.AXF_ITR_TXT_PayloadHash__c == payload, 'CONFLICT');
      Map<Id, AXF_OBJ_BankAccountTransaction__c> confirmedLegs = legs(
        new Set<Id>{
          row.AXF_ITR_LKP_DebitTransaction__c,
          row.AXF_ITR_LKP_CreditTransaction__c
        }
      );
      TransferView replay = view(row, confirmedLegs);
      replay.replayed = true;
      return replay;
    }
    // CANDIDATE or UNILATERAL: the exact same request replays; a fresh operationKey retries
    // (the state stays revisable -- a leg fixed later can turn UNILATERAL into CONFIRMED).
    if (
      row.AXF_ITR_TXT_OperationKey__c != null &&
      row.AXF_ITR_TXT_OperationKey__c == input.operationKey
    ) {
      check(row.AXF_ITR_TXT_PayloadHash__c == payload, 'CONFLICT');
      Map<Id, AXF_OBJ_BankAccountTransaction__c> priorLegs = legs(
        new Set<Id>{
          row.AXF_ITR_LKP_DebitTransaction__c,
          row.AXF_ITR_LKP_CreditTransaction__c
        }
      );
      TransferView replay = view(row, priorLegs);
      replay.replayed = true;
      return replay;
    }
    check(row.AXF_ITR_NUM_Version__c == input.expectedVersion, 'CONFLICT');
    Map<Id, AXF_OBJ_BankAccountTransaction__c> byId = legs(
      new Set<Id>{
        row.AXF_ITR_LKP_DebitTransaction__c,
        row.AXF_ITR_LKP_CreditTransaction__c
      }
    );
    Boolean eligible = byId.size() == 2 && unilateralReasonOrNull(byId) == null;
    Savepoint sp = Database.setSavepoint();
    try {
      AXF_OBJ_InternalTransfer__c change = new AXF_OBJ_InternalTransfer__c(
        Id = row.Id,
        AXF_ITR_PKL_State__c = eligible ? STATE_CONFIRMED : STATE_UNILATERAL,
        AXF_ITR_NUM_Version__c = row.AXF_ITR_NUM_Version__c + 1,
        AXF_ITR_TXT_OperationKey__c = input.operationKey,
        AXF_ITR_TXT_PayloadHash__c = payload,
        AXF_ITR_DT_ConfirmedAt__c = eligible ? System.now() : null
      );
      Database.update(change, AccessLevel.USER_MODE);
      row.AXF_ITR_PKL_State__c = change.AXF_ITR_PKL_State__c;
      row.AXF_ITR_NUM_Version__c = change.AXF_ITR_NUM_Version__c;
      row.AXF_ITR_DT_ConfirmedAt__c = change.AXF_ITR_DT_ConfirmedAt__c;
      if (eligible) {
        resolveReviewItem(row.Id, 'Transferencia interna confirmada.');
      }
      return view(row, byId);
    } catch (Exception failure) {
      Database.rollback(sp);
      if (failure instanceof TransferException) {
        throw failure;
      }
      throw new TransferException('UNAVAILABLE');
    }
  }

  /** Null when both legs are still exact opposites, same currency, and both holders authorized. */
  private String unilateralReasonOrNull(
    Map<Id, AXF_OBJ_BankAccountTransaction__c> byId
  ) {
    if (byId.size() != 2) {
      return 'LEG_MISSING';
    }
    List<AXF_OBJ_BankAccountTransaction__c> rows = byId.values();
    AXF_OBJ_BankAccountTransaction__c a = rows[0];
    AXF_OBJ_BankAccountTransaction__c b = rows[1];
    if (
      a.AXF_BAT_TXT_CurrencyIsoCode__c != b.AXF_BAT_TXT_CurrencyIsoCode__c ||
      a.AXF_BAT_NUM_Magnitude__c != b.AXF_BAT_NUM_Magnitude__c ||
      a.AXF_BAT_PKL_Direction__c == b.AXF_BAT_PKL_Direction__c
    ) {
      return 'VALUE_INCOMPATIBLE';
    }
    Id holderA = a.AXF_BAT_MDR_BankAccount__r?.AXF_BA_LKP_Account__c;
    Id holderB = b.AXF_BAT_MDR_BankAccount__r?.AXF_BA_LKP_Account__c;
    if (holderA == null || holderA != holderB) {
      return 'PARTIAL_AUTHORIZATION';
    }
    Set<Id> authorized = authorizedAccounts();
    if (!authorized.contains(holderA)) {
      return 'PARTIAL_AUTHORIZATION';
    }
    return null;
  }

  private void resolveReviewItem(Id internalTransferId, String note) {
    List<AXF_OBJ_ReviewItem__c> rows = [
      SELECT Id, AXF_RVI_PKL_State__c, AXF_RVI_NUM_Version__c
      FROM AXF_OBJ_ReviewItem__c
      WHERE
        AXF_RVI_LKP_InternalTransfer__c = :internalTransferId
        AND AXF_RVI_PKL_State__c = 'OPEN'
      WITH USER_MODE
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      return;
    }
    ALT_CLS_ReviewQueueService.ResolveInputDTO resolveInput = new ALT_CLS_ReviewQueueService.ResolveInputDTO();
    resolveInput.reviewItemId = rows[0].Id;
    resolveInput.decision = 'RESOLVED';
    resolveInput.note = note;
    resolveInput.expectedVersion = rows[0].AXF_RVI_NUM_Version__c;
    new ALT_CLS_ReviewQueueService().resolve(resolveInput);
  }

  /**
   * @description Reverses one CONFIRMED transfer with a reason: appends a new REVERSED row
   * pointing to the original, which is never edited. Replay by operationKey returns the prior
   * compensation; a divergent payload or a different operationKey over an already reversed pair
   * conflicts.
   */
  public TransferView reverse(ReverseInput input) {
    requireAccess();
    check(
      input != null &&
        input.internalTransferId != null &&
        !String.isBlank(input.operationKey) &&
        input.operationKey.length() <= 80,
      'INVALID'
    );
    check(input.expectedVersion != null, 'INVALID');
    check(
      input.reasonCode != null && REASONS.contains(input.reasonCode),
      'INVALID_REASON'
    );
    String note = String.isBlank(input.reasonNote)
      ? null
      : input.reasonNote.trim();
    check(note == null || note.length() <= 255, 'INVALID');
    AXF_OBJ_InternalTransfer__c original = fetch(input.internalTransferId);
    check(original.AXF_ITR_LKP_OriginalTransfer__c == null, 'INVALID_TARGET');
    check(original.AXF_ITR_PKL_State__c == STATE_CONFIRMED, 'INVALID_TARGET');
    String reversalKey = AXF_CLS_IdentityFraming.key(
      new List<Object>{ 'ITR-REVERSED', original.Id }
    );
    String payload = AXF_CLS_IdentityFraming.key(
      new List<Object>{
        'ITR-REVERSE',
        original.Id,
        input.expectedVersion,
        input.reasonCode,
        note
      }
    );
    List<AXF_OBJ_InternalTransfer__c> existing = [
      SELECT
        Id,
        AXF_ITR_TXT_OperationKey__c,
        AXF_ITR_TXT_PayloadHash__c,
        AXF_ITR_PKL_State__c,
        AXF_ITR_NUM_Version__c,
        AXF_ITR_DT_ConfirmedAt__c,
        AXF_ITR_DT_ReversedAt__c,
        AXF_ITR_PKL_ReversalReason__c,
        AXF_ITR_TXT_ReversalNote__c,
        AXF_ITR_LKP_DebitTransaction__c,
        AXF_ITR_LKP_CreditTransaction__c,
        AXF_ITR_LKP_OriginalTransfer__c
      FROM AXF_OBJ_InternalTransfer__c
      WHERE AXF_ITR_LKP_OriginalTransfer__c = :original.Id
      WITH USER_MODE
      LIMIT 1
    ];
    Map<Id, AXF_OBJ_BankAccountTransaction__c> byId = legs(
      new Set<Id>{
        original.AXF_ITR_LKP_DebitTransaction__c,
        original.AXF_ITR_LKP_CreditTransaction__c
      }
    );
    if (!existing.isEmpty()) {
      AXF_OBJ_InternalTransfer__c prior = existing[0];
      check(
        prior.AXF_ITR_TXT_OperationKey__c == input.operationKey,
        'ALREADY_REVERSED'
      );
      check(prior.AXF_ITR_TXT_PayloadHash__c == payload, 'CONFLICT');
      TransferView replay = view(prior, byId);
      replay.replayed = true;
      replay.reasonCode = prior.AXF_ITR_PKL_ReversalReason__c;
      replay.reasonNote = prior.AXF_ITR_TXT_ReversalNote__c;
      return replay;
    }
    check(original.AXF_ITR_NUM_Version__c == input.expectedVersion, 'CONFLICT');
    Savepoint sp = Database.setSavepoint();
    try {
      AXF_OBJ_InternalTransfer__c reversal = new AXF_OBJ_InternalTransfer__c(
        AXF_ITR_LKP_DebitTransaction__c = original.AXF_ITR_LKP_DebitTransaction__c,
        AXF_ITR_LKP_CreditTransaction__c = original.AXF_ITR_LKP_CreditTransaction__c,
        AXF_ITR_PKL_State__c = STATE_REVERSED,
        AXF_ITR_EXI_NeutralityKey__c = reversalKey,
        AXF_ITR_NUM_Version__c = 0,
        AXF_ITR_LKP_OriginalTransfer__c = original.Id,
        AXF_ITR_DT_ReversedAt__c = System.now(),
        AXF_ITR_TXT_OperationKey__c = input.operationKey,
        AXF_ITR_TXT_PayloadHash__c = payload,
        AXF_ITR_PKL_ReversalReason__c = input.reasonCode,
        AXF_ITR_TXT_ReversalNote__c = note,
        OwnerId = original.OwnerId
      );
      Database.insert(reversal, AccessLevel.USER_MODE);
      TransferView result = view(reversal, byId);
      result.originalTransferId = original.Id;
      result.reasonCode = input.reasonCode;
      result.reasonNote = note;
      return result;
    } catch (Exception failure) {
      Database.rollback(sp);
      if (failure instanceof TransferException) {
        throw failure;
      }
      // Concurrent reversal winning the unique NeutralityKey race lands here too.
      throw new TransferException('CONFLICT');
    }
  }
}
