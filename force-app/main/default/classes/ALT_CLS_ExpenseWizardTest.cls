@IsTest
private class ALT_CLS_ExpenseWizardTest {
  private static Account holder(String name) {
    Account account = new Account(Name = name);
    insert account;
    return account;
  }

  private static ALT_CLS_ExpenseWizard.Request request(Id holderId) {
    ALT_CLS_ExpenseWizard.Request request = new ALT_CLS_ExpenseWizard.Request();
    request.holderId = holderId;
    request.description = 'Conta de luz';
    request.amount = 180;
    request.dueDate = Date.newInstance(2026, 10, 20);
    request.status = 'Pending';
    return request;
  }

  private static void assertRejected(
    ALT_CLS_ExpenseWizard.Request request,
    String expected
  ) {
    try {
      AXF_CLS_CTRL_ExpenseWizard.createStandalone(JSON.serialize(request));
      System.assert(false, 'expected AuraHandledException');
    } catch (AuraHandledException e) {
      System.assertEquals(expected, e.getMessage());
    }
  }

  @IsTest
  static void createsOnePendingExpense() {
    Account h = holder('Titular');
    AXF_OBJ_BankAccount__c account = new AXF_OBJ_BankAccount__c(
      Name = 'Conta',
      AXF_BA_MD_Holder__c = h.Id,
      AXF_BA_PKL_Institution__c = '341',
      AXF_BA_PKL_Type__c = 'Checking'
    );
    insert account;
    ALT_CLS_ExpenseWizard.Request request = request(h.Id);
    request.accountId = account.Id;
    request.paymentDate = Date.newInstance(2026, 10, 1);

    Id id = AXF_CLS_CTRL_ExpenseWizard.createStandalone(
      JSON.serialize(request)
    );

    AXF_OBJ_Entry__c entry = [
      SELECT
        Name,
        AXF_ENT_PKL_Type__c,
        AXF_ENT_PKL_Status__c,
        AXF_ENT_CUR_Amount__c,
        AXF_ENT_LKP_BankAccount__c,
        AXF_ENT_DAT_PaymentDate__c,
        AXF_ENT_LKP_Contract__c
      FROM AXF_OBJ_Entry__c
      WHERE Id = :id
    ];
    System.assertEquals(1, [SELECT COUNT() FROM AXF_OBJ_Entry__c]);
    System.assertEquals('Conta de luz', entry.Name);
    System.assertEquals('Expense', entry.AXF_ENT_PKL_Type__c);
    System.assertEquals('Pending', entry.AXF_ENT_PKL_Status__c);
    System.assertEquals(180, entry.AXF_ENT_CUR_Amount__c);
    System.assertEquals(account.Id, entry.AXF_ENT_LKP_BankAccount__c);
    System.assertEquals(null, entry.AXF_ENT_DAT_PaymentDate__c);
    System.assertEquals(null, entry.AXF_ENT_LKP_Contract__c);
  }

  @IsTest
  static void createsARealizedCashExpenseWithPaymentDate() {
    ALT_CLS_ExpenseWizard.Request request = request(holder('Titular').Id);
    request.status = 'Realized';
    request.paymentDate = Date.newInstance(2026, 10, 5);

    Id id = AXF_CLS_CTRL_ExpenseWizard.createStandalone(
      JSON.serialize(request)
    );

    AXF_OBJ_Entry__c entry = [
      SELECT AXF_ENT_PKL_Status__c, AXF_ENT_DAT_PaymentDate__c
      FROM AXF_OBJ_Entry__c
      WHERE Id = :id
    ];
    System.assertEquals('Realized', entry.AXF_ENT_PKL_Status__c);
    System.assertEquals(
      Date.newInstance(2026, 10, 5),
      entry.AXF_ENT_DAT_PaymentDate__c
    );
  }

