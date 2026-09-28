/**
 * @description Business service layer for Credit Card statement querying (invoices,
 * transactions, filters and totals). Consumed by AXF_CLS_CTRL_CreditCardStatement. Contains no
 * @AuraEnabled members and no LWC-specific concepts, per PROJECT_RULES.md §3.
 */
public inherited sharing class ALT_CLS_CreditCardStatement {
  public class StatementResult {
    public List<TransactionRow> transactions;
    public Decimal totalCredits; // Payments / refunds (negative values)
    public Decimal totalDebits; // Charges / purchases (positive values)
    public Decimal netBalance; // Sum of both

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
    public Boolean isCredit;

    public TransactionRow(AXF_OBJ_CreditCardTransaction__c txn) {
      this.id = txn.Id;
      this.transactionDate = txn.AXF_CCT_DAT_Date__c;
      this.description = txn.AXF_CCT_TXT_Description__c;
      this.categoryName = txn.AXF_CCT_LKP_Category__r != null
        ? txn.AXF_CCT_LKP_Category__r.Name
        : null;
      this.amount = txn.AXF_CCT_CUR_Amount__c == null
        ? 0
        : txn.AXF_CCT_CUR_Amount__c;
      // On a credit card, payments/refunds are negative (credit), while purchases are positive (debit)
      this.isCredit = this.amount < 0;
    }
  }

  /**
   * @description Returns all invoices for a given Credit Card, ordered by due date descending.
   */
  public List<AXF_OBJ_CreditCardInvoice__c> getInvoices(Id creditCardId) {
    if (creditCardId == null) {
      return new List<AXF_OBJ_CreditCardInvoice__c>();
    }
    return [
      SELECT
        Id,
        Name,
        AXF_CCI_TXT_Period__c,
        AXF_CCI_DAT_DueDate__c,
        AXF_CCI_DAT_ClosingDate__c,
        AXF_CCI_CUR_TotalAmount__c,
        AXF_CCI_PKL_Status__c
      FROM AXF_OBJ_CreditCardInvoice__c
      WHERE AXF_CCI_MD_CreditCard__c = :creditCardId
      WITH SECURITY_ENFORCED
      ORDER BY AXF_CCI_DAT_DueDate__c DESC, Id DESC
      LIMIT 100
    ];
  }

  /**
   * @description Returns transactions for the selected Credit Card Invoice, filtered by description and amount range.
   */
  public StatementResult getStatement(
    Id invoiceId,
    String description,
    Decimal valueMin,
    Decimal valueMax
  ) {
    StatementResult result = new StatementResult();

    if (invoiceId == null) {
      return result;
    }

    String descriptionLike = String.isNotBlank(description)
      ? '%' + description.trim() + '%'
      : null;

    String query =
      'SELECT Id, AXF_CCT_DAT_Date__c, AXF_CCT_TXT_Description__c, AXF_CCT_CUR_Amount__c, AXF_CCT_LKP_Category__r.Name ' +
      'FROM AXF_OBJ_CreditCardTransaction__c ' +
      'WHERE AXF_CCT_LKP_CreditCardInvoice__c = :invoiceId ';

    if (descriptionLike != null) {
      query += 'AND AXF_CCT_TXT_Description__c LIKE :descriptionLike ';
    }
    if (valueMin != null) {
      query += 'AND AXF_CCT_CUR_Amount__c >= :valueMin ';
    }
    if (valueMax != null) {
      query += 'AND AXF_CCT_CUR_Amount__c <= :valueMax ';
    }

    query += 'WITH SECURITY_ENFORCED ORDER BY AXF_CCT_DAT_Date__c ASC, Id ASC LIMIT 500';

    List<AXF_OBJ_CreditCardTransaction__c> transactions = Database.query(query);

    for (AXF_OBJ_CreditCardTransaction__c txn : transactions) {
      Decimal amount = txn.AXF_CCT_CUR_Amount__c == null
        ? 0
        : txn.AXF_CCT_CUR_Amount__c;

      if (amount < 0) {
        result.totalCredits += amount;
      } else {
        result.totalDebits += amount;
      }

      result.transactions.add(new TransactionRow(txn));
    }

    result.netBalance = result.totalCredits + result.totalDebits;

    return result;
  }
}
