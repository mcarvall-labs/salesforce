/**
 * @description Business service layer for Investment Capacity metrics and monthly balance
 * calculations, plus triggering a full Pluggy connections sync. Consumed by
 * AXF_CLS_CTRL_InvestmentCapacityKPI and AXF_CLS_CTRL_MonthlyBalanceKPI. Contains no
 * @AuraEnabled members and no LWC-specific concepts, per PROJECT_RULES.md §3.
 */
public inherited sharing class ALT_CLS_InvestmentCapacity {
  public class MonthlyBalanceResult {
    public Decimal plannedRevenues;
    public Decimal realizedRevenues;
    public Decimal plannedExpenses;
    public Decimal realizedExpenses;
    public Decimal plannedBalance;
    public Decimal realizedBalance;
  }

  public class BankAccountBalanceResult {
    public String id;
    public String accName;
    public Decimal balance;
  }

  public class AccountHolderResult {
    public String id;
    public String holderName;
  }

  public class InvestmentCapacityResult {
    public Decimal bankAccountsBalance;
    public Decimal monthProjectedSurplus;
    public Decimal totalInvestmentCapacity;
    public List<BankAccountBalanceResult> positiveBankAccounts = new List<BankAccountBalanceResult>();
    public List<AccountHolderResult> accountHolders = new List<AccountHolderResult>();
  }

  public MonthlyBalanceResult getMonthlyBalanceMetrics(
    String selectedAccountId
  ) {
    return calculateMonthlyBalance(selectedAccountId);
  }

  private MonthlyBalanceResult calculateMonthlyBalance(
    String selectedAccountId
  ) {
    Date startOfMonth = Date.today().toStartOfMonth();
    Date endOfMonth = startOfMonth.addMonths(1).addDays(-1);

    List<AXF_OBJ_CashFlow__c> monthEntries;
    if (String.isNotBlank(selectedAccountId) && selectedAccountId != 'ALL') {
      monthEntries = [
        SELECT
          Id,
          RecordType.DeveloperName,
          AXF_CF_CUR_Value__c,
          AXF_CF_PKL_Status__c
        FROM AXF_OBJ_CashFlow__c
        WHERE
          AXF_CF_DAT_DueDate__c >= :startOfMonth
          AND AXF_CF_DAT_DueDate__c <= :endOfMonth
          AND AXF_CF_LKP_Account__c = :selectedAccountId
        WITH USER_MODE
      ];
    } else {
      monthEntries = [
        SELECT
          Id,
          RecordType.DeveloperName,
          AXF_CF_CUR_Value__c,
          AXF_CF_PKL_Status__c
        FROM AXF_OBJ_CashFlow__c
        WHERE
          AXF_CF_DAT_DueDate__c >= :startOfMonth
          AND AXF_CF_DAT_DueDate__c <= :endOfMonth
        WITH USER_MODE
      ];
    }

    MonthlyBalanceResult result = new MonthlyBalanceResult();
    result.plannedRevenues = 0;
    result.realizedRevenues = 0;
    result.plannedExpenses = 0;
    result.realizedExpenses = 0;

    for (AXF_OBJ_CashFlow__c cf : monthEntries) {
      Decimal val = cf.AXF_CF_CUR_Value__c != null ? cf.AXF_CF_CUR_Value__c : 0;
      if (cf.RecordType.DeveloperName == 'AXF_CF_RT_Revenue') {
        result.plannedRevenues += val;
        if (
          cf.AXF_CF_PKL_Status__c == 'RECEBIDA' ||
          cf.AXF_CF_PKL_Status__c == 'RECEBIDA_EM_ATRASO'
        ) {
          result.realizedRevenues += val;
        }
      } else if (cf.RecordType.DeveloperName == 'AXF_CF_RT_Expense') {
        result.plannedExpenses += val;
        if (
          cf.AXF_CF_PKL_Status__c == 'PAGA' ||
          cf.AXF_CF_PKL_Status__c == 'PAGA_EM_ATRASO'
        ) {
          result.realizedExpenses += val;
        }
      }
    }

    result.plannedBalance = result.plannedRevenues - result.plannedExpenses;
    result.realizedBalance = result.realizedRevenues - result.realizedExpenses;

    return result;
  }

  public InvestmentCapacityResult getInvestmentCapacityMetrics(
    String selectedAccountId
  ) {
    Decimal bankSum = 0;

    List<AXF_OBJ_BankAccount__c> accList;
    if (String.isNotBlank(selectedAccountId) && selectedAccountId != 'ALL') {
      accList = [
        SELECT
          Id,
          Name,
          AXF_BA_CUR_Balance__c,
          AXF_BA_LKP_Account__c,
          AXF_BA_LKP_Account__r.Name
        FROM AXF_OBJ_BankAccount__c
        WHERE
          AXF_BA_CUR_Balance__c != 0
          AND AXF_BA_CUR_Balance__c != NULL
          AND AXF_BA_LKP_Account__c = :selectedAccountId
        WITH USER_MODE
        ORDER BY Name ASC
      ];

      AggregateResult[] arList = [
        SELECT SUM(AXF_BA_CUR_Balance__c) totalBalance
        FROM AXF_OBJ_BankAccount__c
        WHERE AXF_BA_LKP_Account__c = :selectedAccountId
        WITH USER_MODE
      ];
      if (!arList.isEmpty() && arList[0].get('totalBalance') != null) {
        bankSum = (Decimal) arList[0].get('totalBalance');
      }
    } else {
      accList = [
        SELECT
          Id,
          Name,
          AXF_BA_CUR_Balance__c,
          AXF_BA_LKP_Account__c,
          AXF_BA_LKP_Account__r.Name
        FROM AXF_OBJ_BankAccount__c
        WHERE AXF_BA_CUR_Balance__c != 0 AND AXF_BA_CUR_Balance__c != NULL
        WITH USER_MODE
        ORDER BY Name ASC
      ];

      AggregateResult[] arList = [
        SELECT SUM(AXF_BA_CUR_Balance__c) totalBalance
        FROM AXF_OBJ_BankAccount__c
        WITH USER_MODE
      ];
      if (!arList.isEmpty() && arList[0].get('totalBalance') != null) {
        bankSum = (Decimal) arList[0].get('totalBalance');
      }
    }

    List<BankAccountBalanceResult> posAccounts = new List<BankAccountBalanceResult>();
    for (AXF_OBJ_BankAccount__c acc : accList) {
      BankAccountBalanceResult bResult = new BankAccountBalanceResult();
      bResult.id = acc.Id;
      bResult.accName = acc.Name;
      bResult.balance = acc.AXF_BA_CUR_Balance__c;
      posAccounts.add(bResult);
    }

    List<AccountHolderResult> holders = new List<AccountHolderResult>();
    List<AXF_OBJ_BankAccount__c> allAccountsWithHolders = [
      SELECT AXF_BA_LKP_Account__c, AXF_BA_LKP_Account__r.Name
      FROM AXF_OBJ_BankAccount__c
      WHERE AXF_BA_LKP_Account__c != NULL
      WITH USER_MODE
    ];

    Map<Id, String> holderMap = new Map<Id, String>();
    for (AXF_OBJ_BankAccount__c ba : allAccountsWithHolders) {
      if (!holderMap.containsKey(ba.AXF_BA_LKP_Account__c)) {
        String fullName = ba.AXF_BA_LKP_Account__r.Name;
        String displayName = fullName;
        if (String.isNotBlank(fullName)) {
          List<String> parts = fullName.trim().split('\\s+');
          if (parts.size() > 1) {
            displayName = parts[0] + ' ' + parts[parts.size() - 1];
          }
        }
        holderMap.put(ba.AXF_BA_LKP_Account__c, displayName);
      }
    }

    for (Id hId : holderMap.keySet()) {
      AccountHolderResult hResult = new AccountHolderResult();
      hResult.id = hId;
      hResult.holderName = holderMap.get(hId);
      holders.add(hResult);
    }

    MonthlyBalanceResult monthResult = calculateMonthlyBalance(
      selectedAccountId
    );

    InvestmentCapacityResult result = new InvestmentCapacityResult();
    result.bankAccountsBalance = bankSum;
    result.monthProjectedSurplus = monthResult.plannedBalance;
    result.totalInvestmentCapacity = bankSum + monthResult.plannedBalance;
    result.positiveBankAccounts = posAccounts;
    result.accountHolders = holders;

    return result;
  }

  public String triggerSyncAllConnections() {
    System.enqueueJob(new AXF_CLS_PluggyItemSyncQueueable());
    return 'Sincronização iniciada com sucesso.';
  }
}
