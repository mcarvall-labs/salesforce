/**
 * @description Bank statement of a bank account: transactions of one month with the running
 * balance after each line. Pluggy sends no balance per line, so it is derived from the current
 * account balance by walking the transactions from newest to oldest. Transactions without a
 * date are left out; a missing amount counts as zero.
 */
public with sharing class ALT_CLS_BankStatement {
  public class Row {
    public Id id;
    public Date transactionDate;
    public String description;
    public Decimal amount;
    public Decimal runningBalance;
  }

  public class Statement {
    public Decimal balance;
    public String currencyCode;
    public String month;
    public Boolean truncated = false;
    public List<String> months = new List<String>();
    public List<Row> rows = new List<Row>();
  }

  @TestVisible
  private static Integer maxTransactions = 2000;

  public Statement build(Id bankAccountId, String month) {
    AXF_OBJ_BankAccount__c account = [
      SELECT AXF_BA_CUR_Balance__c, CurrencyIsoCode
      FROM AXF_OBJ_BankAccount__c
      WHERE Id = :bankAccountId
      WITH USER_MODE
    ];
    Statement statement = new Statement();
    statement.balance = account.AXF_BA_CUR_Balance__c;
    statement.currencyCode = account.CurrencyIsoCode;
    List<Row> all = new List<Row>();
    Decimal running = account.AXF_BA_CUR_Balance__c;
    Integer fetched = 0;
    for (AXF_OBJ_BankAccountTransaction__c bankTransaction : [
      SELECT
        AXF_BAT_DAT_Date__c,
        AXF_BAT_TXT_Description__c,
        AXF_BAT_CUR_Amount__c
      FROM AXF_OBJ_BankAccountTransaction__c
      WHERE
        AXF_BAT_MD_BankAccount__c = :bankAccountId
        AND AXF_BAT_DAT_Date__c != NULL
      WITH USER_MODE
      ORDER BY AXF_BAT_DAT_Date__c DESC, CreatedDate DESC, Id DESC
      LIMIT :(maxTransactions + 1)
    ]) {
      fetched++;
      if (fetched > maxTransactions) {
        statement.truncated = true;
        break;
      }
      Decimal amount = bankTransaction.AXF_BAT_CUR_Amount__c == null
        ? 0
        : bankTransaction.AXF_BAT_CUR_Amount__c;
      Row row = new Row();
      row.id = bankTransaction.Id;
      row.transactionDate = bankTransaction.AXF_BAT_DAT_Date__c;
      row.description = bankTransaction.AXF_BAT_TXT_Description__c;
      row.amount = amount;
      row.runningBalance = running;
      if (running != null) {
        running -= amount;
      }
      all.add(row);
      String rowMonth = monthOf(row.transactionDate);
      if (!statement.months.contains(rowMonth)) {
        statement.months.add(rowMonth);
      }
    }
    statement.month = String.isBlank(month) && !statement.months.isEmpty()
      ? statement.months[0]
      : month;
    for (Row row : all) {
      if (monthOf(row.transactionDate) == statement.month) {
        statement.rows.add(row);
      }
    }
    return statement;
  }

  private String monthOf(Date value) {
    return String.valueOf(value).substring(0, 7);
  }
}
