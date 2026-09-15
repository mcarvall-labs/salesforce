/**
 * @description Trigger para AXF_OBJ_ClosureRun__c (AXF-119).
 * Nenhuma regra vive aqui: tudo delega ao handler.
 */
trigger AXF_TRG_ClosureRun on AXF_OBJ_ClosureRun__c(
  before insert,
  before update,
  before delete
) {
  if (Trigger.isBefore && Trigger.isInsert) {
    AXF_CLS_CLRTriggerHandler.handleBeforeInsert(Trigger.new);
  }
  if (Trigger.isBefore && Trigger.isUpdate) {
    AXF_CLS_CLRTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
  }
  if (Trigger.isBefore && Trigger.isDelete) {
    AXF_CLS_CLRTriggerHandler.handleBeforeDelete(Trigger.old, Trigger.oldMap);
  }
}
