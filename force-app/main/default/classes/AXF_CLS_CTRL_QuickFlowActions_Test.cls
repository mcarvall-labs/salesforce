@IsTest
private class AXF_CLS_CTRL_QuickFlowActions_Test {
  @TestSetup
  static void setupTestData() {
    User testUser = AXF_CLS_CashFlowTestFactory.createDomainUser();
    System.runAs(testUser) {
      Account testAccount = AXF_CLS_CashFlowTestFactory.createAccount(
        'Test Household'
      );
      Account otherAccount = AXF_CLS_CashFlowTestFactory.createAccount(
        'Other Household'
      );
      AXF_CLS_CashFlowTestFactory.createCategory('Supermercado', true);
      AXF_CLS_CashFlowTestFactory.createBankAccount(
        testAccount.Id,
        'ACC_TEST_001',
        0
      );
      AXF_CLS_CashFlowTestFactory.createCreditCard(
        testAccount.Id,
        'CARD_TEST_001'
      );
      AXF_CLS_CashFlowTestFactory.createBankAccount(
        otherAccount.Id,
        'ACC_OTHER_001',
        0
      );
      AXF_CLS_CashFlowTestFactory.createCreditCard(
        otherAccount.Id,
        'CARD_OTHER_001'
      );
    }
  }

  private static Account household() {
    return [SELECT Id FROM Account WHERE Name = 'Test Household' LIMIT 1];
  }

  private static AXF_OBJ_BankAccount__c bankAccount(String externalId) {
    return [
      SELECT Id
      FROM AXF_OBJ_BankAccount__c
      WHERE AXF_BA_EXI_PluggyAccountId__c = :externalId
    ];
  }

  private static AXF_OBJ_CreditCard__c creditCard(String externalId) {
    return [
      SELECT Id
      FROM AXF_OBJ_CreditCard__c
      WHERE AXF_CC_EXI_PluggyCreditCardId__c = :externalId
    ];
  }

  private static AXF_CLS_CTRL_QuickFlowActions.CashFlowCreationDTO validDto() {
    AXF_CLS_CTRL_QuickFlowActions.CashFlowCreationDTO dto = new AXF_CLS_CTRL_QuickFlowActions.CashFlowCreationDTO();
    dto.type = 'DESPESA';
    dto.description = 'Compra';
    dto.accountId = household().Id;
    dto.purchaseDate = Date.today();
    dto.firstDueDate = Date.today();
    dto.paymentMode = 'A_VISTA';
    dto.amount = 10;
    dto.paymentMethod = 'BOLETO';
    return dto;
  }

  private static String errorFor(
    AXF_CLS_CTRL_QuickFlowActions.CashFlowCreationDTO dto
  ) {
    try {
      AXF_CLS_CTRL_QuickFlowActions.createCashFlowSeries(dto);
      return null;
    } catch (AuraHandledException e) {
      return e.getMessage();
    }
  }

  @IsTest
  static void testCreateCashFlowSeries_Success() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      Account acc = household();
      AXF_OBJ_Category__c cat = [SELECT Id FROM AXF_OBJ_Category__c LIMIT 1];
      AXF_OBJ_BankAccount__c bankAcc = bankAccount('ACC_TEST_001');

      // Financing entries require a Financing Type and do not accept recurring fields.
      AXF_CLS_CTRL_QuickFlowActions.CashFlowCreationDTO dto = new AXF_CLS_CTRL_QuickFlowActions.CashFlowCreationDTO();
      dto.type = 'DESPESA';
      dto.description = 'Financiamento Carro';
      dto.categoryId = cat.Id;
      dto.accountId = acc.Id;
      dto.purchaseDate = Date.today();
      dto.firstDueDate = Date.today().addDays(5);
      dto.paymentMode = 'FINANCIAMENTO';
      dto.financingType = 'PRICE';
      dto.amount = 1200.00;
      dto.isTotalAmount = false;
      dto.totalInstallments = 2;
      dto.paymentMethod = 'DEBITO_CONTA';
      dto.bankAccountId = bankAcc.Id;

      Test.startTest();
      List<Id> ids = AXF_CLS_CTRL_QuickFlowActions.createCashFlowSeries(dto);
      Test.stopTest();

