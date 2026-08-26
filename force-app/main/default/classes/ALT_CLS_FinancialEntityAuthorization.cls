public with sharing class ALT_CLS_FinancialEntityAuthorization {
  @TestVisible
  private static Boolean allowCustomPermissionsInTests = false;
  public static final String POLICY_VERSION = 'AXF-AUTHORIZATION@1.0.0';
  public static final String PURPOSE = 'HOUSEHOLD_OPERATIONS';

  public Decision authorize(String capability, Id householdId, Id entityId) {
    Decision decision = new Decision();
    decision.policyVersion = POLICY_VERSION;
    decision.purpose = PURPOSE;
    if (
      String.isBlank(capability) ||
      householdId == null ||
      !hasCustomPermission(capability)
    )
      return decision;

    Datetime nowValue = System.now();
    List<AXF_OBJ_HouseholdFinancialEntity__c> memberships = [
      SELECT Id, AXF_HFE_LKP_FinancialEntity__c
      FROM AXF_OBJ_HouseholdFinancialEntity__c
      WHERE
        AXF_HFE_MD_Household__c = :householdId
        AND AXF_HFE_PKL_Status__c = 'ACTIVE'
        AND AXF_HFE_DT_ValidFrom__c <= :nowValue
        AND (AXF_HFE_DT_ValidTo__c = NULL
        OR AXF_HFE_DT_ValidTo__c > :nowValue)
      WITH USER_MODE
    ];
    if (memberships.isEmpty())
      return decision;
    if (entityId != null) {
      Boolean entityMembershipActive = false;
      for (AXF_OBJ_HouseholdFinancialEntity__c membership : memberships)
        if (membership.AXF_HFE_LKP_FinancialEntity__c == entityId)
          entityMembershipActive = true;
      if (!entityMembershipActive)
        return decision;
    }

    Id currentUserId = UserInfo.getUserId();
    List<AXF_OBJ_EntityAccessGrant__c> grants;
    if (entityId == null) {
      grants = [
        SELECT
          Id,
          AXF_EAG_NUM_GrantRevision__c,
          AXF_EAG_TXT_OperationSet__c,
          AXF_EAG_TXT_FieldPolicyVersion__c
        FROM AXF_OBJ_EntityAccessGrant__c
        WHERE
          AXF_EAG_LKP_Household__c = :householdId
          AND AXF_EAG_LKP_User__c = :currentUserId
          AND AXF_EAG_PKL_Status__c = 'ACTIVE'
          AND AXF_EAG_TXT_Purpose__c = :PURPOSE
          AND AXF_EAG_DT_ValidFrom__c <= :nowValue
          AND (AXF_EAG_DT_ValidTo__c = NULL
          OR AXF_EAG_DT_ValidTo__c > :nowValue)
          AND AXF_EAG_PKL_ScopeType__c = 'HOUSEHOLD'
        WITH USER_MODE
        LIMIT 1
      ];
    } else {
      grants = [
        SELECT
          Id,
          AXF_EAG_NUM_GrantRevision__c,
          AXF_EAG_TXT_OperationSet__c,
          AXF_EAG_TXT_FieldPolicyVersion__c
        FROM AXF_OBJ_EntityAccessGrant__c
        WHERE
          AXF_EAG_LKP_Household__c = :householdId
          AND AXF_EAG_LKP_User__c = :currentUserId
          AND AXF_EAG_PKL_Status__c = 'ACTIVE'
          AND AXF_EAG_TXT_Purpose__c = :PURPOSE
          AND AXF_EAG_DT_ValidFrom__c <= :nowValue
          AND (AXF_EAG_DT_ValidTo__c = NULL
          OR AXF_EAG_DT_ValidTo__c > :nowValue)
          AND AXF_EAG_PKL_ScopeType__c = 'ENTITY'
          AND AXF_EAG_LKP_FinancialEntity__c = :entityId
        WITH USER_MODE
        LIMIT 1
      ];
    }
    if (
      grants.isEmpty() ||
      !containsCapability(grants[0].AXF_EAG_TXT_OperationSet__c, capability)
    )
      return decision;
    decision.allowed = true;
    decision.grantVersion = grants[0].AXF_EAG_NUM_GrantRevision__c;
    decision.allowedActions.add(capability);
    if (grants[0].AXF_EAG_TXT_FieldPolicyVersion__c == POLICY_VERSION)
      decision.allowedFields.add('legalName');
    return decision;
  }

  private static Boolean hasCustomPermission(String capability) {
    return (Test.isRunningTest() && allowCustomPermissionsInTests) ||
      FeatureManagement.checkPermission(capability);
  }

  private static Boolean containsCapability(
    String operationSet,
    String capability
  ) {
    return (',' +
      String.valueOf(operationSet) +
      ',')
      .contains(',' + capability + ',');
  }

  public class Decision {
    public Boolean allowed = false;
    public Set<String> allowedActions = new Set<String>();
    public Set<String> allowedFields = new Set<String>();
    public Decimal grantVersion;
    public String policyVersion;
    public String purpose;
  }
}
