@IsTest
private class ALT_CLS_ContractGenerationTest {
  private static Account holder;

  private static Id rt(String developerName) {
    return Schema.SObjectType.AXF_OBJ_Contract__c.getRecordTypeInfosByDeveloperName()
      .get(developerName)
      .getRecordTypeId();
  }

  private static AXF_OBJ_Contract__c contract(String recordType) {
    if (holder == null) {
      holder = new Account(Name = 'Titular');
      insert holder;
    }
    return new AXF_OBJ_Contract__c(
      Name = 'Contrato',
      AXF_CTR_MD_Holder__c = holder.Id,
      RecordTypeId = rt(recordType),
      AXF_CTR_PKL_Direction__c = 'Expense',
      AXF_CTR_PKL_Status__c = 'Active',
      AXF_CTR_DAT_FirstDueDate__c = Date.today().addDays(5),
      AXF_CTR_CUR_Amount__c = 100
    );
  }

  private static List<AXF_OBJ_Entry__c> entries(Id contractId) {
    return [
      SELECT
        Id,
        Name,
        AXF_ENT_CUR_Amount__c,
        AXF_ENT_DAT_DueDate__c,
        AXF_ENT_DAT_Competence__c,
        AXF_ENT_NUM_InstallmentNumber__c,
        AXF_ENT_PKL_Status__c,
        AXF_ENT_PKL_Type__c,
        AXF_ENT_LKP_BankAccount__c,
        AXF_ENT_MD_Holder__c
      FROM AXF_OBJ_Entry__c
      WHERE AXF_ENT_LKP_Contract__c = :contractId
      ORDER BY AXF_ENT_DAT_DueDate__c
    ];
  }

  private static ALT_CLS_ContractGeneration.Result run(
    AXF_OBJ_Contract__c c,
    Boolean updatePending
  ) {
    return new ALT_CLS_ContractGeneration()
      .generate(new Set<Id>{ c.Id }, updatePending);
  }

  @IsTest
  static void recurringGeneratesPendingEntriesAndRerunDoesNotDuplicate() {
    AXF_OBJ_Contract__c c = contract('AXF_Recurring');
    c.AXF_CTR_DAT_EndDate__c = Date.today().addMonths(3);
    insert c;
    ALT_CLS_ContractGeneration.Result first = run(c, true);
    List<AXF_OBJ_Entry__c> rows = entries(c.Id);
    System.assertEquals(first.created, rows.size());
    System.assert(
      rows.size() >= 3 && rows.size() <= 4,
      'entries ' + rows.size()
    );
    System.assertEquals('Pending', rows[0].AXF_ENT_PKL_Status__c);
    System.assertEquals('Expense', rows[0].AXF_ENT_PKL_Type__c);
    System.assertEquals(holder.Id, rows[0].AXF_ENT_MD_Holder__c);
    System.assertEquals(null, rows[0].AXF_ENT_NUM_InstallmentNumber__c);
    ALT_CLS_ContractGeneration.Result second = run(c, true);
    System.assertEquals(0, second.created);
    System.assertEquals(0, second.updated);
    System.assertEquals(rows.size(), entries(c.Id).size());
  }

  @IsTest
  static void recurringWithoutEndDateStopsTwelveMonthsAhead() {
    AXF_OBJ_Contract__c c = contract('AXF_Recurring');
    insert c;
    run(c, true);
    List<AXF_OBJ_Entry__c> rows = entries(c.Id);
    System.assert(
      rows.size() >= 12 && rows.size() <= 13,
      'entries ' + rows.size()
    );
    System.assert(
      rows[rows.size() - 1].AXF_ENT_DAT_DueDate__c <= Date.today().addMonths(12)
    );
  }

  @IsTest
  static void installmentGeneratesEveryParcelOnce() {
    AXF_OBJ_Contract__c c = contract('AXF_Installment');
    c.AXF_CTR_NUM_InstallmentCount__c = 6;
    insert c;
    System.assertEquals(6, run(c, true).created);
    List<AXF_OBJ_Entry__c> rows = entries(c.Id);
    System.assertEquals(1, rows[0].AXF_ENT_NUM_InstallmentNumber__c);
    System.assertEquals(6, rows[5].AXF_ENT_NUM_InstallmentNumber__c);
    System.assertEquals(0, run(c, true).created);
  }

  @IsTest
  static void consortiumBehavesLikeInstallment() {
    AXF_OBJ_Contract__c c = contract('AXF_Consortium');
    c.AXF_CTR_NUM_InstallmentCount__c = 4;
    insert c;
    System.assertEquals(4, run(c, false).created);
  }

