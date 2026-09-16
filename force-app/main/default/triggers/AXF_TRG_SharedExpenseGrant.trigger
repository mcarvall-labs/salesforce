/**
 * @description Trigger para AXF_OBJ_SharedExpenseGrant__c (AXF-6).
 * Nenhuma regra vive aqui: tudo delega ao handler.
 */
trigger AXF_TRG_SharedExpenseGrant on AXF_OBJ_SharedExpenseGrant__c(
  before insert,
  before update,
  before delete
) {
  if (Trigger.isBefore && Trigger.isInsert) {
    AXF_CLS_SEGTriggerHandler.handleBeforeInsert(Trigger.new);
  }
  if (Trigger.isBefore && Trigger.isUpdate) {
    AXF_CLS_SEGTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
  }
  if (Trigger.isBefore && Trigger.isDelete) {
    AXF_CLS_SEGTriggerHandler.handleBeforeDelete(Trigger.old, Trigger.oldMap);
  }
}
