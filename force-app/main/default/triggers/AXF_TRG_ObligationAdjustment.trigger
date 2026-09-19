/**
 * @description Trigger para AXF_OBJ_ObligationAdjustment__c (AXF-104).
 * Imutabilidade da evidência de ajuste e guarda de escrita direta.
 * Nenhuma regra vive aqui: tudo delega ao handler.
 */
trigger AXF_TRG_ObligationAdjustment on AXF_OBJ_ObligationAdjustment__c(
  before insert,
  before update,
  before delete
) {
  if (Trigger.isBefore && Trigger.isInsert) {
    AXF_CLS_ObligationAdjustmentHandler.handleBeforeInsert(Trigger.new);
  }
  if (Trigger.isBefore && Trigger.isUpdate) {
    AXF_CLS_ObligationAdjustmentHandler.handleBeforeUpdate(
      Trigger.new,
      Trigger.oldMap
    );
  }
  if (Trigger.isBefore && Trigger.isDelete) {
    AXF_CLS_ObligationAdjustmentHandler.handleBeforeDelete(Trigger.old);
  }
}
