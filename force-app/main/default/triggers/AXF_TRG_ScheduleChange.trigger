/**
 * @description Trigger para AXF_OBJ_ScheduleChange__c (AXF-103). Recibo de operação imutável,
 * delimitado por OperationKey, com guarda de delete.
 */
trigger AXF_TRG_ScheduleChange on AXF_OBJ_ScheduleChange__c(
  before insert,
  before update,
  before delete
) {
  if (Trigger.isBefore && Trigger.isInsert) {
    AXF_CLS_SCHTriggerHandler.handleBeforeInsert(Trigger.new);
  }
  if (Trigger.isBefore && Trigger.isUpdate) {
    AXF_CLS_SCHTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
  }
  if (Trigger.isBefore && Trigger.isDelete) {
    AXF_CLS_SCHTriggerHandler.handleBeforeDelete(Trigger.old);
  }
}
