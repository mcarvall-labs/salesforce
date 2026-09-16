/**
 * AXF-20 — plan (preview) and save (draft) an amortization/recurrence schedule as
 * planned `AXF_OBJ_FinancialTransaction__c` records (Status = PLANNED).
 *
 * Formula authority: ALT_CLS_AmortizationSchedule / AMORTIZATION-POLICY.md v1.0.0.
 * Authorization: the target Account must be one of the caller's authorized contexts
 * (AXF-3); ownership/sharing/CRUD/FLS are native (`as user`). No fact is published.
 * Idempotency (G6): occurrences share `AXF_FTX_TXT_ScheduleGroupKey__c`; each carries a
 * per-occurrence `AXF_FTX_EXI_ClientRequestId__c = groupKey-<seq>`. Re-saving the same
 * plan is a no-op; the same groupKey with a different plan is CONFLICT, never overwrite.
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

    // Internal idempotency check — SYSTEM_MODE because the new schedule fields' FLS
    // rides AXF_PS_FinancialEntry (LWC/LDS use); the authority gate above is isAuthorized().
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

    List<AXF_OBJ_FinancialTransaction__c> rows = new List<AXF_OBJ_FinancialTransaction__c>();
    for (ALT_CLS_AmortizationSchedule.Occurrence o : schedule.occurrences) {
      rows.add(
        new AXF_OBJ_FinancialTransaction__c(
          AXF_FTX_LKP_Account__c = input.accountId,
          AXF_FTX_PKL_Direction__c = input.direction.toUpperCase(),
          AXF_FTX_NUM_Magnitude__c = o.payment,
          AXF_FTX_TXT_CurrencyIsoCode__c = input.currencyIsoCode.toUpperCase(),
          AXF_FTX_DAT_DueDate__c = Date.valueOf(o.dueDate),
          AXF_FTX_DAT_PurchaseDate__c = Date.valueOf(o.dueDate),
          AXF_FTX_PKL_Status__c = 'PLANNED',
          AXF_FTX_CHK_IsEstimated__c = false,
          AXF_FTX_NUM_Version__c = 0,
          AXF_FTX_EXI_ClientRequestId__c = input.groupKey +
            '-' +
            String.valueOf(o.sequence).leftPad(4, '0'),
          AXF_FTX_TXT_ScheduleGroupKey__c = input.groupKey,
          AXF_FTX_NUM_Sequence__c = o.sequence,
          AXF_FTX_PKL_Modality__c = schedule.modality,
          AXF_FTX_NUM_PrincipalPortion__c = o.principalPortion,
          AXF_FTX_NUM_InterestPortion__c = o.interestPortion,
          AXF_FTX_NUM_FeePortion__c = o.feePortion,
          AXF_FTX_NUM_ClosingBalance__c = o.closingBalance,
          AXF_FTX_CHK_RoundingResidual__c = o.roundingResidualApplied
        )
      );
    }

    // Write in SYSTEM_MODE: the authority gate is isAuthorized() above (authorized
    // context, AXF-3); these internal schedule fields' FLS is for LWC/LDS use.
    // Matches AXF-88/85/15 internal-workflow pattern.
    try {
      Database.insert(rows, AccessLevel.SYSTEM_MODE);
    } catch (Exception e) {
      return fail(r, 'INVALID', 'Não foi possível salvar o cronograma.');
    }

    r.outcome = 'SAVED';
    r.occurrenceCount = rows.size();
    r.message = rows.size() + ' ocorrência(s) planejada(s).';
    return r;
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
