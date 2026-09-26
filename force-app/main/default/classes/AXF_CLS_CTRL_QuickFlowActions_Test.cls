@isTest
private class AXF_CLS_CTRL_QuickFlowActions_Test {

    @testSetup
    static void setupTestData() {
        Account testAccount = new Account(Name = 'Test Household');
        insert testAccount;

        Id expenseRtId = Schema.SObjectType.AXF_OBJ_Category__c.getRecordTypeInfosByDeveloperName()
            .get('AXF_CAT_RT_Expense').getRecordTypeId();
        AXF_OBJ_Category__c testCategory = new AXF_OBJ_Category__c(
            Name = 'Supermercado',
            RecordTypeId = expenseRtId
        );
        insert testCategory;

        AXF_OBJ_BankAccount__c testBankAcc = new AXF_OBJ_BankAccount__c(
            Name = 'Conta Corrente Itaú',
            AXF_BA_LKP_Account__c = testAccount.Id,
            AXF_BA_EXI_PluggyAccountId__c = 'ACC_TEST_001'
        );
        insert testBankAcc;

        AXF_OBJ_CreditCard__c testCard = new AXF_OBJ_CreditCard__c(
            Name = 'Cartão Nubank',
            AXF_CC_LKP_Account__c = testAccount.Id,
            AXF_CC_EXI_PluggyCreditCardId__c = 'CARD_TEST_001'
        );
        insert testCard;
    }

    @isTest
    static void testCreateCashFlowSeries_Success() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        AXF_OBJ_Category__c cat = [SELECT Id FROM AXF_OBJ_Category__c LIMIT 1];
        AXF_OBJ_BankAccount__c bankAcc = [SELECT Id FROM AXF_OBJ_BankAccount__c LIMIT 1];

        AXF_CLS_CTRL_QuickFlowActions.CashFlowCreationDTO dto = new AXF_CLS_CTRL_QuickFlowActions.CashFlowCreationDTO();
        dto.type = 'DESPESA';
        dto.description = 'Financiamento Carro';
        dto.categoryId = cat.Id;
        dto.accountId = acc.Id;
        dto.purchaseDate = Date.today();
        dto.firstDueDate = Date.today().addDays(5);
        dto.paymentMode = 'FINANCIAMENTO';
        dto.amount = 1200.00;
        dto.isTotalAmount = false;
        dto.totalInstallments = 2;
        dto.paymentMethod = 'DEBITO_CONTA';
        dto.bankAccountId = bankAcc.Id;
        dto.recurringType = 'FIXO';
        dto.provisioningStrategy = 'VALOR_BASE';

        Test.startTest();
        List<Id> ids = AXF_CLS_CTRL_QuickFlowActions.createCashFlowSeries(dto);
        Test.stopTest();

        Assert.areEqual(2, ids.size(), 'Should create 2 cash flow records');
        AXF_OBJ_CashFlow__c createdCf = [SELECT Id, AXF_CF_PKL_PaymentMode__c, AXF_CF_PKL_PaymentMethod__c, AXF_CF_LKP_BankAccount__c FROM AXF_OBJ_CashFlow__c WHERE Id = :ids[0]];
        Assert.areEqual('FINANCIAMENTO', createdCf.AXF_CF_PKL_PaymentMode__c);
        Assert.areEqual('DEBITO_CONTA', createdCf.AXF_CF_PKL_PaymentMethod__c);
        Assert.areEqual(bankAcc.Id, createdCf.AXF_CF_LKP_BankAccount__c);
    }

    @isTest
    static void testCreateCashFlowSeries_CreditCard() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        AXF_OBJ_CreditCard__c card = [SELECT Id FROM AXF_OBJ_CreditCard__c LIMIT 1];

        AXF_CLS_CTRL_QuickFlowActions.CashFlowCreationDTO dto = new AXF_CLS_CTRL_QuickFlowActions.CashFlowCreationDTO();
        dto.type = 'DESPESA';
        dto.description = 'Compra no Cartão';
        dto.accountId = acc.Id;
        dto.purchaseDate = Date.today();
        dto.firstDueDate = Date.today();
        dto.paymentMode = 'A_VISTA';
        dto.amount = 350.00;
        dto.isTotalAmount = true;
        dto.totalInstallments = 1;
        dto.paymentMethod = 'CARTAO_CREDITO';
        dto.creditCardId = card.Id;

        Test.startTest();
        List<Id> ids = AXF_CLS_CTRL_QuickFlowActions.createCashFlowSeries(dto);
        Test.stopTest();

        Assert.areEqual(1, ids.size());
        AXF_OBJ_CashFlow__c createdCf = [SELECT Id, AXF_CF_LKP_CreditCard__c FROM AXF_OBJ_CashFlow__c WHERE Id = :ids[0]];
        Assert.areEqual(card.Id, createdCf.AXF_CF_LKP_CreditCard__c);
    }

    @isTest
    static void testCreateCashFlowSeries_Validations() {
        Test.startTest();
        try {
            AXF_CLS_CTRL_QuickFlowActions.createCashFlowSeries(null);
            Assert.fail('Should have thrown AuraHandledException for null dto');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }

        try {
            AXF_CLS_CTRL_QuickFlowActions.CashFlowCreationDTO dto = new AXF_CLS_CTRL_QuickFlowActions.CashFlowCreationDTO();
            dto.accountId = null;
            AXF_CLS_CTRL_QuickFlowActions.createCashFlowSeries(dto);
            Assert.fail('Should have thrown AuraHandledException for null accountId');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }
        Test.stopTest();
    }
}