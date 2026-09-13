/** @description AXF-103 — motor único de projeção: disjunção persistida/virtual, compromisso restante, sobreposição zero e estados explícitos. */
@IsTest(isParallel=false)
private class ALT_CLS_ScheduleProjectionTest {
  private static Id businessRecordType() {
    return Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
      .getRecordTypeInfosByDeveloperName()
      .get('AXF_Business')
      .getRecordTypeId();
  }

  private static Account holder(String name) {
    Account value = new Account(
      Name = name,
      RecordTypeId = businessRecordType()
    );
    insert value;
    return value;
  }

  private static ALT_CLS_FinancialScheduleService.CreateInput request(
    Id accountId,
    String method,
    Integer totalInstallments,
    Integer trackingStart,
    Date trackingDue,
    String legacyKey
  ) {
    ALT_CLS_FinancialScheduleService.CreateInput value = new ALT_CLS_FinancialScheduleService.CreateInput();
    value.accountId = accountId;
    value.direction = 'DEBIT';
    value.currencyIsoCode = 'BRL';
    value.method = method;
    value.totalInstallments = totalInstallments;
    value.firstSequence = 1;
    value.trackingStartSequence = trackingStart;
    value.trackingDueDate = trackingDue;
    value.periodMonths = 1;
    value.principal = 360000;
    value.periodRate = 0.01;
    value.referenceAmount = 500.00;
    value.legacyGroupKey = legacyKey;
    return value;
  }

