/**
 * @description AXF-151: current-account ("Conta Corrente") capability. Lists the bank accounts and
 * wallets of the authorized holders with their balance, builds the monthly/period statement of one
 * account (bank facts plus manual entries not yet allocated) with a derived reconciliation status,
 * suggests candidates inside the AXF-MATCHING@1.1.0 window and confirms one of them through the
 * AXF-134 link contract. The balance of an account without a Pluggy connection is edited manually
 * under optimistic versioning; a connected account is refreshed through the discovery flow.
 * Reconciliation state is never written: it is always derived from the canonical allocations.
 */
public with sharing class ALT_CLS_BankStatementService {
  public static final String MATCHING_POLICY = ALT_CLS_MatchingWindow.POLICY;
  public static final String CP_CONFIGURE = 'AXF_CanConfigure';
  public static final String TYPE_WALLET = 'WALLET';
  public static final String LINE_FACT = 'FACT';
  public static final String LINE_ENTRY = 'ENTRY';
  public static final String STATUS_RECONCILED = 'RECONCILED';
  public static final String STATUS_PARTIAL = 'PARTIAL';
  public static final String STATUS_UNRECONCILED = 'UNRECONCILED';
  public static final String STATUS_UNVERIFIED = 'UNVERIFIED';
  /** Policy 1.1.0 window: |Δamount| ≤ 5% of the source amount, |Δdate| ≤ 7 calendar days. */
  public static final Decimal AMOUNT_TOLERANCE = ALT_CLS_MatchingWindow.AMOUNT_TOLERANCE;
  public static final Integer DAY_WINDOW = ALT_CLS_MatchingWindow.DAY_WINDOW;
  public static final Integer MAX_ACCOUNTS = 200;
  public static final Integer MAX_FACTS = 500;
  public static final Integer MAX_ENTRIES = 200;
  public static final Integer MAX_PERIOD_DAYS = 366;
  /** Candidate/source pages read per suggestion; the scan never grows past it. */
  public static final Integer MAX_SUGGESTION_PAGES = 4;
  private static final Set<String> PLAN_KINDS = new Set<String>{
    'PLANNED',
    'ACTUAL_ONLY'
  };

  @TestVisible
  private static Boolean canConfigureOverride;
  @TestVisible
  private static Date todayOverride;

  public class BankStatementException extends Exception {
  }

  public class AccountView {
    @AuraEnabled
    public Id bankAccountId;
    @AuraEnabled
    public Id holderId;
    @AuraEnabled
    public String holderLabel;
    @AuraEnabled
    public String institutionName;
    @AuraEnabled
    public String numberMasked;
    @AuraEnabled
    public String accountType;
    @AuraEnabled
    public Boolean wallet = false;
    @AuraEnabled
    public Boolean hasConnection = false;
    @AuraEnabled
    public Decimal currentBalance;
    @AuraEnabled
    public String currencyIso;
    @AuraEnabled
    public Decimal version;
    @AuraEnabled
    public Boolean canEditBalance = false;
    @AuraEnabled
    public Boolean canRefresh = false;
  }

  public class StatementQuery {
    public Id bankAccountId;
    public Integer year;
    public Integer month;
    public Date fromDate;
    public Date toDate;
    public Decimal minAmount;
    public Decimal maxAmount;
    public String term;
  }

  public class LineView {
    @AuraEnabled
    public String lineKind;
    @AuraEnabled
    public Id recordId;
    @AuraEnabled
    public Date lineDate;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public String direction;
    @AuraEnabled
    public String currencyIso;
    /** PLUGGY | CSV | MANUAL for a fact; PLANNED | ACTUAL_ONLY for a manual entry. */
    @AuraEnabled
    public String origin;
    @AuraEnabled
    public Decimal allocated;
    @AuraEnabled
    public Decimal residual;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Decimal version;
    @AuraEnabled
    public Boolean canSuggest = false;
  }

  public class StatementView {
    @AuraEnabled
    public String matchingPolicy = MATCHING_POLICY;
    @AuraEnabled
    public AccountView account;
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
    /** False without the link capability: the statement is read-only and offers no suggestion. */
    @AuraEnabled
    public Boolean canReconcile = false;
    @AuraEnabled
    public Boolean truncated = false;
    @AuraEnabled
    public List<LineView> lines = new List<LineView>();
  }

  public class SuggestionQuery {
    public Id bankAccountId;
    public String lineKind;
    public Id recordId;
  }

  public class SuggestionView {
    /** The bank fact (link source) and the financial transaction (link target) of the pair. */
    @AuraEnabled
    public Id sourceId;
    @AuraEnabled
    public Decimal sourceVersion;
    @AuraEnabled
    public Id targetId;
    @AuraEnabled
    public Decimal targetVersion;
    /** The counterpart shown to the user: a planned entry for a fact line, a fact for an entry line. */
    @AuraEnabled
    public Id candidateId;
    @AuraEnabled
    public Date candidateDate;
    @AuraEnabled
    public Decimal candidateAmount;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public String currencyIso;
    @AuraEnabled
    public Decimal amountDelta;
    @AuraEnabled
    public Integer dayDelta;
    /** min(source residual, target available): what one click allocates. */
    @AuraEnabled
    public Decimal allocationAmount;
    @AuraEnabled
    public Boolean tied = false;
  }

  public class SuggestionPage {
    @AuraEnabled
    public String matchingPolicy = MATCHING_POLICY;
    @AuraEnabled
    public Boolean truncated = false;
    @AuraEnabled
    public List<SuggestionView> items = new List<SuggestionView>();
  }

  public class ConfirmInput {
    public Id bankAccountId;
    public Id sourceId;
    public Decimal sourceVersion;
    public Id targetId;
    public Decimal targetVersion;
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

  public class BalanceInput {
    public Id bankAccountId;
    public Decimal balance;
    public Decimal expectedVersion;
  }

  public class RefreshResult {
    @AuraEnabled
    public String state;
    @AuraEnabled
    public Boolean complete = false;
    @AuraEnabled
    public AccountView account;
  }

  // ------------------------------------------------------------------ access

  /** @description Reading and reconciling rely on the link capability (AXF-134) and AXF-25. */
  public static void requireAccess() {
    try {
      ALT_CLS_SourceLinkService.requireAccess();
    } catch (ALT_CLS_SourceLinkService.SourceLinkException denied) {
      throw new BankStatementException('UNAVAILABLE');
    }
  }

  public static Boolean canConfigure() {
    return canConfigureOverride == null
      ? FeatureManagement.checkPermission(CP_CONFIGURE)
      : canConfigureOverride;
  }

  private Boolean reconcileCache;
  /** Link capability (AXF-134 + AXF-25): only it unlocks suggestions and confirmation. */
  public Boolean canReconcile() {
    if (reconcileCache == null) {
      try {
        requireAccess();
        reconcileCache = true;
      } catch (BankStatementException denied) {
        reconcileCache = false;
      }
    }
    return reconcileCache;
  }

  private static void check(Boolean valid, String code) {
    if (!valid) {
      throw new BankStatementException(code);
    }
  }

  private static Date today() {
    return todayOverride == null ? Date.today() : todayOverride;
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

  // ---------------------------------------------------------------- accounts

  /** @description Available bank accounts and wallets of every authorized holder, with balance. */
  public List<AccountView> listAccounts() {
    // Read path: the authorized context and USER_MODE object access are the only authority.
    Set<Id> holders = authorizedHolders().keySet();
    List<AccountView> result = new List<AccountView>();
    if (holders.isEmpty()) {
      return result;
    }
    for (AXF_OBJ_BankAccount__c row : [
      SELECT
        Id,
        AXF_BA_LKP_Account__c,
        AXF_BA_TXT_InstitutionName__c,
        AXF_BA_LKP_BankInstitution__r.Name,
        AXF_BA_TXT_NumberMasked__c,
        AXF_BA_TXT_Type__c,
        AXF_BA_LKP_Connection__c,
        AXF_BA_CUR_CurrentBalance__c,
        AXF_BA_TXT_CurrencyIsoCode__c,
        AXF_BA_NUM_Version__c
      FROM AXF_OBJ_BankAccount__c
      WHERE
        AXF_BA_LKP_Account__c IN :holders
        AND AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE'
      WITH USER_MODE
      ORDER BY AXF_BA_LKP_Account__c, AXF_BA_TXT_InstitutionName__c, Id
      LIMIT :MAX_ACCOUNTS
    ]) {
      result.add(view(row));
    }
    return result;
  }

  private AccountView view(AXF_OBJ_BankAccount__c row) {
    AccountView v = new AccountView();
    v.bankAccountId = row.Id;
    v.holderId = row.AXF_BA_LKP_Account__c;
    v.holderLabel = authorizedHolders().get(row.AXF_BA_LKP_Account__c);
    v.accountType = row.AXF_BA_TXT_Type__c;
    v.wallet = TYPE_WALLET.equalsIgnoreCase(row.AXF_BA_TXT_Type__c);
    v.institutionName = v.wallet
      ? null
      : (row.AXF_BA_LKP_BankInstitution__r == null
          ? row.AXF_BA_TXT_InstitutionName__c
          : row.AXF_BA_LKP_BankInstitution__r.Name);
    v.numberMasked = row.AXF_BA_TXT_NumberMasked__c;
    v.hasConnection = row.AXF_BA_LKP_Connection__c != null;
    v.currentBalance = row.AXF_BA_CUR_CurrentBalance__c;
    v.currencyIso = row.AXF_BA_TXT_CurrencyIsoCode__c;
    v.version = row.AXF_BA_NUM_Version__c == null
      ? 0
      : row.AXF_BA_NUM_Version__c;
    Boolean configure = canConfigure();
    v.canRefresh = configure && v.hasConnection;
    v.canEditBalance = configure && !v.hasConnection;
    return v;
  }

  /** One account of an authorized holder; anything else is indistinguishable from missing. */
  private AXF_OBJ_BankAccount__c readAccount(Id bankAccountId) {
    check(
      bankAccountId != null &&
        bankAccountId.getSObjectType() == AXF_OBJ_BankAccount__c.SObjectType,
      'INVALID_INPUT'
    );
    List<AXF_OBJ_BankAccount__c> rows = [
      SELECT
        Id,
        AXF_BA_LKP_Account__c,
        AXF_BA_TXT_InstitutionName__c,
        AXF_BA_LKP_BankInstitution__r.Name,
        AXF_BA_TXT_NumberMasked__c,
        AXF_BA_TXT_Type__c,
        AXF_BA_LKP_Connection__c,
        AXF_BA_CUR_CurrentBalance__c,
        AXF_BA_TXT_CurrencyIsoCode__c,
        AXF_BA_NUM_Version__c,
        AXF_BA_PKL_AvailabilityState__c
      FROM AXF_OBJ_BankAccount__c
      WHERE Id = :bankAccountId
      WITH USER_MODE
      LIMIT 1
    ];
    check(
      rows.size() == 1 &&
        authorizedHolders().containsKey(rows[0].AXF_BA_LKP_Account__c) &&
        rows[0].AXF_BA_PKL_AvailabilityState__c == 'AVAILABLE',
      'NOT_ACCESSIBLE'
    );
    return rows[0];
  }

  // --------------------------------------------------------------- statement

  /** @description Facts and unallocated manual entries of one account in a month or custom period. */
  public StatementView statement(StatementQuery query) {
    check(query != null, 'INVALID_INPUT');
    AXF_OBJ_BankAccount__c account = readAccount(query.bankAccountId);
    StatementView result = new StatementView();
    result.canReconcile = canReconcile();
    result.account = view(account);
    period(query, result);
    check(
      (query.minAmount == null ||
        query.minAmount >= 0) &&
        (query.maxAmount == null ||
        query.maxAmount >= 0) &&
        (query.minAmount == null ||
        query.maxAmount == null ||
        query.minAmount <= query.maxAmount) &&
        (query.term == null ||
        query.term.length() <= 100),
      'INVALID_INPUT'
    );
    List<LineView> lines = new List<LineView>();
    lines.addAll(factLines(account, query, result));
    lines.addAll(entryLines(account, query, result));
    List<LineKey> keys = new List<LineKey>();
    for (LineView line : lines) {
      keys.add(new LineKey(line));
    }
    keys.sort();
    for (LineKey key : keys) {
      result.lines.add(key.line);
    }
    return result;
  }

  /** A custom period wins over the month; both are bounded and validated. */
  private static void period(StatementQuery query, StatementView result) {
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

  private static String pattern(String term) {
    // Bound values treat escaped wildcards literally; the search never reaches the SOQL text.
    return ('%' +
    term.trim().replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_') +
    '%');
  }

  private static String amountFilter(String field, StatementQuery query) {
    return (query.minAmount == null ? '' : ' AND ' + field + ' >= :minAmount') +
      (query.maxAmount == null ? '' : ' AND ' + field + ' <= :maxAmount');
  }

  private Map<String, Object> binds(
    AXF_OBJ_BankAccount__c account,
    StatementQuery query,
    StatementView result,
    Integer cap
  ) {
    return new Map<String, Object>{
      'bankAccountId' => account.Id,
      'holderId' => account.AXF_BA_LKP_Account__c,
      'fromDate' => result.fromDate,
      'toDate' => result.toDate,
      'minAmount' => query.minAmount,
      'maxAmount' => query.maxAmount,
      'pattern' => String.isBlank(query.term) ? null : pattern(query.term),
      'planKinds' => PLAN_KINDS,
      'cap' => cap + 1
    };
  }

  private List<LineView> factLines(
    AXF_OBJ_BankAccount__c account,
    StatementQuery query,
    StatementView result
  ) {
    String soql =
      'SELECT Id, AXF_BAT_NUM_Magnitude__c, AXF_BAT_TXT_CurrencyIsoCode__c, AXF_BAT_PKL_Direction__c,' +
      ' AXF_BAT_DAT_Date__c, AXF_BAT_TXT_Description__c, AXF_BAT_PKL_Source__c, AXF_BAT_NUM_Version__c' +
      ' FROM AXF_OBJ_BankAccountTransaction__c' +
      ' WHERE AXF_BAT_MDR_BankAccount__c = :bankAccountId' +
      ' AND AXF_BAT_PKL_Status__c = \'POSTED\'' +
      ' AND AXF_BAT_DAT_Date__c >= :fromDate AND AXF_BAT_DAT_Date__c <= :toDate' +
      amountFilter('AXF_BAT_NUM_Magnitude__c', query) +
      (String.isBlank(query.term)
        ? ''
        : ' AND AXF_BAT_TXT_Description__c LIKE :pattern') +
      ' ORDER BY AXF_BAT_DAT_Date__c DESC, Id ASC LIMIT :cap';
    List<AXF_OBJ_BankAccountTransaction__c> rows = (List<AXF_OBJ_BankAccountTransaction__c>) Database.queryWithBinds(
      soql,
      binds(account, query, result, MAX_FACTS),
      AccessLevel.USER_MODE
    );
    if (rows.size() > MAX_FACTS) {
      result.truncated = true;
      rows.remove(rows.size() - 1);
    }
    Set<Id> unverified = new Set<Id>();
    Map<Id, Decimal> nets = nets(
      true,
      new Map<Id, AXF_OBJ_BankAccountTransaction__c>(rows).keySet(),
      unverified
    );
    List<LineView> lines = new List<LineView>();
    for (AXF_OBJ_BankAccountTransaction__c row : rows) {
      LineView line = new LineView();
      line.lineKind = LINE_FACT;
      line.recordId = row.Id;
      line.lineDate = row.AXF_BAT_DAT_Date__c;
      line.description = row.AXF_BAT_TXT_Description__c;
      line.amount = row.AXF_BAT_NUM_Magnitude__c;
      line.direction = row.AXF_BAT_PKL_Direction__c;
      line.currencyIso = row.AXF_BAT_TXT_CurrencyIsoCode__c;
      line.origin = row.AXF_BAT_PKL_Source__c;
      line.version = row.AXF_BAT_NUM_Version__c == null
        ? 0
        : row.AXF_BAT_NUM_Version__c;
      applyStatus(line, nets, unverified);
      line.canSuggest = line.canSuggest && canReconcile();
      lines.add(line);
    }
    return lines;
  }

  /**
   * Manual entries (planned or actual-only) posted against this account whose net allocation is
   * zero. Any allocated entry is shown only through the fact that carries it, so nothing doubles.
   */
  private List<LineView> entryLines(
    AXF_OBJ_BankAccount__c account,
    StatementQuery query,
    StatementView result
  ) {
    String soql =
      'SELECT Id, AXF_FTX_NUM_Magnitude__c, AXF_FTX_TXT_CurrencyIsoCode__c, AXF_FTX_PKL_Direction__c,' +
      ' AXF_FTX_DAT_DueDate__c, AXF_FTX_DAT_PurchaseDate__c, AXF_FTX_TXT_Description__c,' +
      ' AXF_FTX_PKL_PlanKind__c, AXF_FTX_NUM_Version__c' +
      ' FROM AXF_OBJ_FinancialTransaction__c' +
      ' WHERE AXF_FTX_LKP_BankAccount__c = :bankAccountId' +
      ' AND AXF_FTX_LKP_Account__c = :holderId' +
      ' AND AXF_FTX_PKL_PlanKind__c IN :planKinds' +
      ' AND (AXF_FTX_PKL_ScheduleState__c = NULL OR AXF_FTX_PKL_ScheduleState__c != \'CANCELLED\')' +
      ' AND ((AXF_FTX_DAT_DueDate__c >= :fromDate AND AXF_FTX_DAT_DueDate__c <= :toDate)' +
      ' OR (AXF_FTX_DAT_DueDate__c = NULL AND AXF_FTX_DAT_PurchaseDate__c >= :fromDate' +
      ' AND AXF_FTX_DAT_PurchaseDate__c <= :toDate))' +
      amountFilter('AXF_FTX_NUM_Magnitude__c', query) +
      (String.isBlank(query.term)
        ? ''
        : ' AND AXF_FTX_TXT_Description__c LIKE :pattern') +
      ' ORDER BY AXF_FTX_DAT_DueDate__c DESC NULLS LAST, AXF_FTX_DAT_PurchaseDate__c DESC, Id ASC LIMIT :cap';
    List<AXF_OBJ_FinancialTransaction__c> rows = (List<AXF_OBJ_FinancialTransaction__c>) Database.queryWithBinds(
      soql,
      binds(account, query, result, MAX_ENTRIES),
      AccessLevel.USER_MODE
    );
    if (rows.size() > MAX_ENTRIES) {
      result.truncated = true;
      rows.remove(rows.size() - 1);
    }
    Set<Id> unverified = new Set<Id>();
    Map<Id, Decimal> nets = nets(
      false,
      new Map<Id, AXF_OBJ_FinancialTransaction__c>(rows).keySet(),
      unverified
    );
    List<LineView> lines = new List<LineView>();
    for (AXF_OBJ_FinancialTransaction__c row : rows) {
      Decimal net = nets.containsKey(row.Id) ? nets.get(row.Id) : 0;
      if (unverified.contains(row.Id) || net != 0) {
        continue;
      }
      LineView line = new LineView();
      line.lineKind = LINE_ENTRY;
      line.recordId = row.Id;
      line.lineDate = row.AXF_FTX_DAT_DueDate__c == null
        ? row.AXF_FTX_DAT_PurchaseDate__c
        : row.AXF_FTX_DAT_DueDate__c;
      line.description = row.AXF_FTX_TXT_Description__c;
      line.amount = row.AXF_FTX_NUM_Magnitude__c;
      line.direction = row.AXF_FTX_PKL_Direction__c;
      line.currencyIso = row.AXF_FTX_TXT_CurrencyIsoCode__c;
      line.origin = row.AXF_FTX_PKL_PlanKind__c;
      line.version = row.AXF_FTX_NUM_Version__c == null
        ? 0
        : row.AXF_FTX_NUM_Version__c;
      line.allocated = 0;
      line.residual = line.amount;
      line.status = STATUS_UNRECONCILED;
      // Only a planned entry can be the target of a link (AXF-134).
      line.canSuggest =
        canReconcile() &&
        row.AXF_FTX_PKL_PlanKind__c == 'PLANNED' &&
        line.amount != null &&
        line.amount > 0;
      lines.add(line);
    }
    return lines;
  }

  /**
   * Net allocation (APPLICATION minus REVERSAL) per fact or entry. With the link capability the
   * link contract's verified net is used; without it the net of the allocations the user can see,
   * and a truncated or refused read leaves the rows unverified instead of guessing.
   */
  private Map<Id, Decimal> nets(
    Boolean sourceSide,
    Set<Id> ids,
    Set<Id> unverified
  ) {
    if (ids.isEmpty()) {
      return new Map<Id, Decimal>();
    }
    if (canReconcile()) {
      ALT_CLS_SourceLinkService link = new ALT_CLS_SourceLinkService();
      return sourceSide
        ? link.netOfSources(ids, unverified)
        : link.netOfTargets(ids, unverified);
    }
    Map<Id, Decimal> result = new Map<Id, Decimal>();
    Integer cap = ALT_CLS_SourceLinkService.MAX_ALLOCATION_ROWS;
    List<AXF_OBJ_ReconciliationAllocation__c> rows;
    try {
      rows = sourceSide
        ? [
            SELECT
              AXF_RA_LKP_BankTransaction__c,
              AXF_RA_LKP_FinancialTransaction__c,
              AXF_RA_PKL_Kind__c,
              AXF_RA_NUM_Magnitude__c
            FROM AXF_OBJ_ReconciliationAllocation__c
            WHERE AXF_RA_LKP_BankTransaction__c IN :ids
            WITH USER_MODE
            LIMIT :cap
          ]
        : [
            SELECT
              AXF_RA_LKP_BankTransaction__c,
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
      Id key = sourceSide
        ? row.AXF_RA_LKP_BankTransaction__c
        : row.AXF_RA_LKP_FinancialTransaction__c;
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
    LineView line,
    Map<Id, Decimal> nets,
    Set<Id> unverified
  ) {
    if (unverified.contains(line.recordId) || line.amount == null) {
      line.status = STATUS_UNVERIFIED;
      return;
    }
    line.allocated = nets.containsKey(line.recordId)
      ? nets.get(line.recordId)
      : 0;
    line.residual = line.amount - line.allocated;
    if (line.residual <= 0) {
      line.status = STATUS_RECONCILED;
    } else if (line.allocated > 0) {
      line.status = STATUS_PARTIAL;
    } else {
      line.status = STATUS_UNRECONCILED;
    }
    line.canSuggest = line.residual > 0;
  }

  private class LineKey implements Comparable {
    public LineView line;
    public LineKey(LineView line) {
      this.line = line;
    }
    public Integer compareTo(Object other) {
      LineView b = ((LineKey) other).line;
      if (line.lineDate != b.lineDate) {
        if (line.lineDate == null) {
          return 1;
        }
        if (b.lineDate == null) {
          return -1;
        }
        return line.lineDate > b.lineDate ? -1 : 1;
      }
      if (line.lineKind != b.lineKind) {
        return line.lineKind == LINE_FACT ? -1 : 1;
      }
      return String.valueOf(line.recordId)
        .compareTo(String.valueOf(b.recordId));
    }
  }

  // ------------------------------------------------------------- suggestions

  /** @description Candidates of one line inside the AXF-MATCHING@1.1.0 window; never a score. */
  public SuggestionPage suggest(SuggestionQuery query) {
    requireAccess();
    check(
      query != null &&
        query.recordId != null &&
        (query.lineKind == LINE_FACT ||
        query.lineKind == LINE_ENTRY),
      'INVALID_INPUT'
    );
    AXF_OBJ_BankAccount__c account = readAccount(query.bankAccountId);
    SuggestionPage page = new SuggestionPage();
    List<SuggestionView> items = query.lineKind == LINE_FACT
      ? factSuggestions(account, query.recordId, page)
      : entrySuggestions(account, query.recordId, page);
    List<ALT_CLS_MatchingWindow.Ranked> ranked = new List<ALT_CLS_MatchingWindow.Ranked>();
    for (SuggestionView item : items) {
      ranked.add(
        new ALT_CLS_MatchingWindow.Ranked(
          item.amountDelta,
          item.dayDelta,
          item.candidateId,
          item
        )
      );
    }
    // Ties stay explicit: the same distance on both axes never selects a winner.
    for (
      ALT_CLS_MatchingWindow.Ranked entry : ALT_CLS_MatchingWindow.order(ranked)
    ) {
      SuggestionView item = (SuggestionView) entry.item;
      item.tied = entry.tied;
      page.items.add(item);
    }
    return page;
  }

  /** The bank fact of this account, read and evaluated by the link contract. */
  private ALT_CLS_SourceLinkService.SourceView readFact(
    AXF_OBJ_BankAccount__c account,
    Id factId
  ) {
    check(
      factId.getSObjectType() == AXF_OBJ_BankAccountTransaction__c.SObjectType,
      'INVALID_INPUT'
    );
    ALT_CLS_SourceLinkService.SourceView source;
    try {
      source = new ALT_CLS_SourceLinkService()
        .readSource(factId, ALT_CLS_SourceLinkService.KIND_BANK);
    } catch (ALT_CLS_SourceLinkService.SourceLinkException hidden) {
      throw new BankStatementException('NOT_ACCESSIBLE');
    }
    check(source.fundingId == account.Id, 'NOT_ACCESSIBLE');
    return source;
  }

  public static Boolean inWindow(
    Decimal baseAmount,
    Date baseDate,
    Decimal otherAmount,
    Date otherDate
  ) {
    return ALT_CLS_MatchingWindow.inWindow(
      baseAmount,
      baseDate,
      otherAmount,
      otherDate
    );
  }

  private List<SuggestionView> factSuggestions(
    AXF_OBJ_BankAccount__c account,
    Id factId,
    SuggestionPage page
  ) {
    ALT_CLS_SourceLinkService.SourceView source = readFact(account, factId);
    List<SuggestionView> result = new List<SuggestionView>();
    if (!source.eligible) {
      return result;
    }
    ALT_CLS_SourceLinkService service = new ALT_CLS_SourceLinkService();
    for (Integer pageNo = 1; pageNo <= MAX_SUGGESTION_PAGES; pageNo++) {
      ALT_CLS_SourceLinkService.CandidateQuery request = new ALT_CLS_SourceLinkService.CandidateQuery();
      request.sourceId = source.sourceId;
      request.sourceKind = ALT_CLS_SourceLinkService.KIND_BANK;
      request.pageNumber = pageNo;
      request.pageSize = ALT_CLS_SourceLinkService.MAX_PAGE;
      ALT_CLS_SourceLinkService.CandidatePage candidates = service.listCandidates(
        request
      );
      page.truncated = page.truncated || candidates.scanTruncated;
      for (ALT_CLS_SourceLinkService.CandidateView c : candidates.items) {
        if (c.persisted != true) {
          // A projection is never linkable; the presentation order may interleave it.
          continue;
        }
        if (
          c.linkable != true ||
          c.currencyIso != source.currencyIso ||
          c.direction != source.direction ||
          !inWindow(source.amount, source.factDate, c.amount, c.dueDate)
        ) {
          continue;
        }
        SuggestionView s = new SuggestionView();
        s.sourceId = source.sourceId;
        s.sourceVersion = source.version;
        s.targetId = c.targetId;
        s.targetVersion = c.version;
        s.candidateId = c.targetId;
        s.candidateDate = c.dueDate;
        s.candidateAmount = c.amount;
        s.description = c.description;
        s.currencyIso = c.currencyIso;
        s.amountDelta = (c.amount - source.amount).abs();
        s.dayDelta = Math.abs(source.factDate.daysBetween(c.dueDate));
        s.allocationAmount = Math.min(source.residual, c.residual);
        result.add(s);
      }
      if (!candidates.hasMore) {
        return result;
      }
    }
    page.truncated = true;
    return result;
  }

  private AXF_OBJ_FinancialTransaction__c readEntry(
    AXF_OBJ_BankAccount__c account,
    Id entryId
  ) {
    check(
      entryId.getSObjectType() == AXF_OBJ_FinancialTransaction__c.SObjectType,
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
      WHERE Id = :entryId
      WITH USER_MODE
      LIMIT 1
    ];
    check(
      rows.size() == 1 &&
        rows[0].AXF_FTX_LKP_Account__c == account.AXF_BA_LKP_Account__c,
      'NOT_ACCESSIBLE'
    );
    return rows[0];
  }

  private static Date entryDate(AXF_OBJ_FinancialTransaction__c row) {
    return row.AXF_FTX_DAT_DueDate__c == null
      ? row.AXF_FTX_DAT_PurchaseDate__c
      : row.AXF_FTX_DAT_DueDate__c;
  }

  /** Available amount of a target entry, or null when its allocations cannot be verified. */
  private static Decimal entryResidual(AXF_OBJ_FinancialTransaction__c row) {
    Set<Id> unverified = new Set<Id>();
    Map<Id, Decimal> nets = new ALT_CLS_SourceLinkService()
      .netOfTargets(new Set<Id>{ row.Id }, unverified);
    if (unverified.contains(row.Id) || row.AXF_FTX_NUM_Magnitude__c == null) {
      return null;
    }
    return row.AXF_FTX_NUM_Magnitude__c -
      (nets.containsKey(row.Id) ? nets.get(row.Id) : 0);
  }

  private List<SuggestionView> entrySuggestions(
    AXF_OBJ_BankAccount__c account,
    Id entryId,
    SuggestionPage page
  ) {
    AXF_OBJ_FinancialTransaction__c entry = readEntry(account, entryId);
    check(entry.AXF_FTX_LKP_BankAccount__c == account.Id, 'NOT_ACCESSIBLE');
    List<SuggestionView> result = new List<SuggestionView>();
    Date onDate = entryDate(entry);
    Decimal available = entryResidual(entry);
    if (
      entry.AXF_FTX_PKL_PlanKind__c != 'PLANNED' ||
      entry.AXF_FTX_PKL_ScheduleState__c == 'CANCELLED' ||
      entry.AXF_FTX_LKP_CreditCard__c != null ||
      onDate == null ||
      available == null ||
      available <= 0
    ) {
      return result;
    }
    // Facts of THIS account inside the 7-day window only, bounded; never the holder's feed.
    Decimal base = entry.AXF_FTX_NUM_Magnitude__c;
    Date fromDate = onDate.addDays(-DAY_WINDOW);
    Date toDate = onDate.addDays(DAY_WINDOW);
    Decimal minAmount = ALT_CLS_MatchingWindow.minAmount(base);
    Decimal maxAmount = ALT_CLS_MatchingWindow.maxAmount(base);
    String iso = entry.AXF_FTX_TXT_CurrencyIsoCode__c;
    String direction = entry.AXF_FTX_PKL_Direction__c;
    Id bankAccountId = account.Id;
    Integer cap = MAX_FACTS + 1;
    List<AXF_OBJ_BankAccountTransaction__c> rows = [
      SELECT
        Id,
        AXF_BAT_NUM_Magnitude__c,
        AXF_BAT_TXT_CurrencyIsoCode__c,
        AXF_BAT_PKL_Direction__c,
        AXF_BAT_DAT_Date__c,
        AXF_BAT_TXT_Description__c,
        AXF_BAT_NUM_Version__c
      FROM AXF_OBJ_BankAccountTransaction__c
      WHERE
        AXF_BAT_MDR_BankAccount__c = :bankAccountId
        AND AXF_BAT_PKL_Status__c = 'POSTED'
        AND AXF_BAT_TXT_CurrencyIsoCode__c = :iso
        AND AXF_BAT_PKL_Direction__c = :direction
        AND AXF_BAT_DAT_Date__c >= :fromDate
        AND AXF_BAT_DAT_Date__c <= :toDate
        AND AXF_BAT_NUM_Magnitude__c >= :minAmount
        AND AXF_BAT_NUM_Magnitude__c <= :maxAmount
      WITH USER_MODE
      ORDER BY AXF_BAT_DAT_Date__c DESC, Id ASC
      LIMIT :cap
    ];
    if (rows.size() > MAX_FACTS) {
      page.truncated = true;
      rows.remove(rows.size() - 1);
    }
    Set<Id> unverified = new Set<Id>();
    Map<Id, Decimal> nets = new ALT_CLS_SourceLinkService()
      .netOfSources(
        new Map<Id, AXF_OBJ_BankAccountTransaction__c>(rows).keySet(),
        unverified
      );
    for (AXF_OBJ_BankAccountTransaction__c row : rows) {
      Decimal residual =
        row.AXF_BAT_NUM_Magnitude__c -
        (nets.containsKey(row.Id) ? nets.get(row.Id) : 0);
      // Only a fact that is verified and not exhausted can be linked by one click.
      if (
        unverified.contains(row.Id) ||
        residual <= 0 ||
        !inWindow(
          base,
          onDate,
          row.AXF_BAT_NUM_Magnitude__c,
          row.AXF_BAT_DAT_Date__c
        )
      ) {
        continue;
      }
      SuggestionView s = new SuggestionView();
      s.sourceId = row.Id;
      s.sourceVersion = row.AXF_BAT_NUM_Version__c == null
        ? 0
        : row.AXF_BAT_NUM_Version__c;
      s.targetId = entry.Id;
      s.targetVersion = entry.AXF_FTX_NUM_Version__c == null
        ? 0
        : entry.AXF_FTX_NUM_Version__c;
      s.candidateId = row.Id;
      s.candidateDate = row.AXF_BAT_DAT_Date__c;
      s.candidateAmount = row.AXF_BAT_NUM_Magnitude__c;
      s.description = row.AXF_BAT_TXT_Description__c;
      s.currencyIso = row.AXF_BAT_TXT_CurrencyIsoCode__c;
      s.amountDelta = (row.AXF_BAT_NUM_Magnitude__c - base).abs();
      s.dayDelta = Math.abs(onDate.daysBetween(row.AXF_BAT_DAT_Date__c));
      s.allocationAmount = Math.min(residual, available);
      result.add(s);
    }
    return result;
  }

  // ----------------------------------------------------------------- confirm

  /**
   * @description One-click confirmation of a displayed suggestion: an explicit human command. The
   * pair is re-checked against the window, then linked through the AXF-134 contract with
   * min(source residual, target available), the displayed versions and a fresh operation key.
   */
  public ConfirmResult confirm(ConfirmInput input) {
    requireAccess();
    check(
      input != null &&
        input.sourceId != null &&
        input.targetId != null &&
        input.sourceVersion != null &&
        input.targetVersion != null &&
        String.isNotBlank(input.operationKey) &&
        input.operationKey.length() <= 80,
      'INVALID_INPUT'
    );
    AXF_OBJ_BankAccount__c account = readAccount(input.bankAccountId);
    ALT_CLS_SourceLinkService.SourceView source = readFact(
      account,
      input.sourceId
    );
    AXF_OBJ_FinancialTransaction__c target = readEntry(account, input.targetId);
    Date targetDate = entryDate(target);
    // Either side may have been the line the suggestion was built for.
    check(
      target.AXF_FTX_TXT_CurrencyIsoCode__c == source.currencyIso &&
        target.AXF_FTX_PKL_Direction__c == source.direction &&
        (inWindow(
          source.amount,
          source.factDate,
          target.AXF_FTX_NUM_Magnitude__c,
          targetDate
        ) ||
        inWindow(
          target.AXF_FTX_NUM_Magnitude__c,
          targetDate,
          source.amount,
          source.factDate
        )),
      'OUT_OF_WINDOW'
    );
    Decimal available = entryResidual(target);
    check(available != null, 'ALLOCATIONS_UNVERIFIED');
    check(available > 0, 'TARGET_REALIZED');
    if (!source.eligible) {
      throw new BankStatementException(source.reasons[0]);
    }
    ALT_CLS_SourceLinkService.ConfirmInput request = new ALT_CLS_SourceLinkService.ConfirmInput();
    request.sourceId = source.sourceId;
    request.sourceKind = ALT_CLS_SourceLinkService.KIND_BANK;
    request.sourceVersion = input.sourceVersion;
    request.targetId = target.Id;
    request.targetVersion = input.targetVersion;
    request.amount = Math.min(source.residual, available);
    request.recognitionDate = source.factDate;
    request.changesReviewed = false;
    request.economicRole = ALT_CLS_SourceLinkService.ROLE_APPLICATION;
    request.operationKey = input.operationKey;
    ALT_CLS_SourceLinkService.ConfirmResult linked;
    try {
      linked = new ALT_CLS_SourceLinkService().confirm(request);
    } catch (ALT_CLS_SourceLinkService.SourceLinkException failure) {
      throw new BankStatementException(failure.getMessage());
    }
    ConfirmResult result = new ConfirmResult();
    result.allocationId = linked.allocationId;
    result.replayed = linked.replayed;
    result.amount = linked.amount;
    result.currencyIso = linked.currencyIso;
    return result;
  }

  // ----------------------------------------------------------------- balance

  /**
   * @description Manual balance of an account without a Pluggy connection (wallet or manual
   * account), under the same gate as configuration and optimistic versioning.
   */
  public AccountView updateBalance(BalanceInput input) {
    check(canConfigure(), 'UNAVAILABLE');
    check(
      input != null &&
        input.balance != null &&
        input.balance.scale() <= 2 &&
        input.balance.abs() < 10000000000000000.0 &&
        input.expectedVersion != null,
      'INVALID_INPUT'
    );
    AXF_OBJ_BankAccount__c account = readAccount(input.bankAccountId);
    check(account.AXF_BA_LKP_Connection__c == null, 'NOT_ALLOWED');
    List<AXF_OBJ_BankAccount__c> locked = [
      SELECT Id, AXF_BA_NUM_Version__c
      FROM AXF_OBJ_BankAccount__c
      WHERE Id = :account.Id
      WITH USER_MODE
      LIMIT 1
      FOR UPDATE
    ];
    check(locked.size() == 1, 'NOT_ACCESSIBLE');
    Decimal current = locked[0].AXF_BA_NUM_Version__c == null
      ? 0
      : locked[0].AXF_BA_NUM_Version__c;
    check(current == input.expectedVersion, 'CONFLICT');
    AXF_OBJ_BankAccount__c change = new AXF_OBJ_BankAccount__c(
      Id = account.Id,
      AXF_BA_CUR_CurrentBalance__c = input.balance,
      AXF_BA_NUM_Version__c = current + 1
    );
    Database.update(change, AccessLevel.USER_MODE);
    return view(readAccount(account.Id));
  }

  /** @description Refreshes a connected account through the Pluggy discovery of its connection. */
  public RefreshResult refresh(Id bankAccountId) {
    check(canConfigure(), 'UNAVAILABLE');
    AXF_OBJ_BankAccount__c account = readAccount(bankAccountId);
    check(account.AXF_BA_LKP_Connection__c != null, 'NOT_ALLOWED');
    RefreshResult result = new RefreshResult();
    try {
      AXF_CLS_PluggyDiscoveryService.DiscoveryResult run = new AXF_CLS_PluggyDiscoveryService()
        .startOrResume(account.AXF_BA_LKP_Connection__c);
      result.state = run.state;
      result.complete = run.complete == true;
    } catch (AXF_CLS_PluggyDiscoveryException failure) {
      check(
        failure.getMessage() != null &&
        failure.getMessage().startsWith('CONFLICT'),
        'REFRESH_FAILED'
      );
      result.state = 'RUNNING';
    } catch (AXF_CLS_PluggyCollectionBlockedException blocked) {
      throw new BankStatementException('REFRESH_BLOCKED');
    } catch (AXF_CLS_PluggyIntegrationException failure) {
      throw new BankStatementException('REFRESH_FAILED');
    }
    result.account = view(readAccount(account.Id));
    return result;
  }
}
