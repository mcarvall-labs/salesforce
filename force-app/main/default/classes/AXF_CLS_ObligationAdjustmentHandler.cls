/**
 * @description Handler de trigger para AXF_OBJ_ObligationAdjustment__c (AXF-104).
 * O ajuste é evidência não monetária imutável: só a capacidade autorizada do serviço de
 * obrigação pode inserir, nenhuma atualização é aceita e nenhuma exclusão é permitida.
 * Nenhuma regra vive no trigger: tudo delega aqui.
 */
public with sharing class AXF_CLS_ObligationAdjustmentHandler {
  public static void handleBeforeInsert(
    List<AXF_OBJ_ObligationAdjustment__c> newList
  ) {
    Boolean allowed = ALT_CLS_ObligationService.isWriting();
    for (AXF_OBJ_ObligationAdjustment__c record : newList) {
      if (!allowed) {
        record.addError(
          'Use o serviço de obrigação. Ajustes são evidência não monetária imutável e não podem ser inseridos diretamente (AXF-104).'
        );
        continue;
      }
      if (
        record.AXF_OAD_NUM_SignedAmount__c == null ||
        record.AXF_OAD_NUM_SignedAmount__c == 0
      ) {
        record.addError(
          'O valor com sinal é obrigatório e nunca zero: um delta zero é um recebimento sem ajuste (AXF-104).'
        );
        continue;
      }
      if (
        record.AXF_OAD_LKP_FinancialTransaction__c == null ||
        record.AXF_OAD_LKP_SettlementDecision__c == null
      ) {
        record.addError(
          'O ajuste deve pertencer a uma ocorrência e à decisão que o originou (AXF-104).'
        );
        continue;
      }
      if (
        String.isBlank(record.AXF_OAD_TXT_CurrencyIsoCode__c) ||
        String.isBlank(record.AXF_OAD_PKL_Kind__c) ||
        String.isBlank(record.AXF_OAD_PKL_Reason__c)
      ) {
        record.addError(
          'Moeda, tipo e motivo do ajuste são obrigatórios (AXF-104).'
        );
        continue;
      }
      if (record.AXF_OAD_PKL_Kind__c == 'COMPENSATION') {
        if (record.AXF_OAD_LKP_OriginalAdjustment__c == null) {
          record.addError(
            'Uma compensação deve identificar o ajuste neutralizado (AXF-104).'
          );
        }
        continue;
      }
      if (record.AXF_OAD_LKP_OriginalAdjustment__c != null) {
        record.addError(
          'Só uma compensação aponta o ajuste original (AXF-104).'
        );
      }
    }
  }

  public static void handleBeforeUpdate(
    List<AXF_OBJ_ObligationAdjustment__c> newList,
    Map<Id, AXF_OBJ_ObligationAdjustment__c> oldMap
  ) {
    for (AXF_OBJ_ObligationAdjustment__c record : newList) {
      record.addError(
        'Ajustes de obrigação são evidência imutável; a correção cria um novo ajuste (AXF-104).'
      );
    }
  }

  public static void handleBeforeDelete(
    List<AXF_OBJ_ObligationAdjustment__c> oldList
  ) {
    for (AXF_OBJ_ObligationAdjustment__c record : oldList) {
      record.addError(
        'Ajustes de obrigação são evidência imutável e não podem ser excluídos (AXF-104).'
      );
    }
  }
}
