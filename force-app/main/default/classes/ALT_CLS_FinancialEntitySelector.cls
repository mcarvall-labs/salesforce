public with sharing class ALT_CLS_FinancialEntitySelector {
  public List<AXF_OBJ_FinancialEntity__c> selectAccessible() {
    Set<Id> entityIds = readableEntityIds();
    if (entityIds.isEmpty())
      return new List<AXF_OBJ_FinancialEntity__c>();
    return selectSummaries(entityIds, null);
  }

  public AXF_OBJ_FinancialEntity__c selectAccessibleByRef(String entityRef) {
    Set<Id> entityIds = readableEntityIds();
    if (entityIds.isEmpty())
      return null;
    List<AXF_OBJ_FinancialEntity__c> rows = selectSummaries(
      entityIds,
      entityRef
    );
    return rows.isEmpty() ? null : rows[0];
  }

  private static Set<Id> readableEntityIds() {
    Datetime nowValue = System.now();
    Set<Id> entityIds = new Set<Id>();
    for (AXF_OBJ_EntityAccessGrant__c grant : [
      SELECT AXF_EAG_LKP_FinancialEntity__c, AXF_EAG_TXT_OperationSet__c
      FROM AXF_OBJ_EntityAccessGrant__c
      WHERE
        AXF_EAG_LKP_User__c = :UserInfo.getUserId()
        AND AXF_EAG_PKL_Status__c = 'ACTIVE'
        AND AXF_EAG_PKL_ScopeType__c = 'ENTITY'
        AND AXF_EAG_TXT_Purpose__c = 'HOUSEHOLD_OPERATIONS'
        AND AXF_EAG_DT_ValidFrom__c <= :nowValue
        AND (AXF_EAG_DT_ValidTo__c = NULL
        OR AXF_EAG_DT_ValidTo__c > :nowValue)
      WITH USER_MODE
    ]) {
      if (
        (',' +
          grant.AXF_EAG_TXT_OperationSet__c +
          ',')
          .contains(',AXF_ReadFinancialEntity,')
      )
        entityIds.add(grant.AXF_EAG_LKP_FinancialEntity__c);
    }
    return entityIds;
  }

  private static List<AXF_OBJ_FinancialEntity__c> selectSummaries(
    Set<Id> entityIds,
    String entityRef
  ) {
    if (entityRef != null)
      return [
        SELECT
          Id,
          AXF_FIE_EXI_EntityRef__c,
          AXF_FIE_TXT_DisplayName__c,
          AXF_FIE_DAT_ActiveTo__c,
          AXF_FIE_PKL_Kind__c,
          AXF_FIE_PKL_Lifecycle__c,
          AXF_FIE_NUM_Version__c,
          AXF_FIE_LKP_Household__c,
          AXF_FIE_LKP_Household__r.AXF_HH_TXT_ReportingCurrencyIsoCode__c
        FROM AXF_OBJ_FinancialEntity__c
        WHERE Id IN :entityIds AND AXF_FIE_EXI_EntityRef__c = :entityRef
        WITH USER_MODE
        LIMIT 1
      ];
    return [
      SELECT
        Id,
        AXF_FIE_EXI_EntityRef__c,
        AXF_FIE_TXT_DisplayName__c,
        AXF_FIE_DAT_ActiveTo__c,
        AXF_FIE_PKL_Kind__c,
        AXF_FIE_PKL_Lifecycle__c,
        AXF_FIE_NUM_Version__c,
        AXF_FIE_LKP_Household__c,
        AXF_FIE_LKP_Household__r.AXF_HH_TXT_ReportingCurrencyIsoCode__c
      FROM AXF_OBJ_FinancialEntity__c
      WHERE Id IN :entityIds
      WITH USER_MODE
      ORDER BY AXF_FIE_TXT_DisplayName__c
    ];
  }

  public AXF_OBJ_FinancialEntity__c selectAccessibleDetailByRef(
    String entityRef
  ) {
    AXF_OBJ_FinancialEntity__c visible = selectAccessibleByRef(entityRef);
    if (visible == null)
      return null;
    return [
      SELECT
        Id,
        AXF_FIE_EXI_EntityRef__c,
        AXF_FIE_TXT_DisplayName__c,
        AXF_FIE_TXT_LegalName__c,
        AXF_FIE_DAT_ActiveTo__c,
        AXF_FIE_PKL_Kind__c,
        AXF_FIE_PKL_Lifecycle__c,
        AXF_FIE_NUM_Version__c,
        AXF_FIE_LKP_Household__c,
        AXF_FIE_LKP_Household__r.AXF_HH_TXT_ReportingCurrencyIsoCode__c
      FROM AXF_OBJ_FinancialEntity__c
      WHERE Id = :visible.Id
      WITH USER_MODE
      LIMIT 1
    ];
  }
}
