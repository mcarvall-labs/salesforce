/**
 * @description Handler de trigger para AXF_OBJ_BillingDocument__c (AXF-65).
 * Somente despacho de contexto; regras em ALT_CLS_BillingGuard.documents.
 */
public with sharing class AXF_CLS_BDOTriggerHandler {
  public static void handleBeforeInsert(
    List<AXF_OBJ_BillingDocument__c> newList
  ) {
    ALT_CLS_BillingGuard.documents(newList, null, false);
  }

  public static void handleBeforeUpdate(
    List<AXF_OBJ_BillingDocument__c> newList,
    Map<Id, AXF_OBJ_BillingDocument__c> oldMap
  ) {
    ALT_CLS_BillingGuard.documents(newList, oldMap, false);
  }

  public static void handleBeforeDelete(
    List<AXF_OBJ_BillingDocument__c> oldList,
    Map<Id, AXF_OBJ_BillingDocument__c> oldMap
  ) {
    ALT_CLS_BillingGuard.documents(oldList, oldMap, true);
  }
}
