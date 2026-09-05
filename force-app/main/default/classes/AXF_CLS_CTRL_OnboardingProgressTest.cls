/**
 * @description Tests for AXF_CLS_CTRL_OnboardingProgress (AXF-88): the controller
 * only delegates, so this proves each entry point wires through and that
 * `canConfigure` reflects the caller.
 */
@IsTest(isParallel=false)
private class AXF_CLS_CTRL_OnboardingProgressTest {
  private static void allow() {
    ALT_CLS_AxonOnboardingProgress.canConfigureOverride = true;
    AXF_CLS_CTRL_OnboardingProgress.canConfigureOverride = true;
  }

  private static ALT_CLS_AxonOnboardingProgress.OnboardingState confirm(
    String step,
    Integer version,
    String evidence
  ) {
    return AXF_CLS_CTRL_OnboardingProgress.confirmStep(
      step,
      version,
      evidence,
      null
    );
  }

  @IsTest
  static void canConfigureReflectsCaller() {
    AXF_CLS_CTRL_OnboardingProgress.canConfigureOverride = false;
    System.assertEquals(false, AXF_CLS_CTRL_OnboardingProgress.canConfigure());
    AXF_CLS_CTRL_OnboardingProgress.canConfigureOverride = true;
    System.assertEquals(true, AXF_CLS_CTRL_OnboardingProgress.canConfigure());
  }

  @IsTest
  static void delegatesEveryEntryPoint() {
    allow();
    Test.startTest();
    ALT_CLS_AxonOnboardingProgress.OnboardingState s = AXF_CLS_CTRL_OnboardingProgress.getState();
    System.assertEquals(7, s.steps.size());

    s = confirm('WELCOME_PREFS', s.version, 'BRL');
    System.assertEquals('CONFIRMED', s.outcome);

    s = AXF_CLS_CTRL_OnboardingProgress.skipStep('PEOPLE_ACCESS', s.version);
    System.assertEquals('SKIPPED', s.outcome);

    s = AXF_CLS_CTRL_OnboardingProgress.markResultUnknown(
      'PLUGGY_CREDENTIALS',
      s.version,
      'corr-1'
    );
    System.assertEquals('UNKNOWN_PARKED', s.outcome);

    s = AXF_CLS_CTRL_OnboardingProgress.reconcileStep(
      'PLUGGY_CREDENTIALS',
      s.version,
      true,
      'nc-ref'
    );
    System.assertEquals('RECONCILED', s.outcome);

    s = AXF_CLS_CTRL_OnboardingProgress.reopenStep('WELCOME_PREFS', s.version);
    System.assertEquals('REOPENED', s.outcome);

    s = confirm('WELCOME_PREFS', s.version, 'BRL');
    s = AXF_CLS_CTRL_OnboardingProgress.complete(s.version, true);
    Test.stopTest();
    System.assertEquals('COMPLETED', s.outcome);
  }

  @IsTest
  static void confirmStepTakesPrimitiveParams() {
    allow();
    Test.startTest();
    ALT_CLS_AxonOnboardingProgress.OnboardingState s = AXF_CLS_CTRL_OnboardingProgress.getState();
    ALT_CLS_AxonOnboardingProgress.OnboardingState ok = AXF_CLS_CTRL_OnboardingProgress.confirmStep(
      'WELCOME_PREFS',
      s.version,
      'wizard',
      null
    );
    // a missing stepKey (the Aura-binding failure this signature fixes) is a
    // clean INVALID, never an unhandled exception
    ALT_CLS_AxonOnboardingProgress.OnboardingState bad = AXF_CLS_CTRL_OnboardingProgress.confirmStep(
      null,
      ok.version,
      'wizard',
      null
    );
    Test.stopTest();
    System.assertEquals('CONFIRMED', ok.outcome);
    System.assertEquals('INVALID', bad.outcome);
  }

  @IsTest
  static void forbiddenWithoutAuthority() {
    AXF_CLS_CTRL_OnboardingProgress.canConfigureOverride = false;
    ALT_CLS_AxonOnboardingProgress.canConfigureOverride = false;
    Test.startTest();
    ALT_CLS_AxonOnboardingProgress.OnboardingState s = AXF_CLS_CTRL_OnboardingProgress.getState();
    Test.stopTest();
    System.assert(s.forbidden);
  }
}
