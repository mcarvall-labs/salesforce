/**
 * AXF-103 fatia 2 — worker da reposição rolante: um cronograma por transação, com finalizador.
 *
 * Padrão do repositório (`AXF_CLS_SourceDeleteQueueable`): o finalizador é anexado ANTES do
 * trabalho. Se a transação abortar, o finalizador roda em transação SEPARADA e limitada para
 * gravar o metadado de falha higienizado (`RetryCount`, `NextAttemptAt`, `LastErrorCode`) e
 * encadear o restante do lote — o efeito financeiro parcial já foi revertido pelo rollback.
 *
 * A escada de recuo é 1, 5 e 30 minutos. Os degraus de 1 e 5 cabem no enqueue atrasado e são
 * reenfileirados COM o atraso do degrau; o degrau de 30 NÃO cabe (o teto da plataforma é 10
 * minutos), então ele fica persistido em `NextAttemptAt` e é retomado pela passagem de recuperação
 * do agendador — um timer inventado seria pior. A quarta falha consecutiva esgota o orçamento:
 * nada é reagendado na cadeia e o estado fica acionável, com o realarme limitado descrito em
 * `AXF_CLS_ScheduleReplenishmentRecovery`.
 *
 * Nada aqui gera por conta própria: toda geração passa por
 * `ALT_CLS_FinancialScheduleService.replenishSchedule`.
 *
 * Observabilidade (AC11): cada transação de worker deixa um rastro estruturado — rodadas
 * consumidas, itens re-enfileirados, replays, falhas e ABORTOS DE CADEIA com motivo higienizado.
 * `continueChain` chama `Policy.current()`, e uma política removida no meio da cadeia lançava
 * `PolicyException` para fora de `execute`/finalizador sem tratamento nem estado registrado; agora
 * o aborto é classificado, registrado e o worker termina sem derrubar a transação.
 */
