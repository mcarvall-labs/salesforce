trigger AXF_TRG_BankInstitution on AXF_OBJ_BankInstitution__c(
  before insert,
  before update
) {
  if (Trigger.isInsert) {
    AXF_CLS_TH_BankInstitution.handleBeforeInsert(Trigger.new);
  } else if (Trigger.isUpdate) {
    AXF_CLS_TH_BankInstitution.handleBeforeUpdate(Trigger.new);
  }
}
