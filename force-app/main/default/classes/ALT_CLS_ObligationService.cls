/**
 * @description Realização ajustada, ajustes de obrigação com sinal e revisão de referência
 * recorrente (AXF-104). Evolução aditiva do AXF-25 sobre a fundação AXF-103.
 *
 * Invariantes implementadas aqui:
 * - B = base vigente autoritativa do AXF-103 (`CurrentBasis`, senão a magnitude original
 *   imutável), preservada separadamente da previsão original e congelada no primeiro uso
 *   financeiro. A liquidação nunca é limitada pela estimativa original obsoleta.
 * - A = soma dos valores com sinal dos ajustes; uma compensação carrega o valor exatamente
 *   oposto, então a soma já é o líquido válido. E = B + A é a obrigação efetiva; N = alocações
 *   válidas menos compensações; R = E - N, nunca silenciosamente truncado.
 * - Um ajuste é não monetário: altera E, nunca o caixa, a disponibilidade da fonte nem os
 *   totais realizados. Um valor menor sozinho nunca marca o restante como pago.
 * - Uma referência recorrente só nasce de uma parcela INTEIRA explicada e integralmente
 *   liquidada, com cobertura válida e cronograma estimado, e segue a sequência absoluta de
 *   parcelas — nunca a hora de chegada.
 */
