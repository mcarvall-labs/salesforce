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

  private static ALT_CLS_AxonOnboardingProgress.ConfirmInput confirm(
    String step,
    Integer version,
    String evidence
  ) {
    ALT_CLS_AxonOnboardingProgress.ConfirmInput c = new ALT_CLS_AxonOnboardingProgress.ConfirmInput();
    c.stepKey = step;
    c.expectedVersion = version;
    c.evidenceRef = evidence;
    return c;
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

    s = AXF_CLS_CTRL_OnboardingProgress.confirmStep(
      confirm('WELCOME_PREFS', s.version, 'BRL')
    );
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

    s = AXF_CLS_CTRL_OnboardingProgress.confirmStep(
      confirm('WELCOME_PREFS', s.version, 'BRL')
    );
    s = AXF_CLS_CTRL_OnboardingProgress.complete(s.version, true);
    Test.stopTest();
    System.assertEquals('COMPLETED', s.outcome);
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