      Assert.areEqual(2, ids.size(), 'Should create 2 cash flow records');
      AXF_OBJ_CashFlow__c createdCf = [
        SELECT
          Id,
          AXF_CF_PKL_PaymentMode__c,
          AXF_CF_PKL_PaymentMethod__c,
          AXF_CF_LKP_BankAccount__c,
          AXF_CF_LKP_Category__c,
          AXF_CF_CUR_Value__c
        FROM AXF_OBJ_CashFlow__c
        WHERE Id = :ids[0]
      ];
      Assert.areEqual('FINANCIAMENTO', createdCf.AXF_CF_PKL_PaymentMode__c);
      Assert.areEqual('DEBITO_CONTA', createdCf.AXF_CF_PKL_PaymentMethod__c);
      Assert.areEqual(bankAcc.Id, createdCf.AXF_CF_LKP_BankAccount__c);
      Assert.areEqual(cat.Id, createdCf.AXF_CF_LKP_Category__c);
      Assert.areEqual(1200, createdCf.AXF_CF_CUR_Value__c);
    }
  }

  @IsTest
  static void testCreateCashFlowSeries_CreditCard() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      Account acc = household();
      AXF_OBJ_CreditCard__c card = creditCard('CARD_TEST_001');

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
      AXF_OBJ_CashFlow__c createdCf = [
        SELECT Id, AXF_CF_LKP_CreditCard__c, AXF_CF_PKL_Status__c
        FROM AXF_OBJ_CashFlow__c
        WHERE Id = :ids[0]
      ];
      Assert.areEqual(card.Id, createdCf.AXF_CF_LKP_CreditCard__c);
      Assert.areEqual('PENDENTE', createdCf.AXF_CF_PKL_Status__c);
    }
  }

  @IsTest
  static void testCreateCashFlowSeries_PaidRecurringRevenue() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      AXF_CLS_CTRL_QuickFlowActions.CashFlowCreationDTO dto = validDto();
      dto.type = 'RECEITA';
      dto.description = '  Aluguel recebido  ';
      dto.paymentMode = 'RECORRENTE';
      dto.recurringType = 'FIXO';
      dto.provisioningStrategy = 'VALOR_BASE';
      dto.totalInstallments = 2;
      dto.paymentMethod = 'TRANSFERENCIA_PIX';
      dto.bankAccountId = bankAccount('ACC_TEST_001').Id;
      dto.firstDueDate = null;
      dto.isPaid = true;
      dto.paidValue = 10;
      dto.paymentDate = Date.today();

      Test.startTest();
      List<Id> ids = AXF_CLS_CTRL_QuickFlowActions.createCashFlowSeries(dto);
      Test.stopTest();

      Assert.areEqual(2, ids.size());
      AXF_OBJ_CashFlow__c first = [
        SELECT
          Name,
          AXF_CF_PKL_Status__c,
          AXF_CF_CUR_PaidValue__c,
          AXF_CF_DAT_DueDate__c
        FROM AXF_OBJ_CashFlow__c
        WHERE Id = :ids[0]
      ];
      Assert.areEqual(
        'Aluguel recebido (1/2)',
        first.Name,
        'Description is trimmed'
      );
      Assert.areEqual('RECEBIDA', first.AXF_CF_PKL_Status__c);
      Assert.areEqual(10, first.AXF_CF_CUR_PaidValue__c);
      Assert.areEqual(
        Date.today(),
        first.AXF_CF_DAT_DueDate__c,
        'Due date defaults to the purchase date'
      );
    }
  }

  @IsTest
  static void testCreateCashFlowSeries_ConfirmedPastDue() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      AXF_CLS_CTRL_QuickFlowActions.CashFlowCreationDTO dto = validDto();
      dto.firstDueDate = Date.today().addDays(-2);
      dto.pastDueConfirmed = true;

      Test.startTest();
      List<Id> ids = AXF_CLS_CTRL_QuickFlowActions.createCashFlowSeries(dto);
      Test.stopTest();

      Assert.areEqual(
        'VENCIDA',
        [
          SELECT AXF_CF_PKL_Status__c
          FROM AXF_OBJ_CashFlow__c
          WHERE Id = :ids[0]
        ]
        .AXF_CF_PKL_Status__c
      );
    }
  }

  @IsTest
  static void testCreateCashFlowSeries_Validations() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      Id categoryId = [SELECT Id FROM AXF_OBJ_Category__c LIMIT 1].Id;
      Id bankId = bankAccount('ACC_TEST_001').Id;
      Id cardId = creditCard('CARD_TEST_001').Id;
      Map<String, AXF_CLS_CTRL_QuickFlowActions.CashFlowCreationDTO> cases = new Map<String, AXF_CLS_CTRL_QuickFlowActions.CashFlowCreationDTO>();

      AXF_CLS_CTRL_QuickFlowActions.CashFlowCreationDTO dto = validDto();
      dto.description = ' ';
      cases.put(
        'Description, Due Date, and a positive amount are required.',
        dto
      );

      dto = validDto();
      dto.type = 'OUTRO';
      cases.put('Select a valid entry type.', dto);

      dto = validDto();
      dto.paymentMode = 'FINANCIAMENTO';
      dto.financingType = 'PRICE';
      dto.totalInstallments = 121;
      cases.put('Total Installments must be between 1 and 120.', dto);

      dto = validDto();
      dto.accountId = categoryId;
      cases.put('Account is required.', dto);

      dto = validDto();
      dto.categoryId = 'not-an-id';
      cases.put('Invalid Category.', dto);

      dto = validDto();
      dto.paymentMethod = null;
      cases.put('Select a valid Payment Method.', dto);

      dto = validDto();
      dto.paymentMethod = 'DEBITO_CONTA';
      cases.put('Select one Bank Account for the chosen Payment Method.', dto);

      dto = validDto();
      dto.paymentMethod = 'CARTAO_CREDITO';
      dto.bankAccountId = bankId;
      cases.put('Select one Credit Card for the chosen Payment Method.', dto);

      dto = validDto();
      dto.creditCardId = cardId;
      cases.put(
        'Bank Account and Credit Card are not applicable to the chosen Payment Method.',
        dto
      );

      dto = validDto();
      dto.totalInstallments = 2;
      cases.put('A single payment cannot have multiple installments.', dto);

      dto = validDto();
      dto.paymentMode = 'RECORRENTE';
      dto.recurringType = 'FIXO';
      cases.put(
        'Recurring Type and Provisioning Strategy are required for recurring entries.',
        dto
      );

      dto = validDto();
      dto.paymentMode = 'RECORRENTE';
      dto.recurringType = 'MENSAL';
      dto.provisioningStrategy = 'VALOR_BASE';
      cases.put('Select valid recurring configuration values.', dto);

      dto = validDto();
      dto.recurringType = 'FIXO';
      cases.put(
        'Recurring fields are not applicable to the selected modality.',
        dto
      );

      dto = validDto();
      dto.paymentMode = 'FINANCIAMENTO';
      dto.totalInstallments = 12;
      cases.put('Financing Type is required for financing entries.', dto);

      dto = validDto();
      dto.paymentMode = 'FINANCIAMENTO';
      dto.financingType = 'GERMAN';
      dto.totalInstallments = 12;
      cases.put('Select a valid Financing Type.', dto);

      dto = validDto();
      dto.paymentMode = 'FINANCIAMENTO_SAC';
      dto.financingType = 'PRICE';
      dto.totalInstallments = 12;
      cases.put('SAC financing requires the SAC Financing Type.', dto);

      dto = validDto();
      dto.monthlyAdjustmentRate = 1;
      cases.put(
        'Financing fields are not applicable to the selected modality.',
        dto
      );

      dto = validDto();
      dto.paymentMode = 'CONSORCIO';
      dto.totalInstallments = 12;
      cases.put(
        'Adjustment Anniversary is required only for consortium entries.',
        dto
      );

      dto = validDto();
      dto.paymentMethod = 'DEBITO_CONTA';
      dto.bankAccountId = bankAccount('ACC_OTHER_001').Id;
      cases.put(
        'The selected Bank Account does not belong to the Account holder.',
        dto
      );

      dto = validDto();
      dto.paymentMethod = 'CARTAO_CREDITO';
      dto.creditCardId = creditCard('CARD_OTHER_001').Id;
      cases.put(
        'The selected Credit Card does not belong to the Account holder.',
        dto
      );

      dto = validDto();
      dto.isPaid = true;
      cases.put(
        'Paid Value and Payment Date are required for a paid entry.',
        dto
      );

      dto = validDto();
      dto.paidValue = 10;
      cases.put('Settlement fields are not applicable to an open entry.', dto);

      dto = validDto();
      dto.firstDueDate = Date.today().addDays(-1);
      cases.put(
        'Confirm the creation of the past-due entry before saving.',
        dto
      );

      dto = validDto();
      dto.description = 'X'.repeat(120);
      cases.put('Unable to save the cash-flow entry.', dto);

      Test.startTest();
      String nullPayload = errorFor(null);
      AXF_CLS_CTRL_QuickFlowActions.CashFlowCreationDTO noAccount = validDto();
      noAccount.accountId = null;
      String missingAccount = errorFor(noAccount);
      Map<String, String> actual = new Map<String, String>();
      for (String expected : cases.keySet()) {
        actual.put(expected, errorFor(cases.get(expected)));
      }
      Test.stopTest();

      Assert.areEqual('Invalid input payload.', nullPayload);
      Assert.areEqual('Account is required.', missingAccount);
      for (String expected : cases.keySet()) {
        Assert.areEqual(
          expected,
          actual.get(expected),
          'Unexpected validation result'
        );
      }
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM AXF_OBJ_CashFlow__c],
        'No entry is saved on validation errors'
      );
    }
  }

  @IsTest
  static void testRecentFinancialOptions() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      Id accountId = household().Id;

      Test.startTest();
      List<AXF_CLS_CTRL_QuickFlowActions.FinancialOptionDTO> banks = AXF_CLS_CTRL_QuickFlowActions.getRecentBankAccounts(
        accountId
      );
      List<AXF_CLS_CTRL_QuickFlowActions.FinancialOptionDTO> cards = AXF_CLS_CTRL_QuickFlowActions.getRecentCreditCards(
        accountId
      );
      String missingAccount;
      try {
        AXF_CLS_CTRL_QuickFlowActions.getRecentBankAccounts(null);
      } catch (AuraHandledException e) {
        missingAccount = e.getMessage();
      }
      Test.stopTest();

      Assert.areEqual(1, banks.size());
      Assert.areEqual(bankAccount('ACC_TEST_001').Id, banks[0].id);
      Assert.isNotNull(banks[0].displayLabel);
      Assert.areEqual(1, cards.size());
      Assert.areEqual(creditCard('CARD_TEST_001').Id, cards[0].id);
      Assert.areEqual('Account is required.', missingAccount);
    }
  }
}
