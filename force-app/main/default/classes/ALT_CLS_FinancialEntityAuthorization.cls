public with sharing class ALT_CLS_FinancialEntityAuthorization {
  @TestVisible
  private static Boolean allowCustomPermissionsInTests = false;
  public Decision authorize(String capability, Id householdId, Id entityId) {
    Decision decision = new Decision();
    if (
      String.isBlank(capability) ||
      householdId == null ||
      !hasCustomPermission(capability)
    )
      return decision;

    List<AXF_OBJ_Household__c> households = [
      SELECT Id, OwnerId
      FROM AXF_OBJ_Household__c
      WHERE Id = :householdId
      WITH USER_MODE
      LIMIT 1
    ];
    if (households.isEmpty())
      return decision;
    if (
      entityId != null &&
      [
        SELECT COUNT()
        FROM AXF_OBJ_FinancialEntity__c
        WHERE Id = :entityId AND AXF_FIE_LKP_Household__c = :householdId
        WITH USER_MODE
      ] == 0
    )
      return decision;
    Id accessId = entityId == null ? householdId : entityId;
    List<UserRecordAccess> accessRows = [
      SELECT RecordId, HasReadAccess, HasEditAccess
      FROM UserRecordAccess
      WHERE UserId = :UserInfo.getUserId() AND RecordId = :accessId
    ];
    if (accessRows.isEmpty() || !accessRows[0].HasReadAccess)
      return decision;
    if (
      capability == 'AXF_UpdateFinancialEntity' &&
      (entityId == null || !accessRows[0].HasEditAccess)
    )
      return decision;
    if (
      capability == 'AXF_CreateFinancialEntity' &&
      households[0].OwnerId != UserInfo.getUserId() &&
      !accessRows[0].HasEditAccess
    )
      return decision;
    decision.allowed = true;
    decision.allowedActions.add(capability);
    decision.allowedFields.add('legalName');
    return decision;
  }

  private static Boolean hasCustomPermission(String capability) {
    return (Test.isRunningTest() && allowCustomPermissionsInTests) ||
      FeatureManagement.checkPermission(capability);
  }

  public class Decision {
    public Boolean allowed = false;
    public Set<String> allowedActions = new Set<String>();
    public Set<String> allowedFields = new Set<String>();
  }
}
