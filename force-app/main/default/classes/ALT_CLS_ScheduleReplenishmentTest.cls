/**
 * @description AXF-103 fatia 2 — regra pura da reposição rolante: matriz de I/O sem DML.
 *
 * O critério de "o que falta" entra como a leitura do motor único (`OccurrenceLine`), a mesma que
 * a leitura autorizada usa. Aqui se verifica o recorte da janela, o limite da transação, o avanço
 * do cursor de cobertura, o critério de DESPACHO do agendador e a política de retry — inclusive
 * que a classe não executa nenhuma consulta nem escrita.
 */
@IsTest(isParallel=false)
private class ALT_CLS_ScheduleReplenishmentTest {
  private static ALT_CLS_ScheduleProjection.OccurrenceLine line(
    Integer sequence,
    Date nominalDueDate,
    Boolean persisted
  ) {
    ALT_CLS_ScheduleProjection.OccurrenceLine value = new ALT_CLS_ScheduleProjection.OccurrenceLine();
    value.sequence = sequence;
    value.nominalDueDate = nominalDueDate;
    value.persisted = persisted;
    value.amount = 100.00;
    return value;
  }

  private static Date monthly(Date origin, Integer offset) {
    return ALT_CLS_ScheduleCalendar.shift(origin, offset, origin.day());
  }

  private static ALT_CLS_ScheduleReplenishment.PlanInput input(
    List<ALT_CLS_ScheduleProjection.OccurrenceLine> lines,
    Date windowEndDate,
    Integer trackingStart,
    Integer coverage
  ) {
    ALT_CLS_ScheduleReplenishment.PlanInput value = new ALT_CLS_ScheduleReplenishment.PlanInput();
    value.lines = lines;
    value.windowEndDate = windowEndDate;
    value.trackingStartSequence = trackingStart;
    value.coverageSequence = coverage;
    value.coverageComplete = true;
    return value;
  }

  @IsTest
  static void plansOnlyTheMissingEligibleOccurrencesInsideTheWindow() {
    Date origin = Date.newInstance(2027, 1, 10);
    Date windowEnd = ALT_CLS_ScheduleCalendar.monthEnd(
      Date.newInstance(2027, 3, 1)
    );
    List<ALT_CLS_ScheduleProjection.OccurrenceLine> lines = new List<ALT_CLS_ScheduleProjection.OccurrenceLine>{
      line(1, monthly(origin, 0), true),
      line(2, monthly(origin, 1), true),
      line(3, monthly(origin, 2), false),
      line(4, monthly(origin, 3), false),
      line(5, monthly(origin, 4), false),
      line(6, monthly(origin, 5), false)
    };

    ALT_CLS_ScheduleReplenishment.Plan plan = ALT_CLS_ScheduleReplenishment.plan(
      input(lines, windowEnd, 1, 2)
    );

    Assert.areEqual(
      new List<Integer>{ 3 },
      plan.sequences,
      'Só a ocorrência elegível ausente dentro da janela'
    );
    Assert.areEqual(1, plan.missingCount);
    Assert.areEqual(3, plan.eligibleCount);
    Assert.areEqual(
      3,
      plan.coverageSequence,
      'Cobertura avança para o contíguo'
    );
    Assert.areEqual(2, plan.previousCoverageSequence);
    Assert.areEqual(false, plan.moreWork);
    Assert.areEqual(false, plan.termReached, 'Ainda há virtual além da janela');
    Assert.areEqual(3, plan.beyondWindowCount);
    Assert.areEqual(false, plan.evaluationCut);
  }

  @IsTest
  static void aGapBelowTheCursorIsMaterializedAndTheCursorNeverSkipsIt() {
    Date origin = Date.newInstance(2027, 1, 10);
    Date windowEnd = ALT_CLS_ScheduleCalendar.monthEnd(
      Date.newInstance(2027, 5, 1)
    );
    List<ALT_CLS_ScheduleProjection.OccurrenceLine> lines = new List<ALT_CLS_ScheduleProjection.OccurrenceLine>{
      line(1, monthly(origin, 0), true),
      line(2, monthly(origin, 1), true),
      line(3, monthly(origin, 2), false),
      line(4, monthly(origin, 3), true),
      line(5, monthly(origin, 4), true)
    };

    ALT_CLS_ScheduleReplenishment.Plan plan = ALT_CLS_ScheduleReplenishment.plan(
      input(lines, windowEnd, 1, 5)
    );

    Assert.areEqual(
      new List<Integer>{ 3 },
      plan.sequences,
      'A lacuna abaixo do cursor é materializada, e o que está acima dela não é duplicado'
    );
    Assert.areEqual(
      5,
      plan.coverageSequence,
      'Preenchida a lacuna, a cobertura alcança o prefixo contíguo completo'
    );
    Assert.areEqual(
      5,
      plan.previousCoverageSequence,
      'O cursor persistido foi lido como ponto de partida'
    );
  }

