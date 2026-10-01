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
}
