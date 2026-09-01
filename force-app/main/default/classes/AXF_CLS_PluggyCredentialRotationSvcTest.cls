/**
 * @description AXF-11 AC2, G4-2. Candidate is tested before promotion; a failing candidate
 * never touches the active slot; concurrency yields CONFLICT; promotion flips the pointer.
 */
@IsTest
private class AXF_CLS_PluggyCredentialRotationSvcTest {
  @IsTest
  static void healthyCandidateCanBePromoted() {
    AXF_CLS_PluggyTestData.connection('ITEM_A');
    AXF_CLS_PluggyTestData.config(false, 'PRIMARY', 'NONE');
    AXF_CLS_PluggyCredentialRotationService.canConfigureOverride = true;
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());
    AXF_CLS_PluggyCredentialRotationService.candidateClientForTests = new AXF_CLS_PluggyHttpClient();

    Test.startTest();
    AXF_CLS_PluggyCredentialRotationService svc = new AXF_CLS_PluggyCredentialRotationService();
    AXF_CLS_PluggyCredentialRotationService.RotationResult testRes = svc.testCandidate();
    System.assertEquals(true, testRes.candidateHealthy, testRes.message);
    System.assertEquals('TESTED_OK', testRes.state);

    AXF_CLS_PluggyCredentialRotationService.RotationResult prom = svc.promote();
    Test.stopTest();

    System.assertEquals('PROMOTED', prom.state);
    System.assertEquals(
      'CANDIDATE',
      AXF_CLS_PluggySettings.activeSlot(),
      'pointer flipped'
    );
  }

  @IsTest
  static void failingCandidatePreservesActive() {
    AXF_CLS_PluggyTestData.connection('ITEM_A');
    AXF_CLS_PluggyTestData.config(false, 'PRIMARY', 'NONE');
    AXF_CLS_PluggyCredentialRotationService.canConfigureOverride = true;

    AXF_CLS_PluggyHttpCalloutMock mock = new AXF_CLS_PluggyHttpCalloutMock();
    mock.authStatus = 401; // candidate cannot authenticate
    Test.setMock(HttpCalloutMock.class, mock);
    AXF_CLS_PluggyCredentialRotationService.candidateClientForTests = new AXF_CLS_PluggyHttpClient();

    Test.startTest();
    AXF_CLS_PluggyCredentialRotationService svc = new AXF_CLS_PluggyCredentialRotationService();
    AXF_CLS_PluggyCredentialRotationService.RotationResult testRes = svc.testCandidate();
    Test.stopTest();

    System.assertEquals(false, testRes.candidateHealthy);
    System.assertEquals('ROLLED_BACK', testRes.state);
    System.assertEquals(
      'PRIMARY',
      AXF_CLS_PluggySettings.activeSlot(),
      'active slot untouched'
    );

    try {
      svc.promote();
      System.assert(false, 'must not promote a failed candidate');
    } catch (AXF_CLS_PluggyConfigException e) {
      // expected
    }
  }

  @IsTest
  static void concurrentTestYieldsConflict() {
    AXF_CLS_PluggyTestData.config(false, 'PRIMARY', 'TESTING');
    AXF_CLS_PluggyCredentialRotationService.canConfigureOverride = true;

    try {
      new AXF_CLS_PluggyCredentialRotationService().testCandidate();
      System.assert(false, 'a TESTING state must block a second test');
    } catch (AXF_CLS_PluggyConfigException e) {
      System.assert(e.getMessage().containsIgnoreCase('CONFLICT'));
    }
  }

  @IsTest
  static void rotationRequiresAuthority() {
    AXF_CLS_PluggyCredentialRotationService.canConfigureOverride = false;
    try {
      new AXF_CLS_PluggyCredentialRotationService().testCandidate();
      System.assert(false, 'unauthorized rotation must fail');
    } catch (AXF_CLS_PluggyConfigException e) {
      System.assert(e.getMessage().containsIgnoreCase('autoriza'));
    }
  }

  @IsTest
  static void rotatesFromCandidateBackToPrimary() {
    AXF_CLS_PluggyTestData.connection('ITEM_A');
    AXF_CLS_PluggyTestData.config(false, 'CANDIDATE', 'NONE');
    AXF_CLS_PluggyCredentialRotationService.canConfigureOverride = true;
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());
    AXF_CLS_PluggyCredentialRotationService.candidateClientForTests = new AXF_CLS_PluggyHttpClient();

    Test.startTest();
    AXF_CLS_PluggyCredentialRotationService svc = new AXF_CLS_PluggyCredentialRotationService();
    System.assertEquals('TESTED_OK', svc.testCandidate().state);
    System.assertEquals('PROMOTED', svc.promote().state);
    Test.stopTest();

    System.assertEquals('PRIMARY', AXF_CLS_PluggySettings.activeSlot());
  }

  @IsTest
  static void promoteWithoutTestIsRejected() {
    AXF_CLS_PluggyTestData.config(false, 'PRIMARY', 'NONE');
    AXF_CLS_PluggyCredentialRotationService.canConfigureOverride = true;
    try {
      new AXF_CLS_PluggyCredentialRotationService().promote();
      System.assert(false, 'promote without a passing test must fail');
    } catch (AXF_CLS_PluggyConfigException e) {
      System.assert(e.getMessage().containsIgnoreCase('teste'));
    }
  }

  @IsTest
  static void rollbackLeavesActiveUnchanged() {
    AXF_CLS_PluggyTestData.config(false, 'PRIMARY', 'TESTED_OK');
    AXF_CLS_PluggyCredentialRotationService.canConfigureOverride = true;

    AXF_CLS_PluggyCredentialRotationService.RotationResult r = new AXF_CLS_PluggyCredentialRotationService()
      .rollback();

    System.assertEquals('ROLLED_BACK', r.state);
    System.assertEquals('PRIMARY', AXF_CLS_PluggySettings.activeSlot());
  }
}
