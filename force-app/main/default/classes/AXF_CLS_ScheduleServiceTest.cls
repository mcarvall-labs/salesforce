/** @description AXF-20 — plan/save schedule as PLANNED FinancialTransaction drafts. */
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

  private static Integer occCount(String groupKey) {
    return [
      SELECT COUNT()
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE AXF_FTX_TXT_ScheduleGroupKey__c = :groupKey
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
    AXF_CLS_ScheduleService.authorizedOverride = new Set<Id>{ a.Id };
    String gk = 'gk-price-0001';

    AXF_CLS_ScheduleService.SaveResult first = AXF_CLS_ScheduleService.save(
      saveInput(a.Id, gk)
    );
    AXF_CLS_ScheduleService.SaveResult again = AXF_CLS_ScheduleService.save(
      saveInput(a.Id, gk)
    );

    System.assertEquals('SAVED', first.outcome, first.message);
    System.assertEquals(4, first.occurrenceCount);
    System.assertEquals('ALREADY', again.outcome);
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
        AXF_FTX_TXT_ScheduleGroupKey__c = :gk
        AND AXF_FTX_NUM_Sequence__c = 1
    ];
    System.assertEquals('PLANNED', seq1.AXF_FTX_PKL_Status__c);
    System.assertEquals('PRICE', seq1.AXF_FTX_PKL_Modality__c);
    System.assertEquals(262.62, seq1.AXF_FTX_NUM_Magnitude__c);
    System.assertEquals(242.62, seq1.AXF_FTX_NUM_PrincipalPortion__c);
    System.assertEquals(20.00, seq1.AXF_FTX_NUM_InterestPortion__c);
    System.assertEquals(757.38, seq1.AXF_FTX_NUM_ClosingBalance__c);
    System.assertEquals(gk + '-0001', seq1.AXF_FTX_EXI_ClientRequestId__c);
  }

  @IsTest
  static void differentPlanUnderSameKeyConflicts() {
    Account a = holder();
    AXF_CLS_ScheduleService.authorizedOverride = new Set<Id>{ a.Id };
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

    AXF_CLS_ScheduleService.SaveResult r = AXF_CLS_ScheduleService.save(
      saveInput(a.Id, 'gk-forbid-01')
    );

    System.assertEquals('FORBIDDEN', r.outcome);
    System.assertEquals(0, occCount('gk-forbid-01'));
  }

  @IsTest
  static void blockedModalityIsNotPersisted() {
    Account a = holder();
    AXF_CLS_ScheduleService.authorizedOverride = new Set<Id>{ a.Id };
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
    AXF_CLS_ScheduleService.authorizedOverride = new Set<Id>{ a.Id };
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
    AXF_CLS_ScheduleService.authorizedOverride = new Set<Id>{ a.Id };

    ALT_CLS_AmortizationSchedule.ScheduleResult preview = AXF_CLS_CTRL_ScheduleWizard.planSchedule(
      priceplan()
    );
    AXF_CLS_ScheduleService.SaveResult saved = AXF_CLS_CTRL_ScheduleWizard.saveSchedule(
      saveInput(a.Id, 'gk-ctrl-0001')
    );

    System.assertEquals('OK', preview.outcome);
    System.assertEquals('SAVED', saved.outcome, saved.message);
  }
}
