public with sharing class AXF_CLS_CTRL_ConnectionDashboard {
  public class ConnectionRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String holder;
    @AuraEnabled
    public String institution;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Datetime lastSync;
    @AuraEnabled
    public String errorMessage;
  }

  public class DashboardData {
    @AuraEnabled
    public Integer active;
    @AuraEnabled
    public Integer error;
    @AuraEnabled
    public Integer paused;
    @AuraEnabled
    public List<ConnectionRow> rows = new List<ConnectionRow>();
  }

  public class SyncView {
    @AuraEnabled
    public Boolean success;
    @AuraEnabled
    public String message;
  }

  @AuraEnabled(cacheable=true)
  public static DashboardData getDashboard() {
    ALT_CLS_PluggyConnectionSummary.Summary summary = new ALT_CLS_PluggyConnectionSummary()
      .summarize();
    DashboardData data = new DashboardData();
    data.active = summary.active;
    data.error = summary.error;
    data.paused = summary.paused;
    for (ALT_CLS_PluggyConnectionSummary.Row source : summary.rows) {
      ConnectionRow row = new ConnectionRow();
      row.id = source.id;
      row.holder = source.holder;
      row.institution = source.institution;
      row.status = source.status;
      row.lastSync = source.lastSync;
      row.errorMessage = source.errorMessage;
      data.rows.add(row);
    }
    return data;
  }

  // Brings the accounts and cards of one connection. Their transactions and invoices come with
  // the scheduled sync (AXF-184): a callout cannot follow the DML of this one.
  @AuraEnabled
  public static SyncView syncConnection(Id connectionId) {
    if (connectionId == null) {
      throw new AuraHandledException('Informe a conexão.');
    }
    ALT_CLS_PluggyAccountSync.Result result = new ALT_CLS_PluggyAccountSync()
      .sync(connectionId);
    SyncView view = new SyncView();
    view.success = result.success;
    view.message = result.success
      ? result.message +
        ' ' +
        result.accounts +
        ' contas e ' +
        result.cards +
        ' cartões.'
      : result.message;
    return view;
  }
}
