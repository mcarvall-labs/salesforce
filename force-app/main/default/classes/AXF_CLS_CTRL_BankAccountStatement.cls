/**
 * @description Dedicated controller for the aXF_LWC_bankAccountStatement LWC. Thin entry point
 * that delegates to ALT_CLS_BankAccountStatement for the actual query/calculation logic, per
 * PROJECT_RULES.md §3. Renamed from AXF_CLS_BankAccountStatementController (US-094).
 */
public with sharing class AXF_CLS_CTRL_BankAccountStatement {
  public class StatementResult {
    @AuraEnabled
    public List<TransactionRow> transactions;
    @AuraEnabled
    public Decimal totalCredits;
    @AuraEnabled
    public Decimal totalDebits;
    @AuraEnabled
    public Decimal netBalance;

    public StatementResult() {
      this.transactions = new List<TransactionRow>();
      this.totalCredits = 0;
      this.totalDebits = 0;
      this.netBalance = 0;
    }
  }

  public class TransactionRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public Datetime transactionDate;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public String categoryName;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public Decimal runningBalance;
    @AuraEnabled
    public Boolean isCredit;

    public TransactionRow(ALT_CLS_BankAccountStatement.TransactionRow row) {
      this.id = row.id;
      this.transactionDate = row.transactionDate;
      this.description = row.description;
      this.categoryName = row.categoryName;
      this.amount = row.amount;
      this.runningBalance = row.runningBalance;
      this.isCredit = row.isCredit;
    }
  }

  @AuraEnabled(cacheable=true)
  public static StatementResult getStatement(
    Id bankAccountId,
    Date periodStart,
    Date periodEnd,
    String description,
    Decimal valueMin,
    Decimal valueMax
  ) {
    ALT_CLS_BankAccountStatement businessService = new ALT_CLS_BankAccountStatement();
    ALT_CLS_BankAccountStatement.StatementResult businessResult = businessService.getStatement(
      bankAccountId,
      periodStart,
      periodEnd,
      description,
      valueMin,
      valueMax
    );

    StatementResult result = new StatementResult();
    result.totalCredits = businessResult.totalCredits;
    result.totalDebits = businessResult.totalDebits;
    result.netBalance = businessResult.netBalance;
    for (
      ALT_CLS_BankAccountStatement.TransactionRow row : businessResult.transactions
    ) {
      result.transactions.add(new TransactionRow(row));
    }
    return result;
  }
}
