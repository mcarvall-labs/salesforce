/**
 * @description Business service layer for the Cash Flow Home capability: monthly movements
 * (expenses/revenues), bank/credit card transaction search for settlement linking, cash flow
 * entry creation (single or installment series), and settlement of existing entries. Consumed
 * by AXF_CLS_CTRL_ExpenseHomeTable, AXF_CLS_CTRL_RevenueHomeTable and AXF_CLS_CTRL_QuickFlowActions.
 * Contains no @AuraEnabled members and no LWC-specific concepts, per PROJECT_RULES.md §3.
 */
public inherited sharing class ALT_CLS_CashFlowHome {

    private static final Decimal DEFAULT_SAC_MONTHLY_ADJUSTMENT_RATE = -1.50;
    public class CashFlowSeriesRequest {
        public String entryType;
        public String description;
        public Id categoryId;
        public Id accountId;
        public Date purchaseDate;
        public Date firstDueDate;
        public String paymentMode;
        public Decimal amount;
        public Boolean isTotalAmount;
        public Integer totalInstallments;
        public String paymentMethod;
        public Id bankAccountId;
        public Id creditCardId;
        public String recurringType;
        public String provisioningStrategy;
        public String financingType;
        public Decimal monthlyAdjustmentRate;
        public Date adjustmentAnniversary;
        public Boolean isPaid;
        public Decimal paidValue;
        public Date paymentDate;
    }

    public List<AXF_OBJ_CashFlow__c> getMonthlyMovements(String recordTypeDeveloperName, Id categoryId) {
        Date today = Date.today();
        Date monthStart = Date.newInstance(today.year(), today.month(), 1);
        Date monthEnd = monthStart.addMonths(1).addDays(-1);

        Map<String, Schema.RecordTypeInfo> rtInfos = AXF_OBJ_CashFlow__c.SObjectType
            .getDescribe(SObjectDescribeOptions.DEFERRED)
            .getRecordTypeInfosByDeveloperName();
        if (!rtInfos.containsKey(recordTypeDeveloperName)) {
            return new List<AXF_OBJ_CashFlow__c>();
        }
        Id rtId = rtInfos.get(recordTypeDeveloperName).getRecordTypeId();

        String query = 'SELECT Id, Name, AXF_CF_DAT_DueDate__c, AXF_CF_DAT_PaymentDate__c, AXF_CF_PKL_Status__c, ' +
                       '       AXF_CF_CUR_Value__c, AXF_CF_LKP_Category__c, AXF_CF_LKP_Category__r.Name, ' +
                       '       AXF_CF_LKP_BankAccountTransaction__c, AXF_CF_LKP_CreditCardTransaction__c ' +
                       'FROM AXF_OBJ_CashFlow__c ' +
                       'WHERE RecordTypeId = :rtId ' +
                       'AND AXF_CF_DAT_DueDate__c >= :monthStart ' +
                       'AND AXF_CF_DAT_DueDate__c <= :monthEnd ';

        if (categoryId != null) {
            query += 'AND AXF_CF_LKP_Category__c = :categoryId ';
        }

        query += 'ORDER BY AXF_CF_DAT_DueDate__c ASC';

        Map<String, Object> queryBinds = new Map<String, Object>{
            'rtId' => rtId,
            'monthStart' => monthStart,
            'monthEnd' => monthEnd,
            'categoryId' => categoryId
        };
        return Database.queryWithBinds(query, queryBinds, AccessLevel.USER_MODE);
    }

    public List<AXF_OBJ_BankAccountTransaction__c> searchBankTransactions(String searchTerm) {
        String term = '%' + String.escapeSingleQuotes(searchTerm) + '%';
        return [
            SELECT Id, Name, AXF_BAT_DAT_Date__c, AXF_BAT_TXT_Description__c, AXF_BAT_CUR_Amount__c
            FROM AXF_OBJ_BankAccountTransaction__c
            WHERE AXF_BAT_TXT_Description__c LIKE :term
            WITH USER_MODE
            ORDER BY AXF_BAT_DAT_Date__c DESC
            LIMIT 10
        ];
    }

    public List<AXF_OBJ_CreditCardTransaction__c> searchCreditCardTransactions(String searchTerm) {
        String term = '%' + String.escapeSingleQuotes(searchTerm) + '%';
        return [
            SELECT Id, Name, AXF_CCT_DAT_Date__c, AXF_CCT_TXT_Description__c, AXF_CCT_CUR_Amount__c
            FROM AXF_OBJ_CreditCardTransaction__c
            WHERE AXF_CCT_TXT_Description__c LIKE :term
            WITH USER_MODE
            ORDER BY AXF_CCT_DAT_Date__c DESC
            LIMIT 10
        ];
    }

    public void settleCashFlow(Id cashFlowId, String targetStatus, Date paymentDate, Id bankTransactionId, Id creditCardTransactionId) {
        if (cashFlowId == null) {
            throw new IllegalArgumentException('Cash Flow ID is required.');
        }

        AXF_OBJ_CashFlow__c cf = new AXF_OBJ_CashFlow__c(Id = cashFlowId);
        cf.AXF_CF_PKL_Status__c = targetStatus;
        cf.AXF_CF_DAT_PaymentDate__c = paymentDate;
        if (bankTransactionId != null) {
            cf.AXF_CF_LKP_BankAccountTransaction__c = bankTransactionId;
        }
        if (creditCardTransactionId != null) {
            cf.AXF_CF_LKP_CreditCardTransaction__c = creditCardTransactionId;
        }
        Database.update(cf, AccessLevel.USER_MODE);
    }

    /**
     * @description Creates a single Cash Flow entry, or an installment series sharing an
     * AXF_OBJ_InstallmentGroup__c parent when totalInstallments > 1.
     */
    public List<Id> createCashFlowSeries(CashFlowSeriesRequest request) {
        String rtDevName = (request.entryType == 'DESPESA' || request.entryType == 'Expense')
            ? 'AXF_CF_RT_Expense'
            : 'AXF_CF_RT_Revenue';
        Id recordTypeId = Schema.SObjectType.AXF_OBJ_CashFlow__c.getRecordTypeInfosByDeveloperName()
            .get(rtDevName)
            .getRecordTypeId();

        Integer installmentCount = request.totalInstallments != null && request.totalInstallments > 0
            ? request.totalInstallments
            : 1;
        Decimal installmentAmount = request.amount != null ? request.amount : 0;
        if (request.isTotalAmount == true && installmentCount > 1 && installmentAmount > 0) {
            installmentAmount = (installmentAmount / installmentCount).setScale(2, System.RoundingMode.HALF_UP);
        }

        Id installmentGroupId;
        if (installmentCount > 1) {
            String groupType = resolveGroupType(request.paymentMode);
            String resolvedFinancingType = resolveFinancingType(
                groupType,
                request.paymentMode,
                request.financingType
            );
            Decimal resolvedMonthlyAdjustmentRate = resolveMonthlyAdjustmentRate(
                resolvedFinancingType,
                request.monthlyAdjustmentRate
            );
            validateConsortiumConfiguration(groupType, request.adjustmentAnniversary);

            AXF_OBJ_InstallmentGroup__c groupRecord = new AXF_OBJ_InstallmentGroup__c(
                AXF_IG_NUM_TotalInstallments__c = groupType == 'RECURRING' ? null : installmentCount,
                AXF_IG_CUR_TotalAmount__c = groupType == 'RECURRING'
                    ? null
                    : (request.isTotalAmount == true ? request.amount : installmentAmount * installmentCount),
                AXF_IG_CUR_InstallmentAmount__c = installmentAmount,
                AXF_IG_DAT_FirstDueDate__c = request.firstDueDate,
                AXF_IG_PKL_GroupType__c = groupType,
                AXF_IG_PKL_FinancingType__c = resolvedFinancingType,
                AXF_IG_PCT_MonthlyAdjustmentRate__c = resolvedMonthlyAdjustmentRate,
                AXF_IG_DAT_AdjustmentAnniversary__c = groupType == 'CONSORTIUM'
                    ? request.adjustmentAnniversary
                    : null
            );
            Database.insert(groupRecord, AccessLevel.USER_MODE);
            installmentGroupId = groupRecord.Id;
        }

        List<AXF_OBJ_CashFlow__c> entries = new List<AXF_OBJ_CashFlow__c>();
        Date baseDueDate = request.firstDueDate != null ? request.firstDueDate : Date.today();
        Date resolvedPurchaseDate = request.purchaseDate != null ? request.purchaseDate : Date.today();
        for (Integer index = 0; index < installmentCount; index++) {
            Date dueDate = baseDueDate.addMonths(index);
            Boolean isSettledOccurrence = request.isPaid == true && index == 0;
            Decimal occurrenceAmount = request.isTotalAmount == true && installmentCount > 1 && index == installmentCount - 1
                ? request.amount - (installmentAmount * (installmentCount - 1))
                : installmentAmount;
            entries.add(new AXF_OBJ_CashFlow__c(
                RecordTypeId = recordTypeId,
                Name = installmentCount > 1
                    ? request.description + ' (' + (index + 1) + '/' + installmentCount + ')'
                    : request.description,
                AXF_CF_CUR_Value__c = occurrenceAmount,
                AXF_CF_CUR_PaidValue__c = isSettledOccurrence ? request.paidValue : null,
                AXF_CF_DAT_PurchaseDate__c = resolvedPurchaseDate,
                AXF_CF_DAT_DueDate__c = dueDate,
                AXF_CF_DAT_PaymentDate__c = isSettledOccurrence ? request.paymentDate : null,
                AXF_CF_PKL_PaymentMode__c = request.paymentMode,
                AXF_CF_PKL_PaymentMethod__c = request.paymentMethod,
                AXF_CF_PKL_RecurringType__c = request.recurringType,
                AXF_CF_PKL_ProvisioningStrategy__c = request.recurringType == 'VARIAVEL' ? request.provisioningStrategy : null,
                AXF_CF_CHK_IsEstimated__c = request.recurringType == 'VARIAVEL' && !isSettledOccurrence,
                AXF_CF_PKL_Status__c = resolveInitialStatus(request.entryType, dueDate, isSettledOccurrence, request.paymentDate),
                AXF_CF_NUM_CurrentInstallment__c = index + 1,
                AXF_CF_NUM_TotalInstallments__c = request.paymentMode == 'RECORRENTE' ? null : installmentCount,
                AXF_CF_LKP_Category__c = request.categoryId,
                AXF_CF_LKP_Account__c = request.accountId,
                AXF_CF_LKP_BankAccount__c = request.bankAccountId,
                AXF_CF_LKP_CreditCard__c = request.creditCardId,
                AXF_CF_LKP_InstallmentGroup__c = installmentGroupId
            ));
        }

        Database.insert(entries, AccessLevel.USER_MODE);
        List<Id> insertedIds = new List<Id>();
        for (AXF_OBJ_CashFlow__c entry : entries) {
            insertedIds.add(entry.Id);
        }
        return insertedIds;
    }
    private static String resolveInitialStatus(String entryType, Date dueDate, Boolean isSettled, Date paymentDate) {
        if (!isSettled) {
            return dueDate < Date.today() ? 'VENCIDA' : 'PENDENTE';
        }

        Boolean isExpense = entryType == 'DESPESA' || entryType == 'Expense';
        Boolean isLate = paymentDate > dueDate;
        if (isExpense) {
            return isLate ? 'PAGA_EM_ATRASO' : 'PAGA';
        }
        return isLate ? 'RECEBIDA_EM_ATRASO' : 'RECEBIDA';
    }
    private static String resolveGroupType(String paymentMode) {
        if (paymentMode == 'FINANCIAMENTO' || paymentMode == 'FINANCIAMENTO_SAC') {
            return 'FINANCING';
        }
        if (paymentMode == 'CONSORCIO') {
            return 'CONSORTIUM';
        }
        if (paymentMode == 'RECORRENTE') {
            return 'RECURRING';
        }
        return 'INSTALLMENT';
    }

    private static String resolveFinancingType(String groupType, String paymentMode, String financingType) {
        if (groupType != 'FINANCING') {
            return null;
        }

        String resolvedType = String.isNotBlank(financingType)
            ? financingType.toUpperCase()
            : (paymentMode == 'FINANCIAMENTO_SAC' ? 'SAC' : 'PRICE');
        if (resolvedType != 'PRICE' && resolvedType != 'SAC') {
            throw new IllegalArgumentException('Financing Type must be PRICE or SAC.');
        }
        return resolvedType;
    }

    private static Decimal resolveMonthlyAdjustmentRate(String financingType, Decimal monthlyAdjustmentRate) {
        if (financingType != 'SAC') {
            if (monthlyAdjustmentRate != null) {
                throw new IllegalArgumentException('Monthly Adjustment Rate is applicable only to SAC financing groups.');
            }
            return null;
        }
        return monthlyAdjustmentRate != null
            ? monthlyAdjustmentRate
            : DEFAULT_SAC_MONTHLY_ADJUSTMENT_RATE;
    }

    private static void validateConsortiumConfiguration(String groupType, Date adjustmentAnniversary) {
        if (groupType == 'CONSORTIUM' && adjustmentAnniversary == null) {
            throw new IllegalArgumentException('Adjustment Anniversary is required for consortium groups.');
        }
        if (groupType != 'CONSORTIUM' && adjustmentAnniversary != null) {
            throw new IllegalArgumentException('Adjustment Anniversary is applicable only to consortium groups.');
        }
    }
}
