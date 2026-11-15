/**
 * @description Sets the PluggyConnection Name to "Holder - Institution (code)". The Name of
 * a Person Account holder and the institution label are not readable from a Flow, so the
 * name is built here, in the before-save handler.
 */
public with sharing class ALT_CLS_PluggyConnectionName {
  private static final Integer NAME_LENGTH = 80;

  public void apply(List<AXF_OBJ_PluggyConnection__c> connections) {
    Set<Id> holderIds = new Set<Id>();
    for (AXF_OBJ_PluggyConnection__c connection : connections) {
      holderIds.add(connection.AXF_CON_MD_Holder__c);
    }
    Map<Id, Account> holders = new Map<Id, Account>(
      [SELECT Name FROM Account WHERE Id IN :holderIds WITH USER_MODE]
    );
    Map<String, String> labels = institutionLabels();

    for (AXF_OBJ_PluggyConnection__c connection : connections) {
      Account holder = holders.get(connection.AXF_CON_MD_Holder__c);
      String holderName = holder == null ? '' : holder.Name;
      connection.Name = (holderName +
        ' - ' +
        institutionName(connection.AXF_CON_PKL_Institution__c, labels))
        .left(NAME_LENGTH);
    }
  }

  private Map<String, String> institutionLabels() {
    Map<String, String> labels = new Map<String, String>();
    for (
      Schema.PicklistEntry entry : AXF_OBJ_PluggyConnection__c.AXF_CON_PKL_Institution__c.getDescribe()
        .getPicklistValues()
    ) {
      labels.put(entry.getValue(), entry.getLabel());
    }
    return labels;
  }

  private String institutionName(String code, Map<String, String> labels) {
    String label = labels.get(code);
    String prefix = code + ' - ';
    String bankName = label != null && label.startsWith(prefix)
      ? label.substring(prefix.length())
      : code;
    return bankName + ' (' + code + ')';
  }
}
