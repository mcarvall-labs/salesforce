/**
 * @description Handler de trigger para AXF_OBJ_ReconciliationAllocation__c (AXF-25 / AXF-105).
 * Somente despacho de contexto: escrita apenas pelo servico atomico, imutabilidade do conteudo e alocacao tipada permanecem em ALT_CLS_RealizationGuard.allocations.
 */
public with sharing class AXF_CLS_RATriggerHandler {
  public static void handleBeforeInsert(
    List<AXF_OBJ_ReconciliationAllocation__c> newList
  ) {
    ALT_CLS_RealizationGuard.allocations(newList, null, false);
  }

  public static void handleBeforeUpdate(
    List<AXF_OBJ_ReconciliationAllocation__c> newList,
    Map<Id, AXF_OBJ_ReconciliationAllocation__c> oldMap
  ) {
    ALT_CLS_RealizationGuard.allocations(newList, oldMap, false);
  }

  public static void handleBeforeDelete(
    List<AXF_OBJ_ReconciliationAllocation__c> oldList,
    Map<Id, AXF_OBJ_ReconciliationAllocation__c> oldMap
  ) {
    ALT_CLS_RealizationGuard.allocations(oldList, oldMap, true);
  }
}
