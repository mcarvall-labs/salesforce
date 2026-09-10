trigger AXF_TRG_RealizationBankTransaction on AXF_OBJ_BankAccountTransaction__c(
  before insert,
  before update,
  before delete
) {
  ALT_CLS_RealizationGuard.originals(
    Trigger.isDelete ? Trigger.old : Trigger.new,
    Trigger.oldMap,
    Trigger.isDelete
  );
}
