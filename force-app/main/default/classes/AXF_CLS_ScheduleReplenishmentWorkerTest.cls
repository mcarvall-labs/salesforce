/**
 * @description AXF-103 fatia 2 — worker, agendador, passagem de recuperação e finalizador da
 * reposição rolante: a matriz de I/O ponta a ponta.
 *
 * Cobre: reposição mensal com a janela rolada, reconciliação do cursor e a NÃO regressão dele,
 * lacuna abaixo do cursor, linha cancelada dentro do prefixo coberto, cronograma desligado, falha
 * de DML com reversão integral e metadado higienizado em transação separada, escada de recuo
 * percorrida até o orçamento esgotado e o realarme limitado, replay pela produção com colisão
 * real de chave única, fim do termo, principal sem visibilidade (permanente e sem consumo de
 * orçamento), principal sem permissão, leitura de autoridade inconclusiva, deriva de revisão e de
 * ponteiro entre a leitura e o lock, orçamento de verificações de lacuna, ordem do lock do titular,
 * pontos de entrada (agendador, recuperação dirigida, passagem de recuperação) e a política
 * versionada da cadência.
 *
 * Duas verificações de PLATAFORMA estão embutidas aqui, porque decisões de projeto dependem
 * delas: `SYSTEM_MODE` não amplia visibilidade de registro, e DML também respeita o acesso ao
 * registro. Elas são o motivo declarado das classes privilegiadas do job.
 */
@IsTest(isParallel=false)
private class AXF_CLS_ScheduleReplenishmentWorkerTest {
  private static final String GESTOR_PS = 'AXF_PS_GestorFinanceiro';

  /** Leitor no escopo de compartilhamento da classe: SYSTEM_MODE com `with sharing`. */
  public with sharing class SharedScopedReader {
    public Integer countSchedules() {
      return [
        SELECT COUNT()
        FROM AXF_OBJ_FinancialSchedule__c
        WITH SYSTEM_MODE
      ];
    }
  }

  /** Leitor do caminho privilegiado declarado: SYSTEM_MODE com `without sharing`. */
  public without sharing class PrivilegedScopedReader {
    public Integer countSchedules() {
      return [
        SELECT COUNT()
        FROM AXF_OBJ_FinancialSchedule__c
        WITH SYSTEM_MODE
      ];
    }
  }

  /**
   * Escritor no escopo de compartilhamento da classe: DML de metadado operacional com
   * `with sharing` em linha invisível. É a hipótese que sustenta a existência do
   * `AXF_CLS_ScheduleReplenishmentStateWriter`.
   */
  public with sharing class SharedScopedWriter {
    public Boolean updateRetry(Id scheduleId, Integer value) {
      try {
        Database.update(
          new AXF_OBJ_FinancialSchedule__c(
            Id = scheduleId,
            AXF_FSC_NUM_RetryCount__c = value
          ),
          AccessLevel.SYSTEM_MODE
        );
        return true;
      } catch (DmlException refused) {
        return false;
      }
    }
  }

  /** O caminho privilegiado declarado: a MESMA DML a partir de `without sharing`. */
  public without sharing class PrivilegedScopedWriter {
    public Boolean updateRetry(Id scheduleId, Integer value) {
      try {
        Database.update(
          new AXF_OBJ_FinancialSchedule__c(
            Id = scheduleId,
            AXF_FSC_NUM_RetryCount__c = value
          ),
          AccessLevel.SYSTEM_MODE
        );
        return true;
      } catch (DmlException refused) {
        return false;
      }
    }
  }

  /** Contexto de finalizador com o desfecho de falha, para exercitar o caminho real sem fila. */
  private class FailedFinalizerContext implements FinalizerContext {
    private final Exception failure;

    FailedFinalizerContext(Exception failure) {
      this.failure = failure;
    }

    public Id getAsyncApexJobId() {
      return null;
    }

    public String getRequestId() {
      return 'axf103-replenishment-test';
    }

    public ParentJobResult getResult() {
      return ParentJobResult.UNHANDLED_EXCEPTION;
    }

    public Exception getException() {
      return failure;
    }
  }

  // --- fixtures ------------------------------------------------------------

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

  /** Cronograma ACTIVE com a janela inicial gravada pela porta única. */
  private static AXF_OBJ_FinancialSchedule__c schedule(
    Id holderId,
    Integer totalInstallments,
    Integer horizonMonths
  ) {
    return schedule(holderId, totalInstallments, horizonMonths, null);
  }

