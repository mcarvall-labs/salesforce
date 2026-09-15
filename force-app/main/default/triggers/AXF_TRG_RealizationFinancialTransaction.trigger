/**
 * @description Trigger para AXF_OBJ_FinancialTransaction__c (AXF-25 / AXF-105).
 * Nenhuma regra vive aqui: tudo delega ao handler.
 */
trigger AXF_TRG_RealizationFinancialTransaction on AXF_OBJ_FinancialTransaction__c(
  before insert,
  before update,
  before delete
) {
  if (Trigger.isBefore && Trigger.isInsert) {
    AXF_CLS_FTXTriggerHandler.handleBeforeInsert(Trigger.new);
  }
  if (Trigger.isBefore && Trigger.isUpdate) {
    AXF_CLS_FTXTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
  }
  if (Trigger.isBefore && Trigger.isDelete) {
    AXF_CLS_FTXTriggerHandler.handleBeforeDelete(Trigger.old, Trigger.oldMap);
  }
}