public with sharing class AXF_CLS_ScheduleReplenishmentQueueable implements Queueable {
  public static final String ABORT_POLICY_UNAVAILABLE = 'POLICY_UNAVAILABLE';
  public static final String ABORT_SELECTION_FAILED = 'SELECTION_FAILED';

  private final List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem> pending;
  private final Integer round;
  private final Boolean recovery;

  /** Degrau de encadeamento observado pelo teste: o que foi pedido e o que foi aplicado. */
  public class ChainStep {
    public Id scheduleId;
    public Integer delayMinutes;
    public Integer round;
    public Boolean recovery;

    public ChainStep(
      Id scheduleId,
      Integer delayMinutes,
      Integer round,
      Boolean recovery
    ) {
      this.scheduleId = scheduleId;
      this.delayMinutes = delayMinutes;
      this.round = round;
      this.recovery = recovery;
    }
  }

  /** Rastro consultável de UMA transação de worker. */
  public class ChainTrace {
    public Integer itemsProcessed = 0;
    public Integer itemsRequeued = 0;
    public Integer replays = 0;
    public Integer failures = 0;
    public Integer roundsConsumed = 0;
    public List<ChainStep> chained = new List<ChainStep>();
    public List<String> aborts = new List<String>();

    public String describe() {
      return 'worker processados=' +
        itemsProcessed +
        ' reEnfileirados=' +
        itemsRequeued +
        ' replays=' +
        replays +
        ' falhas=' +
        failures +
        ' rodadas=' +
        roundsConsumed +
        ' encadeados=' +
        chained.size() +
        ' abortos=' +
        String.join(aborts, ',');
    }
  }

  /**
   * Quando não nulo, o encadeamento é REGISTRADO em vez de enfileirado (observabilidade de
   * teste). O registro preserva o atraso PEDIDO, e não apenas a intenção: sem ele, o recuo de 1 e
   * de 5 minutos não teria como ser observado.
   */
  @TestVisible
  private static List<ChainStep> chainLog;
  /** Força o enfileiramento atrasado a ser RECUSADO, para exercitar o fallback imediato. */
  @TestVisible
  private static Integer forcedDelayedRejectionsForTest = 0;
  /** Último desfecho por cronograma observado pelo teste. */
  @TestVisible
  private static ALT_CLS_FinancialScheduleService.ReplenishmentResult lastResultForTest;

  private static ChainTrace lastTrace = new ChainTrace();

  public static ChainTrace lastTrace() {
    return lastTrace;
  }

  public AXF_CLS_ScheduleReplenishmentQueueable(
    List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem> work,
    Integer round
  ) {
    this(work, round, false);
  }

  public AXF_CLS_ScheduleReplenishmentQueueable(
    List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem> work,
    Integer round,
    Boolean recovery
  ) {
    this.pending = (work == null)
      ? new List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem>()
      : work;
    this.round = (round == null) ? 0 : round;
    this.recovery = recovery;
  }

  public void execute(QueueableContext context) {
    if (pending.isEmpty()) {
      continueChain(round);
      emitTrace();
      return;
    }
    AXF_CLS_ScheduleReplenishmentSelector.WorkItem item = pending.remove(0);
    // O finalizador recebe uma CÓPIA do restante no momento do anexo: se a transação abortar
    // depois, o que foi acrescentado à lista viva (trabalho que ainda falta do mesmo cronograma)
    // não vira uma segunda entrada do mesmo cronograma.
    System.attachFinalizer(
      new ReplenishmentFinalizer(
        item,
        new List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem>(pending),
        round,
        recovery
      )
    );

    ALT_CLS_FinancialScheduleService.ReplenishmentRequest request = new ALT_CLS_FinancialScheduleService.ReplenishmentRequest();
    request.scheduleId = item.scheduleId;
    request.holderId = item.holderId;
    request.recovery = recovery;
    ALT_CLS_FinancialScheduleService.ReplenishmentResult result = ALT_CLS_FinancialScheduleService.replenishSchedule(
      request
    );
    lastResultForTest = result;
    lastTrace.itemsProcessed++;
    if (result.replay == true) {
      lastTrace.replays++;
    }

    if (result.outcome == ALT_CLS_FinancialScheduleService.OUTCOME_FAILED) {
      lastTrace.failures++;
      // A transação precisa abortar para que a reversão seja integral e o metadado de falha seja
      // gravado pelo finalizador, em transação separada.
      ReplenishmentFailureException failure = new ReplenishmentFailureException(
        result.message
      );
      failure.errorCode = ALT_CLS_ScheduleReplenishment.sanitizeErrorCode(
        result.errorCode
      );
      emitTrace();
      throw failure;
    }

    if (result.moreWork == true) {
      // O cronograma ainda tem ocorrência elegível além do limite desta transação: volta para o
      // FIM da fila, para que os outros cronogramas também progridam. `moreWork` é recalculado
      // pela produção SOB O LOCK, então uma passagem que não criou nada (replay, colisão, no-op)
      // não entra aqui e não gasta uma rodada da cadeia.
      requeueAtTheEnd(pending, item);
      lastTrace.itemsRequeued++;
    }
    if (!pending.isEmpty()) {
      // Os itens que restam vieram da MESMA solicitação: um lote dirigido continua dirigido.
      chain(pending, 0, round, recovery);
      emitTrace();
      return;
    }
    continueChain(round + 1);
    emitTrace();
  }

  /**
   * @description Drena o conjunto devido: enquanto houver trabalho elegível e o teto de rodadas
   * não tiver sido alcançado, a cadeia re-seleciona. O que exceder o teto NÃO é descartado em
   * silêncio: como a seleção é por cobertura atrás da janela, o cronograma ainda não coberto
   * continua no conjunto devido e é retomado pela passagem seguinte do agendamento — mensal ou de
   * recuperação, esta última diária.
   *
   * A re-seleção é sempre uma passagem NORMAL: um lote dirigido pelo operador não pode estender o
   * "ignorar o portão terminal" a cronogramas que ninguém pediu para retomar.
   *
   * Uma política removida no meio da cadeia é ABORTO REGISTRADO, não exceção que escapa: sem
   * isso, a cadeia morreria sem deixar estado nem motivo.
   */
  private static void continueChain(Integer nextRound) {
    AXF_CLS_ScheduleReplenishmentPolicy policy;
    try {
      policy = AXF_CLS_ScheduleReplenishmentPolicy.current();
    } catch (AXF_CLS_ScheduleReplenishmentPolicy.PolicyException unavailable) {
      lastTrace.aborts.add(ABORT_POLICY_UNAVAILABLE);
      System.debug(
        LoggingLevel.ERROR,
        'AXF103 reposicao: cadeia interrompida, politica indisponivel. ' +
        lastTrace.describe()
      );
      return;
    }
    if (nextRound > policy.maxContinuationRounds) {
      lastTrace.aborts.add('ROUND_LIMIT');
      return;
    }
    lastTrace.roundsConsumed++;
    List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem> more;
    try {
      more = AXF_CLS_ScheduleReplenishmentSelector.selectDue(
        policy.dispatchBatchSize
      );
    } catch (Exception selectionFailure) {
      lastTrace.aborts.add(ABORT_SELECTION_FAILED);
      System.debug(
        LoggingLevel.ERROR,
        'AXF103 reposicao: cadeia interrompida, selecao falhou. ' +
        lastTrace.describe()
      );
      return;
    }
    if (more.isEmpty()) {
      return;
    }
    chain(more, 0, nextRound, false);
  }

  /**
   * @description Encadeia a continuação, APLICANDO o atraso do degrau.
   *
   * Em TESTE o encadeamento é REGISTRADO em vez de enfileirado — precedente do repositório
   * (`AXF_CLS_PluggySyncQueueable`). Um job que enfileira um filho de dentro do `Test.stopTest()`
   * falha aqui com `System.AsyncException: Maximum stack depth has been reached`, verificado por
   * sonda: o teste passaria a medir a profundidade de encadeamento da plataforma em vez do
   * comportamento da cadeia. O registro preserva o ATRASO pedido e a POSIÇÃO do item.
   *
   * A sonda do fallback (`forcedDelayedRejectionsForTest`) é a exceção: ela PRECISA do caminho real
   * de enfileiramento para que o enfileiramento atrasado seja recusado e o imediato assuma.
   */
  private static void chain(
    List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem> work,
    Integer delayMinutes,
    Integer round,
    Boolean recovery
  ) {
    if (work == null || work.isEmpty()) {
      return;
    }
    Integer appliedDelay = (delayMinutes != null &&
      delayMinutes > 0)
      ? delayMinutes
      : null;
    Boolean delayedProbe =
      appliedDelay != null &&
      Test.isRunningTest() &&
      forcedDelayedRejectionsForTest != null &&
      forcedDelayedRejectionsForTest > 0;
    if (Test.isRunningTest() && !delayedProbe) {
      record(appliedDelay, round, recovery, work, false);
      return;
    }
    AXF_CLS_ScheduleReplenishmentQueueable next = new AXF_CLS_ScheduleReplenishmentQueueable(
      work,
      round,
      recovery
    );
    if (appliedDelay == null) {
      System.enqueueJob(next);
      record(null, round, recovery, work, false);
      return;
    }
    if (delayedProbe) {
      forcedDelayedRejectionsForTest--;
    }
    try {
      if (delayedProbe) {
        throw new DelayedEnqueueRejectedException(
          'Enfileiramento atrasado recusado (sonda de teste).'
        );
      }
      System.enqueueJob(next, appliedDelay);
      record(appliedDelay, round, recovery, work, false);
    } catch (Exception delayedRejected) {
      // Orgs que recusam encadeamento atrasado continuam com o encadeamento imediato: o
      // `NextAttemptAt` persistido preserva o recuo do degrau.
      System.enqueueJob(next);
      record(appliedDelay, round, recovery, work, true);
    }
  }

  /**
   * @description Posição declarada do trabalho inacabado: o FIM da fila, para que os outros
   * cronogramas progridam antes da nova tentativa. É uma função pura justamente para que a posição
   * seja ASSERTÁVEL — uma inserção na frente mudaria a ordem e não seria pega por nenhum efeito
   * persistido.
   */
  @TestVisible
  private static List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem> requeueAtTheEnd(
    List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem> pending,
    AXF_CLS_ScheduleReplenishmentSelector.WorkItem item
  ) {
    if (pending == null || item == null) {
      return pending;
    }
    pending.add(item);
    return pending;
  }

  private static void record(
    Integer appliedDelay,
    Integer round,
    Boolean recovery,
    List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem> work,
    Boolean fallback
  ) {
    for (AXF_CLS_ScheduleReplenishmentSelector.WorkItem item : work) {
      lastTrace.chained.add(
        new ChainStep(item.scheduleId, appliedDelay, round, recovery)
      );
    }
    if (chainLog != null) {
      for (AXF_CLS_ScheduleReplenishmentSelector.WorkItem item : work) {
        chainLog.add(
          new ChainStep(item.scheduleId, appliedDelay, round, recovery)
        );
      }
    }
    if (fallback) {
      lastTrace.aborts.add('DELAYED_ENQUEUE_FALLBACK');
    }
  }

  private static void emitTrace() {
    System.debug(
      LoggingLevel.INFO,
      'AXF103 reposicao worker. ' + lastTrace.describe()
    );
  }

  /** @description Enfileira uma passagem de recuperação DIRIGIDA para cronogramas nomeados. */
  public static Id recover(
    List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem> work
  ) {
    if (work == null || work.isEmpty()) {
      return null;
    }
    // Defesa em profundidade: mesmo que um chamador monte os itens à mão, o lote dirigido só
    // segue para titulares cuja autoridade o principal pode COMPROVAR.
    List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem> accepted = new List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem>();
    for (AXF_CLS_ScheduleReplenishmentSelector.WorkItem item : work) {
      if (
        item != null &&
        AXF_CLS_ScheduleReplenishmentSelector.isHolderAuthorized(item.holderId)
      ) {
        accepted.add(item);
      }
    }
    if (accepted.isEmpty()) {
      return null;
    }
    // `recovery = true` é o que faz a passagem dirigida IGNORAR o portão de despacho: é
    // exatamente por isso que ela existe, e é o que a torna capaz de retomar um cronograma com o
    // orçamento esgotado. A revalidação de estado, autoridade e permissão continua valendo na
    // transação de geração.
    return System.enqueueJob(
      new AXF_CLS_ScheduleReplenishmentQueueable(accepted, 0, true)
    );
  }

  /** @description Falha recuperável da passagem, com o código higienizado já classificado. */
  public class ReplenishmentFailureException extends Exception {
    public String errorCode;
  }

  /** Falha sintética do fallback de enfileiramento atrasado (sonda de teste). */
  private class DelayedEnqueueRejectedException extends Exception {
  }

  /**
   * Transação separada: preserva o metadado de falha e reagenda o trabalho restante.
   */
  @TestVisible
  private class ReplenishmentFinalizer implements Finalizer {
    private final AXF_CLS_ScheduleReplenishmentSelector.WorkItem failed;
    private final List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem> remaining;
    private final Integer round;
    private final Boolean recovery;

    @TestVisible
    private ReplenishmentFinalizer(
      AXF_CLS_ScheduleReplenishmentSelector.WorkItem activeWork,
      List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem> rest,
      Integer round,
      Boolean recovery
    ) {
      this.failed = activeWork;
      this.remaining = rest;
      this.round = round;
      this.recovery = recovery;
    }

    public void execute(FinalizerContext context) {
      if (context.getResult() == ParentJobResult.SUCCESS) {
        // Caminho de sucesso já encadeou o restante na própria transação.
        return;
      }
      String errorCode = codeOf(context);
      lastTrace.failures++;
      ALT_CLS_FinancialScheduleService.FailureRecord failure = ALT_CLS_FinancialScheduleService.recordReplenishmentFailure(
        failed.scheduleId,
        errorCode,
        System.now()
      );
      if (failure != null && failure.statePersisted != true) {
        // O desfecho terminal existe, mas o estado acionável não pôde ser gravado: o operador
        // precisa ver isso no rastro, senão o cronograma parece parado sem motivo.
        lastTrace.aborts.add('STATE_NOT_PERSISTED');
      }
      List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem> next = new List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem>(
        remaining
      );
      Integer delay = null;
      if (failure != null && failure.terminal != true) {
        delay = failure.delayMinutes;
        if (delay != null) {
          // O degrau cabe no enqueue atrasado: o cronograma volta para o FIM da fila, para que o
          // restante do lote continue antes da nova tentativa.
          next.add(failed);
          lastTrace.itemsRequeued++;
        }
      }
      if (!next.isEmpty()) {
        chain(next, delay, round, recovery);
      } else {
        // Nada a encadear (degrau de 30 minutos ou orçamento esgotado): o trabalho restante do
        // conjunto devido é retomado pela seleção, e o cronograma falho fica com o horário
        // persistido em `NextAttemptAt`.
        continueChain(round + 1);
      }
      emitTrace();
    }

    /** Código higienizado do desfecho: nunca stack trace, mensagem de DML nem nome de campo. */
    private String codeOf(FinalizerContext context) {
      Exception failure = context.getException();
      if (failure instanceof ReplenishmentFailureException) {
        return ALT_CLS_ScheduleReplenishment.sanitizeErrorCode(
          ((ReplenishmentFailureException) failure).errorCode
        );
      }
      if (failure instanceof System.DmlException) {
        return ALT_CLS_ScheduleReplenishment.ERROR_DML;
      }
      if (failure instanceof System.QueryException) {
        return ALT_CLS_ScheduleReplenishment.ERROR_QUERY;
      }
      if (failure instanceof ALT_CLS_ScheduleCalendar.CalendarException) {
        return ALT_CLS_ScheduleReplenishment.ERROR_CALENDAR;
      }
      if (failure instanceof System.MathException) {
        return ALT_CLS_ScheduleReplenishment.ERROR_FORMULA;
      }
      return ALT_CLS_ScheduleReplenishment.ERROR_UNEXPECTED;
    }
  }
}
