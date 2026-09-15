/**
 * @description AXF-137: eight horizons x three scenarios with integral, non-probabilistic
 * inclusion; the full remaining commitment comes from the AXF-103 projection (360-installment
 * schedule beyond the persisted window, no double counting); obligations beyond the horizon and
 * overdue occurrences stay visible; context/asOf/policy/confidence travel with the result;
 * absence, partial access or a stale projection derive DEGRADED/BLOCKED, never zero.
 */
@IsTest(isParallel=false)
// API 62: AXON_DEV enforces FLS on plain test DML under runAs from API 67 onwards.
private class ALT_CLS_ForecastComparisonServiceTest {
  private static User byAlias(String alias) {
    return [SELECT Id FROM User WHERE Alias = :alias LIMIT 1];
  }

  @TestSetup
  static void setup() {
    Id profileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
    .Id;
    List<User> users = new List<User>();
    for (String alias : new List<String>{ 'axf137g', 'axf137p', 'axf137n' }) {
      users.add(
        new User(
          Alias = alias,
          Email = alias + '@example.invalid',
          EmailEncodingKey = 'UTF-8',
          LastName = 'User ' + alias,
          LanguageLocaleKey = 'pt_BR',
          LocaleSidKey = 'pt_BR',
          TimeZoneSidKey = 'America/Sao_Paulo',
          ProfileId = profileId,
          Username = alias + '.' + System.now().getTime() + '@example.invalid'
        )
      );
    }
    insert users;
    Map<String, Id> permissionSets = new Map<String, Id>();
    for (PermissionSet permission : [
      SELECT Id, Name
      FROM PermissionSet
      WHERE
        Name IN (
          'AXF_PS_GestorFinanceiro',
          'AXF_PS_FinancialEntry',
          'AXF_PS_Participante'
        )
    ]) {
      permissionSets.put(permission.Name, permission.Id);
    }
    Assert.areEqual(3, permissionSets.size(), 'permission sets must exist');
    List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (Integer i = 0; i < 2; i++) {
      assignments.add(
        new PermissionSetAssignment(
          AssigneeId = users[i].Id,
          PermissionSetId = permissionSets.get('AXF_PS_GestorFinanceiro')
        )
      );
      assignments.add(
        new PermissionSetAssignment(
          AssigneeId = users[i].Id,
          PermissionSetId = permissionSets.get('AXF_PS_FinancialEntry')
        )
      );
    }
    assignments.add(
      new PermissionSetAssignment(
        AssigneeId = users[2].Id,
        PermissionSetId = permissionSets.get('AXF_PS_Participante')
      )
    );
    insert assignments;
  }

  private static Account holder(String name) {
    Account result = new Account(
      Name = name,
      RecordTypeId = Account.SObjectType.getDescribe()
        .getRecordTypeInfosByDeveloperName()
        .get('AXF_Business')
        .getRecordTypeId()
    );
    insert result;
    return result;
  }

  private static ALT_CLS_FinancialScheduleService.CreateResult schedule(
    Id accountId,
    String method,
    Integer totalInstallments,
    Integer trackingStart,
    Date trackingDue,
    String key
  ) {
    ALT_CLS_FinancialScheduleService.CreateInput input = new ALT_CLS_FinancialScheduleService.CreateInput();
    input.accountId = accountId;
    input.direction = 'DEBIT';
    input.currencyIsoCode = 'BRL';
    input.method = method;
    input.totalInstallments = totalInstallments;
    input.firstSequence = 1;
    input.trackingStartSequence = trackingStart;
    input.trackingDueDate = trackingDue;
    input.periodMonths = 1;
    input.principal = 360000;
    input.periodRate = 0.01;
    input.referenceAmount = 500.00;
    input.legacyGroupKey = key;
    ALT_CLS_FinancialScheduleService.CreateResult result = ALT_CLS_FinancialScheduleService.createSchedule(
      input
    );
    Assert.areEqual('CREATED', result.outcome, result.message);
    return result;
  }

  private static AXF_OBJ_FinancialTransaction__c plan(
    Id accountId,
    String key,
    Decimal magnitude,
    String direction,
    String status,
    Date due,
    Boolean estimated
  ) {
    return new AXF_OBJ_FinancialTransaction__c(
      AXF_FTX_LKP_Account__c = accountId,
      AXF_FTX_NUM_Magnitude__c = magnitude,
      AXF_FTX_PKL_Direction__c = direction,
      AXF_FTX_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_FTX_DAT_PurchaseDate__c = due,
      AXF_FTX_DAT_DueDate__c = due,
      AXF_FTX_PKL_Status__c = status,
      AXF_FTX_CHK_IsEstimated__c = estimated,
      AXF_FTX_EXI_ClientRequestId__c = 'ftx-137-' + key
    );
  }

  private static ALT_CLS_ForecastComparisonService.Input input(
    List<Id> ids,
    Integer months,
    String scenario
  ) {
    ALT_CLS_ForecastComparisonService.Input value = new ALT_CLS_ForecastComparisonService.Input();
    value.accountIds = ids;
    value.horizonMonths = months;
    value.scenario = scenario;
    return value;
  }

  private static ALT_CLS_ForecastComparisonService.HorizonTotal horizon(
    ALT_CLS_ForecastComparisonService.Result result,
    Integer months,
    String currencyIso
  ) {
    for (
      ALT_CLS_ForecastComparisonService.HorizonTotal total : result.horizons
    ) {
      if (total.horizonMonths == months && total.currencyIso == currencyIso) {
        return total;
      }
    }
    return null;
  }