  @IsTest
  static void aGapOutsideTheWindowDoesNotRegressThePersistedCoverage() {
    Date origin = Date.newInstance(2027, 1, 10);
    Date windowEnd = ALT_CLS_ScheduleCalendar.monthEnd(
      Date.newInstance(2027, 2, 1)
    );
    List<ALT_CLS_ScheduleProjection.OccurrenceLine> lines = new List<ALT_CLS_ScheduleProjection.OccurrenceLine>{
      line(1, monthly(origin, 0), true),
      line(2, monthly(origin, 1), true),
      line(3, monthly(origin, 2), false),
      line(4, monthly(origin, 3), true),
      line(5, monthly(origin, 4), true)
    };

    ALT_CLS_ScheduleReplenishment.Plan plan = ALT_CLS_ScheduleReplenishment.plan(
      input(lines, windowEnd, 1, 5)
    );

    Assert.areEqual(
      new List<Integer>(),
      plan.sequences,
      'A lacuna está fora da janela: não é trabalho desta passagem'
    );
    Assert.areEqual(
      2,
      plan.coverageSequence,
      'O prefixo contíguo contabilizado para na lacuna'
    );
    Assert.isTrue(
      plan.coverageSequence < plan.previousCoverageSequence,
      'É a produção que impede a regressão do cursor; a regra reporta o valor honesto'
    );
  }

  @IsTest
  static void theTransactionLimitIsEnforcedAndTheRemainderIsReported() {
    Date origin = Date.newInstance(2027, 1, 10);
    Date windowEnd = ALT_CLS_ScheduleCalendar.monthEnd(monthly(origin, 70));
    List<ALT_CLS_ScheduleProjection.OccurrenceLine> lines = new List<ALT_CLS_ScheduleProjection.OccurrenceLine>();
    for (Integer sequence = 1; sequence <= 60; sequence++) {
      lines.add(line(sequence, monthly(origin, sequence - 1), false));
    }

    ALT_CLS_ScheduleReplenishment.Plan plan = ALT_CLS_ScheduleReplenishment.plan(
      input(lines, windowEnd, 1, 0)
    );

    Assert.areEqual(
      ALT_CLS_ScheduleReplenishment.MAX_OCCURRENCES_PER_TRANSACTION,
      plan.sequences.size(),
      'Nunca acima do limite de engenharia por transação'
    );
    Assert.areEqual(1, plan.firstPlannedSequence);
    Assert.areEqual(50, plan.lastPlannedSequence);
    Assert.areEqual(
      true,
      plan.moreWork,
      'O excedente é relatado, não descartado'
    );
    Assert.areEqual(50, plan.coverageSequence);
    Assert.areEqual(false, plan.termReached);
  }

  @IsTest
  static void aSmallerLimitIsHonouredAndAWiderOneIsClamped() {
    Assert.areEqual(10, ALT_CLS_ScheduleReplenishment.clampLimit(10));
    Assert.areEqual(
      ALT_CLS_ScheduleReplenishment.MAX_OCCURRENCES_PER_TRANSACTION,
      ALT_CLS_ScheduleReplenishment.clampLimit(500)
    );
    Assert.areEqual(
      ALT_CLS_ScheduleReplenishment.MAX_OCCURRENCES_PER_TRANSACTION,
      ALT_CLS_ScheduleReplenishment.clampLimit(null)
    );
    Assert.areEqual(
      ALT_CLS_ScheduleReplenishment.MAX_OCCURRENCES_PER_TRANSACTION,
      ALT_CLS_ScheduleReplenishment.clampLimit(0)
    );
  }

  @IsTest
  static void theTermIsOnlyCompleteWhenNothingIsMissingAndNothingIsVirtualBeyond() {
    Date origin = Date.newInstance(2027, 1, 10);
    Date windowEnd = ALT_CLS_ScheduleCalendar.monthEnd(
      Date.newInstance(2027, 6, 1)
    );
    List<ALT_CLS_ScheduleProjection.OccurrenceLine> lines = new List<ALT_CLS_ScheduleProjection.OccurrenceLine>{
      line(4, monthly(origin, 0), true),
      line(5, monthly(origin, 1), false)
    };

    ALT_CLS_ScheduleReplenishment.Plan plan = ALT_CLS_ScheduleReplenishment.plan(
      input(lines, windowEnd, 4, 4)
    );
    Assert.areEqual(false, plan.termReached);

    ALT_CLS_ScheduleReplenishment.PlanInput noLines = input(
      new List<ALT_CLS_ScheduleProjection.OccurrenceLine>(),
      windowEnd,
      4,
      5
    );
    Assert.areEqual(
      true,
      ALT_CLS_ScheduleReplenishment.plan(noLines).termReached,
      'Tudo materializado, nada virtual além da janela: o termo terminou'
    );
  }

