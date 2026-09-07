/**
 * @description Trigger para AXF_OBJ_ReviewItem__c (AXF-94).
 * Garante sem delete e resolucao/descarto somente via servico (expurgo G7).
 */
trigger AXF_TRG_ReviewItem on AXF_OBJ_ReviewItem__c(
  before update,
  before delete
) {
  if (Trigger.isBefore && Trigger.isUpdate) {
    AXF_CLS_ReviewQueueTriggerHandler.handleBeforeUpdate(
      Trigger.new,
      Trigger.oldMap
    );
  }
  if (Trigger.isBefore && Trigger.isDelete) {
    AXF_CLS_ReviewQueueTriggerHandler.handleBeforeDelete(Trigger.old);
  }
}