  @IsTest
  static void rejectsInvalidRequestsWithoutCreatingAnything() {
    Id holderId = holder('Titular').Id;
    ALT_CLS_ExpenseWizard.Request noHolder = request(holderId);
    noHolder.holderId = null;
    assertRejected(noHolder, 'Informe o titular.');
    ALT_CLS_ExpenseWizard.Request noDescription = request(holderId);
    noDescription.description = ' ';
    assertRejected(noDescription, 'Informe a descrição.');
    ALT_CLS_ExpenseWizard.Request zero = request(holderId);
    zero.amount = 0;
    assertRejected(zero, 'O valor deve ser maior que zero.');
    ALT_CLS_ExpenseWizard.Request noDue = request(holderId);
    noDue.dueDate = null;
    assertRejected(noDue, 'Informe o vencimento.');
    ALT_CLS_ExpenseWizard.Request badStatus = request(holderId);
    badStatus.status = 'Other';
    assertRejected(badStatus, 'Situação inválida.');
    ALT_CLS_ExpenseWizard.Request noPayment = request(holderId);
    noPayment.status = 'Realized';
    assertRejected(noPayment, 'Informe a data de pagamento.');
    System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_Entry__c]);
  }

  @IsTest
  static void rejectsAccountAndCardTogether() {
    Account h = holder('Titular');
    ALT_CLS_ExpenseWizard.Request request = request(h.Id);
    request.accountId = account(h.Id).Id;
    request.cardId = card(h.Id).Id;
    assertRejected(request, 'Escolha a conta ou o cartão, não os dois.');
  }

  @IsTest
  static void rejectsSourcesOfAnotherHolderAndIncomeCategories() {
    Account mine = holder('Meu');
    Account other = holder('Outro');
    ALT_CLS_ExpenseWizard.Request withAccount = request(mine.Id);
    withAccount.accountId = account(other.Id).Id;
    assertRejected(withAccount, 'A conta não pertence ao titular.');
    ALT_CLS_ExpenseWizard.Request withCard = request(mine.Id);
    withCard.cardId = card(other.Id).Id;
    assertRejected(withCard, 'O cartão não pertence ao titular.');
    AXF_OBJ_Category__c income = new AXF_OBJ_Category__c(
      Name = 'Salário',
      AXF_CAT_PKL_Type__c = 'Income'
    );
    insert income;
    ALT_CLS_ExpenseWizard.Request withCategory = request(mine.Id);
    withCategory.categoryId = income.Id;
    assertRejected(withCategory, 'A categoria não é de despesa.');
    System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_Entry__c]);
  }

  private static AXF_OBJ_BankAccount__c account(Id holderId) {
    AXF_OBJ_BankAccount__c account = new AXF_OBJ_BankAccount__c(
      Name = 'Conta',
      AXF_BA_MD_Holder__c = holderId,
      AXF_BA_PKL_Institution__c = '341',
      AXF_BA_PKL_Type__c = 'Checking'
    );
    insert account;
    return account;
  }

  private static AXF_OBJ_CreditCard__c card(Id holderId) {
    AXF_OBJ_CreditCard__c card = new AXF_OBJ_CreditCard__c(
      Name = 'Cartão',
      AXF_CC_MD_Holder__c = holderId,
      AXF_CC_PKL_Institution__c = '341'
    );
    insert card;
    return card;
  }

  private static ALT_CLS_ExpenseWizard.RecurringRequest recurring(Id holderId) {
    ALT_CLS_ExpenseWizard.RecurringRequest recurring = new ALT_CLS_ExpenseWizard.RecurringRequest();
    recurring.base = request(holderId);
    recurring.base.amount = 2500;
    recurring.base.description = 'Aluguel';
    recurring.base.dueDate = Date.today().addDays(3);
    return recurring;
  }

  private static void assertRecurringRejected(
    ALT_CLS_ExpenseWizard.RecurringRequest request,
    String expected
  ) {
    try {
      AXF_CLS_CTRL_ExpenseWizard.createRecurring(JSON.serialize(request));
      System.assert(false, 'expected AuraHandledException');
    } catch (AuraHandledException e) {
      System.assertEquals(expected, e.getMessage());
    }
  }

  @IsTest
  static void createsTheRecurringContractWithPendingEntries() {
    Account h = holder('Titular');
    ALT_CLS_ExpenseWizard.RecurringRequest recurring = recurring(h.Id);
    recurring.variableAmount = true;
    recurring.base.accountId = account(h.Id).Id;

    Id id = AXF_CLS_CTRL_ExpenseWizard.createRecurring(
      JSON.serialize(recurring)
    );

    AXF_OBJ_Contract__c contract = [
      SELECT
        RecordType.DeveloperName,
        AXF_CTR_PKL_Direction__c,
        AXF_CTR_PKL_Status__c,
        AXF_CTR_BOL_VariableAmount__c,
        AXF_CTR_NUM_DueDay__c
      FROM AXF_OBJ_Contract__c
      WHERE Id = :id
    ];
    System.assertEquals('AXF_Recurring', contract.RecordType.DeveloperName);
    System.assertEquals('Expense', contract.AXF_CTR_PKL_Direction__c);
    System.assertEquals('Active', contract.AXF_CTR_PKL_Status__c);
    System.assertEquals(true, contract.AXF_CTR_BOL_VariableAmount__c);
    System.assertEquals(
      recurring.base.dueDate.day(),
      contract.AXF_CTR_NUM_DueDay__c
    );
    List<AXF_OBJ_Entry__c> entries = [
      SELECT
        AXF_ENT_PKL_Status__c,
        AXF_ENT_PKL_Type__c,
        AXF_ENT_LKP_BankAccount__c
      FROM AXF_OBJ_Entry__c
      WHERE AXF_ENT_LKP_Contract__c = :id
    ];
    System.assert(entries.size() >= 12, 'expected about 12 months of entries');
    for (AXF_OBJ_Entry__c entry : entries) {
      System.assertEquals('Pending', entry.AXF_ENT_PKL_Status__c);
      System.assertEquals('Expense', entry.AXF_ENT_PKL_Type__c);
      System.assertEquals(
        recurring.base.accountId,
        entry.AXF_ENT_LKP_BankAccount__c
      );
    }
  }

  @IsTest
  static void endDateLimitsTheEntriesAndFixedAmountIsNotVariable() {
    ALT_CLS_ExpenseWizard.RecurringRequest recurring = recurring(
      holder('Titular').Id
    );
    recurring.base.dueDate = Date.today().addDays(1);
    recurring.endDate = Date.today().addDays(1).addMonths(2);

    Id id = AXF_CLS_CTRL_ExpenseWizard.createRecurring(
      JSON.serialize(recurring)
    );

    System.assertEquals(
      3,
      [SELECT COUNT() FROM AXF_OBJ_Entry__c WHERE AXF_ENT_LKP_Contract__c = :id]
    );
    System.assertEquals(
      false,
      [
        SELECT AXF_CTR_BOL_VariableAmount__c
        FROM AXF_OBJ_Contract__c
        WHERE Id = :id
      ]
      .AXF_CTR_BOL_VariableAmount__c
    );
  }

  @IsTest
  static void previewListsTheDatesTheContractWouldGenerate() {
    ALT_CLS_ExpenseWizard.RecurringRequest recurring = recurring(
      holder('Titular').Id
    );
    recurring.base.dueDate = Date.today().addDays(1);
    recurring.endDate = Date.today().addDays(1).addMonths(1);

    List<ALT_CLS_ExpenseWizard.PreviewItem> items = AXF_CLS_CTRL_ExpenseWizard.previewRecurring(
      JSON.serialize(recurring)
    );

    System.assertEquals(2, items.size());
    System.assertEquals(2500, items[0].amount);
    System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_Contract__c]);
  }

  private static ALT_CLS_ExpenseWizard.InstallmentRequest installment(
    Id holderId
  ) {
    ALT_CLS_ExpenseWizard.InstallmentRequest installment = new ALT_CLS_ExpenseWizard.InstallmentRequest();
    installment.base = request(holderId);
    installment.base.description = 'Geladeira';
    installment.base.amount = 1000;
    installment.base.dueDate = Date.today().addDays(5);
    installment.count = 3;
    return installment;
  }

  private static void assertInstallmentRejected(
    ALT_CLS_ExpenseWizard.InstallmentRequest request,
    String expected
  ) {
    try {
      AXF_CLS_CTRL_ExpenseWizard.createInstallment(JSON.serialize(request));
      System.assert(false, 'expected AuraHandledException');
    } catch (AuraHandledException e) {
      System.assertEquals(expected, e.getMessage());
    }
  }

  @IsTest
  static void totalIsSplitAndTheLastInstallmentAbsorbsTheResidue() {
    Account h = holder('Titular');
    ALT_CLS_ExpenseWizard.InstallmentRequest installment = installment(h.Id);
    installment.base.cardId = card(h.Id).Id;
    AXF_OBJ_Category__c category = new AXF_OBJ_Category__c(
      Name = 'Casa',
      AXF_CAT_PKL_Type__c = 'Expense'
    );
    insert category;
    installment.base.categoryId = category.Id;

    List<ALT_CLS_ExpenseWizard.PreviewItem> preview = AXF_CLS_CTRL_ExpenseWizard.previewInstallment(
      JSON.serialize(installment)
    );
    System.assertEquals(333.34, preview[2].amount);
    Id id = AXF_CLS_CTRL_ExpenseWizard.createInstallment(
      JSON.serialize(installment)
    );

    AXF_OBJ_Contract__c contract = [
      SELECT
        RecordType.DeveloperName,
        AXF_CTR_CUR_Amount__c,
        AXF_CTR_LKP_CreditCard__c,
        AXF_CTR_LKP_Category__c,
        AXF_CTR_PKL_Direction__c
      FROM AXF_OBJ_Contract__c
      WHERE Id = :id
    ];
    System.assertEquals(
      installment.base.cardId,
      contract.AXF_CTR_LKP_CreditCard__c
    );
    System.assertEquals(category.Id, contract.AXF_CTR_LKP_Category__c);
    System.assertEquals('Expense', contract.AXF_CTR_PKL_Direction__c);
    System.assertEquals('AXF_Installment', contract.RecordType.DeveloperName);
    System.assertEquals(333.33, contract.AXF_CTR_CUR_Amount__c);
    List<AXF_OBJ_Entry__c> entries = [
      SELECT
        AXF_ENT_CUR_Amount__c,
        AXF_ENT_NUM_InstallmentNumber__c,
        AXF_ENT_PKL_Status__c,
        AXF_ENT_LKP_CreditCard__c
      FROM AXF_OBJ_Entry__c
      WHERE AXF_ENT_LKP_Contract__c = :id
      ORDER BY AXF_ENT_NUM_InstallmentNumber__c
    ];
    System.assertEquals(3, entries.size());
    System.assertEquals(333.33, entries[0].AXF_ENT_CUR_Amount__c);
    System.assertEquals(333.34, entries[2].AXF_ENT_CUR_Amount__c);
    Decimal sum = 0;
    for (AXF_OBJ_Entry__c entry : entries) {
      sum += entry.AXF_ENT_CUR_Amount__c;
      System.assertEquals('Pending', entry.AXF_ENT_PKL_Status__c);
      System.assertEquals(
        installment.base.cardId,
        entry.AXF_ENT_LKP_CreditCard__c
      );
    }
    System.assertEquals(1000, sum);
  }

  @IsTest
  static void aRoundedUpInstallmentGivesTheNegativeResidueToTheLastOne() {
    ALT_CLS_ExpenseWizard.InstallmentRequest installment = installment(
      holder('Titular').Id
    );
    installment.base.amount = 100;
    installment.count = 6;

    Id id = AXF_CLS_CTRL_ExpenseWizard.createInstallment(
      JSON.serialize(installment)
    );

    List<AXF_OBJ_Entry__c> entries = [
      SELECT AXF_ENT_CUR_Amount__c
      FROM AXF_OBJ_Entry__c
      WHERE AXF_ENT_LKP_Contract__c = :id
      ORDER BY AXF_ENT_NUM_InstallmentNumber__c
    ];
    System.assertEquals(16.67, entries[0].AXF_ENT_CUR_Amount__c);
    System.assertEquals(16.65, entries[5].AXF_ENT_CUR_Amount__c);
    Decimal sum = 0;
    for (AXF_OBJ_Entry__c entry : entries) {
      sum += entry.AXF_ENT_CUR_Amount__c;
    }
    System.assertEquals(100, sum);
  }

  @IsTest
  static void installmentValueMultipliesByTheCount() {
    ALT_CLS_ExpenseWizard.InstallmentRequest installment = installment(
      holder('Titular').Id
    );
    installment.amountIsTotal = false;
    installment.base.amount = 300;
    installment.count = 10;

    List<ALT_CLS_ExpenseWizard.PreviewItem> items = AXF_CLS_CTRL_ExpenseWizard.previewInstallment(
      JSON.serialize(installment)
    );
    Id id = AXF_CLS_CTRL_ExpenseWizard.createInstallment(
      JSON.serialize(installment)
    );

    System.assertEquals(10, items.size());
    System.assertEquals(300, items[9].amount);
    System.assertEquals(
      3000,
      (Decimal) [
          SELECT SUM(AXF_ENT_CUR_Amount__c) total
          FROM AXF_OBJ_Entry__c
          WHERE AXF_ENT_LKP_Contract__c = :id
        ][0]
        .get('total')
    );
  }

  @IsTest
  static void rejectsInvalidInstallmentRequestsWithoutCreatingAnything() {
    Account mine = holder('Meu');
    Account other = holder('Outro');
    ALT_CLS_ExpenseWizard.InstallmentRequest one = installment(mine.Id);
    one.count = 1;
    assertInstallmentRejected(one, 'O número de parcelas deve ser de 2 a 120.');
    ALT_CLS_ExpenseWizard.InstallmentRequest many = installment(mine.Id);
    many.count = 121;
    assertInstallmentRejected(
      many,
      'O número de parcelas deve ser de 2 a 120.'
    );
    ALT_CLS_ExpenseWizard.InstallmentRequest zero = installment(mine.Id);
    zero.base.amount = 0;
    assertInstallmentRejected(zero, 'O valor deve ser maior que zero.');
    ALT_CLS_ExpenseWizard.InstallmentRequest tiny = installment(mine.Id);
    tiny.base.amount = 0.01;
    assertInstallmentRejected(
      tiny,
      'O valor da parcela deve ser maior que zero.'
    );
    ALT_CLS_ExpenseWizard.InstallmentRequest small = installment(mine.Id);
    small.base.amount = 1;
    small.count = 120;
    assertInstallmentRejected(
      small,
      'O valor total é pequeno demais para este número de parcelas.'
    );
    ALT_CLS_ExpenseWizard.InstallmentRequest foreignAccount = installment(
      mine.Id
    );
    foreignAccount.base.accountId = account(other.Id).Id;
    assertInstallmentRejected(
      foreignAccount,
      'A conta não pertence ao titular.'
    );
    ALT_CLS_ExpenseWizard.InstallmentRequest noDue = installment(mine.Id);
    noDue.base.dueDate = null;
    assertInstallmentRejected(noDue, 'Informe o primeiro vencimento.');
    ALT_CLS_ExpenseWizard.InstallmentRequest foreign = installment(mine.Id);
    foreign.base.cardId = card(other.Id).Id;
    assertInstallmentRejected(foreign, 'O cartão não pertence ao titular.');
    ALT_CLS_ExpenseWizard.InstallmentRequest both = installment(mine.Id);
    both.base.accountId = account(mine.Id).Id;
    both.base.cardId = card(mine.Id).Id;
    assertInstallmentRejected(
      both,
      'Escolha a conta ou o cartão, não os dois.'
    );
    System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_Contract__c]);
    System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_Entry__c]);
  }

  @IsTest
  static void aContractThatWouldGenerateNoEntriesIsRolledBack() {
    ALT_CLS_ExpenseWizard.RecurringRequest recurring = recurring(
      holder('Titular').Id
    );
    // Beyond the 12 months horizon: the schedule is empty.
    recurring.base.dueDate = Date.today().addMonths(24);

    assertRecurringRejected(
      recurring,
      'Nenhum lançamento seria gerado para este período.'
    );
    System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_Contract__c]);
    System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_Entry__c]);
    try {
      AXF_CLS_CTRL_ExpenseWizard.previewRecurring(JSON.serialize(recurring));
      System.assert(false, 'expected AuraHandledException');
    } catch (AuraHandledException e) {
      System.assertEquals(
        'Nenhum lançamento seria gerado para este período.',
        e.getMessage()
      );
    }
  }

  @IsTest
  static void rejectsInvalidRecurringRequestsWithoutCreatingAnything() {
    Account mine = holder('Meu');
    Account other = holder('Outro');
    ALT_CLS_ExpenseWizard.RecurringRequest badDay = recurring(mine.Id);
    badDay.dueDay = 32;
    assertRecurringRejected(badDay, 'O dia do vencimento deve ser de 1 a 31.');
    ALT_CLS_ExpenseWizard.RecurringRequest badEnd = recurring(mine.Id);
    badEnd.endDate = badEnd.base.dueDate.addDays(-1);
    assertRecurringRejected(
      badEnd,
      'A data de fim não pode ser anterior ao primeiro vencimento.'
    );
    ALT_CLS_ExpenseWizard.RecurringRequest zero = recurring(mine.Id);
    zero.base.amount = 0;
    assertRecurringRejected(zero, 'O valor deve ser maior que zero.');
    ALT_CLS_ExpenseWizard.RecurringRequest noDue = recurring(mine.Id);
    noDue.base.dueDate = null;
    assertRecurringRejected(noDue, 'Informe o primeiro vencimento.');
    ALT_CLS_ExpenseWizard.RecurringRequest foreign = recurring(mine.Id);
    foreign.base.accountId = account(other.Id).Id;
    assertRecurringRejected(foreign, 'A conta não pertence ao titular.');
    ALT_CLS_ExpenseWizard.RecurringRequest foreignCard = recurring(mine.Id);
    foreignCard.base.cardId = card(other.Id).Id;
    assertRecurringRejected(foreignCard, 'O cartão não pertence ao titular.');
    ALT_CLS_ExpenseWizard.RecurringRequest both = recurring(mine.Id);
    both.base.accountId = account(mine.Id).Id;
    both.base.cardId = card(mine.Id).Id;
    assertRecurringRejected(both, 'Escolha a conta ou o cartão, não os dois.');
    ALT_CLS_ExpenseWizard.RecurringRequest noHolder = recurring(mine.Id);
    noHolder.base.holderId = null;
    assertRecurringRejected(noHolder, 'Informe o titular.');
    ALT_CLS_ExpenseWizard.RecurringRequest noDescription = recurring(mine.Id);
    noDescription.base.description = ' ';
    assertRecurringRejected(noDescription, 'Informe a descrição.');
    System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_Contract__c]);
    System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_Entry__c]);
  }

  @IsTest
  static void optionsListExpenseCategoriesAndOnlyTheHolderSources() {
    Account mine = holder('Meu');
    Account other = holder('Outro');
    insert new List<AXF_OBJ_Category__c>{
      new AXF_OBJ_Category__c(
        Name = 'Moradia',
        AXF_CAT_PKL_Type__c = 'Expense'
      ),
      new AXF_OBJ_Category__c(Name = 'Geral', AXF_CAT_PKL_Type__c = 'Both'),
      new AXF_OBJ_Category__c(Name = 'Salário', AXF_CAT_PKL_Type__c = 'Income')
    };
    insert new List<AXF_OBJ_BankAccount__c>{
      new AXF_OBJ_BankAccount__c(
        Name = 'Minha conta',
        AXF_BA_MD_Holder__c = mine.Id,
        AXF_BA_PKL_Institution__c = '341',
        AXF_BA_PKL_Type__c = 'Checking'
      ),
      new AXF_OBJ_BankAccount__c(
        Name = 'Conta alheia',
        AXF_BA_MD_Holder__c = other.Id,
        AXF_BA_PKL_Institution__c = '341',
        AXF_BA_PKL_Type__c = 'Checking'
      )
    };
    insert new AXF_OBJ_CreditCard__c(
      Name = 'Meu cartão',
      AXF_CC_MD_Holder__c = mine.Id,
      AXF_CC_PKL_Institution__c = '341'
    );

    ALT_CLS_ExpenseWizard.Options options = AXF_CLS_CTRL_ExpenseWizard.getOptions(
      mine.Id
    );

    System.assertEquals(2, options.categories.size());
    System.assertEquals('Geral', options.categories[0].label);
    System.assertEquals(1, options.accounts.size());
    System.assertEquals('Minha conta', options.accounts[0].label);
    System.assertEquals(1, options.cards.size());
    System.assertEquals(
      0,
      AXF_CLS_CTRL_ExpenseWizard.getOptions(null).accounts.size()
    );
  }

  @IsTest
  static void userWithoutPermissionGetsAReadableError() {
    User user = new User(
      Alias = 'axfexpw',
      Email = 'axfexpw@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'NoExpenseWizard',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = ALT_CLS_ConnectionTestUser.standardProfileId(),
      TimeZoneSidKey = 'America/Sao_Paulo',
      Username = 'axfexpw' + System.currentTimeMillis() + '@example.com'
    );
    insert user;
    Id holderId = holder('Titular').Id;
    System.runAs(user) {
      try {
        AXF_CLS_CTRL_ExpenseWizard.createStandalone(
          JSON.serialize(request(holderId))
        );
        System.assert(false, 'expected AuraHandledException');
      } catch (AuraHandledException e) {
        System.assertNotEquals(null, e.getMessage());
      }
    }
    System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_Entry__c]);
  }
}