  @IsTest
  static void threeHundredSixtyInstallmentsBeyondThePersistedWindowAreCountedOnce() {
    System.runAs(byAlias('axf137g')) {
      Account ana = holder('Ana Financiamento');
      Date today = Date.today();
      Date trackingDue = today.addMonths(1).toStartOfMonth().addDays(9);
      ALT_CLS_FinancialScheduleService.CreateResult created = schedule(
        ana.Id,
        'INSTALLMENT',
        360,
        5,
        trackingDue,
        'fc-360'
      );
      Assert.isTrue(
        created.occurrenceCount < 356,
        'so a janela operacional e persistida'
      );
      ALT_CLS_ScheduleProjection.ProjectionInput read = new ALT_CLS_ScheduleProjection.ProjectionInput();
      read.scheduleId = created.scheduleId;
      read.asOfDate = today;
      ALT_CLS_ScheduleProjection.ProjectionResult projection = ALT_CLS_FinancialScheduleService.readProjection(
        read
      );
      Assert.areEqual('OK', projection.outcome, projection.message);
      Assert.areEqual(356, projection.lines.size(), 'parcelas 5..360');
      ALT_CLS_ForecastComparisonService service = new ALT_CLS_ForecastComparisonService();
      Test.startTest();
      ALT_CLS_ForecastComparisonService.Result result = service.compare(
        input(
          new List<Id>{ ana.Id },
          24,
          ALT_CLS_ForecastComparisonService.SCENARIO_CONSERVATIVE
        )
      );
      Test.stopTest();
      Assert.areEqual(
        ALT_CLS_ForecastComparisonService.CONFIDENCE_INFORMATIVE,
        result.confidence,
        'obrigacoes alem do horizonte ficam visiveis na explicacao; nada oculto'
      );
      Assert.isTrue(result.reasons.contains('OBLIGATIONS_BEYOND_HORIZON'));
      Assert.isFalse(result.reasons.contains('COMMITMENT_UNBOUNDED'));
      Assert.areEqual(1, result.sources.size());
      Assert.areEqual(356, result.sources[0].occurrenceCount);
      Assert.isTrue(result.sources[0].coverageComplete);
      Assert.areEqual(new List<String>{ 'BRL' }, result.currencies);
      Assert.areEqual(
        ALT_CLS_ForecastComparisonService.POLICY_VERSION,
        result.policyVersion
      );
      Assert.areEqual(today, result.asOf);
      Integer within = 0;
      Decimal expectedWithin = 0;
      for (ALT_CLS_ScheduleProjection.OccurrenceLine line : projection.lines) {
        if (line.effectiveDueDate <= result.horizonEnd) {
          within++;
          expectedWithin += line.amount;
        }
      }
      ALT_CLS_ForecastComparisonService.HorizonTotal h24 = horizon(
        result,
        24,
        'BRL'
      );
      Assert.areEqual(
        expectedWithin.setScale(2),
        h24.confirmedOut.setScale(2),
        'parcelas dentro do horizonte, persistidas e virtuais, uma vez cada'
      );
      Assert.areEqual(356 - within, h24.beyondCount);
      Assert.areEqual(
        projection.totalRemaining,
        (h24.confirmedOut + h24.beyondOut).setScale(2),
        'dentro + alem = compromisso restante, sem dupla contagem'
      );
      Assert.areEqual(0, h24.probableOut);
      Assert.areEqual(0, h24.uncertainOut);
      Assert.areEqual(h24.conservativeNet, h24.optimisticNet, 'nada ponderado');
      Decimal previous = -1;
      for (Integer months : ALT_CLS_ForecastComparisonService.HORIZONS) {
        ALT_CLS_ForecastComparisonService.HorizonTotal total = horizon(
          result,
          months,
          'BRL'
        );
        Assert.isTrue(
          total.confirmedOut >= previous,
          'horizonte maior nunca soma menos'
        );
        Assert.areEqual(
          projection.totalRemaining,
          (total.confirmedOut + total.beyondOut).setScale(2),
          'conservacao em todo horizonte'
        );
        previous = total.confirmedOut;
      }
      Assert.areEqual(
        within,
        countPeriods(result),
        'mes a mes cobre exatamente as ocorrencias do horizonte'
      );
      Assert.isTrue(result.overdue.isEmpty());
      Assert.isTrue(result.allowedActions.contains('REVIEW_SCHEDULES'));
    }
  }

  private static Integer countPeriods(
    ALT_CLS_ForecastComparisonService.Result result
  ) {
    Integer count = 0;
    for (ALT_CLS_ForecastComparisonService.PeriodView period : result.periods) {
      count += period.count;
    }
    return count;
  }

  private static Integer monthsBetween(Date fromDate, Date toDate) {
    Integer count = 0;
    Date month = fromDate.toStartOfMonth();
    while (month <= toDate) {
      count++;
      month = month.addMonths(1);
    }
    return count;
  }

