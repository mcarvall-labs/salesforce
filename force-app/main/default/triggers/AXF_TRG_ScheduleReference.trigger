/**
 * @description Trigger para AXF_OBJ_ScheduleReference__c (AXF-103). Imutabilidade da evidência
 * de referência recorrente e guarda de delete.
 */
trigger AXF_TRG_ScheduleReference on AXF_OBJ_ScheduleReference__c(
  before insert,
  before update,
  before delete
) {
  if (Trigger.isBefore && Trigger.isInsert) {
    AXF_CLS_SRFTriggerHandler.handleBeforeInsert(Trigger.new);
  }
  if (Trigger.isBefore && Trigger.isUpdate) {
    AXF_CLS_SRFTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
  }
  if (Trigger.isBefore && Trigger.isDelete) {
    AXF_CLS_SRFTriggerHandler.handleBeforeDelete(Trigger.old);
  }
}
