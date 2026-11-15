trigger AXF_TRG_Contract on AXF_OBJ_Contract__c(after update) {
  AXF_CLS_ContractHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
}
