/**
 * @description Trigger para AXF_OBJ_FxSettlement__c (AXF-59).
 * Sem delete; imutavel apos CONFIRMED/CORRECTION/REVERSAL.
 */
trigger AXF_TRG_FxSettlement on AXF_OBJ_FxSettlement__c(
  before update,
  before delete
) {
  if (Trigger.isBefore && Trigger.isUpdate) {
    AXF_CLS_FxSettlementTriggerHandler.handleBeforeUpdate(
      Trigger.new,
      Trigger.oldMap
    );
  }
  if (Trigger.isBefore && Trigger.isDelete) {
    AXF_CLS_FxSettlementTriggerHandler.handleBeforeDelete(Trigger.old);
  }
}
