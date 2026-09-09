/** @description Protects review evidence, typed references, terminal decisions and retention. */
public with sharing class AXF_CLS_ReviewQueueTriggerHandler {
  @TestVisible
  public static Boolean guardEnabled = false;

  private static final Set<String> FINAL_STATES = new Set<String>{
    ALT_CLS_ReviewQueueService.STATE_RESOLVED,
    ALT_CLS_ReviewQueueService.STATE_DISMISSED
  };

  /** @description Only the authorized producer may create review evidence. */
  public static void handleBeforeInsert(List<AXF_OBJ_ReviewItem__c> rows) {
    if (!guardEnabled) {
      for (AXF_OBJ_ReviewItem__c row : rows)
        row.addError('Review creation must use the authorized service.');
    }
  }

  public static void handleBeforeUpdate(
    List<AXF_OBJ_ReviewItem__c> newList,
    Map<Id, AXF_OBJ_ReviewItem__c> oldMap
  ) {
    for (AXF_OBJ_ReviewItem__c rec : newList) {
      AXF_OBJ_ReviewItem__c old = oldMap.get(rec.Id);
      if (FINAL_STATES.contains(old.AXF_RVI_PKL_State__c)) {
        rec.addError(
          'Item de revisao resolvido/descartado e imutavel (AXF-94).'
        );
        continue;
      }
      for (String field : rec.getPopulatedFieldsAsMap().keySet()) {
        String lower = field.toLowerCase();
        if (
          lower.startsWith('axf_rvi_') &&
          !new Set<String>{
              'axf_rvi_pkl_state__c',
              'axf_rvi_num_version__c',
              'axf_rvi_lkp_resolvedbyuser__c',
              'axf_rvi_dt_resolvedat__c',
              'axf_rvi_tal_resolutionnote__c'
            }
            .contains(lower) &&
          rec.get(field) != old.get(field)
        ) {
          rec.addError('Review references and evidence are immutable.');
          break;
        }
      }
      if (!guardEnabled) {
        rec.addError('Review decisions must use the authorized service.');
      }
    }
  }

  public static void handleBeforeDelete(List<AXF_OBJ_ReviewItem__c> oldList) {
    for (AXF_OBJ_ReviewItem__c rec : oldList) {
      rec.addError('Item de revisao nao pode ser excluido (AXF-94).');
    }
  }
}
