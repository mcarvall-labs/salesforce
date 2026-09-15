/**
 * @description Trigger para AXF_OBJ_EconomicAllocationSet__c (AXF-126).
 * Nenhuma regra vive aqui: tudo delega ao handler.
 */
trigger AXF_TRG_EconomicAllocationSet on AXF_OBJ_EconomicAllocationSet__c(
  before insert,
  before update,
  before delete
) {
  if (Trigger.isBefore && Trigger.isInsert) {
    AXF_CLS_EASTriggerHandler.handleBeforeInsert(Trigger.new);
  }
  if (Trigger.isBefore && Trigger.isUpdate) {
    AXF_CLS_EASTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
  }
  if (Trigger.isBefore && Trigger.isDelete) {
    AXF_CLS_EASTriggerHandler.handleBeforeDelete(Trigger.old, Trigger.oldMap);
  }
}
