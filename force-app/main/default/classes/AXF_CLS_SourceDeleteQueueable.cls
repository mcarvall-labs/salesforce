/** @description Confirms authenticated deletion hints without deleting local evidence. */
public with sharing class AXF_CLS_SourceDeleteQueueable implements Queueable, Database.AllowsCallouts {
  private List<Id> pending;
  @TestVisible
  private static List<Id> scheduledForTest;
  public AXF_CLS_SourceDeleteQueueable(List<Id> runIds) {
    pending = runIds.clone();
  }
  public void execute(QueueableContext context) {
    if (pending.isEmpty())
      return;
    Id runId = pending.remove(0);
    ALT_CLS_SourceDeleteInbox inbox = new ALT_CLS_SourceDeleteInbox();
    ALT_CLS_SourceDeleteInbox.Work work = inbox.load(runId);
    if (work == null) {
      enqueueRemaining(pending);
      return;
    }
    System.attachFinalizer(new RetryFinalizer(work, pending));
    List<String> chunk = new List<String>();
    for (
      Integer index = work.cursor;
      index < work.ids.size() &&
      chunk.size() < 40;
      index++
    )
      chunk.add(work.ids[index]);
    process(work.event, new Set<String>(chunk));
    if (inbox.complete(work, chunk.size()))
      pending.add(runId);
    enqueueRemaining(pending);
  }

  private static void enqueueRemaining(List<Id> remaining) {
    if (!remaining.isEmpty())
      System.enqueueJob(new AXF_CLS_SourceDeleteQueueable(remaining));
  }

  /** @description Separate transaction preserves failed work and schedules later scopes fairly. */
  @TestVisible
  private class RetryFinalizer implements Finalizer {
    private ALT_CLS_SourceDeleteInbox.Work work;
    private List<Id> remaining;
    @TestVisible
    private RetryFinalizer(
      ALT_CLS_SourceDeleteInbox.Work activeWork,
      List<Id> rest
    ) {
      work = activeWork;
      remaining = rest.clone();
    }
    public void execute(FinalizerContext context) {
      if (context.getResult() == ParentJobResult.SUCCESS)
        return;
      if (new ALT_CLS_SourceDeleteInbox().fail(work))
        remaining.add(work.runId);
      if (!remaining.isEmpty()) {
        Integer delayMinutes = Math.max(
          1,
          Math.min(
            10,
            (AXF_CLS_PluggySyncPolicy.current().backoffSeconds + 59) / 60
          )
        );
        if (Test.isRunningTest() && scheduledForTest != null)
          scheduledForTest.addAll(remaining);
        else
          System.enqueueJob(
            new AXF_CLS_SourceDeleteQueueable(remaining),
            delayMinutes
          );
      }
    }
  }

  @TestVisible
  private static void process(
    AXF_PluggyWebhookEvent__e event,
    Set<String> ids
  ) {
    if (
      ids.isEmpty() ||
      ids.size() > 40 ||
      event.AXF_PWE_TXT_EventType__c != 'transactions/deleted'
    )
      throw new AXF_CLS_ReviewQueueException('Invalid deletion scope.');
    String observed = event.AXF_PWE_TXT_ObservedItemId__c;
    List<AXF_OBJ_PluggyConnection__c> connections = [
      SELECT
        Id,
        AXF_CON_EXI_PluggyItemId__c,
        AXF_CON_PKL_ConsentState__c,
        AXF_CON_PKL_CollectionState__c
      FROM AXF_OBJ_PluggyConnection__c
      WHERE
        AXF_CON_EXI_PluggyItemId__c = :observed
        OR AXF_CON_TXT_ObservedItemId__c = :observed
      WITH USER_MODE
    ];
    if (
      connections.size() != 1 ||
      connections[0].AXF_CON_PKL_ConsentState__c != 'ACTIVE' ||
      connections[0].AXF_CON_PKL_CollectionState__c != 'ACTIVE' ||
      AXF_CLS_PluggySettings.collectionGloballyPaused()
    )
      throw new AXF_CLS_ReviewQueueException(
        'Deletion review requires an authorized active connection.'
      );
    Id connectionId = connections[0].Id;
    String accountId = event.AXF_PWE_TXT_AccountId__c;
    Set<Id> bankIds = new Set<Id>();
    Set<Id> cardIds = new Set<Id>();
    for (AXF_OBJ_BankAccount__c bank : [
      SELECT Id
      FROM AXF_OBJ_BankAccount__c
      WHERE
        AXF_BA_LKP_Connection__c = :connectionId
        AND AXF_BA_EXI_PluggyAccountId__c = :accountId
      WITH USER_MODE
    ])
      bankIds.add(bank.Id);
    for (AXF_OBJ_CreditCard__c card : [
      SELECT Id
      FROM AXF_OBJ_CreditCard__c
      WHERE
        AXF_CC_LKP_Connection__c = :connectionId
        AND AXF_CC_EXI_PluggyAccountId__c = :accountId
      WITH USER_MODE
    ])
      cardIds.add(card.Id);
    if (bankIds.size() + cardIds.size() != 1)
      throw new AXF_CLS_ReviewQueueException(
        'Deletion account is unavailable or ambiguous.'
      );
    String prefix = bankIds.isEmpty() ? 'AXF_CCT_' : 'AXF_BAT_';
    String objectName = bankIds.isEmpty()
      ? 'AXF_OBJ_CreditCardTransaction__c'
      : 'AXF_OBJ_BankAccountTransaction__c';
    String parentField = bankIds.isEmpty()
      ? 'AXF_CCT_MDR_CreditCard__c'
      : 'AXF_BAT_MDR_BankAccount__c';
    Set<Id> parentIds = bankIds.isEmpty() ? cardIds : bankIds;
    List<SObject> facts = Database.queryWithBinds(
      'SELECT ' +
        ALT_CLS_SourceChangeReview.selectFields(prefix) +
        ' FROM ' +
        objectName +
        ' WHERE ' +
        parentField +
        ' IN :parents AND ' +
        prefix +
        'EXI_SourceKey__c IN :keys AND ' +
        prefix +
        'PKL_Source__c = \'PLUGGY\'',
      new Map<String, Object>{ 'parents' => parentIds, 'keys' => ids },
      AccessLevel.USER_MODE
    );
    List<SObject> deleted = new List<SObject>();
    AXF_CLS_PluggyHttpClient client = new AXF_CLS_PluggyHttpClient();
    AXF_CLS_PluggyHttpClient.PluggyResponse itemResponse = client.getJson(
      '/items/' +
      EncodingUtil.urlEncode(
        connections[0].AXF_CON_EXI_PluggyItemId__c,
        'UTF-8'
      )
    );
    if (
      !itemResponse.isSuccess ||
      itemResponse.body == null ||
      (String) itemResponse.body.get('status') != 'UPDATED'
    )
      throw new AXF_CLS_PluggyIntegrationException(
        'Connection could not confirm completed source collection.'
      );
    for (SObject fact : facts) {
      String sourceKey = (String) fact.get(prefix + 'EXI_SourceKey__c');
      AXF_CLS_PluggyHttpClient.PluggyResponse response = client.getJson(
        '/transactions/' + EncodingUtil.urlEncode(sourceKey, 'UTF-8')
      );
      if (response.statusCode == 404)
        deleted.add(fact);
      else if (
        !response.isSuccess ||
        response.body == null ||
        (String) response.body.get('id') != sourceKey ||
        (String) response.body.get('accountId') != accountId
      )
        throw new AXF_CLS_PluggyIntegrationException(
          'Deletion confirmation failed; retry the authenticated event.'
        );
    }
    // Every transaction lookup precedes the consent service's write.
    AXF_CLS_PluggyConsentService.ConsentSnapshot consent = new AXF_CLS_PluggyConsentService()
      .refresh(connectionId);
    if (!consent.collectionAllowed)
      throw new AXF_CLS_ReviewQueueException(
        'Collection authorization changed before deletion review.'
      );
    Map<String, Object> result = new ALT_CLS_SourceChangeReview()
      .reviewDeleted(deleted, event.AXF_PWE_TXT_CorrelationId__c);
    if ((Integer) result.get('bad') > 0)
      throw new AXF_CLS_ReviewQueueException(
        'Deletion evidence was not recorded; retry the authenticated event.'
      );
  }
}
