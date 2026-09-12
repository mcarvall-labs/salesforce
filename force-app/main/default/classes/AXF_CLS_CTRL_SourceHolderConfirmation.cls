/**
 * @description Thin Aura/LWC controller for "Confirmar titulares das contas e
 * cartões" (AXF-85). Delegates to ALT_CLS_SourceHolderConfirmation; authority
 * (`AXF_CanConfigure`) is enforced in the service before any effect.
 */
public with sharing class AXF_CLS_CTRL_SourceHolderConfirmation {
  @AuraEnabled(cacheable=true)
  public static ALT_CLS_SourceHolderConfirmation.Overview getOverview() {
    return new ALT_CLS_SourceHolderConfirmation().overview();
  }

  @AuraEnabled(cacheable=true)
  public static ALT_CLS_SourceHolderConfirmation.SourceView getSourceHolder(
    Id sourceId,
    String kind
  ) {
    return new ALT_CLS_SourceHolderConfirmation()
      .getSourceHolder(sourceId, kind);
  }

  // Primitive params (not the service's inner DTO) so the LWC call binds reliably:
  // Aura does not populate the fields of an @AuraEnabled Apex class that is an inner
  // class of another top-level class, so ConfirmInput arrived all-null and every
  // confirmation was rejected as INVALID. Same limitation fixed in
  // AXF_CLS_CTRL_OnboardingProgress. AXF-85 / AXF-106.
  @AuraEnabled
  public static ALT_CLS_SourceHolderConfirmation.ConfirmResult confirmHolder(
    Id sourceId,
    String kind,
    Id holderId,
    Integer expectedVersion,
    String note
  ) {
    ALT_CLS_SourceHolderConfirmation.ConfirmInput input = new ALT_CLS_SourceHolderConfirmation.ConfirmInput();
    input.sourceId = sourceId;
    input.kind = kind;
    input.holderId = holderId;
    input.expectedVersion = expectedVersion;
    input.note = note;
    return new ALT_CLS_SourceHolderConfirmation().confirmHolder(input);
  }
}
