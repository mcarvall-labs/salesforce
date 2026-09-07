/**
 * @description Trigger para AXF_OBJ_FxApplicationSnapshot__c (AXF-24).
 * Sem delete; imutavel; ACTIVE -> SUPERSEDED via servico.
 */
trigger AXF_TRG_FxApplicationSnapshot on AXF_OBJ_FxApplicationSnapshot__c(
  before update,
  before delete
) {
  if (Trigger.isBefore && Trigger.isUpdate) {
    AXF_CLS_FxSnapshotTriggerHandler.handleBeforeUpdate(
      Trigger.new,
      Trigger.oldMap
    );
  }
  if (Trigger.isBefore && Trigger.isDelete) {
    AXF_CLS_FxSnapshotTriggerHandler.handleBeforeDelete(Trigger.old);
  }
}