  @IsTest
  static void pretrackingHistoryIsNeverGeneratedNorCounted() {
    Date origin = Date.newInstance(2026, 1, 10);
    Date windowEnd = ALT_CLS_ScheduleCalendar.monthEnd(
      Date.newInstance(2027, 3, 1)
    );
    List<ALT_CLS_ScheduleProjection.OccurrenceLine> lines = new List<ALT_CLS_ScheduleProjection.OccurrenceLine>{
      line(1, monthly(origin, 0), false),
      line(2, monthly(origin, 12), false),
      line(3, monthly(origin, 13), true),
      line(4, monthly(origin, 14), false)
    };

    ALT_CLS_ScheduleReplenishment.Plan plan = ALT_CLS_ScheduleReplenishment.plan(
      input(lines, windowEnd, 3, 3)
    );

    Assert.areEqual(
      new List<Integer>{ 4 },
      plan.sequences,
      'Nada abaixo de TrackingStartSequence é gerado'
    );
    Assert.areEqual(
      4,
      plan.coverageSequence,
      'O histórico pré-rastreamento não participa da cobertura'
    );
  }

  @IsTest
  static void unboundedRecurrenceNeverReportsAFinishedTerm() {
    Date origin = Date.newInstance(2027, 1, 10);
    Date windowEnd = ALT_CLS_ScheduleCalendar.monthEnd(
      Date.newInstance(2027, 12, 1)
    );
    List<ALT_CLS_ScheduleProjection.OccurrenceLine> lines = new List<ALT_CLS_ScheduleProjection.OccurrenceLine>{
      line(1, monthly(origin, 0), true)
    };
    ALT_CLS_ScheduleReplenishment.PlanInput unbounded = input(
      lines,
      windowEnd,
      1,
      1
    );
    unbounded.unbounded = true;
    unbounded.coverageComplete = false;

    ALT_CLS_ScheduleReplenishment.Plan plan = ALT_CLS_ScheduleReplenishment.plan(
      unbounded
    );

    Assert.areEqual(false, plan.termReached);
    Assert.areEqual(
      false,
      plan.evaluationCut,
      'Recorrência indefinida não é truncamento por teto de avaliação'
    );
  }

  @IsTest
  static void evaluationCutIsPartialCoverageAndNotARetryableFailure() {
    Date origin = Date.newInstance(2027, 1, 10);
    Date windowEnd = ALT_CLS_ScheduleCalendar.monthEnd(
      Date.newInstance(2028, 12, 1)
    );
    List<ALT_CLS_ScheduleProjection.OccurrenceLine> lines = new List<ALT_CLS_ScheduleProjection.OccurrenceLine>{
      line(1, monthly(origin, 0), true),
      line(2, monthly(origin, 1), true),
      line(3, monthly(origin, 2), false)
    };
    ALT_CLS_ScheduleReplenishment.PlanInput cut = input(lines, windowEnd, 1, 2);
    cut.coverageComplete = false;

    ALT_CLS_ScheduleReplenishment.Plan plan = ALT_CLS_ScheduleReplenishment.plan(
      cut
    );

    Assert.areEqual(true, plan.evaluationCut);
    Assert.areEqual(
      new List<Integer>{ 3 },
      plan.sequences,
      'Materializa o que estava ao alcance em vez de falhar por inteiro'
    );
    Assert.areEqual(
      false,
      plan.termReached,
      'Cobertura parcial nunca é apresentada como termo concluído'
    );
  }

  @IsTest
  static void planRefusesToRunWithoutTheWindowEdge() {
    Boolean rejected = false;
    try {
      ALT_CLS_ScheduleReplenishment.plan(
        input(new List<ALT_CLS_ScheduleProjection.OccurrenceLine>(), null, 1, 0)
      );
    } catch (ALT_CLS_ScheduleReplenishment.ReplenishmentException expected) {
      rejected = true;
    }
    Assert.isTrue(rejected, 'Sem a borda da janela o recorte é recusado');
  }

  @IsTest
  static void coverageIsTheContiguousPrefixOnly() {
    Assert.areEqual(
      3,
      ALT_CLS_ScheduleReplenishment.coverageAfter(
        1,
        new Set<Integer>{ 1, 2, 3, 7, 9 }
      )
    );
    Assert.areEqual(
      0,
      ALT_CLS_ScheduleReplenishment.coverageAfter(1, new Set<Integer>{ 4, 5 })
    );
    Assert.areEqual(
      84,
      ALT_CLS_ScheduleReplenishment.coverageAfter(85, new Set<Integer>{ 84, 3 })
    );
    Assert.areEqual(
      87,
      ALT_CLS_ScheduleReplenishment.coverageAfter(
        85,
        new Set<Integer>{ 85, 86, 87 }
      ),
      'O prefixo contíguo a partir do rastreamento avança até a última contabilizada'
    );
  }

