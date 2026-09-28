/**
 * @description Queueable class to synchronize Bank Account transactions sequentially.
 */
public with sharing class AXF_CLS_PluggyBankAccountSyncQueueable implements Queueable, Database.AllowsCallouts {
  private List<AXF_OBJ_BankAccount__c> bankAccountsToProcess;
  private String resumeAccountId;
  private String resumeCursor;
  private Integer retryAttempt = 0;

  private static final Integer BATCH_SIZE = 40; // Safe limit for callouts
  private static final Integer BASE_BACKOFF_SECONDS = 15;
  private static final Integer MAX_BACKOFF_SECONDS = 300;
  private static final Integer DEFAULT_LOOKBACK_DAYS = 90; // Used on first sync (no prior successful run recorded)

  /**
   * @description Default constructor querying all active bank accounts with a valid Pluggy ID.
   */
  public AXF_CLS_PluggyBankAccountSyncQueueable() {
    this(
      [
        SELECT Id
        FROM AXF_OBJ_BankAccount__c
        WHERE AXF_BA_EXI_PluggyAccountId__c != NULL
      ]
    );
  }

  /**
   * @description Constructor accepting a specific list of bank accounts to synchronize.
   * @param bankAccounts List of bank account records to process.
   */
  public AXF_CLS_PluggyBankAccountSyncQueueable(
    List<AXF_OBJ_BankAccount__c> bankAccounts
  ) {
    this.bankAccountsToProcess = bankAccounts;
  }

  /**
   * @description Constructor used to resume a batch after a Pluggy API rate limit (HTTP 429) response,
   * restarting the affected account from the cursor where it was interrupted.
   * @param bankAccounts Accounts still pending, starting with the one that was rate limited.
   * @param resumeAccountId Id of the account that should resume from resumeCursor instead of starting fresh.
   * @param resumeCursor Cursor to resume pagination from for resumeAccountId.
   * @param retryAttempt Number of consecutive rate limit retries so far, used for exponential backoff.
   */
  public AXF_CLS_PluggyBankAccountSyncQueueable(
    List<AXF_OBJ_BankAccount__c> bankAccounts,
    String resumeAccountId,
    String resumeCursor,
    Integer retryAttempt
  ) {
    this.bankAccountsToProcess = bankAccounts;
    this.resumeAccountId = resumeAccountId;
    this.resumeCursor = resumeCursor;
    this.retryAttempt = retryAttempt;
  }

  /**
   * @description Execute method that syncs Transactions for the current batch.
   */
  public void execute(QueueableContext context) {
    if (bankAccountsToProcess == null || bankAccountsToProcess.isEmpty()) {
      return;
    }

    // Query the necessary fields for the bank accounts to process
    List<AXF_OBJ_BankAccount__c> accountsToSync = [
      SELECT
        Id,
        AXF_BA_EXI_PluggyAccountId__c,
        AXF_BA_LKP_PluggyConnection__c,
        AXF_BA_LKP_PluggyConnection__r.AXF_CON_EXI_PluggyItemId__c,
        AXF_BA_DT_LastTransactionSync__c
      FROM AXF_OBJ_BankAccount__c
      WHERE
        Id IN :bankAccountsToProcess
        AND AXF_BA_EXI_PluggyAccountId__c != NULL
    ];

    if (accountsToSync.isEmpty()) {
      return;
    }

    Integer batchSize = Math.min(accountsToSync.size(), BATCH_SIZE);
    String apiKey = AXF_CLS_PluggyAuthService.getValidApiKey();

    AXF_CLS_PluggyTxSync_Service.TransactionSyncResult txResult = new AXF_CLS_PluggyTxSync_Service.TransactionSyncResult();
    List<AXF_OBJ_BankAccount__c> syncedAccounts = new List<AXF_OBJ_BankAccount__c>();
    Date today = Date.today();

    for (Integer i = 0; i < batchSize; i++) {
      AXF_OBJ_BankAccount__c acc = accountsToSync[i];

      try {
        if (acc.AXF_BA_LKP_PluggyConnection__c != null) {
          String cursorForThisAccount = (resumeCursor != null &&
            acc.Id == resumeAccountId)
            ? resumeCursor
            : null;
          // Incremental sync: dateFrom = last successful sync (or a 90-day lookback on first sync),
          // so the nightly job only re-fetches the delta instead of the whole history every night.
          Date dateFrom = acc.AXF_BA_DT_LastTransactionSync__c != null
            ? acc.AXF_BA_DT_LastTransactionSync__c.date()
            : today.addDays(-DEFAULT_LOOKBACK_DAYS);

          AXF_CLS_PluggyTxSync_Service.TransactionSyncResult accTxResult = AXF_CLS_PluggyTxSync_Service.fetchTransactionsForConnection(
            acc.AXF_BA_LKP_PluggyConnection__r.AXF_CON_EXI_PluggyItemId__c,
            apiKey,
            acc.AXF_BA_EXI_PluggyAccountId__c,
            cursorForThisAccount,
            dateFrom,
            today
          );
          txResult.bankAccountTransactions.addAll(
            accTxResult.bankAccountTransactions
          );

          // Only mark as fully synced when pagination for this account completed without
          // being interrupted by a rate limit / governor limit exception.
          syncedAccounts.add(
            new AXF_OBJ_BankAccount__c(
              Id = acc.Id,
              AXF_BA_DT_LastTransactionSync__c = Datetime.now()
            )
          );
        }
      } catch (AXF_CLS_PluggyTxSync_Service.RateLimitException rle) {
        // Never throw-and-discard: merge in whatever pages were already fetched for THIS account
        // before the interruption, then upsert everything fetched so far (including transactions
        // from accounts already fully processed in this batch) before rescheduling.
        if (rle.partialResult != null) {
          txResult.bankAccountTransactions.addAll(
            rle.partialResult.bankAccountTransactions
          );
        }
        if (!txResult.bankAccountTransactions.isEmpty()) {
          AXF_CLS_PluggyTxSync_Service.upsertTransactions(txResult);
        }
        if (!syncedAccounts.isEmpty()) {
          update syncedAccounts;
        }
        rescheduleFromRateLimit(accountsToSync, i, acc.Id, rle);
        return;
      } catch (Exception e) {
        // Failures for a specific bank account should not block others
      }
    }

    if (!txResult.bankAccountTransactions.isEmpty()) {
      AXF_CLS_PluggyTxSync_Service.upsertTransactions(txResult);
    }

    if (!syncedAccounts.isEmpty()) {
      update syncedAccounts;
    }

    // Chain next execution if there are remaining bank accounts beyond this batch
    if (batchSize < accountsToSync.size() && !Test.isRunningTest()) {
      List<AXF_OBJ_BankAccount__c> remaining = new List<AXF_OBJ_BankAccount__c>();
      for (Integer i = batchSize; i < accountsToSync.size(); i++) {
        remaining.add(new AXF_OBJ_BankAccount__c(Id = accountsToSync[i].Id));
      }
      System.enqueueJob(new AXF_CLS_PluggyBankAccountSyncQueueable(remaining));
    }
  }

  /**
   * @description Builds the continuation batch (rate-limited account onward, plus anything already pending)
   * and schedules a delayed retry, honoring the Pluggy Retry-After header or falling back to exponential backoff.
   */
  private void rescheduleFromRateLimit(
    List<AXF_OBJ_BankAccount__c> accountsToSync,
    Integer rateLimitedIndex,
    Id rateLimitedAccountId,
    AXF_CLS_PluggyTxSync_Service.RateLimitException rle
  ) {
    if (Test.isRunningTest()) {
      return;
    }

    List<AXF_OBJ_BankAccount__c> retryBatch = new List<AXF_OBJ_BankAccount__c>();
    for (Integer j = rateLimitedIndex; j < accountsToSync.size(); j++) {
      retryBatch.add(new AXF_OBJ_BankAccount__c(Id = accountsToSync[j].Id));
    }

    Integer nextAttempt = retryAttempt + 1;
    Integer delaySeconds = rle.retryAfterSeconds != null
      ? rle.retryAfterSeconds
      : Math.min(
          BASE_BACKOFF_SECONDS * (Integer) Math.pow(2, retryAttempt),
          MAX_BACKOFF_SECONDS
        );
    delaySeconds = Math.max(delaySeconds, 5);

    Queueable retryJob = new AXF_CLS_PluggyBankAccountSyncQueueable(
      retryBatch,
      rateLimitedAccountId,
      rle.resumeCursor,
      nextAttempt
    );
    Datetime fireTime = Datetime.now().addSeconds(delaySeconds);
    String jobName = 'AXF_PluggyBankAccountRetry_' + Datetime.now().getTime();
    System.schedule(
      jobName,
      AXF_CLS_PluggyRetryScheduler.toCronExpression(fireTime),
      new AXF_CLS_PluggyRetryScheduler(retryJob)
    );
  }
}
