public with sharing class AXF_CLS_CTRL_InvoicePdf {
  public ALT_CLS_TimesheetDocument.InvoiceView view { get; private set; }
  public String error { get; private set; }

  public AXF_CLS_CTRL_InvoicePdf() {
    Map<String, String> params = ApexPages.currentPage().getParameters();
    try {
      view = new ALT_CLS_TimesheetDocument()
        .invoiceView(
          (Id) params.get('id'),
          Integer.valueOf(params.get('year')),
          Integer.valueOf(params.get('month'))
        );
    } catch (Exception e) {
      error = e.getMessage();
    }
  }
}
