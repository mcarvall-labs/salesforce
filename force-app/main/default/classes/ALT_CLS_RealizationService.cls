/** @description Atomic manual realization, immutable compensation and reporting recovery (AXF-25). */
public with sharing class ALT_CLS_RealizationService {
  private static Boolean writing = false;
  /** @description Read-only trigger capability; callers cannot enable writes. */
  public static Boolean isWriting() {
    return writing;
  }
  public class RealizationException extends Exception {
  }
  public class Input {
    public Id targetId;
    public Id accountId;
    public Id sourceId;
    public String sourceKind;
    public Id fundingId;
    public Decimal amount;
    public String currencyIso;
    public String direction;
    public Date recognitionDate;
    public Decimal targetVersion;
    public Decimal sourceVersion;
    public String operationKey;
  }
  public class View {
    public Id targetId;
    public Decimal version;
    public String currencyIso;
    public String planKind;
    public Decimal planned;
    public Decimal realized;
    public Decimal residual;
    public Decimal reportingAmount;
    public String reportingIso;
    public Boolean pendingFx;
    public String state;
    public List<AXF_OBJ_ReconciliationAllocation__c> allocations;
  }
  private static final String RA_FIELDS = 'Id,Name,AXF_RA_LKP_FinancialTransaction__c,AXF_RA_LKP_BankTransaction__c,AXF_RA_LKP_CardTransaction__c,AXF_RA_LKP_ManualTransaction__c,AXF_RA_LKP_OriginalAllocation__c,AXF_RA_LKP_FxSnapshot__c,AXF_RA_NUM_Magnitude__c,AXF_RA_TXT_CurrencyIsoCode__c,AXF_RA_DAT_RecognitionDate__c,AXF_RA_EXI_AllocationKey__c,AXF_RA_TXT_PayloadHash__c,AXF_RA_PKL_Kind__c,AXF_RA_PKL_FxState__c,AXF_RA_TXT_ReportingIso__c,AXF_RA_NUM_ReportingAmount__c';
  private static final String FTX_FIELDS = 'Id,AXF_FTX_LKP_Account__c,AXF_FTX_NUM_Magnitude__c,AXF_FTX_TXT_CurrencyIsoCode__c,AXF_FTX_PKL_Direction__c,AXF_FTX_DAT_PurchaseDate__c,AXF_FTX_NUM_Version__c,AXF_FTX_PKL_PlanKind__c,AXF_FTX_LKP_BankAccount__c,AXF_FTX_LKP_CreditCard__c';

  /** @description All mutations and reads require this explicit capability plus native record access. */
  public static void requireAccess() {
    if (!FeatureManagement.checkPermission('AXF_CanRealize')) {
      throw new RealizationException('UNAVAILABLE');
    }
  }
  private static String hash(List<Object> values) {
    return AXF_CLS_IdentityFraming.key(values);
  }
  private static Decimal version(Decimal value) {
    return value == null ? 0 : value;
  }
  private static void check(Boolean valid, String code) {
    if (!valid) {
      throw new RealizationException(code);
    }
  }
  private static void authorizeAccount(Id accountId) {
    Boolean allowed = false;
    for (
      AXF_CLS_AuthorizedContextService.ContextView context : AXF_CLS_AuthorizedContextService.listAuthorizedContexts()
    ) {
      if (context.accountId == accountId) {
        allowed = true;
      }
    }
    check(allowed, 'UNAVAILABLE');
  }
  private AXF_OBJ_FinancialTransaction__c target(Id targetId, Boolean lockRow) {
    List<SObject> rows = Database.queryWithBinds(
      'SELECT ' +
        FTX_FIELDS +
        ' FROM AXF_OBJ_FinancialTransaction__c WHERE Id = :targetId' +
        (lockRow ? ' FOR UPDATE' : ''),
      new Map<String, Object>{ 'targetId' => targetId },
      AccessLevel.USER_MODE
    );
    check(rows.size() == 1, 'UNAVAILABLE');
    AXF_OBJ_FinancialTransaction__c row = (AXF_OBJ_FinancialTransaction__c) rows[0];
    check(row.AXF_FTX_PKL_PlanKind__c != 'CASH_FACT', 'INVALID_ROLE');
    authorizeAccount(row.AXF_FTX_LKP_Account__c);
    return row;
  }
  private class Source {
    public SObject record;
    public Id accountId;
    public String prefix;
    public Decimal amount;
    public String iso;
    public String direction;
    public Decimal currentVersion;
  }
  private Source source(Id sourceId, String kind, Boolean lockRow) {
    check(
      new Set<String>{ 'CASH', 'BANK', 'CARD' }.contains(kind),
      'INVALID_SOURCE'
    );
    String prefix = kind == 'CASH' ? 'FTX' : kind == 'BANK' ? 'BAT' : 'CCT';
    String objectName = kind == 'CASH'
      ? 'AXF_OBJ_FinancialTransaction__c'
      : kind == 'BANK'
          ? 'AXF_OBJ_BankAccountTransaction__c'
          : 'AXF_OBJ_CreditCardTransaction__c';
    String parent = kind == 'BANK'
      ? 'AXF_BAT_MDR_BankAccount__r.AXF_BA_LKP_Account__c'
      : 'AXF_CCT_MDR_CreditCard__r.AXF_CC_LKP_Account__c';
    String fields = kind == 'CASH'
      ? FTX_FIELDS
      : 'Id,AXF_' +
        prefix +
        '_NUM_Magnitude__c,AXF_' +
        prefix +
        '_TXT_CurrencyIsoCode__c,AXF_' +
        prefix +
        '_PKL_Direction__c,AXF_' +
        prefix +
        '_NUM_Version__c,' +
        parent;
    List<SObject> rows = Database.queryWithBinds(
      'SELECT ' +
        fields +
        ' FROM ' +
        objectName +
        ' WHERE Id = :sourceId' +
        (lockRow ? ' FOR UPDATE' : ''),
      new Map<String, Object>{ 'sourceId' => sourceId },
      AccessLevel.USER_MODE
    );
    check(rows.size() == 1, 'UNAVAILABLE');
    Source result = new Source();
    result.record = rows[0];
    result.prefix = prefix;
    if (kind == 'CASH') {
      check(
        (String) rows[0].get('AXF_FTX_PKL_PlanKind__c') == 'CASH_FACT',
        'INVALID_ROLE'
      );
      result.accountId = (Id) rows[0].get('AXF_FTX_LKP_Account__c');
    } else {
      result.accountId = (Id) rows[0]
        .getSObject(parent.substringBefore('.'))
        .get(parent.substringAfter('.'));
    }
    authorizeAccount(result.accountId);
    result.amount = (Decimal) rows[0]
      .get('AXF_' + prefix + '_NUM_Magnitude__c');
    result.iso = (String) rows[0]
      .get('AXF_' + prefix + '_TXT_CurrencyIsoCode__c');
    result.direction = (String) rows[0]
      .get('AXF_' + prefix + '_PKL_Direction__c');
    result.currentVersion = version(
      (Decimal) rows[0].get('AXF_' + prefix + '_NUM_Version__c')
    );
    return result;
  }
  private String kind(AXF_OBJ_ReconciliationAllocation__c row) {
    return row.AXF_RA_LKP_BankTransaction__c != null
      ? 'BANK'
      : row.AXF_RA_LKP_CardTransaction__c != null ? 'CARD' : 'CASH';
  }
  /** @description Captures the authorized source version before a user confirms an application. */
  public Decimal sourceVersion(Id factId, String factKind) {
    requireAccess();
    return source(factId, factKind, false).currentVersion;
  }
  private Id sourceId(AXF_OBJ_ReconciliationAllocation__c row) {
    return row.AXF_RA_LKP_BankTransaction__c != null
      ? row.AXF_RA_LKP_BankTransaction__c
      : row.AXF_RA_LKP_CardTransaction__c != null
          ? row.AXF_RA_LKP_CardTransaction__c
          : row.AXF_RA_LKP_ManualTransaction__c;
  }
  private List<AXF_OBJ_ReconciliationAllocation__c> allocations(
    String whereClause,
    Map<String, Object> binds
  ) {
    return (List<AXF_OBJ_ReconciliationAllocation__c>) Database.queryWithBinds(
      'SELECT ' +
        RA_FIELDS +
        ' FROM AXF_OBJ_ReconciliationAllocation__c WHERE ' +
        whereClause,
      binds,
      AccessLevel.USER_MODE
    );
  }
  private AXF_OBJ_ReconciliationAllocation__c allocation(Id allocationId) {
    List<AXF_OBJ_ReconciliationAllocation__c> rows = allocations(
      'Id = :allocationId',
      new Map<String, Object>{ 'allocationId' => allocationId }
    );
    check(rows.size() == 1, 'UNAVAILABLE');
    return rows[0];
  }

  /** @description Applies once under target-then-source locks; failures roll back every effect. */
  public Id apply(Input input) {
    requireAccess();
    check(
      input != null &&
        !String.isBlank(input.operationKey) &&
        input.operationKey.length() <= 80,
      'INVALID'
    );
    check(
      input.amount != null &&
        input.amount > 0 &&
        input.amount == input.amount.setScale(2) &&
        input.recognitionDate != null,
      'INVALID'
    );
    check(
      new Set<String>{ 'CASH', 'BANK', 'CARD' }.contains(input.sourceKind),
      'INVALID_SOURCE'
    );
    check(input.sourceId == null || input.fundingId == null, 'INVALID_SOURCE');
    check(
      input.sourceKind != 'CASH' || input.fundingId == null,
      'INVALID_SOURCE'
    );
    String operation = hash(new List<Object>{ 'AXF25', input.operationKey });
    String payload = hash(
      new List<Object>{
        'APPLICATION',
        input.targetId,
        input.accountId,
        input.sourceId,
        input.sourceKind,
        input.fundingId,
        input.amount,
        input.currencyIso,
        input.direction,
        input.recognitionDate,
        input.targetVersion,
        input.sourceVersion
      }
    );
    Savepoint sp = Database.setSavepoint();
    try {
      writing = true;
      Id holderId = input.targetId == null
        ? input.accountId
        : target(input.targetId, false).AXF_FTX_LKP_Account__c;
      authorizeAccount(holderId);
      // Native holder lock serializes first writes before the idempotency lookup.
      List<SObject> holders = Database.queryWithBinds(
        'SELECT Id FROM Account WHERE Id=:holderId FOR UPDATE',
        new Map<String, Object>{ 'holderId' => holderId },
        AccessLevel.USER_MODE
      );
      check(holders.size() == 1, 'UNAVAILABLE');
      List<AXF_OBJ_ReconciliationAllocation__c> previous = allocations(
        'AXF_RA_EXI_AllocationKey__c = :operation',
        new Map<String, Object>{ 'operation' => operation }
      );
      if (!previous.isEmpty()) {
        target(previous[0].AXF_RA_LKP_FinancialTransaction__c, false);
        source(sourceId(previous[0]), kind(previous[0]), false);
        check(previous[0].AXF_RA_TXT_PayloadHash__c == payload, 'CONFLICT');
        return previous[0].Id;
      }
      AXF_OBJ_FinancialTransaction__c plan;
      if (input.targetId == null) {
        authorizeAccount(input.accountId);
        check(
          input.currencyIso != null &&
            Pattern.matches('[A-Z]{3}', input.currencyIso) &&
            new Set<String>{ 'DEBIT', 'CREDIT' }.contains(input.direction),
          'INVALID'
        );
        plan = new AXF_OBJ_FinancialTransaction__c(
          AXF_FTX_LKP_Account__c = input.accountId,
          AXF_FTX_NUM_Magnitude__c = input.amount,
          AXF_FTX_TXT_CurrencyIsoCode__c = input.currencyIso,
          AXF_FTX_PKL_Direction__c = input.direction,
          AXF_FTX_DAT_PurchaseDate__c = input.recognitionDate,
          AXF_FTX_EXI_ClientRequestId__c = hash(
              new List<Object>{ 'AXF25-ACTUAL', input.operationKey }
            )
            .substring(0, 36),
          AXF_FTX_PKL_PlanKind__c = 'ACTUAL_ONLY',
          AXF_FTX_PKL_Status__c = 'CONFIRMED',
          AXF_FTX_NUM_Version__c = 0
        );
        insert as user plan;
      } else {
        plan = target(input.targetId, true);
        check(
          input.targetVersion != null &&
            version(plan.AXF_FTX_NUM_Version__c) == input.targetVersion,
          'CONFLICT'
        );
      }
      Id factId = input.sourceId;
      if (factId == null) {
        factId = createFact(input, plan);
      }
      check(factId != plan.Id, 'INVALID_ROLE');
      Source fact = source(factId, input.sourceKind, true);
      check(
        input.sourceId == null ||
        (input.sourceVersion != null &&
        fact.currentVersion == input.sourceVersion),
        'CONFLICT'
      );
      check(
        fact.accountId == plan.AXF_FTX_LKP_Account__c &&
          fact.direction == plan.AXF_FTX_PKL_Direction__c,
        'INVALID_SOURCE'
      );
      check(
        fact.iso == plan.AXF_FTX_TXT_CurrencyIsoCode__c,
        'CURRENCY_MISMATCH'
      );
      check(
        input.amount <=
          plan.AXF_FTX_NUM_Magnitude__c -
          new Conservation().net(plan.Id, null) &&
          input.amount <= fact.amount - new Conservation().net(null, factId),
        'UNAVAILABLE_AMOUNT'
      );
      AXF_ReportCurrencyPref__c preference = AXF_ReportCurrencyPref__c.getOrgDefaults();
      check(
        preference != null &&
        !String.isBlank(preference.AXF_RCP_TXT_IsoCode__c),
        'REPORTING_CURRENCY_REQUIRED'
      );
      AXF_OBJ_ReconciliationAllocation__c row = new AXF_OBJ_ReconciliationAllocation__c(
        AXF_RA_LKP_FinancialTransaction__c = plan.Id,
        AXF_RA_NUM_Magnitude__c = input.amount,
        AXF_RA_TXT_CurrencyIsoCode__c = fact.iso,
        AXF_RA_DAT_RecognitionDate__c = input.recognitionDate,
        AXF_RA_EXI_AllocationKey__c = operation,
        AXF_RA_TXT_PayloadHash__c = payload,
        AXF_RA_PKL_Kind__c = 'APPLICATION',
        AXF_RA_PKL_FxState__c = 'PENDING_FX',
        AXF_RA_TXT_ReportingIso__c = preference.AXF_RCP_TXT_IsoCode__c
      );
      row.put(
        'AXF_RA_LKP_' +
          (input.sourceKind == 'BANK'
            ? 'BankTransaction'
            : input.sourceKind == 'CARD'
                ? 'CardTransaction'
                : 'ManualTransaction') +
          '__c',
        factId
      );
      insert as user row;
      recognize(row);
      bump(plan, fact);
      return row.Id;
    } catch (Exception failure) {
      Database.rollback(sp);
      if (failure instanceof RealizationException) {
        throw failure;
      }
      throw new RealizationException('UNAVAILABLE');
    } finally {
      writing = false;
    }
  }
  private Id createFact(Input input, AXF_OBJ_FinancialTransaction__c plan) {
    if (input.sourceKind == 'CASH') {
      AXF_OBJ_FinancialTransaction__c cash = new AXF_OBJ_FinancialTransaction__c(
        AXF_FTX_LKP_Account__c = plan.AXF_FTX_LKP_Account__c,
        AXF_FTX_NUM_Magnitude__c = input.amount,
        AXF_FTX_TXT_CurrencyIsoCode__c = plan.AXF_FTX_TXT_CurrencyIsoCode__c,
        AXF_FTX_PKL_Direction__c = plan.AXF_FTX_PKL_Direction__c,
        AXF_FTX_DAT_PurchaseDate__c = input.recognitionDate,
        AXF_FTX_EXI_ClientRequestId__c = hash(
            new List<Object>{ 'AXF25-CASH', input.operationKey }
          )
          .substring(0, 36),
        AXF_FTX_PKL_PlanKind__c = 'CASH_FACT',
        AXF_FTX_PKL_Status__c = 'CONFIRMED',
        AXF_FTX_NUM_Version__c = 0
      );
      insert as user cash;
      return cash.Id;
    }
    Boolean allowed = false;
    for (
      AXF_CLS_FinancialEntryService.FundingSourceOption funding : AXF_CLS_FinancialEntryService.getFundingSources(
        plan.AXF_FTX_LKP_Account__c
      )
    ) {
      if (
        input.fundingId != null &&
        (input.sourceKind == 'BANK'
          ? funding.bankAccountId
          : funding.creditCardId) == input.fundingId
      ) {
        allowed = true;
      }
    }
    check(allowed, 'UNAVAILABLE');
    String prefix = input.sourceKind == 'BANK' ? 'BAT' : 'CCT';
    SObject fact = input.sourceKind == 'BANK'
      ? (SObject) new AXF_OBJ_BankAccountTransaction__c()
      : (SObject) new AXF_OBJ_CreditCardTransaction__c();
    fact.put(
      'AXF_' +
        prefix +
        '_MDR_' +
        (prefix == 'BAT' ? 'BankAccount' : 'CreditCard') +
        '__c',
      input.fundingId
    );
    fact.put('AXF_' + prefix + '_NUM_Magnitude__c', input.amount);
    fact.put(
      'AXF_' + prefix + '_TXT_CurrencyIsoCode__c',
      plan.AXF_FTX_TXT_CurrencyIsoCode__c
    );
    fact.put(
      'AXF_' + prefix + '_PKL_Direction__c',
      plan.AXF_FTX_PKL_Direction__c
    );
    fact.put('AXF_' + prefix + '_DAT_Date__c', input.recognitionDate);
    fact.put('AXF_' + prefix + '_PKL_Source__c', 'MANUAL');
    fact.put(
      'AXF_' + prefix + '_EXI_SourceKey__c',
      hash(new List<Object>{ 'AXF25-MANUAL', input.operationKey })
    );
    fact.put('AXF_' + prefix + '_NUM_Version__c', 0);
    Database.insert(fact, AccessLevel.USER_MODE);
    return fact.Id;
  }
  private void bump(AXF_OBJ_FinancialTransaction__c plan, Source fact) {
    List<SObject> updates = new List<SObject>{
      new AXF_OBJ_FinancialTransaction__c(
        Id = plan.Id,
        AXF_FTX_NUM_Version__c = version(plan.AXF_FTX_NUM_Version__c) + 1
      )
    };
    SObject factUpdate = fact.record.getSObjectType()
      .newSObject(fact.record.Id);
    factUpdate.put(
      'AXF_' + fact.prefix + '_NUM_Version__c',
      fact.currentVersion + 1
    );
    updates.add(factUpdate);
    Database.update(updates, AccessLevel.USER_MODE);
  }
  private void recognize(AXF_OBJ_ReconciliationAllocation__c row) {
    ALT_CLS_FxConversionService.ConversionInputDTO input = new ALT_CLS_FxConversionService.ConversionInputDTO();
    input.targetType = 'RECONCILIATION_ALLOCATION';
    input.targetId = row.Id;
    input.purpose = 'RECOGNITION';
    input.reportingIso = row.AXF_RA_TXT_ReportingIso__c;
    input.side = [
        SELECT AXF_FTX_PKL_Direction__c
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE Id = :row.AXF_RA_LKP_FinancialTransaction__c
        WITH USER_MODE
      ]
      .AXF_FTX_PKL_Direction__c == 'DEBIT'
      ? 'SELL'
      : 'BUY';
    input.policyVersion = 'AXF24-PTAX-5D-v1';
    input.roundingPolicy = 'HALF_UP_2';
    ALT_CLS_FxConversionService.ConversionResultDTO converted = new ALT_CLS_FxConversionService()
      .applyConversion(input);
    if (converted.outcome == 'MISSING_RATE') {
      return;
    }
    row.AXF_RA_PKL_FxState__c = 'READY';
    row.AXF_RA_LKP_FxSnapshot__c = converted.snapshotId;
    row.AXF_RA_NUM_ReportingAmount__c = converted.outcome == 'SAME_CURRENCY'
      ? row.AXF_RA_NUM_Magnitude__c
      : converted.reportingAmount;
    update as user row;
  }
  /** @description Appends one full compensation; prior recognition evidence is never recalculated. */
  public Id reverse(
    Id allocationId,
    Decimal expectedVersion,
    String operationKey
  ) {
    requireAccess();
    check(
      !String.isBlank(operationKey) && operationKey.length() <= 80,
      'INVALID'
    );
    Savepoint sp = Database.setSavepoint();
    try {
      writing = true;
      AXF_OBJ_ReconciliationAllocation__c original = allocation(allocationId);
      check(original.AXF_RA_PKL_Kind__c == 'APPLICATION', 'INVALID');
      AXF_OBJ_FinancialTransaction__c plan = target(
        original.AXF_RA_LKP_FinancialTransaction__c,
        true
      );
      Source fact = source(sourceId(original), kind(original), true);
      String key = hash(new List<Object>{ 'AXF25', operationKey });
      String payload = hash(
        new List<Object>{ 'REVERSAL', allocationId, expectedVersion }
      );
      List<AXF_OBJ_ReconciliationAllocation__c> prior = allocations(
        'AXF_RA_EXI_AllocationKey__c = :key',
        new Map<String, Object>{ 'key' => key }
      );
      if (!prior.isEmpty()) {
        check(prior[0].AXF_RA_TXT_PayloadHash__c == payload, 'CONFLICT');
        return prior[0].Id;
      }
      check(
        expectedVersion != null &&
          version(plan.AXF_FTX_NUM_Version__c) == expectedVersion,
        'CONFLICT'
      );
      check(!new Conservation().reversed(allocationId), 'CONFLICT');
      AXF_OBJ_ReconciliationAllocation__c reversal = original.clone(
        false,
        false,
        false,
        false
      );
      reversal.AXF_RA_PKL_Kind__c = 'REVERSAL';
      reversal.AXF_RA_LKP_OriginalAllocation__c = original.Id;
      reversal.AXF_RA_EXI_AllocationKey__c = key;
      reversal.AXF_RA_TXT_PayloadHash__c = payload;
      insert as user reversal;
      bump(plan, fact);
      return reversal.Id;
    } catch (Exception failure) {
      Database.rollback(sp);
      if (failure instanceof RealizationException) {
        throw failure;
      }
      throw new RealizationException('UNAVAILABLE');
    } finally {
      writing = false;
    }
  }
  /** @description Recovery affects only the missing recognition evidence, never the original realization. */
  public void retryFx(Id allocationId) {
    requireAccess();
    Savepoint sp = Database.setSavepoint();
    try {
      writing = true;
      AXF_OBJ_ReconciliationAllocation__c row = allocation(allocationId);
      target(row.AXF_RA_LKP_FinancialTransaction__c, true);
      source(sourceId(row), kind(row), false);
      if (row.AXF_RA_PKL_Kind__c == 'REVERSAL') {
        row = allocation(row.AXF_RA_LKP_OriginalAllocation__c);
      }
      if (row.AXF_RA_PKL_FxState__c == 'READY') {
        return;
      }
      recognize(row);
      List<AXF_OBJ_ReconciliationAllocation__c> reversals = allocations(
        'AXF_RA_LKP_OriginalAllocation__c = :original',
        new Map<String, Object>{ 'original' => row.Id }
      );
      for (AXF_OBJ_ReconciliationAllocation__c reversal : reversals) {
        reversal.AXF_RA_PKL_FxState__c = row.AXF_RA_PKL_FxState__c;
        reversal.AXF_RA_LKP_FxSnapshot__c = row.AXF_RA_LKP_FxSnapshot__c;
        reversal.AXF_RA_NUM_ReportingAmount__c = row.AXF_RA_NUM_ReportingAmount__c;
      }
      if (!reversals.isEmpty()) {
        update as user reversals;
      }
    } catch (Exception failure) {
      Database.rollback(sp);
      throw new RealizationException('UNAVAILABLE');
    } finally {
      writing = false;
    }
  }
  /** @description Fails closed if a total would require an inaccessible allocation or source. */
  public View read(Id targetId) {
    requireAccess();
    AXF_OBJ_FinancialTransaction__c plan = target(targetId, false);
    View result = new View();
    result.targetId = plan.Id;
    result.version = version(plan.AXF_FTX_NUM_Version__c);
    result.currencyIso = plan.AXF_FTX_TXT_CurrencyIsoCode__c;
    result.planKind = plan.AXF_FTX_PKL_PlanKind__c;
    result.planned = plan.AXF_FTX_PKL_PlanKind__c == 'ACTUAL_ONLY'
      ? 0
      : plan.AXF_FTX_NUM_Magnitude__c;
    result.realized = 0;
    result.reportingAmount = 0;
    result.pendingFx = false;
    result.allocations = allocations(
      'AXF_RA_LKP_FinancialTransaction__c = :targetId',
      new Map<String, Object>{ 'targetId' => targetId }
    );
    check(
      new Conservation().countTarget(targetId) == result.allocations.size(),
      'UNAVAILABLE'
    );
    authorizeSources(result.allocations);
    for (AXF_OBJ_ReconciliationAllocation__c row : result.allocations) {
      Decimal sign = row.AXF_RA_PKL_Kind__c == 'REVERSAL' ? -1 : 1;
      result.realized += sign * row.AXF_RA_NUM_Magnitude__c;
      result.pendingFx =
        result.pendingFx || row.AXF_RA_PKL_FxState__c != 'READY';
      if (
        result.reportingIso != null &&
        result.reportingIso != row.AXF_RA_TXT_ReportingIso__c
      ) {
        result.pendingFx = true;
      }
      result.reportingIso = row.AXF_RA_TXT_ReportingIso__c;
      if (row.AXF_RA_NUM_ReportingAmount__c != null) {
        result.reportingAmount += sign * row.AXF_RA_NUM_ReportingAmount__c;
      }
    }
    if (result.pendingFx) {
      result.reportingAmount = null;
    }
    result.residual = plan.AXF_FTX_PKL_PlanKind__c == 'ACTUAL_ONLY'
      ? 0
      : plan.AXF_FTX_NUM_Magnitude__c - result.realized;
    result.state = result.realized == 0
      ? 'NONE'
      : result.realized == plan.AXF_FTX_NUM_Magnitude__c
          ? 'REALIZED'
          : 'PARTIAL';
    return result;
  }
  private void authorizeSources(
    List<AXF_OBJ_ReconciliationAllocation__c> rows
  ) {
    Set<Id> cash = new Set<Id>(),
      bank = new Set<Id>(),
      card = new Set<Id>(),
      accounts = new Set<Id>();
    for (
      AXF_CLS_AuthorizedContextService.ContextView context : AXF_CLS_AuthorizedContextService.listAuthorizedContexts()
    ) {
      accounts.add(context.accountId);
    }
    for (AXF_OBJ_ReconciliationAllocation__c row : rows) {
      if (kind(row) == 'CASH') {
        cash.add(sourceId(row));
      } else if (kind(row) == 'BANK') {
        bank.add(sourceId(row));
      } else {
        card.add(sourceId(row));
      }
    }
    List<AXF_OBJ_FinancialTransaction__c> cashRows = [
      SELECT Id, AXF_FTX_LKP_Account__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE Id IN :cash
      WITH USER_MODE
    ];
    check(cashRows.size() == cash.size(), 'UNAVAILABLE');
    for (AXF_OBJ_FinancialTransaction__c row : cashRows) {
      check(accounts.contains(row.AXF_FTX_LKP_Account__c), 'UNAVAILABLE');
    }
    List<AXF_OBJ_BankAccountTransaction__c> bankRows = [
      SELECT Id, AXF_BAT_MDR_BankAccount__r.AXF_BA_LKP_Account__c
      FROM AXF_OBJ_BankAccountTransaction__c
      WHERE Id IN :bank
      WITH USER_MODE
    ];
    check(bankRows.size() == bank.size(), 'UNAVAILABLE');
    for (AXF_OBJ_BankAccountTransaction__c row : bankRows) {
      check(
        accounts.contains(row.AXF_BAT_MDR_BankAccount__r.AXF_BA_LKP_Account__c),
        'UNAVAILABLE'
      );
    }
    List<AXF_OBJ_CreditCardTransaction__c> cardRows = [
      SELECT Id, AXF_CCT_MDR_CreditCard__r.AXF_CC_LKP_Account__c
      FROM AXF_OBJ_CreditCardTransaction__c
      WHERE Id IN :card
      WITH USER_MODE
    ];
    check(cardRows.size() == card.size(), 'UNAVAILABLE');
    for (AXF_OBJ_CreditCardTransaction__c row : cardRows) {
      check(
        accounts.contains(row.AXF_CCT_MDR_CreditCard__r.AXF_CC_LKP_Account__c),
        'UNAVAILABLE'
      );
    }
  }
  /** @description Private conservation only. Explicit permission gates apply; inaccessible amounts never leave this boundary. */
  private without sharing class Conservation {
    // System visibility preserves conservation across private effects; values stay inside this private class.
    @SuppressWarnings('PMD.ApexCRUDViolation')
    public Decimal net(Id targetId, Id factId) {
      requireAccess();
      Decimal total = 0;
      for (AggregateResult groupRow : [
        SELECT AXF_RA_PKL_Kind__c kind, SUM(AXF_RA_NUM_Magnitude__c) amount
        FROM AXF_OBJ_ReconciliationAllocation__c
        WHERE
          (AXF_RA_LKP_FinancialTransaction__c != NULL
          AND AXF_RA_LKP_FinancialTransaction__c = :targetId)
          OR (AXF_RA_LKP_BankTransaction__c != NULL
          AND AXF_RA_LKP_BankTransaction__c = :factId)
          OR (AXF_RA_LKP_CardTransaction__c != NULL
          AND AXF_RA_LKP_CardTransaction__c = :factId)
          OR (AXF_RA_LKP_ManualTransaction__c != NULL
          AND AXF_RA_LKP_ManualTransaction__c = :factId)
        GROUP BY AXF_RA_PKL_Kind__c
      ]) {
        total +=
          ((String) groupRow.get('kind') == 'REVERSAL' ? -1 : 1) *
          (Decimal) groupRow.get('amount');
      }
      return total;
    }
    @SuppressWarnings('PMD.ApexCRUDViolation')
    public Boolean reversed(Id allocationId) {
      requireAccess();
      return [
          SELECT COUNT()
          FROM AXF_OBJ_ReconciliationAllocation__c
          WHERE AXF_RA_LKP_OriginalAllocation__c = :allocationId
        ] > 0;
    }
    @SuppressWarnings('PMD.ApexCRUDViolation')
    public Integer countTarget(Id targetId) {
      requireAccess();
      return [
        SELECT COUNT()
        FROM AXF_OBJ_ReconciliationAllocation__c
        WHERE AXF_RA_LKP_FinancialTransaction__c = :targetId
      ];
    }
  }
}