  @IsTest
  static void scenariosIncludeTiersIntegrallyAndOverdueStaysVisible() {
    System.runAs(byAlias('axf137g')) {
      Account ana = holder('Ana Cenarios');
      Date today = Date.today();
      Date nextMonth = today.addMonths(1).toStartOfMonth().addDays(4);
      insert new List<AXF_OBJ_FinancialTransaction__c>{
        plan(ana.Id, 'salary', 5000, 'CREDIT', 'CONFIRMED', nextMonth, false),
        plan(ana.Id, 'rent', 2000, 'DEBIT', 'PLANNED', nextMonth, false),
        plan(
          ana.Id,
          'trip',
          800,
          'DEBIT',
          'PLANNED',
          nextMonth.addMonths(4),
          true
        ),
        plan(
          ana.Id,
          'late',
          300,
          'DEBIT',
          'PLANNED',
          today.addDays(-10),
          false
        ),
        plan(
          ana.Id,
          'paid',
          999,
          'DEBIT',
          'CONFIRMED',
          today.addDays(-5),
          false
        ),
        plan(ana.Id, 'far', 100, 'DEBIT', 'PLANNED', today.addMonths(30), false)
      };
      // Estimated recurrence (reference value): AXF-138 applies the policy, which approves no
      // method for that class, so it is not summed — see the reason, fallback and exclusion below.
      schedule(ana.Id, 'ESTIMATED', 6, 1, nextMonth, 'fc-est');
      ALT_CLS_ForecastComparisonService service = new ALT_CLS_ForecastComparisonService();
      Test.startTest();
      ALT_CLS_ForecastComparisonService.Result three = service.compare(
        input(
          new List<Id>{ ana.Id },
          3,
          ALT_CLS_ForecastComparisonService.SCENARIO_INTERMEDIATE
        )
      );
      Test.stopTest();
      ALT_CLS_ForecastComparisonService.HorizonTotal h3 = horizon(
        three,
        3,
        'BRL'
      );
      Assert.areEqual(5000, h3.confirmedIn, 'confirmado futuro entra integral');
      Assert.areEqual(0, h3.confirmedOut);
      // rent 2000: the estimated recurrence of 500 is no longer a probable contribution.
      Assert.areEqual(
        2000,
        h3.probableOut,
        'provavel: apenas o plano; a recorrencia estimada nao tem metodo aprovado'
      );
      Assert.areEqual(0, h3.uncertainOut, 'viagem estimada so daqui a 5 meses');
      Assert.areEqual(5000, h3.conservativeNet);
      Assert.areEqual(5000 - 2000, h3.intermediateNet);
      Assert.areEqual(
        5000 - 2000,
        h3.optimisticNet,
        'sem incertos nos 3 meses'
      );
      ALT_CLS_ForecastComparisonService.HorizonTotal h6 = horizon(
        three,
        6,
        'BRL'
      );
      Assert.areEqual(
        800,
        h6.uncertainOut,
        'incerto entra integral no otimista'
      );
      Assert.areEqual(h6.intermediateNet - 800, h6.optimisticNet);
      Assert.isTrue(h3.beyondCount >= 2, 'alem do horizonte existe');
      Assert.isTrue(
        h3.beyondOut >= 100 + 800,
        'viagem e plano distante alem de 3 meses'
      );
      ALT_CLS_ForecastComparisonService.HorizonTotal h24 = horizon(
        three,
        24,
        'BRL'
      );
      Assert.areEqual(
        100,
        h24.beyondOut,
        'plano a 30 meses continua visivel alem de 24'
      );
      Assert.areEqual(1, three.overdue.size());
      Assert.areEqual(300, three.overdue[0].amountOut, 'vencido nunca some');
      Assert.isTrue(three.reasons.contains('OVERDUE_OBLIGATIONS'));
      Assert.isTrue(three.reasons.contains('OBLIGATIONS_BEYOND_HORIZON'));
      Assert.isTrue(three.reasons.contains('NO_APPROVED_METHOD'));
      Assert.areEqual(
        ALT_CLS_ForecastComparisonService.CONFIDENCE_BLOCKED,
        three.confidence,
        'omitir a recorrencia estimada de uma obrigacao poderia aumentar a capacidade'
      );
      Assert.areEqual(1, three.exclusions.size(), 'a omissao fica registrada');
      Assert.areEqual(ana.Id, three.exclusions[0].accountId);
      Assert.areEqual('NO_APPROVED_METHOD', three.exclusions[0].reason);
      Assert.areEqual(
        2,
        three.sources.size(),
        'cronograma estimado + planos avulsos'
      );
      Decimal confirmedOutTotal = 0;
      for (
        ALT_CLS_ForecastComparisonService.PeriodView period : three.periods
      ) {
        confirmedOutTotal += period.confirmedOut;
      }
      Assert.areEqual(
        0,
        confirmedOutTotal,
        'confirmado no passado e historico: nem periodo nem vencido'
      );
      Assert.areEqual(
        300,
        three.overdue[0].amountOut,
        'apenas o plano vencido nao confirmado entra no vencido'
      );
      for (
        ALT_CLS_ForecastComparisonService.SourceView source : three.sources
      ) {
        if (source.kind == 'PLAN') {
          Assert.areEqual(
            5,
            source.occurrenceCount,
            'historico realizado (paid) nao conta como ocorrencia de previsao'
          );
        }
      }
      // Every month of the selected horizon is listed, zero rows included.
      Set<String> months = new Set<String>();
      for (
        ALT_CLS_ForecastComparisonService.PeriodView period : three.periods
      ) {
        months.add(period.periodKey);
      }
      Assert.areEqual(
        monthsBetween(today, three.horizonEnd),
        months.size(),
        'nenhum mes do horizonte fica implicito'
      );
    }
  }

