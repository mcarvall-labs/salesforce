/**
 * @description Handler de trigger para AXF_OBJ_SettlementDecision__c (AXF-104).
 * A decisão é a operação tipada e o recibo imutável de repetição. Só a capacidade autorizada
 * do serviço de obrigação pode inserir; a única atualização admitida é a conclusão do
 * resultado do próprio comando, ainda dentro da transação. Nenhuma exclusão é permitida.
 * Nenhuma regra vive no trigger: tudo delega aqui.
 */
public with sharing class AXF_CLS_SettlementDecisionHandler {
  private static final Set<String> COMPLETION_FIELDS = new Set<String>{
    'AXF_SDC_TAL_ResultJson__c'
  };
  private static final Set<String> OPERATIONS = new Set<String>{
    'APPLY',
    'CLASSIFY',
    'REVERSE',
    'AMEND_OBLIGATION'
  };
  private static final Set<String> CLASSIFICATIONS = new Set<String>{
    'EXPLAINED',
    'UNCLASSIFIED',
    'NOT_APPLICABLE'
  };

  public static void handleBeforeInsert(
    List<AXF_OBJ_SettlementDecision__c> newList
  ) {
    Boolean allowed = ALT_CLS_ObligationService.isWriting();
    for (AXF_OBJ_SettlementDecision__c record : newList) {
      if (!allowed) {
        record.addError(
          'Use o serviço de obrigação. A decisão de liquidação é o recibo imutável da operação e não pode ser inserida diretamente (AXF-104).'
        );
        continue;
      }
      if (String.isBlank(record.AXF_SDC_EXI_DecisionKey__c)) {
        record.addError('A chave determinística da decisão é obrigatória.');
        continue;
      }
      if (record.AXF_SDC_LKP_FinancialTransaction__c == null) {
        record.addError(
          'A decisão deve pertencer a uma ocorrência financeira.'
        );
        continue;
      }
      if (
        String.isBlank(record.AXF_SDC_PKL_Operation__c) ||
        !OPERATIONS.contains(record.AXF_SDC_PKL_Operation__c)
      ) {
        record.addError(
          'Operação inválida: use APPLY, CLASSIFY, REVERSE ou AMEND_OBLIGATION (AXF-104).'
        );
        continue;
      }
      if (
        String.isBlank(record.AXF_SDC_PKL_Classification__c) ||
        !CLASSIFICATIONS.contains(record.AXF_SDC_PKL_Classification__c)
      ) {
        record.addError(
          'Classificação inválida: use EXPLAINED, UNCLASSIFIED ou NOT_APPLICABLE (AXF-104).'
        );
        continue;
      }
      if (record.AXF_SDC_DAT_EconomicDate__c == null) {
        record.addError('A data econômica da decisão é obrigatória.');
        continue;
      }
      if (
        record.AXF_SDC_LKP_Actor__c == null ||
        record.AXF_SDC_DT_CommittedAt__c == null
      ) {
        record.addError('O ator e o instante de confirmação são obrigatórios.');
        continue;
      }
      // O modo descreve a parcela INTEIRA: existe na aplicação de caixa e na classificação
      // posterior de uma parcela já liquidada. AMEND_OBLIGATION e REVERSE não propõem
      // obrigação resultante a partir de um pagamento.
      if (
        record.AXF_SDC_PKL_Operation__c != 'APPLY' &&
        record.AXF_SDC_PKL_Operation__c != 'CLASSIFY' &&
        record.AXF_SDC_PKL_Mode__c != null
      ) {
        record.addError(
          'O modo PARTIAL/FULL pertence apenas às operações APPLY e CLASSIFY (AXF-104).'
        );
        continue;
      }
      if (record.AXF_SDC_PKL_Classification__c != 'EXPLAINED') {
        if (
          record.AXF_SDC_NUM_RecurringAmount__c != null ||
          record.AXF_SDC_NUM_ExceptionalCharges__c != null ||
          record.AXF_SDC_NUM_OneOffDiscount__c != null
        ) {
          record.addError(
            'Componentes só existem numa classificação EXPLAINED; ausência nunca é zero presumido (AXF-104).'
          );
        }
        continue;
      }
      if (
        record.AXF_SDC_NUM_RecurringAmount__c == null ||
        record.AXF_SDC_NUM_ExceptionalCharges__c == null ||
        record.AXF_SDC_NUM_OneOffDiscount__c == null
      ) {
        record.addError(
          'Uma classificação completa exige explicitamente valor recorrente, encargos excepcionais e desconto pontual (AXF-104).'
        );
        continue;
      }
      if (
        record.AXF_SDC_NUM_RecurringAmount__c < 0 ||
        record.AXF_SDC_NUM_ExceptionalCharges__c < 0 ||
        record.AXF_SDC_NUM_OneOffDiscount__c < 0
      ) {
        record.addError(
          'Todos os componentes da parcela inteira são não negativos (AXF-104).'
        );
        continue;
      }
      if (
        record.AXF_SDC_NUM_RecurringAmount__c +
        record.AXF_SDC_NUM_ExceptionalCharges__c -
        record.AXF_SDC_NUM_OneOffDiscount__c !=
        record.AXF_SDC_NUM_EffectiveObligation__c
      ) {
        record.addError(
          'Recorrente + encargos excepcionais - desconto pontual deve ser igual à obrigação efetiva liquidada (AXF-104).'
        );
        continue;
      }
      if (
        record.AXF_SDC_TXT_CoverageHash__c == null ||
        record.AXF_SDC_NUM_CoverageCount__c == null
      ) {
        record.addError(
          'Uma classificação completa exige a cobertura exata das contribuições (AXF-104).'
        );
      }
    }
  }

  public static void handleBeforeUpdate(
    List<AXF_OBJ_SettlementDecision__c> newList,
    Map<Id, AXF_OBJ_SettlementDecision__c> oldMap
  ) {
    for (AXF_OBJ_SettlementDecision__c record : newList) {
      AXF_OBJ_SettlementDecision__c before = oldMap.get(record.Id);
      for (String field : record.getPopulatedFieldsAsMap().keySet()) {
        if (!field.endsWith('__c') || COMPLETION_FIELDS.contains(field)) {
          continue;
        }
        if (!isChanged(record.get(field), before.get(field))) {
          continue;
        }
        record.addError(
          'A decisão de liquidação é o recibo imutável da operação; a correção cria uma decisão nova (AXF-104).'
        );
        break;
      }
    }
  }

  private static Boolean isChanged(Object newValue, Object oldValue) {
    if (newValue == null && oldValue == null) {
      return false;
    }
    if (newValue == null || oldValue == null) {
      return true;
    }
    return String.valueOf(newValue) != String.valueOf(oldValue);
  }

  public static void handleBeforeDelete(
    List<AXF_OBJ_SettlementDecision__c> oldList
  ) {
    for (AXF_OBJ_SettlementDecision__c record : oldList) {
      record.addError(
        'Decisões de liquidação são o recibo imutável da operação e não podem ser excluídas (AXF-104).'
      );
    }
  }
}
