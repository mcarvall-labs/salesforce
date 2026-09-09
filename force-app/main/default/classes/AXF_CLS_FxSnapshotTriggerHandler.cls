/**
 * @description Handler de trigger para AXF_OBJ_FxApplicationSnapshot__c (AXF-24).
 * Imutabilidade: sem delete; conteudo congelado; transicao ACTIVE -> SUPERSEDED via servico.
 */
public with sharing class AXF_CLS_FxSnapshotTriggerHandler {
  private static final Set<String> MUTABLE_IN_ACTIVE = new Set<String>{
    'AXF_FXS_PKL_State__c',
    'AXF_FXS_NUM_Version__c'
  };

  public static void handleBeforeUpdate(
    List<AXF_OBJ_FxApplicationSnapshot__c> newList,
    Map<Id, AXF_OBJ_FxApplicationSnapshot__c> oldMap
  ) {
    for (AXF_OBJ_FxApplicationSnapshot__c record : newList) {
      AXF_OBJ_FxApplicationSnapshot__c oldRecord = oldMap.get(record.Id);
      if (oldRecord.AXF_FXS_PKL_State__c == 'SUPERSEDED') {
        record.addError('Snapshots SUPERSEDED sao historicos e imutaveis.');
        continue;
      }
      Map<String, Object> oldFields = oldRecord.getPopulatedFieldsAsMap();
      for (String field : record.getPopulatedFieldsAsMap().keySet()) {
        if (!isChanged(record.get(field), oldFields.get(field))) {
          continue;
        }
        if (!MUTABLE_IN_ACTIVE.contains(field)) {
          record.addError(
            'Campo ' + field + ' imutavel em snapshot FX (AXF-24).'
          );
          break;
        }
        if (
          field == 'AXF_FXS_PKL_State__c' &&
          record.AXF_FXS_PKL_State__c != 'SUPERSEDED'
        ) {
          record.addError(
            'Transicao de estado invalida (ACTIVE -> SUPERSEDED).'
          );
          break;
        }
      }
    }
  }

  public static void handleBeforeDelete(
    List<AXF_OBJ_FxApplicationSnapshot__c> oldList
  ) {
    for (AXF_OBJ_FxApplicationSnapshot__c record : oldList) {
      record.addError(
        'FxApplicationSnapshot e imutavel e nao pode ser excluido (AXF-24).'
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
