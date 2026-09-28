public with sharing class AXF_CLS_TH_CashFlow {
  private static final String STATUS_PENDENTE = 'PENDENTE';
  private static final String STATUS_PAGA = 'PAGA';
  private static final String STATUS_PAGA_EM_ATRASO = 'PAGA_EM_ATRASO';
  private static final String STATUS_RECEBIDA = 'RECEBIDA';
  private static final String STATUS_RECEBIDA_EM_ATRASO = 'RECEBIDA_EM_ATRASO';

  public static void handleBeforeInsert(List<AXF_OBJ_CashFlow__c> newRecords) {
    applyPaymentStatusRules(newRecords);
  }

  public static void handleBeforeUpdate(
    List<AXF_OBJ_CashFlow__c> newRecords,
    Map<Id, AXF_OBJ_CashFlow__c> oldMap
  ) {
    applyPaymentStatusRules(newRecords);
  }

  public static void handleAfterInsert(List<AXF_OBJ_CashFlow__c> newRecords) {
    Set<Id> groupIds = collectGroupIds(newRecords, null);
    recalculateInstallmentGroups(groupIds);
    ALT_CLS_SacFinancing.afterCashFlowChange(groupIds);
  }

  public static void handleAfterUpdate(
    List<AXF_OBJ_CashFlow__c> newRecords,
    Map<Id, AXF_OBJ_CashFlow__c> oldMap
  ) {
    Set<Id> groupIds = collectGroupIds(newRecords, oldMap);
    recalculateInstallmentGroups(groupIds);
    ALT_CLS_SacFinancing.afterCashFlowChange(groupIds);
  }

  public static void handleAfterDelete(List<AXF_OBJ_CashFlow__c> oldRecords) {
    recalculateInstallmentGroups(collectGroupIds(oldRecords, null));
  }

  private static Set<Id> collectGroupIds(
    List<AXF_OBJ_CashFlow__c> records,
    Map<Id, AXF_OBJ_CashFlow__c> oldMap
  ) {
    Set<Id> groupIds = new Set<Id>();
    for (AXF_OBJ_CashFlow__c cf : records) {
      if (cf.AXF_CF_LKP_InstallmentGroup__c != null) {
        groupIds.add(cf.AXF_CF_LKP_InstallmentGroup__c);
      }
      if (
        oldMap != null &&
        oldMap.containsKey(cf.Id) &&
        oldMap.get(cf.Id).AXF_CF_LKP_InstallmentGroup__c != null
      ) {
        groupIds.add(oldMap.get(cf.Id).AXF_CF_LKP_InstallmentGroup__c);
      }
    }
    return groupIds;
  }

  private static void recalculateInstallmentGroups(Set<Id> groupIds) {
    if (groupIds.isEmpty()) {
      return;
    }

    Map<Id, AXF_OBJ_InstallmentGroup__c> groupsToUpdate = new Map<Id, AXF_OBJ_InstallmentGroup__c>();
    for (Id groupId : groupIds) {
      groupsToUpdate.put(
        groupId,
        new AXF_OBJ_InstallmentGroup__c(
          Id = groupId,
          AXF_IG_NUM_PaidInstallmentsCount__c = 0,
          AXF_IG_NUM_PendingInstallmentsCount__c = 0,
          AXF_IG_NUM_OverdueInstallmentsCount__c = 0,
          AXF_IG_CUR_TotalPaidAmount__c = 0,
          AXF_IG_CUR_TotalRemainingAmount__c = 0
        )
      );
    }

    for (AXF_OBJ_CashFlow__c cf : [
      SELECT
        AXF_CF_LKP_InstallmentGroup__c,
        AXF_CF_PKL_Status__c,
        AXF_CF_CUR_Value__c
      FROM AXF_OBJ_CashFlow__c
      WHERE AXF_CF_LKP_InstallmentGroup__c IN :groupIds
      WITH USER_MODE
    ]) {
      AXF_OBJ_InstallmentGroup__c grp = groupsToUpdate.get(
        cf.AXF_CF_LKP_InstallmentGroup__c
      );
      Decimal value = cf.AXF_CF_CUR_Value__c == null
        ? 0
        : cf.AXF_CF_CUR_Value__c;

      if (
        cf.AXF_CF_PKL_Status__c == STATUS_PAGA ||
        cf.AXF_CF_PKL_Status__c == STATUS_PAGA_EM_ATRASO ||
        cf.AXF_CF_PKL_Status__c == STATUS_RECEBIDA ||
        cf.AXF_CF_PKL_Status__c == STATUS_RECEBIDA_EM_ATRASO
      ) {
        grp.AXF_IG_NUM_PaidInstallmentsCount__c++;
        grp.AXF_IG_CUR_TotalPaidAmount__c += value;
      } else if (cf.AXF_CF_PKL_Status__c == 'VENCIDA') {
        grp.AXF_IG_NUM_OverdueInstallmentsCount__c++;
        grp.AXF_IG_CUR_TotalRemainingAmount__c += value;
      } else {
        grp.AXF_IG_NUM_PendingInstallmentsCount__c++;
        grp.AXF_IG_CUR_TotalRemainingAmount__c += value;
      }
    }

    Database.update(groupsToUpdate.values(), AccessLevel.USER_MODE);
  }

  private static void applyPaymentStatusRules(
    List<AXF_OBJ_CashFlow__c> records
  ) {
    for (AXF_OBJ_CashFlow__c cf : records) {
      String settledStatus = resolveSettledStatus(cf);
      if (settledStatus == null) {
        continue;
      }

      if (cf.AXF_CF_DAT_PaymentDate__c == null) {
        cf.AXF_CF_DAT_PaymentDate__c = Date.today();
      }

      if (
        cf.AXF_CF_DAT_DueDate__c != null &&
        cf.AXF_CF_DAT_PaymentDate__c > cf.AXF_CF_DAT_DueDate__c
      ) {
        cf.AXF_CF_PKL_Status__c = settledStatus == STATUS_PAGA
          ? STATUS_PAGA_EM_ATRASO
          : STATUS_RECEBIDA_EM_ATRASO;
      } else {
        cf.AXF_CF_PKL_Status__c = settledStatus;
      }
    }
  }

  private static String resolveSettledStatus(AXF_OBJ_CashFlow__c cf) {
    if (
      cf.AXF_CF_PKL_Status__c == STATUS_PAGA ||
      cf.AXF_CF_PKL_Status__c == STATUS_PAGA_EM_ATRASO
    ) {
      return STATUS_PAGA;
    }
    if (
      cf.AXF_CF_PKL_Status__c == STATUS_RECEBIDA ||
      cf.AXF_CF_PKL_Status__c == STATUS_RECEBIDA_EM_ATRASO
    ) {
      return STATUS_RECEBIDA;
    }
    return null;
  }
}
