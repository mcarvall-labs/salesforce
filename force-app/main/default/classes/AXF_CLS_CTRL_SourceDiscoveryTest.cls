/**
 * @description AXF-84. The controller surfaces status/sources and turns a blocked or
 * conflicting discovery into a clean DTO instead of an exception.
 */
@IsTest
private class AXF_CLS_CTRL_SourceDiscoveryTest {
  static AXF_OBJ_PluggyConnection__c conn() {
    return AXF_CLS_PluggyTestData.connection('ITEM_A');
  }

  @TestSetup
  static void seed() {
    // Committed before each test runs, so registerConnection's callout is not blocked by
    // pending DML when it re-uses an existing connection.
    AXF_CLS_PluggyTestData.connection('ITEM_DUP');
  }

  @IsTest
  static void startDiscoverySucceedsThroughController() {
    AXF_OBJ_PluggyConnection__c c = conn();
    AXF_CLS_PluggyDiscoveryService.canDiscoverOverride = true;
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());

    Test.startTest();
    AXF_CLS_PluggyDiscoveryService.DiscoveryResult r = AXF_CLS_CTRL_SourceDiscovery.startDiscovery(
      c.Id
    );
    Test.stopTest();

    System.assertEquals('SUCCEEDED', r.state);
    System.assertEquals(
      2,
      AXF_CLS_CTRL_SourceDiscovery.getDiscovered(c.Id).size()
    );
    System.assertEquals(
      'SUCCEEDED',
      AXF_CLS_CTRL_SourceDiscovery.getStatus(c.Id).state
    );
  }

  @IsTest
  static void blockedDiscoveryReturnsTerminalDto() {
    AXF_OBJ_PluggyConnection__c c = conn();
    c.AXF_CON_PKL_ConsentState__c = 'REVOKED';
    update c;
    AXF_CLS_PluggyDiscoveryService.canDiscoverOverride = true;

    AXF_CLS_PluggyDiscoveryService.DiscoveryResult r = AXF_CLS_CTRL_SourceDiscovery.startDiscovery(
      c.Id
    );
    System.assertEquals('FAILED_TERMINAL', r.state);
    System.assertEquals(false, r.complete);
  }

  @IsTest
  static void registerConnectionCreatesAndValidatesTheItemId() {
    AXF_CLS_PluggyTestData.grantIntegrationAccess();
    AXF_CLS_PluggyDiscoveryService.canDiscoverOverride = true;
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());

    Test.startTest();
    AXF_CLS_PluggyDiscoveryService.RegisterResult r = AXF_CLS_CTRL_SourceDiscovery.registerConnection(
      'ITEM_NEW_1'
    );
    Test.stopTest();

    System.assertEquals(true, r.created);
    System.assertEquals('Test Bank', r.institution);
    AXF_OBJ_PluggyConnection__c saved = [
      SELECT AXF_CON_TXT_ObservedItemId__c, AXF_CON_TXT_ConnectorId__c
      FROM AXF_OBJ_PluggyConnection__c
      WHERE AXF_CON_EXI_PluggyItemId__c = 'ITEM_NEW_1'
    ];
    System.assertEquals('ITEM_OBSERVED_A', saved.AXF_CON_TXT_ObservedItemId__c);
    System.assertEquals('201', saved.AXF_CON_TXT_ConnectorId__c);
  }

  @IsTest
  static void registerConnectionRejectsUnknownItemId() {
    AXF_CLS_PluggyDiscoveryService.canDiscoverOverride = true;
    AXF_CLS_PluggyHttpCalloutMock mock = new AXF_CLS_PluggyHttpCalloutMock();
    mock.itemStatus = 404;
    Test.setMock(HttpCalloutMock.class, mock);

    Boolean threw = false;
    Test.startTest();
    try {
      AXF_CLS_CTRL_SourceDiscovery.registerConnection('ITEM_GHOST');
    } catch (AuraHandledException e) {
      threw = true;
    }
    Test.stopTest();
    System.assertEquals(true, threw, 'a 404 Item ID must be rejected');
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM AXF_OBJ_PluggyConnection__c
        WHERE AXF_CON_EXI_PluggyItemId__c = 'ITEM_GHOST'
      ]
    );
  }

  @IsTest
  static void registerConnectionIsIdempotentOnTheItemId() {
    AXF_OBJ_PluggyConnection__c c = [
      SELECT Id
      FROM AXF_OBJ_PluggyConnection__c
      WHERE AXF_CON_EXI_PluggyItemId__c = 'ITEM_DUP'
      LIMIT 1
    ];
    AXF_CLS_PluggyDiscoveryService.canDiscoverOverride = true;
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());

    Test.startTest();
    AXF_CLS_PluggyDiscoveryService.RegisterResult r = AXF_CLS_CTRL_SourceDiscovery.registerConnection(
      'ITEM_DUP'
    );
    Test.stopTest();

    System.assertEquals(false, r.created);
    System.assertEquals(c.Id, r.connectionId);
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM AXF_OBJ_PluggyConnection__c
        WHERE AXF_CON_EXI_PluggyItemId__c = 'ITEM_DUP'
      ]
    );
  }

  @IsTest
  static void registerConnectionRejectsMeuPluggyLink() {
    AXF_CLS_PluggyTestData.grantIntegrationAccess();
    AXF_CLS_PluggyDiscoveryService.canDiscoverOverride = true;
    Boolean threw = false;
    try {
      AXF_CLS_CTRL_SourceDiscovery.registerConnection(
        'https://connect.meupluggy.com.br/abc'
      );
    } catch (AuraHandledException e) {
      threw = true;
    }
    System.assertEquals(true, threw, 'a MeuPluggy link must be rejected');
  }

  @IsTest
  static void registerConnectionRejectsInvalidItemId() {
    AXF_CLS_PluggyTestData.grantIntegrationAccess();
    AXF_CLS_PluggyDiscoveryService.canDiscoverOverride = true;
    Boolean threw = false;
    try {
      AXF_CLS_CTRL_SourceDiscovery.registerConnection('ab');
    } catch (AuraHandledException e) {
      threw = true;
    }
    System.assertEquals(true, threw, 'a too-short Item ID must be rejected');
  }

  @IsTest
  static void registerConnectionDeniedWithoutAuthority() {
    AXF_CLS_PluggyTestData.grantIntegrationAccess();
    AXF_CLS_PluggyDiscoveryService.canDiscoverOverride = false;
    Boolean threw = false;
    try {
      AXF_CLS_CTRL_SourceDiscovery.registerConnection('ITEM_DENIED');
    } catch (AuraHandledException e) {
      threw = true;
    }
    System.assertEquals(true, threw, 'no authority => denied');
  }

  @IsTest
  static void unauthorizedReturnsRetryableDto() {
    AXF_OBJ_PluggyConnection__c c = conn();
    AXF_CLS_PluggyDiscoveryService.canDiscoverOverride = false;

    AXF_CLS_PluggyDiscoveryService.DiscoveryResult r = AXF_CLS_CTRL_SourceDiscovery.startDiscovery(
      c.Id
    );
    System.assertEquals(false, r.complete);
    System.assert(r.message.containsIgnoreCase('autoriza'));
  }
}
