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

  @AuraEnabled
  public static ALT_CLS_AxonHolder.SaveResult saveHolder(ALT_CLS_AxonHolder.SaveInput input) {
    return new ALT_CLS_AxonHolder().saveHolder(input);
  }
}
