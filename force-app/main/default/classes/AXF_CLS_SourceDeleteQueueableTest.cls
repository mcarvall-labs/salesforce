@IsTest
private class AXF_CLS_SourceDeleteQueueableTest {
  private class FailedContext implements FinalizerContext {
    public Id getAsyncApexJobId() {
      return null;
    }
    public String getRequestId() {
      return 'test-request';
    }
    public ParentJobResult getResult() {
      return ParentJobResult.UNHANDLED_EXCEPTION;
    }
    public Exception getException() {
      return new AXF_CLS_PluggyIntegrationException('Transient failure');
    }
  }
  private class DeletionMock implements HttpCalloutMock {
    Integer status;
    AXF_CLS_PluggyHttpCalloutMock other = new AXF_CLS_PluggyHttpCalloutMock();
    DeletionMock(Integer code) {
      status = code;
    }
    public HttpResponse respond(HttpRequest request) {
      if (!request.getEndpoint().contains('/transactions/'))
        return other.respond(request);
      HttpResponse response = new HttpResponse();
      response.setStatusCode(status);
      response.setBody('{"id":"DELETE_TX","accountId":"DELETE_ACCOUNT"}');
      return response;
    }
  }
  private static AXF_PluggyWebhookEvent__e setup(Boolean card) {
    Id connection = AXF_CLS_PluggyTestData.connection('ITEM_A').Id;
    if (card) {
      Id parent = AXF_CLS_PluggyTestData.creditCard(
          connection,
          'DELETE_ACCOUNT',
          true
        )
        .Id;
      insert new AXF_OBJ_CreditCardTransaction__c(
        AXF_CCT_MDR_CreditCard__c = parent,
        AXF_CCT_EXI_SourceKey__c = 'DELETE_TX',
        AXF_CCT_PKL_Source__c = 'PLUGGY',
        AXF_CCT_DAT_Date__c = Date.today(),
        AXF_CCT_NUM_Magnitude__c = 12,
        AXF_CCT_PKL_Direction__c = 'DEBIT',
        AXF_CCT_PKL_Status__c = 'POSTED',
        AXF_CCT_TXT_CurrencyIsoCode__c = 'BRL',
        AXF_CCT_TXT_Description__c = 'Original',
        AXF_CCT_TXT_NormalizedDescription__c = 'original'
      );
    } else {
      Id parent = AXF_CLS_PluggyTestData.bankAccount(
          connection,
          'DELETE_ACCOUNT',
          true
        )
        .Id;
      insert new AXF_OBJ_BankAccountTransaction__c(
        AXF_BAT_MDR_BankAccount__c = parent,
        AXF_BAT_EXI_SourceKey__c = 'DELETE_TX',
        AXF_BAT_PKL_Source__c = 'PLUGGY',
        AXF_BAT_DAT_Date__c = Date.today(),
        AXF_BAT_NUM_Magnitude__c = 12,
        AXF_BAT_PKL_Direction__c = 'DEBIT',
        AXF_BAT_PKL_Status__c = 'POSTED',
        AXF_BAT_TXT_CurrencyIsoCode__c = 'BRL',
        AXF_BAT_TXT_Description__c = 'Original',
        AXF_BAT_TXT_NormalizedDescription__c = 'original'
      );
    }
    return new AXF_PluggyWebhookEvent__e(
      AXF_PWE_TXT_EventType__c = 'transactions/deleted',
      AXF_PWE_TXT_ObservedItemId__c = 'ITEM_A',
      AXF_PWE_TXT_AccountId__c = 'DELETE_ACCOUNT',
      AXF_PWE_TAL_TransactionIds__c = '["DELETE_TX"]',
      AXF_PWE_TXT_CorrelationId__c = 'deletion-test'
    );
  }
  @IsTest
  static void confirmsBankDeletionAndPreservesFact() {
    AXF_PluggyWebhookEvent__e event = setup(false);
    List<Id> runIds = new ALT_CLS_SourceDeleteInbox()
      .admit(new List<AXF_PluggyWebhookEvent__e>{ event });
    Test.setMock(HttpCalloutMock.class, new DeletionMock(404));
    Test.startTest();
    System.enqueueJob(new AXF_CLS_SourceDeleteQueueable(runIds));
    Test.stopTest();
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AXF_OBJ_ReviewItem__c
        WHERE AXF_RVI_PKL_Type__c = 'SOURCE_DELETE'
      ]
    );
    Assert.areEqual(1, [SELECT COUNT() FROM AXF_OBJ_BankAccountTransaction__c]);
    Assert.areEqual(
      12,
      [SELECT AXF_RVI_NUM_PriorAmount__c FROM AXF_OBJ_ReviewItem__c LIMIT 1]
      .AXF_RVI_NUM_PriorAmount__c
    );
  }
  @IsTest
  static void confirmsCardDeletion() {
    AXF_PluggyWebhookEvent__e event = setup(true);
    Test.setMock(HttpCalloutMock.class, new DeletionMock(404));
    Test.startTest();
    AXF_CLS_SourceDeleteQueueable.process(
      event,
      new Set<String>{ 'DELETE_TX' }
    );
    Test.stopTest();
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AXF_OBJ_ReviewItem__c
        WHERE AXF_RVI_LKP_CreditCardTransaction__c != NULL
      ]
    );
    Assert.areEqual(1, [SELECT COUNT() FROM AXF_OBJ_CreditCardTransaction__c]);
  }
  @IsTest
  static void stillPresentDoesNotBecomeDeletion() {
    AXF_PluggyWebhookEvent__e event = setup(false);
    Test.setMock(HttpCalloutMock.class, new DeletionMock(200));
    Test.startTest();
    AXF_CLS_SourceDeleteQueueable.process(
      event,
      new Set<String>{ 'DELETE_TX' }
    );
    Test.stopTest();
    Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_ReviewItem__c]);
  }
  @IsTest
  static void httpFailuresNeverProveDeletion() {
    AXF_PluggyWebhookEvent__e event = setup(false);
    Test.startTest();
    for (Integer status : new List<Integer>{ 401, 403, 429, 500, 503 }) {
      Test.setMock(HttpCalloutMock.class, new DeletionMock(status));
      Boolean failed = false;
      try {
        AXF_CLS_SourceDeleteQueueable.process(
          event,
          new Set<String>{ 'DELETE_TX' }
        );
      } catch (AXF_CLS_PluggyIntegrationException expected) {
        failed = true;
      }
      Assert.isTrue(failed, 'HTTP ' + status + ' cannot prove deletion.');
    }
    Test.stopTest();
    Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_ReviewItem__c]);
  }
  @IsTest
  static void wrongAccountIsRejected() {
    AXF_PluggyWebhookEvent__e event = setup(false);
    event.AXF_PWE_TXT_AccountId__c = 'WRONG_ACCOUNT';
    Test.startTest();
    Boolean rejected = false;
    try {
      AXF_CLS_SourceDeleteQueueable.process(
        event,
        new Set<String>{ 'DELETE_TX' }
      );
    } catch (AXF_CLS_ReviewQueueException expected) {
      rejected = true;
    }
    Test.stopTest();
    Assert.isTrue(rejected);
    Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_ReviewItem__c]);
  }

  @IsTest
  static void pausedCollectionIsRejected() {
    AXF_PluggyWebhookEvent__e event = setup(false);
    AXF_OBJ_PluggyConnection__c connection = [
      SELECT Id
      FROM AXF_OBJ_PluggyConnection__c
      LIMIT 1
    ];
    connection.AXF_CON_PKL_CollectionState__c = 'PAUSED';
    update connection;
    Test.startTest();
    Boolean rejected = false;
    try {
      AXF_CLS_SourceDeleteQueueable.process(
        event,
        new Set<String>{ 'DELETE_TX' }
      );
    } catch (AXF_CLS_ReviewQueueException expected) {
      rejected = true;
    }
    Test.stopTest();
    Assert.isTrue(rejected);
    Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_ReviewItem__c]);
  }

  @IsTest
  static void finalizerPreservesLaterEventAndRetryCompletesOnce() {
    AXF_PluggyWebhookEvent__e event = setup(false);
    AXF_PluggyWebhookEvent__e later = event.clone();
    later.AXF_PWE_TAL_TransactionIds__c = '["LATER_TX"]';
    ALT_CLS_SourceDeleteInbox inbox = new ALT_CLS_SourceDeleteInbox();
    Id firstId = inbox.admit(new List<AXF_PluggyWebhookEvent__e>{ event })[0];
    Id laterId = inbox.admit(new List<AXF_PluggyWebhookEvent__e>{ later })[0];
    ALT_CLS_SourceDeleteInbox.Work first = inbox.load(firstId);
    AXF_CLS_SourceDeleteQueueable.scheduledForTest = new List<Id>();
    Test.setMock(HttpCalloutMock.class, new DeletionMock(503));
    Test.startTest();
    Boolean failed = false;
    try {
      AXF_CLS_SourceDeleteQueueable.process(
        first.event,
        new Set<String>(first.ids)
      );
    } catch (AXF_CLS_PluggyIntegrationException expected) {
      failed = true;
    }
    Assert.isTrue(failed, 'The first provider response must fail.');
    new AXF_CLS_SourceDeleteQueueable.RetryFinalizer(
        first,
        new List<Id>{ laterId }
      )
      .execute(new FailedContext());
    Assert.areEqual(
      new List<Id>{ laterId, firstId },
      AXF_CLS_SourceDeleteQueueable.scheduledForTest,
      'Later work survives and runs before the failed scope retries.'
    );
    Assert.areEqual(
      0,
      inbox.load(firstId).cursor,
      'Failed work did not advance.'
    );
    Assert.areEqual(
      0,
      inbox.load(laterId).cursor,
      'Later event remains durably pending.'
    );
    Test.setMock(HttpCalloutMock.class, new DeletionMock(404));
    // Retry runs in its own transaction after the finalizer's checkpoint DML.
    System.enqueueJob(
      new AXF_CLS_SourceDeleteQueueable(new List<Id>{ firstId })
    );
    Test.stopTest();
    Assert.isNull(inbox.load(firstId), 'Successful retry becomes terminal.');
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AXF_OBJ_ReviewItem__c
        WHERE AXF_RVI_PKL_Type__c = 'SOURCE_DELETE'
      ]
    );
    Assert.areEqual(1, [SELECT COUNT() FROM AXF_OBJ_BankAccountTransaction__c]);
    Assert.isNotNull(
      inbox.load(laterId),
      'Other pending event is not discarded by success.'
    );
  }
}