  @IsTest
  static void multiCurrencyUnboundedFloorAndPlanCeilingAreExplicit() {
    System.runAs(byAlias('axf137g')) {
      Account ana = holder('Ana Moedas');
      Date today = Date.today();
      Date nextMonth = today.addMonths(1).toStartOfMonth().addDays(4);
      AXF_OBJ_FinancialTransaction__c usd = plan(
        ana.Id,
        'usd',
        100,
        'DEBIT',
        'PLANNED',
        nextMonth,
        false
      );
      usd.AXF_FTX_TXT_CurrencyIsoCode__c = 'USD';
      // Purchased 13 months ago, due last month: overdue and still visible.
      AXF_OBJ_FinancialTransaction__c oldPurchase = plan(
        ana.Id,
        'old-purchase',
        40,
        'DEBIT',
        'PLANNED',
        today.addDays(-20),
        false
      );
      oldPurchase.AXF_FTX_DAT_PurchaseDate__c = today.addMonths(-13);
      // Due 13 months ago: outside the one-year window by due date.
      AXF_OBJ_FinancialTransaction__c ancient = plan(
        ana.Id,
        'ancient',
        7,
        'DEBIT',
        'PLANNED',
        today.addMonths(-13),
        false
      );
      insert new List<AXF_OBJ_FinancialTransaction__c>{
        plan(ana.Id, 'brl', 300, 'DEBIT', 'PLANNED', nextMonth, false),
        usd,
        oldPurchase,
        ancient
      };
      ALT_CLS_ForecastComparisonService service = new ALT_CLS_ForecastComparisonService();
      Test.startTest();
      ALT_CLS_ForecastComparisonService.Result mixed = service.compare(
        input(
          new List<Id>{ ana.Id },
          3,
          ALT_CLS_ForecastComparisonService.SCENARIO_INTERMEDIATE
        )
      );
      Test.stopTest();
      Assert.areEqual(new List<String>{ 'BRL', 'USD' }, mixed.currencies);
      Assert.isTrue(mixed.reasons.contains('MULTI_CURRENCY'));
      Assert.areEqual(16, mixed.horizons.size(), 'oito horizontes por moeda');
      Assert.areEqual(300, horizon(mixed, 3, 'BRL').probableOut, 'BRL isolado');
      Assert.areEqual(100, horizon(mixed, 3, 'USD').probableOut, 'USD isolado');
      Assert.areEqual(1, mixed.overdue.size());
      Assert.areEqual(
        40,
        mixed.overdue[0].amountOut,
        'compra antiga com vencimento recente continua vencida e visivel'
      );
      Assert.areEqual(
        1,
        mixed.overdue[0].count,
        'vencido ha 13 meses fica fora da janela'
      );

      // Indefinite recurrence: coverage incomplete and no method approved for its reference
      // amounts, so the commitment is reported and never closed into a total.
      ALT_CLS_FinancialScheduleService.CreateInput open = new ALT_CLS_FinancialScheduleService.CreateInput();
      open.accountId = ana.Id;
      open.direction = 'DEBIT';
      open.currencyIsoCode = 'BRL';
      open.method = 'ESTIMATED';
      open.totalInstallments = null;
      open.firstSequence = 1;
      open.trackingStartSequence = 1;
      open.trackingDueDate = nextMonth;
      open.periodMonths = 1;
      open.referenceAmount = 90;
      open.legacyGroupKey = 'fc-open';
      ALT_CLS_FinancialScheduleService.CreateResult created = ALT_CLS_FinancialScheduleService.createSchedule(
        open
      );
      Assert.areEqual('CREATED', created.outcome, created.message);
      ALT_CLS_ForecastComparisonService.Result unbounded = service.compare(
        input(
          new List<Id>{ ana.Id },
          3,
          ALT_CLS_ForecastComparisonService.SCENARIO_CONSERVATIVE
        )
      );
      ALT_CLS_ForecastComparisonService.SourceView scheduleView;
      for (
        ALT_CLS_ForecastComparisonService.SourceView source : unbounded.sources
      ) {
        if (source.kind == 'SCHEDULE') {
          scheduleView = source;
        }
      }
      Assert.isNotNull(scheduleView);
      Assert.isFalse(scheduleView.coverageComplete, 'cobertura incompleta');
      Assert.isTrue(scheduleView.unbounded, 'recorrencia indefinida');
      Assert.isTrue(unbounded.unboundedCommitment);
      Assert.isTrue(unbounded.reasons.contains('COMMITMENT_UNBOUNDED'));
      Assert.isTrue(unbounded.reasons.contains('NO_APPROVED_METHOD'));
      Assert.areEqual(
        ALT_CLS_ForecastComparisonService.CONFIDENCE_BLOCKED,
        unbounded.confidence,
        'a recorrencia estimada nao tem metodo aprovado: omite-la poderia aumentar a capacidade'
      );

      // Plan ceiling refuses instead of truncating (seam mirrors scheduleLimit).
      try {
        ALT_CLS_ForecastComparisonService.planLimit = 0;
        ALT_CLS_ForecastComparisonService.Result volume = service.compare(
          input(
            new List<Id>{ ana.Id },
            3,
            ALT_CLS_ForecastComparisonService.SCENARIO_CONSERVATIVE
          )
        );
        Assert.isTrue(volume.reasons.contains('VOLUME_EXCEEDED'));
        Assert.areEqual(
          ALT_CLS_ForecastComparisonService.CONFIDENCE_BLOCKED,
          volume.confidence
        );
        Assert.isTrue(volume.horizons.isEmpty(), 'recusa, nao trunca');
      } finally {
        ALT_CLS_ForecastComparisonService.planLimit = ALT_CLS_ForecastComparisonService.MAX_PLANS;
      }
    }
  }

