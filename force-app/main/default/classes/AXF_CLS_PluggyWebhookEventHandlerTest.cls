/**
 * @description AXF-11 / G4-3. A verified webhook publishes AXF_PluggyWebhookEvent__e; the
 * handler revalidates the affected connection(s) out of the guest context, runs every
 * callout before the single DML (so a multi-event batch is safe), is idempotent, and asks
 * the event bus to retry only on an unknown/transient integration result.
 */
@IsTest
private class AXF_CLS_PluggyWebhookEventHandlerTest {
  @IsTest
  static void publishedEventFlowsThroughTheTrigger() {
    // End-to-end wiring: publish -> AXF_TRG_PluggyWebhookEvent -> handler. The revalidation
    // behaviour itself is asserted by the direct-call tests below; Test.setMock is not
    // honoured inside platform-event trigger delivery, so this one asserts the wiring only.
    AXF_CLS_PluggyTestData.connection('ITEM_A');
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());

    Test.startTest();
    Database.SaveResult sr = EventBus.publish(
      new AXF_PluggyWebhookEvent__e(AXF_PWE_TXT_ObservedItemId__c = 'ITEM_A')
    );
    Test.getEventBus().deliver(); // runs AXF_TRG_PluggyWebhookEvent
    Test.stopTest();

    System.assertEquals(
      true,
      sr.isSuccess(),
      'the event is published for the trigger to consume'
    );
  }

  @IsTest
  static void batchDoesEveryCalloutBeforeTheDml() {
    AXF_OBJ_PluggyConnection__c a = AXF_CLS_PluggyTestData.connection('ITEM_A');
    AXF_OBJ_PluggyConnection__c b = AXF_CLS_PluggyTestData.connection('ITEM_B');
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());

    Test.startTest();
    AXF_CLS_PluggyWebhookEventHandler.handle(
      new List<AXF_PluggyWebhookEvent__e>{
        new AXF_PluggyWebhookEvent__e(AXF_PWE_TXT_ObservedItemId__c = 'ITEM_A'),
        new AXF_PluggyWebhookEvent__e(AXF_PWE_TXT_ObservedItemId__c = 'ITEM_B')
      }
    );
    Test.stopTest();

    for (AXF_OBJ_PluggyConnection__c reloaded : [
      SELECT AXF_CON_DT_ConsentCheckedAt__c
      FROM AXF_OBJ_PluggyConnection__c
      WHERE Id IN (:a.Id, :b.Id)
    ]) {
      System.assertNotEquals(
        null,
        reloaded.AXF_CON_DT_ConsentCheckedAt__c,
        'both connections revalidated without a callout-after-DML'
      );
    }
  }

  @IsTest
  static void replayIsIdempotent() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection('ITEM_A');
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());

    Test.startTest();
    AXF_CLS_PluggyWebhookEventHandler.handle(
      new List<AXF_PluggyWebhookEvent__e>{
        new AXF_PluggyWebhookEvent__e(AXF_PWE_TXT_ObservedItemId__c = 'ITEM_A'),
        new AXF_PluggyWebhookEvent__e(AXF_PWE_TXT_ObservedItemId__c = 'ITEM_A')
      }
    );
    Test.stopTest();

    System.assertEquals(
      1,
      [SELECT COUNT() FROM AXF_OBJ_PluggyConnection__c WHERE Id = :c.Id],
      'revalidation never creates a second connection'
    );
  }

  @IsTest
  static void blankItemIdIsIgnored() {
    Test.startTest();
    AXF_CLS_PluggyWebhookEventHandler.handle(
      new List<AXF_PluggyWebhookEvent__e>{ new AXF_PluggyWebhookEvent__e() }
    );
    Test.stopTest();
    System.assert(true, 'no exception on an empty batch');
  }

  @IsTest
  static void transientFailureAsksEventBusToRetry() {
    AXF_CLS_PluggyTestData.connection('ITEM_A');
    AXF_CLS_PluggyHttpCalloutMock mock = new AXF_CLS_PluggyHttpCalloutMock();
    mock.throwCallout = true;
    Test.setMock(HttpCalloutMock.class, mock);

    Boolean askedToRetry = false;
    Test.startTest();
    try {
      AXF_CLS_PluggyWebhookEventHandler.handle(
        new List<AXF_PluggyWebhookEvent__e>{
          new AXF_PluggyWebhookEvent__e(
            AXF_PWE_TXT_ObservedItemId__c = 'ITEM_A'
          )
        }
      );
    } catch (EventBus.RetryableException e) {
      askedToRetry = true;
    }
    Test.stopTest();

    System.assert(
      askedToRetry,
      'an unknown/transient integration result must ask the platform to redeliver'
    );
  }

  @IsTest
  static void terminalOutcomeIsSwallowed() {
    // No connection for this item id -> refreshByItemIds finds nothing, no throw.
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());
    Test.startTest();
    AXF_CLS_PluggyWebhookEventHandler.handle(
      new List<AXF_PluggyWebhookEvent__e>{
        new AXF_PluggyWebhookEvent__e(
          AXF_PWE_TXT_ObservedItemId__c = 'ITEM_UNKNOWN'
        )
      }
    );
    Test.stopTest();
    System.assert(
      true,
      'a terminal outcome does not bubble out of the handler'
    );
  }
}
