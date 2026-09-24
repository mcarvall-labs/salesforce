/**
 * @description AXF-20 — plan/save schedule as PLANNED FinancialTransaction drafts. AXF-156: the
 * save persists a managed AXF-103 schedule (same formula), keyed by the groupKey.
 */
@IsTest(isParallel=false)
private class AXF_CLS_ScheduleServiceTest {
  private static Id rt(String dev) {
    return Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
      .getRecordTypeInfosByDeveloperName()
      .get(dev)
      .getRecordTypeId();
  }

  private static Account holder() {
    Account a = new Account(
      Name = 'Titular Cronograma',
      RecordTypeId = rt('AXF_Business')
    );
    insert a;
    return a;
  }

  private static AXF_CLS_ScheduleService.PlanInput priceplan() {
    AXF_CLS_ScheduleService.PlanInput p = new AXF_CLS_ScheduleService.PlanInput();
    p.modality = 'PRICE';
    p.principal = 1000.00;
    p.installments = 4;
    p.periodRate = 0.02;
    p.firstDueDate = Date.newInstance(2026, 3, 15);
    return p;
  }

  private static AXF_CLS_ScheduleService.SaveInput saveInput(
    Id accountId,
    String groupKey
  ) {
    AXF_CLS_ScheduleService.SaveInput s = new AXF_CLS_ScheduleService.SaveInput();
    s.plan = priceplan();
    s.accountId = accountId;
    s.direction = 'DEBIT';
    s.currencyIsoCode = 'BRL';
    s.groupKey = groupKey;
    return s;
  }

