trigger AXF_TRG_BankAccount on AXF_OBJ_BankAccount__c(
  before insert,
  before update
) {
  if (Trigger.isBefore && Trigger.isInsert) {
    AXF_CLS_BATriggerHandler.handleBeforeInsert(Trigger.new);
  }
  if (Trigger.isBefore && Trigger.isUpdate) {
    AXF_CLS_BATriggerHandler.handleBeforeUpdate(Trigger.new);
  }
}
