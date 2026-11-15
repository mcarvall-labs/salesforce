public with sharing class AXF_CLS_CTRL_InvoiceTransactions {
  public class LineView {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public Date transactionDate;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public Decimal amountBRL;
    @AuraEnabled
    public String originalCurrency;
    @AuraEnabled
    public String installment;
  }

  public class InvoiceView {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String cardName;
    @AuraEnabled
    public String period;
    @AuraEnabled
    public Date closingDate;
    @AuraEnabled
    public Date dueDate;
    @AuraEnabled
    public Decimal totalAmount;
    @AuraEnabled
    public String currencyCode;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public List<LineView> lines = new List<LineView>();
  }

  // Accepts an invoice Id, or the Id of an Entry that points to an invoice (the record page of the
  // invoice Entry); returns null when the Entry has no invoice.
  @AuraEnabled
  public static InvoiceView getInvoice(Id recordId) {
    if (recordId == null) {
      throw new AuraHandledException('Informe a fatura.');
    }
    Id invoiceId = recordId;
    try {
      if (recordId.getSObjectType() == AXF_OBJ_Entry__c.SObjectType) {
        List<AXF_OBJ_Entry__c> entries = [
          SELECT AXF_ENT_LKP_Invoice__c
          FROM AXF_OBJ_Entry__c
          WHERE Id = :recordId
          WITH USER_MODE
        ];
        if (entries.isEmpty() || entries[0].AXF_ENT_LKP_Invoice__c == null) {
          return null;
        }
        invoiceId = entries[0].AXF_ENT_LKP_Invoice__c;
      } else if (
        recordId.getSObjectType() != AXF_OBJ_CreditCardInvoice__c.SObjectType
      ) {
        throw new AuraHandledException('Registro sem fatura.');
      }
      List<AXF_OBJ_CreditCardInvoice__c> invoices = [
        SELECT
          AXF_CCI_TXT_Period__c,
          AXF_CCI_DAT_ClosingDate__c,
          AXF_CCI_DAT_DueDate__c,
          AXF_CCI_CUR_TotalAmount__c,
          AXF_CCI_PKL_Status__c,
          CurrencyIsoCode,
          AXF_CCI_MD_CreditCard__r.Name
        FROM AXF_OBJ_CreditCardInvoice__c
        WHERE Id = :invoiceId
        WITH USER_MODE
      ];
      if (invoices.isEmpty()) {
        return null;
      }
      InvoiceView view = new InvoiceView();
      view.id = invoices[0].Id;
      view.cardName = invoices[0].AXF_CCI_MD_CreditCard__r.Name;
      view.period = invoices[0].AXF_CCI_TXT_Period__c;
      view.closingDate = invoices[0].AXF_CCI_DAT_ClosingDate__c;
      view.dueDate = invoices[0].AXF_CCI_DAT_DueDate__c;
      view.totalAmount = invoices[0].AXF_CCI_CUR_TotalAmount__c;
      // The invoice total is always in BRL (E6-11).
      view.currencyCode = 'BRL';
      view.status = invoices[0].AXF_CCI_PKL_Status__c;
      for (
        ALT_CLS_CardInvoices.Line line : new ALT_CLS_CardInvoices()
          .lines(invoiceId)
      ) {
        LineView item = new LineView();
        item.id = line.id;
        item.transactionDate = line.transactionDate;
        item.description = line.description;
        item.amount = line.amount;
        item.amountBRL = line.amountBRL;
        item.originalCurrency = line.originalCurrency;
        item.installment = line.installment;
        view.lines.add(item);
      }
      return view;
    } catch (QueryException e) {
      throw new AuraHandledException('Sem acesso à fatura.');
    }
  }
}
