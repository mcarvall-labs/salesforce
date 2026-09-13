/**
 * @description Handler de trigger para AXF_OBJ_ScheduleChange__c (AXF-103).
 * O recibo é imutável e delimitado por OperationKey: nenhuma atualização é aceita, nenhuma
 * exclusão é permitida. Nesta fatia apenas CREATE é gravado pelo serviço; uma operação
 * revertida não deixa recibo.
 */
public with sharing class AXF_CLS_SCHTriggerHandler {
  public static final String OPERATION_CREATE = 'CREATE';
  private static final Set<String> SCOPES = new Set<String>{
    'ONE',
    'FROM_SEQUENCE',
    'ALL_TRACKED'
  };

  public static void handleBeforeInsert(
    List<AXF_OBJ_ScheduleChange__c> newList
  ) {
    for (AXF_OBJ_ScheduleChange__c record : newList) {
      // O recibo é EVIDÊNCIA do serviço, não um registro de usuário. Criar em
      // AXF_OBJ_ScheduleChange__c é concedido a Gestor e a entrada financeira: sem esta guarda,
      // qualquer um deles insere um recibo arbitrário (Operation, Scope e ResultJson
      // inventados) e o recibo deixa de ser prova da operação. Mesmo mecanismo de contexto
      // autorizado usado em FSC/SDF/SRF.
      if (!ALT_CLS_FinancialScheduleService.isWriting()) {
        record.addError(
          'O recibo de alteração do cronograma é gravado pelo serviço autorizado e não é criado por DML direta (AXF-103).'
        );
        continue;
      }
      if (String.isBlank(record.AXF_SCH_EXI_OperationKey__c)) {
        record.addError('A chave da operação é obrigatória.');
        continue;
      }
      if (String.isBlank(record.AXF_SCH_TXT_PayloadHash__c)) {
        record.addError('O hash do payload é obrigatório.');
        continue;
      }
      if (record.AXF_SCH_LKP_Schedule__c == null) {
        record.addError('O recibo deve apontar o cronograma alterado.');
        continue;
      }
      if (
        record.AXF_SCH_NUM_Revision__c == null ||
        record.AXF_SCH_NUM_Revision__c < 1
      ) {
        record.addError('A revisão do recibo deve ser maior ou igual a 1.');
        continue;
      }
      if (
        String.isBlank(record.AXF_SCH_PKL_Scope__c) ||
        !SCOPES.contains(record.AXF_SCH_PKL_Scope__c)
      ) {
        record.addError(
          'Escopo inválido: use ONE, FROM_SEQUENCE ou ALL_TRACKED.'
        );
        continue;
      }
      if (
        record.AXF_SCH_PKL_Operation__c == OPERATION_CREATE &&
        record.AXF_SCH_NUM_FromSequence__c == null
      ) {
        record.addError(
          'O recibo de criação registra a sequência inicial de rastreamento.'
        );
        continue;
      }
      if (record.AXF_SCH_LKP_Actor__c == null) {
        record.AXF_SCH_LKP_Actor__c = UserInfo.getUserId();
      }
      if (record.AXF_SCH_DT_CommittedAt__c == null) {
        record.AXF_SCH_DT_CommittedAt__c = System.now();
      }
    }
  }

  public static void handleBeforeUpdate(
    List<AXF_OBJ_ScheduleChange__c> newList,
    Map<Id, AXF_OBJ_ScheduleChange__c> oldMap
  ) {
    for (AXF_OBJ_ScheduleChange__c record : newList) {
      AXF_OBJ_ScheduleChange__c oldRecord = oldMap.get(record.Id);
      for (String field : record.getPopulatedFieldsAsMap().keySet()) {
        if (!field.endsWith('__c')) {
          continue;
        }
        if (isChanged(record.get(field), oldRecord.get(field))) {
          record.addError(
            'O recibo de alteração é imutável: um recibo não é reescrito depois de confirmado (AXF-103).'
          );
          break;
        }
      }
    }
  }

  public static void handleBeforeDelete(
    List<AXF_OBJ_ScheduleChange__c> oldList
  ) {
    for (AXF_OBJ_ScheduleChange__c record : oldList) {
      record.addError(
        'Recibos de alteração de cronograma não podem ser excluídos (AXF-103).'
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
