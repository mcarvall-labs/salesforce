/**
 * @description Trigger handler of AXF_OBJ_CreditCardTransaction__c (AXF-105 boundary): dispatches each context to
 * the production rule classes, unchanged. Reconciliation link guards.
 */
public with sharing class AXF_CLS_CCTTriggerHandler {
  public static void handleBeforeInsert(
    List<AXF_OBJ_CreditCardTransaction__c> newList
  ) {
    AXF_CLS_TH_Reconciliation.validateCards(newList, null);
  }

  public static void handleBeforeUpdate(
    List<AXF_OBJ_CreditCardTransaction__c> newList,
    Map<Id, AXF_OBJ_CreditCardTransaction__c> oldMap
  ) {
    AXF_CLS_TH_Reconciliation.validateCards(newList, oldMap);
  }

  public static void handleBeforeDelete(
    List<AXF_OBJ_CreditCardTransaction__c> oldList
  ) {
    AXF_CLS_TH_Reconciliation.preventCardDelete(oldList);
  }
}
