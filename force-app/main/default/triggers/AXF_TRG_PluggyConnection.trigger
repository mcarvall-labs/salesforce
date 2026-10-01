trigger AXF_TRG_PluggyConnection on AXF_OBJ_PluggyConnection__c(
  before insert,
  before update
) {
  if (Trigger.isBefore) {
    AXF_CLS_PluggyConnectionHandler.handleBeforeSave(Trigger.new);
  }
}
