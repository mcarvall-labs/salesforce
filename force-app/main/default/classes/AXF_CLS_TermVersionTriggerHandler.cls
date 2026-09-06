/**
 * @description Handler de trigger para AXF_OBJ_ContractTermVersion__c (AXF-53).
 * Garante imutabilidade estrita de termos ACTIVE e SUPERSEDED e protecao contra delecao (AC 2, AD-31).
 */
public with sharing class AXF_CLS_TermVersionTriggerHandler {

  public static void handleBeforeUpdate(List<AXF_OBJ_ContractTermVersion__c> newList, Map<Id, AXF_OBJ_ContractTermVersion__c> oldMap) {
    for (AXF_OBJ_ContractTermVersion__c newRecord : newList) {
      AXF_OBJ_ContractTermVersion__c oldRecord = oldMap.get(newRecord.Id);

      // Se o registro estava SUPERSEDED, ele e historico e 100% imutavel
      if (oldRecord.AXF_CTV_PKL_Status__c == ALT_CLS_ContractRemunerationService.STATUS_SUPERSEDED) {
        newRecord.addError('Termos com status SUPERSEDED sao historicos e estritamente imutaveis (AD-31).');
        continue;
      }

      // Se o registro estava ACTIVE
      if (oldRecord.AXF_CTV_PKL_Status__c == ALT_CLS_ContractRemunerationService.STATUS_ACTIVE) {
        // A unica transicao permitida para um termo ACTIVE e para SUPERSEDED (ao ser sucedido)
        if (newRecord.AXF_CTV_PKL_Status__c != ALT_CLS_ContractRemunerationService.STATUS_SUPERSEDED) {
          newRecord.addError('Termos com status ACTIVE sao imutaveis e nao podem ser alterados diretamente (AD-31).');
          continue;
        }

        // Se esta sendo promovido para SUPERSEDED, as condicoes financeiras e modelo nao podem mudar
        if (newRecord.AXF_CTV_PKL_RemunerationModel__c != oldRecord.AXF_CTV_PKL_RemunerationModel__c ||
            newRecord.AXF_CTV_TXT_CurrencyIsoCode__c != oldRecord.AXF_CTV_TXT_CurrencyIsoCode__c ||
            newRecord.AXF_CTV_DAT_EffectiveFrom__c != oldRecord.AXF_CTV_DAT_EffectiveFrom__c ||
            newRecord.AXF_CTV_CUR_Rate__c != oldRecord.AXF_CTV_CUR_Rate__c ||
            newRecord.AXF_CTV_CUR_ContractedAmount__c != oldRecord.AXF_CTV_CUR_ContractedAmount__c ||
            newRecord.AXF_CTV_NUM_HoursQuantity__c != oldRecord.AXF_CTV_NUM_HoursQuantity__c ||
            newRecord.AXF_CTV_NUM_Installments__c != oldRecord.AXF_CTV_NUM_Installments__c) {
          newRecord.addError('Condicoes financeiras e parametros de termos vigentes sao imutaveis ao serem sucedidos.');
        }
      }
    }
  }

  public static void handleBeforeDelete(List<AXF_OBJ_ContractTermVersion__c> oldList) {
    for (AXF_OBJ_ContractTermVersion__c record : oldList) {
      if (record.AXF_CTV_PKL_Status__c == ALT_CLS_ContractRemunerationService.STATUS_ACTIVE ||
          record.AXF_CTV_PKL_Status__c == ALT_CLS_ContractRemunerationService.STATUS_SUPERSEDED) {
        record.addError('Termos com status ' + record.AXF_CTV_PKL_Status__c + ' sao autoritativos e nao podem ser excluidos (AC 2, AD-31).');
      }
    }
  }
}