  private static void authorize(Id accountId) {
    AXF_CLS_ScheduleService.authorizedOverride = new Set<Id>{ accountId };
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      accountId
    };
  }

  private static Integer occCount(String groupKey) {
    return [
      SELECT COUNT()
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE AXF_FTX_LKP_Schedule__r.AXF_FSC_TXT_LegacyGroupKey__c = :groupKey
    ];
  }

  @IsTest
  static void planPreviewsWithoutPersisting() {
    ALT_CLS_AmortizationSchedule.ScheduleResult r = AXF_CLS_ScheduleService.plan(
      priceplan()
    );

    System.assertEquals('OK', r.outcome);
    System.assertEquals(4, r.occurrences.size());
    System.assertEquals(
      0,
      [SELECT COUNT() FROM AXF_OBJ_FinancialTransaction__c]
    );
  }

  @IsTest
  static void saveCreatesPlannedDraftsAndIsIdempotent() {
    Account a = holder();
    authorize(a.Id);
    String gk = 'gk-price-0001';

    AXF_CLS_ScheduleService.SaveResult first = AXF_CLS_ScheduleService.save(
      saveInput(a.Id, gk)
    );
    AXF_CLS_ScheduleService.SaveResult again = AXF_CLS_ScheduleService.save(
      saveInput(a.Id, gk)
    );

    System.assertEquals('SAVED', first.outcome, first.message);
    System.assertEquals(4, first.occurrenceCount);
    System.assertNotEquals(null, first.scheduleId);
    System.assertEquals('ALREADY', again.outcome, again.message);
    System.assertEquals(first.scheduleId, again.scheduleId);
    System.assertEquals(4, occCount(gk));

    AXF_OBJ_FinancialTransaction__c seq1 = [
      SELECT
        AXF_FTX_PKL_Status__c,
        AXF_FTX_PKL_Modality__c,
        AXF_FTX_NUM_Magnitude__c,
        AXF_FTX_NUM_PrincipalPortion__c,
        AXF_FTX_NUM_InterestPortion__c,
        AXF_FTX_NUM_ClosingBalance__c,
        AXF_FTX_EXI_ClientRequestId__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE
        AXF_FTX_LKP_Schedule__c = :first.scheduleId
        AND AXF_FTX_NUM_Sequence__c = 1
    ];
    System.assertEquals('PLANNED', seq1.AXF_FTX_PKL_Status__c);
    System.assertEquals('PRICE', seq1.AXF_FTX_PKL_Modality__c);
    System.assertEquals(262.62, seq1.AXF_FTX_NUM_Magnitude__c);
    System.assertEquals(242.62, seq1.AXF_FTX_NUM_PrincipalPortion__c);
    System.assertEquals(20.00, seq1.AXF_FTX_NUM_InterestPortion__c);
    System.assertEquals(757.38, seq1.AXF_FTX_NUM_ClosingBalance__c);
    System.assert(seq1.AXF_FTX_EXI_ClientRequestId__c.startsWith('AXF1'));

    AXF_OBJ_FinancialSchedule__c root = [
      SELECT
        AXF_FSC_PKL_State__c,
        AXF_FSC_BOL_GenerationEnabled__c,
        AXF_FSC_LKP_ActiveDefinition__r.AXF_SDF_PKL_Method__c,
        AXF_FSC_LKP_ActiveDefinition__r.AXF_SDF_NUM_TotalInstallments__c,
        AXF_FSC_LKP_ActiveDefinition__r.AXF_SDF_NUM_PeriodMonths__c
      FROM AXF_OBJ_FinancialSchedule__c
      WHERE Id = :first.scheduleId
    ];
    System.assertEquals('ACTIVE', root.AXF_FSC_PKL_State__c);
    System.assertEquals(true, root.AXF_FSC_BOL_GenerationEnabled__c);
    System.assertEquals(
      'PRICE',
      root.AXF_FSC_LKP_ActiveDefinition__r.AXF_SDF_PKL_Method__c
    );
    System.assertEquals(
      4,
      root.AXF_FSC_LKP_ActiveDefinition__r.AXF_SDF_NUM_TotalInstallments__c
    );
    System.assertEquals(
      1,
      root.AXF_FSC_LKP_ActiveDefinition__r.AXF_SDF_NUM_PeriodMonths__c
    );
  }

  @IsTest
  static void sameKeyUnderAnotherCalendarConflicts() {
    Account a = holder();
    authorize(a.Id);
    String gk = 'gk-calendar-01';
    AXF_CLS_ScheduleService.save(saveInput(a.Id, gk));

    AXF_CLS_ScheduleService.SaveInput moved = saveInput(a.Id, gk);
    moved.plan.firstDueDate = Date.newInstance(2026, 4, 15);
    AXF_CLS_ScheduleService.SaveResult r = AXF_CLS_ScheduleService.save(moved);

    System.assertEquals('CONFLICT', r.outcome);
    System.assertEquals(
      1,
      [SELECT COUNT() FROM AXF_OBJ_FinancialSchedule__c],
      'nenhum segundo cronograma com a mesma chave'
    );
  }

  @IsTest
  static void legacyGroupKeepsItsReplayAnswer() {
    Account a = holder();
    authorize(a.Id);
    String gk = 'gk-legacy-001';
    ALT_CLS_AmortizationSchedule.ScheduleResult plan = AXF_CLS_ScheduleService.plan(
      priceplan()
    );
    List<AXF_OBJ_FinancialTransaction__c> rows = new List<AXF_OBJ_FinancialTransaction__c>();
    for (ALT_CLS_AmortizationSchedule.Occurrence o : plan.occurrences) {
      rows.add(
        new AXF_OBJ_FinancialTransaction__c(
          AXF_FTX_LKP_Account__c = a.Id,
          AXF_FTX_PKL_Direction__c = 'DEBIT',
          AXF_FTX_NUM_Magnitude__c = o.payment,
          AXF_FTX_TXT_CurrencyIsoCode__c = 'BRL',
          AXF_FTX_DAT_DueDate__c = Date.valueOf(o.dueDate),
          AXF_FTX_DAT_PurchaseDate__c = Date.valueOf(o.dueDate),
          AXF_FTX_PKL_Status__c = 'PLANNED',
          AXF_FTX_EXI_ClientRequestId__c = gk + '-' + o.sequence,
          AXF_FTX_TXT_ScheduleGroupKey__c = gk,
          AXF_FTX_NUM_Sequence__c = o.sequence,
          AXF_FTX_PKL_Modality__c = 'PRICE'
        )
      );
    }
    insert rows;

    AXF_CLS_ScheduleService.SaveResult same = AXF_CLS_ScheduleService.save(
      saveInput(a.Id, gk)
    );
    AXF_CLS_ScheduleService.SaveInput changed = saveInput(a.Id, gk);
    changed.plan.principal = 2000.00;
    AXF_CLS_ScheduleService.SaveResult other = AXF_CLS_ScheduleService.save(
      changed
    );

    System.assertEquals('ALREADY', same.outcome);
    System.assertEquals('CONFLICT', other.outcome);
    System.assertEquals(
      0,
      [SELECT COUNT() FROM AXF_OBJ_FinancialSchedule__c],
      'grupo legado não é adotado'
    );
  }

  @IsTest
  static void originAndDescriptionReachTheInstallments() {
    Account a = holder();
    authorize(a.Id);
    AXF_OBJ_BankAccount__c cash = new AXF_OBJ_BankAccount__c(
      AXF_BA_LKP_Account__c = a.Id,
      AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_BA_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BA_TXT_Type__c = 'WALLET',
      AXF_BA_NUM_Version__c = 1
    );
    insert cash;
    AXF_CLS_ScheduleService.SaveInput s = saveInput(a.Id, 'gk-origin-0001');
    s.plan.modality = 'INSTALLMENT';
    s.plan.periodRate = null;
    s.bankAccountId = cash.Id;
    s.description = 'Geladeira';

    AXF_CLS_ScheduleService.SaveResult r = AXF_CLS_ScheduleService.save(s);

    System.assertEquals('SAVED', r.outcome, r.message);
    for (AXF_OBJ_FinancialTransaction__c row : [
      SELECT
        AXF_FTX_LKP_BankAccount__c,
        AXF_FTX_TXT_Description__c,
        AXF_FTX_NUM_Magnitude__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE AXF_FTX_LKP_Schedule__c = :r.scheduleId
    ]) {
      System.assertEquals(cash.Id, row.AXF_FTX_LKP_BankAccount__c);
      System.assertEquals('Geladeira', row.AXF_FTX_TXT_Description__c);
      System.assertEquals(250.00, row.AXF_FTX_NUM_Magnitude__c);
    }
  }

  @IsTest
  static void differentPlanUnderSameKeyConflicts() {
    Account a = holder();
    authorize(a.Id);
    String gk = 'gk-conflict-01';

    AXF_CLS_ScheduleService.save(saveInput(a.Id, gk));

    AXF_CLS_ScheduleService.SaveInput changed = saveInput(a.Id, gk);
    changed.plan.principal = 2000.00;
    AXF_CLS_ScheduleService.SaveResult r = AXF_CLS_ScheduleService.save(
      changed
    );

    System.assertEquals('CONFLICT', r.outcome);
    System.assertEquals(
      4,
      occCount(gk),
      'conflito preserva o rascunho, não sobrescreve'
    );
  }

  @IsTest
  static void unauthorizedAccountIsForbidden() {
    Account a = holder();
    AXF_CLS_ScheduleService.authorizedOverride = new Set<Id>();
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>();

    AXF_CLS_ScheduleService.SaveResult r = AXF_CLS_ScheduleService.save(
      saveInput(a.Id, 'gk-forbid-01')
    );

    System.assertEquals('FORBIDDEN', r.outcome);
    System.assertEquals(0, occCount('gk-forbid-01'));
  }

  @IsTest
  static void blockedModalityIsNotPersisted() {
    Account a = holder();
    authorize(a.Id);
    AXF_CLS_ScheduleService.SaveInput s = saveInput(a.Id, 'gk-consorcio-1');
    s.plan.modality = 'CONSORCIO';

    AXF_CLS_ScheduleService.SaveResult r = AXF_CLS_ScheduleService.save(s);

    System.assertEquals('BLOCKED', r.outcome);
    System.assert(r.message.contains('AXF-97'));
    System.assertEquals(0, occCount('gk-consorcio-1'));
  }

  @IsTest
  static void invalidGroupKeyIsRejected() {
    Account a = holder();
    authorize(a.Id);
    AXF_CLS_ScheduleService.SaveInput s = saveInput(
      a.Id,
      'this-group-key-is-way-too-long-to-fit'
    );

    AXF_CLS_ScheduleService.SaveResult r = AXF_CLS_ScheduleService.save(s);

    System.assertEquals('INVALID', r.outcome);
  }

  @IsTest
  static void controllerListsAuthorizedContexts() {
    Account a = holder();

    List<AXF_CLS_AuthorizedContextService.ContextView> rows = AXF_CLS_CTRL_ScheduleWizard.authorizedContexts();

    Boolean found = false;
    for (AXF_CLS_AuthorizedContextService.ContextView v : rows) {
      if (v.accountId == a.Id) {
        found = true;
      }
    }
    System.assertEquals(
      true,
      found,
      'o titular criado deve aparecer como contexto autorizado'
    );
  }

  @IsTest
  static void controllerDelegates() {
    Account a = holder();
    authorize(a.Id);

    ALT_CLS_AmortizationSchedule.ScheduleResult preview = AXF_CLS_CTRL_ScheduleWizard.planSchedule(
      'PRICE',
      1000.00,
      4,
      0.02,
      Date.newInstance(2026, 3, 15),
      null,
      null,
      null
    );
    AXF_CLS_ScheduleService.SaveResult saved = AXF_CLS_CTRL_ScheduleWizard.saveSchedule(
      JSON.serialize(priceplan()),
      a.Id,
      'DEBIT',
      'BRL',
      'gk-ctrl-0001',
      null,
      null,
      'Carro'
    );

    System.assertEquals('OK', preview.outcome);
    System.assertEquals('SAVED', saved.outcome, saved.message);
  }

  @IsTest
  static void everyModalityPersistsTheMagnitudesOfThePreview() {
    Account a = holder();
    authorize(a.Id);
    List<AXF_CLS_ScheduleService.PlanInput> plans = new List<AXF_CLS_ScheduleService.PlanInput>();
    AXF_CLS_ScheduleService.PlanInput recurring = priceplan();
    recurring.modality = 'RECURRING';
    recurring.principal = null;
    recurring.periodRate = null;
    recurring.fixedValue = 89.90;
    plans.add(recurring);
    AXF_CLS_ScheduleService.PlanInput price = priceplan();
    price.flatFeePerInstallment = 5;
    price.upfrontFee = 10;
    plans.add(price);
    AXF_CLS_ScheduleService.PlanInput sac = priceplan();
    sac.modality = 'SAC';
    sac.flatFeePerInstallment = 2.5;
    sac.upfrontFee = 7;
    plans.add(sac);

    Integer index = 0;
    for (AXF_CLS_ScheduleService.PlanInput plan : plans) {
      AXF_CLS_ScheduleService.SaveInput s = saveInput(
        a.Id,
        'gk-mod-' + index++
      );
      s.plan = plan;
      AXF_CLS_ScheduleService.SaveResult r = AXF_CLS_ScheduleService.save(s);
      System.assertEquals('SAVED', r.outcome, plan.modality + ': ' + r.message);
      ALT_CLS_AmortizationSchedule.ScheduleResult preview = AXF_CLS_ScheduleService.plan(
        plan
      );
      List<AXF_OBJ_FinancialTransaction__c> rows = [
        SELECT
          AXF_FTX_NUM_Magnitude__c,
          AXF_FTX_NUM_FeePortion__c,
          AXF_FTX_PKL_Modality__c
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE AXF_FTX_LKP_Schedule__c = :r.scheduleId
        ORDER BY AXF_FTX_NUM_Sequence__c
      ];
      System.assertEquals(preview.occurrences.size(), rows.size());
      for (Integer i = 0; i < rows.size(); i++) {
        System.assertEquals(
          preview.occurrences[i].payment,
          rows[i].AXF_FTX_NUM_Magnitude__c,
          plan.modality + ' parcela ' + (i + 1)
        );
        System.assertEquals(
          preview.occurrences[i].feePortion,
          rows[i].AXF_FTX_NUM_FeePortion__c
        );
        System.assertEquals(plan.modality, rows[i].AXF_FTX_PKL_Modality__c);
      }
    }
  }

  @IsTest
  static void sameKeyOfAnotherHolderIsNeitherAConflictNorDisclosed() {
    Account mine = holder();
    Account foreign = holder();
    AXF_CLS_ScheduleService.authorizedOverride = new Set<Id>{
      mine.Id,
      foreign.Id
    };
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      mine.Id,
      foreign.Id
    };
    AXF_CLS_ScheduleService.SaveResult theirs = AXF_CLS_ScheduleService.save(
      saveInput(foreign.Id, 'gk-shared-0001')
    );
    System.assertEquals('SAVED', theirs.outcome, theirs.message);

    AXF_CLS_ScheduleService.SaveInput moved = saveInput(
      mine.Id,
      'gk-shared-0001'
    );
    moved.plan.firstDueDate = Date.newInstance(2026, 4, 15);
    AXF_CLS_ScheduleService.SaveResult ours = AXF_CLS_ScheduleService.save(
      moved
    );
    System.assertEquals('SAVED', ours.outcome, ours.message);
    System.assertNotEquals(theirs.scheduleId, ours.scheduleId);

    AXF_CLS_ScheduleService.SaveInput changed = saveInput(
      mine.Id,
      'gk-shared-0001'
    );
    AXF_CLS_ScheduleService.SaveResult conflict = AXF_CLS_ScheduleService.save(
      changed
    );
    System.assertEquals('CONFLICT', conflict.outcome);
    System.assertEquals(null, conflict.scheduleId, 'nenhum Id no conflito');
  }
}