  @IsTest
  static void partialAccessDegradesStaleSchedulesBlockAndGuardsHold() {
    Account shared;
    System.runAs(byAlias('axf137p')) {
      shared = holder('Empresa Parcial');
      insert plan(
        shared.Id,
        'hidden',
        700,
        'DEBIT',
        'PLANNED',
        Date.today().addMonths(1),
        false
      );
      insert new AccountTeamMember(
        AccountId = shared.Id,
        UserId = byAlias('axf137g').Id,
        TeamMemberRole = ALT_CLS_AxonCompanyResponsible.validTeamRole(),
        AccountAccessLevel = 'Read',
        OpportunityAccessLevel = 'None',
        CaseAccessLevel = 'None'
      );
    }
    System.runAs(byAlias('axf137g')) {
      Account mine = holder('Empresa Minha');
      insert plan(
        mine.Id,
        'mine',
        50,
        'DEBIT',
        'PLANNED',
        Date.today().addMonths(1),
        false
      );
      ALT_CLS_ForecastComparisonService service = new ALT_CLS_ForecastComparisonService();
      ALT_CLS_ForecastComparisonService.Result mixed = service.compare(
        input(
          new List<Id>{ mine.Id, shared.Id, null },
          12,
          ALT_CLS_ForecastComparisonService.SCENARIO_OPTIMISTIC
        )
      );
      Assert.areEqual(2, mixed.holders.size());
      Assert.isTrue(mixed.reasons.contains('COVERAGE_UNVERIFIED'));
      Assert.areEqual(
        ALT_CLS_ForecastComparisonService.CONFIDENCE_DEGRADED,
        mixed.confidence
      );
      Map<Id, String> states = new Map<Id, String>();
      for (
        ALT_CLS_ForecastComparisonService.HolderScope scope : mixed.holders
      ) {
        states.put(scope.accountId, scope.state);
      }
      Assert.areEqual('AUTHORIZED', states.get(mine.Id));
      Assert.areEqual('UNKNOWN', states.get(shared.Id), 'parcial e retido');
      Assert.areEqual(1, mixed.exclusions.size(), 'uma exclusao explicita');
      Assert.areEqual(shared.Id, mixed.exclusions[0].accountId);
      Assert.areEqual('COVERAGE_UNVERIFIED', mixed.exclusions[0].reason);
      // The withheld holder never contributes: no total, period or source carries 700.
      for (
        ALT_CLS_ForecastComparisonService.HorizonTotal total : mixed.horizons
      ) {
        Assert.areNotEqual(
          700,
          total.probableOut,
          'valor do titular parcial nao vaza'
        );
        Assert.areNotEqual(750, total.probableOut);
      }
      Assert.areEqual(50, horizon(mixed, 12, 'BRL').probableOut);
      Assert.areEqual(
        1,
        mixed.sources.size(),
        'so a fonte do titular autorizado'
      );
      Assert.areEqual(1, mixed.sources[0].occurrenceCount);

      // A non-Axon account and an invisible account are excluded with their own reason.
      Account plain = new Account(Name = 'Sem tipo Axon');
      insert plain;
      ALT_CLS_ForecastComparisonService.Result typed = service.compare(
        input(
          new List<Id>{ mine.Id, plain.Id },
          12,
          ALT_CLS_ForecastComparisonService.SCENARIO_OPTIMISTIC
        )
      );
      Assert.areEqual(1, typed.exclusions.size());
      Assert.areEqual('NOT_A_HOLDER', typed.exclusions[0].reason);
      ALT_CLS_ForecastComparisonService.Result none = service.compare(
        input(
          new List<Id>{ shared.Id },
          12,
          ALT_CLS_ForecastComparisonService.SCENARIO_CONSERVATIVE
        )
      );
      Assert.areEqual(
        ALT_CLS_ForecastComparisonService.CONFIDENCE_BLOCKED,
        none.confidence
      );
      Assert.isTrue(none.reasons.contains('NO_AUTHORIZED_SCOPE'));
      Assert.isTrue(none.allowedActions.isEmpty());
      Assert.isTrue(none.horizons.isEmpty(), 'ausencia nao vira zero');

      // A stale projection is material: BLOCKED with the explicit reason.
      ALT_CLS_FinancialScheduleService.CreateResult created = schedule(
        mine.Id,
        'INSTALLMENT',
        12,
        1,
        Date.today().addMonths(1),
        'fc-stale'
      );
      ALT_CLS_ForecastComparisonService.Result stale;
      try {
        ALT_CLS_ScheduleProjection.recheckOverride = new AXF_OBJ_FinancialSchedule__c(
          Id = created.scheduleId,
          AXF_FSC_NUM_ProjectionRevision__c = 999,
          AXF_FSC_NUM_FinancialVersion__c = 999
        );
        stale = service.compare(
          input(
            new List<Id>{ mine.Id },
            12,
            ALT_CLS_ForecastComparisonService.SCENARIO_CONSERVATIVE
          )
        );
      } finally {
        ALT_CLS_ScheduleProjection.recheckOverride = null;
      }
      Assert.areEqual(
        ALT_CLS_ForecastComparisonService.CONFIDENCE_BLOCKED,
        stale.confidence
      );
      Assert.isTrue(
        stale.reasons.contains('SCHEDULE_STALE'),
        String.join(stale.reasons, ',')
      );
      Assert.areEqual('STALE', stale.sources[0].outcome);

      // Volume ceiling refuses instead of truncating.
      ALT_CLS_ForecastComparisonService.Result volume;
      try {
        ALT_CLS_ForecastComparisonService.scheduleLimit = 0;
        volume = service.compare(
          input(
            new List<Id>{ mine.Id },
            12,
            ALT_CLS_ForecastComparisonService.SCENARIO_CONSERVATIVE
          )
        );
      } finally {
        ALT_CLS_ForecastComparisonService.scheduleLimit = ALT_CLS_ForecastComparisonService.MAX_SCHEDULES;
      }
      Assert.isTrue(volume.reasons.contains('VOLUME_EXCEEDED'));
      Assert.areEqual(
        ALT_CLS_ForecastComparisonService.CONFIDENCE_BLOCKED,
        volume.confidence
      );

      // asOf in the past is echoed, not silently replaced.
      ALT_CLS_ForecastComparisonService.Input past = input(
        new List<Id>{ mine.Id },
        3,
        ALT_CLS_ForecastComparisonService.SCENARIO_CONSERVATIVE
      );
      past.asOf = Date.today().addDays(-3);
      ALT_CLS_ForecastComparisonService.Result echoed = service.compare(past);
      Assert.areEqual(past.asOf, echoed.asOf);
      Assert.isTrue(echoed.reasons.contains('AS_OF_NOT_TODAY'));

      for (
        ALT_CLS_ForecastComparisonService.Input bad : new List<ALT_CLS_ForecastComparisonService.Input>{
          null,
          input(new List<Id>{ null }, 12, 'CONSERVATIVE'),
          input(new List<Id>{ mine.Id }, 7, 'CONSERVATIVE'),
          input(new List<Id>{ mine.Id }, 12, 'LIKELY')
        }
      ) {
        try {
          service.compare(bad);
          Assert.fail('INVALID_INPUT');
        } catch (ALT_CLS_ForecastComparisonService.ForecastException expected) {
          Assert.areEqual('INVALID_INPUT', expected.code);
        }
      }
    }
    System.runAs(byAlias('axf137n')) {
      try {
        new ALT_CLS_ForecastComparisonService()
          .compare(input(new List<Id>{ shared.Id }, 12, 'CONSERVATIVE'));
        Assert.fail('sem capacidade');
      } catch (ALT_CLS_ForecastComparisonService.ForecastException expected) {
        Assert.areEqual('FORBIDDEN', expected.code);
      }
    }
  }

