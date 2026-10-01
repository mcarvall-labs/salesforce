public with sharing class AXF_CLS_CTRL_PluggyWizard {
  public class WizardState {
    @AuraEnabled
    public Boolean hasCredentials;
  }

  public class StepResult {
    @AuraEnabled
    public Boolean success;
    @AuraEnabled
    public String message;
  }

  @AuraEnabled(cacheable=false)
  public static WizardState getState() {
    WizardState state = new WizardState();
    state.hasCredentials = new ALT_CLS_PluggyCredential().hasCredentials();
    return state;
  }

  @AuraEnabled
  public static StepResult saveCredentials(
    String clientId,
    String clientSecret
  ) {
    return toStepResult(
      new ALT_CLS_PluggyCredential().save(clientId, clientSecret)
    );
  }

  @AuraEnabled
  public static StepResult testCredentials() {
    return toStepResult(new ALT_CLS_PluggyCredential().testAuthentication());
  }

  private static StepResult toStepResult(
    ALT_CLS_PluggyCredential.Result result
  ) {
    StepResult stepResult = new StepResult();
    stepResult.success = result.success;
    stepResult.message = result.message;
    return stepResult;
  }
}
