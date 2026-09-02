/**
 * @description Thin Aura/LWC controller for onboarding progress (AXF-88).
 * Delegates to ALT_CLS_AxonOnboardingProgress.
 *
 * `with sharing`; authority (`AXF_CanConfigure`) is enforced in the service
 * before any effect and getState() returns `forbidden` with no rows when it is
 * missing (AC7). The wizard UI is AXF-90.
 */
public with sharing class AXF_CLS_CTRL_OnboardingProgress {
  @TestVisible
  private static Boolean canConfigureOverride;

  private static Boolean callerCanConfigure() {
    if (canConfigureOverride != null) {
      return canConfigureOverride;
    }
    return FeatureManagement.checkPermission('AXF_CanConfigure');
  }

  @AuraEnabled(cacheable=true)
  public static Boolean canConfigure() {
    return callerCanConfigure();
  }

  @AuraEnabled
  public static ALT_CLS_AxonOnboardingProgress.OnboardingState getState() {
    return new ALT_CLS_AxonOnboardingProgress().getState();
  }

  @AuraEnabled
  public static ALT_CLS_AxonOnboardingProgress.OnboardingState confirmStep(
    ALT_CLS_AxonOnboardingProgress.ConfirmInput input
  ) {
    return new ALT_CLS_AxonOnboardingProgress().confirmStep(input);
  }

  @AuraEnabled
  public static ALT_CLS_AxonOnboardingProgress.OnboardingState skipStep(
    String stepKey,
    Integer expectedVersion
  ) {
    return new ALT_CLS_AxonOnboardingProgress()
      .skipStep(stepKey, expectedVersion);
  }

  @AuraEnabled
  public static ALT_CLS_AxonOnboardingProgress.OnboardingState reopenStep(
    String stepKey,
    Integer expectedVersion
  ) {
    return new ALT_CLS_AxonOnboardingProgress()
      .reopenStep(stepKey, expectedVersion);
  }

  @AuraEnabled
  public static ALT_CLS_AxonOnboardingProgress.OnboardingState markResultUnknown(
    String stepKey,
    Integer expectedVersion,
    String correlationId
  ) {
    return new ALT_CLS_AxonOnboardingProgress()
      .markResultUnknown(stepKey, expectedVersion, correlationId);
  }

  @AuraEnabled
  public static ALT_CLS_AxonOnboardingProgress.OnboardingState reconcileStep(
    String stepKey,
    Integer expectedVersion,
    Boolean confirmed,
    String evidenceRef
  ) {
    return new ALT_CLS_AxonOnboardingProgress()
      .reconcileStep(stepKey, expectedVersion, confirmed, evidenceRef);
  }

  @AuraEnabled
  public static ALT_CLS_AxonOnboardingProgress.OnboardingState complete(
    Integer expectedVersion,
    Boolean acknowledgePending
  ) {
    return new ALT_CLS_AxonOnboardingProgress()
      .complete(expectedVersion, acknowledgePending);
  }
}
