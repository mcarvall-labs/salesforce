/**
 * @description AXF-30: monta e confirma uma conciliacao N:N sob o comando unico
 * `reconciliation.allocation.confirm.v1` (major v1 fixado em 17/09/2026).
 *
 * Contrato (AXF-30-N-N-RECONCILIATION.md, ratificado 17/09/2026):
 * - `AXF_OBJ_Reconciliation__c` / RCN e a raiz ratificada que agrupa N linhas de
 *   `AXF_OBJ_ReconciliationAllocation__c` / RA confirmadas atomicamente; o RA ganha apenas o
 *   Lookup `AXF_RA_LKP_Reconciliation__c` (Restrict), nunca Master-Detail.
 * - Identidade do agregado: `reconciliation-v1 = SHA-256(frame("reconciliation-v1", operationId,
 *   correlationId, sorted(factIdentities), sorted(targetIdentities)))`.
 * - Escopo de idempotencia: operationId + aggregateType(RCN) + ReconciliationKey + idempotencyKey.
 *   O CorrelationId (UUID v4 por intencao humana) faz parte da identidade: um CorrelationId
 *   diferente e outra intencao, nunca um replay. Os 8 campos ratificados nao incluem campo de
 *   idempotency key, entao a chave duravel do escopo e a propria ReconciliationKey.
 * - Ordem de lock determinista, sempre por Id: token ativo do agregado (20) -> fatos de origem
 *   BAT/CCT/FTX manuais (30) -> alvos FTX (50) -> RCN/RA (60). Um registro cujo rank so e
 *   descoberto ao ser lido (um fato declarado como alvo, ou um alvo declarado como fato) aborta
 *   com `LOCK_PLAN_CHANGED`: o plano nao e refeito fora de ordem e o mesmo escopo pode repetir.
 * - Comando all-or-none: um unico Savepoint; qualquer rejeicao desfaz tudo e devolve erro tipado
 *   `{code, reasons}`. O rascunho revisavel e estado local de UI, nunca mutacao server-side propria.
 * - Residual PERSISTIDO (`AXF_RCN_NUM_ResidualMagnitude__c` + `AXF_RCN_TXT_ResidualCurrency__c`):
 *   0 quando CONFIRMED sem sobra; a soma dos residuos de fonte e alvo quando PARTIAL; nulo somente
 *   quando o resultado do commit e desconhecido (`RESULT_UNKNOWN`), porque os 8 campos ratificados
 *   nao incluem um campo de motivo e a picklist ratificada nao aceita um nono valor.
 * - Nenhuma tolerancia, peso, cotacao inventada ou conclusao automatica: moeda divergente sem
 *   evidencia material e `CURRENCY_MISMATCH`, nunca paridade presumida.
 *
 * As linhas sao gravadas pelo contrato AXF-25 (`ALT_CLS_RealizationService.apply`), que e a unica
 * porta de escrita de RA (ALT_CLS_RealizationGuard): tipagem XOR, evidencia FX de reconhecimento,
 * conservacao e bump de versao de alvo/fato permanecem exatamente onde estavam. A identidade
 * canonica da linha (`alloc-v2`) e fornecida pelo agregado, de modo que cada RA tem identidade
 * propria independente da proposta/run.
 */