  @IsTest
  static void dispatchCriterionFollowsTheDayPeriod() {
    // AXF-155: semanal a partir de 01/01/2027 — a 5ª ocorrência vence em 29/01, a 6ª em 05/02.
    ALT_CLS_ScheduleReplenishment.DispatchInput input = new ALT_CLS_ScheduleReplenishment.DispatchInput();
    input.firstSequence = 1;
    input.firstDueDate = Date.newInstance(2027, 1, 1);
    input.periodDays = 7;
    input.trackingStartSequence = 1;
    input.coverageSequence = 4;
    input.windowEndDate = Date.newInstance(2027, 1, 31);
    Assert.isTrue(
      ALT_CLS_ScheduleReplenishment.isBehindWindow(input),
      'A próxima semana ainda cabe na janela'
    );
    input.coverageSequence = 5;
    Assert.isFalse(
      ALT_CLS_ScheduleReplenishment.isBehindWindow(input),
      'A próxima semana cai depois do fim da janela'
    );
    input.periodMonths = 1;
    Assert.isFalse(
      ALT_CLS_ScheduleReplenishment.isBehindWindow(input),
      'Periodicidade dupla é recusada pelo calendário e não despacha'
    );
  }

  @IsTest
  static void dispatchCriterionComparesTheNextEligibleSequenceWithTheWindowEdge() {
    Date origin = Date.newInstance(2027, 1, 10);
    Date windowEnd = ALT_CLS_ScheduleCalendar.monthEnd(
      Date.newInstance(2027, 3, 1)
    );

    ALT_CLS_ScheduleReplenishment.DispatchInput due = dispatch(
      origin,
      windowEnd,
      12,
      1,
      0
    );
    Assert.areEqual(true, ALT_CLS_ScheduleReplenishment.isBehindWindow(due));

    ALT_CLS_ScheduleReplenishment.DispatchInput caughtUp = dispatch(
      origin,
      windowEnd,
      12,
      1,
      3
    );
    Assert.areEqual(
      false,
      ALT_CLS_ScheduleReplenishment.isBehindWindow(caughtUp),
      'Coberto até a borda da janela sai do conjunto devido'
    );

    ALT_CLS_ScheduleReplenishment.DispatchInput atTerm = dispatch(
      origin,
      windowEnd,
      2,
      1,
      2
    );
    Assert.areEqual(
      false,
      ALT_CLS_ScheduleReplenishment.isBehindWindow(atTerm),
      'Fim do termo: nada é criado além dele'
    );

    ALT_CLS_ScheduleReplenishment.DispatchInput belowTracking = dispatch(
      origin,
      ALT_CLS_ScheduleCalendar.monthEnd(Date.newInstance(2027, 2, 1)),
      12,
      5,
      0
    );
    Assert.areEqual(
      false,
      ALT_CLS_ScheduleReplenishment.isBehindWindow(belowTracking),
      'A varredura começa em TrackingStartSequence: as parcelas 1 e 2 estão na janela, mas histórico pré-rastreamento não é trabalho'
    );
  }

  @IsTest
  static void dispatchCriterionClampsTheAnchorAtMonthEnd() {
    ALT_CLS_ScheduleReplenishment.DispatchInput input = new ALT_CLS_ScheduleReplenishment.DispatchInput();
    input.firstSequence = 1;
    input.firstDueDate = Date.newInstance(2027, 1, 31);
    input.periodMonths = 1;
    input.anchorDay = 31;
    input.trackingStartSequence = 1;
    input.coverageSequence = 0;
    input.lastCoveredSequence = 4;
    input.windowEndDate = Date.newInstance(2027, 2, 28);

    Assert.areEqual(
      true,
      ALT_CLS_ScheduleReplenishment.isBehindWindow(input),
      'A âncora no dia 31 cai no último dia de fevereiro'
    );

    input.coverageSequence = 1;
    Assert.areEqual(
      true,
      ALT_CLS_ScheduleReplenishment.isBehindWindow(input),
      'A parcela de fevereiro cai no último dia do mês curto e ainda está na borda'
    );

    input.coverageSequence = 2;
    Assert.areEqual(
      false,
      ALT_CLS_ScheduleReplenishment.isBehindWindow(input),
      'A parcela de março volta ao dia 31 e fica fora da borda'
    );
  }

