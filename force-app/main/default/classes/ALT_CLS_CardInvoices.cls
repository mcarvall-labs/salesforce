/**
 * @description Invoices of a credit card (newest due date first) and the transactions of one
 * invoice, read with the caller's CRUD/FLS and sharing.
 */
public with sharing class ALT_CLS_CardInvoices {
  public class Invoice {
    public Id id;
    public String period;
    public Date dueDate;
    public Decimal totalAmount;
    public String status;
    public String currencyCode;
  }

  public class Line {
    public Id id;
    public Date transactionDate;
    public String description;
    public Decimal amount;
    public Decimal amountBRL;
    public String originalCurrency;
    public String installment;
  }

  private static final Integer MAX_ROWS = 500;

  public List<Invoice> invoices(Id creditCardId) {
    List<Invoice> items = new List<Invoice>();
    for (AXF_OBJ_CreditCardInvoice__c invoice : [
      SELECT
        AXF_CCI_TXT_Period__c,
        AXF_CCI_DAT_DueDate__c,
        AXF_CCI_CUR_TotalAmount__c,
        AXF_CCI_PKL_Status__c,
        CurrencyIsoCode
      FROM AXF_OBJ_CreditCardInvoice__c
      WHERE AXF_CCI_MD_CreditCard__c = :creditCardId
      WITH USER_MODE
      ORDER BY
        AXF_CCI_DAT_DueDate__c DESC NULLS LAST,
        AXF_CCI_TXT_Period__c DESC
      LIMIT :MAX_ROWS
    ]) {
      Invoice item = new Invoice();
      item.id = invoice.Id;
      item.period = invoice.AXF_CCI_TXT_Period__c;
      item.dueDate = invoice.AXF_CCI_DAT_DueDate__c;
      item.totalAmount = invoice.AXF_CCI_CUR_TotalAmount__c;
      item.status = invoice.AXF_CCI_PKL_Status__c;
      item.currencyCode = invoice.CurrencyIsoCode;
      items.add(item);
    }
    return items;
  }

  public List<Line> lines(Id invoiceId) {
    List<Line> items = new List<Line>();
    for (AXF_OBJ_CreditCardTransaction__c cardTransaction : [
      SELECT
        AXF_CCT_DAT_Date__c,
        AXF_CCT_TXT_Description__c,
        AXF_CCT_CUR_Amount__c,
        AXF_CCT_CUR_AmountBRL__c,
        AXF_CCT_TXT_CurrencyCode__c,
        AXF_CCT_TXT_Installment__c
      FROM AXF_OBJ_CreditCardTransaction__c
      WHERE AXF_CCT_LKP_Invoice__c = :invoiceId
      WITH USER_MODE
      ORDER BY AXF_CCT_DAT_Date__c DESC, CreatedDate DESC
      LIMIT :MAX_ROWS
    ]) {
      Line item = new Line();
      item.id = cardTransaction.Id;
      item.transactionDate = cardTransaction.AXF_CCT_DAT_Date__c;
      item.description = cardTransaction.AXF_CCT_TXT_Description__c;
      item.amount = cardTransaction.AXF_CCT_CUR_Amount__c;
      item.amountBRL = cardTransaction.AXF_CCT_CUR_AmountBRL__c;
      item.originalCurrency = cardTransaction.AXF_CCT_TXT_CurrencyCode__c;
      item.installment = cardTransaction.AXF_CCT_TXT_Installment__c;
      items.add(item);
    }
    return items;
  }
}
