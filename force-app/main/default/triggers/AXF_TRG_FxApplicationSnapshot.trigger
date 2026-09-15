/**
 * @description Trigger para AXF_OBJ_FxApplicationSnapshot__c (AXF-24 / AXF-105).
 * Nenhuma regra vive aqui: tudo delega a AXF_CLS_FxSnapshotTriggerHandler (imutabilidade e transicoes de estado).
 */
trigger AXF_TRG_FxApplicationSnapshot on AXF_OBJ_FxApplicationSnapshot__c(
  before insert,
  before update,
  before delete
) {
  if (Trigger.isBefore && Trigger.isInsert) {
    AXF_CLS_FxSnapshotTriggerHandler.handleBeforeInsert(Trigger.new);
  }
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
