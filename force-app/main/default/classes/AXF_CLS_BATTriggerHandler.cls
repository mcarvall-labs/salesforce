/**
 * @description Trigger handler of AXF_OBJ_BankAccountTransaction__c (AXF-105 boundary): dispatches each context to
 * the production rule classes, unchanged. Reconciliation link guards.
 */
public with sharing class AXF_CLS_BATTriggerHandler {
  public static void handleBeforeInsert(
    List<AXF_OBJ_BankAccountTransaction__c> newList
  ) {
    AXF_CLS_TH_Reconciliation.validateBanks(newList, null);
  }

  public static void handleBeforeUpdate(
    List<AXF_OBJ_BankAccountTransaction__c> newList,
    Map<Id, AXF_OBJ_BankAccountTransaction__c> oldMap
  ) {
    AXF_CLS_TH_Reconciliation.validateBanks(newList, oldMap);
  }

  public static void handleBeforeDelete(
    List<AXF_OBJ_BankAccountTransaction__c> oldList
  ) {
    AXF_CLS_TH_Reconciliation.preventBankDelete(oldList);
  }
}
