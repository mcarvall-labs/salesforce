/**
 * @description Handler de trigger para AXF_OBJ_BillingDocumentLine__c (AXF-65).
 * Somente despacho de contexto; regras em ALT_CLS_BillingGuard.lines.
 */
public with sharing class AXF_CLS_BDLTriggerHandler {
  public static void handleBeforeInsert(
    List<AXF_OBJ_BillingDocumentLine__c> newList
  ) {
    ALT_CLS_BillingGuard.lines(newList, null, false);
  }

  public static void handleBeforeUpdate(
    List<AXF_OBJ_BillingDocumentLine__c> newList,
    Map<Id, AXF_OBJ_BillingDocumentLine__c> oldMap
  ) {
    ALT_CLS_BillingGuard.lines(newList, oldMap, false);
  }

  public static void handleBeforeDelete(
    List<AXF_OBJ_BillingDocumentLine__c> oldList,
    Map<Id, AXF_OBJ_BillingDocumentLine__c> oldMap
  ) {
    ALT_CLS_BillingGuard.lines(oldList, oldMap, true);
  }
}