  @IsTest
  static void theBackoffLadderIsWalkedAndTheBudgetEndsVisible() {
    DateTime failedAt = DateTime.newInstance(2027, 5, 10, 12, 0, 0);

    ALT_CLS_ScheduleReplenishment.RetryDecision first = ALT_CLS_ScheduleReplenishment.nextAttempt(
      0,
      failedAt
    );
    Assert.areEqual(1, first.retryCount);
    Assert.areEqual(1, first.delayMinutes, 'Primeiro degrau: 1 minuto');
    Assert.areEqual(
      failedAt.addMinutes(1),
      first.nextAttemptAt,
      'Há próximo horário de tentativa persistido'
    );
    Assert.areEqual(false, first.exhausted);

    ALT_CLS_ScheduleReplenishment.RetryDecision second = ALT_CLS_ScheduleReplenishment.nextAttempt(
      1,
      failedAt
    );
    Assert.areEqual(2, second.retryCount);
    Assert.areEqual(5, second.delayMinutes, 'Segundo degrau: 5 minutos');
    Assert.areEqual(failedAt.addMinutes(5), second.nextAttemptAt);

    ALT_CLS_ScheduleReplenishment.RetryDecision third = ALT_CLS_ScheduleReplenishment.nextAttempt(
      2,
      failedAt
    );
    Assert.areEqual(3, third.retryCount);
    Assert.areEqual(
      null,
      third.delayMinutes,
      'O degrau de 30 minutos não cabe no enqueue atrasado'
    );
    Assert.areEqual(
      failedAt.addMinutes(30),
      third.nextAttemptAt,
      'O degrau de 30 minutos fica persistido para a passagem seguinte'
    );
    Assert.areEqual(false, third.exhausted);

    ALT_CLS_ScheduleReplenishment.RetryDecision fourth = ALT_CLS_ScheduleReplenishment.nextAttempt(
      3,
      failedAt
    );
    Assert.areEqual(true, fourth.exhausted, 'Orçamento esgotado e visível');
    Assert.areEqual(3, fourth.retryCount);
    Assert.areEqual(null, fourth.nextAttemptAt, 'Nada mais é agendado');
    Assert.areEqual(null, fourth.delayMinutes);

    ALT_CLS_ScheduleReplenishment.RetryDecision beyond = ALT_CLS_ScheduleReplenishment.nextAttempt(
      9,
      failedAt
    );
    Assert.areEqual(true, beyond.exhausted);
    Assert.areEqual(
      3,
      beyond.retryCount,
      'O contador nunca passa do orçamento'
    );
  }

  @IsTest
  static void theLadderIsClosedAndOnlyTheApprovedOneIsAccepted() {
    Assert.areEqual(1, ALT_CLS_ScheduleReplenishment.backoffMinutes(1));
    Assert.areEqual(5, ALT_CLS_ScheduleReplenishment.backoffMinutes(2));
    Assert.areEqual(30, ALT_CLS_ScheduleReplenishment.backoffMinutes(3));
    for (Integer step : new List<Integer>{ 0, 4, -1, null }) {
      Boolean rejected = false;
      try {
        ALT_CLS_ScheduleReplenishment.backoffMinutes(step);
      } catch (ALT_CLS_ScheduleReplenishment.ReplenishmentException expected) {
        rejected = true;
      }
      Assert.isTrue(rejected, 'Degrau fora da escada é recusado: ' + step);
    }
    Assert.areEqual(
      true,
      ALT_CLS_ScheduleReplenishment.isApprovedLadder(
        new List<Integer>{ 1, 5, 30 }
      )
    );
    for (
      List<Integer> candidate : new List<List<Integer>>{
        new List<Integer>{ 1, 5 },
        new List<Integer>{ 1, 5, 30, 60 },
        new List<Integer>{ 2, 5, 30 },
        new List<Integer>(),
        null
      }
    ) {
      Assert.areEqual(
        false,
        ALT_CLS_ScheduleReplenishment.isApprovedLadder(candidate),
        'Escada diferente da aprovada é recusada'
      );
    }
    Assert.areEqual(
      3,
      ALT_CLS_ScheduleReplenishment.MAX_RETRY_COUNT,
      'O orçamento é o tamanho da escada aprovada'
    );
  }

  @IsTest
  static void reconciledStateClearsEverything() {
    ALT_CLS_ScheduleReplenishment.RetryDecision clean = ALT_CLS_ScheduleReplenishment.reconciled();
    Assert.areEqual(0, clean.retryCount);
    Assert.areEqual(null, clean.nextAttemptAt);
    Assert.areEqual(null, clean.delayMinutes);
    Assert.areEqual(false, clean.exhausted);
  }

