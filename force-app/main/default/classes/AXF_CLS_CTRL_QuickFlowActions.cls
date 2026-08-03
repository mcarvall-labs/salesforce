/**
 * @description Dedicated controller for aXF_LWC_quickFlowActions.
 */
public with sharing class AXF_CLS_CTRL_QuickFlowActions {
    private static final Set<String> BANK_METHODS = new Set<String>{ 'DEBITO_CONTA', 'TRANSFERENCIA_PIX' };
    private static final Set<String> CARD_METHODS = new Set<String>{ 'CARTAO_CREDITO' };
    private static final Set<String> OTHER_METHODS = new Set<String>{ 'BOLETO', 'DINHEIRO' };
    private static final Set<String> PAYMENT_MODES = new Set<String>{
        'A_VISTA', 'RECORRENTE', 'FINANCIAMENTO', 'FINANCIAMENTO_SAC', 'CONSORCIO'
    };
    private static final Set<String> RECURRING_TYPES = new Set<String>{ 'FIXO', 'VARIAVEL' };
    private static final Set<String> PROVISIONING_STRATEGIES = new Set<String>{ 'MEDIA_MOVEL', 'ULTIMO_VALOR', 'VALOR_BASE' };
    private static final Set<String> FINANCING_TYPES = new Set<String>{ 'PRICE', 'SAC' };

    public class CashFlowCreationDTO {
        @AuraEnabled public String type;
        @AuraEnabled public String description;
        @AuraEnabled public String categoryId;
        @AuraEnabled public String accountId;
        @AuraEnabled public Date purchaseDate;
        @AuraEnabled public Date firstDueDate;
        @AuraEnabled public String paymentMode;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Boolean isTotalAmount;
        @AuraEnabled public Integer totalInstallments;
        @AuraEnabled public String paymentMethod;
        @AuraEnabled public String bankAccountId;
        @AuraEnabled public String creditCardId;
        @AuraEnabled public String recurringType;
        @AuraEnabled public String provisioningStrategy;
        @AuraEnabled public String financingType;
        @AuraEnabled public Decimal monthlyAdjustmentRate;
        @AuraEnabled public Date adjustmentAnniversary;
        @AuraEnabled public Boolean isPaid;
        @AuraEnabled public Decimal paidValue;
        @AuraEnabled public Date paymentDate;
        @AuraEnabled public Boolean pastDueConfirmed;
    }

    @AuraEnabled
    public static List<Id> createCashFlowSeries(CashFlowCreationDTO dto) {
        try {
            ALT_CLS_CashFlowHome.CashFlowSeriesRequest request = validateAndMap(dto);
            return new ALT_CLS_CashFlowHome().createCashFlowSeries(request);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw handled('Unable to save the cash-flow entry.');
        }
    }

    private static ALT_CLS_CashFlowHome.CashFlowSeriesRequest validateAndMap(CashFlowCreationDTO dto) {
        if (dto == null) {
            throw handled('Invalid input payload.');
        }
        if (String.isBlank(dto.description) || dto.amount == null || dto.amount <= 0 || dto.firstDueDate == null) {
            throw handled('Description, Due Date, and a positive amount are required.');
        }
        if (dto.type != 'DESPESA' && dto.type != 'RECEITA') {
            throw handled('Select a valid entry type.');
        }
        Boolean recurringMode = dto.paymentMode == 'RECORRENTE';
        if (!recurringMode && (dto.totalInstallments == null || dto.totalInstallments < 1 || dto.totalInstallments > 120)) {
            throw handled('Total Installments must be between 1 and 120.');
        }        Id accountId = parseId(dto.accountId, Account.SObjectType, 'Account is required.');
        Id categoryId = parseOptionalId(dto.categoryId, AXF_OBJ_Category__c.SObjectType, 'Invalid Category.');
        Id bankAccountId = parseOptionalId(
            dto.bankAccountId,
            AXF_OBJ_BankAccount__c.SObjectType,
            'Invalid Bank Account.'
        );
        Id creditCardId = parseOptionalId(
            dto.creditCardId,
            AXF_OBJ_CreditCard__c.SObjectType,
            'Invalid Credit Card.'
        );

        validatePaymentMethod(dto.paymentMethod, bankAccountId, creditCardId);
        validateModality(dto);
        validateOwnership(accountId, bankAccountId, creditCardId);
        validatePaidFields(dto);
        validatePastDueConfirmation(dto);

        ALT_CLS_CashFlowHome.CashFlowSeriesRequest request = new ALT_CLS_CashFlowHome.CashFlowSeriesRequest();
        request.entryType = dto.type;
        request.description = dto.description.trim();
        request.categoryId = categoryId;
        request.accountId = accountId;
        request.purchaseDate = dto.purchaseDate;
        request.firstDueDate = dto.firstDueDate;
        request.paymentMode = dto.paymentMode;
        request.amount = dto.amount;
        request.isTotalAmount = dto.isTotalAmount == true;
        request.totalInstallments = dto.paymentMode == 'RECORRENTE' ? 6 : dto.totalInstallments;
        request.paymentMethod = dto.paymentMethod;
        request.bankAccountId = bankAccountId;
        request.creditCardId = creditCardId;
        request.recurringType = dto.recurringType;
        request.provisioningStrategy = dto.provisioningStrategy;
        request.financingType = dto.financingType;
        request.monthlyAdjustmentRate = dto.monthlyAdjustmentRate;
        request.adjustmentAnniversary = dto.adjustmentAnniversary;
        request.isPaid = dto.isPaid == true;
        request.paidValue = request.isPaid ? dto.paidValue : null;
        request.paymentDate = request.isPaid ? dto.paymentDate : null;
        return request;
    }

    private static void validatePaymentMethod(String method, Id bankAccountId, Id creditCardId) {
        if (String.isBlank(method) || (!BANK_METHODS.contains(method) && !CARD_METHODS.contains(method) && !OTHER_METHODS.contains(method))) {
            throw handled('Select a valid Payment Method.');
        }
        if (BANK_METHODS.contains(method) && (bankAccountId == null || creditCardId != null)) {
            throw handled('Select one Bank Account for the chosen Payment Method.');
        }
        if (CARD_METHODS.contains(method) && (creditCardId == null || bankAccountId != null)) {
            throw handled('Select one Credit Card for the chosen Payment Method.');
        }
        if (OTHER_METHODS.contains(method) && (bankAccountId != null || creditCardId != null)) {
            throw handled('Bank Account and Credit Card are not applicable to the chosen Payment Method.');
        }
    }

    private static void validateModality(CashFlowCreationDTO dto) {
        Boolean recurring = dto.paymentMode == 'RECORRENTE';
        Boolean financing = dto.paymentMode == 'FINANCIAMENTO' || dto.paymentMode == 'FINANCIAMENTO_SAC';
        Boolean consortium = dto.paymentMode == 'CONSORCIO';

        if (dto.paymentMode == 'A_VISTA' && dto.totalInstallments != null && dto.totalInstallments > 1) {
            throw handled('A single payment cannot have multiple installments.');
        }
        if (recurring && dto.type != 'DESPESA') {
            throw handled('Recurring entries are available only for Expenses.');
        }
        if (recurring && !RECURRING_TYPES.contains(dto.recurringType)) {
            throw handled('Select a valid Recurring Type.');
        }
        Boolean variableRecurring = recurring && dto.recurringType == 'VARIAVEL';
        if (variableRecurring && !PROVISIONING_STRATEGIES.contains(dto.provisioningStrategy)) {
            throw handled('Select a valid Provisioning Strategy for variable recurrence.');
        }
        if (recurring && !variableRecurring && String.isNotBlank(dto.provisioningStrategy)) {
            throw handled('Provisioning Strategy is applicable only to variable recurrence.');
        }        if (!recurring && (String.isNotBlank(dto.recurringType) || String.isNotBlank(dto.provisioningStrategy))) {
            throw handled('Recurring fields are not applicable to the selected modality.');
        }
        if (financing && String.isBlank(dto.financingType)) {
            throw handled('Financing Type is required for financing entries.');
        }
        if (financing && !FINANCING_TYPES.contains(dto.financingType)) {
            throw handled('Select a valid Financing Type.');
        }
        if (dto.paymentMode == 'FINANCIAMENTO_SAC' && dto.financingType != 'SAC') {
            throw handled('SAC financing requires the SAC Financing Type.');
        }
        if (!financing && (String.isNotBlank(dto.financingType) || dto.monthlyAdjustmentRate != null)) {
            throw handled('Financing fields are not applicable to the selected modality.');
        }
        if (consortium != (dto.adjustmentAnniversary != null)) {
            throw handled('Adjustment Anniversary is required only for consortium entries.');
        }
    }
    private static void validateOwnership(Id accountId, Id bankAccountId, Id creditCardId) {
        if (bankAccountId != null && [
            SELECT COUNT()
            FROM AXF_OBJ_BankAccount__c
            WHERE Id = :bankAccountId AND AXF_BA_LKP_Account__c = :accountId
            WITH USER_MODE
        ] == 0) {
            throw handled('The selected Bank Account does not belong to the Account holder.');
        }
        if (creditCardId != null && [
            SELECT COUNT()
            FROM AXF_OBJ_CreditCard__c
            WHERE Id = :creditCardId AND AXF_CC_LKP_Account__c = :accountId
            WITH USER_MODE
        ] == 0) {
            throw handled('The selected Credit Card does not belong to the Account holder.');
        }
    }

    private static void validatePaidFields(CashFlowCreationDTO dto) {
        if (dto.isPaid == true && (dto.paidValue == null || dto.paidValue <= 0 || dto.paymentDate == null)) {
            throw handled('Paid Value and Payment Date are required for a paid entry.');
        }
        if (dto.isPaid != true && (dto.paidValue != null || dto.paymentDate != null)) {
            throw handled('Settlement fields are not applicable to an open entry.');
        }
    }

    private static void validatePastDueConfirmation(CashFlowCreationDTO dto) {
        if (dto.isPaid != true && dto.firstDueDate != null && dto.firstDueDate < Date.today() && dto.pastDueConfirmed != true) {
            throw handled('Confirm the creation of the past-due entry before saving.');
        }
    }

    private static Id parseId(String value, Schema.SObjectType expectedType, String message) {
        Id parsed = parseOptionalId(value, expectedType, message);
        if (parsed == null) {
            throw handled(message);
        }
        return parsed;
    }

    private static Id parseOptionalId(String value, Schema.SObjectType expectedType, String message) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            Id parsed = (Id) value;
            if (parsed.getSObjectType() != expectedType) {
                throw handled(message);
            }
            return parsed;
        } catch (Exception e) {
            throw handled(message);
        }
    }

    private static AuraHandledException handled(String message) {
        AuraHandledException exceptionValue = new AuraHandledException(message);
        exceptionValue.setMessage(message);
        return exceptionValue;
    }
}
