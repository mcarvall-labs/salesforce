public with sharing class AXF_CLS_PluggyConnectionHandler {
  public static void handleBeforeSave(
    List<AXF_OBJ_PluggyConnection__c> connections
  ) {
    new ALT_CLS_PluggyConnectionName().apply(connections);
  }
}
