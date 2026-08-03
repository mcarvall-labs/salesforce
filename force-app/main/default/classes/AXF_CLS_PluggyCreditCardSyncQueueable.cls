/**
 * @description Queueable class to synchronize Credit Card bills and transactions sequentially.
 * Uses SyncPhase state chaining to execute bills fetch and transactions fetch in separate transactions,
 * avoiding the Salesforce "You have uncommitted work pending" callout exception.
 */
public with sharing class AXF_CLS_PluggyCreditCardSyncQueueable implements Queueable, Database.AllowsCallouts {

    public enum SyncPhase { BILLS, TRANSACTIONS }

    private List<AXF_OBJ_CreditCard__c> creditCardsToProcess;
    private SyncPhase phase;
    private String resumeAccountId;
    private String resumeCursor;
    private Integer retryAttempt = 0;

    private static final Integer BATCH_SIZE = 30; // Safe limit to avoid hitting 100 callouts limit
    private static final Integer BASE_BACKOFF_SECONDS = 15;
    private static final Integer MAX_BACKOFF_SECONDS = 300;
    private static final Integer DEFAULT_LOOKBACK_DAYS = 90; // Used on first sync (no prior successful run recorded)

    /**
     * @description Default constructor querying all active credit cards with a valid Pluggy ID, starting with BILLS phase.
     */
    public AXF_CLS_PluggyCreditCardSyncQueueable() {
        this([
            SELECT Id
            FROM AXF_OBJ_CreditCard__c
            WHERE AXF_CC_EXI_PluggyCreditCardId__c != null
        ], SyncPhase.BILLS);
    }

    /**
     * @description Constructor accepting a specific list of credit cards to synchronize, starting with BILLS phase.
     * @param creditCards List of credit card records to process.
     */
    public AXF_CLS_PluggyCreditCardSyncQueueable(List<AXF_OBJ_CreditCard__c> creditCards) {
        this(creditCards, SyncPhase.BILLS);
    }

    /**
     * @description Constructor accepting a specific list of credit cards and the sync phase.
     * @param creditCards List of credit card records to process.
     * @param phase The sync phase (BILLS or TRANSACTIONS) to execute.
     */
    public AXF_CLS_PluggyCreditCardSyncQueueable(List<AXF_OBJ_CreditCard__c> creditCards, SyncPhase phase) {
        this.creditCardsToProcess = creditCards;
        this.phase = phase;
    }

    /**
     * @description Constructor used to resume the TRANSACTIONS phase after a Pluggy API rate limit (HTTP 429)
     * response, restarting the affected card from the cursor where it was interrupted.
     * @param creditCards Cards still pending, starting with the one that was rate limited.
     * @param phase The sync phase to resume in (always TRANSACTIONS for rate limit retries).
     * @param resumeAccountId Pluggy credit card Id that should resume from resumeCursor instead of starting fresh.
     * @param resumeCursor Cursor to resume pagination from for resumeAccountId.
     * @param retryAttempt Number of consecutive rate limit retries so far, used for exponential backoff.
     */
    public AXF_CLS_PluggyCreditCardSyncQueueable(List<AXF_OBJ_CreditCard__c> creditCards, SyncPhase phase, String resumeAccountId, String resumeCursor, Integer retryAttempt) {
        this.creditCardsToProcess = creditCards;
        this.phase = phase;
        this.resumeAccountId = resumeAccountId;
        this.resumeCursor = resumeCursor;
        this.retryAttempt = retryAttempt;
    }

    /**
     * @description Execute method that performs the callout/DML logic depending on the current phase.
     */
    public void execute(QueueableContext context) {
        if (creditCardsToProcess == null || creditCardsToProcess.isEmpty()) {
            return;
        }

        // Query the necessary fields for the credit cards to process
        List<AXF_OBJ_CreditCard__c> cardsToSync = [
            SELECT Id, AXF_CC_EXI_PluggyCreditCardId__c, AXF_CC_LKP_PluggyConnection__c, AXF_CC_LKP_PluggyConnection__r.AXF_CON_EXI_PluggyItemId__c,
                   AXF_CC_DT_LastTransactionSync__c
            FROM AXF_OBJ_CreditCard__c
            WHERE Id IN :creditCardsToProcess
            AND AXF_CC_EXI_PluggyCreditCardId__c != null
        ];

        if (cardsToSync.isEmpty()) {
            return;
        }

        Integer batchSize = Math.min(cardsToSync.size(), BATCH_SIZE);
        List<AXF_OBJ_CreditCard__c> currentBatch = new List<AXF_OBJ_CreditCard__c>();
        List<AXF_OBJ_CreditCard__c> remaining = new List<AXF_OBJ_CreditCard__c>();

        for (Integer i = 0; i < cardsToSync.size(); i++) {
            if (i < batchSize) {
                currentBatch.add(cardsToSync[i]);
            } else {
                remaining.add(cardsToSync[i]);
            }
        }

        String apiKey = AXF_CLS_PluggyAuthService.getValidApiKey();

        if (this.phase == SyncPhase.BILLS) {
            // PHASE 1: Sync and Upsert Bills (Invoices)
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
                    // Failures for a specific card should not block others
                }
            }

            if (!invoicesToUpsert.isEmpty()) {
                AXF_CLS_PluggyBillSync_Service.upsertBills(invoicesToUpsert);
            }

            // Chain transition to next step
            if (!Test.isRunningTest()) {
                if (!remaining.isEmpty()) {
                    // Continue in BILLS phase for remaining cards
                    System.enqueueJob(new AXF_CLS_PluggyCreditCardSyncQueueable(remaining, SyncPhase.BILLS));
                } else {
                    // All bills for all cards have been upserted. Now run TRANSACTIONS phase.
                    System.enqueueJob(new AXF_CLS_PluggyCreditCardSyncQueueable(cardsToSync, SyncPhase.TRANSACTIONS));
                }
            }

        } else if (this.phase == SyncPhase.TRANSACTIONS) {
            // PHASE 2: Sync and Upsert Credit Card Transactions using the Account-level method
            AXF_CLS_PluggyTxSync_Service.TransactionSyncResult txResult = new AXF_CLS_PluggyTxSync_Service.TransactionSyncResult();
            List<AXF_OBJ_CreditCard__c> syncedCards = new List<AXF_OBJ_CreditCard__c>();
            Date today = Date.today();

            for (Integer i = 0; i < currentBatch.size(); i++) {
                AXF_OBJ_CreditCard__c card = currentBatch[i];

                try {
                    if (card.AXF_CC_LKP_PluggyConnection__c != null) {
                        String cursorForThisCard = (resumeCursor != null && card.Id == resumeAccountId) ? resumeCursor : null;
                        // Incremental sync: dateFrom = last successful sync (or a 90-day lookback on first
                        // sync), so the nightly job only re-fetches the delta instead of the whole history.
                        Date dateFrom = card.AXF_CC_DT_LastTransactionSync__c != null
                            ? card.AXF_CC_DT_LastTransactionSync__c.date()
                            : today.addDays(-DEFAULT_LOOKBACK_DAYS);

                        AXF_CLS_PluggyTxSync_Service.TransactionSyncResult cardTxResult =
                            AXF_CLS_PluggyTxSync_Service.fetchTransactionsForConnection(
                                card.AXF_CC_LKP_PluggyConnection__r.AXF_CON_EXI_PluggyItemId__c,
                                apiKey,
                                card.AXF_CC_EXI_PluggyCreditCardId__c,
                                cursorForThisCard,
                                dateFrom,
                                today
                            );
                        txResult.creditCardTransactions.addAll(cardTxResult.creditCardTransactions);

                        // Only mark as fully synced when pagination for this card completed without
                        // being interrupted by a rate limit / governor limit exception.
                        syncedCards.add(new AXF_OBJ_CreditCard__c(
                            Id = card.Id,
                            AXF_CC_DT_LastTransactionSync__c = Datetime.now()
                        ));
                    }
                } catch (AXF_CLS_PluggyTxSync_Service.RateLimitException rle) {
                    // Never throw-and-discard: merge in whatever pages were already fetched for THIS card
                    // before the interruption, then upsert everything fetched so far before rescheduling.
                    if (rle.partialResult != null) {
                        txResult.creditCardTransactions.addAll(rle.partialResult.creditCardTransactions);
                    }
                    if (!txResult.creditCardTransactions.isEmpty()) {
                        AXF_CLS_PluggyTxSync_Service.upsertTransactions(txResult);
                    }
                    if (!syncedCards.isEmpty()) {
                        update syncedCards;
                    }
                    rescheduleFromRateLimit(currentBatch, remaining, i, card.Id, rle);
                    return;
                } catch (Exception e) {
                    // Failures for a specific card should not block others
                }
            }

            if (!txResult.creditCardTransactions.isEmpty()) {
                AXF_CLS_PluggyTxSync_Service.upsertTransactions(txResult);
            }

            if (!syncedCards.isEmpty()) {
                update syncedCards;
            }

            // Chain next execution if there are remaining cards in TRANSACTIONS phase
            if (!remaining.isEmpty() && !Test.isRunningTest()) {
                System.enqueueJob(new AXF_CLS_PluggyCreditCardSyncQueueable(remaining, SyncPhase.TRANSACTIONS));
            }
        }
    }

    /**
     * @description Builds the continuation batch (rate-limited card onward, plus anything already pending)
     * and schedules a delayed retry, honoring the Pluggy Retry-After header or falling back to exponential backoff.
     */
    private void rescheduleFromRateLimit(List<AXF_OBJ_CreditCard__c> currentBatch, List<AXF_OBJ_CreditCard__c> remaining, Integer rateLimitedIndex, Id rateLimitedCardId, AXF_CLS_PluggyTxSync_Service.RateLimitException rle) {
        if (Test.isRunningTest()) {
            return;
        }

        List<AXF_OBJ_CreditCard__c> retryBatch = new List<AXF_OBJ_CreditCard__c>();
        for (Integer j = rateLimitedIndex; j < currentBatch.size(); j++) {
            retryBatch.add(new AXF_OBJ_CreditCard__c(Id = currentBatch[j].Id));
        }
        for (AXF_OBJ_CreditCard__c pending : remaining) {
            retryBatch.add(new AXF_OBJ_CreditCard__c(Id = pending.Id));
        }

        Integer nextAttempt = retryAttempt + 1;
        Integer delaySeconds = rle.retryAfterSeconds != null
            ? rle.retryAfterSeconds
            : Math.min(BASE_BACKOFF_SECONDS * (Integer) Math.pow(2, retryAttempt), MAX_BACKOFF_SECONDS);
        delaySeconds = Math.max(delaySeconds, 5);

        Queueable retryJob = new AXF_CLS_PluggyCreditCardSyncQueueable(retryBatch, SyncPhase.TRANSACTIONS, rateLimitedCardId, rle.resumeCursor, nextAttempt);
        Datetime fireTime = Datetime.now().addSeconds(delaySeconds);
        String jobName = 'AXF_PluggyCreditCardRetry_' + Datetime.now().getTime();
        System.schedule(jobName, AXF_CLS_PluggyRetryScheduler.toCronExpression(fireTime), new AXF_CLS_PluggyRetryScheduler(retryJob));
    }
}