  @IsTest
  static void sourceIsCopiedToTheEntries() {
    AXF_OBJ_Contract__c c = contract('AXF_Installment');
    c.AXF_CTR_NUM_InstallmentCount__c = 2;
    insert c;
    AXF_OBJ_BankAccount__c bank = new AXF_OBJ_BankAccount__c(
      Name = 'Conta',
      AXF_BA_MD_Holder__c = holder.Id,
      AXF_BA_PKL_Institution__c = '341',
      AXF_BA_PKL_Type__c = 'Checking'
    );
    insert bank;
    c.AXF_CTR_LKP_BankAccount__c = bank.Id;
    update c;
    run(c, true);
    for (AXF_OBJ_Entry__c e : entries(c.Id)) {
      System.assertEquals(bank.Id, e.AXF_ENT_LKP_BankAccount__c);
    }
  }

  @IsTest
  static void financingUsesTheScheduleOfTheChosenSystem() {
    AXF_OBJ_Contract__c c = contract('AXF_Financing');
    c.AXF_CTR_CUR_Amount__c = null;
    c.AXF_CTR_CUR_FinancedAmount__c = 12000;
    c.AXF_CTR_PCT_MonthlyRate__c = 1;
    c.AXF_CTR_NUM_InstallmentCount__c = 12;
    c.AXF_CTR_PKL_AmortizationSystem__c = 'SAC';
    insert c;
    System.assertEquals(12, run(c, true).created);
    List<AXF_OBJ_Entry__c> rows = entries(c.Id);
    System.assertEquals(1120, rows[0].AXF_ENT_CUR_Amount__c);
    System.assertEquals(1010, rows[11].AXF_ENT_CUR_Amount__c);
  }

  @IsTest
  static void regenerateUpdatesOnlyPendingFutureEntries() {
    AXF_OBJ_Contract__c c = contract('AXF_Installment');
    c.AXF_CTR_NUM_InstallmentCount__c = 3;
    insert c;
    run(c, true);
    List<AXF_OBJ_Entry__c> rows = entries(c.Id);
    // Parcel 1 is realized; parcel 2 was edited by hand; parcel 3 stays as generated.
    rows[0].AXF_ENT_PKL_Status__c = 'Realized';
    rows[0].AXF_ENT_DAT_PaymentDate__c = Date.today();
    rows[1].AXF_ENT_CUR_Amount__c = 999;
    update new List<AXF_OBJ_Entry__c>{ rows[0], rows[1] };
    c.AXF_CTR_CUR_Amount__c = 150;
    update c;
    ALT_CLS_ContractGeneration.Result result = run(c, true);
    // Parcel 1 is due in 5 days but Realized, so only parcels 2 and 3 change.
    System.assertEquals(2, result.updated);
    List<AXF_OBJ_Entry__c> after = entries(c.Id);
    System.assertEquals(
      100,
      after[0].AXF_ENT_CUR_Amount__c,
      'Realized never changes'
    );
    System.assertEquals(
      150,
      after[1].AXF_ENT_CUR_Amount__c,
      'Manual edit is overwritten'
    );
    System.assertEquals(150, after[2].AXF_ENT_CUR_Amount__c);
  }

  @IsTest
  static void withoutUpdatePendingOnlyMissingEntriesAreAdded() {
    AXF_OBJ_Contract__c c = contract('AXF_Recurring');
    c.AXF_CTR_DAT_EndDate__c = Date.today().addMonths(2);
    insert c;
    run(c, true);
    Integer before = entries(c.Id).size();
    c.AXF_CTR_CUR_Amount__c = 500;
    c.AXF_CTR_DAT_EndDate__c = Date.today().addMonths(4);
    update c;
    ALT_CLS_ContractGeneration.Result result = run(c, false);
    System.assertEquals(0, result.updated);
    System.assert(result.created > 0);
    System.assertEquals(100, entries(c.Id)[0].AXF_ENT_CUR_Amount__c);
    System.assert(entries(c.Id).size() > before);
  }

  @IsTest
  static void incompleteOrClosedContractsAreSkippedWithAMessage() {
    AXF_OBJ_Contract__c noAmount = contract('AXF_Recurring');
    noAmount.AXF_CTR_CUR_Amount__c = null;
    AXF_OBJ_Contract__c closed = contract('AXF_Recurring');
    closed.AXF_CTR_PKL_Status__c = 'Closed';
    AXF_OBJ_Contract__c service = contract('AXF_ServiceProvision');
    AXF_OBJ_Contract__c noCount = contract('AXF_Installment');
    insert new List<AXF_OBJ_Contract__c>{ noAmount, closed, service, noCount };
    ALT_CLS_ContractGeneration.Result result = new ALT_CLS_ContractGeneration()
      .generate(
        new Set<Id>{ noAmount.Id, closed.Id, service.Id, noCount.Id },
        true
      );
    System.assertEquals(0, result.created);
    System.assertEquals(4, result.messages.size());
  }

