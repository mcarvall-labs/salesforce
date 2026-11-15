public with sharing class AXF_CLS_CTRL_BankStatement {
  public class StatementRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public Date transactionDate;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public Decimal runningBalance;
  }

  public class StatementView {
    @AuraEnabled
    public Decimal balance;
    @AuraEnabled
    public String currencyCode;
    @AuraEnabled
    public String month;
    @AuraEnabled
    public Boolean truncated;
    @AuraEnabled
    public List<String> months;
    @AuraEnabled
    public List<StatementRow> rows;
  }

  @AuraEnabled
  public static StatementView getStatement(Id bankAccountId, String month) {
    if (bankAccountId == null) {
      throw new AuraHandledException('Informe a conta bancária.');
    }
    ALT_CLS_BankStatement.Statement statement;
    try {
      statement = new ALT_CLS_BankStatement().build(bankAccountId, month);
    } catch (QueryException e) {
      throw new AuraHandledException('Não foi possível carregar o extrato.');
    }
    StatementView view = new StatementView();
    view.balance = statement.balance;
    view.currencyCode = statement.currencyCode;
    view.month = statement.month;
    view.truncated = statement.truncated;
    view.months = statement.months;
    view.rows = new List<StatementRow>();
    for (ALT_CLS_BankStatement.Row row : statement.rows) {
      StatementRow item = new StatementRow();
      item.id = row.id;
      item.transactionDate = row.transactionDate;
      item.description = row.description;
      item.amount = row.amount;
      item.runningBalance = row.runningBalance;
      view.rows.add(item);
    }
    return view;
  }
}
