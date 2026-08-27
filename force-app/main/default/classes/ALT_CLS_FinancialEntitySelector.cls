public with sharing class ALT_CLS_FinancialEntitySelector {
  public List<AXF_OBJ_FinancialEntity__c> selectAccessible() {
    return selectSummaries(null);
  }

  public AXF_OBJ_FinancialEntity__c selectAccessibleByRef(String entityRef) {
    List<AXF_OBJ_FinancialEntity__c> rows = selectSummaries(entityRef);
    return rows.isEmpty() ? null : rows[0];
  }

  private static List<AXF_OBJ_FinancialEntity__c> selectSummaries(
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
          AXF_FIE_LKP_Household__r.OwnerId,
          AXF_FIE_LKP_Household__r.AXF_HH_NUM_Version__c,
          AXF_FIE_LKP_Household__r.AXF_HH_TXT_ReportingCurrencyIsoCode__c
        FROM AXF_OBJ_FinancialEntity__c
        WHERE AXF_FIE_EXI_EntityRef__c = :entityRef
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
        AXF_FIE_LKP_Household__r.OwnerId,
        AXF_FIE_LKP_Household__r.AXF_HH_NUM_Version__c,
        AXF_FIE_LKP_Household__r.AXF_HH_TXT_ReportingCurrencyIsoCode__c
      FROM AXF_OBJ_FinancialEntity__c
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
        AXF_FIE_LKP_Household__r.OwnerId,
        AXF_FIE_LKP_Household__r.AXF_HH_NUM_Version__c,
        AXF_FIE_LKP_Household__r.AXF_HH_TXT_ReportingCurrencyIsoCode__c
      FROM AXF_OBJ_FinancialEntity__c
      WHERE Id = :visible.Id
      WITH USER_MODE
      LIMIT 1
    ];
  }
}