  @IsTest
  static void theErrorCatalogIsClosedAndSanitized() {
    Assert.areEqual(
      'DML_FAILED',
      ALT_CLS_ScheduleReplenishment.sanitizeErrorCode('dml_failed')
    );
    Assert.areEqual(
      'UNEXPECTED',
      ALT_CLS_ScheduleReplenishment.sanitizeErrorCode(
        'Update failed. First exception on row 0 with id 001xx; first error: FIELD_CUSTOM_VALIDATION'
      ),
      'Nenhuma mensagem de exceção chega ao campo persistido'
    );
    Assert.areEqual(
      'UNEXPECTED',
      ALT_CLS_ScheduleReplenishment.sanitizeErrorCode(
        'AXF_FSC_TXT_LastErrorCode__c'
      )
    );
    Assert.areEqual(
      'UNEXPECTED',
      ALT_CLS_ScheduleReplenishment.sanitizeErrorCode(null)
    );
    Assert.areEqual(
      'UNEXPECTED',
      ALT_CLS_ScheduleReplenishment.sanitizeErrorCode('   ')
    );
    Assert.areEqual(
      'PRINCIPAL_WITHOUT_VISIBILITY',
      ALT_CLS_ScheduleReplenishment.sanitizeErrorCode(
        'principal_without_visibility'
      )
    );
  }

  @IsTest
  static void terminalStatesBlockDispatchWithoutConsumingBudget() {
    Assert.areEqual(
      true,
      ALT_CLS_ScheduleReplenishment.isTerminal(
        ALT_CLS_ScheduleReplenishment.ERROR_EXHAUSTED
      )
    );
    Assert.areEqual(
      true,
      ALT_CLS_ScheduleReplenishment.isTerminal(
        ALT_CLS_ScheduleReplenishment.ERROR_PRINCIPAL_WITHOUT_VISIBILITY
      )
    );
    Assert.areEqual(
      true,
      ALT_CLS_ScheduleReplenishment.isTerminal(
        ALT_CLS_ScheduleReplenishment.ERROR_PERMISSION_DENIED
      )
    );
    Assert.areEqual(
      true,
      ALT_CLS_ScheduleReplenishment.isTerminal(
        ALT_CLS_ScheduleReplenishment.ERROR_IDENTITY
      )
    );
    Assert.areEqual(
      false,
      ALT_CLS_ScheduleReplenishment.isTerminal(
        ALT_CLS_ScheduleReplenishment.ERROR_DML
      ),
      'Falha de DML é recuperável'
    );
    Assert.areEqual(
      false,
      ALT_CLS_ScheduleReplenishment.isTerminal(null),
      'Estado limpo não é terminal'
    );
    Assert.areEqual(
      true,
      ALT_CLS_ScheduleReplenishment.isRetryable(
        ALT_CLS_ScheduleReplenishment.ERROR_PROJECTION_STALE
      )
    );

    Assert.areEqual(
      false,
      ALT_CLS_ScheduleReplenishment.blocksDispatch(null, 0, 3)
    );
    Assert.areEqual(
      false,
      ALT_CLS_ScheduleReplenishment.blocksDispatch('DML_FAILED', 2, 3)
    );
    Assert.areEqual(
      true,
      ALT_CLS_ScheduleReplenishment.blocksDispatch('DML_FAILED', 3, 3),
      'Orçamento esgotado tira o cronograma do conjunto devido'
    );
    Assert.areEqual(
      true,
      ALT_CLS_ScheduleReplenishment.blocksDispatch(
        ALT_CLS_ScheduleReplenishment.ERROR_PERMISSION_DENIED,
        0,
        3
      ),
      'Código terminal bloqueia o despacho SEM consumir orçamento'
    );
    Assert.areEqual(
      true,
      ALT_CLS_ScheduleReplenishment.blocksDispatch('DML_FAILED', 3, null),
      'Sem orçamento declarado vale o da escada aprovada'
    );
  }

  @IsTest
  static void thePureRuleExecutesNoQueryAndNoDml() {
    Date origin = Date.newInstance(2027, 1, 10);
    List<ALT_CLS_ScheduleProjection.OccurrenceLine> lines = new List<ALT_CLS_ScheduleProjection.OccurrenceLine>{
      line(1, monthly(origin, 0), false),
      line(2, monthly(origin, 1), true)
    };
    Integer queries = Limits.getQueries();
    Integer dml = Limits.getDmlStatements();

    ALT_CLS_ScheduleReplenishment.plan(
      input(
        lines,
        ALT_CLS_ScheduleCalendar.monthEnd(Date.newInstance(2027, 6, 1)),
        1,
        0
      )
    );
    ALT_CLS_ScheduleReplenishment.coverageAfter(1, new Set<Integer>{ 1, 2 });
    ALT_CLS_ScheduleReplenishment.nextAttempt(
      0,
      DateTime.newInstance(2027, 5, 10, 12, 0, 0)
    );
    ALT_CLS_ScheduleReplenishment.sanitizeErrorCode('DML_FAILED');
    ALT_CLS_ScheduleReplenishment.isBehindWindow(
      dispatch(
        origin,
        ALT_CLS_ScheduleCalendar.monthEnd(Date.newInstance(2027, 6, 1)),
        12,
        1,
        0
      )
    );

    Assert.areEqual(queries, Limits.getQueries(), 'A regra não executa SOQL');
    Assert.areEqual(dml, Limits.getDmlStatements(), 'A regra não executa DML');
  }

