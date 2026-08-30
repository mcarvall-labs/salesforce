/**
 * @description Dedicated controller for the aXF_LWC_accessLevelConfig LWC. Thin entry point
 * that validates input and delegates to ALT_CLS_AxonAccessProvisioning, per PROJECT_RULES.md
 * §3. Enforces the AXF_CanConfigure authority server-side; never returns stack traces or PII.
 * AXF-7.
 */
public with sharing class AXF_CLS_CTRL_AccessLevelConfig {
  public class UserAccessDTO {
    @AuraEnabled
    public Id userId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String username;
    @AuraEnabled
    public Boolean isActive;
    @AuraEnabled
    public String currentLevel;
  }

  public class ApplyResultDTO {
    @AuraEnabled
    public Id userId;
    @AuraEnabled
    public String level;
    @AuraEnabled
    public String outcome;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public String currentLevel;
  }

  /**
   * @description Test seam mirroring the service: when non-null, overrides the
   * AXF_CanConfigure check so tests exercise both authorized and forbidden paths.
   */
  @TestVisible
  private static Boolean canConfigureOverride;

  private static Boolean callerCanConfigure() {
    if (canConfigureOverride != null) {
      return canConfigureOverride;
    }
    return FeatureManagement.checkPermission('AXF_CanConfigure');
  }

  /**
   * @description Whether the running user may configure access levels.
   */
  @AuraEnabled(cacheable=true)
  public static Boolean canConfigure() {
    return callerCanConfigure();
  }

  /**
   * @description Active internal users with their current Axon access level. Returns an empty
   * list (not an error) when the caller is not authorized, so the UI shows FORBIDDEN cleanly.
   */
  @AuraEnabled(cacheable=true)
  public static List<UserAccessDTO> getEligibleUsers() {
    if (!callerCanConfigure()) {
      return new List<UserAccessDTO>();
    }

    List<User> users = [
      SELECT Id, Name, Username, IsActive
      FROM User
      WHERE IsActive = TRUE
      AND UserType = 'Standard'
      WITH USER_MODE
      ORDER BY Name
      LIMIT 200
    ];

    Set<Id> ids = new Map<Id, User>(users).keySet();
    Map<Id, String> levels = new ALT_CLS_AxonAccessProvisioning().currentLevels(ids);

    List<UserAccessDTO> dtos = new List<UserAccessDTO>();
    for (User u : users) {
      UserAccessDTO dto = new UserAccessDTO();
      dto.userId = u.Id;
      dto.name = u.Name;
      dto.username = u.Username;
      dto.isActive = u.IsActive;
      dto.currentLevel = levels.get(u.Id);
      dtos.add(dto);
    }
    return dtos;
  }

  /**
   * @description Applies an access level to a user. Validates the id and level here; the
   * authority, existence, license, idempotency and concurrency rules live in the service.
   */
  @AuraEnabled
  public static ApplyResultDTO applyAccessLevel(Id userId, String level) {
    ApplyResultDTO out = new ApplyResultDTO();
    out.userId = userId;
    out.level = level;

    ALT_CLS_AxonAccessProvisioning.Tier tier = ALT_CLS_AxonAccessProvisioning.parseLevel(level);

    ALT_CLS_AxonAccessProvisioning service = new ALT_CLS_AxonAccessProvisioning();
    ALT_CLS_AxonAccessProvisioning.Result res = service.applyAccessLevel(userId, tier);

    out.outcome = res.outcome == null ? null : res.outcome.name();
    out.message = res.message;

    if (userId != null && userId.getSobjectType() == User.SObjectType) {
      out.currentLevel = service.currentLevels(new Set<Id>{ userId }).get(userId);
    }
    return out;
  }
}
