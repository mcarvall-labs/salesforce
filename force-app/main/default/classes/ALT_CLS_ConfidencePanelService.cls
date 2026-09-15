/**
 * @description AXF-143 — basic confidence panel (S1 of AXF-48): explains, for a scope of
 * people/companies, which sources an indicator depends on, when each source last succeeded,
 * whether it is still current under its freshness limit, which sources are excluded and why,
 * the currencies involved, and the level/allowed actions derived on the server.
 *
 * Rules:
 * - Everything is read with the caller's effective access (`with sharing`, `USER_MODE`). A
 *   holder that is not visible is reported as `NOT_AUTHORIZED` without confirming existence.
 * - Freshness limit per source: the source's own `FreshnessLimitHours` or the policy default
 *   (`AXF_CMT_ConfidencePolicy__mdt.Default`). Past the limit the source stays visible but is
 *   `STALE` (never shown as current); no recorded success is `UNKNOWN`, which is distinct from a
 *   current source with zero facts.
 * - Level: `BLOCKED` when nothing readable/authorized (or policy/field access missing),
 *   `DEGRADED` when any included source is stale/unknown or anything was excluded, otherwise
 *   `INFORMATIVE`. The UI only renders these; it never recalculates.
 * - A readable Account outside the Axon record types is `NOT_A_HOLDER`; at most `MAX_SCOPE`
 *   holders per request; freshness is compared in milliseconds against `asOf` (a source at or
 *   past its limit is STALE; a success recorded in the future is UNKNOWN + `FUTURE_SUCCESS`).
 * - Manual sources without an import timestamp fall back to the newest fact's creation time and
 *   carry `IMPORT_DATE_MISSING`, so a source with facts is never reported as "never succeeded".
 * - Exceptions of excluded sources stay on the row but never become panel reasons.
 * - Matching/Forecasting canonical states are the sibling story's concern; no score is invented.
 */
