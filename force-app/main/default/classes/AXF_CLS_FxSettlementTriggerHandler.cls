/**
 * @description Handler de trigger para AXF_OBJ_FxSettlement__c (AXF-59).
 * Garante: bloqueio de delete; nenhuma edicao de registros CONFIRMED/CORRECTION/REVERSAL
 * (correcao/estorno usam novos registros em stories posteriores).
 */
public with sharing class AXF_CLS_FxSettlementTriggerHandler {
  public static void handleBeforeDelete(List<AXF_OBJ_FxSettlement__c> oldList) {
    for (AXF_OBJ_FxSettlement__c record : oldList) {
      record.addError(
        'FxSettlement nao pode ser excluida (AXF-59; correcao/estorno usa novos registros).'
      );
    }
  }

  public static void handleBeforeUpdate(
    List<AXF_OBJ_FxSettlement__c> newList,
    Map<Id, AXF_OBJ_FxSettlement__c> oldMap
  ) {
    for (AXF_OBJ_FxSettlement__c record : newList) {
      AXF_OBJ_FxSettlement__c oldRecord = oldMap.get(record.Id);
      String oldState = oldRecord.AXF_FXT_PKL_State__c;
      if (
        oldState == 'CONFIRMED' ||
        oldState == 'CORRECTION' ||
        oldState == 'REVERSAL'
      ) {
        record.addError(
          'Liquidacoes ' +
            oldState +
            ' sao imutaveis; correcao/estorno usa novo registro (AXF-59/63).'
        );
      }
    }
  }
}
