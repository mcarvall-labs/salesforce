/**
 * @description Trigger para AXF_OBJ_ContractTermVersion__c.
 * Garante imutabilidade de termos ACTIVE e SUPERSEDED e protecao contra delecao (AXF-53, AC 2, AD-31).
 */
trigger AXF_TRG_ContractTermVersion on AXF_OBJ_ContractTermVersion__c (before update, before delete) {
  if (Trigger.isBefore && Trigger.isUpdate) {
    AXF_CLS_TermVersionTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
  }
  if (Trigger.isBefore && Trigger.isDelete) {
    AXF_CLS_TermVersionTriggerHandler.handleBeforeDelete(Trigger.old);
  }
}