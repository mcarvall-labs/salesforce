/**
 * @description Thin Aura/LWC controller for the holder register (pessoas e empresas
 * titulares). Delegates all logic to ALT_CLS_AxonHolder. AXF-80.
 *
 * `with sharing` + the service's USER_MODE queries enforce object CRUD, FLS and
 * record sharing on every entry point, so a direct Apex/URL/API call from a user
 * without access is denied the same way the UI is (AC3).
 */
public with sharing class AXF_CLS_CTRL_Holder {
  @TestVisible
  private static Boolean canConfigureOverride;

  private static Boolean callerCanConfigure() {
    if (canConfigureOverride != null) {
      return canConfigureOverride;
    }
    return FeatureManagement.checkPermission('AXF_CanConfigure');
  }

  /**
   * @description Whether the caller may create / edit holders (AXF_CanConfigure).
   * Read access does not depend on this.
   */
  @AuraEnabled(cacheable=true)
  public static Boolean canConfigure() {
    return callerCanConfigure();
  }

  @AuraEnabled(cacheable=true)
  public static List<ALT_CLS_AxonHolder.HolderView> listHolders(String search) {
    return new ALT_CLS_AxonHolder().listHolders(search);
  }

  @AuraEnabled(cacheable=true)
  public static ALT_CLS_AxonHolder.HolderView getHolder(Id accountId) {
    return new ALT_CLS_AxonHolder().getHolder(accountId);
  }

  // Primitive params (not the service's inner DTO) so the LWC call binds reliably:
  // Aura does not populate the fields of an @AuraEnabled Apex class that is an inner
  // class of another top-level class, which silently delivered an all-null SaveInput
  // and made every holder registration fail with "tipo de titular invalido". Same
  // limitation already fixed in AXF_CLS_CTRL_OnboardingProgress. AXF-80 / AXF-106.
  @AuraEnabled
  public static ALT_CLS_AxonHolder.SaveResult saveHolder(
    Id accountId,
    String type,
    String firstName,
    String lastName,
    String name,
    Datetime expectedLastModifiedDate,
    Boolean confirmedDespiteDuplicates
  ) {
    ALT_CLS_AxonHolder.SaveInput input = new ALT_CLS_AxonHolder.SaveInput();
    input.accountId = accountId;
    input.type = type;
    input.firstName = firstName;
    input.lastName = lastName;
    input.name = name;
    input.expectedLastModifiedDate = expectedLastModifiedDate;
    input.confirmedDespiteDuplicates = confirmedDespiteDuplicates;
    return new ALT_CLS_AxonHolder().saveHolder(input);
  }
}
