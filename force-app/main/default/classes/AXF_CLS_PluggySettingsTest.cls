/**
 * @description Focused tests for AXF_CLS_PluggySettings: code defaults before the
 * org-default row exists, slot resolution and the persisted working row.
 */
@IsTest(isParallel=false)
private class AXF_CLS_PluggySettingsTest {
  @IsTest
  static void defaultsApplyWithoutOrgRow() {
    delete [SELECT Id FROM AXF_PluggyIntegrationConfig__c];
    System.assertEquals(
      AXF_CLS_PluggySettings.NC_PRIMARY,
      AXF_CLS_PluggySettings.activeNamedCredential()
    );
    System.assertEquals(
      AXF_CLS_PluggySettings.SLOT_PRIMARY,
      AXF_CLS_PluggySettings.activeSlot()
    );
    System.assertEquals(
      false,
      AXF_CLS_PluggySettings.collectionGloballyPaused()
    );
    System.assertEquals(true, AXF_CLS_PluggySettings.webhookEnabled());
    System.assertEquals('NONE', AXF_CLS_PluggySettings.rotationState());
  }

  @IsTest
  static void saveCandidateSlotIsReadBack() {
    delete [SELECT Id FROM AXF_PluggyIntegrationConfig__c];
    AXF_PluggyIntegrationConfig__c row = AXF_CLS_PluggySettings.currentOrgDefaultForUpdate();
    row.AXF_PIC_TXT_ActiveSlot__c = 'candidate';
    row.AXF_PIC_BOL_CollectionGloballyPaused__c = true;
    row.AXF_PIC_BOL_WebhookEnabled__c = false;
    row.AXF_PIC_TXT_RotationState__c = 'PENDING';

    Test.startTest();
    AXF_CLS_PluggySettings.save(row);
    Test.stopTest();

    System.assertNotEquals(null, row.Id, 'org-default row persisted');
    System.assertEquals(
      AXF_CLS_PluggySettings.NC_CANDIDATE,
      AXF_CLS_PluggySettings.activeNamedCredential()
    );
    System.assertEquals(
      AXF_CLS_PluggySettings.SLOT_CANDIDATE,
      AXF_CLS_PluggySettings.activeSlot()
    );
    System.assertEquals(
      true,
      AXF_CLS_PluggySettings.collectionGloballyPaused()
    );
    System.assertEquals(false, AXF_CLS_PluggySettings.webhookEnabled());
    System.assertEquals('PENDING', AXF_CLS_PluggySettings.rotationState());
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM AXF_PluggyIntegrationConfig__c
        WHERE SetupOwnerId = :UserInfo.getOrganizationId()
      ]
    );
  }

  @IsTest
  static void overrideForTestsIsUsed() {
    AXF_CLS_PluggySettings.overrideForTests = new AXF_PluggyIntegrationConfig__c(
      AXF_PIC_BOL_WebhookEnabled__c = false
    );
    System.assertEquals(false, AXF_CLS_PluggySettings.webhookEnabled());
  }
}
