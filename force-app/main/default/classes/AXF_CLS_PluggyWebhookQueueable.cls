/**
 * @description Runs the fetch a verified Pluggy webhook triggers. For AXF-11 the fetch is a
 * consent/state revalidation of the affected connection (G4-5). Full transaction/account
 * sync driven by webhooks belongs to AXF-12; this keeps AXF-11 self-contained and idempotent
 * (revalidation can run any number of times with the same effect).
 */
public with sharing class AXF_CLS_PluggyWebhookQueueable implements Queueable, Database.AllowsCallouts {
  private final String pluggyItemId;

  public AXF_CLS_PluggyWebhookQueueable(String pluggyItemId) {
    this.pluggyItemId = pluggyItemId;
  }

  public void execute(QueueableContext context) {
    if (String.isBlank(pluggyItemId)) {
      return;
    }
    new AXF_CLS_PluggyConsentService().refreshByItemId(pluggyItemId);
  }
}
