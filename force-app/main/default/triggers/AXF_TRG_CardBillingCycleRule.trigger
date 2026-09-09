/**
 * @description Trigger para AXF_OBJ_CardBillingCycleRule__c (AXF-35).
 * Garante imutabilidade de regras ACTIVE/SUPERSEDED e bloqueio de delete.
 */
trigger AXF_TRG_CardBillingCycleRule on AXF_OBJ_CardBillingCycleRule__c(
  before update,
  before delete
) {
  if (Trigger.isBefore && Trigger.isUpdate) {
    AXF_CLS_CardBillingCycleTriggerHandler.handleBeforeUpdate(
      Trigger.new,
      Trigger.oldMap
    );
  }
  if (Trigger.isBefore && Trigger.isDelete) {
    AXF_CLS_CardBillingCycleTriggerHandler.handleBeforeDelete(Trigger.old);
  }
}
