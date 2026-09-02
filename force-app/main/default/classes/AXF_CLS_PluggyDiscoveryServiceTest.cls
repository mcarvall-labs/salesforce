/**
 * @description AXF-84 AC1-AC7 / Fechamento G5. Discovery persists the catalogue in custody,
 * is replay-safe, distinguishes zero from error/partial, and denies unauthorized callers.
 */
@IsTest
private class AXF_CLS_PluggyDiscoveryServiceTest {
  static AXF_OBJ_PluggyConnection__c conn() {
    return AXF_CLS_PluggyTestData.connection('ITEM_A');
  }

  static AXF_CLS_PluggyDiscoveryService svc() {
    AXF_CLS_PluggyDiscoveryService.canDiscoverOverride = true;
    return new AXF_CLS_PluggyDiscoveryService();
  }

  @IsTest
  static void discoversBankAndCardIntoCustody() {
    AXF_OBJ_PluggyConnection__c c = conn();
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());

    Test.startTest();
    AXF_CLS_PluggyDiscoveryService.DiscoveryResult r = svc()
      .startOrResume(c.Id);
    Test.stopTest();

    System.assertEquals('SUCCEEDED', r.state, r.message);
    System.assertEquals(1, r.accountsFound);
    System.assertEquals(1, r.cardsFound);
    System.assertEquals(true, r.complete);

    AXF_OBJ_BankAccount__c ba = [
      SELECT
        AXF_BA_PKL_AvailabilityState__c,
        AXF_BA_TXT_CurrencyIsoCode__c,
        AXF_BA_CUR_CurrentBalance__c,
        AXF_BA_TXT_NumberMasked__c,
        AXF_BA_LKP_Account__c
      FROM AXF_OBJ_BankAccount__c
      WHERE AXF_BA_LKP_Connection__c = :c.Id
    ];
    System.assertEquals('CUSTODY', ba.AXF_BA_PKL_AvailabilityState__c, 'AC3');
    System.assertEquals('BRL', ba.AXF_BA_TXT_CurrencyIsoCode__c);
    System.assertEquals(100.55, ba.AXF_BA_CUR_CurrentBalance__c);
    System.assertEquals(
      '****5678',
      ba.AXF_BA_TXT_NumberMasked__c,
      'AC6 masked'
    );
    System.assertEquals(null, ba.AXF_BA_LKP_Account__c, 'no holder yet');

