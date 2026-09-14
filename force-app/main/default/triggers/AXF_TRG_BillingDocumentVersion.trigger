/**
 * @description Trigger para AXF_OBJ_BillingDocumentVersion__c (AXF-65).
 * Nenhuma regra vive aqui: tudo delega ao handler.
 */
trigger AXF_TRG_BillingDocumentVersion on AXF_OBJ_BillingDocumentVersion__c(
  before insert,
  before update,
  before delete
) {
  if (Trigger.isBefore && Trigger.isInsert) {
    AXF_CLS_BDVTriggerHandler.handleBeforeInsert(Trigger.new);
  }
  if (Trigger.isBefore && Trigger.isUpdate) {
    AXF_CLS_BDVTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
  }
  if (Trigger.isBefore && Trigger.isDelete) {
    AXF_CLS_BDVTriggerHandler.handleBeforeDelete(Trigger.old, Trigger.oldMap);
  }
}
