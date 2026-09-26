trigger AXF_TRG_BankAccountTransaction on AXF_OBJ_BankAccountTransaction__c(
  before insert,
  before update,
  before delete
) {
  if (Trigger.isBefore && Trigger.isInsert) {
    AXF_CLS_BATTriggerHandler.handleBeforeInsert(Trigger.new);
  }
  if (Trigger.isBefore && Trigger.isUpdate) {
    AXF_CLS_BATTriggerHandler.handleBeforeUpdate(
      Trigger.new,
      (Map<Id, AXF_OBJ_BankAccountTransaction__c>) Trigger.oldMap
    );
  }
  if (Trigger.isBefore && Trigger.isDelete) {
    AXF_CLS_BATTriggerHandler.handleBeforeDelete(Trigger.old);
  }
}
