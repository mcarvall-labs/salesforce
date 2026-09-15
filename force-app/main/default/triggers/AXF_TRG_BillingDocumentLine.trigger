/**
 * @description Trigger para AXF_OBJ_BillingDocumentLine__c (AXF-65).
 * Nenhuma regra vive aqui: tudo delega ao handler.
 */
trigger AXF_TRG_BillingDocumentLine on AXF_OBJ_BillingDocumentLine__c(
  before insert,
  before update,
  before delete
) {
  if (Trigger.isBefore && Trigger.isInsert) {
    AXF_CLS_BDLTriggerHandler.handleBeforeInsert(Trigger.new);
  }
  if (Trigger.isBefore && Trigger.isUpdate) {
    AXF_CLS_BDLTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
  }
  if (Trigger.isBefore && Trigger.isDelete) {
    AXF_CLS_BDLTriggerHandler.handleBeforeDelete(Trigger.old, Trigger.oldMap);
  }
}