  /**
   * AXF-138, GF-76 — every contribution is placed in a §3 class with the §2 evidence authority
   * and the method v1.0.0 permits for it; the overlap between a schedule and the persisted row
   * that restates it is resolved once, and the taxonomy, cutoff, currencies and policy identity
   * travel with the result.
   */
  @IsTest
  static void policyClassificationRecordsAuthorityMethodAndResolvedOverlaps() {
    System.runAs(byAlias('axf137g')) {
      Account ana = holder('Ana PolÃ­tica');
      Date today = Date.today();
      Date nextMonth = today.addMonths(1).toStartOfMonth().addDays(6);
      ALT_CLS_FinancialScheduleService.CreateResult created = schedule(
        ana.Id,
        'INSTALLMENT',
        6,
        1,
        nextMonth,
        'policy-authority'
      );
      insert new List<AXF_OBJ_FinancialTransaction__c>{
        plan(ana.Id, 'fact', 400, 'CREDIT', 'CONFIRMED', nextMonth, false),
        plan(ana.Id, 'scenario', 150, 'DEBIT', 'PLANNED', nextMonth, false)
      };
      ALT_CLS_ScheduleProjection.ProjectionInput read = new ALT_CLS_ScheduleProjection.ProjectionInput();
      read.scheduleId = created.scheduleId;
      read.asOfDate = today;
      ALT_CLS_ScheduleProjection.ProjectionResult projection = ALT_CLS_FinancialScheduleService.readProjection(
        read
      );
      Assert.areEqual('OK', projection.outcome, projection.message);
      Integer persisted = 0;
      for (ALT_CLS_ScheduleProjection.OccurrenceLine line : projection.lines) {
        if (line.persisted == true) {
          persisted++;
        }
      }
      Assert.isTrue(
        persisted > 0,
        'a janela operacional ja tem linhas persistidas'
      );
      ALT_CLS_ForecastComparisonService service = new ALT_CLS_ForecastComparisonService();
      Test.startTest();
      ALT_CLS_ForecastComparisonService.Result result = service.compare(
        input(
          new List<Id>{ ana.Id },
          6,
          ALT_CLS_ForecastComparisonService.SCENARIO_OPTIMISTIC
        )
      );
      Test.stopTest();
      Assert.areEqual(
        ALT_CLS_ForecastComparisonService.CATEGORY_TAXONOMY,
        result.categoryTaxonomy
      );
      Assert.areEqual(
        ALT_CLS_ForecastComparisonService.POLICY_VERSION,
        result.policyVersion
      );
      Assert.areEqual(today, result.asOf, 'o corte e a data de posicao');
      Assert.areEqual(
        new List<String>{ 'BRL' },
        result.currencies,
        'FX preservado'
      );
      Assert.isTrue(
        result.fallbacks.isEmpty(),
        'nenhum fallback foi necessario'
      );
      Map<String, ALT_CLS_ForecastComparisonService.CategoryView> byClass = new Map<String, ALT_CLS_ForecastComparisonService.CategoryView>();
      for (
        ALT_CLS_ForecastComparisonService.CategoryView view : result.categories
      ) {
        byClass.put(view.category + '|' + String.valueOf(view.authority), view);
      }
      ALT_CLS_ForecastComparisonService.CategoryView contractual = byClass.get(
        ALT_CLS_ForecastComparisonService.CATEGORY_CONTRACTUAL_INSTALLMENT +
          '|' +
          ALT_CLS_ForecastComparisonService.AUTHORITY_CONTRACT_INSTALLMENT
      );
      Assert.isNotNull(contractual, 'cronograma de parcelamento e contratual');
      Assert.areEqual(
        ALT_CLS_ForecastComparisonService.METHOD_AUTHORITATIVE_SCHEDULE,
        contractual.method
      );
      Assert.areEqual(
        projection.lines.size(),
        contractual.contributionCount,
        'cada ocorrencia do cronograma entra uma vez'
      );
      Assert.areEqual(
        ALT_CLS_ForecastComparisonService.METHOD_INTEGRAL_SCENARIO_INCLUSION,
        byClass.get(
            ALT_CLS_ForecastComparisonService.CATEGORY_EXPLICIT_SCENARIO_ITEM +
              '|' +
              ALT_CLS_ForecastComparisonService.AUTHORITY_CONFIRMED_FACT
          )
          .method,
        'fato confirmado e evidencia de autoridade 1'
      );
      Assert.areEqual(
        1,
        byClass.get(
            ALT_CLS_ForecastComparisonService.CATEGORY_EXPLICIT_SCENARIO_ITEM +
              '|' +
              ALT_CLS_ForecastComparisonService.AUTHORITY_CONFIRMED_FACT
          )
          .contributionCount
      );
      Assert.areEqual(
        1,
        byClass.get(
            ALT_CLS_ForecastComparisonService.CATEGORY_EXPLICIT_SCENARIO_ITEM +
              '|' +
              ALT_CLS_ForecastComparisonService.AUTHORITY_SCENARIO_ITEM
          )
          .contributionCount,
        'o item explicito de cenario e autoridade 5'
      );
      // §2: the persisted occurrence is counted once, by the schedule that owns it.
      ALT_CLS_ForecastComparisonService.SourceView scheduleView;
      for (
        ALT_CLS_ForecastComparisonService.SourceView source : result.sources
      ) {
        if (source.kind == 'SCHEDULE') {
          scheduleView = source;
        }
      }
      Assert.isNotNull(scheduleView);
      Assert.areEqual(persisted, scheduleView.resolvedOverlapCount);
      // No duplication: inside + beyond still equals the single remaining commitment.
      ALT_CLS_ForecastComparisonService.HorizonTotal h24 = horizon(
        result,
        24,
        'BRL'
      );
      Assert.areEqual(
        projection.totalRemaining.setScale(2),
        (h24.confirmedOut + h24.beyondOut).setScale(2)
      );
      Assert.areEqual(
        150,
        h24.probableOut,
        'o item de cenario nao foi duplicado'
      );
    }
  }

