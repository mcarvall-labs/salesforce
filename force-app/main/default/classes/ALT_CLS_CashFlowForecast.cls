/**
 * @description Keeps open-ended RECURRING and PRICE-financing AXF_OBJ_InstallmentGroup__c
 * series projected FUTURE_HORIZON_MONTHS ahead of today, adding one occurrence per group per
 * run so a monthly schedule advances the horizon at the same pace as time passing.
 */
public inherited sharing class ALT_CLS_CashFlowForecast {
  public static final Integer FUTURE_HORIZON_MONTHS = 6;

  public void extendActiveGroups() {
    Date horizonEnd = Date.today().addMonths(FUTURE_HORIZON_MONTHS);

    Map<Id, AXF_OBJ_InstallmentGroup__c> groupsById = new Map<Id, AXF_OBJ_InstallmentGroup__c>(
      [
        SELECT Id, AXF_IG_PKL_GroupType__c, AXF_IG_NUM_TotalInstallments__c
        FROM AXF_OBJ_InstallmentGroup__c
        WHERE
          AXF_IG_PKL_GroupType__c = 'RECURRING'
          OR (AXF_IG_PKL_GroupType__c = 'FINANCING'
          AND AXF_IG_PKL_FinancingType__c = 'PRICE')
        WITH USER_MODE
      ]
    );
    if (groupsById.isEmpty()) {
      return;
    }

    Map<Id, AXF_OBJ_CashFlow__c> latestEntryByGroup = new Map<Id, AXF_OBJ_CashFlow__c>();
    for (AXF_OBJ_CashFlow__c entry : [
      SELECT
        Name,
        RecordTypeId,
        AXF_CF_CUR_Value__c,
        AXF_CF_DAT_PurchaseDate__c,
        AXF_CF_DAT_DueDate__c,
        AXF_CF_PKL_PaymentMode__c,
        AXF_CF_PKL_PaymentMethod__c,
        AXF_CF_PKL_RecurringType__c,
        AXF_CF_PKL_ProvisioningStrategy__c,
        AXF_CF_NUM_CurrentInstallment__c,
        AXF_CF_NUM_TotalInstallments__c,
        AXF_CF_LKP_Category__c,
        AXF_CF_LKP_Account__c,
        AXF_CF_LKP_BankAccount__c,
        AXF_CF_LKP_CreditCard__c,
        AXF_CF_LKP_InstallmentGroup__c
      FROM AXF_OBJ_CashFlow__c
      WHERE AXF_CF_LKP_InstallmentGroup__c IN :groupsById.keySet()
      ORDER BY
        AXF_CF_LKP_InstallmentGroup__c,
        AXF_CF_DAT_DueDate__c DESC,
        AXF_CF_NUM_CurrentInstallment__c DESC
    ]) {
      if (
        !latestEntryByGroup.containsKey(entry.AXF_CF_LKP_InstallmentGroup__c)
      ) {
        latestEntryByGroup.put(entry.AXF_CF_LKP_InstallmentGroup__c, entry);
      }
    }

    List<AXF_OBJ_CashFlow__c> toInsert = new List<AXF_OBJ_CashFlow__c>();
    for (AXF_OBJ_CashFlow__c latest : latestEntryByGroup.values()) {
      if (latest.AXF_CF_DAT_DueDate__c >= horizonEnd) {
        continue;
      }
      AXF_OBJ_InstallmentGroup__c groupRecord = groupsById.get(
        latest.AXF_CF_LKP_InstallmentGroup__c
      );
      Integer nextSequence = latest.AXF_CF_NUM_CurrentInstallment__c == null
        ? null
        : Integer.valueOf(latest.AXF_CF_NUM_CurrentInstallment__c) + 1;
      if (groupRecord.AXF_IG_PKL_GroupType__c == 'FINANCING') {
        Integer total = groupRecord.AXF_IG_NUM_TotalInstallments__c == null
          ? null
          : Integer.valueOf(groupRecord.AXF_IG_NUM_TotalInstallments__c);
        if (nextSequence == null || total == null || nextSequence > total) {
          continue;
        }
      }
      toInsert.add(buildNextEntry(latest, nextSequence));
    }

    if (!toInsert.isEmpty()) {
      Database.insert(toInsert, AccessLevel.USER_MODE);
    }
  }

  private static AXF_OBJ_CashFlow__c buildNextEntry(
    AXF_OBJ_CashFlow__c latest,
    Integer nextSequence
  ) {
    Date dueDate = latest.AXF_CF_DAT_DueDate__c.addMonths(1);
    String baseName = latest.Name.contains(' (')
      ? latest.Name.substringBefore(' (')
      : latest.Name;
    return new AXF_OBJ_CashFlow__c(
      RecordTypeId = latest.RecordTypeId,
      Name = nextSequence == null
        ? baseName
        : (baseName +
            ' (' +
            nextSequence +
            '/' +
            Integer.valueOf(latest.AXF_CF_NUM_TotalInstallments__c) +
            ')')
            .left(80),
      AXF_CF_CUR_Value__c = latest.AXF_CF_CUR_Value__c,
      AXF_CF_DAT_PurchaseDate__c = latest.AXF_CF_DAT_PurchaseDate__c,
      AXF_CF_DAT_DueDate__c = dueDate,
      AXF_CF_PKL_Status__c = dueDate < Date.today() ? 'VENCIDA' : 'PENDENTE',
      AXF_CF_PKL_PaymentMode__c = latest.AXF_CF_PKL_PaymentMode__c,
      AXF_CF_PKL_PaymentMethod__c = latest.AXF_CF_PKL_PaymentMethod__c,
      AXF_CF_PKL_RecurringType__c = latest.AXF_CF_PKL_RecurringType__c,
      AXF_CF_PKL_ProvisioningStrategy__c = latest.AXF_CF_PKL_ProvisioningStrategy__c,
      AXF_CF_CHK_IsEstimated__c = latest.AXF_CF_PKL_RecurringType__c ==
        'VARIAVEL',
      AXF_CF_NUM_CurrentInstallment__c = nextSequence,
      AXF_CF_NUM_TotalInstallments__c = latest.AXF_CF_NUM_TotalInstallments__c,
      AXF_CF_LKP_Category__c = latest.AXF_CF_LKP_Category__c,
      AXF_CF_LKP_Account__c = latest.AXF_CF_LKP_Account__c,
      AXF_CF_LKP_BankAccount__c = latest.AXF_CF_LKP_BankAccount__c,
      AXF_CF_LKP_CreditCard__c = latest.AXF_CF_LKP_CreditCard__c,
      AXF_CF_LKP_InstallmentGroup__c = latest.AXF_CF_LKP_InstallmentGroup__c
    );
  }
}
