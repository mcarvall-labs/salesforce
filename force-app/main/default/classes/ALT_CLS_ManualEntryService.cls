/**
 * @description AXF-153: manual expense/income entries and their reconciliation. Realizes an entry at
 * once — a wallet or an unconnected account/card gets a MANUAL fact through the AXF-25 realization
 * contract; a Pluggy-connected source is realized only against a chosen Pluggy fact through the
 * AXF-134 link contract — suggests Pluggy facts of the same source inside the AXF-MATCHING@1.1.0
 * window (ALT_CLS_MatchingWindow), searches them by period and description without the amount
 * window, confirms one explicit pair, and lists the manual entries of the authorized holders with a
 * reconciliation status derived from the canonical allocations. Nothing here scores, auto-confirms,
 * writes a reconciliation status or alters a confirmed fact.
 */
public with sharing class ALT_CLS_ManualEntryService {
  public static final String MATCHING_POLICY = ALT_CLS_MatchingWindow.POLICY;
  public static final String ORIGIN_BANK_ACCOUNT = 'BANK_ACCOUNT';
  public static final String ORIGIN_CREDIT_CARD = 'CREDIT_CARD';
  public static final String ORIGIN_WALLET = 'WALLET';
  public static final String ORIGIN_NONE = 'NONE';
  public static final String STATUS_RECONCILED = 'RECONCILED';
  public static final String STATUS_PARTIAL = 'PARTIAL';
  public static final String STATUS_UNRECONCILED = 'UNRECONCILED';
  public static final String STATUS_UNVERIFIED = 'UNVERIFIED';
  public static final Integer MAX_FACTS = 200;
  public static final Integer MAX_ENTRIES = 500;
  public static final Integer MAX_ORIGINS = 200;
  public static final Integer MAX_PERIOD_DAYS = 366;
  public static final Integer MAX_TERM = 100;
  private static final String CP_REALIZE = 'AXF_CanRealize';
  private static final Set<String> DIRECTIONS = new Set<String>{
    'DEBIT',
    'CREDIT'
  };
  private static final Set<String> PLAN_KINDS = new Set<String>{
    'PLANNED',
    'ACTUAL_ONLY'
  };
  private static final Set<String> STATUSES = new Set<String>{
    STATUS_RECONCILED,
    STATUS_PARTIAL,
    STATUS_UNRECONCILED,
    STATUS_UNVERIFIED
  };

  @TestVisible
  private static Date todayOverride;

  public class ManualEntryException extends Exception {
  }

  // --------------------------------------------------------------------- DTOs

  /** A draft entry (before saving) or, with `targetId`, a saved planned entry. */
  public class Draft {
    public Id targetId;
    public Id accountId;
    public Id bankAccountId;
    public Id creditCardId;
    public String direction;
    public Decimal amount;
    public String currencyIsoCode;
    public Date entryDate;
  }

  public class SearchQuery {
    public Draft entry;
    public Date fromDate;
    public Date toDate;
    public String term;
  }

  public class RealizeInput {
    public Draft entry;
    /** The chosen Pluggy fact — mandatory for a connected source, forbidden otherwise. */
    public Id factId;
    public Decimal factVersion;
    public String operationKey;
  }

  public class RealizeResult {
    @AuraEnabled
    public String matchingPolicy = MATCHING_POLICY;
    @AuraEnabled
    public Id financialTransactionId;
    @AuraEnabled
    public Id allocationId;
    /** True when the entry was realized against a chosen Pluggy fact (already reconciled). */
    @AuraEnabled
    public Boolean linkedToFact = false;
    @AuraEnabled
    public Boolean replayed = false;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public String currencyIso;
  }

  public class ConfirmInput {
    public Id targetId;
    public Decimal targetVersion;
    public Id sourceId;
    public Decimal sourceVersion;
    public String operationKey;
  }

  public class ConfirmResult {
    @AuraEnabled
    public String matchingPolicy = MATCHING_POLICY;
    @AuraEnabled
    public Id allocationId;
    @AuraEnabled
    public Boolean replayed = false;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public String currencyIso;
  }

  public class FactView {
    @AuraEnabled
    public Id sourceId;
    @AuraEnabled
    public Decimal sourceVersion;
    @AuraEnabled
    public Date factDate;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public Decimal residual;
    @AuraEnabled
    public String currencyIso;
    @AuraEnabled
    public Decimal amountDelta;
    @AuraEnabled
    public Integer dayDelta;
    /** What one click allocates: min(fact residual, entry available). */
    @AuraEnabled
    public Decimal allocationAmount;
    @AuraEnabled
    public Boolean inWindow = false;
    @AuraEnabled
    public Boolean tied = false;
  }

  public class FactPage {
    @AuraEnabled
    public String matchingPolicy = MATCHING_POLICY;
    /** Only a Pluggy-connected source has facts to reconcile with. */
    @AuraEnabled
    public Boolean connected = false;
    /** The saved entry the facts are offered for (null for a draft) and its displayed version. */
    @AuraEnabled
    public Id targetId;
    @AuraEnabled
    public Decimal targetVersion;
    /** Amount still available on the saved entry (null for a draft or when unverifiable). */
    @AuraEnabled
    public Decimal available;
    @AuraEnabled
    public Date fromDate;
    @AuraEnabled
    public Date toDate;
    @AuraEnabled
    public Boolean truncated = false;
    @AuraEnabled
    public List<FactView> items = new List<FactView>();
  }

  public class ReportQuery {
    public Integer year;
    public Integer month;
    public Date fromDate;
    public Date toDate;
    public String status;
    public String direction;
    public Id originId;
  }

  public class EntryView {
    @AuraEnabled
    public Id recordId;
    @AuraEnabled
    public Id holderId;
    @AuraEnabled
    public String holderLabel;
    @AuraEnabled
    public Date entryDate;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public String direction;
    @AuraEnabled
    public String currencyIso;
    /** PLANNED (forecast) or ACTUAL_ONLY (posted as already realized). */
    @AuraEnabled
    public String planKind;
    @AuraEnabled
    public Id originId;
    /** BANK_ACCOUNT | CREDIT_CARD | WALLET | NONE. */
    @AuraEnabled
    public String originKind = ORIGIN_NONE;
    @AuraEnabled
    public String originLabel;
    @AuraEnabled
    public Decimal allocated;
    @AuraEnabled
    public Decimal residual;
    @AuraEnabled
    public String status;
  }

  public class OriginOption {
    @AuraEnabled
    public Id originId;
    @AuraEnabled
    public String kind;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Id holderId;
  }

  public class ReportView {
    @AuraEnabled
    public String matchingPolicy = MATCHING_POLICY;
    @AuraEnabled
    public Integer year;
    @AuraEnabled
    public Integer month;
    @AuraEnabled
    public Date fromDate;
    @AuraEnabled
    public Date toDate;
    @AuraEnabled
    public Boolean customPeriod = false;
    @AuraEnabled
    public Boolean truncated = false;
    @AuraEnabled
    public List<EntryView> entries = new List<EntryView>();
    @AuraEnabled
    public List<OriginOption> origins = new List<OriginOption>();
  }

  /** The funding source of an entry: a bank account (current account or wallet) or a card. */
  private class Funding {
    public Id fundingId;
    public Id holderId;
    public String sourceKind; // BANK | CARD
    public Boolean wallet = false;
    public Boolean connected = false;
  }

  /** What the window is built around: the entry's source, direction, currency, amount and date. */
  private class Base {
    public Funding funding;
    public String direction;
    public String iso;
    public Decimal amount;
    public Date onDate;
    public AXF_OBJ_FinancialTransaction__c target;
    /** Amount still available on the entry; null when its allocations cannot be verified. */
    public Decimal available;
  }

  // ------------------------------------------------------------------- access

  /** @description Suggestions, search and confirmation rely on the link capability (AXF-134 + AXF-25). */
  public static void requireAccess() {
    try {
      ALT_CLS_SourceLinkService.requireAccess();
    } catch (ALT_CLS_SourceLinkService.SourceLinkException denied) {
      throw new ManualEntryException('UNAVAILABLE');
    }
  }

  /** @description Link capability: Pluggy suggestions, search and one-click confirmation. */
  public static Boolean canReconcile() {
    try {
      requireAccess();
      return true;
    } catch (ManualEntryException denied) {
      return false;
    }
  }

  /** @description Realization capability (AXF-25): posting an entry that already happened. */
  public static Boolean canRealize() {
    return FeatureManagement.checkPermission(CP_REALIZE);
  }

  private static void check(Boolean valid, String code) {
    if (!valid) {
      throw new ManualEntryException(code);
    }
  }

  private static Date today() {
    return todayOverride == null ? Date.today() : todayOverride;
  }

  private static Boolean validKey(String operationKey) {
    return String.isNotBlank(operationKey) && operationKey.length() <= 80;
  }

  private Map<Id, String> authorizedCache;
  /** Authorized holders and their labels; the context service is the only authority. */
  private Map<Id, String> authorizedHolders() {
    if (authorizedCache == null) {
      authorizedCache = new Map<Id, String>();
      for (
        AXF_CLS_AuthorizedContextService.ContextView context : AXF_CLS_AuthorizedContextService.listAuthorizedContexts()
      ) {
        authorizedCache.put(context.accountId, context.label);
      }
    }
    return authorizedCache;
  }

  // ------------------------------------------------------------------ funding

  /** One available source of an authorized holder; anything else is indistinguishable from missing. */
  private Funding funding(Id holderId, Id bankAccountId, Id creditCardId) {
    check((bankAccountId == null) != (creditCardId == null), 'INVALID_INPUT');
    Funding result = new Funding();
    if (bankAccountId != null) {
      check(
        bankAccountId.getSObjectType() == AXF_OBJ_BankAccount__c.SObjectType,
        'INVALID_INPUT'
      );
      List<AXF_OBJ_BankAccount__c> rows = [
        SELECT
          Id,
          AXF_BA_LKP_Account__c,
          AXF_BA_PKL_AvailabilityState__c,
          AXF_BA_TXT_Type__c,
          AXF_BA_LKP_Connection__c
        FROM AXF_OBJ_BankAccount__c
        WHERE Id = :bankAccountId
        WITH USER_MODE
        LIMIT 1
      ];
      check(
        rows.size() == 1 &&
          rows[0].AXF_BA_LKP_Account__c == holderId &&
          authorizedHolders().containsKey(holderId) &&
          rows[0].AXF_BA_PKL_AvailabilityState__c == 'AVAILABLE',
        'NOT_ACCESSIBLE'
      );
      result.fundingId = rows[0].Id;
      result.holderId = holderId;
      result.sourceKind = ALT_CLS_SourceLinkService.KIND_BANK;
      result.wallet = ALT_CLS_BankStatementService.TYPE_WALLET.equalsIgnoreCase(
        rows[0].AXF_BA_TXT_Type__c
      );
      result.connected =
        !result.wallet && rows[0].AXF_BA_LKP_Connection__c != null;
      return result;
    }
    check(
      creditCardId.getSObjectType() == AXF_OBJ_CreditCard__c.SObjectType,
      'INVALID_INPUT'
    );
    List<AXF_OBJ_CreditCard__c> rows = [
      SELECT
        Id,
        AXF_CC_LKP_Account__c,
        AXF_CC_PKL_AvailabilityState__c,
        AXF_CC_LKP_Connection__c
      FROM AXF_OBJ_CreditCard__c
      WHERE Id = :creditCardId
      WITH USER_MODE
      LIMIT 1
    ];
    check(
      rows.size() == 1 &&
        rows[0].AXF_CC_LKP_Account__c == holderId &&
        authorizedHolders().containsKey(holderId) &&
        rows[0].AXF_CC_PKL_AvailabilityState__c == 'AVAILABLE',
      'NOT_ACCESSIBLE'
    );
    result.fundingId = rows[0].Id;
    result.holderId = holderId;
    result.sourceKind = ALT_CLS_SourceLinkService.KIND_CARD;
    result.connected = rows[0].AXF_CC_LKP_Connection__c != null;
    return result;
  }

  private Base base(Draft draft) {
    check(draft != null, 'INVALID_INPUT');
    if (draft.targetId != null) {
      return targetBase(draft.targetId);
    }
    check(
      draft.accountId != null &&
      authorizedHolders().containsKey(draft.accountId),
      'NOT_ACCESSIBLE'
    );
    check(
      DIRECTIONS.contains(draft.direction) &&
        draft.amount != null &&
        draft.amount > 0 &&
        draft.amount == draft.amount.setScale(2) &&
        draft.currencyIsoCode != null &&
        Pattern.matches('[A-Z]{3}', draft.currencyIsoCode) &&
        draft.entryDate != null,
      'INVALID_INPUT'
    );
    Base result = new Base();
    result.funding = funding(
      draft.accountId,
      draft.bankAccountId,
      draft.creditCardId
    );
    result.direction = draft.direction;
    result.iso = draft.currencyIsoCode;
    result.amount = draft.amount;
    result.onDate = draft.entryDate;
    result.available = draft.amount;
    return result;
  }

  private static Date entryDate(AXF_OBJ_FinancialTransaction__c row) {
    return row.AXF_FTX_DAT_DueDate__c == null
      ? row.AXF_FTX_DAT_PurchaseDate__c
      : row.AXF_FTX_DAT_DueDate__c;
  }

  /** A saved planned entry of an authorized holder, posted against one of its sources. */
  private Base targetBase(Id targetId) {
    check(
      targetId.getSObjectType() == AXF_OBJ_FinancialTransaction__c.SObjectType,
      'INVALID_INPUT'
    );
    List<AXF_OBJ_FinancialTransaction__c> rows = [
      SELECT
        Id,
        AXF_FTX_LKP_Account__c,
        AXF_FTX_LKP_BankAccount__c,
        AXF_FTX_LKP_CreditCard__c,
        AXF_FTX_NUM_Magnitude__c,
        AXF_FTX_TXT_CurrencyIsoCode__c,
        AXF_FTX_PKL_Direction__c,
        AXF_FTX_DAT_DueDate__c,
        AXF_FTX_DAT_PurchaseDate__c,
        AXF_FTX_PKL_PlanKind__c,
        AXF_FTX_PKL_ScheduleState__c,
        AXF_FTX_NUM_Version__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE Id = :targetId
      WITH USER_MODE
      LIMIT 1
    ];
    check(
      rows.size() == 1 &&
      authorizedHolders().containsKey(rows[0].AXF_FTX_LKP_Account__c),
      'NOT_ACCESSIBLE'
    );
    AXF_OBJ_FinancialTransaction__c row = rows[0];
    check(
      row.AXF_FTX_PKL_PlanKind__c == 'PLANNED' &&
        row.AXF_FTX_PKL_ScheduleState__c != 'CANCELLED' &&
        (row.AXF_FTX_LKP_BankAccount__c != null ||
        row.AXF_FTX_LKP_CreditCard__c != null),
      'INVALID_TARGET'
    );
    Base result = new Base();
    result.funding = funding(
      row.AXF_FTX_LKP_Account__c,
      row.AXF_FTX_LKP_BankAccount__c,
      row.AXF_FTX_LKP_CreditCard__c
    );
    result.direction = row.AXF_FTX_PKL_Direction__c;
    result.iso = row.AXF_FTX_TXT_CurrencyIsoCode__c;
    result.amount = row.AXF_FTX_NUM_Magnitude__c;
    result.onDate = entryDate(row);
    result.target = row;
    Set<Id> unverified = new Set<Id>();
    Map<Id, Decimal> nets = new ALT_CLS_SourceLinkService()
      .netOfTargets(new Set<Id>{ row.Id }, unverified);
    result.available = unverified.contains(row.Id) || result.amount == null
      ? null
      : result.amount - (nets.containsKey(row.Id) ? nets.get(row.Id) : 0);
    return result;
  }

  // -------------------------------------------------------------------- facts

  private static String prefix(String sourceKind) {
    return sourceKind == ALT_CLS_SourceLinkService.KIND_BANK ? 'BAT' : 'CCT';
  }

  /** Pluggy facts of one source, same currency and direction, within dates; filters are bound. */
  private static String factSoql(String sourceKind, String extra) {
    String p = prefix(sourceKind);
    String f = 'AXF_' + p + '_';
    return 'SELECT Id, ' +
      f +
      'NUM_Magnitude__c, ' +
      f +
      'TXT_CurrencyIsoCode__c, ' +
      f +
      'PKL_Direction__c, ' +
      f +
      'DAT_Date__c, ' +
      f +
      'TXT_Description__c, ' +
      f +
      'NUM_Version__c FROM ' +
      (p == 'BAT'
        ? 'AXF_OBJ_BankAccountTransaction__c WHERE AXF_BAT_MDR_BankAccount__c'
        : 'AXF_OBJ_CreditCardTransaction__c WHERE AXF_CCT_MDR_CreditCard__c') +
      ' = :fundingId AND ' +
      f +
      'PKL_Source__c = \'PLUGGY\' AND ' +
      f +
      'PKL_Status__c = \'POSTED\' AND ' +
      f +
      'TXT_CurrencyIsoCode__c = :iso AND ' +
      f +
      'PKL_Direction__c = :direction AND ' +
      f +
      'DAT_Date__c >= :fromDate AND ' +
      f +
      'DAT_Date__c <= :toDate' +
      extra.replace('{p}', f) +
      ' ORDER BY ' +
      f +
      'DAT_Date__c DESC, Id ASC LIMIT :cap';
  }

  private static String pattern(String term) {
    // Bound values treat escaped wildcards literally; the search never reaches the SOQL text.
    return ('%' +
    term.trim().replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_') +
    '%');
  }

  /** Converts rows into views; exhausted or unverifiable facts are never offered. */
  private List<FactView> facts(Base b, List<SObject> rows) {
    List<FactView> result = new List<FactView>();
    if (rows.isEmpty()) {
      return result;
    }
    String f = 'AXF_' + prefix(b.funding.sourceKind) + '_';
    Set<Id> ids = new Map<Id, SObject>(rows).keySet();
    Set<Id> unverified = new Set<Id>();
    Map<Id, Decimal> nets = new ALT_CLS_SourceLinkService()
      .netOfSources(ids, unverified);
    for (SObject row : rows) {
      Decimal amount = (Decimal) row.get(f + 'NUM_Magnitude__c');
      Date onDate = (Date) row.get(f + 'DAT_Date__c');
      if (unverified.contains(row.Id) || amount == null || onDate == null) {
        continue;
      }
      Decimal residual =
        amount - (nets.containsKey(row.Id) ? nets.get(row.Id) : 0);
      if (residual <= 0) {
        continue;
      }
      Decimal version = (Decimal) row.get(f + 'NUM_Version__c');
      FactView v = new FactView();
      v.sourceId = row.Id;
      v.sourceVersion = version == null ? 0 : version;
      v.factDate = onDate;
      v.description = (String) row.get(f + 'TXT_Description__c');
      v.amount = amount;
      v.residual = residual;
      v.currencyIso = (String) row.get(f + 'TXT_CurrencyIsoCode__c');
      v.amountDelta = (amount - b.amount).abs();
      v.dayDelta = Math.abs(b.onDate.daysBetween(onDate));
      v.allocationAmount = Math.min(residual, b.available);
      v.inWindow = ALT_CLS_MatchingWindow.inWindow(
        b.amount,
        b.onDate,
        amount,
        onDate
      );
      result.add(v);
    }
    return result;
  }

  private Map<String, Object> binds(Base b, Date fromDate, Date toDate) {
    return new Map<String, Object>{
      'fundingId' => b.funding.fundingId,
      'iso' => b.iso,
      'direction' => b.direction,
      'fromDate' => fromDate,
      'toDate' => toDate,
      'cap' => MAX_FACTS + 1
    };
  }

  private static FactPage newPage(Base b) {
    FactPage result = new FactPage();
    result.connected = b.funding.connected;
    if (b.target != null) {
      result.targetId = b.target.Id;
      result.targetVersion = b.target.AXF_FTX_NUM_Version__c == null
        ? 0
        : b.target.AXF_FTX_NUM_Version__c;
      result.available = b.available;
    }
    return result;
  }

  private static Boolean reconcilable(Base b) {
    return b.funding.connected && b.available != null && b.available > 0;
  }

  /**
   * @description Pluggy facts of the entry's source inside the AXF-MATCHING@1.1.0 window (same
   * currency and direction, ±5% amount, ±7 days, residual > 0), in presentation order with explicit
   * ties; never a score. An unconnected source (wallet, manual account/card) has none.
   */
  public FactPage suggest(Draft draft) {
    requireAccess();
    Base b = base(draft);
    FactPage page = newPage(b);
    page.fromDate = b.onDate.addDays(-ALT_CLS_MatchingWindow.DAY_WINDOW);
    page.toDate = b.onDate.addDays(ALT_CLS_MatchingWindow.DAY_WINDOW);
    if (!reconcilable(b)) {
      return page;
    }
    Map<String, Object> values = binds(b, page.fromDate, page.toDate);
    values.put('minAmount', ALT_CLS_MatchingWindow.minAmount(b.amount));
    values.put('maxAmount', ALT_CLS_MatchingWindow.maxAmount(b.amount));
    List<SObject> rows = Database.queryWithBinds(
      factSoql(
        b.funding.sourceKind,
        ' AND {p}NUM_Magnitude__c >= :minAmount AND {p}NUM_Magnitude__c <= :maxAmount'
      ),
      values,
      AccessLevel.USER_MODE
    );
    if (rows.size() > MAX_FACTS) {
      page.truncated = true;
      rows.remove(rows.size() - 1);
    }
    List<ALT_CLS_MatchingWindow.Ranked> ranked = new List<ALT_CLS_MatchingWindow.Ranked>();
    for (FactView v : facts(b, rows)) {
      if (v.inWindow) {
        ranked.add(
          new ALT_CLS_MatchingWindow.Ranked(
            v.amountDelta,
            v.dayDelta,
            v.sourceId,
            v
          )
        );
      }
    }
    for (
      ALT_CLS_MatchingWindow.Ranked entry : ALT_CLS_MatchingWindow.order(ranked)
    ) {
      FactView v = (FactView) entry.item;
      v.tied = entry.tied;
      page.items.add(v);
    }
    return page;
  }

  /**
   * @description Manual search: Pluggy facts of the entry's source in a chosen period (default: the
   * month of the entry, at most 366 days) matching a description, without the amount window.
   */
  public FactPage search(SearchQuery query) {
    requireAccess();
    check(query != null, 'INVALID_INPUT');
    Base b = base(query.entry);
    FactPage page = newPage(b);
    if (query.fromDate == null && query.toDate == null) {
      page.fromDate = b.onDate.toStartOfMonth();
      page.toDate = page.fromDate.addMonths(1).addDays(-1);
    } else {
      check(
        query.fromDate != null &&
          query.toDate != null &&
          query.fromDate <= query.toDate &&
          query.fromDate.daysBetween(query.toDate) < MAX_PERIOD_DAYS,
        'INVALID_INPUT'
      );
      page.fromDate = query.fromDate;
      page.toDate = query.toDate;
    }
    check(
      query.term == null || query.term.length() <= MAX_TERM,
      'INVALID_INPUT'
    );
    if (!reconcilable(b)) {
      return page;
    }
    Map<String, Object> values = binds(b, page.fromDate, page.toDate);
    Boolean filtered = String.isNotBlank(query.term);
    values.put('pattern', filtered ? pattern(query.term) : null);
    List<SObject> rows = Database.queryWithBinds(
      factSoql(
        b.funding.sourceKind,
        filtered ? ' AND {p}TXT_Description__c LIKE :pattern' : ''
      ),
      values,
      AccessLevel.USER_MODE
    );
    if (rows.size() > MAX_FACTS) {
      page.truncated = true;
      rows.remove(rows.size() - 1);
    }
    page.items.addAll(facts(b, rows));
    return page;
  }

  /** The Pluggy fact, read and evaluated by the link contract, of exactly this source. */
  private ALT_CLS_SourceLinkService.SourceView readFact(
    Funding funding,
    Id factId
  ) {
    check(factId != null, 'INVALID_INPUT');
    Schema.SObjectType type = factId.getSObjectType();
    String kind = type == AXF_OBJ_BankAccountTransaction__c.SObjectType
      ? ALT_CLS_SourceLinkService.KIND_BANK
      : type == AXF_OBJ_CreditCardTransaction__c.SObjectType
          ? ALT_CLS_SourceLinkService.KIND_CARD
          : null;
    check(kind != null, 'INVALID_INPUT');
    check(kind == funding.sourceKind, 'NOT_ACCESSIBLE');
    ALT_CLS_SourceLinkService.SourceView source;
    try {
      source = new ALT_CLS_SourceLinkService().readSource(factId, kind);
    } catch (ALT_CLS_SourceLinkService.SourceLinkException hidden) {
      throw new ManualEntryException('NOT_ACCESSIBLE');
    }
    check(
      source.fundingId == funding.fundingId &&
        source.accountId == funding.holderId &&
        source.origin == 'PLUGGY',
      'NOT_ACCESSIBLE'
    );
    return source;
  }

  // ------------------------------------------------------------------ confirm

  /**
   * @description One explicit click on a displayed fact: links it to the saved planned entry
   * through the AXF-134 contract with min(fact residual, entry available). A fact found by the
   * manual search is confirmed the same way; the window never blocks an explicit human choice.
   */
  public ConfirmResult confirm(ConfirmInput input) {
    requireAccess();
    check(
      input != null &&
        input.targetId != null &&
        input.targetVersion != null &&
        input.sourceId != null &&
        input.sourceVersion != null &&
        validKey(input.operationKey),
      'INVALID_INPUT'
    );
    Base b = targetBase(input.targetId);
    ALT_CLS_SourceLinkService.SourceView source = readFact(
      b.funding,
      input.sourceId
    );
    check(b.available != null, 'ALLOCATIONS_UNVERIFIED');
    check(b.available > 0, 'TARGET_REALIZED');
    if (!source.eligible) {
      throw new ManualEntryException(source.reasons[0]);
    }
    ALT_CLS_SourceLinkService.ConfirmInput request = new ALT_CLS_SourceLinkService.ConfirmInput();
    request.sourceId = source.sourceId;
    request.sourceKind = source.sourceKind;
    request.sourceVersion = input.sourceVersion;
    request.targetId = b.target.Id;
    request.targetVersion = input.targetVersion;
    request.amount = Math.min(source.residual, b.available);
    request.recognitionDate = source.factDate;
    request.changesReviewed = false;
    request.economicRole = ALT_CLS_SourceLinkService.ROLE_APPLICATION;
    request.operationKey = input.operationKey;
    ALT_CLS_SourceLinkService.ConfirmResult linked = link(request);
    ConfirmResult result = new ConfirmResult();
    result.allocationId = linked.allocationId;
    result.replayed = linked.replayed;
    result.amount = linked.amount;
    result.currencyIso = linked.currencyIso;
    return result;
  }

  private static ALT_CLS_SourceLinkService.ConfirmResult link(
    ALT_CLS_SourceLinkService.ConfirmInput request
  ) {
    try {
      return new ALT_CLS_SourceLinkService().confirm(request);
    } catch (ALT_CLS_SourceLinkService.SourceLinkException failure) {
      throw new ManualEntryException(failure.getMessage());
    }
  }

  // ------------------------------------------------------------------ realize

  /**
   * @description Posts an entry that already happened. A wallet or an unconnected account/card is
   * realized at once with a MANUAL fact (AXF-25: ACTUAL_ONLY + allocated fact, one command). A
   * Pluggy-connected source is realized only against the chosen Pluggy fact (AXF-134 with no
   * target: the ACTUAL_ONLY entry is born reconciled to it); without a fact nothing is written.
   */
  public RealizeResult realize(RealizeInput input) {
    check(
      input != null &&
        input.entry != null &&
        input.entry.targetId == null &&
        validKey(input.operationKey),
      'INVALID_INPUT'
    );
    Base b = base(input.entry);
    RealizeResult result = new RealizeResult();
    if (!b.funding.connected) {
      check(input.factId == null, 'INVALID_INPUT');
      check(canRealize(), 'UNAVAILABLE');
      ALT_CLS_RealizationService.Input request = new ALT_CLS_RealizationService.Input();
      request.targetId = null;
      request.sourceId = null;
      request.accountId = b.funding.holderId;
      request.sourceKind = b.funding.sourceKind;
      request.fundingId = b.funding.fundingId;
      request.amount = b.amount;
      request.currencyIso = b.iso;
      request.direction = b.direction;
      request.recognitionDate = b.onDate;
      request.economicRole = ALT_CLS_SourceLinkService.ROLE_APPLICATION;
      request.operationKey = input.operationKey;
      Id allocationId;
      try {
        allocationId = new ALT_CLS_RealizationService().apply(request);
      } catch (ALT_CLS_RealizationService.RealizationException failure) {
        throw new ManualEntryException(failure.getMessage());
      }
      List<AXF_OBJ_ReconciliationAllocation__c> rows = [
        SELECT
          AXF_RA_LKP_FinancialTransaction__c,
          AXF_RA_NUM_Magnitude__c,
          AXF_RA_TXT_CurrencyIsoCode__c
        FROM AXF_OBJ_ReconciliationAllocation__c
        WHERE Id = :allocationId
        WITH USER_MODE
        LIMIT 1
      ];
      check(rows.size() == 1, 'UNAVAILABLE');
      result.allocationId = allocationId;
      result.financialTransactionId = rows[0]
        .AXF_RA_LKP_FinancialTransaction__c;
      result.amount = rows[0].AXF_RA_NUM_Magnitude__c;
      result.currencyIso = rows[0].AXF_RA_TXT_CurrencyIsoCode__c;
      return result;
    }
    requireAccess();
    check(input.factId != null && input.factVersion != null, 'FACT_REQUIRED');
    ALT_CLS_SourceLinkService.SourceView source = readFact(
      b.funding,
      input.factId
    );
    check(
      source.direction == b.direction && source.currencyIso == b.iso,
      'FACT_MISMATCH'
    );
    ALT_CLS_SourceLinkService.ConfirmInput request = new ALT_CLS_SourceLinkService.ConfirmInput();
    request.sourceId = source.sourceId;
    request.sourceKind = source.sourceKind;
    request.sourceVersion = input.factVersion;
    request.targetId = null;
    request.targetVersion = null;
    // The fact is the truth of what was paid: never more than what is still available on it.
    request.amount = source.residual == null
      ? b.amount
      : Math.min(b.amount, source.residual);
    request.recognitionDate = b.onDate;
    // The typed amount/date are the user's explicit review of any difference from the fact.
    request.changesReviewed =
      request.amount != source.residual ||
      b.onDate != source.factDate;
    request.economicRole = ALT_CLS_SourceLinkService.ROLE_APPLICATION;
    request.operationKey = input.operationKey;
    ALT_CLS_SourceLinkService.ConfirmResult linked = link(request);
    result.financialTransactionId = linked.targetId;
    result.allocationId = linked.allocationId;
    result.linkedToFact = true;
    result.replayed = linked.replayed;
    result.amount = linked.amount;
    result.currencyIso = linked.currencyIso;
    return result;
  }

  // ------------------------------------------------------------------- report

  /**
   * @description Manual entries (planned or posted as realized, outside any schedule or contract)
   * of every authorized holder in a month or custom period, with the source they were posted on and
   * a reconciliation status derived from the allocations. Reading needs only the authorized context
   * and USER_MODE access; an allocation read that is refused or truncated leaves the entry
   * unverified instead of guessing.
   */
  public ReportView listEntries(ReportQuery query) {
    check(query != null, 'INVALID_INPUT');
    check(
      (String.isBlank(query.status) || STATUSES.contains(query.status)) &&
        (String.isBlank(query.direction) ||
        DIRECTIONS.contains(query.direction)) &&
        (query.originId == null ||
        query.originId.getSObjectType() == AXF_OBJ_BankAccount__c.SObjectType ||
        query.originId.getSObjectType() == AXF_OBJ_CreditCard__c.SObjectType),
      'INVALID_INPUT'
    );
    ReportView result = new ReportView();
    period(query, result);
    Set<Id> holders = authorizedHolders().keySet();
    if (holders.isEmpty()) {
      return result;
    }
    Map<Id, OriginOption> origins = origins(holders);
    result.origins.addAll(origins.values());
    Boolean byDirection = String.isNotBlank(query.direction);
    String soql =
      'SELECT Id, AXF_FTX_LKP_Account__c, AXF_FTX_LKP_BankAccount__c, AXF_FTX_LKP_CreditCard__c,' +
      ' AXF_FTX_NUM_Magnitude__c, AXF_FTX_TXT_CurrencyIsoCode__c, AXF_FTX_PKL_Direction__c,' +
      ' AXF_FTX_DAT_DueDate__c, AXF_FTX_DAT_PurchaseDate__c, AXF_FTX_TXT_Description__c,' +
      ' AXF_FTX_PKL_PlanKind__c' +
      ' FROM AXF_OBJ_FinancialTransaction__c' +
      ' WHERE AXF_FTX_LKP_Account__c IN :holders' +
      ' AND AXF_FTX_PKL_PlanKind__c IN :planKinds' +
      ' AND AXF_FTX_LKP_Schedule__c = NULL AND AXF_FTX_LKP_Contract__c = NULL' +
      ' AND (AXF_FTX_PKL_ScheduleState__c = NULL OR AXF_FTX_PKL_ScheduleState__c != \'CANCELLED\')' +
      ' AND ((AXF_FTX_DAT_DueDate__c >= :fromDate AND AXF_FTX_DAT_DueDate__c <= :toDate)' +
      ' OR (AXF_FTX_DAT_DueDate__c = NULL AND AXF_FTX_DAT_PurchaseDate__c >= :fromDate' +
      ' AND AXF_FTX_DAT_PurchaseDate__c <= :toDate))' +
      (byDirection ? ' AND AXF_FTX_PKL_Direction__c = :direction' : '') +
      ' ORDER BY AXF_FTX_DAT_DueDate__c DESC NULLS LAST, AXF_FTX_DAT_PurchaseDate__c DESC, Id ASC' +
      ' LIMIT :cap';
    List<AXF_OBJ_FinancialTransaction__c> rows = (List<AXF_OBJ_FinancialTransaction__c>) Database.queryWithBinds(
      soql,
      new Map<String, Object>{
        'holders' => holders,
        'planKinds' => PLAN_KINDS,
        'fromDate' => result.fromDate,
        'toDate' => result.toDate,
        'direction' => byDirection ? query.direction : null,
        'cap' => MAX_ENTRIES + 1
      },
      AccessLevel.USER_MODE
    );
    if (rows.size() > MAX_ENTRIES) {
      result.truncated = true;
      rows.remove(rows.size() - 1);
    }
    Set<Id> ids = new Map<Id, AXF_OBJ_FinancialTransaction__c>(rows).keySet();
    Set<Id> unverified = new Set<Id>();
    Map<Id, Decimal> nets = nets(ids, unverified);
    Map<Id, Id> derived = derivedOrigins(rows);
    for (AXF_OBJ_FinancialTransaction__c row : rows) {
      EntryView v = new EntryView();
      v.recordId = row.Id;
      v.holderId = row.AXF_FTX_LKP_Account__c;
      v.holderLabel = authorizedHolders().get(row.AXF_FTX_LKP_Account__c);
      v.entryDate = entryDate(row);
      v.description = row.AXF_FTX_TXT_Description__c;
      v.amount = row.AXF_FTX_NUM_Magnitude__c;
      v.direction = row.AXF_FTX_PKL_Direction__c;
      v.currencyIso = row.AXF_FTX_TXT_CurrencyIsoCode__c;
      v.planKind = row.AXF_FTX_PKL_PlanKind__c;
      v.originId = row.AXF_FTX_LKP_BankAccount__c != null
        ? row.AXF_FTX_LKP_BankAccount__c
        : row.AXF_FTX_LKP_CreditCard__c != null
            ? row.AXF_FTX_LKP_CreditCard__c
            : derived.get(row.Id);
      OriginOption origin = v.originId == null ? null : origins.get(v.originId);
      if (origin != null) {
        v.originKind = origin.kind;
        v.originLabel = origin.label;
      } else if (v.originId != null) {
        v.originKind = v.originId.getSObjectType() ==
          AXF_OBJ_CreditCard__c.SObjectType
          ? ORIGIN_CREDIT_CARD
          : ORIGIN_BANK_ACCOUNT;
      }
      applyStatus(v, nets, unverified);
      if (
        (String.isNotBlank(query.status) && v.status != query.status) ||
        (query.originId != null &&
        v.originId != query.originId)
      ) {
        continue;
      }
      result.entries.add(v);
    }
    return result;
  }

  /** A custom period wins over the month; both are bounded and validated. */
  private static void period(ReportQuery query, ReportView result) {
    if (query.fromDate != null || query.toDate != null) {
      check(
        query.fromDate != null &&
          query.toDate != null &&
          query.fromDate <= query.toDate &&
          query.fromDate.daysBetween(query.toDate) < MAX_PERIOD_DAYS,
        'INVALID_INPUT'
      );
      result.customPeriod = true;
      result.fromDate = query.fromDate;
      result.toDate = query.toDate;
      result.year = query.fromDate.year();
      result.month = query.fromDate.month();
      return;
    }
    Integer year = query.year == null ? today().year() : query.year;
    Integer month = query.month == null ? today().month() : query.month;
    check(
      year >= 1900 && year <= 9999 && month >= 1 && month <= 12,
      'INVALID_INPUT'
    );
    result.year = year;
    result.month = month;
    result.fromDate = Date.newInstance(year, month, 1);
    result.toDate = result.fromDate.addMonths(1).addDays(-1);
  }

  /** Accounts, wallets and cards of the authorized holders, labelled for display and filtering. */
  private static Map<Id, OriginOption> origins(Set<Id> holders) {
    Map<Id, OriginOption> result = new Map<Id, OriginOption>();
    // A refused read of one kind of source only leaves those labels unknown; it never hides entries.
    try {
      addBankOrigins(holders, result);
    } catch (Exception refused) {
      result.clear();
    }
    Map<Id, OriginOption> cards = new Map<Id, OriginOption>();
    try {
      addCardOrigins(holders, cards);
    } catch (Exception refused) {
      cards.clear();
    }
    result.putAll(cards);
    return result;
  }

  private static void addBankOrigins(
    Set<Id> holders,
    Map<Id, OriginOption> result
  ) {
    for (AXF_OBJ_BankAccount__c row : [
      SELECT
        Id,
        AXF_BA_LKP_Account__c,
        AXF_BA_TXT_InstitutionName__c,
        AXF_BA_LKP_BankInstitution__r.Name,
        AXF_BA_TXT_NumberMasked__c,
        AXF_BA_TXT_Type__c
      FROM AXF_OBJ_BankAccount__c
      WHERE AXF_BA_LKP_Account__c IN :holders
      WITH USER_MODE
      ORDER BY AXF_BA_TXT_InstitutionName__c, Id
      LIMIT :MAX_ORIGINS
    ]) {
      Boolean wallet = ALT_CLS_BankStatementService.TYPE_WALLET.equalsIgnoreCase(
        row.AXF_BA_TXT_Type__c
      );
      OriginOption o = new OriginOption();
      o.originId = row.Id;
      o.holderId = row.AXF_BA_LKP_Account__c;
      o.kind = wallet ? ORIGIN_WALLET : ORIGIN_BANK_ACCOUNT;
      o.label = label(
        wallet
          ? System.Label.AXF_BankStatement_wallet
          : (row.AXF_BA_LKP_BankInstitution__r == null
              ? row.AXF_BA_TXT_InstitutionName__c
              : row.AXF_BA_LKP_BankInstitution__r.Name),
        row.AXF_BA_TXT_NumberMasked__c
      );
      result.put(row.Id, o);
    }
  }

  private static void addCardOrigins(
    Set<Id> holders,
    Map<Id, OriginOption> result
  ) {
    for (AXF_OBJ_CreditCard__c row : [
      SELECT
        Id,
        AXF_CC_LKP_Account__c,
        AXF_CC_TXT_InstitutionName__c,
        AXF_CC_LKP_BankInstitution__r.Name,
        AXF_CC_TXT_LastFourMasked__c
      FROM AXF_OBJ_CreditCard__c
      WHERE AXF_CC_LKP_Account__c IN :holders
      WITH USER_MODE
      ORDER BY AXF_CC_TXT_InstitutionName__c, Id
      LIMIT :MAX_ORIGINS
    ]) {
      OriginOption o = new OriginOption();
      o.originId = row.Id;
      o.holderId = row.AXF_CC_LKP_Account__c;
      o.kind = ORIGIN_CREDIT_CARD;
      o.label = label(
        row.AXF_CC_LKP_BankInstitution__r == null
          ? row.AXF_CC_TXT_InstitutionName__c
          : row.AXF_CC_LKP_BankInstitution__r.Name,
        row.AXF_CC_TXT_LastFourMasked__c
      );
      result.put(row.Id, o);
    }
  }

  private static String label(String name, String masked) {
    String result = String.isBlank(name) ? '' : name.trim();
    if (String.isNotBlank(masked)) {
      result += (result == '' ? '' : ' ') + masked.trim();
    }
    return result;
  }

  /**
   * An entry posted as realized from a fact carries no source lookup (the realization contract
   * creates it from the fact): its origin is the source of the fact it is allocated to.
   */
  private static Map<Id, Id> derivedOrigins(
    List<AXF_OBJ_FinancialTransaction__c> rows
  ) {
    Map<Id, Id> result = new Map<Id, Id>();
    Set<Id> missing = new Set<Id>();
    for (AXF_OBJ_FinancialTransaction__c row : rows) {
      if (
        row.AXF_FTX_LKP_BankAccount__c == null &&
        row.AXF_FTX_LKP_CreditCard__c == null
      ) {
        missing.add(row.Id);
      }
    }
    if (missing.isEmpty()) {
      return result;
    }
    Integer cap = ALT_CLS_SourceLinkService.MAX_ALLOCATION_ROWS;
    try {
      for (AXF_OBJ_ReconciliationAllocation__c row : [
        SELECT
          AXF_RA_LKP_FinancialTransaction__c,
          AXF_RA_LKP_BankTransaction__r.AXF_BAT_MDR_BankAccount__c,
          AXF_RA_LKP_CardTransaction__r.AXF_CCT_MDR_CreditCard__c
        FROM AXF_OBJ_ReconciliationAllocation__c
        WHERE
          AXF_RA_LKP_FinancialTransaction__c IN :missing
          AND AXF_RA_PKL_Kind__c = 'APPLICATION'
        WITH USER_MODE
        ORDER BY CreatedDate ASC, Id ASC
        LIMIT :cap
      ]) {
        Id origin = row.AXF_RA_LKP_BankTransaction__r
            ?.AXF_BAT_MDR_BankAccount__c != null
          ? row.AXF_RA_LKP_BankTransaction__r.AXF_BAT_MDR_BankAccount__c
          : row.AXF_RA_LKP_CardTransaction__r?.AXF_CCT_MDR_CreditCard__c;
        if (
          origin != null &&
          !result.containsKey(row.AXF_RA_LKP_FinancialTransaction__c)
        ) {
          result.put(row.AXF_RA_LKP_FinancialTransaction__c, origin);
        }
      }
    } catch (Exception refused) {
      // Without read access to the allocations the origin simply stays unknown.
      return result;
    }
    return result;
  }

  /**
   * Net allocation (APPLICATION minus REVERSAL) per entry. With the link capability the link
   * contract's verified net is used; without it the net of the allocations the user can see, and a
   * truncated or refused read leaves the entries unverified.
   */
  private static Map<Id, Decimal> nets(Set<Id> ids, Set<Id> unverified) {
    if (ids.isEmpty()) {
      return new Map<Id, Decimal>();
    }
    if (canReconcile()) {
      return new ALT_CLS_SourceLinkService().netOfTargets(ids, unverified);
    }
    Map<Id, Decimal> result = new Map<Id, Decimal>();
    Integer cap = ALT_CLS_SourceLinkService.MAX_ALLOCATION_ROWS;
    List<AXF_OBJ_ReconciliationAllocation__c> rows;
    try {
      rows = [
        SELECT
          AXF_RA_LKP_FinancialTransaction__c,
          AXF_RA_PKL_Kind__c,
          AXF_RA_NUM_Magnitude__c
        FROM AXF_OBJ_ReconciliationAllocation__c
        WHERE AXF_RA_LKP_FinancialTransaction__c IN :ids
        WITH USER_MODE
        LIMIT :cap
      ];
    } catch (Exception refused) {
      unverified.addAll(ids);
      return result;
    }
    if (rows.size() >= cap) {
      unverified.addAll(ids);
      return result;
    }
    for (AXF_OBJ_ReconciliationAllocation__c row : rows) {
      Id key = row.AXF_RA_LKP_FinancialTransaction__c;
      Decimal sign = row.AXF_RA_PKL_Kind__c == 'REVERSAL' ? -1 : 1;
      result.put(
        key,
        (result.containsKey(key) ? result.get(key) : 0) +
        sign * row.AXF_RA_NUM_Magnitude__c
      );
    }
    return result;
  }

  private static void applyStatus(
    EntryView v,
    Map<Id, Decimal> nets,
    Set<Id> unverified
  ) {
    if (unverified.contains(v.recordId) || v.amount == null) {
      v.status = STATUS_UNVERIFIED;
      return;
    }
    v.allocated = nets.containsKey(v.recordId) ? nets.get(v.recordId) : 0;
    v.residual = v.amount - v.allocated;
    if (v.residual <= 0) {
      v.status = STATUS_RECONCILED;
    } else if (v.allocated > 0) {
      v.status = STATUS_PARTIAL;
    } else {
      v.status = STATUS_UNRECONCILED;
    }
  }
}