  @IsTest
  static void aLineWithoutNominalDueDateIsAPlanDefectAndNeverOutsideTheWindow() {
    Date origin = Date.newInstance(2027, 1, 10);
    Date windowEnd = ALT_CLS_ScheduleCalendar.monthEnd(
      Date.newInstance(2027, 3, 1)
    );
    ALT_CLS_ScheduleProjection.OccurrenceLine broken = line(2, null, false);
    Boolean rejected = false;
    try {
      ALT_CLS_ScheduleReplenishment.plan(
        input(
          new List<ALT_CLS_ScheduleProjection.OccurrenceLine>{
            line(1, monthly(origin, 0), true),
            broken
          },
          windowEnd,
          1,
          1
        )
      );
    } catch (ALT_CLS_ScheduleReplenishment.ReplenishmentException expected) {
      rejected = true;
      Assert.isTrue(
        expected.getMessage().contains('sem vencimento nominal'),
        'A recusa nomeia o defeito de plano: ' + expected.getMessage()
      );
    }
    Assert.isTrue(
      rejected,
      'Ausência de vencimento nominal é defeito de PLANO, nunca "fora da janela"'
    );

    // Controle: a MESMA linha com vencimento acima da borda é apenas trabalho fora da janela —
    // prova que o desfecho acima não vem de uma comparação de data.
    ALT_CLS_ScheduleReplenishment.Plan outside = ALT_CLS_ScheduleReplenishment.plan(
      input(
        new List<ALT_CLS_ScheduleProjection.OccurrenceLine>{
          line(1, monthly(origin, 0), true),
          line(2, monthly(origin, 9), false)
        },
        windowEnd,
        1,
        1
      )
    );
    Assert.areEqual(1, outside.beyondWindowCount);
    Assert.areEqual(0, outside.missingCount);
  }

  @IsTest
  static void theOperatorFacingErrorCodesAreClosedSanitizedAndDocumented() {
    for (
      String code : new List<String>{
        ALT_CLS_ScheduleReplenishment.ERROR_PROJECTION_AMBIGUOUS,
        ALT_CLS_ScheduleReplenishment.ERROR_PROJECTION_UNSUPPORTED,
        ALT_CLS_ScheduleReplenishment.ERROR_PROJECTION_INVALID,
        ALT_CLS_ScheduleReplenishment.ERROR_PROJECTION_MISSING,
        ALT_CLS_ScheduleReplenishment.ERROR_PLAN_INCOMPLETE,
        ALT_CLS_ScheduleReplenishment.ERROR_SCALE_LIMIT,
        ALT_CLS_ScheduleReplenishment.ERROR_AUTHORITY_TRUNCATED
      }
    ) {
      Assert.areEqual(
        code,
        ALT_CLS_ScheduleReplenishment.sanitizeErrorCode(code.toLowerCase()),
        'O código ' + code + ' está no catálogo fechado e é higienizado'
      );
    }
    Assert.areEqual(
      'UNEXPECTED',
      ALT_CLS_ScheduleReplenishment.sanitizeErrorCode(
        'PROJECTION_BLOCKED_BY_SOMETHING_ELSE'
      ),
      'O que não está no catálogo vira UNEXPECTED'
    );
  }

  @IsTest
  static void theTruncatedAuthorityScopeIsNotTerminalWhileRealBlocksAre() {
    Assert.areEqual(
      false,
      ALT_CLS_ScheduleReplenishment.isTerminal(
        ALT_CLS_ScheduleReplenishment.ERROR_AUTHORITY_TRUNCATED
      ),
      'O teto diferido de 200 titulares NÃO é "principal sem visibilidade"'
    );
    Assert.areEqual(
      true,
      ALT_CLS_ScheduleReplenishment.isRetryable(
        ALT_CLS_ScheduleReplenishment.ERROR_AUTHORITY_TRUNCATED
      )
    );
    Assert.areEqual(
      false,
      ALT_CLS_ScheduleReplenishment.blocksDispatch(
        ALT_CLS_ScheduleReplenishment.ERROR_AUTHORITY_TRUNCATED,
        0,
        3
      ),
      'A leitura inconclusiva não bloqueia o despacho nem grava estado permanente'
    );
    for (
      String code : new List<String>{
        ALT_CLS_ScheduleReplenishment.ERROR_PROJECTION_AMBIGUOUS,
        ALT_CLS_ScheduleReplenishment.ERROR_PROJECTION_UNSUPPORTED,
        ALT_CLS_ScheduleReplenishment.ERROR_PROJECTION_INVALID,
        ALT_CLS_ScheduleReplenishment.ERROR_PROJECTION_MISSING,
        ALT_CLS_ScheduleReplenishment.ERROR_PLAN_INCOMPLETE,
        ALT_CLS_ScheduleReplenishment.ERROR_SCALE_LIMIT
      }
    ) {
      Assert.areEqual(
        true,
        ALT_CLS_ScheduleReplenishment.isTerminal(code),
        code + ' é permanente e acionável'
      );
      Assert.areEqual(
        true,
        ALT_CLS_ScheduleReplenishment.blocksDispatch(code, 0, 3),
        code + ' tira o cronograma do despacho automático'
      );
    }
  }

