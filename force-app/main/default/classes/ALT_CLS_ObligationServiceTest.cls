/**
 * @description Contratos de realização ajustada, ajustes de obrigação com sinal e revisão de
 * referência recorrente (AXF-104) sobre a fundação AXF-103.
 *
 * As evidências novas nascem sem acesso nativo: as leituras de verificação usam o mesmo modo
 * de sistema que o serviço usa, porque a fronteira de conservação é a capacidade autorizada,
 * não a FLS. A concessão de visibilidade a usuários reais é um artefato de permissão separado.
 */
@IsTest(isParallel=false)
private class ALT_CLS_ObligationServiceTest {
  private static User actor() {
    return [SELECT Id FROM User WHERE Alias = 'axf104' LIMIT 1];
  }

  @TestSetup
  static void setup() {
    User actor = new User(
      Alias = 'axf104',
      Email = 'axf104@example.invalid',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Obligation Tester',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      TimeZoneSidKey = 'America/Sao_Paulo',
      ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
      .Id,
      Username = 'axf104.' + System.now().getTime() + '@example.invalid'
    );
    insert actor;
    List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (PermissionSet permission : [
      SELECT Id
      FROM PermissionSet
      WHERE
        Name IN (
          'AXF_PS_Realization',
          'AXF_PS_FinancialEntry',
          'AXF_PS_GestorFinanceiro'
        )
    ]) {
      assignments.add(
        new PermissionSetAssignment(
          AssigneeId = actor.Id,
          PermissionSetId = permission.Id
        )
      );
    }
    insert assignments;
    PermissionSet capability = new PermissionSet(
      Name = 'AXF104TestCapability',
      Label = 'AXF104 test capability'
    );
    insert capability;
    insert new SetupEntityAccess(
      ParentId = capability.Id,
      SetupEntityId = [
        SELECT Id
        FROM CustomPermission
        WHERE DeveloperName = 'AXF_CanRealize'
      ]
      .Id
    );
    insert new PermissionSetAssignment(
      AssigneeId = actor.Id,
      PermissionSetId = capability.Id
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert new AXF_ReportCurrencyPref__c(
        SetupOwnerId = UserInfo.getOrganizationId(),
        AXF_RCP_TXT_IsoCode__c = 'BRL'
      );
    }
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

  /**
   * @description Cronograma estimado real da fundação AXF-103: a referência inicial é o
   * recorrente conhecido e cada ocorrência nasce com base corrente igual a ela.
   */
  private static ALT_CLS_FinancialScheduleService.CreateResult estimatedSchedule(
    Id accountId,
    Decimal recurringAmount,
    String suffix
  ) {
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      accountId
    };
    ALT_CLS_FinancialScheduleService.CreateInput input = new ALT_CLS_FinancialScheduleService.CreateInput();
    input.accountId = accountId;
    input.direction = 'DEBIT';
    input.currencyIsoCode = 'BRL';
    input.method = 'ESTIMATED';
    input.totalInstallments = 24;
    input.firstSequence = 1;
    input.firstDueDate = Date.today();
    input.trackingStartSequence = 1;
    input.trackingDueDate = Date.today();
    input.periodMonths = 1;
    input.referenceAmount = recurringAmount;
    input.reason = 'AXF-104 fixture ' + suffix;
    input.timeZone = 'America/Sao_Paulo';
    ALT_CLS_FinancialScheduleService.CreateResult result = ALT_CLS_FinancialScheduleService.createSchedule(
      input
    );
    Assert.areEqual('CREATED', result.outcome, result.message);
    return result;
  }

  private static AXF_OBJ_FinancialTransaction__c occurrence(
    Id scheduleId,
    Integer sequence
  ) {
    return [
      SELECT
        Id,
        AXF_FTX_NUM_Version__c,
        AXF_FTX_NUM_Magnitude__c,
        AXF_FTX_NUM_CurrentBasis__c,
        AXF_FTX_BOL_BasisFrozen__c,
        AXF_FTX_NUM_Sequence__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE
        AXF_FTX_LKP_Schedule__c = :scheduleId
        AND AXF_FTX_NUM_Sequence__c = :sequence
      LIMIT 1
    ];
  }

  private static Decimal versionOf(Id targetId) {
    return [
      SELECT AXF_FTX_NUM_Version__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE Id = :targetId
    ]
    .AXF_FTX_NUM_Version__c;
  }

  private static ALT_CLS_ObligationService.SettlementInput cashRequest(
    Id targetId,
    String operationKey,
    String mode,
    Decimal amount,
    Decimal expectedVersion
  ) {
    ALT_CLS_ObligationService.SettlementInput input = new ALT_CLS_ObligationService.SettlementInput();
    input.operationKey = operationKey;
    input.targetId = targetId;
    input.mode = mode;
    input.amount = amount;
    input.currencyIso = 'BRL';
    input.economicDate = Date.today();
    input.expectedTargetVersion = expectedVersion;
    input.sourceKind = 'CASH';
    input.classification = mode == ALT_CLS_ObligationService.MODE_FULL
      ? ALT_CLS_ObligationService.CLASSIFICATION_UNCLASSIFIED
      : ALT_CLS_ObligationService.CLASSIFICATION_NOT_APPLICABLE;
    input.explanation = 'Diferença revisada explicitamente.';
    return input;
  }

  /** @description FULL explicado: a decomposição descreve a parcela INTEIRA liquidada. */
  private static void explained(
    ALT_CLS_ObligationService.SettlementInput input,
    Decimal recurring,
    Decimal charges,
    Decimal discount
  ) {
    input.classification = ALT_CLS_ObligationService.CLASSIFICATION_EXPLAINED;
    input.recurringAmount = recurring;
    input.exceptionalCharges = charges;
    input.oneOffDiscount = discount;
    input.explanation = 'Parcela integral revisada explicitamente.';
  }

  private static ALT_CLS_ObligationService.SettlementResult applyCash(
    ALT_CLS_ObligationService.SettlementInput input
  ) {
    return new ALT_CLS_ObligationService().apply(input);
  }

  private static Integer countReference(Id scheduleId, String kind) {
    return [
      SELECT COUNT()
      FROM AXF_OBJ_ScheduleReference__c
      WHERE
        AXF_SRF_LKP_Schedule__c = :scheduleId
        AND AXF_SRF_PKL_Kind__c = :kind
      WITH SYSTEM_MODE
    ];
  }

  private static Decimal referenceAmountOf(Id referenceId) {
    return [
      SELECT AXF_SRF_NUM_RecurringAmount__c
      FROM AXF_OBJ_ScheduleReference__c
      WHERE Id = :referenceId
      WITH SYSTEM_MODE
    ]
    .AXF_SRF_NUM_RecurringAmount__c;
  }

