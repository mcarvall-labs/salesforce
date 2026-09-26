/**
 * @description Axon Finance home dashboard over the production cash-flow model. One holder filter
 * (all holders, or one AXF_*_LKP_Account__c holder) drives every panel, with the production
 * rules of ALT_CLS_InvestmentCapacity and ALT_CLS_CashFlowAlerts:
 * - month = AXF_OBJ_CashFlow__c due this month; realized = PAGA / PAGA_EM_ATRASO (expense) or
 *   RECEBIDA / RECEBIDA_EM_ATRASO (revenue);
 * - overdue = PENDENTE / VENCIDA due before this month;
 * - projected balance = bank account balances + the month's planned balance.
 * Every read runs in USER_MODE.
 */
public with sharing class ALT_CLS_HomeDashboard {
  public static final Integer MAX_ROWS = 500;
  public static final String STATUS_SETTLED = 'SETTLED';
  public static final String STATUS_OPEN = 'OPEN';
  private static final String RT_EXPENSE = 'AXF_CF_RT_Expense';
  private static final String RT_REVENUE = 'AXF_CF_RT_Revenue';
  private static final Set<String> SETTLED = new Set<String>{
    'PAGA',
    'PAGA_EM_ATRASO',
    'RECEBIDA',
    'RECEBIDA_EM_ATRASO'
  };
  private static final Set<String> PENDING = new Set<String>{
    'PENDENTE',
    'VENCIDA'
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
    public String currencyIso = 'BRL';
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

  /** Dashboard of one holder, or of every holder when holderId is null. */
  public DashboardView dashboard(Id holderId) {
    DashboardView result = new DashboardView();
    Map<Id, String> holders = holders();
    for (Id id : holders.keySet()) {
      HolderOption option = new HolderOption();
      option.holderId = id;
      option.label = holders.get(id);
      result.holders.add(option);
    }
    if (holderId != null && !holders.containsKey(holderId)) {
      throw new DashboardException('INVALID_INPUT');
    }
    result.holderId = holderId;
    Date today = todayOverride == null ? Date.today() : todayOverride;
    result.monthStart = today.toStartOfMonth();
    Date monthEnd = result.monthStart.addMonths(1).addDays(-1);

    for (
      AXF_OBJ_CashFlow__c row : entries(
        holderId,
        result.monthStart,
        monthEnd,
        null,
        result
      )
    ) {
      EntryView v = view(row);
      if (row.RecordType.DeveloperName == RT_REVENUE) {
        result.monthRevenues.add(v);
        result.plannedRevenue += v.amount;
        result.realizedRevenue += v.realized;
      } else if (row.RecordType.DeveloperName == RT_EXPENSE) {
        result.monthExpenses.add(v);
        result.plannedExpense += v.amount;
        result.realizedExpense += v.realized;
      }
    }
    for (
      AXF_OBJ_CashFlow__c row : entries(
        holderId,
        null,
        result.monthStart.addDays(-1),
        PENDING,
        result
      )
    ) {
      EntryView v = view(row);
      if (row.RecordType.DeveloperName == RT_REVENUE) {
        result.overdueRevenues.add(v);
        result.overdueRevenueTotal += v.amount;
      } else if (row.RecordType.DeveloperName == RT_EXPENSE) {
        result.overdueExpenses.add(v);
        result.overdueExpenseTotal += v.amount;
      }
    }
    for (AXF_OBJ_BankAccount__c row : accounts(holderId)) {
      Decimal balance = row.AXF_BA_CUR_Balance__c == null
        ? 0
        : row.AXF_BA_CUR_Balance__c;
      result.accountsBalance += balance;
      if (balance != 0) {
        AccountView a = new AccountView();
        a.bankAccountId = row.Id;
        a.name = row.Name;
        a.balance = balance;
        a.currencyIso = String.isBlank(row.AXF_BA_PKL_Currency__c)
          ? 'BRL'
          : row.AXF_BA_PKL_Currency__c;
        result.accounts.add(a);
      }
    }
    result.plannedBalance = result.plannedRevenue - result.plannedExpense;
    result.realizedBalance = result.realizedRevenue - result.realizedExpense;
    result.monthSurplus = result.plannedBalance;
    result.projectedBalance = result.accountsBalance + result.plannedBalance;
    return result;
  }

  /** Holders that own a bank account, labelled "First Last" as the production KPI does. */
  private static Map<Id, String> holders() {
    Map<Id, String> result = new Map<Id, String>();
    for (AXF_OBJ_BankAccount__c row : [
      SELECT AXF_BA_LKP_Account__c, AXF_BA_LKP_Account__r.Name
      FROM AXF_OBJ_BankAccount__c
      WHERE AXF_BA_LKP_Account__c != NULL
      WITH USER_MODE
      ORDER BY AXF_BA_LKP_Account__r.Name
      LIMIT :MAX_ROWS
    ]) {
      if (!result.containsKey(row.AXF_BA_LKP_Account__c)) {
        result.put(
          row.AXF_BA_LKP_Account__c,
          shortName(row.AXF_BA_LKP_Account__r.Name)
        );
      }
    }
    return result;
  }

  @TestVisible
  private static String shortName(String fullName) {
    if (String.isBlank(fullName)) {
      return fullName;
    }
    List<String> parts = fullName.trim().split('\\s+');
    return parts.size() > 1
      ? parts[0] + ' ' + parts[parts.size() - 1]
      : fullName.trim();
  }

  private static List<AXF_OBJ_CashFlow__c> entries(
    Id holderId,
    Date fromDate,
    Date toDate,
    Set<String> statuses,
    DashboardView result
  ) {
    String soql =
      'SELECT Id, Name, RecordType.DeveloperName, AXF_CF_CUR_Value__c, AXF_CF_PKL_Status__c,' +
      ' AXF_CF_DAT_DueDate__c, AXF_CF_LKP_Category__r.Name, AXF_CF_LKP_Account__r.Name' +
      ' FROM AXF_OBJ_CashFlow__c WHERE AXF_CF_DAT_DueDate__c <= :toDate' +
      (fromDate == null ? '' : ' AND AXF_CF_DAT_DueDate__c >= :fromDate') +
      (statuses == null ? '' : ' AND AXF_CF_PKL_Status__c IN :statuses') +
      (holderId == null ? '' : ' AND AXF_CF_LKP_Account__c = :holderId') +
      ' ORDER BY AXF_CF_DAT_DueDate__c ASC, Id ASC LIMIT :cap';
    List<AXF_OBJ_CashFlow__c> rows = (List<AXF_OBJ_CashFlow__c>) Database.queryWithBinds(
      soql,
      new Map<String, Object>{
        'fromDate' => fromDate,
        'toDate' => toDate,
        'statuses' => statuses,
        'holderId' => holderId,
        'cap' => MAX_ROWS + 1
      },
      AccessLevel.USER_MODE
    );
    if (rows.size() > MAX_ROWS) {
      result.truncated = true;
      rows.remove(rows.size() - 1);
    }
    return rows;
  }

  private static List<AXF_OBJ_BankAccount__c> accounts(Id holderId) {
    String soql =
      'SELECT Id, Name, AXF_BA_CUR_Balance__c, AXF_BA_PKL_Currency__c FROM AXF_OBJ_BankAccount__c' +
      (holderId == null ? '' : ' WHERE AXF_BA_LKP_Account__c = :holderId') +
      ' ORDER BY Name ASC LIMIT :cap';
    return (List<AXF_OBJ_BankAccount__c>) Database.queryWithBinds(
      soql,
      new Map<String, Object>{ 'holderId' => holderId, 'cap' => MAX_ROWS },
      AccessLevel.USER_MODE
    );
  }

  private static EntryView view(AXF_OBJ_CashFlow__c row) {
    EntryView v = new EntryView();
    v.recordId = row.Id;
    v.description = row.Name;
    v.category = row.AXF_CF_LKP_Category__r?.Name;
    v.holderLabel = row.AXF_CF_LKP_Account__r?.Name;
    v.entryDate = row.AXF_CF_DAT_DueDate__c;
    v.amount = row.AXF_CF_CUR_Value__c == null ? 0 : row.AXF_CF_CUR_Value__c;
    Boolean settled = SETTLED.contains(row.AXF_CF_PKL_Status__c);
    v.realized = settled ? v.amount : 0;
    v.residual = v.amount - v.realized;
    v.status = settled ? STATUS_SETTLED : STATUS_OPEN;
    return v;
  }
}
