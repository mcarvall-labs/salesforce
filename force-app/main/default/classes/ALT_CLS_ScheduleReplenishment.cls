/**
 * AXF-103 fatia 2 — regra pura da reposição rolante da janela do cronograma.
 *
 * Decide, sem SOQL, sem DML e sem describe:
 *  1. quais ocorrências elegíveis ainda faltam dentro da janela rolante, respeitando o limite de
 *     50 por transação e o fim do termo;
 *  2. até onde a cobertura avança — só sobre o prefixo contíguo efetivamente contabilizado;
 *  3. a escada de recuo (1, 5 e 30 minutos), o orçamento de tentativas e a janela do REALARME
 *     limitado depois do orçamento esgotado;
 *  4. se um cronograma está atrás da janela para fins de DESPACHO (o agendador não usa o motor
 *     de projeção, que é uma leitura autorizada por titular);
 *  5. os limites de engenharia DECLARADOS (ocorrências por transação, cronogramas por cadeia,
 *     identidades rastreadas por cronograma) e o catálogo fechado de códigos de erro.
 *
 * O critério de "o que falta" NÃO é reimplementado aqui: a entrada é a leitura do motor único de
 * projeção (`ALT_CLS_ScheduleProjection.ProjectionResult.lines`), que já decide persistida
 * contra virtual pela mesma identidade que a leitura usa. Esta classe decide apenas o recorte da
 * janela, o limite da transação, o avanço do cursor de cobertura e a política de retry — e é
 * testável sem DML.
 */
