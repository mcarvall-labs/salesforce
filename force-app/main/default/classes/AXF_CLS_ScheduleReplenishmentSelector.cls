/**
 * AXF-103 fatia 2 — caminho privilegiado DECLARADO de leitura do job de reposição.
 *
 * Por que esta classe existe (decisão explícita, não comentário): as keywords de
 * compartilhamento da classe é que governam visibilidade de registro. `AccessLevel.SYSTEM_MODE`
 * desliga apenas permissão de objeto e FLS — ele NÃO amplia visibilidade de registro. Um
 * agendador `with sharing` que lesse a fila com SYSTEM_MODE selecionaria ZERO cronogramas em
 * produção e a funcionalidade ficaria muda, com a suíte inteira verde.
 *
 * Portanto o caminho de leitura do job vive aqui, `without sharing`, restrito ao mínimo
 * necessário para DESPACHO: identidade do cronograma, titular, cursores, estado de retry e o
 * calendário da definição vigente. Nenhum valor financeiro, nenhuma evidência e nenhuma escrita
 * atravessam esta classe. A geração em si continua passando pela porta única de escrita
 * (ALT_CLS_FinancialScheduleService), que revalida autoridade do titular e permissão a cada
 * transação — e um titular que o principal não enxerga é desfecho PERMANENTE e NÃO RETOMÁVEL,
 * nunca consumo de orçamento de retry.
 *
 * A leitura privilegiada é INALCANÇÁVEL fora do caminho interno: `workItems` é privado e visível
 * apenas ao teste. O único ponto de entrada PÚBLICO que aceita Ids é `directedWork`, e ele submete
 * o chamador à MESMA autoridade de titular do serviço antes de devolver qualquer identidade.
 */
