/**
 * @description Maintains deterministic SAC estimates and the six-occurrence rolling window.
 */
public inherited sharing class ALT_CLS_SacFinancing {
    private static final Integer HORIZON = 6;
    public static Boolean processing = false;

    public static Decimal estimate(Decimal baseValue, Decimal rate, Integer periods) {
        if (baseValue == null || baseValue <= 0) throw new IllegalArgumentException('SAC base value must be positive.');
        Decimal result = baseValue;
        for (Integer index = 0; index < periods; index++) result *= (1 + rate / 100);
        result = result.setScale(2, System.RoundingMode.HALF_UP);
        if (result <= 0) throw new IllegalArgumentException('SAC installment estimates must remain positive.');
        return result;
    }

    public static Integer initialWindow(Integer totalInstallments) {
        return Math.min(HORIZON, totalInstallments);
    }

    public static void afterCashFlowChange(Set<Id> groupIds) {
        if (processing || groupIds == null || groupIds.isEmpty()) return;
        for (AXF_OBJ_InstallmentGroup__c groupRecord : [
            SELECT Id, AXF_IG_NUM_TotalInstallments__c, AXF_IG_CUR_InstallmentAmount__c,
                   AXF_IG_DAT_FirstDueDate__c, AXF_IG_PCT_MonthlyAdjustmentRate__c
            FROM AXF_OBJ_InstallmentGroup__c
            WHERE Id IN :groupIds AND AXF_IG_PKL_FinancingType__c = 'SAC'
            WITH USER_MODE
        ]) maintain(groupRecord, true);
    }

    public static void afterGroupRateChange(List<AXF_OBJ_InstallmentGroup__c> records, Map<Id, AXF_OBJ_InstallmentGroup__c> oldMap) {
        if (processing) return;
        for (AXF_OBJ_InstallmentGroup__c groupRecord : records) {
            AXF_OBJ_InstallmentGroup__c previous = oldMap.get(groupRecord.Id);
            if (groupRecord.AXF_IG_PKL_FinancingType__c == 'SAC'
                && groupRecord.AXF_IG_PCT_MonthlyAdjustmentRate__c != previous.AXF_IG_PCT_MonthlyAdjustmentRate__c) {
                maintain(groupRecord, false);
            }
        }
    }

    private static void maintain(AXF_OBJ_InstallmentGroup__c suppliedGroup, Boolean deriveRate) {
        AXF_OBJ_InstallmentGroup__c groupRecord = [
            SELECT Id, AXF_IG_NUM_TotalInstallments__c, AXF_IG_CUR_InstallmentAmount__c,
                   AXF_IG_DAT_FirstDueDate__c, AXF_IG_PCT_MonthlyAdjustmentRate__c
            FROM AXF_OBJ_InstallmentGroup__c WHERE Id = :suppliedGroup.Id WITH USER_MODE FOR UPDATE
        ];
        List<AXF_OBJ_CashFlow__c> entries = [
            SELECT Id, Name, RecordTypeId, AXF_CF_CUR_Value__c, AXF_CF_CUR_PaidValue__c,
                   AXF_CF_DAT_PurchaseDate__c, AXF_CF_DAT_DueDate__c, AXF_CF_DAT_PaymentDate__c,
                   AXF_CF_PKL_Status__c, AXF_CF_PKL_PaymentMode__c, AXF_CF_PKL_PaymentMethod__c,
                   AXF_CF_CHK_IsEstimated__c, AXF_CF_NUM_CurrentInstallment__c, AXF_CF_NUM_TotalInstallments__c,
                   AXF_CF_LKP_Category__c, AXF_CF_LKP_Account__c, AXF_CF_LKP_BankAccount__c,
                   AXF_CF_LKP_CreditCard__c, AXF_CF_LKP_InstallmentGroup__c
            FROM AXF_OBJ_CashFlow__c WHERE AXF_CF_LKP_InstallmentGroup__c = :groupRecord.Id
            WITH USER_MODE ORDER BY AXF_CF_NUM_CurrentInstallment__c
        ];
        if (entries.isEmpty()) return;
        List<AXF_OBJ_CashFlow__c> actuals = new List<AXF_OBJ_CashFlow__c>();
        Integer maxSequence = 0;
        for (AXF_OBJ_CashFlow__c entry : entries) {
            maxSequence = Math.max(maxSequence, Integer.valueOf(entry.AXF_CF_NUM_CurrentInstallment__c));
            if (entry.AXF_CF_CHK_IsEstimated__c == false && entry.AXF_CF_CUR_PaidValue__c != null) actuals.add(entry);
        }
        Decimal rate = groupRecord.AXF_IG_PCT_MonthlyAdjustmentRate__c;
        if (deriveRate && actuals.size() >= 2) {
            Decimal rateTotal = 0;
            for (Integer index = 1; index < actuals.size(); index++) {
                Decimal previousValue = actuals[index - 1].AXF_CF_CUR_PaidValue__c;
                rateTotal += ((actuals[index].AXF_CF_CUR_PaidValue__c / previousValue) - 1) * 100;
            }
            Decimal effectiveRate = (rateTotal / (actuals.size() - 1)).setScale(2, System.RoundingMode.HALF_UP);
            if (effectiveRate != rate) {
                groupRecord.AXF_IG_PCT_MonthlyAdjustmentRate__c = effectiveRate;
                rate = effectiveRate;
            }
        }
        AXF_OBJ_CashFlow__c anchor = actuals.isEmpty() ? null : actuals[actuals.size() - 1];
        Integer anchorSequence = anchor == null ? 1 : Integer.valueOf(anchor.AXF_CF_NUM_CurrentInstallment__c);
        Decimal anchorValue = anchor == null ? groupRecord.AXF_IG_CUR_InstallmentAmount__c : anchor.AXF_CF_CUR_PaidValue__c;
        List<AXF_OBJ_CashFlow__c> updates = new List<AXF_OBJ_CashFlow__c>();
        for (AXF_OBJ_CashFlow__c entry : entries) {
            Integer sequence = Integer.valueOf(entry.AXF_CF_NUM_CurrentInstallment__c);
            if (entry.AXF_CF_CHK_IsEstimated__c == true && entry.AXF_CF_CUR_PaidValue__c == null && sequence >= anchorSequence) {
                Integer periods = anchor == null ? sequence - 1 : sequence - anchorSequence;
                Decimal value = estimate(anchorValue, rate, periods);
                if (entry.AXF_CF_CUR_Value__c != value) { entry.AXF_CF_CUR_Value__c = value; updates.add(entry); }
            }
        }
        Integer total = Integer.valueOf(groupRecord.AXF_IG_NUM_TotalInstallments__c);
        Integer desiredMax = Math.min(total, Math.max(initialWindow(total), anchorSequence + HORIZON));
        AXF_OBJ_CashFlow__c template = entries[0];
        List<AXF_OBJ_CashFlow__c> inserts = new List<AXF_OBJ_CashFlow__c>();
        for (Integer sequence = maxSequence + 1; sequence <= desiredMax; sequence++) {
            inserts.add(buildEntry(template, groupRecord, sequence, estimate(anchorValue, rate, anchor == null ? sequence - 1 : sequence - anchorSequence)));
        }
        processing = true;
        try {
            if (deriveRate && groupRecord.AXF_IG_PCT_MonthlyAdjustmentRate__c != suppliedGroup.AXF_IG_PCT_MonthlyAdjustmentRate__c)
                Database.update(groupRecord, AccessLevel.USER_MODE);
            if (!updates.isEmpty()) Database.update(updates, AccessLevel.USER_MODE);
            if (!inserts.isEmpty()) Database.insert(inserts, AccessLevel.USER_MODE);
        } finally { processing = false; }
    }

    private static AXF_OBJ_CashFlow__c buildEntry(AXF_OBJ_CashFlow__c source, AXF_OBJ_InstallmentGroup__c groupRecord, Integer sequence, Decimal value) {
        String baseName = source.Name.contains(' (') ? source.Name.substringBefore(' (') : source.Name;
        return new AXF_OBJ_CashFlow__c(
            RecordTypeId = source.RecordTypeId, Name = (baseName + ' (' + sequence + '/' + groupRecord.AXF_IG_NUM_TotalInstallments__c + ')').left(80),
            AXF_CF_CUR_Value__c = value, AXF_CF_DAT_PurchaseDate__c = source.AXF_CF_DAT_PurchaseDate__c,
            AXF_CF_DAT_DueDate__c = groupRecord.AXF_IG_DAT_FirstDueDate__c.addMonths(sequence - 1),
            AXF_CF_PKL_Status__c = groupRecord.AXF_IG_DAT_FirstDueDate__c.addMonths(sequence - 1) < Date.today() ? 'VENCIDA' : 'PENDENTE',
            AXF_CF_PKL_PaymentMode__c = source.AXF_CF_PKL_PaymentMode__c, AXF_CF_PKL_PaymentMethod__c = source.AXF_CF_PKL_PaymentMethod__c,
            AXF_CF_CHK_IsEstimated__c = true, AXF_CF_NUM_CurrentInstallment__c = sequence,
            AXF_CF_NUM_TotalInstallments__c = groupRecord.AXF_IG_NUM_TotalInstallments__c,
            AXF_CF_LKP_Category__c = source.AXF_CF_LKP_Category__c, AXF_CF_LKP_Account__c = source.AXF_CF_LKP_Account__c,
            AXF_CF_LKP_BankAccount__c = source.AXF_CF_LKP_BankAccount__c, AXF_CF_LKP_CreditCard__c = source.AXF_CF_LKP_CreditCard__c,
            AXF_CF_LKP_InstallmentGroup__c = groupRecord.Id
        );
    }
}
