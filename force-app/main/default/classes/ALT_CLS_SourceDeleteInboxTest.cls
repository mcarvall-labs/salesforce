/** @description Verifies durable admission, failure retention and duplicate checkpoint safety. */
@IsTest
private class ALT_CLS_SourceDeleteInboxTest {
  private static AXF_PluggyWebhookEvent__e event(List<String> ids) {
    return new AXF_PluggyWebhookEvent__e(
      AXF_PWE_TXT_EventType__c = 'transactions/deleted',
      AXF_PWE_TXT_ObservedItemId__c = 'inbox-item',
      AXF_PWE_TXT_AccountId__c = 'inbox-account',
      AXF_PWE_TXT_CorrelationId__c = 'inbox-correlation',
      AXF_PWE_TAL_TransactionIds__c = JSON.serialize(ids)
    );
  }
  private static void setupConnection() {
    AXF_CLS_PluggyTestData.grantIntegrationAccess();
    AXF_CLS_PluggyTestData.connection('inbox-item');
  }
  @IsTest
  static void shouldPersistBeforeWorkAndDeduplicateOrderIndependentReplay() {
    setupConnection();
    ALT_CLS_SourceDeleteInbox inbox = new ALT_CLS_SourceDeleteInbox();
    Test.startTest();
    List<Id> first = inbox.admit(
      new List<AXF_PluggyWebhookEvent__e>{ event(new List<String>{ 'b', 'a' }) }
    );
    List<Id> replay = inbox.admit(
      new List<AXF_PluggyWebhookEvent__e>{
        event(new List<String>{ 'a', 'b', 'a' })
      }
    );
    ALT_CLS_SourceDeleteInbox.Work work = inbox.load(first[0]);
    Test.stopTest();
    Assert.areEqual(
      first[0],
      replay[0],
      'Webhook retries reuse the durable run.'
    );
    Assert.areEqual(
      new List<String>{ 'a', 'b' },
      work.ids,
      'Only canonical typed identifiers are persisted.'
    );
    Assert.areEqual(
      0,
      work.cursor,
      'No hint is acknowledged as processed on admission.'
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AXF_OBJ_IntegrationRun__c
        WHERE AXF_INR_PKL_Product__c = 'SOURCE_DELETIONS'
      ]
    );
  }
  @IsTest
  static void shouldNotAdvanceTwiceForConcurrentCheckpointReplay() {
    setupConnection();
    ALT_CLS_SourceDeleteInbox inbox = new ALT_CLS_SourceDeleteInbox();
    Id runId = inbox.admit(
      new List<AXF_PluggyWebhookEvent__e>{ event(new List<String>{ 'a', 'b' }) }
    )[0];
    ALT_CLS_SourceDeleteInbox.Work first = inbox.load(runId);
    ALT_CLS_SourceDeleteInbox.Work concurrent = inbox.load(runId);
    Test.startTest();
    Assert.isTrue(inbox.complete(first, 1), 'The second identifier remains.');
    Assert.isTrue(
      inbox.complete(concurrent, 1),
      'Stale duplicate cannot acknowledge the next identifier.'
    );
    ALT_CLS_SourceDeleteInbox.Work remaining = inbox.load(runId);
    Assert.areEqual(1, remaining.cursor);
    Assert.isFalse(inbox.complete(remaining, 1));
    Assert.isNull(inbox.load(runId), 'Completed work cannot run again.');
    Assert.areEqual(
      0,
      inbox.admit(
          new List<AXF_PluggyWebhookEvent__e>{
            event(new List<String>{ 'a', 'b' })
          }
        )
        .size()
    );
    Test.stopTest();
  }
  @IsTest
  static void shouldRetainHintsAndLaterEventAfterExhaustedAttempts() {
    setupConnection();
    ALT_CLS_SourceDeleteInbox inbox = new ALT_CLS_SourceDeleteInbox();
    List<Id> runs = inbox.admit(
      new List<AXF_PluggyWebhookEvent__e>{
        event(new List<String>{ 'a' }),
        event(new List<String>{ 'later' })
      }
    );
    Integer ceiling = AXF_CLS_PluggySyncPolicy.current().maxAttempts;
    Test.startTest();
    for (Integer attempt = 1; attempt <= ceiling; attempt++) {
      Boolean retry = inbox.fail(inbox.load(runs[0]));
      Assert.areEqual(
        attempt < ceiling,
        retry,
        'Automatic retries obey the approved ceiling.'
      );
    }
    ALT_CLS_SourceDeleteInbox.Work exhausted = inbox.load(runs[0]);
    ALT_CLS_SourceDeleteInbox.Work later = inbox.load(runs[1]);
    Test.stopTest();
    Assert.areEqual(0, exhausted.cursor, 'Failure never advances progress.');
    Assert.areEqual(
      1,
      exhausted.ids.size(),
      'The original identifier survives exhaustion.'
    );
    Assert.areEqual(
      0,
      later.cursor,
      'A later event remains independently durable.'
    );
    Assert.areEqual(
      'FAILED_TERMINAL',
      [
        SELECT AXF_INR_PKL_State__c
        FROM AXF_OBJ_IntegrationRun__c
        WHERE Id = :runs[0]
      ]
      .AXF_INR_PKL_State__c
    );
  }
  @IsTest
  static void shouldIgnoreFailureFromStaleWorkerAfterSuccessfulCheckpoint() {
    setupConnection();
    ALT_CLS_SourceDeleteInbox inbox = new ALT_CLS_SourceDeleteInbox();
    Id runId = inbox.admit(
      new List<AXF_PluggyWebhookEvent__e>{ event(new List<String>{ 'a' }) }
    )[0];
    ALT_CLS_SourceDeleteInbox.Work work = inbox.load(runId);
    Test.startTest();
    inbox.complete(work, 1);
    Assert.isFalse(inbox.fail(work));
    Test.stopTest();
    Assert.areEqual(
      'SUCCEEDED',
      [
        SELECT AXF_INR_PKL_State__c
        FROM AXF_OBJ_IntegrationRun__c
        WHERE Id = :runId
      ]
      .AXF_INR_PKL_State__c
    );
  }
}