public with sharing class ALT_CLS_ConfidencePanelService {
  public static final String LEVEL_INFORMATIVE = 'INFORMATIVE';
  public static final String LEVEL_DEGRADED = 'DEGRADED';
  public static final String LEVEL_BLOCKED = 'BLOCKED';
  private static final String CP_EXPLAIN = 'AXF_CanExplainConfidence';
  private static final Set<String> AXON_RECORD_TYPES = new Set<String>{
    ALT_CLS_AxonHolder.RT_PERSON,
    ALT_CLS_AxonHolder.RT_BUSINESS
  };
  /** Largest scope accepted in one request. */
  public static final Integer MAX_SCOPE = 200;
  private static final Long HOUR_MS = 3600000L;

  /** Test seam: policy record (the CMT instance cannot be mocked). */
  @TestVisible
  private static AXF_CMT_ConfidencePolicy__mdt policyOverride;

  /** Test seam: evaluation instant. */
  @TestVisible
  private static Datetime nowOverride;

  public class ConfidenceException extends Exception {
    public String code;
  }

  public class HolderOption {
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String name;
  }

  public class SourceView {
    @AuraEnabled
    public Id sourceId;
    @AuraEnabled
    public String kind; // BANK | CARD
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Id holderId;
    @AuraEnabled
    public String holderName;
    @AuraEnabled
    public String origin; // PLUGGY | MANUAL
    @AuraEnabled
    public String currencyIso;
    @AuraEnabled
    public Datetime lastSuccessAt;
    @AuraEnabled
    public Integer freshnessLimitHours;
    @AuraEnabled
    public String freshness; // CURRENT | STALE | UNKNOWN
    @AuraEnabled
    public Boolean included;
    @AuraEnabled
    public String exclusionReason; // null | CUSTODY
    @AuraEnabled
    public Integer factCount; // null = unknown
    @AuraEnabled
    public Boolean navigable;
    @AuraEnabled
    public List<String> exceptions = new List<String>();
  }

  public class Exclusion {
    @AuraEnabled
    public Id accountId; // only ids the caller supplied
    @AuraEnabled
    public String reason; // NOT_AUTHORIZED | NOT_A_HOLDER
  }

  public class Panel {
    @AuraEnabled
    public String policyVersion;
    @AuraEnabled
    public Datetime asOf;
    @AuraEnabled
    public String level;
    @AuraEnabled
    public List<String> reasons = new List<String>();
    @AuraEnabled
    public List<String> allowedActions = new List<String>();
    @AuraEnabled
    public List<String> currencies = new List<String>();
    @AuraEnabled
    public List<SourceView> sources = new List<SourceView>();
    @AuraEnabled
    public List<Exclusion> exclusions = new List<Exclusion>();
    @AuraEnabled
    public Integer includedCount = 0;
    @AuraEnabled
    public Integer excludedCount = 0;
  }

  /** Visible Axon people/companies the caller may put in scope. */
  public List<HolderOption> listHolders() {
    requireCapability();
    List<HolderOption> result = new List<HolderOption>();
    for (Account holder : [
      SELECT Id, Name
      FROM Account
      WHERE RecordType.DeveloperName IN :AXON_RECORD_TYPES
      WITH USER_MODE
      ORDER BY Name
      LIMIT 200
    ]) {
      HolderOption option = new HolderOption();
      option.accountId = holder.Id;
      option.name = holder.Name;
      result.add(option);
    }
    return result;
  }

  public Panel explain(List<Id> accountIds) {
    requireCapability();
    Set<Id> requested = new Set<Id>();
    if (accountIds != null) {
      for (Id accountId : accountIds) {
        if (accountId != null) {
          requested.add(accountId);
        }
      }
    }
    if (requested.isEmpty() || requested.size() > MAX_SCOPE) {
      throw failure('INVALID_INPUT');
    }
    Panel panel = new Panel();
    panel.asOf = nowOverride == null ? Datetime.now() : nowOverride;

    AXF_CMT_ConfidencePolicy__mdt policy = policyOverride != null
      ? policyOverride
      : AXF_CMT_ConfidencePolicy__mdt.getInstance('Default');
    if (policy == null) {
      return blocked(panel, 'POLICY_MISSING');
    }
    panel.policyVersion = policy.AXF_CFP_TXT_PolicyVersion__c;
    Integer defaultLimit = policy.AXF_CFP_NUM_DefaultFreshnessHours__c == null
      ? null
      : policy.AXF_CFP_NUM_DefaultFreshnessHours__c.intValue();
    if (defaultLimit == null || defaultLimit <= 0) {
      return blocked(panel, 'POLICY_INVALID');
    }
    List<String> gaps = missingAccess();
    if (!gaps.isEmpty()) {
      panel.reasons.addAll(gaps);
      return blocked(panel, null);
    }

    Map<Id, Account> visible = new Map<Id, Account>();
    Set<Id> notHolders = new Set<Id>();
    for (Account holder : [
      SELECT Id, Name, RecordTypeId, RecordType.DeveloperName
      FROM Account
      WHERE Id IN :requested
      WITH USER_MODE
    ]) {
      if (
        holder.RecordTypeId != null &&
        AXON_RECORD_TYPES.contains(holder.RecordType.DeveloperName)
      ) {
        visible.put(holder.Id, holder);
      } else {
        notHolders.add(holder.Id);
      }
    }
    for (Id accountId : requested) {
      if (!visible.containsKey(accountId)) {
        Exclusion exclusion = new Exclusion();
        exclusion.accountId = accountId;
        exclusion.reason = notHolders.contains(accountId)
          ? 'NOT_A_HOLDER'
          : 'NOT_AUTHORIZED';
        panel.exclusions.add(exclusion);
      }
    }
    if (visible.isEmpty()) {
      return blocked(panel, 'NO_AUTHORIZED_SCOPE');
    }

    Set<Id> holderIds = visible.keySet();
    Map<Id, SourceView> sources = new Map<Id, SourceView>();
    for (AXF_OBJ_BankAccount__c bank : [
      SELECT
        Id,
        AXF_BA_LKP_Account__c,
        AXF_BA_TXT_InstitutionName__c,
        AXF_BA_TXT_NumberMasked__c,
        AXF_BA_TXT_CurrencyIsoCode__c,
        AXF_BA_PKL_AvailabilityState__c,
        AXF_BA_NUM_FreshnessLimitHours__c,
        AXF_BA_LKP_Connection__c,
        AXF_BA_LKP_Connection__r.AXF_CON_DT_LastSuccessAt__c,
        AXF_BA_LKP_Connection__r.AXF_CON_PKL_ConsentState__c,
        AXF_BA_LKP_Connection__r.AXF_CON_PKL_CollectionState__c
      FROM AXF_OBJ_BankAccount__c
      WHERE AXF_BA_LKP_Account__c IN :holderIds
      WITH USER_MODE
      ORDER BY AXF_BA_TXT_InstitutionName__c, AXF_BA_TXT_NumberMasked__c
    ]) {
      SourceView view = baseView(
        bank.Id,
        'BANK',
        label(
          bank.AXF_BA_TXT_InstitutionName__c,
          bank.AXF_BA_TXT_NumberMasked__c
        ),
        visible.get(bank.AXF_BA_LKP_Account__c),
        bank.AXF_BA_TXT_CurrencyIsoCode__c,
        bank.AXF_BA_PKL_AvailabilityState__c,
        bank.AXF_BA_NUM_FreshnessLimitHours__c,
        defaultLimit
      );
      applyConnection(
        view,
        bank.AXF_BA_LKP_Connection__c,
        bank.AXF_BA_LKP_Connection__r
      );
      sources.put(view.sourceId, view);
    }
    for (AXF_OBJ_CreditCard__c card : [
      SELECT
        Id,
        AXF_CC_LKP_Account__c,
        AXF_CC_TXT_InstitutionName__c,
        AXF_CC_TXT_LastFourMasked__c,
        AXF_CC_TXT_CurrencyIsoCode__c,
        AXF_CC_PKL_AvailabilityState__c,
        AXF_CC_NUM_FreshnessLimitHours__c,
        AXF_CC_LKP_Connection__c,
        AXF_CC_LKP_Connection__r.AXF_CON_DT_LastSuccessAt__c,
        AXF_CC_LKP_Connection__r.AXF_CON_PKL_ConsentState__c,
        AXF_CC_LKP_Connection__r.AXF_CON_PKL_CollectionState__c
      FROM AXF_OBJ_CreditCard__c
      WHERE AXF_CC_LKP_Account__c IN :holderIds
      WITH USER_MODE
      ORDER BY AXF_CC_TXT_InstitutionName__c, AXF_CC_TXT_LastFourMasked__c
    ]) {
      SourceView view = baseView(
        card.Id,
        'CARD',
        label(
          card.AXF_CC_TXT_InstitutionName__c,
          card.AXF_CC_TXT_LastFourMasked__c
        ),
        visible.get(card.AXF_CC_LKP_Account__c),
        card.AXF_CC_TXT_CurrencyIsoCode__c,
        card.AXF_CC_PKL_AvailabilityState__c,
        card.AXF_CC_NUM_FreshnessLimitHours__c,
        defaultLimit
      );
      applyConnection(
        view,
        card.AXF_CC_LKP_Connection__c,
        card.AXF_CC_LKP_Connection__r
      );
      sources.put(view.sourceId, view);
    }
    applyFacts(sources, panel.asOf);

    Set<String> currencies = new Set<String>();
    Boolean anyDegraded = false;
    for (SourceView view : sources.values()) {
      panel.sources.add(view);
      if (view.included) {
        panel.includedCount++;
        if (String.isNotBlank(view.currencyIso)) {
          currencies.add(view.currencyIso);
        }
        if (view.freshness != 'CURRENT' || !view.exceptions.isEmpty()) {
          anyDegraded = true;
        }
      } else {
        panel.excludedCount++;
        anyDegraded = true;
      }
    }
    panel.currencies.addAll(currencies);
    panel.currencies.sort();
    if (!panel.exclusions.isEmpty()) {
      anyDegraded = true;
    }
    if (panel.includedCount == 0) {
      // Say why nothing is readable before blocking.
      if (panel.excludedCount > 0) {
        addReason(panel, 'SOURCE_EXCLUDED');
      }
      if (!panel.exclusions.isEmpty()) {
        addReason(panel, 'HOLDER_NOT_AUTHORIZED');
      }
      return blocked(panel, 'NO_READABLE_SOURCE');
    }
    panel.level = anyDegraded ? LEVEL_DEGRADED : LEVEL_INFORMATIVE;
    if (anyDegraded) {
      for (SourceView view : panel.sources) {
        if (!view.included) {
          // Row-level exceptions of an excluded source are informative only.
          addReason(panel, 'SOURCE_EXCLUDED');
          continue;
        }
        if (view.freshness == 'STALE') {
          addReason(panel, 'STALE_SOURCE');
        }
        if (view.freshness == 'UNKNOWN') {
          addReason(panel, 'UNKNOWN_FRESHNESS');
        }
        for (String exceptionCode : view.exceptions) {
          addReason(panel, exceptionCode);
        }
      }
      if (!panel.exclusions.isEmpty()) {
        addReason(panel, 'HOLDER_NOT_AUTHORIZED');
      }
    }
    panel.allowedActions.add('OPEN_SOURCE');
    if (anyDegraded) {
      panel.allowedActions.add('REVIEW_SOURCE_HEALTH');
    }
    return panel;
  }

  // ---------------------------------------------------------------- helpers

  private static SourceView baseView(
    Id sourceId,
    String kind,
    String sourceLabel,
    Account holder,
    String currencyIso,
    String availability,
    Decimal ownLimit,
    Integer defaultLimit
  ) {
    SourceView view = new SourceView();
    view.sourceId = sourceId;
    view.kind = kind;
    view.label = sourceLabel;
    view.holderId = holder.Id;
    view.holderName = holder.Name;
    view.currencyIso = currencyIso;
    view.origin = 'MANUAL';
    view.freshnessLimitHours = ownLimit == null ||
      ownLimit <= 0
      ? defaultLimit
      : ownLimit.intValue();
    view.navigable = true;
    view.included = availability != 'CUSTODY';
    view.exclusionReason = view.included ? null : 'CUSTODY';
    view.freshness = 'UNKNOWN';
    return view;
  }

  private static void applyConnection(
    SourceView view,
    Id connectionId,
    AXF_OBJ_PluggyConnection__c connection
  ) {
    if (connectionId == null) {
      return;
    }
    view.origin = 'PLUGGY';
    if (connection == null) {
      // Connection exists but is not readable: nothing about it is asserted.
      view.exceptions.add('CONNECTION_NOT_READABLE');
      return;
    }
    view.lastSuccessAt = connection.AXF_CON_DT_LastSuccessAt__c;
    if (connection.AXF_CON_PKL_ConsentState__c == 'REVOKED') {
      view.exceptions.add('CONSENT_REVOKED');
    } else if (connection.AXF_CON_PKL_ConsentState__c == 'STALE') {
      view.exceptions.add('CONSENT_STALE');
    }
    if (connection.AXF_CON_PKL_CollectionState__c == 'PAUSED') {
      view.exceptions.add('COLLECTION_PAUSED');
    }
  }

  /** Fact counts (zero is a legitimate answer) and, for manual/CSV sources, the last import as success. */
  private static void applyFacts(Map<Id, SourceView> sources, Datetime asOf) {
    Set<Id> bankIds = new Set<Id>();
    Set<Id> cardIds = new Set<Id>();
    for (SourceView view : sources.values()) {
      view.factCount = 0;
      if (view.kind == 'BANK') {
        bankIds.add(view.sourceId);
      } else {
        cardIds.add(view.sourceId);
      }
    }
    if (!bankIds.isEmpty()) {
      for (AggregateResult row : [
        SELECT
          AXF_BAT_MDR_BankAccount__c source,
          COUNT(Id) total,
          MAX(AXF_BAT_DTM_ImportedAt__c) imported,
          MAX(CreatedDate) created
        FROM AXF_OBJ_BankAccountTransaction__c
        WHERE AXF_BAT_MDR_BankAccount__c IN :bankIds
        WITH USER_MODE
        GROUP BY AXF_BAT_MDR_BankAccount__c
      ]) {
        applyFactRow(sources.get((Id) row.get('source')), row);
      }
    }
    if (!cardIds.isEmpty()) {
      for (AggregateResult row : [
        SELECT
          AXF_CCT_MDR_CreditCard__c source,
          COUNT(Id) total,
          MAX(AXF_CCT_DTM_ImportedAt__c) imported,
          MAX(CreatedDate) created
        FROM AXF_OBJ_CreditCardTransaction__c
        WHERE AXF_CCT_MDR_CreditCard__c IN :cardIds
        WITH USER_MODE
        GROUP BY AXF_CCT_MDR_CreditCard__c
      ]) {
        applyFactRow(sources.get((Id) row.get('source')), row);
      }
    }
    for (SourceView view : sources.values()) {
      if (view.lastSuccessAt == null) {
        view.freshness = 'UNKNOWN';
        view.exceptions.add('NO_SUCCESS_RECORDED');
        continue;
      }
      Long ageMs = asOf.getTime() - view.lastSuccessAt.getTime();
      if (ageMs < 0) {
        // A success recorded after the evaluation instant cannot be trusted as current.
        view.freshness = 'UNKNOWN';
        view.exceptions.add('FUTURE_SUCCESS');
        continue;
      }
      view.freshness = ageMs >= view.freshnessLimitHours * HOUR_MS
        ? 'STALE'
        : 'CURRENT';
      if (view.freshness == 'STALE') {
        view.exceptions.add('FRESHNESS_EXCEEDED');
      }
    }
  }

  private static void applyFactRow(SourceView view, AggregateResult row) {
    if (view == null) {
      return;
    }
    view.factCount = (Integer) row.get('total');
    if (view.origin == 'MANUAL') {
      view.lastSuccessAt = (Datetime) row.get('imported');
      if (view.lastSuccessAt == null && view.factCount > 0) {
        // Hand-keyed facts carry no import timestamp; their creation is the recorded success.
        view.lastSuccessAt = (Datetime) row.get('created');
        view.exceptions.add('IMPORT_DATE_MISSING');
      }
    }
  }

  private static List<String> missingAccess() {
    List<String> gaps = new List<String>();
    Map<Schema.SObjectType, List<Schema.SObjectField>> required = new Map<Schema.SObjectType, List<Schema.SObjectField>>{
      Account.SObjectType => new List<Schema.SObjectField>{
        Account.Name,
        Account.RecordTypeId
      },
      AXF_OBJ_BankAccount__c.SObjectType => new List<Schema.SObjectField>{
        AXF_OBJ_BankAccount__c.AXF_BA_LKP_Account__c,
        AXF_OBJ_BankAccount__c.AXF_BA_TXT_InstitutionName__c,
        AXF_OBJ_BankAccount__c.AXF_BA_TXT_NumberMasked__c,
        AXF_OBJ_BankAccount__c.AXF_BA_PKL_AvailabilityState__c,
        AXF_OBJ_BankAccount__c.AXF_BA_TXT_CurrencyIsoCode__c,
        AXF_OBJ_BankAccount__c.AXF_BA_NUM_FreshnessLimitHours__c,
        AXF_OBJ_BankAccount__c.AXF_BA_LKP_Connection__c
      },
      AXF_OBJ_CreditCard__c.SObjectType => new List<Schema.SObjectField>{
        AXF_OBJ_CreditCard__c.AXF_CC_LKP_Account__c,
        AXF_OBJ_CreditCard__c.AXF_CC_TXT_InstitutionName__c,
        AXF_OBJ_CreditCard__c.AXF_CC_TXT_LastFourMasked__c,
        AXF_OBJ_CreditCard__c.AXF_CC_PKL_AvailabilityState__c,
        AXF_OBJ_CreditCard__c.AXF_CC_TXT_CurrencyIsoCode__c,
        AXF_OBJ_CreditCard__c.AXF_CC_NUM_FreshnessLimitHours__c,
        AXF_OBJ_CreditCard__c.AXF_CC_LKP_Connection__c
      },
      AXF_OBJ_PluggyConnection__c.SObjectType => new List<Schema.SObjectField>{
        AXF_OBJ_PluggyConnection__c.AXF_CON_DT_LastSuccessAt__c,
        AXF_OBJ_PluggyConnection__c.AXF_CON_PKL_ConsentState__c,
        AXF_OBJ_PluggyConnection__c.AXF_CON_PKL_CollectionState__c
      },
      AXF_OBJ_BankAccountTransaction__c.SObjectType => new List<Schema.SObjectField>{
        AXF_OBJ_BankAccountTransaction__c.AXF_BAT_DTM_ImportedAt__c
      },
      AXF_OBJ_CreditCardTransaction__c.SObjectType => new List<Schema.SObjectField>{
        AXF_OBJ_CreditCardTransaction__c.AXF_CCT_DTM_ImportedAt__c
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

  private static Panel blocked(Panel panel, String reason) {
    panel.level = LEVEL_BLOCKED;
    if (reason != null) {
      addReason(panel, reason);
    }
    panel.allowedActions.clear();
    return panel;
  }

  private static void addReason(Panel panel, String reason) {
    if (!panel.reasons.contains(reason)) {
      panel.reasons.add(reason);
    }
  }

  private static String label(String institution, String masked) {
    if (String.isBlank(institution)) {
      return String.isBlank(masked) ? '' : masked;
    }
    return String.isBlank(masked) ? institution : institution + ' ' + masked;
  }

  private static void requireCapability() {
    if (!FeatureManagement.checkPermission(CP_EXPLAIN)) {
      throw failure('FORBIDDEN');
    }
  }

  private static ConfidenceException failure(String code) {
    ConfidenceException result = new ConfidenceException(code);
    result.code = code;
    return result;
  }
}
