@IsTest
private class ALT_CLS_ContractScopeTest {
  private static final Date TODAY = Date.newInstance(2026, 10, 15);
  private static Account holder;

  private static AXF_OBJ_Contract__c contract(
    String recordType,
    Integer count
  ) {
    if (holder == null) {
      holder = new Account(Name = 'Titular');
      insert holder;
    }
    AXF_OBJ_Contract__c c = new AXF_OBJ_Contract__c(
      Name = 'Carta',
      AXF_CTR_MD_Holder__c = holder.Id,
      RecordTypeId = Schema.SObjectType.AXF_OBJ_Contract__c.getRecordTypeInfosByDeveloperName()
        .get(recordType)
        .getRecordTypeId(),
      AXF_CTR_PKL_Direction__c = 'Expense',
      AXF_CTR_PKL_Status__c = 'Active',
      AXF_CTR_DAT_FirstDueDate__c = Date.newInstance(2026, 5, 10),
      AXF_CTR_CUR_Amount__c = 100,
      AXF_CTR_NUM_InstallmentCount__c = count
    );
    insert c;
    new ALT_CLS_ContractGeneration(TODAY).generate(new Set<Id>{ c.Id }, false);
    return c;
  }

  private static AXF_OBJ_Contract__c proposed(Id contractId) {
    return ALT_CLS_ContractGeneration.load(new Set<Id>{ contractId })[0];
  }

  private static ALT_CLS_ContractScope.Plan plan(
    AXF_OBJ_Contract__c p,
    Map<String, ALT_CLS_ContractScope.Choice> choices
  ) {
    ALT_CLS_ContractScope service = new ALT_CLS_ContractScope();
    service.today = TODAY;
    return service.plan(p, choices);
  }

  private static Map<String, ALT_CLS_ContractScope.Choice> choose(
    String field,
    String scope,
    Integer fromNumber
  ) {
    return new Map<String, ALT_CLS_ContractScope.Choice>{
      field => new ALT_CLS_ContractScope.Choice(scope, fromNumber)
    };
  }

  private static void realize(Id contractId, Integer installmentNumber) {
    AXF_OBJ_Entry__c entry = [
      SELECT Id
      FROM AXF_OBJ_Entry__c
      WHERE
        AXF_ENT_LKP_Contract__c = :contractId
        AND AXF_ENT_NUM_InstallmentNumber__c = :installmentNumber
    ];
    entry.AXF_ENT_PKL_Status__c = 'Realized';
    entry.AXF_ENT_DAT_PaymentDate__c = Date.newInstance(2026, 5, 10);
    update entry;
  }

  private static Integer updatedFor(String scope, Integer fromNumber) {
    AXF_OBJ_Contract__c c = contract('AXF_Installment', 12);
    realize(c.Id, 1);
    AXF_OBJ_Contract__c p = proposed(c.Id);
    p.AXF_CTR_CUR_Amount__c = 150;
    return plan(
        p,
        choose(ALT_CLS_ContractScope.FIELD_AMOUNT, scope, fromNumber)
      )
      .updated;
  }

  @IsTest
  static void eachScopeSelectsItsPendingEntries() {
    // Parcels 1..12 are due 10/05/2026 .. 10/04/2027; today is 15/10/2026 (parcel 6 is due in
    // the current month, parcels 1..6 are overdue, 7..12 are future) and parcel 1 is Realized.
    System.assertEquals(11, updatedFor(ALT_CLS_ContractScope.SCOPE_ALL, null));
  }

  @IsTest
  static void futureScope() {
    System.assertEquals(
      6,
      updatedFor(ALT_CLS_ContractScope.SCOPE_FUTURE, null)
    );
  }

  @IsTest
  static void fromScope() {
    System.assertEquals(4, updatedFor(ALT_CLS_ContractScope.SCOPE_FROM, 9));
  }

  @IsTest
  static void monthScope() {
    System.assertEquals(1, updatedFor(ALT_CLS_ContractScope.SCOPE_MONTH, null));
  }

  @IsTest
  static void overdueScope() {
    System.assertEquals(
      5,
      updatedFor(ALT_CLS_ContractScope.SCOPE_OVERDUE, null)
    );
  }

  @IsTest
  static void noneScopeChangesNothing() {
    System.assertEquals(0, updatedFor(ALT_CLS_ContractScope.SCOPE_NONE, null));
    AXF_OBJ_Contract__c c = contract('AXF_Installment', 3);
    AXF_OBJ_Contract__c p = proposed(c.Id);
    p.AXF_CTR_CUR_Amount__c = 150;
    p.Name = 'Outro';
    ALT_CLS_ContractScope.Plan result = plan(p, null);
    System.assertEquals(0, result.updated);
    System.assertEquals(3, result.kept);
  }

