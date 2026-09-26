/**
 * @description Thin controller for aXF_LWC_confirmSourceHolders (and the holder read of
 * aXF_LWC_onboardingWizard) over the legacy PROD model. Delegates to
 * ALT_CLS_SourceHolderLink; authority (AXF_CanConfigure) is enforced there.
 */
public with sharing class AXF_CLS_CTRL_SourceHolderConfirmation {
  // Test-only hook to exercise the sanitized error path.
  @TestVisible
  private static Boolean simulateFailure = false;

  @AuraEnabled(cacheable=true)
  public static AXF_CLS_SourceSetupDTO.HolderOverview getOverview() {
    try {
      if (simulateFailure) {
        throw new DmlException('Simulated failure');
      }
      return new ALT_CLS_SourceHolderLink().overview();
    } catch (Exception e) {
      String message = 'Não foi possível carregar as fontes.';
      AuraHandledException ex = new AuraHandledException(message);
      ex.setMessage(message);
      throw ex;
    }
  }

  // Primitive params so the LWC call binds reliably. The legacy model has no source
  // version nor confirmation note: expectedVersion and note are accepted and ignored.
  @AuraEnabled
  public static AXF_CLS_SourceSetupDTO.ConfirmResult confirmHolder(
    Id sourceId,
    String kind,
    Id holderId,
    Integer expectedVersion,
    String note
  ) {
    return new ALT_CLS_SourceHolderLink()
      .confirmHolder(sourceId, kind, holderId);
  }
}
