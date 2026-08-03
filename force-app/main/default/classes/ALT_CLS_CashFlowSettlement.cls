/**
 * @description Consolidates Cash Flow settlement and maintains recurring forecast horizons.
 * Contains no Aura-enabled members and can be reused by settlement controllers.
 */
public inherited sharing class ALT_CLS_CashFlowSettlement {
    private static final Integer FUTURE_HORIZON = 6;
    private static final Set<String> OPEN_STATUSES = new Set<String>{ 'PENDENTE', 'VENCIDA' };
    private static final Set<String> SETTLED_STATUSES = new Set<String>{ 'PAGA', 'PAGA_EM_ATRASO' };

    public void settleExpense(
        Id cashFlowId,
        Decimal paidValue,
        Date paymentDate,
        Id bankTransactionId,
        Id creditCardTransactionId
    ) {
        validateInput(cashFlowId, paidValue, paymentDate, bankTransactionId, creditCardTransactionId);

        AXF_OBJ_CashFlow__c target = [
            SELECT Id, Name, RecordTypeId, RecordType.DeveloperName,
                   AXF_CF_CUR_Value__c, AXF_CF_CUR_PaidValue__c,
                   AXF_CF_DAT_PurchaseDate__c, AXF_CF_DAT_DueDate__c, AXF_CF_DAT_PaymentDate__c,
                   AXF_CF_PKL_Status__c, AXF_CF_PKL_PaymentMode__c, AXF_CF_PKL_PaymentMethod__c,
                   AXF_CF_PKL_RecurringType__c, AXF_CF_PKL_ProvisioningStrategy__c,
                   AXF_CF_NUM_CurrentInstallment__c, AXF_CF_NUM_TotalInstallments__c,
                   AXF_CF_LKP_Category__c, AXF_CF_LKP_Account__c,
                   AXF_CF_LKP_BankAccount__c, AXF_CF_LKP_CreditCard__c,
                   AXF_CF_LKP_InstallmentGroup__c
            FROM AXF_OBJ_CashFlow__c
            WHERE Id = :cashFlowId
            WITH USER_MODE
        ];
        if (target.RecordType.DeveloperName != 'AXF_CF_RT_Expense') {
            throw new IllegalArgumentException('Only Expense entries can be settled by this operation.');
        }

        AXF_OBJ_InstallmentGroup__c groupRecord;
        List<AXF_OBJ_CashFlow__c> series = new List<AXF_OBJ_CashFlow__c>{ target };
        if (target.AXF_CF_LKP_InstallmentGroup__c != null) {
            groupRecord = [
                SELECT Id, AXF_IG_PKL_GroupType__c, AXF_IG_NUM_TotalInstallments__c,
                       AXF_IG_CUR_InstallmentAmount__c
                FROM AXF_OBJ_InstallmentGroup__c
                WHERE Id = :target.AXF_CF_LKP_InstallmentGroup__c
                WITH USER_MODE
                FOR UPDATE
            ];
            series = [
                SELECT Id, Name, RecordTypeId,
                       AXF_CF_CUR_Value__c, AXF_CF_CUR_PaidValue__c,
                       AXF_CF_DAT_PurchaseDate__c, AXF_CF_DAT_DueDate__c, AXF_CF_DAT_PaymentDate__c,
                       AXF_CF_PKL_Status__c, AXF_CF_PKL_PaymentMode__c, AXF_CF_PKL_PaymentMethod__c,
                       AXF_CF_PKL_RecurringType__c, AXF_CF_PKL_ProvisioningStrategy__c,
                       AXF_CF_CHK_IsEstimated__c,
                       AXF_CF_NUM_CurrentInstallment__c, AXF_CF_NUM_TotalInstallments__c,
                       AXF_CF_LKP_Category__c, AXF_CF_LKP_Account__c,
                       AXF_CF_LKP_BankAccount__c, AXF_CF_LKP_CreditCard__c,
                       AXF_CF_LKP_InstallmentGroup__c
                FROM AXF_OBJ_CashFlow__c
                WHERE AXF_CF_LKP_InstallmentGroup__c = :groupRecord.Id
                WITH USER_MODE
                FOR UPDATE
            ];
        }

        if (target.AXF_CF_LKP_InstallmentGroup__c == null) {
            List<AXF_OBJ_CashFlow__c> targetLock = [
                SELECT Id
                FROM AXF_OBJ_CashFlow__c
                WHERE Id = :target.Id
                WITH USER_MODE
                FOR UPDATE
            ];
            if (targetLock.isEmpty()) {
                throw new IllegalArgumentException('Cash Flow was not found.');
            }
        }
        applyActualSettlement(target, paidValue, paymentDate, bankTransactionId, creditCardTransactionId);
        List<AXF_OBJ_CashFlow__c> recordsToUpdate = new List<AXF_OBJ_CashFlow__c>{ target };
        List<AXF_OBJ_CashFlow__c> recordsToInsert = new List<AXF_OBJ_CashFlow__c>();

        if (groupRecord != null && groupRecord.AXF_IG_PKL_GroupType__c == 'RECURRING') {
            maintainRecurringForecast(
                target,
                groupRecord,
                series,
                paidValue,
                recordsToUpdate,
                recordsToInsert
            );
        }

        Database.update(recordsToUpdate, AccessLevel.USER_MODE);
        if (!recordsToInsert.isEmpty()) {
            Database.insert(recordsToInsert, AccessLevel.USER_MODE);
        }
    }

    private static void validateInput(
        Id cashFlowId,
        Decimal paidValue,
        Date paymentDate,
        Id bankTransactionId,
        Id creditCardTransactionId
    ) {
        if (cashFlowId == null || paidValue == null || paidValue <= 0 || paymentDate == null) {
            throw new IllegalArgumentException('Cash Flow, positive Paid Value, and Payment Date are required.');
        }
        if (bankTransactionId != null && creditCardTransactionId != null) {
            throw new IllegalArgumentException('Select at most one reconciliation transaction.');
        }
    }

    private static void applyActualSettlement(
        AXF_OBJ_CashFlow__c target,
        Decimal paidValue,
        Date paymentDate,
        Id bankTransactionId,
        Id creditCardTransactionId
    ) {
        target.AXF_CF_CUR_Value__c = paidValue;
        target.AXF_CF_CUR_PaidValue__c = paidValue;
        target.AXF_CF_DAT_PaymentDate__c = paymentDate;
        target.AXF_CF_PKL_Status__c = paymentDate > target.AXF_CF_DAT_DueDate__c ? 'PAGA_EM_ATRASO' : 'PAGA';
        target.AXF_CF_CHK_IsEstimated__c = false;
        target.AXF_CF_LKP_BankAccountTransaction__c = bankTransactionId;
        target.AXF_CF_LKP_CreditCardTransaction__c = creditCardTransactionId;
    }

    private static void maintainRecurringForecast(
        AXF_OBJ_CashFlow__c target,
        AXF_OBJ_InstallmentGroup__c groupRecord,
        List<AXF_OBJ_CashFlow__c> series,
        Decimal paidValue,
        List<AXF_OBJ_CashFlow__c> recordsToUpdate,
        List<AXF_OBJ_CashFlow__c> recordsToInsert
    ) {
        Boolean variable = target.AXF_CF_PKL_RecurringType__c == 'VARIAVEL';
        Decimal forecastValue = variable
            ? resolveForecastValue(target, groupRecord, series, paidValue)
            : groupRecord.AXF_IG_CUR_InstallmentAmount__c;

        Integer openFutureCount = 0;
        Integer maxSequence = 0;
        Date latestDueDate = target.AXF_CF_DAT_DueDate__c;
        Set<Date> occupiedDueDates = new Set<Date>();
        for (AXF_OBJ_CashFlow__c entry : series) {
            occupiedDueDates.add(entry.AXF_CF_DAT_DueDate__c);
            Integer entrySequence = entry.AXF_CF_NUM_CurrentInstallment__c == null
                ? 0
                : Integer.valueOf(entry.AXF_CF_NUM_CurrentInstallment__c);
            maxSequence = Math.max(maxSequence, entrySequence);
            if (entry.AXF_CF_DAT_DueDate__c > latestDueDate) {
                latestDueDate = entry.AXF_CF_DAT_DueDate__c;
            }
            if (entry.Id != target.Id && entry.AXF_CF_DAT_DueDate__c > target.AXF_CF_DAT_DueDate__c
                && OPEN_STATUSES.contains(entry.AXF_CF_PKL_Status__c)) {
                openFutureCount++;
                if (variable) {
                    entry.AXF_CF_CUR_Value__c = forecastValue;
                    entry.AXF_CF_CHK_IsEstimated__c = true;
                    recordsToUpdate.add(entry);
                }
            }
        }

        Boolean openEnded = groupRecord.AXF_IG_NUM_TotalInstallments__c == null;
        while (openEnded && openFutureCount < FUTURE_HORIZON) {
            latestDueDate = latestDueDate.addMonths(1);
            if (occupiedDueDates.contains(latestDueDate)) {
                continue;
            }
            maxSequence++;
            recordsToInsert.add(buildForecastEntry(target, latestDueDate, maxSequence, forecastValue, variable));
            occupiedDueDates.add(latestDueDate);
            openFutureCount++;
        }
    }

    private static Decimal resolveForecastValue(
        AXF_OBJ_CashFlow__c target,
        AXF_OBJ_InstallmentGroup__c groupRecord,
        List<AXF_OBJ_CashFlow__c> series,
        Decimal paidValue
    ) {
        String strategy = target.AXF_CF_PKL_ProvisioningStrategy__c;
        if (strategy == 'ULTIMO_VALOR') {
            return paidValue;
        }
        if (strategy == 'VALOR_BASE') {
            return groupRecord.AXF_IG_CUR_InstallmentAmount__c;
        }
        if (strategy != 'MEDIA_MOVEL') {
            throw new IllegalArgumentException('Unsupported Provisioning Strategy.');
        }

        Decimal total = paidValue;
        Integer count = 1;
        for (AXF_OBJ_CashFlow__c entry : series) {
            if (entry.Id != target.Id && SETTLED_STATUSES.contains(entry.AXF_CF_PKL_Status__c)) {
                total += entry.AXF_CF_CUR_PaidValue__c != null
                    ? entry.AXF_CF_CUR_PaidValue__c
                    : entry.AXF_CF_CUR_Value__c;
                count++;
            }
        }
        return (total / count).setScale(2, System.RoundingMode.HALF_UP);
    }

    private static AXF_OBJ_CashFlow__c buildForecastEntry(
        AXF_OBJ_CashFlow__c source,
        Date dueDate,
        Integer sequence,
        Decimal forecastValue,
        Boolean variable
    ) {
        String generatedName = source.Name + ' - ' + String.valueOf(sequence);
        if (generatedName.length() > 80) {
            generatedName = generatedName.left(80);
        }
        return new AXF_OBJ_CashFlow__c(
            RecordTypeId = source.RecordTypeId,
            Name = generatedName,
            AXF_CF_CUR_Value__c = forecastValue,
            AXF_CF_DAT_PurchaseDate__c = source.AXF_CF_DAT_PurchaseDate__c,
            AXF_CF_DAT_DueDate__c = dueDate,
            AXF_CF_PKL_Status__c = dueDate < Date.today() ? 'VENCIDA' : 'PENDENTE',
            AXF_CF_PKL_PaymentMode__c = source.AXF_CF_PKL_PaymentMode__c,
            AXF_CF_PKL_PaymentMethod__c = source.AXF_CF_PKL_PaymentMethod__c,
            AXF_CF_PKL_RecurringType__c = source.AXF_CF_PKL_RecurringType__c,
            AXF_CF_PKL_ProvisioningStrategy__c = variable ? source.AXF_CF_PKL_ProvisioningStrategy__c : null,
            AXF_CF_CHK_IsEstimated__c = variable,
            AXF_CF_NUM_CurrentInstallment__c = sequence,
            AXF_CF_NUM_TotalInstallments__c = null,
            AXF_CF_LKP_Category__c = source.AXF_CF_LKP_Category__c,
            AXF_CF_LKP_Account__c = source.AXF_CF_LKP_Account__c,
            AXF_CF_LKP_BankAccount__c = source.AXF_CF_LKP_BankAccount__c,
            AXF_CF_LKP_CreditCard__c = source.AXF_CF_LKP_CreditCard__c,
            AXF_CF_LKP_InstallmentGroup__c = source.AXF_CF_LKP_InstallmentGroup__c
        );
    }
}