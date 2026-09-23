/**
 * AXF-20 — plan (preview) and save (draft) an amortization/recurrence schedule as
 * planned `AXF_OBJ_FinancialTransaction__c` records (Status = PLANNED).
 *
 * Formula authority: ALT_CLS_AmortizationSchedule / AMORTIZATION-POLICY.md v1.0.0.
 * Authorization: the target Account must be one of the caller's authorized contexts
 * (AXF-3); ownership/sharing/CRUD/FLS are native (`as user`). No fact is published.
 * Idempotency (G6): the groupKey identifies the plan. Re-saving the same plan is a no-op
 * (ALREADY); the same groupKey with a different plan is CONFLICT, never overwrite.
 *
 * AXF-156: PRICE, SAC, INSTALLMENT and RECURRING (always with a term) are persisted as a
 * managed AXF-103 schedule through `ALT_CLS_FinancialScheduleService.createSchedule` — same
 * AXF-20 formula, `PeriodMonths = 1`, generation enabled, optional origin/description applied
 * to the installments. The groupKey becomes the schedule's legacy group key (part of its
 * identity), so a replay is the command replay. Groups saved before AXF-156 (FTX rows carrying
 * `AXF_FTX_TXT_ScheduleGroupKey__c`) keep their original ALREADY/CONFLICT answer.
 */