  /**
   * AXF-138, GF-77 — a class v1.0.0 gives no method to is never estimated. The occurrence of a
   * schedule whose amount comes from a reference value instead of the approved formula — created
   * through the normal schedule command, no field blanked — asserts no amount, tier or
   * probability and is recorded as an exclusion of its holder; because its omission could
   * increase the capacity shown the result is BLOCKED, while the same occurrence as an inflow
   * cannot increase capacity and stays display-only.
   */
  @IsTest
  static void classWithoutApprovedMethodIsNotEstimatedAndGatesByMaterialImpact() {
    System.runAs(byAlias('axf137g')) {
      Account debitHolder = holder('Ana Sem Metodo Debito');
      Account creditHolder = holder('Ana Sem Metodo Credito');
      Date today = Date.today();
      Date nextMonth = today.addMonths(1).toStartOfMonth().addDays(6);
      // Both schedules are created by the normal command path: the estimated one takes its
      // amounts from a reference value, the permitted one from the approved formula.
      ALT_CLS_FinancialScheduleService.CreateResult unauthorized = schedule(
        debitHolder.Id,
        'ESTIMATED',
        6,
        1,
        nextMonth,
        'policy-noauthority'
      );
      ALT_CLS_FinancialScheduleService.CreateResult permitted = schedule(
        debitHolder.Id,
        'INSTALLMENT',
        6,
        1,
        nextMonth,
        'policy-permitted'
      );
      ALT_CLS_FinancialScheduleService.CreateInput credit = new ALT_CLS_FinancialScheduleService.CreateInput();
      credit.accountId = creditHolder.Id;
      credit.direction = 'CREDIT';
      credit.currencyIsoCode = 'BRL';
      credit.method = 'ESTIMATED';
      credit.totalInstallments = 6;
      credit.firstSequence = 1;
      credit.trackingStartSequence = 1;
      credit.trackingDueDate = nextMonth;
      credit.periodMonths = 1;
      credit.referenceAmount = 500;
      credit.legacyGroupKey = 'policy-noauthority-cred';
      ALT_CLS_FinancialScheduleService.CreateResult creditSchedule = ALT_CLS_FinancialScheduleService.createSchedule(
        credit
      );
      Assert.areEqual(
        'CREATED',
        creditSchedule.outcome,
        creditSchedule.message
      );
      // The estimated schedule projects normally: its amounts exist and are readable. Only the
      // policy's category → method table has no method for the class that produced them.
      ALT_CLS_ScheduleProjection.ProjectionInput read = new ALT_CLS_ScheduleProjection.ProjectionInput();
      read.scheduleId = unauthorized.scheduleId;
      read.asOfDate = today;
      ALT_CLS_ScheduleProjection.ProjectionResult projection = ALT_CLS_FinancialScheduleService.readProjection(
        read
      );
      Assert.areEqual(
        'OK',
        projection.outcome,
        'o cronograma continua projetavel: ' + projection.message
      );
      Assert.isTrue(projection.totalRemaining > 0);
      ALT_CLS_ForecastComparisonService service = new ALT_CLS_ForecastComparisonService();
      Test.startTest();
      ALT_CLS_ForecastComparisonService.Result debit = service.compare(
        input(
          new List<Id>{ debitHolder.Id },
          6,
          ALT_CLS_ForecastComparisonService.SCENARIO_OPTIMISTIC
        )
      );
      ALT_CLS_ForecastComparisonService.Result creditResult = service.compare(
        input(
          new List<Id>{ creditHolder.Id },
          6,
          ALT_CLS_ForecastComparisonService.SCENARIO_OPTIMISTIC
        )
      );
      Test.stopTest();
      Assert.isTrue(debit.reasons.contains('NO_APPROVED_METHOD'));
      Assert.areEqual(
        ALT_CLS_ForecastComparisonService.CONFIDENCE_BLOCKED,
        debit.confidence,
        'omitir uma obrigacao poderia aumentar a capacidade mostrada'
      );
      Assert.isTrue(
        debit.fallbacks.contains(
          ALT_CLS_ForecastComparisonService.FALLBACK_BLOCKED_MATERIAL_OMISSION
        ),
        String.join(debit.fallbacks, ',')
      );
      // The class is recorded with no method and with no authority that was never established,
      // and it counts no contribution: the occurrence never became one.
      ALT_CLS_ForecastComparisonService.CategoryView unclassified = categoryOf(
        debit,
        ALT_CLS_ForecastComparisonService.CATEGORY_UNPREDICTABLE_STATISTICAL
      );
      Assert.isNotNull(unclassified, 'a classe sem metodo e registrada');
      Assert.isNull(
        unclassified.method,
        'v1.0.0 nao aprova metodo para a classe'
      );
      Assert.isNull(
        unclassified.authority,
        'nenhuma autoridade foi estabelecida para a classe'
      );
      Assert.areEqual(
        0,
        unclassified.contributionCount,
        'a ocorrencia sem metodo nao virou contribuicao'
      );
      // The omission is recorded against its holder, so the total is not silently short.
      Assert.areEqual(
        1,
        debit.exclusions.size(),
        'uma exclusao por titular e motivo'
      );
      Assert.areEqual(debitHolder.Id, debit.exclusions[0].accountId);
      Assert.areEqual('NO_APPROVED_METHOD', debit.exclusions[0].reason);
      // Nothing is asserted for the class without a method: only the permitted schedule counts.
      ALT_CLS_ScheduleProjection.ProjectionInput permittedRead = new ALT_CLS_ScheduleProjection.ProjectionInput();
      permittedRead.scheduleId = permitted.scheduleId;
      permittedRead.asOfDate = today;
      ALT_CLS_ScheduleProjection.ProjectionResult permittedProjection = ALT_CLS_FinancialScheduleService.readProjection(
        permittedRead
      );
      Assert.areEqual(
        'OK',
        permittedProjection.outcome,
        permittedProjection.message
      );
      Decimal permittedTotal = 0;
      for (
        ALT_CLS_ScheduleProjection.OccurrenceLine line : permittedProjection.lines
      ) {
        if (line.effectiveDueDate <= debit.horizonEnd) {
          permittedTotal += line.amount;
        }
      }
      ALT_CLS_ForecastComparisonService.HorizonTotal debitTotal = horizon(
        debit,
        6,
        'BRL'
      );
      Assert.areEqual(
        permittedTotal.setScale(2),
        (debitTotal.confirmedOut + debitTotal.probableOut).setScale(2),
        'nenhuma media, peso ou probabilidade foi inventada para a classe sem metodo'
      );
      Assert.areEqual(0, debitTotal.uncertainOut, 'nada incerto foi inventado');
      ALT_CLS_ForecastComparisonService.CategoryView contractual = categoryOf(
        debit,
        ALT_CLS_ForecastComparisonService.CATEGORY_CONTRACTUAL_INSTALLMENT
      );
      Assert.areEqual(
        permittedProjection.lines.size(),
        contractual.contributionCount,
        'so a ocorrencia com metodo aprovado vira contribuicao'
      );
      // An inflow omission cannot increase the capacity shown: display-only, never a total.
      Assert.areEqual(
        ALT_CLS_ForecastComparisonService.CONFIDENCE_INFORMATIVE,
        creditResult.confidence
      );
      Assert.isTrue(
        creditResult.fallbacks.contains(
          ALT_CLS_ForecastComparisonService.FALLBACK_INFORMATIVE_DISPLAY
        ),
        String.join(creditResult.fallbacks, ',')
      );
      Assert.isTrue(creditResult.reasons.contains('NO_APPROVED_METHOD'));
      Assert.areEqual(1, creditResult.exclusions.size());
      Assert.areEqual(creditHolder.Id, creditResult.exclusions[0].accountId);
      Assert.areEqual('NO_APPROVED_METHOD', creditResult.exclusions[0].reason);
      Assert.areEqual(
        0,
        categoryOf(
            creditResult,
            ALT_CLS_ForecastComparisonService.CATEGORY_UNPREDICTABLE_STATISTICAL
          )
          .contributionCount
      );
      Assert.isTrue(
        creditResult.horizons.isEmpty(),
        'a classe sem metodo nao contribui com nenhum total'
      );
    }
  }

