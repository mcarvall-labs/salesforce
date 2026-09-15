/**
 * @description Handler de trigger para AXF_OBJ_SharedExpenseGrant__c (AXF-6).
 * Regras de integridade, sem consulta a outros objetos: concessoes nascem e mudam apenas pelo
 * servico (versao, idempotencia e notificacao vivem la); sem delete (evidencia de acesso e
 * conservada; o lookup ao lancamento e Restrict por decisao); identidade (lancamento +
 * colaborador + chave derivada) imutavel; status ACTIVE|REVOKED coerente com RevokedAt/RevokedBy
 * e toda mudanca de status/permissao avanca a versao.
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
      if (!ALT_CLS_SharedExpenseService.isWriting()) {
        grant.addError('Use o servico de despesa compartilhada (AXF-6).');
        continue;
      }
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
      if (grant.AXF_SEG_NUM_Version__c == null) {
        grant.AXF_SEG_NUM_Version__c = 1;
      }
      // Identity is derived, never supplied.
      grant.AXF_SEG_EXI_GrantKey__c =
        String.valueOf(grant.AXF_SEG_LKP_FinancialTransaction__c) +
        ':' +
        String.valueOf(grant.AXF_SEG_LKP_Collaborator__c);
    }
  }

  public static void handleBeforeUpdate(
    List<AXF_OBJ_SharedExpenseGrant__c> newList,
    Map<Id, AXF_OBJ_SharedExpenseGrant__c> oldMap
  ) {
    for (AXF_OBJ_SharedExpenseGrant__c grant : newList) {
      AXF_OBJ_SharedExpenseGrant__c before = oldMap.get(grant.Id);
      if (!ALT_CLS_SharedExpenseService.isWriting()) {
        grant.addError('Use o servico de despesa compartilhada (AXF-6).');
        continue;
      }
      Boolean frozenChanged = false;
      for (String field : FROZEN) {
        // Case-sensitive: the key is a case-sensitive external id.
        if (
          !String.valueOf(grant.get(field))
            .equals(String.valueOf(before.get(field)))
        ) {
          frozenChanged = true;
        }
      }
      if (frozenChanged) {
        grant.addError(
          'A concessao de colaboracao e imutavel; revogue e conceda novamente.'
        );
        continue;
      }
      if (
        grant.AXF_SEG_PKL_Status__c ==
        ALT_CLS_SharedExpenseService.STATUS_ACTIVE &&
        (grant.AXF_SEG_DT_RevokedAt__c != null ||
        grant.AXF_SEG_LKP_RevokedBy__c != null)
      ) {
        grant.addError('Concessao ativa nao carrega dados de revogacao.');
        continue;
      }
      if (
        grant.AXF_SEG_PKL_Status__c ==
        ALT_CLS_SharedExpenseService.STATUS_REVOKED &&
        grant.AXF_SEG_DT_RevokedAt__c == null
      ) {
        grant.addError('Revogacao exige data de revogacao.');
        continue;
      }
      if (
        grant.AXF_SEG_PKL_Status__c != before.AXF_SEG_PKL_Status__c ||
        grant.AXF_SEG_PKL_Permission__c != before.AXF_SEG_PKL_Permission__c
      ) {
        if (grant.AXF_SEG_NUM_Version__c == before.AXF_SEG_NUM_Version__c) {
          grant.addError('Mudanca de status ou permissao exige nova versao.');
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
