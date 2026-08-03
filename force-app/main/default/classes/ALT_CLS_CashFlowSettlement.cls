/**
 * @description Consolidates Cash Flow settlement and maintains recurring forecast horizons.
 * Contains no Aura-enabled members and can be reused by settlement controllers.
 */
public inherited sharing class ALT_CLS_CashFlowSettlement {
    private static final Integer FUTURE_HORIZON = 6;
    private static final Set<String> OPEN_STATUSES = new Set<String>{ 'PENDENTE', 'VENCIDA' };
    private static final Set<String> SETTLED_STATUSES = new Set<String>{ 'PAGA', 'PAGA_EM_ATRASO' };
    public static Boolean serviceOperation = false;

    public class ReconciliationSuggestion {
        public Id transactionId;
        public String source;
        public Date transactionDate;
        public Decimal amount;
        public String description;
        public Integer score;
        public String confidence;
    }

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
                   AXF_CF_LKP_InstallmentGroup__c, AXF_CF_PKL_ReconciliationStatus__c,
                   AXF_CF_LKP_BankAccountTransaction__c, AXF_CF_LKP_CreditCardTransaction__c
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
                       AXF_IG_CUR_InstallmentAmount__c, AXF_IG_CUR_TotalAmount__c,
                       AXF_IG_PKL_FinancingType__c
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
                       AXF_CF_LKP_InstallmentGroup__c, AXF_CF_PKL_ReconciliationStatus__c,
                   AXF_CF_LKP_BankAccountTransaction__c, AXF_CF_LKP_CreditCardTransaction__c
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
        SObject reconciliationTransaction = prepareReconciliation(
            target,
            bankTransactionId,
            creditCardTransactionId
        );
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

        serviceOperation = true;
        try {
            Database.update(recordsToUpdate, AccessLevel.USER_MODE);
            if (!recordsToInsert.isEmpty()) {
                Database.insert(recordsToInsert, AccessLevel.USER_MODE);
            }
            if (reconciliationTransaction != null) {
                Database.update(reconciliationTransaction, AccessLevel.USER_MODE);
            }
        } finally {
            serviceOperation = false;
        }    }

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
        target.AXF_CF_PKL_ReconciliationStatus__c = bankTransactionId != null || creditCardTransactionId != null
            ? 'RECONCILED'
            : 'UNRECONCILED';
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

    public List<ReconciliationSuggestion> getSuggestions(Id cashFlowId) {
        if (cashFlowId == null) {
            throw new IllegalArgumentException('Cash Flow ID is required.');
        }
        AXF_OBJ_CashFlow__c cashFlow = [
            SELECT Id, AXF_CF_CUR_Value__c, AXF_CF_DAT_DueDate__c,
                   AXF_CF_LKP_BankAccount__c, AXF_CF_LKP_CreditCard__c
            FROM AXF_OBJ_CashFlow__c
            WHERE Id = :cashFlowId
            WITH USER_MODE
        ];
        Date startDate = cashFlow.AXF_CF_DAT_DueDate__c.addDays(-7);
        Date endDate = cashFlow.AXF_CF_DAT_DueDate__c.addDays(7);
        List<ReconciliationSuggestion> suggestions = new List<ReconciliationSuggestion>();
        if (cashFlow.AXF_CF_LKP_BankAccount__c != null) {
            for (AXF_OBJ_BankAccountTransaction__c transactionRecord : [
                SELECT Id, AXF_BAT_DAT_Date__c, AXF_BAT_CUR_Amount__c, AXF_BAT_TXT_Description__c
                FROM AXF_OBJ_BankAccountTransaction__c
                WHERE AXF_BAT_LKP_BankAccount__c = :cashFlow.AXF_CF_LKP_BankAccount__c
                  AND AXF_BAT_DAT_Date__c >= :startDate AND AXF_BAT_DAT_Date__c <= :endDate
                  AND AXF_BAT_PKL_ReconciliationStatus__c = 'UNRECONCILED'
                  AND AXF_BAT_LKP_CashFlow__c = null
                WITH USER_MODE
                LIMIT 100
            ]) {
                addSuggestion(suggestions, 'BANK', transactionRecord.Id, transactionRecord.AXF_BAT_DAT_Date__c,
                    transactionRecord.AXF_BAT_CUR_Amount__c, transactionRecord.AXF_BAT_TXT_Description__c, cashFlow);
            }
        }
        if (cashFlow.AXF_CF_LKP_CreditCard__c != null) {
            for (AXF_OBJ_CreditCardTransaction__c transactionRecord : [
                SELECT Id, AXF_CCT_DAT_Date__c, AXF_CCT_CUR_Amount__c, AXF_CCT_TXT_Description__c
                FROM AXF_OBJ_CreditCardTransaction__c
                WHERE AXF_CCT_LKP_CreditCard__c = :cashFlow.AXF_CF_LKP_CreditCard__c
                  AND AXF_CCT_DAT_Date__c >= :startDate AND AXF_CCT_DAT_Date__c <= :endDate
                  AND AXF_CCT_PKL_ReconciliationStatus__c = 'UNRECONCILED'
                  AND AXF_CCT_LKP_CashFlow__c = null
                WITH USER_MODE
                LIMIT 100
            ]) {
                addSuggestion(suggestions, 'CARD', transactionRecord.Id, transactionRecord.AXF_CCT_DAT_Date__c,
                    transactionRecord.AXF_CCT_CUR_Amount__c, transactionRecord.AXF_CCT_TXT_Description__c, cashFlow);
            }
        }
        suggestions.sort(new SuggestionComparator());
        return suggestions;
    }

    public void unreconcile(Id cashFlowId) {
        AXF_OBJ_CashFlow__c cashFlow = [
            SELECT Id, AXF_CF_PKL_ReconciliationStatus__c,
                   AXF_CF_LKP_BankAccountTransaction__c, AXF_CF_LKP_CreditCardTransaction__c
            FROM AXF_OBJ_CashFlow__c WHERE Id = :cashFlowId WITH USER_MODE FOR UPDATE
        ];
        SObject transactionRecord;
        if (cashFlow.AXF_CF_LKP_BankAccountTransaction__c != null) {
            AXF_OBJ_BankAccountTransaction__c bank = [
                SELECT Id, AXF_BAT_LKP_CashFlow__c FROM AXF_OBJ_BankAccountTransaction__c
                WHERE Id = :cashFlow.AXF_CF_LKP_BankAccountTransaction__c WITH USER_MODE FOR UPDATE
            ];
            bank.AXF_BAT_LKP_CashFlow__c = null;
            bank.AXF_BAT_PKL_ReconciliationStatus__c = 'UNRECONCILED';
            transactionRecord = bank;
        } else if (cashFlow.AXF_CF_LKP_CreditCardTransaction__c != null) {
            AXF_OBJ_CreditCardTransaction__c card = [
                SELECT Id, AXF_CCT_LKP_CashFlow__c FROM AXF_OBJ_CreditCardTransaction__c
                WHERE Id = :cashFlow.AXF_CF_LKP_CreditCardTransaction__c WITH USER_MODE FOR UPDATE
            ];
            card.AXF_CCT_LKP_CashFlow__c = null;
            card.AXF_CCT_PKL_ReconciliationStatus__c = 'UNRECONCILED';
            transactionRecord = card;
        }
        cashFlow.AXF_CF_LKP_BankAccountTransaction__c = null;
        cashFlow.AXF_CF_LKP_CreditCardTransaction__c = null;
        cashFlow.AXF_CF_PKL_ReconciliationStatus__c = 'UNRECONCILED';
        serviceOperation = true;
        try {
            Database.update(cashFlow, AccessLevel.USER_MODE);
            if (transactionRecord != null) {
                Database.update(transactionRecord, AccessLevel.USER_MODE);
            }
        } finally {
            serviceOperation = false;
        }
    }

    private static SObject prepareReconciliation(AXF_OBJ_CashFlow__c target, Id bankId, Id cardId) {
        if ((target.AXF_CF_LKP_BankAccountTransaction__c != null && target.AXF_CF_LKP_BankAccountTransaction__c != bankId)
            || (target.AXF_CF_LKP_CreditCardTransaction__c != null && target.AXF_CF_LKP_CreditCardTransaction__c != cardId)) {
            throw new IllegalArgumentException('Unreconcile the existing transaction before selecting another one.');
        }
        if (bankId != null) {
            AXF_OBJ_BankAccountTransaction__c bank = [
                SELECT Id, AXF_BAT_LKP_BankAccount__c, AXF_BAT_PKL_ReconciliationStatus__c, AXF_BAT_LKP_CashFlow__c
                FROM AXF_OBJ_BankAccountTransaction__c WHERE Id = :bankId WITH USER_MODE FOR UPDATE
            ];
            if (bank.AXF_BAT_LKP_CashFlow__c != null && bank.AXF_BAT_LKP_CashFlow__c != target.Id)
                throw new IllegalArgumentException('The bank transaction is already reconciled.');
            if (target.AXF_CF_LKP_BankAccount__c != null && bank.AXF_BAT_LKP_BankAccount__c != target.AXF_CF_LKP_BankAccount__c)
                throw new IllegalArgumentException('The bank transaction belongs to another Bank Account.');
            bank.AXF_BAT_PKL_ReconciliationStatus__c = 'RECONCILED';
            bank.AXF_BAT_LKP_CashFlow__c = target.Id;
            return bank;
        }
        if (cardId != null) {
            AXF_OBJ_CreditCardTransaction__c card = [
                SELECT Id, AXF_CCT_LKP_CreditCard__c, AXF_CCT_PKL_ReconciliationStatus__c, AXF_CCT_LKP_CashFlow__c
                FROM AXF_OBJ_CreditCardTransaction__c WHERE Id = :cardId WITH USER_MODE FOR UPDATE
            ];
            if (card.AXF_CCT_LKP_CashFlow__c != null && card.AXF_CCT_LKP_CashFlow__c != target.Id)
                throw new IllegalArgumentException('The credit-card transaction is already reconciled.');
            if (target.AXF_CF_LKP_CreditCard__c != null && card.AXF_CCT_LKP_CreditCard__c != target.AXF_CF_LKP_CreditCard__c)
                throw new IllegalArgumentException('The transaction belongs to another Credit Card.');
            card.AXF_CCT_PKL_ReconciliationStatus__c = 'RECONCILED';
            card.AXF_CCT_LKP_CashFlow__c = target.Id;
            return card;
        }
        return null;
    }

    private static void addSuggestion(List<ReconciliationSuggestion> values, String source, Id recordId, Datetime valueDate,
        Decimal amount, String description, AXF_OBJ_CashFlow__c cashFlow) {
        Decimal expected = cashFlow.AXF_CF_CUR_Value__c.abs();
        Decimal difference = (amount.abs() - expected).abs();
        Integer score = difference == 0 ? 80 : (expected > 0 && difference / expected <= 0.05 ? 70 : 50);
        Integer dateDifference = Math.abs(cashFlow.AXF_CF_DAT_DueDate__c.daysBetween(valueDate.date()));
        score += dateDifference == 0 ? 20 : (dateDifference <= 3 ? 10 : 0);
        if (score < 60) return;
        ReconciliationSuggestion suggestion = new ReconciliationSuggestion();
        suggestion.transactionId = recordId; suggestion.source = source; suggestion.transactionDate = valueDate.date();
        suggestion.amount = amount; suggestion.description = description; suggestion.score = score;
        suggestion.confidence = score >= 80 ? 'HIGH' : 'MEDIUM';
        values.add(suggestion);
    }

    private class SuggestionComparator implements Comparator<ReconciliationSuggestion> {
        public Integer compare(ReconciliationSuggestion left, ReconciliationSuggestion right) {
            if (left.score != right.score) return right.score - left.score;
            Integer dateComparison = left.transactionDate.daysBetween(right.transactionDate);
            if (dateComparison != 0) return dateComparison;
            return String.valueOf(left.transactionId).compareTo(String.valueOf(right.transactionId));
        }
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
