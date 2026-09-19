/**
 * @description Trigger para AXF_OBJ_SettlementDecision__c (AXF-104).
 * Imutabilidade do recibo de operação e guarda de escrita direta.
 * Nenhuma regra vive aqui: tudo delega ao handler.
 */
trigger AXF_TRG_SettlementDecision on AXF_OBJ_SettlementDecision__c(
  before insert,
  before update,
  before delete
) {
  if (Trigger.isBefore && Trigger.isInsert) {
    AXF_CLS_SettlementDecisionHandler.handleBeforeInsert(Trigger.new);
  }
  if (Trigger.isBefore && Trigger.isUpdate) {
    AXF_CLS_SettlementDecisionHandler.handleBeforeUpdate(
      Trigger.new,
      Trigger.oldMap
    );
  }
  if (Trigger.isBefore && Trigger.isDelete) {
    AXF_CLS_SettlementDecisionHandler.handleBeforeDelete(Trigger.old);
  }
}
