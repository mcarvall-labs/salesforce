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
