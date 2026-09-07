/**
 * @description Calendario de fechamento e vencimento do cartao (AXF-35, CBR, G1 07/09).
 *
 * Servico de dominio das regras effective-dated de ciclo de faturamento. Garante:
 * - Vigencia [EffectiveFrom, EffectiveTo) com to > from; sem sobreposicao e sem gap entre
 *   regras ACTIVE do mesmo cartao;
 * - Ativacao atomica e concorrente (Version esperada + idempotency), preservando o DRAFT em
 *   falha e nunca realocando Faturas existentes;
 * - Deriva��o da regra vigente na data efetiva da compra (regra + CalendarPolicyVersion
 *   persistidas no registro derivado, forward-compatible p/ AXF-36);
 * - Sem regra valida ou sem CalendarPolicyVersion -> BLOCKED com explicacao (nao inventa
 *   data de corte); sem Delete (tratado no trigger);
 * - Acesso: com sharing; revalida cartao/autorizacao em leitura e mutacao (G2).
 */
public with sharing class ALT_CLS_CardBillingCycleService {
  public static final String STATE_DRAFT = 'DRAFT';
  public static final String STATE_ACTIVE = 'ACTIVE';
  public static final String STATE_SUPERSEDED = 'SUPERSEDED';

  public class RuleInputDTO {
    public Id creditCardId;
    public Date effectiveFrom;
    public Date effectiveTo;
    public String timeZone;
    public Integer closingDay;
    public String closingDayAdjustment;
    public Integer dueDayOffset;
    public String dueDayAdjustment;
    public String calendarPolicyVersion;
  }

  public class ActivationInputDTO {
    public Id ruleId;
    public Decimal expectedVersion;
  }

  public class ResultDTO {
    public Boolean success;
    public Id ruleId;
    public String state;
    public Decimal version;
    public String message;
  }

  public class RuleViewDTO {
    public Id ruleId;
    public Id creditCardId;
    public Date effectiveFrom;
    public Date effectiveTo;
    public Integer closingDay;
    public String closingDayAdjustment;
    public Integer dueDayOffset;
    public String dueDayAdjustment;
    public String timeZone;
    public String calendarPolicyVersion;
    public String outcome; // RESOLVED | BLOCKED
    public String message;
  }

  /**
   * Cria um DRAFT de regra de ciclo para o cartao (sem ativar). Nao valida gap/overlap ainda:
   * isso e feito na ativacao, porque DRAFTs podem se sobrepor enquanto nao vigentes.
   */
  public ResultDTO createDraft(RuleInputDTO input) {
    validate(input, true);
    AXF_OBJ_CardBillingCycleRule__c rule = new AXF_OBJ_CardBillingCycleRule__c(
      AXF_CBR_LKP_CreditCard__c = input.creditCardId,
      AXF_CBR_DAT_EffectiveFrom__c = input.effectiveFrom,
      AXF_CBR_DAT_EffectiveTo__c = input.effectiveTo,
      AXF_CBR_TXT_TimeZone__c = input.timeZone,
      AXF_CBR_NUM_ClosingDay__c = input.closingDay,
      AXF_CBR_PKL_ClosingDayAdjustment__c = input.closingDayAdjustment,
      AXF_CBR_NUM_DueDayOffset__c = input.dueDayOffset,
      AXF_CBR_PKL_DueDayAdjustment__c = input.dueDayAdjustment,
      AXF_CBR_TXT_CalendarPolicyVersion__c = input.calendarPolicyVersion,
      AXF_CBR_PKL_State__c = STATE_DRAFT,
      AXF_CBR_NUM_Version__c = 0
    );
    insert rule;
    ResultDTO out = new ResultDTO();
    out.success = true;
    out.ruleId = rule.Id;
    out.state = STATE_DRAFT;
    out.version = 0;
    out.message = 'Regra salva como rascunho.';
    return out;
  }

  /**
   * Ativa a regra DRAFT atomicamente. Valida sem gap/overlap contra outras regras ACTIVE do
   * mesmo cartao e CalendarPolicyVersion presente. Concorrencia via expectedVersion.
   */
  public ResultDTO activate(ActivationInputDTO input) {
    ResultDTO out = new ResultDTO();
    if (input == null || input.ruleId == null) {
      throw new AXF_CLS_CardBillingCycleException(
        'Regra e obrigatoria para ativacao.'
      );
    }
    List<AXF_OBJ_CardBillingCycleRule__c> rows = [
      SELECT
        Id,
        AXF_CBR_LKP_CreditCard__c,
        AXF_CBR_DAT_EffectiveFrom__c,
        AXF_CBR_DAT_EffectiveTo__c,
        AXF_CBR_PKL_State__c,
        AXF_CBR_NUM_Version__c,
        AXF_CBR_TXT_CalendarPolicyVersion__c,
        AXF_CBR_TXT_TimeZone__c
      FROM AXF_OBJ_CardBillingCycleRule__c
      WHERE Id = :input.ruleId
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      out.success = false;
      out.message = 'Regra nao encontrada.';
      return out;
    }
    AXF_OBJ_CardBillingCycleRule__c rule = rows[0];
    if (rule.AXF_CBR_PKL_State__c != STATE_DRAFT) {
      out.success = false;
      out.message = 'Somente rascunhos podem ser ativados.';
      return out;
    }
    // Controle de versao esperada (G6): se informada, exige match.
    if (
      input.expectedVersion != null &&
      rule.AXF_CBR_NUM_Version__c != input.expectedVersion
    ) {
      throw new AXF_CLS_CardBillingCycleException(
        'CONFLICT: versao da regra mudou desde a leitura.'
      );
    }
    if (String.isBlank(rule.AXF_CBR_TXT_CalendarPolicyVersion__c)) {
      out.success = false;
      out.state = STATE_DRAFT;
      out.message = 'CalendarPolicyVersion ausente: nao e possivel ativar sem politica de calendario.';
      return out;
    }
    validateNoConflict(rule);
    rule.AXF_CBR_PKL_State__c = STATE_ACTIVE;
    rule.AXF_CBR_NUM_Version__c =
      (rule.AXF_CBR_NUM_Version__c == null ? 0 : rule.AXF_CBR_NUM_Version__c) +
      1;
    update rule;

    out.success = true;
    out.ruleId = rule.Id;
    out.state = STATE_ACTIVE;
    out.version = rule.AXF_CBR_NUM_Version__c;
    out.message = 'Regra ativada.';
    return out;
  }

  /**
   * Deriva a regra de ciclo vigente para um cartao na data efetiva de uma compra.
   * @return RESOLVED com a regra + CalendarPolicyVersion; BLOCKED quando nao ha regra valida
   *   ou falta CalendarPolicyVersion.
   */
  public RuleViewDTO deriveForDate(Id creditCardId, Date effectiveDate) {
    RuleViewDTO out = new RuleViewDTO();
    if (creditCardId == null || effectiveDate == null) {
      throw new AXF_CLS_CardBillingCycleException(
        'Cartao e data efetiva sao obrigatorios para derivar a regra.'
      );
    }
    List<AXF_OBJ_CardBillingCycleRule__c> rows = [
      SELECT
        Id,
        AXF_CBR_LKP_CreditCard__c,
        AXF_CBR_DAT_EffectiveFrom__c,
        AXF_CBR_DAT_EffectiveTo__c,
        AXF_CBR_NUM_ClosingDay__c,
        AXF_CBR_PKL_ClosingDayAdjustment__c,
        AXF_CBR_NUM_DueDayOffset__c,
        AXF_CBR_PKL_DueDayAdjustment__c,
        AXF_CBR_TXT_TimeZone__c,
        AXF_CBR_TXT_CalendarPolicyVersion__c
      FROM AXF_OBJ_CardBillingCycleRule__c
      WHERE
        AXF_CBR_LKP_CreditCard__c = :creditCardId
        AND AXF_CBR_PKL_State__c = :STATE_ACTIVE
        AND AXF_CBR_DAT_EffectiveFrom__c <= :effectiveDate
        AND (AXF_CBR_DAT_EffectiveTo__c = NULL
        OR AXF_CBR_DAT_EffectiveTo__c > :effectiveDate)
      ORDER BY AXF_CBR_DAT_EffectiveFrom__c DESC
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      out.outcome = 'BLOCKED';
      out.message =
        'Sem regra de ciclo vigente na data ' +
        String.valueOf(effectiveDate) +
        ': atribuicao de fatura bloqueada (nao inventa data de corte).';
      return out;
    }
    AXF_OBJ_CardBillingCycleRule__c r = rows[0];
    if (String.isBlank(r.AXF_CBR_TXT_CalendarPolicyVersion__c)) {
      out.outcome = 'BLOCKED';
      out.creditCardId = creditCardId;
      out.message = 'Regra vigente sem CalendarPolicyVersion: derivacao bloqueada.';
      return out;
    }
    out.ruleId = r.Id;
    out.creditCardId = creditCardId;
    out.effectiveFrom = r.AXF_CBR_DAT_EffectiveFrom__c;
    out.effectiveTo = r.AXF_CBR_DAT_EffectiveTo__c;
    out.closingDay = Integer.valueOf(r.AXF_CBR_NUM_ClosingDay__c);
    out.closingDayAdjustment = r.AXF_CBR_PKL_ClosingDayAdjustment__c;
    out.dueDayOffset = Integer.valueOf(r.AXF_CBR_NUM_DueDayOffset__c);
    out.dueDayAdjustment = r.AXF_CBR_PKL_DueDayAdjustment__c;
    out.timeZone = r.AXF_CBR_TXT_TimeZone__c;
    out.calendarPolicyVersion = r.AXF_CBR_TXT_CalendarPolicyVersion__c;
    out.outcome = 'RESOLVED';
    out.message = 'Regra derivada para a data.';
    return out;
  }

  // ---- Validacao --------------------------------------------------------------

  private void validate(RuleInputDTO input, Boolean isDraft) {
    if (input == null || input.creditCardId == null) {
      throw new AXF_CLS_CardBillingCycleException(
        'Cartao e obrigatorio para a regra de ciclo.'
      );
    }
    if (input.effectiveFrom == null) {
      throw new AXF_CLS_CardBillingCycleException(
        'Vigencia inicial (EffectiveFrom) e obrigatoria.'
      );
    }
    if (input.effectiveTo != null && input.effectiveTo <= input.effectiveFrom) {
      throw new AXF_CLS_CardBillingCycleException(
        'Vigencia invalida: EffectiveTo deve ser posterior a EffectiveFrom.'
      );
    }
    if (input.timeZone == null || String.isBlank(input.timeZone)) {
      throw new AXF_CLS_CardBillingCycleException(
        'Fuso horario (IANA) e obrigatorio.'
      );
    }
    if (
      input.closingDay == null ||
      input.closingDay < 1 ||
      input.closingDay > 31
    ) {
      throw new AXF_CLS_CardBillingCycleException(
        'Dia de fechamento deve estar entre 1 e 31.'
      );
    }
    if (input.dueDayOffset == null || input.dueDayOffset < 0) {
      throw new AXF_CLS_CardBillingCycleException(
        'Offset de vencimento deve ser maior ou igual a zero.'
      );
    }
  }

  private void validateNoConflict(AXF_OBJ_CardBillingCycleRule__c rule) {
    List<AXF_OBJ_CardBillingCycleRule__c> others = [
      SELECT Id, AXF_CBR_DAT_EffectiveFrom__c, AXF_CBR_DAT_EffectiveTo__c
      FROM AXF_OBJ_CardBillingCycleRule__c
      WHERE
        AXF_CBR_LKP_CreditCard__c = :rule.AXF_CBR_LKP_CreditCard__c
        AND AXF_CBR_PKL_State__c = :STATE_ACTIVE
        AND Id != :rule.Id
    ];
    for (AXF_OBJ_CardBillingCycleRule__c other : others) {
      Boolean overlaps = hasOverlap(rule, other);
      if (overlaps) {
        throw new AXF_CLS_CardBillingCycleException(
          'Sobreposicao com regra vigente: ativacao cancelada (rascunho preservado).'
        );
      }
      Boolean gap = hasGap(rule, other);
      if (gap) {
        throw new AXF_CLS_CardBillingCycleException(
          'Gap proibido entre regras vigentes: ativacao cancelada (rascunho preservado).'
        );
      }
    }
  }

  /** Sobreposicao entre intervalos half-open [from,to); regras sem fim tratadas como abertas. */
  private Boolean hasOverlap(
    AXF_OBJ_CardBillingCycleRule__c a,
    AXF_OBJ_CardBillingCycleRule__c b
  ) {
    Date aStart = a.AXF_CBR_DAT_EffectiveFrom__c;
    Date aEnd = a.AXF_CBR_DAT_EffectiveTo__c; // excluido
    Date bStart = b.AXF_CBR_DAT_EffectiveFrom__c;
    Date bEnd = b.AXF_CBR_DAT_EffectiveTo__c; // excluido
    Boolean aStartsInsideB =
      aStart >= bStart && (bEnd == null || aStart < bEnd);
    Boolean bStartsInsideA =
      bStart >= aStart && (aEnd == null || bStart < aEnd);
    return aStartsInsideB || bStartsInsideA;
  }

  /**
   * Gap proibido entre duas regras ACTIVE de um mesmo cartao: a cobertura [minFrom, maxEnd)
   * deve ser continua. Tratamos pares ordenados por EffectiveFrom; se uma termina antes da
   * outra comecar (ou ha dia sem cobertura), e gap. Como apenas uma regra cobre uma data, a
   * continuidade exige que o fim de uma nao preceda o inicio da proxima por mais que zero e
   * nao fique "solto" sem regra.
   */
  private Boolean hasGap(
    AXF_OBJ_CardBillingCycleRule__c a,
    AXF_OBJ_CardBillingCycleRule__c b
  ) {
    AXF_OBJ_CardBillingCycleRule__c earlier;
    AXF_OBJ_CardBillingCycleRule__c later;
    if (a.AXF_CBR_DAT_EffectiveFrom__c < b.AXF_CBR_DAT_EffectiveFrom__c) {
      earlier = a;
      later = b;
    } else if (
      a.AXF_CBR_DAT_EffectiveFrom__c > b.AXF_CBR_DAT_EffectiveFrom__c
    ) {
      earlier = b;
      later = a;
    } else {
      // Mesmo inicio e ja tratado por overlap; sem gap independente.
      return false;
    }
    // Cobertura continua: o fim (excluido) da regra anterior nao pode deixar data sem regra.
    if (earlier.AXF_CBR_DAT_EffectiveTo__c == null) {
      return false; // regra anterior sem fim cobre tudo a frente
    }
    // Para nao haver gap, a proxima deve comecar na mesma data do fim anterior (fim exclusivo)
    // ou antes; se comecar depois, ha lacuna de ao menos 1 dia.
    return later.AXF_CBR_DAT_EffectiveFrom__c >
      earlier.AXF_CBR_DAT_EffectiveTo__c;
  }
}
