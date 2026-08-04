/** Maintains the finite rolling window for fixed-value PRICE financing. */
public inherited sharing class ALT_CLS_PriceFinancing {
  private static final Integer FUTURE_HORIZON = 6;
  public static Integer initialWindow(Integer totalInstallments) {
    return Math.min(totalInstallments, FUTURE_HORIZON + 1);
  }
  public static void maintain(Id groupId, Integer settledSequence) {
    AXF_OBJ_InstallmentGroup__c groupRecord = [
      SELECT
        Id,
        AXF_IG_NUM_TotalInstallments__c,
        AXF_IG_CUR_TotalAmount__c,
        AXF_IG_CUR_InstallmentAmount__c,
        AXF_IG_DAT_FirstDueDate__c
      FROM AXF_OBJ_InstallmentGroup__c
      WHERE
        Id = :groupId
        AND AXF_IG_PKL_GroupType__c = 'FINANCING'
        AND AXF_IG_PKL_FinancingType__c = 'PRICE'
      WITH USER_MODE
      FOR UPDATE
    ];
    List<AXF_OBJ_CashFlow__c> entries = [
      SELECT
        Id,
        Name,
        RecordTypeId,
        AXF_CF_DAT_PurchaseDate__c,
        AXF_CF_PKL_PaymentMode__c,
        AXF_CF_PKL_PaymentMethod__c,
        AXF_CF_NUM_CurrentInstallment__c,
        AXF_CF_LKP_Category__c,
        AXF_CF_LKP_Account__c,
        AXF_CF_LKP_BankAccount__c,
        AXF_CF_LKP_CreditCard__c
      FROM AXF_OBJ_CashFlow__c
      WHERE AXF_CF_LKP_InstallmentGroup__c = :groupId
      WITH USER_MODE
      ORDER BY AXF_CF_NUM_CurrentInstallment__c
    ];
    if (entries.isEmpty()) {
      return;
    }
    Integer total = Integer.valueOf(
      groupRecord.AXF_IG_NUM_TotalInstallments__c
    );
    Integer maxSequence = Integer.valueOf(
      entries[entries.size() - 1].AXF_CF_NUM_CurrentInstallment__c
    );
    Integer desiredMax = Math.min(total, settledSequence + FUTURE_HORIZON);
    AXF_OBJ_CashFlow__c source = entries[0];
    String baseName = source.Name.contains(' (')
      ? source.Name.substringBefore(' (')
      : source.Name;
    List<AXF_OBJ_CashFlow__c> inserts = new List<AXF_OBJ_CashFlow__c>();
    for (
      Integer sequence = maxSequence + 1; sequence <= desiredMax; sequence++
    ) {
      Date dueDate = groupRecord.AXF_IG_DAT_FirstDueDate__c.addMonths(
        sequence - 1
      );
      Decimal value = sequence == total
        ? groupRecord.AXF_IG_CUR_TotalAmount__c -
          (groupRecord.AXF_IG_CUR_InstallmentAmount__c * (total - 1))
        : groupRecord.AXF_IG_CUR_InstallmentAmount__c;
      inserts.add(
        new AXF_OBJ_CashFlow__c(
          RecordTypeId = source.RecordTypeId,
          Name = (baseName + ' (' + sequence + '/' + total + ')').left(80),
          AXF_CF_CUR_Value__c = value,
          AXF_CF_DAT_PurchaseDate__c = source.AXF_CF_DAT_PurchaseDate__c,
          AXF_CF_DAT_DueDate__c = dueDate,
          AXF_CF_PKL_Status__c = dueDate < Date.today()
            ? 'VENCIDA'
            : 'PENDENTE',
          AXF_CF_PKL_PaymentMode__c = source.AXF_CF_PKL_PaymentMode__c,
          AXF_CF_PKL_PaymentMethod__c = source.AXF_CF_PKL_PaymentMethod__c,
          AXF_CF_NUM_CurrentInstallment__c = sequence,
          AXF_CF_NUM_TotalInstallments__c = total,
          AXF_CF_LKP_Category__c = source.AXF_CF_LKP_Category__c,
          AXF_CF_LKP_Account__c = source.AXF_CF_LKP_Account__c,
          AXF_CF_LKP_BankAccount__c = source.AXF_CF_LKP_BankAccount__c,
          AXF_CF_LKP_CreditCard__c = source.AXF_CF_LKP_CreditCard__c,
          AXF_CF_LKP_InstallmentGroup__c = groupId
        )
      );
    }
    if (!inserts.isEmpty()) {
      Database.insert(inserts, AccessLevel.USER_MODE);
    }
  }
}