  private static ALT_CLS_FinancialScheduleService.CreateResult create(
    Id accountId,
    String method,
    Integer totalInstallments,
    Integer trackingStart,
    Date trackingDue,
    String legacyKey
  ) {
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      accountId
    };
    ALT_CLS_FinancialScheduleService.CreateResult result = ALT_CLS_FinancialScheduleService.createSchedule(
      request(
        accountId,
        method,
        totalInstallments,
        trackingStart,
        trackingDue,
        legacyKey
      )
    );
    Assert.areEqual('CREATED', result.outcome, result.message);
    return result;
  }

  private static ALT_CLS_ScheduleProjection.ProjectionResult read(
    Id scheduleId
  ) {
    return read(scheduleId, Date.today(), null);
  }

  private static ALT_CLS_ScheduleProjection.ProjectionResult read(
    Id scheduleId,
    Date asOfDate,
    Integer throughSequence
  ) {
    ALT_CLS_ScheduleProjection.ProjectionInput input = new ALT_CLS_ScheduleProjection.ProjectionInput();
    input.scheduleId = scheduleId;
    input.asOfDate = asOfDate;
    input.throughSequence = throughSequence;
    return ALT_CLS_FinancialScheduleService.readProjection(input);
  }

  /** Último dia do mês corrente mais onze. */
  private static Date windowEnd() {
    Date shifted = Date.today().addMonths(11);
    return Date.newInstance(
      shifted.year(),
      shifted.month(),
      Date.daysInMonth(shifted.year(), shifted.month())
    );
  }

  /** Quantas sequências da faixa caem dentro da janela do mês corrente mais onze. */
  private static Integer expectedWindowCount(
    Integer firstSequence,
    Integer lastSequence,
    Date trackingDue
  ) {
    Integer count = 0;
    for (
      Integer sequence = firstSequence; sequence <= lastSequence; sequence++
    ) {
      if (trackingDue.addMonths(sequence - firstSequence) > windowEnd()) {
        break;
      }
      count++;
    }
    return count;
  }

  @IsTest
  static void fullTermTotalSumsPersistedAndVirtualExactlyOnce() {
    Account holder = holder('AXF103 projeção 360');
    Date trackingDue = Date.today().addMonths(1);
    ALT_CLS_FinancialScheduleService.CreateResult created = create(
      holder.Id,
      'INSTALLMENT',
      360,
      85,
      trackingDue,
      'proj-360'
    );

    ALT_CLS_ScheduleProjection.ProjectionResult result = read(
      created.scheduleId
    );

    Assert.areEqual('OK', result.outcome, result.message);
    Assert.areEqual(
      276,
      result.evaluatedCount,
      'Todas as sequências rastreadas (85..360) são cobertas uma única vez'
    );
    Integer persisted = expectedWindowCount(85, 360, trackingDue);
    Assert.areEqual(persisted, result.persistedCount);
    Assert.areEqual(276 - persisted, result.virtualCount);
    Assert.areEqual(
      276,
      result.overdueCount + result.futureCount,
      'Vencidas e futuras são disjuntas e cobrem toda a faixa'
    );
    Assert.areEqual(
      (result.overdueTotal + result.futureTotal).setScale(2),
      result.totalRemaining,
      'O total é a soma das vencidas com as futuras'
    );
    Assert.isTrue(
      result.coverageComplete,
      'Um prazo finito cobre todas as sequências rastreadas'
    );
    Assert.isFalse(result.unbounded);
    Assert.isTrue(
      result.estimated,
      'Há componente não confirmado, então o total é rotulado estimado'
    );
    Assert.isTrue(
      result.fullyEstimated,
      'Sem nenhum componente confirmado o total é integralmente estimado'
    );
    Assert.isFalse(
      result.complete,
      'Um total integralmente estimado nunca chega como completo a quem só lê `complete`'
    );
    Assert.areEqual(
      0.00,
      result.confirmedTotal,
      'Nada confirmado dentro da faixa avaliada'
    );
    Assert.areEqual(
      result.totalRemaining,
      result.estimatedTotal,
      'O total é integralmente estimado'
    );
    Assert.areEqual(12, result.horizonMonths);
    Assert.areEqual(windowEnd(), result.horizonEndDate);

    // A soma equivale exatamente à fórmula aprovada para a mesma faixa: nada foi contado duas
    // vezes e nenhuma sequência ficou de fora.
    ALT_CLS_AmortizationSchedule.ScheduleInput formula = new ALT_CLS_AmortizationSchedule.ScheduleInput();
    formula.modality = 'INSTALLMENT';
    formula.principal = 360000;
    formula.installments = 360;
    formula.firstDueDate = trackingDue;
    ALT_CLS_AmortizationSchedule.ScheduleResult generated = ALT_CLS_AmortizationSchedule.generate(
      formula
    );
    Decimal expected = 0;
    for (Integer sequence = 85; sequence <= 360; sequence++) {
      expected += generated.occurrences[sequence - 1].payment;
    }
    Assert.areEqual(
      expected.setScale(2),
      result.totalRemaining,
      'O compromisso restante é a soma canônica das ocorrências rastreadas'
    );

    // Total EXPLÍCITO do horizonte solicitado: as ocorrências persistidas são exatamente as que
    // vencem dentro do mês corrente mais onze, e o horizonte é exposto como campo próprio.
    Decimal horizonExpected = 0;
    for (Integer index = 0; index < persisted; index++) {
      horizonExpected += generated.occurrences[84 + index].payment;
    }
    Assert.areEqual(persisted, result.horizonCount);
    Assert.areEqual(
      horizonExpected.setScale(2),
      result.horizonTotal,
      'O total do horizonte é explícito e não depende de inferência do consumidor'
    );

    Set<String> identities = new Set<String>();
    Integer previous = 84;
    for (ALT_CLS_ScheduleProjection.OccurrenceLine line : result.lines) {
      Assert.isTrue(
        identities.add(line.occurrenceKey),
        'Identidade de ocorrência repetida: ' + line.occurrenceKey
      );
      Assert.areEqual(64, line.occurrenceKey.length());
      Assert.areEqual(
        previous + 1,
        line.sequence,
        'Faixa contígua sem lacunas'
      );
      previous = line.sequence;
      if (!line.persisted) {
        Assert.isTrue(
          line.estimated,
          'Componente virtual é uma estimativa declarada'
        );
      }
    }
    Assert.areEqual(360, previous);
  }

  @IsTest
  static void gapBelowCoverageAppearsAsVirtualAndIsNeverDuplicated() {
    Account holder = holder('AXF103 lacuna');
    ALT_CLS_FinancialScheduleService.CreateResult created = create(
      holder.Id,
      'INSTALLMENT',
      24,
      1,
      Date.today(),
      'proj-gap'
    );
    ALT_CLS_ScheduleProjection.ProjectionResult before = read(
      created.scheduleId
    );
    Assert.areEqual(24, before.evaluatedCount);
    Assert.isTrue(before.persistedCount > 0, before.message);

    AXF_OBJ_FinancialTransaction__c removed = [
      SELECT Id, AXF_FTX_NUM_CurrentBasis__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE
        AXF_FTX_LKP_Schedule__c = :created.scheduleId
        AND AXF_FTX_NUM_Sequence__c = 3
      LIMIT 1
    ];
    Decimal removedAmount = removed.AXF_FTX_NUM_CurrentBasis__c;
    delete removed;

    ALT_CLS_ScheduleProjection.ProjectionResult after = read(
      created.scheduleId
    );

    Assert.areEqual(
      before.evaluatedCount,
      after.evaluatedCount,
      'A lacuna continua sendo uma obrigação conhecida'
    );
    Assert.areEqual(before.persistedCount - 1, after.persistedCount);
    Assert.areEqual(before.virtualCount + 1, after.virtualCount);
    Assert.areEqual(
      before.totalRemaining,
      after.totalRemaining,
      'A ocorrência ausente é projetada como virtual, contada uma única vez'
    );

    String expectedKey = ALT_CLS_ScheduleProjection.occurrenceKey(
      after.scheduleKey,
      3
    );
    Boolean found = false;
    for (ALT_CLS_ScheduleProjection.OccurrenceLine line : after.lines) {
      if (line.sequence != 3) {
        continue;
      }
      found = true;
      Assert.isFalse(line.persisted);
      Assert.areEqual(expectedKey, line.occurrenceKey);
      Assert.areEqual(removedAmount, line.amount);
    }
    Assert.isTrue(found, 'A sequência ausente aparece na projeção');
  }

  @IsTest
  static void staleRevisionDriftWithholdsTheTotal() {
    Account holder = holder('AXF103 obsoleto');
    ALT_CLS_FinancialScheduleService.CreateResult created = create(
      holder.Id,
      'INSTALLMENT',
      24,
      1,
      Date.today(),
      'proj-stale'
    );
    AXF_OBJ_FinancialSchedule__c root = [
      SELECT
        Id,
        AXF_FSC_NUM_ProjectionRevision__c,
        AXF_FSC_NUM_FinancialVersion__c,
        AXF_FSC_DAT_TerminationDate__c
      FROM AXF_OBJ_FinancialSchedule__c
      WHERE Id = :created.scheduleId
    ];
    AXF_OBJ_FinancialSchedule__c drifted = root.clone(
      false,
      true,
      false,
      false
    );
    drifted.AXF_FSC_NUM_ProjectionRevision__c =
      root.AXF_FSC_NUM_ProjectionRevision__c + 1;
    // A fronteira de encerramento acompanha a releitura: só a revisão é que divergiu.
    drifted.AXF_FSC_DAT_TerminationDate__c = root.AXF_FSC_DAT_TerminationDate__c;
    ALT_CLS_ScheduleProjection.recheckOverride = drifted;

    ALT_CLS_ScheduleProjection.ProjectionResult result = read(
      created.scheduleId
    );

    Assert.areEqual('STALE', result.outcome, result.message);
    Assert.isNull(result.totalRemaining);
    Assert.isNull(result.overdueTotal);
    Assert.isNull(result.futureTotal);
    Assert.isFalse(result.complete);
    Assert.isTrue(result.lines.isEmpty());
    Assert.areEqual(
      root.AXF_FSC_NUM_ProjectionRevision__c.longValue(),
      result.capturedProjectionRevision
    );
    Assert.areEqual(
      drifted.AXF_FSC_NUM_ProjectionRevision__c.longValue(),
      result.recheckedProjectionRevision
    );
  }

  @IsTest
  static void conflictingConfirmationsAtTheSameEconomicSequenceBlockTheTotal() {
    Account holder = holder('AXF103 ambíguo');
    ALT_CLS_FinancialScheduleService.CreateResult created = create(
      holder.Id,
      'ESTIMATED',
      12,
      1,
      Date.today(),
      'proj-amb'
    );
    insert new AXF_OBJ_ScheduleReference__c(
      AXF_SRF_EXI_ReferenceKey__c = 'amb-conflicting-confirmation',
      AXF_SRF_LKP_Schedule__c = created.scheduleId,
      AXF_SRF_NUM_EconomicSequence__c = 1,
      AXF_SRF_NUM_EffectiveSequence__c = 1,
      AXF_SRF_NUM_RecurringAmount__c = 999.00,
      AXF_SRF_PKL_Kind__c = 'MANUAL'
    );

    ALT_CLS_ScheduleProjection.ProjectionResult result = read(
      created.scheduleId
    );

    Assert.areEqual('AMBIGUOUS', result.outcome, result.message);
    Assert.isNull(result.totalRemaining);
    Assert.isTrue(result.lines.isEmpty());
  }

  @IsTest
  static void terminationCancelsEligibleFutureOccurrencesAndKeepsProtectedOnes() {
    Account holder = holder('AXF103 encerrado');
    ALT_CLS_FinancialScheduleService.CreateResult created = create(
      holder.Id,
      'INSTALLMENT',
      24,
      1,
      Date.today(),
      'proj-terminate'
    );
    AXF_OBJ_FinancialTransaction__c protectedRow = [
      SELECT Id, AXF_FTX_NUM_CurrentBasis__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE
        AXF_FTX_LKP_Schedule__c = :created.scheduleId
        AND AXF_FTX_NUM_Sequence__c = 5
      LIMIT 1
    ];
    protectedRow.AXF_FTX_PKL_Status__c = 'CONFIRMED';
    protectedRow.AXF_FTX_BOL_BasisFrozen__c = true;
    update protectedRow;

    // Encerramento efetivo é um comando versionado da fatia seguinte: uma edição direta não
    // pode cancelar obrigações elegíveis sem recibo, sem revisão e deixando o cache em OPEN.
    Assert.isFalse(
      Database.update(
          new AXF_OBJ_FinancialSchedule__c(
            Id = created.scheduleId,
            AXF_FSC_DAT_TerminationDate__c = Date.today()
          ),
          false
        )
        .isSuccess(),
      'A data de encerramento é mantida pelo serviço autorizado'
    );
    Assert.isNull(
      [
        SELECT AXF_FSC_DAT_TerminationDate__c
        FROM AXF_OBJ_FinancialSchedule__c
        WHERE Id = :created.scheduleId
      ]
      .AXF_FSC_DAT_TerminationDate__c,
      'Nenhum encerramento foi registrado'
    );

    // O predicado do leitor já existe e é coberto: quando o comando autorizado gravar a
    // fronteira, as ocorrências futuras elegíveis saem e as protegidas permanecem.
    ALT_CLS_ScheduleProjection.terminationOverride = Date.today();
    ALT_CLS_ScheduleProjection.ProjectionResult result = read(
      created.scheduleId
    );

    Assert.areEqual('OK', result.outcome, result.message);
    Assert.areEqual(
      2,
      result.evaluatedCount,
      'Só a parcela do dia e a obrigação protegida permanecem'
    );
    Set<Integer> sequences = new Set<Integer>();
    for (ALT_CLS_ScheduleProjection.OccurrenceLine line : result.lines) {
      sequences.add(line.sequence);
    }
    Assert.isTrue(sequences.contains(1));
    Assert.isTrue(sequences.contains(5));

    // Sem a fronteira, todas as ocorrências rastreadas continuam contando.
    ALT_CLS_ScheduleProjection.terminationOverride = null;
    Assert.areEqual(
      24,
      read(created.scheduleId).evaluatedCount,
      'Sem fronteira efetiva nada é cancelado'
    );
  }

  @IsTest
  static void directEngineCallIsRefusedForAnUnauthorizedHolder() {
    Account holder = holder('AXF103 motor');
    ALT_CLS_FinancialScheduleService.CreateResult created = create(
      holder.Id,
      'INSTALLMENT',
      12,
      1,
      Date.today(),
      'proj-engine-gate'
    );

    // O motor lê com SYSTEM_MODE: ele não pode ser um atalho de leitura autorizada.
    ALT_CLS_ScheduleProjection.authorizedOverride = new Set<Id>();
    ALT_CLS_ScheduleProjection.ProjectionInput input = new ALT_CLS_ScheduleProjection.ProjectionInput();
    input.scheduleId = created.scheduleId;
    input.asOfDate = Date.today();
    ALT_CLS_ScheduleProjection.ProjectionResult denied = ALT_CLS_ScheduleProjection.project(
      input
    );

    Assert.areEqual('FORBIDDEN', denied.outcome, denied.message);
    Assert.isTrue(denied.lines.isEmpty());
    Assert.isNull(denied.totalRemaining);

    // O titular autorizado continua lendo normalmente pelo mesmo motor.
    ALT_CLS_ScheduleProjection.authorizedOverride = new Set<Id>{ holder.Id };
    Assert.areEqual('OK', ALT_CLS_ScheduleProjection.project(input).outcome);
  }

  @IsTest
  static void overdueAndFutureSplitIsDisjointWithTheBoundaryCountedAsFuture() {
    Account holder = holder('AXF103 vencidas');
    // Principal não divisível pelo prazo: as parcelas NÃO têm o mesmo valor, então somar o balde
    // errado (ou contar a ocorrência errada) não passa por coincidência.
    ALT_CLS_FinancialScheduleService.CreateInput input = request(
      holder.Id,
      'INSTALLMENT',
      24,
      1,
      Date.today(),
      'proj-overdue'
    );
    input.principal = 1000000.00;
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      holder.Id
    };
    ALT_CLS_FinancialScheduleService.CreateResult created = ALT_CLS_FinancialScheduleService.createSchedule(
      input
    );
    Assert.areEqual('CREATED', created.outcome, created.message);

    // Cada ocorrência vence em today + (n-1) meses. Lendo com asOf três meses à frente, as
    // três primeiras vencem no passado e as demais são futuras.
    Date asOf = Date.today().addMonths(3);
    ALT_CLS_ScheduleProjection.ProjectionResult result = read(
      created.scheduleId,
      asOf,
      null
    );

    Assert.areEqual('OK', result.outcome, result.message);
    ALT_CLS_AmortizationSchedule.ScheduleInput formula = new ALT_CLS_AmortizationSchedule.ScheduleInput();
    formula.modality = 'INSTALLMENT';
    formula.principal = 1000000.00;
    formula.installments = 24;
    formula.firstDueDate = Date.today();
    ALT_CLS_AmortizationSchedule.ScheduleResult generated = ALT_CLS_AmortizationSchedule.generate(
      formula
    );
    Assert.areEqual('OK', generated.outcome, generated.message);

    // Valores concretos da fórmula aprovada, por balde — não a soma das próprias linhas lidas.
    Decimal overdueExpected = 0;
    Decimal futureExpected = 0;
    for (Integer sequence = 1; sequence <= 24; sequence++) {
      if (Date.today().addMonths(sequence - 1) < asOf) {
        overdueExpected += generated.occurrences[sequence - 1].payment;
      } else {
        futureExpected += generated.occurrences[sequence - 1].payment;
      }
    }
    Assert.areNotEqual(
      overdueExpected,
      futureExpected,
      'Os baldes precisam ter valores diferentes para a asserção ser significativa'
    );
    Assert.areEqual(
      3,
      result.overdueCount,
      'Três vencidas até a data de corte'
    );
    Assert.areEqual(21, result.futureCount, 'As demais são futuras');
    Assert.areEqual(
      overdueExpected.setScale(2),
      result.overdueTotal,
      'O total vencido é o valor concreto da fórmula para as vencidas'
    );
    Assert.areEqual(
      futureExpected.setScale(2),
      result.futureTotal,
      'O total futuro é o valor concreto da fórmula para as futuras'
    );
    Assert.areEqual(
      (result.overdueTotal + result.futureTotal).setScale(2),
      result.totalRemaining
    );

    // Uma linha exatamente na data de corte NÃO é vencida: o limite é estrito e é futuro.
    Date boundary = [
      SELECT AXF_FTX_DAT_DueDate__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE
        AXF_FTX_LKP_Schedule__c = :created.scheduleId
        AND AXF_FTX_NUM_Sequence__c = 4
      LIMIT 1
    ]
    .AXF_FTX_DAT_DueDate__c;
    ALT_CLS_ScheduleProjection.ProjectionResult atBoundary = read(
      created.scheduleId,
      boundary,
      null
    );
    Assert.areEqual(3, atBoundary.overdueCount);
    for (ALT_CLS_ScheduleProjection.OccurrenceLine line : atBoundary.lines) {
      if (line.sequence == 4) {
        Assert.isFalse(
          line.overdue,
          'Vencimento exatamente na data de corte conta como futuro'
        );
      }
    }
  }

  @IsTest
  static void throughSequencePagesTheProjectionWithExplicitContinuation() {
    Account holder = holder('AXF103 paginação');
    ALT_CLS_FinancialScheduleService.CreateResult created = create(
      holder.Id,
      'INSTALLMENT',
      24,
      1,
      Date.today(),
      'proj-paging'
    );

    ALT_CLS_ScheduleProjection.ProjectionResult result = read(
      created.scheduleId,
      Date.today(),
      5
    );

    Assert.areEqual('OK', result.outcome, result.message);
    Assert.areEqual(5, result.throughSequence);
    Assert.areEqual(5, result.evaluatedCount);
    Assert.isFalse(
      result.complete,
      'Uma leitura truncada nunca devolve total completo'
    );
    Assert.areEqual(6, result.continuationSequence);
    Decimal expected = 0;
    for (ALT_CLS_ScheduleProjection.OccurrenceLine line : result.lines) {
      Assert.isTrue(line.sequence <= 5);
      expected += line.amount;
    }
    Assert.areEqual(
      expected.setScale(2),
      result.totalRemaining,
      'O total cobre apenas a faixa solicitada'
    );
  }

  @IsTest
  static void evaluationCapTruncatesAndReportsContinuationInsteadOfATotal() {
    Account holder = holder('AXF103 teto');
    ALT_CLS_FinancialScheduleService.CreateResult created = create(
      holder.Id,
      'INSTALLMENT',
      1200,
      1,
      Date.today(),
      'proj-cap'
    );

    ALT_CLS_ScheduleProjection.ProjectionResult result = read(
      created.scheduleId,
      Date.today(),
      null
    );

    Assert.areEqual('OK', result.outcome, result.message);
    Assert.areEqual(
      ALT_CLS_ScheduleProjection.MAX_EVALUATED_SEQUENCES,
      result.evaluatedCount,
      'A avaliação para no teto declarado'
    );
    Assert.isFalse(result.complete);
    Assert.areEqual(
      ALT_CLS_ScheduleProjection.MAX_EVALUATED_SEQUENCES + 1,
      result.continuationSequence
    );
  }

  @IsTest
  static void confirmedLinesClearTheEstimatedLabelAndRevertingOneFlipsItBack() {
    Account holder = holder('AXF103 rótulo');
    // Três parcelas a partir de hoje: a janela inicial cobre todas, então não sobra virtual.
    ALT_CLS_FinancialScheduleService.CreateResult created = create(
      holder.Id,
      'INSTALLMENT',
      3,
      1,
      Date.today(),
      'proj-label'
    );

    List<AXF_OBJ_FinancialTransaction__c> rows = [
      SELECT Id
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE AXF_FTX_LKP_Schedule__c = :created.scheduleId
    ];
    Assert.areEqual(3, rows.size(), 'A janela cobre as três parcelas');
    for (AXF_OBJ_FinancialTransaction__c row : rows) {
      row.AXF_FTX_PKL_Status__c = 'CONFIRMED';
      row.AXF_FTX_CHK_IsEstimated__c = false;
    }
    update rows;

    ALT_CLS_ScheduleProjection.ProjectionResult confirmed = read(
      created.scheduleId
    );
    Assert.areEqual('OK', confirmed.outcome, confirmed.message);
    Assert.isFalse(
      confirmed.estimated,
      'Sem componente não confirmado o total não é rotulado estimado'
    );
    Assert.areEqual(0, confirmed.unconfirmedCount);
    for (ALT_CLS_ScheduleProjection.OccurrenceLine line : confirmed.lines) {
      Assert.isTrue(line.confirmed);
      Assert.isFalse(line.estimated);
    }

    // Reverter uma linha reintroduz o componente não confirmado e o rótulo volta.
    AXF_OBJ_FinancialTransaction__c reverted = rows[0];
    reverted.AXF_FTX_PKL_Status__c = 'PLANNED';
    update reverted;

    ALT_CLS_ScheduleProjection.ProjectionResult reverted1 = read(
      created.scheduleId
    );
    Assert.isTrue(reverted1.estimated);
    Assert.areEqual(1, reverted1.unconfirmedCount);
  }

  @IsTest
  static void duplicatePersistedIdentityIsNeverSilentlyOverwritten() {
    Account holder = holder('AXF103 duplicado');
    ALT_CLS_FinancialScheduleService.CreateResult created = create(
      holder.Id,
      'INSTALLMENT',
      12,
      1,
      Date.today(),
      'proj-duplicate'
    );
    AXF_OBJ_FinancialTransaction__c existing = [
      SELECT Id, AXF_FTX_NUM_CurrentBasis__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE
        AXF_FTX_LKP_Schedule__c = :created.scheduleId
        AND AXF_FTX_NUM_Sequence__c = 2
      LIMIT 1
    ];

    // Uma segunda linha persistida para a mesma identidade (cronograma, sequência), sem chave
    // de ocorrência — exatamente o caso que a leitura não pode reduzir a um mapa arbitrário.
    insert new AXF_OBJ_FinancialTransaction__c(
      AXF_FTX_LKP_Account__c = holder.Id,
      AXF_FTX_LKP_Schedule__c = created.scheduleId,
      AXF_FTX_NUM_Sequence__c = 2,
      AXF_FTX_NUM_Magnitude__c = 12.34,
      AXF_FTX_NUM_CurrentBasis__c = 12.34,
      AXF_FTX_PKL_Direction__c = 'DEBIT',
      AXF_FTX_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_FTX_DAT_PurchaseDate__c = Date.today(),
      AXF_FTX_PKL_Status__c = 'PLANNED',
      AXF_FTX_PKL_PlanKind__c = 'PLANNED',
      AXF_FTX_NUM_Version__c = 0,
      AXF_FTX_EXI_ClientRequestId__c = 'axf103-duplicate-identity'
    );

    ALT_CLS_ScheduleProjection.ProjectionResult result = read(
      created.scheduleId
    );
    Assert.areEqual('INVALID', result.outcome, result.message);
    Assert.isNull(result.totalRemaining);
    Assert.isNotNull(existing.AXF_FTX_NUM_CurrentBasis__c);
  }

  @IsTest
  static void adoptedOccurrenceWithoutCurrentBasisUsesTheImmutableMagnitude() {
    Account holder = holder('AXF103 adotado');
    ALT_CLS_FinancialScheduleService.CreateResult created = create(
      holder.Id,
      'INSTALLMENT',
      12,
      1,
      Date.today(),
      'proj-adopted'
    );
    ALT_CLS_ScheduleProjection.ProjectionResult before = read(
      created.scheduleId
    );

    AXF_OBJ_FinancialTransaction__c adopted = [
      SELECT Id, AXF_FTX_NUM_CurrentBasis__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE
        AXF_FTX_LKP_Schedule__c = :created.scheduleId
        AND AXF_FTX_NUM_Sequence__c = 2
      LIMIT 1
    ];
    Decimal originalBasis = adopted.AXF_FTX_NUM_CurrentBasis__c;
    // Ocorrência adotada: sem base corrente, e a magnitude original é a base congelada.
    adopted.AXF_FTX_NUM_CurrentBasis__c = null;
    adopted.AXF_FTX_NUM_Magnitude__c = originalBasis + 777.00;
    update adopted;

    ALT_CLS_ScheduleProjection.ProjectionResult after = read(
      created.scheduleId
    );
    Assert.areEqual('OK', after.outcome, after.message);
    Boolean found = false;
    for (ALT_CLS_ScheduleProjection.OccurrenceLine line : after.lines) {
      if (line.sequence == 2) {
        found = true;
        Assert.areEqual(
          originalBasis + 777.00,
          line.amount,
          'Sem base corrente vale a magnitude original, não o valor recalculado'
        );
      }
    }
    Assert.isTrue(found);
    Assert.areEqual(
      (before.totalRemaining + 777.00).setScale(2),
      after.totalRemaining,
      'O valor da referência do cronograma não substitui a magnitude original'
    );
    Assert.areNotEqual(before.totalRemaining, after.totalRemaining);
  }

  @IsTest
  static void cancelledPersistedOccurrenceLeavesTheTotal() {
    Account holder = holder('AXF103 cancelado');
    ALT_CLS_FinancialScheduleService.CreateResult created = create(
      holder.Id,
      'INSTALLMENT',
      24,
      1,
      Date.today(),
      'proj-cancelled'
    );
    ALT_CLS_ScheduleProjection.ProjectionResult before = read(
      created.scheduleId
    );
    AXF_OBJ_FinancialTransaction__c row = [
      SELECT Id, AXF_FTX_NUM_CurrentBasis__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE
        AXF_FTX_LKP_Schedule__c = :created.scheduleId
        AND AXF_FTX_NUM_Sequence__c = 2
      LIMIT 1
    ];
    Decimal cancelled = row.AXF_FTX_NUM_CurrentBasis__c;
    row.AXF_FTX_PKL_ScheduleState__c = 'CANCELLED';
    update row;

    ALT_CLS_ScheduleProjection.ProjectionResult after = read(
      created.scheduleId
    );

    Assert.areEqual(before.evaluatedCount - 1, after.evaluatedCount);
    Assert.areEqual(
      (before.totalRemaining - cancelled).setScale(2),
      after.totalRemaining,
      'Uma ocorrência cancelada sai do total e não reaparece como virtual'
    );
    for (ALT_CLS_ScheduleProjection.OccurrenceLine line : after.lines) {
      Assert.areNotEqual(2, line.sequence);
    }
  }

  @IsTest
  static void unboundedRecurrenceReturnsOnlyTheRequestedHorizon() {
    Account holder = holder('AXF103 indefinido');
    ALT_CLS_FinancialScheduleService.CreateResult created = create(
      holder.Id,
      'ESTIMATED',
      null,
      1,
      Date.today().addMonths(1),
      'proj-unbounded'
    );

    ALT_CLS_ScheduleProjection.ProjectionResult result = read(
      created.scheduleId
    );

    Assert.areEqual('OK', result.outcome, result.message);
    Assert.isTrue(result.unbounded);
    Assert.isFalse(
      result.complete,
      'Recorrência indefinida nunca devolve um total de vida finito'
    );
    Assert.isNotNull(result.totalRemaining);
    Assert.areEqual(
      expectedWindowCount(1, 12, Date.today().addMonths(1)),
      result.evaluatedCount,
      'O total devolvido é explicitamente o do horizonte solicitado'
    );
    Assert.isNotNull(result.continuationSequence);
  }

  @IsTest
  static void definitionResolutionPrefersTheHighestRevisionAtOrBelowTheSequence() {
    List<AXF_OBJ_ScheduleDefinition__c> definitions = new List<AXF_OBJ_ScheduleDefinition__c>{
      new AXF_OBJ_ScheduleDefinition__c(
        AXF_SDF_NUM_Revision__c = 1,
        AXF_SDF_NUM_EffectiveSequence__c = 1
      ),
      new AXF_OBJ_ScheduleDefinition__c(
        AXF_SDF_NUM_Revision__c = 2,
        AXF_SDF_NUM_EffectiveSequence__c = 50
      ),
      new AXF_OBJ_ScheduleDefinition__c(
        AXF_SDF_NUM_Revision__c = 3,
        AXF_SDF_NUM_EffectiveSequence__c = 200
      )
    };

    Assert.areEqual(
      1,
      ALT_CLS_ScheduleProjection.resolveDefinition(definitions, 49)
        .AXF_SDF_NUM_Revision__c
    );
    Assert.areEqual(
      2,
      ALT_CLS_ScheduleProjection.resolveDefinition(definitions, 50)
        .AXF_SDF_NUM_Revision__c
    );
    Assert.areEqual(
      2,
      ALT_CLS_ScheduleProjection.resolveDefinition(definitions, 199)
        .AXF_SDF_NUM_Revision__c
    );
    Assert.areEqual(
      3,
      ALT_CLS_ScheduleProjection.resolveDefinition(definitions, 200)
        .AXF_SDF_NUM_Revision__c
    );
    Assert.isNull(
      ALT_CLS_ScheduleProjection.resolveDefinition(definitions, 0),
      'Sem definição efetiva não há ocorrência presumida'
    );

    List<AXF_OBJ_ScheduleDefinition__c> tie = new List<AXF_OBJ_ScheduleDefinition__c>{
      new AXF_OBJ_ScheduleDefinition__c(
        AXF_SDF_NUM_Revision__c = 1,
        AXF_SDF_NUM_EffectiveSequence__c = 50
      ),
      new AXF_OBJ_ScheduleDefinition__c(
        AXF_SDF_NUM_Revision__c = 2,
        AXF_SDF_NUM_EffectiveSequence__c = 50
      )
    };
    Assert.areEqual(
      2,
      ALT_CLS_ScheduleProjection.resolveDefinition(tie, 50)
        .AXF_SDF_NUM_Revision__c,
      'Em mesma sequência efetiva vence a maior revisão'
    );
  }

  @IsTest
  static void referenceResolutionOrdersEconomicallyAndIgnoresCompensations() {
    List<AXF_OBJ_ScheduleReference__c> references = new List<AXF_OBJ_ScheduleReference__c>{
      new AXF_OBJ_ScheduleReference__c(
        AXF_SRF_NUM_EconomicSequence__c = 1,
        AXF_SRF_NUM_EffectiveSequence__c = 1,
        AXF_SRF_NUM_RecurringAmount__c = 100.00,
        AXF_SRF_PKL_Kind__c = 'INITIAL'
      ),
      new AXF_OBJ_ScheduleReference__c(
        AXF_SRF_NUM_EconomicSequence__c = 5,
        AXF_SRF_NUM_EffectiveSequence__c = 10,
        AXF_SRF_NUM_RecurringAmount__c = 200.00,
        AXF_SRF_PKL_Kind__c = 'MANUAL'
      ),
      new AXF_OBJ_ScheduleReference__c(
        AXF_SRF_NUM_EconomicSequence__c = 9,
        AXF_SRF_NUM_EffectiveSequence__c = 1,
        AXF_SRF_NUM_RecurringAmount__c = 300.00,
        AXF_SRF_PKL_Kind__c = 'COMPENSATION'
      )
    };

    Assert.areEqual(
      100.00,
      ALT_CLS_ScheduleProjection.resolveReference(references, 9)
        .AXF_SRF_NUM_RecurringAmount__c,
      'Uma referência ainda não efetiva não antecipa o valor'
    );
    Assert.areEqual(
      200.00,
      ALT_CLS_ScheduleProjection.resolveReference(references, 10)
        .AXF_SRF_NUM_RecurringAmount__c,
      'A ordem econômica decide a precedência, não o carimbo de tempo'
    );
    Assert.isFalse(
      ALT_CLS_ScheduleProjection.isAmbiguous(references, 20),
      'Compensações não criam ambiguidade'
    );
  }

  @IsTest
  static void occurrenceIdentityAndClientRequestTokenAreDeterministic() {
    String key = ALT_CLS_ScheduleProjection.occurrenceKey('schedule-key', 7);

    Assert.areEqual(
      AXF_CLS_IdentityFraming.key(
        new List<Object>{ 'axf103-occ-v1', 'schedule-key', 7 }
      ),
      key,
      'A identidade é hash(tag de versão, chave do cronograma, sequência)'
    );
    Assert.areEqual(64, key.length());
    Assert.areNotEqual(
      key,
      ALT_CLS_ScheduleProjection.occurrenceKey('schedule-key', 8)
    );

    String token = ALT_CLS_ScheduleProjection.clientRequestId(key);
    Assert.areEqual(36, token.length());
    Assert.areEqual(token, ALT_CLS_ScheduleProjection.clientRequestId(key));
    Assert.areNotEqual(
      token,
      ALT_CLS_ScheduleProjection.clientRequestId(
        ALT_CLS_ScheduleProjection.occurrenceKey('schedule-key', 8)
      )
    );
  }

  @IsTest
  static void scheduleWithoutADefinitionNeverYieldsAPartialTotal() {
    Account holder = holder('AXF103 sem definição');
    AXF_OBJ_FinancialSchedule__c root = new AXF_OBJ_FinancialSchedule__c(
      AXF_FSC_EXI_ScheduleKey__c = 'fsc-without-definition',
      AXF_FSC_LKP_Account__c = holder.Id,
      AXF_FSC_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_FSC_PKL_Direction__c = 'DEBIT',
      AXF_FSC_PKL_State__c = 'DRAFT',
      AXF_FSC_NUM_TrackingStartSequence__c = 1
    );
    insert root;
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      holder.Id
    };

    ALT_CLS_ScheduleProjection.ProjectionResult result = read(root.Id);

    Assert.areEqual('INVALID', result.outcome, result.message);
    Assert.isNull(result.totalRemaining);
  }

  @IsTest
  static void unauthorizedHolderCannotReadTheCommitment() {
    Account holder = holder('AXF103 não autorizado');
    ALT_CLS_FinancialScheduleService.CreateResult created = create(
      holder.Id,
      'INSTALLMENT',
      12,
      1,
      Date.today(),
      'proj-forbidden'
    );
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>();

    ALT_CLS_ScheduleProjection.ProjectionResult result = read(
      created.scheduleId
    );

    Assert.areEqual('FORBIDDEN', result.outcome, result.message);
    Assert.isNull(result.totalRemaining);
  }

  @IsTest
  static void readPortRefusesAnUnauthorizedHolder() {
    Account holder = holder('AXF103 porta negada');
    ALT_CLS_FinancialScheduleService.CreateResult created = create(
      holder.Id,
      'INSTALLMENT',
      12,
      1,
      Date.today(),
      'proj-port-forbidden'
    );
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>();

    // A porta de leitura exposta à UI não é um atalho: a checagem de titular continua sendo a
    // autoridade, e o motor não é alcançável sem ela.
    ALT_CLS_ScheduleProjection.ProjectionResult denied = AXF_CLS_CTRL_FinancialSchedule.readProjection(
      created.scheduleId,
      Date.today(),
      null
    );

    Assert.areEqual('FORBIDDEN', denied.outcome, denied.message);
    Assert.isTrue(denied.lines.isEmpty());
    Assert.isNull(denied.totalRemaining);
  }

  @IsTest
  static void compensatedReferenceIsDiscardedInsteadOfInflatingTheTotal() {
    Account holder = holder('AXF103 compensação');
    // 24 parcelas: doze dentro da janela materializada e doze ainda VIRTUAIS. A referência
    // vigente é a autoridade do valor virtual; a ocorrência persistida mantém a base congelada.
    ALT_CLS_FinancialScheduleService.CreateResult created = create(
      holder.Id,
      'ESTIMATED',
      24,
      1,
      Date.today(),
      'proj-compensated'
    );
    AXF_OBJ_ScheduleReference__c manual = new AXF_OBJ_ScheduleReference__c(
      AXF_SRF_EXI_ReferenceKey__c = 'compensated-manual',
      AXF_SRF_LKP_Schedule__c = created.scheduleId,
      AXF_SRF_NUM_EconomicSequence__c = 5,
      AXF_SRF_NUM_EffectiveSequence__c = 1,
      AXF_SRF_NUM_RecurringAmount__c = 900.00,
      AXF_SRF_PKL_Kind__c = 'MANUAL',
      AXF_SRF_DT_ConfirmedAt__c = System.now(),
      AXF_SRF_LKP_ConfirmedBy__c = UserInfo.getUserId()
    );
    insert manual;

    ALT_CLS_ScheduleProjection.ProjectionResult before = read(
      created.scheduleId
    );
    Assert.areEqual('OK', before.outcome, before.message);
    Assert.isTrue(
      before.virtualCount > 0,
      'Sem ocorrência virtual a referência não teria efeito algum'
    );
    Assert.areEqual(
      16800.00,
      before.totalRemaining,
      'A referência de maior ordem econômica é a vigente para o componente virtual (12 x 900) somada à base congelada das persistidas (12 x 500)'
    );

    // A compensação retira a referência manual: ela não é mais selecionada nem fornece valor.
    insert new AXF_OBJ_ScheduleReference__c(
      AXF_SRF_EXI_ReferenceKey__c = 'compensated-withdrawal',
      AXF_SRF_LKP_Schedule__c = created.scheduleId,
      AXF_SRF_NUM_EconomicSequence__c = 6,
      AXF_SRF_NUM_EffectiveSequence__c = 1,
      AXF_SRF_NUM_RecurringAmount__c = 0.00,
      AXF_SRF_PKL_Kind__c = 'COMPENSATION',
      AXF_SRF_LKP_Compensates__c = manual.Id
    );

    ALT_CLS_ScheduleProjection.ProjectionResult after = read(
      created.scheduleId
    );
    Assert.areEqual('OK', after.outcome, after.message);
    Assert.areEqual(
      12000.00,
      after.totalRemaining,
      'A referência retirada não fornece mais valor: o componente virtual volta à referência inicial (12 x 500) com a mesma base congelada (12 x 500)'
    );
    Assert.isFalse(after.lines.isEmpty());
    for (ALT_CLS_ScheduleProjection.OccurrenceLine line : after.lines) {
      Assert.areNotEqual(
        manual.Id,
        line.referenceId,
        'A referência compensada não é selecionada'
      );
      Assert.areEqual(500.00, line.amount);
    }

    // Uma retirada NUNCA é um pagamento negativo: o mecanismo é a compensação, e um valor
    // recorrente negativo é recusado.
    Assert.isFalse(
      Database.insert(
          new AXF_OBJ_ScheduleReference__c(
            AXF_SRF_EXI_ReferenceKey__c = 'negative-withdrawal',
            AXF_SRF_LKP_Schedule__c = created.scheduleId,
            AXF_SRF_NUM_EconomicSequence__c = 7,
            AXF_SRF_NUM_EffectiveSequence__c = 1,
            AXF_SRF_NUM_RecurringAmount__c = -100.00,
            AXF_SRF_PKL_Kind__c = 'MANUAL'
          ),
          false
        )
        .isSuccess(),
      'Uma retirada não é registrada como valor recorrente negativo'
    );
  }

  @IsTest
  static void compensationOfAnotherScheduleIsRejected() {
    Account holder = holder('AXF103 compensação alheia');
    ALT_CLS_FinancialScheduleService.CreateResult first = create(
      holder.Id,
      'ESTIMATED',
      12,
      1,
      Date.today(),
      'proj-compensates-a'
    );
    ALT_CLS_FinancialScheduleService.CreateResult second = create(
      holder.Id,
      'ESTIMATED',
      12,
      1,
      Date.today().addDays(1),
      'proj-compensates-b'
    );
    AXF_OBJ_ScheduleReference__c foreign = [
      SELECT Id
      FROM AXF_OBJ_ScheduleReference__c
      WHERE AXF_SRF_LKP_Schedule__c = :first.scheduleId
      LIMIT 1
    ];

    // Uma compensação que aponta a referência de OUTRO cronograma não neutralizaria nada: ela
    // seria aceita como evidência e o valor compensado continuaria sendo somado.
    Assert.isFalse(
      Database.insert(
          new AXF_OBJ_ScheduleReference__c(
            AXF_SRF_EXI_ReferenceKey__c = 'compensates-foreign',
            AXF_SRF_LKP_Schedule__c = second.scheduleId,
            AXF_SRF_NUM_EconomicSequence__c = 2,
            AXF_SRF_NUM_EffectiveSequence__c = 1,
            AXF_SRF_NUM_RecurringAmount__c = 0.00,
            AXF_SRF_PKL_Kind__c = 'COMPENSATION',
            AXF_SRF_LKP_Compensates__c = foreign.Id
          ),
          false
        )
        .isSuccess(),
      'A compensação só neutraliza referência do mesmo cronograma'
    );
  }

  @IsTest
  static void persistedOccurrenceUnderAForeignIdentityIsRejected() {
    Account holder = holder('AXF103 identidade alheia');
    ALT_CLS_FinancialScheduleService.CreateResult created = create(
      holder.Id,
      'INSTALLMENT',
      12,
      1,
      Date.today(),
      'proj-identity'
    );
    AXF_OBJ_FinancialTransaction__c row = [
      SELECT Id
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE
        AXF_FTX_LKP_Schedule__c = :created.scheduleId
        AND AXF_FTX_NUM_Sequence__c = 2
      LIMIT 1
    ];
    row.AXF_FTX_EXI_OccurrenceKey__c = ALT_CLS_ScheduleProjection.occurrenceKey(
      'outra-identidade-de-cronograma',
      2
    );
    update row;

    ALT_CLS_ScheduleProjection.ProjectionResult result = read(
      created.scheduleId
    );

    Assert.areEqual('INVALID', result.outcome, result.message);
    Assert.isNull(
      result.totalRemaining,
      'Uma linha sob outra identidade não conta como a esperada'
    );
    Assert.isFalse(result.complete);
  }

  @IsTest
  static void trackedSequenceWithoutAnEffectiveDefinitionIsRejected() {
    Account holder = holder('AXF103 lacuna de definição');
    AXF_OBJ_FinancialSchedule__c root = new AXF_OBJ_FinancialSchedule__c(
      AXF_FSC_EXI_ScheduleKey__c = 'fsc-gap-definition',
      AXF_FSC_LKP_Account__c = holder.Id,
      AXF_FSC_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_FSC_PKL_Direction__c = 'DEBIT',
      AXF_FSC_PKL_State__c = 'DRAFT',
      AXF_FSC_NUM_TrackingStartSequence__c = 1
    );
    insert root;
    // A definição só passa a existir na sequência 5: as sequências 1..4 do intervalo rastreado
    // ficam sem definição efetiva e não podem ser omitidas em silêncio sob um resultado
    // rotulado completo.
    insert new AXF_OBJ_ScheduleDefinition__c(
      AXF_SDF_EXI_DefinitionKey__c = 'sdf-gap-definition',
      AXF_SDF_LKP_Schedule__c = root.Id,
      AXF_SDF_NUM_Revision__c = 1,
      AXF_SDF_NUM_EffectiveSequence__c = 5,
      AXF_SDF_PKL_Method__c = 'INSTALLMENT',
      AXF_SDF_NUM_TotalInstallments__c = 8,
      AXF_SDF_NUM_FirstSequence__c = 5,
      AXF_SDF_DAT_FirstDueDate__c = Date.today(),
      AXF_SDF_NUM_AnchorDay__c = 10,
      AXF_SDF_NUM_PeriodMonths__c = 1,
      AXF_SDF_NUM_Principal__c = 1200
    );
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      holder.Id
    };

    ALT_CLS_ScheduleProjection.ProjectionResult result = read(root.Id);

    Assert.areEqual('INVALID', result.outcome, result.message);
    Assert.isNull(result.totalRemaining);
    Assert.isFalse(result.complete);
    Assert.isFalse(result.coverageComplete);
  }

  @IsTest
  static void fullySettledScheduleReturnsAZeroTotalInsteadOfInvalid() {
    Account holder = holder('AXF103 liquidado');
    ALT_CLS_FinancialScheduleService.CreateResult created = create(
      holder.Id,
      'INSTALLMENT',
      3,
      1,
      Date.today(),
      'proj-settled'
    );
    List<AXF_OBJ_FinancialTransaction__c> rows = [
      SELECT Id
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE AXF_FTX_LKP_Schedule__c = :created.scheduleId
    ];
    Assert.areEqual(3, rows.size(), 'A janela cobre as três parcelas');
    for (AXF_OBJ_FinancialTransaction__c row : rows) {
      row.AXF_FTX_PKL_ScheduleState__c = 'CANCELLED';
    }
    update rows;

    ALT_CLS_ScheduleProjection.ProjectionResult result = read(
      created.scheduleId
    );

    Assert.areEqual('OK', result.outcome, result.message);
    Assert.areEqual(0, result.evaluatedCount);
    Assert.areEqual(
      0.00,
      result.totalRemaining,
      'Um cronograma totalmente liquidado tem total ZERO, não nulo'
    );
    Assert.areEqual(0.00, result.overdueTotal);
    Assert.areEqual(0.00, result.futureTotal);
    Assert.areEqual(0.00, result.horizonTotal);
    Assert.isTrue(
      result.coverageComplete,
      'A cobertura é completa: o prazo é finito e nada foi truncado'
    );
  }

  @IsTest
  static void invalidPaginationRequestIsAnErrorInsteadOfTheFullTotal() {
    Account holder = holder('AXF103 paginação inválida');
    ALT_CLS_FinancialScheduleService.CreateResult created = create(
      holder.Id,
      'INSTALLMENT',
      12,
      1,
      Date.today(),
      'proj-paging-invalid'
    );

    for (Integer invalid : new List<Integer>{ 0, -1 }) {
      ALT_CLS_ScheduleProjection.ProjectionResult result = read(
        created.scheduleId,
        Date.today(),
        invalid
      );
      Assert.areEqual('INVALID', result.outcome, result.message);
      Assert.isNull(
        result.totalRemaining,
        'Um pedido de paginação inválido não devolve o total completo'
      );
    }
  }

  @IsTest
  static void terminationBoundaryDriftAloneMakesTheReadStale() {
    Account holder = holder('AXF103 fronteira obsoleta');
    ALT_CLS_FinancialScheduleService.CreateResult created = create(
      holder.Id,
      'INSTALLMENT',
      12,
      1,
      Date.today(),
      'proj-termination-stale'
    );
    AXF_OBJ_FinancialSchedule__c root = [
      SELECT
        Id,
        AXF_FSC_NUM_ProjectionRevision__c,
        AXF_FSC_NUM_FinancialVersion__c
      FROM AXF_OBJ_FinancialSchedule__c
      WHERE Id = :created.scheduleId
    ];
    AXF_OBJ_FinancialSchedule__c drifted = root.clone(
      false,
      true,
      false,
      false
    );
    // Só a fronteira de encerramento mudou: nem a revisão de projeção nem a época financeira.
    drifted.AXF_FSC_DAT_TerminationDate__c = Date.today().addMonths(6);
    ALT_CLS_ScheduleProjection.recheckOverride = drifted;

    ALT_CLS_ScheduleProjection.ProjectionResult result = read(
      created.scheduleId
    );

    Assert.areEqual('STALE', result.outcome, result.message);
    Assert.isNull(result.totalRemaining);
    Assert.isNull(result.horizonTotal);
    Assert.isFalse(result.complete);
    Assert.isNotNull(
      result.recheckedTerminationDate,
      'A fronteira relida participa da rechecagem de versão'
    );
  }

  @IsTest
  static void equalAmountConfirmationsAtTheSameEconomicSequenceAreAmbiguous() {
    Account holder = holder('AXF103 ambíguo mesmo valor');
    ALT_CLS_FinancialScheduleService.CreateResult created = create(
      holder.Id,
      'ESTIMATED',
      12,
      1,
      Date.today(),
      'proj-amb-equal'
    );
    // MESMO valor da referência inicial e MESMA ordem econômica: duas confirmações válidas na
    // mesma ordem econômica conflitam mesmo com o mesmo valor, porque a ordem econômica é a
    // autoridade de precedência e nenhuma das duas vence a outra.
    insert new AXF_OBJ_ScheduleReference__c(
      AXF_SRF_EXI_ReferenceKey__c = 'amb-equal-amount',
      AXF_SRF_LKP_Schedule__c = created.scheduleId,
      AXF_SRF_NUM_EconomicSequence__c = 1,
      AXF_SRF_NUM_EffectiveSequence__c = 1,
      AXF_SRF_NUM_RecurringAmount__c = 500.00,
      AXF_SRF_PKL_Kind__c = 'MANUAL',
      AXF_SRF_DT_ConfirmedAt__c = System.now(),
      AXF_SRF_LKP_ConfirmedBy__c = UserInfo.getUserId()
    );

    ALT_CLS_ScheduleProjection.ProjectionResult result = read(
      created.scheduleId
    );

    Assert.areEqual('AMBIGUOUS', result.outcome, result.message);
    Assert.isNull(result.totalRemaining);
    Assert.isTrue(result.lines.isEmpty());
  }

  @IsTest
  static void terminationBoundaryUsesTheEffectiveDueDateNotTheNominalOne() {
    Account holder = holder('AXF103 vencimento efetivo');
    ALT_CLS_FinancialScheduleService.CreateResult created = create(
      holder.Id,
      'INSTALLMENT',
      6,
      1,
      Date.today(),
      'proj-effective-boundary'
    );
    AXF_OBJ_FinancialTransaction__c third = [
      SELECT Id
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE
        AXF_FTX_LKP_Schedule__c = :created.scheduleId
        AND AXF_FTX_NUM_Sequence__c = 3
      LIMIT 1
    ];
    // O vencimento NOMINAL da sequência 3 é hoje + 2 meses e o EFETIVO passa a ser hoje.
    third.AXF_FTX_DAT_DueDate__c = Date.today();
    update third;

    ALT_CLS_ScheduleProjection.terminationOverride = Date.today();
    ALT_CLS_ScheduleProjection.ProjectionResult result = read(
      created.scheduleId
    );
    ALT_CLS_ScheduleProjection.terminationOverride = null;

    Assert.areEqual('OK', result.outcome, result.message);
    Set<Integer> sequences = new Set<Integer>();
    for (ALT_CLS_ScheduleProjection.OccurrenceLine line : result.lines) {
      sequences.add(line.sequence);
    }
    Assert.isTrue(
      sequences.contains(3),
      'A fronteira é o vencimento EFETIVO: uma parcela cujo pagamento efetivo está na fronteira permanece'
    );
    Assert.isFalse(
      sequences.contains(2),
      'A parcela cujo vencimento efetivo é posterior à fronteira sai do total'
    );
    Assert.areEqual(2, result.evaluatedCount, result.message);
  }
}
