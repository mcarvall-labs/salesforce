/**
 * @description Handler de trigger para AXF_OBJ_ClosureRun__c (AXF-119). Somente despacho de
 * contexto e integridade local: sem delete, escopo/correlacao imutaveis, CLOSED terminal.
 */
public with sharing class AXF_CLS_CLRTriggerHandler {
  private static final Set<String> FROZEN = new Set<String>{
    'AXF_CLR_LKP_Account__c',
    'AXF_CLR_EXI_ScopeKey__c',
    'AXF_CLR_TXT_CorrelationId__c'
  };

  public static void handleBeforeInsert(List<AXF_OBJ_ClosureRun__c> newList) {
    for (AXF_OBJ_ClosureRun__c run : newList) {
      if (run.AXF_CLR_PKL_Status__c == null) {
        run.AXF_CLR_PKL_Status__c = 'REQUESTED';
      }
      if (run.AXF_CLR_PKL_Stage__c == null) {
        run.AXF_CLR_PKL_Stage__c = 'NONE';
      }
      if (run.AXF_CLR_PKL_Status__c == 'CLOSED') {
        run.addError('Um encerramento nao nasce CLOSED.');
      }
    }
  }

  public static void handleBeforeUpdate(
    List<AXF_OBJ_ClosureRun__c> newList,
    Map<Id, AXF_OBJ_ClosureRun__c> oldMap
  ) {
    for (AXF_OBJ_ClosureRun__c run : newList) {
      AXF_OBJ_ClosureRun__c before = oldMap.get(run.Id);
      for (String field : FROZEN) {
        if (run.get(field) != before.get(field)) {
          run.addError('Escopo e correlacao do encerramento sao imutaveis.');
          break;
        }
      }
      if (
        before.AXF_CLR_PKL_Status__c == 'CLOSED' &&
        run.AXF_CLR_PKL_Status__c != 'CLOSED'
      ) {
        run.addError('CLOSED e terminal (AXF-119).');
      }
    }
  }

  public static void handleBeforeDelete(
    List<AXF_OBJ_ClosureRun__c> oldList,
    Map<Id, AXF_OBJ_ClosureRun__c> oldMap
  ) {
    for (AXF_OBJ_ClosureRun__c run : oldList) {
      run.addError(
        'Encerramentos nao sao excluidos: sao evidencia minima do lifecycle.'
      );
    }
  }
}
