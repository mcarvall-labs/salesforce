/**
 * @description Thin Aura/LWC controller for "Adicionar pessoa e dar acesso ao
 * Axon" (AXF-82). Delegates to ALT_CLS_AxonUserProvisioning.
 *
 * `with sharing` + USER_MODE nas leituras; a autoridade (`AXF_CanConfigure`) é
 * validada no serviço antes de qualquer efeito (AC6).
 */
public with sharing class AXF_CLS_CTRL_UserProvisioning {
  @TestVisible
  private static Boolean canConfigureOverride;

  private static Boolean callerCanConfigure() {
    if (canConfigureOverride != null) {
      return canConfigureOverride;
    }
    return FeatureManagement.checkPermission('AXF_CanConfigure');
  }

  public class EligibleUser {
    @AuraEnabled
    public Id userId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String username;
    @AuraEnabled
    public String email;
  }

  public class Preflight {
    @AuraEnabled
    public Boolean canConfigure;
    @AuraEnabled
    public Boolean salesforceLicenseAvailable;
    @AuraEnabled
    public Integer salesforceLicensesFree;
  }

  @AuraEnabled(cacheable=true)
  public static Boolean canConfigure() {
    return callerCanConfigure();
  }

  @AuraEnabled(cacheable=true)
  public static Preflight preflight() {
    Preflight p = new Preflight();
    p.canConfigure = callerCanConfigure();
    Integer free = 0;
    for (UserLicense ul : [
      SELECT UsedLicenses, TotalLicenses
      FROM UserLicense
      WHERE Name = 'Salesforce' AND Status = 'Active'
    ]) {
      free += Math.max(0, ul.TotalLicenses - ul.UsedLicenses);
    }
    p.salesforceLicensesFree = free;
    p.salesforceLicenseAvailable = free > 0;
    return p;
  }

  @AuraEnabled(cacheable=true)
  public static List<EligibleUser> findLinkableUsers(String search) {
    if (!callerCanConfigure()) {
      return new List<EligibleUser>();
    }
    String pattern =
      '%' +
      String.escapeSingleQuotes(search == null ? '' : search.trim()) +
      '%';
    List<EligibleUser> out = new List<EligibleUser>();
    for (User u : [
      SELECT Id, Name, Username, Email
      FROM User
      WHERE
        IsActive = TRUE
        AND UserType = 'Standard'
        AND (Name LIKE :pattern
        OR Username LIKE :pattern
        OR Email LIKE :pattern)
      WITH USER_MODE
      ORDER BY Name
      LIMIT 50
    ]) {
      EligibleUser e = new EligibleUser();
      e.userId = u.Id;
      e.name = u.Name;
      e.username = u.Username;
      e.email = u.Email;
      out.add(e);
    }
    return out;
  }

  @AuraEnabled
  public static ALT_CLS_AxonUserProvisioning.Result start(
    ALT_CLS_AxonUserProvisioning.StartInput input
  ) {
    return new ALT_CLS_AxonUserProvisioning().start(input);
  }

  @AuraEnabled
  public static ALT_CLS_AxonUserProvisioning.Result resume(Id provisioningId) {
    return new ALT_CLS_AxonUserProvisioning().resume(provisioningId);
  }

  @AuraEnabled(cacheable=true)
  public static ALT_CLS_AxonUserProvisioning.Result getStatus(
    Id provisioningId
  ) {
    return new ALT_CLS_AxonUserProvisioning().getStatus(provisioningId);
  }
}