  @IsTest
  static void batchAndScheduleExtendOnlyActiveRecurringContracts() {
    AXF_OBJ_Contract__c recurring = contract('AXF_Recurring');
    AXF_OBJ_Contract__c installment = contract('AXF_Installment');
    installment.AXF_CTR_NUM_INSTALLMENTCOUNT__c = 2;
    insert new List<AXF_OBJ_Contract__c>{ recurring, installment };
    Test.startTest();
    ALT_CLS_ContractGenerationBatch.run();
    Test.stopTest();
    System.assert(entries(recurring.Id).size() >= 12);
    System.assertEquals(0, entries(installment.Id).size());
    System.assertNotEquals(
      null,
      ALT_CLS_ContractGenerationSchedule.scheduleMonthly()
    );
    // Scheduling again replaces the job instead of duplicating it.
    ALT_CLS_ContractGenerationSchedule.scheduleMonthly();
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM CronTrigger
        WHERE CronJobDetail.Name = :ALT_CLS_ContractGenerationSchedule.JOB_NAME
      ]
    );
  }

  @IsTest
  static void controllerReturnsTheSummary() {
    AXF_OBJ_Contract__c c = contract('AXF_Installment');
    c.AXF_CTR_NUM_InstallmentCount__c = 3;
    insert c;
    AXF_CLS_CTRL_ContractGeneration.Summary summary = AXF_CLS_CTRL_ContractGeneration.generate(
      c.Id
    );
    System.assertEquals(3, summary.created);
    System.assertEquals(0, summary.updated);
    Boolean failed = false;
    try {
      AXF_CLS_CTRL_ContractGeneration.generate(null);
    } catch (AuraHandledException e) {
      failed = true;
    }
    System.assert(failed, 'Expected an error without a contract');
  }

  @IsTest
  static void sourceCategoryAndCurrencyAreCopiedAndRefreshedOnRegenerate() {
    AXF_OBJ_Contract__c c = contract('AXF_Consortium');
    c.AXF_CTR_NUM_InstallmentCount__c = 2;
    insert c;
    AXF_OBJ_CreditCard__c card = new AXF_OBJ_CreditCard__c(
      Name = 'Cartão',
      AXF_CC_MD_Holder__c = holder.Id,
      AXF_CC_PKL_Institution__c = '341'
    );
    insert card;
    AXF_OBJ_Category__c category = new AXF_OBJ_Category__c(
      Name = 'Casa',
      AXF_CAT_PKL_Type__c = 'Expense'
    );
    insert category;
    c.AXF_CTR_LKP_CreditCard__c = card.Id;
    c.AXF_CTR_LKP_Category__c = category.Id;
    update c;
    run(c, true);
    AXF_OBJ_Entry__c first = [
      SELECT AXF_ENT_LKP_CreditCard__c, AXF_ENT_LKP_Category__c, CurrencyIsoCode
      FROM AXF_OBJ_Entry__c
      WHERE AXF_ENT_LKP_Contract__c = :c.Id
      ORDER BY AXF_ENT_DAT_DueDate__c
      LIMIT 1
    ];
    System.assertEquals(card.Id, first.AXF_ENT_LKP_CreditCard__c);
    System.assertEquals(category.Id, first.AXF_ENT_LKP_Category__c);
    System.assertEquals(
      [SELECT CurrencyIsoCode FROM AXF_OBJ_Contract__c WHERE Id = :c.Id]
      .CurrencyIsoCode,
      first.CurrencyIsoCode
    );
    // Changing the first due date moves the Pending entries on regenerate.
    c.AXF_CTR_DAT_FirstDueDate__c = Date.today().addDays(20);
    update c;
    System.assertEquals(2, run(c, true).updated);
    System.assertEquals(
      Date.today().addDays(20),
      entries(c.Id)[0].AXF_ENT_DAT_DueDate__c
    );
  }

  @IsTest
  static void priceFinancingIsWrittenWithTheLastInstallmentAbsorbingTheResidue() {
    AXF_OBJ_Contract__c c = contract('AXF_Financing');
    c.AXF_CTR_CUR_Amount__c = null;
    c.AXF_CTR_CUR_FinancedAmount__c = 12000;
    c.AXF_CTR_PCT_MonthlyRate__c = 1;
    c.AXF_CTR_NUM_InstallmentCount__c = 12;
    c.AXF_CTR_PKL_AmortizationSystem__c = 'PRICE';
    insert c;
    System.assertEquals(12, run(c, true).created);
    List<AXF_OBJ_Entry__c> rows = entries(c.Id);
    System.assertEquals(1066.19, rows[0].AXF_ENT_CUR_Amount__c);
    Decimal paid = 0;
    for (AXF_OBJ_Entry__c e : rows) {
      paid += e.AXF_ENT_CUR_Amount__c;
    }
    System.assert(Math.abs(paid - 12794.28) < 0.2, 'total paid ' + paid);
  }

  @IsTest
  static void financingWithoutASystemIsSkipped() {
    AXF_OBJ_Contract__c c = contract('AXF_Financing');
    c.AXF_CTR_CUR_Amount__c = null;
    c.AXF_CTR_CUR_FinancedAmount__c = 1000;
    c.AXF_CTR_PCT_MonthlyRate__c = 1;
    c.AXF_CTR_NUM_InstallmentCount__c = 3;
    insert c;
    ALT_CLS_ContractGeneration.Result result = run(c, true);
    System.assertEquals(0, result.created);
    System.assertEquals(1, result.messages.size());
  }

  @IsTest
  static void recurringStartsAtTheFirstDueDateOfTheContract() {
    AXF_OBJ_Contract__c c = contract('AXF_Recurring');
    c.AXF_CTR_DAT_FirstDueDate__c = Date.today().addMonths(-6);
    c.AXF_CTR_DAT_EndDate__c = Date.today().addMonths(1);
    insert c;
    run(c, true);
    List<AXF_OBJ_Entry__c> rows = entries(c.Id);
    // Months -6 to +1 of today: 8 entries, the past ones stay Pending.
    System.assertEquals(8, rows.size());
    System.assertEquals(
      c.AXF_CTR_DAT_FirstDueDate__c,
      rows[0].AXF_ENT_DAT_DueDate__c
    );
    System.assertEquals('Pending', rows[0].AXF_ENT_PKL_Status__c);
    // Running again, even with the refresh, adds nothing and leaves the past ones alone.
    ALT_CLS_ContractGeneration.Result again = run(c, true);
    System.assertEquals(0, again.created);
    System.assertEquals(0, again.updated);
    System.assertEquals(8, entries(c.Id).size());
  }

  @IsTest
  static void batchNeverRewritesAnExistingEntry() {
    AXF_OBJ_Contract__c c = contract('AXF_Recurring');
    c.AXF_CTR_DAT_EndDate__c = Date.today().addMonths(2);
    insert c;
    run(c, true);
    List<AXF_OBJ_Entry__c> rows = entries(c.Id);
    rows[0].AXF_ENT_CUR_Amount__c = 321;
    update rows[0];
    c.AXF_CTR_CUR_Amount__c = 500;
    update c;
    Test.startTest();
    ALT_CLS_ContractGenerationBatch.run();
    Test.stopTest();
    System.assertEquals(321, entries(c.Id)[0].AXF_ENT_CUR_Amount__c);
  }

  @IsTest
  static void controllerRefreshesPendingEntriesOnTheSecondCall() {
    AXF_OBJ_Contract__c c = contract('AXF_Installment');
    c.AXF_CTR_NUM_INSTALLMENTCOUNT__c = 2;
    insert c;
    AXF_CLS_CTRL_ContractGeneration.generate(c.Id);
    c.AXF_CTR_CUR_Amount__c = 175;
    update c;
    AXF_CLS_CTRL_ContractGeneration.Summary summary = AXF_CLS_CTRL_ContractGeneration.generate(
      c.Id
    );
    System.assertEquals(0, summary.created);
    System.assertEquals(2, summary.updated);
    System.assertEquals(175, entries(c.Id)[1].AXF_ENT_CUR_Amount__c);
  }

  @IsTest
  static void scheduleUsesTheMonthlyCronAndRunsTheBatch() {
    AXF_OBJ_Contract__c c = contract('AXF_Recurring');
    insert c;
    Test.startTest();
    Id jobId = ALT_CLS_ContractGenerationSchedule.scheduleMonthly();
    System.assertEquals(
      ALT_CLS_ContractGenerationSchedule.MONTHLY_AT_4AM,
      [SELECT CronExpression FROM CronTrigger WHERE Id = :jobId].CronExpression
    );
    new ALT_CLS_ContractGenerationSchedule().execute(null);
    Test.stopTest();
    System.assert(entries(c.Id).size() >= 12);
  }
}
