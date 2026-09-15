/**
 * @description Matcher deterministico de recorrencia de assinaturas de servico (AXF-110, S2 do
 * epico AXF-108, gate G2). Consome as observacoes ja qualificadas de S1 (AXF-109) e devolve
 * atribuicoes de stream/ciclo, historico insuficiente e ambiguidades. Puro por contrato: sem
 * SOQL, sem DML, sem UI e sem LLM. A mesma entrada produz sempre a mesma saida,
 * independentemente da ordem das observacoes recebidas.
 *
 * Politica versionada (POLICY_VERSION), conforme P1-P3 do epico AXF-108 com Q1 aceito em
 * 2026-09-13:
 * - P1: minimo de 3 cobrancas liquidadas mensais / 2 anuais em ciclos consecutivos ancorados;
 *   tolerancia de data de +/-5 dias (mensal) e +/-15 dias (anual). A cobranca elegivel mais
 *   antiga estabelece a ancora do calendario. A aritmetica e de calendario (mes/ano), nunca de
 *   intervalos brutos de 30/365 dias; dia 29/30/31 e fixado no ultimo dia do mes alvo sem
 *   alterar a ancora, e 29/02 ancora em 28/02 fora de ano bissexto. Uma cobranca proxima do
 *   primeiro dia pode cair no mes de postagem anterior dentro da tolerancia, sem que a fronteira
 *   de mes de postagem rejeite o ciclo. A evidencia do candidato sao os ciclos minimos exigidos,
 *   e a proxima estimativa e uma cadencia depois do ciclo mais recente observado no stream —
 *   nunca depois da evidencia minima, que poderia cair no passado.
 * - P2: referencia M = mediana das cobrancas de evidencia; toda cobranca de evidencia V precisa
 *   satisfazer abs(V - M) <= max(piso, 10% x M), com igualdade na fronteira aceita. O piso de
 *   BRL 5,00 vale para streams em BRL; outra moeda nao recebe piso, porque P2 proibe interpretar
 *   um limite em BRL como valor convertido sem politica de conversao acordada (dependencia
 *   explicita ainda aberta). Cobranca posterior a evidencia minima permanece no stream como
 *   historico observado, e a divergencia de valor dela e um evento de mudanca de preco, tratado
 *   no contrato de assinatura confirmada (S3/S4) e nao aqui.
 * - P3: o agrupamento ocorre somente dentro do mesmo titular autorizado, moeda e fonte de
 *   pagamento estavel (a conta bancaria ou o cartao do fato, nunca a identidade da transacao nem
 *   o texto do estabelecimento). Identidade de estabelecimento generica (Amazon/Google) nao
 *   qualifica sozinha (AC10); somente observacoes ELIGIBLE, de debito, com indicio de servico
 *   formam stream.
 *
 * No maximo uma cobranca e atribuida a cada ciclo esperado. Se duas cobrancas elegiveis cairem no
 * mesmo ciclo sem evidencia que as distinga, o stream e devolvido como AMBIGUOUS para revisao,
 * com as cobrancas em conflito, sem atribuicao arbitraria (AC03/AC15) — a ambiguidade tem
 * precedencia sobre uma qualificacao na outra cadencia. O estado durável, o agendamento, a
 * ancora persistida e as decisoes do usuario pertencem a S3/S4: esta classe nao persiste nada.
 *
 * Contrato do chamador: a janela de observacoes entregue delimita a ancora (a cobranca elegivel
 * mais antiga da janela). O chamador deve entregar a janela de historico completa e estavel da
 * fonte, porque uma janela deslizante pode reancorar um stream de fim de mes. A enumeracao de
 * ancoras concorrentes prevista em P1 continua diferida para a calibracao Q1.
 */
