/**
 * @description Trigger para AXF_OBJ_CreditCard__c: nome padronizado "TITULAR - INSTITUICAO".
 */
trigger AXF_TRG_CreditCard on AXF_OBJ_CreditCard__c(
  before insert,
  before update
) {
  if (Trigger.isBefore && Trigger.isInsert) {
    AXF_CLS_CCTriggerHandler.handleBeforeInsert(Trigger.new);
  }
  if (Trigger.isBefore && Trigger.isUpdate) {
    AXF_CLS_CCTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
  }
}
