/**
 * @description Handler de trigger para AXF_OBJ_ContractScheduleRun__c (AXF-55).
 * Garante: (1) bloqueio de delete; (2) imutabilidade dos vínculos/identidade/horizonte apos
 * criacao; (3) transicoes de estado somente via servico (PREVIEW -> APPLYING -> COMPLETE|FAILED,
 * FAILED -> APPLYING); (4) token de escopo ativo liberado apenas ao concluir.
 */
public with sharing class AXF_CLS_CSRTriggerHandler {
  private static final Set<String> IMMUTABLE_FIELDS = new Set<String>{
    'AXF_CSR_LKP_Contract__c',
    'AXF_CSR_LKP_TermVersion__c',
    'AXF_CSR_EXI_OccurrenceKey__c',
    'AXF_CSR_EXI_InputHash__c',
    'AXF_CSR_TXT_CorrelationId__c',
    'AXF_CSR_DAT_HorizonFrom__c',
    'AXF_CSR_DAT_HorizonThrough__c'
  };

  public static void handleBeforeInsert(
    List<AXF_OBJ_ContractScheduleRun__c> newList
  ) {
    for (AXF_OBJ_ContractScheduleRun__c record : newList) {
      if (record.AXF_CSR_PKL_State__c == null) {
        record.AXF_CSR_PKL_State__c = ALT_CLS_ContractAgendaService.STATE_PREVIEW;
      }
    }
  }

  public static void handleBeforeUpdate(
    List<AXF_OBJ_ContractScheduleRun__c> newList,
    Map<Id, AXF_OBJ_ContractScheduleRun__c> oldMap
  ) {
    for (AXF_OBJ_ContractScheduleRun__c record : newList) {
      AXF_OBJ_ContractScheduleRun__c oldRecord = oldMap.get(record.Id);

      for (String field : IMMUTABLE_FIELDS) {
        if (isChanged(record.get(field), oldRecord.get(field))) {
          record.addError(
            'Campo imutavel ' + field + ' nao pode ser alterado (AXF-55).'
          );
          break;
        }
      }

      String oldState = oldRecord.AXF_CSR_PKL_State__c;
      String newState = record.AXF_CSR_PKL_State__c;
      if (!isAllowedTransition(oldState, newState)) {
        record.addError(
          'Transicao de estado invalida: ' + oldState + ' -> ' + newState + '.'
        );
      }
    }
  }

  public static void handleBeforeDelete(
    List<AXF_OBJ_ContractScheduleRun__c> oldList
  ) {
    for (AXF_OBJ_ContractScheduleRun__c record : oldList) {
      record.addError(
        'ContractScheduleRun e imutavel e nao pode ser excluido (AXF-55).'
      );
    }
  }

  private static Boolean isAllowedTransition(String oldState, String newState) {
    if (oldState == newState) {
      return true;
    }
    if (newState == null) {
      return false;
    }
    if (oldState == 'PREVIEW') {
      return newState == 'APPLYING' || newState == 'FAILED' || newState == 'COMPLETE';
    }
    if (oldState == 'APPLYING') {
      return newState == 'COMPLETE' || newState == 'FAILED';
    }
    if (oldState == 'FAILED') {
      return newState == 'APPLYING';
    }
    return false; // COMPLETE e terminal
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
