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
  static void aCardPaidRecurringExpenseKeepsTheCardOnTheContractAndEntries() {
    Account h = holder('Titular');
    ALT_CLS_ExpenseWizard.RecurringRequest recurring = recurring(h.Id);
    recurring.base.cardId = card(h.Id).Id;

    Id id = AXF_CLS_CTRL_ExpenseWizard.createRecurring(
      JSON.serialize(recurring)
    );

    System.assertEquals(
      recurring.base.cardId,
      [SELECT AXF_CTR_LKP_CreditCard__c FROM AXF_OBJ_Contract__c WHERE Id = :id]
      .AXF_CTR_LKP_CreditCard__c
    );
    for (AXF_OBJ_Entry__c entry : [
      SELECT AXF_ENT_LKP_CreditCard__c, AXF_ENT_LKP_BankAccount__c
      FROM AXF_OBJ_Entry__c
      WHERE AXF_ENT_LKP_Contract__c = :id
    ]) {
      System.assertEquals(
        recurring.base.cardId,
        entry.AXF_ENT_LKP_CreditCard__c
      );
      System.assertEquals(null, entry.AXF_ENT_LKP_BankAccount__c);
    }
  }

  @IsTest
  static void anExplicitDueDayIsKeptAndUsedByTheEntries() {
    ALT_CLS_ExpenseWizard.RecurringRequest recurring = recurring(
      holder('Titular').Id
    );
    Date start = Date.today().toStartOfMonth().addMonths(1);
    recurring.base.dueDate = start.addDays(2);
    recurring.dueDay = 28;
    recurring.endDate = start.addMonths(3);

    List<ALT_CLS_ExpenseWizard.PreviewItem> preview = AXF_CLS_CTRL_ExpenseWizard.previewRecurring(
      JSON.serialize(recurring)
    );
    Id id = AXF_CLS_CTRL_ExpenseWizard.createRecurring(
      JSON.serialize(recurring)
    );

    System.assertEquals(
      28,
      [SELECT AXF_CTR_NUM_DueDay__c FROM AXF_OBJ_Contract__c WHERE Id = :id]
      .AXF_CTR_NUM_DueDay__c
    );
    List<AXF_OBJ_Entry__c> entries = [
      SELECT AXF_ENT_DAT_DueDate__c
      FROM AXF_OBJ_Entry__c
      WHERE AXF_ENT_LKP_Contract__c = :id
      ORDER BY AXF_ENT_DAT_DueDate__c
    ];
    System.assertEquals(preview.size(), entries.size());
    for (Integer i = 0; i < entries.size(); i++) {
      System.assertEquals(
        preview[i].dueDate,
        entries[i].AXF_ENT_DAT_DueDate__c
      );
      System.assertEquals(28, entries[i].AXF_ENT_DAT_DueDate__c.day());
    }
  }

  @IsTest
  static void anOpenEndedRecurringExpenseGeneratesTwelveMonthsAhead() {
    ALT_CLS_ExpenseWizard.RecurringRequest recurring = recurring(
      holder('Titular').Id
    );
    recurring.base.dueDate = Date.today().addDays(1);
    recurring.dueDay = recurring.base.dueDate.day();

    Id id = AXF_CLS_CTRL_ExpenseWizard.createRecurring(
      JSON.serialize(recurring)
    );

    List<AXF_OBJ_Entry__c> entries = [
      SELECT AXF_ENT_DAT_DueDate__c
      FROM AXF_OBJ_Entry__c
      WHERE AXF_ENT_LKP_Contract__c = :id
    ];
    Date horizon = Date.today().addMonths(12);
    for (AXF_OBJ_Entry__c entry : entries) {
      System.assert(
        entry.AXF_ENT_DAT_DueDate__c <= horizon,
        'no entry beyond the 12 months horizon'
      );
    }
    System.assert(
      entries.size() >= 12 && entries.size() <= 13,
      'about 12 months of entries, got ' + entries.size()
    );
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
  static void persistedDueDatesMatchThePreviewEvenFromTheEndOfTheMonth() {
    Account h = holder('Titular');
    ALT_CLS_ExpenseWizard.InstallmentRequest installment = installment(h.Id);
    installment.base.dueDate = Date.today()
      .toStartOfMonth()
      .addMonths(1)
      .addDays(30);
    installment.base.accountId = account(h.Id).Id;
    installment.count = 4;

    List<ALT_CLS_ExpenseWizard.PreviewItem> preview = AXF_CLS_CTRL_ExpenseWizard.previewInstallment(
      JSON.serialize(installment)
    );
    Id id = AXF_CLS_CTRL_ExpenseWizard.createInstallment(
      JSON.serialize(installment)
    );

    List<AXF_OBJ_Entry__c> entries = [
      SELECT AXF_ENT_DAT_DueDate__c, AXF_ENT_LKP_BankAccount__c
      FROM AXF_OBJ_Entry__c
      WHERE AXF_ENT_LKP_Contract__c = :id
      ORDER BY AXF_ENT_NUM_InstallmentNumber__c
    ];
    System.assertEquals(4, entries.size());
    for (Integer i = 0; i < entries.size(); i++) {
      System.assertEquals(
        preview[i].dueDate,
        entries[i].AXF_ENT_DAT_DueDate__c
      );
      System.assertEquals(
        installment.base.accountId,
        entries[i].AXF_ENT_LKP_BankAccount__c
      );
    }
    System.assertEquals(
      installment.base.accountId,
      [
        SELECT AXF_CTR_LKP_BankAccount__c
        FROM AXF_OBJ_Contract__c
        WHERE Id = :id
      ]
      .AXF_CTR_LKP_BankAccount__c
    );
  }

  @IsTest
  static void theLimitsOfTheInstallmentCountAreAccepted() {
    for (Integer count : new List<Integer>{ 2, 120 }) {
      ALT_CLS_ExpenseWizard.InstallmentRequest installment = installment(
        holder('Titular ' + count).Id
      );
      installment.base.amount = 1200;
      installment.count = count;

      Id id = AXF_CLS_CTRL_ExpenseWizard.createInstallment(
        JSON.serialize(installment)
      );

      System.assertEquals(
        count,
        [
          SELECT COUNT()
          FROM AXF_OBJ_Entry__c
          WHERE AXF_ENT_LKP_Contract__c = :id
        ]
      );
    }
  }

  @IsTest
  static void anInstallmentValueWithManyDecimalsIsRoundedOnceAndAddsUp() {
    ALT_CLS_ExpenseWizard.InstallmentRequest installment = installment(
      holder('Titular').Id
    );
    installment.amountIsTotal = false;
    installment.base.amount = 300.005;
    installment.count = 10;

    List<ALT_CLS_ExpenseWizard.PreviewItem> preview = AXF_CLS_CTRL_ExpenseWizard.previewInstallment(
      JSON.serialize(installment)
    );

    Decimal sum = 0;
    for (ALT_CLS_ExpenseWizard.PreviewItem item : preview) {
      System.assertEquals(300.01, item.amount);
      sum += item.amount;
    }
    System.assertEquals(3000.10, sum);
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
    ALT_CLS_ExpenseWizard.InstallmentRequest huge = installment(mine.Id);
    huge.base.amount = 1000000000000000.00;
    assertInstallmentRejected(huge, 'O valor total está acima do limite.');
    ALT_CLS_ExpenseWizard.InstallmentRequest noHolder = installment(mine.Id);
    noHolder.base.holderId = null;
    assertInstallmentRejected(noHolder, 'Informe o titular.');
    ALT_CLS_ExpenseWizard.InstallmentRequest noDescription = installment(
      mine.Id
    );
    noDescription.base.description = ' ';
    assertInstallmentRejected(noDescription, 'Informe a descrição.');
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

  private static ALT_CLS_ExpenseWizard.ConsortiumRequest consortium(
    Id holderId
  ) {
    ALT_CLS_ExpenseWizard.ConsortiumRequest consortium = new ALT_CLS_ExpenseWizard.ConsortiumRequest();
    consortium.base = request(holderId);
    consortium.base.description = 'Consórcio do carro';
    consortium.base.amount = 1200;
    consortium.base.dueDate = Date.today().addDays(10);
    consortium.count = 60;
    consortium.administrator = 'Administradora X';
    return consortium;
  }

  private static void assertConsortiumRejected(
    ALT_CLS_ExpenseWizard.ConsortiumRequest request,
    String expected
  ) {
    try {
      AXF_CLS_CTRL_ExpenseWizard.createConsortium(JSON.serialize(request));
      System.assert(false, 'expected AuraHandledException');
    } catch (AuraHandledException e) {
      System.assertEquals(expected, e.getMessage());
    }
  }

  @IsTest
  static void createsTheConsortiumContractWithEveryInstallment() {
    Account h = holder('Titular');
    ALT_CLS_ExpenseWizard.ConsortiumRequest consortium = consortium(h.Id);
    consortium.awardedOn = Date.today().addMonths(6);
    consortium.base.cardId = card(h.Id).Id;

    List<ALT_CLS_ExpenseWizard.PreviewItem> preview = AXF_CLS_CTRL_ExpenseWizard.previewConsortium(
      JSON.serialize(consortium)
    );
    Id id = AXF_CLS_CTRL_ExpenseWizard.createConsortium(
      JSON.serialize(consortium)
    );

    AXF_OBJ_Contract__c contract = [
      SELECT
        RecordType.DeveloperName,
        AXF_CTR_PKL_Direction__c,
        AXF_CTR_PKL_Status__c,
        AXF_CTR_CUR_Amount__c,
        AXF_CTR_TXT_Counterparty__c,
        AXF_CTR_DAT_AwardedOn__c,
        AXF_CTR_LKP_CreditCard__c
      FROM AXF_OBJ_Contract__c
      WHERE Id = :id
    ];
    System.assertEquals('AXF_Consortium', contract.RecordType.DeveloperName);
    System.assertEquals('Expense', contract.AXF_CTR_PKL_Direction__c);
    System.assertEquals('Active', contract.AXF_CTR_PKL_Status__c);
    System.assertEquals(1200, contract.AXF_CTR_CUR_Amount__c);
    System.assertEquals(
      'Administradora X',
      contract.AXF_CTR_TXT_Counterparty__c
    );
    System.assertEquals(
      consortium.awardedOn,
      contract.AXF_CTR_DAT_AwardedOn__c
    );
    System.assertEquals(
      consortium.base.cardId,
      contract.AXF_CTR_LKP_CreditCard__c
    );
    List<AXF_OBJ_Entry__c> entries = [
      SELECT
        AXF_ENT_CUR_Amount__c,
        AXF_ENT_DAT_DueDate__c,
        AXF_ENT_PKL_Status__c,
        AXF_ENT_LKP_CreditCard__c
      FROM AXF_OBJ_Entry__c
      WHERE AXF_ENT_LKP_Contract__c = :id
      ORDER BY AXF_ENT_NUM_InstallmentNumber__c
    ];
    System.assertEquals(60, entries.size());
    System.assertEquals(60, preview.size());
    for (Integer i = 0; i < entries.size(); i++) {
      System.assertEquals(1200, entries[i].AXF_ENT_CUR_Amount__c);
      System.assertEquals('Pending', entries[i].AXF_ENT_PKL_Status__c);
      System.assertEquals(
        preview[i].dueDate,
        entries[i].AXF_ENT_DAT_DueDate__c
      );
      System.assertEquals(
        consortium.base.cardId,
        entries[i].AXF_ENT_LKP_CreditCard__c
      );
    }
  }

  @IsTest
  static void aConsortiumWithoutAdministratorOrAwardDateIsAccepted() {
    ALT_CLS_ExpenseWizard.ConsortiumRequest consortium = consortium(
      holder('Titular').Id
    );
    consortium.administrator = '  ';
    consortium.count = 2;

    Id id = AXF_CLS_CTRL_ExpenseWizard.createConsortium(
      JSON.serialize(consortium)
    );

    AXF_OBJ_Contract__c contract = [
      SELECT AXF_CTR_TXT_Counterparty__c, AXF_CTR_DAT_AwardedOn__c
      FROM AXF_OBJ_Contract__c
      WHERE Id = :id
    ];
    System.assertEquals(null, contract.AXF_CTR_TXT_Counterparty__c);
    System.assertEquals(null, contract.AXF_CTR_DAT_AwardedOn__c);
    System.assertEquals(
      2,
      [SELECT COUNT() FROM AXF_OBJ_Entry__c WHERE AXF_ENT_LKP_Contract__c = :id]
    );
  }

  @IsTest
  static void anIncompleteGenerationIsRefusedWithItsMessage() {
    ALT_CLS_ContractGeneration.Result complete = new ALT_CLS_ContractGeneration.Result();
    complete.created = 3;
    ALT_CLS_ExpenseWizard.requireComplete(complete, 3);

    ALT_CLS_ContractGeneration.Result shortfall = new ALT_CLS_ContractGeneration.Result();
    shortfall.created = 2;
    try {
      ALT_CLS_ExpenseWizard.requireComplete(shortfall, 3);
      System.assert(false, 'expected ExpenseWizardException');
    } catch (ALT_CLS_ExpenseWizard.ExpenseWizardException e) {
      System.assertEquals(
        'Não foi possível gerar todas as parcelas.',
        e.getMessage()
      );
    }

    ALT_CLS_ContractGeneration.Result failed = new ALT_CLS_ContractGeneration.Result();
    failed.created = 3;
    failed.messages.add('Contrato: informe o valor.');
    try {
      ALT_CLS_ExpenseWizard.requireComplete(failed, 3);
      System.assert(false, 'expected ExpenseWizardException');
    } catch (ALT_CLS_ExpenseWizard.ExpenseWizardException e) {
      System.assertEquals('Contrato: informe o valor.', e.getMessage());
    }
  }

  @IsTest
  static void aConsortiumKeepsTheMonthlyCadenceAndAddsUpToTheTotal() {
    ALT_CLS_ExpenseWizard.ConsortiumRequest consortium = consortium(
      holder('Titular').Id
    );
    consortium.base.dueDate = Date.today()
      .toStartOfMonth()
      .addMonths(1)
      .addDays(14);

    Id id = AXF_CLS_CTRL_ExpenseWizard.createConsortium(
      JSON.serialize(consortium)
    );

    List<AXF_OBJ_Entry__c> entries = [
      SELECT AXF_ENT_DAT_DueDate__c, AXF_ENT_CUR_Amount__c
      FROM AXF_OBJ_Entry__c
      WHERE AXF_ENT_LKP_Contract__c = :id
      ORDER BY AXF_ENT_NUM_InstallmentNumber__c
    ];
    Decimal total = 0;
    for (Integer i = 0; i < entries.size(); i++) {
      System.assertEquals(
        consortium.base.dueDate.addMonths(i),
        entries[i].AXF_ENT_DAT_DueDate__c
      );
      total += entries[i].AXF_ENT_CUR_Amount__c;
    }
    System.assertEquals(72000, total);
  }

  @IsTest
  static void aConsortiumPaidFromABankAccountKeepsTheAccount() {
    Account h = holder('Titular');
    ALT_CLS_ExpenseWizard.ConsortiumRequest consortium = consortium(h.Id);
    consortium.count = 3;
    consortium.base.accountId = account(h.Id).Id;

    Id id = AXF_CLS_CTRL_ExpenseWizard.createConsortium(
      JSON.serialize(consortium)
    );

    System.assertEquals(
      consortium.base.accountId,
      [
        SELECT AXF_CTR_LKP_BankAccount__c
        FROM AXF_OBJ_Contract__c
        WHERE Id = :id
      ]
      .AXF_CTR_LKP_BankAccount__c
    );
    for (AXF_OBJ_Entry__c entry : [
      SELECT AXF_ENT_LKP_BankAccount__c
      FROM AXF_OBJ_Entry__c
      WHERE AXF_ENT_LKP_Contract__c = :id
    ]) {
      System.assertEquals(
        consortium.base.accountId,
        entry.AXF_ENT_LKP_BankAccount__c
      );
    }
  }

  @IsTest
  static void rejectsInvalidConsortiumRequestsWithoutCreatingAnything() {
    Account mine = holder('Meu');
    Account other = holder('Outro');
    ALT_CLS_ExpenseWizard.ConsortiumRequest one = consortium(mine.Id);
    one.count = 1;
    assertConsortiumRejected(one, 'O número de parcelas deve ser de 2 a 240.');
    ALT_CLS_ExpenseWizard.ConsortiumRequest many = consortium(mine.Id);
    many.count = 241;
    assertConsortiumRejected(many, 'O número de parcelas deve ser de 2 a 240.');
    ALT_CLS_ExpenseWizard.ConsortiumRequest zero = consortium(mine.Id);
    zero.base.amount = 0;
    assertConsortiumRejected(zero, 'O valor deve ser maior que zero.');
    ALT_CLS_ExpenseWizard.ConsortiumRequest tiny = consortium(mine.Id);
    tiny.base.amount = 0.001;
    assertConsortiumRejected(
      tiny,
      'O valor da parcela deve ser maior que zero.'
    );
    ALT_CLS_ExpenseWizard.ConsortiumRequest huge = consortium(mine.Id);
    huge.base.amount = 100000000000000.00;
    assertConsortiumRejected(huge, 'O valor total está acima do limite.');
    ALT_CLS_ExpenseWizard.ConsortiumRequest longName = consortium(mine.Id);
    longName.administrator = 'a'.repeat(121);
    assertConsortiumRejected(
      longName,
      'O nome da administradora deve ter até 120 caracteres.'
    );
    ALT_CLS_ExpenseWizard.ConsortiumRequest noDue = consortium(mine.Id);
    noDue.base.dueDate = null;
    assertConsortiumRejected(noDue, 'Informe o primeiro vencimento.');
    ALT_CLS_ExpenseWizard.ConsortiumRequest noHolder = consortium(mine.Id);
    noHolder.base.holderId = null;
    assertConsortiumRejected(noHolder, 'Informe o titular.');
    ALT_CLS_ExpenseWizard.ConsortiumRequest noDescription = consortium(mine.Id);
    noDescription.base.description = ' ';
    assertConsortiumRejected(noDescription, 'Informe a descrição.');
    ALT_CLS_ExpenseWizard.ConsortiumRequest foreign = consortium(mine.Id);
    foreign.base.accountId = account(other.Id).Id;
    assertConsortiumRejected(foreign, 'A conta não pertence ao titular.');
    ALT_CLS_ExpenseWizard.ConsortiumRequest both = consortium(mine.Id);
    both.base.accountId = account(mine.Id).Id;
    both.base.cardId = card(mine.Id).Id;
    assertConsortiumRejected(both, 'Escolha a conta ou o cartão, não os dois.');
    System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_Contract__c]);
    System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_Entry__c]);
  }

  // The charge fields reach the deploy user through a permission set group
  // that is recalculated asynchronously, so a deploy that creates the fields
  // and their FLS together would run these tests before the access exists.
  // A direct assignment takes effect immediately.
  private static void grantFinancingFieldAccess() {
    Id userId = UserInfo.getUserId();
    Id permissionSetId = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'AXF_PS_Usuario'
    ]
    .Id;
    if (
      ![
          SELECT Id
          FROM PermissionSetAssignment
          WHERE AssigneeId = :userId AND PermissionSetId = :permissionSetId
        ]
        .isEmpty()
    ) {
      return;
    }
    System.runAs(new User(Id = userId)) {
      insert new PermissionSetAssignment(
        AssigneeId = userId,
        PermissionSetId = permissionSetId
      );
    }
  }

  private static ALT_CLS_ExpenseWizard.FinancingRequest financing(Id holderId) {
    ALT_CLS_ExpenseWizard.FinancingRequest financing = new ALT_CLS_ExpenseWizard.FinancingRequest();
    financing.base = request(holderId);
    financing.base.description = 'Financiamento do apartamento';
    financing.base.amount = 1200;
    financing.base.dueDate = Date.today().addDays(10);
    financing.count = 12;
    financing.monthlyRate = 1;
    financing.amortizationSystem = 'SAC';
    financing.creditor = 'Banco Y';
    return financing;
  }

  private static void assertFinancingRejected(
    ALT_CLS_ExpenseWizard.FinancingRequest request,
    String expected
  ) {
    try {
      AXF_CLS_CTRL_ExpenseWizard.createFinancing(JSON.serialize(request));
      System.assert(false, 'expected AuraHandledException');
    } catch (AuraHandledException e) {
      System.assertEquals(expected, e.getMessage());
    }
  }

  @IsTest
  static void aSacFinancingMatchesTheReferenceTable() {
    grantFinancingFieldAccess();
    Account h = holder('Titular');
    ALT_CLS_ExpenseWizard.FinancingRequest financing = financing(h.Id);
    financing.base.accountId = account(h.Id).Id;

    List<ALT_CLS_ExpenseWizard.PreviewItem> preview = AXF_CLS_CTRL_ExpenseWizard.previewFinancing(
      JSON.serialize(financing)
    );
    Id id = AXF_CLS_CTRL_ExpenseWizard.createFinancing(
      JSON.serialize(financing)
    );

    // SAC: constant amortization of 100, interest of 1 % on the outstanding balance.
    System.assertEquals(12, preview.size());
    System.assertEquals(112.00, preview[0].amount);
    System.assertEquals(12.00, preview[0].interest);
    System.assertEquals(111.00, preview[1].amount);
    System.assertEquals(11.00, preview[1].interest);
    System.assertEquals(101.00, preview[11].amount);
    System.assertEquals(1.00, preview[11].interest);
    AXF_OBJ_Contract__c contract = [
      SELECT
        RecordType.DeveloperName,
        AXF_CTR_PKL_Direction__c,
        AXF_CTR_PKL_Status__c,
        AXF_CTR_CUR_FinancedAmount__c,
        AXF_CTR_PCT_MonthlyRate__c,
        AXF_CTR_PKL_AmortizationSystem__c,
        AXF_CTR_TXT_Counterparty__c,
        AXF_CTR_LKP_BankAccount__c
      FROM AXF_OBJ_Contract__c
      WHERE Id = :id
    ];
    System.assertEquals('AXF_Financing', contract.RecordType.DeveloperName);
    System.assertEquals('Expense', contract.AXF_CTR_PKL_Direction__c);
    System.assertEquals('Active', contract.AXF_CTR_PKL_Status__c);
    System.assertEquals(1200, contract.AXF_CTR_CUR_FinancedAmount__c);
    System.assertEquals(1, contract.AXF_CTR_PCT_MonthlyRate__c);
    System.assertEquals('SAC', contract.AXF_CTR_PKL_AmortizationSystem__c);
    System.assertEquals('Banco Y', contract.AXF_CTR_TXT_Counterparty__c);
    System.assertEquals(
      financing.base.accountId,
      contract.AXF_CTR_LKP_BankAccount__c
    );
    List<AXF_OBJ_Entry__c> entries = [
      SELECT
        AXF_ENT_CUR_Amount__c,
        AXF_ENT_DAT_DueDate__c,
        AXF_ENT_LKP_BankAccount__c
      FROM AXF_OBJ_Entry__c
      WHERE AXF_ENT_LKP_Contract__c = :id
      ORDER BY AXF_ENT_NUM_InstallmentNumber__c
    ];
    System.assertEquals(12, entries.size());
    Decimal total = 0;
    Decimal interest = 0;
    for (Integer i = 0; i < entries.size(); i++) {
      System.assertEquals(preview[i].amount, entries[i].AXF_ENT_CUR_Amount__c);
      System.assertEquals(
        preview[i].dueDate,
        entries[i].AXF_ENT_DAT_DueDate__c
      );
      System.assertEquals(
        financing.base.accountId,
        entries[i].AXF_ENT_LKP_BankAccount__c
      );
      total += entries[i].AXF_ENT_CUR_Amount__c;
      interest += preview[i].interest;
    }
    System.assertEquals(1278.00, total);
    System.assertEquals(78.00, interest);
  }

  @IsTest
  static void aPriceFinancingHasAConstantInstallmentAndTheInterestAddsUp() {
    grantFinancingFieldAccess();
    ALT_CLS_ExpenseWizard.FinancingRequest financing = financing(
      holder('Titular').Id
    );
    financing.base.amount = 1000;
    financing.amortizationSystem = 'PRICE';

    List<ALT_CLS_ExpenseWizard.PreviewItem> preview = AXF_CLS_CTRL_ExpenseWizard.previewFinancing(
      JSON.serialize(financing)
    );
    Id id = AXF_CLS_CTRL_ExpenseWizard.createFinancing(
      JSON.serialize(financing)
    );

    // PRICE: PMT = 1000 * 0.01 / (1 - 1.01^-12) = 88.85; the first interest is 1 % of 1000.
    System.assertEquals(88.85, preview[0].amount);
    System.assertEquals(88.85, preview[10].amount);
    System.assertEquals(10.00, preview[0].interest);
    Decimal total = 0;
    Decimal interest = 0;
    for (ALT_CLS_ExpenseWizard.PreviewItem item : preview) {
      total += item.amount;
      interest += item.interest;
    }
    // Everything paid minus the principal is the interest; the last installment settles the balance.
    System.assertEquals(total - 1000, interest);
    System.assertEquals(
      total,
      [
          SELECT SUM(AXF_ENT_CUR_Amount__c) total
          FROM AXF_OBJ_Entry__c
          WHERE AXF_ENT_LKP_Contract__c = :id
        ][0]
        .get('total')
    );
  }

  @IsTest
  static void thePreviewAndTheSavedScheduleAgreeForAnUnroundRateAndAmount() {
    grantFinancingFieldAccess();
    for (String kind : new List<String>{ 'PRICE', 'SAC' }) {
      Account h = holder('Titular ' + kind);
      ALT_CLS_ExpenseWizard.FinancingRequest financing = financing(h.Id);
      financing.base.amount = 1234.56;
      financing.monthlyRate = 0.12345;
      financing.count = 7;
      financing.amortizationSystem = kind;

      List<ALT_CLS_ExpenseWizard.PreviewItem> preview = AXF_CLS_CTRL_ExpenseWizard.previewFinancing(
        JSON.serialize(financing)
      );
      Id id = AXF_CLS_CTRL_ExpenseWizard.createFinancing(
        JSON.serialize(financing)
      );

      System.assertEquals(
        0.1235,
        [
          SELECT AXF_CTR_PCT_MonthlyRate__c
          FROM AXF_OBJ_Contract__c
          WHERE Id = :id
        ]
        .AXF_CTR_PCT_MonthlyRate__c
      );
      List<AXF_OBJ_Entry__c> entries = [
        SELECT AXF_ENT_CUR_Amount__c, AXF_ENT_DAT_DueDate__c
        FROM AXF_OBJ_Entry__c
        WHERE AXF_ENT_LKP_Contract__c = :id
        ORDER BY AXF_ENT_NUM_InstallmentNumber__c
      ];
      System.assertEquals(7, entries.size(), kind);
      Decimal paid = 0;
      Decimal interest = 0;
      for (Integer i = 0; i < entries.size(); i++) {
        System.assertEquals(
          preview[i].amount,
          entries[i].AXF_ENT_CUR_Amount__c,
          kind
        );
        System.assertEquals(
          preview[i].dueDate,
          entries[i].AXF_ENT_DAT_DueDate__c,
          kind
        );
        paid += entries[i].AXF_ENT_CUR_Amount__c;
        interest += preview[i].interest;
      }
      // The last installment settles the balance: what was paid is the principal plus the interest.
      System.assertEquals(paid - 1234.56, interest, kind);
    }
  }

  @IsTest
  static void thePriceTableMatchesTheReferenceInstallmentByInstallment() {
    grantFinancingFieldAccess();
    ALT_CLS_ExpenseWizard.FinancingRequest financing = financing(
      holder('Titular').Id
    );
    financing.base.amount = 1000;
    financing.amortizationSystem = 'PRICE';

    List<ALT_CLS_ExpenseWizard.PreviewItem> preview = AXF_CLS_CTRL_ExpenseWizard.previewFinancing(
      JSON.serialize(financing)
    );
    Id id = AXF_CLS_CTRL_ExpenseWizard.createFinancing(
      JSON.serialize(financing)
    );

    List<AXF_OBJ_Entry__c> entries = [
      SELECT AXF_ENT_CUR_Amount__c, AXF_ENT_DAT_DueDate__c
      FROM AXF_OBJ_Entry__c
      WHERE AXF_ENT_LKP_Contract__c = :id
      ORDER BY AXF_ENT_NUM_InstallmentNumber__c
    ];
    System.assertEquals(12, entries.size());
    for (Integer i = 0; i < entries.size(); i++) {
      System.assertEquals(preview[i].amount, entries[i].AXF_ENT_CUR_Amount__c);
      System.assertEquals(
        preview[i].dueDate,
        entries[i].AXF_ENT_DAT_DueDate__c
      );
    }
    // Reference: 11 installments of 88,85 and a last one that settles the balance.
    System.assertEquals(88.85, entries[10].AXF_ENT_CUR_Amount__c);
    Decimal last = entries[11].AXF_ENT_CUR_Amount__c;
    System.assert(last >= 88.80 && last <= 88.95, 'last installment ' + last);
    Decimal total = 0;
    for (AXF_OBJ_Entry__c entry : entries) {
      total += entry.AXF_ENT_CUR_Amount__c;
    }
    System.assert(total >= 1066.10 && total <= 1066.30, 'total ' + total);
  }

  @IsTest
  static void theLimitsOfTheFinancingCountAreAccepted() {
    grantFinancingFieldAccess();
    for (Integer count : new List<Integer>{ 2, 480 }) {
      ALT_CLS_ExpenseWizard.FinancingRequest financing = financing(
        holder('Titular ' + count).Id
      );
      financing.base.amount = 100000;
      financing.count = count;

      Id id = AXF_CLS_CTRL_ExpenseWizard.createFinancing(
        JSON.serialize(financing)
      );

      System.assertEquals(
        count,
        [
          SELECT COUNT()
          FROM AXF_OBJ_Entry__c
          WHERE AXF_ENT_LKP_Contract__c = :id
        ]
      );
    }
  }

  @IsTest
  static void aFinancingWithoutInterestSplitsThePrincipal() {
    grantFinancingFieldAccess();
    ALT_CLS_ExpenseWizard.FinancingRequest financing = financing(
      holder('Titular').Id
    );
    financing.monthlyRate = 0;
    financing.amortizationSystem = 'PRICE';
    financing.creditor = ' ';

    List<ALT_CLS_ExpenseWizard.PreviewItem> preview = AXF_CLS_CTRL_ExpenseWizard.previewFinancing(
      JSON.serialize(financing)
    );
    Id id = AXF_CLS_CTRL_ExpenseWizard.createFinancing(
      JSON.serialize(financing)
    );

    for (ALT_CLS_ExpenseWizard.PreviewItem item : preview) {
      System.assertEquals(100.00, item.amount);
      System.assertEquals(0, item.interest);
    }
    System.assertEquals(
      null,
      [
        SELECT AXF_CTR_TXT_Counterparty__c
        FROM AXF_OBJ_Contract__c
        WHERE Id = :id
      ]
      .AXF_CTR_TXT_Counterparty__c
    );
  }

  @IsTest
  static void rejectsInvalidFinancingRequestsWithoutCreatingAnything() {
    Account mine = holder('Meu');
    Account other = holder('Outro');
    ALT_CLS_ExpenseWizard.FinancingRequest one = financing(mine.Id);
    one.count = 1;
    assertFinancingRejected(one, 'O número de parcelas deve ser de 2 a 480.');
    ALT_CLS_ExpenseWizard.FinancingRequest many = financing(mine.Id);
    many.count = 481;
    assertFinancingRejected(many, 'O número de parcelas deve ser de 2 a 480.');
    ALT_CLS_ExpenseWizard.FinancingRequest zero = financing(mine.Id);
    zero.base.amount = 0;
    assertFinancingRejected(
      zero,
      'O valor financiado deve ser maior que zero.'
    );
    ALT_CLS_ExpenseWizard.FinancingRequest tiny = financing(mine.Id);
    tiny.base.amount = 0.001;
    assertFinancingRejected(
      tiny,
      'O valor financiado deve ser maior que zero.'
    );
    ALT_CLS_ExpenseWizard.FinancingRequest noRate = financing(mine.Id);
    noRate.monthlyRate = null;
    assertFinancingRejected(
      noRate,
      'A taxa mensal deve estar entre 0% e 100%.'
    );
    ALT_CLS_ExpenseWizard.FinancingRequest negative = financing(mine.Id);
    negative.monthlyRate = -0.5;
    assertFinancingRejected(
      negative,
      'A taxa mensal deve estar entre 0% e 100%.'
    );
    ALT_CLS_ExpenseWizard.FinancingRequest tooHigh = financing(mine.Id);
    tooHigh.monthlyRate = 100.5;
    assertFinancingRejected(
      tooHigh,
      'A taxa mensal deve estar entre 0% e 100%.'
    );
    ALT_CLS_ExpenseWizard.FinancingRequest badSystem = financing(mine.Id);
    badSystem.amortizationSystem = 'OUTRO';
    assertFinancingRejected(badSystem, 'Escolha o sistema: SAC ou PRICE.');
    ALT_CLS_ExpenseWizard.FinancingRequest noSystem = financing(mine.Id);
    noSystem.amortizationSystem = null;
    assertFinancingRejected(noSystem, 'Escolha o sistema: SAC ou PRICE.');
    ALT_CLS_ExpenseWizard.FinancingRequest longName = financing(mine.Id);
    longName.creditor = 'a'.repeat(121);
    assertFinancingRejected(
      longName,
      'O nome do credor deve ter até 120 caracteres.'
    );
    ALT_CLS_ExpenseWizard.FinancingRequest noDue = financing(mine.Id);
    noDue.base.dueDate = null;
    assertFinancingRejected(noDue, 'Informe o primeiro vencimento.');
    ALT_CLS_ExpenseWizard.FinancingRequest noHolder = financing(mine.Id);
    noHolder.base.holderId = null;
    assertFinancingRejected(noHolder, 'Informe o titular.');
    ALT_CLS_ExpenseWizard.FinancingRequest noDescription = financing(mine.Id);
    noDescription.base.description = ' ';
    assertFinancingRejected(noDescription, 'Informe a descrição.');
    ALT_CLS_ExpenseWizard.FinancingRequest huge = financing(mine.Id);
    huge.base.amount = 1000000000000000.00;
    assertFinancingRejected(huge, 'O valor total está acima do limite.');
    ALT_CLS_ExpenseWizard.FinancingRequest foreign = financing(mine.Id);
    foreign.base.cardId = card(other.Id).Id;
    assertFinancingRejected(foreign, 'O cartão não pertence ao titular.');
    ALT_CLS_ExpenseWizard.FinancingRequest foreignAccount = financing(mine.Id);
    foreignAccount.base.accountId = account(other.Id).Id;
    assertFinancingRejected(foreignAccount, 'A conta não pertence ao titular.');
    ALT_CLS_ExpenseWizard.FinancingRequest roundsAboveTheCap = financing(
      mine.Id
    );
    roundsAboveTheCap.monthlyRate = 100.00005;
    assertFinancingRejected(
      roundsAboveTheCap,
      'A taxa mensal deve estar entre 0% e 100%.'
    );
    ALT_CLS_ExpenseWizard.FinancingRequest tooSmallToSplit = financing(mine.Id);
    tooSmallToSplit.base.amount = 0.05;
    tooSmallToSplit.monthlyRate = 0;
    assertFinancingRejected(
      tooSmallToSplit,
      'O valor financiado é pequeno demais para este número de parcelas.'
    );
    ALT_CLS_ExpenseWizard.FinancingRequest hugeTotal = financing(mine.Id);
    hugeTotal.base.amount = 999999999999999.00;
    hugeTotal.monthlyRate = 100;
    hugeTotal.amortizationSystem = 'PRICE';
    assertFinancingRejected(hugeTotal, 'O valor total está acima do limite.');
    ALT_CLS_ExpenseWizard.FinancingRequest both = financing(mine.Id);
    both.base.accountId = account(mine.Id).Id;
    both.base.cardId = card(mine.Id).Id;
    assertFinancingRejected(both, 'Escolha a conta ou o cartão, não os dois.');
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
  static void optionsCarryTheCategoryParentAndNewCategoriesAreExpenses() {
    ALT_CLS_ExpenseWizard.Option parent = AXF_CLS_CTRL_ExpenseWizard.createCategory(
      '  Moradia ',
      null
    );
    ALT_CLS_ExpenseWizard.Option child = AXF_CLS_CTRL_ExpenseWizard.createCategory(
      'Energia',
      parent.id
    );

    System.assertEquals('Moradia', parent.label);
    System.assertEquals(parent.id, child.parentId);
    AXF_OBJ_Category__c saved = [
      SELECT AXF_CAT_PKL_Type__c, AXF_CAT_LKP_Parent__c
      FROM AXF_OBJ_Category__c
      WHERE Id = :child.id
    ];
    System.assertEquals('Expense', saved.AXF_CAT_PKL_Type__c);
    System.assertEquals(parent.id, saved.AXF_CAT_LKP_Parent__c);

    Map<Id, Id> parentOf = new Map<Id, Id>();
    for (
      ALT_CLS_ExpenseWizard.Option option : AXF_CLS_CTRL_ExpenseWizard.getOptions(
          null
        )
        .categories
    ) {
      parentOf.put(option.id, option.parentId);
    }
    System.assertEquals(null, parentOf.get(parent.id));
    System.assertEquals(parent.id, parentOf.get(child.id));
  }

  @IsTest
  static void aBlankParentCreatesATopLevelCategory() {
    ALT_CLS_ExpenseWizard.Option top = AXF_CLS_CTRL_ExpenseWizard.createCategory(
      'Lazer',
      ''
    );
    System.assertEquals(null, top.parentId);
    System.assertEquals(
      null,
      [
        SELECT AXF_CAT_LKP_Parent__c
        FROM AXF_OBJ_Category__c
        WHERE Id = :top.id
      ]
      .AXF_CAT_LKP_Parent__c
    );
  }

  @IsTest
  static void aParentThatIsNotAnIdGetsAReadableError() {
    try {
      AXF_CLS_CTRL_ExpenseWizard.createCategory('Lazer', 'Nenhuma');
      System.assert(false, 'expected AuraHandledException');
    } catch (AuraHandledException e) {
      System.assertEquals('A categoria pai é inválida.', e.getMessage());
    }
    System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_Category__c]);
  }

  @IsTest
  static void aCategoryNeedsAName() {
    try {
      AXF_CLS_CTRL_ExpenseWizard.createCategory(' ', null);
      System.assert(false, 'expected AuraHandledException');
    } catch (AuraHandledException e) {
      System.assertEquals('Informe o nome da categoria.', e.getMessage());
    }
    System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_Category__c]);
  }

  @IsTest
  static void aBlankOrMalformedRequestGetsAReadableError() {
    for (String bad : new List<String>{ null, '', ' ', 'null' }) {
      try {
        AXF_CLS_CTRL_ExpenseWizard.createStandalone(bad);
        System.assert(false, 'expected AuraHandledException');
      } catch (AuraHandledException e) {
        System.assertEquals('Pedido não informado.', e.getMessage());
      }
    }
    try {
      AXF_CLS_CTRL_ExpenseWizard.createStandalone('{');
      System.assert(false, 'expected AuraHandledException');
    } catch (AuraHandledException e) {
      System.assertEquals('Pedido inválido.', e.getMessage());
    }
    try {
      AXF_CLS_CTRL_ExpenseWizard.createStandalone('{"amount":"abc"}');
      System.assert(false, 'expected AuraHandledException');
    } catch (AuraHandledException e) {
      System.assertEquals('Pedido inválido.', e.getMessage());
    }
  }

  @IsTest
  static void aCategoryWithTheSameNameAndParentIsReusedNotDuplicated() {
    ALT_CLS_ExpenseWizard.Option first = AXF_CLS_CTRL_ExpenseWizard.createCategory(
      'Moradia',
      null
    );
    ALT_CLS_ExpenseWizard.Option again = AXF_CLS_CTRL_ExpenseWizard.createCategory(
      'Moradia',
      null
    );
    ALT_CLS_ExpenseWizard.Option child = AXF_CLS_CTRL_ExpenseWizard.createCategory(
      'Moradia',
      first.id
    );

    System.assertEquals(first.id, again.id);
    System.assertNotEquals(first.id, child.id);
    System.assertEquals(2, [SELECT COUNT() FROM AXF_OBJ_Category__c]);
  }

  @IsTest
  static void theParentOfANewCategoryMustBeAnExpenseCategory() {
    AXF_OBJ_Category__c income = new AXF_OBJ_Category__c(
      Name = 'Salário',
      AXF_CAT_PKL_Type__c = 'Income'
    );
    insert income;
    try {
      AXF_CLS_CTRL_ExpenseWizard.createCategory('Bônus', income.Id);
      System.assert(false, 'expected AuraHandledException');
    } catch (AuraHandledException e) {
      System.assertEquals('A categoria pai não é de despesa.', e.getMessage());
    }
    System.assertEquals(1, [SELECT COUNT() FROM AXF_OBJ_Category__c]);
  }

  @IsTest
  static void userWithoutPermissionCannotCreateACategory() {
    User user = new User(
      Alias = 'axfcatw',
      Email = 'axfcatw@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'NoCategoryAccess',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = ALT_CLS_ConnectionTestUser.standardProfileId(),
      TimeZoneSidKey = 'America/Sao_Paulo',
      Username = 'axfcatw' + System.currentTimeMillis() + '@example.com'
    );
    insert user;
    System.runAs(user) {
      try {
        AXF_CLS_CTRL_ExpenseWizard.createCategory('Pet', null);
        System.assert(false, 'expected AuraHandledException');
      } catch (AuraHandledException e) {
        System.assertNotEquals(null, e.getMessage());
      }
    }
    System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_Category__c]);
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

  @IsTest
  static void chargesAreSavedOnTheContractAndAddedToEveryInstallment() {
    grantFinancingFieldAccess();
    Account h = holder('Titular');
    ALT_CLS_ExpenseWizard.FinancingRequest financing = financing(h.Id);
    financing.insurance = 10;
    financing.adminFee = 5;
    financing.otherCharges = 2.50;

    List<ALT_CLS_ExpenseWizard.PreviewItem> preview = AXF_CLS_CTRL_ExpenseWizard.previewFinancing(
      JSON.serialize(financing)
    );
    Id id = AXF_CLS_CTRL_ExpenseWizard.createFinancing(
      JSON.serialize(financing)
    );

    // SAC 1,200.00 at 1 %: 100.00 + 12.00 of interest + 17.50 of charges.
    System.assertEquals(129.50, preview[0].amount);
    System.assertEquals(12.00, preview[0].interest);
    System.assertEquals(17.50, preview[0].charges);
    AXF_OBJ_Contract__c contract = [
      SELECT
        AXF_CTR_CUR_Insurance__c,
        AXF_CTR_CUR_AdminFee__c,
        AXF_CTR_CUR_OtherCharges__c,
        AXF_CTR_CUR_UpfrontCosts__c
      FROM AXF_OBJ_Contract__c
      WHERE Id = :id
    ];
    System.assertEquals(10, contract.AXF_CTR_CUR_Insurance__c);
    System.assertEquals(5, contract.AXF_CTR_CUR_AdminFee__c);
    System.assertEquals(2.50, contract.AXF_CTR_CUR_OtherCharges__c);
    System.assertEquals(0, contract.AXF_CTR_CUR_UpfrontCosts__c);
    List<AXF_OBJ_Entry__c> entries = [
      SELECT AXF_ENT_CUR_Amount__c
      FROM AXF_OBJ_Entry__c
      WHERE AXF_ENT_LKP_Contract__c = :id
      ORDER BY AXF_ENT_NUM_InstallmentNumber__c
    ];
    System.assertEquals(12, entries.size());
    for (Integer i = 0; i < 12; i++) {
      System.assertEquals(preview[i].amount, entries[i].AXF_ENT_CUR_Amount__c);
    }
  }

  @IsTest
  static void upfrontCostsAreFinancedWithTheAmount() {
    grantFinancingFieldAccess();
    Account h = holder('Titular');
    ALT_CLS_ExpenseWizard.FinancingRequest financing = financing(h.Id);
    financing.base.amount = 1000;
    financing.monthlyRate = 0;
    financing.upfrontCosts = 200;

    Id id = AXF_CLS_CTRL_ExpenseWizard.createFinancing(
      JSON.serialize(financing)
    );

    // 1,000.00 financed plus 200.00 of fees: 1,200.00 over 12 months without interest.
    AXF_OBJ_Contract__c contract = [
      SELECT AXF_CTR_CUR_FinancedAmount__c, AXF_CTR_CUR_UpfrontCosts__c
      FROM AXF_OBJ_Contract__c
      WHERE Id = :id
    ];
    System.assertEquals(1000, contract.AXF_CTR_CUR_FinancedAmount__c);
    System.assertEquals(200, contract.AXF_CTR_CUR_UpfrontCosts__c);
    for (AXF_OBJ_Entry__c entry : [
      SELECT AXF_ENT_CUR_Amount__c
      FROM AXF_OBJ_Entry__c
      WHERE AXF_ENT_LKP_Contract__c = :id
    ]) {
      System.assertEquals(100.00, entry.AXF_ENT_CUR_Amount__c);
    }
  }

  @IsTest
  static void anInformedInstallmentGivesTheImpliedRateAndTheOtherInstallments() {
    grantFinancingFieldAccess();
    Account h = holder('Titular');
    ALT_CLS_ExpenseWizard.FinancingRequest financing = financing(h.Id);
    financing.base.amount = 1000;
    financing.monthlyRate = null;
    financing.installmentAmount = 88.85;
    financing.amortizationSystem = 'PRICE';
    financing.insurance = 10;

    List<ALT_CLS_ExpenseWizard.PreviewItem> preview = AXF_CLS_CTRL_ExpenseWizard.previewFinancing(
      JSON.serialize(financing)
    );
    Id id = AXF_CLS_CTRL_ExpenseWizard.createFinancing(
      JSON.serialize(financing)
    );

    System.assertEquals(12, preview.size());
    System.assertEquals(98.85, preview[0].amount);
    System.assertEquals(98.85, preview[10].amount);
    System.assert(
      Math.abs(preview[0].monthlyRate - 1) < 0.001,
      'rate ' + preview[0].monthlyRate
    );
    AXF_OBJ_Contract__c contract = [
      SELECT AXF_CTR_PCT_MonthlyRate__c, AXF_CTR_CUR_InformedInstallment__c
      FROM AXF_OBJ_Contract__c
      WHERE Id = :id
    ];
    System.assertEquals(88.85, contract.AXF_CTR_CUR_InformedInstallment__c);
    System.assertEquals(
      preview[0].monthlyRate,
      contract.AXF_CTR_PCT_MonthlyRate__c
    );
    System.assertEquals(
      12,
      [SELECT COUNT() FROM AXF_OBJ_Entry__c WHERE AXF_ENT_LKP_Contract__c = :id]
    );
  }

  @IsTest
  static void rejectsInvalidInstallmentsAndChargesWithoutCreatingAnything() {
    Account h = holder('Titular');
    ALT_CLS_ExpenseWizard.FinancingRequest sac = financing(h.Id);
    sac.installmentAmount = 100;
    assertFinancingRejected(
      sac,
      'Com a parcela informada o sistema é PRICE (parcela constante).'
    );

    ALT_CLS_ExpenseWizard.FinancingRequest low = financing(h.Id);
    low.amortizationSystem = 'PRICE';
    low.installmentAmount = 50;
    assertFinancingRejected(
      low,
      'A parcela informada não paga o valor financiado com taxa entre 0% e 100%.'
    );

    ALT_CLS_ExpenseWizard.FinancingRequest negative = financing(h.Id);
    negative.insurance = -1;
    assertFinancingRejected(
      negative,
      'Seguro, taxas e tarifas devem ser zero ou mais, dentro do limite.'
    );
    ALT_CLS_ExpenseWizard.FinancingRequest tooHigh = financing(h.Id);
    tooHigh.base.amount = 1000;
    tooHigh.amortizationSystem = 'PRICE';
    tooHigh.installmentAmount = 1500;
    assertFinancingRejected(
      tooHigh,
      'A parcela informada não paga o valor financiado com taxa entre 0% e 100%.'
    );
    ALT_CLS_ExpenseWizard.FinancingRequest huge = financing(h.Id);
    huge.otherCharges = 1000000000000000.00;
    assertFinancingRejected(
      huge,
      'Seguro, taxas e tarifas devem ser zero ou mais, dentro do limite.'
    );
    System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_Contract__c]);
    System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_Entry__c]);
  }
}
