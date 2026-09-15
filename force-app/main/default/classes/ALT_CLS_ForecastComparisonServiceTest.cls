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
      // Estimated recurrence: reference value, PROBABLE tier.
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
      // rent 2000 + estimated occurrences of 500 in months +1 and +2 (horizon = current + 2)
      Assert.areEqual(
        2000 + 1000,
        h3.probableOut,
        'provavel: plano + estimados'
      );
      Assert.areEqual(0, h3.uncertainOut, 'viagem estimada so daqui a 5 meses');
      Assert.areEqual(5000, h3.conservativeNet);
      Assert.areEqual(5000 - 3000, h3.intermediateNet);
      Assert.areEqual(
        5000 - 3000,
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
      Assert.areEqual(
        ALT_CLS_ForecastComparisonService.CONFIDENCE_DEGRADED,
        three.confidence
      );
      Assert.areEqual(
        2,
        three.sources.size(),
        'cronograma estimado + planos avulsos'
      );
      Boolean paidCounted = false;
      for (
        ALT_CLS_ForecastComparisonService.PeriodView period : three.periods
      ) {
        if (period.confirmedOut == 999) {
          paidCounted = true;
        }
      }
      Assert.isFalse(
        paidCounted,
        'confirmado no passado e historico, nao previsao'
      );
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
      Assert.isFalse(
        JSON.serialize(mixed).contains('700'),
        'valor do titular parcial nao vaza'
      );
      Assert.areEqual(50, horizon(mixed, 12, 'BRL').probableOut);
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
      ALT_CLS_ScheduleProjection.recheckOverride = new AXF_OBJ_FinancialSchedule__c(
        Id = created.scheduleId,
        AXF_FSC_NUM_ProjectionRevision__c = 999,
        AXF_FSC_NUM_FinancialVersion__c = 999
      );
      ALT_CLS_ForecastComparisonService.Result stale = service.compare(
        input(
          new List<Id>{ mine.Id },
          12,
          ALT_CLS_ForecastComparisonService.SCENARIO_CONSERVATIVE
        )
      );
      ALT_CLS_ScheduleProjection.recheckOverride = null;
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
      ALT_CLS_ForecastComparisonService.scheduleLimit = 0;
      ALT_CLS_ForecastComparisonService.Result volume = service.compare(
        input(
          new List<Id>{ mine.Id },
          12,
          ALT_CLS_ForecastComparisonService.SCENARIO_CONSERVATIVE
        )
      );
      ALT_CLS_ForecastComparisonService.scheduleLimit = ALT_CLS_ForecastComparisonService.MAX_SCHEDULES;
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
