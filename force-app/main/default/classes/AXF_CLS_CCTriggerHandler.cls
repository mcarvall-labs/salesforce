/**
 * @description Trigger handler of AXF_OBJ_CreditCard__c (AXF-105 boundary): dispatches each context to
 * the production rule classes, unchanged. Standardized record name.
 */
public with sharing class AXF_CLS_CCTriggerHandler {
  public static void handleBeforeInsert(List<AXF_OBJ_CreditCard__c> newList) {
    AXF_CLS_TH_AccountCardNaming.handleCreditCards(newList);
  }

  public static void handleBeforeUpdate(List<AXF_OBJ_CreditCard__c> newList) {
    AXF_CLS_TH_AccountCardNaming.handleCreditCards(newList);
  }
}
