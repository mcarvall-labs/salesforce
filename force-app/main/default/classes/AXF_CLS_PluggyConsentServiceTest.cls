/**
 * @description AXF-11 AC3/AC4, G4-5. Consent capture and state transitions.
 */
@IsTest
private class AXF_CLS_PluggyConsentServiceTest {
  @IsTest
  static void activeConsentMapsFieldsAndKeepsStateActive() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection('ITEM_A');
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());

    Test.startTest();
    AXF_CLS_PluggyConsentService.ConsentSnapshot snap = new AXF_CLS_PluggyConsentService()
      .refresh(c.Id);
    Test.stopTest();

    System.assertEquals('ACTIVE', snap.consentState);
    AXF_OBJ_PluggyConnection__c reloaded = [
      SELECT
        AXF_CON_TXT_ObservedItemId__c,
        AXF_CON_TXT_ConsentId__c,
        AXF_CON_TXT_ConsentObservedItemId__c,
        AXF_CON_TAL_ConsentScope__c,
        AXF_CON_DT_ConsentExpiresAt__c,
        AXF_CON_DT_ConsentCheckedAt__c,
        AXF_CON_EXI_PluggyItemId__c
      FROM AXF_OBJ_PluggyConnection__c
      WHERE Id = :c.Id
    ];
    System.assertEquals(
      'ITEM_OBSERVED_A',
      reloaded.AXF_CON_TXT_ObservedItemId__c
    );
    System.assertEquals(
      'ITEM_A',
      reloaded.AXF_CON_EXI_PluggyItemId__c,
      'operation key untouched'
    );
    System.assertEquals(
      'ITEM_ORIGIN_A',
      reloaded.AXF_CON_TXT_ConsentObservedItemId__c,
      'Consent.itemId preserved separately (D-85)'
    );
    System.assertEquals(
      null,
      reloaded.AXF_CON_DT_ConsentExpiresAt__c,
      'null expiresAt stays null'
    );
    System.assert(reloaded.AXF_CON_TAL_ConsentScope__c.contains('ACCOUNTS'));
    System.assertNotEquals(null, reloaded.AXF_CON_DT_ConsentCheckedAt__c);
  }

  @IsTest
  static void expiredConsentGoesStale() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection('ITEM_A');
    AXF_CLS_PluggyHttpCalloutMock mock = new AXF_CLS_PluggyHttpCalloutMock();
    mock.consentExpiresAt = '2020-01-01T00:00:00.000Z';
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    AXF_CLS_PluggyConsentService.ConsentSnapshot snap = new AXF_CLS_PluggyConsentService()
      .refresh(c.Id);
    Test.stopTest();

    System.assertEquals('STALE', snap.consentState);
    System.assertEquals(false, snap.collectionAllowed);
  }

  @IsTest
  static void revokedConsentGoesRevoked() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection('ITEM_A');
    AXF_CLS_PluggyHttpCalloutMock mock = new AXF_CLS_PluggyHttpCalloutMock();
    mock.consentRevokedAt = '2026-06-01T00:00:00.000Z';
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    AXF_CLS_PluggyConsentService.ConsentSnapshot snap = new AXF_CLS_PluggyConsentService()
      .refresh(c.Id);
    Test.stopTest();

    System.assertEquals('REVOKED', snap.consentState);
  }

  @IsTest
  static void loginErrorItemGoesRevoked() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection('ITEM_A');
    AXF_CLS_PluggyHttpCalloutMock mock = new AXF_CLS_PluggyHttpCalloutMock();
    mock.itemBodyStatus = 'LOGIN_ERROR';
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    AXF_CLS_PluggyConsentService.ConsentSnapshot snap = new AXF_CLS_PluggyConsentService()
      .refresh(c.Id);
    Test.stopTest();

    System.assertEquals('REVOKED', snap.consentState);
  }

  @IsTest
  static void forbiddenConsentsListDoesNotDowngradeActive() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection('ITEM_A');
    AXF_CLS_PluggyHttpCalloutMock mock = new AXF_CLS_PluggyHttpCalloutMock();
    mock.consentsStatus = 403; // free plan
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    AXF_CLS_PluggyConsentService.ConsentSnapshot snap = new AXF_CLS_PluggyConsentService()
      .refresh(c.Id);
    Test.stopTest();

    System.assertEquals(
      'ACTIVE',
      snap.consentState,
      '403 on /consents is not proof of revocation'
    );
  }

  @IsTest
  static void notFoundItemGoesRevoked() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection('ITEM_A');
    AXF_CLS_PluggyHttpCalloutMock mock = new AXF_CLS_PluggyHttpCalloutMock();
    mock.itemStatus = 404;
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    AXF_CLS_PluggyConsentService.ConsentSnapshot snap = new AXF_CLS_PluggyConsentService()
      .refresh(c.Id);
    Test.stopTest();

    System.assertEquals('REVOKED', snap.consentState);
  }

  @IsTest
  static void refreshByItemIdResolvesConnection() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection('ITEM_A');
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());

    Test.startTest();
    new AXF_CLS_PluggyConsentService().refreshByItemId('ITEM_A');
    Test.stopTest();

    AXF_OBJ_PluggyConnection__c reloaded = [
      SELECT AXF_CON_DT_ConsentCheckedAt__c
      FROM AXF_OBJ_PluggyConnection__c
      WHERE Id = :c.Id
    ];
    System.assertNotEquals(null, reloaded.AXF_CON_DT_ConsentCheckedAt__c);
  }
}
