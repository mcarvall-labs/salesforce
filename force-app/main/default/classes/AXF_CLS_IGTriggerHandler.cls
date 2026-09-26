/**
 * @description Trigger handler of AXF_OBJ_InstallmentGroup__c (AXF-105 boundary): dispatches each context to
 * the production rule classes, unchanged. SAC adjustment-rate changes.
 */
public with sharing class AXF_CLS_IGTriggerHandler {
  public static void handleAfterUpdate(
    List<AXF_OBJ_InstallmentGroup__c> newList,
    Map<Id, AXF_OBJ_InstallmentGroup__c> oldMap
  ) {
    ALT_CLS_SacFinancing.afterGroupRateChange(newList, oldMap);
  }
}
