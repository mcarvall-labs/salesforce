/**
 * @description Status counters and rows of the holder's Pluggy connections for the
 * Configuração home dashboard. Reads run in user mode.
 */
public with sharing class ALT_CLS_PluggyConnectionSummary {
  public class Row {
    public Id id;
    public String holder;
    public String institution;
    public String status;
    public Datetime lastSync;
    public String errorMessage;
  }

  public class Summary {
    public Integer active = 0;
    public Integer error = 0;
    public Integer paused = 0;
    public List<Row> rows = new List<Row>();
  }

  public Summary summarize() {
    Summary summary = new Summary();
    for (AXF_OBJ_PluggyConnection__c connection : [
      SELECT
        Id,
        AXF_CON_MD_Holder__r.Name,
        toLabel(AXF_CON_PKL_Institution__c) institution,
        AXF_CON_PKL_Status__c,
        AXF_CON_DT_LastSyncDatetime__c,
        AXF_CON_TAL_SyncErrorMessage__c
      FROM AXF_OBJ_PluggyConnection__c
      WITH USER_MODE
      ORDER BY AXF_CON_MD_Holder__r.Name, Name
      LIMIT 200
    ]) {
      Row row = new Row();
      row.id = connection.Id;
      row.holder = connection.AXF_CON_MD_Holder__r.Name;
      row.institution = (String) connection.get('institution');
      row.status = connection.AXF_CON_PKL_Status__c;
      row.lastSync = connection.AXF_CON_DT_LastSyncDatetime__c;
      row.errorMessage = connection.AXF_CON_TAL_SyncErrorMessage__c;
      summary.rows.add(row);
      if (row.status == 'Active') {
        summary.active++;
      } else if (row.status == 'Error') {
        summary.error++;
      } else if (row.status == 'Paused') {
        summary.paused++;
      }
    }
    return summary;
  }
}
