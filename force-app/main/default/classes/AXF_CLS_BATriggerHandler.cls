/**
 * @description Trigger handler of AXF_OBJ_BankAccount__c: standardized record name (production parity).
 */
public with sharing class AXF_CLS_BATriggerHandler {
  public static void handleBeforeInsert(List<AXF_OBJ_BankAccount__c> newList) {
    new ALT_CLS_SourceNaming().nameBankAccounts(newList);
  }

  public static void handleBeforeUpdate(
    List<AXF_OBJ_BankAccount__c> newList,
    Map<Id, AXF_OBJ_BankAccount__c> oldMap
  ) {
    new ALT_CLS_SourceNaming().nameBankAccounts(newList);
  }
}
