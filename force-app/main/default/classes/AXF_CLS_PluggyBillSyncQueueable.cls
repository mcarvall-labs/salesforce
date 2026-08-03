public with sharing class AXF_CLS_PluggyBillSyncQueueable implements Queueable, Database.AllowsCallouts {

    private static final Integer MAX_CALLOUTS_PER_EXECUTION = 90;

    private List<AXF_OBJ_CreditCard__c> creditCardsToProcess;

    public AXF_CLS_PluggyBillSyncQueueable(List<AXF_OBJ_CreditCard__c> creditCards) {
        this.creditCardsToProcess = creditCards;
    }

    public void execute(QueueableContext context) {
        if (creditCardsToProcess.isEmpty()) {
            return;
        }

        Integer batchSize = Math.min(creditCardsToProcess.size(), MAX_CALLOUTS_PER_EXECUTION);
        List<AXF_OBJ_CreditCard__c> currentBatch = new List<AXF_OBJ_CreditCard__c>();
        List<AXF_OBJ_CreditCard__c> remaining = new List<AXF_OBJ_CreditCard__c>();

        for (Integer i = 0; i < creditCardsToProcess.size(); i++) {
            if (i < batchSize) {
                currentBatch.add(creditCardsToProcess[i]);
            } else {
                remaining.add(creditCardsToProcess[i]);
            }
        }

        String apiKey = AXF_CLS_PluggyAuthService.getValidApiKey();
        List<AXF_OBJ_CreditCardInvoice__c> invoicesToUpsert = new List<AXF_OBJ_CreditCardInvoice__c>();

        for (AXF_OBJ_CreditCard__c card : currentBatch) {
            try {
                invoicesToUpsert.addAll(
                    AXF_CLS_PluggyBillSync_Service.fetchBillsForCreditCard(
                        card.Id,
                        card.AXF_CC_EXI_PluggyCreditCardId__c,
                        apiKey
                    )
                );
            } catch (Exception e) {
                // Falha ao buscar faturas de um cartão não deve interromper os demais.
            }
        }

        AXF_CLS_PluggyBillSync_Service.upsertBills(invoicesToUpsert);

        if (!remaining.isEmpty() && !Test.isRunningTest()) {
            System.enqueueJob(new AXF_CLS_PluggyBillSyncQueueable(remaining));
        }
    }
}