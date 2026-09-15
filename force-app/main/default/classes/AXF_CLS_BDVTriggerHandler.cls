/**
 * @description Handler de trigger para AXF_OBJ_BillingDocumentVersion__c (AXF-65).
 * Somente despacho de contexto; regras em ALT_CLS_BillingGuard.versions.
 */
public with sharing class AXF_CLS_BDVTriggerHandler {
  public static void handleBeforeInsert(
    List<AXF_OBJ_BillingDocumentVersion__c> newList
  ) {
    ALT_CLS_BillingGuard.versions(newList, null, false);
  }

  public static void handleBeforeUpdate(
    List<AXF_OBJ_BillingDocumentVersion__c> newList,
    Map<Id, AXF_OBJ_BillingDocumentVersion__c> oldMap
  ) {
    ALT_CLS_BillingGuard.versions(newList, oldMap, false);
  }

  public static void handleBeforeDelete(
    List<AXF_OBJ_BillingDocumentVersion__c> oldList,
    Map<Id, AXF_OBJ_BillingDocumentVersion__c> oldMap
  ) {
    ALT_CLS_BillingGuard.versions(oldList, oldMap, true);
  }
}
