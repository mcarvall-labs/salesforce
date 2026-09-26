/**
 * @description Trigger handler of AXF_OBJ_BankInstitution__c (AXF-105 boundary): dispatches each context to
 * the production rule classes, unchanged. Bank institution normalization.
 */
public with sharing class AXF_CLS_BITriggerHandler {
  public static void handleBeforeInsert(
    List<AXF_OBJ_BankInstitution__c> newList
  ) {
    AXF_CLS_TH_BankInstitution.handleBeforeInsert(newList);
  }

  public static void handleBeforeUpdate(
    List<AXF_OBJ_BankInstitution__c> newList
  ) {
    AXF_CLS_TH_BankInstitution.handleBeforeUpdate(newList);
  }
}