public inherited sharing class ALT_CLS_SubscriptionRecurrenceMatcher {
  /** @description Bump quando as regras P1/P2/P3 abaixo mudarem; viaja no resultado. */
  public static final String POLICY_VERSION = 'subscription-recurrence@1.0.0';

  /** P1 — minimo de cobrancas liquidadas para sustentar cada cadencia. */
  public static final Integer MONTHLY_MINIMUM_CHARGES = 3;
  public static final Integer ANNUAL_MINIMUM_CHARGES = 2;

  /** P1 — tolerancia de data, em dias, ao redor da data ancorada. */
  public static final Integer MONTHLY_DATE_TOLERANCE_DAYS = 5;
  public static final Integer ANNUAL_DATE_TOLERANCE_DAYS = 15;

  /** P2 — faixa de valor do candidato inicial: max(piso, taxa x referencia). */
  public static final Decimal CANDIDATE_VALUE_FLOOR = 5.00;
  public static final Decimal CANDIDATE_VALUE_RATE = 0.10;
  /** Moeda a que o piso de P2 se refere; outra moeda nao recebe piso. */
  public static final String CANDIDATE_VALUE_FLOOR_CURRENCY = 'BRL';

  /** Maior lote aceito em uma chamada, na mesma disciplina do S1. */
  public static final Integer MAX_BATCH = 500;

  public static final String MONTHLY = 'MONTHLY';
  public static final String ANNUAL = 'ANNUAL';

  public static final String QUALIFIED = 'QUALIFIED';
  public static final String INSUFFICIENT_HISTORY = 'INSUFFICIENT_HISTORY';
  public static final String AMBIGUOUS = 'AMBIGUOUS';

  public static final String REASON_MISSING_CYCLES = 'MISSING_CYCLES';
  public static final String REASON_VALUE_BAND = 'VALUE_BAND';
  public static final String REASON_CYCLE_COLLISION = 'CYCLE_COLLISION';

  /** Vocabulario do contrato de entrada, publicado por S1 (AXF-109). */
  public static final String ELIGIBLE = 'ELIGIBLE';
  public static final String SERVICE_CANDIDATE = 'SERVICE_CANDIDATE';
  public static final String DEBIT = 'DEBIT';

  public static final String INVALID_INPUT = 'INVALID_INPUT';

  public class RecurrenceException extends Exception {
    public String code;
  }

  /**
   * Entrada pura, sem dependencia de SObject. `transactionIdentity` identifica o fato de origem
   * (revisoes da mesma transacao) e `paymentSourceId` identifica a fonte de pagamento estavel
   * (conta bancaria ou cartao) usada no agrupamento P3.
   */
  public class Observation {
    public String observationKey;
    public String transactionIdentity;
    public Decimal revision;
    public Id ownerId;
    public String paymentSourceId;
    public String currencyIsoCode;
    public String normalizedMerchant;
    public String eligibility;
    public String serviceHint;
    public String direction;
    public Date chargedOn;
    public Decimal magnitude;
  }

  /** Evidencia de um ciclo esperado da cadencia proposta. */
  public class CycleAssignment {
    public Integer cycleIndex;
    public Date expectedDate;
    public Date chargedOn;
    public Decimal magnitude;
    public String observationKey;
  }

  /** Resultado por stream: atribuicoes, insuficiencia de historico ou ambiguidade. */
  public class StreamAssignment {
    public String streamKey;
    public Id ownerId;
    public String paymentSourceId;
    public String currencyIsoCode;
    public String normalizedMerchant;
    public String cadence;
    public Date anchorDate;
    public String outcome;
    public String reason;
    public Decimal referenceAmount;
    public Date nextEstimateDate;
    /** Ciclos consecutivos evidenciados a partir da ancora. */
    public Integer evidencedCycles = 0;
    /** Total de ciclos com cobranca atribuida, incluindo alem da evidencia minima. */
    public Integer observedCycles = 0;
    /** Maior ciclo com cobranca atribuida no stream. */
    public Integer lastObservedCycle;
    /** Cobrancas do stream fora da tolerancia de qualquer ciclo esperado. */
    public Integer unmatchedObservations = 0;
    public List<CycleAssignment> evidence = new List<CycleAssignment>();
    /** Cobrancas em conflito no mesmo ciclo, devolvidas para revisao (AC03/AC15). */
    public List<CycleAssignment> ambiguousEvidence = new List<CycleAssignment>();
    public List<Integer> ambiguousCycles = new List<Integer>();
  }

  public class EvaluateInput {
    /** Titular autorizado que delimita o escopo da avaliacao. */
    public Id ownerId;
    public List<Observation> observations;
  }

  public class EvaluateResult {
    public String policyVersion = POLICY_VERSION;
    public Id ownerId;
    public Integer eligibleObservations = 0;
    /** Observacoes de outro titular, fora do escopo autorizado. */
    public Integer outOfScopeObservations = 0;
    /** Observacoes do titular sem elegibilidade, debito, indicio de servico ou campos do S1. */
    public Integer ineligibleObservations = 0;
    /** Revisoes anteriores do mesmo fato descartadas em favor da mais recente. */
    public Integer deduplicatedObservations = 0;
    /** Cobrancas elegiveis fora da tolerancia de qualquer ciclo do seu stream. */
    public Integer unmatchedObservations = 0;
    public Integer qualifiedStreams = 0;
    public Integer insufficientHistoryStreams = 0;
    public Integer ambiguousStreams = 0;
    public List<StreamAssignment> streams = new List<StreamAssignment>();
  }

  private class Stream {
    String streamKey;
    Id ownerId;
    String paymentSourceId;
    String currencyIsoCode;
    String normalizedMerchant;
    List<Observation> charges = new List<Observation>();
  }

  private class Attempt {
    String cadence;
    String outcome;
    String reason;
    Integer minimum = 0;
    Integer evidencedCycles = 0;
    Integer observedCycles = 0;
    Integer unmatchedObservations = 0;
    Integer lastObservedCycle;
    Decimal referenceAmount;
    Date nextEstimateDate;
    List<CycleAssignment> evidence = new List<CycleAssignment>();
    List<CycleAssignment> ambiguousEvidence = new List<CycleAssignment>();
    List<Integer> collisions = new List<Integer>();
  }

  /** Ordenacao estavel (data, depois identidade) — remove a dependencia da ordem de entrada. */
  private class ChargeOrder implements Comparator<Observation> {
    public Integer compare(Observation left, Observation right) {
      if (left.chargedOn != right.chargedOn) {
        return left.chargedOn < right.chargedOn ? -1 : 1;
      }
      if (left.observationKey == right.observationKey) {
        return 0;
      }
      return left.observationKey < right.observationKey ? -1 : 1;
    }
  }

  /**
   * @description Avalia as observacoes de um titular autorizado e devolve um resultado por stream
   * agrupado. Streams saem em ordem deterministica de chave.
   */
  public static EvaluateResult evaluate(EvaluateInput input) {
    if (input == null || input.ownerId == null) {
      throw failure(INVALID_INPUT);
    }
    List<Observation> observations = input.observations == null
      ? new List<Observation>()
      : input.observations;
    if (observations.size() > MAX_BATCH) {
      throw failure(INVALID_INPUT);
    }
    EvaluateResult result = new EvaluateResult();
    result.ownerId = input.ownerId;

    // S1 mantem uma linha imutavel por revisao do mesmo fato: vale apenas a mais recente.
    Map<String, Observation> latestByFact = new Map<String, Observation>();
    for (Observation candidate : observations) {
      if (candidate == null) {
        result.ineligibleObservations++;
        continue;
      }
      if (candidate.ownerId != input.ownerId) {
        result.outOfScopeObservations++;
        continue;
      }
      if (!qualifies(candidate)) {
        result.ineligibleObservations++;
        continue;
      }
      Observation previous = latestByFact.get(candidate.transactionIdentity);
      if (previous == null || isNewerRevision(candidate, previous)) {
        if (previous != null) {
          result.deduplicatedObservations++;
        }
        latestByFact.put(candidate.transactionIdentity, candidate);
      } else {
        result.deduplicatedObservations++;
      }
    }

    Map<String, Stream> groups = new Map<String, Stream>();
    for (Observation candidate : latestByFact.values()) {
      result.eligibleObservations++;
      String key = streamKey(candidate);
      Stream bucket = groups.get(key);
      if (bucket == null) {
        bucket = new Stream();
        bucket.streamKey = key;
        bucket.ownerId = candidate.ownerId;
        bucket.paymentSourceId = candidate.paymentSourceId;
        bucket.currencyIsoCode = candidate.currencyIsoCode;
        bucket.normalizedMerchant = candidate.normalizedMerchant;
        groups.put(key, bucket);
      }
      bucket.charges.add(candidate);
    }

    List<String> keys = new List<String>(groups.keySet());
    keys.sort();
    for (String key : keys) {
      StreamAssignment assignment = assign(groups.get(key));
      result.unmatchedObservations += assignment.unmatchedObservations;
      result.streams.add(assignment);
      if (assignment.outcome == QUALIFIED) {
        result.qualifiedStreams++;
      } else if (assignment.outcome == AMBIGUOUS) {
        result.ambiguousStreams++;
      } else {
        result.insufficientHistoryStreams++;
      }
    }
    return result;
  }

  /**
   * @description Mapeia observacoes ja materializadas por S1 para a entrada pura do matcher.
   * Le apenas os campos em memoria: nao executa consulta nem gravacao.
   *
   * Contrato do chamador: a consulta que produz `rows` deve trazer a fonte de pagamento estavel
   * (`AXF_TOB_LKP_BankTransaction__r.AXF_BAT_MDR_BankAccount__c` ou
   * `AXF_TOB_LKP_CardTransaction__r.AXF_CCT_MDR_CreditCard__c`) e as revisoes do fato. Uma linha
   * sem fonte resolvida falha fechada e nao forma stream.
   */
  public static List<Observation> fromObservations(
    List<AXF_OBJ_TransactionObservation__c> rows
  ) {
    List<Observation> result = new List<Observation>();
    if (rows == null) {
      return result;
    }
    for (AXF_OBJ_TransactionObservation__c row : rows) {
      if (row == null) {
        continue;
      }
      Observation observation = new Observation();
      observation.observationKey = String.isBlank(
          row.AXF_TOB_EXI_ObservationKey__c
        )
        ? String.valueOf(row.Id)
        : row.AXF_TOB_EXI_ObservationKey__c;
      observation.transactionIdentity = row.AXF_TOB_TXT_SourceIdentity__c;
      observation.revision = row.AXF_TOB_NUM_Revision__c;
      observation.ownerId = row.AXF_TOB_LKP_Account__c;
      observation.paymentSourceId = paymentSourceId(row);
      observation.currencyIsoCode = row.AXF_TOB_TXT_CurrencyIsoCode__c;
      observation.normalizedMerchant = row.AXF_TOB_TXT_NormalizedMerchant__c;
      observation.eligibility = row.AXF_TOB_PKL_Eligibility__c;
      observation.serviceHint = row.AXF_TOB_PKL_ServiceHint__c;
      observation.direction = row.AXF_TOB_PKL_Direction__c;
      observation.chargedOn = row.AXF_TOB_DAT_Date__c;
      observation.magnitude = row.AXF_TOB_NUM_Magnitude__c;
      result.add(observation);
    }
    return result;
  }

  private static String paymentSourceId(AXF_OBJ_TransactionObservation__c row) {
    Id source = row.AXF_TOB_LKP_BankTransaction__c != null
      ? row.AXF_TOB_LKP_BankTransaction__r?.AXF_BAT_MDR_BankAccount__c
      : row.AXF_TOB_LKP_CardTransaction__r?.AXF_CCT_MDR_CreditCard__c;
    return source == null ? null : String.valueOf(source);
  }

  // ------------------------------------------------------------ agrupamento (P3)

  private static Boolean qualifies(Observation candidate) {
    return candidate.eligibility == ELIGIBLE &&
      candidate.serviceHint == SERVICE_CANDIDATE &&
      candidate.direction == DEBIT &&
      candidate.chargedOn != null &&
      candidate.magnitude != null &&
      String.isNotBlank(candidate.observationKey) &&
      String.isNotBlank(candidate.transactionIdentity) &&
      String.isNotBlank(candidate.paymentSourceId) &&
      String.isNotBlank(candidate.currencyIsoCode) &&
      String.isNotBlank(candidate.normalizedMerchant);
  }

  private static Boolean isNewerRevision(Observation left, Observation right) {
    Decimal leftRevision = left.revision == null ? 0 : left.revision;
    Decimal rightRevision = right.revision == null ? 0 : right.revision;
    if (leftRevision != rightRevision) {
      return leftRevision > rightRevision;
    }
    return left.observationKey > right.observationKey;
  }

  /**
   * Identidade estavel do stream derivada de conteudo (titular, fonte de pagamento estavel,
   * moeda, estabelecimento normalizado) — nunca da identidade da transacao, que e unica por
   * cobranca, nem da versao de regra. Replay e mudanca de versao nao inventam outro stream.
   */
  private static String streamKey(Observation candidate) {
    return AXF_CLS_IdentityFraming.key(
      new List<Object>{
        candidate.ownerId,
        candidate.paymentSourceId,
        candidate.currencyIsoCode,
        candidate.normalizedMerchant
      }
    );
  }

  // ------------------------------------------------------------ avaliacao por stream (P1/P2)

  private static StreamAssignment assign(Stream bucket) {
    List<Observation> charges = new List<Observation>(bucket.charges);
    charges.sort(new ChargeOrder());
    StreamAssignment result = new StreamAssignment();
    result.streamKey = bucket.streamKey;
    result.ownerId = bucket.ownerId;
    result.paymentSourceId = bucket.paymentSourceId;
    result.currencyIsoCode = bucket.currencyIsoCode;
    result.normalizedMerchant = bucket.normalizedMerchant;
    result.anchorDate = charges[0].chargedOn;

    Attempt monthly = attempt(
      charges,
      MONTHLY,
      MONTHLY_MINIMUM_CHARGES,
      MONTHLY_DATE_TOLERANCE_DAYS,
      bucket.currencyIsoCode
    );
    Attempt annual = attempt(
      charges,
      ANNUAL,
      ANNUAL_MINIMUM_CHARGES,
      ANNUAL_DATE_TOLERANCE_DAYS,
      bucket.currencyIsoCode
    );
    result.unmatchedObservations = monthly.unmatchedObservations;
    result.observedCycles = monthly.observedCycles;
    result.lastObservedCycle = monthly.lastObservedCycle;

    // A ambiguidade exige revisao mesmo quando a outra cadencia qualificaria: cobrancas
    // indistinguiveis no mesmo ciclo nao podem ser resolvidas por escolha de cadencia (AC03).
    Attempt ambiguous = monthly.outcome == AMBIGUOUS
      ? monthly
      : (annual.outcome == AMBIGUOUS ? annual : null);
    if (ambiguous != null) {
      return describe(result, ambiguous);
    }
    if (monthly.outcome == QUALIFIED) {
      return describe(result, monthly);
    }
    if (annual.outcome == QUALIFIED) {
      return describe(result, annual);
    }
    // Nenhuma cadencia qualificou: relata-se a que mais avancou, na proporcao do proprio minimo.
    Attempt chosen = progress(annual) > progress(monthly) ? annual : monthly;
    return describe(result, chosen);
  }

  private static Decimal progress(Attempt attempt) {
    return attempt.minimum == 0
      ? 0
      : Decimal.valueOf(attempt.evidencedCycles) / attempt.minimum;
  }

  private static StreamAssignment describe(
    StreamAssignment result,
    Attempt attempt
  ) {
    result.cadence = attempt.cadence;
    result.outcome = attempt.outcome;
    result.reason = attempt.reason;
    result.evidencedCycles = attempt.evidencedCycles;
    result.observedCycles = attempt.observedCycles;
    result.lastObservedCycle = attempt.lastObservedCycle;
    // A referencia e o historico observado permanecem visiveis tambem quando a faixa de valor
    // barra o candidato: sao a explicacao da recusa, nao parte da proposta.
    result.referenceAmount = attempt.referenceAmount;
    result.evidence = attempt.evidence;
    result.ambiguousEvidence = attempt.ambiguousEvidence;
    result.ambiguousCycles = attempt.collisions;
    if (attempt.outcome == QUALIFIED) {
      result.nextEstimateDate = attempt.nextEstimateDate;
    }
    return result;
  }

  private static Attempt attempt(
    List<Observation> charges,
    String cadence,
    Integer minimum,
    Integer tolerance,
    String currencyIsoCode
  ) {
    Attempt result = new Attempt();
    result.cadence = cadence;
    result.minimum = minimum;
    Date anchor = charges[0].chargedOn;

    Map<Integer, List<Observation>> byCycle = new Map<Integer, List<Observation>>();
    for (Observation charge : charges) {
      Integer cycle = nearestCycle(
        anchor,
        cadence,
        charge.chargedOn,
        tolerance
      );
      if (cycle == null) {
        result.unmatchedObservations++;
        continue;
      }
      if (!byCycle.containsKey(cycle)) {
        byCycle.put(cycle, new List<Observation>());
      }
      byCycle.get(cycle).add(charge);
    }

    List<Integer> cycles = new List<Integer>(byCycle.keySet());
    cycles.sort();
    for (Integer cycle : cycles) {
      List<Observation> inCycle = byCycle.get(cycle);
      if (inCycle.size() > 1) {
        result.collisions.add(cycle);
        for (Observation charge : inCycle) {
          result.ambiguousEvidence.add(
            row(charge, cycle, expectedDate(anchor, cadence, cycle))
          );
        }
      }
    }
    if (!result.collisions.isEmpty()) {
      result.outcome = AMBIGUOUS;
      result.reason = REASON_CYCLE_COLLISION;
      return result;
    }

    result.observedCycles = cycles.size();
    result.lastObservedCycle = cycles[cycles.size() - 1];

    // Ciclos consecutivos a partir da ancora; um ciclo faltante bloqueia a qualificacao inicial.
    for (Integer index = 0; index < minimum; index++) {
      if (!byCycle.containsKey(index)) {
        result.outcome = INSUFFICIENT_HISTORY;
        result.reason = REASON_MISSING_CYCLES;
        result.evidencedCycles = index;
        return result;
      }
    }
    result.evidencedCycles = minimum;

    List<Decimal> amounts = new List<Decimal>();
    for (Integer index = 0; index < minimum; index++) {
      Observation charge = byCycle.get(index)[0];
      result.evidence.add(
        row(charge, index, expectedDate(anchor, cadence, index))
      );
      amounts.add(charge.magnitude);
    }
    result.referenceAmount = median(amounts);

    Decimal band = valueFloor(currencyIsoCode);
    Decimal relative = result.referenceAmount * CANDIDATE_VALUE_RATE;
    if (relative > band) {
      band = relative;
    }
    for (CycleAssignment evidenceRow : result.evidence) {
      if ((evidenceRow.magnitude - result.referenceAmount).abs() > band) {
        result.outcome = INSUFFICIENT_HISTORY;
        result.reason = REASON_VALUE_BAND;
        return result;
      }
    }

    result.outcome = QUALIFIED;
    // Uma cadencia depois do ciclo mais recente observado, sempre a partir da ancora retida —
    // nunca depois da evidencia minima, que produziria uma data ja no passado (AC07).
    result.nextEstimateDate = expectedDate(
      anchor,
      cadence,
      result.lastObservedCycle + 1
    );
    return result;
  }

  /** Piso de P2 na moeda do stream; moeda sem piso configurado usa apenas a taxa relativa. */
  private static Decimal valueFloor(String currencyIsoCode) {
    return currencyIsoCode == CANDIDATE_VALUE_FLOOR_CURRENCY
      ? CANDIDATE_VALUE_FLOOR
      : 0;
  }

  private static CycleAssignment row(
    Observation charge,
    Integer cycle,
    Date expected
  ) {
    CycleAssignment result = new CycleAssignment();
    result.cycleIndex = cycle;
    result.expectedDate = expected;
    result.chargedOn = charge.chargedOn;
    result.magnitude = charge.magnitude;
    result.observationKey = charge.observationKey;
    return result;
  }

  /**
   * Ciclo esperado mais proximo da data observada, ou null quando nenhum cai na tolerancia. A
   * varredura de -1 a +1 com comparacao estrita define a escolha de forma deterministica; com as
   * tolerancias configuradas (+/-5 e +/-15 dias) dois ciclos vizinhos nunca ficam ambos dentro da
   * tolerancia da mesma data, porque estao a cerca de um mes ou um ano de distancia.
   */
  private static Integer nearestCycle(
    Date anchor,
    String cadence,
    Date chargedOn,
    Integer tolerance
  ) {
    Integer base = cadence == MONTHLY
      ? monthIndex(chargedOn) - monthIndex(anchor)
      : chargedOn.year() - anchor.year();
    Integer best = null;
    Integer bestDistance = null;
    for (Integer offset = -1; offset <= 1; offset++) {
      Integer cycle = base + offset;
      if (cycle < 0) {
        continue;
      }
      Integer distance = Math.abs(
        expectedDate(anchor, cadence, cycle).daysBetween(chargedOn)
      );
      if (bestDistance == null || distance < bestDistance) {
        best = cycle;
        bestDistance = distance;
      }
    }
    if (bestDistance == null || bestDistance > tolerance) {
      return null;
    }
    return best;
  }

  /** Data esperada do ciclo: mes/ano de calendario com fixacao do dia no ultimo dia do mes. */
  private static Date expectedDate(Date anchor, String cadence, Integer cycle) {
    return addMonthsClamped(anchor, cadence == MONTHLY ? cycle : cycle * 12);
  }

  private static Date addMonthsClamped(Date anchor, Integer months) {
    Integer total = monthIndex(anchor) + months;
    Integer year = total / 12;
    Integer month = Math.mod(total, 12) + 1;
    Integer day = Math.min(anchor.day(), Date.daysInMonth(year, month));
    return Date.newInstance(year, month, day);
  }

  private static Integer monthIndex(Date value) {
    return value.year() * 12 + (value.month() - 1);
  }

  private static Decimal median(List<Decimal> amounts) {
    List<Decimal> sorted = new List<Decimal>(amounts);
    sorted.sort();
    Integer size = sorted.size();
    if (Math.mod(size, 2) == 1) {
      return sorted[size / 2];
    }
    return (sorted[size / 2 - 1] + sorted[size / 2]) / 2;
  }

  private static RecurrenceException failure(String code) {
    RecurrenceException result = new RecurrenceException(code);
    result.code = code;
    return result;
  }
}
