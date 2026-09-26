trigger AXF_TRG_CashFlow on AXF_OBJ_CashFlow__c(
  before insert,
  before update,
  before delete,
  after insert,
  after update,
  after delete
) {
  if (Trigger.isBefore && Trigger.isInsert) {
    AXF_CLS_CFTriggerHandler.handleBeforeInsert(Trigger.new);
  }
  if (Trigger.isBefore && Trigger.isUpdate) {
    AXF_CLS_CFTriggerHandler.handleBeforeUpdate(
      Trigger.new,
      (Map<Id, AXF_OBJ_CashFlow__c>) Trigger.oldMap
    );
  }
  if (Trigger.isBefore && Trigger.isDelete) {
    AXF_CLS_CFTriggerHandler.handleBeforeDelete(Trigger.old);
  }
  if (Trigger.isAfter && Trigger.isInsert) {
    AXF_CLS_CFTriggerHandler.handleAfterInsert(Trigger.new);
  }
  if (Trigger.isAfter && Trigger.isUpdate) {
    AXF_CLS_CFTriggerHandler.handleAfterUpdate(
      Trigger.new,
      (Map<Id, AXF_OBJ_CashFlow__c>) Trigger.oldMap
    );
  }
  if (Trigger.isAfter && Trigger.isDelete) {
    AXF_CLS_CFTriggerHandler.handleAfterDelete(Trigger.old);
  }
}
