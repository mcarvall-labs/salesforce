trigger AXF_TRG_BankInstitution on AXF_OBJ_BankInstitution__c(
  before insert,
  before update
) {
  if (Trigger.isBefore && Trigger.isInsert) {
    AXF_CLS_BITriggerHandler.handleBeforeInsert(Trigger.new);
  }
  if (Trigger.isBefore && Trigger.isUpdate) {
    AXF_CLS_BITriggerHandler.handleBeforeUpdate(Trigger.new);
  }
}
