/**
 * @description Handler de trigger para AXF_OBJ_WorkRecord__c (AXF-56).
 * Garante imutabilidade de registros APPROVED e SUPERSEDED e protecao contra exclusao direta (AC 2, AC 3).
 */
public with sharing class AXF_CLS_WorkRecordTriggerHandler {

  public static final String STATUS_DRAFT = 'DRAFT';
  public static final String STATUS_SUBMITTED = 'SUBMITTED';
  public static final String STATUS_APPROVED = 'APPROVED';
  public static final String STATUS_REJECTED = 'REJECTED';
  public static final String STATUS_SUPERSEDED = 'SUPERSEDED';

  public static void handleBeforeInsert(List<AXF_OBJ_WorkRecord__c> newList) {
    for (AXF_OBJ_WorkRecord__c wr : newList) {
      if (wr.AXF_WR_PKL_Status__c == null) {
        wr.AXF_WR_PKL_Status__c = STATUS_DRAFT;
      }
      if (wr.AXF_WR_NUM_Quantity__c != null && wr.AXF_WR_CUR_Rate__c != null) {
        wr.AXF_WR_CUR_TotalAmount__c = (wr.AXF_WR_NUM_Quantity__c * wr.AXF_WR_CUR_Rate__c).setScale(2, System.RoundingMode.HALF_UP);
      }
    }
  }

  public static void handleBeforeUpdate(List<AXF_OBJ_WorkRecord__c> newList, Map<Id, AXF_OBJ_WorkRecord__c> oldMap) {
    for (AXF_OBJ_WorkRecord__c newRecord : newList) {
      AXF_OBJ_WorkRecord__c oldRecord = oldMap.get(newRecord.Id);

      // Atualiza total caso quantidade ou taxa tenham mudado em status editavel
      if (newRecord.AXF_WR_NUM_Quantity__c != null && newRecord.AXF_WR_CUR_Rate__c != null) {
        newRecord.AXF_WR_CUR_TotalAmount__c = (newRecord.AXF_WR_NUM_Quantity__c * newRecord.AXF_WR_CUR_Rate__c).setScale(2, System.RoundingMode.HALF_UP);
      }

      // Se o registro estava SUPERSEDED, ele e imutavel
      if (oldRecord.AXF_WR_PKL_Status__c == STATUS_SUPERSEDED) {
        newRecord.addError('Registros de trabalho SUPERSEDED sao historicos e imutaveis (AXF-56).');
        continue;
      }

      // Se o registro estava APPROVED
      if (oldRecord.AXF_WR_PKL_Status__c == STATUS_APPROVED) {
        // Apenas transicao para SUPERSEDED e permitida (quando substituido por correcao)
        if (newRecord.AXF_WR_PKL_Status__c != STATUS_SUPERSEDED) {
          newRecord.addError('Registros de trabalho APPROVED sao auditaveis e imutaveis. Para correcao, reverta/substitua por um novo registro (AXF-56 AC 3).');
          continue;
        }

        // Se esta sendo promovido para SUPERSEDED, valores e evidencias essenciais nao podem ser modificados
        if (newRecord.AXF_WR_NUM_Quantity__c != oldRecord.AXF_WR_NUM_Quantity__c ||
            newRecord.AXF_WR_CUR_Rate__c != oldRecord.AXF_WR_CUR_Rate__c ||
            newRecord.AXF_WR_CUR_TotalAmount__c != oldRecord.AXF_WR_CUR_TotalAmount__c ||
            newRecord.AXF_WR_DAT_StartDate__c != oldRecord.AXF_WR_DAT_StartDate__c ||
            newRecord.AXF_WR_DAT_EndDate__c != oldRecord.AXF_WR_DAT_EndDate__c ||
            newRecord.AXF_WR_EXI_EvidenceHash__c != oldRecord.AXF_WR_EXI_EvidenceHash__c ||
            newRecord.AXF_WR_LKP_Contract__c != oldRecord.AXF_WR_LKP_Contract__c) {
          newRecord.addError('Nao e permitido alterar os dados originais ou de evidencia de um registro aprovado ao substitui-lo.');
        }
      }
    }
  }

  public static void handleBeforeDelete(List<AXF_OBJ_WorkRecord__c> oldList) {
    for (AXF_OBJ_WorkRecord__c record : oldList) {
      if (record.AXF_WR_PKL_Status__c == STATUS_APPROVED || record.AXF_WR_PKL_Status__c == STATUS_SUPERSEDED) {
        record.addError('Registros de trabalho com status ' + record.AXF_WR_PKL_Status__c + ' nao podem ser excluidos (AXF-56 AC 2, AC 3).');
      }
    }
  }
}
