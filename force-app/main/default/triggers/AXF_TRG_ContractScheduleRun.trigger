/**
 * @description Trigger para AXF_OBJ_ContractScheduleRun__c (AXF-55).
 * Maquina de estados da execucao da agenda + imutabilidade e bloqueio de delete.
 */
trigger AXF_TRG_ContractScheduleRun on AXF_OBJ_ContractScheduleRun__c(
  before insert,
  before update,
  before delete
) {
  if (Trigger.isBefore && Trigger.isInsert) {
    AXF_CLS_CSRTriggerHandler.handleBeforeInsert(Trigger.new);
  }
  if (Trigger.isBefore && Trigger.isUpdate) {
    AXF_CLS_CSRTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
  }
  if (Trigger.isBefore && Trigger.isDelete) {
    AXF_CLS_CSRTriggerHandler.handleBeforeDelete(Trigger.old);
  }
}