public inherited sharing class ALT_CLS_ScheduleReplenishment {
  /** Limite de engenharia de ocorrências materializadas por transação. */
  public static final Integer MAX_OCCURRENCES_PER_TRANSACTION = 50;
  /**
   * Maior atraso aceito pelo enqueue atrasado da plataforma (0–10 minutos). O degrau de 30
   * minutos não cabe nele: fica persistido em `NextAttemptAt` para a passagem seguinte do
   * agendador, em vez de um timer inventado.
   */
  public static final Integer MAX_DELAYED_ENQUEUE_MINUTES = 10;
  /** Escada de recuo aprovada, em minutos, por degrau. Outro valor exige aprovação humana. */
  public static final List<Integer> BACKOFF_MINUTES = new List<Integer>{
    1,
    5,
    30
  };
  /**
   * Orçamento de tentativas: a escada tem três degraus, então a quarta falha consecutiva esgota o
   * orçamento. Esgotado, o trabalho para e sinaliza atenção operacional em vez de repetir.
   */
  public static final Integer MAX_RETRY_COUNT = BACKOFF_MINUTES.size();
  /**
   * Teto DECLARADO de trabalho de UMA cadeia de despacho: `DispatchBatchSize` vezes
   * `MaxContinuationRounds` não pode ultrapassar este número. O orçamento assíncrono da org é
   * finito; uma política que prometa mais do que isto é recusada na fronteira, em vez de
   * descobrir o teto no meio da drenagem.
   */
  public static final Integer MAX_SCHEDULES_PER_CHAIN = 500;
  /**
   * Teto DECLARADO de identidades rastreadas lidas em memória para UM cronograma. A leitura de
   * identidades é o único ponto da passagem que cresce com o histórico já materializado: acima
   * deste número a passagem RECUSA em vez de carregar a linha inteira e estourar o heap no meio
   * do savepoint.
   */
  public static final Integer MAX_TRACKED_IDENTITIES_PER_SCHEDULE = 4000;
  /**
   * Janela padrão do realarme limitado de um orçamento esgotado, em horas. A política aprovada
   * pode declarar outra; o que não pode existir é repetição sem limite nem espera.
   */
  public static final Integer DEFAULT_REARM_HOURS = 24;

  public static final String ERROR_DML = 'DML_FAILED';
  public static final String ERROR_QUERY = 'QUERY_FAILED';
  public static final String ERROR_PROJECTION_STALE = 'PROJECTION_STALE';
  public static final String ERROR_PROJECTION_BLOCKED = 'PROJECTION_BLOCKED';
  public static final String ERROR_PROJECTION_AMBIGUOUS = 'PROJECTION_AMBIGUOUS';
  public static final String ERROR_PROJECTION_UNSUPPORTED = 'PROJECTION_UNSUPPORTED';
  public static final String ERROR_PROJECTION_INVALID = 'PROJECTION_INVALID';
  public static final String ERROR_PROJECTION_MISSING = 'PROJECTION_MISSING';
  public static final String ERROR_PLAN_INCOMPLETE = 'PLAN_INCOMPLETE';
  public static final String ERROR_CALENDAR = 'CALENDAR_FAILED';
  public static final String ERROR_FORMULA = 'FORMULA_FAILED';
  public static final String ERROR_IDENTITY = 'IDENTITY_CONFLICT';
  public static final String ERROR_HOLDER_UNAVAILABLE = 'HOLDER_UNAVAILABLE';
  public static final String ERROR_PRINCIPAL_WITHOUT_VISIBILITY = 'PRINCIPAL_WITHOUT_VISIBILITY';
  public static final String ERROR_PERMISSION_DENIED = 'PERMISSION_DENIED';
  public static final String ERROR_AUTHORITY_TRUNCATED = 'AUTHORITY_SCOPE_TRUNCATED';
  public static final String ERROR_SCALE_LIMIT = 'SCALE_LIMIT_EXCEEDED';
  public static final String ERROR_EXHAUSTED = 'RETRY_EXHAUSTED';
  public static final String ERROR_UNEXPECTED = 'UNEXPECTED';

  /**
   * Catálogo fechado: nenhum texto livre — mensagem de exceção, nome de campo ou stack trace —
   * chega ao campo persistido. O que não está aqui vira `UNEXPECTED`.
   *
   * Significado de cada código para o OPERADOR (a lista é a superfície acionável do estado
   * persistido em `AXF_FSC_TXT_LastErrorCode__c`):
   *  - `DML_FAILED` / `QUERY_FAILED`: falha de infraestrutura na escrita/leitura. Recuperável:
   *    a passagem repete com recuo.
   *  - `PROJECTION_STALE`: a revisão ou o ponteiro vigente mudou entre a leitura e o lock.
   *    Recuperável: nada foi gravado e a passagem seguinte relê.
   *  - `PROJECTION_AMBIGUOUS`: há confirmações de referência conflitantes na mesma ordem
   *    econômica. PERMANENTE: só uma resolução explícita da referência libera.
   *  - `PROJECTION_UNSUPPORTED`: a definição vigente não produz valor (método sem valor,
   *    fórmula sem resultado). PERMANENTE: exige correção da definição.
   *  - `PROJECTION_INVALID`: a leitura recusou a sequência rastreada — definição efetiva
   *    ausente, ocorrência duplicada na mesma identidade, identidade que não corresponde à
   *    posição, ou ponteiro para definição/referência de outro cronograma. PERMANENTE.
   *  - `PROJECTION_MISSING`: a leitura autorizada não devolveu resultado. PERMANENTE.
   *  - `PROJECTION_BLOCKED`: desfecho de leitura fora do catálogo conhecido, ou recorte da
   *    janela recusado pelo motor de regra (defeito de plano). PERMANENTE.
   *  - `PLAN_INCOMPLETE`: uma linha da projeção chegou sem vencimento nominal; o recorte não
   *    pode ser decidido. PERMANENTE — é defeito de plano, nunca "fora da janela".
   *  - `CALENDAR_FAILED` / `FORMULA_FAILED`: o calendário ou a fórmula aprovada recusou a
   *    sequência (inclusive estouro numérico determinístico). PERMANENTE.
   *  - `IDENTITY_CONFLICT`: a sequência já pertence a outra identidade completa. PERMANENTE.
   *  - `PRINCIPAL_WITHOUT_VISIBILITY`: o principal não enxerga o cronograma nem o titular.
   *    PERMANENTE: provisione visibilidade; repetir não resolve.
   *  - `PERMISSION_DENIED`: o principal não tem permissão de criação da ocorrência.
   *    PERMANENTE: provisione a permissão.
   *  - `SCALE_LIMIT_EXCEEDED`: o cronograma tem mais identidades rastreadas do que o teto
   *    declarado. PERMANENTE: exige dimensionamento antes de nova passagem.
   *  - `AUTHORITY_SCOPE_TRUNCATED`: NÃO é "sem visibilidade" — é o teto diferido de 200
   *    titulares do serviço de contextos autorizados não permitindo CONCLUIR a autorização.
   *    NÃO terminal: nenhum estado bloqueante é gravado e o despacho continua.
   *  - `RETRY_EXHAUSTED`: o orçamento de tentativas acabou. Terminal, com realarme limitado.
   *  - `UNEXPECTED`: qualquer outro desfecho. Recuperável com recuo.
   */
  private static final Set<String> ERROR_CODES = new Set<String>{
    ERROR_DML,
    ERROR_QUERY,
    ERROR_PROJECTION_STALE,
    ERROR_PROJECTION_BLOCKED,
    ERROR_PROJECTION_AMBIGUOUS,
    ERROR_PROJECTION_UNSUPPORTED,
    ERROR_PROJECTION_INVALID,
    ERROR_PROJECTION_MISSING,
    ERROR_PLAN_INCOMPLETE,
    ERROR_CALENDAR,
    ERROR_FORMULA,
    ERROR_IDENTITY,
    ERROR_HOLDER_UNAVAILABLE,
    ERROR_PRINCIPAL_WITHOUT_VISIBILITY,
    ERROR_PERMISSION_DENIED,
    ERROR_AUTHORITY_TRUNCATED,
    ERROR_SCALE_LIMIT,
    ERROR_EXHAUSTED,
    ERROR_UNEXPECTED
  };

  /**
   * Falhas que NÃO melhoram por repetição: um titular que o principal não enxerga, uma permissão
   * ausente, uma identidade conflitante, um calendário ou uma fórmula recusados pelo motor, um
   * bloqueio de leitura (duplicidade, ambiguidade, definição ausente), um plano incompleto, um
   * cronograma acima do teto declarado de escala ou o orçamento esgotado.
   * Elas são registradas como estado ACIONÁVEL e nunca consomem orçamento de retry; enquanto
   * estiverem marcadas, o cronograma sai do conjunto devido (senão a cauda da fila morre de fome
   * atrás de um cronograma que nunca vai progredir).
   *
   * `AUTHORITY_SCOPE_TRUNCATED` NÃO está aqui de propósito: confundir o teto diferido de 200
   * titulares do serviço de contextos com "principal sem visibilidade" gravaria um estado
   * permanente e bloqueante de despacho que nenhuma correção de visibilidade limpa.
   */
  private static final Set<String> TERMINAL_CODES = new Set<String>{
    ERROR_IDENTITY,
    ERROR_CALENDAR,
    ERROR_FORMULA,
    ERROR_PROJECTION_BLOCKED,
    ERROR_PROJECTION_AMBIGUOUS,
    ERROR_PROJECTION_UNSUPPORTED,
    ERROR_PROJECTION_INVALID,
    ERROR_PROJECTION_MISSING,
    ERROR_PLAN_INCOMPLETE,
    ERROR_PRINCIPAL_WITHOUT_VISIBILITY,
    ERROR_PERMISSION_DENIED,
    ERROR_SCALE_LIMIT,
    ERROR_EXHAUSTED
  };

  public class ReplenishmentException extends Exception {
  }

  /**
   * Entrada do planejamento: a leitura do motor único, já recortada por identidade e revisão.
   */
  public class PlanInput {
    /** Linhas do motor único para o cronograma, em sequência ascendente. */
    public List<ALT_CLS_ScheduleProjection.OccurrenceLine> lines;
    /** Fim do mês do horizonte persistido, informado pelo motor (`horizonEndDate`). */
    public Date windowEndDate;
    /** Nada abaixo desta sequência é conhecido — inclusive para a cobertura. */
    public Integer trackingStartSequence;
    /** Cursor de cobertura persistido. */
    public Integer coverageSequence;
    /** Limite de ocorrências desta transação. */
    public Integer maxOccurrences;
    /** Recorrência indefinida: nunca existe fim de termo a registrar. */
    public Boolean unbounded = false;
    /**
     * O motor avaliou a faixa inteira sem truncar (`ProjectionResult.coverageComplete`). Falso na
     * recorrência indefinida, onde "cobertura completa" não existe.
     */
    public Boolean coverageComplete = false;
  }

  public class Plan {
    /** Sequências a materializar nesta transação, em ordem ascendente. */
    public List<Integer> sequences = new List<Integer>();
    public Set<Integer> planned = new Set<Integer>();
    public Integer firstPlannedSequence;
    public Integer lastPlannedSequence;
    public Integer previousCoverageSequence;
    /** Cobertura depois desta transação: o prefixo contíguo contabilizado. */
    public Integer coverageSequence;
    /** Há trabalho elegível além do limite desta transação: a continuação precisa encadear. */
    public Boolean moreWork = false;
    /** O termo terminou: nada mais será criado, nem agora nem depois. */
    public Boolean termReached = false;
    /** Ocorrências elegíveis dentro da janela. */
    public Integer eligibleCount = 0;
    /** Ocorrências elegíveis ausentes dentro da janela. */
    public Integer missingCount = 0;
    /**
     * Ocorrências virtuais DEPOIS do fim da janela. Não são trabalho desta passagem, mas
     * enquanto existirem o termo não terminou.
     */
    public Integer beyondWindowCount = 0;
    /**
     * O motor truncou por teto de avaliação. A passagem materializa o que estava ao alcance e
     * registra cobertura parcial — NUNCA como falha retomável que queima orçamento.
     */
    public Boolean evaluationCut = false;
    public Date windowEndDate;

    /** Nenhuma ocorrência elegível ficou de fora desta passagem. */
    public Boolean nothingMissing() {
      return missingCount == 0;
    }
  }

  public class RetryDecision {
    /** Tentativas acumuladas depois desta decisão. */
    public Integer retryCount = 0;
    /** Atraso que cabe no enqueue atrasado; nulo no degrau de 30 minutos e no esgotado. */
    public Integer delayMinutes;
    /** Próxima tentativa persistida; nulo quando o orçamento se esgotou. */
    public DateTime nextAttemptAt;
    /** Orçamento esgotado: para e sinaliza em vez de repetir indefinidamente. */
    public Boolean exhausted = false;
  }

  /**
   * Entrada do critério de DESPACHO. É deliberadamente barato: o agendador percorre a fila de
   * cronogramas sem executar a leitura autorizada por titular de cada um.
   */
  public class DispatchInput {
    public Integer firstSequence;
    public Date firstDueDate;
    public Integer periodMonths;
    /** AXF-155: periodicidade em dias (7/14), exclusiva com `periodMonths`. */
    public Integer periodDays;
    public Integer anchorDay;
    /** Última sequência do termo; nulo em recorrência indefinida. */
    public Integer lastCoveredSequence;
    public Integer trackingStartSequence;
    public Integer coverageSequence;
    /** Fim do mês do horizonte, calculado com `ALT_CLS_ScheduleCalendar`. */
    public Date windowEndDate;
  }

  /**
   * @description Recorte da janela rolante e seleção do que materializar nesta transação.
   *
   * A varredura parte de `TrackingStartSequence`, e não do cursor de cobertura: uma lacuna abaixo
   * do cursor continua sendo uma obrigação conhecida e precisa ser materializada. A cobertura, ao
   * contrário, só avança sobre o prefixo contíguo contabilizado — nunca sobre uma lacuna.
   *
   * Uma linha SEM vencimento nominal não é "fora da janela": ela é defeito de plano, e o recorte
   * é RECUSADO com código próprio em vez de tratar a ausência como ausência de trabalho.
   */
  public static Plan plan(PlanInput input) {
    if (input == null || input.lines == null) {
      throw new ReplenishmentException(
        'A reposição exige a projeção do cronograma como entrada.'
      );
    }
    if (input.windowEndDate == null) {
      // Sem o fim da janela nenhuma ocorrência seria elegível e a passagem viraria um no-op
      // silencioso sobre uma obrigação conhecida: o recorte é recusado em vez de mentir.
      throw new ReplenishmentException(
        'A reposição exige o fim da janela rolante calculado pelo motor de projeção.'
      );
    }
    Plan result = new Plan();
    Integer trackingStart = (input.trackingStartSequence == null ||
      input.trackingStartSequence < 1)
      ? 1
      : input.trackingStartSequence;
    Integer maxOccurrences = clampLimit(input.maxOccurrences);
    result.windowEndDate = input.windowEndDate;
    result.previousCoverageSequence = (input.coverageSequence == null)
      ? 0
      : input.coverageSequence;
    result.evaluationCut =
      input.unbounded != true &&
      input.coverageComplete != true;

    List<Integer> missing = new List<Integer>();
    Set<Integer> accounted = new Set<Integer>();
    for (ALT_CLS_ScheduleProjection.OccurrenceLine line : input.lines) {
      if (
        line == null ||
        line.sequence == null ||
        line.sequence < trackingStart
      ) {
        // Histórico pré-rastreamento permanece desconhecido: não é somado, não é gerado e não
        // participa da cobertura.
        continue;
      }
      if (line.nominalDueDate == null) {
        // Ausência de vencimento nominal NÃO é "fora da janela": é defeito de plano. Tratá-la
        // como fora da janela deixaria a ocorrência virtual para sempre e faria `termReached`
        // nunca ficar verdadeiro — em silêncio.
        throw new ReplenishmentException(
          'A linha da sequência ' +
            line.sequence +
            ' chegou sem vencimento nominal: o recorte da janela não é decidível.'
        );
      }
      if (!withinWindow(line.nominalDueDate, input.windowEndDate)) {
        if (line.persisted == true) {
          // Cobertura é o prefixo contíguo CONTABILIZADO, não o recorte da janela: uma ocorrência
          // persistida acima da borda continua contabilizada e não pode fazer o cursor regredir.
          accounted.add(line.sequence);
        } else {
          result.beyondWindowCount++;
        }
        continue;
      }
      result.eligibleCount++;
      if (line.persisted == true) {
        accounted.add(line.sequence);
      } else {
        missing.add(line.sequence);
      }
    }

    result.missingCount = missing.size();
    for (Integer index = 0; index < missing.size(); index++) {
      if (result.sequences.size() >= maxOccurrences) {
        result.moreWork = true;
        break;
      }
      Integer sequence = missing[index];
      result.sequences.add(sequence);
      result.planned.add(sequence);
      // O que esta transação vai gravar já conta para a cobertura: o cursor é persistido junto da
      // materialização, na mesma transação.
      accounted.add(sequence);
    }
    if (!result.sequences.isEmpty()) {
      result.firstPlannedSequence = result.sequences[0];
      result.lastPlannedSequence = result.sequences[
        result.sequences.size() - 1
      ];
    }
    result.coverageSequence = coverageAfter(trackingStart, accounted);
    // Um recorte truncado pelo teto de avaliação não autoriza dizer "acabou": a passagem
    // registra cobertura PARCIAL, sem queimar tentativa, e a continuação pega o resto.
    result.termReached =
      input.unbounded != true &&
      input.coverageComplete == true &&
      result.missingCount == 0 &&
      result.beyondWindowCount == 0;
    return result;
  }

  /**
   * @description Limite de ocorrências por transação, nunca acima do teto de engenharia. Um
   * pedido maior é reduzido, não recusado: o trabalho continua encadeando.
   */
  public static Integer clampLimit(Integer requested) {
    if (requested == null || requested < 1) {
      return MAX_OCCURRENCES_PER_TRANSACTION;
    }
    return Math.min(requested, MAX_OCCURRENCES_PER_TRANSACTION);
  }

  /**
   * @description Cursor de cobertura: a maior sequência do prefixo contíguo contabilizado a
   * partir de `TrackingStartSequence`. Não é a maior sequência gravada nem a data da última
   * execução: uma lacuna interrompe o avanço, e o que está acima da lacuna não a ultrapassa.
   */
  public static Integer coverageAfter(
    Integer trackingStartSequence,
    Set<Integer> accountedSequences
  ) {
    Integer start = (trackingStartSequence == null ||
      trackingStartSequence < 1)
      ? 1
      : trackingStartSequence;
    Set<Integer> accounted = (accountedSequences == null)
      ? new Set<Integer>()
      : accountedSequences;
    Integer frontier = start - 1;
    for (Integer sequence : accounted) {
      if (sequence != null && sequence >= start && sequence > frontier) {
        frontier = sequence;
      }
    }
    // O laço para na primeira lacuna, então ele nunca roda mais do que o próprio conjunto
    // contabilizado: o custo é proporcional ao dado, não à sequência mais alta já vista.
    Integer coverage = start - 1;
    for (Integer sequence = start; sequence <= frontier; sequence++) {
      if (!accounted.contains(sequence)) {
        break;
      }
      coverage = sequence;
    }
    return coverage;
  }

  /**
   * @description O cronograma está atrás da janela? Critério de DESPACHO do agendador: existe ao
   * menos uma sequência elegível acima da cobertura, dentro do termo e com vencimento nominal
   * dentro da janela. Não substitui o motor de projeção, que continua sendo a autoridade de
   * valor, identidade e truncamento dentro da transação de geração.
   */
  public static Boolean isBehindWindow(DispatchInput input) {
    if (
      input == null ||
      input.firstDueDate == null ||
      input.windowEndDate == null
    ) {
      return false;
    }
    Integer trackingStart = (input.trackingStartSequence == null ||
      input.trackingStartSequence < 1)
      ? 1
      : input.trackingStartSequence;
    Integer coverage = (input.coverageSequence == null)
      ? 0
      : input.coverageSequence;
    Integer next = Math.max(coverage + 1, trackingStart);
    if (input.lastCoveredSequence != null && next > input.lastCoveredSequence) {
      // Fim do termo alcançado: nada é criado além dele.
      return false;
    }
    Date nominal;
    try {
      nominal = ALT_CLS_ScheduleCalendar.nominalDueDate(
        input.firstDueDate,
        (input.firstSequence == null) ? 1 : input.firstSequence,
        input.periodMonths,
        input.periodDays,
        input.anchorDay,
        next
      );
    } catch (ALT_CLS_ScheduleCalendar.CalendarException invalidCalendar) {
      // Um calendário que o motor puro recusa é estado acionável do cronograma, não motivo para
      // mantê-lo na fila: quem decide o desfecho é a passagem autorizada, e não o agendador.
      return false;
    }
    return !(nominal > input.windowEndDate);
  }

  /**
   * @description Existe uma LACUNA abaixo do cursor de cobertura? A cobertura é o prefixo
   * contíguo contabilizado, então o número de identidades VÁLIDAS persistidas dentro de
   * `[TrackingStartSequence, CoverageSequence]` precisa ser exatamente o tamanho desse intervalo.
   * Um número menor prova a lacuna — é o sinal barato e correto de que o cronograma está atrás
   * mesmo quando a borda da janela já não avança (uma ocorrência persistida apagada depois do
   * avanço do cursor deixa exatamente esse estado).
   *
   * "Identidade válida" é a mesma definição que a projeção usa: a linha cancelada não conta. Se
   * a contagem incluísse canceladas, uma linha `CANCELLED` dentro do intervalo faria a contagem
   * bater com o esperado, o detector nunca dispararia e o cronograma sairia da fila.
   */
  public static Boolean hasCoverageHole(
    Integer persistedInRange,
    Integer coverageSequence,
    Integer trackingStartSequence
  ) {
    Integer start = (trackingStartSequence == null ||
      trackingStartSequence < 1)
      ? 1
      : trackingStartSequence;
    Integer coverage = (coverageSequence == null) ? 0 : coverageSequence;
    if (coverage < start) {
      // Nada confirmado ainda: não existe prefixo onde caiba lacuna.
      return false;
    }
    Integer expected = coverage - start + 1;
    Integer persisted = (persistedInRange == null) ? 0 : persistedInRange;
    return persisted < expected;
  }

  /**
   * @description Decisão de recuo para uma falha. A tentativa N+1 usa o degrau N da escada; a
   * partir da quarta falha consecutiva o orçamento se esgota, nada é agendado e o estado
   * persistido passa a ser o sinal acionável.
   */
  public static RetryDecision nextAttempt(
    Integer retryCount,
    DateTime failedAt
  ) {
    if (failedAt == null) {
      throw new ReplenishmentException(
        'A decisão de recuo exige o instante da falha.'
      );
    }
    RetryDecision decision = new RetryDecision();
    Integer previous = (retryCount == null || retryCount < 0) ? 0 : retryCount;
    Integer next = previous + 1;
    if (next > MAX_RETRY_COUNT) {
      decision.retryCount = MAX_RETRY_COUNT;
      decision.exhausted = true;
      return decision;
    }
    decision.retryCount = next;
    Integer minutes = backoffMinutes(next);
    decision.nextAttemptAt = failedAt.addMinutes(minutes);
    decision.delayMinutes = (minutes > MAX_DELAYED_ENQUEUE_MINUTES)
      ? null
      : minutes;
    return decision;
  }

  /**
   * @description Instante do REALARME limitado de um orçamento esgotado. O orçamento de retry
   * continua esgotado — nenhuma passagem automática o reinicia —, mas o cronograma passa a ter um
   * horário declarado a partir do qual a passagem de recuperação tenta UMA vez de novo. Sem isso,
   * quatro falhas transitórias desligariam a reposição daquele cronograma para sempre; com um
   * reset irrestrito, a falha permanente repetiria para sempre.
   */
  public static DateTime rearmAt(DateTime failedAt, Integer rearmHours) {
    if (failedAt == null) {
      throw new ReplenishmentException('O realarme exige o instante da falha.');
    }
    Integer hours = (rearmHours == null ||
      rearmHours < 1)
      ? DEFAULT_REARM_HOURS
      : rearmHours;
    return failedAt.addHours(hours);
  }

  /**
   * @description Degrau N da escada aprovada. Uma escada diferente da aprovada é recusada em vez
   * de aceita em silêncio: mudar 1/5/30 exige aprovação humana.
   */
  public static Integer backoffMinutes(Integer step) {
    if (step == null || step < 1 || step > BACKOFF_MINUTES.size()) {
      throw new ReplenishmentException(
        'Degrau de recuo fora da escada aprovada (1, 5 e 30 minutos).'
      );
    }
    return BACKOFF_MINUTES[step - 1];
  }

  /** @description Valida uma escada declarada contra a escada aprovada. */
  public static Boolean isApprovedLadder(List<Integer> declared) {
    return declared != null && declared.equals(BACKOFF_MINUTES);
  }

  /**
   * @description O orçamento assíncrono de UMA cadeia cabe no teto declarado? `DispatchBatchSize`
   * vezes `MaxContinuationRounds` é o número máximo de cronogramas que uma cadeia pode despachar;
   * a política é recusada na fronteira quando promete mais do que o teto.
   */
  public static Boolean isChainBudgetRespected(
    Integer dispatchBatchSize,
    Integer maxContinuationRounds
  ) {
    if (
      dispatchBatchSize == null ||
      dispatchBatchSize < 1 ||
      maxContinuationRounds == null ||
      maxContinuationRounds < 1
    ) {
      return false;
    }
    Long promised = (Long) dispatchBatchSize * (Long) maxContinuationRounds;
    return promised <= MAX_SCHEDULES_PER_CHAIN;
  }

  /**
   * @description A leitura de identidades rastreadas cabe no teto declarado? Acima dele a
   * passagem recusa em vez de carregar o histórico inteiro em memória.
   */
  public static Boolean isTrackedIdentitiesWithinLimit(Integer count) {
    return count != null && count <= MAX_TRACKED_IDENTITIES_PER_SCHEDULE;
  }

  /**
   * @description Estado de retry reconciliado por uma passagem bem-sucedida: orçamento zerado,
   * sem próximo horário e sem código de erro pendente.
   */
  public static RetryDecision reconciled() {
    return new RetryDecision();
  }

  /**
   * @description O cronograma está bloqueado para DESPACHO AUTOMÁTICO? Orçamento esgotado ou
   * estado terminal persistido mantêm o cronograma fora do conjunto devido — a passagem continua
   * registrada e consultável, e nenhuma tentativa é consumida por repetição. O realarme do
   * orçamento esgotado acontece pela passagem de RECUPERAÇÃO, e não por este portão.
   */
  public static Boolean blocksDispatch(
    String lastErrorCode,
    Integer retryCount,
    Integer maxRetryCount
  ) {
    Integer budget = (maxRetryCount == null ||
      maxRetryCount < 1)
      ? MAX_RETRY_COUNT
      : maxRetryCount;
    if (retryCount != null && retryCount >= budget) {
      return true;
    }
    return isTerminal(lastErrorCode);
  }

  /** @description Código terminal: não melhora por repetição. */
  public static Boolean isTerminal(String code) {
    return !String.isBlank(code) && TERMINAL_CODES.contains(code);
  }

  /**
   * @description Os códigos terminais, para o caminho privilegiado de leitura do job excluí-los
   * na PRÓPRIA consulta da fila em vez de gastar uma posição do lote num cronograma que nunca vai
   * progredir.
   */
  public static Set<String> terminalCodes() {
    return TERMINAL_CODES.clone();
  }

  /** @description Código recuperável: repetir é legítimo, com recuo limitado. */
  public static Boolean isRetryable(String code) {
    return !String.isBlank(code) && !TERMINAL_CODES.contains(code);
  }

  /**
   * @description Código de erro higienizado. Qualquer coisa fora do catálogo — mensagem de
   * exceção, nome de campo, identificador — vira `UNEXPECTED`: o campo persistido nunca carrega
   * stack trace nem dado sensível.
   */
  public static String sanitizeErrorCode(String raw) {
    if (String.isBlank(raw)) {
      return ERROR_UNEXPECTED;
    }
    String candidate = raw.trim().toUpperCase();
    return ERROR_CODES.contains(candidate) ? candidate : ERROR_UNEXPECTED;
  }

  private static Boolean withinWindow(Date nominalDueDate, Date windowEndDate) {
    if (nominalDueDate == null || windowEndDate == null) {
      return false;
    }
    return !(nominalDueDate > windowEndDate);
  }
}
