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

  // "Sincronizar agora": starts the full sync (accounts, cards, transactions, invoices) of one
  // connection in the background; the dashboard shows the new status when it finishes.
  @AuraEnabled
  public static SyncView syncConnection(Id connectionId) {
    if (connectionId == null) {
      throw new AuraHandledException('Informe a conexão.');
    }
    List<AXF_OBJ_PluggyConnection__c> found = [
      SELECT AXF_CON_PKL_Status__c
      FROM AXF_OBJ_PluggyConnection__c
      WHERE Id = :connectionId
      WITH USER_MODE
    ];
    SyncView view = new SyncView();
    if (found.isEmpty()) {
      view.success = false;
      view.message = 'Conexão não encontrada.';
    } else if (found[0].AXF_CON_PKL_Status__c == 'Paused') {
      view.success = false;
      view.message = 'A conexão está pausada.';
    } else {
      ALT_CLS_PluggySyncBatch.run(connectionId);
      view.success = true;
      view.message = 'Sincronização iniciada. Atualize o painel em instantes.';
    }
    return view;
  }
}
