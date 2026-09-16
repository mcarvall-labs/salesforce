/**
 * @description Trigger para AXF_OBJ_TransactionObservation__c (AXF-109).
 * Nenhuma regra vive aqui: tudo delega ao handler.
 */
trigger AXF_TRG_TransactionObservation on AXF_OBJ_TransactionObservation__c(
  before insert,
  before update,
  before delete
) {
  if (Trigger.isBefore && Trigger.isInsert) {
    AXF_CLS_TOBTriggerHandler.handleBeforeInsert(Trigger.new);
  }
  if (Trigger.isBefore && Trigger.isUpdate) {
    AXF_CLS_TOBTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
  }
  if (Trigger.isBefore && Trigger.isDelete) {
    AXF_CLS_TOBTriggerHandler.handleBeforeDelete(Trigger.old, Trigger.oldMap);
  }
}