  private static ALT_CLS_ForecastComparisonService.CategoryView categoryOf(
    ALT_CLS_ForecastComparisonService.Result result,
    String category
  ) {
    for (
      ALT_CLS_ForecastComparisonService.CategoryView view : result.categories
    ) {
      if (view.category == category) {
        return view;
      }
    }
    return null;
  }

  @IsTest
  static void controllerSanitizesAndDelegates() {
    System.runAs(byAlias('axf137g')) {
      Account ana = holder('Ana Controller');
      insert plan(
        ana.Id,
        'ctl',
        10,
        'DEBIT',
        'PLANNED',
        Date.today().addMonths(2),
        false
      );
      AXF_CLS_CTRL_ForecastComparison.Context context = AXF_CLS_CTRL_ForecastComparison.getContext(
        ''
      );
      Assert.isTrue(context.canCompare);
      Assert.areEqual(8, context.horizons.size());
      Assert.isFalse(context.holders.isEmpty());
      try {
        AXF_CLS_CTRL_ForecastComparison.compare('{"nope":1}');
        Assert.fail('JSON invalido');
      } catch (AuraHandledException expected) {
        Assert.areEqual('INVALID_INPUT', expected.getMessage());
      }
      ALT_CLS_ForecastComparisonService.Result result = AXF_CLS_CTRL_ForecastComparison.compare(
        JSON.serialize(input(new List<Id>{ ana.Id }, 6, 'INTERMEDIATE'))
      );
      Assert.areEqual(6, result.horizonMonths);
      Assert.areEqual(10, horizon(result, 6, 'BRL').probableOut);
    }
    System.runAs(byAlias('axf137n')) {
      AXF_CLS_CTRL_ForecastComparison.Context context = AXF_CLS_CTRL_ForecastComparison.getContext(
        ''
      );
      Assert.isFalse(context.canCompare);
      Assert.isTrue(context.holders.isEmpty());
      try {
        AXF_CLS_CTRL_ForecastComparison.compare(
          JSON.serialize(
            input(new List<Id>{ byAlias('axf137n').Id }, 3, 'CONSERVATIVE')
          )
        );
        Assert.fail('sanitizado');
      } catch (AuraHandledException expected) {
        Assert.areEqual('FORBIDDEN', expected.getMessage());
      }
    }
  }
}
