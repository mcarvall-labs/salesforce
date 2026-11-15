/**
 * @description Full Pluggy sync in three chained phases, each in its own transaction (a callout
 * cannot follow DML): 1) accounts and cards of every Active/Error connection, 2) transactions of
 * the synced bank accounts, 3) invoices and transactions of the synced cards. Then each
 * connection gets Status, Last Sync and the error message. Run with scope size 1.
 * A connection whose first phase fails is marked Error and skipped by the later phases; a failure
 * in phase 2 does not stop phase 3 of that connection (they are independent).
 */
public with sharing class ALT_CLS_PluggySyncBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {
  public static final Integer SCOPE_SIZE = 1;
  private static final Integer MAX_MESSAGE = 4000;
  private static final Integer LAST_PHASE = 3;

  @TestVisible
  private static Boolean chainNextPhase = true;

  private final Integer phase;
  private final Id connectionFilter;
  private final Set<Id> attempted;
  private final Map<Id, String> errors;
  // Connections whose first phase failed: phases 2 and 3 leave them out.
  private final Set<Id> skipped;

  public ALT_CLS_PluggySyncBatch(Id connectionFilter) {
    this(
      connectionFilter,
      1,
      new Set<Id>(),
      new Map<Id, String>(),
      new Set<Id>()
    );
  }

  @TestVisible
  private ALT_CLS_PluggySyncBatch(
    Id connectionFilter,
    Integer phase,
    Set<Id> attempted,
    Map<Id, String> errors,
    Set<Id> skipped
  ) {
    this.connectionFilter = connectionFilter;
    this.phase = phase;
    this.attempted = attempted;
    this.errors = errors;
    this.skipped = skipped;
  }

  public static Id run(Id connectionFilter) {
    return Database.executeBatch(
      new ALT_CLS_PluggySyncBatch(connectionFilter),
      SCOPE_SIZE
    );
  }

  public Database.QueryLocator start(Database.BatchableContext context) {
    Set<Id> synced = syncedConnections();
    Id filterId = connectionFilter;
    if (phase == 1) {
      String query = 'SELECT Id FROM AXF_OBJ_PluggyConnection__c WHERE AXF_CON_PKL_Status__c IN (\'Active\', \'Error\')';
      if (filterId != null) {
        query += ' AND Id = :filterId';
      }
      return Database.getQueryLocator(query);
    }
    if (phase == 2) {
      return Database.getQueryLocator(
        [
          SELECT Id, AXF_BA_LKP_Connection__c
          FROM AXF_OBJ_BankAccount__c
          WHERE
            AXF_BA_EXI_PluggyAccountId__c != NULL
            AND AXF_BA_LKP_Connection__c IN :synced
        ]
      );
    }
    return Database.getQueryLocator(
      [
        SELECT Id, AXF_CC_LKP_Connection__c
        FROM AXF_OBJ_CreditCard__c
        WHERE
          AXF_CC_EXI_PluggyCardId__c != NULL
          AND AXF_CC_LKP_Connection__c IN :synced
      ]
    );
  }

  public void execute(Database.BatchableContext context, List<SObject> scope) {
    for (SObject record : scope) {
      try {
        runStep(record);
      } catch (Exception e) {
        fail(connectionOf(record), e.getTypeName() + ': ' + e.getMessage());
      }
    }
  }

  public void finish(Database.BatchableContext context) {
    if (phase < LAST_PHASE) {
      if (!chainNextPhase) {
        return;
      }
      // After phase 1 every error is a first-phase failure.
      Set<Id> nextSkipped = phase == 1 ? errors.keySet().clone() : skipped;
      try {
        Database.executeBatch(
          new ALT_CLS_PluggySyncBatch(
            connectionFilter,
            phase + 1,
            attempted,
            errors,
            nextSkipped
          ),
          SCOPE_SIZE
        );
        return;
      } catch (Exception e) {
        // The chain broke: record what was done and mark the rest as failed.
        for (Id connectionId : attempted) {
          fail(connectionId, e.getTypeName() + ': ' + e.getMessage());
        }
      }
    }
    recordResults();
  }

  private void runStep(SObject record) {
    if (phase == 1) {
      attempted.add(record.Id);
      ALT_CLS_PluggyAccountSync.Result result = new ALT_CLS_PluggyAccountSync()
        .sync(record.Id);
      if (!result.success) {
        fail(record.Id, result.message);
      }
    } else if (phase == 2) {
      ALT_CLS_PluggyTransactionSync.Result result = new ALT_CLS_PluggyTransactionSync()
        .sync(record.Id);
      if (!result.success) {
        fail(connectionOf(record), result.message);
      }
    } else {
      ALT_CLS_PluggyCardSync.Result result = new ALT_CLS_PluggyCardSync()
        .sync(record.Id);
      if (!result.success) {
        fail(connectionOf(record), result.message);
      }
    }
  }

  private Id connectionOf(SObject record) {
    if (phase == 1) {
      return record.Id;
    }
    return (Id) record.get(
      phase == 2 ? 'AXF_BA_LKP_Connection__c' : 'AXF_CC_LKP_Connection__c'
    );
  }

  // The first error of a connection is the one kept for the user.
  private void fail(Id connectionId, String message) {
    if (connectionId != null && !errors.containsKey(connectionId)) {
      errors.put(connectionId, message);
    }
  }

  private Set<Id> syncedConnections() {
    Set<Id> synced = new Set<Id>(attempted);
    synced.removeAll(phase == 1 ? errors.keySet() : skipped);
    return synced;
  }

  private void recordResults() {
    List<AXF_OBJ_PluggyConnection__c> updates = new List<AXF_OBJ_PluggyConnection__c>();
    for (Id connectionId : attempted) {
      String error = errors.get(connectionId);
      AXF_OBJ_PluggyConnection__c connection = new AXF_OBJ_PluggyConnection__c(
        Id = connectionId,
        AXF_CON_PKL_Status__c = error == null ? 'Active' : 'Error',
        AXF_CON_TAL_SyncErrorMessage__c = error == null
          ? null
          : error.abbreviate(MAX_MESSAGE)
      );
      if (error == null) {
        connection.AXF_CON_DT_LastSyncDatetime__c = System.now();
      }
      updates.add(connection);
    }
    // Partial save: one deleted or locked connection must not drop the others' result.
    Database.update(updates, false);
  }
}
