/**
 * @description Handler de trigger para AXF_OBJ_ArchiveRun__c (AXF-95). Somente despacho de
 * contexto: checkpoints nascem e mudam apenas pelo servico de arquivamento; nunca sao apagados.
 */
public with sharing class AXF_CLS_ArchiveRunTriggerHandler {
  public static void handleBeforeInsert(List<AXF_OBJ_ArchiveRun__c> newList) {
    guard(newList);
  }

  public static void handleBeforeUpdate(
    List<AXF_OBJ_ArchiveRun__c> newList,
    Map<Id, AXF_OBJ_ArchiveRun__c> oldMap
  ) {
    guard(newList);
    for (AXF_OBJ_ArchiveRun__c row : newList) {
      AXF_OBJ_ArchiveRun__c before = oldMap.get(row.Id);
      if (
        row.AXF_ARR_EXI_RunKey__c != before.AXF_ARR_EXI_RunKey__c ||
        row.AXF_ARR_PKL_SourceFamily__c != before.AXF_ARR_PKL_SourceFamily__c ||
        row.AXF_ARR_LKP_Account__c != before.AXF_ARR_LKP_Account__c ||
        row.AXF_ARR_TXT_PolicyVersion__c !=
        before.AXF_ARR_TXT_PolicyVersion__c ||
        row.AXF_ARR_DAT_HotWindowStart__c !=
        before.AXF_ARR_DAT_HotWindowStart__c
      ) {
        row.addError('Archive run identity is immutable.');
      }
    }
  }

  public static void handleBeforeDelete(
    List<AXF_OBJ_ArchiveRun__c> oldList,
    Map<Id, AXF_OBJ_ArchiveRun__c> oldMap
  ) {
    for (AXF_OBJ_ArchiveRun__c row : oldList) {
      row.addError('Archive runs cannot be deleted.');
    }
  }

  private static void guard(List<AXF_OBJ_ArchiveRun__c> rows) {
    if (ALT_CLS_ArchiveRunService.isWriting()) {
      return;
    }
    for (AXF_OBJ_ArchiveRun__c row : rows) {
      row.addError('Use the archive run service.');
    }
  }
}
