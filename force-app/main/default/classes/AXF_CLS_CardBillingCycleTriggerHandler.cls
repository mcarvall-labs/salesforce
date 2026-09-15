/**
 * @description Handler de trigger para AXF_OBJ_CardBillingCycleRule__c (AXF-35).
 * Garante: regras ACTIVE e SUPERSEDED sao imutaveis por edicao direta (somente o servico ativa/
 * substitui atomicamente); sem Delete de regra (G2); protege contra exclusao em cascata indevida.
 */
public with sharing class AXF_CLS_CardBillingCycleTriggerHandler {
  public static void handleBeforeUpdate(
    List<AXF_OBJ_CardBillingCycleRule__c> newList,
    Map<Id, AXF_OBJ_CardBillingCycleRule__c> oldMap
  ) {
    for (AXF_OBJ_CardBillingCycleRule__c rec : newList) {
      AXF_OBJ_CardBillingCycleRule__c old = oldMap.get(rec.Id);
      String oldState = old.AXF_CBR_PKL_State__c;
      String newState = rec.AXF_CBR_PKL_State__c;

      if (oldState == ALT_CLS_CardBillingCycleService.STATE_SUPERSEDED) {
        rec.addError('Regras SUPERSEDED sao historicas e imutaveis (AXF-35).');
        continue;
      }
      // Em ACTIVE, a unica transicao direta permitida e para SUPERSEDED (ao ser substituido
      // por uma regra nova). Conteudo (vigencia/dias/fuso/policy) nao pode mudar.
      if (oldState == ALT_CLS_CardBillingCycleService.STATE_ACTIVE) {
        if (
          newState != null &&
          newState != ALT_CLS_CardBillingCycleService.STATE_SUPERSEDED
        ) {
          rec.addError(
            'Regras ACTIVE nao podem ser alteradas diretamente; ative uma regra nova (AXF-35).'
          );
          continue;
        }
        if (changedFinancial(rec, old)) {
          rec.addError(
            'Regras ACTIVE sao imutaveis; substitua por uma nova regra de ciclo.'
          );
        }
      }
    }
  }

  public static void handleBeforeDelete(
    List<AXF_OBJ_CardBillingCycleRule__c> oldList
  ) {
    for (AXF_OBJ_CardBillingCycleRule__c rec : oldList) {
      rec.addError(
        'Regra de ciclo do cartao nao pode ser excluida (AXF-35, G2).'
      );
    }
  }

  private static Boolean changedFinancial(
    AXF_OBJ_CardBillingCycleRule__c rec,
    AXF_OBJ_CardBillingCycleRule__c old
  ) {
    return rec.AXF_CBR_DAT_EffectiveFrom__c !=
      old.AXF_CBR_DAT_EffectiveFrom__c ||
      rec.AXF_CBR_DAT_EffectiveTo__c != old.AXF_CBR_DAT_EffectiveTo__c ||
      rec.AXF_CBR_TXT_TimeZone__c != old.AXF_CBR_TXT_TimeZone__c ||
      rec.AXF_CBR_NUM_ClosingDay__c != old.AXF_CBR_NUM_ClosingDay__c ||
      rec.AXF_CBR_PKL_ClosingDayAdjustment__c !=
      old.AXF_CBR_PKL_ClosingDayAdjustment__c ||
      rec.AXF_CBR_NUM_DueDayOffset__c != old.AXF_CBR_NUM_DueDayOffset__c ||
      rec.AXF_CBR_PKL_DueDayAdjustment__c !=
      old.AXF_CBR_PKL_DueDayAdjustment__c ||
      rec.AXF_CBR_TXT_CalendarPolicyVersion__c !=
      old.AXF_CBR_TXT_CalendarPolicyVersion__c;
  }
}
