/**
 * @description Handler de trigger para AXF_OBJ_FinancialSchedule__c (AXF-103).
 * Garante: (1) bloqueio de delete; (2) identidade e autoridade do titular congeladas depois de
 * ACTIVE, incluindo proibição de reparentar cronograma em uso; (3) transições de estado
 * somente DRAFT -> ACTIVE|ENDED e ACTIVE -> ENDED, com ENDED terminal; (4) versão monotônica;
 * (5) ACTIVE exige definição vigente do mesmo cronograma e, no método estimado, referência
 * vigente. Nenhuma regra é duplicada em Flow: o handler é a autoridade.
 */
public with sharing class AXF_CLS_FSCTriggerHandler {
  public static final String STATE_DRAFT = 'DRAFT';
  public static final String STATE_ACTIVE = 'ACTIVE';
  public static final String STATE_ENDED = 'ENDED';
  public static final String METHOD_ESTIMATED = 'ESTIMATED';

  /** Identidade e autoridade congeladas a partir de ACTIVE. */
  private static final Set<String> ACTIVE_FROZEN_FIELDS = new Set<String>{
    'AXF_FSC_EXI_ScheduleKey__c',
    'AXF_FSC_LKP_Account__c',
    'AXF_FSC_LKP_Contract__c',
    'AXF_FSC_TXT_CurrencyIsoCode__c',
    'AXF_FSC_PKL_Direction__c',
    'AXF_FSC_NUM_TrackingStartSequence__c'
  };

  /**
   * Campos mantidos apenas pelo serviço autorizado: identidade derivada, ponteiros vigentes,
   * contadores e cursores. Não são editáveis por comando direto — a plataforma não permite
   * expressar isso em FLS para campos obrigatórios, então a trava vive aqui.
   */
  private static final Set<String> SERVICE_MANAGED_FIELDS = new Set<String>{
    'AXF_FSC_EXI_ScheduleKey__c',
    'AXF_FSC_PKL_State__c',
    'AXF_FSC_NUM_Version__c',
    'AXF_FSC_LKP_ActiveDefinition__c',
    'AXF_FSC_LKP_ActiveReference__c',
    'AXF_FSC_NUM_CoverageSequence__c',
    'AXF_FSC_NUM_ProjectionRevision__c',
    'AXF_FSC_NUM_AppliedRevision__c',
    'AXF_FSC_NUM_FinancialVersion__c',
    'AXF_FSC_NUM_RefreshCursor__c',
    'AXF_FSC_BOL_GenerationEnabled__c',
    'AXF_FSC_DT_NextAttemptAt__c',
    'AXF_FSC_NUM_RetryCount__c',
    'AXF_FSC_TXT_LastErrorCode__c',
    // O encerramento efetivo é um comando versionado da fatia seguinte: enquanto ele não
    // existe, uma edição direta não pode cancelar obrigações elegíveis sem recibo nem revisão.
    'AXF_FSC_DAT_TerminationDate__c',
    // A janela materializada e o horizonte lido derivam deste campo; ele não pode mudar de
    // comportamento por DML direta.
    'AXF_FSC_NUM_HorizonMonths__c',
    // Participa da identidade do cronograma: se mudasse depois de ACTIVE, a chave gravada
    // deixaria de corresponder à recalculada.
    'AXF_FSC_TXT_LegacyGroupKey__c'
  };

  public static void handleBeforeInsert(
    List<AXF_OBJ_FinancialSchedule__c> newList
  ) {
    Set<Id> definitionIds = new Set<Id>();
    for (AXF_OBJ_FinancialSchedule__c record : newList) {
      if (
        record.AXF_FSC_PKL_State__c == STATE_ACTIVE &&
        record.AXF_FSC_LKP_ActiveDefinition__c != null
      ) {
        definitionIds.add(record.AXF_FSC_LKP_ActiveDefinition__c);
      }
    }
    Map<Id, AXF_OBJ_ScheduleDefinition__c> definitions = definitionIds.isEmpty()
      ? new Map<Id, AXF_OBJ_ScheduleDefinition__c>()
      : new Map<Id, AXF_OBJ_ScheduleDefinition__c>(
          [
            SELECT Id, AXF_SDF_LKP_Schedule__c, AXF_SDF_PKL_Method__c
            FROM AXF_OBJ_ScheduleDefinition__c
            WHERE Id IN :definitionIds
            WITH SYSTEM_MODE
          ]
        );

    for (AXF_OBJ_FinancialSchedule__c record : newList) {
      if (String.isBlank(record.AXF_FSC_EXI_ScheduleKey__c)) {
        record.addError('A chave determinística do cronograma é obrigatória.');
        continue;
      }
      if (record.AXF_FSC_LKP_Account__c == null) {
        record.addError('O titular do cronograma é obrigatório.');
        continue;
      }
      if (
        record.AXF_FSC_NUM_TrackingStartSequence__c == null ||
        record.AXF_FSC_NUM_TrackingStartSequence__c < 1
      ) {
        record.addError(
          'A sequência inicial de rastreamento deve ser maior ou igual a 1.'
        );
        continue;
      }
      if (String.isBlank(record.AXF_FSC_PKL_State__c)) {
        record.AXF_FSC_PKL_State__c = STATE_DRAFT;
      }
      if (record.AXF_FSC_PKL_State__c != STATE_ACTIVE) {
        continue;
      }
      // As invariantes de ACTIVE valem também na inserção: uma raiz ACTIVE inserida
      // diretamente não pode apontar definição ausente, alheia ou estimada sem referência.
      if (record.AXF_FSC_LKP_ActiveDefinition__c == null) {
        record.addError(
          'Um cronograma ACTIVE exige uma definição vigente do mesmo cronograma.'
        );
        continue;
      }
      AXF_OBJ_ScheduleDefinition__c definition = definitions.get(
        record.AXF_FSC_LKP_ActiveDefinition__c
      );
      if (definition == null) {
        record.addError(
          'Um cronograma ACTIVE exige uma definição vigente existente.'
        );
        continue;
      }
      if (definition.AXF_SDF_LKP_Schedule__c != record.Id) {
        record.addError(
          'A definição vigente deve pertencer ao mesmo cronograma.'
        );
        continue;
      }
      if (
        definition.AXF_SDF_PKL_Method__c == METHOD_ESTIMATED &&
        record.AXF_FSC_LKP_ActiveReference__c == null
      ) {
        record.addError(
          'Um cronograma estimado exige uma referência vigente; um método calculado pode omiti-la.'
        );
      }
    }
  }

  public static void handleBeforeUpdate(
    List<AXF_OBJ_FinancialSchedule__c> newList,
    Map<Id, AXF_OBJ_FinancialSchedule__c> oldMap
  ) {
    Set<Id> definitionIds = new Set<Id>();
    for (AXF_OBJ_FinancialSchedule__c record : newList) {
      if (
        record.AXF_FSC_PKL_State__c == STATE_ACTIVE &&
        record.AXF_FSC_LKP_ActiveDefinition__c != null
      ) {
        definitionIds.add(record.AXF_FSC_LKP_ActiveDefinition__c);
      }
    }
    Map<Id, AXF_OBJ_ScheduleDefinition__c> definitions = definitionIds.isEmpty()
      ? new Map<Id, AXF_OBJ_ScheduleDefinition__c>()
      : new Map<Id, AXF_OBJ_ScheduleDefinition__c>(
          [
            SELECT Id, AXF_SDF_LKP_Schedule__c, AXF_SDF_PKL_Method__c
            FROM AXF_OBJ_ScheduleDefinition__c
            WHERE Id IN :definitionIds
            WITH SYSTEM_MODE
          ]
        );

    for (AXF_OBJ_FinancialSchedule__c record : newList) {
      AXF_OBJ_FinancialSchedule__c oldRecord = oldMap.get(record.Id);
      // Uma atualização parcial não pode ser lida como alteração: só campos efetivamente
      // enviados participam das invariantes.
      Map<String, Object> populated = record.getPopulatedFieldsAsMap();

      if (!ALT_CLS_FinancialScheduleService.isWriting()) {
        for (String field : SERVICE_MANAGED_FIELDS) {
          if (
            populated.containsKey(field) &&
            isChanged(record.get(field), oldRecord.get(field))
          ) {
            record.addError(
              'Campos derivados do cronograma (identidade, estado, ponteiros, contadores e cursores) são mantidos pelo serviço autorizado e não são editáveis diretamente (AXF-103).'
            );
            break;
          }
        }
      }

      for (String field : ACTIVE_FROZEN_FIELDS) {
        if (
          populated.containsKey(field) &&
          isChanged(record.get(field), oldRecord.get(field)) &&
          oldRecord.AXF_FSC_PKL_State__c != STATE_DRAFT
        ) {
          record.addError(
            'Campo ' +
              field +
              ' é imutável depois de ACTIVE: identidade, titular, natureza e moeda não mudam, e cronograma em uso não é reparentado.'
          );
          break;
        }
      }

      String oldState = oldRecord.AXF_FSC_PKL_State__c;
      String newState = (record.AXF_FSC_PKL_State__c == null)
        ? oldState
        : record.AXF_FSC_PKL_State__c;
      if (!isAllowedTransition(oldState, newState)) {
        record.addError(
          'Transição de estado inválida: ' +
            oldState +
            ' -> ' +
            newState +
            '. Um cronograma encerrado não é reativado por edição comum.'
        );
      }

      if (
        populated.containsKey('AXF_FSC_NUM_Version__c') &&
        record.AXF_FSC_NUM_Version__c != null &&
        oldRecord.AXF_FSC_NUM_Version__c != null &&
        record.AXF_FSC_NUM_Version__c < oldRecord.AXF_FSC_NUM_Version__c
      ) {
        record.addError('A versão do cronograma é monotônica não decrescente.');
      }

      if (
        populated.containsKey('AXF_FSC_DAT_TerminationDate__c') &&
        oldRecord.AXF_FSC_DAT_TerminationDate__c != null &&
        record.AXF_FSC_DAT_TerminationDate__c == null
      ) {
        record.addError(
          'A data de encerramento não é apagada por uma edição comum.'
        );
      }

      Boolean activating =
        newState == STATE_ACTIVE &&
        (oldState != STATE_ACTIVE ||
        populated.containsKey('AXF_FSC_LKP_ActiveDefinition__c') ||
        populated.containsKey('AXF_FSC_LKP_ActiveReference__c'));
      if (!activating) {
        continue;
      }
      AXF_OBJ_ScheduleDefinition__c definition = definitions.get(
        record.AXF_FSC_LKP_ActiveDefinition__c
      );
      if (definition == null) {
        record.addError(
          'Um cronograma ACTIVE exige uma definição vigente existente.'
        );
        continue;
      }
      if (definition.AXF_SDF_LKP_Schedule__c != record.Id) {
        record.addError(
          'A definição vigente deve pertencer ao mesmo cronograma.'
        );
        continue;
      }
      if (
        definition.AXF_SDF_PKL_Method__c == METHOD_ESTIMATED &&
        record.AXF_FSC_LKP_ActiveReference__c == null
      ) {
        record.addError(
          'Um cronograma estimado exige uma referência vigente; um método calculado pode omiti-la.'
        );
      }
    }
  }

  public static void handleBeforeDelete(
    List<AXF_OBJ_FinancialSchedule__c> oldList
  ) {
    for (AXF_OBJ_FinancialSchedule__c record : oldList) {
      record.addError(
        'Cronogramas financeiros são imutáveis e não podem ser excluídos (AXF-103).'
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
    if (oldState == STATE_DRAFT || oldState == null) {
      return newState == STATE_ACTIVE || newState == STATE_ENDED;
    }
    if (oldState == STATE_ACTIVE) {
      return newState == STATE_ENDED;
    }
    return false; // ENDED é terminal nesta fundação.
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
