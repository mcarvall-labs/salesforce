/**
 * @description Handler de trigger para AXF_OBJ_ReviewItem__c (AXF-94).
 * Permite a resolucao/descarto apenas quando realizada pelo servico (ALT_CLS_ReviewQueueService),
 * que garante o expurgo dos valores anteriores (G7). Edicao direta sem o guard, re-transicao de
 * itens ja finais e delete sao bloqueados.
 */
public with sharing class AXF_CLS_ReviewQueueTriggerHandler {
  @TestVisible
  public static Boolean guardEnabled = false;

  private static final Set<String> FINAL_STATES = new Set<String>{
    ALT_CLS_ReviewQueueService.STATE_RESOLVED,
    ALT_CLS_ReviewQueueService.STATE_DISMISSED
  };

  public static void handleBeforeUpdate(
    List<AXF_OBJ_ReviewItem__c> newList,
    Map<Id, AXF_OBJ_ReviewItem__c> oldMap
  ) {
    if (guardEnabled == true) {
      return; // servico esta gerenciando a resolucao (expurgo garantido)
    }
    for (AXF_OBJ_ReviewItem__c rec : newList) {
      AXF_OBJ_ReviewItem__c old = oldMap.get(rec.Id);
      if (FINAL_STATES.contains(old.AXF_RVI_PKL_State__c)) {
        rec.addError(
          'Item de revisao resolvido/descartado e imutavel (AXF-94).'
        );
        continue;
      }
      if (rec.AXF_RVI_PKL_State__c != old.AXF_RVI_PKL_State__c) {
        rec.addError('Resolucao deve ser feita pelo servico (expurgo G7).');
      }
    }
  }

  public static void handleBeforeDelete(List<AXF_OBJ_ReviewItem__c> oldList) {
    for (AXF_OBJ_ReviewItem__c rec : oldList) {
      rec.addError('Item de revisao nao pode ser excluido (AXF-94).');
    }
  }
}
