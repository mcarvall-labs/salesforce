public with sharing class AXF_CLS_CTRL_TimesheetPdf {
  public ALT_CLS_TimesheetDocument.TimesheetView view { get; private set; }
  public String error { get; private set; }

  public AXF_CLS_CTRL_TimesheetPdf() {
    Map<String, String> params = ApexPages.currentPage().getParameters();
    try {
      view = new ALT_CLS_TimesheetDocument()
        .timesheetView(
          (Id) params.get('id'),
          Integer.valueOf(params.get('year')),
          Integer.valueOf(params.get('month'))
        );
    } catch (Exception e) {
      error = e.getMessage();
    }
  }
}