  /** Duas schedules do MESMO titular exigem discriminador: ele participa da identidade. */
  private static AXF_OBJ_FinancialSchedule__c schedule(
    Id holderId,
    Integer totalInstallments,
    Integer horizonMonths,
    String legacyGroupKey
  ) {
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      holderId
    };
    ALT_CLS_FinancialScheduleService.CreateInput input = new ALT_CLS_FinancialScheduleService.CreateInput();
    input.accountId = holderId;
    input.direction = 'DEBIT';
    input.currencyIsoCode = 'BRL';
    input.method = 'INSTALLMENT';
    input.totalInstallments = totalInstallments;
    input.firstSequence = 1;
    input.trackingStartSequence = 1;
    input.trackingDueDate = Date.today();
    input.periodMonths = 1;
    input.principal = totalInstallments * 500;
    input.horizonMonths = horizonMonths;
    input.legacyGroupKey = legacyGroupKey;
    ALT_CLS_FinancialScheduleService.CreateResult result = ALT_CLS_FinancialScheduleService.createSchedule(
      input
    );
    Assert.areEqual('CREATED', result.outcome, result.message);
    return [
      SELECT
        Id,
        AXF_FSC_EXI_ScheduleKey__c,
        AXF_FSC_LKP_Account__c,
        AXF_FSC_NUM_HorizonMonths__c,
        AXF_FSC_NUM_CoverageSequence__c,
        AXF_FSC_LKP_ActiveDefinition__c
      FROM AXF_OBJ_FinancialSchedule__c
      WHERE Id = :result.scheduleId
    ];
  }

  /**
   * Simula a passagem do tempo: a janela rolante avança (o horizonte persistido cresce dentro do
   * teto do CAMPO aprovado, 2 dígitos) e a geração é ligada. O horizonte é campo mantido pelo
   * serviço, então a montagem usa a capacidade de escrita que o serviço libera apenas para o
   * comando autorizado.
   *
   * Um horizonte acima do default aprovado (12) é usado SOMENTE onde o cenário exige mais
   * ocorrências dentro de uma janela do que o limite de transação — o limite de 50 é inalcançável
   * dentro de 12 meses de periodicidade mensal.
   */
  private static void rollWindowForward(
    Id scheduleId,
    Integer horizonMonths,
    Boolean enabled
  ) {
    ALT_CLS_FinancialScheduleService.writing = true;
    try {
      update new AXF_OBJ_FinancialSchedule__c(
        Id = scheduleId,
        AXF_FSC_NUM_HorizonMonths__c = horizonMonths,
        AXF_FSC_BOL_GenerationEnabled__c = enabled
      );
    } finally {
      ALT_CLS_FinancialScheduleService.writing = false;
    }
  }

  /** Escreve um campo mantido pelo serviço, sob a capacidade que o serviço libera. */
  private static void serviceWrite(AXF_OBJ_FinancialSchedule__c row) {
    ALT_CLS_FinancialScheduleService.writing = true;
    try {
      update row;
    } finally {
      ALT_CLS_FinancialScheduleService.writing = false;
    }
  }

  private static Date scheduleOrigin(Id scheduleId) {
    return [
      SELECT AXF_SDF_DAT_FirstDueDate__c
      FROM AXF_OBJ_ScheduleDefinition__c
      WHERE AXF_SDF_LKP_Schedule__c = :scheduleId
      LIMIT 1
    ]
    .AXF_SDF_DAT_FirstDueDate__c;
  }

  /** Sequências elegíveis dentro da janela, pelo MESMO calendário puro que o motor usa. */
  private static Integer sequencesInsideWindow(
    Date origin,
    Integer lastSequence,
    Integer horizonMonths
  ) {
    Date windowEnd = ALT_CLS_ScheduleCalendar.monthEndShifted(
      Date.today(),
      Math.max(0, horizonMonths - 1)
    );
    Integer count = 0;
    for (Integer sequence = 1; sequence <= lastSequence; sequence++) {
      if (
        ALT_CLS_ScheduleCalendar.nominalDueDate(
          origin,
          1,
          1,
          origin.day(),
          sequence
        ) > windowEnd
      ) {
        break;
      }
      count++;
    }
    return count;
  }

  private static List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem> workFor(
    Id scheduleId
  ) {
    return AXF_CLS_ScheduleReplenishmentSelector.workItems(
      new Set<Id>{ scheduleId }
    );
  }

  private static ALT_CLS_FinancialScheduleService.ReplenishmentRequest request(
    Id scheduleId,
    Boolean recovery
  ) {
    ALT_CLS_FinancialScheduleService.ReplenishmentRequest value = new ALT_CLS_FinancialScheduleService.ReplenishmentRequest();
    value.scheduleId = scheduleId;
    value.holderId = [
      SELECT AXF_FSC_LKP_Account__c
      FROM AXF_OBJ_FinancialSchedule__c
      WHERE Id = :scheduleId
      LIMIT 1
    ]
    .AXF_FSC_LKP_Account__c;
    value.recovery = recovery;
    return value;
  }

  private static Integer occurrencesOf(Id scheduleId) {
    return [
      SELECT COUNT()
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE AXF_FTX_LKP_Schedule__c = :scheduleId
    ];
  }

  private static Integer rowsOfSequence(Id scheduleId, Integer sequence) {
    return [
      SELECT COUNT()
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE
        AXF_FTX_LKP_Schedule__c = :scheduleId
        AND AXF_FTX_NUM_Sequence__c = :sequence
    ];
  }

  private static AXF_OBJ_FinancialSchedule__c stateOf(Id scheduleId) {
    return [
      SELECT
        AXF_FSC_NUM_CoverageSequence__c,
        AXF_FSC_NUM_FinancialVersion__c,
        AXF_FSC_NUM_RetryCount__c,
        AXF_FSC_DT_NextAttemptAt__c,
        AXF_FSC_TXT_LastErrorCode__c,
        AXF_FSC_NUM_RefreshCursor__c,
        AXF_FSC_NUM_ProjectionRevision__c,
        AXF_FSC_BOL_GenerationEnabled__c,
        AXF_FSC_PKL_State__c
      FROM AXF_OBJ_FinancialSchedule__c
      WHERE Id = :scheduleId
    ];
  }

  /** Apaga a ocorrência de uma sequência: o estado de "lacuna" que o detector precisa achar. */
  private static void deleteSequence(Id scheduleId, Integer sequence) {
    List<AXF_OBJ_FinancialTransaction__c> rows = [
      SELECT Id
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE
        AXF_FTX_LKP_Schedule__c = :scheduleId
        AND AXF_FTX_NUM_Sequence__c = :sequence
    ];
    Assert.areEqual(
      1,
      rows.size(),
      'A sequência precisa existir para virar lacuna'
    );
    delete rows;
  }

  /** Marca a ocorrência como CANCELLED: cache derivado de obrigação cancelada. */
  private static void cancelSequence(Id scheduleId, Integer sequence) {
    List<AXF_OBJ_FinancialTransaction__c> rows = [
      SELECT Id, AXF_FTX_PKL_ScheduleState__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE
        AXF_FTX_LKP_Schedule__c = :scheduleId
        AND AXF_FTX_NUM_Sequence__c = :sequence
    ];
    Assert.areEqual(1, rows.size());
    rows[0].AXF_FTX_PKL_ScheduleState__c = 'CANCELLED';
    update rows;
  }

  /**
   * Roda UMA passagem pelo worker de forma síncrona. O `Finalizer` só pode ser anexado dentro do
   * contexto assíncrono real — por isso o caminho de fila é exercitado com `System.enqueueJob` e
   * `System.schedule`, e os desfechos por cronograma são observados pela porta única de escrita.
   */
  private static ALT_CLS_FinancialScheduleService.ReplenishmentResult runPass(
    Id scheduleId,
    Boolean recovery
  ) {
    return ALT_CLS_FinancialScheduleService.replenishSchedule(
      request(scheduleId, recovery)
    );
  }

  private static AXF_CLS_ScheduleReplenishmentQueueable.ReplenishmentFinalizer finalizerFor(
    Id failingId,
    Id laterId
  ) {
    List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem> work = workFor(
      failingId
    );
    List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem> rest = workFor(
      laterId
    );
    return new AXF_CLS_ScheduleReplenishmentQueueable.ReplenishmentFinalizer(
      work[0],
      rest,
      0,
      false
    );
  }

  private static AXF_CLS_ScheduleReplenishmentQueueable.ReplenishmentFinalizer finalizerForException(
    Id scheduleId
  ) {
    List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem> work = workFor(
      scheduleId
    );
    return new AXF_CLS_ScheduleReplenishmentQueueable.ReplenishmentFinalizer(
      work[0],
      new List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem>(),
      0,
      false
    );
  }

  private static List<Integer> ladderDelays() {
    List<Integer> delays = new List<Integer>();
    for (
      AXF_CLS_ScheduleReplenishmentQueueable.ChainStep step : AXF_CLS_ScheduleReplenishmentQueueable.chainLog
    ) {
      delays.add(step.delayMinutes);
    }
    return delays;
  }

  /** Faixa do instante persistido: evita a virada de minuto como falha intermitente. */
  private static void assertLadderStep(
    DateTime before,
    DateTime after,
    DateTime actual,
    Integer minutes,
    String label
  ) {
    Assert.isNotNull(actual, label + ': há instante persistido');
    Assert.isTrue(
      actual.getTime() >= before.addMinutes(minutes).getTime(),
      label + ': ' + actual + ' é posterior a ' + before.addMinutes(minutes)
    );
    Assert.isTrue(
      actual.getTime() <= after.addMinutes(minutes).getTime(),
      label + ': ' + actual + ' é anterior a ' + after.addMinutes(minutes)
    );
  }

  // --- exceções REAIS, para classificação de verdade -------------------------

  private static System.DmlException realDmlException() {
    try {
      insert new AXF_OBJ_FinancialSchedule__c();
    } catch (System.DmlException expected) {
      return expected;
    }
    Assert.fail(
      'A inserção inválida de cronograma precisava lançar DmlException'
    );
    return null;
  }

  private static System.QueryException realQueryException() {
    try {
      Database.query('SELECT Id FROM Account WHERE AXF_Nao_Existe__c = 1');
    } catch (System.QueryException expected) {
      return expected;
    }
    Assert.fail('A consulta inválida precisava lançar QueryException');
    return null;
  }

  private static System.MathException realMathException() {
    try {
      Decimal.valueOf(1).setScale(40);
    } catch (System.MathException expected) {
      return expected;
    }
    try {
      Decimal.valueOf(1).divide(Decimal.valueOf(3), 40);
    } catch (System.MathException expected) {
      return expected;
    }
    ALT_CLS_AmortizationSchedule.ScheduleInput input = new ALT_CLS_AmortizationSchedule.ScheduleInput();
    input.modality = 'PRICE';
    input.principal = Decimal.valueOf('9999999999999999.99');
    input.installments = 360;
    input.periodRate = Decimal.valueOf('9999999999.9999999999');
    input.firstDueDate = Date.today();
    try {
      ALT_CLS_AmortizationSchedule.generate(input);
    } catch (System.MathException expected) {
      return expected;
    }
    Assert.fail('Nenhuma expressão produziu um MathException real');
    return null;
  }

  private static ALT_CLS_ScheduleCalendar.CalendarException realCalendarException() {
    try {
      ALT_CLS_ScheduleCalendar.nominalDueDate(Date.today(), 1, 1, 99, 2);
    } catch (ALT_CLS_ScheduleCalendar.CalendarException expected) {
      return expected;
    }
    Assert.fail('O calendário precisava recusar o dia âncora 99');
    return null;
  }

  // --- reposição mensal ----------------------------------------------------

  @IsTest
  static void monthlyPassMaterializesOnlyTheMissingIdentitiesInsideTheWindow() {
    Account account = holder('AXF103 reposicao mensal');
    AXF_OBJ_FinancialSchedule__c schedule = schedule(account.Id, 24, 2);
    Id scheduleId = schedule.Id;
    Date origin = scheduleOrigin(scheduleId);
    Integer before = occurrencesOf(scheduleId);
    Assert.areEqual(
      sequencesInsideWindow(origin, 24, 2),
      before,
      'A criação grava apenas a janela inicial'
    );
    AXF_OBJ_FinancialTransaction__c protectedBefore = [
      SELECT
        AXF_FTX_NUM_Magnitude__c,
        AXF_FTX_NUM_CurrentBasis__c,
        AXF_FTX_DAT_DueDate__c,
        AXF_FTX_PKL_Status__c,
        AXF_FTX_PKL_ScheduleState__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE
        AXF_FTX_LKP_Schedule__c = :scheduleId
        AND AXF_FTX_NUM_Sequence__c = 1
    ];
    Integer schBefore = [
      SELECT COUNT()
      FROM AXF_OBJ_ScheduleChange__c
      WHERE AXF_SCH_LKP_Schedule__c = :scheduleId
    ];

    rollWindowForward(scheduleId, 3, true);

    Test.startTest();
    AXF_CLS_ScheduleReplenishmentScheduler.PassReport report = AXF_CLS_ScheduleReplenishmentScheduler.run();
    Test.stopTest();
    Assert.isNotNull(report.jobId, 'Havia cronograma devido para despachar');
    Assert.areEqual(1, report.dispatched, report.describe());

    Integer expected = sequencesInsideWindow(origin, 24, 3);
    Assert.isTrue(
      expected > before,
      'A janela rolou e havia o que materializar'
    );
    Assert.areEqual(
      expected,
      occurrencesOf(scheduleId),
      'Só as identidades elegíveis ausentes dentro da janela foram criadas'
    );
    Assert.areEqual(
      expected,
      [
        SELECT COUNT()
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE
          AXF_FTX_LKP_Schedule__c = :scheduleId
          AND AXF_FTX_NUM_Sequence__c >= 1
      ],
      'Uma linha por identidade, nenhuma duplicata'
    );

    AXF_OBJ_FinancialTransaction__c protectedAfter = [
      SELECT
        AXF_FTX_NUM_Magnitude__c,
        AXF_FTX_NUM_CurrentBasis__c,
        AXF_FTX_DAT_DueDate__c,
        AXF_FTX_PKL_Status__c,
        AXF_FTX_PKL_ScheduleState__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE
        AXF_FTX_LKP_Schedule__c = :scheduleId
        AND AXF_FTX_NUM_Sequence__c = 1
    ];
    Assert.areEqual(
      protectedBefore.AXF_FTX_NUM_Magnitude__c,
      protectedAfter.AXF_FTX_NUM_Magnitude__c,
      'A magnitude original de uma linha existente nunca é reescrita'
    );
    Assert.areEqual(
      protectedBefore.AXF_FTX_NUM_CurrentBasis__c,
      protectedAfter.AXF_FTX_NUM_CurrentBasis__c
    );
    Assert.areEqual(
      protectedBefore.AXF_FTX_DAT_DueDate__c,
      protectedAfter.AXF_FTX_DAT_DueDate__c
    );
    Assert.areEqual('PLANNED', protectedAfter.AXF_FTX_PKL_Status__c);
    Assert.areEqual('OPEN', protectedAfter.AXF_FTX_PKL_ScheduleState__c);

    AXF_OBJ_FinancialSchedule__c state = stateOf(scheduleId);
    Assert.areEqual(
      expected,
      state.AXF_FSC_NUM_CoverageSequence__c.intValue(),
      'A cobertura avança até o fim do prefixo contíguo contabilizado'
    );
    Assert.areEqual(
      2,
      state.AXF_FSC_NUM_FinancialVersion__c.intValue(),
      'Materialização é mudança de composição persistida: FinancialVersion avança'
    );
    Assert.areEqual(0, state.AXF_FSC_NUM_RetryCount__c.intValue());
    Assert.isNull(state.AXF_FSC_DT_NextAttemptAt__c);
    Assert.isNull(state.AXF_FSC_TXT_LastErrorCode__c);
    Assert.areEqual(
      0,
      state.AXF_FSC_NUM_RefreshCursor__c.intValue(),
      'RefreshCursor é cursor distinto e não participa da cobertura'
    );
    Assert.areEqual(
      schBefore,
      [
        SELECT COUNT()
        FROM AXF_OBJ_ScheduleChange__c
        WHERE AXF_SCH_LKP_Schedule__c = :scheduleId
      ],
      'A reposição é atualização de cache e NÃO grava recibo de comando de domínio'
    );
  }

  @IsTest
  static void theFirstPassReconcilesTheCoverageCursorByProduction() {
    Account account = holder('AXF103 reconciliacao');
    AXF_OBJ_FinancialSchedule__c schedule = schedule(account.Id, 24, 3);
    Id scheduleId = schedule.Id;
    Assert.areEqual(
      0,
      stateOf(scheduleId).AXF_FSC_NUM_CoverageSequence__c.intValue(),
      'A criação não movimenta o cursor'
    );
    rollWindowForward(scheduleId, 3, true);
    Integer before = occurrencesOf(scheduleId);

    ALT_CLS_FinancialScheduleService.ReplenishmentResult result = runPass(
      scheduleId,
      false
    );

    Assert.areEqual('NOOP', result.outcome, result.message);
    Assert.areEqual(0, result.createdCount);
    Assert.areEqual(
      0,
      result.previousCoverageSequence,
      'O plano pré-lock viu o cursor persistido em zero'
    );
    Assert.areEqual(
      before,
      result.coverageSequence,
      'O cursor reconciliado é recalculado pela produção a partir das identidades lidas sob o lock'
    );
    Assert.areEqual(
      0,
      ALT_CLS_FinancialScheduleService.lastPreLockCoverage,
      'O valor reconciliado não é o do plano pré-lock'
    );
    Assert.areEqual(
      before,
      stateOf(scheduleId).AXF_FSC_NUM_CoverageSequence__c.intValue()
    );
    Assert.areEqual(before, occurrencesOf(scheduleId), 'Nada foi criado');
  }

  @IsTest
  static void aGapBelowTheCursorIsCaughtUpWithoutDuplicationNorSkipping() {
    Account account = holder('AXF103 lacuna');
    AXF_OBJ_FinancialSchedule__c schedule = schedule(account.Id, 24, 3);
    Id scheduleId = schedule.Id;
    rollWindowForward(scheduleId, 4, true);
    runPass(scheduleId, false);
    Integer materialized = occurrencesOf(scheduleId);
    Assert.areEqual(
      materialized,
      stateOf(scheduleId).AXF_FSC_NUM_CoverageSequence__c.intValue()
    );

    // Simula a lacuna pós-tracking: uma ocorrência persistida não referenciada desapareceu abaixo
    // do cursor, que continua no valor já confirmado.
    deleteSequence(scheduleId, 2);
    Assert.areEqual(materialized - 1, occurrencesOf(scheduleId));

    // A borda da janela já não avança; só a verificação de LACUNA mantém o cronograma devido.
    List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem> due = AXF_CLS_ScheduleReplenishmentSelector.selectDue(
      25
    );
    Boolean selected = false;
    for (AXF_CLS_ScheduleReplenishmentSelector.WorkItem item : due) {
      selected = selected || item.scheduleId == scheduleId;
    }
    Assert.isTrue(
      selected,
      'Uma lacuna abaixo do cursor mantém o cronograma no conjunto devido'
    );

    ALT_CLS_FinancialScheduleService.ReplenishmentResult result = runPass(
      scheduleId,
      false
    );

    Assert.areEqual('GENERATED', result.outcome, result.message);
    Assert.areEqual(
      1,
      result.createdCount,
      'Catch-up limitado materializa a lacuna'
    );
    Assert.areEqual(2, result.firstCreatedSequence, 'Nunca pula sequência');
    Assert.areEqual(
      materialized,
      occurrencesOf(scheduleId),
      'Nunca duplica: a contagem volta ao valor anterior'
    );
    Assert.areEqual(
      4,
      [
        SELECT COUNT()
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE
          AXF_FTX_LKP_Schedule__c = :scheduleId
          AND AXF_FTX_NUM_Sequence__c <= 4
      ],
      'Todas as sequências de 1 a 4 existem uma única vez'
    );
    Assert.areEqual(
      materialized,
      stateOf(scheduleId).AXF_FSC_NUM_CoverageSequence__c.intValue(),
      'O cursor volta ao prefixo contíguo confirmado'
    );
  }

  /**
   * Item 5: uma linha CANCELLED dentro do prefixo coberto NÃO conta como identidade válida. Se
   * contasse, a contagem bateria com o esperado, o detector de lacuna nunca dispararia e o
   * cronograma sairia da fila com uma identidade ausente dentro do intervalo coberto.
   */
  @IsTest
  static void aCancelledIdentityInsideTheCoveredPrefixIsNotCountedAsPersisted() {
    Account account = holder('AXF103 cancelada');
    AXF_OBJ_FinancialSchedule__c schedule = schedule(account.Id, 24, 3);
    Id scheduleId = schedule.Id;
    rollWindowForward(scheduleId, 3, true);
    runPass(scheduleId, false);
    Integer coverage = stateOf(scheduleId)
      .AXF_FSC_NUM_CoverageSequence__c.intValue();
    Assert.isTrue(coverage >= 3, 'Há prefixo coberto: ' + coverage);

    // Controle: coberto e sem lacuna, o cronograma NÃO está devido.
    Boolean dueBefore = false;
    for (
      AXF_CLS_ScheduleReplenishmentSelector.WorkItem item : AXF_CLS_ScheduleReplenishmentSelector.selectDue(
        25
      )
    ) {
      dueBefore = dueBefore || item.scheduleId == scheduleId;
    }
    Assert.areEqual(
      false,
      dueBefore,
      'Coberto e contíguo sai do conjunto devido'
    );

    deleteSequence(scheduleId, 2);
    cancelSequence(scheduleId, 3);

    Assert.areEqual(
      coverage - 2,
      AXF_CLS_ScheduleReplenishmentSelector.persistedInRange(
        scheduleId,
        1,
        coverage
      ),
      'A contagem usa identidades VÁLIDAS: nem a apagada nem a cancelada contam'
    );

    Boolean dueAfter = false;
    for (
      AXF_CLS_ScheduleReplenishmentSelector.WorkItem item : AXF_CLS_ScheduleReplenishmentSelector.selectDue(
        25
      )
    ) {
      dueAfter = dueAfter || item.scheduleId == scheduleId;
    }
    Assert.isTrue(
      dueAfter,
      'A lacuna (e não a linha cancelada) mantém o cronograma no conjunto devido'
    );
  }

  /**
   * Item 7: a verificação de lacuna NÃO pode estar atrás do critério de borda. Um cronograma
   * simultaneamente atrasado e com lacuna abaixo do cursor tem o intervalo verificado do mesmo
   * jeito — sem isso, o intervalo coberto nunca é conferido como contíguo.
   */
  @IsTest
  static void aScheduleBehindTheWindowAlsoHasItsCoveredIntervalVerified() {
    Account account = holder('AXF103 atrasado com lacuna');
    AXF_OBJ_FinancialSchedule__c schedule = schedule(account.Id, 24, 3);
    Id scheduleId = schedule.Id;
    rollWindowForward(scheduleId, 3, true);
    runPass(scheduleId, false);
    // A janela volta a avançar E existe uma lacuna abaixo do cursor.
    deleteSequence(scheduleId, 2);
    rollWindowForward(scheduleId, 6, true);

    List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem> due = AXF_CLS_ScheduleReplenishmentSelector.selectDue(
      25
    );
    Assert.areEqual(1, due.size());
    Assert.isTrue(
      AXF_CLS_ScheduleReplenishmentSelector.lastTrace()
        .holeVerifiedScheduleIds.contains(scheduleId),
      'O intervalo coberto foi verificado mesmo com o cronograma atrasado'
    );
    Assert.areEqual(
      1,
      AXF_CLS_ScheduleReplenishmentSelector.lastTrace().holesFound,
      'A lacuna foi encontrada'
    );
  }

  @IsTest
  static void aDisabledScheduleGeneratesNothingAndIsRecordedAsSkipped() {
    Account account = holder('AXF103 desligado');
    AXF_OBJ_FinancialSchedule__c schedule = schedule(account.Id, 24, 2);
    Id scheduleId = schedule.Id;
    rollWindowForward(scheduleId, 4, false);
    Integer before = occurrencesOf(scheduleId);

    List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem> due = AXF_CLS_ScheduleReplenishmentSelector.selectDue(
      25
    );
    for (AXF_CLS_ScheduleReplenishmentSelector.WorkItem item : due) {
      Assert.isTrue(
        item.scheduleId != scheduleId,
        'Cronograma desligado está fora do conjunto devido'
      );
    }

    ALT_CLS_FinancialScheduleService.ReplenishmentResult result = ALT_CLS_FinancialScheduleService.replenishSchedule(
      request(scheduleId, false)
    );

    Assert.areEqual('SKIPPED', result.outcome, result.message);
    Assert.areEqual(
      null,
      result.errorCode,
      'Desligado é registrado como pulado, nunca como erro'
    );
    Assert.areEqual(false, result.terminal);
    Assert.areEqual(0, result.createdCount);
    Assert.areEqual(before, occurrencesOf(scheduleId), 'Nenhuma linha nova');
    Assert.areEqual(
      false,
      ALT_CLS_FinancialScheduleService.lastReplenishmentLockedHolder,
      'O caminho que retorna antes do lock relata que ele NÃO foi tomado'
    );

    AXF_OBJ_FinancialSchedule__c state = stateOf(scheduleId);
    Assert.isNull(state.AXF_FSC_TXT_LastErrorCode__c);
    Assert.areEqual(0, state.AXF_FSC_NUM_RetryCount__c.intValue());
    Assert.isNull(state.AXF_FSC_DT_NextAttemptAt__c);

    // Desligar nunca esconde a obrigação: a leitura continua contando o virtual.
    ALT_CLS_ScheduleProjection.ProjectionInput projectionInput = new ALT_CLS_ScheduleProjection.ProjectionInput();
    projectionInput.scheduleId = scheduleId;
    ALT_CLS_ScheduleProjection.ProjectionResult projection = ALT_CLS_FinancialScheduleService.readProjection(
      projectionInput
    );
    Assert.areEqual('OK', projection.outcome, projection.message);
    Assert.isTrue(
      projection.virtualCount > 0,
      'As obrigações futuras seguem visíveis como virtuais'
    );
    Assert.isTrue(projection.totalRemaining > 0);
  }

  @IsTest
  static void theTermIsCompletedWithoutCreatingAnythingBeyondIt() {
    Account account = holder('AXF103 termo');
    AXF_OBJ_FinancialSchedule__c schedule = schedule(account.Id, 3, 3);
    Id scheduleId = schedule.Id;
    rollWindowForward(scheduleId, 12, true);
    Integer before = occurrencesOf(scheduleId);

    ALT_CLS_FinancialScheduleService.ReplenishmentResult result = runPass(
      scheduleId,
      false
    );

    Assert.areEqual('COMPLETE', result.outcome, result.message);
    Assert.areEqual(0, result.createdCount);
    Assert.areEqual(true, result.termReached, 'A conclusão fica registrada');
    Assert.areEqual(
      before,
      occurrencesOf(scheduleId),
      'Nada é criado além do termo'
    );
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE
          AXF_FTX_LKP_Schedule__c = :scheduleId
          AND AXF_FTX_NUM_Sequence__c > 3
      ],
      'Sem linha fantasma depois do termo'
    );
    Assert.isNull(stateOf(scheduleId).AXF_FSC_TXT_LastErrorCode__c);
  }

  /**
   * Item 18: NENHUMA costura de produção semeia linhas concorrentes. O "worker vencedor" é a
   * própria produção — uma passagem real grava a identidade — e a colisão de chave única também é
   * real: a MESMA identidade é reinserida e o `Database.insert` falha com `DUPLICATE_VALUE`. A
   * releitura autorizada (`recoverFromCollision`) classifica REPLAY e reconcilia o cursor.
   *
   * A releitura é chamada diretamente porque o entrelaçamento — uma linha aparecendo ENTRE a
   * leitura autorizada e a escrita — não é produzível dentro de UMA transação de teste. O que o
   * teste injeta é o `DmlException` da colisão real; a classificação e o cursor são produção.
   */
  @IsTest
  static void anIdentityOccupiedWithTheCorrectKeyIsReplayAndTheCursorComesFromProduction() {
    Account account = holder('AXF103 dois workers');
    AXF_OBJ_FinancialSchedule__c schedule = schedule(account.Id, 24, 3);
    Id scheduleId = schedule.Id;
    rollWindowForward(scheduleId, 4, true);
    ALT_CLS_FinancialScheduleService.ReplenishmentResult first = runPass(
      scheduleId,
      false
    );
    Assert.areEqual('GENERATED', first.outcome, first.message);
    Assert.areEqual(1, rowsOfSequence(scheduleId, 4));
    Integer before = occurrencesOf(scheduleId);

    AXF_OBJ_FinancialTransaction__c winner = [
      SELECT
        Id,
        AXF_FTX_LKP_Account__c,
        AXF_FTX_LKP_Schedule__c,
        AXF_FTX_LKP_ScheduleDefinition__c,
        AXF_FTX_LKP_ScheduleReference__c,
        AXF_FTX_EXI_OccurrenceKey__c,
        AXF_FTX_EXI_ClientRequestId__c,
        AXF_FTX_NUM_CurrentBasis__c,
        AXF_FTX_NUM_ProjectionRevision__c,
        AXF_FTX_BOL_BasisFrozen__c,
        AXF_FTX_DAT_NominalDueDate__c,
        AXF_FTX_DAT_DueDate__c,
        AXF_FTX_DAT_PurchaseDate__c,
        AXF_FTX_PKL_ScheduleState__c,
        AXF_FTX_PKL_Status__c,
        AXF_FTX_PKL_PlanKind__c,
        AXF_FTX_NUM_Magnitude__c,
        AXF_FTX_CHK_IsEstimated__c,
        AXF_FTX_NUM_PrincipalPortion__c,
        AXF_FTX_NUM_InterestPortion__c,
        AXF_FTX_NUM_FeePortion__c,
        AXF_FTX_NUM_ClosingBalance__c,
        AXF_FTX_CHK_RoundingResidual__c,
        AXF_FTX_NUM_Sequence__c,
        AXF_FTX_PKL_Direction__c,
        AXF_FTX_TXT_CurrencyIsoCode__c,
        AXF_FTX_NUM_Version__c,
        AXF_FTX_TXT_ScheduleGroupKey__c,
        AXF_FTX_PKL_Modality__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE
        AXF_FTX_LKP_Schedule__c = :scheduleId
        AND AXF_FTX_NUM_Sequence__c = 4
      LIMIT 1
    ];
    System.DmlException collision;
    try {
      insert winner.clone(false, false, false, false);
      Assert.fail('A chave única da identidade precisa colidir');
    } catch (System.DmlException expected) {
      collision = expected;
    }
    Assert.areEqual(
      System.StatusCode.DUPLICATE_VALUE,
      collision.getDmlType(0),
      'A colisão é de chave única, não de outro defeito'
    );

    ALT_CLS_FinancialScheduleService.ReplenishmentResult result = new ALT_CLS_FinancialScheduleService.ReplenishmentResult();
    result.scheduleId = scheduleId;
    result.scheduleKey = schedule.AXF_FSC_EXI_ScheduleKey__c;
    ALT_CLS_FinancialScheduleService.ReplenishmentResult replayed = ALT_CLS_FinancialScheduleService.recoverFromCollision(
      request(scheduleId, false),
      new List<Integer>{ 4 },
      result,
      1,
      collision
    );

    Assert.areEqual('REPLAY', replayed.outcome, replayed.message);
    Assert.areEqual(true, replayed.replay, 'O perdedor retoma sem duplicar');
    Assert.areEqual(0, replayed.createdCount);
    Assert.areEqual(
      before,
      occurrencesOf(scheduleId),
      'Existe exatamente uma ocorrência por identidade'
    );
    Assert.areEqual(1, rowsOfSequence(scheduleId, 4));
    Assert.areEqual(
      4,
      stateOf(scheduleId).AXF_FSC_NUM_CoverageSequence__c.intValue(),
      'O cursor reconciliado é calculado pela produção, nunca pelo plano montado no teste'
    );
    Assert.areEqual(
      4,
      replayed.coverageSequence,
      'O desfecho autorizado devolve o cursor reconciliado'
    );
    Assert.isNull(stateOf(scheduleId).AXF_FSC_TXT_LastErrorCode__c);
  }

  // --- falha, retry e orçamento --------------------------------------------

  @IsTest
  static void aDmlFailureRollsBackEverythingAndTheFinalizerRecordsASanitizedCode() {
    Account account = holder('AXF103 falha dml');
    AXF_OBJ_FinancialSchedule__c schedule = schedule(account.Id, 24, 3);
    Id scheduleId = schedule.Id;
    rollWindowForward(scheduleId, 4, true);
    Integer before = occurrencesOf(scheduleId);

    AXF_CLS_ScheduleReplenishmentQueueable.chainLog = new List<AXF_CLS_ScheduleReplenishmentQueueable.ChainStep>();
    ALT_CLS_FinancialScheduleService.forcedReplenishmentFailureCode = ALT_CLS_ScheduleReplenishment.ERROR_DML;
    Boolean failedAsync = false;
    try {
      Test.startTest();
      System.enqueueJob(
        new AXF_CLS_ScheduleReplenishmentQueueable(workFor(scheduleId), 0)
      );
      try {
        Test.stopTest();
      } catch (Exception expected) {
        // A transação de geração aborta de propósito: o finalizador grava o metadado depois.
        failedAsync = true;
      }
    } finally {
      ALT_CLS_FinancialScheduleService.forcedReplenishmentFailureCode = null;
      AXF_CLS_ScheduleReplenishmentQueueable.chainLog = null;
    }

    Assert.isTrue(
      failedAsync,
      'A falha de DML é reportada como falha da passagem'
    );
    Assert.areEqual(
      before,
      occurrencesOf(scheduleId),
      'Nenhum efeito financeiro parcial persiste'
    );
    AXF_OBJ_FinancialSchedule__c state = stateOf(scheduleId);
    Assert.areEqual(
      'DML_FAILED',
      state.AXF_FSC_TXT_LastErrorCode__c,
      'O código persistido é higienizado, sem stack trace nem mensagem de DML'
    );
    Assert.areEqual(
      1,
      state.AXF_FSC_NUM_RetryCount__c.intValue(),
      'O metadado de falha foi gravado pelo finalizador, em transação separada'
    );
    Assert.isNotNull(
      state.AXF_FSC_DT_NextAttemptAt__c,
      'Há próximo horário de tentativa'
    );
  }

  @IsTest
  static void theFinalizerWalksTheLadderAndChainsTheRestOfTheBatch() {
    Account account = holder('AXF103 escada');
    AXF_OBJ_FinancialSchedule__c failing = schedule(
      account.Id,
      24,
      3,
      'axf103-ladder-a'
    );
    AXF_OBJ_FinancialSchedule__c later = schedule(
      account.Id,
      24,
      3,
      'axf103-ladder-b'
    );
    // A janela já rolou: existe trabalho elegível, e só o estado terminal o mantém fora do
    // despacho automático.
    rollWindowForward(failing.Id, 4, true);
    AXF_CLS_ScheduleReplenishmentQueueable.chainLog = new List<AXF_CLS_ScheduleReplenishmentQueueable.ChainStep>();
    AXF_CLS_ScheduleReplenishmentQueueable.ReplenishmentFailureException boom = new AXF_CLS_ScheduleReplenishmentQueueable.ReplenishmentFailureException(
      'falha recuperável'
    );
    boom.errorCode = 'DML_FAILED';

    try {
      // 1) Primeiro degrau: 1 minuto, e o cronograma falho volta para o FIM da fila.
      DateTime beforeFirst = System.now().addSeconds(-1);
      finalizerFor(failing.Id, later.Id)
        .execute(new FailedFinalizerContext(boom));
      DateTime afterFirst = System.now().addSeconds(1);
      Assert.areEqual(
        new List<Id>{ later.Id, failing.Id },
        chainedIds(),
        'O restante do lote segue antes da nova tentativa'
      );
      Assert.areEqual(
        new List<Integer>{ 1, 1 },
        ladderDelays(),
        'O degrau de 1 minuto é APLICADO no encadeamento atrasado, não só persistido'
      );
      AXF_OBJ_FinancialSchedule__c first = stateOf(failing.Id);
      Assert.areEqual(1, first.AXF_FSC_NUM_RetryCount__c.intValue());
      Assert.areEqual('DML_FAILED', first.AXF_FSC_TXT_LastErrorCode__c);
      assertLadderStep(
        beforeFirst,
        afterFirst,
        first.AXF_FSC_DT_NextAttemptAt__c,
        1,
        'Primeiro degrau'
      );

      // 2) Segundo degrau.
      AXF_CLS_ScheduleReplenishmentQueueable.chainLog = new List<AXF_CLS_ScheduleReplenishmentQueueable.ChainStep>();
      DateTime beforeSecond = System.now().addSeconds(-1);
      finalizerFor(failing.Id, later.Id)
        .execute(new FailedFinalizerContext(boom));
      DateTime afterSecond = System.now().addSeconds(1);
      Assert.areEqual(new List<Id>{ later.Id, failing.Id }, chainedIds());
      Assert.areEqual(
        new List<Integer>{ 5, 5 },
        ladderDelays(),
        'Segundo degrau aplicado no encadeamento: 5 minutos'
      );
      AXF_OBJ_FinancialSchedule__c second = stateOf(failing.Id);
      Assert.areEqual(2, second.AXF_FSC_NUM_RetryCount__c.intValue());
      assertLadderStep(
        beforeSecond,
        afterSecond,
        second.AXF_FSC_DT_NextAttemptAt__c,
        5,
        'Segundo degrau'
      );

      // 3) Terceiro degrau: 30 minutos não cabem no enqueue atrasado. Ele fica persistido em
      // NextAttemptAt e o cronograma NÃO volta para a fila desta passagem.
      AXF_CLS_ScheduleReplenishmentQueueable.chainLog = new List<AXF_CLS_ScheduleReplenishmentQueueable.ChainStep>();
      DateTime beforeThird = System.now().addSeconds(-1);
      finalizerFor(failing.Id, later.Id)
        .execute(new FailedFinalizerContext(boom));
      DateTime afterThird = System.now().addSeconds(1);
      Assert.areEqual(
        new List<Id>{ later.Id },
        chainedIds(),
        'O degrau de 30 minutos é retomado pela passagem do agendador, não por um timer inventado'
      );
      Assert.areEqual(
        new List<Integer>{ null },
        ladderDelays(),
        'Sem atraso aplicado: o degrau de 30 minutos não cabe no enqueue'
      );
      AXF_OBJ_FinancialSchedule__c third = stateOf(failing.Id);
      Assert.areEqual(3, third.AXF_FSC_NUM_RetryCount__c.intValue());
      assertLadderStep(
        beforeThird,
        afterThird,
        third.AXF_FSC_DT_NextAttemptAt__c,
        30,
        'Terceiro degrau'
      );

      // 4) Quarta falha: orçamento esgotado, nada é agendado na cadeia e o estado fica acionável
      // com uma JANELA DE REALARME declarada (item 12), não um limbo indefinido.
      AXF_CLS_ScheduleReplenishmentQueueable.chainLog = new List<AXF_CLS_ScheduleReplenishmentQueueable.ChainStep>();
      DateTime beforeExhausted = System.now().addSeconds(-1);
      finalizerFor(failing.Id, later.Id)
        .execute(new FailedFinalizerContext(boom));
      DateTime afterExhausted = System.now().addSeconds(1);
      Assert.areEqual(new List<Id>{ later.Id }, chainedIds());
      AXF_OBJ_FinancialSchedule__c exhausted = stateOf(failing.Id);
      Assert.areEqual(3, exhausted.AXF_FSC_NUM_RetryCount__c.intValue());
      assertLadderStep(
        beforeExhausted,
        afterExhausted,
        exhausted.AXF_FSC_DT_NextAttemptAt__c,
        24 * 60,
        'Realarme do orçamento esgotado'
      );
      Assert.areEqual(
        ALT_CLS_ScheduleReplenishment.ERROR_EXHAUSTED,
        exhausted.AXF_FSC_TXT_LastErrorCode__c,
        'O fim da escada é visível e não parece retomada pendente'
      );

      // 5) O estado esgotado bloqueia o DESPACHO AUTOMÁTICO e é retomável de forma DIRIGIDA.
      for (
        AXF_CLS_ScheduleReplenishmentSelector.WorkItem item : AXF_CLS_ScheduleReplenishmentSelector.selectDue(
          25
        )
      ) {
        Assert.isTrue(
          item.scheduleId != failing.Id,
          'O orçamento esgotado tira o cronograma do despacho automático'
        );
      }
      Assert.areEqual(
        3,
        stateOf(failing.Id).AXF_FSC_NUM_RetryCount__c.intValue(),
        'Nenhum orçamento é consumido por repetição automática'
      );

      // A recuperação dirigida limpa o estado quando a passagem volta a dar certo.
      ALT_CLS_FinancialScheduleService.ReplenishmentResult recovered = runPass(
        failing.Id,
        true
      );
      Assert.areEqual('GENERATED', recovered.outcome, recovered.message);
      AXF_OBJ_FinancialSchedule__c clean = stateOf(failing.Id);
      Assert.areEqual(0, clean.AXF_FSC_NUM_RetryCount__c.intValue());
      Assert.isNull(clean.AXF_FSC_TXT_LastErrorCode__c);
      Assert.isNull(clean.AXF_FSC_DT_NextAttemptAt__c);
    } finally {
      AXF_CLS_ScheduleReplenishmentQueueable.chainLog = null;
    }
  }

  private static List<Id> chainedIds() {
    List<Id> ids = new List<Id>();
    for (
      AXF_CLS_ScheduleReplenishmentQueueable.ChainStep step : AXF_CLS_ScheduleReplenishmentQueueable.chainLog
    ) {
      ids.add(step.scheduleId);
    }
    return ids;
  }

  /**
   * Item 12: quatro falhas transitórias NÃO podem desligar a reposição daquele cronograma para
   * sempre. O orçamento continua esgotado — nenhuma passagem automática o reinicia —, mas existe
   * uma janela declarada, e é isso que o operador observa.
   */
  @IsTest
  static void anExhaustedBudgetIsReArmedOncePerDeclaredWindowAndTheRecoveryPassResumesIt() {
    Account account = holder('AXF103 realarme');
    AXF_OBJ_FinancialSchedule__c schedule = schedule(account.Id, 24, 3);
    Id scheduleId = schedule.Id;
    rollWindowForward(scheduleId, 4, true);
    Integer before = occurrencesOf(scheduleId);

    DateTime failedAt = System.now();
    for (Integer attempt = 0; attempt < 4; attempt++) {
      ALT_CLS_FinancialScheduleService.recordReplenishmentFailure(
        scheduleId,
        ALT_CLS_ScheduleReplenishment.ERROR_DML,
        failedAt
      );
    }

    AXF_OBJ_FinancialSchedule__c exhausted = stateOf(scheduleId);
    Assert.areEqual(3, exhausted.AXF_FSC_NUM_RetryCount__c.intValue());
    Assert.areEqual(
      ALT_CLS_ScheduleReplenishment.ERROR_EXHAUSTED,
      exhausted.AXF_FSC_TXT_LastErrorCode__c
    );
    Assert.areEqual(
      failedAt.addHours(24),
      exhausted.AXF_FSC_DT_NextAttemptAt__c,
      'A janela do realarme é declarada e observável'
    );

    // O despacho automático nunca o alcança, nem antes nem depois da janela.
    for (
      AXF_CLS_ScheduleReplenishmentSelector.WorkItem item : AXF_CLS_ScheduleReplenishmentSelector.selectDue(
        25
      )
    ) {
      Assert.isTrue(
        item.scheduleId != scheduleId,
        'Fora do despacho automático'
      );
    }

    // Antes da janela: nada é realarmado.
    Assert.areEqual(
      0,
      AXF_CLS_ScheduleReplenishmentSelector.selectBlockedForRearm(
          failedAt.addHours(23),
          25
        )
        .size(),
      'O realarme espera a janela declarada'
    );
    AXF_CLS_ScheduleReplenishmentScheduler.PassReport early = AXF_CLS_ScheduleReplenishmentRecovery.run();
    Assert.isNull(
      early.jobId,
      'A passagem de recuperação não realarma antes da janela'
    );

    // Depois da janela: UMA tentativa, pela passagem de recuperação.
    Assert.areEqual(
      1,
      AXF_CLS_ScheduleReplenishmentSelector.selectBlockedForRearm(
          failedAt.addHours(25),
          25
        )
        .size(),
      'Passada a janela, o cronograma esgotado é realarmado'
    );
    serviceWrite(
      new AXF_OBJ_FinancialSchedule__c(
        Id = scheduleId,
        AXF_FSC_DT_NextAttemptAt__c = failedAt.addHours(-1)
      )
    );
    Test.startTest();
    AXF_CLS_ScheduleReplenishmentScheduler.PassReport pass = AXF_CLS_ScheduleReplenishmentRecovery.run();
    Test.stopTest();
    Assert.isNotNull(pass.jobId, pass.describe());

    AXF_OBJ_FinancialSchedule__c clean = stateOf(scheduleId);
    Assert.areEqual(0, clean.AXF_FSC_NUM_RetryCount__c.intValue());
    Assert.isNull(clean.AXF_FSC_TXT_LastErrorCode__c);
    Assert.isNull(clean.AXF_FSC_DT_NextAttemptAt__c);
    Assert.isTrue(
      occurrencesOf(scheduleId) > before,
      'A tentativa realarmada materializou a janela'
    );
  }

  /**
   * Item 41: o reenfileiramento ATRASADO precisa ser observado com o atraso aplicado, e o
   * fallback imediato precisa existir para orgs que recusam encadeamento atrasado.
   */
  @IsTest
  static void theDelayedEnqueueFallsBackToImmediateWhenThePlatformRefusesIt() {
    Account account = holder('AXF103 fallback');
    AXF_OBJ_FinancialSchedule__c failing = schedule(
      account.Id,
      24,
      3,
      'axf103-fallback-a'
    );
    AXF_OBJ_FinancialSchedule__c later = schedule(
      account.Id,
      24,
      3,
      'axf103-fallback-b'
    );
    rollWindowForward(failing.Id, 4, true);
    rollWindowForward(later.Id, 4, true);
    Integer before = occurrencesOf(later.Id);

    AXF_CLS_ScheduleReplenishmentQueueable.ReplenishmentFailureException boom = new AXF_CLS_ScheduleReplenishmentQueueable.ReplenishmentFailureException(
      'falha recuperável'
    );
    boom.errorCode = 'DML_FAILED';
    AXF_CLS_ScheduleReplenishmentQueueable.forcedDelayedRejectionsForTest = 1;
    try {
      Test.startTest();
      finalizerFor(failing.Id, later.Id)
        .execute(new FailedFinalizerContext(boom));
      Test.stopTest();
    } finally {
      AXF_CLS_ScheduleReplenishmentQueueable.forcedDelayedRejectionsForTest = 0;
    }

    Assert.areEqual(
      0,
      AXF_CLS_ScheduleReplenishmentQueueable.forcedDelayedRejectionsForTest,
      'O enfileiramento atrasado foi de fato tentado'
    );
    Assert.isTrue(
      AXF_CLS_ScheduleReplenishmentQueueable.lastTrace()
        .aborts.contains('DELAYED_ENQUEUE_FALLBACK'),
      'O fallback imediato foi usado e registrado'
    );
    Assert.isTrue(
      occurrencesOf(later.Id) > before,
      'O encadeamento imediato do fallback realmente executou'
    );
  }

  /**
   * Itens 11 e 45: a classificação de exceções REAIS no finalizador. Uma falha sintética não
   * distingue os ramos; um `DmlException`, um `QueryException`, um `CalendarException` e um
   * `MathException` de verdade distinguem.
   */
  @IsTest
  static void realExceptionTypesAreClassifiedByTheirOwnSanitizedCodes() {
    Account account = holder('AXF103 classificacao');
    AXF_OBJ_FinancialSchedule__c dmlSchedule = schedule(
      account.Id,
      24,
      3,
      'axf103-class-dml'
    );
    AXF_OBJ_FinancialSchedule__c querySchedule = schedule(
      account.Id,
      24,
      3,
      'axf103-class-query'
    );
    AXF_OBJ_FinancialSchedule__c calendarSchedule = schedule(
      account.Id,
      24,
      3,
      'axf103-class-calendar'
    );
    AXF_OBJ_FinancialSchedule__c formulaSchedule = schedule(
      account.Id,
      24,
      3,
      'axf103-class-formula'
    );
    AXF_OBJ_FinancialSchedule__c otherSchedule = schedule(
      account.Id,
      24,
      3,
      'axf103-class-other'
    );

    AXF_CLS_ScheduleReplenishmentQueueable.chainLog = new List<AXF_CLS_ScheduleReplenishmentQueueable.ChainStep>();
    try {
      finalizerForException(dmlSchedule.Id)
        .execute(new FailedFinalizerContext(realDmlException()));
      finalizerForException(querySchedule.Id)
        .execute(new FailedFinalizerContext(realQueryException()));
      finalizerForException(calendarSchedule.Id)
        .execute(new FailedFinalizerContext(realCalendarException()));
      finalizerForException(formulaSchedule.Id)
        .execute(new FailedFinalizerContext(realMathException()));
      finalizerForException(otherSchedule.Id)
        .execute(
          new FailedFinalizerContext(
            new ALT_CLS_ScheduleReplenishment.ReplenishmentException('x')
          )
        );
    } finally {
      AXF_CLS_ScheduleReplenishmentQueueable.chainLog = null;
    }

    Assert.areEqual(
      'DML_FAILED',
      stateOf(dmlSchedule.Id).AXF_FSC_TXT_LastErrorCode__c
    );
    Assert.areEqual(
      'QUERY_FAILED',
      stateOf(querySchedule.Id).AXF_FSC_TXT_LastErrorCode__c
    );
    Assert.areEqual(
      'CALENDAR_FAILED',
      stateOf(calendarSchedule.Id).AXF_FSC_TXT_LastErrorCode__c
    );
    Assert.areEqual(
      'FORMULA_FAILED',
      stateOf(formulaSchedule.Id).AXF_FSC_TXT_LastErrorCode__c
    );
    Assert.areEqual(
      'UNEXPECTED',
      stateOf(otherSchedule.Id).AXF_FSC_TXT_LastErrorCode__c
    );
    Assert.areEqual(
      1,
      stateOf(dmlSchedule.Id).AXF_FSC_NUM_RetryCount__c.intValue(),
      'Uma falha recuperável consome um degrau'
    );
  }

  /**
   * Item 45: código TERMINAL congela o orçamento — não consome tentativa e não agenda nada.
   */
  @IsTest
  static void aTerminalCodeFreezesTheBudgetWithoutConsumingAttempts() {
    Account account = holder('AXF103 terminal');
    AXF_OBJ_FinancialSchedule__c schedule = schedule(account.Id, 24, 3);
    Id scheduleId = schedule.Id;
    rollWindowForward(scheduleId, 4, true);

    ALT_CLS_FinancialScheduleService.FailureRecord record = ALT_CLS_FinancialScheduleService.recordReplenishmentFailure(
      scheduleId,
      ALT_CLS_ScheduleReplenishment.ERROR_PERMISSION_DENIED,
      System.now()
    );

    Assert.areEqual(true, record.terminal);
    Assert.areEqual(
      0,
      record.retryCount,
      'Uma condição permanente NÃO consome orçamento de retry'
    );
    Assert.isNull(record.nextAttemptAt, 'Nada é agendado automaticamente');
    Assert.areEqual(
      true,
      record.statePersisted,
      'O estado acionável foi gravado: ' + record.stateWriteFailure
    );
    AXF_OBJ_FinancialSchedule__c state = stateOf(scheduleId);
    Assert.areEqual(0, state.AXF_FSC_NUM_RetryCount__c.intValue());
    Assert.isNull(state.AXF_FSC_DT_NextAttemptAt__c);
    Assert.areEqual(
      ALT_CLS_ScheduleReplenishment.ERROR_PERMISSION_DENIED,
      state.AXF_FSC_TXT_LastErrorCode__c
    );
  }

  /**
   * Itens 2, 3 e 21: a passagem de recuperação é o ponto de entrada REAL do estado esgotado.
   */
  @IsTest
  static void directedRecoveryResumesANamedExhaustedScheduleAndNothingElse() {
    Account account = holder('AXF103 dirigida');
    AXF_OBJ_FinancialSchedule__c named = schedule(
      account.Id,
      24,
      3,
      'axf103-directed-a'
    );
    AXF_OBJ_FinancialSchedule__c other = schedule(
      account.Id,
      24,
      3,
      'axf103-directed-b'
    );
    rollWindowForward(named.Id, 4, true);
    rollWindowForward(other.Id, 4, true);
    DateTime failedAt = System.now();
    for (Integer attempt = 0; attempt < 4; attempt++) {
      ALT_CLS_FinancialScheduleService.recordReplenishmentFailure(
        named.Id,
        ALT_CLS_ScheduleReplenishment.ERROR_DML,
        failedAt
      );
      ALT_CLS_FinancialScheduleService.recordReplenishmentFailure(
        other.Id,
        ALT_CLS_ScheduleReplenishment.ERROR_DML,
        failedAt
      );
    }
    Integer before = occurrencesOf(named.Id);

    AXF_CLS_ScheduleReplenishmentScheduler.RecoveryResult result;
    Test.startTest();
    result = AXF_CLS_ScheduleReplenishmentScheduler.recover(
      new Set<Id>{ named.Id }
    );
    Test.stopTest();

    Assert.isNotNull(result.jobId, result.message);
    Assert.areEqual(1, result.accepted, result.message);
    Assert.areEqual(0, result.refused.size(), result.message);
    Assert.areEqual(
      0,
      stateOf(named.Id).AXF_FSC_NUM_RetryCount__c.intValue(),
      'A passagem dirigida retomou o cronograma nomeado'
    );
    Assert.isNull(stateOf(named.Id).AXF_FSC_TXT_LastErrorCode__c);
    Assert.isTrue(occurrencesOf(named.Id) > before);

    // O "ignorar o portão terminal" NÃO se estende a terceiros.
    Assert.areEqual(
      ALT_CLS_ScheduleReplenishment.ERROR_EXHAUSTED,
      stateOf(other.Id).AXF_FSC_TXT_LastErrorCode__c,
      'O cronograma NÃO nomeado continua esgotado'
    );
    for (
      AXF_CLS_ScheduleReplenishmentSelector.WorkItem item : AXF_CLS_ScheduleReplenishmentSelector.selectDue(
        25
      )
    ) {
      Assert.isTrue(
        item.scheduleId != other.Id,
        'O não nomeado continua fora do despacho'
      );
    }
  }

  @IsTest
  static void directedRecoveryRefusesSchedulesTheCallerCannotProveAuthorityOver() {
    Account account = holder('AXF103 autoridade dirigida');
    AXF_OBJ_FinancialSchedule__c schedule = schedule(account.Id, 24, 3);
    Id scheduleId = schedule.Id;
    rollWindowForward(scheduleId, 4, true);

    AXF_CLS_ScheduleReplenishmentScheduler.RecoveryResult truncated;
    Integer previousLimit = AXF_CLS_ScheduleReplenishmentSelector.authorizedContextLimitForTest;
    AXF_CLS_ScheduleReplenishmentSelector.authorizedContextLimitForTest = 1;
    try {
      truncated = AXF_CLS_ScheduleReplenishmentScheduler.recover(
        new Set<Id>{ scheduleId }
      );
    } finally {
      AXF_CLS_ScheduleReplenishmentSelector.authorizedContextLimitForTest = previousLimit;
    }
    Assert.isNull(
      truncated.jobId,
      'Sem poder CONCLUIR a autoridade, nada é enfileirado'
    );
    Assert.areEqual(0, truncated.accepted);
    Assert.areEqual(1, truncated.refused.size());
    Assert.areEqual(scheduleId, truncated.refused[0]);

    AXF_CLS_ScheduleReplenishmentScheduler.RecoveryResult unknown = AXF_CLS_ScheduleReplenishmentScheduler.recover(
      new Set<Id>{ scheduleId, null }
    );
    Assert.areEqual(1, unknown.accepted);
    Assert.areEqual(
      0,
      unknown.refused.size(),
      'O Id nulo não é um cronograma nomeado e não é relatado como recusa'
    );
  }

  // --- acesso e autorização ------------------------------------------------

  @IsTest
  static void aPrincipalWithoutVisibilityIsPermanentAndConsumesNoBudget() {
    Account account = holder('AXF103 invisivel');
    AXF_OBJ_FinancialSchedule__c schedule = schedule(account.Id, 24, 2);
    Id scheduleId = schedule.Id;
    rollWindowForward(scheduleId, 4, true);
    Integer before = occurrencesOf(scheduleId);
    Id holderId = schedule.AXF_FSC_LKP_Account__c;
    ALT_CLS_FinancialScheduleService.authorizedOverride = null;

    User stranger = strangerUser();
    Integer sharedCount = -1;
    Integer privilegedCount = -1;
    ALT_CLS_FinancialScheduleService.ReplenishmentResult denied;
    System.runAs(stranger) {
      // Verificação de PLATAFORMA que sustenta a decisão de projeto: SYSTEM_MODE desliga apenas
      // permissão de objeto e FLS; quem governa visibilidade de registro é a keyword da classe.
      sharedCount = new SharedScopedReader().countSchedules();
      privilegedCount = new PrivilegedScopedReader().countSchedules();

      // O caminho privilegiado declarado do job RESOLVE o trabalho mesmo sem visibilidade — é ele
      // que impede a funcionalidade de ficar muda em produção.
      List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem> work = workFor(
        scheduleId
      );
      Assert.areEqual(1, work.size());
      Assert.areEqual(holderId, work[0].holderId);

      ALT_CLS_FinancialScheduleService.ReplenishmentRequest deniedRequest = new ALT_CLS_FinancialScheduleService.ReplenishmentRequest();
      deniedRequest.scheduleId = scheduleId;
      deniedRequest.holderId = holderId;
      denied = ALT_CLS_FinancialScheduleService.replenishSchedule(
        deniedRequest
      );
    }

    Assert.areEqual(
      0,
      sharedCount,
      'SYSTEM_MODE em classe with sharing não amplia visibilidade de registro'
    );
    Assert.areEqual(
      1,
      privilegedCount,
      'O caminho privilegiado declarado enxerga o trabalho'
    );
    Assert.areEqual('FORBIDDEN', denied.outcome, denied.message);
    Assert.areEqual(
      ALT_CLS_ScheduleReplenishment.ERROR_PRINCIPAL_WITHOUT_VISIBILITY,
      denied.errorCode
    );
    Assert.areEqual(true, denied.terminal, 'É desfecho PERMANENTE');
    Assert.areEqual(0, denied.createdCount);
    Assert.areEqual(before, occurrencesOf(scheduleId), 'Nada é gerado');

    AXF_OBJ_FinancialSchedule__c state = stateOf(scheduleId);
    Assert.areEqual(
      0,
      state.AXF_FSC_NUM_RetryCount__c.intValue(),
      'Nenhum orçamento de retry é consumido'
    );
    Assert.isNull(
      state.AXF_FSC_DT_NextAttemptAt__c,
      'Desfecho permanente e não retomável: nada é agendado'
    );
    Assert.areEqual(
      ALT_CLS_ScheduleReplenishment.ERROR_PRINCIPAL_WITHOUT_VISIBILITY,
      state.AXF_FSC_TXT_LastErrorCode__c,
      'O estado acionável é registrado mesmo sem o principal enxergar a linha'
    );
    Assert.areEqual(
      true,
      denied.statePersisted,
      'O registro privilegiado devolveu o desfecho: ' + denied.stateWriteFailure
    );
    for (
      AXF_CLS_ScheduleReplenishmentSelector.WorkItem item : AXF_CLS_ScheduleReplenishmentSelector.selectDue(
        25
      )
    ) {
      Assert.isTrue(
        item.scheduleId != scheduleId,
        'Um estado permanente sai do conjunto devido em vez de morrer de fome a fila'
      );
    }
  }

  /**
   * Verificação de PLATAFORMA que sustenta o SEGUNDO escritor: DML também respeita o acesso ao
   * registro. Sem o teste que SEPARA as duas hipóteses, a classe privilegiada ficaria sem
   * evidência — se a afirmação fosse falsa, ela seria supérflua e nada acusaria.
   */
  @IsTest
  static void systemModeDmlRespectsRecordAccessSoThePrivilegedWriterIsNecessary() {
    Account account = holder('AXF103 dml invisivel');
    AXF_OBJ_FinancialSchedule__c schedule = schedule(account.Id, 24, 2);
    Id scheduleId = schedule.Id;
    ALT_CLS_FinancialScheduleService.authorizedOverride = null;
    User stranger = strangerUser();

    Boolean sharedUpdated = false;
    Boolean privilegedUpdated = false;
    System.runAs(stranger) {
      ALT_CLS_FinancialScheduleService.writing = true;
      try {
        sharedUpdated = new SharedScopedWriter().updateRetry(scheduleId, 2);
        privilegedUpdated = new PrivilegedScopedWriter()
          .updateRetry(scheduleId, 2);
      } finally {
        ALT_CLS_FinancialScheduleService.writing = false;
      }
    }
    Assert.areEqual(
      false,
      sharedUpdated,
      'DML em linha invisível FALHA numa classe with sharing, mesmo em SYSTEM_MODE'
    );
    Assert.areEqual(
      true,
      privilegedUpdated,
      'A MESMA DML passa no caminho privilegiado declared without sharing'
    );
    Assert.areEqual(
      2,
      stateOf(scheduleId).AXF_FSC_NUM_RetryCount__c.intValue(),
      'A gravação privilegiada é a que persistiu'
    );
    serviceWrite(
      new AXF_OBJ_FinancialSchedule__c(
        Id = scheduleId,
        AXF_FSC_NUM_RetryCount__c = 0
      )
    );
  }

  @IsTest
  static void aPrincipalWithoutPermissionGeneratesNothing() {
    User gestor = gestorUser();
    Id holderId;
    Id scheduleId;
    System.runAs(gestor) {
      Account account = new Account(
        Name = 'AXF103 sem permissao de ocorrencia',
        RecordTypeId = businessRecordType()
      );
      insert account;
      holderId = account.Id;
      ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
        holderId
      };
      scheduleId = schedule(holderId, 24, 2).Id;
    }
    rollWindowForward(scheduleId, 4, true);
    Integer before = occurrencesOf(scheduleId);

    ALT_CLS_FinancialScheduleService.ReplenishmentResult denied;
    System.runAs(gestor) {
      Assert.areEqual(
        false,
        AXF_OBJ_FinancialTransaction__c.SObjectType.getDescribe()
          .isCreateable(),
        'O principal deste teste não tem permissão de criação da ocorrência'
      );
      ALT_CLS_FinancialScheduleService.ReplenishmentRequest deniedRequest = new ALT_CLS_FinancialScheduleService.ReplenishmentRequest();
      deniedRequest.scheduleId = scheduleId;
      deniedRequest.holderId = holderId;
      denied = ALT_CLS_FinancialScheduleService.replenishSchedule(
        deniedRequest
      );
    }

    Assert.areEqual('FORBIDDEN', denied.outcome, denied.message);
    Assert.areEqual(
      ALT_CLS_ScheduleReplenishment.ERROR_PERMISSION_DENIED,
      denied.errorCode
    );
    Assert.areEqual(true, denied.terminal);
    Assert.areEqual(0, denied.createdCount, 'Nada é gerado');
    Assert.areEqual(before, occurrencesOf(scheduleId));
    Assert.areEqual(
      0,
      stateOf(scheduleId).AXF_FSC_NUM_RetryCount__c.intValue()
    );
    Assert.areEqual(
      true,
      denied.statePersisted,
      'O registro privilegiado do estado acionável aconteceu: ' +
      denied.stateWriteFailure
    );
    Assert.areEqual(
      ALT_CLS_ScheduleReplenishment.ERROR_PERMISSION_DENIED,
      stateOf(scheduleId).AXF_FSC_TXT_LastErrorCode__c,
      'O estado acionável fica persistido para o operador'
    );
    Assert.isNull(stateOf(scheduleId).AXF_FSC_DT_NextAttemptAt__c);
    for (
      AXF_CLS_ScheduleReplenishmentSelector.WorkItem item : AXF_CLS_ScheduleReplenishmentSelector.selectDue(
        25
      )
    ) {
      Assert.isTrue(
        item.scheduleId != scheduleId,
        'O cronograma sai do conjunto devido em vez de parecer parado'
      );
    }
  }

  /**
   * Item 14: o teto DIFERIDO de 200 titulares do serviço de contextos não é "principal sem
   * visibilidade". O MESMO cenário, lido com o teto efetivo no tamanho observado e com o teto real,
   * produz desfechos DIFERENTES — e só o segundo é permanente e bloqueante de despacho.
   */
  @IsTest
  static void anInconclusiveAuthorityReadIsNotAPermanentBlockingState() {
    Account account = holder('AXF103 autoridade inconclusiva');
    Account other = holder('AXF103 outro titular visivel');
    AXF_OBJ_FinancialSchedule__c schedule = schedule(account.Id, 24, 3);
    Id scheduleId = schedule.Id;
    rollWindowForward(scheduleId, 4, true);
    Integer before = occurrencesOf(scheduleId);
    ALT_CLS_FinancialScheduleService.authorizedOverride = null;
    // A leitura de contextos passa a devolver OUTRO titular: o do cronograma não está na página.
    AXF_CLS_AuthorizedContextService.contextsOverride = [
      SELECT Id, Name, IsPersonAccount, RecordType.DeveloperName
      FROM Account
      WHERE Id = :other.Id
    ];
    Integer previousLimit = ALT_CLS_FinancialScheduleService.authorizedContextLimitForTest;
    ALT_CLS_FinancialScheduleService.ReplenishmentResult inconclusive;
    try {
      ALT_CLS_FinancialScheduleService.authorizedContextLimitForTest = 1;
      inconclusive = runPass(scheduleId, false);
    } finally {
      ALT_CLS_FinancialScheduleService.authorizedContextLimitForTest = previousLimit;
    }

    Assert.areEqual(
      ALT_CLS_ScheduleReplenishment.ERROR_AUTHORITY_TRUNCATED,
      inconclusive.errorCode,
      inconclusive.message
    );
    Assert.areEqual(
      false,
      inconclusive.terminal,
      'Leitura inconclusiva NÃO é desfecho permanente'
    );
    Assert.areEqual(0, inconclusive.createdCount);
    Assert.areEqual(before, occurrencesOf(scheduleId));
    Assert.isNull(
      terminalErrorCodeOf(scheduleId),
      'Nenhum estado bloqueante é gravado por uma limitação de LEITURA'
    );
    Assert.areEqual(
      true,
      isDue(scheduleId),
      'O inconclusivo continua no conjunto devido'
    );

    // O MESMO cenário com o teto REAL do serviço: agora é ausência de visibilidade de fato, e o
    // desfecho é permanente e bloqueante.
    ALT_CLS_FinancialScheduleService.ReplenishmentResult denied;
    try {
      ALT_CLS_FinancialScheduleService.authorizedContextLimitForTest = ALT_CLS_FinancialScheduleService.AUTHORIZED_CONTEXT_LIMIT;
      denied = runPass(scheduleId, false);
    } finally {
      ALT_CLS_FinancialScheduleService.authorizedContextLimitForTest = previousLimit;
      AXF_CLS_AuthorizedContextService.contextsOverride = null;
    }

    Assert.areEqual(
      ALT_CLS_ScheduleReplenishment.ERROR_PRINCIPAL_WITHOUT_VISIBILITY,
      denied.errorCode,
      denied.message
    );
    Assert.areEqual(
      true,
      denied.terminal,
      'Ausência real de visibilidade é permanente'
    );
    Assert.areEqual(
      ALT_CLS_ScheduleReplenishment.ERROR_PRINCIPAL_WITHOUT_VISIBILITY,
      terminalErrorCodeOf(scheduleId)
    );
    Assert.areEqual(
      false,
      isDue(scheduleId),
      'Um estado permanente sai do conjunto devido; o inconclusivo não'
    );
  }

  /** Código de erro persistido, lido por um caminho que enxerga a linha em qualquer cenário. */
  private static String terminalErrorCodeOf(Id scheduleId) {
    return AXF_CLS_ScheduleReplenishmentStateWriter.read(scheduleId)
      .AXF_FSC_TXT_LastErrorCode__c;
  }

  /**
   * Item 1: nada revalidava revisão e ponteiros ATIVOS sob o lock. Sem esta rechecagem, uma
   * definição confirmada entre a leitura e o lock produziria linhas apontando para a definição
   * antiga sob a etiqueta da revisão nova, sem STALE.
   */
  @IsTest
  static void aRevisionDriftBetweenTheReadAndTheLockIsStaleAndWritesNothing() {
    Account account = holder('AXF103 deriva de revisao');
    AXF_OBJ_FinancialSchedule__c schedule = schedule(account.Id, 24, 3);
    Id scheduleId = schedule.Id;
    rollWindowForward(scheduleId, 4, true);
    Integer before = occurrencesOf(scheduleId);
    Integer coverage = stateOf(scheduleId)
      .AXF_FSC_NUM_CoverageSequence__c.intValue();

    ALT_CLS_FinancialScheduleService.ReplenishmentResult result;
    ALT_CLS_FinancialScheduleService.lockedRevisionOverrideForTest =
      stateOf(scheduleId).AXF_FSC_NUM_ProjectionRevision__c.longValue() + 1;
    try {
      result = runPass(scheduleId, false);
    } finally {
      ALT_CLS_FinancialScheduleService.lockedRevisionOverrideForTest = null;
    }

    Assert.areEqual('FAILED', result.outcome, result.message);
    Assert.areEqual(
      ALT_CLS_ScheduleReplenishment.ERROR_PROJECTION_STALE,
      result.errorCode
    );
    Assert.areEqual(
      false,
      result.terminal,
      'Deriva de revisão é recuperável: a passagem relê com recuo limitado'
    );
    Assert.areEqual(0, result.createdCount);
    Assert.areEqual(before, occurrencesOf(scheduleId), 'Nada foi gravado');
    Assert.areEqual(
      coverage,
      stateOf(scheduleId).AXF_FSC_NUM_CoverageSequence__c.intValue(),
      'O cursor não avançou sobre uma leitura que não é a vigente'
    );
    Assert.isNull(stateOf(scheduleId).AXF_FSC_TXT_LastErrorCode__c);
  }

  @IsTest
  static void anActivePointerDriftBetweenTheReadAndTheLockIsStaleAndWritesNothing() {
    Account account = holder('AXF103 deriva de ponteiro');
    AXF_OBJ_FinancialSchedule__c schedule = schedule(
      account.Id,
      24,
      3,
      'axf103-drift-a'
    );
    AXF_OBJ_FinancialSchedule__c other = schedule(
      account.Id,
      24,
      3,
      'axf103-drift-b'
    );
    rollWindowForward(schedule.Id, 4, true);
    Integer before = occurrencesOf(schedule.Id);

    ALT_CLS_FinancialScheduleService.ReplenishmentResult result;
    ALT_CLS_FinancialScheduleService.lockedDefinitionOverrideForTest = other.AXF_FSC_LKP_ActiveDefinition__c;
    try {
      result = runPass(schedule.Id, false);
    } finally {
      ALT_CLS_FinancialScheduleService.lockedDefinitionOverrideForTest = null;
    }

    Assert.areEqual(
      ALT_CLS_ScheduleReplenishment.ERROR_PROJECTION_STALE,
      result.errorCode,
      result.message
    );
    Assert.areEqual(0, result.createdCount);
    Assert.areEqual(before, occurrencesOf(schedule.Id), 'Nada foi gravado');
  }

  /**
   * Itens 12 e 13: cada desfecho de bloqueio da leitura vira um código PRÓPRIO e acionável, e
   * nenhum deles consome orçamento de retry.
   */
  @IsTest
  static void eachProjectionBlockingOutcomeHasItsOwnPersistedCode() {
    Account account = holder('AXF103 codigos de bloqueio');
    AXF_OBJ_FinancialSchedule__c ambiguous = schedule(
      account.Id,
      24,
      3,
      'axf103-block-amb'
    );
    AXF_OBJ_FinancialSchedule__c unsupported = schedule(
      account.Id,
      24,
      3,
      'axf103-block-uns'
    );
    AXF_OBJ_FinancialSchedule__c invalid = schedule(
      account.Id,
      24,
      3,
      'axf103-block-inv'
    );
    AXF_OBJ_FinancialSchedule__c missing = schedule(
      account.Id,
      24,
      3,
      'axf103-block-mis'
    );
    for (
      AXF_OBJ_FinancialSchedule__c candidate : new List<AXF_OBJ_FinancialSchedule__c>{
        ambiguous,
        unsupported,
        invalid,
        missing
      }
    ) {
      rollWindowForward(candidate.Id, 4, true);
    }

    assertBlockingCode(
      ambiguous.Id,
      ALT_CLS_ScheduleProjection.OUTCOME_AMBIGUOUS,
      ALT_CLS_ScheduleReplenishment.ERROR_PROJECTION_AMBIGUOUS
    );
    assertBlockingCode(
      unsupported.Id,
      ALT_CLS_ScheduleProjection.OUTCOME_UNSUPPORTED,
      ALT_CLS_ScheduleReplenishment.ERROR_PROJECTION_UNSUPPORTED
    );
    assertBlockingCode(
      invalid.Id,
      ALT_CLS_ScheduleProjection.OUTCOME_INVALID,
      ALT_CLS_ScheduleReplenishment.ERROR_PROJECTION_INVALID
    );
    // Projeção NULA: sem resultado não há o que materializar nem como decidir.
    ALT_CLS_ScheduleProjection.ProjectionResult nullResult = new ALT_CLS_ScheduleProjection.ProjectionResult();
    nullResult.outcome = ALT_CLS_ScheduleProjection.OUTCOME_INVALID;
    ALT_CLS_FinancialScheduleService.projectionOverrideForTest = nullResult;
    ALT_CLS_FinancialScheduleService.forceNullProjectionForTest = true;
    ALT_CLS_FinancialScheduleService.ReplenishmentResult nullPass;
    try {
      nullPass = runPass(missing.Id, false);
    } finally {
      ALT_CLS_FinancialScheduleService.forceNullProjectionForTest = false;
      ALT_CLS_FinancialScheduleService.projectionOverrideForTest = null;
    }
    Assert.areEqual(
      ALT_CLS_ScheduleReplenishment.ERROR_PROJECTION_MISSING,
      nullPass.errorCode,
      nullPass.message
    );
    Assert.areEqual(
      ALT_CLS_ScheduleReplenishment.ERROR_PROJECTION_MISSING,
      stateOf(missing.Id).AXF_FSC_TXT_LastErrorCode__c
    );
  }

  private static void assertBlockingCode(
    Id scheduleId,
    String projectionOutcome,
    String expectedCode
  ) {
    ALT_CLS_ScheduleProjection.ProjectionResult forced = new ALT_CLS_ScheduleProjection.ProjectionResult();
    forced.outcome = projectionOutcome;
    forced.scheduleId = scheduleId;
    ALT_CLS_FinancialScheduleService.projectionOverrideForTest = forced;
    ALT_CLS_FinancialScheduleService.ReplenishmentResult result;
    try {
      result = runPass(scheduleId, false);
    } finally {
      ALT_CLS_FinancialScheduleService.projectionOverrideForTest = null;
    }
    Assert.areEqual(expectedCode, result.errorCode, result.message);
    Assert.areEqual(true, result.terminal, expectedCode + ' é permanente');
    Assert.areEqual(
      expectedCode,
      stateOf(scheduleId).AXF_FSC_TXT_LastErrorCode__c,
      'O operador vê o código próprio do desfecho'
    );
    Assert.isNull(
      stateOf(scheduleId).AXF_FSC_DT_NextAttemptAt__c,
      'Bloqueio de leitura não agenda tentativa'
    );
  }

  /**
   * Item 11: um estouro numérico determinístico da fórmula aprovada é PERMANENTE e IMEDIATO — não
   * pode queimar as três tentativas e virar RETRY_EXHAUSTED por engano.
   */
  @IsTest
  static void aNumericalOverflowOnTheAuthorizedReadIsPermanentAndImmediate() {
    Account account = holder('AXF103 estouro');
    AXF_OBJ_FinancialSchedule__c schedule = schedule(account.Id, 24, 3);
    Id scheduleId = schedule.Id;
    rollWindowForward(scheduleId, 4, true);
    Integer before = occurrencesOf(scheduleId);

    String persistedCode;
    ALT_CLS_FinancialScheduleService.ReplenishmentResult result;
    ALT_CLS_FinancialScheduleService.authorizedReadFailureForTest = realMathException();
    try {
      result = runPass(scheduleId, false);
      persistedCode = stateOf(scheduleId).AXF_FSC_TXT_LastErrorCode__c;
    } finally {
      ALT_CLS_FinancialScheduleService.authorizedReadFailureForTest = null;
    }

    Assert.areEqual(
      ALT_CLS_ScheduleReplenishment.ERROR_FORMULA,
      result.errorCode,
      result.message
    );
    Assert.areEqual(true, result.terminal);
    Assert.areEqual(ALT_CLS_ScheduleReplenishment.ERROR_FORMULA, persistedCode);
    Assert.areEqual(
      0,
      stateOf(scheduleId).AXF_FSC_NUM_RetryCount__c.intValue(),
      'O estouro é imediato: nenhuma tentativa é consumida'
    );
    Assert.isNull(stateOf(scheduleId).AXF_FSC_DT_NextAttemptAt__c);
    Assert.areEqual(before, occurrencesOf(scheduleId));
  }

  /**
   * Item 47: uma gravação RECUSADA do estado acionável não pode passar em silêncio. O desfecho
   * terminal existe, o registro não, e o operador precisa ver isso — e o cronograma continua no
   * conjunto devido em vez de parecer parado.
   */
  @IsTest
  static void aRefusedStateWriteLeavesAConsultableTraceAndKeepsTheScheduleDue() {
    Account account = holder('AXF103 registro recusado');
    AXF_OBJ_FinancialSchedule__c schedule = schedule(account.Id, 24, 3);
    Id scheduleId = schedule.Id;
    rollWindowForward(scheduleId, 4, true);

    ALT_CLS_ScheduleProjection.ProjectionResult forced = new ALT_CLS_ScheduleProjection.ProjectionResult();
    forced.outcome = ALT_CLS_ScheduleProjection.OUTCOME_INVALID;
    forced.scheduleId = scheduleId;
    ALT_CLS_FinancialScheduleService.projectionOverrideForTest = forced;
    AXF_CLS_ScheduleReplenishmentStateWriter.forcedRefusalsForTest = 1;
    ALT_CLS_FinancialScheduleService.ReplenishmentResult result;
    try {
      result = runPass(scheduleId, false);
    } finally {
      ALT_CLS_FinancialScheduleService.projectionOverrideForTest = null;
      AXF_CLS_ScheduleReplenishmentStateWriter.forcedRefusalsForTest = 0;
    }

    Assert.areEqual(
      ALT_CLS_ScheduleReplenishment.ERROR_PROJECTION_INVALID,
      result.errorCode
    );
    Assert.areEqual(
      false,
      result.statePersisted,
      'A gravação foi recusada e o desfecho NÃO esconde isso'
    );
    Assert.areEqual(
      AXF_CLS_ScheduleReplenishmentStateWriter.REASON_FORCED,
      result.stateWriteFailure
    );
    Assert.isTrue(
      result.message.contains('NÃO foi gravado'),
      'O rastro é consultável no próprio desfecho: ' + result.message
    );
    Assert.isNull(
      stateOf(scheduleId).AXF_FSC_TXT_LastErrorCode__c,
      'Nada foi persistido de fato'
    );

    Boolean stillDue = false;
    for (
      AXF_CLS_ScheduleReplenishmentSelector.WorkItem item : AXF_CLS_ScheduleReplenishmentSelector.selectDue(
        25
      )
    ) {
      stillDue = stillDue || item.scheduleId == scheduleId;
    }
    Assert.isTrue(
      stillDue,
      'Sem o estado gravado o cronograma continua no conjunto devido'
    );
  }

  /**
   * Itens 2 e 15: o lock do titular precede a PRIMEIRA leitura e a PRIMEIRA DML descendente, e o
   * campo de observação relata o desfecho REAL do lock.
   */
  @IsTest
  static void theHolderLockPrecedesTheDescendantReadsAndTheDescendantDml() {
    Account account = holder('AXF103 ordem do lock');
    AXF_OBJ_FinancialSchedule__c schedule = schedule(account.Id, 24, 3);
    Id scheduleId = schedule.Id;
    rollWindowForward(scheduleId, 4, true);

    ALT_CLS_FinancialScheduleService.lockTraceForTest = new List<String>();
    try {
      runPass(scheduleId, false);
      Assert.areEqual(
        true,
        ALT_CLS_FinancialScheduleService.lastReplenishmentLockedHolder,
        'O campo relata o desfecho REAL do lock'
      );
      List<String> trace = ALT_CLS_FinancialScheduleService.lockTraceForTest;
      Assert.areEqual(
        'HOLDER_LOCK',
        trace[0],
        'O primeiro passo do caminho é o lock do titular: ' + trace
      );
      Assert.isTrue(
        trace.indexOf('LOCKED_ROOT_READ') > 0,
        'A releitura da raiz acontece DEPOIS do lock: ' + trace
      );
      Assert.isTrue(
        trace.indexOf('IDENTITIES_READ') > trace.indexOf('HOLDER_LOCK'),
        'A leitura de identidades descendente acontece depois do lock: ' + trace
      );
    } finally {
      ALT_CLS_FinancialScheduleService.lockTraceForTest = null;
    }

    // O caminho do metadado de falha adquire o lock na MESMA ordem.
    AXF_OBJ_FinancialSchedule__c before = stateOf(scheduleId);
    ALT_CLS_FinancialScheduleService.recordReplenishmentFailure(
      scheduleId,
      ALT_CLS_ScheduleReplenishment.ERROR_DML,
      System.now()
    );
    Assert.areEqual(
      true,
      AXF_CLS_ScheduleReplenishmentStateWriter.lockedHolderBeforeWrite(),
      'O escritor do estado operacional adquire o lock do titular antes da DML'
    );
    Assert.areEqual(
      true,
      AXF_CLS_ScheduleReplenishmentStateWriter.wasWritten()
    );
    Assert.areEqual(
      1,
      stateOf(scheduleId).AXF_FSC_NUM_RetryCount__c.intValue(),
      'O metadado operacional foi gravado'
    );
  }

  /**
   * Item 44: a exceção estreita do handler só libera o que o worker privilegiado grava. Fora do
   * worker, DML direta sobre os TRÊS campos operacionais é recusada.
   */
  @IsTest
  static void directDmlOnTheOperationalStateFieldsIsRefusedOutsideTheWorker() {
    Account account = holder('AXF103 dml direta');
    AXF_OBJ_FinancialSchedule__c schedule = schedule(account.Id, 24, 3);
    Id scheduleId = schedule.Id;

    Assert.isFalse(
      Database.update(
          new AXF_OBJ_FinancialSchedule__c(
            Id = scheduleId,
            AXF_FSC_NUM_RetryCount__c = 2
          ),
          false
        )
        .isSuccess(),
      'O contador de tentativas não é editável diretamente'
    );
    Assert.isFalse(
      Database.update(
          new AXF_OBJ_FinancialSchedule__c(
            Id = scheduleId,
            AXF_FSC_DT_NextAttemptAt__c = System.now()
          ),
          false
        )
        .isSuccess(),
      'O próximo horário de tentativa não é editável diretamente'
    );
    Assert.isFalse(
      Database.update(
          new AXF_OBJ_FinancialSchedule__c(
            Id = scheduleId,
            AXF_FSC_TXT_LastErrorCode__c = 'DML_FAILED'
          ),
          false
        )
        .isSuccess(),
      'O código de erro não é editável diretamente'
    );

    // Controle: os MESMOS campos passam pelo caminho privilegiado declarado.
    Assert.areEqual(
      true,
      ALT_CLS_FinancialScheduleService.recordReplenishmentFailure(
          scheduleId,
          ALT_CLS_ScheduleReplenishment.ERROR_DML,
          System.now()
        )
        .statePersisted
    );
    Assert.areEqual(
      1,
      stateOf(scheduleId).AXF_FSC_NUM_RetryCount__c.intValue()
    );
  }

  // --- fila, seleção e observabilidade --------------------------------------

  /**
   * Item 39: o portão `NextAttemptAt` é o que faz a escada 1/5/30 ESPERAR. Um cronograma com
   * horário no futuro não entra no conjunto devido e volta a entrar quando o horário vence.
   */
  @IsTest
  static void theNextAttemptGateKeepsTheScheduleOutOfTheDueSetUntilItIsDue() {
    Account account = holder('AXF103 portao next attempt');
    AXF_OBJ_FinancialSchedule__c schedule = schedule(account.Id, 24, 3);
    Id scheduleId = schedule.Id;
    rollWindowForward(scheduleId, 4, true);

    Assert.areEqual(
      true,
      isDue(scheduleId),
      'Sem horário pendente, o cronograma atrasado está devido'
    );

    ALT_CLS_FinancialScheduleService.recordReplenishmentFailure(
      scheduleId,
      ALT_CLS_ScheduleReplenishment.ERROR_DML,
      System.now()
    );
    DateTime scheduled = stateOf(scheduleId).AXF_FSC_DT_NextAttemptAt__c;
    Assert.isTrue(
      scheduled > System.now(),
      'O primeiro degrau agenda o futuro: ' + scheduled
    );
    Assert.areEqual(
      false,
      isDue(scheduleId),
      'Com horário no futuro o cronograma sai do conjunto devido'
    );

    serviceWrite(
      new AXF_OBJ_FinancialSchedule__c(
        Id = scheduleId,
        AXF_FSC_DT_NextAttemptAt__c = System.now().addMinutes(-1)
      )
    );
    Assert.areEqual(
      true,
      isDue(scheduleId),
      'Vencido o horário, o cronograma volta ao conjunto devido'
    );
  }

  private static Boolean isDue(Id scheduleId) {
    for (
      AXF_CLS_ScheduleReplenishmentSelector.WorkItem item : AXF_CLS_ScheduleReplenishmentSelector.selectDue(
        25
      )
    ) {
      if (item.scheduleId == scheduleId) {
        return true;
      }
    }
    return false;
  }

  /**
   * Item 8: uma cabeça com código terminal NÃO pode travar a fila nem consumir posição do lote.
   * A exclusão tem de estar na PRÓPRIA consulta — com o teto de leitura reduzido a 1, um terminal
   * que ordena primeiro esconderia o cronograma devido.
   */
  @IsTest
  static void aTerminalHeadDoesNotStallTheQueueNorConsumeTheBatch() {
    Account account = holder('AXF103 cabeca terminal');
    AXF_OBJ_FinancialSchedule__c terminal = schedule(
      account.Id,
      24,
      3,
      'axf103-head-terminal'
    );
    AXF_OBJ_FinancialSchedule__c due = schedule(
      account.Id,
      24,
      3,
      'axf103-head-due'
    );
    rollWindowForward(terminal.Id, 4, true);
    rollWindowForward(due.Id, 4, true);
    // O terminal ordena PRIMEIRO: revisão de projeção menor.
    serviceWrite(
      new AXF_OBJ_FinancialSchedule__c(
        Id = terminal.Id,
        AXF_FSC_NUM_ProjectionRevision__c = 1
      )
    );
    serviceWrite(
      new AXF_OBJ_FinancialSchedule__c(
        Id = due.Id,
        AXF_FSC_NUM_ProjectionRevision__c = 2
      )
    );
    ALT_CLS_FinancialScheduleService.recordReplenishmentFailure(
      terminal.Id,
      ALT_CLS_ScheduleReplenishment.ERROR_PERMISSION_DENIED,
      System.now()
    );

    Integer previousLimit = AXF_CLS_ScheduleReplenishmentSelector.candidateLimitOverrideForTest;
    AXF_CLS_ScheduleReplenishmentSelector.candidateLimitOverrideForTest = 1;
    List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem> selected;
    try {
      selected = AXF_CLS_ScheduleReplenishmentSelector.selectDue(25);
    } finally {
      restoreCandidateLimit(previousLimit);
    }

    Assert.areEqual(
      1,
      selected.size(),
      'O cronograma devido foi alcançado apesar da cabeça terminal'
    );
    Assert.areEqual(due.Id, selected[0].scheduleId);
  }

  private static void restoreCandidateLimit(Integer previous) {
    AXF_CLS_ScheduleReplenishmentSelector.candidateLimitOverrideForTest = previous;
  }

  /**
   * Item 46: a folga declarada entre candidatos LIDOS e trabalho DESPACHADO é o que permite
   * alcançar, na MESMA passagem, um cronograma devido que ordena depois de outro não devido.
   */
  @IsTest
  static void theCandidateSlackReachesADueScheduleBehindANonDueOne() {
    Account account = holder('AXF103 folga de candidatos');
    AXF_OBJ_FinancialSchedule__c caughtUp = schedule(
      account.Id,
      1,
      3,
      'axf103-slack-caught'
    );
    AXF_OBJ_FinancialSchedule__c due = schedule(
      account.Id,
      24,
      2,
      'axf103-slack-due'
    );
    rollWindowForward(caughtUp.Id, 3, true);
    runPass(caughtUp.Id, false);
    rollWindowForward(due.Id, 2, true);
    runPass(due.Id, false);
    // O não devido ordena PRIMEIRO: cobertura 1 contra cobertura 2 do devido.
    Assert.areEqual(
      1,
      stateOf(caughtUp.Id).AXF_FSC_NUM_CoverageSequence__c.intValue()
    );
    Assert.areEqual(
      2,
      stateOf(due.Id).AXF_FSC_NUM_CoverageSequence__c.intValue()
    );
    rollWindowForward(due.Id, 4, true);
    Assert.areEqual(
      false,
      isDue(caughtUp.Id),
      'O primeiro candidato está coberto até o fim do termo'
    );

    AXF_ScheduleReplenishmentPolicy__mdt oneByOne = policyRecord(
      '0 0 4 1 * ?',
      '0 0 4 * * ?',
      'America/Sao_Paulo',
      '1,5,30',
      1,
      20,
      24
    );
    AXF_CLS_ScheduleReplenishmentPolicy.overrideRecord = oneByOne;
    List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem> selected;
    try {
      selected = AXF_CLS_ScheduleReplenishmentSelector.selectDue(1);
    } finally {
      AXF_CLS_ScheduleReplenishmentPolicy.overrideRecord = null;
    }

    Assert.areEqual(
      1,
      selected.size(),
      'A folga declarada alcançou o devido na mesma passagem'
    );
    Assert.areEqual(due.Id, selected[0].scheduleId);
  }

  /**
   * Itens 6 e 49: o orçamento de verificações de lacuna é DECLARADO, e o que não pôde ser
   * verificado NÃO é descartado em silêncio — continua no conjunto devido.
   */
  @IsTest
  static void theHoleCheckBudgetIsDeclaredAndTheUnverifiedCandidateIsNotSilentlyDropped() {
    Account account = holder('AXF103 orcamento de lacuna');
    AXF_OBJ_FinancialSchedule__c clean = schedule(
      account.Id,
      1,
      3,
      'axf103-budget-clean'
    );
    AXF_OBJ_FinancialSchedule__c holed = schedule(
      account.Id,
      24,
      3,
      'axf103-budget-holed'
    );
    rollWindowForward(clean.Id, 3, true);
    runPass(clean.Id, false);
    rollWindowForward(holed.Id, 3, true);
    runPass(holed.Id, false);
    // O primeiro candidato lido está coberto até o fim do termo e NÃO está devido; o segundo
    // carrega a lacuna. A ordem por cobertura ascendente (1 antes de 3) é determinística.
    Assert.areEqual(
      1,
      stateOf(clean.Id).AXF_FSC_NUM_CoverageSequence__c.intValue()
    );
    Assert.areEqual(
      3,
      stateOf(holed.Id).AXF_FSC_NUM_CoverageSequence__c.intValue()
    );
    deleteSequence(holed.Id, 2);
    Assert.areEqual(false, isDue(clean.Id));

    // Com orçamento suficiente, a lacuna é ENCONTRADA (não é fail-open).
    List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem> verified = AXF_CLS_ScheduleReplenishmentSelector.selectDue(
      25
    );
    Assert.areEqual(1, verified.size());
    Assert.areEqual(holed.Id, verified[0].scheduleId);
    Assert.areEqual(
      1,
      AXF_CLS_ScheduleReplenishmentSelector.lastTrace().holesFound
    );
    Assert.areEqual(
      0,
      AXF_CLS_ScheduleReplenishmentSelector.lastTrace().unverifiedDispatched
    );

    // Com o orçamento esgotado pelo primeiro candidato, o não verificado continua devido.
    Integer previousBudget = AXF_CLS_ScheduleReplenishmentSelector.holeCheckLimitOverrideForTest;
    AXF_CLS_ScheduleReplenishmentSelector.holeCheckLimitOverrideForTest = 1;
    List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem> failOpen;
    try {
      failOpen = AXF_CLS_ScheduleReplenishmentSelector.selectDue(25);
    } finally {
      AXF_CLS_ScheduleReplenishmentSelector.holeCheckLimitOverrideForTest = previousBudget;
    }
    Assert.areEqual(
      1,
      failOpen.size(),
      'O não verificado NÃO foi descartado em silêncio'
    );
    Assert.areEqual(holed.Id, failOpen[0].scheduleId);
    Assert.areEqual(
      1,
      AXF_CLS_ScheduleReplenishmentSelector.lastTrace().unverifiedDispatched,
      'O rastro diz que ele foi despachado SEM verificação'
    );

    // E a passagem autorizada que se segue REPARA a lacuna de verdade.
    ALT_CLS_FinancialScheduleService.ReplenishmentResult repaired = runPass(
      holed.Id,
      false
    );
    Assert.areEqual('GENERATED', repaired.outcome, repaired.message);
    Assert.areEqual(1, rowsOfSequence(holed.Id, 2));
  }

  /**
   * Itens 10 e 40: a passagem com excedente REAL. O cronograma acima do limite de transação drena
   * em passagens sucessivas, a produção relata `moreWork` sob o lock, e o trabalho inacabado volta
   * para o FIM da fila.
   *
   * O encadeamento em si não é exercitado ponta a ponta aqui: um job que enfileira um filho de
   * dentro do `Test.stopTest()` falha neste org com `System.AsyncException: Maximum stack depth has
   * been reached` (verificado por sonda, isolado). O que se assere é a decisão de re-enfileirar e a
   * POSIÇÃO declarada do item, e a drenagem pelas passagens reais da porta única.
   */
  @IsTest
  static void aPassBeyondTheTransactionLimitRequeuesItselfAtTheEndOfTheQueue() {
    Account account = holder('AXF103 acima do limite');
    // 60 parcelas: o limite de transação (50) é inalcançável dentro do horizonte default de 12
    // meses com periodicidade mensal, então o cenário usa o teto de 2 dígitos do próprio campo.
    AXF_OBJ_FinancialSchedule__c schedule = schedule(account.Id, 60, 6);
    Id scheduleId = schedule.Id;
    rollWindowForward(scheduleId, 60, true);
    Integer initial = occurrencesOf(scheduleId);
    Assert.areEqual(6, initial, 'A janela inicial grava 6 ocorrências');

    // A POSIÇÃO do trabalho inacabado é o fim da fila: os outros cronogramas progridem antes.
    List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem> queue = new List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem>();
    queue.add(workFor(scheduleId)[0]);
    AXF_CLS_ScheduleReplenishmentSelector.WorkItem others = workFor(
      scheduleId
    )[0];
    queue.add(others);
    AXF_CLS_ScheduleReplenishmentQueueable.requeueAtTheEnd(
      queue,
      workFor(scheduleId)[0]
    );
    Assert.areEqual(3, queue.size());
    Assert.areEqual(
      others.scheduleId,
      queue[1].scheduleId,
      'O item inacabado NÃO se antepõe ao restante do lote'
    );

    ALT_CLS_FinancialScheduleService.ReplenishmentResult first = runPass(
      scheduleId,
      false
    );
    Assert.areEqual('GENERATED', first.outcome, first.message);
    Assert.areEqual(
      ALT_CLS_ScheduleReplenishment.MAX_OCCURRENCES_PER_TRANSACTION,
      first.createdCount,
      'Nunca acima do limite de engenharia por transação'
    );
    Assert.areEqual(
      true,
      first.moreWork,
      'O excedente é relatado pela produção, sob o lock'
    );
    Assert.areEqual(
      initial + first.createdCount,
      stateOf(scheduleId).AXF_FSC_NUM_CoverageSequence__c.intValue()
    );

    // A passagem seguinte drena o resto e NÃO re-enfileira.
    ALT_CLS_FinancialScheduleService.ReplenishmentResult second = runPass(
      scheduleId,
      false
    );
    Assert.areEqual(
      60 - initial - first.createdCount,
      second.createdCount,
      second.message
    );
    Assert.areEqual(false, second.moreWork);
    Assert.areEqual(
      60,
      stateOf(scheduleId).AXF_FSC_NUM_CoverageSequence__c.intValue()
    );
    Assert.areEqual(60, occurrencesOf(scheduleId));
  }

  /**
   * Item 38: o guarda de NÃO regressão do cursor. Uma ocorrência apagada abaixo do prefixo já
   * confirmado, com a janela recuada, não pode rebaixar `CoverageSequence`.
   */
  @IsTest
  static void thePersistedCoverageNeverRegressesBelowTheConfirmedPrefix() {
    Account account = holder('AXF103 nao regressao do cursor');
    AXF_OBJ_FinancialSchedule__c schedule = schedule(account.Id, 24, 3);
    Id scheduleId = schedule.Id;
    rollWindowForward(scheduleId, 3, true);
    runPass(scheduleId, false);
    rollWindowForward(scheduleId, 4, true);
    ALT_CLS_FinancialScheduleService.ReplenishmentResult advanced = runPass(
      scheduleId,
      false
    );
    Assert.areEqual('GENERATED', advanced.outcome, advanced.message);
    Assert.areEqual(
      4,
      stateOf(scheduleId).AXF_FSC_NUM_CoverageSequence__c.intValue(),
      'A quarta ocorrência foi materializada e o cursor avançou'
    );

    // A janela recua e a ocorrência 4 desaparece: o prefixo contíguo cai para 3.
    rollWindowForward(scheduleId, 3, true);
    deleteSequence(scheduleId, 4);

    runPass(scheduleId, false);

    Assert.areEqual(
      4,
      stateOf(scheduleId).AXF_FSC_NUM_CoverageSequence__c.intValue(),
      'O progresso já confirmado não é rebaixado por uma leitura que não o alcança'
    );
  }

  /**
   * Item 5 do bloco E (20): mais de um cronograma devido no MESMO despacho.
   */
  @IsTest
  static void moreThanOneDueScheduleIsDispatchedInASinglePass() {
    Account account = holder('AXF103 dois devidos');
    AXF_OBJ_FinancialSchedule__c first = schedule(
      account.Id,
      24,
      3,
      'axf103-multi-a'
    );
    AXF_OBJ_FinancialSchedule__c second = schedule(
      account.Id,
      24,
      3,
      'axf103-multi-b'
    );
    rollWindowForward(first.Id, 4, true);
    rollWindowForward(second.Id, 4, true);
    Integer firstBefore = occurrencesOf(first.Id);
    Integer secondBefore = occurrencesOf(second.Id);

    Test.startTest();
    AXF_CLS_ScheduleReplenishmentScheduler.PassReport report = AXF_CLS_ScheduleReplenishmentScheduler.run();
    Test.stopTest();

    Assert.isNotNull(report.jobId, report.describe());
    Assert.areEqual(
      2,
      report.dispatched,
      'Os DOIS cronogramas devidos entraram no mesmo despacho: ' +
      report.describe()
    );
    Assert.areEqual(2, report.candidatesRead, report.describe());
    Assert.areEqual(
      0,
      report.unverifiedDispatched,
      'Ambos foram verificados, e não despachados por falha de orçamento'
    );
    Assert.isTrue(
      occurrencesOf(first.Id) > firstBefore,
      'O primeiro da cadeia executou e materializou a janela'
    );
    Assert.areEqual(
      secondBefore,
      occurrencesOf(second.Id),
      'O segundo item da MESMA cadeia é entregue à continuação registrada'
    );
  }

  /**
   * Item 21 (AC11): observabilidade de cadeia. Uma política removida no meio da cadeia é ABORTO
   * REGISTRADO, não exceção que escapa de `execute`; e o teto de rodadas interrompe a cadeia.
   */
  @IsTest
  static void aMissingPolicyMidChainIsRecordedInsteadOfThrown() {
    AXF_CLS_ScheduleReplenishmentQueueable.lastTrace().aborts.clear();
    AXF_CLS_ScheduleReplenishmentPolicy.forceMissing = true;
    try {
      new AXF_CLS_ScheduleReplenishmentQueueable(
          new List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem>(),
          0
        )
        .execute(null);
    } finally {
      AXF_CLS_ScheduleReplenishmentPolicy.forceMissing = false;
    }
    Assert.areEqual(
      1,
      AXF_CLS_ScheduleReplenishmentQueueable.lastTrace().aborts.size(),
      'O aborto foi registrado: ' +
      AXF_CLS_ScheduleReplenishmentQueueable.lastTrace().describe()
    );
    Assert.areEqual(
      AXF_CLS_ScheduleReplenishmentQueueable.ABORT_POLICY_UNAVAILABLE,
      AXF_CLS_ScheduleReplenishmentQueueable.lastTrace().aborts[0]
    );
  }

  @IsTest
  static void theContinuationRoundBudgetStopsTheChainAfterTheDeclaredLimit() {
    Account account = holder('AXF103 rodadas');
    AXF_OBJ_FinancialSchedule__c schedule = schedule(account.Id, 24, 3);
    rollWindowForward(schedule.Id, 4, true);

    AXF_ScheduleReplenishmentPolicy__mdt singleRound = policyRecord(
      '0 0 4 1 * ?',
      '0 0 4 * * ?',
      'America/Sao_Paulo',
      '1,5,30',
      25,
      1,
      24
    );
    AXF_CLS_ScheduleReplenishmentPolicy.overrideRecord = singleRound;
    AXF_CLS_ScheduleReplenishmentQueueable.chainLog = new List<AXF_CLS_ScheduleReplenishmentQueueable.ChainStep>();
    try {
      // Rodada 1: dentro do teto — a cadeia re-seleciona e encadeia o devido.
      new AXF_CLS_ScheduleReplenishmentQueueable(
          new List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem>(),
          1
        )
        .execute(null);
      Assert.areEqual(
        1,
        AXF_CLS_ScheduleReplenishmentQueueable.lastTrace().roundsConsumed
      );
      Assert.areEqual(
        new List<Id>{ schedule.Id },
        chainedIds(),
        'Dentro do teto a cadeia continua drenando'
      );

      // Rodada 2: acima do teto declarado — a cadeia PARA, e registra por quê.
      AXF_CLS_ScheduleReplenishmentQueueable.chainLog = new List<AXF_CLS_ScheduleReplenishmentQueueable.ChainStep>();
      AXF_CLS_ScheduleReplenishmentQueueable.lastTrace().aborts.clear();
      new AXF_CLS_ScheduleReplenishmentQueueable(
          new List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem>(),
          2
        )
        .execute(null);
      Assert.isTrue(
        AXF_CLS_ScheduleReplenishmentQueueable.chainLog.isEmpty(),
        'Acima do teto a cadeia não encadeia'
      );
      Assert.isTrue(
        AXF_CLS_ScheduleReplenishmentQueueable.lastTrace()
          .aborts.contains('ROUND_LIMIT'),
        'O motivo do fim da cadeia fica registrado'
      );
    } finally {
      AXF_CLS_ScheduleReplenishmentPolicy.overrideRecord = null;
      AXF_CLS_ScheduleReplenishmentQueueable.chainLog = null;
    }
  }

  // --- agendador e cadência -------------------------------------------------

  /**
   * Item 4: `System.schedule` NÃO aceita fuso (o compilador recusa a quarta assinatura), e o
   * `CronTrigger` herda o fuso do usuário que registra. A promessa de "04:00" só se sustenta se
   * quem registra estiver no fuso declarado — e é isso que o registro passa a EXIGIR, em vez de
   * prometer um horário que não seria cumprido.
   */
  @IsTest
  static void theRegistrationRefusesAPrincipalOutsideTheDeclaredTimeZone() {
    AXF_CLS_ScheduleReplenishmentPolicy policy = AXF_CLS_ScheduleReplenishmentPolicy.current();
    User pacific = userInTimeZone('axf103-pacific', 'America/Los_Angeles');
    Boolean refused = false;

    System.runAs(pacific) {
      Assert.areEqual(
        'America/Los_Angeles',
        UserInfo.getTimeZone().getID(),
        'O usuário que registra está em OUTRO fuso'
      );
      Test.startTest();
      try {
        AXF_CLS_ScheduleReplenishmentScheduler.registerMonthly();
      } catch (AXF_CLS_ScheduleReplenishmentPolicy.PolicyException expected) {
        refused = true;
        Assert.isTrue(
          expected.getMessage().contains(policy.scheduleTimeZone),
          'A recusa nomeia o fuso declarado: ' + expected.getMessage()
        );
      }
      try {
        AXF_CLS_ScheduleReplenishmentRecovery.registerRecovery();
      } catch (AXF_CLS_ScheduleReplenishmentPolicy.PolicyException expected) {
        Assert.isTrue(
          expected.getMessage().contains(policy.scheduleTimeZone),
          expected.getMessage()
        );
      }
      Test.stopTest();
    }

    Assert.isTrue(refused, 'Registrar fora do fuso declarado é RECUSADO');
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM CronTrigger
        WHERE
          CronJobDetail.Name IN :new List<String>{
            AXF_CLS_ScheduleReplenishmentPolicy.MONTHLY_JOB_NAME,
            AXF_CLS_ScheduleReplenishmentPolicy.RECOVERY_JOB_NAME
          }
      ],
      'Nenhum job é registrado com o horário errado'
    );
  }

  @IsTest
  static void theRegistrationUsesTheApprovedExpressionsInTheDeclaredTimeZone() {
    AXF_CLS_ScheduleReplenishmentPolicy policy = AXF_CLS_ScheduleReplenishmentPolicy.current();
    User saoPaulo = userInTimeZone('axf103.saopaulo', 'America/Sao_Paulo');
    Id monthly;
    Id recovery;

    System.runAs(saoPaulo) {
      Assert.areEqual(
        policy.scheduleTimeZone,
        UserInfo.getTimeZone().getID(),
        'O principal que registra está no fuso declarado'
      );
      Test.startTest();
      monthly = AXF_CLS_ScheduleReplenishmentScheduler.registerMonthly();
      recovery = AXF_CLS_ScheduleReplenishmentRecovery.registerRecovery();
      Test.stopTest();
    }

    Assert.isNotNull(monthly);
    Assert.isNotNull(recovery);
    List<CronTrigger> triggers = [
      SELECT CronExpression, TimeZoneSidKey, CronJobDetail.Name
      FROM CronTrigger
      WHERE
        CronJobDetail.Name = :AXF_CLS_ScheduleReplenishmentPolicy.MONTHLY_JOB_NAME
        OR CronJobDetail.Name = :AXF_CLS_ScheduleReplenishmentPolicy.RECOVERY_JOB_NAME
      ORDER BY CronJobDetail.Name
    ];
    Assert.areEqual(2, triggers.size(), 'As duas passagens foram registradas');
    Assert.areEqual(
      policy.monthlyCron,
      triggers[0].CronExpression,
      'A passagem mensal usa a expressão aprovada'
    );
    Assert.areEqual(
      policy.recoveryCron,
      triggers[1].CronExpression,
      'A passagem de recuperação usa a expressão aprovada'
    );
    for (CronTrigger cronTrigger : triggers) {
      Assert.areEqual(
        policy.scheduleTimeZone,
        cronTrigger.TimeZoneSidKey,
        'O fuso do CronTrigger é o fuso DECLARADO, porque o principal está nele'
      );
    }
  }

  /**
   * Item 42: `execute(SchedulableContext)` precisa RODAR. Um `execute` vazio deixaria o job
   * mensal mudo em produção com a suíte verde.
   */
  @IsTest
  static void theSchedulerEntryPointExecutesThePassWhenInvoked() {
    Account account = holder('AXF103 ponto de entrada');
    AXF_OBJ_FinancialSchedule__c schedule = schedule(account.Id, 24, 3);
    Id scheduleId = schedule.Id;
    rollWindowForward(scheduleId, 4, true);
    Integer before = occurrencesOf(scheduleId);

    Test.startTest();
    new AXF_CLS_ScheduleReplenishmentScheduler().execute(null);
    Test.stopTest();

    Assert.isTrue(
      occurrencesOf(scheduleId) > before,
      'O ponto de entrada execute(SchedulableContext) executou a passagem'
    );
  }

  @IsTest
  static void theSchedulerEntryPointRunsThroughSystemScheduleWithoutGeneratingAnything() {
    Account account = holder('AXF103 agendador');
    AXF_OBJ_FinancialSchedule__c schedule = schedule(account.Id, 24, 2);
    Id scheduleId = schedule.Id;
    // Nada devido: a geração está desligada e a janela está coberta.
    Integer before = occurrencesOf(scheduleId);

    Test.startTest();
    System.schedule(
      'AXF Reposicao Rolante teste',
      '0 0 4 1 1 ? 2099',
      new AXF_CLS_ScheduleReplenishmentScheduler()
    );
    Test.stopTest();

    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM CronTrigger
        WHERE CronJobDetail.Name = 'AXF Reposicao Rolante teste'
      ],
      'O ponto de entrada execute(SchedulableContext) foi exercitado'
    );
    Assert.areEqual(
      before,
      occurrencesOf(scheduleId),
      'O agendador não gera nada por conta própria'
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AXF_OBJ_ScheduleChange__c
        WHERE AXF_SCH_LKP_Schedule__c = :scheduleId
      ]
    );
  }

  @IsTest
  static void theRecoveryPassEntryPointRunsThroughSystemSchedule() {
    User saoPaulo = userInTimeZone('axf103.recuperacao', 'America/Sao_Paulo');
    Test.startTest();
    System.runAs(saoPaulo) {
      AXF_CLS_ScheduleReplenishmentRecovery.registerRecovery();
    }
    Test.stopTest();
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM CronTrigger
        WHERE
          CronJobDetail.Name = :AXF_CLS_ScheduleReplenishmentPolicy.RECOVERY_JOB_NAME
      ],
      'A passagem de recuperação é um ponto de entrada registrável'
    );
  }

  @IsTest
  static void theDispatchCriterionReachesTheTailOfTheDueSet() {
    Account account = holder('AXF103 cauda');
    AXF_OBJ_FinancialSchedule__c first = schedule(account.Id, 24, 1);
    AXF_OBJ_FinancialSchedule__c second = schedule(account.Id, 36, 1);
    AXF_OBJ_FinancialSchedule__c third = schedule(account.Id, 12, 1);
    rollWindowForward(first.Id, 2, true);
    rollWindowForward(second.Id, 2, true);
    rollWindowForward(third.Id, 2, true);

    List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem> due = AXF_CLS_ScheduleReplenishmentSelector.selectDue(
      2
    );
    Assert.areEqual(2, due.size(), 'O lote de uma passagem é respeitado');

    // O que excedeu o lote não foi descartado: continua no conjunto devido. Cada cronograma
    // processado sai por ficar coberto, então a passagem seguinte alcança a cauda.
    Set<Id> dispatched = new Set<Id>();
    for (AXF_CLS_ScheduleReplenishmentSelector.WorkItem item : due) {
      dispatched.add(item.scheduleId);
      runPass(item.scheduleId, false);
    }
    for (
      AXF_OBJ_FinancialSchedule__c candidate : new List<AXF_OBJ_FinancialSchedule__c>{
        first,
        second,
        third
      }
    ) {
      if (dispatched.contains(candidate.Id)) {
        continue;
      }
      Boolean stillDue = false;
      for (
        AXF_CLS_ScheduleReplenishmentSelector.WorkItem item : AXF_CLS_ScheduleReplenishmentSelector.selectDue(
          25
        )
      ) {
        stillDue = stillDue || item.scheduleId == candidate.Id;
      }
      Assert.isTrue(
        stillDue,
        'O excedente do lote permanece no conjunto devido e é re-selecionado'
      );
    }
  }

  /**
   * Item 22: `describeSchedule()` é a única superfície de operação. O texto precisa servir para
   * registrar de fato, trazer o fuso e as DUAS expressões, e corresponder ao registro lido.
   */
  @IsTest
  static void describeScheduleServesRegistrationAndMatchesThePolicyRecord() {
    AXF_ScheduleReplenishmentPolicy__mdt stored = AXF_ScheduleReplenishmentPolicy__mdt.getInstance(
      'Default'
    );
    Assert.isNotNull(stored, 'O registro aprovado existe na org');
    AXF_CLS_ScheduleReplenishmentPolicy policy = AXF_CLS_ScheduleReplenishmentPolicy.current();
    String described = policy.describeSchedule();

    Assert.areEqual(
      stored.AXF_SRP_TXT_MonthlyCron__c,
      policy.monthlyCron,
      'A expressão mensal descrita é a do registro lido'
    );
    Assert.areEqual(
      stored.AXF_SRP_TXT_RecoveryCron__c,
      policy.recoveryCron,
      'A expressão de recuperação descrita é a do registro lido'
    );
    Assert.isTrue(
      described.contains('mensal=[' + policy.monthlyCron + ']'),
      described
    );
    Assert.isTrue(
      described.contains('recuperacao=[' + policy.recoveryCron + ']'),
      described
    );
    Assert.isTrue(
      described.contains('fusoDeclarado=' + policy.scheduleTimeZone),
      'O fuso declarado aparece no texto de operação: ' + described
    );
    Assert.isTrue(
      described.contains('fusoDoRegistrante='),
      'O fuso EFETIVO do principal que registra aparece: ' + described
    );
    Assert.isTrue(
      described.contains(
        'jobMensal=' + AXF_CLS_ScheduleReplenishmentPolicy.MONTHLY_JOB_NAME
      ) &&
      described.contains(
        'jobRecuperacao=' +
        AXF_CLS_ScheduleReplenishmentPolicy.RECOVERY_JOB_NAME
      ),
      'O texto nomeia os dois jobs a registrar: ' + described
    );
    Assert.isTrue(
      described.contains('AXF_CLS_ScheduleReplenishmentScheduler') &&
      described.contains('AXF_CLS_ScheduleReplenishmentRecovery'),
      'O texto nomeia as duas classes a registrar: ' + described
    );

    // O texto SERVE para registrar: a expressão que ele reporta é aceita pelo agendador, no fuso
    // declarado, por um principal que está nele.
    User saoPaulo = userInTimeZone('axf103.descricao', 'America/Sao_Paulo');
    Test.startTest();
    System.runAs(saoPaulo) {
      AXF_CLS_ScheduleReplenishmentScheduler.registerMonthly();
    }
    Test.stopTest();
    CronTrigger registered = [
      SELECT CronExpression, TimeZoneSidKey
      FROM CronTrigger
      WHERE
        CronJobDetail.Name = :AXF_CLS_ScheduleReplenishmentPolicy.MONTHLY_JOB_NAME
    ];
    Assert.areEqual(policy.monthlyCron, registered.CronExpression);
    Assert.areEqual(policy.scheduleTimeZone, registered.TimeZoneSidKey);
  }

  @IsTest
  static void theCadencePolicyIsVersionedAndRefusesAnUnapprovedLadder() {
    AXF_CLS_ScheduleReplenishmentPolicy policy = AXF_CLS_ScheduleReplenishmentPolicy.current();
    Assert.areEqual('0 0 4 1 * ?', policy.monthlyCron);
    Assert.areEqual('0 0 4 * * ?', policy.recoveryCron);
    Assert.areEqual('America/Sao_Paulo', policy.scheduleTimeZone);
    Assert.areEqual(25, policy.dispatchBatchSize);
    Assert.areEqual(20, policy.maxContinuationRounds);
    Assert.areEqual(24, policy.rearmHours);
    Assert.areEqual(
      ALT_CLS_ScheduleReplenishment.BACKOFF_MINUTES,
      policy.backoffMinutes,
      'A escada declarada é a aprovada: 1, 5 e 30 minutos'
    );
    Assert.isTrue(policy.describeSchedule().contains('recuperacao='));

    Boolean missingRefused = false;
    AXF_CLS_ScheduleReplenishmentPolicy.forceMissing = true;
    try {
      AXF_CLS_ScheduleReplenishmentPolicy.current();
    } catch (AXF_CLS_ScheduleReplenishmentPolicy.PolicyException expected) {
      missingRefused = true;
    } finally {
      AXF_CLS_ScheduleReplenishmentPolicy.forceMissing = false;
    }
    Assert.isTrue(
      missingRefused,
      'Sem política aprovada o despacho recusa rodar'
    );

    assertPolicyRefused(
      policyRecord(
        '0 0 4 1 * ?',
        '0 0 4 * * ?',
        'America/Sao_Paulo',
        '1,5,30,60',
        25,
        20,
        24
      ),
      'Backoff fora da escada aprovada exige aprovação humana'
    );
    assertPolicyRefused(
      policyRecord(
        '0 0 4 1 * ?',
        '0 0 4 * * ?',
        'America/Sao_Paulo',
        '1,5,30',
        0,
        20,
        24
      ),
      'Limite inválido recusa a política'
    );
    assertPolicyRefused(
      policyRecord(
        '',
        '0 0 4 * * ?',
        'America/Sao_Paulo',
        '1,5,30',
        25,
        20,
        24
      ),
      'Expressão mensal em branco recusa a política (a plataforma não impõe <required> de mdt)'
    );
    assertPolicyRefused(
      policyRecord(
        '0 0 4 1 * ?',
        '',
        'America/Sao_Paulo',
        '1,5,30',
        25,
        20,
        24
      ),
      'Expressão de recuperação em branco recusa a política'
    );
    assertPolicyRefused(
      policyRecord('0 0 4 1 * ?', '0 0 4 * * ?', '', '1,5,30', 25, 20, 24),
      'Fuso em branco recusa a política'
    );
    assertPolicyRefused(
      policyRecord(
        '0 0 4 1 * ?',
        '0 0 4 * * ?',
        'America/Sao_Paulo',
        '1,5,30',
        25,
        20,
        null
      ),
      'Janela de realarme ausente recusa a política'
    );
    assertPolicyRefused(
      policyRecord(
        '0 0 4 1 * ?',
        '0 0 4 * * ?',
        'America/Sao_Paulo',
        '1,5,30',
        30,
        30,
        24
      ),
      'Lote x rodadas acima do teto declarado da cadeia recusa a política'
    );
  }

  private static void assertPolicyRefused(
    AXF_ScheduleReplenishmentPolicy__mdt record,
    String label
  ) {
    Boolean refused = false;
    AXF_CLS_ScheduleReplenishmentPolicy.overrideRecord = record;
    try {
      AXF_CLS_ScheduleReplenishmentPolicy.current();
    } catch (AXF_CLS_ScheduleReplenishmentPolicy.PolicyException expected) {
      refused = true;
    } finally {
      AXF_CLS_ScheduleReplenishmentPolicy.overrideRecord = null;
    }
    Assert.isTrue(refused, label);
  }

  private static AXF_ScheduleReplenishmentPolicy__mdt policyRecord(
    String monthlyCron,
    String recoveryCron,
    String timeZone,
    String ladder,
    Integer batchSize,
    Integer rounds,
    Integer rearmHours
  ) {
    return new AXF_ScheduleReplenishmentPolicy__mdt(
      AXF_SRP_TXT_MonthlyCron__c = monthlyCron,
      AXF_SRP_TXT_RecoveryCron__c = recoveryCron,
      AXF_SRP_TXT_ScheduleTimeZone__c = timeZone,
      AXF_SRP_TXT_BackoffMinutes__c = ladder,
      AXF_SRP_NUM_DispatchBatchSize__c = batchSize,
      AXF_SRP_NUM_MaxContinuationRounds__c = rounds,
      AXF_SRP_NUM_RearmHours__c = rearmHours
    );
  }

  /**
   * Itens 7 (borda + lacuna) e 23 (teto e custo): o custo de uma passagem é MEDIDO, e os limites
   * declarados de escala são asseridos.
   */
  @IsTest
  static void aPassOnALongScheduleStaysInsideTheMeasuredCost() {
    Account account = holder('AXF103 custo');
    AXF_OBJ_FinancialSchedule__c schedule = schedule(account.Id, 360, 1);
    Id scheduleId = schedule.Id;
    rollWindowForward(scheduleId, 12, true);
    Integer queriesBefore = Limits.getQueries();
    Long cpuBefore = Limits.getCpuTime();
    Integer dmlRowsBefore = Limits.getDmlRows();
    Integer heapBefore = Limits.getHeapSize();

    ALT_CLS_FinancialScheduleService.ReplenishmentResult result = runPass(
      scheduleId,
      false
    );

    Integer queries = Limits.getQueries() - queriesBefore;
    Long cpu = Limits.getCpuTime() - cpuBefore;
    Integer dmlRows = Limits.getDmlRows() - dmlRowsBefore;
    Integer heap = Limits.getHeapSize() - heapBefore;
    // Custo MEDIDO em AXON_DEV para um cronograma de 360 parcelas com a janela rolada de 1 para
    // 12 meses: 14 consultas, 133 ms de CPU e 12 linhas gravadas (11 ocorrências novas mais a
    // linha do cursor). A leitura do motor avalia as 360 parcelas e está incluída nesse CPU. Os
    // limites abaixo folgam sobre a medição sem deixar de registrar o custo: uma passagem que
    // estoure qualquer um deles exige revisão de dimensionamento antes de produção.
    Assert.isTrue(queries <= 25, 'Consultas da passagem: ' + queries);
    Assert.isTrue(dmlRows <= 60, 'Linhas gravadas na passagem: ' + dmlRows);
    Assert.isTrue(cpu < 5000, 'CPU da passagem: ' + cpu + 'ms');
    Assert.isTrue(
      heap < 1000000,
      'Heap consumido pela passagem: ' +
        heap +
        ' bytes (teto declarado de identidades: ' +
        ALT_CLS_ScheduleReplenishment.MAX_TRACKED_IDENTITIES_PER_SCHEDULE +
        ')'
    );
    Assert.areEqual(
      11,
      result.createdCount,
      'Materializou o que faltava dentro da janela rolada'
    );
    Assert.areEqual('GENERATED', result.outcome, result.message);
  }

  /**
   * Item 23: o teto DECLARADO de identidades rastreadas é efetivo — acima dele a passagem recusa
   * em vez de carregar o histórico inteiro em memória.
   */
  @IsTest
  static void aScheduleBeyondTheDeclaredIdentityCeilingIsRefusedAsAScaleLimit() {
    Account account = holder('AXF103 teto de escala');
    AXF_OBJ_FinancialSchedule__c schedule = schedule(account.Id, 24, 3);
    Id scheduleId = schedule.Id;
    rollWindowForward(scheduleId, 4, true);
    Integer before = occurrencesOf(scheduleId);

    ALT_CLS_FinancialScheduleService.ReplenishmentResult result;
    ALT_CLS_FinancialScheduleService.trackedIdentityCeilingOverrideForTest = 2;
    try {
      result = runPass(scheduleId, false);
    } finally {
      ALT_CLS_FinancialScheduleService.trackedIdentityCeilingOverrideForTest = null;
    }

    Assert.areEqual(
      ALT_CLS_ScheduleReplenishment.ERROR_SCALE_LIMIT,
      result.errorCode,
      result.message
    );
    Assert.areEqual(true, result.terminal);
    Assert.areEqual(before, occurrencesOf(scheduleId), 'Nada é gravado');
    Assert.areEqual(
      ALT_CLS_ScheduleReplenishment.ERROR_SCALE_LIMIT,
      stateOf(scheduleId).AXF_FSC_TXT_LastErrorCode__c
    );
  }

  // --- personas -------------------------------------------------------------

  private static User strangerUser() {
    return userInTimeZone('axf103.estranho', 'America/Sao_Paulo');
  }

  private static User gestorUser() {
    User value = userInTimeZone('axf103.gestor', 'America/Sao_Paulo');
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert new PermissionSetAssignment(
        AssigneeId = value.Id,
        PermissionSetId = [
          SELECT Id
          FROM PermissionSet
          WHERE Name = :GESTOR_PS
          LIMIT 1
        ]
        .Id
      );
    }
    return value;
  }

  private static User userInTimeZone(String prefix, String timeZone) {
    Id profileId = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Minimum Access - Salesforce'
      LIMIT 1
    ]
    .Id;
    User value = new User(
      ProfileId = profileId,
      LastName = prefix,
      Email = prefix + '@example.invalid',
      Username = prefix + '.' + Crypto.getRandomInteger() + '@example.invalid',
      Alias = prefix.replace('.', '').substring(0, 8),
      TimeZoneSidKey = timeZone,
      LocaleSidKey = 'pt_BR',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'pt_BR'
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert value;
    }
    return value;
  }
}
