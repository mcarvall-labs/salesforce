/** @description Bulk trigger integrity checks. System visibility is required to protect hidden historical references. */
public without sharing class ALT_CLS_RealizationGuard {
  /** @description Application recognition evidence can only originate in the authorized transaction. */
  public static void snapshots(List<AXF_OBJ_FxApplicationSnapshot__c> rows) {
    for (AXF_OBJ_FxApplicationSnapshot__c row : rows) {
      if (
        (row.AXF_FXS_PKL_TargetType__c == 'RECONCILIATION_ALLOCATION' ||
        row.AXF_FXS_LKP_ReconciliationAllocation__c != null) &&
        (!ALT_CLS_RealizationService.isWriting() ||
        row.AXF_FXS_PKL_Purpose__c != 'RECOGNITION')
      ) {
        row.addError(
          'Recognition evidence must be created by the realization service.'
        );
      }
    }
  }
  /** @description Only the atomic service can append effects or complete FX evidence. */
  public static void allocations(
    List<AXF_OBJ_ReconciliationAllocation__c> rows,
    Map<Id, AXF_OBJ_ReconciliationAllocation__c> oldMap,
    Boolean deleting
  ) {
    for (AXF_OBJ_ReconciliationAllocation__c row : rows) {
      if (deleting || !ALT_CLS_RealizationService.isWriting()) {
        row.addError(
          'Use the realization service. Historical effects cannot be deleted.'
        );
        continue;
      }
      if (oldMap != null) {
        AXF_OBJ_ReconciliationAllocation__c before = oldMap.get(row.Id);
        for (String field : row.getPopulatedFieldsAsMap().keySet()) {
          if (
            field.endsWith('__c') &&
            row.get(field) != before.get(field) &&
            !new Set<String>{
                'AXF_RA_PKL_FxState__c',
                'AXF_RA_LKP_FxSnapshot__c',
                'AXF_RA_NUM_ReportingAmount__c'
              }
              .contains(field)
          ) {
            row.addError('Allocation content is immutable.');
            break;
          }
        }
        if (before.AXF_RA_PKL_FxState__c == 'READY') {
          row.addError('Recognition evidence is already frozen.');
        }
      }
      Integer sources =
        (row.AXF_RA_LKP_BankTransaction__c == null ? 0 : 1) +
        (row.AXF_RA_LKP_CardTransaction__c == null ? 0 : 1) +
        (row.AXF_RA_LKP_ManualTransaction__c == null ? 0 : 1);
      if (
        sources != 1 ||
        row.AXF_RA_LKP_FinancialTransaction__c == null ||
        row.AXF_RA_LKP_FinancialTransaction__c ==
        row.AXF_RA_LKP_ManualTransaction__c ||
        row.AXF_RA_NUM_Magnitude__c == null ||
        row.AXF_RA_NUM_Magnitude__c <= 0
      ) {
        row.addError('Invalid typed allocation.');
      }
    }
  }
  /** @description Original facts and target financial fields stay immutable once referenced, including after reversal. */
  // Trigger integrity must include hidden references, regardless of the caller's CRUD permissions.
  @SuppressWarnings('PMD.ApexCRUDViolation')
  public static void originals(
    List<SObject> rows,
    Map<Id, SObject> oldMap,
    Boolean deleting
  ) {
    Set<Id> ids = new Set<Id>();
    for (SObject row : rows) {
      if (row.Id != null) {
        ids.add(row.Id);
      }
    }
    Set<Id> referenced = new Set<Id>();
    for (AXF_OBJ_ReconciliationAllocation__c allocation : [
      SELECT
        AXF_RA_LKP_FinancialTransaction__c,
        AXF_RA_LKP_BankTransaction__c,
        AXF_RA_LKP_CardTransaction__c,
        AXF_RA_LKP_ManualTransaction__c
      FROM AXF_OBJ_ReconciliationAllocation__c
      WHERE
        AXF_RA_LKP_FinancialTransaction__c IN :ids
        OR AXF_RA_LKP_BankTransaction__c IN :ids
        OR AXF_RA_LKP_CardTransaction__c IN :ids
        OR AXF_RA_LKP_ManualTransaction__c IN :ids
    ]) {
      referenced.add(allocation.AXF_RA_LKP_FinancialTransaction__c);
      referenced.add(allocation.AXF_RA_LKP_BankTransaction__c);
      referenced.add(allocation.AXF_RA_LKP_CardTransaction__c);
      referenced.add(allocation.AXF_RA_LKP_ManualTransaction__c);
    }
    for (SObject row : rows) {
      Boolean financial =
        row.getSObjectType() == AXF_OBJ_FinancialTransaction__c.SObjectType;
      if (oldMap == null) {
        if (
          financial &&
          row.get('AXF_FTX_PKL_PlanKind__c') != null &&
          row.get('AXF_FTX_PKL_PlanKind__c') != 'PLANNED' &&
          !ALT_CLS_RealizationService.isWriting()
        ) {
          row.addError(
            'Financial roles are assigned by the realization service.'
          );
        }
        continue;
      }
      SObject before = oldMap.get(row.Id);
      if (
        financial &&
        row.get('AXF_FTX_PKL_PlanKind__c') !=
        before.get('AXF_FTX_PKL_PlanKind__c')
      ) {
        row.addError('Financial role is immutable.');
      }
      if (!referenced.contains(row.Id)) {
        continue;
      }
      if (deleting) {
        row.addError('Referenced financial evidence cannot be deleted.');
        continue;
      }
      for (String field : row.getPopulatedFieldsAsMap().keySet()) {
        if (!field.endsWith('__c') || row.get(field) == before.get(field)) {
          continue;
        }
        if (
          field.endsWith('_NUM_Version__c') &&
          ALT_CLS_RealizationService.isWriting()
        ) {
          continue;
        }
        row.addError(
          'Original financial evidence is immutable; append a reversal.'
        );
        break;
      }
    }
  }
}