  @IsTest
  static void eachFieldHasItsOwnScope() {
    AXF_OBJ_Contract__c c = contract('AXF_Installment', 12);
    realize(c.Id, 1);
    AXF_OBJ_Contract__c p = proposed(c.Id);
    p.AXF_CTR_CUR_Amount__c = 150;
    p.Name = 'Nova';
    Map<String, ALT_CLS_ContractScope.Choice> choices = choose(
      ALT_CLS_ContractScope.FIELD_AMOUNT,
      ALT_CLS_ContractScope.SCOPE_FUTURE,
      null
    );
    choices.put(
      ALT_CLS_ContractScope.FIELD_NAME,
      new ALT_CLS_ContractScope.Choice(ALT_CLS_ContractScope.SCOPE_ALL, null)
    );
    ALT_CLS_ContractScope.Plan result = plan(p, choices);
    System.assertEquals(11, result.updated);
    System.assertEquals(1, result.preserved);
    System.assertEquals(0, result.kept);
    for (ALT_CLS_ContractScope.Row row : result.rows) {
      if (row.outcome == ALT_CLS_ContractScope.OUTCOME_PRESERVED) {
        System.assertEquals(row.name, row.newName);
        System.assertEquals(row.amount, row.newAmount);
        continue;
      }
      System.assertEquals('Nova ' + row.ordinal + '/12', row.newName);
      System.assertEquals(
        row.ordinal >= 7 ? 150 : 100,
        row.newAmount,
        'parcel ' + row.ordinal
      );
    }
    for (AXF_OBJ_Entry__c change : result.toUpdate) {
      System.assertNotEquals(null, change.Name);
    }
  }

  @IsTest
  static void dueDateAndCompetenceFollowTheContract() {
    AXF_OBJ_Contract__c c = contract('AXF_Installment', 4);
    AXF_OBJ_Contract__c p = proposed(c.Id);
    p.AXF_CTR_DAT_FirstDueDate__c = Date.newInstance(2026, 5, 20);
    ALT_CLS_ContractScope.Plan result = plan(
      p,
      choose(
        ALT_CLS_ContractScope.FIELD_DUE,
        ALT_CLS_ContractScope.SCOPE_ALL,
        null
      )
    );
    System.assertEquals(4, result.updated);
    System.assertEquals(
      Date.newInstance(2026, 5, 20),
      result.rows[0].newDueDate
    );
    System.assertEquals(
      Date.newInstance(2026, 8, 20),
      result.rows[3].newDueDate
    );
    for (AXF_OBJ_Entry__c change : result.toUpdate) {
      System.assertEquals(
        change.AXF_ENT_DAT_DueDate__c.toStartOfMonth(),
        change.AXF_ENT_DAT_Competence__c
      );
    }
  }

  @IsTest
  static void categoryAndAccountAreCopiedToTheScopedEntries() {
    AXF_OBJ_Contract__c c = contract('AXF_Installment', 3);
    AXF_OBJ_BankAccount__c bank = new AXF_OBJ_BankAccount__c(
      Name = 'Conta',
      AXF_BA_MD_Holder__c = holder.Id,
      AXF_BA_PKL_Institution__c = '341',
      AXF_BA_PKL_Type__c = 'Checking'
    );
    insert bank;
    AXF_OBJ_Category__c category = new AXF_OBJ_Category__c(
      Name = 'Casa',
      AXF_CAT_PKL_Type__c = 'Expense'
    );
    insert category;
    AXF_OBJ_Contract__c p = proposed(c.Id);
    p.AXF_CTR_LKP_BankAccount__c = bank.Id;
    p.AXF_CTR_LKP_Category__c = category.Id;
    Map<String, ALT_CLS_ContractScope.Choice> choices = choose(
      ALT_CLS_ContractScope.FIELD_ACCOUNT,
      ALT_CLS_ContractScope.SCOPE_ALL,
      null
    );
    ALT_CLS_ContractScope.Plan onlyAccount = plan(p, choices);
    System.assertEquals(3, onlyAccount.updated);
    System.assertEquals(
      bank.Id,
      onlyAccount.toUpdate[0].AXF_ENT_LKP_BankAccount__c
    );
    System.assertEquals(null, onlyAccount.toUpdate[0].AXF_ENT_LKP_Category__c);
    choices.put(
      ALT_CLS_ContractScope.FIELD_CATEGORY,
      new ALT_CLS_ContractScope.Choice(ALT_CLS_ContractScope.SCOPE_FROM, 3)
    );
    ALT_CLS_ContractScope.Plan both = plan(p, choices);
    System.assertEquals(category.Id, both.toUpdate[2].AXF_ENT_LKP_Category__c);
    System.assertEquals(null, both.toUpdate[0].AXF_ENT_LKP_Category__c);
  }

  @IsTest
  static void aCaseOnlyRenameChangesTheScopedEntries() {
    AXF_OBJ_Contract__c c = contract('AXF_Installment', 3);
    AXF_OBJ_Contract__c p = proposed(c.Id);
    p.Name = 'carta';
    ALT_CLS_ContractScope.Plan result = plan(
      p,
      choose(
        ALT_CLS_ContractScope.FIELD_NAME,
        ALT_CLS_ContractScope.SCOPE_ALL,
        null
      )
    );
    System.assertEquals(3, result.updated);
    System.assert('carta 1/3'.equals(result.rows[0].newName));
  }