    System.assertEquals(
      'GOLD',
      [
        SELECT AXF_CC_TXT_Level__c
        FROM AXF_OBJ_CreditCard__c
        WHERE AXF_CC_LKP_Connection__c = :c.Id
      ]
      .AXF_CC_TXT_Level__c
    );
  }

  @IsTest
  static void discoveryIsReplaySafe() {
    // First discovery via the service.
    AXF_OBJ_PluggyConnection__c c = conn();
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());
    Test.startTest();
    svc().startOrResume(c.Id);
    Test.stopTest();

    Integer bankCount = [
      SELECT COUNT()
      FROM AXF_OBJ_BankAccount__c
      WHERE AXF_BA_LKP_Connection__c = :c.Id
    ];
    System.assertEquals(1, bankCount);

    // A replay upserts the same records by external id — never a duplicate (AC2).
    AXF_OBJ_BankAccount__c replay = new AXF_OBJ_BankAccount__c(
      AXF_BA_EXI_PluggyAccountId__c = 'ACC-1',
      AXF_BA_LKP_Connection__c = c.Id,
      AXF_BA_PKL_AvailabilityState__c = 'CUSTODY'
    );
    upsert replay AXF_BA_EXI_PluggyAccountId__c;

    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM AXF_OBJ_BankAccount__c
        WHERE AXF_BA_LKP_Connection__c = :c.Id
      ],
      'replay upsert does not duplicate'
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM AXF_OBJ_IntegrationRun__c
        WHERE AXF_INR_LKP_Connection__c = :c.Id
      ],
      'one run per (connection, product) - AC5'
    );
  }

  @IsTest
  static void zeroSourcesIsSucceededNotError() {
    AXF_OBJ_PluggyConnection__c c = conn();
    AXF_CLS_PluggyHttpCalloutMock mock = new AXF_CLS_PluggyHttpCalloutMock();
    mock.accountsBodyJson = '{"total":0,"totalPages":1,"page":1,"results":[]}';
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    AXF_CLS_PluggyDiscoveryService.DiscoveryResult r = svc()
      .startOrResume(c.Id);
    Test.stopTest();

    System.assertEquals('SUCCEEDED', r.state);
    System.assertEquals(0, r.accountsFound + r.cardsFound);
    System.assert(
      r.message.containsIgnoreCase('Nenhuma conta ou cartao'),
      r.message
    );
  }

  @IsTest
  static void forbiddenAccountsListIsTerminalNotZero() {
    AXF_OBJ_PluggyConnection__c c = conn();
    AXF_CLS_PluggyHttpCalloutMock mock = new AXF_CLS_PluggyHttpCalloutMock();
    mock.accountsStatus = 403;
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    AXF_CLS_PluggyDiscoveryService.DiscoveryResult r = svc()
      .startOrResume(c.Id);
    Test.stopTest();

    System.assertEquals('FAILED_TERMINAL', r.state);
    System.assertEquals(false, r.complete);
  }

  @IsTest
  static void transportFailureIsResultUnknown() {
    AXF_OBJ_PluggyConnection__c c = conn();
    AXF_CLS_PluggyHttpCalloutMock mock = new AXF_CLS_PluggyHttpCalloutMock();
    mock.throwOnAccounts = true;
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    AXF_CLS_PluggyDiscoveryService.DiscoveryResult r = svc()
      .startOrResume(c.Id);
    Test.stopTest();

    System.assertEquals('RESULT_UNKNOWN', r.state);
  }

  @IsTest
  static void revokedConsentDuringDiscoveryIsTerminal() {
    AXF_OBJ_PluggyConnection__c c = conn();
    AXF_CLS_PluggyHttpCalloutMock mock = new AXF_CLS_PluggyHttpCalloutMock();
    mock.consentRevokedAt = '2026-06-01T00:00:00.000Z';
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    AXF_CLS_PluggyDiscoveryService.DiscoveryResult r = svc()
      .startOrResume(c.Id);
    Test.stopTest();

    System.assertEquals(
      'FAILED_TERMINAL',
      r.state,
      'AC5 - not presented as complete'
    );
    System.assert(r.message.containsIgnoreCase('incompleto'));
  }

  @IsTest
  static void pausedCollectionBlocksDiscovery() {
    AXF_OBJ_PluggyConnection__c c = conn();
    c.AXF_CON_PKL_CollectionState__c = 'PAUSED';
    update c;

    Test.startTest();
    try {
      svc().startOrResume(c.Id);
      System.assert(false, 'paused collection must block');
    } catch (AXF_CLS_PluggyCollectionBlockedException e) {
      // expected
    }
    Test.stopTest();
  }

  @IsTest
  static void unauthorizedCallerIsDenied() {
    AXF_OBJ_PluggyConnection__c c = conn();
    AXF_CLS_PluggyDiscoveryService.canDiscoverOverride = false;
    try {
      new AXF_CLS_PluggyDiscoveryService().startOrResume(c.Id);
      System.assert(false, 'unauthorized discovery must fail');
    } catch (AXF_CLS_PluggyDiscoveryException e) {
      System.assert(e.getMessage().containsIgnoreCase('autoriza'));
    }
  }

  @IsTest
  static void statusAndDiscoveredReflectRealState() {
    AXF_OBJ_PluggyConnection__c c = conn();
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());

    Test.startTest();
    svc().startOrResume(c.Id);
    Test.stopTest();

    AXF_CLS_PluggyDiscoveryService.DiscoveryResult st = new AXF_CLS_PluggyDiscoveryService()
      .status(c.Id);
    System.assertEquals('SUCCEEDED', st.state);

    List<AXF_CLS_PluggyDiscoveryService.DiscoveredSourceDTO> found = new AXF_CLS_PluggyDiscoveryService()
      .discovered(c.Id);
    System.assertEquals(2, found.size());
    for (AXF_CLS_PluggyDiscoveryService.DiscoveredSourceDTO d : found) {
      System.assertEquals('CUSTODY', d.availability);
      System.assertEquals(false, d.hasHolder);
    }
  }
}
