/**
 * @description Trigger para AXF_OBJ_ScheduleDefinition__c (AXF-103). Imutabilidade da evidência
 * de definição, unicidade/monotonicidade da revisão e guarda de delete.
 */
trigger AXF_TRG_ScheduleDefinition on AXF_OBJ_ScheduleDefinition__c(
  before insert,
  before update,
  before delete
) {
  if (Trigger.isBefore && Trigger.isInsert) {
    AXF_CLS_SDFTriggerHandler.handleBeforeInsert(Trigger.new);
  }
  if (Trigger.isBefore && Trigger.isUpdate) {
    AXF_CLS_SDFTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
  }
  if (Trigger.isBefore && Trigger.isDelete) {
    AXF_CLS_SDFTriggerHandler.handleBeforeDelete(Trigger.old);
  }
}
