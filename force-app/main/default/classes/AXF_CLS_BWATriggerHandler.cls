/**
 * @description Handler de trigger para AXF_OBJ_BillingDocumentWorkAllocation__c (AXF-65).
 * Somente despacho de contexto; regras em ALT_CLS_BillingGuard.workAllocations.
 */
public with sharing class AXF_CLS_BWATriggerHandler {
  public static void handleBeforeInsert(
    List<AXF_OBJ_BillingDocumentWorkAllocation__c> newList
  ) {
    ALT_CLS_BillingGuard.workAllocations(newList, null, false);
  }

  public static void handleBeforeUpdate(
    List<AXF_OBJ_BillingDocumentWorkAllocation__c> newList,
    Map<Id, AXF_OBJ_BillingDocumentWorkAllocation__c> oldMap
  ) {
    ALT_CLS_BillingGuard.workAllocations(newList, oldMap, false);
  }

  public static void handleBeforeDelete(
    List<AXF_OBJ_BillingDocumentWorkAllocation__c> oldList,
    Map<Id, AXF_OBJ_BillingDocumentWorkAllocation__c> oldMap
  ) {
    ALT_CLS_BillingGuard.workAllocations(oldList, oldMap, true);
  }
}
