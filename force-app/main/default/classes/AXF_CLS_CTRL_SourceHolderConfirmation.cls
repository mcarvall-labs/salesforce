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

  @AuraEnabled
  public static ALT_CLS_SourceHolderConfirmation.ConfirmResult confirmHolder(
    ALT_CLS_SourceHolderConfirmation.ConfirmInput input
  ) {
    return new ALT_CLS_SourceHolderConfirmation().confirmHolder(input);
  }
}
