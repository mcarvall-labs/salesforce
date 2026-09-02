/**
 * @description Handles AXF_PluggyWebhookEvent__e. One event is published per verified
 * inbound Pluggy webhook (AXF_CLS_PluggyWebhookResource). For AXF-11 the reaction is a
 * consent/state revalidation of the affected connection (G4-5) — the payload itself is
 * never written as a fact. Full transaction/account sync driven by webhooks is AXF-12;
 * this keeps AXF-11 self-contained.
 *
 * Runs as the Automated Process user (platform event trigger context), which must carry
 * AXF_PS_PluggyIntegration so the callout + AXF_OBJ_PluggyConnection__c update succeed.
 * Assigning that permission set to the Automated Process user is a manual install step.
 *
 * Idempotent: revalidation can run any number of times with the same effect, so an event
 * replay is safe. A transient integration failure (unknown result / transport) asks the
 * event bus to redeliver the batch; a terminal outcome is swallowed — the periodic sweep
 * in AXF-12 is the backstop for anything missed here.
 */
public with sharing class AXF_CLS_PluggyWebhookEventHandler {
  public static void handle(List<AXF_PluggyWebhookEvent__e> events) {
    // Configuration is deliberately evaluated here, in the Automated Process context,
    // never by the public Site guest user.
    if (!AXF_CLS_PluggySettings.webhookEnabled()) {
      return;
    }
    Set<String> observedItemIds = new Set<String>();
    for (AXF_PluggyWebhookEvent__e evt : events) {
      if (String.isNotBlank(evt.AXF_PWE_TXT_ObservedItemId__c)) {
        observedItemIds.add(evt.AXF_PWE_TXT_ObservedItemId__c);
      }
    }
    if (observedItemIds.isEmpty()) {
      return;
    }
    try {
      // Bulk: every callout runs before the single DML, so a multi-event batch never
      // trips a callout-after-DML.
      new AXF_CLS_PluggyConsentService().refreshByItemIds(observedItemIds);
    } catch (AXF_CLS_PluggyIntegrationException transientFailure) {
      // Unknown / transport failure: let the platform redeliver this batch.
      throw new EventBus.RetryableException(transientFailure.getMessage());
    } catch (Exception terminal) {
      // Terminal (e.g. connection not visible): nothing to retry. AXF-12's periodic
      // sweep reconciles anything a lost webhook would have missed.
    }
  }
}
