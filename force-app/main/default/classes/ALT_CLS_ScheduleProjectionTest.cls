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
    Assert.isTrue(result.complete, 'Um prazo finito produz um total completo');
    Assert.isFalse(result.unbounded);
    Assert.isTrue(
      result.estimated,
      'Há componente não confirmado, então o total é rotulado estimado'
    );

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
    drifted.AXF_FSC_NUM_ProjectionRevision__c =
      root.AXF_FSC_NUM_ProjectionRevision__c + 1;
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
    ALT_CLS_FinancialScheduleService.CreateResult created = create(
      holder.Id,
      'INSTALLMENT',
      24,
      1,
      Date.today(),
      'proj-overdue'
    );

    // Cada ocorrência vence em today + (n-1) meses. Lendo com asOf três meses à frente, as
    // três primeiras vencem no passado e as demais são futuras.
    Date asOf = Date.today().addMonths(3);
    ALT_CLS_ScheduleProjection.ProjectionResult result = read(
      created.scheduleId,
      asOf,
      null
    );

    Assert.areEqual('OK', result.outcome, result.message);
    Assert.areEqual(
      3,
      result.overdueCount,
      'Três vencidas até a data de corte'
    );
    Assert.areEqual(
      result.evaluatedCount - 3,
      result.futureCount,
      'Vencidas e futuras são disjuntas e cobrem toda a faixa'
    );
    Decimal overdueExpected = 0;
    Decimal futureExpected = 0;
    for (ALT_CLS_ScheduleProjection.OccurrenceLine line : result.lines) {
      if (line.overdue) {
        overdueExpected += line.amount;
      } else {
        futureExpected += line.amount;
      }
    }
    Assert.areEqual(overdueExpected.setScale(2), result.overdueTotal);
    Assert.areEqual(futureExpected.setScale(2), result.futureTotal);
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
}