public with sharing class ALT_CLS_ObligationService {
  public class ObligationException extends Exception {
  }

  /** Capacidade de escrita das evidências AXF-104; lida pelo guard de FTX. */
  // @TestVisible só amplia o acesso nos testes: em produção o serviço continua sendo o único que
  // liga a capacidade, e nenhum caminho de execução lê ou escreve este campo de fora.
  @TestVisible
  private static Boolean writing = false;
  /** Capacidade estreita que permite mover os campos de referência da raiz do cronograma. */
  private static Boolean referenceWriting = false;

  public static Boolean isWriting() {
    return writing;
  }

  public static Boolean isWritingReference() {
    return referenceWriting;
  }

  public static final String OPERATION_APPLY = 'APPLY';
  public static final String OPERATION_CLASSIFY = 'CLASSIFY';
  public static final String OPERATION_REVERSE = 'REVERSE';
  public static final String OPERATION_AMEND = 'AMEND_OBLIGATION';
  public static final String MODE_PARTIAL = 'PARTIAL';
  public static final String MODE_FULL = 'FULL';
  public static final String CLASSIFICATION_EXPLAINED = 'EXPLAINED';
  public static final String CLASSIFICATION_UNCLASSIFIED = 'UNCLASSIFIED';
  public static final String CLASSIFICATION_NOT_APPLICABLE = 'NOT_APPLICABLE';
  public static final String KIND_ADJUSTMENT = 'ADJUSTMENT';
  public static final String KIND_COMPENSATION = 'COMPENSATION';
  public static final String PLAN_ACTUAL_ONLY = 'ACTUAL_ONLY';
  public static final String PLAN_CASH_FACT = 'CASH_FACT';
  public static final String METHOD_ESTIMATED = 'ESTIMATED';
  public static final String REFERENCE_KIND_EVIDENCE = 'REALIZATION';

  /** Campos de referência da raiz que esta capacidade pode mover (ver AXF_CLS_FSCTriggerHandler). */
  public static final Set<String> REFERENCE_FIELDS = new Set<String>{
    'AXF_FSC_LKP_ActiveReference__c',
    'AXF_FSC_NUM_FinancialVersion__c',
    'AXF_FSC_NUM_ProjectionRevision__c'
  };

  private static final String CAPABILITY = 'AXF104';
  private static final String DECISION_TAG = 'axf104-sdc-v1';
  private static final String ADJUSTMENT_TAG = 'axf104-oad-v1';
  private static final String REFERENCE_TAG = 'axf104-srf-v1';
  private static final String COVERAGE_TAG = 'axf104-cov-v1';
  private static final Decimal MAX_MONEY = 99999999999999.99;
  private static final Set<String> ADJUSTMENT_REASONS = new Set<String>{
    'ESTIMATE_REVISION',
    'CONTRACTUAL_RECURRING',
    'EXCEPTIONAL_CHARGE',
    'ONE_OFF_DISCOUNT',
    'CORRECTION',
    'UNCLASSIFIED'
  };
  private static final String FTX_FIELDS =
    'Id,AXF_FTX_LKP_Account__c,AXF_FTX_NUM_Magnitude__c,AXF_FTX_NUM_CurrentBasis__c,' +
    'AXF_FTX_BOL_BasisFrozen__c,AXF_FTX_TXT_CurrencyIsoCode__c,AXF_FTX_NUM_Version__c,' +
    'AXF_FTX_PKL_PlanKind__c,AXF_FTX_PKL_Direction__c,AXF_FTX_LKP_Schedule__c,' +
    'AXF_FTX_NUM_Sequence__c';
  private static final String SDC_FIELDS =
    'Id,AXF_SDC_EXI_DecisionKey__c,AXF_SDC_TXT_PayloadHash__c,' +
    'AXF_SDC_LKP_FinancialTransaction__c,AXF_SDC_LKP_Schedule__c,AXF_SDC_LKP_Allocation__c,' +
    'AXF_SDC_LKP_OriginalDecision__c,AXF_SDC_PKL_Operation__c,AXF_SDC_PKL_Mode__c,' +
    'AXF_SDC_PKL_Classification__c,AXF_SDC_NUM_BasisAmount__c,AXF_SDC_NUM_PriorNetApplied__c,' +
    'AXF_SDC_NUM_EffectiveObligation__c,AXF_SDC_NUM_RecurringAmount__c,' +
    'AXF_SDC_NUM_ExceptionalCharges__c,AXF_SDC_NUM_OneOffDiscount__c,' +
    'AXF_SDC_NUM_TargetVersion__c,AXF_SDC_NUM_ScheduleVersion__c,' +
    'AXF_SDC_DAT_EconomicDate__c,AXF_SDC_NUM_EconomicSequence__c,AXF_SDC_TXT_CoverageHash__c,' +
    'AXF_SDC_NUM_CoverageCount__c,AXF_SDC_TAL_ResultJson__c';

  /** Entrada tipada de uma operação de liquidação ajustada. */
  public class SettlementInput {
    public String operationKey;
    public Id targetId;
    public String mode;
    public String classification;
    public Decimal amount;
    public String currencyIso;
    public Date economicDate;
    /** Proposta explícita de delta com sinal, aceita apenas em PARTIAL. */
    public Decimal amendment;
    public Decimal recurringAmount;
    public Decimal exceptionalCharges;
    public Decimal oneOffDiscount;
    public String reasonCode;
    public String explanation;
    public Integer economicSequence;
    public Id originalDecisionId;
    public Decimal expectedTargetVersion;
    public Decimal expectedScheduleVersion;
    public String sourceKind;
    public Id sourceId;
    public Id fundingId;
    public Decimal expectedSourceVersion;
  }

  /** Resultado autorizado devolvido pela repetição equivalente. */
  public class SettlementResult {
    public String outcome;
    public String message;
    public String operation;
    public String mode;
    public String classification;
    public Id targetId;
    public Id decisionId;
    public Id allocationId;
    public Id adjustmentId;
    public Id referenceId;
    public Decimal basisAmount;
    public Decimal adjustmentTotal;
    public Decimal effectiveObligation;
    public Decimal netApplied;
    public Decimal outstandingObligation;
    public Decimal recurringAmount;
    public String coverageHash;
    public Long coverageCount;
    public Boolean replay = false;
  }

  /** Estado efetivo de uma ocorrência sob bloqueio. */
  public class ObligationView {
    public Id targetId;
    public Id scheduleId;
    public String planKind;
    public String currencyIso;
    public Integer sequence;
    public Decimal originalMagnitude;
    public Decimal basisAmount;
    public Boolean basisFrozen;
    public Decimal adjustmentTotal;
    public Decimal effectiveObligation;
    public Decimal netApplied;
    public Decimal outstandingObligation;
    public Decimal applicationCapacity;
    public Decimal targetVersion;
    public String coverageHash;
    public Long coverageCount;
  }

  private class Basis {
    public AXF_OBJ_FinancialTransaction__c row;
    public Id accountId;
    public Id scheduleId;
    public String planKind;
    public String currencyIso;
    public Integer sequence;
    public Decimal originalMagnitude;
    public Decimal currentBasis;
    public Boolean frozen;
    public Decimal targetVersion;

    public Decimal resolved() {
      return currentBasis != null ? currentBasis : originalMagnitude;
    }
  }

  private class Coverage {
    public String hash;
    public Long count;
    public Decimal netApplied;
  }

  private static void check(Boolean valid, String code) {
    if (!valid) {
      throw new ObligationException(code);
    }
  }

  private static Decimal version(Decimal value) {
    return value == null ? 0 : value;
  }

  private static String frameHash(List<Object> parts) {
    return AXF_CLS_IdentityFraming.sha256Hex(
      AXF_CLS_IdentityFraming.frame(parts)
    );
  }

  /**
   * @description Conjunto autorizado resolvido uma vez por transação: a autoridade do titular
   * não muda dentro de um mesmo comando, e reler o contexto a cada leitura de alvo consumiria
   * o limite de SOQL sem alterar a decisão de acesso.
   */
  @TestVisible
  private static Set<Id> authorizedAccounts;
  @TestVisible
  private static Id authorizedAccountsUser;

  private static Set<Id> authorizedAccountIds() {
    if (
      authorizedAccounts == null ||
      authorizedAccountsUser != UserInfo.getUserId()
    ) {
      // O cache é por usuário em execução: um mesmo contexto de transação nunca reaproveita a
      // autoridade resolvida para outro usuário.
      authorizedAccountsUser = UserInfo.getUserId();
      authorizedAccounts = new Set<Id>();
      for (
        AXF_CLS_AuthorizedContextService.ContextView context : AXF_CLS_AuthorizedContextService.listAuthorizedContexts()
      ) {
        authorizedAccounts.add(context.accountId);
      }
    }
    return authorizedAccounts;
  }

  private static void authorizeAccount(Id accountId) {
    check(authorizedAccountIds().contains(accountId), 'UNAVAILABLE');
  }

  private static Basis resolve(Id targetId, Boolean lockRow) {
    List<SObject> rows = Database.queryWithBinds(
      'SELECT ' +
        FTX_FIELDS +
        ' FROM AXF_OBJ_FinancialTransaction__c WHERE Id = :targetId' +
        (lockRow ? ' FOR UPDATE' : ''),
      new Map<String, Object>{ 'targetId' => targetId },
      AccessLevel.USER_MODE
    );
    check(rows.size() == 1, 'UNAVAILABLE');
    AXF_OBJ_FinancialTransaction__c row = (AXF_OBJ_FinancialTransaction__c) rows[0];
    check(row.AXF_FTX_PKL_PlanKind__c != PLAN_CASH_FACT, 'INVALID_ROLE');
    authorizeAccount(row.AXF_FTX_LKP_Account__c);
    Basis result = new Basis();
    result.row = row;
    result.accountId = row.AXF_FTX_LKP_Account__c;
    result.scheduleId = row.AXF_FTX_LKP_Schedule__c;
    result.planKind = row.AXF_FTX_PKL_PlanKind__c;
    result.currencyIso = row.AXF_FTX_TXT_CurrencyIsoCode__c;
    result.sequence = row.AXF_FTX_NUM_Sequence__c == null
      ? null
      : row.AXF_FTX_NUM_Sequence__c.intValue();
    result.originalMagnitude = row.AXF_FTX_NUM_Magnitude__c;
    result.currentBasis = row.AXF_FTX_NUM_CurrentBasis__c;
    result.frozen = row.AXF_FTX_BOL_BasisFrozen__c == true;
    result.targetVersion = version(row.AXF_FTX_NUM_Version__c);
    check(result.originalMagnitude != null, 'INVALID');
    return result;
  }

  /**
   * @description A = soma dos valores com sinal dos ajustes. Uma compensação carrega o valor
   * exatamente oposto ao ajuste que ela neutraliza, então a soma já é o líquido válido.
   */
  private static Decimal adjustmentTotal(Id targetId) {
    Decimal total = 0;
    for (AggregateResult row : [
      SELECT SUM(AXF_OAD_NUM_SignedAmount__c) amount
      FROM AXF_OBJ_ObligationAdjustment__c
      WHERE AXF_OAD_LKP_FinancialTransaction__c = :targetId
      WITH SYSTEM_MODE
    ]) {
      if (row.get('amount') != null) {
        total += (Decimal) row.get('amount');
      }
    }
    return total;
  }

  private static Decimal netApplied(Id targetId) {
    Decimal total = 0;
    for (AggregateResult row : [
      SELECT AXF_RA_PKL_Kind__c kind, SUM(AXF_RA_NUM_Magnitude__c) amount
      FROM AXF_OBJ_ReconciliationAllocation__c
      WHERE AXF_RA_LKP_FinancialTransaction__c = :targetId
      WITH SYSTEM_MODE
      GROUP BY AXF_RA_PKL_Kind__c
    ]) {
      total +=
        ((String) row.get('kind') == 'REVERSAL' ? -1 : 1) *
        (Decimal) row.get('amount');
    }
    return total;
  }

  /**
   * @description Cobertura das contribuições: alocações originais ativas, ordenadas
   * canonicamente, com valores e moeda imutáveis, mais a versão da base e a obrigação efetiva.
   * Um ponteiro único para a última alocação não é prova de cobertura.
   */
  private static Coverage coverageFor(
    Id targetId,
    Decimal basisVersion,
    Decimal effectiveObligation
  ) {
    Set<Id> reversed = new Set<Id>();
    for (AXF_OBJ_ReconciliationAllocation__c row : [
      SELECT AXF_RA_LKP_OriginalAllocation__c
      FROM AXF_OBJ_ReconciliationAllocation__c
      WHERE
        AXF_RA_LKP_FinancialTransaction__c = :targetId
        AND AXF_RA_PKL_Kind__c = 'REVERSAL'
        AND AXF_RA_LKP_OriginalAllocation__c != NULL
      WITH SYSTEM_MODE
    ]) {
      reversed.add(row.AXF_RA_LKP_OriginalAllocation__c);
    }
    List<AXF_OBJ_ReconciliationAllocation__c> active = new List<AXF_OBJ_ReconciliationAllocation__c>();
    Decimal net = 0;
    for (AXF_OBJ_ReconciliationAllocation__c row : [
      SELECT Id, AXF_RA_NUM_Magnitude__c, AXF_RA_TXT_CurrencyIsoCode__c
      FROM AXF_OBJ_ReconciliationAllocation__c
      WHERE
        AXF_RA_LKP_FinancialTransaction__c = :targetId
        AND AXF_RA_PKL_Kind__c = 'APPLICATION'
      WITH SYSTEM_MODE
      ORDER BY Id ASC
    ]) {
      if (reversed.contains(row.Id)) {
        continue;
      }
      active.add(row);
      net += row.AXF_RA_NUM_Magnitude__c;
    }
    List<Object> parts = new List<Object>{
      COVERAGE_TAG,
      targetId,
      basisVersion,
      effectiveObligation
    };
    for (AXF_OBJ_ReconciliationAllocation__c row : active) {
      parts.add(row.Id);
      parts.add(row.AXF_RA_NUM_Magnitude__c);
      parts.add(row.AXF_RA_TXT_CurrencyIsoCode__c);
    }
    Coverage result = new Coverage();
    result.hash = frameHash(parts);
    result.count = active.size();
    result.netApplied = net;
    return result;
  }

  private static AXF_OBJ_SettlementDecision__c decisionByKey(String key) {
    List<AXF_OBJ_SettlementDecision__c> rows = (List<AXF_OBJ_SettlementDecision__c>) Database.queryWithBinds(
      'SELECT ' +
        SDC_FIELDS +
        ' FROM AXF_OBJ_SettlementDecision__c WHERE AXF_SDC_EXI_DecisionKey__c = :key',
      new Map<String, Object>{ 'key' => key },
      AccessLevel.SYSTEM_MODE
    );
    return rows.isEmpty() ? null : rows[0];
  }

  /** @description Replay equivalente devolve o resultado original; carga alterada conflita. */
  private static SettlementResult replay(
    AXF_OBJ_SettlementDecision__c row,
    String payloadHash
  ) {
    check(row.AXF_SDC_TXT_PayloadHash__c == payloadHash, 'CONFLICT');
    check(!String.isBlank(row.AXF_SDC_TAL_ResultJson__c), 'CONFLICT');
    SettlementResult result;
    try {
      result = (SettlementResult) JSON.deserialize(
        row.AXF_SDC_TAL_ResultJson__c,
        SettlementResult.class
      );
    } catch (Exception malformed) {
      throw new ObligationException('CONFLICT');
    }
    result.replay = true;
    return result;
  }

  private static void lockHolder(Id accountId) {
    List<SObject> holders = Database.queryWithBinds(
      'SELECT Id FROM Account WHERE Id = :accountId FOR UPDATE',
      new Map<String, Object>{ 'accountId' => accountId },
      AccessLevel.USER_MODE
    );
    check(holders.size() == 1, 'UNAVAILABLE');
  }

  private static String decisionKey(Id holderId, String operationKey) {
    return AXF_CLS_IdentityFraming.key(
      new List<Object>{
        DECISION_TAG,
        CAPABILITY,
        holderId,
        UserInfo.getUserId(),
        operationKey
      }
    );
  }

  private static List<Object> canonicalParts(SettlementInput input) {
    return new List<Object>{
      CAPABILITY,
      input.operationKey,
      input.targetId,
      input.mode,
      input.classification,
      input.amount,
      input.currencyIso,
      input.economicDate,
      input.amendment,
      input.recurringAmount,
      input.exceptionalCharges,
      input.oneOffDiscount,
      input.reasonCode,
      input.explanation,
      input.economicSequence,
      input.originalDecisionId,
      input.expectedTargetVersion,
      input.expectedScheduleVersion,
      input.sourceKind,
      input.sourceId,
      input.fundingId,
      input.expectedSourceVersion
    };
  }

  private static String payloadHash(SettlementInput input) {
    return frameHash(canonicalParts(input));
  }

  /**
   * @description Valida a decomposição da parcela INTEIRA. Componentes ausentes nunca assumem
   * zero em silêncio: EXPLAINED exige explicitamente os três componentes e a equação
   * recorrente + excepcionais - desconto pontual = obrigação efetiva resultante.
   */
  private static void validateComponents(
    SettlementInput input,
    Decimal resultingObligation
  ) {
    if (input.classification == CLASSIFICATION_UNCLASSIFIED) {
      check(
        input.recurringAmount == null &&
          input.exceptionalCharges == null &&
          input.oneOffDiscount == null,
        'INVALID_COMPONENTS'
      );
      check(!String.isBlank(input.explanation), 'REASON_REQUIRED');
      return;
    }
    check(
      input.classification == CLASSIFICATION_EXPLAINED,
      'INVALID_CLASSIFICATION'
    );
    check(
      input.recurringAmount != null &&
        input.exceptionalCharges != null &&
        input.oneOffDiscount != null,
      'INVALID_COMPONENTS'
    );
    for (
      Decimal component : new List<Decimal>{
        input.recurringAmount,
        input.exceptionalCharges,
        input.oneOffDiscount
      }
    ) {
      check(
        component >= 0 && Math.abs(component) <= MAX_MONEY,
        'INVALID_COMPONENTS'
      );
      check(component == component.setScale(2), 'INVALID_COMPONENTS');
    }
    Decimal explained =
      input.recurringAmount +
      input.exceptionalCharges -
      input.oneOffDiscount;
    check(explained == resultingObligation, 'COMPONENT_TOTAL_MISMATCH');
    check(!String.isBlank(input.explanation), 'REASON_REQUIRED');
  }

  private static void validateMoney(Decimal value) {
    check(
      value == null ||
      (Math.abs(value) <= MAX_MONEY &&
      value == value.setScale(2)),
      'INVALID_AMOUNT'
    );
  }

  private static void validateCommon(SettlementInput input) {
    check(
      input != null &&
        input.targetId != null &&
        !String.isBlank(input.operationKey) &&
        input.operationKey.length() <= 80 &&
        input.economicDate != null,
      'INVALID'
    );
    check(
      input.currencyIso != null &&
      Pattern.matches('[A-Z]{3}', input.currencyIso),
      'INVALID'
    );
    check(
      input.reasonCode == null || ADJUSTMENT_REASONS.contains(input.reasonCode),
      'INVALID_REASON'
    );
    validateMoney(input.amount);
    validateMoney(input.amendment);
  }

  /** @description Visão efetiva de uma ocorrência: B, A, E, N, R e a capacidade de aplicação. */
  public ObligationView read(Id targetId) {
    ALT_CLS_RealizationService.requireAccess();
    Basis basis = resolve(targetId, false);
    Decimal basisAmount = basis.resolved();
    Decimal adjustments = adjustmentTotal(targetId);
    Decimal effective = basisAmount + adjustments;
    Decimal net = netApplied(targetId);
    Coverage coverage = coverageFor(targetId, basis.targetVersion, effective);
    ObligationView view = new ObligationView();
    view.targetId = basis.row.Id;
    view.scheduleId = basis.scheduleId;
    view.planKind = basis.planKind;
    view.currencyIso = basis.currencyIso;
    view.sequence = basis.sequence;
    view.originalMagnitude = basis.originalMagnitude;
    view.basisAmount = basisAmount;
    view.basisFrozen = basis.frozen;
    view.adjustmentTotal = adjustments;
    view.effectiveObligation = effective;
    view.netApplied = net;
    // ACTUAL_ONLY preserva a representação factual e as aplicações líquidas, mas não carrega
    // dívida de previsão: o residual é zero. A capacidade factual é outra grandeza, igual à
    // magnitude imutável menos as alocações líquidas.
    view.outstandingObligation = basis.planKind == PLAN_ACTUAL_ONLY
      ? 0
      : effective - net;
    view.applicationCapacity = basis.planKind == PLAN_ACTUAL_ONLY
      ? basis.originalMagnitude - net
      : effective - net;
    view.targetVersion = basis.targetVersion;
    view.coverageHash = coverage.hash;
    view.coverageCount = coverage.count;
    return view;
  }

  /**
   * @description Aplica caixa com ajuste de obrigação revisado. PARTIAL deixa explicitamente
   * uma obrigação em aberto; FULL propõe Enew = N + Q. O modo é explícito: um valor menor
   * sozinho nunca marca o restante como pago.
   */
  public SettlementResult apply(SettlementInput input) {
    ALT_CLS_RealizationService.requireAccess();
    validateCommon(input);
    check(
      input.mode == MODE_PARTIAL || input.mode == MODE_FULL,
      'INVALID_MODE'
    );
    check(input.amount != null && input.amount > 0, 'INVALID');
    check(input.classification != null, 'INVALID_CLASSIFICATION');
    check(
      new Set<String>{ 'CASH', 'BANK', 'CARD' }.contains(input.sourceKind),
      'INVALID_SOURCE'
    );
    Savepoint sp = Database.setSavepoint();
    SettlementResult result = new SettlementResult();
    try {
      writing = true;
      Basis pre = resolve(input.targetId, false);
      String key = decisionKey(pre.accountId, input.operationKey);
      String hash = payloadHash(input);
      // A repetição equivalente é resolvida pela identidade da operação ANTES da verificação
      // de versão obsoleta.
      AXF_OBJ_SettlementDecision__c existing = decisionByKey(key);
      if (existing != null) {
        return replay(existing, hash);
      }
      lockHolder(pre.accountId);
      existing = decisionByKey(key);
      if (existing != null) {
        return replay(existing, hash);
      }
      Basis basis = resolve(input.targetId, true);
      check(
        input.expectedTargetVersion != null &&
          basis.targetVersion == input.expectedTargetVersion,
        'CONFLICT'
      );
      check(basis.currencyIso == input.currencyIso, 'CURRENCY_MISMATCH');
      Boolean factual = basis.planKind == PLAN_ACTUAL_ONLY;
      Decimal basisAmount = basis.resolved();
      Decimal adjustments = adjustmentTotal(basis.row.Id);
      Decimal effective = basisAmount + adjustments;
      Decimal net = netApplied(basis.row.Id);
      Decimal delta;
      Decimal resulting;
      if (factual) {
        // Nenhum ajuste com sinal, nenhum desconto sintético e nenhuma dívida fabricada.
        check(input.amendment == null || input.amendment == 0, 'INVALID_ROLE');
        check(adjustments == 0, 'INVALID_ROLE');
        check(
          input.classification == CLASSIFICATION_NOT_APPLICABLE,
          'INVALID_CLASSIFICATION'
        );
        Decimal capacity = basis.originalMagnitude - net;
        check(capacity > 0, 'UNAVAILABLE_AMOUNT');
        if (input.mode == MODE_FULL) {
          check(input.amount == capacity, 'INVALID_FACTUAL_TOTAL');
        } else {
          check(input.amount < capacity, 'INVALID_FACTUAL_TOTAL');
        }
        resulting = effective;
        delta = 0;
      } else if (input.mode == MODE_PARTIAL) {
        delta = input.amendment == null ? 0 : input.amendment;
        check(net + input.amount <= effective + delta, 'UNAVAILABLE_AMOUNT');
        // N + Q igual a E + delta liquida a obrigação: o rótulo parcial contradiria o
        // resultado calculado, então o comando explica em vez de persistir a contradição.
        check(net + input.amount < effective + delta, 'SETTLES_OBLIGATION');
        check(
          input.classification == CLASSIFICATION_NOT_APPLICABLE,
          'INVALID_CLASSIFICATION'
        );
        check(
          input.recurringAmount == null &&
            input.exceptionalCharges == null &&
            input.oneOffDiscount == null,
          'INVALID_COMPONENTS'
        );
        if (delta != 0) {
          check(!String.isBlank(input.reasonCode), 'REASON_REQUIRED');
        }
        resulting = effective + delta;
      } else {
        resulting = net + input.amount;
        delta = resulting - effective;
        check(
          resulting >= 0 && Math.abs(resulting) <= MAX_MONEY,
          'INVALID_AMOUNT'
        );
        validateComponents(input, resulting);
      }
      check(delta == delta.setScale(2), 'INVALID_AMOUNT');
      // O caixa é aplicado pelo caminho AXF-25, com a capacidade derivada da obrigação
      // efetiva — nunca limitada pela estimativa original obsoleta.
      ALT_CLS_RealizationService.Input cash = new ALT_CLS_RealizationService.Input();
      cash.operationKey = input.operationKey;
      cash.targetId = input.targetId;
      cash.accountId = basis.accountId;
      cash.sourceKind = input.sourceKind;
      cash.sourceId = input.sourceId;
      cash.fundingId = input.fundingId;
      cash.amount = input.amount;
      cash.currencyIso = input.currencyIso;
      cash.direction = basis.row.AXF_FTX_PKL_Direction__c;
      cash.recognitionDate = input.economicDate;
      cash.targetVersion = input.expectedTargetVersion;
      cash.sourceVersion = input.expectedSourceVersion;
      // A capacidade do alvo é a obrigação efetiva RESULTANTE (E + delta): é o ajuste
      // revisado que autoriza a liquidação, nunca a estimativa original obsoleta. A fonte
      // permanece limitada pela própria disponibilidade real.
      cash.effectiveObligation = factual
        ? basis.originalMagnitude
        : effective + delta;
      result.targetId = input.targetId;
      result.allocationId = new ALT_CLS_RealizationService().apply(cash);
      if (!factual) {
        freezeBasis(basis);
      }
      Decimal committedEffective = factual ? effective : resulting;
      Decimal netAfter = netApplied(input.targetId);
      // Todo escritor financeiro retira a classificação/referência invalidada antes de
      // publicar a sua, mesmo que a ocorrência permaneça integralmente liquidada.
      withdrawInvalidated(basis, null);
      // A versão de base do hash é a versão lida sob bloqueio, exatamente a que a decisão
      // carimba: só assim todo escritor posterior reproduz a mesma cobertura ao rechecar.
      Coverage coverage = coverageFor(
        input.targetId,
        basis.targetVersion,
        committedEffective
      );
      result.operation = OPERATION_APPLY;
      result.mode = input.mode;
      result.classification = input.classification;
      result.basisAmount = basisAmount;
      result.adjustmentTotal = adjustments + delta;
      result.effectiveObligation = committedEffective;
      result.netApplied = netAfter;
      result.outstandingObligation = factual
        ? 0
        : committedEffective - netAfter;
      result.recurringAmount = input.recurringAmount;
      result.coverageHash = coverage.hash;
      result.coverageCount = coverage.count;
      result.outcome = 'APPLIED';
      result.message =
        'Liquidação ' +
        input.mode +
        ': ' +
        input.amount +
        ' aplicados; obrigação efetiva ' +
        committedEffective +
        ' e ' +
        (committedEffective - netAfter) +
        ' em aberto.';
      AXF_OBJ_SettlementDecision__c decision = writeDecision(
        input,
        basis,
        key,
        hash,
        OPERATION_APPLY,
        basisAmount,
        committedEffective,
        net,
        effectiveSequenceFor(input, basis),
        coverage,
        result
      );
      result.adjustmentId = delta == 0
        ? null
        : writeAdjustment(
            input,
            basis,
            decision.Id,
            delta,
            result.allocationId
          );
      result.referenceId = publishReference(input, basis, result, decision.Id);
      persistResult(result);
      return result;
    } catch (Exception failure) {
      Database.rollback(sp);
      if (failure instanceof ObligationException) {
        throw failure;
      }
      // O caminho de caixa do AXF-25 devolve códigos já saneados; preservá-los mantém a
      // causa acionável para o autorizador em vez de mascará-la como indisponibilidade.
      if (failure instanceof ALT_CLS_RealizationService.RealizationException) {
        throw new ObligationException(failure.getMessage());
      }
      // Nenhum detalhe interno cruza esta fronteira: o autorizador recebe um código estável.
      throw new ObligationException('UNAVAILABLE');
    } finally {
      writing = false;
    }
  }

  private static Integer effectiveSequenceFor(
    SettlementInput input,
    Basis basis
  ) {
    if (input.economicSequence != null && input.economicSequence > 0) {
      return input.economicSequence;
    }
    return basis.sequence;
  }

  private static Id writeAdjustment(
    SettlementInput input,
    Basis basis,
    Id decisionId,
    Decimal delta,
    Id allocationId
  ) {
    check(delta != 0, 'INVALID');
    String reason = String.isBlank(input.reasonCode)
      ? 'CORRECTION'
      : input.reasonCode;
    check(ADJUSTMENT_REASONS.contains(reason), 'INVALID_REASON');
    AXF_OBJ_ObligationAdjustment__c row = new AXF_OBJ_ObligationAdjustment__c(
      AXF_OAD_EXI_AdjustmentKey__c = AXF_CLS_IdentityFraming.key(
        new List<Object>{
          ADJUSTMENT_TAG,
          CAPABILITY,
          decisionId,
          delta,
          KIND_ADJUSTMENT
        }
      ),
      AXF_OAD_LKP_SettlementDecision__c = decisionId,
      AXF_OAD_LKP_FinancialTransaction__c = basis.row.Id,
      AXF_OAD_LKP_Allocation__c = allocationId,
      AXF_OAD_NUM_SignedAmount__c = delta,
      AXF_OAD_TXT_CurrencyIsoCode__c = basis.currencyIso,
      AXF_OAD_PKL_Kind__c = KIND_ADJUSTMENT,
      AXF_OAD_PKL_Reason__c = reason,
      AXF_OAD_TAL_Explanation__c = input.explanation,
      AXF_OAD_NUM_BasisVersion__c = basis.targetVersion,
      AXF_OAD_DAT_EffectiveDate__c = input.economicDate,
      AXF_OAD_LKP_Actor__c = UserInfo.getUserId(),
      AXF_OAD_DT_RecordedAt__c = System.now()
    );
    Database.insert(row, AccessLevel.SYSTEM_MODE);
    return row.Id;
  }

  /** @description A base revisada congela antes do primeiro uso financeiro e nunca é reprecificada. */
  private static void freezeBasis(Basis basis) {
    AXF_OBJ_FinancialTransaction__c row = new AXF_OBJ_FinancialTransaction__c(
      Id = basis.row.Id
    );
    Boolean changed = false;
    if (basis.currentBasis == null) {
      row.AXF_FTX_NUM_CurrentBasis__c = basis.resolved();
      changed = true;
    }
    if (!basis.frozen) {
      row.AXF_FTX_BOL_BasisFrozen__c = true;
      changed = true;
    }
    if (!changed) {
      return;
    }
    Database.update(row, AccessLevel.SYSTEM_MODE);
  }

  private static AXF_OBJ_SettlementDecision__c writeDecision(
    SettlementInput input,
    Basis basis,
    String decisionKeyValue,
    String hash,
    String operation,
    Decimal basisAmount,
    Decimal effectiveObligation,
    Decimal netAppliedBefore,
    Integer sequence,
    Coverage coverage,
    SettlementResult result
  ) {
    check(
      effectiveObligation == effectiveObligation.setScale(2) &&
        Math.abs(effectiveObligation) <= MAX_MONEY,
      'INVALID'
    );
    AXF_OBJ_SettlementDecision__c row = new AXF_OBJ_SettlementDecision__c(
      AXF_SDC_EXI_DecisionKey__c = decisionKeyValue,
      AXF_SDC_TXT_PayloadHash__c = hash,
      AXF_SDC_LKP_FinancialTransaction__c = basis.row.Id,
      AXF_SDC_LKP_Schedule__c = basis.scheduleId,
      AXF_SDC_LKP_Allocation__c = result.allocationId,
      AXF_SDC_LKP_OriginalDecision__c = input.originalDecisionId,
      AXF_SDC_PKL_Operation__c = operation,
      AXF_SDC_PKL_Mode__c = input.mode,
      AXF_SDC_PKL_Classification__c = input.classification,
      AXF_SDC_NUM_BasisAmount__c = basisAmount,
      AXF_SDC_NUM_PriorNetApplied__c = netAppliedBefore,
      AXF_SDC_NUM_EffectiveObligation__c = effectiveObligation,
      AXF_SDC_NUM_TargetVersion__c = basis.targetVersion,
      AXF_SDC_DAT_EconomicDate__c = input.economicDate,
      AXF_SDC_NUM_EconomicSequence__c = sequence,
      AXF_SDC_TXT_CoverageHash__c = coverage.hash,
      AXF_SDC_NUM_CoverageCount__c = coverage.count,
      AXF_SDC_TAL_Explanation__c = input.explanation,
      AXF_SDC_LKP_Actor__c = UserInfo.getUserId(),
      AXF_SDC_DT_CommittedAt__c = System.now(),
      AXF_SDC_TAL_CanonicalPayload__c = frameHash(canonicalParts(input))
        .abbreviate(32000)
    );
    if (input.classification == CLASSIFICATION_EXPLAINED) {
      row.AXF_SDC_NUM_RecurringAmount__c = input.recurringAmount;
      row.AXF_SDC_NUM_ExceptionalCharges__c = input.exceptionalCharges;
      row.AXF_SDC_NUM_OneOffDiscount__c = input.oneOffDiscount;
    }
    if (input.expectedScheduleVersion != null) {
      row.AXF_SDC_NUM_ScheduleVersion__c = input.expectedScheduleVersion;
    }
    Database.insert(row, AccessLevel.SYSTEM_MODE);
    result.decisionId = row.Id;
    return row;
  }

  /**
   * @description CLASSIFY descreve uma parcela INTEIRA já liquidada sem movimentar caixa. Não
   * cria previsão anterior e exige a ligação explícita de cronograma/sequência.
   */
  public SettlementResult classify(SettlementInput input) {
    ALT_CLS_RealizationService.requireAccess();
    validateCommon(input);
    input.mode = MODE_FULL;
    check(
      input.classification == CLASSIFICATION_EXPLAINED,
      'INVALID_CLASSIFICATION'
    );
    check(
      input.amount == null &&
        input.amendment == null &&
        input.sourceId == null &&
        input.sourceKind == null &&
        input.fundingId == null,
      'INVALID_SOURCE'
    );
    check(
      input.economicSequence != null && input.economicSequence > 0,
      'INVALID'
    );
    Savepoint sp = Database.setSavepoint();
    SettlementResult result = new SettlementResult();
    try {
      writing = true;
      Basis pre = resolve(input.targetId, false);
      String key = decisionKey(pre.accountId, input.operationKey);
      String hash = payloadHash(input);
      AXF_OBJ_SettlementDecision__c existing = decisionByKey(key);
      if (existing != null) {
        return replay(existing, hash);
      }
      lockHolder(pre.accountId);
      existing = decisionByKey(key);
      if (existing != null) {
        return replay(existing, hash);
      }
      Basis basis = resolve(input.targetId, true);
      check(
        input.expectedTargetVersion != null &&
          basis.targetVersion == input.expectedTargetVersion,
        'CONFLICT'
      );
      check(basis.currencyIso == input.currencyIso, 'CURRENCY_MISMATCH');
      Decimal basisAmount = basis.resolved();
      Decimal adjustments = adjustmentTotal(basis.row.Id);
      Decimal effective = basisAmount + adjustments;
      Decimal net = netApplied(basis.row.Id);
      // A classificação deve corresponder à obrigação liquidada vigente sob bloqueio.
      check(effective == net, 'NOT_FULLY_SETTLED');
      validateComponents(input, effective);
      Coverage coverage = coverageFor(
        basis.row.Id,
        basis.targetVersion,
        effective
      );
      result.operation = OPERATION_CLASSIFY;
      result.mode = MODE_FULL;
      result.classification = input.classification;
      result.targetId = input.targetId;
      result.basisAmount = basisAmount;
      result.adjustmentTotal = adjustments;
      result.effectiveObligation = effective;
      result.netApplied = net;
      result.outstandingObligation = 0;
      result.recurringAmount = input.recurringAmount;
      result.coverageHash = coverage.hash;
      result.coverageCount = coverage.count;
      result.outcome = 'CLASSIFIED';
      result.message = 'Parcela integralmente liquidada classificada; nenhum caixa foi movimentado.';
      AXF_OBJ_SettlementDecision__c decision = writeDecision(
        input,
        basis,
        key,
        hash,
        OPERATION_CLASSIFY,
        basisAmount,
        effective,
        net,
        effectiveSequenceFor(input, basis),
        coverage,
        result
      );
      result.referenceId = publishReference(input, basis, result, decision.Id);
      persistResult(result);
      return result;
    } catch (Exception failure) {
      Database.rollback(sp);
      if (failure instanceof ObligationException) {
        throw failure;
      }
      // O caminho de caixa do AXF-25 devolve códigos já saneados; preservá-los mantém a
      // causa acionável para o autorizador em vez de mascará-la como indisponibilidade.
      if (failure instanceof ALT_CLS_RealizationService.RealizationException) {
        throw new ObligationException(failure.getMessage());
      }
      // Nenhum detalhe interno cruza esta fronteira: o autorizador recebe um código estável.
      throw new ObligationException('UNAVAILABLE');
    } finally {
      writing = false;
    }
  }

  /**
   * @description AMEND_OBLIGATION altera individualmente a obrigação efetiva de uma ocorrência
   * prevista. Não aceita fonte, alocação nem valor de caixa, exige o novo valor efetivo e o
   * motivo, e nunca é compensado apenas porque uma alocação de caixa foi estornada.
   */
  public SettlementResult amend(SettlementInput input) {
    ALT_CLS_RealizationService.requireAccess();
    validateCommon(input);
    check(input.amount != null, 'INVALID');
    check(input.classification == CLASSIFICATION_NOT_APPLICABLE, 'INVALID');
    check(String.isBlank(input.mode), 'INVALID_MODE');
    check(!String.isBlank(input.reasonCode), 'REASON_REQUIRED');
    check(!String.isBlank(input.explanation), 'REASON_REQUIRED');
    check(
      input.sourceId == null &&
        input.sourceKind == null &&
        input.fundingId == null &&
        input.amendment == null,
      'INVALID_SOURCE'
    );
    Savepoint sp = Database.setSavepoint();
    SettlementResult result = new SettlementResult();
    try {
      writing = true;
      Basis pre = resolve(input.targetId, false);
      String key = decisionKey(pre.accountId, input.operationKey);
      String hash = payloadHash(input);
      AXF_OBJ_SettlementDecision__c existing = decisionByKey(key);
      if (existing != null) {
        return replay(existing, hash);
      }
      lockHolder(pre.accountId);
      existing = decisionByKey(key);
      if (existing != null) {
        return replay(existing, hash);
      }
      Basis basis = resolve(input.targetId, true);
      check(
        input.expectedTargetVersion != null &&
          basis.targetVersion == input.expectedTargetVersion,
        'CONFLICT'
      );
      check(basis.planKind != PLAN_ACTUAL_ONLY, 'INVALID_ROLE');
      check(basis.currencyIso == input.currencyIso, 'CURRENCY_MISMATCH');
      Decimal basisAmount = basis.resolved();
      Decimal adjustments = adjustmentTotal(basis.row.Id);
      Decimal effective = basisAmount + adjustments;
      Decimal net = netApplied(basis.row.Id);
      Decimal proposed = input.amount;
      check(
        proposed == proposed.setScale(2) && proposed <= MAX_MONEY,
        'INVALID_AMOUNT'
      );
      // Enew >= N >= 0: nunca estorna, move caixa ou perdoa saldo implicitamente.
      check(net >= 0 && proposed >= net, 'AMOUNT_BELOW_PAID');
      Decimal delta = proposed - effective;
      check(delta == delta.setScale(2), 'INVALID_AMOUNT');
      Coverage coverage = coverageFor(
        basis.row.Id,
        basis.targetVersion,
        proposed
      );
      result.operation = OPERATION_AMEND;
      result.classification = input.classification;
      result.targetId = input.targetId;
      result.basisAmount = basisAmount;
      result.adjustmentTotal = adjustments + delta;
      result.effectiveObligation = proposed;
      result.netApplied = net;
      result.outstandingObligation = proposed - net;
      result.coverageHash = coverage.hash;
      result.coverageCount = coverage.count;
      result.outcome = delta == 0 ? 'NOOP' : 'AMENDED';
      result.message = delta == 0
        ? 'Delta zero: recebimento sem ajuste; nenhuma versão financeira foi incrementada.'
        : 'Obrigação efetiva revisada individualmente.';
      AXF_OBJ_SettlementDecision__c decision = writeDecision(
        input,
        basis,
        key,
        hash,
        OPERATION_AMEND,
        basisAmount,
        proposed,
        net,
        effectiveSequenceFor(input, basis),
        coverage,
        result
      );
      if (delta != 0) {
        // A correção da obrigação congela a base revisada e retira a classificação
        // invalidada, mesmo quando Enew = N.
        freezeBasis(basis);
        result.adjustmentId = writeAdjustment(
          input,
          basis,
          decision.Id,
          delta,
          null
        );
        withdrawInvalidated(basis, null);
      }
      persistResult(result);
      return result;
    } catch (Exception failure) {
      Database.rollback(sp);
      if (failure instanceof ObligationException) {
        throw failure;
      }
      // O caminho de caixa do AXF-25 devolve códigos já saneados; preservá-los mantém a
      // causa acionável para o autorizador em vez de mascará-la como indisponibilidade.
      if (failure instanceof ALT_CLS_RealizationService.RealizationException) {
        throw new ObligationException(failure.getMessage());
      }
      // Nenhum detalhe interno cruza esta fronteira: o autorizador recebe um código estável.
      throw new ObligationException('UNAVAILABLE');
    } finally {
      writing = false;
    }
  }

  /**
   * @description Valida, ANTES de qualquer escrita, que o estorno compensado deixa a ocorrência
   * com E >= N >= 0. Efeitos dependentes sobreviventes falham atomicamente, sem mutação.
   */
  public static void assertReversalAllowed(Id allocationId) {
    List<AXF_OBJ_ReconciliationAllocation__c> rows = [
      SELECT
        Id,
        AXF_RA_LKP_FinancialTransaction__c,
        AXF_RA_NUM_Magnitude__c,
        AXF_RA_PKL_Kind__c
      FROM AXF_OBJ_ReconciliationAllocation__c
      WHERE Id = :allocationId
      WITH SYSTEM_MODE
    ];
    if (rows.size() != 1 || rows[0].AXF_RA_PKL_Kind__c != 'APPLICATION') {
      return;
    }
    Id targetId = rows[0].AXF_RA_LKP_FinancialTransaction__c;
    if (targetId == null) {
      return;
    }
    Basis basis = resolve(targetId, false);
    // Uma única leitura das evidências de ajuste fornece o líquido A, o conjunto já compensado
    // e o ajuste atribuível a esta aplicação.
    List<AXF_OBJ_ObligationAdjustment__c> adjustments = [
      SELECT
        Id,
        AXF_OAD_LKP_OriginalAdjustment__c,
        AXF_OAD_LKP_Allocation__c,
        AXF_OAD_NUM_SignedAmount__c,
        AXF_OAD_PKL_Kind__c
      FROM AXF_OBJ_ObligationAdjustment__c
      WHERE AXF_OAD_LKP_FinancialTransaction__c = :targetId
      WITH SYSTEM_MODE
    ];
    Decimal adjustmentsTotal = 0;
    Set<Id> alreadyCompensated = new Set<Id>();
    for (AXF_OBJ_ObligationAdjustment__c row : adjustments) {
      adjustmentsTotal += row.AXF_OAD_NUM_SignedAmount__c;
      if (row.AXF_OAD_LKP_OriginalAdjustment__c != null) {
        alreadyCompensated.add(row.AXF_OAD_LKP_OriginalAdjustment__c);
      }
    }
    Decimal attributable = 0;
    for (AXF_OBJ_ObligationAdjustment__c row : adjustments) {
      if (
        row.AXF_OAD_PKL_Kind__c == KIND_ADJUSTMENT &&
        row.AXF_OAD_LKP_Allocation__c == allocationId &&
        !alreadyCompensated.contains(row.Id)
      ) {
        attributable += row.AXF_OAD_NUM_SignedAmount__c;
      }
    }
    // Ajustes independentes (Allocation nula) sobrevivem ao estorno de caixa e nunca são
    // compensados apenas porque a alocação foi estornada.
    Decimal effectiveAfter =
      basis.resolved() + (adjustmentsTotal - attributable);
    Decimal netAfter = netApplied(targetId) - rows[0].AXF_RA_NUM_Magnitude__c;
    if (netAfter < 0 || effectiveAfter < netAfter) {
      throw new ObligationException('DEPENDENT_EFFECTS');
    }
  }

  /**
   * @description Compensa APENAS o ajuste atribuível e retira a classificação/referência
   * dependente invalidada. Um ACTUAL_ONLY não recebe ajuste nem dívida fabricada.
   */
  public static void compensateForReversal(
    Id targetId,
    Id originalAllocationId,
    Id reversalAllocationId
  ) {
    Basis basis = resolve(targetId, false);
    if (basis.planKind == PLAN_ACTUAL_ONLY) {
      return;
    }
    // Uma única leitura das evidências de ajuste do alvo fornece o líquido A, o conjunto já
    // compensado e os ajustes atribuíveis à aplicação estornada.
    List<AXF_OBJ_ObligationAdjustment__c> adjustments = [
      SELECT
        Id,
        AXF_OAD_LKP_OriginalAdjustment__c,
        AXF_OAD_LKP_Allocation__c,
        AXF_OAD_NUM_SignedAmount__c,
        AXF_OAD_TXT_CurrencyIsoCode__c,
        AXF_OAD_PKL_Reason__c,
        AXF_OAD_PKL_Kind__c
      FROM AXF_OBJ_ObligationAdjustment__c
      WHERE AXF_OAD_LKP_FinancialTransaction__c = :targetId
      WITH SYSTEM_MODE
    ];
    Decimal adjustmentsTotal = 0;
    Set<Id> alreadyCompensated = new Set<Id>();
    for (AXF_OBJ_ObligationAdjustment__c row : adjustments) {
      adjustmentsTotal += row.AXF_OAD_NUM_SignedAmount__c;
      if (row.AXF_OAD_LKP_OriginalAdjustment__c != null) {
        alreadyCompensated.add(row.AXF_OAD_LKP_OriginalAdjustment__c);
      }
    }
    List<AXF_OBJ_ObligationAdjustment__c> compensationSources = new List<AXF_OBJ_ObligationAdjustment__c>();
    for (AXF_OBJ_ObligationAdjustment__c row : adjustments) {
      // Só o ajuste atribuível à aplicação estornada é compensado; um ajuste independente
      // (Allocation nula) ou de outra aplicação nunca é tocado.
      if (
        row.AXF_OAD_PKL_Kind__c == KIND_ADJUSTMENT &&
        row.AXF_OAD_LKP_Allocation__c == originalAllocationId &&
        !alreadyCompensated.contains(row.Id)
      ) {
        compensationSources.add(row);
      }
    }
    Decimal effective = basis.resolved() + adjustmentsTotal;
    Decimal net = netApplied(targetId);
    if (compensationSources.isEmpty()) {
      withdrawInvalidated(basis, null);
      return;
    }
    writing = true;
    try {
      AXF_OBJ_SettlementDecision__c decision = new AXF_OBJ_SettlementDecision__c(
        AXF_SDC_EXI_DecisionKey__c = AXF_CLS_IdentityFraming.key(
          new List<Object>{
            DECISION_TAG,
            CAPABILITY,
            OPERATION_REVERSE,
            reversalAllocationId
          }
        ),
        AXF_SDC_TXT_PayloadHash__c = frameHash(
          new List<Object>{
            CAPABILITY,
            OPERATION_REVERSE,
            reversalAllocationId
          }
        ),
        AXF_SDC_LKP_FinancialTransaction__c = targetId,
        AXF_SDC_LKP_Schedule__c = basis.scheduleId,
        AXF_SDC_LKP_Allocation__c = reversalAllocationId,
        AXF_SDC_PKL_Operation__c = OPERATION_REVERSE,
        AXF_SDC_PKL_Classification__c = CLASSIFICATION_NOT_APPLICABLE,
        AXF_SDC_NUM_BasisAmount__c = basis.resolved(),
        AXF_SDC_NUM_PriorNetApplied__c = net,
        AXF_SDC_NUM_EffectiveObligation__c = effective,
        AXF_SDC_NUM_TargetVersion__c = basis.targetVersion,
        AXF_SDC_DAT_EconomicDate__c = System.today(),
        AXF_SDC_NUM_EconomicSequence__c = basis.sequence,
        AXF_SDC_LKP_Actor__c = UserInfo.getUserId(),
        AXF_SDC_DT_CommittedAt__c = System.now()
      );
      Database.insert(decision, AccessLevel.SYSTEM_MODE);
      List<AXF_OBJ_ObligationAdjustment__c> compensations = new List<AXF_OBJ_ObligationAdjustment__c>();
      for (AXF_OBJ_ObligationAdjustment__c rebuilt : compensationSources) {
        compensations.add(
          new AXF_OBJ_ObligationAdjustment__c(
            AXF_OAD_EXI_AdjustmentKey__c = AXF_CLS_IdentityFraming.key(
              new List<Object>{
                ADJUSTMENT_TAG,
                CAPABILITY,
                rebuilt.Id,
                KIND_COMPENSATION
              }
            ),
            AXF_OAD_LKP_FinancialTransaction__c = targetId,
            AXF_OAD_LKP_SettlementDecision__c = decision.Id,
            AXF_OAD_LKP_OriginalAdjustment__c = rebuilt.Id,
            AXF_OAD_LKP_Allocation__c = null,
            AXF_OAD_NUM_SignedAmount__c = -rebuilt.AXF_OAD_NUM_SignedAmount__c,
            AXF_OAD_TXT_CurrencyIsoCode__c = rebuilt.AXF_OAD_TXT_CurrencyIsoCode__c,
            AXF_OAD_PKL_Kind__c = KIND_COMPENSATION,
            AXF_OAD_PKL_Reason__c = rebuilt.AXF_OAD_PKL_Reason__c,
            AXF_OAD_DAT_EffectiveDate__c = System.today(),
            AXF_OAD_LKP_Actor__c = UserInfo.getUserId(),
            AXF_OAD_DT_RecordedAt__c = System.now()
          )
        );
      }
      Database.insert(compensations, AccessLevel.SYSTEM_MODE);
      // Qualquer estorno que invalide uma parcela antes completa retira a referência dela.
      // O ponteiro vigente só é movido para um sobrevivente; a projeção AXF-103 recalcula as
      // estimativas elegíveis a partir da revisão solicitada avançada.
      Basis after = resolve(targetId, false);
      withdrawInvalidated(after, null);
    } finally {
      writing = false;
    }
  }

  /**
   * @description Todo escritor financeiro recheca a cobertura, a versão da base e a obrigação
   * efetiva da classificação completa. Divergência retira o candidato antigo, mesmo que a
   * ocorrência permaneça integralmente liquidada.
   */
  private static void withdrawInvalidated(Basis basis, Id keepDecisionId) {
    Decimal effective = basis.resolved() + adjustmentTotal(basis.row.Id);
    Decimal net = netApplied(basis.row.Id);
    List<AXF_OBJ_SettlementDecision__c> decisions = [
      SELECT
        Id,
        AXF_SDC_NUM_EffectiveObligation__c,
        AXF_SDC_TXT_CoverageHash__c,
        AXF_SDC_NUM_CoverageCount__c,
        AXF_SDC_NUM_TargetVersion__c
      FROM AXF_OBJ_SettlementDecision__c
      WHERE
        AXF_SDC_LKP_FinancialTransaction__c = :basis.row.Id
        AND AXF_SDC_PKL_Classification__c = 'EXPLAINED'
      WITH SYSTEM_MODE
      ORDER BY AXF_SDC_NUM_EconomicSequence__c ASC, Id ASC
    ];
    for (AXF_OBJ_SettlementDecision__c decision : decisions) {
      if (keepDecisionId != null && decision.Id == keepDecisionId) {
        continue;
      }
      Coverage current = coverageFor(
        basis.row.Id,
        decision.AXF_SDC_NUM_TargetVersion__c,
        decision.AXF_SDC_NUM_EffectiveObligation__c
      );
      Decimal snapshotCount = decision.AXF_SDC_NUM_CoverageCount__c;
      Boolean stale =
        current.hash != decision.AXF_SDC_TXT_CoverageHash__c ||
        snapshotCount == null ||
        current.count != snapshotCount.longValue() ||
        decision.AXF_SDC_NUM_EffectiveObligation__c != effective ||
        net != decision.AXF_SDC_NUM_EffectiveObligation__c;
      if (!stale) {
        continue;
      }
      withdrawReference(
        basis,
        decision.Id,
        'Classificação invalidada pela mudança de cobertura ou de obrigação efetiva.'
      );
    }
  }

  private static AXF_OBJ_FinancialSchedule__c scheduleRoot(Id scheduleId) {
    if (scheduleId == null) {
      return null;
    }
    List<AXF_OBJ_FinancialSchedule__c> rows = [
      SELECT
        Id,
        AXF_FSC_EXI_ScheduleKey__c,
        AXF_FSC_LKP_ActiveReference__c,
        AXF_FSC_LKP_ActiveDefinition__c,
        AXF_FSC_NUM_FinancialVersion__c,
        AXF_FSC_NUM_ProjectionRevision__c,
        AXF_FSC_PKL_State__c
      FROM AXF_OBJ_FinancialSchedule__c
      WHERE Id = :scheduleId
      WITH SYSTEM_MODE
    ];
    return rows.isEmpty() ? null : rows[0];
  }

  private static Boolean estimatedSchedule(AXF_OBJ_FinancialSchedule__c root) {
    if (root == null || root.AXF_FSC_LKP_ActiveDefinition__c == null) {
      return false;
    }
    List<AXF_OBJ_ScheduleDefinition__c> definitions = [
      SELECT Id, AXF_SDF_PKL_Method__c
      FROM AXF_OBJ_ScheduleDefinition__c
      WHERE Id = :root.AXF_FSC_LKP_ActiveDefinition__c
      WITH SYSTEM_MODE
    ];
    return !definitions.isEmpty() &&
      definitions[0].AXF_SDF_PKL_Method__c == METHOD_ESTIMATED;
  }

  private static Set<Id> compensatedReferences(Id scheduleId) {
    Set<Id> compensated = new Set<Id>();
    for (AXF_OBJ_ScheduleReference__c row : [
      SELECT AXF_SRF_LKP_Compensates__c
      FROM AXF_OBJ_ScheduleReference__c
      WHERE
        AXF_SRF_LKP_Schedule__c = :scheduleId
        AND AXF_SRF_PKL_Kind__c = 'COMPENSATION'
        AND AXF_SRF_LKP_Compensates__c != NULL
      WITH SYSTEM_MODE
    ]) {
      compensated.add(row.AXF_SRF_LKP_Compensates__c);
    }
    return compensated;
  }

  private static List<AXF_OBJ_ScheduleReference__c> activeReferences(
    Id scheduleId
  ) {
    Set<Id> compensated = compensatedReferences(scheduleId);
    List<AXF_OBJ_ScheduleReference__c> active = new List<AXF_OBJ_ScheduleReference__c>();
    for (AXF_OBJ_ScheduleReference__c row : [
      SELECT
        Id,
        AXF_SRF_NUM_EconomicSequence__c,
        AXF_SRF_NUM_EffectiveSequence__c
      FROM AXF_OBJ_ScheduleReference__c
      WHERE
        AXF_SRF_LKP_Schedule__c = :scheduleId
        AND AXF_SRF_PKL_Kind__c != 'COMPENSATION'
      WITH SYSTEM_MODE
      ORDER BY AXF_SRF_NUM_EconomicSequence__c ASC, Id ASC
    ]) {
      if (!compensated.contains(row.Id)) {
        active.add(row);
      }
    }
    return active;
  }

  /**
   * @description Produz a referência recorrente a partir de uma parcela INTEIRA explicada e
   * integralmente liquidada. Só cronogramas estimados consomem referências recorrentes. A
   * sequência efetiva é a PRÓXIMA sequência absoluta de parcelas — nunca a próxima data de
   * processamento. Uma referência ativa na MESMA ordem econômica é retirada antes, para que a
   * precedência permaneça determinística e nunca ambígua.
   */
  private static Id publishReference(
    SettlementInput input,
    Basis basis,
    SettlementResult result,
    Id decisionId
  ) {
    if (
      input.classification != CLASSIFICATION_EXPLAINED ||
      input.mode != MODE_FULL
    ) {
      return null;
    }
    Integer sequence = effectiveSequenceFor(input, basis);
    if (sequence == null || sequence < 1) {
      return null;
    }
    AXF_OBJ_FinancialSchedule__c root = scheduleRoot(basis.scheduleId);
    if (root == null || !estimatedSchedule(root)) {
      return null;
    }
    AXF_OBJ_ScheduleReference__c superseded;
    for (AXF_OBJ_ScheduleReference__c row : activeReferences(root.Id)) {
      Integer economic = row.AXF_SRF_NUM_EconomicSequence__c == null
        ? 0
        : row.AXF_SRF_NUM_EconomicSequence__c.intValue();
      if (economic == sequence) {
        superseded = row;
      }
    }
    List<AXF_OBJ_ScheduleReference__c> inserts = new List<AXF_OBJ_ScheduleReference__c>();
    if (superseded != null) {
      inserts.add(
        compensationReference(
          root.Id,
          superseded.Id,
          superseded.AXF_SRF_NUM_EconomicSequence__c,
          superseded.AXF_SRF_NUM_EffectiveSequence__c,
          'Substituída por classificação explícita da mesma ordem econômica.'
        )
      );
    }
    AXF_OBJ_ScheduleReference__c reference = new AXF_OBJ_ScheduleReference__c(
      AXF_SRF_EXI_ReferenceKey__c = AXF_CLS_IdentityFraming.key(
        new List<Object>{
          REFERENCE_TAG,
          CAPABILITY,
          root.AXF_FSC_EXI_ScheduleKey__c,
          sequence,
          input.recurringAmount,
          input.operationKey
        }
      ),
      AXF_SRF_LKP_Schedule__c = root.Id,
      AXF_SRF_NUM_EconomicSequence__c = sequence,
      AXF_SRF_NUM_EffectiveSequence__c = sequence + 1,
      AXF_SRF_NUM_RecurringAmount__c = input.recurringAmount,
      AXF_SRF_PKL_Kind__c = REFERENCE_KIND_EVIDENCE,
      AXF_SRF_LKP_SourceAllocation__c = result.allocationId,
      AXF_SRF_LKP_SettlementDecision__c = decisionId,
      AXF_SRF_LKP_Predecessor__c = superseded == null ? null : superseded.Id,
      AXF_SRF_LKP_ConfirmedBy__c = UserInfo.getUserId(),
      AXF_SRF_DT_ConfirmedAt__c = System.now(),
      AXF_SRF_TAL_Reason__c = input.explanation
    );
    inserts.add(reference);
    Database.insert(inserts, AccessLevel.SYSTEM_MODE);
    // O valor publicado é o componente recorrente da parcela inteira — nunca o total
    // liquidado nem o último pagamento.
    bumpSchedule(root, reference.Id);
    return reference.Id;
  }

  private static AXF_OBJ_ScheduleReference__c compensationReference(
    Id scheduleId,
    Id compensatesId,
    Decimal economicSequence,
    Decimal effectiveSequence,
    String reason
  ) {
    return new AXF_OBJ_ScheduleReference__c(
      AXF_SRF_EXI_ReferenceKey__c = AXF_CLS_IdentityFraming.key(
        new List<Object>{ REFERENCE_TAG, CAPABILITY, compensatesId, 'WITHDRAW' }
      ),
      AXF_SRF_LKP_Schedule__c = scheduleId,
      AXF_SRF_NUM_EconomicSequence__c = economicSequence,
      AXF_SRF_NUM_EffectiveSequence__c = effectiveSequence,
      AXF_SRF_NUM_RecurringAmount__c = 0,
      AXF_SRF_PKL_Kind__c = KIND_COMPENSATION,
      AXF_SRF_LKP_Compensates__c = compensatesId,
      AXF_SRF_LKP_ConfirmedBy__c = UserInfo.getUserId(),
      AXF_SRF_DT_ConfirmedAt__c = System.now(),
      AXF_SRF_TAL_Reason__c = reason
    );
  }

  /** @description Retira a referência de uma decisão; o leitor AXF-103 recalcula o sobrevivente. */
  private static void withdrawReference(
    Basis basis,
    Id decisionId,
    String reason
  ) {
    if (basis == null || basis.scheduleId == null || decisionId == null) {
      return;
    }
    AXF_OBJ_FinancialSchedule__c root = scheduleRoot(basis.scheduleId);
    if (root == null) {
      return;
    }
    Set<Id> compensated = compensatedReferences(root.Id);
    List<AXF_OBJ_ScheduleReference__c> inserts = new List<AXF_OBJ_ScheduleReference__c>();
    for (AXF_OBJ_ScheduleReference__c row : [
      SELECT
        Id,
        AXF_SRF_NUM_EconomicSequence__c,
        AXF_SRF_NUM_EffectiveSequence__c
      FROM AXF_OBJ_ScheduleReference__c
      WHERE
        AXF_SRF_LKP_Schedule__c = :root.Id
        AND AXF_SRF_LKP_SettlementDecision__c = :decisionId
        AND AXF_SRF_PKL_Kind__c = 'REALIZATION'
      WITH SYSTEM_MODE
    ]) {
      if (compensated.contains(row.Id)) {
        continue;
      }
      inserts.add(
        compensationReference(
          root.Id,
          row.Id,
          row.AXF_SRF_NUM_EconomicSequence__c,
          row.AXF_SRF_NUM_EffectiveSequence__c,
          reason
        )
      );
    }
    if (inserts.isEmpty()) {
      return;
    }
    Database.insert(inserts, AccessLevel.SYSTEM_MODE);
    bumpSchedule(root, null);
  }

  /**
   * @description Avança a revisão solicitada da projeção e a versão financeira do cronograma
   * atomicamente, e reposiciona o ponteiro da referência vigente no sobrevivente válido.
   */
  private static void bumpSchedule(
    AXF_OBJ_FinancialSchedule__c root,
    Id activeReference
  ) {
    AXF_OBJ_FinancialSchedule__c revision = new AXF_OBJ_FinancialSchedule__c(
      Id = root.Id,
      AXF_FSC_NUM_FinancialVersion__c = version(
          root.AXF_FSC_NUM_FinancialVersion__c
        ) + 1,
      AXF_FSC_NUM_ProjectionRevision__c = version(
          root.AXF_FSC_NUM_ProjectionRevision__c
        ) + 1
    );
    Id resolved = survivingReference(root.Id);
    revision.AXF_FSC_LKP_ActiveReference__c = activeReference == null
      ? (resolved == null ? root.AXF_FSC_LKP_ActiveReference__c : resolved)
      : activeReference;
    referenceWriting = true;
    try {
      Database.update(revision, AccessLevel.SYSTEM_MODE);
    } finally {
      referenceWriting = false;
    }
  }

  private static Id survivingReference(Id scheduleId) {
    AXF_OBJ_ScheduleReference__c survivor;
    for (AXF_OBJ_ScheduleReference__c row : activeReferences(scheduleId)) {
      survivor = row;
    }
    return survivor == null ? null : survivor.Id;
  }

  /** @description O recibo imutável é completado no mesmo comando; nada é visível pela metade. */
  private static void persistResult(SettlementResult result) {
    if (result.decisionId == null) {
      return;
    }
    Database.update(
      new AXF_OBJ_SettlementDecision__c(
        Id = result.decisionId,
        AXF_SDC_TAL_ResultJson__c = JSON.serialize(result)
      ),
      AccessLevel.SYSTEM_MODE
    );
  }
}
