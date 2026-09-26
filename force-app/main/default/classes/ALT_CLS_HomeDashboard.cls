/**
 * @description Home dashboard of the Axon Finance app (production parity): month balance
 * planned vs realized, overdue expenses/income from previous months, the month's expenses and
 * income, and the projected balance (available account balances + the month's pending net).
 * One holder filter applies to every panel; holders come only from the authorized context and
 * every read runs in USER_MODE. "Realized" is the entry's net reconciliation allocation
 * (ALT_CLS_ManualEntryService.nets); an ACTUAL_ONLY entry is realized by definition.
 */
public with sharing class ALT_CLS_HomeDashboard {
  public static final Integer MAX_ENTRIES = 500;
  public static final Integer MAX_ACCOUNTS = 200;
  public static final Integer OVERDUE_MONTHS = 12;
  public static final String STATUS_SETTLED = 'SETTLED';
  public static final String STATUS_PARTIAL = 'PARTIAL';
  public static final String STATUS_OPEN = 'OPEN';
  public static final String STATUS_UNVERIFIED = 'UNVERIFIED';
  private static final String PLAN_ACTUAL_ONLY = 'ACTUAL_ONLY';
  private static final Set<String> PLAN_KINDS = new Set<String>{
    'PLANNED',
    PLAN_ACTUAL_ONLY
  };

  @TestVisible
  private static Date todayOverride;

  public class DashboardException extends Exception {
  }

  public class HolderOption {
    @AuraEnabled
    public Id holderId;
    @AuraEnabled
    public String label;
  }

  public class EntryView {
    @AuraEnabled
    public Id recordId;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public String category;
    @AuraEnabled
    public String holderLabel;
    @AuraEnabled
    public Date entryDate;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public Decimal realized;
    @AuraEnabled
    public Decimal residual;
    @AuraEnabled
    public String currencyIso;
    @AuraEnabled
    public String status;
  }

  public class AccountView {
    @AuraEnabled
    public Id bankAccountId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Decimal balance;
    @AuraEnabled
    public String currencyIso;
  }

  public class DashboardView {
    @AuraEnabled
    public List<HolderOption> holders = new List<HolderOption>();
    @AuraEnabled
    public Id holderId;
    @AuraEnabled
    public Date monthStart;
    @AuraEnabled
    public String currencyIso = 'BRL';
    @AuraEnabled
    public Boolean mixedCurrency = false;
    @AuraEnabled
    public Boolean truncated = false;
    @AuraEnabled
    public Decimal plannedRevenue = 0;
    @AuraEnabled
    public Decimal realizedRevenue = 0;
    @AuraEnabled
    public Decimal plannedExpense = 0;
    @AuraEnabled
    public Decimal realizedExpense = 0;
    @AuraEnabled
    public Decimal plannedBalance = 0;
    @AuraEnabled
    public Decimal realizedBalance = 0;
    @AuraEnabled
    public List<EntryView> overdueExpenses = new List<EntryView>();
    @AuraEnabled
    public Decimal overdueExpenseTotal = 0;
    @AuraEnabled
    public List<EntryView> overdueRevenues = new List<EntryView>();
    @AuraEnabled
    public Decimal overdueRevenueTotal = 0;
    @AuraEnabled
    public List<EntryView> monthExpenses = new List<EntryView>();
    @AuraEnabled
    public List<EntryView> monthRevenues = new List<EntryView>();
    @AuraEnabled
    public List<AccountView> accounts = new List<AccountView>();
    @AuraEnabled
    public Decimal accountsBalance = 0;
    @AuraEnabled
    public Decimal monthSurplus = 0;
    @AuraEnabled
    public Decimal projectedBalance = 0;
  }

  /** Dashboard of one authorized holder, or of every authorized holder when holderId is null. */
  public DashboardView dashboard(Id holderId) {
    DashboardView result = new DashboardView();
    Map<Id, String> authorized = new Map<Id, String>();
    for (
      AXF_CLS_AuthorizedContextService.ContextView context : AXF_CLS_AuthorizedContextService.listAuthorizedContexts()
    ) {
      authorized.put(context.accountId, context.label);
      HolderOption option = new HolderOption();
      option.holderId = context.accountId;
      option.label = context.label;
      result.holders.add(option);
    }
    if (holderId != null && !authorized.containsKey(holderId)) {
      throw new DashboardException('INVALID_INPUT');
    }
    result.holderId = holderId;
    Date today = todayOverride == null ? Date.today() : todayOverride;
    result.monthStart = today.toStartOfMonth();
    Set<Id> holders = holderId == null
      ? authorized.keySet()
      : new Set<Id>{ holderId };
    if (holders.isEmpty()) {
      return result;
    }
    List<AXF_OBJ_FinancialTransaction__c> month = entries(
      holders,
      PLAN_KINDS,
      result.monthStart,
      result.monthStart.addMonths(1).addDays(-1),
      result
    );
    List<AXF_OBJ_FinancialTransaction__c> overdue = entries(
      holders,
      new Set<String>{ 'PLANNED' },
      result.monthStart.addMonths(-OVERDUE_MONTHS),
      result.monthStart.addDays(-1),
      result
    );
    Set<Id> ids = new Set<Id>(
      new Map<Id, AXF_OBJ_FinancialTransaction__c>(month).keySet()
    );
    ids.addAll(new Map<Id, AXF_OBJ_FinancialTransaction__c>(overdue).keySet());
    Set<Id> unverified = new Set<Id>();
    Map<Id, Decimal> nets = ALT_CLS_ManualEntryService.nets(ids, unverified);
    Set<String> currencies = new Set<String>();
    for (AXF_OBJ_FinancialTransaction__c row : month) {
      EntryView v = view(row, authorized, nets, unverified);
      currencies.add(v.currencyIso);
      if (row.AXF_FTX_PKL_Direction__c == 'CREDIT') {
        result.monthRevenues.add(v);
        result.plannedRevenue += v.amount;
        result.realizedRevenue += v.realized;
        result.monthSurplus += v.residual;
      } else {
        result.monthExpenses.add(v);
        result.plannedExpense += v.amount;
        result.realizedExpense += v.realized;
        result.monthSurplus -= v.residual;
      }
    }
    for (AXF_OBJ_FinancialTransaction__c row : overdue) {
      EntryView v = view(row, authorized, nets, unverified);
      if (v.status == STATUS_SETTLED) {
        continue;
      }
      currencies.add(v.currencyIso);
      if (row.AXF_FTX_PKL_Direction__c == 'CREDIT') {
        result.overdueRevenues.add(v);
        result.overdueRevenueTotal += v.residual;
      } else {
        result.overdueExpenses.add(v);
        result.overdueExpenseTotal += v.residual;
      }
    }
    for (AXF_OBJ_BankAccount__c row : [
      SELECT
        Id,
        Name,
        AXF_BA_CUR_CurrentBalance__c,
        AXF_BA_TXT_CurrencyIsoCode__c
      FROM AXF_OBJ_BankAccount__c
      WHERE
        AXF_BA_LKP_Account__c IN :holders
        AND AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE'
      WITH USER_MODE
      ORDER BY Name
      LIMIT :MAX_ACCOUNTS
    ]) {
      AccountView a = new AccountView();
      a.bankAccountId = row.Id;
      a.name = row.Name;
      a.balance = row.AXF_BA_CUR_CurrentBalance__c == null
        ? 0
        : row.AXF_BA_CUR_CurrentBalance__c;
      a.currencyIso = row.AXF_BA_TXT_CurrencyIsoCode__c;
      currencies.add(a.currencyIso);
      result.accounts.add(a);
      result.accountsBalance += a.balance;
    }
    result.plannedBalance = result.plannedRevenue - result.plannedExpense;
    result.realizedBalance = result.realizedRevenue - result.realizedExpense;
    result.projectedBalance = result.accountsBalance + result.monthSurplus;
    currencies.remove(null);
    if (currencies.size() == 1) {
      result.currencyIso = new List<String>(currencies)[0];
    }
    result.mixedCurrency = currencies.size() > 1;
    return result;
  }

  private static List<AXF_OBJ_FinancialTransaction__c> entries(
    Set<Id> holders,
    Set<String> planKinds,
    Date fromDate,
    Date toDate,
    DashboardView result
  ) {
    Integer cap = MAX_ENTRIES + 1;
    List<AXF_OBJ_FinancialTransaction__c> rows = [
      SELECT
        Id,
        AXF_FTX_LKP_Account__c,
        AXF_FTX_NUM_Magnitude__c,
        AXF_FTX_TXT_CurrencyIsoCode__c,
        AXF_FTX_PKL_Direction__c,
        AXF_FTX_PKL_PlanKind__c,
        AXF_FTX_DAT_DueDate__c,
        AXF_FTX_DAT_PurchaseDate__c,
        AXF_FTX_TXT_Description__c,
        AXF_FTX_TXT_UserCategory__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE
        AXF_FTX_LKP_Account__c IN :holders
        AND AXF_FTX_PKL_PlanKind__c IN :planKinds
        AND (AXF_FTX_PKL_ScheduleState__c = NULL
        OR AXF_FTX_PKL_ScheduleState__c != 'CANCELLED')
        AND ((AXF_FTX_DAT_DueDate__c >= :fromDate
        AND AXF_FTX_DAT_DueDate__c <= :toDate)
        OR (AXF_FTX_DAT_DueDate__c = NULL
        AND AXF_FTX_DAT_PurchaseDate__c >= :fromDate
        AND AXF_FTX_DAT_PurchaseDate__c <= :toDate))
      WITH USER_MODE
      ORDER BY
        AXF_FTX_DAT_DueDate__c ASC NULLS LAST,
        AXF_FTX_DAT_PurchaseDate__c ASC,
        Id ASC
      LIMIT :cap
    ];
    if (rows.size() > MAX_ENTRIES) {
      result.truncated = true;
      rows.remove(rows.size() - 1);
    }
    return rows;
  }

  private static EntryView view(
    AXF_OBJ_FinancialTransaction__c row,
    Map<Id, String> holders,
    Map<Id, Decimal> nets,
    Set<Id> unverified
  ) {
    EntryView v = new EntryView();
    v.recordId = row.Id;
    v.description = row.AXF_FTX_TXT_Description__c;
    v.category = row.AXF_FTX_TXT_UserCategory__c;
    v.holderLabel = holders.get(row.AXF_FTX_LKP_Account__c);
    v.entryDate = row.AXF_FTX_DAT_DueDate__c != null
      ? row.AXF_FTX_DAT_DueDate__c
      : row.AXF_FTX_DAT_PurchaseDate__c;
    v.amount = row.AXF_FTX_NUM_Magnitude__c == null
      ? 0
      : row.AXF_FTX_NUM_Magnitude__c;
    v.currencyIso = row.AXF_FTX_TXT_CurrencyIsoCode__c;
    Boolean actual = row.AXF_FTX_PKL_PlanKind__c == PLAN_ACTUAL_ONLY;
    Boolean unknown = !actual && unverified.contains(row.Id);
    Decimal allocated = actual
      ? v.amount
      : unknown || !nets.containsKey(row.Id) ? 0 : nets.get(row.Id);
    v.realized = Math.min(Math.max(allocated, 0), v.amount);
    v.residual = v.amount - v.realized;
    if (unknown) {
      v.status = STATUS_UNVERIFIED;
    } else if (v.residual <= 0) {
      v.status = STATUS_SETTLED;
    } else if (v.realized > 0) {
      v.status = STATUS_PARTIAL;
    } else {
      v.status = STATUS_OPEN;
    }
    return v;
  }
}
