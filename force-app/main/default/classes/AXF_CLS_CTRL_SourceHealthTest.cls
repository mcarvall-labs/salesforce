/**
 * @description AXF-11 AC7. Saude das fontes lists institution/consent/collection/last
 * success/impact/permitted action, exposes no secret, and honours authority for actions.
 */
@IsTest
private class AXF_CLS_CTRL_SourceHealthTest {
  @IsTest
  static void listsSourcesWithImpactAndAction() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection('ITEM_A');
    c.AXF_CON_DT_LastSuccessAt__c = Datetime.now().addDays(-1);
    c.AXF_CON_TXT_LastStatusCode__c = 'OK';
    update c;
    AXF_CLS_CTRL_SourceHealth.canManageOverride = true;

    List<AXF_CLS_CTRL_SourceHealth.SourceDTO> rows = AXF_CLS_CTRL_SourceHealth.getSources();

    System.assertEquals(1, rows.size());
    AXF_CLS_CTRL_SourceHealth.SourceDTO d = rows[0];
    System.assertEquals('Test Bank', d.institution);
    System.assertEquals('ACTIVE', d.consentState);
    System.assertEquals('PAUSE', d.permittedAction);
    System.assert(d.impact.containsIgnoreCase('ativa'));
    // DTO has no secret-bearing field by construction; sanity check the visible text.
    System.assert(!String.valueOf(d).containsIgnoreCase('secret'));
  }

  @IsTest
  static void revokedShowsReauthorizeAction() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection('ITEM_A');
    c.AXF_CON_PKL_ConsentState__c = 'REVOKED';
    update c;
    AXF_CLS_CTRL_SourceHealth.canManageOverride = true;

    AXF_CLS_CTRL_SourceHealth.SourceDTO d = AXF_CLS_CTRL_SourceHealth.getSources()[0];
    System.assertEquals('REAUTHORIZE', d.permittedAction);
    System.assert(d.impact.containsIgnoreCase('revogado'));
  }

  @IsTest
  static void unauthorizedCallerGetsNoActions() {
    AXF_CLS_PluggyTestData.connection('ITEM_A');
    AXF_CLS_CTRL_SourceHealth.canManageOverride = false;

    AXF_CLS_CTRL_SourceHealth.SourceDTO d = AXF_CLS_CTRL_SourceHealth.getSources()[0];
    System.assertEquals(false, d.canManage);
    System.assertEquals('NONE', d.permittedAction);
  }

  @IsTest
  static void pauseThroughControllerRequiresAuthority() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection('ITEM_A');
    AXF_CLS_PluggyCollectionControlService.canConfigureOverride = false;
    try {
      AXF_CLS_CTRL_SourceHealth.pauseConnection(c.Id);
      System.assert(false, 'unauthorized pause must fail');
    } catch (AXF_CLS_PluggyConfigException e) {
      // expected
    }
  }

  @IsTest
  static void refreshConsentThroughController() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection('ITEM_A');
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());

    Test.startTest();
    AXF_CLS_PluggyConsentService.ConsentSnapshot snap = AXF_CLS_CTRL_SourceHealth.refreshConsent(
      c.Id
    );
    Test.stopTest();

    System.assertEquals('ACTIVE', snap.consentState);
  }
}