  @IsTest
  static void theRearmWindowIsBoundedAndDerivedFromTheFailureInstant() {
    DateTime failedAt = DateTime.newInstance(2027, 5, 10, 12, 0, 0);
    Assert.areEqual(
      failedAt.addHours(24),
      ALT_CLS_ScheduleReplenishment.rearmAt(failedAt, 24),
      'A janela do realarme é declarada, e não um reset imediato'
    );
    Assert.areEqual(
      failedAt.addHours(ALT_CLS_ScheduleReplenishment.DEFAULT_REARM_HOURS),
      ALT_CLS_ScheduleReplenishment.rearmAt(failedAt, null),
      'Sem janela declarada vale a padrão declarada'
    );
    Assert.areEqual(
      failedAt.addHours(ALT_CLS_ScheduleReplenishment.DEFAULT_REARM_HOURS),
      ALT_CLS_ScheduleReplenishment.rearmAt(failedAt, 0)
    );
    Boolean rejected = false;
    try {
      ALT_CLS_ScheduleReplenishment.rearmAt(null, 24);
    } catch (ALT_CLS_ScheduleReplenishment.ReplenishmentException expected) {
      rejected = true;
    }
    Assert.isTrue(rejected, 'O realarme exige o instante da falha');
  }

  @IsTest
  static void theDeclaredEngineeringLimitsAreEnforced() {
    Assert.areEqual(
      true,
      ALT_CLS_ScheduleReplenishment.isChainBudgetRespected(25, 20),
      'A política aprovada (25 x 20) cabe no teto declarado da cadeia'
    );
    Assert.areEqual(
      false,
      ALT_CLS_ScheduleReplenishment.isChainBudgetRespected(26, 20),
      'Um lote maior prometeria mais cronogramas do que o teto'
    );
    Assert.areEqual(
      false,
      ALT_CLS_ScheduleReplenishment.isChainBudgetRespected(25, 21)
    );
    Assert.areEqual(
      false,
      ALT_CLS_ScheduleReplenishment.isChainBudgetRespected(0, 20)
    );
    Assert.areEqual(
      false,
      ALT_CLS_ScheduleReplenishment.isChainBudgetRespected(25, null)
    );
    Assert.isTrue(
      ALT_CLS_ScheduleReplenishment.MAX_SCHEDULES_PER_CHAIN >=
      ALT_CLS_ScheduleReplenishment.MAX_OCCURRENCES_PER_TRANSACTION,
      'O teto da cadeia não pode ser menor que o de uma transação'
    );
    Assert.areEqual(
      true,
      ALT_CLS_ScheduleReplenishment.isTrackedIdentitiesWithinLimit(
        ALT_CLS_ScheduleReplenishment.MAX_TRACKED_IDENTITIES_PER_SCHEDULE
      )
    );
    Assert.areEqual(
      false,
      ALT_CLS_ScheduleReplenishment.isTrackedIdentitiesWithinLimit(
        ALT_CLS_ScheduleReplenishment.MAX_TRACKED_IDENTITIES_PER_SCHEDULE + 1
      )
    );
    Assert.areEqual(
      false,
      ALT_CLS_ScheduleReplenishment.isTrackedIdentitiesWithinLimit(null)
    );
  }

  private static ALT_CLS_ScheduleReplenishment.DispatchInput dispatch(
    Date firstDueDate,
    Date windowEndDate,
    Integer lastCoveredSequence,
    Integer trackingStartSequence,
    Integer coverageSequence
  ) {
    ALT_CLS_ScheduleReplenishment.DispatchInput input = new ALT_CLS_ScheduleReplenishment.DispatchInput();
    input.firstSequence = 1;
    input.firstDueDate = firstDueDate;
    input.periodMonths = 1;
    input.anchorDay = firstDueDate.day();
    input.lastCoveredSequence = lastCoveredSequence;
    input.trackingStartSequence = trackingStartSequence;
    input.coverageSequence = coverageSequence;
    input.windowEndDate = windowEndDate;
    return input;
  }
}
