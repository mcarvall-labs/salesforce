/**
 * @description Trigger para AXF_OBJ_ReconciliationAllocation__c (AXF-25 / AXF-105).
 * Nenhuma regra vive aqui: tudo delega ao handler.
 */
trigger AXF_TRG_RealizationAllocation on AXF_OBJ_ReconciliationAllocation__c(
  before insert,
  before update,
  before delete
) {
  if (Trigger.isBefore && Trigger.isInsert) {
    AXF_CLS_RATriggerHandler.handleBeforeInsert(Trigger.new);
  }
  if (Trigger.isBefore && Trigger.isUpdate) {
    AXF_CLS_RATriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
  }
  if (Trigger.isBefore && Trigger.isDelete) {
    AXF_CLS_RATriggerHandler.handleBeforeDelete(Trigger.old, Trigger.oldMap);
  }
}