public without sharing class AXF_CLS_ScheduleReplenishmentSelector {
  public static final String STATE_ACTIVE = 'ACTIVE';
  public static final String STATE_CANCELLED = 'CANCELLED';

  /**
   * Teto de candidatos lidos por passagem. Não é uma afirmação de capacidade da plataforma: é o
   * limite que mantém a leitura da fila seletiva e previsível. O excedente NÃO é descartado — ele
   * permanece no conjunto devido e é re-selecionado pela própria cadeia ou pela passagem seguinte.
   */
  public static final Integer MAX_CANDIDATES = 200;
  /** Fator de folga entre candidatos lidos e trabalho realmente despachado numa passagem. */
  @TestVisible
  private static final Integer CANDIDATE_FACTOR = 4;
  /**
   * Orçamento DECLARADO de verificações de LACUNA por passagem. Cada verificação é uma contagem
   * indexada por cronograma, e a passagem inteira precisa caber no limite de consultas da
   * plataforma. O orçamento NÃO descarta em silêncio: um candidato que não pôde ser verificado
   * continua no conjunto devido (fail-open) e é DESPACHADO, porque "não verificado" não é
   * "sem trabalho" — e a passagem autorizada que se segue verifica e repara de verdade.
   */
  public static final Integer MAX_HOLE_CHECKS = 50;
  /**
   * Teto do serviço de contextos autorizados (AXF-3): `listAuthorizedContexts()` lê com `LIMIT
   * 200`, limitação de infraestrutura DIFERIDA pela spec. Ela é declarada aqui só para
   * DISTINGUIR "não autorizado" de "não foi possível concluir" — este caminho não altera aquele
   * serviço.
   */
  public static final Integer AUTHORIZED_CONTEXT_LIMIT = 200;

  /** Sobrescreve o teto de leitura da fila (teste do critério efetivo de seleção). */
  @TestVisible
  private static Integer candidateLimitOverrideForTest;
  /** Sobrescreve o orçamento de verificações de lacuna (teste do limite declarado). */
  @TestVisible
  private static Integer holeCheckLimitOverrideForTest;
  /**
   * Teto EFETIVO de contextos autorizados nesta transação. O default é o teto real do serviço;
   * o teste o reduz para exercitar a conclusão inconclusiva sem criar 200 titulares.
   */
  @TestVisible
  private static Integer authorizedContextLimitForTest = AUTHORIZED_CONTEXT_LIMIT;

  /**
   * Rastro consultável de UMA passagem de despacho: decisões tomadas, candidatos lidos contra
   * despachados, verificações de lacuna consumidas e candidatos despachados sem verificação. É o
   * que a AC11 exige que exista: sem ele, o descarte deixa de ser observável.
   */
  public class DispatchTrace {
    public Integer candidatesRead = 0;
    public Integer dispatched = 0;
    public Integer holeChecksConsumed = 0;
    public Integer holeChecksSkippedByBudget = 0;
    public Integer unverifiedDispatched = 0;
    public Integer holesFound = 0;
    public Integer skippedByState = 0;
    public Integer rearmCandidatesRead = 0;
    public Integer rearmDispatched = 0;
    public List<Id> holeVerifiedScheduleIds = new List<Id>();

    public String describe() {
      return 'despacho candidatos=' +
        candidatesRead +
        ' despachados=' +
        dispatched +
        ' verificacoes=' +
        holeChecksConsumed +
        ' naoVerificadosDespachados=' +
        unverifiedDispatched +
        ' lacunas=' +
        holesFound +
        ' puladosPorEstado=' +
        skippedByState +
        ' realarmeLidos=' +
        rearmCandidatesRead +
        ' realarmeDespachados=' +
        rearmDispatched;
    }
  }

  /** Último rastro da passagem nesta transação. */
  private static DispatchTrace lastTrace = new DispatchTrace();

  public static DispatchTrace lastTrace() {
    return lastTrace;
  }

  /** Item de trabalho do job: o mínimo para despachar e autorizar. Nenhum dado financeiro. */
  public class WorkItem {
    public Id scheduleId;
    public Id holderId;
    public Integer coverageSequence;
  }

  /** Desfecho da leitura DIRIGIDA: o que o chamador provou poder ver, e o que foi recusado. */
  public class DirectedWork {
    public List<WorkItem> accepted = new List<WorkItem>();
    public List<Id> refused = new List<Id>();
  }

  /**
   * @description Cronogramas vencidos e habilitados, na ordem em que a fila deve ser drenada.
   *
   * A seleção é por COBERTURA ATRÁS DA JANELA, não por `NextAttemptAt` isolado: `NextAttemptAt`
   * é apenas um portão (o degrau de 30 minutos que não cabe no enqueue atrasado fica persistido
   * ali e a passagem seguinte o respeita). O que já está coberto até a borda da janela sai
   * naturalmente do conjunto devido, então a ordenação por cobertura ascendente avança para a
   * cauda sem marcador extra: cada passagem consome a cabeça, e a cabeça coberta sai.
   *
   * Portões de eligibilidade na PRÓPRIA consulta, não por descarte em memória: estado ACTIVE,
   * `GenerationEnabled`, orçamento de tentativas não esgotado, sem código de erro TERMINAL,
   * `NextAttemptAt` vencido ou ausente e definição vigente EXISTENTE com primeiro vencimento
   * preenchido. Sem isso, uma cabeça terminal ou sem definição consumiria posições do lote para
   * sempre e travaria a cauda da fila.
   *
   * A verificação de LACUNA é independente do critério de borda: um cronograma simultaneamente
   * atrasado e com lacuna abaixo do cursor também tem o intervalo verificado como contíguo.
   */
  public static List<WorkItem> selectDue(Integer requested) {
    AXF_CLS_ScheduleReplenishmentPolicy policy = AXF_CLS_ScheduleReplenishmentPolicy.current();
    Integer batchSize = requirePositive(
      requested,
      policy.dispatchBatchSize,
      'limite de despacho'
    );
    Integer candidateLimit = candidateLimitFor(batchSize);
    DateTime now = System.now();
    DispatchTrace trace = new DispatchTrace();
    lastTrace = trace;
    // O orçamento de tentativas é o tamanho da escada aprovada — declarado uma única vez.
    Integer retryBudget = ALT_CLS_ScheduleReplenishment.MAX_RETRY_COUNT;
    Set<String> terminalCodes = ALT_CLS_ScheduleReplenishment.terminalCodes();
    List<AXF_OBJ_FinancialSchedule__c> candidates = [
      SELECT
        Id,
        AXF_FSC_LKP_Account__c,
        AXF_FSC_NUM_CoverageSequence__c,
        AXF_FSC_NUM_TrackingStartSequence__c,
        AXF_FSC_NUM_HorizonMonths__c,
        AXF_FSC_NUM_RetryCount__c,
        AXF_FSC_TXT_LastErrorCode__c,
        AXF_FSC_LKP_ActiveDefinition__c
      FROM AXF_OBJ_FinancialSchedule__c
      WHERE
        AXF_FSC_PKL_State__c = :STATE_ACTIVE
        AND AXF_FSC_BOL_GenerationEnabled__c = TRUE
        AND AXF_FSC_LKP_Account__c != NULL
        AND AXF_FSC_LKP_ActiveDefinition__c != NULL
        AND AXF_FSC_LKP_ActiveDefinition__r.AXF_SDF_DAT_FirstDueDate__c != NULL
        AND AXF_FSC_NUM_RetryCount__c < :retryBudget
        AND (AXF_FSC_TXT_LastErrorCode__c = NULL
        OR AXF_FSC_TXT_LastErrorCode__c NOT IN :terminalCodes)
        AND (AXF_FSC_DT_NextAttemptAt__c = NULL
        OR AXF_FSC_DT_NextAttemptAt__c <= :now)
      WITH SYSTEM_MODE
      ORDER BY
        AXF_FSC_NUM_CoverageSequence__c ASC,
        AXF_FSC_NUM_ProjectionRevision__c ASC,
        Id ASC
      LIMIT :candidateLimit
    ];
    trace.candidatesRead = candidates.size();
    if (candidates.isEmpty()) {
      return new List<WorkItem>();
    }

    Map<Id, AXF_OBJ_ScheduleDefinition__c> definitions = definitionsOf(
      candidates
    );
    Date today = Date.today();
    Integer holeChecksLeft = holeCheckLimit();
    List<WorkItem> due = new List<WorkItem>();
    for (AXF_OBJ_FinancialSchedule__c candidate : candidates) {
      if (due.size() >= batchSize) {
        // O excedente fica no conjunto devido: nada é descartado em silêncio.
        break;
      }
      if (
        ALT_CLS_ScheduleReplenishment.isTerminal(
          candidate.AXF_FSC_TXT_LastErrorCode__c
        )
      ) {
        // Guarda de defesa: a consulta já exclui terminais.
        trace.skippedByState++;
        continue;
      }
      AXF_OBJ_ScheduleDefinition__c definition = definitions.get(
        candidate.AXF_FSC_LKP_ActiveDefinition__c
      );
      if (
        definition == null ||
        definition.AXF_SDF_DAT_FirstDueDate__c == null
      ) {
        // Guarda de defesa: a consulta já exige definição existente com primeiro vencimento.
        trace.skippedByState++;
        continue;
      }
      Integer horizon = (candidate.AXF_FSC_NUM_HorizonMonths__c == null)
        ? ALT_CLS_FinancialScheduleService.DEFAULT_HORIZON_MONTHS
        : candidate.AXF_FSC_NUM_HorizonMonths__c.intValue();
      Date windowEnd = ALT_CLS_ScheduleCalendar.monthEndShifted(
        today,
        Math.max(0, horizon - 1)
      );
      ALT_CLS_ScheduleReplenishment.DispatchInput dispatch = new ALT_CLS_ScheduleReplenishment.DispatchInput();
      dispatch.firstSequence = intOf(definition.AXF_SDF_NUM_FirstSequence__c);
      dispatch.firstDueDate = definition.AXF_SDF_DAT_FirstDueDate__c;
      dispatch.periodMonths = intOf(definition.AXF_SDF_NUM_PeriodMonths__c);
      dispatch.periodDays = intOf(definition.AXF_SDF_NUM_PeriodDays__c);
      dispatch.anchorDay = intOf(definition.AXF_SDF_NUM_AnchorDay__c);
      dispatch.lastCoveredSequence = lastCoveredSequence(definition);
      dispatch.trackingStartSequence = intOf(
        candidate.AXF_FSC_NUM_TrackingStartSequence__c
      );
      dispatch.coverageSequence = intOf(
        candidate.AXF_FSC_NUM_CoverageSequence__c
      );
      dispatch.windowEndDate = windowEnd;
      Boolean behindWindow = ALT_CLS_ScheduleReplenishment.isBehindWindow(
        dispatch
      );
      // As DUAS verificações são independentes: a borda da janela pode já não avançar e ainda
      // assim existir uma lacuna abaixo do cursor (uma ocorrência persistida apagada depois do
      // avanço do cursor deixa exatamente esse estado). Um cronograma atrasado E com lacuna tem o
      // intervalo verificado como contíguo do mesmo jeito.
      Boolean verified = false;
      Boolean hole = false;
      if (holeChecksLeft > 0) {
        holeChecksLeft--;
        verified = true;
        hole = ALT_CLS_ScheduleReplenishment.hasCoverageHole(
          persistedInRange(
            candidate.Id,
            dispatch.trackingStartSequence,
            dispatch.coverageSequence
          ),
          dispatch.coverageSequence,
          dispatch.trackingStartSequence
        );
        trace.holeChecksConsumed++;
        trace.holeVerifiedScheduleIds.add(candidate.Id);
        if (hole) {
          trace.holesFound++;
        }
      } else {
        trace.holeChecksSkippedByBudget++;
      }
      if (!behindWindow && verified && !hole) {
        continue;
      }
      if (!behindWindow && !verified) {
        // Não verificado NÃO é "sem trabalho": o candidato continua devido e é despachado. Um
        // candidato verificado e sem lacuna é o único que sai da fila.
        trace.unverifiedDispatched++;
      }
      WorkItem item = new WorkItem();
      item.scheduleId = candidate.Id;
      item.holderId = candidate.AXF_FSC_LKP_Account__c;
      item.coverageSequence = dispatch.coverageSequence;
      due.add(item);
      trace.dispatched++;
    }
    return due;
  }

  /**
   * @description Cronogramas com ORÇAMENTO ESGOTADO cuja janela de REALARME já venceu. Eles não
   * voltam ao despacho automático (`RetryCount` no orçamento os mantém fora de `selectDue`): o que
   * esta leitura entrega é a passagem de RECUPERAÇÃO, que tenta UMA vez de novo por janela. Sem
   * isso, quatro falhas transitórias desligariam a reposição daquele cronograma para sempre; com
   * um reset irrestrito, a falha permanente repetiria sem limite.
   *
   * Códigos TERMINAIS não aparecem aqui de propósito: eles ficaram com `NextAttemptAt` nulo porque
   * dependem de ação humana, e a retomada deles é a passagem DIRIGIDA (`directedWork`).
   */
  public static List<WorkItem> selectBlockedForRearm(
    DateTime asOf,
    Integer requested
  ) {
    DateTime moment = (asOf == null) ? System.now() : asOf;
    AXF_CLS_ScheduleReplenishmentPolicy policy = AXF_CLS_ScheduleReplenishmentPolicy.current();
    Integer batchSize = requirePositive(
      requested,
      policy.dispatchBatchSize,
      'limite de realarme'
    );
    Integer retryBudget = ALT_CLS_ScheduleReplenishment.MAX_RETRY_COUNT;
    List<AXF_OBJ_FinancialSchedule__c> rows = [
      SELECT Id, AXF_FSC_LKP_Account__c, AXF_FSC_NUM_CoverageSequence__c
      FROM AXF_OBJ_FinancialSchedule__c
      WHERE
        AXF_FSC_PKL_State__c = :STATE_ACTIVE
        AND AXF_FSC_BOL_GenerationEnabled__c = TRUE
        AND AXF_FSC_LKP_Account__c != NULL
        AND AXF_FSC_NUM_RetryCount__c >= :retryBudget
        AND AXF_FSC_DT_NextAttemptAt__c != NULL
        AND AXF_FSC_DT_NextAttemptAt__c <= :moment
      WITH SYSTEM_MODE
      ORDER BY AXF_FSC_DT_NextAttemptAt__c ASC, Id ASC
      LIMIT :batchSize
    ];
    lastTrace.rearmCandidatesRead = rows.size();
    List<WorkItem> items = new List<WorkItem>();
    for (AXF_OBJ_FinancialSchedule__c row : rows) {
      WorkItem item = new WorkItem();
      item.scheduleId = row.Id;
      item.holderId = row.AXF_FSC_LKP_Account__c;
      item.coverageSequence = intOf(row.AXF_FSC_NUM_CoverageSequence__c);
      items.add(item);
    }
    lastTrace.rearmDispatched = items.size();
    return items;
  }

  /**
   * @description Item de trabalho para cronogramas NOMEADOS, usado pela passagem de recuperação
   * DIRIGIDA. É a leitura privilegiada do caminho interno — por isso é PRIVADA e visível apenas ao
   * teste: nenhum consumidor externo alcança identidade, titular ou cursor por aqui.
   */
  @TestVisible
  private static List<WorkItem> workItems(Set<Id> scheduleIds) {
    List<WorkItem> items = new List<WorkItem>();
    if (scheduleIds == null || scheduleIds.isEmpty()) {
      return items;
    }
    for (AXF_OBJ_FinancialSchedule__c row : [
      SELECT Id, AXF_FSC_LKP_Account__c, AXF_FSC_NUM_CoverageSequence__c
      FROM AXF_OBJ_FinancialSchedule__c
      WHERE Id IN :scheduleIds AND AXF_FSC_LKP_Account__c != NULL
      WITH SYSTEM_MODE
    ]) {
      WorkItem item = new WorkItem();
      item.scheduleId = row.Id;
      item.holderId = row.AXF_FSC_LKP_Account__c;
      item.coverageSequence = intOf(row.AXF_FSC_NUM_CoverageSequence__c);
      items.add(item);
    }
    return items;
  }

  /**
   * @description Leitura DIRIGIDA, submetida à MESMA autoridade de titular do serviço: o chamador
   * só recebe trabalho dos cronogramas cujo titular ele enxerga. Um Id que o chamador não provou
   * poder ver é RECUSADO e relatado, nunca processado em silêncio — dirigir recuperação não pode
   * virar um caminho para queimar o estado acionável de um titular alheio.
   *
   * A autoridade vem de `AXF_CLS_AuthorizedContextService`, a mesma que o motor de projeção e a
   * porta de escrita usam. Quando a leitura de contextos alcança o teto diferido de 200 titulares,
   * a conclusão é "não foi possível provar" e a recusa é o desfecho seguro: o chamador repete
   * depois, e nenhum estado é gravado.
   */
  public static DirectedWork directedWork(Set<Id> scheduleIds) {
    DirectedWork work = new DirectedWork();
    if (scheduleIds == null || scheduleIds.isEmpty()) {
      return work;
    }
    Set<Id> authorized = authorizedHolderIds();
    Boolean truncated = authorized == null;
    for (WorkItem item : workItems(scheduleIds)) {
      if (!truncated && authorized.contains(item.holderId)) {
        work.accepted.add(item);
        continue;
      }
      work.refused.add(item.scheduleId);
    }
    // Um Id pedido que não existe (ou não tem titular) também é recusa relatada.
    Set<Id> known = new Set<Id>();
    for (WorkItem item : work.accepted) {
      known.add(item.scheduleId);
    }
    for (Id refused : work.refused) {
      known.add(refused);
    }
    for (Id requested : scheduleIds) {
      if (requested != null && !known.contains(requested)) {
        work.refused.add(requested);
      }
    }
    return work;
  }

  /**
   * @description Titulares que o principal que executa enxerga AGORA, ou nulo quando o teto
   * diferido de 200 contextos impede CONCLUIR a autorização.
   */
  private static Set<Id> authorizedHolderIds() {
    Set<Id> authorized = new Set<Id>();
    List<AXF_CLS_AuthorizedContextService.ContextView> contexts = AXF_CLS_AuthorizedContextService.listAuthorizedContexts();
    for (AXF_CLS_AuthorizedContextService.ContextView view : contexts) {
      if (view.accountId != null) {
        authorized.add(view.accountId);
      }
    }
    Integer contextLimit = (authorizedContextLimitForTest == null)
      ? AUTHORIZED_CONTEXT_LIMIT
      : authorizedContextLimitForTest;
    return (contexts.size() >= contextLimit) ? null : authorized;
  }

  /**
   * @description O principal que executa enxerga este titular? Nulo/indefinido — inclusive quando
   * o teto diferido de contextos impede concluir — devolve `false`, que é o desfecho seguro para
   * autorizar trabalho dirigido.
   */
  public static Boolean isHolderAuthorized(Id holderId) {
    if (holderId == null) {
      return false;
    }
    Set<Id> authorized = authorizedHolderIds();
    return authorized != null && authorized.contains(holderId);
  }

  /** @description Última sequência descrita pelo termo, ou nulo em recorrência indefinida. */
  public static Integer lastCoveredSequence(
    AXF_OBJ_ScheduleDefinition__c definition
  ) {
    if (
      definition.AXF_SDF_NUM_TotalInstallments__c == null ||
      definition.AXF_SDF_NUM_FirstSequence__c == null
    ) {
      return null;
    }
    return definition.AXF_SDF_NUM_FirstSequence__c.intValue() +
      definition.AXF_SDF_NUM_TotalInstallments__c.intValue() -
      1;
  }

  /**
   * @description Identidades VÁLIDAS persistidas dentro de `[TrackingStartSequence,
   * CoverageSequence]`. É a contagem que prova (ou descarta) uma lacuna abaixo do cursor, por
   * cronograma, sem ler os valores financeiros nem carregar as linhas.
   *
   * A definição de "válida" é a MESMA da projeção: a linha `CANCELLED` é cache derivado de uma
   * obrigação logicamente cancelada e a projeção a pula — contá-la aqui faria a contagem bater com
   * o esperado, o detector de lacuna nunca dispararia e o cronograma sairia da fila com uma
   * ocorrência ausente dentro do intervalo coberto.
   */
  public static Integer persistedInRange(
    Id scheduleId,
    Integer trackingStartSequence,
    Integer coverageSequence
  ) {
    if (scheduleId == null) {
      return 0;
    }
    Integer start = (trackingStartSequence == null ||
      trackingStartSequence < 1)
      ? 1
      : trackingStartSequence;
    Integer coverage = (coverageSequence == null) ? 0 : coverageSequence;
    if (coverage < start) {
      return 0;
    }
    return [
      SELECT COUNT()
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE
        AXF_FTX_LKP_Schedule__c = :scheduleId
        AND AXF_FTX_NUM_Sequence__c >= :start
        AND AXF_FTX_NUM_Sequence__c <= :coverage
        AND (AXF_FTX_PKL_ScheduleState__c = NULL
        OR AXF_FTX_PKL_ScheduleState__c != :STATE_CANCELLED)
      WITH SYSTEM_MODE
    ];
  }

  /** Teto de leitura da fila: o lote com folga declarada, nunca acima do teto absoluto. */
  private static Integer candidateLimitFor(Integer batchSize) {
    if (candidateLimitOverrideForTest != null) {
      return Math.max(1, candidateLimitOverrideForTest);
    }
    return Math.min(
      MAX_CANDIDATES,
      Math.max(batchSize, batchSize * CANDIDATE_FACTOR)
    );
  }

  /** Orçamento de verificações de lacuna desta passagem. */
  private static Integer holeCheckLimit() {
    Integer declared = (holeCheckLimitOverrideForTest == null)
      ? MAX_HOLE_CHECKS
      : holeCheckLimitOverrideForTest;
    return Math.max(0, declared);
  }

  private static Map<Id, AXF_OBJ_ScheduleDefinition__c> definitionsOf(
    List<AXF_OBJ_FinancialSchedule__c> candidates
  ) {
    Set<Id> definitionIds = new Set<Id>();
    for (AXF_OBJ_FinancialSchedule__c candidate : candidates) {
      if (candidate.AXF_FSC_LKP_ActiveDefinition__c != null) {
        definitionIds.add(candidate.AXF_FSC_LKP_ActiveDefinition__c);
      }
    }
    Map<Id, AXF_OBJ_ScheduleDefinition__c> definitions = new Map<Id, AXF_OBJ_ScheduleDefinition__c>();
    if (definitionIds.isEmpty()) {
      return definitions;
    }
    for (AXF_OBJ_ScheduleDefinition__c definition : [
      SELECT
        Id,
        AXF_SDF_NUM_FirstSequence__c,
        AXF_SDF_DAT_FirstDueDate__c,
        AXF_SDF_NUM_PeriodMonths__c,
        AXF_SDF_NUM_PeriodDays__c,
        AXF_SDF_NUM_AnchorDay__c,
        AXF_SDF_NUM_TotalInstallments__c
      FROM AXF_OBJ_ScheduleDefinition__c
      WHERE Id IN :definitionIds
      WITH SYSTEM_MODE
    ]) {
      definitions.put(definition.Id, definition);
    }
    return definitions;
  }

  private static Integer requirePositive(
    Integer requested,
    Integer fallback,
    String label
  ) {
    Integer value = (requested == null || requested < 1) ? fallback : requested;
    if (value == null || value < 1) {
      throw new AXF_CLS_ScheduleReplenishmentPolicy.PolicyException(
        'O ' + label + ' precisa ser um inteiro positivo.'
      );
    }
    return value;
  }

  private static Integer intOf(Decimal value) {
    return (value == null) ? null : Integer.valueOf(value);
  }
}
