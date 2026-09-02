/**
 * @description Subscriber for AXF_PluggyWebhookEvent__e. A verified inbound Pluggy webhook
 * (AXF_CLS_PluggyWebhookResource, running as the Site guest user) publishes one event per
 * notification; this trigger runs the consent/state revalidation OUT of the guest context
 * — it executes as the Automated Process user, which carries AXF_PS_PluggyIntegration
 * (External Credential principal access + AXF_OBJ_PluggyConnection__c write). AXF-11 / G4-3.
 */
trigger AXF_TRG_PluggyWebhookEvent on AXF_PluggyWebhookEvent__e(after insert) {
  AXF_CLS_PluggyWebhookEventHandler.handle(Trigger.new);
}
