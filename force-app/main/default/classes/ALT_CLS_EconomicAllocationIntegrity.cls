/**
 * @description Integrity reads of the economic allocation domain that must not depend on the
 * caller's sharing (AXF-126): whether an active (confirmed) set exists for a fact identity and
 * the highest revision already used. Returns ids and numbers only.
 */
public without sharing class ALT_CLS_EconomicAllocationIntegrity {
  @SuppressWarnings('PMD.ApexCRUDViolation')
  public static Id activeSetId(String activeToken) {
    for (AXF_OBJ_EconomicAllocationSet__c row : [
      SELECT Id
      FROM AXF_OBJ_EconomicAllocationSet__c
      WHERE AXF_EAS_EXI_ActiveToken__c = :activeToken
      WITH SYSTEM_MODE
      LIMIT 1
    ]) {
      return row.Id;
    }
    return null;
  }

  @SuppressWarnings('PMD.ApexCRUDViolation')
  public static Integer maxRevision(String identity) {
    Integer revision = 0;
    for (AXF_OBJ_EconomicAllocationSet__c row : [
      SELECT AXF_EAS_NUM_Revision__c
      FROM AXF_OBJ_EconomicAllocationSet__c
      WHERE AXF_EAS_TXT_FactIdentity__c = :identity
      WITH SYSTEM_MODE
    ]) {
      Integer current = row.AXF_EAS_NUM_Revision__c == null
        ? 0
        : Integer.valueOf(row.AXF_EAS_NUM_Revision__c);
      revision = Math.max(revision, current);
    }
    return revision;
  }
}
