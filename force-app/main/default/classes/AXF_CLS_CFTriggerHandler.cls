/**
 * @description Trigger handler of AXF_OBJ_CashFlow__c (AXF-105 boundary): dispatches each context to
 * the production rule classes, unchanged. Reconciliation guards, then cash-flow rules.
 */
public with sharing class AXF_CLS_CFTriggerHandler {
  public static void handleBeforeInsert(List<AXF_OBJ_CashFlow__c> newList) {
    AXF_CLS_TH_Reconciliation.validateCashFlows(newList, null);
    AXF_CLS_TH_CashFlow.handleBeforeInsert(newList);
  }

  public static void handleBeforeUpdate(
    List<AXF_OBJ_CashFlow__c> newList,
    Map<Id, AXF_OBJ_CashFlow__c> oldMap
  ) {
    AXF_CLS_TH_Reconciliation.validateCashFlows(newList, oldMap);
    AXF_CLS_TH_CashFlow.handleBeforeUpdate(newList, oldMap);
  }

  public static void handleBeforeDelete(List<AXF_OBJ_CashFlow__c> oldList) {
    AXF_CLS_TH_Reconciliation.preventCashFlowDelete(oldList);
  }

  public static void handleAfterInsert(List<AXF_OBJ_CashFlow__c> newList) {
    AXF_CLS_TH_CashFlow.handleAfterInsert(newList);
  }

  public static void handleAfterUpdate(
    List<AXF_OBJ_CashFlow__c> newList,
    Map<Id, AXF_OBJ_CashFlow__c> oldMap
  ) {
    AXF_CLS_TH_CashFlow.handleAfterUpdate(newList, oldMap);
  }

  public static void handleAfterDelete(List<AXF_OBJ_CashFlow__c> oldList) {
    AXF_CLS_TH_CashFlow.handleAfterDelete(oldList);
  }
}