  private static AXF_OBJ_SettlementDecision__c decisionOf(Id decisionId) {
    return [
      SELECT
        AXF_SDC_NUM_RecurringAmount__c,
        AXF_SDC_NUM_ExceptionalCharges__c,
        AXF_SDC_NUM_OneOffDiscount__c,
        AXF_SDC_NUM_EffectiveObligation__c,
        AXF_SDC_TXT_CoverageHash__c,
        AXF_SDC_NUM_CoverageCount__c,
        AXF_SDC_PKL_Operation__c,
        AXF_SDC_PKL_Mode__c,
        AXF_SDC_PKL_Classification__c,
        AXF_SDC_TAL_ResultJson__c
      FROM AXF_OBJ_SettlementDecision__c
      WHERE Id = :decisionId
      WITH SYSTEM_MODE
    ];
  }

  // ---------------------------------------------------------------------------------------
  // AC 2 / AC 3 �?" pagamento parcial nunca substitui a referência
  // ---------------------------------------------------------------------------------------
  @IsTest
  static void partialPaymentLeavesOutstandingObligationAndPublishesNoReference() {
    System.runAs(actor()) {
      Account owner = holder('AXF104 partial');
      ALT_CLS_FinancialScheduleService.CreateResult schedule = estimatedSchedule(
        owner.Id,
        1000,
        'partial'
      );
      AXF_OBJ_FinancialTransaction__c target = occurrence(
        schedule.scheduleId,
        1
      );

      ALT_CLS_ObligationService.SettlementResult result = applyCash(
        cashRequest(
          target.Id,
          'axf104-partial-400',
          ALT_CLS_ObligationService.MODE_PARTIAL,
          400,
          0
        )
      );

      Assert.areEqual('APPLIED', result.outcome, result.message);
      Assert.areEqual(1000.00, result.effectiveObligation);
      Assert.areEqual(400.00, result.netApplied);
      Assert.areEqual(600.00, result.outstandingObligation);
      Assert.areEqual(
        0.00,
        result.adjustmentTotal,
        'PARTIAL sem delta não cria ajuste'
      );
      Assert.isNull(result.adjustmentId);
      Assert.isNull(result.referenceId, 'PARTIAL não publica referência');
      Assert.areEqual(
        0,
        countReference(schedule.scheduleId, 'REALIZATION'),
        'Um pagamento parcial nunca substitui a referência recorrente'
      );
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM AXF_OBJ_ObligationAdjustment__c WITH SYSTEM_MODE]
      );

