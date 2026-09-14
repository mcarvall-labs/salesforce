/**
 * @description Trigger para AXF_OBJ_BillingDocument__c (AXF-65).
 * Nenhuma regra vive aqui: tudo delega ao handler.
 */
trigger AXF_TRG_BillingDocument on AXF_OBJ_BillingDocument__c(
  before insert,
  before update,
  before delete
) {
  if (Trigger.isBefore && Trigger.isInsert) {
    AXF_CLS_BDOTriggerHandler.handleBeforeInsert(Trigger.new);
  }
  if (Trigger.isBefore && Trigger.isUpdate) {
    AXF_CLS_BDOTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
  }
  if (Trigger.isBefore && Trigger.isDelete) {
    AXF_CLS_BDOTriggerHandler.handleBeforeDelete(Trigger.old, Trigger.oldMap);
  }
}
