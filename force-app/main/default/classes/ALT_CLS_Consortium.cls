/** Maintains consortium rolling windows and confirmed future-value adjustments. */
public inherited sharing class ALT_CLS_Consortium {
    private static final Integer HORIZON = 6;
    public static Integer initialWindow(Integer totalInstallments) { return Math.min(HORIZON, totalInstallments); }

    public static void maintain(Id groupId, Integer settledSequence, Decimal paidValue, Boolean adjustmentConfirmed) {
        AXF_OBJ_InstallmentGroup__c groupRecord = [
            SELECT Id, AXF_IG_NUM_TotalInstallments__c, AXF_IG_CUR_InstallmentAmount__c, AXF_IG_DAT_FirstDueDate__c
            FROM AXF_OBJ_InstallmentGroup__c WHERE Id = :groupId AND AXF_IG_PKL_GroupType__c = 'CONSORTIUM'
            WITH USER_MODE FOR UPDATE
        ];
        List<AXF_OBJ_CashFlow__c> entries = [
            SELECT Id, Name, RecordTypeId, AXF_CF_CUR_PaidValue__c, AXF_CF_DAT_PurchaseDate__c,
                   AXF_CF_DAT_DueDate__c, AXF_CF_PKL_PaymentMode__c, AXF_CF_PKL_PaymentMethod__c,
                   AXF_CF_NUM_CurrentInstallment__c, AXF_CF_LKP_Category__c, AXF_CF_LKP_Account__c,
                   AXF_CF_LKP_BankAccount__c, AXF_CF_LKP_CreditCard__c
            FROM AXF_OBJ_CashFlow__c WHERE AXF_CF_LKP_InstallmentGroup__c = :groupId
            WITH USER_MODE ORDER BY AXF_CF_NUM_CurrentInstallment__c
        ];
        if (entries.isEmpty()) return;
        Decimal baseValue = adjustmentConfirmed ? paidValue : groupRecord.AXF_IG_CUR_InstallmentAmount__c;
        List<AXF_OBJ_CashFlow__c> updates = new List<AXF_OBJ_CashFlow__c>();
        if (adjustmentConfirmed) {
            groupRecord.AXF_IG_CUR_InstallmentAmount__c = paidValue;
            for (AXF_OBJ_CashFlow__c entry : entries) {
                if (entry.AXF_CF_NUM_CurrentInstallment__c > settledSequence && entry.AXF_CF_CUR_PaidValue__c == null)
                    updates.add(new AXF_OBJ_CashFlow__c(Id = entry.Id, AXF_CF_CUR_Value__c = paidValue, AXF_CF_CHK_IsEstimated__c = true));
            }
        }
        Integer total = Integer.valueOf(groupRecord.AXF_IG_NUM_TotalInstallments__c);
        Integer maxSequence = Integer.valueOf(entries[entries.size() - 1].AXF_CF_NUM_CurrentInstallment__c);
        Integer desiredMax = Math.min(total, Math.max(initialWindow(total), settledSequence + HORIZON));
        AXF_OBJ_CashFlow__c source = entries[0];
        List<AXF_OBJ_CashFlow__c> inserts = new List<AXF_OBJ_CashFlow__c>();
        for (Integer sequence = maxSequence + 1; sequence <= desiredMax; sequence++) {
            Date dueDate = groupRecord.AXF_IG_DAT_FirstDueDate__c.addMonths(sequence - 1);
            String baseName = source.Name.contains(' (') ? source.Name.substringBefore(' (') : source.Name;
            inserts.add(new AXF_OBJ_CashFlow__c(
                RecordTypeId = source.RecordTypeId, Name = (baseName + ' (' + sequence + '/' + total + ')').left(80),
                AXF_CF_CUR_Value__c = baseValue, AXF_CF_DAT_PurchaseDate__c = source.AXF_CF_DAT_PurchaseDate__c,
                AXF_CF_DAT_DueDate__c = dueDate, AXF_CF_PKL_Status__c = dueDate < Date.today() ? 'VENCIDA' : 'PENDENTE',
                AXF_CF_PKL_PaymentMode__c = source.AXF_CF_PKL_PaymentMode__c, AXF_CF_PKL_PaymentMethod__c = source.AXF_CF_PKL_PaymentMethod__c,
                AXF_CF_CHK_IsEstimated__c = true, AXF_CF_NUM_CurrentInstallment__c = sequence, AXF_CF_NUM_TotalInstallments__c = total,
                AXF_CF_LKP_Category__c = source.AXF_CF_LKP_Category__c, AXF_CF_LKP_Account__c = source.AXF_CF_LKP_Account__c,
                AXF_CF_LKP_BankAccount__c = source.AXF_CF_LKP_BankAccount__c, AXF_CF_LKP_CreditCard__c = source.AXF_CF_LKP_CreditCard__c,
                AXF_CF_LKP_InstallmentGroup__c = groupId
            ));
        }
        if (adjustmentConfirmed) Database.update(groupRecord, AccessLevel.USER_MODE);
        if (!updates.isEmpty()) Database.update(updates, AccessLevel.USER_MODE);
        if (!inserts.isEmpty()) Database.insert(inserts, AccessLevel.USER_MODE);
    }
}
