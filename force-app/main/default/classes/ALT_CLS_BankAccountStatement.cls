/**
 * @description Business service layer for Bank Account statement querying (transactions,
 * filters, running balance and totals). Consumed by AXF_CLS_CTRL_BankAccountStatement. Contains
 * no @AuraEnabled members and no LWC-specific concepts, per PROJECT_RULES.md §3.
 */
public inherited sharing class ALT_CLS_BankAccountStatement {
  public class StatementResult {
    public List<TransactionRow> transactions;
    public Decimal totalCredits;
    public Decimal totalDebits;
    public Decimal netBalance;

    public StatementResult() {
      this.transactions = new List<TransactionRow>();
      this.totalCredits = 0;
      this.totalDebits = 0;
      this.netBalance = 0;
    }
  }

  public class TransactionRow {
    public Id id;
    public Datetime transactionDate;
    public String description;
    public String categoryName;
    public Decimal amount;
    public Decimal runningBalance;
    public Boolean isCredit;

    public TransactionRow(
      AXF_OBJ_BankAccountTransaction__c txn,
      Decimal runningBalance
    ) {
      this.id = txn.Id;
      this.transactionDate = txn.AXF_BAT_DAT_Date__c;
      this.description = txn.AXF_BAT_TXT_Description__c;
      this.categoryName = txn.AXF_BAT_LKP_Category__r != null
        ? txn.AXF_BAT_LKP_Category__r.Name
        : null;
      this.amount = txn.AXF_BAT_CUR_Amount__c == null
        ? 0
        : txn.AXF_BAT_CUR_Amount__c;
      this.runningBalance = runningBalance;
      this.isCredit = this.amount >= 0;
    }
  }

  /**
   * @description Retorna as transações da Conta Bancária informada no formato de extrato, já
   * filtradas por período/descrição/valor e com o saldo acumulado calculado sobre o conjunto de
   * resultados filtrado (não sobre o saldo total da conta). A consulta é montada dinamicamente
   * para que cada filtro seja opcional, sempre com os valores informados via bind variable
   * (nunca concatenados na string da query).
   */
  public StatementResult getStatement(
    Id bankAccountId,
    Date periodStart,
    Date periodEnd,
    String description,
    Decimal valueMin,
    Decimal valueMax
  ) {
    StatementResult result = new StatementResult();

    if (bankAccountId == null) {
      return result;
    }

    Datetime periodStartDt = periodStart != null
      ? Datetime.newInstance(periodStart, Time.newInstance(0, 0, 0, 0))
      : null;
    Datetime periodEndDt = periodEnd != null
      ? Datetime.newInstance(periodEnd, Time.newInstance(23, 59, 59, 999))
      : null;
    String descriptionLike = String.isNotBlank(description)
      ? '%' + description.trim() + '%'
      : null;

    String query =
      'SELECT Id, AXF_BAT_DAT_Date__c, AXF_BAT_TXT_Description__c, AXF_BAT_CUR_Amount__c, AXF_BAT_LKP_Category__r.Name ' +
      'FROM AXF_OBJ_BankAccountTransaction__c ' +
      'WHERE AXF_BAT_LKP_BankAccount__c = :bankAccountId ';

    if (periodStartDt != null) {
      query += 'AND AXF_BAT_DAT_Date__c >= :periodStartDt ';
    }
    if (periodEndDt != null) {
      query += 'AND AXF_BAT_DAT_Date__c <= :periodEndDt ';
    }
    if (descriptionLike != null) {
      query += 'AND AXF_BAT_TXT_Description__c LIKE :descriptionLike ';
    }
    if (valueMin != null) {
      query += 'AND AXF_BAT_CUR_Amount__c >= :valueMin ';
    }
    if (valueMax != null) {
      query += 'AND AXF_BAT_CUR_Amount__c <= :valueMax ';
    }

    query += 'WITH SECURITY_ENFORCED ORDER BY AXF_BAT_DAT_Date__c ASC, Id ASC LIMIT 500';

    List<AXF_OBJ_BankAccountTransaction__c> transactions = Database.query(
      query
    );

    Decimal runningBalance = 0;
    for (AXF_OBJ_BankAccountTransaction__c txn : transactions) {
      Decimal amount = txn.AXF_BAT_CUR_Amount__c == null
        ? 0
        : txn.AXF_BAT_CUR_Amount__c;
      runningBalance += amount;

      if (amount >= 0) {
        result.totalCredits += amount;
      } else {
        result.totalDebits += amount;
      }

      result.transactions.add(new TransactionRow(txn, runningBalance));
    }

    result.netBalance = result.totalCredits + result.totalDebits;

    return result;
  }
}
