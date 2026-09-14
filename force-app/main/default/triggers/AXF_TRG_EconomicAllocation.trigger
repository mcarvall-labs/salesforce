/**
 * @description Trigger para AXF_OBJ_EconomicAllocation__c (AXF-126).
 * Nenhuma regra vive aqui: tudo delega ao handler.
 */
trigger AXF_TRG_EconomicAllocation on AXF_OBJ_EconomicAllocation__c(
  before insert,
  before update,
  before delete
) {
  if (Trigger.isBefore && Trigger.isInsert) {
    AXF_CLS_EATriggerHandler.handleBeforeInsert(Trigger.new);
  }
  if (Trigger.isBefore && Trigger.isUpdate) {
    AXF_CLS_EATriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
  }
  if (Trigger.isBefore && Trigger.isDelete) {
    AXF_CLS_EATriggerHandler.handleBeforeDelete(Trigger.old, Trigger.oldMap);
  }
}
