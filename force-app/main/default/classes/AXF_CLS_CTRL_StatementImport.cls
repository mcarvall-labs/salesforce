public with sharing class AXF_CLS_CTRL_StatementImport {
  public class LineView {
    @AuraEnabled
    public Date lineDate;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String error;
    @AuraEnabled
    public String note;
  }

  public class PreviewView {
    @AuraEnabled
    public List<LineView> lines = new List<LineView>();
    @AuraEnabled
    public Integer newCount;
    @AuraEnabled
    public Integer duplicateCount;
    @AuraEnabled
    public Integer errorCount;
    @AuraEnabled
    public List<String> warnings;
  }

  public class ImportView {
    @AuraEnabled
    public Boolean success;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Integer imported;
  }

  @AuraEnabled
  public static PreviewView preview(
    Id recordId,
    String fileName,
    String content
  ) {
    try {
      ALT_CLS_StatementImport.Preview preview = new ALT_CLS_StatementImport()
        .preview(recordId, fileName, content);
      PreviewView view = new PreviewView();
      view.newCount = preview.newCount;
      view.duplicateCount = preview.duplicateCount;
      view.errorCount = preview.errorCount;
      view.warnings = preview.warnings;
      for (ALT_CLS_StatementImport.Line line : preview.lines) {
        LineView item = new LineView();
        item.lineDate = line.lineDate;
        item.description = line.description;
        item.amount = line.amount;
        item.status = line.status;
        item.error = line.error;
        item.note = line.note;
        view.lines.add(item);
      }
      return view;
    } catch (ALT_CLS_StatementImport.ImportException e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  @AuraEnabled
  public static ImportView importStatement(
    Id recordId,
    String fileName,
    String content
  ) {
    try {
      ALT_CLS_StatementImport.Result result = new ALT_CLS_StatementImport()
        .importFile(recordId, fileName, content);
      ImportView view = new ImportView();
      view.success = result.success;
      view.message = result.message;
      view.imported = result.imported;
      return view;
    } catch (ALT_CLS_StatementImport.ImportException e) {
      throw new AuraHandledException(e.getMessage());
    }
  }
}
