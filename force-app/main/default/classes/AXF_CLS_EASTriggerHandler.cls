/**
 * @description Handler de trigger para AXF_OBJ_EconomicAllocationSet__c (AXF-126).
 * Somente despacho de contexto; regras em ALT_CLS_EconomicAllocationGuard.sets.
 */
public with sharing class AXF_CLS_EASTriggerHandler {
  public static void handleBeforeInsert(
    List<AXF_OBJ_EconomicAllocationSet__c> newList
  ) {
    ALT_CLS_EconomicAllocationGuard.sets(newList, null, false);
  }

  public static void handleBeforeUpdate(
    List<AXF_OBJ_EconomicAllocationSet__c> newList,
    Map<Id, AXF_OBJ_EconomicAllocationSet__c> oldMap
  ) {
    ALT_CLS_EconomicAllocationGuard.sets(newList, oldMap, false);
  }

  public static void handleBeforeDelete(
    List<AXF_OBJ_EconomicAllocationSet__c> oldList,
    Map<Id, AXF_OBJ_EconomicAllocationSet__c> oldMap
  ) {
    ALT_CLS_EconomicAllocationGuard.sets(oldList, oldMap, true);
  }
}
