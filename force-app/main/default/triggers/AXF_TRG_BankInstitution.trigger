trigger AXF_TRG_BankInstitution on AXF_OBJ_BankInstitution__c (before insert, before update) {
    AXF_CLS_TH_BankInstitution.handleBeforeInsertUpdate(Trigger.new);
}