      ALT_CLS_ObligationService.ObligationView view = new ALT_CLS_ObligationService()
        .read(target.Id);
      Assert.areEqual(1000.00, view.basisAmount);
      Assert.areEqual(0.00, view.adjustmentTotal);
      Assert.areEqual(1000.00, view.effectiveObligation);
      Assert.areEqual(600.00, view.outstandingObligation);
      Assert.isTrue(
        view.basisFrozen,
        'A base congela no primeiro uso financeiro'
      );
      Assert.areEqual(
        1000.00,
        view.originalMagnitude,
        'A previsão original permanece preservada'
      );
    }
  }

  @IsTest
  static void partialEqualToOneSettlementIsRejectedInsteadOfContradictoryLabel() {
    System.runAs(actor()) {
      Account owner = holder('AXF104 settles');
      ALT_CLS_FinancialScheduleService.CreateResult schedule = estimatedSchedule(
        owner.Id,
        1000,
        'settles'
      );
      AXF_OBJ_FinancialTransaction__c target = occurrence(
        schedule.scheduleId,
        1
      );
      String code;
      try {
        applyCash(
          cashRequest(
            target.Id,
            'axf104-partial-full-amount',
            ALT_CLS_ObligationService.MODE_PARTIAL,
            1000,
            0
          )
        );
      } catch (ALT_CLS_ObligationService.ObligationException expected) {
        code = expected.getMessage();
      }
      Assert.areEqual(
        'SETTLES_OBLIGATION',
        code,
        'Um parcial que liquida por inteiro é explicado, não persistido como rótulo contraditório'
      );
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM AXF_OBJ_ReconciliationAllocation__c],
        'A falha reverte o efeito composto'
      );
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM AXF_OBJ_SettlementDecision__c WITH SYSTEM_MODE]
      );
    }
  }

  // ---------------------------------------------------------------------------------------
  // AC 9 / AC 10 �?" recorrente + excepcionais �^' desconto pontual = parcela inteira liquidada
  // ---------------------------------------------------------------------------------------
  @IsTest
  static void explainedFullPublishesTheRecurringComponentNotTheSettledTotal() {
    System.runAs(actor()) {
      Account owner = holder('AXF104 explained');
      ALT_CLS_FinancialScheduleService.CreateResult schedule = estimatedSchedule(
        owner.Id,
        1000,
        'explained'
      );
      AXF_OBJ_FinancialTransaction__c target = occurrence(
        schedule.scheduleId,
        1
      );
      applyCash(
        cashRequest(
          target.Id,
          'axf104-explained-prior-400',
          ALT_CLS_ObligationService.MODE_PARTIAL,
          400,
          versionOf(target.Id)
        )
      );
      ALT_CLS_ObligationService.SettlementInput full = cashRequest(
        target.Id,
        'axf104-explained-650',
        ALT_CLS_ObligationService.MODE_FULL,
        650,
        versionOf(target.Id)
      );
      explained(full, 1000, 50, 0);

      ALT_CLS_ObligationService.SettlementResult result = applyCash(full);

      Assert.areEqual('APPLIED', result.outcome, result.message);
      Assert.areEqual(
        1050.00,
        result.effectiveObligation,
        '400 anterior mais 650 liquida 1050'
      );
      Assert.areEqual(1050.00, result.netApplied);
      Assert.areEqual(0.00, result.outstandingObligation);
      Assert.areEqual(
        50.00,
        result.adjustmentTotal,
        'O encargo excepcional é um ajuste não monetário'
      );
      Assert.isNotNull(result.referenceId);
      AXF_OBJ_ScheduleReference__c published = [
        SELECT
          AXF_SRF_NUM_RecurringAmount__c,
          AXF_SRF_PKL_Kind__c,
          AXF_SRF_NUM_EconomicSequence__c,
          AXF_SRF_NUM_EffectiveSequence__c,
          AXF_SRF_LKP_SettlementDecision__c
        FROM AXF_OBJ_ScheduleReference__c
        WHERE Id = :result.referenceId
        WITH SYSTEM_MODE
      ];
      Assert.areEqual(
        1000.00,
        published.AXF_SRF_NUM_RecurringAmount__c,
        'A referência publica o recorrente, nunca 650 nem 1050'
      );
      Assert.areEqual('REALIZATION', published.AXF_SRF_PKL_Kind__c);
      Assert.areEqual(
        1,
        published.AXF_SRF_NUM_EconomicSequence__c.intValue(),
        'A ordem econômica de origem é a sequência absoluta da parcela'
      );
      Assert.areEqual(
        2,
        published.AXF_SRF_NUM_EffectiveSequence__c.intValue(),
        'A sequência efetiva é a PR�"XIMA parcela absoluta'
      );
      Assert.areEqual(
        result.decisionId,
        published.AXF_SRF_LKP_SettlementDecision__c,
        'A classificação da parcela inteira possui a referência'
      );
      AXF_OBJ_SettlementDecision__c decision = decisionOf(result.decisionId);
      Assert.areEqual('APPLY', decision.AXF_SDC_PKL_Operation__c);
      Assert.areEqual('FULL', decision.AXF_SDC_PKL_Mode__c);
      Assert.areEqual('EXPLAINED', decision.AXF_SDC_PKL_Classification__c);
      Assert.areEqual(1000.00, decision.AXF_SDC_NUM_RecurringAmount__c);
      Assert.areEqual(50.00, decision.AXF_SDC_NUM_ExceptionalCharges__c);
      Assert.areEqual(0.00, decision.AXF_SDC_NUM_OneOffDiscount__c);
      Assert.areEqual(1050.00, decision.AXF_SDC_NUM_EffectiveObligation__c);
      Assert.areEqual(64, decision.AXF_SDC_TXT_CoverageHash__c.length());
      Assert.areEqual(2, decision.AXF_SDC_NUM_CoverageCount__c.intValue());
      Assert.isTrue(
        decision.AXF_SDC_TAL_ResultJson__c.contains('referenceId'),
        'O recibo guarda o resultado autorizado para replay'
      );
    }
  }

  @IsTest
  static void explainedFullWithoutExceptionalComponentsRevisesLaterEstimate() {
    System.runAs(actor()) {
      Account owner = holder('AXF104 revision');
      ALT_CLS_FinancialScheduleService.CreateResult schedule = estimatedSchedule(
        owner.Id,
        1000,
        'revision'
      );
      AXF_OBJ_FinancialTransaction__c target = occurrence(
        schedule.scheduleId,
        1
      );
      ALT_CLS_ObligationService.SettlementInput full = cashRequest(
        target.Id,
        'axf104-revision-950',
        ALT_CLS_ObligationService.MODE_FULL,
        950,
        versionOf(target.Id)
      );
      explained(full, 950, 0, 0);

      ALT_CLS_ObligationService.SettlementResult result = applyCash(full);

      Assert.areEqual(950.00, result.effectiveObligation);
      Assert.areEqual(-50.00, result.adjustmentTotal);
      Assert.areEqual(
        950.00,
        referenceAmountOf(result.referenceId),
        'Uma revisão explícita para 950 passa a valer para as estimativas seguintes'
      );
    }
  }

  @IsTest
  static void oneOffDiscountDoesNotMoveTheRecurringReference() {
    System.runAs(actor()) {
      Account owner = holder('AXF104 discount');
      ALT_CLS_FinancialScheduleService.CreateResult schedule = estimatedSchedule(
        owner.Id,
        1000,
        'discount'
      );
      AXF_OBJ_FinancialTransaction__c target = occurrence(
        schedule.scheduleId,
        1
      );
      ALT_CLS_ObligationService.SettlementInput full = cashRequest(
        target.Id,
        'axf104-discount-950',
        ALT_CLS_ObligationService.MODE_FULL,
        950,
        versionOf(target.Id)
      );
      // Recorrente 1000 com desconto pontual 50 liquida 950, mas a referência segue 1000.
      explained(full, 1000, 0, 50);

      ALT_CLS_ObligationService.SettlementResult result = applyCash(full);

      Assert.areEqual(950.00, result.effectiveObligation);
      Assert.areEqual(-50.00, result.adjustmentTotal);
      Assert.areEqual(
        1000.00,
        referenceAmountOf(result.referenceId),
        'Um desconto pontual reduz esta liquidação, nunca a próxima referência'
      );
    }
  }

  @IsTest
  static void unclassifiedFullSettlesWithAdjustmentAndPublishesNoReference() {
    System.runAs(actor()) {
      Account owner = holder('AXF104 unclassified');
      ALT_CLS_FinancialScheduleService.CreateResult schedule = estimatedSchedule(
        owner.Id,
        1000,
        'unclassified'
      );
      AXF_OBJ_FinancialTransaction__c target = occurrence(
        schedule.scheduleId,
        1
      );
      ALT_CLS_ObligationService.SettlementInput full = cashRequest(
        target.Id,
        'axf104-unclassified-950',
        ALT_CLS_ObligationService.MODE_FULL,
        950,
        versionOf(target.Id)
      );
      full.explanation = 'Diferença ainda não classificada.';

      ALT_CLS_ObligationService.SettlementResult result = applyCash(full);

      Assert.areEqual('APPLIED', result.outcome, result.message);
      Assert.areEqual(950.00, result.effectiveObligation);
      Assert.areEqual(-50.00, result.adjustmentTotal);
      Assert.isNotNull(result.adjustmentId, 'A diferença é um ajuste revisado');
      Assert.isNull(
        result.referenceId,
        'UNCLASSIFIED liquida mas não publica referência'
      );
      Assert.areEqual(0, countReference(schedule.scheduleId, 'REALIZATION'));
      Assert.areEqual(
        'UNCLASSIFIED',
        decisionOf(result.decisionId).AXF_SDC_PKL_Classification__c
      );
    }
  }

  // ---------------------------------------------------------------------------------------
  // AC 9 / AC 10 �?" classificação posterior não movimenta caixa e publica a referência
  // ---------------------------------------------------------------------------------------
  @IsTest
  static void laterClassificationChangesNoCashAndPublishesReference() {
    System.runAs(actor()) {
      Account owner = holder('AXF104 classify');
      ALT_CLS_FinancialScheduleService.CreateResult schedule = estimatedSchedule(
        owner.Id,
        1000,
        'classify'
      );
      AXF_OBJ_FinancialTransaction__c target = occurrence(
        schedule.scheduleId,
        1
      );
      ALT_CLS_ObligationService.SettlementInput full = cashRequest(
        target.Id,
        'axf104-classify-settle',
        ALT_CLS_ObligationService.MODE_FULL,
        950,
        versionOf(target.Id)
      );
      full.explanation = 'Diferença ainda não classificada.';
      ALT_CLS_ObligationService.SettlementResult settled = applyCash(full);
      Integer allocationsBefore = [
        SELECT COUNT()
        FROM AXF_OBJ_ReconciliationAllocation__c
      ];
      Decimal versionBefore = versionOf(target.Id);

      ALT_CLS_ObligationService.SettlementInput classify = new ALT_CLS_ObligationService.SettlementInput();
      classify.operationKey = 'axf104-classify-later';
      classify.targetId = target.Id;
      classify.classification = ALT_CLS_ObligationService.CLASSIFICATION_EXPLAINED;
      classify.recurringAmount = 950;
      classify.exceptionalCharges = 0;
      classify.oneOffDiscount = 0;
      classify.reasonCode = 'ESTIMATE_REVISION';
      classify.explanation = 'Revisão de estimativa confirmada na classificação.';
      classify.economicSequence = 1;
      classify.currencyIso = 'BRL';
      classify.economicDate = Date.today();
      classify.expectedTargetVersion = versionBefore;
      classify.originalDecisionId = settled.decisionId;

      ALT_CLS_ObligationService.SettlementResult result = new ALT_CLS_ObligationService()
        .classify(classify);

      Assert.areEqual('CLASSIFIED', result.outcome, result.message);
      Assert.isNotNull(
        result.referenceId,
        'A classificação tardia publica a referência'
      );
      Assert.areEqual(
        allocationsBefore,
        [SELECT COUNT() FROM AXF_OBJ_ReconciliationAllocation__c],
        'A classificação não cria nem consome caixa'
      );
      Assert.areEqual(
        versionBefore,
        versionOf(target.Id),
        'Uma operação sem caixa não incrementa a versão do alvo'
      );
      Assert.areEqual(950.00, referenceAmountOf(result.referenceId));
      Assert.areEqual(
        'CLASSIFY',
        decisionOf(result.decisionId).AXF_SDC_PKL_Operation__c,
        'A classificação tardia é uma decisão tipada de CLASSIFY'
      );
      Assert.areEqual(
        2,
        [SELECT COUNT() FROM AXF_OBJ_SettlementDecision__c WITH SYSTEM_MODE]
      );
    }
  }

  // ---------------------------------------------------------------------------------------
  // AC 1 �?" a liquidação não é limitada pela estimativa original obsoleta
  // ---------------------------------------------------------------------------------------
  @IsTest
  static void fullAboveOriginalEstimateIsNotCappedByTheObsoleteEstimate() {
    System.runAs(actor()) {
      Account owner = holder('AXF104 above');
      ALT_CLS_FinancialScheduleService.CreateResult schedule = estimatedSchedule(
        owner.Id,
        1000,
        'above'
      );
      AXF_OBJ_FinancialTransaction__c target = occurrence(
        schedule.scheduleId,
        1
      );
      Assert.areEqual(1000.00, target.AXF_FTX_NUM_Magnitude__c);

      ALT_CLS_ObligationService.SettlementInput full = cashRequest(
        target.Id,
        'axf104-above-1050',
        ALT_CLS_ObligationService.MODE_FULL,
        1050,
        versionOf(target.Id)
      );
      explained(full, 1000, 50, 0);

      ALT_CLS_ObligationService.SettlementResult result = applyCash(full);

      Assert.areEqual('APPLIED', result.outcome, result.message);
      Assert.areEqual(1050.00, result.effectiveObligation);
      Assert.areEqual(1050.00, result.netApplied);
      AXF_OBJ_FinancialTransaction__c after = occurrence(
        schedule.scheduleId,
        1
      );
      Assert.areEqual(
        1000.00,
        after.AXF_FTX_NUM_Magnitude__c,
        'A previsão original permanece preservada e imutável'
      );
      Assert.isTrue(after.AXF_FTX_BOL_BasisFrozen__c);
    }
  }

  // ---------------------------------------------------------------------------------------
  // AC 2 �?" um ajuste não é caixa e não aumenta a disponibilidade da fonte
  // ---------------------------------------------------------------------------------------
  @IsTest
  static void adjustmentIsNotCashAndCannotFundTheSource() {
    System.runAs(actor()) {
      Account owner = holder('AXF104 not cash');
      ALT_CLS_FinancialScheduleService.CreateResult schedule = estimatedSchedule(
        owner.Id,
        1000,
        'notcash'
      );
      AXF_OBJ_FinancialTransaction__c target = occurrence(
        schedule.scheduleId,
        1
      );
      applyCash(
        cashRequest(
          target.Id,
          'axf104-notcash-200',
          ALT_CLS_ObligationService.MODE_PARTIAL,
          200,
          versionOf(target.Id)
        )
      );
      Id cashFactId = [
        SELECT AXF_RA_LKP_ManualTransaction__c
        FROM AXF_OBJ_ReconciliationAllocation__c
        WHERE AXF_RA_LKP_FinancialTransaction__c = :target.Id
        LIMIT 1
      ]
      .AXF_RA_LKP_ManualTransaction__c;
      Decimal factVersion = [
        SELECT AXF_FTX_NUM_Version__c
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE Id = :cashFactId
      ]
      .AXF_FTX_NUM_Version__c;
      // O ajuste eleva a obrigação efetiva para 1800, mas não cria caixa nenhum.
      ALT_CLS_ObligationService.SettlementInput partial = cashRequest(
        target.Id,
        'axf104-notcash-raise',
        ALT_CLS_ObligationService.MODE_PARTIAL,
        800,
        versionOf(target.Id)
      );
      partial.amendment = 800;
      partial.reasonCode = 'EXCEPTIONAL_CHARGE';
      partial.explanation = 'Encargo excepcional revisado.';
      partial.sourceId = cashFactId;
      partial.expectedSourceVersion = factVersion;

      String code;
      try {
        applyCash(partial);
      } catch (ALT_CLS_ObligationService.ObligationException expected) {
        code = expected.getMessage();
      }
      Assert.areEqual(
        'UNAVAILABLE_AMOUNT',
        code,
        'O ajuste revisado não financia a fonte: a disponibilidade real continua limitando'
      );
      ALT_CLS_ObligationService.ObligationView view = new ALT_CLS_ObligationService()
        .read(target.Id);
      Assert.areEqual(
        1000.00,
        view.effectiveObligation,
        'A falha reverte o ajuste proposto: a obrigação efetiva continua sendo a base'
      );
      Assert.areEqual(0.00, view.adjustmentTotal);
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM AXF_OBJ_ObligationAdjustment__c WITH SYSTEM_MODE]
      );
    }
  }

  // ---------------------------------------------------------------------------------------
  // AC 6 / AC 15 �?" repetição equivalente, carga alterada e versão obsoleta
  // ---------------------------------------------------------------------------------------
  @IsTest
  static void equivalentReplayReturnsOriginalResultAndChangedPayloadConflicts() {
    System.runAs(actor()) {
      Account owner = holder('AXF104 replay');
      ALT_CLS_FinancialScheduleService.CreateResult schedule = estimatedSchedule(
        owner.Id,
        1000,
        'replay'
      );
      AXF_OBJ_FinancialTransaction__c target = occurrence(
        schedule.scheduleId,
        1
      );
      ALT_CLS_ObligationService.SettlementResult created = applyCash(
        cashRequest(
          target.Id,
          'axf104-replay',
          ALT_CLS_ObligationService.MODE_PARTIAL,
          400,
          0
        )
      );
      Assert.isFalse(created.replay);
      // A repetição é resolvida pela identidade da operação ANTES da versão obsoleta: a
      // versão informada já está velha e mesmo assim o resultado original é devolvido.
      ALT_CLS_ObligationService.SettlementResult replayed = applyCash(
        cashRequest(
          target.Id,
          'axf104-replay',
          ALT_CLS_ObligationService.MODE_PARTIAL,
          400,
          0
        )
      );
      Assert.isTrue(replayed.replay);
      Assert.areEqual(created.decisionId, replayed.decisionId);
      Assert.areEqual(created.allocationId, replayed.allocationId);
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM AXF_OBJ_ReconciliationAllocation__c]
      );
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM AXF_OBJ_SettlementDecision__c WITH SYSTEM_MODE]
      );

      String code;
      try {
        applyCash(
          cashRequest(
            target.Id,
            'axf104-replay',
            ALT_CLS_ObligationService.MODE_PARTIAL,
            401,
            0
          )
        );
      } catch (ALT_CLS_ObligationService.ObligationException expected) {
        code = expected.getMessage();
      }
      Assert.areEqual('CONFLICT', code);
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM AXF_OBJ_ReconciliationAllocation__c]
      );
    }
  }

  @IsTest
  static void staleTargetVersionConflicts() {
    System.runAs(actor()) {
      Account owner = holder('AXF104 stale');
      ALT_CLS_FinancialScheduleService.CreateResult schedule = estimatedSchedule(
        owner.Id,
        1000,
        'stale'
      );
      AXF_OBJ_FinancialTransaction__c target = occurrence(
        schedule.scheduleId,
        1
      );
      String code;
      try {
        applyCash(
          cashRequest(
            target.Id,
            'axf104-stale',
            ALT_CLS_ObligationService.MODE_PARTIAL,
            100,
            7
          )
        );
      } catch (ALT_CLS_ObligationService.ObligationException expected) {
        code = expected.getMessage();
      }
      Assert.areEqual('CONFLICT', code);
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM AXF_OBJ_ReconciliationAllocation__c]
      );
    }
  }

  // ---------------------------------------------------------------------------------------
  // AC 13 �?" ACTUAL_ONLY: capacidade factual, nenhum ajuste, nenhuma dívida fabricada
  // ---------------------------------------------------------------------------------------
  @IsTest
  static void actualOnlyUsesFactualCapacityAndRejectsAnyAmendment() {
    System.runAs(actor()) {
      Account owner = holder('AXF104 actual only');
      // Uma ocorrência ACTUAL_ONLY só existe pelo comando autorizado: o papel financeiro não
      // pode ser forjado por DML direta.
      ALT_CLS_RealizationService.Input origin = new ALT_CLS_RealizationService.Input();
      origin.operationKey = 'axf104-factual-origin';
      origin.accountId = owner.Id;
      origin.sourceKind = 'CASH';
      origin.amount = 1000;
      origin.currencyIso = 'BRL';
      origin.direction = 'DEBIT';
      origin.recognitionDate = Date.today();
      Id originAllocation = new ALT_CLS_RealizationService().apply(origin);
      AXF_OBJ_FinancialTransaction__c factual = [
        SELECT Id, AXF_FTX_NUM_Version__c
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE
          AXF_FTX_LKP_Account__c = :owner.Id
          AND AXF_FTX_PKL_PlanKind__c = 'ACTUAL_ONLY'
        LIMIT 1
      ];
      // O estorno preserva o histórico factual e N�fO fabrica dívida nem reinterpreta a
      // ocorrência como prevista.
      new ALT_CLS_RealizationService()
        .reverse(
          originAllocation,
          factual.AXF_FTX_NUM_Version__c,
          'axf104-factual-reset'
        );

      ALT_CLS_ObligationService.ObligationView before = new ALT_CLS_ObligationService()
        .read(factual.Id);
      Assert.areEqual(
        1000.00,
        before.applicationCapacity,
        'A capacidade factual independe do residual de previsão, que é zero'
      );
      Assert.areEqual(
        0.00,
        before.outstandingObligation,
        'ACTUAL_ONLY não tem dívida prevista, mesmo após um estorno'
      );
      Assert.areEqual(0.00, before.netApplied);

      // PARTIAL precisa ser estritamente menor que a capacidade factual.
      String code;
      try {
        applyCash(
          cashRequest(
            factual.Id,
            'axf104-factual-full-as-partial',
            ALT_CLS_ObligationService.MODE_PARTIAL,
            1000,
            versionOf(factual.Id)
          )
        );
      } catch (ALT_CLS_ObligationService.ObligationException expected) {
        code = expected.getMessage();
      }
      Assert.areEqual('INVALID_FACTUAL_TOTAL', code);

      applyCash(
        cashRequest(
          factual.Id,
          'axf104-factual-400',
          ALT_CLS_ObligationService.MODE_PARTIAL,
          400,
          versionOf(factual.Id)
        )
      );
      ALT_CLS_ObligationService.ObligationView after = new ALT_CLS_ObligationService()
        .read(factual.Id);
      Assert.areEqual(600.00, after.applicationCapacity);
      Assert.areEqual(
        0.00,
        after.outstandingObligation,
        'Uma ocorrência factual não carrega dívida de previsão, mesmo com aplicações válidas'
      );
      Assert.areEqual(400.00, after.netApplied);
      Assert.areEqual(0.00, after.adjustmentTotal);

      ALT_CLS_ObligationService.SettlementInput amend = new ALT_CLS_ObligationService.SettlementInput();
      amend.operationKey = 'axf104-factual-amend';
      amend.targetId = factual.Id;
      amend.amount = 900;
      amend.currencyIso = 'BRL';
      amend.economicDate = Date.today();
      amend.reasonCode = 'CORRECTION';
      amend.explanation = 'Tentativa de emenda em ocorrência factual.';
      amend.classification = ALT_CLS_ObligationService.CLASSIFICATION_NOT_APPLICABLE;
      amend.expectedTargetVersion = versionOf(factual.Id);
      String amendCode;
      try {
        new ALT_CLS_ObligationService().amend(amend);
      } catch (ALT_CLS_ObligationService.ObligationException expected) {
        amendCode = expected.getMessage();
      }
      Assert.areEqual(
        'INVALID_ROLE',
        amendCode,
        'Nenhuma emenda de obrigação com sinal é permitida em ACTUAL_ONLY'
      );
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM AXF_OBJ_ObligationAdjustment__c WITH SYSTEM_MODE]
      );
    }
  }

  // ---------------------------------------------------------------------------------------
  // AC 14 �?" emenda individual: sem caixa, nunca abaixo do pago, congela a base revisada
  // ---------------------------------------------------------------------------------------
  @IsTest
  static void amendmentRequiresAmountAtLeastNetPaidAndFreezesTheBasis() {
    System.runAs(actor()) {
      Account owner = holder('AXF104 amend');
      ALT_CLS_FinancialScheduleService.CreateResult schedule = estimatedSchedule(
        owner.Id,
        1000,
        'amend'
      );
      AXF_OBJ_FinancialTransaction__c target = occurrence(
        schedule.scheduleId,
        1
      );
      applyCash(
        cashRequest(
          target.Id,
          'axf104-amend-400',
          ALT_CLS_ObligationService.MODE_PARTIAL,
          400,
          versionOf(target.Id)
        )
      );
      ALT_CLS_ObligationService.SettlementInput below = new ALT_CLS_ObligationService.SettlementInput();
      below.operationKey = 'axf104-amend-below';
      below.targetId = target.Id;
      below.amount = 300;
      below.currencyIso = 'BRL';
      below.economicDate = Date.today();
      below.reasonCode = 'CORRECTION';
      below.explanation = 'Tentativa abaixo do valor pago.';
      below.classification = ALT_CLS_ObligationService.CLASSIFICATION_NOT_APPLICABLE;
      below.expectedTargetVersion = versionOf(target.Id);
      String code;
      try {
        new ALT_CLS_ObligationService().amend(below);
      } catch (ALT_CLS_ObligationService.ObligationException expected) {
        code = expected.getMessage();
      }
      Assert.areEqual(
        'AMOUNT_BELOW_PAID',
        code,
        'Enew < N é rejeitado atomicamente em vez de estornar ou perdoar saldo'
      );
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM AXF_OBJ_ObligationAdjustment__c WITH SYSTEM_MODE]
      );

      ALT_CLS_ObligationService.SettlementInput raise = new ALT_CLS_ObligationService.SettlementInput();
      raise.operationKey = 'axf104-amend-raise';
      raise.targetId = target.Id;
      raise.amount = 1200;
      raise.currencyIso = 'BRL';
      raise.economicDate = Date.today();
      raise.reasonCode = 'CONTRACTUAL_RECURRING';
      raise.explanation = 'Recorrente contratual revisado em consenso.';
      raise.classification = ALT_CLS_ObligationService.CLASSIFICATION_NOT_APPLICABLE;
      raise.expectedTargetVersion = versionOf(target.Id);
      ALT_CLS_ObligationService.SettlementResult amended = new ALT_CLS_ObligationService()
        .amend(raise);
      Assert.areEqual('AMENDED', amended.outcome, amended.message);
      Assert.areEqual(1200.00, amended.effectiveObligation);
      Assert.areEqual(200.00, amended.adjustmentTotal);
      Assert.isNotNull(amended.adjustmentId);
      Assert.isNull(
        [
          SELECT AXF_OAD_LKP_Allocation__c
          FROM AXF_OBJ_ObligationAdjustment__c
          WHERE Id = :amended.adjustmentId
          WITH SYSTEM_MODE
        ]
        .AXF_OAD_LKP_Allocation__c,
        'Uma emenda individual não pertence a nenhuma alocação de caixa'
      );
      Assert.isTrue(
        occurrence(schedule.scheduleId, 1).AXF_FTX_BOL_BasisFrozen__c,
        'Uma emenda com delta não nulo congela a base revisada'
      );

      // Delta zero é recebimento sem ajuste: nenhum ajuste novo e nenhuma versão financeira.
      ALT_CLS_ObligationService.SettlementInput noop = new ALT_CLS_ObligationService.SettlementInput();
      noop.operationKey = 'axf104-amend-noop';
      noop.targetId = target.Id;
      noop.amount = 1200;
      noop.currencyIso = 'BRL';
      noop.economicDate = Date.today();
      noop.reasonCode = 'CORRECTION';
      noop.explanation = 'Confirmação sem mudança de valor.';
      noop.classification = ALT_CLS_ObligationService.CLASSIFICATION_NOT_APPLICABLE;
      noop.expectedTargetVersion = versionOf(target.Id);
      ALT_CLS_ObligationService.SettlementResult receipt = new ALT_CLS_ObligationService()
        .amend(noop);
      Assert.areEqual('NOOP', receipt.outcome, receipt.message);
      Assert.isNull(receipt.adjustmentId);
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM AXF_OBJ_ObligationAdjustment__c WITH SYSTEM_MODE]
      );
    }
  }

  @IsTest
  static void independentAmendmentSurvivesCashReversal() {
    System.runAs(actor()) {
      Account owner = holder('AXF104 independent');
      ALT_CLS_FinancialScheduleService.CreateResult schedule = estimatedSchedule(
        owner.Id,
        1000,
        'independent'
      );
      AXF_OBJ_FinancialTransaction__c target = occurrence(
        schedule.scheduleId,
        1
      );
      ALT_CLS_ObligationService.SettlementResult applied = applyCash(
        cashRequest(
          target.Id,
          'axf104-independent-400',
          ALT_CLS_ObligationService.MODE_PARTIAL,
          400,
          versionOf(target.Id)
        )
      );
      ALT_CLS_ObligationService.SettlementInput raise = new ALT_CLS_ObligationService.SettlementInput();
      raise.operationKey = 'axf104-independent-raise';
      raise.targetId = target.Id;
      raise.amount = 1200;
      raise.currencyIso = 'BRL';
      raise.economicDate = Date.today();
      raise.reasonCode = 'CONTRACTUAL_RECURRING';
      raise.explanation = 'Recorrente contratual independente do caixa.';
      raise.classification = ALT_CLS_ObligationService.CLASSIFICATION_NOT_APPLICABLE;
      raise.expectedTargetVersion = versionOf(target.Id);
      new ALT_CLS_ObligationService().amend(raise);
      Assert.areEqual(
        1200.00,
        new ALT_CLS_ObligationService().read(target.Id).effectiveObligation
      );

      new ALT_CLS_RealizationService()
        .reverse(
          applied.allocationId,
          versionOf(target.Id),
          'axf104-independent-reverse'
        );

      ALT_CLS_ObligationService.ObligationView view = new ALT_CLS_ObligationService()
        .read(target.Id);
      Assert.areEqual(
        1200.00,
        view.effectiveObligation,
        'Uma emenda independente sobrevive ao estorno do caixa'
      );
      Assert.areEqual(0.00, view.netApplied);
      Assert.areEqual(1200.00, view.outstandingObligation);
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM AXF_OBJ_ObligationAdjustment__c
          WHERE AXF_OAD_PKL_Kind__c = 'ADJUSTMENT'
          WITH SYSTEM_MODE
        ],
        'A emenda independente nunca é compensada por um estorno de caixa'
      );
      Assert.areEqual(
        0,
        [
          SELECT COUNT()
          FROM AXF_OBJ_ObligationAdjustment__c
          WHERE AXF_OAD_PKL_Kind__c = 'COMPENSATION'
          WITH SYSTEM_MODE
        ]
      );
    }
  }

  // ---------------------------------------------------------------------------------------
  // AC 5 / AC 11 / AC 12 �?" estorno compensa só o ajuste atribuível e retira a referência
  // ---------------------------------------------------------------------------------------
  @IsTest
  static void reversalCompensatesOnlyTheAttributableAdjustmentAndWithdrawsReference() {
    System.runAs(actor()) {
      Account owner = holder('AXF104 reversal');
      ALT_CLS_FinancialScheduleService.CreateResult schedule = estimatedSchedule(
        owner.Id,
        1000,
        'reversal'
      );
      AXF_OBJ_FinancialTransaction__c target = occurrence(
        schedule.scheduleId,
        1
      );
      ALT_CLS_ObligationService.SettlementInput full = cashRequest(
        target.Id,
        'axf104-reversal-1050',
        ALT_CLS_ObligationService.MODE_FULL,
        1050,
        versionOf(target.Id)
      );
      explained(full, 1000, 50, 0);
      ALT_CLS_ObligationService.SettlementResult settled = applyCash(full);
      Assert.areEqual(1050.00, settled.effectiveObligation);
      Assert.areEqual(50.00, settled.adjustmentTotal);
      Assert.isNotNull(settled.referenceId);

      new ALT_CLS_RealizationService()
        .reverse(
          settled.allocationId,
          versionOf(target.Id),
          'axf104-reversal-undo'
        );

      ALT_CLS_ObligationService.ObligationView view = new ALT_CLS_ObligationService()
        .read(target.Id);
      Assert.areEqual(
        1000.00,
        view.effectiveObligation,
        'O estorno restaura a obriga��o efetiva anterior'
      );
      Assert.areEqual(0.00, view.netApplied);
      Assert.areEqual(1000.00, view.outstandingObligation);
      Assert.areEqual(
        0.00,
        view.adjustmentTotal,
        'S� o ajuste atribu�vel � aplica��o estornada � compensado'
      );
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM AXF_OBJ_ObligationAdjustment__c
          WHERE AXF_OAD_PKL_Kind__c = 'COMPENSATION'
          WITH SYSTEM_MODE
        ]
      );
      // O estorno retira a refer�ncia dependente da classifica��o invalidada: a evid�ncia
      // original permanece imut�vel e a retirada a aponta explicitamente.
      List<AXF_OBJ_ScheduleReference__c> references = [
        SELECT Id, AXF_SRF_PKL_Kind__c, AXF_SRF_LKP_Compensates__c
        FROM AXF_OBJ_ScheduleReference__c
        WHERE AXF_SRF_LKP_Schedule__c = :schedule.scheduleId
        WITH SYSTEM_MODE
      ];
      Integer withdrawals = 0;
      for (AXF_OBJ_ScheduleReference__c row : references) {
        if (
          row.AXF_SRF_PKL_Kind__c == 'COMPENSATION' &&
          row.AXF_SRF_LKP_Compensates__c == settled.referenceId
        ) {
          withdrawals++;
        }
      }
      Assert.areEqual(
        1,
        withdrawals,
        'A refer�ncia publicada pela classifica��o invalidada � retirada explicitamente'
      );
    }
  }

  // ---------------------------------------------------------------------------------------
  // AC 11 �?" a precedência segue a sequência absoluta, nunca a hora de chegada
  // ---------------------------------------------------------------------------------------
  @IsTest
  static void outOfOrderSettlementNeverOverwritesANewerInstallmentReference() {
    System.runAs(actor()) {
      Account owner = holder('AXF104 out of order');
      ALT_CLS_FinancialScheduleService.CreateResult schedule = estimatedSchedule(
        owner.Id,
        1000,
        'outoforder'
      );
      AXF_OBJ_FinancialTransaction__c newerInstallment = occurrence(
        schedule.scheduleId,
        5
      );
      ALT_CLS_ObligationService.SettlementInput newerFull = cashRequest(
        newerInstallment.Id,
        'axf104-ooo-5',
        ALT_CLS_ObligationService.MODE_FULL,
        1100,
        versionOf(newerInstallment.Id)
      );
      explained(newerFull, 1100, 0, 0);
      ALT_CLS_ObligationService.SettlementResult newerResult = applyCash(
        newerFull
      );

      AXF_OBJ_FinancialTransaction__c olderInstallment = occurrence(
        schedule.scheduleId,
        3
      );
      ALT_CLS_ObligationService.SettlementInput olderFull = cashRequest(
        olderInstallment.Id,
        'axf104-ooo-3',
        ALT_CLS_ObligationService.MODE_FULL,
        900,
        versionOf(olderInstallment.Id)
      );
      explained(olderFull, 900, 0, 0);
      ALT_CLS_ObligationService.SettlementResult olderResult = applyCash(
        olderFull
      );

      Assert.areEqual(
        5,
        [
            SELECT AXF_SRF_NUM_EconomicSequence__c
            FROM AXF_OBJ_ScheduleReference__c
            WHERE Id = :newerResult.referenceId
            WITH SYSTEM_MODE
          ]
          .AXF_SRF_NUM_EconomicSequence__c.intValue()
      );
      Assert.areEqual(
        3,
        [
            SELECT AXF_SRF_NUM_EconomicSequence__c
            FROM AXF_OBJ_ScheduleReference__c
            WHERE Id = :olderResult.referenceId
            WITH SYSTEM_MODE
          ]
          .AXF_SRF_NUM_EconomicSequence__c.intValue()
      );
      // A referência mais nova continua vigente para as parcelas seguintes: a chegada tardia
      // de uma parcela mais antiga não a substitui.
      Assert.areEqual(
        6,
        [
            SELECT AXF_SRF_NUM_EffectiveSequence__c
            FROM AXF_OBJ_ScheduleReference__c
            WHERE Id = :newerResult.referenceId
            WITH SYSTEM_MODE
          ]
          .AXF_SRF_NUM_EffectiveSequence__c.intValue()
      );
      Assert.areEqual(
        2,
        countReference(schedule.scheduleId, 'REALIZATION'),
        'Duas ordens econômicas distintas coexistem sem ambiguidade'
      );
    }
  }

  // ---------------------------------------------------------------------------------------
  // AC 9 �?" a equação de componentes não pode ser burlada
  // ---------------------------------------------------------------------------------------
  @IsTest
  static void componentEquationAndMissingComponentsAreRejected() {
    System.runAs(actor()) {
      Account owner = holder('AXF104 components');
      ALT_CLS_FinancialScheduleService.CreateResult schedule = estimatedSchedule(
        owner.Id,
        1000,
        'components'
      );
      AXF_OBJ_FinancialTransaction__c target = occurrence(
        schedule.scheduleId,
        1
      );
      ALT_CLS_ObligationService.SettlementInput mismatch = cashRequest(
        target.Id,
        'axf104-components-mismatch',
        ALT_CLS_ObligationService.MODE_FULL,
        950,
        versionOf(target.Id)
      );
      // 1000 + 50 �^' 0 = 1050, mas a parcela liquidada é 950.
      explained(mismatch, 1000, 50, 0);
      String code;
      try {
        applyCash(mismatch);
      } catch (ALT_CLS_ObligationService.ObligationException expected) {
        code = expected.getMessage();
      }
      Assert.areEqual('COMPONENT_TOTAL_MISMATCH', code);

      ALT_CLS_ObligationService.SettlementInput missing = cashRequest(
        target.Id,
        'axf104-components-missing',
        ALT_CLS_ObligationService.MODE_FULL,
        950,
        versionOf(target.Id)
      );
      missing.classification = ALT_CLS_ObligationService.CLASSIFICATION_EXPLAINED;
      missing.explanation = 'Componentes ausentes.';
      String missingCode;
      try {
        applyCash(missing);
      } catch (ALT_CLS_ObligationService.ObligationException expected) {
        missingCode = expected.getMessage();
      }
      Assert.areEqual(
        'INVALID_COMPONENTS',
        missingCode,
        'Componentes ausentes nunca assumem zero em silêncio'
      );

      ALT_CLS_ObligationService.SettlementInput negative = cashRequest(
        target.Id,
        'axf104-components-negative',
        ALT_CLS_ObligationService.MODE_FULL,
        950,
        versionOf(target.Id)
      );
      explained(negative, 1000, 0, 0);
      negative.exceptionalCharges = -50;
      String negativeCode;
      try {
        applyCash(negative);
      } catch (ALT_CLS_ObligationService.ObligationException expected) {
        negativeCode = expected.getMessage();
      }
      Assert.areEqual('INVALID_COMPONENTS', negativeCode);
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM AXF_OBJ_ReconciliationAllocation__c]
      );
    }
  }

  @IsTest
  static void crossCurrencyApplicationFails() {
    System.runAs(actor()) {
      Account owner = holder('AXF104 currency');
      ALT_CLS_FinancialScheduleService.CreateResult schedule = estimatedSchedule(
        owner.Id,
        1000,
        'currency'
      );
      AXF_OBJ_FinancialTransaction__c target = occurrence(
        schedule.scheduleId,
        1
      );
      ALT_CLS_ObligationService.SettlementInput input = cashRequest(
        target.Id,
        'axf104-currency',
        ALT_CLS_ObligationService.MODE_PARTIAL,
        100,
        versionOf(target.Id)
      );
      input.currencyIso = 'USD';
      String code;
      try {
        applyCash(input);
      } catch (ALT_CLS_ObligationService.ObligationException expected) {
        code = expected.getMessage();
      }
      Assert.areEqual('CURRENCY_MISMATCH', code);
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM AXF_OBJ_ReconciliationAllocation__c]
      );
    }
  }

  // ---------------------------------------------------------------------------------------
  // AC 10 / AC 16 �?" evidência imutável e fronteira de escrita direta
  // ---------------------------------------------------------------------------------------
  @IsTest
  static void directEvidenceWritesAreRejected() {
    System.runAs(actor()) {
      Account owner = holder('AXF104 direct dml');
      ALT_CLS_FinancialScheduleService.CreateResult schedule = estimatedSchedule(
        owner.Id,
        1000,
        'directdml'
      );
      AXF_OBJ_FinancialTransaction__c target = occurrence(
        schedule.scheduleId,
        1
      );
      List<AXF_OBJ_SettlementDecision__c> decisions = new List<AXF_OBJ_SettlementDecision__c>{
        new AXF_OBJ_SettlementDecision__c(
          AXF_SDC_EXI_DecisionKey__c = 'axf104-direct-decision',
          AXF_SDC_TXT_PayloadHash__c = 'x',
          AXF_SDC_LKP_FinancialTransaction__c = target.Id,
          AXF_SDC_PKL_Operation__c = 'APPLY',
          AXF_SDC_PKL_Mode__c = 'PARTIAL',
          AXF_SDC_PKL_Classification__c = 'NOT_APPLICABLE',
          AXF_SDC_DAT_EconomicDate__c = Date.today(),
          AXF_SDC_LKP_Actor__c = UserInfo.getUserId(),
          AXF_SDC_DT_CommittedAt__c = System.now()
        )
      };
      Database.SaveResult[] decisionResults = Database.insert(
        decisions,
        false,
        AccessLevel.SYSTEM_MODE
      );
      Assert.isFalse(
        decisionResults[0].isSuccess(),
        'Uma decisão não pode ser inserida diretamente'
      );
      Assert.isTrue(
        decisionResults[0].getErrors()[0]
          .getMessage()
          .contains('serviço de obrigação')
      );

      List<AXF_OBJ_ObligationAdjustment__c> adjustments = new List<AXF_OBJ_ObligationAdjustment__c>{
        new AXF_OBJ_ObligationAdjustment__c(
          AXF_OAD_EXI_AdjustmentKey__c = 'axf104-direct-adjustment',
          AXF_OAD_LKP_FinancialTransaction__c = target.Id,
          AXF_OAD_NUM_SignedAmount__c = 10,
          AXF_OAD_TXT_CurrencyIsoCode__c = 'BRL',
          AXF_OAD_PKL_Kind__c = 'ADJUSTMENT',
          AXF_OAD_PKL_Reason__c = 'CORRECTION'
        )
      };
      Database.SaveResult[] adjustmentResults = Database.insert(
        adjustments,
        false,
        AccessLevel.SYSTEM_MODE
      );
      Assert.isFalse(
        adjustmentResults[0].isSuccess(),
        'Um ajuste não pode ser inserido diretamente'
      );
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM AXF_OBJ_SettlementDecision__c WITH SYSTEM_MODE]
      );
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM AXF_OBJ_ObligationAdjustment__c WITH SYSTEM_MODE]
      );
    }
  }

  @IsTest
  static void evidenceIsImmutableAndDeletionIsBlocked() {
    System.runAs(actor()) {
      Account owner = holder('AXF104 immutable');
      ALT_CLS_FinancialScheduleService.CreateResult schedule = estimatedSchedule(
        owner.Id,
        1000,
        'immutable'
      );
      AXF_OBJ_FinancialTransaction__c target = occurrence(
        schedule.scheduleId,
        1
      );
      ALT_CLS_ObligationService.SettlementInput full = cashRequest(
        target.Id,
        'axf104-immutable',
        ALT_CLS_ObligationService.MODE_FULL,
        950,
        versionOf(target.Id)
      );
      full.explanation = 'Diferença revisada.';
      ALT_CLS_ObligationService.SettlementResult settled = applyCash(full);
      Assert.isNotNull(settled.adjustmentId);

      Database.SaveResult decisionRewrite = Database.update(
        new AXF_OBJ_SettlementDecision__c(
          Id = settled.decisionId,
          AXF_SDC_TAL_Explanation__c = 'reescrita'
        ),
        false,
        AccessLevel.SYSTEM_MODE
      );
      Assert.areEqual(
        1,
        decisionRewrite.getErrors().size(),
        'A decisão é o recibo imutável da operação'
      );

      Database.SaveResult adjustmentRewrite = Database.update(
        new AXF_OBJ_ObligationAdjustment__c(
          Id = settled.adjustmentId,
          AXF_OAD_NUM_SignedAmount__c = 0
        ),
        false,
        AccessLevel.SYSTEM_MODE
      );
      Assert.areEqual(
        1,
        adjustmentRewrite.getErrors().size(),
        'O ajuste é evidência imutável'
      );

      Assert.isFalse(
        Database.delete(settled.decisionId, false, AccessLevel.SYSTEM_MODE)
          .isSuccess(),
        'Uma decisão não pode ser excluída'
      );
      Assert.isFalse(
        Database.delete(settled.adjustmentId, false, AccessLevel.SYSTEM_MODE)
          .isSuccess(),
        'Um ajuste não pode ser excluído'
      );
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM AXF_OBJ_SettlementDecision__c WITH SYSTEM_MODE]
      );
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM AXF_OBJ_ObligationAdjustment__c WITH SYSTEM_MODE]
      );
    }
  }
}
