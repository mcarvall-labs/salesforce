/**
 * @description Integrity reads of the billing domain that must not depend on the caller's
 * sharing (AXF-65): whether a planned entry is already billed and how much of a WorkRecord is
 * already allocated, across every document regardless of owner. Returns ids and sums only —
 * never names, amounts of other people's documents or record existence beyond the ids the
 * caller already holds. Cancelled documents release their entries and allocations.
 */
public without sharing class ALT_CLS_BillingIntegrity {
  @SuppressWarnings('PMD.ApexCRUDViolation')
  public static Set<Id> billedFacts(
    Set<Id> factIds,
    Set<String> effectiveStates
  ) {
    Set<Id> result = new Set<Id>();
    if (factIds == null || factIds.isEmpty()) {
      return result;
    }
    for (AXF_OBJ_BillingDocumentLine__c line : [
      SELECT AXF_BDL_LKP_FinancialTransaction__c
      FROM AXF_OBJ_BillingDocumentLine__c
      WHERE
        AXF_BDL_LKP_FinancialTransaction__c IN :factIds
        AND AXF_BDL_MDR_DocumentVersion__r.AXF_BDV_PKL_State__c IN :effectiveStates
        AND AXF_BDL_MDR_DocumentVersion__r.AXF_BDV_LKP_BillingDocument__r.AXF_BDO_PKL_Lifecycle__c != 'CANCELLED'
      WITH SYSTEM_MODE
    ]) {
      result.add(line.AXF_BDL_LKP_FinancialTransaction__c);
    }
    return result;
  }

  @SuppressWarnings('PMD.ApexCRUDViolation')
  public static Map<Id, Decimal> allocatedByWorkRecord(
    Set<Id> workIds,
    Set<String> effectiveStates
  ) {
    Map<Id, Decimal> result = new Map<Id, Decimal>();
    if (workIds == null || workIds.isEmpty()) {
      return result;
    }
    for (AXF_OBJ_BillingDocumentWorkAllocation__c allocation : [
      SELECT AXF_BWA_LKP_WorkRecord__c, AXF_BWA_NUM_AllocatedQuantity__c
      FROM AXF_OBJ_BillingDocumentWorkAllocation__c
      WHERE
        AXF_BWA_LKP_WorkRecord__c IN :workIds
        AND AXF_BWA_MDR_Line__r.AXF_BDL_MDR_DocumentVersion__r.AXF_BDV_PKL_State__c IN :effectiveStates
        AND AXF_BWA_MDR_Line__r.AXF_BDL_MDR_DocumentVersion__r.AXF_BDV_LKP_BillingDocument__r.AXF_BDO_PKL_Lifecycle__c != 'CANCELLED'
      WITH SYSTEM_MODE
    ]) {
      Decimal current = result.get(allocation.AXF_BWA_LKP_WorkRecord__c);
      result.put(
        allocation.AXF_BWA_LKP_WorkRecord__c,
        (current == null ? 0 : current) +
        (allocation.AXF_BWA_NUM_AllocatedQuantity__c == null
          ? 0
          : allocation.AXF_BWA_NUM_AllocatedQuantity__c)
      );
    }
    return result;
  }
}
