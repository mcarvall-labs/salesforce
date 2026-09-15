/**
 * @description AXF-122 — consolidated totals over an authorized scope (S1 of AXF-4).
 *
 * The caller names the people/companies (Accounts) to consolidate. The server keeps only the
 * holders it can actually read (effective sharing + CRUD/FLS, `USER_MODE`), sums only the
 * settled facts (BAT/CCT, status POSTED) of the sources it can read, and keeps every
 * contribution attributed to its person/company, in its original currency, with its effective
 * date range and the source it came from. Nothing is converted, neutralized or reallocated here
 * (siblings AXF-123/124/125).
 *
 * Access contract (AXF-4 AC2/AC3, AD-19/AD-21/AD-22):
 * - A requested holder that is not visible is reported as `NOT_AUTHORIZED` — the same answer
 *   whether it does not exist or is private; nothing about it is loaded.
 * - A visible holder the user does not fully control (`UserRecordAccess.HasAllAccess` false —
 *   reached through team, manual or role sharing) is `UNKNOWN` with coverage `UNVERIFIED`: the
 *   server cannot prove the visible sources are all of them, so its contributions are withheld
 *   and the result becomes `DEGRADED`. A total is never presented with silently omitted data and
 *   private amounts cannot be inferred by difference.
 * - Missing field access on the fact fields the sum depends on makes the whole result `BLOCKED`.
 * - When AXF-5 economic allocations are installed and a confirmed set exists for a fact, the
 *   fact contributes through its shares (attribution `ALLOCATION`); shares attributed outside
 *   the effective scope are counted as `ALLOCATED_OUTSIDE_SCOPE` without naming anyone.
 */
