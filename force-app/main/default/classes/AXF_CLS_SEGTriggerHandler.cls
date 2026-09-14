/**
 * @description Handler de trigger para AXF_OBJ_SharedExpenseGrant__c (AXF-6).
 * Somente despacho de contexto; regras de integridade abaixo, sem consulta a outros objetos:
 * sem delete, identidade (lancamento + colaborador + chave) imutavel, status ACTIVE|REVOKED.
 */
public with sharing class AXF_CLS_SEGTriggerHandler {
  private static final Set<String> FROZEN = new Set<String>{
    'AXF_SEG_LKP_FinancialTransaction__c',
    'AXF_SEG_LKP_Collaborator__c',
    'AXF_SEG_EXI_GrantKey__c'
  };

  public static void handleBeforeInsert(
    List<AXF_OBJ_SharedExpenseGrant__c> newList
  ) {
    for (AXF_OBJ_SharedExpenseGrant__c grant : newList) {
      if (grant.AXF_SEG_LKP_Collaborator__c == null) {
        grant.addError('Colaborador e obrigatorio.');
        continue;
      }
      if (grant.AXF_SEG_PKL_Status__c == null) {
        grant.AXF_SEG_PKL_Status__c = ALT_CLS_SharedExpenseService.STATUS_ACTIVE;
      }
      if (grant.AXF_SEG_PKL_Permission__c == null) {
        grant.AXF_SEG_PKL_Permission__c = ALT_CLS_SharedExpenseService.PERMISSION_VIEW;
      }
    }
  }

  public static void handleBeforeUpdate(
    List<AXF_OBJ_SharedExpenseGrant__c> newList,
    Map<Id, AXF_OBJ_SharedExpenseGrant__c> oldMap
  ) {
    for (AXF_OBJ_SharedExpenseGrant__c grant : newList) {
      AXF_OBJ_SharedExpenseGrant__c before = oldMap.get(grant.Id);
      for (String field : FROZEN) {
        if (grant.get(field) != before.get(field)) {
          grant.addError(
            'A concessao de colaboracao e imutavel; revogue e conceda novamente.'
          );
          break;
        }
      }
    }
  }

  public static void handleBeforeDelete(
    List<AXF_OBJ_SharedExpenseGrant__c> oldList,
    Map<Id, AXF_OBJ_SharedExpenseGrant__c> oldMap
  ) {
    for (AXF_OBJ_SharedExpenseGrant__c grant : oldList) {
      grant.addError(
        'Concessoes de colaboracao nao sao excluidas; use a revogacao (AXF-6).'
      );
    }
  }
}
