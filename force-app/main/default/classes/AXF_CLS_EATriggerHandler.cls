/**
 * @description Handler de trigger para AXF_OBJ_EconomicAllocation__c (AXF-126).
 * Somente despacho de contexto; regras em ALT_CLS_EconomicAllocationGuard.allocations.
 */
public with sharing class AXF_CLS_EATriggerHandler {
  public static void handleBeforeInsert(
    List<AXF_OBJ_EconomicAllocation__c> newList
  ) {
    ALT_CLS_EconomicAllocationGuard.allocations(newList, null, false);
  }

  public static void handleBeforeUpdate(
    List<AXF_OBJ_EconomicAllocation__c> newList,
    Map<Id, AXF_OBJ_EconomicAllocation__c> oldMap
  ) {
    ALT_CLS_EconomicAllocationGuard.allocations(newList, oldMap, false);
  }

  public static void handleBeforeDelete(
    List<AXF_OBJ_EconomicAllocation__c> oldList,
    Map<Id, AXF_OBJ_EconomicAllocation__c> oldMap
  ) {
    ALT_CLS_EconomicAllocationGuard.allocations(oldList, oldMap, true);
  }
}
