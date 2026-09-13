/**
 * @description Handler de trigger para AXF_OBJ_ScheduleReference__c (AXF-103).
 * A referência recorrente é evidência imutável: nenhuma atualização é aceita e nenhuma
 * exclusão é permitida. O valor recorrente nunca é negativo — uma compensação identifica uma
 * referência retirada e precisa apontar a referência que neutraliza.
 */
public with sharing class AXF_CLS_SRFTriggerHandler {
  public static final String KIND_COMPENSATION = 'COMPENSATION';
  private static final Set<String> KINDS = new Set<String>{
    'INITIAL',
    'MANUAL',
    'REALIZATION',
    'COMPENSATION'
  };

  public static void handleBeforeInsert(
    List<AXF_OBJ_ScheduleReference__c> newList
  ) {
    for (AXF_OBJ_ScheduleReference__c record : newList) {
      if (String.isBlank(record.AXF_SRF_EXI_ReferenceKey__c)) {
        record.addError('A chave determinística da referência é obrigatória.');
        continue;
      }
      if (record.AXF_SRF_LKP_Schedule__c == null) {
        record.addError('A referência deve pertencer a um cronograma.');
        continue;
      }
      if (
        record.AXF_SRF_NUM_EconomicSequence__c == null ||
        record.AXF_SRF_NUM_EconomicSequence__c < 1
      ) {
        record.addError('A ordem econômica deve ser maior ou igual a 1.');
        continue;
      }
      if (
        record.AXF_SRF_NUM_EffectiveSequence__c == null ||
        record.AXF_SRF_NUM_EffectiveSequence__c < 1
      ) {
        record.addError('A sequência efetiva deve ser maior ou igual a 1.');
        continue;
      }
      if (
        record.AXF_SRF_NUM_RecurringAmount__c == null ||
        record.AXF_SRF_NUM_RecurringAmount__c < 0
      ) {
        record.addError(
          'O valor recorrente é obrigatório e nunca negativo: uma retirada é registrada como compensação, nunca como pagamento negativo.'
        );
        continue;
      }
      if (
        String.isBlank(record.AXF_SRF_PKL_Kind__c) ||
        !KINDS.contains(record.AXF_SRF_PKL_Kind__c)
      ) {
        record.addError(
          'Tipo de referência inválido: use INITIAL, MANUAL, REALIZATION ou COMPENSATION.'
        );
        continue;
      }
      if (
        record.AXF_SRF_PKL_Kind__c == KIND_COMPENSATION &&
        record.AXF_SRF_LKP_Compensates__c == null
      ) {
        record.addError(
          'Uma compensação deve identificar a referência retirada.'
        );
      }
    }
  }

  public static void handleBeforeUpdate(
    List<AXF_OBJ_ScheduleReference__c> newList,
    Map<Id, AXF_OBJ_ScheduleReference__c> oldMap
  ) {
    for (AXF_OBJ_ScheduleReference__c record : newList) {
      AXF_OBJ_ScheduleReference__c oldRecord = oldMap.get(record.Id);
      for (String field : record.getPopulatedFieldsAsMap().keySet()) {
        if (!field.endsWith('__c')) {
          continue;
        }
        if (isChanged(record.get(field), oldRecord.get(field))) {
          record.addError(
            'A referência de cronograma é evidência imutável; a substituição cria uma nova referência (AXF-103).'
          );
          break;
        }
      }
    }
  }

  public static void handleBeforeDelete(
    List<AXF_OBJ_ScheduleReference__c> oldList
  ) {
    for (AXF_OBJ_ScheduleReference__c record : oldList) {
      record.addError(
        'Referências de cronograma são evidência imutável e não podem ser excluídas (AXF-103).'
      );
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
}
