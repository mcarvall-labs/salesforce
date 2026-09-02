/**
 * @description Thin Aura/LWC controller for "Vincular responsáveis por empresa e
 * conceder acesso financeiro" (AXF-83). Delegates to
 * ALT_CLS_AxonCompanyResponsible; authority (`AXF_CanConfigure`) is enforced in
 * the service before any effect.
 */
public with sharing class AXF_CLS_CTRL_CompanyResponsible {
  @TestVisible
  private static Boolean canConfigureOverride;

  private static Boolean callerCanConfigure() {
    if (canConfigureOverride != null) {
      return canConfigureOverride;
    }
    return FeatureManagement.checkPermission('AXF_CanConfigure');
  }

  public class AccountOption {
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String name;
  }

  @AuraEnabled(cacheable=true)
  public static Boolean canConfigure() {
    return callerCanConfigure();
  }

  @AuraEnabled(cacheable=true)
  public static List<AccountOption> findAccounts(
    String search,
    String recordType
  ) {
    if (
      !callerCanConfigure() ||
      String.isBlank(search) ||
      search.trim().length() < 2 ||
      search.contains('%') ||
      search.contains('_') ||
      search.contains('\\') ||
      (recordType != 'BUSINESS' &&
      recordType != 'PERSON')
    ) {
      return new List<AccountOption>();
    }
    String rt = recordType == 'BUSINESS' ? 'AXF_Business' : 'AXF_Person';
    String pattern = '%' + search.trim() + '%';
    List<AccountOption> out = new List<AccountOption>();
    for (Account a : [
      SELECT Id, Name
      FROM Account
      WHERE RecordType.DeveloperName = :rt AND Name LIKE :pattern
      WITH USER_MODE
      ORDER BY Name
      LIMIT 50
    ]) {
      AccountOption o = new AccountOption();
      o.accountId = a.Id;
      o.name = a.Name;
      out.add(o);
    }
    return out;
  }

  @AuraEnabled(cacheable=true)
  public static List<ALT_CLS_AxonCompanyResponsible.ResponsibilityView> getResponsibilities(
    Id businessId
  ) {
    return new ALT_CLS_AxonCompanyResponsible().getResponsibilities(businessId);
  }

  @AuraEnabled
  public static ALT_CLS_AxonCompanyResponsible.ResponsibilityView confirmResponsibility(
    ALT_CLS_AxonCompanyResponsible.ConfirmInput input
  ) {
    return new ALT_CLS_AxonCompanyResponsible().confirmResponsibility(input);
  }

  @AuraEnabled
  public static ALT_CLS_AxonCompanyResponsible.ResponsibilityView revokeResponsibility(
    Id craId,
    Integer expectedVersion
  ) {
    return new ALT_CLS_AxonCompanyResponsible()
      .revokeResponsibility(craId, expectedVersion);
  }
}
