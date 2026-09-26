/**
 * @description AXF-11. The config controller gates on AXF_CanConfigure and returns a clean
 * FORBIDDEN status, never a secret or a stack trace.
 */
@IsTest
private class AXF_CLS_CTRL_PluggyIntegrationConfigTest {
  @IsTest
  static void forbiddenWhenCallerCannotConfigure() {
    AXF_CLS_CTRL_PluggyIntegrationConfig.canConfigureOverride = false;

    System.assertEquals(
      false,
      AXF_CLS_CTRL_PluggyIntegrationConfig.canConfigure()
    );
    AXF_CLS_CTRL_PluggyIntegrationConfig.StatusDTO d = AXF_CLS_CTRL_PluggyIntegrationConfig.getStatus();
    System.assertEquals(false, d.canConfigure);
    System.assertEquals(
      null,
      d.activeSlot,
      'no data leaked to an unauthorized caller'
    );
  }

  @IsTest
  static void statusReflectsSettingsWhenAuthorized() {
    AXF_OBJ_BankInstitution__c bank = new AXF_OBJ_BankInstitution__c(
      Name = 'Banco Config',
      AXF_BI_EXI_Bank_Number__c = '998'
    );
    insert bank;
    insert new AXF_OBJ_PluggyConnection__c(
      AXF_CON_EXI_PluggyItemId__c = 'ITEM_A',
      AXF_CON_LKP_BankInstitution__c = bank.Id
    );
    insert new AXF_PluggyIntegrationConfig__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      AXF_PIC_BOL_CollectionGloballyPaused__c = true,
      AXF_PIC_TXT_ActiveSlot__c = 'CANDIDATE',
      AXF_PIC_TXT_RotationState__c = 'PROMOTED'
    );
    AXF_CLS_CTRL_PluggyIntegrationConfig.canConfigureOverride = true;

    AXF_CLS_CTRL_PluggyIntegrationConfig.StatusDTO d = AXF_CLS_CTRL_PluggyIntegrationConfig.getStatus();

    System.assertEquals(true, d.canConfigure);
    System.assertEquals('CANDIDATE', d.activeSlot);
    System.assertEquals(true, d.collectionGloballyPaused);
    System.assertEquals(1, d.connectionCount);
  }

  @IsTest
  static void setPrincipalCredentialForbiddenWithoutAuthority() {
    AXF_CLS_CTRL_PluggyIntegrationConfig.canConfigureOverride = false;
    AXF_CLS_PluggyCredentialWriter.Result r = AXF_CLS_CTRL_PluggyIntegrationConfig.setPrincipalCredential(
      'cid',
      'csecret'
    );
    System.assertEquals(false, r.applied);
    System.assert(r.message.containsIgnoreCase('autoriza'));
  }

  @IsTest
  static void setPrincipalCredentialForwardsToNativeMechanism() {
    AXF_CLS_CTRL_PluggyIntegrationConfig.canConfigureOverride = true;
    AXF_CLS_PluggyCredentialWriter.Result r = AXF_CLS_CTRL_PluggyIntegrationConfig.setPrincipalCredential(
      'cid',
      'csecret'
    );
    System.assertEquals(true, r.applied);
    System.assertEquals(
      'AXF_EXC_Pluggy',
      AXF_CLS_PluggyCredentialWriter.lastExternalCredentialForTests
    );
    System.assertEquals(
      true,
      AXF_CLS_PluggyCredentialWriter.lastHadSecretForTests
    );
  }

  @IsTest
  static void setPrincipalCredentialRejectsBlank() {
    AXF_CLS_CTRL_PluggyIntegrationConfig.canConfigureOverride = true;
    AXF_CLS_PluggyCredentialWriter.Result r = AXF_CLS_CTRL_PluggyIntegrationConfig.setPrincipalCredential(
      'cid',
      ''
    );
    System.assertEquals(false, r.applied);
  }
}
