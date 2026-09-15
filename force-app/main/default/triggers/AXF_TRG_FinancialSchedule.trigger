/**
 * @description Trigger para AXF_OBJ_FinancialSchedule__c (AXF-103). Invariantes de identidade,
 * transição de estado e guarda de delete. Nenhuma regra vive aqui: tudo delega ao handler.
 */
trigger AXF_TRG_FinancialSchedule on AXF_OBJ_FinancialSchedule__c(
  before insert,
  before update,
  before delete
) {
  if (Trigger.isBefore && Trigger.isInsert) {
    AXF_CLS_FSCTriggerHandler.handleBeforeInsert(Trigger.new);
  }
  if (Trigger.isBefore && Trigger.isUpdate) {
    AXF_CLS_FSCTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
  }
  if (Trigger.isBefore && Trigger.isDelete) {
    AXF_CLS_FSCTriggerHandler.handleBeforeDelete(Trigger.old);
  }
}
