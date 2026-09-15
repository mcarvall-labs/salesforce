/**
 * @description Trigger para AXF_OBJ_CreditCardTransaction__c (AXF-25 / AXF-105).
 * Nenhuma regra vive aqui: tudo delega ao handler.
 */
trigger AXF_TRG_RealizationCardTransaction on AXF_OBJ_CreditCardTransaction__c(
  before insert,
  before update,
  before delete
) {
  if (Trigger.isBefore && Trigger.isInsert) {
    AXF_CLS_CCTTriggerHandler.handleBeforeInsert(Trigger.new);
  }
  if (Trigger.isBefore && Trigger.isUpdate) {
    AXF_CLS_CCTTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
  }
  if (Trigger.isBefore && Trigger.isDelete) {
    AXF_CLS_CCTTriggerHandler.handleBeforeDelete(Trigger.old, Trigger.oldMap);
  }
}
