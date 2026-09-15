/**
 * @description AXF-12 — the Aura/LWC surface starts an on-demand run, reads per-scope health,
 * and surfaces a blocked collection as a sanitized error.
 */
@IsTest
private class AXF_CLS_CTRL_PluggySyncTest {
  @TestSetup
  static void seed() {
    AXF_CLS_PluggyTestData.grantIntegrationAccess();
    AXF_CLS_PluggyTestData.config(false, 'A', 'TESTED_OK');
    AXF_OBJ_PluggyConnection__c conn = AXF_CLS_PluggyTestData.connection(
      'ITEMCTRL'
    );
    AXF_CLS_PluggyTestData.bankAccount(conn.Id, 'CTRL-BANK-1', true);
  }

  static Id connId() {
    return [SELECT Id FROM AXF_OBJ_PluggyConnection__c LIMIT 1].Id;
  }

  static void policy() {
    AXF_CLS_PluggySyncService.canConfigureOverride = true;
    AXF_CLS_PluggySyncPolicy.overrideRecord = AXF_CLS_PluggyTestData.syncPolicy(
      100,
      10,
      3
    );
  }

  @IsTest
  static void syncNowEnqueuesTheWorkerChain() {
    policy();
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());
    Test.startTest();
    String message = AXF_CLS_CTRL_PluggySync.syncNow(connId());
    Test.stopTest();
    System.assert(message.containsIgnoreCase('sincroniza'), message);
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM AsyncApexJob
        WHERE
          JobType = 'Queueable'
          AND ApexClass.Name = 'AXF_CLS_PluggySyncQueueable'
      ]
    );
  }

  @IsTest
  static void syncNowWithNothingReadyReturnsAFriendlyMessage() {
    policy();
    // mark the only account back into custody
    AXF_OBJ_BankAccount__c b = [SELECT Id FROM AXF_OBJ_BankAccount__c LIMIT 1];
    b.AXF_BA_PKL_AvailabilityState__c = 'CUSTODY';
    update b;
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());
    Test.startTest();
    String message = AXF_CLS_CTRL_PluggySync.syncNow(connId());
    Test.stopTest();
    System.assert(message.containsIgnoreCase('nada a sincronizar'), message);
  }

  @IsTest
  static void healthReturnsRows() {
    policy();
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());
    Test.startTest();
    List<AXF_CLS_PluggySyncService.HealthRow> rows = AXF_CLS_CTRL_PluggySync.health(
      connId()
    );
    Test.stopTest();
    System.assertEquals(1, rows.size());
    System.assertEquals('BANK', rows[0].kind);
  }

  @IsTest
  static void missingPolicySurfacesAsAuraError() {
    AXF_CLS_PluggySyncService.canConfigureOverride = true;
    AXF_CLS_PluggySyncPolicy.forceMissing = true;
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());
    try {
      AXF_CLS_CTRL_PluggySync.syncNow(connId());
      System.assert(false, 'expected AuraHandledException');
    } catch (AuraHandledException e) {
      System.assert(true);
    }
  }

  @IsTest
  static void withoutAuthoritySurfacesAsAuraError() {
    AXF_CLS_PluggySyncService.canConfigureOverride = false;
    AXF_CLS_PluggySyncPolicy.overrideRecord = AXF_CLS_PluggyTestData.syncPolicy(
      100,
      10,
      3
    );
    try {
      AXF_CLS_CTRL_PluggySync.health(connId());
      System.assert(false, 'expected AuraHandledException');
    } catch (AuraHandledException e) {
      System.assert(true);
    }
  }

  @IsTest
  static void blockedCollectionSurfacesAsAuraError() {
    policy();
    AXF_CLS_PluggyTestData.grantIntegrationAccess();
    AXF_PluggyIntegrationConfig__c cfg = [
      SELECT Id, AXF_PIC_BOL_CollectionGloballyPaused__c
      FROM AXF_PluggyIntegrationConfig__c
      LIMIT 1
    ];
    cfg.AXF_PIC_BOL_CollectionGloballyPaused__c = true;
    update cfg;

    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());
    Test.startTest();
    try {
      AXF_CLS_CTRL_PluggySync.syncNow(connId());
      System.assert(false, 'expected AuraHandledException');
    } catch (AuraHandledException e) {
      System.assert(true);
    }
    Test.stopTest();
  }
}