public with sharing class ALT_CLS_ReconciliationService {
  /** operationId ratificado no OPERATION-REGISTRY (major v1 fixado em 17/09/2026). */
  public static final String OP_CONFIRM = 'reconciliation.allocation.confirm.v1';
  /** Identity tag of the aggregate frame. */
  public static final String IDENTITY_VERSION = 'reconciliation-v1';
  /** Capability of the confirmation; it never grants record access. */
  public static final String CP_CONFIRM = 'AXF_CanConfirmReconciliation';
  public static final String CP_REALIZE = 'AXF_CanRealize';
  /** Frozen policy of the confirmation (Matching v1). */
  public static final String POLICY_VERSION = ALT_CLS_MatchEvidence.MATCHING_POLICY;
  /** Identity of one line, per IMPLEMENTATION-CONTRACTS §3: alloc-v2. */
  public static final String ALLOCATION_IDENTITY_VERSION = 'alloc-v2';
  public static final String TARGET_TYPE = 'FINANCIAL_TRANSACTION';
  /**
   * Economic kind declared by this aggregate. The reconciliation workbench is the matching surface
   * (AXF-MATCHING@1.0.0 owns candidates and evidence), so the kind is MATCHING — never inferred
   * from a description, a category or the statement a line belongs to.
   */
  public static final String ECONOMIC_KIND = 'MATCHING';
  public static final String STATE_CONFIRMING = 'CONFIRMING';
  public static final String STATE_CONFIRMED = 'CONFIRMED';
  /** AXF-140, policy §3: a non-zero residual stays PARTIAL — no approved tolerance zeroes it. */
  public static final String STATE_PARTIAL = ALT_CLS_MatchEvidence.STATE_PARTIAL;
  /** AXF-140, policy §3: material evidence is missing. */
  public static final String STATE_BLOCKED = ALT_CLS_MatchEvidence.STATE_BLOCKED;
  /** Terminal de falha, permitido somente antes de CONFIRMED (IMPLEMENTATION-CONTRACTS §3). */
  public static final String STATE_FAILED = 'FAILED';
  /** Reason carried with the sanctioned `BLOCKED` state of GF-75 (no ninth picklist value). */
  public static final String REASON_RESULT_UNKNOWN = 'RESULT_UNKNOWN';
  public static final String KIND_BANK = 'BANK';
  public static final String KIND_CARD = 'CARD';
  public static final String KIND_MANUAL = 'MANUAL';
  public static final Integer MAX_LINES = 200;
  public static final Integer MAX_KEY = 80;
  public static final Integer MAX_SOURCES = 50;
  public static final Integer MAX_CANDIDATES = 100;
  private static final Integer IDENTITY_MAX = 128;
  private static final Set<String> KINDS = new Set<String>{
    KIND_BANK,
    KIND_CARD,
    KIND_MANUAL
  };
  private static final String BOUNDARY_AXF104 = 'AXF104_OBLIGATION_ADJUSTMENT_PENDING';

  public class ReconciliationException extends Exception {
    public String code;
    public List<String> reasons = new List<String>();
  }

  /** Uma linha pedida: fato de origem tipado, alvo planejado e valor. */
  public class LineInput {
    @AuraEnabled
    public String factKind;
    @AuraEnabled
    public Id factId;
    @AuraEnabled
    public Id targetId;
    @AuraEnabled
    public Decimal amount;
  }

  public class PreviewInput {
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String factKind;
    @AuraEnabled
    public Id factId;
    @AuraEnabled
    public String correlationId;
    @AuraEnabled
    public List<LineInput> lines;
  }

  public class ConfirmInput {
    @AuraEnabled
    public List<LineInput> lines;
    @AuraEnabled
    public Decimal expectedVersion;
    @AuraEnabled
    public String idempotencyKey;
    @AuraEnabled
    public String correlationId;
  }

  /** Tentativa humana reenviada depois de um timeout: a mesma intencao, sem inventar identidade. */
  public class AttemptInput {
    @AuraEnabled
    public String correlationId;
    @AuraEnabled
    public List<LineInput> lines;
  }

  public class SourceView {
    @AuraEnabled
    public Id factId;
    @AuraEnabled
    public String factKind;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public Date factDate;
    @AuraEnabled
    public Decimal magnitude;
    @AuraEnabled
    public Decimal residual;
    @AuraEnabled
    public String currencyIso;
    @AuraEnabled
    public String direction;
    @AuraEnabled
    public Decimal version;
  }

  public class CandidateView {
    @AuraEnabled
    public Id targetId;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public Date dueDate;
    @AuraEnabled
    public Decimal magnitude;
    @AuraEnabled
    public Decimal available;
    @AuraEnabled
    public Decimal residual;
    @AuraEnabled
    public String currencyIso;
    @AuraEnabled
    public String direction;
    @AuraEnabled
    public Decimal version;
    @AuraEnabled
    public Boolean linkable = false;
    @AuraEnabled
    public List<String> reasons = new List<String>();
    /** Policy §2: candidates are presented, never selected, scored or confirmed here. */
    @AuraEnabled
    public String state = ALT_CLS_MatchEvidence.STATE_CONSULTATIVE;
    @AuraEnabled
    public List<ALT_CLS_MatchEvidence.EvidenceView> evidence = new List<ALT_CLS_MatchEvidence.EvidenceView>();
    /** Presentation only: exact external identity appears first; it selects nothing. */
    @AuraEnabled
    public Boolean identityExact = false;
    @AuraEnabled
    public Boolean lowEvidence = false;
  }

  /** Fonte, alvo, disponivel, alocado, residual e moeda de uma linha: tudo vem do servico. */
  public class LineView {
    @AuraEnabled
    public String factKind;
    @AuraEnabled
    public Id factId;
    @AuraEnabled
    public String factLabel;
    @AuraEnabled
    public Id targetId;
    @AuraEnabled
    public String targetLabel;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public Decimal available;
    @AuraEnabled
    public Decimal allocated;
    @AuraEnabled
    public Decimal residual;
    @AuraEnabled
    public Decimal sourceResidual;
    @AuraEnabled
    public String currencyIso;
    @AuraEnabled
    public String state;
    @AuraEnabled
    public Id allocationId;
    @AuraEnabled
    public String allocationKey;
    @AuraEnabled
    public List<String> reasons = new List<String>();
  }

  public class WorkbenchView {
    @AuraEnabled
    public String policyVersion = POLICY_VERSION;
    @AuraEnabled
    public String state = ALT_CLS_MatchEvidence.STATE_CONSULTATIVE;
    @AuraEnabled
    public Id reconciliationId;
    @AuraEnabled
    public String reconciliationKey;
    @AuraEnabled
    public Decimal expectedVersion = 0;
    @AuraEnabled
    public Decimal residualMagnitude;
    @AuraEnabled
    public String residualCurrency;
    @AuraEnabled
    public Datetime effectiveAt;
    @AuraEnabled
    public Decimal allocatedTotal = 0;
    @AuraEnabled
    public Boolean unknownOutcome = false;
    @AuraEnabled
    public SourceView source;
    @AuraEnabled
    public List<SourceView> sources = new List<SourceView>();
    @AuraEnabled
    public List<CandidateView> candidates = new List<CandidateView>();
    @AuraEnabled
    public List<LineView> lines = new List<LineView>();
  }

  public class ConfirmResult {
    @AuraEnabled
    public String policyVersion = POLICY_VERSION;
    @AuraEnabled
    public Id reconciliationId;
    @AuraEnabled
    public String reconciliationKey;
    @AuraEnabled
    public String state;
    @AuraEnabled
    public Boolean replayed = false;
    @AuraEnabled
    public Decimal version;
    @AuraEnabled
    public Decimal residualMagnitude;
    @AuraEnabled
    public String residualCurrency;
    @AuraEnabled
    public Datetime effectiveAt;
    @AuraEnabled
    public Decimal allocatedTotal = 0;
    @AuraEnabled
    public List<LineView> lines = new List<LineView>();
    @AuraEnabled
    public List<String> boundaries = new List<String>();
  }

  /** Fato de origem tipado, resolvido por Id (rank 30). */
  private class Fact {
    String kind;
    Id id;
    String label;
    String description;
    String identity;
    Id accountId;
    Decimal magnitude;
    String currencyIso;
    String direction;
    Decimal version;
    Date factDate;
  }

  /** Alvo planejado FTX (rank 50). */
  private class Target {
    Id id;
    String label;
    String description;
    String identity;
    Id accountId;
    Decimal magnitude;
    Decimal obligation;
    String currencyIso;
    String direction;
    String planKind;
    Decimal version;
    Date dueDate;
  }

  /** Net applied and obligation adjustments, read once per transaction, in bulk. */
  private class Amounts {
    Map<Id, Decimal> byTarget = new Map<Id, Decimal>();
    Map<Id, Decimal> byFact = new Map<Id, Decimal>();
    Map<Id, Decimal> adjustments = new Map<Id, Decimal>();
    Map<String, Decimal> byAllocationKey = new Map<String, Decimal>();

    Decimal target(Id id) {
      return byTarget.containsKey(id) ? byTarget.get(id) : 0;
    }
    Decimal fact(Id id) {
      return byFact.containsKey(id) ? byFact.get(id) : 0;
    }
    Decimal adjustment(Id id) {
      return adjustments.containsKey(id) ? adjustments.get(id) : 0;
    }
  }

  // ------------------------------------------------------------------ capability

  /** @description Capability of the confirmation plus the AXF-25 realization capability. */
  public static void requireAccess() {
    if (
      !FeatureManagement.checkPermission(CP_CONFIRM) ||
      !FeatureManagement.checkPermission(CP_REALIZE)
    ) {
      throw failure('UNAVAILABLE', new List<String>());
    }
  }

  // ------------------------------------------------------------------ preview

  /**
   * @description Read-only evaluation of a draft: eligible sources of one holder, consultative
   * candidates of one source and, for the requested lines, source/target/available/allocated/
   * residual/currency. Nothing is written and nothing is concluded.
   */
  public WorkbenchView preview(PreviewInput input) {
    requireAccess();
    if (input == null) {
      throw failure('INVALID_INPUT', new List<String>());
    }
    WorkbenchView view = new WorkbenchView();
    if (input.factId == null) {
      view.sources = sources(input.accountId);
      return view;
    }
    Fact fact = resolveFact(input.factKind, input.factId);
    SourceView source = sourceView(fact);
    source.residual =
      fact.magnitude -
      netAmounts(null, new Set<Id>{ fact.id }).fact(fact.id);
    view.source = source;
    view.candidates = candidates(fact);
    if (input.lines != null && !input.lines.isEmpty()) {
      Plan plan = plan(input.lines, input.correlationId);
      evaluate(plan, view);
    }
    return view;
  }

  // ------------------------------------------------------------------ confirm

  /**
   * @description `reconciliation.allocation.confirm.v1`: valida autorizacao, versao, saldo,
   * moeda e conservacao sob a ordem de lock aprovada e grava RCN + N RA em um unico Savepoint.
   */
  public ConfirmResult confirm(ConfirmInput input) {
    requireAccess();
    if (
      input == null ||
      input.lines == null ||
      input.lines.isEmpty() ||
      input.lines.size() > MAX_LINES ||
      String.isBlank(input.idempotencyKey) ||
      input.idempotencyKey.length() > MAX_KEY
    ) {
      throw failure('INVALID_INPUT', new List<String>());
    }
    requireUuid(input.correlationId);
    Plan plan = plan(input.lines, input.correlationId);
    // Rank 20: the aggregate identity token of this intention.
    AXF_OBJ_Reconciliation__c aggregate = lockAggregate(plan.key);
    if (aggregate != null) {
      if (unknownOutcome(aggregate)) {
        // GF-75: the retry stays refused until an authoritative query resolves the outcome.
        throw failure('CONFLICT', new List<String>{ REASON_RESULT_UNKNOWN });
      }
      checkVersion(aggregate, input.expectedVersion);
      if (!STATE_FAILED.equals(aggregate.AXF_RCN_PKL_State__c)) {
        return replay(plan, aggregate);
      }
    }
    Savepoint point = Database.setSavepoint();
    try {
      if (aggregate == null) {
        aggregate = new AXF_OBJ_Reconciliation__c(
          AXF_RCN_PKL_State__c = STATE_CONFIRMING,
          AXF_RCN_NUM_Version__c = 0,
          AXF_RCN_EXI_ReconciliationKey__c = plan.key,
          AXF_RCN_TXT_CorrelationId__c = plan.correlationId,
          AXF_RCN_TXT_PolicyVersion__c = POLICY_VERSION,
          OwnerId = ownerOf(plan.facts[0].accountId)
        );
        Database.insert(aggregate, AccessLevel.USER_MODE);
        grantProposerAccess(aggregate.Id, aggregate.OwnerId);
      } else {
        aggregate.AXF_RCN_PKL_State__c = STATE_CONFIRMING;
        aggregate.AXF_RCN_NUM_Version__c =
          value(aggregate.AXF_RCN_NUM_Version__c) + 1;
        Database.update(aggregate, AccessLevel.USER_MODE);
      }
      // Ranks 30 and 50: every source fact and every target is locked, in Id order, before any write.
      lockFacts(plan.facts);
      lockTargets(plan.targets.values());
      Amounts amounts = amounts(plan);
      validate(plan, amounts);
      write(plan, aggregate, amounts);
      return result(read(aggregate, durablePlan(aggregate, plan)), false);
    } catch (ReconciliationException failure) {
      Database.rollback(point);
      throw failure;
    } catch (ALT_CLS_RealizationService.RealizationException failure) {
      Database.rollback(point);
      // Safety net: the per-line writer already maps its own rejection with the line index.
      throw mapRealization(failure, -1);
    } catch (Exception failure) {
      Database.rollback(point);
      throw failure('UNEXPECTED', new List<String>());
    }
  }

  // ------------------------------------------------------------------ result unknown

  /**
   * @description GF-75: parks an intention whose submit outcome is unknown. The aggregate stays
   * `BLOCKED` with a null residual (unknown outcome) and every later retry under the same
   * CorrelationId is refused with `CONFLICT` until an authoritative query resolves it. Idempotent:
   * parking an already parked intention returns the same state, and an already resolved intention
   * conflicts instead of overwriting its outcome.
   */
  public WorkbenchView parkResultUnknown(AttemptInput input) {
    requireAccess();
    if (input == null) {
      throw failure('INVALID_INPUT', new List<String>());
    }
    requireUuid(input.correlationId);
    Plan plan = plan(input.lines, input.correlationId);
    Savepoint point = Database.setSavepoint();
    try {
      AXF_OBJ_Reconciliation__c aggregate = lockAggregate(plan.key);
      if (aggregate == null) {
        aggregate = new AXF_OBJ_Reconciliation__c(
          AXF_RCN_PKL_State__c = STATE_BLOCKED,
          AXF_RCN_NUM_Version__c = 1,
          AXF_RCN_EXI_ReconciliationKey__c = plan.key,
          AXF_RCN_TXT_CorrelationId__c = plan.correlationId,
          AXF_RCN_TXT_PolicyVersion__c = POLICY_VERSION,
          OwnerId = ownerOf(plan.facts[0].accountId)
        );
        Database.insert(aggregate, AccessLevel.USER_MODE);
        grantProposerAccess(aggregate.Id, aggregate.OwnerId);
        return viewOf(aggregate);
      }
      // An existing outcome is reported as it is and never overwritten: parking is idempotent and a
      // resolved aggregate keeps its durable state.
      return viewOf(aggregate);
    } catch (ReconciliationException failure) {
      Database.rollback(point);
      throw failure;
    } catch (Exception failure) {
      Database.rollback(point);
      throw failure('UNEXPECTED', new List<String>());
    }
  }

  /**
   * @description GF-75: authoritative query that resolves an unknown outcome without duplicating an
   * allocation. A durable line set resolves the aggregate to its derived state; no line at all
   * closes it as `FAILED` (allowed only before CONFIRMED) so the same intention may be attempted
   * again under the same identity.
   */
  public WorkbenchView resolveResult(AttemptInput input) {
    requireAccess();
    if (input == null) {
      throw failure('INVALID_INPUT', new List<String>());
    }
    requireUuid(input.correlationId);
    Plan plan = plan(input.lines, input.correlationId);
    AXF_OBJ_Reconciliation__c aggregate = lockAggregate(plan.key);
    if (aggregate == null) {
      // Nothing durable exists for this intention: the outcome is known to be "no effect".
      WorkbenchView view = new WorkbenchView();
      view.reconciliationKey = plan.key;
      view.state = STATE_FAILED;
      return view;
    }
    Plan durable = durablePlan(aggregate, plan);
    if (durable.lines.isEmpty()) {
      aggregate.AXF_RCN_PKL_State__c = STATE_FAILED;
      aggregate.AXF_RCN_NUM_ResidualMagnitude__c = null;
      aggregate.AXF_RCN_TXT_ResidualCurrency__c = null;
      aggregate.AXF_RCN_DT_EffectiveAt__c = null;
      aggregate.AXF_RCN_NUM_Version__c =
        value(aggregate.AXF_RCN_NUM_Version__c) + 1;
      Database.update(aggregate, AccessLevel.USER_MODE);
      return viewOf(aggregate);
    }
    String state = aggregate.AXF_RCN_PKL_State__c;
    if (
      STATE_CONFIRMED.equals(state) ||
      STATE_PARTIAL.equals(state) ||
      STATE_FAILED.equals(state)
    ) {
      // Already resolved: the authoritative answer is the durable one and is never rewritten.
      return read(aggregate, durable);
    }
    // CONFIRMING or BLOCKED: the outcome and the residual are recomputed from the durable rows, so
    // a resolution (for example the recognition evidence arriving) closes the aggregate here.
    return close(durable, aggregate, true);
  }

  // ------------------------------------------------------------------ planning

  /** Plano materializado de uma intencao: fatos, alvos, linhas e a identidade do agregado. */
  private class Plan {
    String correlationId;
    String key;
    List<LineInput> lines = new List<LineInput>();
    List<Fact> facts = new List<Fact>();
    Map<Id, Target> targets = new Map<Id, Target>();
    Map<String, Fact> factsByKey = new Map<String, Fact>();
    Map<Id, AXF_OBJ_ReconciliationAllocation__c> committed = new Map<Id, AXF_OBJ_ReconciliationAllocation__c>();
    Map<String, Decimal> amountsByFact = new Map<String, Decimal>();
    Map<Id, Decimal> amountsByTarget = new Map<Id, Decimal>();
    List<String> allocationKeys = new List<String>();
  }

  /**
   * @description Materializes the plan of one intention. Facts and targets are read without a lock
   * here (the command locks them in rank order); the identity comes from the canonical identities
   * of the records, never from a Salesforce record id where a durable identity exists.
   */
  private Plan plan(List<LineInput> lines, String correlationId) {
    if (
      lines == null ||
      lines.isEmpty() ||
      lines.size() > MAX_LINES ||
      String.isBlank(correlationId)
    ) {
      throw failure('INVALID_INPUT', new List<String>());
    }
    Plan result = new Plan();
    result.correlationId = correlationId;
    result.lines = lines;
    Set<String> factIdentities = new Set<String>();
    Set<String> targetIdentities = new Set<String>();
    Set<Id> targetIds = new Set<Id>();
    for (LineInput line : lines) {
      if (
        line == null ||
        line.factId == null ||
        line.targetId == null ||
        line.amount == null ||
        line.amount <= 0 ||
        line.amount != line.amount.setScale(2)
      ) {
        throw failure('INVALID_INPUT', new List<String>());
      }
      String factKey = key(factKindOf(line.factId), line.factId);
      if (!result.factsByKey.containsKey(factKey)) {
        Fact fact = resolveFact(line.factKind, line.factId);
        result.factsByKey.put(factKey, fact);
        result.facts.add(fact);
        factIdentities.add(fact.identity);
      }
      if (!targetIds.contains(line.targetId)) {
        if (result.targets.size() >= MAX_LINES) {
          throw failure('INVALID_INPUT', new List<String>());
        }
        targetIds.add(line.targetId);
        Target target = resolveTarget(line.targetId);
        result.targets.put(target.id, target);
        targetIdentities.add(target.identity);
      }
      result.amountsByFact.put(
        factKey,
        value(result.amountsByFact.get(factKey)) + line.amount
      );
      result.amountsByTarget.put(
        line.targetId,
        value(result.amountsByTarget.get(line.targetId)) + line.amount
      );
      result.allocationKeys.add(
        allocationIdentity(
          result.factsByKey.get(factKey).identity,
          result.targets.get(line.targetId).identity
        )
      );
    }
    result.key = reconciliationKey(
      correlationId,
      factIdentities,
      targetIdentities
    );
    return result;
  }

  /**
   * @description `reconciliation-v1`. A lista ordenada de identidades e o proprio conjunto: dois
   * comandos com o mesmo conjunto e a mesma intencao humana produzem a mesma chave.
   */
  @TestVisible
  private static String reconciliationKey(
    String correlationId,
    Set<String> factIdentities,
    Set<String> targetIdentities
  ) {
    List<String> facts = new List<String>(factIdentities);
    List<String> targets = new List<String>(targetIdentities);
    facts.sort();
    targets.sort();
    List<Object> frame = new List<Object>{ IDENTITY_VERSION, OP_CONFIRM };
    frame.add(correlationId);
    frame.add(String.join(facts, ','));
    frame.add(String.join(targets, ','));
    return AXF_CLS_IdentityFraming.key(frame);
  }

  /** @description `alloc-v2` of one line, per IMPLEMENTATION-CONTRACTS §3. */
  @TestVisible
  private static String allocationIdentity(
    String factIdentity,
    String targetIdentity
  ) {
    return AXF_CLS_IdentityFraming.key(
      new List<Object>{
        ALLOCATION_IDENTITY_VERSION,
        factIdentity,
        TARGET_TYPE,
        targetIdentity,
        ECONOMIC_KIND
      }
    );
  }

  private static String key(String kind, Id id) {
    return kind + '|' + id;
  }

  private String requireUuid(String correlationId) {
    if (
      String.isBlank(correlationId) ||
      correlationId.length() != 36 ||
      !Pattern.matches(
        '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
        correlationId
      )
    ) {
      throw failure('INVALID_INPUT', new List<String>());
    }
    return correlationId;
  }

  private static String factKindOf(Id factId) {
    return factId.getSObjectType() ==
      AXF_OBJ_BankAccountTransaction__c.SObjectType
      ? KIND_BANK
      : factId.getSObjectType() ==
          AXF_OBJ_CreditCardTransaction__c.SObjectType
          ? KIND_CARD
          : factId.getSObjectType() ==
              AXF_OBJ_FinancialTransaction__c.SObjectType
              ? KIND_MANUAL
              : null;
  }

  /**
   * Durable external identity of a financial transaction. The client request id is the canonical
   * external identity of the occurrence: org-wide unique, required and independent of the run that
   * proposed it. A record id is never used while that identity exists.
   */
  private static String externalIdentity(
    AXF_OBJ_FinancialTransaction__c row
  ) {
    return String.isBlank(row.AXF_FTX_EXI_ClientRequestId__c)
      ? String.valueOf(row.Id)
      : row.AXF_FTX_EXI_ClientRequestId__c.left(IDENTITY_MAX);
  }

  // ------------------------------------------------------------------ records

  private Fact resolveFact(String declaredKind, Id factId) {
    String kind = factKindOf(factId);
    if (kind == null) {
      throw failure('INVALID_INPUT', new List<String>());
    }
    if (
      String.isNotBlank(declaredKind) &&
      declaredKind.toUpperCase() != kind
    ) {
      throw failure('INVALID_INPUT', new List<String>());
    }
    Fact fact = new Fact();
    fact.id = factId;
    fact.kind = kind;
    if (kind == KIND_BANK) {
      List<AXF_OBJ_BankAccountTransaction__c> rows = [
        SELECT
          Id,
          Name,
          AXF_BAT_EXI_SourceKey__c,
          AXF_BAT_NUM_Magnitude__c,
          AXF_BAT_NUM_Version__c,
          AXF_BAT_TXT_CurrencyIsoCode__c,
          AXF_BAT_PKL_Direction__c,
          AXF_BAT_DAT_Date__c,
          AXF_BAT_TXT_Description__c,
          AXF_BAT_MDR_BankAccount__r.AXF_BA_LKP_Account__c
        FROM AXF_OBJ_BankAccountTransaction__c
        WHERE Id = :factId
        WITH USER_MODE
        LIMIT 1
      ];
      if (rows.isEmpty()) {
        throw failure('NOT_ACCESSIBLE', new List<String>());
      }
      fact.label = rows[0].Name;
      fact.identity = rows[0].AXF_BAT_EXI_SourceKey__c;
      fact.magnitude = rows[0].AXF_BAT_NUM_Magnitude__c;
      fact.version = value(rows[0].AXF_BAT_NUM_Version__c);
      fact.currencyIso = rows[0].AXF_BAT_TXT_CurrencyIsoCode__c;
      fact.direction = rows[0].AXF_BAT_PKL_Direction__c;
      fact.factDate = rows[0].AXF_BAT_DAT_Date__c;
      fact.description = rows[0].AXF_BAT_TXT_Description__c;
      fact.accountId = rows[0].AXF_BAT_MDR_BankAccount__r
        ?.AXF_BA_LKP_Account__c;
    } else if (kind == KIND_CARD) {
      List<AXF_OBJ_CreditCardTransaction__c> rows = [
        SELECT
          Id,
          Name,
          AXF_CCT_EXI_SourceKey__c,
          AXF_CCT_NUM_Magnitude__c,
          AXF_CCT_NUM_Version__c,
          AXF_CCT_TXT_CurrencyIsoCode__c,
          AXF_CCT_PKL_Direction__c,
          AXF_CCT_DAT_Date__c,
          AXF_CCT_TXT_Description__c,
          AXF_CCT_MDR_CreditCard__r.AXF_CC_LKP_Account__c
        FROM AXF_OBJ_CreditCardTransaction__c
        WHERE Id = :factId
        WITH USER_MODE
        LIMIT 1
      ];
      if (rows.isEmpty()) {
        throw failure('NOT_ACCESSIBLE', new List<String>());
      }
      fact.label = rows[0].Name;
      fact.identity = rows[0].AXF_CCT_EXI_SourceKey__c;
      fact.magnitude = rows[0].AXF_CCT_NUM_Magnitude__c;
      fact.version = value(rows[0].AXF_CCT_NUM_Version__c);
      fact.currencyIso = rows[0].AXF_CCT_TXT_CurrencyIsoCode__c;
      fact.direction = rows[0].AXF_CCT_PKL_Direction__c;
      fact.factDate = rows[0].AXF_CCT_DAT_Date__c;
      fact.description = rows[0].AXF_CCT_TXT_Description__c;
      fact.accountId = rows[0].AXF_CCT_MDR_CreditCard__r
        ?.AXF_CC_LKP_Account__c;
    } else {
      List<AXF_OBJ_FinancialTransaction__c> rows = [
        SELECT
          Id,
          Name,
          AXF_FTX_NUM_Magnitude__c,
          AXF_FTX_NUM_Version__c,
          AXF_FTX_TXT_CurrencyIsoCode__c,
          AXF_FTX_PKL_Direction__c,
          AXF_FTX_PKL_PlanKind__c,
          AXF_FTX_DAT_PurchaseDate__c,
          AXF_FTX_TXT_Description__c,
          AXF_FTX_EXI_ClientRequestId__c,
          AXF_FTX_LKP_Account__c
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE Id = :factId
        WITH USER_MODE
        LIMIT 1
      ];
      if (rows.isEmpty()) {
        throw failure('NOT_ACCESSIBLE', new List<String>());
      }
      if (rows[0].AXF_FTX_PKL_PlanKind__c != 'CASH_FACT') {
        // Rank 50 discovered while planning rank 30: abort instead of locking out of order.
        throw failure('LOCK_PLAN_CHANGED', new List<String>());
      }
      fact.label = rows[0].Name;
      fact.identity = externalIdentity(rows[0]);
      fact.magnitude = rows[0].AXF_FTX_NUM_Magnitude__c;
      fact.version = value(rows[0].AXF_FTX_NUM_Version__c);
      fact.currencyIso = rows[0].AXF_FTX_TXT_CurrencyIsoCode__c;
      fact.direction = rows[0].AXF_FTX_PKL_Direction__c;
      fact.factDate = rows[0].AXF_FTX_DAT_PurchaseDate__c;
      fact.description = rows[0].AXF_FTX_TXT_Description__c;
      fact.accountId = rows[0].AXF_FTX_LKP_Account__c;
    }
    if (
      String.isBlank(fact.identity) ||
      fact.magnitude == null ||
      fact.magnitude <= 0 ||
      String.isBlank(fact.currencyIso) ||
      fact.accountId == null ||
      fact.direction == null
    ) {
      throw failure('FACT_NOT_RECONCILABLE', new List<String>());
    }
    fact.identity = fact.identity.left(IDENTITY_MAX);
    return fact;
  }

  private Target resolveTarget(Id targetId) {
    if (
      targetId.getSObjectType() !=
      AXF_OBJ_FinancialTransaction__c.SObjectType
    ) {
      // A source fact of rank 30 declared as a target is a rank discovery that came too late:
      // the plan is never relocked out of order, and the same scope may be submitted again.
      throw failure('LOCK_PLAN_CHANGED', new List<String>());
    }
    List<AXF_OBJ_FinancialTransaction__c> rows = [
      SELECT
        Id,
        Name,
        AXF_FTX_NUM_Magnitude__c,
        AXF_FTX_NUM_CurrentBasis__c,
        AXF_FTX_NUM_Version__c,
        AXF_FTX_TXT_CurrencyIsoCode__c,
        AXF_FTX_PKL_Direction__c,
        AXF_FTX_PKL_PlanKind__c,
        AXF_FTX_EXI_ClientRequestId__c,
        AXF_FTX_DAT_DueDate__c,
        AXF_FTX_TXT_Description__c,
        AXF_FTX_LKP_Account__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE Id = :targetId
      WITH USER_MODE
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      throw failure('NOT_ACCESSIBLE', new List<String>());
    }
    if (rows[0].AXF_FTX_PKL_PlanKind__c == 'CASH_FACT') {
      // Rank 30 discovered while planning rank 50: abort instead of locking out of order.
      throw failure('LOCK_PLAN_CHANGED', new List<String>());
    }
    Target target = new Target();
    target.id = rows[0].Id;
    target.label = rows[0].Name;
    target.description = rows[0].AXF_FTX_TXT_Description__c;
    target.identity = externalIdentity(rows[0]);
    target.accountId = rows[0].AXF_FTX_LKP_Account__c;
    target.magnitude = rows[0].AXF_FTX_NUM_Magnitude__c;
    target.obligation = rows[0].AXF_FTX_NUM_CurrentBasis__c;
    target.currencyIso = rows[0].AXF_FTX_TXT_CurrencyIsoCode__c;
    target.direction = rows[0].AXF_FTX_PKL_Direction__c;
    target.planKind = rows[0].AXF_FTX_PKL_PlanKind__c;
    target.version = value(rows[0].AXF_FTX_NUM_Version__c);
    target.dueDate = rows[0].AXF_FTX_DAT_DueDate__c;
    if (
      target.magnitude == null ||
      target.accountId == null ||
      target.currencyIso == null ||
      target.direction == null
    ) {
      throw failure('INVALID_INPUT', new List<String>());
    }
    return target;
  }

  /**
   * Rank 20: the aggregate identity token of this intention, locked. System visibility is required:
   * the identity is org-wide unique, so a row of another owner must never be mistaken for absence.
   */
  private AXF_OBJ_Reconciliation__c lockAggregate(String reconciliationKey) {
    List<AXF_OBJ_Reconciliation__c> rows = [
      SELECT
        Id,
        Name,
        AXF_RCN_PKL_State__c,
        AXF_RCN_NUM_Version__c,
        AXF_RCN_EXI_ReconciliationKey__c,
        AXF_RCN_TXT_CorrelationId__c,
        AXF_RCN_TXT_ResidualCurrency__c,
        AXF_RCN_NUM_ResidualMagnitude__c,
        AXF_RCN_DT_EffectiveAt__c,
        AXF_RCN_TXT_PolicyVersion__c,
        OwnerId
      FROM AXF_OBJ_Reconciliation__c
      WHERE AXF_RCN_EXI_ReconciliationKey__c = :reconciliationKey
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    return rows.isEmpty() ? null : rows[0];
  }

  private AXF_OBJ_Reconciliation__c aggregateByKey(String reconciliationKey) {
    List<AXF_OBJ_Reconciliation__c> rows = [
      SELECT
        Id,
        Name,
        AXF_RCN_PKL_State__c,
        AXF_RCN_NUM_Version__c,
        AXF_RCN_EXI_ReconciliationKey__c,
        AXF_RCN_TXT_CorrelationId__c,
        AXF_RCN_TXT_ResidualCurrency__c,
        AXF_RCN_NUM_ResidualMagnitude__c,
        AXF_RCN_DT_EffectiveAt__c,
        AXF_RCN_TXT_PolicyVersion__c,
        OwnerId
      FROM AXF_OBJ_Reconciliation__c
      WHERE AXF_RCN_EXI_ReconciliationKey__c = :reconciliationKey
      WITH USER_MODE
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0];
  }

  /**
   * Rank 30: every source fact, locked in Id order, one query per typed object. A record that turns
   * out to be a plan is a rank-50 discovery inside rank 30 and aborts the command.
   */
  private void lockFacts(List<Fact> facts) {
    Set<Id> bank = new Set<Id>();
    Set<Id> card = new Set<Id>();
    for (Fact fact : facts) {
      if (fact.kind == KIND_BANK) {
        bank.add(fact.id);
      } else if (fact.kind == KIND_CARD) {
        card.add(fact.id);
      }
    }
    if (!bank.isEmpty()) {
      List<AXF_OBJ_BankAccountTransaction__c> rows = [
        SELECT Id
        FROM AXF_OBJ_BankAccountTransaction__c
        WHERE Id IN :bank
        WITH USER_MODE
        FOR UPDATE
      ];
      if (rows.size() != bank.size()) {
        throw failure('NOT_ACCESSIBLE', new List<String>());
      }
    }
    if (!card.isEmpty()) {
      List<AXF_OBJ_CreditCardTransaction__c> rows = [
        SELECT Id
        FROM AXF_OBJ_CreditCardTransaction__c
        WHERE Id IN :card
        WITH USER_MODE
        FOR UPDATE
      ];
      if (rows.size() != card.size()) {
        throw failure('NOT_ACCESSIBLE', new List<String>());
      }
    }
  }

  /** Rank 50: every target, locked in one Id-ordered query. */
  private void lockTargets(List<Target> targets) {
    Set<Id> ids = new Set<Id>();
    for (Target target : targets) {
      ids.add(target.id);
    }
    if (ids.isEmpty()) {
      return;
    }
    List<AXF_OBJ_FinancialTransaction__c> rows = [
      SELECT Id
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE Id IN :ids
      WITH USER_MODE
      FOR UPDATE
    ];
    if (rows.size() != ids.size()) {
      throw failure('NOT_ACCESSIBLE', new List<String>());
    }
  }

  // ------------------------------------------------------------------ validation

  /**
   * @description Whole-command validation: authorization, currency, direction and conservation.
   * Any reason rejects the command entirely; nothing partial is persisted.
   */
  private void validate(Plan plan, Amounts amounts) {
    Set<Id> authorized = authorizedAccounts();
    List<String> reasons = new List<String>();
    for (Fact fact : plan.facts) {
      if (!authorized.contains(fact.accountId)) {
        reasons.add('UNAUTHORIZED_SOURCE');
      }
    }
    for (Target target : plan.targets.values()) {
      if (!authorized.contains(target.accountId)) {
        reasons.add('UNAUTHORIZED_TARGET');
      }
    }
    if (!reasons.isEmpty()) {
      // A partial authorization rejects the whole command and reveals no private existence.
      throw failure('NOT_ACCESSIBLE', new List<String>());
    }
    for (LineInput line : plan.lines) {
      Fact fact = factOf(plan, line);
      Target target = plan.targets.get(line.targetId);
      if (target == null) {
        throw failure('INVALID_INPUT', new List<String>());
      }
      if (fact.currencyIso != target.currencyIso) {
        reasons.add('CURRENCY_MISMATCH');
      } else if (fact.accountId != target.accountId) {
        reasons.add('HOLDER_MISMATCH');
      } else if (fact.direction != target.direction) {
        reasons.add('DIRECTION_MISMATCH');
      }
    }
    if (!reasons.isEmpty()) {
      throw failure('CURRENCY_MISMATCH', reasons);
    }
    for (Fact fact : plan.facts) {
      Decimal available = fact.magnitude - amounts.fact(fact.id);
      if (plan.amountsByFact.get(key(fact.kind, fact.id)) > available) {
        reasons.add('SOURCE_CAPACITY_EXCEEDED');
      }
    }
    for (Target target : plan.targets.values()) {
      Decimal available =
        capacity(target, amounts) - amounts.target(target.id);
      if (plan.amountsByTarget.get(target.id) > available) {
        reasons.add('TARGET_CAPACITY_EXCEEDED');
      }
    }
    if (!reasons.isEmpty()) {
      // GF-02: an over-allocation rejects the whole command; no RA and no RCN survives.
      throw failure('VALUE_CONSERVATION', reasons);
    }
  }

  /**
   * @description Capacity of a target: the effective obligation (current basis plus signed
   * adjustments) when it exists, exactly as AXF-104 defines it; otherwise the immutable magnitude.
   * A factual plan carries no forecast debt, so its capacity is its magnitude.
   */
  private Decimal capacity(Target target, Amounts amounts) {
    if (target.planKind == 'ACTUAL_ONLY') {
      return target.magnitude;
    }
    Decimal basis = target.obligation == null
      ? target.magnitude
      : target.obligation;
    return basis + amounts.adjustment(target.id);
  }

  /** Net applied per target, per fact and per canonical allocation identity, in bulk. */
  private Amounts amounts(Plan plan) {
    Set<Id> targetIds = new Set<Id>();
    for (Target target : plan.targets.values()) {
      targetIds.add(target.id);
    }
    Set<Id> factIds = new Set<Id>();
    for (Fact fact : plan.facts) {
      factIds.add(fact.id);
    }
    Amounts result = netAmounts(targetIds, factIds);
    // A bind must be a plain variable: the field expression never reaches the query directly.
    List<String> allocationKeys = plan.allocationKeys;
    if (!allocationKeys.isEmpty()) {
      for (AXF_OBJ_ReconciliationAllocation__c row : [
        SELECT
          Id,
          AXF_RA_EXI_AllocationKey__c,
          AXF_RA_PKL_Kind__c,
          AXF_RA_NUM_Magnitude__c,
          AXF_RA_TXT_CurrencyIsoCode__c,
          AXF_RA_LKP_FinancialTransaction__c,
          AXF_RA_LKP_Reconciliation__c
        FROM AXF_OBJ_ReconciliationAllocation__c
        WHERE AXF_RA_EXI_AllocationKey__c IN :allocationKeys
        WITH SYSTEM_MODE
      ]) {
        plan.committed.put(row.Id, row);
        result.byAllocationKey.put(
          row.AXF_RA_EXI_AllocationKey__c,
          (row.AXF_RA_PKL_Kind__c == 'REVERSAL' ? -1 : 1) *
            value(row.AXF_RA_NUM_Magnitude__c)
        );
      }
    }
    return result;
  }

  /** Net applied (applications minus reversals) of the given targets and facts, in bulk. */
  private Amounts netAmounts(Set<Id> targetIds, Set<Id> factIds) {
    Amounts result = new Amounts();
    if (targetIds != null && !targetIds.isEmpty()) {
      for (AggregateResult row : [
        SELECT
          AXF_RA_LKP_FinancialTransaction__c targetId,
          AXF_RA_PKL_Kind__c kind,
          SUM(AXF_RA_NUM_Magnitude__c) amount
        FROM AXF_OBJ_ReconciliationAllocation__c
        WHERE AXF_RA_LKP_FinancialTransaction__c IN :targetIds
        WITH SYSTEM_MODE
        GROUP BY AXF_RA_LKP_FinancialTransaction__c, AXF_RA_PKL_Kind__c
      ]) {
        Id targetId = (Id) row.get('targetId');
        result.byTarget.put(
          targetId,
          value(result.byTarget.get(targetId)) +
            ((String) row.get('kind') == 'REVERSAL' ? -1 : 1) *
            value((Decimal) row.get('amount'))
        );
      }
      for (AggregateResult row : [
        SELECT
          AXF_OAD_LKP_FinancialTransaction__c targetId,
          SUM(AXF_OAD_NUM_SignedAmount__c) amount
        FROM AXF_OBJ_ObligationAdjustment__c
        WHERE AXF_OAD_LKP_FinancialTransaction__c IN :targetIds
        WITH SYSTEM_MODE
        GROUP BY AXF_OAD_LKP_FinancialTransaction__c
      ]) {
        result.adjustments.put(
          (Id) row.get('targetId'),
          value((Decimal) row.get('amount'))
        );
      }
    }
    if (factIds != null && !factIds.isEmpty()) {
      for (AggregateResult row : [
        SELECT
          AXF_RA_LKP_BankTransaction__c factId,
          AXF_RA_PKL_Kind__c kind,
          SUM(AXF_RA_NUM_Magnitude__c) amount
        FROM AXF_OBJ_ReconciliationAllocation__c
        WHERE AXF_RA_LKP_BankTransaction__c IN :factIds
        WITH SYSTEM_MODE
        GROUP BY AXF_RA_LKP_BankTransaction__c, AXF_RA_PKL_Kind__c
      ]) {
        Id factId = (Id) row.get('factId');
        result.byFact.put(
          factId,
          value(result.byFact.get(factId)) +
            ((String) row.get('kind') == 'REVERSAL' ? -1 : 1) *
            value((Decimal) row.get('amount'))
        );
      }
      for (AggregateResult row : [
        SELECT
          AXF_RA_LKP_CardTransaction__c factId,
          AXF_RA_PKL_Kind__c kind,
          SUM(AXF_RA_NUM_Magnitude__c) amount
        FROM AXF_OBJ_ReconciliationAllocation__c
        WHERE AXF_RA_LKP_CardTransaction__c IN :factIds
        WITH SYSTEM_MODE
        GROUP BY AXF_RA_LKP_CardTransaction__c, AXF_RA_PKL_Kind__c
      ]) {
        Id factId = (Id) row.get('factId');
        result.byFact.put(
          factId,
          value(result.byFact.get(factId)) +
            ((String) row.get('kind') == 'REVERSAL' ? -1 : 1) *
            value((Decimal) row.get('amount'))
        );
      }
      for (AggregateResult row : [
        SELECT
          AXF_RA_LKP_ManualTransaction__c factId,
          AXF_RA_PKL_Kind__c kind,
          SUM(AXF_RA_NUM_Magnitude__c) amount
        FROM AXF_OBJ_ReconciliationAllocation__c
        WHERE AXF_RA_LKP_ManualTransaction__c IN :factIds
        WITH SYSTEM_MODE
        GROUP BY AXF_RA_LKP_ManualTransaction__c, AXF_RA_PKL_Kind__c
      ]) {
        Id factId = (Id) row.get('factId');
        result.byFact.put(
          factId,
          value(result.byFact.get(factId)) +
            ((String) row.get('kind') == 'REVERSAL' ? -1 : 1) *
            value((Decimal) row.get('amount'))
        );
      }
    }
    return result;
  }

  // ------------------------------------------------------------------ write

  /** Grava as N linhas pelo contrato AXF-25 e fecha o agregado, tudo no mesmo Savepoint. */
  private void write(Plan plan, AXF_OBJ_Reconciliation__c aggregate, Amounts amounts) {
    Amounts current = amounts;
    for (Integer index = 0; index < plan.lines.size(); index++) {
      LineInput line = plan.lines[index];
      String allocationKey = plan.allocationKeys[index];
      AXF_OBJ_ReconciliationAllocation__c committed = committedFor(
        plan,
        allocationKey
      );
      if (committed != null) {
        // The line is already durable under its canonical identity: it is never written twice.
        if (
          committed.AXF_RA_NUM_Magnitude__c != line.amount ||
          committed.AXF_RA_LKP_Reconciliation__c != aggregate.Id
        ) {
          throw failure(
            'CONFLICT',
            new List<String>{ 'LINE:' + index, 'ALREADY_COMMITTED' }
          );
        }
        continue;
      }
      Fact fact = factOf(plan, line);
      Target target = plan.targets.get(line.targetId);
      ALT_CLS_RealizationService.Input apply = new ALT_CLS_RealizationService.Input();
      apply.targetId = target.id;
      apply.accountId = fact.accountId;
      apply.sourceId = fact.id;
      apply.sourceKind = fact.kind == KIND_BANK
        ? 'BANK'
        : fact.kind == KIND_CARD ? 'CARD' : 'CASH';
      apply.amount = line.amount;
      apply.currencyIso = fact.currencyIso;
      apply.direction = fact.direction;
      apply.recognitionDate = fact.factDate == null
        ? Date.today()
        : fact.factDate;
      // AXF-25 bumps the target and the fact once per applied line: the predicted version of the
      // next line is the locked version plus the lines this command already wrote before it.
      apply.targetVersion =
        value(target.version) +
        writtenLines(plan, index, target.id, false);
      apply.sourceVersion =
        value(fact.version) + writtenLines(plan, index, fact.id, true);
      apply.operationKey =
        OP_CONFIRM + ':' + plan.key.left(30) + ':' + String.valueOf(index);
      apply.allocationIdentity = allocationKey;
      apply.reconciliationId = aggregate.Id;
      if (target.planKind != 'ACTUAL_ONLY') {
        // AXF-104: the revised effective obligation replaces the original estimate as the limit.
        apply.effectiveObligation = capacity(target, current);
      }
      try {
        new ALT_CLS_RealizationService().apply(apply);
      } catch (ALT_CLS_RealizationService.RealizationException failed) {
        throw mapRealization(failed, index);
      }
      current.byTarget.put(
        target.id,
        value(current.byTarget.get(target.id)) + line.amount
      );
      current.byFact.put(
        fact.id,
        value(current.byFact.get(fact.id)) + line.amount
      );
    }
    close(plan, aggregate);
  }

  /** How many lines of this command already wrote to one target (or fact) before `index`. */
  private Integer writtenLines(
    Plan plan,
    Integer index,
    Id id,
    Boolean byFact
  ) {
    Integer count = 0;
    for (Integer i = 0; i < index; i++) {
      if (committedFor(plan, plan.allocationKeys[i]) != null) {
        continue;
      }
      Id candidate = byFact ? plan.lines[i].factId : plan.lines[i].targetId;
      if (candidate == id) {
        count++;
      }
    }
    return count;
  }

  private AXF_OBJ_ReconciliationAllocation__c committedFor(
    Plan plan,
    String allocationKey
  ) {
    for (AXF_OBJ_ReconciliationAllocation__c row : plan.committed.values()) {
      if (row.AXF_RA_EXI_AllocationKey__c == allocationKey) {
        return row;
      }
    }
    return null;
  }

  private Fact factOf(Plan plan, LineInput line) {
    String kind = factKindOf(line.factId);
    if (kind == null) {
      throw failure('INVALID_INPUT', new List<String>());
    }
    Fact fact = plan.factsByKey.get(key(kind, line.factId));
    if (fact == null) {
      throw failure('INVALID_INPUT', new List<String>());
    }
    return fact;
  }

  /**
   * Maps a rejection of the AXF-25 line writer. The line index travels as a reason so the caller
   * can point the draft at the offending line without any internal detail being exposed.
   */
  private ReconciliationException mapRealization(
    ALT_CLS_RealizationService.RealizationException failed,
    Integer index
  ) {
    String code = failed.getMessage();
    List<String> reasons = new List<String>{ 'LINE:' + index };
    if (code == 'UNAVAILABLE_AMOUNT') {
      return failure('VALUE_CONSERVATION', reasons);
    }
    if (code == 'UNAVAILABLE' || code == 'INVALID_ROLE') {
      return failure('NOT_ACCESSIBLE', reasons);
    }
    return failure(code, reasons);
  }

  /** Fecha o agregado com o residual persistido e o estado derivado, sem editar nenhum RA. */
  private void close(
    Plan plan,
    AXF_OBJ_Reconciliation__c aggregate
  ) {
    close(plan, aggregate, false);
  }

  private WorkbenchView close(
    Plan plan,
    AXF_OBJ_Reconciliation__c aggregate,
    Boolean returnView
  ) {
    List<AXF_OBJ_ReconciliationAllocation__c> lines = allocationsOf(
      aggregate.Id
    );
    Amounts net = netAmounts(plan.targets.keySet(), factIds(plan));
    Decimal targetResidual = 0;
    Boolean blocked = false;
    String residualIso = null;
    for (AXF_OBJ_ReconciliationAllocation__c row : lines) {
      residualIso = row.AXF_RA_TXT_CurrencyIsoCode__c;
      if (row.AXF_RA_PKL_FxState__c != 'READY') {
        // Material evidence is missing: the aggregate is BLOCKED, never concluded.
        blocked = true;
      }
    }
    // The persisted residual is the outstanding side of the set (the target side, in the target
    // currency). The source residual is reported per line: an unused remainder of a source fact is
    // its own capacity, not an outstanding obligation of this aggregate.
    for (Target target : plan.targets.values()) {
      targetResidual += capacity(target, net) - net.target(target.id);
    }
    Decimal residual = targetResidual;
    // BLOCKED by missing evidence still persists the computed residual: the only case with a null
    // residual is the unknown-outcome park of GF-75.
    String nextState = blocked
      ? STATE_BLOCKED
      : residual.setScale(8) == 0 ? STATE_CONFIRMED : STATE_PARTIAL;
    if (
      aggregate.AXF_RCN_PKL_State__c == nextState &&
      aggregate.AXF_RCN_NUM_ResidualMagnitude__c == residual &&
      aggregate.AXF_RCN_TXT_ResidualCurrency__c == residualIso
    ) {
      // Nothing changed: the aggregate is not rewritten and its version does not move.
      return returnView ? viewOf(aggregate) : null;
    }
    aggregate.AXF_RCN_NUM_ResidualMagnitude__c = residual;
    aggregate.AXF_RCN_TXT_ResidualCurrency__c = residualIso;
    aggregate.AXF_RCN_DT_EffectiveAt__c = Datetime.now();
    aggregate.AXF_RCN_PKL_State__c = nextState;
    aggregate.AXF_RCN_NUM_Version__c =
      value(aggregate.AXF_RCN_NUM_Version__c) + 1;
    Database.update(aggregate, AccessLevel.USER_MODE);
    return returnView ? viewOf(aggregate) : null;
  }

  private Set<Id> factIds(Plan plan) {
    Set<Id> ids = new Set<Id>();
    for (Fact fact : plan.facts) {
      ids.add(fact.id);
    }
    return ids;
  }

  /** Net applied of a durable line set, keyed by fact and by target (conservation input). */
  private Amounts computed(Plan durable) {
    return netAmounts(durable.targets.keySet(), factIds(durable));
  }

  private static Id sourceIdOf(AXF_OBJ_ReconciliationAllocation__c row) {
    return row.AXF_RA_LKP_BankTransaction__c != null
      ? row.AXF_RA_LKP_BankTransaction__c
      : row.AXF_RA_LKP_CardTransaction__c != null
          ? row.AXF_RA_LKP_CardTransaction__c
          : row.AXF_RA_LKP_ManualTransaction__c;
  }

  private List<AXF_OBJ_ReconciliationAllocation__c> allocationsOf(
    Id aggregateId
  ) {
    return [
      SELECT
        Id,
        AXF_RA_PKL_Kind__c,
        AXF_RA_NUM_Magnitude__c,
        AXF_RA_TXT_CurrencyIsoCode__c,
        AXF_RA_PKL_FxState__c,
        AXF_RA_EXI_AllocationKey__c,
        AXF_RA_NUM_ReportingAmount__c,
        AXF_RA_LKP_FinancialTransaction__c,
        AXF_RA_LKP_FinancialTransaction__r.Name,
        AXF_RA_LKP_BankTransaction__c,
        AXF_RA_LKP_CardTransaction__c,
        AXF_RA_LKP_ManualTransaction__c,
        AXF_RA_LKP_Reconciliation__c
      FROM AXF_OBJ_ReconciliationAllocation__c
      WHERE AXF_RA_LKP_Reconciliation__c = :aggregateId
      WITH SYSTEM_MODE
      ORDER BY Id
    ];
  }

  // ------------------------------------------------------------------ replay and read

  /**
   * @description Authoritative read of the aggregate of one intention: the durable state, the
   * residual and the lines the service computed. Read-only and non-enumerating: an intention that
   * does not exist answers exactly like one the caller cannot reach.
   */
  public WorkbenchView read(AttemptInput input) {
    requireAccess();
    if (input == null) {
      throw failure('INVALID_INPUT', new List<String>());
    }
    requireUuid(input.correlationId);
    Plan plan = plan(input.lines, input.correlationId);
    AXF_OBJ_Reconciliation__c aggregate = aggregateByKey(plan.key);
    if (aggregate == null) {
      throw failure('NOT_ACCESSIBLE', new List<String>());
    }
    return read(aggregate, durablePlan(aggregate, plan));
  }

  /** Double-submit: the durable result of the same intention is returned, never rewritten. */
  private ConfirmResult replay(
    Plan plan,
    AXF_OBJ_Reconciliation__c aggregate
  ) {
    Plan durable = durablePlan(aggregate, plan);
    if (!sameSet(durable, plan)) {
      // Same intention, divergent payload: CONFLICT, and nothing is written.
      throw failure('CONFLICT', new List<String>{ 'DIVERGENT_SET' });
    }
    return result(read(aggregate, durable), true);
  }

  /** The durable line set of an aggregate, with its own facts and targets resolved. */
  private Plan durablePlan(
    AXF_OBJ_Reconciliation__c aggregate,
    Plan request
  ) {
    Plan durable = new Plan();
    durable.correlationId = request.correlationId;
    durable.key = request.key;
    for (AXF_OBJ_ReconciliationAllocation__c row : allocationsOf(
      aggregate.Id
    )) {
      LineInput line = new LineInput();
      line.factKind = row.AXF_RA_LKP_BankTransaction__c != null
        ? KIND_BANK
        : row.AXF_RA_LKP_CardTransaction__c != null ? KIND_CARD : KIND_MANUAL;
      line.factId = sourceIdOf(row);
      line.targetId = row.AXF_RA_LKP_FinancialTransaction__c;
      line.amount = row.AXF_RA_NUM_Magnitude__c;
      durable.lines.add(line);
      durable.allocationKeys.add(row.AXF_RA_EXI_AllocationKey__c);
      if (
        line.targetId != null &&
        !durable.targets.containsKey(line.targetId)
      ) {
        Target target = resolveTarget(line.targetId);
        durable.targets.put(target.id, target);
      }
      String factKey = key(line.factKind, line.factId);
      if (!durable.factsByKey.containsKey(factKey)) {
        Fact fact = resolveFact(line.factKind, line.factId);
        durable.factsByKey.put(factKey, fact);
        durable.facts.add(fact);
      }
    }
    return durable;
  }

  /** True when the submitted intention and the durable line set are the same set. */
  private Boolean sameSet(Plan durable, Plan request) {
    Set<String> submitted = new Set<String>(request.allocationKeys);
    Set<String> stored = new Set<String>(durable.allocationKeys);
    return submitted.size() == stored.size() && submitted.containsAll(stored);
  }

  /** Authoritative read of one aggregate: state, residual and the lines the service computed. */
  private WorkbenchView read(
    AXF_OBJ_Reconciliation__c aggregate,
    Plan durable
  ) {
    WorkbenchView view = viewOf(aggregate);
    List<AXF_OBJ_ReconciliationAllocation__c> rows = allocationsOf(
      aggregate.Id
    );
    Amounts net = computed(durable);
    Decimal allocated = 0;
    for (AXF_OBJ_ReconciliationAllocation__c row : rows) {
      LineView line = new LineView();
      line.factKind = row.AXF_RA_LKP_BankTransaction__c != null
        ? KIND_BANK
        : row.AXF_RA_LKP_CardTransaction__c != null ? KIND_CARD : KIND_MANUAL;
      line.factId = sourceIdOf(row);
      line.targetId = row.AXF_RA_LKP_FinancialTransaction__c;
      line.targetLabel = row.AXF_RA_LKP_FinancialTransaction__r?.Name;
      line.amount = row.AXF_RA_NUM_Magnitude__c;
      line.allocated = row.AXF_RA_PKL_Kind__c == 'REVERSAL'
        ? 0
        : row.AXF_RA_NUM_Magnitude__c;
      line.currencyIso = row.AXF_RA_TXT_CurrencyIsoCode__c;
      line.allocationId = row.Id;
      line.allocationKey = row.AXF_RA_EXI_AllocationKey__c;
      Target target = durable.targets.get(line.targetId);
      if (target != null) {
        line.available = capacity(target, net) - net.target(target.id);
        line.residual = line.available;
        line.state = row.AXF_RA_PKL_FxState__c == 'READY'
          ? (line.residual.setScale(8) == 0 ? STATE_CONFIRMED : STATE_PARTIAL)
          : STATE_BLOCKED;
        if (row.AXF_RA_PKL_FxState__c != 'READY') {
          line.reasons.add('MISSING_MATERIAL_FX');
        }
      }
      Fact fact = durable.factsByKey.get(key(line.factKind, line.factId));
      if (fact != null) {
        line.factLabel = fact.label;
        line.sourceResidual = fact.magnitude - net.fact(fact.id);
      }
      allocated += value(row.AXF_RA_NUM_Magnitude__c);
      view.lines.add(line);
    }
    view.allocatedTotal = allocated;
    return view;
  }

  /** Minimal view of an aggregate: no line is read, no figure is derived elsewhere. */
  private WorkbenchView viewOf(AXF_OBJ_Reconciliation__c aggregate) {
    WorkbenchView view = new WorkbenchView();
    view.reconciliationId = aggregate.Id;
    view.reconciliationKey = aggregate.AXF_RCN_EXI_ReconciliationKey__c;
    view.state = aggregate.AXF_RCN_PKL_State__c;
    view.expectedVersion = value(aggregate.AXF_RCN_NUM_Version__c);
    view.residualMagnitude = aggregate.AXF_RCN_NUM_ResidualMagnitude__c;
    view.residualCurrency = aggregate.AXF_RCN_TXT_ResidualCurrency__c;
    view.effectiveAt = aggregate.AXF_RCN_DT_EffectiveAt__c;
    view.unknownOutcome = unknownOutcome(aggregate);
    return view;
  }

  // ------------------------------------------------------------------ draft evaluation

  /** Read-only evaluation of a draft: no lock, no write, no conclusion. */
  private void evaluate(Plan plan, WorkbenchView view) {
    Amounts amounts = amounts(plan);
    view.reconciliationKey = plan.key;
    AXF_OBJ_Reconciliation__c aggregate = aggregateByKey(plan.key);
    if (aggregate != null) {
      view.reconciliationId = aggregate.Id;
      view.expectedVersion = value(aggregate.AXF_RCN_NUM_Version__c);
      view.state = aggregate.AXF_RCN_PKL_State__c;
      view.unknownOutcome = unknownOutcome(aggregate);
      view.residualMagnitude = aggregate.AXF_RCN_NUM_ResidualMagnitude__c;
      view.residualCurrency = aggregate.AXF_RCN_TXT_ResidualCurrency__c;
      view.effectiveAt = aggregate.AXF_RCN_DT_EffectiveAt__c;
      return;
    }
    Decimal allocatedTotal = 0;
    for (Integer index = 0; index < plan.lines.size(); index++) {
      LineInput line = plan.lines[index];
      Fact fact = factOf(plan, line);
      Target target = plan.targets.get(line.targetId);
      LineView row = new LineView();
      row.factKind = fact.kind;
      row.factId = fact.id;
      row.factLabel = fact.label;
      row.targetId = target.id;
      row.targetLabel = target.label;
      row.amount = line.amount;
      row.currencyIso = fact.currencyIso;
      row.allocationKey = plan.allocationKeys[index];
      Decimal sourceAvailable = fact.magnitude - amounts.fact(fact.id);
      Decimal targetAvailable =
        capacity(target, amounts) - amounts.target(target.id);
      row.available = Math.min(sourceAvailable, targetAvailable);
      row.allocated = amounts.byAllocationKey.containsKey(
          plan.allocationKeys[index]
        )
        ? amounts.byAllocationKey.get(plan.allocationKeys[index])
        : 0;
      if (row.allocated != 0) {
        row.reasons.add('ALREADY_ALLOCATED');
      }
      if (fact.currencyIso != target.currencyIso) {
        row.state = STATE_BLOCKED;
        row.reasons.add('CURRENCY_MISMATCH');
      } else if (fact.direction != target.direction) {
        row.state = STATE_BLOCKED;
        row.reasons.add('DIRECTION_MISMATCH');
      } else {
        row.residual = targetAvailable - line.amount;
        row.sourceResidual = sourceAvailable - line.amount;
        if (line.amount > row.available) {
          row.reasons.add('VALUE_CONSERVATION');
        }
        row.state = row.residual.setScale(8) == 0 &&
          row.sourceResidual.setScale(8) == 0
          ? STATE_CONFIRMED
          : STATE_PARTIAL;
      }
      allocatedTotal += line.amount;
      view.lines.add(row);
    }
    view.allocatedTotal = allocatedTotal;
    // The draft itself is consultative: nothing is committed and nothing is concluded.
    view.state = ALT_CLS_MatchEvidence.STATE_CONSULTATIVE;
  }

  // ------------------------------------------------------------------ options

  /** Facts of one authorized holder that still have residual to reconcile. */
  private List<SourceView> sources(Id accountId) {
    if (accountId == null || !authorizedAccounts().contains(accountId)) {
      throw failure('NOT_ACCESSIBLE', new List<String>());
    }
    List<Fact> facts = new List<Fact>();
    for (AXF_OBJ_BankAccountTransaction__c row : [
      SELECT
        Id,
        Name,
        AXF_BAT_EXI_SourceKey__c,
        AXF_BAT_NUM_Magnitude__c,
        AXF_BAT_NUM_Version__c,
        AXF_BAT_TXT_CurrencyIsoCode__c,
        AXF_BAT_PKL_Direction__c,
        AXF_BAT_DAT_Date__c,
        AXF_BAT_TXT_Description__c
      FROM AXF_OBJ_BankAccountTransaction__c
      WHERE
        AXF_BAT_MDR_BankAccount__r.AXF_BA_LKP_Account__c = :accountId
        AND AXF_BAT_PKL_Status__c = 'POSTED'
      WITH USER_MODE
      ORDER BY AXF_BAT_DAT_Date__c DESC, Id
      LIMIT :MAX_SOURCES
    ]) {
      Fact fact = new Fact();
      fact.kind = KIND_BANK;
      fact.id = row.Id;
      fact.label = row.Name;
      fact.identity = row.AXF_BAT_EXI_SourceKey__c;
      fact.magnitude = row.AXF_BAT_NUM_Magnitude__c;
      fact.version = value(row.AXF_BAT_NUM_Version__c);
      fact.currencyIso = row.AXF_BAT_TXT_CurrencyIsoCode__c;
      fact.direction = row.AXF_BAT_PKL_Direction__c;
      fact.factDate = row.AXF_BAT_DAT_Date__c;
      fact.description = row.AXF_BAT_TXT_Description__c;
      facts.add(fact);
    }
    for (AXF_OBJ_CreditCardTransaction__c row : [
      SELECT
        Id,
        Name,
        AXF_CCT_EXI_SourceKey__c,
        AXF_CCT_NUM_Magnitude__c,
        AXF_CCT_NUM_Version__c,
        AXF_CCT_TXT_CurrencyIsoCode__c,
        AXF_CCT_PKL_Direction__c,
        AXF_CCT_DAT_Date__c,
        AXF_CCT_TXT_Description__c
      FROM AXF_OBJ_CreditCardTransaction__c
      WHERE
        AXF_CCT_MDR_CreditCard__r.AXF_CC_LKP_Account__c = :accountId
        AND AXF_CCT_PKL_Status__c = 'POSTED'
      WITH USER_MODE
      ORDER BY AXF_CCT_DAT_Date__c DESC, Id
      LIMIT :MAX_SOURCES
    ]) {
      Fact fact = new Fact();
      fact.kind = KIND_CARD;
      fact.id = row.Id;
      fact.label = row.Name;
      fact.identity = row.AXF_CCT_EXI_SourceKey__c;
      fact.magnitude = row.AXF_CCT_NUM_Magnitude__c;
      fact.version = value(row.AXF_CCT_NUM_Version__c);
      fact.currencyIso = row.AXF_CCT_TXT_CurrencyIsoCode__c;
      fact.direction = row.AXF_CCT_PKL_Direction__c;
      fact.factDate = row.AXF_CCT_DAT_Date__c;
      fact.description = row.AXF_CCT_TXT_Description__c;
      facts.add(fact);
    }
    for (AXF_OBJ_FinancialTransaction__c row : [
      SELECT
        Id,
        Name,
        AXF_FTX_NUM_Magnitude__c,
        AXF_FTX_NUM_Version__c,
        AXF_FTX_TXT_CurrencyIsoCode__c,
        AXF_FTX_PKL_Direction__c,
        AXF_FTX_DAT_PurchaseDate__c,
        AXF_FTX_TXT_Description__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE
        AXF_FTX_LKP_Account__c = :accountId
        AND AXF_FTX_PKL_PlanKind__c = 'CASH_FACT'
      WITH USER_MODE
      ORDER BY AXF_FTX_DAT_PurchaseDate__c DESC, Id
      LIMIT :MAX_SOURCES
    ]) {
      Fact fact = new Fact();
      fact.kind = KIND_MANUAL;
      fact.id = row.Id;
      fact.label = row.Name;
      fact.identity = 'FTX:' + row.Id;
      fact.magnitude = row.AXF_FTX_NUM_Magnitude__c;
      fact.version = value(row.AXF_FTX_NUM_Version__c);
      fact.currencyIso = row.AXF_FTX_TXT_CurrencyIsoCode__c;
      fact.direction = row.AXF_FTX_PKL_Direction__c;
      fact.factDate = row.AXF_FTX_DAT_PurchaseDate__c;
      fact.description = row.AXF_FTX_TXT_Description__c;
      facts.add(fact);
    }
    Set<Id> ids = new Set<Id>();
    for (Fact fact : facts) {
      ids.add(fact.id);
    }
    Amounts amounts = netAmounts(null, ids);
    List<SourceView> result = new List<SourceView>();
    for (Fact fact : facts) {
      SourceView view = sourceView(fact);
      view.residual = fact.magnitude - amounts.fact(fact.id);
      result.add(view);
    }
    return result;
  }

  private SourceView sourceView(Fact fact) {
    SourceView view = new SourceView();
    view.factId = fact.id;
    view.factKind = fact.kind;
    view.label = fact.label;
    view.description = fact.description;
    view.factDate = fact.factDate;
    view.magnitude = fact.magnitude;
    view.currencyIso = fact.currencyIso;
    view.direction = fact.direction;
    view.version = fact.version;
    view.residual = fact.magnitude;
    return view;
  }

  /**
   * Open targets of the same holder, presented as consultative candidates: every feature is
   * independent evidence (AXF-139/AXF-140), the order is presentation only and nothing is selected,
   * scored or confirmed. A candidate in another currency or direction is BLOCKED and cannot be
   * linked, because confirmation requires exact arithmetic and no rate is ever invented here.
   */
  private List<CandidateView> candidates(Fact fact) {
    List<CandidateView> result = new List<CandidateView>();
    if (fact.accountId == null) {
      return result;
    }
    // A bind is always a plain variable, never a field expression.
    Id holderId = fact.accountId;
    List<Target> targets = new List<Target>();
    for (AXF_OBJ_FinancialTransaction__c row : [
      SELECT
        Id,
        Name,
        AXF_FTX_NUM_Magnitude__c,
        AXF_FTX_NUM_CurrentBasis__c,
        AXF_FTX_NUM_Version__c,
        AXF_FTX_TXT_CurrencyIsoCode__c,
        AXF_FTX_PKL_Direction__c,
        AXF_FTX_PKL_PlanKind__c,
        AXF_FTX_EXI_ClientRequestId__c,
        AXF_FTX_DAT_DueDate__c,
        AXF_FTX_TXT_Description__c,
        AXF_FTX_LKP_Account__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE
        AXF_FTX_LKP_Account__c = :holderId
        AND AXF_FTX_PKL_PlanKind__c != 'CASH_FACT'
      WITH USER_MODE
      ORDER BY Id
      LIMIT :MAX_CANDIDATES
    ]) {
      if (row.AXF_FTX_NUM_Magnitude__c == null) {
        continue;
      }
      Target target = new Target();
      target.id = row.Id;
      target.label = row.Name;
      target.description = row.AXF_FTX_TXT_Description__c;
      target.identity = externalIdentity(row);
      target.accountId = row.AXF_FTX_LKP_Account__c;
      target.magnitude = row.AXF_FTX_NUM_Magnitude__c;
      target.obligation = row.AXF_FTX_NUM_CurrentBasis__c;
      target.currencyIso = row.AXF_FTX_TXT_CurrencyIsoCode__c;
      target.direction = row.AXF_FTX_PKL_Direction__c;
      target.planKind = row.AXF_FTX_PKL_PlanKind__c;
      target.version = value(row.AXF_FTX_NUM_Version__c);
      target.dueDate = row.AXF_FTX_DAT_DueDate__c;
      targets.add(target);
    }
    Set<Id> targetIds = new Set<Id>();
    Set<Id> factIds = new Set<Id>{ fact.id };
    for (Target target : targets) {
      targetIds.add(target.id);
    }
    Amounts amounts = netAmounts(targetIds, factIds);
    Decimal sourceAvailable = fact.magnitude - amounts.fact(fact.id);
    List<ALT_CLS_MatchEvidence.OrderKey> keys = new List<ALT_CLS_MatchEvidence.OrderKey>();
    Map<String, CandidateView> byKey = new Map<String, CandidateView>();
    for (Target target : targets) {
      Decimal available =
        capacity(target, amounts) - amounts.target(target.id);
      CandidateView candidate = new CandidateView();
      candidate.targetId = target.id;
      candidate.label = target.label;
      candidate.description = target.description;
      candidate.dueDate = target.dueDate;
      candidate.magnitude = target.magnitude;
      candidate.available = available;
      candidate.residual = available;
      candidate.currencyIso = target.currencyIso;
      candidate.direction = target.direction;
      candidate.version = target.version;
      candidate.identityExact = fact.identity == target.identity;
      candidate.evidence = ALT_CLS_MatchEvidence.evaluate(
        side(fact, sourceAvailable),
        side(target, available)
      );
      candidate.lowEvidence = ALT_CLS_MatchEvidence.lowEvidence(
        candidate.evidence
      );
      if (fact.currencyIso != target.currencyIso) {
        candidate.state = STATE_BLOCKED;
        candidate.reasons.add('CURRENCY_MISMATCH');
      } else if (fact.direction != target.direction) {
        candidate.state = STATE_BLOCKED;
        candidate.reasons.add('DIRECTION_MISMATCH');
      } else if (available <= 0) {
        candidate.state = STATE_BLOCKED;
        candidate.reasons.add('NO_CAPACITY');
      } else {
        candidate.linkable = true;
        if (sourceAvailable < available) {
          // AXF-140 §3: after the source's available amount is applied the candidate still needs
          // more, so it is PARTIAL and the remainder is reported as it is.
          candidate.state = STATE_PARTIAL;
          candidate.residual = available - sourceAvailable;
          candidate.reasons.add('PARTIAL');
        }
      }
      String recordKey = String.valueOf(target.id);
      keys.add(
        new ALT_CLS_MatchEvidence.OrderKey(
          candidate.evidence,
          target.planKind == 'PLANNED' ? 0 : 1,
          recordKey,
          candidate
        )
      );
      byKey.put(recordKey, candidate);
    }
    keys.sort();
    for (ALT_CLS_MatchEvidence.OrderKey entry : keys) {
      result.add(byKey.get(entry.recordKey));
    }
    return result;
  }

  private ALT_CLS_MatchEvidence.Side side(Fact fact, Decimal residual) {
    ALT_CLS_MatchEvidence.Side result = new ALT_CLS_MatchEvidence.Side();
    result.externalIdentity = fact.identity;
    result.sourceIdentity = fact.id;
    result.holderId = fact.accountId;
    result.currencyIso = fact.currencyIso;
    result.amount = fact.magnitude;
    result.residual = residual;
    result.onDate = fact.factDate;
    result.description = fact.description;
    return result;
  }

  private ALT_CLS_MatchEvidence.Side side(Target target, Decimal residual) {
    ALT_CLS_MatchEvidence.Side result = new ALT_CLS_MatchEvidence.Side();
    result.externalIdentity = target.identity;
    result.sourceIdentity = target.id;
    result.holderId = target.accountId;
    result.currencyIso = target.currencyIso;
    result.amount = target.magnitude;
    result.residual = residual;
    result.onDate = target.dueDate;
    result.description = target.description;
    return result;
  }

  // ------------------------------------------------------------------ helpers

  private ConfirmResult result(WorkbenchView view, Boolean replayed) {
    ConfirmResult confirmed = new ConfirmResult();
    confirmed.reconciliationId = view.reconciliationId;
    confirmed.reconciliationKey = view.reconciliationKey;
    confirmed.state = view.state;
    confirmed.replayed = replayed;
    confirmed.version = view.expectedVersion;
    confirmed.residualMagnitude = view.residualMagnitude;
    confirmed.residualCurrency = view.residualCurrency;
    confirmed.effectiveAt = view.effectiveAt;
    confirmed.allocatedTotal = view.allocatedTotal;
    confirmed.lines = view.lines;
    if (view.state == STATE_PARTIAL || view.state == STATE_BLOCKED) {
      confirmed.boundaries.add(BOUNDARY_AXF104);
    }
    return confirmed;
  }

  /**
   * GF-75: the sanctioned `BLOCKED` state with the outcome still unknown. The residual is the
   * marker: a resolved outcome always persists it (0 when there is no leftover).
   */
  private static Boolean unknownOutcome(
    AXF_OBJ_Reconciliation__c aggregate
  ) {
    return aggregate != null &&
      STATE_BLOCKED.equals(aggregate.AXF_RCN_PKL_State__c) &&
      aggregate.AXF_RCN_NUM_ResidualMagnitude__c == null;
  }

  private static void checkVersion(
    AXF_OBJ_Reconciliation__c aggregate,
    Decimal expectedVersion
  ) {
    if (
      expectedVersion == null ||
      expectedVersion != value(aggregate.AXF_RCN_NUM_Version__c)
    ) {
      // Stale version: the whole command is rejected and the draft stays reviewable.
      throw failure('CONFLICT', new List<String>{ 'STALE_VERSION' });
    }
  }

  private Set<Id> authorizedAccounts() {
    Set<Id> result = new Set<Id>();
    for (
      AXF_CLS_AuthorizedContextService.ContextView context : AXF_CLS_AuthorizedContextService.listAuthorizedContexts()
    ) {
      result.add(context.accountId);
    }
    return result;
  }

  private Id ownerOf(Id accountId) {
    List<Account> rows = [
      SELECT OwnerId
      FROM Account
      WHERE Id = :accountId
      WITH USER_MODE
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      throw failure('NOT_ACCESSIBLE', new List<String>());
    }
    return rows[0].OwnerId;
  }

  /** The aggregate follows the holder's owner (G2); the confirmer keeps access through a share row. */
  @SuppressWarnings('PMD.ApexCRUDViolation')
  private static void grantProposerAccess(Id reconciliationId, Id ownerId) {
    Id me = UserInfo.getUserId();
    if (me == ownerId) {
      return;
    }
    Database.insert(
      new AXF_OBJ_Reconciliation__Share(
        ParentId = reconciliationId,
        UserOrGroupId = me,
        AccessLevel = 'Edit',
        RowCause = Schema.AXF_OBJ_Reconciliation__Share.RowCause.Manual
      ),
      false
    );
  }

  private static Decimal value(Decimal input) {
    return input == null ? 0 : input;
  }

  private static ReconciliationException failure(
    String code,
    List<String> reasons
  ) {
    ReconciliationException problem = new ReconciliationException(code);
    problem.code = code;
    problem.reasons = reasons;
    return problem;
  }
}
