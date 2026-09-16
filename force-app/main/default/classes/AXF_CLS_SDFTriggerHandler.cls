/**
 * @description Handler de trigger para AXF_OBJ_ScheduleDefinition__c (AXF-103).
 * A definição é evidência imutável: nenhuma atualização é aceita e nenhuma exclusão é
 * permitida. Substituir uma definição cria uma revisão maior; a história efetiva nunca é
 * mutada. A revisão é única e monotônica dentro do cronograma.
 */
public with sharing class AXF_CLS_SDFTriggerHandler {
  private static final Set<String> METHODS = new Set<String>{
    'RECURRING',
    'INSTALLMENT',
    'PRICE',
    'SAC',
    'ESTIMATED'
  };

  public static void handleBeforeInsert(
    List<AXF_OBJ_ScheduleDefinition__c> newList
  ) {
    Set<Id> scheduleIds = new Set<Id>();
    for (AXF_OBJ_ScheduleDefinition__c record : newList) {
      if (record.AXF_SDF_LKP_Schedule__c != null) {
        scheduleIds.add(record.AXF_SDF_LKP_Schedule__c);
      }
    }
    Map<Id, Set<String>> existingRevisions = new Map<Id, Set<String>>();
    Map<Id, Decimal> highestRevision = new Map<Id, Decimal>();
    if (!scheduleIds.isEmpty()) {
      for (AXF_OBJ_ScheduleDefinition__c row : [
        SELECT AXF_SDF_LKP_Schedule__c, AXF_SDF_NUM_Revision__c
        FROM AXF_OBJ_ScheduleDefinition__c
        WHERE AXF_SDF_LKP_Schedule__c IN :scheduleIds
        WITH SYSTEM_MODE
      ]) {
        Id scheduleId = row.AXF_SDF_LKP_Schedule__c;
        Set<String> revisions = existingRevisions.get(scheduleId);
        if (revisions == null) {
          revisions = new Set<String>();
          existingRevisions.put(scheduleId, revisions);
        }
        revisions.add(String.valueOf(row.AXF_SDF_NUM_Revision__c));
        Decimal highest = highestRevision.get(scheduleId);
        if (
          highest == null ||
          (row.AXF_SDF_NUM_Revision__c != null &&
          row.AXF_SDF_NUM_Revision__c > highest)
        ) {
          highestRevision.put(scheduleId, row.AXF_SDF_NUM_Revision__c);
        }
      }
    }

    for (AXF_OBJ_ScheduleDefinition__c record : newList) {
      if (String.isBlank(record.AXF_SDF_EXI_DefinitionKey__c)) {
        record.addError('A chave determinística da definição é obrigatória.');
        continue;
      }
      if (record.AXF_SDF_LKP_Schedule__c == null) {
        record.addError('A definição deve pertencer a um cronograma.');
        continue;
      }
      if (
        record.AXF_SDF_NUM_Revision__c == null ||
        record.AXF_SDF_NUM_Revision__c < 1
      ) {
        record.addError('A revisão da definição deve ser maior ou igual a 1.');
        continue;
      }
      if (
        record.AXF_SDF_NUM_EffectiveSequence__c == null ||
        record.AXF_SDF_NUM_EffectiveSequence__c < 1
      ) {
        record.addError('A sequência efetiva deve ser maior ou igual a 1.');
        continue;
      }
      if (
        record.AXF_SDF_NUM_FirstSequence__c == null ||
        record.AXF_SDF_NUM_FirstSequence__c < 1
      ) {
        record.addError('A sequência inicial deve ser maior ou igual a 1.');
        continue;
      }
      if (record.AXF_SDF_DAT_FirstDueDate__c == null) {
        record.addError('O primeiro vencimento é obrigatório.');
        continue;
      }
      if (
        String.isBlank(record.AXF_SDF_PKL_Method__c) ||
        !METHODS.contains(record.AXF_SDF_PKL_Method__c)
      ) {
        record.addError(
          'Método inválido: use RECURRING, INSTALLMENT, PRICE, SAC ou ESTIMATED.'
        );
        continue;
      }
      if (
        record.AXF_SDF_NUM_PeriodMonths__c == null ||
        record.AXF_SDF_NUM_PeriodMonths__c < 1
      ) {
        record.addError('A periodicidade deve ser de pelo menos 1 mês.');
        continue;
      }
      if (
        record.AXF_SDF_NUM_AnchorDay__c == null ||
        record.AXF_SDF_NUM_AnchorDay__c < 1 ||
        record.AXF_SDF_NUM_AnchorDay__c > 31
      ) {
        record.addError('O dia âncora deve estar entre 1 e 31.');
        continue;
      }
      if (
        record.AXF_SDF_NUM_TotalInstallments__c != null &&
        record.AXF_SDF_NUM_TotalInstallments__c < 1
      ) {
        record.addError('O total de parcelas deve ser maior ou igual a 1.');
        continue;
      }
      if (
        record.AXF_SDF_PKL_Method__c != 'ESTIMATED' &&
        record.AXF_SDF_NUM_TotalInstallments__c == null
      ) {
        record.addError(
          'Total de parcelas é obrigatório fora de recorrência indefinida estimada.'
        );
        continue;
      }

      Id scheduleId = record.AXF_SDF_LKP_Schedule__c;
      Set<String> revisions = existingRevisions.get(scheduleId);
      String key = String.valueOf(record.AXF_SDF_NUM_Revision__c);
      if (revisions != null && revisions.contains(key)) {
        record.addError(
          'A revisão ' +
            key +
            ' já existe neste cronograma. Substituir cria uma revisão maior.'
        );
        continue;
      }
      Decimal highest = highestRevision.get(scheduleId);
      if (highest != null && record.AXF_SDF_NUM_Revision__c <= highest) {
        record.addError(
          'A revisão da definição é monotônica dentro do cronograma: a nova revisão deve ser maior que a vigente.'
        );
        continue;
      }
      if (revisions == null) {
        revisions = new Set<String>();
        existingRevisions.put(scheduleId, revisions);
      }
      revisions.add(key);
      highestRevision.put(scheduleId, record.AXF_SDF_NUM_Revision__c);
    }
  }

  public static void handleBeforeUpdate(
    List<AXF_OBJ_ScheduleDefinition__c> newList,
    Map<Id, AXF_OBJ_ScheduleDefinition__c> oldMap
  ) {
    for (AXF_OBJ_ScheduleDefinition__c record : newList) {
      AXF_OBJ_ScheduleDefinition__c oldRecord = oldMap.get(record.Id);
      for (String field : record.getPopulatedFieldsAsMap().keySet()) {
        if (!field.endsWith('__c') || field == 'Id') {
          continue;
        }
        if (isChanged(record.get(field), oldRecord.get(field))) {
          record.addError(
            'A definição do cronograma é evidência imutável; substituir cria uma revisão maior (AXF-103).'
          );
          break;
        }
      }
    }
  }

  public static void handleBeforeDelete(
    List<AXF_OBJ_ScheduleDefinition__c> oldList
  ) {
    for (AXF_OBJ_ScheduleDefinition__c record : oldList) {
      record.addError(
        'Definições de cronograma são evidência imutável e não podem ser excluídas (AXF-103).'
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