  @IsTest
  static void lastFinancingParcelAbsorbsTheResidue() {
    AXF_OBJ_Contract__c c = contract('AXF_Financing', 7);
    c.AXF_CTR_CUR_Amount__c = null;
    c.AXF_CTR_CUR_FinancedAmount__c = 1000;
    c.AXF_CTR_PCT_MonthlyRate__c = 1;
    c.AXF_CTR_PKL_AmortizationSystem__c = 'SAC';
    AXF_CLS_ContractHandler.bypass = true;
    update c;
    new ALT_CLS_ContractGeneration(TODAY).generate(new Set<Id>{ c.Id }, false);
    AXF_OBJ_Contract__c p = proposed(c.Id);
    p.AXF_CTR_CUR_FinancedAmount__c = 1000.07;
    ALT_CLS_ContractScope.Plan result = plan(
      p,
      choose(
        ALT_CLS_ContractScope.FIELD_AMOUNT,
        ALT_CLS_ContractScope.SCOPE_ALL,
        null
      )
    );
    List<ALT_CLS_ContractSchedule.Item> schedule = ALT_CLS_ContractSchedule.financing(
      1000.07,
      1,
      7,
      'SAC',
      p.AXF_CTR_DAT_FirstDueDate__c
    );
    System.assertEquals(
      schedule[6].amount,
      result.rows[6].newAmount,
      'last parcel'
    );
    System.assertEquals(schedule[0].amount, result.rows[0].newAmount);
  }

  @IsTest
  static void recurringFromUsesThePositionAndDueDayMovesTheDate() {
    AXF_OBJ_Contract__c c = contract('AXF_Recurring', null);
    Integer total = [
      SELECT COUNT()
      FROM AXF_OBJ_Entry__c
      WHERE AXF_ENT_LKP_Contract__c = :c.Id
    ];
    System.assert(total > 6, 'entries ' + total);
    AXF_OBJ_Contract__c p = proposed(c.Id);
    p.AXF_CTR_CUR_Amount__c = 130;
    ALT_CLS_ContractScope.Plan fromThird = plan(
      p,
      choose(
        ALT_CLS_ContractScope.FIELD_AMOUNT,
        ALT_CLS_ContractScope.SCOPE_FROM,
        3
      )
    );
    System.assertEquals(total - 2, fromThird.updated);
    System.assertEquals(2, fromThird.kept);
    AXF_OBJ_Contract__c day = proposed(c.Id);
    day.AXF_CTR_NUM_DueDay__c = 20;
    ALT_CLS_ContractScope.Plan moved = plan(
      day,
      choose(
        ALT_CLS_ContractScope.FIELD_DUE,
        ALT_CLS_ContractScope.SCOPE_ALL,
        null
      )
    );
    // The last month may fall past the 12-month horizon once its day moves to the 20th.
    System.assert(
      moved.updated >= total - 1 && moved.updated <= total,
      'updated ' + moved.updated
    );
    System.assertEquals(20, moved.rows[0].newDueDate.day());
  }

  @IsTest
  static void aClosedContractChangesNoEntry() {
    AXF_OBJ_Contract__c c = contract('AXF_Installment', 3);
    AXF_OBJ_Contract__c p = proposed(c.Id);
    p.AXF_CTR_PKL_Status__c = 'Closed';
    p.AXF_CTR_CUR_Amount__c = 150;
    ALT_CLS_ContractScope.Plan result = plan(
      p,
      choose(
        ALT_CLS_ContractScope.FIELD_AMOUNT,
        ALT_CLS_ContractScope.SCOPE_ALL,
        null
      )
    );
    System.assertEquals(0, result.updated);
    System.assertEquals(3, result.kept);
  }

  @IsTest
  static void anIncompleteProposalIsRejected() {
    AXF_OBJ_Contract__c c = contract('AXF_Installment', 3);
    AXF_OBJ_Contract__c p = proposed(c.Id);
    p.AXF_CTR_CUR_Amount__c = null;
    try {
      plan(p, null);
      System.assert(false, 'Expected an error');
    } catch (ALT_CLS_ContractScope.ScopeException e) {
      System.assert(e.getMessage().contains('informe o valor'));
    }
  }

  @IsTest
  static void twoHundredPendingEntriesPlanWithinTheLimits() {
    AXF_OBJ_Contract__c c = contract('AXF_Installment', 200);
    AXF_OBJ_Contract__c p = proposed(c.Id);
    p.AXF_CTR_CUR_Amount__c = 150;
    Test.startTest();
    ALT_CLS_ContractScope.Plan result = plan(
      p,
      choose(
        ALT_CLS_ContractScope.FIELD_AMOUNT,
        ALT_CLS_ContractScope.SCOPE_ALL,
        null
      )
    );
    Test.stopTest();
    System.assertEquals(200, result.updated);
    System.assertEquals(200, result.toUpdate.size());
  }

  @IsTest
  static void missingInstallmentsAreCounted() {
    AXF_OBJ_Contract__c c = contract('AXF_Installment', 3);
    AXF_OBJ_Contract__c p = proposed(c.Id);
    p.AXF_CTR_NUM_InstallmentCount__c = 5;
    System.assertEquals(2, plan(p, null).missing);
  }
}
