/**
 * @description Trigger handler of AXF_OBJ_CreditCard__c: standardized record name (production parity).
 */
public with sharing class AXF_CLS_CCTriggerHandler {
  public static void handleBeforeInsert(List<AXF_OBJ_CreditCard__c> newList) {
    new ALT_CLS_SourceNaming().nameCreditCards(newList);
  }

  public static void handleBeforeUpdate(
    List<AXF_OBJ_CreditCard__c> newList,
    Map<Id, AXF_OBJ_CreditCard__c> oldMap
  ) {
    new ALT_CLS_SourceNaming().nameCreditCards(newList);
  }
}
