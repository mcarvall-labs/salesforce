/**
 * @description AXF-11 AC4/AC5. Pause/resume (local and global), the collection gate, and
 * revalidation of pending work.
 */
@IsTest
private class AXF_CLS_PluggyCollectionControlSvcTest {
  @IsTest
  static void gateAllowsActiveConnection() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection('ITEM_A');
    AXF_CLS_PluggyCollectionControlService svc = new AXF_CLS_PluggyCollectionControlService();
    System.assert(svc.isCollectionAllowed(c.Id));
    svc.assertCollectionAllowed(c.Id); // must not throw
  }

  @IsTest
  static void staleConsentBlocksCollection() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection('ITEM_A');
    c.AXF_CON_PKL_ConsentState__c = 'STALE';
    update c;

    try {
      new AXF_CLS_PluggyCollectionControlService()
        .assertCollectionAllowed(c.Id);
      System.assert(false, 'STALE consent must block');
    } catch (AXF_CLS_PluggyCollectionBlockedException e) {
      System.assert(
        e.getMessage().containsIgnoreCase('desatualizados') ||
        e.getMessage().containsIgnoreCase('expirado')
      );
    }
  }

  @IsTest
  static void revokedConsentBlocksCollection() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection('ITEM_A');
    c.AXF_CON_PKL_ConsentState__c = 'REVOKED';
    update c;
    System.assertEquals(
      false,
      new AXF_CLS_PluggyCollectionControlService().isCollectionAllowed(c.Id)
    );
  }

  @IsTest
  static void localPauseIsIdempotentAndBlocks() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection('ITEM_A');
    AXF_CLS_PluggyCollectionControlService.canConfigureOverride = true;
    AXF_CLS_PluggyCollectionControlService svc = new AXF_CLS_PluggyCollectionControlService();

    svc.pauseConnection(c.Id);
    svc.pauseConnection(c.Id); // idempotent, no error

    AXF_OBJ_PluggyConnection__c reloaded = [
      SELECT
        AXF_CON_PKL_CollectionState__c,
        AXF_CON_DT_PausedAt__c,
        AXF_CON_LKP_PausedBy__c
      FROM AXF_OBJ_PluggyConnection__c
      WHERE Id = :c.Id
    ];
    System.assertEquals('PAUSED', reloaded.AXF_CON_PKL_CollectionState__c);
    System.assertEquals(UserInfo.getUserId(), reloaded.AXF_CON_LKP_PausedBy__c);
    System.assertEquals(false, svc.isCollectionAllowed(c.Id));
  }

  @IsTest
  static void pauseRequiresAuthority() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection('ITEM_A');
    AXF_CLS_PluggyCollectionControlService.canConfigureOverride = false;
    try {
      new AXF_CLS_PluggyCollectionControlService().pauseConnection(c.Id);
      System.assert(false, 'unauthorized pause must fail');
    } catch (AXF_CLS_PluggyConfigException e) {
      System.assert(e.getMessage().containsIgnoreCase('autoriza'));
    }
  }

  @IsTest
  static void resumeRequiresSuccessfulConsentRevalidation() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection('ITEM_A');
    c.AXF_CON_PKL_CollectionState__c = 'PAUSED';
    c.AXF_CON_PKL_ConsentState__c = 'STALE';
    update c;
    AXF_CLS_PluggyCollectionControlService.canConfigureOverride = true;

    AXF_CLS_PluggyHttpCalloutMock mock = new AXF_CLS_PluggyHttpCalloutMock();
    mock.consentRevokedAt = '2026-06-01T00:00:00.000Z';
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    try {
      new AXF_CLS_PluggyCollectionControlService().resumeConnection(c.Id);
      System.assert(
        false,
        'resume must fail when consent is not ACTIVE after refresh'
      );
    } catch (AXF_CLS_PluggyCollectionBlockedException e) {
      // expected
    }
    Test.stopTest();

    System.assertEquals(
      'PAUSED',
      [
        SELECT AXF_CON_PKL_CollectionState__c
        FROM AXF_OBJ_PluggyConnection__c
        WHERE Id = :c.Id
      ]
      .AXF_CON_PKL_CollectionState__c
    );
  }

  @IsTest
  static void resumeSucceedsWhenConsentActive() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection('ITEM_A');
    c.AXF_CON_PKL_CollectionState__c = 'PAUSED';
    update c;
    AXF_CLS_PluggyCollectionControlService.canConfigureOverride = true;
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());

    Test.startTest();
    new AXF_CLS_PluggyCollectionControlService().resumeConnection(c.Id);
    Test.stopTest();

    AXF_OBJ_PluggyConnection__c reloaded = [
      SELECT AXF_CON_PKL_CollectionState__c, AXF_CON_DT_PausedAt__c
      FROM AXF_OBJ_PluggyConnection__c
      WHERE Id = :c.Id
    ];
    System.assertEquals('ACTIVE', reloaded.AXF_CON_PKL_CollectionState__c);
    System.assertEquals(null, reloaded.AXF_CON_DT_PausedAt__c);
  }

  @IsTest
  static void globalPauseBlocksEverythingAndRevalidatePendingCounts() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection('ITEM_A');
    AXF_CLS_PluggyCollectionControlService.canConfigureOverride = true;
    AXF_CLS_PluggyCollectionControlService svc = new AXF_CLS_PluggyCollectionControlService();

    svc.pauseGlobally();
    System.assertEquals(false, svc.isCollectionAllowed(c.Id));
    System.assertEquals(1, svc.revalidatePending());

    svc.resumeGlobally();
    System.assertEquals(true, svc.isCollectionAllowed(c.Id));
    System.assertEquals(0, svc.revalidatePending());
  }
}
