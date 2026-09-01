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
    AXF_CLS_PluggyTestData.connection('ITEM_A');
    AXF_CLS_PluggyTestData.config(true, 'CANDIDATE', 'PROMOTED');
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

  @IsTest
  static void stageCandidateCredentialTargetsCandidateSlot() {
    AXF_CLS_PluggyTestData.config(false, 'PRIMARY', 'NONE');
    AXF_CLS_CTRL_PluggyIntegrationConfig.canConfigureOverride = true;
    AXF_CLS_PluggyCredentialRotationService.canConfigureOverride = true;

    AXF_CLS_PluggyCredentialWriter.Result r = AXF_CLS_CTRL_PluggyIntegrationConfig.stageCandidateCredential(
      'cid',
      'csecret'
    );
    System.assertEquals(true, r.applied);
    System.assertEquals(
      'AXF_EXC_Pluggy_Candidate',
      AXF_CLS_PluggyCredentialWriter.lastExternalCredentialForTests
    );
    System.assertEquals('CANDIDATE', AXF_CLS_PluggySettings.rotationState());
  }

  @IsTest
  static void pauseAndResumeGloballyThroughController() {
    AXF_CLS_CTRL_PluggyIntegrationConfig.canConfigureOverride = true;
    AXF_CLS_PluggyCollectionControlService.canConfigureOverride = true;

    Test.startTest();
    AXF_CLS_CTRL_PluggyIntegrationConfig.pauseGlobally();
    System.assertEquals(
      true,
      AXF_CLS_PluggySettings.collectionGloballyPaused()
    );
    AXF_CLS_CTRL_PluggyIntegrationConfig.resumeGlobally();
    System.assertEquals(
      false,
      AXF_CLS_PluggySettings.collectionGloballyPaused()
    );
    Test.stopTest();
  }

  @IsTest
  static void rotationTestThroughController() {
    AXF_CLS_PluggyTestData.config(false, 'PRIMARY', 'NONE');
    AXF_CLS_CTRL_PluggyIntegrationConfig.canConfigureOverride = true;
    AXF_CLS_PluggyCredentialRotationService.canConfigureOverride = true;
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());
    AXF_CLS_PluggyCredentialRotationService.candidateClientForTests = new AXF_CLS_PluggyHttpClient();

    Test.startTest();
    AXF_CLS_PluggyCredentialRotationService.RotationResult r = AXF_CLS_CTRL_PluggyIntegrationConfig.testCandidate();
    Test.stopTest();

    System.assertEquals('TESTED_OK', r.state);
  }
}
