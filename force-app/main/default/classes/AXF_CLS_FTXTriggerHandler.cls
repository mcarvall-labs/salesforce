/**
 * @description Handler de trigger para AXF_OBJ_FinancialTransaction__c (AXF-25 / AXF-105).
 * Somente despacho de contexto: papel financeiro (PlanKind) atribuido apenas pelo servico de realizacao e imutabilidade do lancamento referenciado permanecem em ALT_CLS_RealizationGuard.originals.
 */
public with sharing class AXF_CLS_FTXTriggerHandler {
  public static void handleBeforeInsert(
    List<AXF_OBJ_FinancialTransaction__c> newList
  ) {
    ALT_CLS_RealizationGuard.originals(newList, null, false);
  }

  public static void handleBeforeUpdate(
    List<AXF_OBJ_FinancialTransaction__c> newList,
    Map<Id, AXF_OBJ_FinancialTransaction__c> oldMap
  ) {
    ALT_CLS_RealizationGuard.originals(newList, oldMap, false);
  }

  public static void handleBeforeDelete(
    List<AXF_OBJ_FinancialTransaction__c> oldList,
    Map<Id, AXF_OBJ_FinancialTransaction__c> oldMap
  ) {
    ALT_CLS_RealizationGuard.originals(oldList, oldMap, true);
  }
}
