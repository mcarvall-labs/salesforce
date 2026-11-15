public with sharing class AXF_CLS_CTRL_CardInvoices {
  public class InvoiceView {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String period;
    @AuraEnabled
    public Date dueDate;
    @AuraEnabled
    public Decimal totalAmount;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String currencyCode;
    @AuraEnabled
    public Boolean projected;
    @AuraEnabled
    public List<LineView> lines;
  }

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
    @AuraEnabled
    public Boolean projected;
  }

  @AuraEnabled
  public static List<InvoiceView> getInvoices(Id creditCardId) {
    if (creditCardId == null) {
      throw new AuraHandledException('Informe o cartão.');
    }
    List<InvoiceView> views = new List<InvoiceView>();
    for (
      ALT_CLS_CardInvoices.Invoice invoice : new ALT_CLS_CardInvoices()
        .invoices(creditCardId)
    ) {
      InvoiceView view = new InvoiceView();
      view.id = invoice.id;
      view.period = invoice.period;
      view.dueDate = invoice.dueDate;
      view.totalAmount = invoice.totalAmount;
      view.status = invoice.status;
      view.currencyCode = invoice.currencyCode;
      view.projected = invoice.projected;
      if (invoice.lines != null) {
        view.lines = new List<LineView>();
        for (ALT_CLS_CardInvoices.Line line : invoice.lines) {
          view.lines.add(toView(line));
        }
      }
      views.add(view);
    }
    return views;
  }

  @AuraEnabled
  public static List<LineView> getLines(Id invoiceId) {
    if (invoiceId == null) {
      throw new AuraHandledException('Informe a fatura.');
    }
    List<LineView> views = new List<LineView>();
    for (
      ALT_CLS_CardInvoices.Line line : new ALT_CLS_CardInvoices()
        .lines(invoiceId)
    ) {
      LineView view = toView(line);
      views.add(view);
    }
    return views;
  }

  private static LineView toView(ALT_CLS_CardInvoices.Line line) {
    LineView view = new LineView();
    view.id = line.id;
    view.transactionDate = line.transactionDate;
    view.description = line.description;
    view.amount = line.amount;
    view.amountBRL = line.amountBRL;
    view.originalCurrency = line.originalCurrency;
    view.installment = line.installment;
    view.projected = line.projected;
    return view;
  }
}
