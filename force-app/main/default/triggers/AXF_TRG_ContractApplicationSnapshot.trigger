/**
 * @description Trigger para AXF_OBJ_ContractApplicationSnapshot__c.
 * Imutabilidade de conteudo e bloqueio de delete (AXF-57, G7-2).
 */
trigger AXF_TRG_ContractApplicationSnapshot on AXF_OBJ_ContractApplicationSnapshot__c(
  before insert,
  before update,
  before delete
) {
  if (Trigger.isBefore && Trigger.isInsert) {
    AXF_CLS_CASTriggerHandler.handleBeforeInsert(Trigger.new);
  }
  if (Trigger.isBefore && Trigger.isUpdate) {
    AXF_CLS_CASTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
  }
  if (Trigger.isBefore && Trigger.isDelete) {
    AXF_CLS_CASTriggerHandler.handleBeforeDelete(Trigger.old);
  }
}