public with sharing class ALT_CLS_ConsolidationService {
  public static final String POLICY_VERSION = 'consolidation-scope@1.0.0';
  public static final String CONFIDENCE_FULL = 'FULL';
  public static final String CONFIDENCE_DEGRADED = 'DEGRADED';
  public static final String CONFIDENCE_BLOCKED = 'BLOCKED';
  private static final String CP_CONSOLIDATE = 'AXF_CanConsolidate';
  private static final Set<String> AXON_RECORD_TYPES = new Set<String>{
    'AXF_Person',
    'AXF_Business'
  };
  private static final String EAS_OBJECT = 'AXF_OBJ_EconomicAllocationSet__c';
  private static final String EA_OBJECT = 'AXF_OBJ_EconomicAllocation__c';

  /** Test seam: replaces the AXF-5 allocation lookup (fact id -> shares). */
  @TestVisible
  private static Map<Id, List<AllocationShare>> allocationOverride;

  public class ConsolidationException extends Exception {
    public String code;
  }

  public class ScopeInput {
    public List<Id> accountIds;
    public Date fromDate;
    public Date toDate;
  }

  public class AllocationShare {
    public Id accountId;
    public Decimal percent;
    public AllocationShare(Id accountId, Decimal percent) {
      this.accountId = accountId;
      this.percent = percent;
    }
  }

  public class HolderScope {
    public Id accountId;
    public String accountName;
    public String state; // AUTHORIZED | UNKNOWN
    public String coverage; // FULL | UNVERIFIED
  }

  public class Exclusion {
    public Id accountId; // only echoed for ids the caller supplied
    public String reason;
    public Integer count = 1;
  }

  public class Contribution {
    public Id accountId;
    public String accountName;
    public String attribution; // HOLDER | ALLOCATION
    public String sourceKind; // BANK | CARD
    public Id sourceId;
    public String sourceLabel;
    public String currencyIso;
    public Decimal inflow = 0;
    public Decimal outflow = 0;
    public Decimal net = 0;
    public Integer factCount = 0;
    public Integer pendingCount = 0;
    public Date effectiveFrom;
    public Date effectiveTo;
  }

  public class Total {
    public String currencyIso;
    public Decimal inflow = 0;
    public Decimal outflow = 0;
    public Decimal net = 0;
    public Integer factCount = 0;
    public Integer holderCount = 0;
  }

  public class Result {
    public String policyVersion = POLICY_VERSION;
    public Datetime asOf;
    public Date fromDate;
    public Date toDate;
    public String confidence;
    public List<String> reasons = new List<String>();
    public List<HolderScope> holders = new List<HolderScope>();
    public List<Exclusion> exclusions = new List<Exclusion>();
    public List<Contribution> contributions = new List<Contribution>();
    public List<Total> totals = new List<Total>();
  }

  private class Fact {
    Id id;
    String kind;
    Id sourceId;
    Id holderId;
    String currencyIso;
    Decimal magnitude;
    String direction;
    String status;
    Date effectiveDate;
  }

  private class Source {
    Id id;
    String kind;
    Id holderId;
    String label;
  }

  public Result consolidate(ScopeInput input) {
    if (
      input == null ||
      input.accountIds == null ||
      input.accountIds.isEmpty()
    ) {
      throw failure('INVALID_INPUT');
    }
    if (
      input.fromDate != null &&
      input.toDate != null &&
      input.fromDate > input.toDate
    ) {
      throw failure('INVALID_INPUT');
    }
    if (!FeatureManagement.checkPermission(CP_CONSOLIDATE)) {
      throw failure('FORBIDDEN');
    }
    Result result = new Result();
    result.asOf = Datetime.now();
    result.fromDate = input.fromDate;
    result.toDate = input.toDate;

    List<String> fieldGaps = missingFieldAccess();
    if (!fieldGaps.isEmpty()) {
      result.confidence = CONFIDENCE_BLOCKED;
      result.reasons.addAll(fieldGaps);
      return result;
    }

    Set<Id> requested = new Set<Id>();
    for (Id accountId : input.accountIds) {
      if (accountId != null) {
        requested.add(accountId);
      }
    }
    Map<Id, Account> visible = new Map<Id, Account>();
    Set<Id> requestedIds = requested;
    for (Account holder : [
      SELECT Id, Name, RecordType.DeveloperName
      FROM Account
      WHERE Id IN :requestedIds
      WITH USER_MODE
    ]) {
      if (AXON_RECORD_TYPES.contains(holder.RecordType.DeveloperName)) {
        visible.put(holder.Id, holder);
      }
    }
    for (Id accountId : requested) {
      if (!visible.containsKey(accountId)) {
        Exclusion exclusion = new Exclusion();
        exclusion.accountId = accountId;
        exclusion.reason = 'NOT_AUTHORIZED';
        result.exclusions.add(exclusion);
      }
    }

    // Coverage: only a holder the user fully controls (owner or equivalent full access) is known
    // to expose every source; a holder reached through partial sharing cannot prove that the
    // visible sources are all of them, so its contribution is withheld instead of summed.
    Set<Id> fullScope = new Set<Id>();
    Set<Id> visibleIds = visible.keySet();
    Id me = UserInfo.getUserId();
    for (UserRecordAccess access : [
      SELECT RecordId, HasAllAccess
      FROM UserRecordAccess
      WHERE UserId = :me AND RecordId IN :visibleIds
    ]) {
      if (access.HasAllAccess == true) {
        fullScope.add(access.RecordId);
      }
    }
    for (Id holderId : visible.keySet()) {
      HolderScope scope = new HolderScope();
      scope.accountId = holderId;
      scope.accountName = visible.get(holderId).Name;
      Boolean full = fullScope.contains(holderId);
      scope.coverage = full ? 'FULL' : 'UNVERIFIED';
      scope.state = full ? 'AUTHORIZED' : 'UNKNOWN';
      result.holders.add(scope);
      if (!full) {
        addReason(result, 'COVERAGE_UNVERIFIED');
      }
    }
    Map<Id, Source> sources = loadSources(fullScope);

    List<Fact> facts = loadFacts(
      sources,
      fullScope,
      input.fromDate,
      input.toDate
    );
    Map<Id, List<AllocationShare>> allocations = loadAllocations(facts, result);
    Map<String, Contribution> byKey = new Map<String, Contribution>();
    Integer outsideScope = 0;
    for (Fact fact : facts) {
      Source source = sources.get(fact.sourceId);
      List<AllocationShare> shares = allocations.get(fact.id);
      if (shares == null || shares.isEmpty()) {
        accumulate(
          byKey,
          visible,
          source,
          fact,
          fact.holderId,
          'HOLDER',
          fact.magnitude
        );
        continue;
      }
      for (AllocationShare share : shares) {
        if (!fullScope.contains(share.accountId)) {
          outsideScope++;
          continue;
        }
        Decimal magnitude = (fact.magnitude *
          share.percent /
          100)
          .setScale(2, RoundingMode.HALF_EVEN);
        accumulate(
          byKey,
          visible,
          source,
          fact,
          share.accountId,
          'ALLOCATION',
          magnitude
        );
      }
    }
    if (outsideScope > 0) {
      Exclusion exclusion = new Exclusion();
      exclusion.reason = 'ALLOCATED_OUTSIDE_SCOPE';
      exclusion.count = outsideScope;
      result.exclusions.add(exclusion);
      addReason(result, 'ALLOCATED_OUTSIDE_SCOPE');
    }
    List<String> keys = new List<String>(byKey.keySet());
    keys.sort();
    Map<String, Total> totals = new Map<String, Total>();
    Map<String, Set<Id>> holdersByCurrency = new Map<String, Set<Id>>();
    for (String key : keys) {
      Contribution contribution = byKey.get(key);
      result.contributions.add(contribution);
      Total total = totals.get(contribution.currencyIso);
      if (total == null) {
        total = new Total();
        total.currencyIso = contribution.currencyIso;
        totals.put(contribution.currencyIso, total);
        holdersByCurrency.put(contribution.currencyIso, new Set<Id>());
      }
      total.inflow += contribution.inflow;
      total.outflow += contribution.outflow;
      total.net += contribution.net;
      total.factCount += contribution.factCount;
      holdersByCurrency.get(contribution.currencyIso)
        .add(contribution.accountId);
    }
    List<String> currencies = new List<String>(totals.keySet());
    currencies.sort();
    for (String currencyIso : currencies) {
      Total total = totals.get(currencyIso);
      total.holderCount = holdersByCurrency.get(currencyIso).size();
      result.totals.add(total);
    }
    if (fullScope.isEmpty()) {
      result.confidence = CONFIDENCE_BLOCKED;
      addReason(result, 'NO_AUTHORIZED_SCOPE');
    } else {
      result.confidence = result.reasons.isEmpty()
        ? CONFIDENCE_FULL
        : CONFIDENCE_DEGRADED;
    }
    return result;
  }

  // ---------------------------------------------------------------- loaders

  private static Map<Id, Source> loadSources(Set<Id> holderIds) {
    Map<Id, Source> result = new Map<Id, Source>();
    if (holderIds.isEmpty()) {
      return result;
    }
    for (AXF_OBJ_BankAccount__c bank : [
      SELECT
        Id,
        AXF_BA_LKP_Account__c,
        AXF_BA_TXT_InstitutionName__c,
        AXF_BA_TXT_NumberMasked__c
      FROM AXF_OBJ_BankAccount__c
      WHERE AXF_BA_LKP_Account__c IN :holderIds
      WITH USER_MODE
    ]) {
      Source source = new Source();
      source.id = bank.Id;
      source.kind = 'BANK';
      source.holderId = bank.AXF_BA_LKP_Account__c;
      source.label = label(
        bank.AXF_BA_TXT_InstitutionName__c,
        bank.AXF_BA_TXT_NumberMasked__c
      );
      result.put(source.id, source);
    }
    for (AXF_OBJ_CreditCard__c card : [
      SELECT
        Id,
        AXF_CC_LKP_Account__c,
        AXF_CC_TXT_InstitutionName__c,
        AXF_CC_TXT_LastFourMasked__c
      FROM AXF_OBJ_CreditCard__c
      WHERE AXF_CC_LKP_Account__c IN :holderIds
      WITH USER_MODE
    ]) {
      Source source = new Source();
      source.id = card.Id;
      source.kind = 'CARD';
      source.holderId = card.AXF_CC_LKP_Account__c;
      source.label = label(
        card.AXF_CC_TXT_InstitutionName__c,
        card.AXF_CC_TXT_LastFourMasked__c
      );
      result.put(source.id, source);
    }
    return result;
  }

  private static List<Fact> loadFacts(
    Map<Id, Source> sources,
    Set<Id> fullScope,
    Date fromDate,
    Date toDate
  ) {
    List<Fact> result = new List<Fact>();
    Set<Id> bankIds = new Set<Id>();
    Set<Id> cardIds = new Set<Id>();
    for (Source source : sources.values()) {
      if (!fullScope.contains(source.holderId)) {
        continue;
      }
      if (source.kind == 'BANK') {
        bankIds.add(source.id);
      } else {
        cardIds.add(source.id);
      }
    }
    Date lower = fromDate == null ? Date.newInstance(1900, 1, 1) : fromDate;
    Date upper = toDate == null ? Date.newInstance(2999, 12, 31) : toDate;
    if (!bankIds.isEmpty()) {
      for (AXF_OBJ_BankAccountTransaction__c row : [
        SELECT
          Id,
          AXF_BAT_MDR_BankAccount__c,
          AXF_BAT_TXT_CurrencyIsoCode__c,
          AXF_BAT_NUM_Magnitude__c,
          AXF_BAT_PKL_Direction__c,
          AXF_BAT_PKL_Status__c,
          AXF_BAT_DAT_Date__c
        FROM AXF_OBJ_BankAccountTransaction__c
        WHERE
          AXF_BAT_MDR_BankAccount__c IN :bankIds
          AND AXF_BAT_DAT_Date__c >= :lower
          AND AXF_BAT_DAT_Date__c <= :upper
        WITH USER_MODE
        ORDER BY AXF_BAT_DAT_Date__c
      ]) {
        Fact fact = new Fact();
        fact.id = row.Id;
        fact.kind = 'BANK';
        fact.sourceId = row.AXF_BAT_MDR_BankAccount__c;
        fact.holderId = sources.get(fact.sourceId).holderId;
        fact.currencyIso = row.AXF_BAT_TXT_CurrencyIsoCode__c;
        fact.magnitude = row.AXF_BAT_NUM_Magnitude__c;
        fact.direction = row.AXF_BAT_PKL_Direction__c;
        fact.status = row.AXF_BAT_PKL_Status__c;
        fact.effectiveDate = row.AXF_BAT_DAT_Date__c;
        result.add(fact);
      }
    }
    if (!cardIds.isEmpty()) {
      for (AXF_OBJ_CreditCardTransaction__c row : [
        SELECT
          Id,
          AXF_CCT_MDR_CreditCard__c,
          AXF_CCT_TXT_CurrencyIsoCode__c,
          AXF_CCT_NUM_Magnitude__c,
          AXF_CCT_PKL_Direction__c,
          AXF_CCT_PKL_Status__c,
          AXF_CCT_DAT_Date__c
        FROM AXF_OBJ_CreditCardTransaction__c
        WHERE
          AXF_CCT_MDR_CreditCard__c IN :cardIds
          AND AXF_CCT_DAT_Date__c >= :lower
          AND AXF_CCT_DAT_Date__c <= :upper
        WITH USER_MODE
        ORDER BY AXF_CCT_DAT_Date__c
      ]) {
        Fact fact = new Fact();
        fact.id = row.Id;
        fact.kind = 'CARD';
        fact.sourceId = row.AXF_CCT_MDR_CreditCard__c;
        fact.holderId = sources.get(fact.sourceId).holderId;
        fact.currencyIso = row.AXF_CCT_TXT_CurrencyIsoCode__c;
        fact.magnitude = row.AXF_CCT_NUM_Magnitude__c;
        fact.direction = row.AXF_CCT_PKL_Direction__c;
        fact.status = row.AXF_CCT_PKL_Status__c;
        fact.effectiveDate = row.AXF_CCT_DAT_Date__c;
        result.add(fact);
      }
    }
    return result;
  }

  /**
   * Confirmed AXF-5 allocation shares per fact, when the allocation objects are installed.
   * Read dynamically so this class deploys before AXF-126 lands; the sum itself is never
   * redefined here (AD-19: the confirmed set is the only attribution authority).
   */
  private static Map<Id, List<AllocationShare>> loadAllocations(
    List<Fact> facts,
    Result summary
  ) {
    if (allocationOverride != null) {
      return allocationOverride;
    }
    Map<Id, List<AllocationShare>> result = new Map<Id, List<AllocationShare>>();
    if (facts.isEmpty()) {
      return result;
    }
    Map<String, Schema.SObjectType> types = Schema.getGlobalDescribe();
    if (
      !types.containsKey(EAS_OBJECT.toLowerCase()) ||
      !types.containsKey(EA_OBJECT.toLowerCase())
    ) {
      return result;
    }
    if (
      !types.get(EAS_OBJECT.toLowerCase()).getDescribe().isAccessible() ||
      !types.get(EA_OBJECT.toLowerCase()).getDescribe().isAccessible()
    ) {
      // The attribution authority exists but this user cannot read it: holder sums may be
      // misattributed, so the result is degraded rather than silently summed by holder.
      addReason(summary, 'ALLOCATION_UNREADABLE');
      return result;
    }
    Set<Id> bankFacts = new Set<Id>();
    Set<Id> cardFacts = new Set<Id>();
    for (Fact fact : facts) {
      if (fact.kind == 'BANK') {
        bankFacts.add(fact.id);
      } else {
        cardFacts.add(fact.id);
      }
    }
    Map<Id, Id> factBySet = new Map<Id, Id>();
    for (
      SObject setRow : Database.queryWithBinds(
        'SELECT Id, AXF_EAS_LKP_BankTransaction__c, AXF_EAS_LKP_CardTransaction__c ' +
          'FROM ' +
          EAS_OBJECT +
          ' WHERE AXF_EAS_PKL_State__c = \'CONFIRMED\' AND (AXF_EAS_LKP_BankTransaction__c IN :bankFacts' +
          ' OR AXF_EAS_LKP_CardTransaction__c IN :cardFacts)',
        new Map<String, Object>{
          'bankFacts' => bankFacts,
          'cardFacts' => cardFacts
        },
        AccessLevel.USER_MODE
      )
    ) {
      Id factId = (Id) setRow.get('AXF_EAS_LKP_BankTransaction__c');
      if (factId == null) {
        factId = (Id) setRow.get('AXF_EAS_LKP_CardTransaction__c');
      }
      factBySet.put(setRow.Id, factId);
    }
    if (factBySet.isEmpty()) {
      return result;
    }
    Set<Id> setIds = factBySet.keySet();
    for (
      SObject share : Database.queryWithBinds(
        'SELECT AXF_EA_MDR_AllocationSet__c, AXF_EA_LKP_Account__c, AXF_EA_NUM_Percent__c FROM ' +
          EA_OBJECT +
          ' WHERE AXF_EA_MDR_AllocationSet__c IN :setIds',
        new Map<String, Object>{ 'setIds' => setIds },
        AccessLevel.USER_MODE
      )
    ) {
      Id factId = factBySet.get((Id) share.get('AXF_EA_MDR_AllocationSet__c'));
      if (!result.containsKey(factId)) {
        result.put(factId, new List<AllocationShare>());
      }
      result.get(factId)
        .add(
          new AllocationShare(
            (Id) share.get('AXF_EA_LKP_Account__c'),
            (Decimal) share.get('AXF_EA_NUM_Percent__c')
          )
        );
    }
    return result;
  }

  // ---------------------------------------------------------------- helpers

  private static void accumulate(
    Map<String, Contribution> byKey,
    Map<Id, Account> visible,
    Source source,
    Fact fact,
    Id accountId,
    String attribution,
    Decimal magnitude
  ) {
    String key = String.join(
      new List<String>{
        String.valueOf(accountId),
        fact.currencyIso,
        String.valueOf(source.id)
      },
      '|'
    );
    Contribution contribution = byKey.get(key);
    if (contribution == null) {
      contribution = new Contribution();
      contribution.accountId = accountId;
      contribution.accountName = visible.get(accountId).Name;
      contribution.attribution = attribution;
      contribution.sourceKind = source.kind;
      contribution.sourceId = source.id;
      contribution.sourceLabel = source.label;
      contribution.currencyIso = fact.currencyIso;
      byKey.put(key, contribution);
    } else if (contribution.attribution != attribution) {
      contribution.attribution = 'MIXED';
    }
    if (fact.status != 'POSTED') {
      contribution.pendingCount++;
      return;
    }
    if (fact.direction == 'CREDIT') {
      contribution.inflow += magnitude;
    } else {
      contribution.outflow += magnitude;
    }
    contribution.net = contribution.inflow - contribution.outflow;
    contribution.factCount++;
    if (
      contribution.effectiveFrom == null ||
      fact.effectiveDate < contribution.effectiveFrom
    ) {
      contribution.effectiveFrom = fact.effectiveDate;
    }
    if (
      contribution.effectiveTo == null ||
      fact.effectiveDate > contribution.effectiveTo
    ) {
      contribution.effectiveTo = fact.effectiveDate;
    }
  }

  private static List<String> missingFieldAccess() {
    List<String> gaps = new List<String>();
    Map<Schema.SObjectType, List<Schema.SObjectField>> required = new Map<Schema.SObjectType, List<Schema.SObjectField>>{
      AXF_OBJ_BankAccountTransaction__c.SObjectType => new List<Schema.SObjectField>{
        AXF_OBJ_BankAccountTransaction__c.AXF_BAT_NUM_Magnitude__c,
        AXF_OBJ_BankAccountTransaction__c.AXF_BAT_PKL_Direction__c,
        AXF_OBJ_BankAccountTransaction__c.AXF_BAT_PKL_Status__c,
        AXF_OBJ_BankAccountTransaction__c.AXF_BAT_TXT_CurrencyIsoCode__c,
        AXF_OBJ_BankAccountTransaction__c.AXF_BAT_DAT_Date__c
      },
      AXF_OBJ_CreditCardTransaction__c.SObjectType => new List<Schema.SObjectField>{
        AXF_OBJ_CreditCardTransaction__c.AXF_CCT_NUM_Magnitude__c,
        AXF_OBJ_CreditCardTransaction__c.AXF_CCT_PKL_Direction__c,
        AXF_OBJ_CreditCardTransaction__c.AXF_CCT_PKL_Status__c,
        AXF_OBJ_CreditCardTransaction__c.AXF_CCT_TXT_CurrencyIsoCode__c,
        AXF_OBJ_CreditCardTransaction__c.AXF_CCT_DAT_Date__c
      }
    };
    for (Schema.SObjectType type : required.keySet()) {
      if (!type.getDescribe().isAccessible()) {
        gaps.add('FIELD_ACCESS:' + type.getDescribe().getName());
        continue;
      }
      for (Schema.SObjectField field : required.get(type)) {
        if (!field.getDescribe().isAccessible()) {
          gaps.add('FIELD_ACCESS:' + field.getDescribe().getName());
        }
      }
    }
    return gaps;
  }

  private static String label(String institution, String masked) {
    return String.isBlank(masked) ? institution : institution + ' ' + masked;
  }

  private static void addReason(Result result, String reason) {
    if (!result.reasons.contains(reason)) {
      result.reasons.add(reason);
    }
  }

  private static ConsolidationException failure(String code) {
    ConsolidationException result = new ConsolidationException(code);
    result.code = code;
    return result;
  }
}
