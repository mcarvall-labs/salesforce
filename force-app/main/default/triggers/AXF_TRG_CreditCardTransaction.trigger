trigger AXF_TRG_CreditCardTransaction on AXF_OBJ_CreditCardTransaction__c(
  before insert,
  before update,
  before delete
) {
  if (Trigger.isBefore && Trigger.isInsert) {
    AXF_CLS_CCTTriggerHandler.handleBeforeInsert(Trigger.new);
  }
  if (Trigger.isBefore && Trigger.isUpdate) {
    AXF_CLS_CCTTriggerHandler.handleBeforeUpdate(
      Trigger.new,
      (Map<Id, AXF_OBJ_CreditCardTransaction__c>) Trigger.oldMap
    );
  }
  if (Trigger.isBefore && Trigger.isDelete) {
    AXF_CLS_CCTTriggerHandler.handleBeforeDelete(Trigger.old);
  }
}