public with sharing class AXF_CLS_ScheduleService {
  private static final Set<String> DIRECTIONS = new Set<String>{
    'CREDIT',
    'DEBIT'
  };

  public class PlanInput {
    @AuraEnabled
    public String modality;
    @AuraEnabled
    public Decimal principal;
    @AuraEnabled
    public Integer installments;
    @AuraEnabled
    public Decimal periodRate;
    @AuraEnabled
    public Date firstDueDate;
    @AuraEnabled
    public Decimal fixedValue;
    @AuraEnabled
    public Decimal flatFeePerInstallment;
    @AuraEnabled
    public Decimal upfrontFee;
  }

  public class SaveInput {
    @AuraEnabled
    public PlanInput plan;
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String direction;
    @AuraEnabled
    public String currencyIsoCode;
    @AuraEnabled
    public String groupKey;
    /** AXF-156: optional origin handed over by the entry wizard (one of them). */
    @AuraEnabled
    public Id bankAccountId;
    @AuraEnabled
    public Id creditCardId;
    /** AXF-156: optional description applied to the installments. */
    @AuraEnabled
    public String description;
  }

  public class SaveResult {
    @AuraEnabled
    public String outcome;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public String groupKey;
    @AuraEnabled
    public Integer occurrenceCount = 0;
    @AuraEnabled
    public ALT_CLS_AmortizationSchedule.ScheduleResult schedule;
    /** AXF-156: the managed schedule that holds the installments. */
    @AuraEnabled
    public Id scheduleId;
  }

  @TestVisible
  private static Set<Id> authorizedOverride;

  public static ALT_CLS_AmortizationSchedule.ScheduleResult plan(
    PlanInput input
  ) {
    return ALT_CLS_AmortizationSchedule.generate(toScheduleInput(input));
  }

  public static SaveResult save(SaveInput input) {
    SaveResult r = new SaveResult();
    if (
      input == null ||
      input.accountId == null ||
      !isAuthorized(input.accountId)
    ) {
      return fail(
        r,
        'FORBIDDEN',
        'Você não tem acesso a esta entidade titular.'
      );
    }
    if (
      String.isBlank(input.direction) ||
      !DIRECTIONS.contains(input.direction.toUpperCase())
    ) {
      return fail(r, 'INVALID', 'Natureza (CREDIT/DEBIT) inválida.');
    }
    if (
      String.isBlank(input.currencyIsoCode) ||
      input.currencyIsoCode.trim().length() != 3
    ) {
      return fail(r, 'INVALID', 'Moeda inválida.');
    }
    if (String.isBlank(input.groupKey) || input.groupKey.length() > 24) {
      return fail(r, 'INVALID', 'Chave do cronograma inválida.');
    }

    ALT_CLS_AmortizationSchedule.ScheduleResult schedule = ALT_CLS_AmortizationSchedule.generate(
      toScheduleInput(input.plan)
    );
    r.schedule = schedule;
    r.groupKey = input.groupKey;
    if (schedule.outcome != 'OK') {
      r.outcome = schedule.outcome;
      r.message = schedule.message;
      return r;
    }

    // Legacy (pre-AXF-156) group under this key: answer as AXF-20 did, never write again.
    // SYSTEM_MODE because the schedule fields' FLS rides AXF_PS_FinancialEntry (LWC/LDS use);
    // the authority gate above is isAuthorized().
    List<AXF_OBJ_FinancialTransaction__c> existing = [
      SELECT
        Id,
        AXF_FTX_PKL_Modality__c,
        AXF_FTX_NUM_Sequence__c,
        AXF_FTX_NUM_Magnitude__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE AXF_FTX_TXT_ScheduleGroupKey__c = :input.groupKey
      WITH SYSTEM_MODE
      ORDER BY AXF_FTX_NUM_Sequence__c
    ];
    if (!existing.isEmpty()) {
      Boolean samePlan =
        existing.size() == schedule.occurrences.size() &&
        existing[0].AXF_FTX_PKL_Modality__c == schedule.modality &&
        existing[0].AXF_FTX_NUM_Magnitude__c == schedule.occurrences[0].payment;
      if (samePlan) {
        r.outcome = 'ALREADY';
        r.occurrenceCount = existing.size();
        r.message = 'Cronograma já salvo — nada foi duplicado.';
      } else {
        r.outcome = 'CONFLICT';
        r.message = 'Já existe um cronograma diferente com esta chave. Gere uma nova.';
      }
      return r;
    }

    ALT_CLS_FinancialScheduleService.CreateInput create = toCreateInput(
      input,
      schedule
    );
    // The same groupKey under another calendar would be another schedule identity: it is the
    // same key with a different plan, so CONFLICT before any write. Only this holder's schedules
    // count, and no schedule Id is returned on a conflict.
    for (AXF_OBJ_FinancialSchedule__c root : [
      SELECT Id, AXF_FSC_EXI_ScheduleKey__c
      FROM AXF_OBJ_FinancialSchedule__c
      WHERE
        AXF_FSC_TXT_LegacyGroupKey__c = :input.groupKey
        AND AXF_FSC_LKP_Account__c = :input.accountId
      WITH SYSTEM_MODE
      LIMIT 1
    ]) {
      String expectedKey;
      try {
        expectedKey = ALT_CLS_FinancialScheduleService.previewScheduleKey(
          create
        );
      } catch (Exception invalid) {
        expectedKey = null;
      }
      if (expectedKey != root.AXF_FSC_EXI_ScheduleKey__c) {
        return fail(
          r,
          'CONFLICT',
          'Já existe um cronograma diferente com esta chave. Gere uma nova.'
        );
      }
    }

    ALT_CLS_FinancialScheduleService.CreateResult created = ALT_CLS_FinancialScheduleService.createSchedule(
      create
    );
    r.occurrenceCount = created.occurrenceCount == null
      ? 0
      : created.occurrenceCount;
    switch on created.outcome {
      when 'CREATED' {
        r.scheduleId = created.scheduleId;
        r.outcome = 'SAVED';
        r.message = r.occurrenceCount + ' ocorrência(s) planejada(s).';
      }
      when 'REPLAY' {
        r.scheduleId = created.scheduleId;
        r.outcome = 'ALREADY';
        r.message = 'Cronograma já salvo — nada foi duplicado.';
      }
      when 'CONFLICT' {
        r.outcome = 'CONFLICT';
        r.message = 'Já existe um cronograma diferente com esta chave. Gere uma nova.';
      }
      when 'FORBIDDEN' {
        r.outcome = 'FORBIDDEN';
        r.message = created.message;
      }
      when else {
        r.outcome = 'INVALID';
        r.message = String.isBlank(created.message)
          ? 'Não foi possível salvar o cronograma.'
          : created.message;
      }
    }
    return r;
  }

  /**
   * @description The AXF-20 plan as an AXF-103 create command: same formula inputs, monthly
   * period, holder, direction, currency, optional origin/description and generation enabled.
   */
  private static ALT_CLS_FinancialScheduleService.CreateInput toCreateInput(
    SaveInput input,
    ALT_CLS_AmortizationSchedule.ScheduleResult schedule
  ) {
    PlanInput plan = input.plan;
    ALT_CLS_FinancialScheduleService.CreateInput create = new ALT_CLS_FinancialScheduleService.CreateInput();
    create.accountId = input.accountId;
    create.direction = input.direction.toUpperCase();
    create.currencyIsoCode = input.currencyIsoCode.trim().toUpperCase();
    create.method = schedule.modality;
    create.totalInstallments = plan.installments;
    create.firstSequence = 1;
    create.firstDueDate = plan.firstDueDate;
    create.periodMonths = 1;
    create.principal = plan.principal;
    create.periodRate = plan.periodRate;
    create.fixedValue = plan.fixedValue;
    create.recurringFee = plan.flatFeePerInstallment;
    create.upfrontFee = plan.upfrontFee;
    create.legacyGroupKey = input.groupKey;
    create.bankAccountId = input.bankAccountId;
    create.creditCardId = input.creditCardId;
    create.description = input.description;
    create.generationEnabled = true;
    return create;
  }

  private static ALT_CLS_AmortizationSchedule.ScheduleInput toScheduleInput(
    PlanInput p
  ) {
    if (p == null) {
      return null;
    }
    ALT_CLS_AmortizationSchedule.ScheduleInput s = new ALT_CLS_AmortizationSchedule.ScheduleInput();
    s.modality = p.modality;
    s.principal = p.principal;
    s.installments = p.installments;
    s.periodRate = p.periodRate;
    s.firstDueDate = p.firstDueDate;
    s.fixedValue = p.fixedValue;
    s.flatFeePerInstallment = p.flatFeePerInstallment;
    s.upfrontFee = p.upfrontFee;
    return s;
  }

  private static Boolean isAuthorized(Id accountId) {
    if (authorizedOverride != null) {
      return authorizedOverride.contains(accountId);
    }
    for (
      AXF_CLS_AuthorizedContextService.ContextView v : AXF_CLS_AuthorizedContextService.listAuthorizedContexts()
    ) {
      if (v.accountId == accountId) {
        return true;
      }
    }
    return false;
  }

  private static SaveResult fail(SaveResult r, String outcome, String message) {
    r.outcome = outcome;
    r.message = message;
    return r;
  }
}
