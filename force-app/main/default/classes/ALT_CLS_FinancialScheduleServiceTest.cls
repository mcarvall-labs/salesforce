/** @description AXF-103 — comando de criação atômico, replay/conflito, limites, evidência imutável e convivência com a guarda AXF-25. */
@IsTest(isParallel=false)
private class ALT_CLS_FinancialScheduleServiceTest {
  private static Id businessRecordType() {
    return Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
      .getRecordTypeInfosByDeveloperName()
      .get('AXF_Business')
      .getRecordTypeId();
  }

  private static User actor() {
    return [SELECT Id FROM User WHERE Alias = 'axf103' LIMIT 1];
  }

  private static Account holder(String name) {
    Account value = new Account(
      Name = name,
      RecordTypeId = businessRecordType()
    );
    insert value;
    return value;
  }

  private static Date windowEnd() {
    Date shifted = Date.today().addMonths(11);
    return Date.newInstance(
      shifted.year(),
      shifted.month(),
      Date.daysInMonth(shifted.year(), shifted.month())
    );
  }

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

  @TestSetup
  static void setup() {
    User actor = new User(
      Alias = 'axf103',
      Email = 'axf103@example.invalid',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Schedule Tester',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      TimeZoneSidKey = 'America/Sao_Paulo',
      ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
      .Id,
      Username = 'axf103.' + System.now().getTime() + '@example.invalid'
    );
    insert actor;

    List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (PermissionSet permission : [
      SELECT Id
      FROM PermissionSet
      WHERE
        Name IN (
          'AXF_PS_Realization',
          'AXF_PS_GestorFinanceiro',
          'AXF_PS_FinancialEntry'
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
      Name = 'AXF103TestCapability',
      Label = 'AXF103 test capability'
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

    // Perfil somente-leitura: recebe apenas AXF_PS_Participante, que não concede criação e não
    // recebe acesso à classe que contém o comando de escrita.
    User participante = actor.clone(false, false, false, false);
    participante.Alias = 'axf103p';
    participante.Username =
      'axf103p.' +
      System.now().getTime() +
      '@example.invalid';
    insert participante;
    insert new PermissionSetAssignment(
      AssigneeId = participante.Id,
      PermissionSetId = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = 'AXF_PS_Participante'
      ]
      .Id
    );

    // A realização exige uma moeda de relatório efetiva; o fixture fica isolado da montagem de
    // permissões para não depender do ator.
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert new AXF_ReportCurrencyPref__c(
        SetupOwnerId = UserInfo.getOrganizationId(),
        AXF_RCP_TXT_IsoCode__c = 'BRL'
      );
    }
  }

  @IsTest
  static void trackedFinancingPersistsOnlyTheBoundedWindowInOneTransaction() {
    Account holder = holder('AXF103 85/360');
    Date trackingDue = Date.today().addMonths(1);
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      holder.Id
    };

    ALT_CLS_FinancialScheduleService.CreateResult result = ALT_CLS_FinancialScheduleService.createSchedule(
      request(holder.Id, 'INSTALLMENT', 360, 85, trackingDue, 'axf103-85360')
    );

    Assert.areEqual('CREATED', result.outcome, result.message);
    Assert.isFalse(result.replay);

    Integer expected = expectedWindowCount(85, 360, trackingDue);
    Assert.isTrue(
      expected > 0 && expected <= 12,
      'A janela inicial deve cobrir o mês corrente mais onze'
    );
    Assert.areEqual(expected, result.occurrenceCount);
    Assert.areEqual(1, [SELECT COUNT() FROM AXF_OBJ_FinancialSchedule__c]);
    Assert.areEqual(1, [SELECT COUNT() FROM AXF_OBJ_ScheduleDefinition__c]);
    Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_ScheduleReference__c]);
    Assert.areEqual(1, [SELECT COUNT() FROM AXF_OBJ_ScheduleChange__c]);
    Assert.areEqual(
      expected,
      [
        SELECT COUNT()
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE AXF_FTX_LKP_Schedule__c = :result.scheduleId
      ],
      'Nunca as 360 parcelas: apenas a janela delimitada'
    );
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE
          AXF_FTX_LKP_Schedule__c = :result.scheduleId
          AND AXF_FTX_NUM_Sequence__c < 85
      ],
      'Nada abaixo da sequência inicial de rastreamento é gerado'
    );

    AXF_OBJ_FinancialSchedule__c root = [
      SELECT
        AXF_FSC_PKL_State__c,
        AXF_FSC_NUM_TrackingStartSequence__c,
        AXF_FSC_NUM_HorizonMonths__c,
        AXF_FSC_NUM_CoverageSequence__c,
        AXF_FSC_NUM_RefreshCursor__c,
        AXF_FSC_NUM_RetryCount__c,
        AXF_FSC_NUM_ProjectionRevision__c,
        AXF_FSC_NUM_AppliedRevision__c,
        AXF_FSC_NUM_FinancialVersion__c,
        AXF_FSC_BOL_GenerationEnabled__c,
        AXF_FSC_DT_NextAttemptAt__c,
        AXF_FSC_TXT_LastErrorCode__c,
        AXF_FSC_LKP_ActiveDefinition__c,
        AXF_FSC_EXI_ScheduleKey__c
      FROM AXF_OBJ_FinancialSchedule__c
      WHERE Id = :result.scheduleId
    ];
    Assert.areEqual('ACTIVE', root.AXF_FSC_PKL_State__c);
    Assert.areEqual(85, root.AXF_FSC_NUM_TrackingStartSequence__c.intValue());
    Assert.areEqual(12, root.AXF_FSC_NUM_HorizonMonths__c.intValue());
    Assert.areEqual(1, root.AXF_FSC_NUM_ProjectionRevision__c.intValue());
    Assert.areEqual(1, root.AXF_FSC_NUM_FinancialVersion__c.intValue());
    Assert.isNotNull(root.AXF_FSC_LKP_ActiveDefinition__c);
    Assert.isFalse(
      root.AXF_FSC_BOL_GenerationEnabled__c,
      'GenerationEnabled permanece desligado por padrão'
    );
    // Campos de cursor entram no esquema por integridade do contrato, mas esta fatia não os move.
    Assert.areEqual(0, root.AXF_FSC_NUM_CoverageSequence__c.intValue());
    Assert.areEqual(0, root.AXF_FSC_NUM_RefreshCursor__c.intValue());
    Assert.areEqual(0, root.AXF_FSC_NUM_RetryCount__c.intValue());
    Assert.isNull(root.AXF_FSC_DT_NextAttemptAt__c);
    Assert.isNull(root.AXF_FSC_TXT_LastErrorCode__c);

    AXF_OBJ_ScheduleDefinition__c definition = [
      SELECT
        AXF_SDF_NUM_Revision__c,
        AXF_SDF_PKL_Method__c,
        AXF_SDF_NUM_FirstSequence__c,
        AXF_SDF_DAT_FirstDueDate__c,
        AXF_SDF_NUM_AnchorDay__c,
        AXF_SDF_NUM_EffectiveSequence__c,
        AXF_SDF_NUM_TotalInstallments__c,
        AXF_SDF_TXT_FormulaVersion__c
      FROM AXF_OBJ_ScheduleDefinition__c
      WHERE AXF_SDF_LKP_Schedule__c = :result.scheduleId
    ];
    Assert.areEqual(1, definition.AXF_SDF_NUM_Revision__c.intValue());
    Assert.areEqual('INSTALLMENT', definition.AXF_SDF_PKL_Method__c);
    Assert.areEqual(1, definition.AXF_SDF_NUM_FirstSequence__c.intValue());
    Assert.areEqual(
      360,
      definition.AXF_SDF_NUM_TotalInstallments__c.intValue()
    );
    Assert.areEqual(
      trackingDue.addMonths(-84),
      definition.AXF_SDF_DAT_FirstDueDate__c,
      'A origem da fórmula é derivada da parcela corrente informada'
    );
    Assert.areEqual(
      ALT_CLS_AmortizationSchedule.POLICY_VERSION,
      definition.AXF_SDF_TXT_FormulaVersion__c
    );

    AXF_OBJ_ScheduleChange__c receipt = [
      SELECT
        AXF_SCH_PKL_Operation__c,
        AXF_SCH_PKL_Scope__c,
        AXF_SCH_NUM_FromSequence__c,
        AXF_SCH_NUM_Revision__c,
        AXF_SCH_TAL_ResultJson__c,
        AXF_SCH_LKP_Actor__c,
        AXF_SCH_DT_CommittedAt__c,
        AXF_SCH_TXT_PayloadHash__c
      FROM AXF_OBJ_ScheduleChange__c
      WHERE Id = :result.changeId
    ];
    Assert.areEqual('CREATE', receipt.AXF_SCH_PKL_Operation__c);
    Assert.areEqual('FROM_SEQUENCE', receipt.AXF_SCH_PKL_Scope__c);
    Assert.areEqual(85, receipt.AXF_SCH_NUM_FromSequence__c.intValue());
    Assert.areEqual(1, receipt.AXF_SCH_NUM_Revision__c.intValue());
    Assert.areEqual(64, receipt.AXF_SCH_TXT_PayloadHash__c.length());
    Assert.areEqual(UserInfo.getUserId(), receipt.AXF_SCH_LKP_Actor__c);
    Assert.isNotNull(receipt.AXF_SCH_DT_CommittedAt__c);
    Assert.isTrue(
      receipt.AXF_SCH_TAL_ResultJson__c.contains('occurrenceCount'),
      'O recibo guarda o resultado autorizado para replay'
    );

    for (AXF_OBJ_FinancialTransaction__c row : [
      SELECT
        AXF_FTX_EXI_OccurrenceKey__c,
        AXF_FTX_EXI_ClientRequestId__c,
        AXF_FTX_NUM_Sequence__c,
        AXF_FTX_LKP_Schedule__c,
        AXF_FTX_PKL_Status__c,
        AXF_FTX_PKL_PlanKind__c,
        AXF_FTX_PKL_ScheduleState__c,
        AXF_FTX_BOL_BasisFrozen__c,
        AXF_FTX_DAT_NominalDueDate__c,
        AXF_FTX_DAT_DueDate__c,
        AXF_FTX_NUM_CurrentBasis__c,
        AXF_FTX_NUM_Magnitude__c,
        AXF_FTX_NUM_ProjectionRevision__c,
        AXF_FTX_TXT_ScheduleGroupKey__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE AXF_FTX_LKP_Schedule__c = :result.scheduleId
    ]) {
      Assert.areEqual(result.scheduleId, row.AXF_FTX_LKP_Schedule__c);
      Assert.areEqual(64, row.AXF_FTX_EXI_OccurrenceKey__c.length());
      Assert.areEqual(36, row.AXF_FTX_EXI_ClientRequestId__c.length());
      Assert.areEqual('PLANNED', row.AXF_FTX_PKL_Status__c);
      Assert.areEqual('PLANNED', row.AXF_FTX_PKL_PlanKind__c);
      Assert.areEqual('OPEN', row.AXF_FTX_PKL_ScheduleState__c);
      Assert.isFalse(row.AXF_FTX_BOL_BasisFrozen__c);
      Assert.areEqual(
        row.AXF_FTX_DAT_NominalDueDate__c,
        row.AXF_FTX_DAT_DueDate__c,
        'O vencimento efetivo nasce igual ao nominal, preservando a âncora do mês'
      );
      Assert.areEqual(
        row.AXF_FTX_NUM_Magnitude__c,
        row.AXF_FTX_NUM_CurrentBasis__c
      );
      Assert.areEqual(1, row.AXF_FTX_NUM_ProjectionRevision__c.intValue());
      Assert.isNull(
        row.AXF_FTX_TXT_ScheduleGroupKey__c,
        'A via nova não reusa o namespace de idempotência de AXF-20'
      );
    }
  }

  @IsTest
  static void repeatedEquivalentCommandReplaysTheOriginalAuthorizedResult() {
    Account holder = holder('AXF103 replay');
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      holder.Id
    };
    ALT_CLS_FinancialScheduleService.CreateInput input = request(
      holder.Id,
      'INSTALLMENT',
      24,
      1,
      Date.today(),
      'axf103-replay'
    );

    ALT_CLS_FinancialScheduleService.CreateResult first = ALT_CLS_FinancialScheduleService.createSchedule(
      input
    );
    Integer occurrences = first.occurrenceCount;
    ALT_CLS_FinancialScheduleService.CreateResult again = ALT_CLS_FinancialScheduleService.createSchedule(
      input
    );

    Assert.areEqual('CREATED', first.outcome, first.message);
    Assert.areEqual('REPLAY', again.outcome, again.message);
    Assert.isTrue(again.replay);
    Assert.areEqual(first.scheduleId, again.scheduleId);
    Assert.areEqual(first.changeId, again.changeId);
    Assert.areEqual(occurrences, again.occurrenceCount);
    Assert.areEqual(1, [SELECT COUNT() FROM AXF_OBJ_FinancialSchedule__c]);
    Assert.areEqual(1, [SELECT COUNT() FROM AXF_OBJ_ScheduleChange__c]);
    Assert.areEqual(
      occurrences,
      [
        SELECT COUNT()
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE AXF_FTX_LKP_Schedule__c = :first.scheduleId
      ],
      'Uma linha por identidade de ocorrência: a repetição não duplica'
    );
    Assert.areEqual(
      occurrences,
      [
        SELECT COUNT()
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE
          AXF_FTX_LKP_Schedule__c = :first.scheduleId
          AND AXF_FTX_EXI_OccurrenceKey__c != NULL
      ]
    );
  }

  @IsTest
  static void changedPayloadOnTheSameScheduleIdentityConflicts() {
    Account holder = holder('AXF103 conflito');
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      holder.Id
    };
    ALT_CLS_FinancialScheduleService.CreateInput input = request(
      holder.Id,
      'INSTALLMENT',
      24,
      1,
      Date.today(),
      'axf103-conflict'
    );
    ALT_CLS_FinancialScheduleService.CreateResult first = ALT_CLS_FinancialScheduleService.createSchedule(
      input
    );
    Assert.areEqual('CREATED', first.outcome, first.message);
    Integer occurrences = first.occurrenceCount;

    input.principal = 480000;
    ALT_CLS_FinancialScheduleService.CreateResult conflicting = ALT_CLS_FinancialScheduleService.createSchedule(
      input
    );

    Assert.areEqual('CONFLICT', conflicting.outcome, conflicting.message);
    Assert.areEqual(1, [SELECT COUNT() FROM AXF_OBJ_FinancialSchedule__c]);
    Assert.areEqual(
      occurrences,
      [
        SELECT COUNT()
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE AXF_FTX_LKP_Schedule__c = :first.scheduleId
      ],
      'Um payload alterado nunca é tratado como replay bem-sucedido'
    );
  }

  @IsTest
  static void windowAboveTheTransactionLimitIsRejectedBeforeWriting() {
    Account holder = holder('AXF103 limite');
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      holder.Id
    };
    ALT_CLS_FinancialScheduleService.windowLimitOverride = 5;

    ALT_CLS_FinancialScheduleService.CreateResult result = ALT_CLS_FinancialScheduleService.createSchedule(
      request(holder.Id, 'INSTALLMENT', 24, 1, Date.today(), 'axf103-limit')
    );

    Assert.areEqual('TOO_LARGE', result.outcome, result.message);
    Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_FinancialSchedule__c]);
    Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_ScheduleDefinition__c]);
    Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_ScheduleChange__c]);
    Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_FinancialTransaction__c]);
  }

  @IsTest
  static void multiHolderAndMultiScheduleCommandsAreRejectedBeforeAnyWrite() {
    Account first = holder('AXF103 titular A');
    Account second = holder('AXF103 titular B');
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      first.Id,
      second.Id
    };

    List<ALT_CLS_FinancialScheduleService.CreateResult> mixed = ALT_CLS_FinancialScheduleService.createSchedules(
      new List<ALT_CLS_FinancialScheduleService.CreateInput>{
        request(first.Id, 'INSTALLMENT', 12, 1, Date.today(), 'axf103-a'),
        request(second.Id, 'INSTALLMENT', 12, 1, Date.today(), 'axf103-b')
      }
    );
    // Um desfecho por entrada: um consumidor que associa por índice não lê o resultado errado.
    Assert.areEqual(2, mixed.size(), 'Um resultado por entrada');
    Assert.areEqual('MULTI_HOLDER', mixed[0].outcome, mixed[0].message);
    Assert.areEqual('MULTI_HOLDER', mixed[1].outcome, mixed[1].message);
    Assert.isNotNull(mixed[0].scheduleKey);
    Assert.isNotNull(mixed[1].scheduleKey);
    Assert.areNotEqual(
      mixed[0].scheduleKey,
      mixed[1].scheduleKey,
      'Cada desfecho carrega a identidade da própria entrada'
    );

    List<ALT_CLS_FinancialScheduleService.CreateResult> sameHolder = ALT_CLS_FinancialScheduleService.createSchedules(
      new List<ALT_CLS_FinancialScheduleService.CreateInput>{
        request(first.Id, 'INSTALLMENT', 12, 1, Date.today(), 'axf103-c'),
        request(first.Id, 'INSTALLMENT', 12, 1, Date.today(), 'axf103-d')
      }
    );
    Assert.areEqual(2, sameHolder.size(), 'Um resultado por entrada');
    Assert.areEqual('INVALID', sameHolder[0].outcome, sameHolder[0].message);
    Assert.areEqual('INVALID', sameHolder[1].outcome, sameHolder[1].message);
    Assert.isNotNull(sameHolder[0].scheduleKey);
    Assert.areNotEqual(
      sameHolder[0].scheduleKey,
      sameHolder[1].scheduleKey,
      'A rejeição em massa não confunde as identidades das entradas'
    );

    Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_FinancialSchedule__c]);
    Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_FinancialTransaction__c]);
  }

  @IsTest
  static void unauthorizedHolderCannotCreateAndNothingIsWritten() {
    Account holder = holder('AXF103 não autorizado');
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>();

    ALT_CLS_FinancialScheduleService.CreateResult result = ALT_CLS_FinancialScheduleService.createSchedule(
      request(holder.Id, 'INSTALLMENT', 12, 1, Date.today(), 'axf103-forbidden')
    );

    Assert.areEqual('FORBIDDEN', result.outcome, result.message);
    Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_FinancialSchedule__c]);
    Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_FinancialTransaction__c]);
  }

  @IsTest
  static void amountBeyondTheEffectiveMagnitudeBoundIsRejectedBeforeWriting() {
    Account holder = holder('AXF103 estouro');
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      holder.Id
    };
    ALT_CLS_FinancialScheduleService.CreateInput input = request(
      holder.Id,
      'INSTALLMENT',
      12,
      1,
      Date.today(),
      'axf103-overflow'
    );
    input.principal = 1000000000000000.00;

    ALT_CLS_FinancialScheduleService.CreateResult result = ALT_CLS_FinancialScheduleService.createSchedule(
      input
    );

    Assert.areEqual('INVALID', result.outcome, result.message);
    Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_FinancialSchedule__c]);
    Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_FinancialTransaction__c]);
  }

  @IsTest
  static void estimatedSchedulePersistsAnInitialReferenceAndMarksEstimates() {
    Account holder = holder('AXF103 estimado');
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      holder.Id
    };

    ALT_CLS_FinancialScheduleService.CreateResult result = ALT_CLS_FinancialScheduleService.createSchedule(
      request(holder.Id, 'ESTIMATED', 12, 1, Date.today(), 'axf103-estimated')
    );

    Assert.areEqual('CREATED', result.outcome, result.message);
    Assert.isNotNull(result.referenceId);
    AXF_OBJ_ScheduleReference__c reference = [
      SELECT
        AXF_SRF_PKL_Kind__c,
        AXF_SRF_NUM_RecurringAmount__c,
        AXF_SRF_NUM_EconomicSequence__c,
        AXF_SRF_DT_ConfirmedAt__c,
        AXF_SRF_LKP_ConfirmedBy__c
      FROM AXF_OBJ_ScheduleReference__c
      WHERE Id = :result.referenceId
    ];
    Assert.areEqual('INITIAL', reference.AXF_SRF_PKL_Kind__c);
    Assert.areEqual(500.00, reference.AXF_SRF_NUM_RecurringAmount__c);
    // As colunas de confirmação de um objeto de evidência imutável não ficam nulas para sempre:
    // o comando autorizado que cria a referência inicial é quem confirma.
    Assert.isNotNull(
      reference.AXF_SRF_DT_ConfirmedAt__c,
      'A referência inicial é confirmada na criação'
    );
    Assert.areEqual(
      UserInfo.getUserId(),
      reference.AXF_SRF_LKP_ConfirmedBy__c,
      'Quem confirmou a referência inicial é o ator do comando'
    );
    Assert.areEqual(
      result.referenceId,
      [
        SELECT AXF_FSC_LKP_ActiveReference__c
        FROM AXF_OBJ_FinancialSchedule__c
        WHERE Id = :result.scheduleId
      ]
      .AXF_FSC_LKP_ActiveReference__c,
      'Um cronograma estimado exige referência vigente'
    );

    for (AXF_OBJ_FinancialTransaction__c row : [
      SELECT
        AXF_FTX_CHK_IsEstimated__c,
        AXF_FTX_NUM_Magnitude__c,
        AXF_FTX_PKL_Modality__c,
        AXF_FTX_LKP_ScheduleReference__c,
        AXF_FTX_NUM_PrincipalPortion__c,
        AXF_FTX_NUM_InterestPortion__c,
        AXF_FTX_NUM_FeePortion__c,
        AXF_FTX_NUM_ClosingBalance__c,
        AXF_FTX_CHK_RoundingResidual__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE AXF_FTX_LKP_Schedule__c = :result.scheduleId
    ]) {
      Assert.isTrue(row.AXF_FTX_CHK_IsEstimated__c);
      Assert.areEqual(500.00, row.AXF_FTX_NUM_Magnitude__c);
      Assert.isNull(
        row.AXF_FTX_PKL_Modality__c,
        'ESTIMATED não é uma modalidade da política de amortização'
      );
      Assert.areEqual(result.referenceId, row.AXF_FTX_LKP_ScheduleReference__c);
      // Sem fórmula aprovada não há decomposição: nula, e não zero inventado.
      Assert.isNull(row.AXF_FTX_NUM_PrincipalPortion__c);
      Assert.isNull(row.AXF_FTX_NUM_InterestPortion__c);
      Assert.isNull(row.AXF_FTX_NUM_FeePortion__c);
      Assert.isNull(row.AXF_FTX_NUM_ClosingBalance__c);
      Assert.isFalse(row.AXF_FTX_CHK_RoundingResidual__c);
    }
  }

  @IsTest
  static void evidenceIsImmutableAndDeletionIsBlocked() {
    Account holder = holder('AXF103 imutável');
    Account other = holder('AXF103 outro titular');
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      holder.Id
    };
    ALT_CLS_FinancialScheduleService.CreateResult result = ALT_CLS_FinancialScheduleService.createSchedule(
      request(holder.Id, 'ESTIMATED', 12, 1, Date.today(), 'axf103-immutable')
    );
    Assert.areEqual('CREATED', result.outcome, result.message);

    AXF_OBJ_ScheduleDefinition__c definition = [
      SELECT Id
      FROM AXF_OBJ_ScheduleDefinition__c
      WHERE AXF_SDF_LKP_Schedule__c = :result.scheduleId
    ];
    AXF_OBJ_ScheduleChange__c receipt = [
      SELECT Id
      FROM AXF_OBJ_ScheduleChange__c
      WHERE Id = :result.changeId
    ];

    Assert.isFalse(
      Database.update(
          new AXF_OBJ_ScheduleDefinition__c(
            Id = definition.Id,
            AXF_SDF_NUM_Principal__c = 1
          ),
          false
        )
        .isSuccess(),
      'A definição é evidência imutável'
    );
    Assert.isFalse(
      Database.delete(definition, false).isSuccess(),
      'A definição não pode ser excluída'
    );
    Assert.isFalse(
      Database.update(
          new AXF_OBJ_ScheduleReference__c(
            Id = result.referenceId,
            AXF_SRF_NUM_RecurringAmount__c = 1
          ),
          false
        )
        .isSuccess(),
      'A referência é evidência imutável'
    );
    Assert.isFalse(
      Database.delete(
          new AXF_OBJ_ScheduleReference__c(Id = result.referenceId),
          false
        )
        .isSuccess(),
      'A referência não pode ser excluída'
    );
    Assert.isFalse(
      Database.update(
          new AXF_OBJ_ScheduleChange__c(
            Id = receipt.Id,
            AXF_SCH_TAL_ResultJson__c = '{}'
          ),
          false
        )
        .isSuccess(),
      'O recibo é imutável'
    );
    Assert.isFalse(
      Database.delete(receipt, false).isSuccess(),
      'O recibo não pode ser excluído'
    );
    Assert.isFalse(
      Database.delete(
          new AXF_OBJ_FinancialSchedule__c(Id = result.scheduleId),
          false
        )
        .isSuccess(),
      'O cronograma não pode ser excluído'
    );
    Assert.isFalse(
      Database.update(
          new AXF_OBJ_FinancialSchedule__c(
            Id = result.scheduleId,
            AXF_FSC_LKP_Account__c = other.Id
          ),
          false
        )
        .isSuccess(),
      'Cronograma em uso não é reparentado'
    );

    // Estado, contadores e revisões derivadas só mudam por comando autorizado: nenhuma edição
    // direta encerra, reabre ou reescreve a revisão de um cronograma.
    Assert.isFalse(
      Database.update(
          new AXF_OBJ_FinancialSchedule__c(
            Id = result.scheduleId,
            AXF_FSC_PKL_State__c = 'ENDED'
          ),
          false
        )
        .isSuccess(),
      'O estado do cronograma é mantido pelo serviço autorizado'
    );
    Assert.isFalse(
      Database.update(
          new AXF_OBJ_FinancialSchedule__c(
            Id = result.scheduleId,
            AXF_FSC_NUM_ProjectionRevision__c = 99
          ),
          false
        )
        .isSuccess(),
      'Contadores e revisões derivadas não são editáveis diretamente'
    );
    Assert.isFalse(
      Database.update(
          new AXF_OBJ_FinancialSchedule__c(
            Id = result.scheduleId,
            AXF_FSC_NUM_FinancialVersion__c = 99
          ),
          false
        )
        .isSuccess(),
      'A época financeira não é reescrita diretamente'
    );
    Assert.areEqual(
      'ACTIVE',
      [
        SELECT AXF_FSC_PKL_State__c
        FROM AXF_OBJ_FinancialSchedule__c
        WHERE Id = :result.scheduleId
      ]
      .AXF_FSC_PKL_State__c
    );
  }

  @IsTest
  static void duplicateDefinitionRevisionIsRejected() {
    Account holder = holder('AXF103 revisão');
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      holder.Id
    };
    ALT_CLS_FinancialScheduleService.CreateResult result = ALT_CLS_FinancialScheduleService.createSchedule(
      request(holder.Id, 'INSTALLMENT', 12, 1, Date.today(), 'axf103-revision')
    );
    Assert.areEqual('CREATED', result.outcome, result.message);

    Assert.isFalse(
      Database.insert(
          new AXF_OBJ_ScheduleDefinition__c(
            AXF_SDF_EXI_DefinitionKey__c = 'axf103-duplicate-revision',
            AXF_SDF_LKP_Schedule__c = result.scheduleId,
            AXF_SDF_NUM_Revision__c = 1,
            AXF_SDF_NUM_EffectiveSequence__c = 1,
            AXF_SDF_PKL_Method__c = 'INSTALLMENT',
            AXF_SDF_NUM_TotalInstallments__c = 12,
            AXF_SDF_NUM_FirstSequence__c = 1,
            AXF_SDF_DAT_FirstDueDate__c = Date.today(),
            AXF_SDF_NUM_AnchorDay__c = 10,
            AXF_SDF_NUM_PeriodMonths__c = 1,
            AXF_SDF_NUM_Principal__c = 1200
          ),
          false
        )
        .isSuccess(),
      'A revisão é única dentro do cronograma'
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AXF_OBJ_ScheduleDefinition__c
        WHERE AXF_SDF_LKP_Schedule__c = :result.scheduleId
      ]
    );
  }

  @IsTest
  static void activeRootWithoutADefinitionIsRejected() {
    Account holder = holder('AXF103 raiz inválida');

    Assert.isFalse(
      Database.insert(
          new AXF_OBJ_FinancialSchedule__c(
            AXF_FSC_EXI_ScheduleKey__c = 'axf103-active-without-definition',
            AXF_FSC_LKP_Account__c = holder.Id,
            AXF_FSC_TXT_CurrencyIsoCode__c = 'BRL',
            AXF_FSC_PKL_Direction__c = 'DEBIT',
            AXF_FSC_PKL_State__c = 'ACTIVE',
            AXF_FSC_NUM_TrackingStartSequence__c = 1
          ),
          false
        )
        .isSuccess(),
      'ACTIVE exige definição vigente do mesmo cronograma'
    );
  }

  @IsTest
  static void referencedEvidenceSurvivesCreateAndProjectionAndTheGuardHolds() {
    Id targetId;
    Account shared;
    System.runAs(actor()) {
      shared = holder('AXF103 guarda AXF-25');
      AXF_OBJ_FinancialTransaction__c target = new AXF_OBJ_FinancialTransaction__c(
        AXF_FTX_LKP_Account__c = shared.Id,
        AXF_FTX_NUM_Magnitude__c = 100,
        AXF_FTX_PKL_Direction__c = 'DEBIT',
        AXF_FTX_TXT_CurrencyIsoCode__c = 'BRL',
        AXF_FTX_DAT_PurchaseDate__c = Date.today(),
        AXF_FTX_DAT_DueDate__c = Date.today(),
        AXF_FTX_PKL_Status__c = 'PLANNED',
        AXF_FTX_PKL_PlanKind__c = 'PLANNED',
        AXF_FTX_NUM_Version__c = 0,
        AXF_FTX_EXI_ClientRequestId__c = 'axf103-legacy-target-0001'
      );
      insert target;
      targetId = target.Id;

      ALT_CLS_RealizationService.Input realization = new ALT_CLS_RealizationService.Input();
      realization.targetId = target.Id;
      realization.sourceKind = 'CASH';
      realization.amount = 40;
      realization.targetVersion = 0;
      realization.operationKey = 'axf103-guard';
      realization.recognitionDate = Date.today();
      new ALT_CLS_RealizationService().apply(realization);
    }
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AXF_OBJ_ReconciliationAllocation__c
        WHERE AXF_RA_LKP_FinancialTransaction__c = :targetId
      ],
      'A evidência de origem fica referenciada por alocação'
    );

    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      shared.Id
    };
    ALT_CLS_FinancialScheduleService.CreateResult created = ALT_CLS_FinancialScheduleService.createSchedule(
      request(shared.Id, 'INSTALLMENT', 24, 1, Date.today(), 'axf103-guard')
    );
    Assert.areEqual('CREATED', created.outcome, created.message);

    ALT_CLS_ScheduleProjection.ProjectionInput input = new ALT_CLS_ScheduleProjection.ProjectionInput();
    input.scheduleId = created.scheduleId;
    input.asOfDate = Date.today();
    ALT_CLS_ScheduleProjection.ProjectionResult projection = ALT_CLS_FinancialScheduleService.readProjection(
      input
    );
    Assert.areEqual('OK', projection.outcome, projection.message);

    AXF_OBJ_FinancialTransaction__c after = [
      SELECT
        AXF_FTX_NUM_Magnitude__c,
        AXF_FTX_PKL_Status__c,
        AXF_FTX_PKL_PlanKind__c,
        AXF_FTX_PKL_Direction__c,
        AXF_FTX_TXT_CurrencyIsoCode__c,
        AXF_FTX_DAT_DueDate__c,
        AXF_FTX_NUM_Version__c,
        AXF_FTX_LKP_Schedule__c,
        AXF_FTX_EXI_OccurrenceKey__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE Id = :targetId
    ];
    Assert.areEqual(100.00, after.AXF_FTX_NUM_Magnitude__c);
    Assert.areEqual('PLANNED', after.AXF_FTX_PKL_Status__c);
    Assert.areEqual('PLANNED', after.AXF_FTX_PKL_PlanKind__c);
    Assert.areEqual('DEBIT', after.AXF_FTX_PKL_Direction__c);
    Assert.areEqual('BRL', after.AXF_FTX_TXT_CurrencyIsoCode__c);
    Assert.areEqual(Date.today(), after.AXF_FTX_DAT_DueDate__c);
    Assert.isNull(
      after.AXF_FTX_LKP_Schedule__c,
      'A criação e a leitura da projeção não vinculam nem alteram a linha referenciada'
    );
    Assert.isNull(after.AXF_FTX_EXI_OccurrenceKey__c);

    Assert.isFalse(
      Database.update(
          new AXF_OBJ_FinancialTransaction__c(
            Id = targetId,
            AXF_FTX_NUM_Magnitude__c = 999
          ),
          false
        )
        .isSuccess(),
      'A guarda AXF-25 continua congelando a evidência já referenciada'
    );
  }

  @IsTest
  static void scheduleBackedOccurrenceCannotForgeAProtectedFinancialRole() {
    Account holder = holder('AXF103 papel forjado');
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      holder.Id
    };
    ALT_CLS_FinancialScheduleService.CreateResult created = ALT_CLS_FinancialScheduleService.createSchedule(
      request(holder.Id, 'INSTALLMENT', 24, 1, Date.today(), 'axf103-role')
    );
    Assert.areEqual('CREATED', created.outcome, created.message);

    Assert.isFalse(
      Database.insert(
          new AXF_OBJ_FinancialTransaction__c(
            AXF_FTX_LKP_Account__c = holder.Id,
            AXF_FTX_LKP_Schedule__c = created.scheduleId,
            AXF_FTX_NUM_Magnitude__c = 10,
            AXF_FTX_PKL_Direction__c = 'DEBIT',
            AXF_FTX_TXT_CurrencyIsoCode__c = 'BRL',
            AXF_FTX_DAT_PurchaseDate__c = Date.today(),
            AXF_FTX_PKL_Status__c = 'PLANNED',
            AXF_FTX_PKL_PlanKind__c = 'CASH_FACT',
            AXF_FTX_NUM_Version__c = 0,
            AXF_FTX_EXI_ClientRequestId__c = 'axf103-forged-role-0001'
          ),
          false
        )
        .isSuccess(),
      'O papel financeiro de uma ocorrência vinculada continua sendo atribuído pelo serviço'
    );
  }

  @IsTest
  static void participanteCannotCreateASchedule() {
    User participante = [
      SELECT Id
      FROM User
      WHERE Alias = 'axf103p'
      LIMIT 1
    ];
    Account holder = holder('AXF103 participante');
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      holder.Id
    };
    ALT_CLS_FinancialScheduleService.CreateInput input = request(
      holder.Id,
      'INSTALLMENT',
      12,
      1,
      Date.today(),
      'axf103-participante'
    );

    ALT_CLS_FinancialScheduleService.CreateResult result;
    System.runAs(participante) {
      result = ALT_CLS_FinancialScheduleService.createSchedule(input);
    }

    Assert.areEqual('FORBIDDEN', result.outcome, result.message);
    Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_FinancialSchedule__c]);
    Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_ScheduleDefinition__c]);
    Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_FinancialTransaction__c]);
  }

  @IsTest
  static void evidenceObjectsAreReadOnlyToUsersAndWritableOnlyThroughTheService() {
    // Declarativo: o perfil que cria a raiz não pode criar/editar a evidência e a referência.
    Map<String, ObjectPermissions> byObject = new Map<String, ObjectPermissions>();
    for (ObjectPermissions permission : [
      SELECT SobjectType, PermissionsCreate, PermissionsEdit, PermissionsRead
      FROM ObjectPermissions
      WHERE
        Parent.Name = 'AXF_PS_GestorFinanceiro'
        AND SobjectType IN (
          'AXF_OBJ_FinancialSchedule__c',
          'AXF_OBJ_ScheduleDefinition__c',
          'AXF_OBJ_ScheduleReference__c',
          'AXF_OBJ_ScheduleChange__c'
        )
    ]) {
      byObject.put(permission.SobjectType, permission);
    }
    Assert.areEqual(4, byObject.size());
    Assert.isTrue(
      byObject.get('AXF_OBJ_FinancialSchedule__c').PermissionsCreate,
      'A raiz é a única com criação, que é a autoridade de escrita do comando'
    );
    Assert.isTrue(byObject.get('AXF_OBJ_FinancialSchedule__c').PermissionsEdit);
    for (
      String evidence : new List<String>{
        'AXF_OBJ_ScheduleDefinition__c',
        'AXF_OBJ_ScheduleReference__c',
        'AXF_OBJ_ScheduleChange__c'
      }
    ) {
      Assert.isFalse(
        byObject.get(evidence).PermissionsCreate,
        evidence + ' não pode ser gravável por usuário'
      );
      Assert.isFalse(
        byObject.get(evidence).PermissionsEdit,
        evidence + ' não pode ser editável por usuário'
      );
      Assert.isTrue(byObject.get(evidence).PermissionsRead);
    }

    // Comportamental: um perfil somente-leitura não consegue forjar a evidência por DML. A
    // definição é montada com todos os campos obrigatórios preenchidos, para que a única causa
    // possível da recusa seja a permissão.
    User participante = [
      SELECT Id
      FROM User
      WHERE Alias = 'axf103p'
      LIMIT 1
    ];
    Account holder = holder('AXF103 evidência');
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      holder.Id
    };
    ALT_CLS_FinancialScheduleService.CreateResult created = ALT_CLS_FinancialScheduleService.createSchedule(
      request(holder.Id, 'INSTALLMENT', 12, 1, Date.today(), 'axf103-evidence')
    );
    Assert.areEqual('CREATED', created.outcome, created.message);

    System.runAs(participante) {
      Assert.isFalse(
        Database.insert(
            new AXF_OBJ_ScheduleDefinition__c(
              AXF_SDF_EXI_DefinitionKey__c = 'axf103-forged-definition',
              AXF_SDF_LKP_Schedule__c = created.scheduleId,
              AXF_SDF_NUM_Revision__c = 2,
              AXF_SDF_NUM_EffectiveSequence__c = 1,
              AXF_SDF_PKL_Method__c = 'INSTALLMENT',
              AXF_SDF_NUM_TotalInstallments__c = 12,
              AXF_SDF_NUM_FirstSequence__c = 1,
              AXF_SDF_DAT_FirstDueDate__c = Date.today(),
              AXF_SDF_NUM_AnchorDay__c = 10,
              AXF_SDF_NUM_PeriodMonths__c = 1,
              AXF_SDF_NUM_Principal__c = 1200
            ),
            false
          )
          .isSuccess(),
        'A definição não é gravável por um perfil somente-leitura'
      );
    }
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AXF_OBJ_ScheduleDefinition__c
        WHERE AXF_SDF_LKP_Schedule__c = :created.scheduleId
      ],
      'Nenhuma evidência forjada foi aceita'
    );
  }

  @IsTest
  static void directlyInsertedActiveRootWithAForeignDefinitionIsRejected() {
    Account holder = holder('AXF103 raiz alheia');
    Account other = holder('AXF103 outro cronograma');
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      holder.Id,
      other.Id
    };
    ALT_CLS_FinancialScheduleService.CreateResult existing = ALT_CLS_FinancialScheduleService.createSchedule(
      request(other.Id, 'INSTALLMENT', 12, 1, Date.today(), 'axf103-foreign')
    );
    Assert.areEqual('CREATED', existing.outcome, existing.message);

    // Raiz ACTIVE inserida diretamente apontando a definição de OUTRO cronograma: as
    // invariantes de ACTIVE precisam valer também na inserção.
    Assert.isFalse(
      Database.insert(
          new AXF_OBJ_FinancialSchedule__c(
            AXF_FSC_EXI_ScheduleKey__c = 'axf103-active-foreign-definition',
            AXF_FSC_LKP_Account__c = holder.Id,
            AXF_FSC_TXT_CurrencyIsoCode__c = 'BRL',
            AXF_FSC_PKL_Direction__c = 'DEBIT',
            AXF_FSC_PKL_State__c = 'ACTIVE',
            AXF_FSC_NUM_TrackingStartSequence__c = 1,
            AXF_FSC_LKP_ActiveDefinition__c = existing.definitionId
          ),
          false
        )
        .isSuccess(),
      'Definição vigente deve pertencer ao mesmo cronograma, inclusive na inserção'
    );
    // E um ponteiro inexistente também não passa.
    Assert.isFalse(
      Database.insert(
          new AXF_OBJ_FinancialSchedule__c(
            AXF_FSC_EXI_ScheduleKey__c = 'axf103-active-missing-definition',
            AXF_FSC_LKP_Account__c = holder.Id,
            AXF_FSC_TXT_CurrencyIsoCode__c = 'BRL',
            AXF_FSC_PKL_Direction__c = 'DEBIT',
            AXF_FSC_PKL_State__c = 'ACTIVE',
            AXF_FSC_NUM_TrackingStartSequence__c = 1
          ),
          false
        )
        .isSuccess(),
      'Definição vigente é obrigatória para ACTIVE'
    );
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM AXF_OBJ_FinancialSchedule__c
        WHERE
          AXF_FSC_EXI_ScheduleKey__c IN (
            'axf103-active-foreign-definition',
            'axf103-active-missing-definition'
          )
      ]
    );
  }

  @IsTest
  static void scheduleIdentityCarriesTheContractAndTheStreamDiscriminator() {
    Account holder = holder('AXF103 identidade');
    String keyPrefix = AXF_OBJ_Contract__c.SObjectType.getDescribe()
      .getKeyPrefix();
    ALT_CLS_FinancialScheduleService.CreateInput first = request(
      holder.Id,
      'INSTALLMENT',
      12,
      1,
      Date.today(),
      'axf103-stream-a'
    );
    ALT_CLS_FinancialScheduleService.CreateInput second = request(
      holder.Id,
      'INSTALLMENT',
      12,
      1,
      Date.today(),
      'axf103-stream-a'
    );
    // Mesmo titular, mesmo calendário, contratos diferentes: não podem colidir.
    first.contractId = Id.valueOf(keyPrefix + '000000000001');
    second.contractId = Id.valueOf(keyPrefix + '000000000002');
    Assert.areNotEqual(
      ALT_CLS_FinancialScheduleService.previewScheduleKey(first),
      ALT_CLS_FinancialScheduleService.previewScheduleKey(second),
      'O contrato participa da identidade do cronograma'
    );

    // Um contrato admite vários cronogramas: sem o contrato real disponível no fixture, o
    // discriminador do fluxo é exercitado no mesmo titular com o mesmo calendário.
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      holder.Id
    };
    ALT_CLS_FinancialScheduleService.CreateResult streamA = ALT_CLS_FinancialScheduleService.createSchedule(
      request(holder.Id, 'INSTALLMENT', 12, 1, Date.today(), 'axf103-stream-a')
    );
    ALT_CLS_FinancialScheduleService.CreateResult streamB = ALT_CLS_FinancialScheduleService.createSchedule(
      request(holder.Id, 'INSTALLMENT', 12, 1, Date.today(), 'axf103-stream-b')
    );
    Assert.areEqual('CREATED', streamA.outcome, streamA.message);
    Assert.areEqual('CREATED', streamB.outcome, streamB.message);
    Assert.areNotEqual(streamA.scheduleId, streamB.scheduleId);
    Assert.isFalse(streamB.replay);
    Assert.areEqual(2, [SELECT COUNT() FROM AXF_OBJ_FinancialSchedule__c]);

    // Reenvio exato do primeiro fluxo continua sendo replay, não um terceiro cronograma.
    ALT_CLS_FinancialScheduleService.CreateResult repeat = ALT_CLS_FinancialScheduleService.createSchedule(
      request(holder.Id, 'INSTALLMENT', 12, 1, Date.today(), 'axf103-stream-a')
    );
    Assert.areEqual('REPLAY', repeat.outcome, repeat.message);
    Assert.areEqual(streamA.scheduleId, repeat.scheduleId);
    Assert.areEqual(2, [SELECT COUNT() FROM AXF_OBJ_FinancialSchedule__c]);
  }

  @IsTest
  static void semanticallyIdenticalRetryReplaysInsteadOfConflicting() {
    Account holder = holder('AXF103 normalização');
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      holder.Id
    };
    ALT_CLS_FinancialScheduleService.CreateInput first = request(
      holder.Id,
      'INSTALLMENT',
      12,
      1,
      Date.today(),
      'axf103-normalize'
    );
    first.timeZone = 'America/Sao_Paulo';
    first.reason = 'carga inicial';
    ALT_CLS_FinancialScheduleService.CreateResult created = ALT_CLS_FinancialScheduleService.createSchedule(
      first
    );
    Assert.areEqual('CREATED', created.outcome, created.message);

    // Mesmo payload econômico, com ruído de representação: espaços em volta do texto, valor de
    // referência enviado como zero em vez de omitido e tarifas nulas.
    ALT_CLS_FinancialScheduleService.CreateInput retry = request(
      holder.Id,
      'INSTALLMENT',
      12,
      1,
      Date.today(),
      '  axf103-normalize  '
    );
    retry.timeZone = '  America/Sao_Paulo  ';
    retry.reason = 'carga inicial';
    retry.referenceAmount = 0.00;
    retry.recurringFee = 0.00;
    retry.upfrontFee = 0.00;
    ALT_CLS_FinancialScheduleService.CreateResult repeated = ALT_CLS_FinancialScheduleService.createSchedule(
      retry
    );

    Assert.areEqual('REPLAY', repeated.outcome, repeated.message);
    Assert.areEqual(created.scheduleId, repeated.scheduleId);
    Assert.areEqual(1, [SELECT COUNT() FROM AXF_OBJ_FinancialSchedule__c]);
  }

  @IsTest
  static void legacyAxF20GroupKeyNamespaceIsNotReusedByThisPath() {
    Account holder = holder('AXF103 namespace');
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      holder.Id
    };

    // AXF-156: o planejador AXF-20 também grava um cronograma gerenciado; a groupKey dele vira a
    // chave legada do cronograma (parte da identidade), nunca o `ScheduleGroupKey` das linhas.
    AXF_CLS_ScheduleService.PlanInput plan = new AXF_CLS_ScheduleService.PlanInput();
    plan.modality = 'INSTALLMENT';
    plan.principal = 1200;
    plan.installments = 3;
    plan.firstDueDate = Date.today();
    AXF_CLS_ScheduleService.SaveInput legacy = new AXF_CLS_ScheduleService.SaveInput();
    legacy.plan = plan;
    legacy.accountId = holder.Id;
    legacy.direction = 'DEBIT';
    legacy.currencyIsoCode = 'BRL';
    legacy.groupKey = 'axf103-shared-key';
    AXF_CLS_ScheduleService.authorizedOverride = new Set<Id>{ holder.Id };
    AXF_CLS_ScheduleService.SaveResult saved = AXF_CLS_ScheduleService.save(
      legacy
    );
    Assert.areEqual('SAVED', saved.outcome, saved.message);
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE AXF_FTX_TXT_ScheduleGroupKey__c = 'axf103-shared-key'
      ],
      'O planejador não grava mais linhas no namespace de agrupamento AXF-20'
    );

    // Um comando direto com a MESMA chave legada e outro calendário é outra identidade: outro
    // cronograma, sem ocupar o campo de agrupamento.
    ALT_CLS_FinancialScheduleService.CreateResult created = ALT_CLS_FinancialScheduleService.createSchedule(
      request(
        holder.Id,
        'INSTALLMENT',
        12,
        1,
        Date.today(),
        'axf103-shared-key'
      )
    );
    Assert.areEqual('CREATED', created.outcome, created.message);
    Assert.areNotEqual(saved.scheduleId, created.scheduleId);
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE
          AXF_FTX_LKP_Schedule__c = :created.scheduleId
          AND AXF_FTX_TXT_ScheduleGroupKey__c != NULL
      ],
      'A via nova não ocupa o namespace de idempotência de AXF-20'
    );
    Assert.areEqual(
      created.occurrenceCount,
      [
        SELECT COUNT()
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE
          AXF_FTX_LKP_Schedule__c = :created.scheduleId
          AND AXF_FTX_EXI_OccurrenceKey__c != NULL
      ],
      'A identidade da via nova é a OccurrenceKey'
    );

    // O reenvio do planejador é o replay do próprio cronograma: ALREADY, sem duplicar.
    AXF_CLS_ScheduleService.SaveResult again = AXF_CLS_ScheduleService.save(
      legacy
    );
    Assert.areEqual('ALREADY', again.outcome, again.message);
    Assert.areEqual(saved.scheduleId, again.scheduleId);
    // E a via nova reenvia como replay, não como conflito.
    ALT_CLS_FinancialScheduleService.CreateResult repeat = ALT_CLS_FinancialScheduleService.createSchedule(
      request(
        holder.Id,
        'INSTALLMENT',
        12,
        1,
        Date.today(),
        'axf103-shared-key'
      )
    );
    Assert.areEqual('REPLAY', repeat.outcome, repeat.message);
    Assert.areEqual(created.scheduleId, repeat.scheduleId);
  }

  @IsTest
  static void calendarFormulaAndAmountFailuresAreReturnedAsInvalidNotThrown() {
    Account holder = holder('AXF103 rejeições');
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      holder.Id
    };

    // Calendário: primeiro vencimento incoerente com a parcela corrente e a sequência.
    ALT_CLS_FinancialScheduleService.CreateInput incoherent = request(
      holder.Id,
      'INSTALLMENT',
      12,
      1,
      Date.today(),
      'axf103-incoherent'
    );
    incoherent.firstDueDate = Date.today().addDays(5);
    incoherent.trackingDueDate = Date.today();
    incoherent.trackingStartSequence = 1;
    ALT_CLS_FinancialScheduleService.CreateResult calendar = ALT_CLS_FinancialScheduleService.createSchedule(
      incoherent
    );
    Assert.areEqual('INVALID', calendar.outcome, calendar.message);

    // Calendário: periodicidade fora do limite de sanidade do calendário puro.
    ALT_CLS_FinancialScheduleService.CreateInput absurd = request(
      holder.Id,
      'INSTALLMENT',
      12,
      1,
      Date.today(),
      'axf103-absurd'
    );
    absurd.periodMonths = 999;
    absurd.totalInstallments = 600;
    absurd.trackingStartSequence = 500;
    ALT_CLS_FinancialScheduleService.CreateResult absurdResult = ALT_CLS_FinancialScheduleService.createSchedule(
      absurd
    );
    Assert.areEqual('INVALID', absurdResult.outcome, absurdResult.message);

    // Fórmula: estouro de precisão em `powDecimal` (taxa e prazo grandes o bastante).
    ALT_CLS_FinancialScheduleService.CreateInput overflow = request(
      holder.Id,
      'PRICE',
      9999,
      1,
      Date.today(),
      'axf103-pow'
    );
    overflow.principal = 99999999999999.99;
    overflow.periodRate = 9.9999999999;
    ALT_CLS_FinancialScheduleService.CreateResult formula = ALT_CLS_FinancialScheduleService.createSchedule(
      overflow
    );
    Assert.areEqual('INVALID', formula.outcome, formula.message);

    // Valor calculado acima do limite efetivo de magnitude: principal e tarifa passam
    // individualmente, mas a parcela não cabe.
    ALT_CLS_FinancialScheduleService.CreateInput amountOverflow = request(
      holder.Id,
      'INSTALLMENT',
      1,
      1,
      Date.today(),
      'axf103-amount'
    );
    amountOverflow.principal = 99999999999999.99;
    amountOverflow.upfrontFee = 99999999999999.99;
    ALT_CLS_FinancialScheduleService.CreateResult amount = ALT_CLS_FinancialScheduleService.createSchedule(
      amountOverflow
    );
    Assert.areEqual('INVALID', amount.outcome, amount.message);

    Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_FinancialSchedule__c]);
    Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_ScheduleDefinition__c]);
    Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_ScheduleChange__c]);
    Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_FinancialTransaction__c]);
  }

  @IsTest
  static void windowAndFormulaAreComputedBeforeTheHolderLock() {
    Account holder = holder('AXF103 ordem');
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      holder.Id
    };

    // Rejeitada pela janela: nenhum lock do titular foi adquirido.
    ALT_CLS_FinancialScheduleService.windowLimitOverride = 5;
    ALT_CLS_FinancialScheduleService.CreateResult rejected = ALT_CLS_FinancialScheduleService.createSchedule(
      request(holder.Id, 'INSTALLMENT', 24, 1, Date.today(), 'axf103-order')
    );
    Assert.areEqual('TOO_LARGE', rejected.outcome, rejected.message);
    Assert.isFalse(
      ALT_CLS_FinancialScheduleService.lastRunLockedHolder,
      'A janela é calculada e validada antes do lock do titular'
    );

    // Aceita pela janela: o lock acontece depois do cálculo.
    ALT_CLS_FinancialScheduleService.windowLimitOverride = null;
    ALT_CLS_FinancialScheduleService.CreateResult accepted = ALT_CLS_FinancialScheduleService.createSchedule(
      request(holder.Id, 'INSTALLMENT', 24, 1, Date.today(), 'axf103-order')
    );
    Assert.areEqual('CREATED', accepted.outcome, accepted.message);
    Assert.isTrue(ALT_CLS_FinancialScheduleService.lastRunLockedHolder);
  }

  @IsTest
  static void windowLimitGuardUsesTheRealConstantAndRejectsActionably() {
    // Limite real: 50 passa, 51 é recusado, sem nenhuma sobreposição.
    ALT_CLS_FinancialScheduleService.enforceWindowLimit(
      ALT_CLS_FinancialScheduleService.MAX_INITIAL_WINDOW
    );
    try {
      ALT_CLS_FinancialScheduleService.enforceWindowLimit(
        ALT_CLS_FinancialScheduleService.MAX_INITIAL_WINDOW + 1
      );
      Assert.fail('Acima do limite real a janela precisa ser recusada');
    } catch (ALT_CLS_FinancialScheduleService.ServiceException expected) {
      Assert.isTrue(
        expected.getMessage().contains('horizonMonths'),
        'A recusa precisa indicar um parâmetro que o comando aceita: ' +
        expected.getMessage()
      );
      Assert.isTrue(
        expected.getMessage().contains('periodMonths'),
        'A recusa precisa indicar o outro parâmetro que o comando aceita: ' +
        expected.getMessage()
      );
    }

    // A sobreposição continua valendo para exercitar a recusa antes de qualquer escrita.
    ALT_CLS_FinancialScheduleService.windowLimitOverride = 5;
    try {
      ALT_CLS_FinancialScheduleService.enforceWindowLimit(6);
      Assert.fail('Acima da sobreposição a janela precisa ser recusada');
    } catch (ALT_CLS_FinancialScheduleService.ServiceException expected) {
      Assert.isTrue(expected.getMessage().contains('6'));
    } finally {
      ALT_CLS_FinancialScheduleService.windowLimitOverride = null;
    }

    Account holder = holder('AXF103 limite real');
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      holder.Id
    };
    // O horizonte é aceito e respeitado, mas nunca além do teto.
    ALT_CLS_FinancialScheduleService.CreateInput shortHorizon = request(
      holder.Id,
      'INSTALLMENT',
      24,
      1,
      Date.today(),
      'axf103-horizon'
    );
    shortHorizon.horizonMonths = 3;
    ALT_CLS_FinancialScheduleService.CreateResult created = ALT_CLS_FinancialScheduleService.createSchedule(
      shortHorizon
    );
    Assert.areEqual('CREATED', created.outcome, created.message);
    Assert.areEqual(3, created.occurrenceCount, 'O horizonte encurta a janela');
    Assert.areEqual(
      3,
      [
          SELECT AXF_FSC_NUM_HorizonMonths__c
          FROM AXF_OBJ_FinancialSchedule__c
          WHERE Id = :created.scheduleId
        ]
        .AXF_FSC_NUM_HorizonMonths__c
        .intValue()
    );

    ALT_CLS_FinancialScheduleService.CreateInput beyondCeiling = request(
      holder.Id,
      'INSTALLMENT',
      24,
      1,
      Date.today(),
      'axf103-horizon-cap'
    );
    beyondCeiling.horizonMonths =
      ALT_CLS_FinancialScheduleService.MAX_HORIZON_MONTHS + 1;
    ALT_CLS_FinancialScheduleService.CreateResult refused = ALT_CLS_FinancialScheduleService.createSchedule(
      beyondCeiling
    );
    Assert.areEqual('INVALID', refused.outcome, refused.message);
  }

  @IsTest
  static void dmlFailureAfterTheRootInsertPersistsNothingOfTheAttempt() {
    Account holder = holder('AXF103 falha dml');
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      holder.Id
    };
    // Ocupa a identidade de ocorrência que a tentativa vai tentar gravar.
    insert new AXF_OBJ_FinancialTransaction__c(
      AXF_FTX_LKP_Account__c = holder.Id,
      AXF_FTX_NUM_Magnitude__c = 10,
      AXF_FTX_PKL_Direction__c = 'DEBIT',
      AXF_FTX_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_FTX_DAT_PurchaseDate__c = Date.today(),
      AXF_FTX_PKL_Status__c = 'PLANNED',
      AXF_FTX_PKL_PlanKind__c = 'PLANNED',
      AXF_FTX_NUM_Version__c = 0,
      AXF_FTX_EXI_ClientRequestId__c = 'axf103-preoccupied-token',
      AXF_FTX_EXI_OccurrenceKey__c = 'axf103-preoccupied-full-identity'
    );
    ALT_CLS_FinancialScheduleService.forcedOccurrenceKey = 'axf103-preoccupied-full-identity';

    ALT_CLS_FinancialScheduleService.CreateResult result = ALT_CLS_FinancialScheduleService.createSchedule(
      request(holder.Id, 'INSTALLMENT', 24, 1, Date.today(), 'axf103-dml')
    );

    // A falha de DML nunca vira sucesso arbitrário: e o rollback não deixa nada da tentativa.
    Assert.isTrue(
      new Set<String>{ 'UNAVAILABLE', 'REPLAY', 'CONFLICT' }
        .contains(result.outcome),
      'Desfecho inesperado: ' + result.outcome + ' :: ' + result.message
    );
    ALT_CLS_FinancialScheduleService.forcedOccurrenceKey = null;
    Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_FinancialSchedule__c]);
    Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_ScheduleDefinition__c]);
    Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_ScheduleChange__c]);
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM AXF_OBJ_FinancialTransaction__c],
      'Resta apenas a linha que ocupava a identidade'
    );
  }

  @IsTest
  static void truncatedIdentityCollisionIsConflictNotUnavailable() {
    Account holder = holder('AXF103 truncado');
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      holder.Id
    };
    ALT_CLS_FinancialScheduleService.CreateInput input = request(
      holder.Id,
      'INSTALLMENT',
      24,
      1,
      Date.today(),
      'axf103-truncated'
    );
    String scheduleKey = ALT_CLS_FinancialScheduleService.previewScheduleKey(
      input
    );
    String fullKey = ALT_CLS_ScheduleProjection.occurrenceKey(scheduleKey, 1);
    // Mesmo token truncado de 36 caracteres, identidade COMPLETA diferente.
    insert new AXF_OBJ_FinancialTransaction__c(
      AXF_FTX_LKP_Account__c = holder.Id,
      AXF_FTX_NUM_Magnitude__c = 10,
      AXF_FTX_PKL_Direction__c = 'DEBIT',
      AXF_FTX_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_FTX_DAT_PurchaseDate__c = Date.today(),
      AXF_FTX_PKL_Status__c = 'PLANNED',
      AXF_FTX_PKL_PlanKind__c = 'PLANNED',
      AXF_FTX_NUM_Version__c = 0,
      AXF_FTX_EXI_OccurrenceKey__c = 'axf103-foreign-full-identity',
      AXF_FTX_EXI_ClientRequestId__c = ALT_CLS_ScheduleProjection.clientRequestId(
        fullKey
      )
    );

    ALT_CLS_FinancialScheduleService.CreateResult result = ALT_CLS_FinancialScheduleService.createSchedule(
      input
    );

    Assert.areEqual('CONFLICT', result.outcome, result.message);
    Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_FinancialSchedule__c]);
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM AXF_OBJ_FinancialTransaction__c],
      'Resta apenas a linha estrangeira'
    );
  }

  @IsTest
  static void legacyRowsDoNotClaimMembershipOfAnOpenSchedule() {
    Account holder = holder('AXF103 cache nulo');

    // Caminho legado/importação/manual: sem escritor de cronograma, o cache derivado é nulo e
    // não declara participação em cronograma aberto por omissão.
    AXF_OBJ_FinancialTransaction__c legacy = new AXF_OBJ_FinancialTransaction__c(
      AXF_FTX_LKP_Account__c = holder.Id,
      AXF_FTX_NUM_Magnitude__c = 100,
      AXF_FTX_PKL_Direction__c = 'DEBIT',
      AXF_FTX_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_FTX_DAT_PurchaseDate__c = Date.today(),
      AXF_FTX_PKL_Status__c = 'PLANNED',
      AXF_FTX_PKL_PlanKind__c = 'PLANNED',
      AXF_FTX_NUM_Version__c = 0,
      AXF_FTX_EXI_ClientRequestId__c = 'axf103-legacy-null-state'
    );
    insert legacy;
    Assert.isNull(
      [
        SELECT AXF_FTX_PKL_ScheduleState__c
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE Id = :legacy.Id
      ]
      .AXF_FTX_PKL_ScheduleState__c,
      'Sem valor padrão: nulo significa que a linha não pertence a um cronograma'
    );

    // E o cronograma de verdade continua marcando as próprias ocorrências.
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      holder.Id
    };
    ALT_CLS_FinancialScheduleService.CreateResult created = ALT_CLS_FinancialScheduleService.createSchedule(
      request(
        holder.Id,
        'INSTALLMENT',
        12,
        1,
        Date.today(),
        'axf103-open-state'
      )
    );
    Assert.areEqual('CREATED', created.outcome, created.message);
    Assert.areEqual(
      created.occurrenceCount,
      [
        SELECT COUNT()
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE
          AXF_FTX_LKP_Schedule__c = :created.scheduleId
          AND AXF_FTX_PKL_ScheduleState__c = 'OPEN'
      ]
    );
  }

  @IsTest
  static void readOnlyEntryPointServesReadersWithoutGrantingTheWriteCommand() {
    // Declarativo: o acesso de classe não é granular por método, então o perfil somente-leitura
    // recebe a porta de LEITURA e não a classe que contém o comando de escrita.
    Id writePort = [
      SELECT Id
      FROM ApexClass
      WHERE Name = 'ALT_CLS_FinancialScheduleService'
    ]
    .Id;
    Id readPort = [
      SELECT Id
      FROM ApexClass
      WHERE Name = 'AXF_CLS_CTRL_FinancialSchedule'
    ]
    .Id;
    Set<Id> participanteClasses = new Set<Id>();
    for (SetupEntityAccess access : [
      SELECT SetupEntityId
      FROM SetupEntityAccess
      WHERE
        Parent.Name = 'AXF_PS_Participante'
        AND SetupEntityType = 'ApexClass'
    ]) {
      participanteClasses.add(access.SetupEntityId);
    }
    Assert.isTrue(
      participanteClasses.contains(readPort),
      'Participante lê pela porta somente-leitura'
    );
    Assert.isFalse(
      participanteClasses.contains(writePort),
      'Participante não recebe a classe do comando de escrita'
    );
    Assert.isFalse(
      participanteClasses.contains(
        [SELECT Id FROM ApexClass WHERE Name = 'ALT_CLS_ScheduleProjection'].Id
      ),
      'O motor de projeção não é exposto como porta pública'
    );

    // Comportamental: a porta de leitura devolve a projeção e respeita a paginação.
    Account holder = holder('AXF103 porta leitura');
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      holder.Id
    };
    ALT_CLS_FinancialScheduleService.CreateResult created = ALT_CLS_FinancialScheduleService.createSchedule(
      request(holder.Id, 'INSTALLMENT', 24, 1, Date.today(), 'axf103-read-port')
    );
    Assert.areEqual('CREATED', created.outcome, created.message);

    ALT_CLS_ScheduleProjection.ProjectionResult result = AXF_CLS_CTRL_FinancialSchedule.readProjection(
      created.scheduleId,
      Date.today(),
      5
    );
    Assert.areEqual('OK', result.outcome, result.message);
    Assert.areEqual(5, result.evaluatedCount);
    Assert.areEqual(5, result.throughSequence);
    Assert.isFalse(result.complete);
  }

  /** Linhas materializadas do cronograma, ordenadas pela sequência absoluta. */
  private static List<AXF_OBJ_FinancialTransaction__c> materializedRows(
    Id scheduleId
  ) {
    return [
      SELECT
        AXF_FTX_NUM_Sequence__c,
        AXF_FTX_NUM_Magnitude__c,
        AXF_FTX_NUM_CurrentBasis__c,
        AXF_FTX_NUM_PrincipalPortion__c,
        AXF_FTX_NUM_InterestPortion__c,
        AXF_FTX_NUM_FeePortion__c,
        AXF_FTX_NUM_ClosingBalance__c,
        AXF_FTX_CHK_RoundingResidual__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE AXF_FTX_LKP_Schedule__c = :scheduleId
      ORDER BY AXF_FTX_NUM_Sequence__c
    ];
  }

  /**
   * Contrato mínimo de um AXF_OBJ_Contract__c real: o comando valida existência, titular e moeda
   * contra o registro físico, então o teste precisa de um contrato de verdade.
   */
  private static AXF_OBJ_Contract__c contractFixture(
    Id holderId,
    String isoCode,
    String suffix
  ) {
    AXF_OBJ_Counterparty__c counterparty = new AXF_OBJ_Counterparty__c(
      Name = 'AXF103 Contraparte ' + suffix,
      AXF_CPTY_TXT_DisplayName__c = 'AXF103 Contraparte ' + suffix,
      AXF_CPTY_TXT_LegalName__c = 'AXF103 Contraparte LTDA ' + suffix,
      AXF_CPTY_TXT_Country__c = 'BR',
      AXF_CPTY_PKL_Kind__c = 'ORGANIZATION',
      AXF_CPTY_PKL_Status__c = 'ACTIVE',
      AXF_CPTY_EXI_CounterpartyKey__c = AXF_CLS_IdentityFraming.key(
        new List<Object>{ 'CPTY', 'AXF103 Contraparte LTDA', suffix, holderId }
      ),
      AXF_CPTY_NUM_Version__c = 1
    );
    insert counterparty;
    AXF_OBJ_CounterpartyEntityRelationship__c relationship = new AXF_OBJ_CounterpartyEntityRelationship__c(
      AXF_CER_LKP_Counterparty__c = counterparty.Id,
      AXF_CER_LKP_Account__c = holderId,
      AXF_CER_PKL_Role__c = 'SUPPLIER',
      AXF_CER_PKL_Status__c = 'ACTIVE',
      AXF_CER_TXT_EntitySpecificDisplay__c = 'Fornecedor AXF103 ' + suffix,
      AXF_CER_EXI_RelationshipKey__c = AXF_CLS_IdentityFraming.key(
        new List<Object>{ 'CER', counterparty.Id, holderId, 'SUPPLIER' }
      ),
      AXF_CER_NUM_Version__c = 1
    );
    insert relationship;
    AXF_OBJ_Contract__c contract = new AXF_OBJ_Contract__c(
      AXF_CTR_LKP_Account__c = holderId,
      AXF_CTR_LKP_Relationship__c = relationship.Id,
      AXF_CTR_LKP_Counterparty__c = counterparty.Id,
      AXF_CTR_TXT_ContractCode__c = 'CTR-AXF103-' + suffix,
      AXF_CTR_EXI_ContractKey__c = AXF_CLS_IdentityFraming.key(
        new List<Object>{ 'CONTRACT', holderId, suffix }
      ),
      AXF_CTR_TXT_Title__c = 'Contrato AXF-103 ' + suffix,
      AXF_CTR_PKL_Lifecycle__c = 'DRAFT',
      AXF_CTR_PKL_Type__c = 'EXPENSE',
      AXF_CTR_TXT_CurrencyIsoCode__c = isoCode,
      AXF_CTR_DAT_StartDate__c = Date.today(),
      AXF_CTR_NUM_Version__c = 1
    );
    insert contract;
    return contract;
  }

  @IsTest
  static void contractMustExistBelongToTheHolderAndShareTheCurrency() {
    Account holder = holder('AXF103 contrato válido');
    Account other = holder('AXF103 contrato alheio');
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      holder.Id,
      other.Id
    };
    AXF_OBJ_Contract__c valid = contractFixture(holder.Id, 'BRL', '0001');
    AXF_OBJ_Contract__c foreign = contractFixture(other.Id, 'BRL', '0002');
    AXF_OBJ_Contract__c foreignCurrency = contractFixture(
      holder.Id,
      'USD',
      '0003'
    );

    // Contrato do próprio titular e mesma moeda: aceito e persistido.
    ALT_CLS_FinancialScheduleService.CreateInput accepted = request(
      holder.Id,
      'INSTALLMENT',
      12,
      1,
      Date.today(),
      'axf103-contract-ok'
    );
    accepted.contractId = valid.Id;
    ALT_CLS_FinancialScheduleService.CreateResult created = ALT_CLS_FinancialScheduleService.createSchedule(
      accepted
    );
    Assert.areEqual('CREATED', created.outcome, created.message);
    Assert.areEqual(
      valid.Id,
      [
        SELECT AXF_FSC_LKP_Contract__c
        FROM AXF_OBJ_FinancialSchedule__c
        WHERE Id = :created.scheduleId
      ]
      .AXF_FSC_LKP_Contract__c
    );

    // Contrato de OUTRO titular: recusado.
    ALT_CLS_FinancialScheduleService.CreateInput crossed = request(
      holder.Id,
      'INSTALLMENT',
      12,
      1,
      Date.today(),
      'axf103-contract-foreign'
    );
    crossed.contractId = foreign.Id;
    ALT_CLS_FinancialScheduleService.CreateResult crossResult = ALT_CLS_FinancialScheduleService.createSchedule(
      crossed
    );
    Assert.areEqual('FORBIDDEN', crossResult.outcome, crossResult.message);

    // Moeda divergente da do contrato: recusada.
    ALT_CLS_FinancialScheduleService.CreateInput wrongCurrency = request(
      holder.Id,
      'INSTALLMENT',
      12,
      1,
      Date.today(),
      'axf103-contract-currency'
    );
    wrongCurrency.contractId = foreignCurrency.Id;
    ALT_CLS_FinancialScheduleService.CreateResult currencyResult = ALT_CLS_FinancialScheduleService.createSchedule(
      wrongCurrency
    );
    Assert.areEqual('INVALID', currencyResult.outcome, currencyResult.message);

    // Contrato inexistente: recusado, nunca gravado por omissão.
    ALT_CLS_FinancialScheduleService.CreateInput missing = request(
      holder.Id,
      'INSTALLMENT',
      12,
      1,
      Date.today(),
      'axf103-contract-missing'
    );
    missing.contractId = Id.valueOf(
      AXF_OBJ_Contract__c.SObjectType.getDescribe().getKeyPrefix() +
      '000000000000'
    );
    ALT_CLS_FinancialScheduleService.CreateResult missingResult = ALT_CLS_FinancialScheduleService.createSchedule(
      missing
    );
    Assert.areEqual('INVALID', missingResult.outcome, missingResult.message);

    Assert.areEqual(
      1,
      [SELECT COUNT() FROM AXF_OBJ_FinancialSchedule__c],
      'Só o cronograma com contrato válido foi gravado'
    );
  }

  @IsTest
  static void feeAndPortionMappingMatchesTheApprovedFormulaForEveryMethod() {
    Account holder = holder('AXF103 tarifas');
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      holder.Id
    };

    for (
      String method : new List<String>{
        'RECURRING',
        'INSTALLMENT',
        'PRICE',
        'SAC'
      }
    ) {
      ALT_CLS_FinancialScheduleService.CreateInput input = request(
        holder.Id,
        method,
        6,
        1,
        Date.today(),
        'axf103-fees-' + method
      );
      input.principal = 12000.00;
      input.periodRate = 0.01;
      input.fixedValue = 2000.00;
      input.recurringFee = 25.00;
      input.upfrontFee = 50.00;

      ALT_CLS_FinancialScheduleService.CreateResult created = ALT_CLS_FinancialScheduleService.createSchedule(
        input
      );
      Assert.areEqual(
        'CREATED',
        created.outcome,
        method + ': ' + created.message
      );

      ALT_CLS_AmortizationSchedule.ScheduleInput formula = new ALT_CLS_AmortizationSchedule.ScheduleInput();
      formula.modality = method;
      formula.principal = (method == 'RECURRING') ? null : 12000.00;
      formula.installments = 6;
      formula.periodRate = (method == 'PRICE' || method == 'SAC') ? 0.01 : null;
      formula.firstDueDate = Date.today();
      formula.fixedValue = (method == 'RECURRING') ? 2000.00 : null;
      formula.flatFeePerInstallment = 25.00;
      formula.upfrontFee = 50.00;
      ALT_CLS_AmortizationSchedule.ScheduleResult generated = ALT_CLS_AmortizationSchedule.generate(
        formula
      );
      Assert.areEqual('OK', generated.outcome, generated.message);

      // A MESMA fórmula sem as tarifas: é o que a ocorrência valeria se o mapeamento de tarifa
      // fosse removido sem quebrar a suíte. A diferença prova que a tarifa está no valor gravado.
      ALT_CLS_AmortizationSchedule.ScheduleInput bare = new ALT_CLS_AmortizationSchedule.ScheduleInput();
      bare.modality = formula.modality;
      bare.principal = formula.principal;
      bare.installments = formula.installments;
      bare.periodRate = formula.periodRate;
      bare.firstDueDate = formula.firstDueDate;
      bare.fixedValue = formula.fixedValue;
      ALT_CLS_AmortizationSchedule.ScheduleResult withoutFees = ALT_CLS_AmortizationSchedule.generate(
        bare
      );
      Assert.areEqual('OK', withoutFees.outcome, withoutFees.message);

      List<AXF_OBJ_FinancialTransaction__c> rows = materializedRows(
        created.scheduleId
      );
      Assert.areEqual(
        6,
        rows.size(),
        method + ': a janela cobre as seis parcelas'
      );
      for (Integer index = 0; index < rows.size(); index++) {
        AXF_OBJ_FinancialTransaction__c row = rows[index];
        String label = method + ' na sequência ' + String.valueOf(index + 1);
        ALT_CLS_AmortizationSchedule.Occurrence expected = generated.occurrences[
          index
        ];
        Assert.areEqual(
          expected.payment,
          row.AXF_FTX_NUM_Magnitude__c,
          label + ': valor da fórmula aprovada'
        );
        Assert.areEqual(
          expected.payment,
          row.AXF_FTX_NUM_CurrentBasis__c,
          label + ': base corrente'
        );
        Assert.areEqual(
          expected.principalPortion,
          row.AXF_FTX_NUM_PrincipalPortion__c,
          label + ': principal persistido'
        );
        Assert.areEqual(
          expected.interestPortion,
          row.AXF_FTX_NUM_InterestPortion__c,
          label + ': juros persistidos'
        );
        Assert.areEqual(
          expected.feePortion,
          row.AXF_FTX_NUM_FeePortion__c,
          label + ': tarifa persistida'
        );
        Assert.areEqual(
          expected.closingBalance,
          row.AXF_FTX_NUM_ClosingBalance__c,
          label + ': saldo persistido'
        );
        Assert.areEqual(
          expected.roundingResidualApplied,
          row.AXF_FTX_CHK_RoundingResidual__c,
          label + ': resíduo de arredondamento persistido'
        );
        Assert.areEqual(
          withoutFees.occurrences[index].payment + expected.feePortion,
          row.AXF_FTX_NUM_Magnitude__c,
          label + ': a tarifa está incluída no valor gravado'
        );
      }
      Assert.areEqual(
        25.00,
        rows[1].AXF_FTX_NUM_FeePortion__c,
        method + ': tarifa recorrente na segunda parcela'
      );
      Assert.areEqual(
        75.00,
        rows[0].AXF_FTX_NUM_FeePortion__c,
        method + ': tarifa recorrente MAIS tarifa inicial na primeira parcela'
      );
    }
  }

  @IsTest
  static void realWindowLimitAcceptsFiftyAndRejectsFiftyOneWithoutPartialWrite() {
    Account holder = holder('AXF103 limite real');
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      holder.Id
    };
    Date atLimitDue = Date.today().addMonths(-38);
    Date overLimitDue = Date.today().addMonths(-39);
    // Autoconferência do fixture: a fronteira real é 50.
    Assert.areEqual(50, expectedWindowCount(1, 60, atLimitDue));
    Assert.areEqual(51, expectedWindowCount(1, 60, overLimitDue));

    ALT_CLS_FinancialScheduleService.CreateInput atLimit = request(
      holder.Id,
      'INSTALLMENT',
      60,
      1,
      atLimitDue,
      'axf103-window-at-limit'
    );
    ALT_CLS_FinancialScheduleService.CreateResult accepted = ALT_CLS_FinancialScheduleService.createSchedule(
      atLimit
    );
    Assert.areEqual('CREATED', accepted.outcome, accepted.message);
    Assert.areEqual(
      50,
      accepted.occurrenceCount,
      'A fronteira real de 50 ocorrências é aceita'
    );

    ALT_CLS_FinancialScheduleService.CreateInput overLimit = request(
      holder.Id,
      'INSTALLMENT',
      60,
      1,
      overLimitDue,
      'axf103-window-over-limit'
    );
    ALT_CLS_FinancialScheduleService.CreateResult rejected = ALT_CLS_FinancialScheduleService.createSchedule(
      overLimit
    );
    Assert.areEqual('TOO_LARGE', rejected.outcome, rejected.message);
    Assert.isNull(
      rejected.scheduleId,
      'Nada foi escrito para a tentativa recusada'
    );
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM AXF_OBJ_FinancialSchedule__c],
      'Nenhum cronograma parcial ficou para trás'
    );
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM AXF_OBJ_ScheduleChange__c],
      'Só o recibo da criação aceita existe'
    );
    Assert.areEqual(
      50,
      [SELECT COUNT() FROM AXF_OBJ_FinancialTransaction__c],
      'Nenhuma ocorrência parcial da tentativa recusada'
    );
  }

  @IsTest
  static void scheduleKeyIsStableUnderAFormulaAmendment() {
    Account holder = holder('AXF103 emenda');
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      holder.Id
    };
    ALT_CLS_FinancialScheduleService.CreateInput original = request(
      holder.Id,
      'INSTALLMENT',
      12,
      1,
      Date.today(),
      'axf103-amendment'
    );
    ALT_CLS_FinancialScheduleService.CreateInput amended = request(
      holder.Id,
      'INSTALLMENT',
      12,
      1,
      Date.today(),
      'axf103-amendment'
    );
    amended.principal = 480000.00;
    amended.periodRate = 0.02;
    amended.recurringFee = 10.00;
    amended.upfrontFee = 99.00;

    Assert.areEqual(
      ALT_CLS_FinancialScheduleService.previewScheduleKey(original),
      ALT_CLS_FinancialScheduleService.previewScheduleKey(amended),
      'Principal, taxa e tarifas não participam da identidade do cronograma'
    );
    Assert.areNotEqual(
      ALT_CLS_FinancialScheduleService.previewPayloadHash(original),
      ALT_CLS_FinancialScheduleService.previewPayloadHash(amended),
      'A emenda de fórmula muda o payload canônico'
    );
    Assert.areNotEqual(
      ALT_CLS_FinancialScheduleService.previewOperationKey(original),
      ALT_CLS_FinancialScheduleService.previewOperationKey(amended),
      'A identidade de operação é delimitada pelo payload'
    );

    Assert.areEqual(
      'CREATED',
      ALT_CLS_FinancialScheduleService.createSchedule(original).outcome
    );
    ALT_CLS_FinancialScheduleService.CreateResult conflicted = ALT_CLS_FinancialScheduleService.createSchedule(
      amended
    );
    Assert.areEqual('CONFLICT', conflicted.outcome, conflicted.message);
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM AXF_OBJ_FinancialSchedule__c],
      'A emenda não cria um segundo cronograma sob a mesma identidade'
    );
  }

  @IsTest
  static void preInsertedRootWithoutAReceiptIsConflictNeverCreated() {
    Account holder = holder('AXF103 raiz pré-inserida');
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      holder.Id
    };
    ALT_CLS_FinancialScheduleService.CreateInput input = request(
      holder.Id,
      'INSTALLMENT',
      12,
      1,
      Date.today(),
      'axf103-pre-root'
    );
    String scheduleKey = ALT_CLS_FinancialScheduleService.previewScheduleKey(
      input
    );
    insert new AXF_OBJ_FinancialSchedule__c(
      AXF_FSC_EXI_ScheduleKey__c = scheduleKey,
      AXF_FSC_LKP_Account__c = holder.Id,
      AXF_FSC_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_FSC_PKL_Direction__c = 'DEBIT',
      AXF_FSC_PKL_State__c = 'DRAFT',
      AXF_FSC_NUM_TrackingStartSequence__c = 1
    );

    ALT_CLS_FinancialScheduleService.CreateResult result = ALT_CLS_FinancialScheduleService.createSchedule(
      input
    );

    Assert.areEqual('CONFLICT', result.outcome, result.message);
    Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_ScheduleDefinition__c]);
    Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_ScheduleChange__c]);
    Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_FinancialTransaction__c]);
  }

  @IsTest
  static void preInsertedEquivalentReceiptReplaysTheOriginalAuthorizedResult() {
    Account holder = holder('AXF103 recibo pré-inserido');
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      holder.Id
    };
    ALT_CLS_FinancialScheduleService.CreateInput input = request(
      holder.Id,
      'INSTALLMENT',
      12,
      1,
      Date.today(),
      'axf103-pre-receipt'
    );
    String scheduleKey = ALT_CLS_FinancialScheduleService.previewScheduleKey(
      input
    );
    String payloadHash = ALT_CLS_FinancialScheduleService.previewPayloadHash(
      input
    );
    String operationKey = ALT_CLS_FinancialScheduleService.previewOperationKey(
      input
    );

    AXF_OBJ_FinancialSchedule__c root = new AXF_OBJ_FinancialSchedule__c(
      AXF_FSC_EXI_ScheduleKey__c = scheduleKey,
      AXF_FSC_LKP_Account__c = holder.Id,
      AXF_FSC_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_FSC_PKL_Direction__c = 'DEBIT',
      AXF_FSC_PKL_State__c = 'DRAFT',
      AXF_FSC_NUM_TrackingStartSequence__c = 1
    );
    insert root;
    ALT_CLS_FinancialScheduleService.CreateResult original = new ALT_CLS_FinancialScheduleService.CreateResult();
    original.outcome = 'CREATED';
    original.scheduleId = root.Id;
    original.scheduleKey = scheduleKey;
    original.occurrenceCount = 7;
    // Evidência já confirmada: só o serviço grava recibo, então o teste usa a MESMA capacidade
    // que o comando usa (a guarda do handler é sobre o contexto, não sobre o objeto).
    ALT_CLS_FinancialScheduleService.writing = true;
    insert new AXF_OBJ_ScheduleChange__c(
      AXF_SCH_EXI_OperationKey__c = operationKey,
      AXF_SCH_TXT_PayloadHash__c = payloadHash,
      AXF_SCH_LKP_Schedule__c = root.Id,
      AXF_SCH_PKL_Operation__c = 'CREATE',
      AXF_SCH_NUM_Revision__c = 1,
      AXF_SCH_PKL_Scope__c = 'FROM_SEQUENCE',
      AXF_SCH_NUM_FromSequence__c = 1,
      AXF_SCH_BOL_IncludeManualOverrides__c = false,
      AXF_SCH_TAL_ResultJson__c = JSON.serialize(original),
      AXF_SCH_DT_CommittedAt__c = System.now(),
      AXF_SCH_LKP_Actor__c = UserInfo.getUserId()
    );
    ALT_CLS_FinancialScheduleService.writing = false;

    ALT_CLS_FinancialScheduleService.CreateResult replay = ALT_CLS_FinancialScheduleService.createSchedule(
      input
    );

    Assert.areEqual('REPLAY', replay.outcome, replay.message);
    Assert.isTrue(replay.replay);
    Assert.areEqual(root.Id, replay.scheduleId);
    Assert.areEqual(
      7,
      replay.occurrenceCount,
      'O resultado autorizado original é devolvido, e não um novo cálculo'
    );
    Assert.areEqual(1, [SELECT COUNT() FROM AXF_OBJ_FinancialSchedule__c]);
    Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_ScheduleDefinition__c]);
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM AXF_OBJ_FinancialTransaction__c],
      'O replay não grava ocorrência alguma'
    );
  }

  @IsTest
  static void malformedAuthorizedResultIsAConflictedReplayNotAnException() {
    Account holder = holder('AXF103 resultado ilegível');
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      holder.Id
    };
    ALT_CLS_FinancialScheduleService.CreateInput input = request(
      holder.Id,
      'INSTALLMENT',
      12,
      1,
      Date.today(),
      'axf103-malformed-result'
    );
    String scheduleKey = ALT_CLS_FinancialScheduleService.previewScheduleKey(
      input
    );
    String payloadHash = ALT_CLS_FinancialScheduleService.previewPayloadHash(
      input
    );
    String operationKey = ALT_CLS_FinancialScheduleService.previewOperationKey(
      input
    );

    AXF_OBJ_FinancialSchedule__c root = new AXF_OBJ_FinancialSchedule__c(
      AXF_FSC_EXI_ScheduleKey__c = scheduleKey,
      AXF_FSC_LKP_Account__c = holder.Id,
      AXF_FSC_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_FSC_PKL_Direction__c = 'DEBIT',
      AXF_FSC_PKL_State__c = 'DRAFT',
      AXF_FSC_NUM_TrackingStartSequence__c = 1
    );
    insert root;
    ALT_CLS_FinancialScheduleService.writing = true;
    insert new AXF_OBJ_ScheduleChange__c(
      AXF_SCH_EXI_OperationKey__c = operationKey,
      AXF_SCH_TXT_PayloadHash__c = payloadHash,
      AXF_SCH_LKP_Schedule__c = root.Id,
      AXF_SCH_PKL_Operation__c = 'CREATE',
      AXF_SCH_NUM_Revision__c = 1,
      AXF_SCH_PKL_Scope__c = 'FROM_SEQUENCE',
      AXF_SCH_NUM_FromSequence__c = 1,
      AXF_SCH_BOL_IncludeManualOverrides__c = false,
      AXF_SCH_TAL_ResultJson__c = '{"occurrenceCount": [',
      AXF_SCH_DT_CommittedAt__c = System.now(),
      AXF_SCH_LKP_Actor__c = UserInfo.getUserId()
    );
    ALT_CLS_FinancialScheduleService.writing = false;

    ALT_CLS_FinancialScheduleService.CreateResult result = ALT_CLS_FinancialScheduleService.createSchedule(
      input
    );

    // Nem exceção de desserialização, nem replay inventado: desfecho controlado.
    Assert.areEqual('CONFLICT', result.outcome, result.message);
    Assert.isFalse(result.replay);
    Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_FinancialTransaction__c]);
  }

  @IsTest
  static void forgedReceiptCannotBeInsertedByDirectDml() {
    Account holder = holder('AXF103 recibo forjado');
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      holder.Id
    };
    ALT_CLS_FinancialScheduleService.CreateResult created = ALT_CLS_FinancialScheduleService.createSchedule(
      request(
        holder.Id,
        'INSTALLMENT',
        12,
        1,
        Date.today(),
        'axf103-forged-receipt'
      )
    );
    Assert.areEqual('CREATED', created.outcome, created.message);

    // Recibo completo e sintaticamente válido, com Operation, Scope e ResultJson inventados:
    // criar em AXF_OBJ_ScheduleChange__c é concedido ao Gestor e à entrada financeira, e sem a
    // guarda de contexto o recibo deixaria de ser prova da operação.
    Database.SaveResult forged = Database.insert(
      new AXF_OBJ_ScheduleChange__c(
        AXF_SCH_EXI_OperationKey__c = 'axf103-forged-operation',
        AXF_SCH_TXT_PayloadHash__c = 'forgedpayload'.rightPad(64, '0'),
        AXF_SCH_LKP_Schedule__c = created.scheduleId,
        AXF_SCH_PKL_Operation__c = 'TERMINATE',
        AXF_SCH_NUM_Revision__c = 2,
        AXF_SCH_PKL_Scope__c = 'ALL_TRACKED',
        AXF_SCH_NUM_FromSequence__c = 1,
        AXF_SCH_BOL_IncludeManualOverrides__c = true,
        AXF_SCH_TAL_ResultJson__c = '{"outcome":"CREATED","occurrenceCount":0}',
        AXF_SCH_TAL_Reason__c = 'recibo forjado',
        AXF_SCH_DT_CommittedAt__c = System.now(),
        AXF_SCH_LKP_Actor__c = UserInfo.getUserId()
      ),
      false
    );

    Assert.isFalse(
      forged.isSuccess(),
      'O recibo é evidência do serviço autorizado, não um registro de usuário'
    );
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM AXF_OBJ_ScheduleChange__c],
      'Só o recibo autorizado da criação existe'
    );
  }

  // --- AXF-155: periodicidade em dias, origem, EDIT e TERMINATE ---------------

  private static AXF_OBJ_BankAccount__c wallet(Id holderId) {
    AXF_OBJ_BankAccount__c result = new AXF_OBJ_BankAccount__c(
      AXF_BA_LKP_Account__c = holderId,
      AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_BA_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BA_TXT_Type__c = 'WALLET',
      AXF_BA_NUM_Version__c = 1
    );
    insert result;
    return result;
  }

  private static ALT_CLS_FinancialScheduleService.CreateInput recurrence(
    Id accountId,
    Date firstDueDate,
    Integer periodDays,
    Integer periodMonths,
    Id bankAccountId,
    String streamKey
  ) {
    ALT_CLS_FinancialScheduleService.CreateInput value = new ALT_CLS_FinancialScheduleService.CreateInput();
    value.accountId = accountId;
    value.direction = 'DEBIT';
    value.currencyIsoCode = 'BRL';
    value.method = 'ESTIMATED';
    value.firstSequence = 1;
    value.firstDueDate = firstDueDate;
    value.periodDays = periodDays;
    value.periodMonths = periodMonths;
    value.horizonMonths = (periodDays == 7) ? 11 : 12;
    value.referenceAmount = 300.00;
    value.bankAccountId = bankAccountId;
    value.description = 'Mão de obra';
    value.generationEnabled = true;
    value.streamKey = streamKey;
    return value;
  }

  private static List<AXF_OBJ_FinancialTransaction__c> occurrencesOf(
    Id scheduleId
  ) {
    return [
      SELECT
        Id,
        AXF_FTX_NUM_Sequence__c,
        AXF_FTX_DAT_DueDate__c,
        AXF_FTX_NUM_CurrentBasis__c,
        AXF_FTX_NUM_Magnitude__c,
        AXF_FTX_PKL_ScheduleState__c,
        AXF_FTX_PKL_Status__c,
        AXF_FTX_LKP_BankAccount__c,
        AXF_FTX_LKP_CreditCard__c,
        AXF_FTX_TXT_Description__c,
        AXF_FTX_NUM_Version__c,
        AXF_FTX_LKP_ScheduleReference__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE AXF_FTX_LKP_Schedule__c = :scheduleId
      ORDER BY AXF_FTX_NUM_Sequence__c
    ];
  }

  private static ALT_CLS_FinancialScheduleService.ChangeInput change(
    Id scheduleId,
    String key,
    Long expectedVersion
  ) {
    ALT_CLS_FinancialScheduleService.ChangeInput value = new ALT_CLS_FinancialScheduleService.ChangeInput();
    value.scheduleId = scheduleId;
    value.operationKey = key;
    value.expectedVersion = expectedVersion;
    return value;
  }

  @IsTest
  static void weeklyRecurrenceSpacesSevenDaysAndAppliesTheOrigin() {
    Account owner = holder('AXF155 semanal');
    AXF_OBJ_BankAccount__c cash = wallet(owner.Id);
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      owner.Id
    };
    Date first = Date.today().addDays(9);

    Test.startTest();
    ALT_CLS_FinancialScheduleService.CreateResult created = ALT_CLS_FinancialScheduleService.createSchedule(
      recurrence(owner.Id, first, 7, null, cash.Id, 'axf155-weekly')
    );
    Test.stopTest();

    Assert.areEqual('CREATED', created.outcome, created.message);
    List<AXF_OBJ_FinancialTransaction__c> rows = occurrencesOf(
      created.scheduleId
    );
    Assert.isTrue(rows.size() > 1 && rows.size() <= 50, 'janela ≤ 50');
    for (Integer i = 0; i < rows.size(); i++) {
      AXF_OBJ_FinancialTransaction__c row = rows[i];
      Assert.areEqual(first.addDays(7 * i), row.AXF_FTX_DAT_DueDate__c);
      Assert.areEqual(cash.Id, row.AXF_FTX_LKP_BankAccount__c);
      Assert.isNull(row.AXF_FTX_LKP_CreditCard__c);
      Assert.areEqual('Mão de obra', row.AXF_FTX_TXT_Description__c);
      Assert.areEqual(300.00, row.AXF_FTX_NUM_CurrentBasis__c);
    }
    // Os campos novos de periodicidade não têm FLS para o usuário do deploy de verificação: a
    // periodicidade é provada pelas datas e pela entrada canônica.
    AXF_OBJ_ScheduleDefinition__c definition = [
      SELECT AXF_SDF_TAL_InputCanonicalJson__c
      FROM AXF_OBJ_ScheduleDefinition__c
      WHERE AXF_SDF_LKP_Schedule__c = :created.scheduleId
    ];
    Map<String, Object> canonical = ALT_CLS_FinancialScheduleService.canonicalInputOf(
      definition
    );
    Assert.areEqual(cash.Id, canonical.get('bankAccountId'));
    Assert.areEqual('Mão de obra', canonical.get('description'));
    AXF_OBJ_FinancialSchedule__c root = [
      SELECT AXF_FSC_BOL_GenerationEnabled__c, AXF_FSC_NUM_HorizonMonths__c
      FROM AXF_OBJ_FinancialSchedule__c
      WHERE Id = :created.scheduleId
    ];
    Assert.isTrue(root.AXF_FSC_BOL_GenerationEnabled__c);
    Assert.areEqual(11, root.AXF_FSC_NUM_HorizonMonths__c.intValue());

    // A projeção lê o mesmo calendário em dias.
    ALT_CLS_ScheduleProjection.authorizedOverride = new Set<Id>{ owner.Id };
    ALT_CLS_ScheduleProjection.ProjectionInput input = new ALT_CLS_ScheduleProjection.ProjectionInput();
    input.scheduleId = created.scheduleId;
    input.asOfDate = Date.today();
    ALT_CLS_ScheduleProjection.ProjectionResult projection = ALT_CLS_ScheduleProjection.project(
      input
    );
    Assert.areEqual('OK', projection.outcome, projection.message);
    Assert.areEqual(first.addDays(7), projection.lines[1].nominalDueDate);
  }

  @IsTest
  static void biweeklyRecurrenceIsIdempotentAndKeepsMonthlyKeysStable() {
    Account owner = holder('AXF155 quinzenal');
    AXF_OBJ_BankAccount__c cash = wallet(owner.Id);
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      owner.Id
    };
    Date first = Date.today().addDays(3);
    ALT_CLS_FinancialScheduleService.CreateInput input = recurrence(
      owner.Id,
      first,
      14,
      null,
      cash.Id,
      'axf155-biweekly'
    );

    ALT_CLS_FinancialScheduleService.CreateResult created = ALT_CLS_FinancialScheduleService.createSchedule(
      input
    );
    ALT_CLS_FinancialScheduleService.CreateResult again = ALT_CLS_FinancialScheduleService.createSchedule(
      input
    );

    Assert.areEqual('CREATED', created.outcome, created.message);
    Assert.areEqual('REPLAY', again.outcome, again.message);
    Assert.areEqual(created.scheduleId, again.scheduleId);
    List<AXF_OBJ_FinancialTransaction__c> rows = occurrencesOf(
      created.scheduleId
    );
    Assert.areEqual(first.addDays(14), rows[1].AXF_FTX_DAT_DueDate__c);

    // Um segundo fluxo do mesmo titular com o mesmo calendário não colide.
    ALT_CLS_FinancialScheduleService.CreateInput other = recurrence(
      owner.Id,
      first,
      14,
      null,
      cash.Id,
      'axf155-biweekly-2'
    );
    other.referenceAmount = 120.00;
    Assert.areEqual(
      'CREATED',
      ALT_CLS_FinancialScheduleService.createSchedule(other).outcome
    );

    // A identidade de um cronograma mensal sem os campos novos continua a do framing legado.
    ALT_CLS_FinancialScheduleService.CreateInput monthly = request(
      owner.Id,
      'INSTALLMENT',
      12,
      1,
      Date.newInstance(2027, 1, 10),
      'axf155-legacy'
    );
    Assert.areEqual(
      AXF_CLS_IdentityFraming.key(
        new List<Object>{
          'axf103-sch-v1',
          owner.Id,
          null,
          'DEBIT',
          'BRL',
          'INSTALLMENT',
          1,
          Date.newInstance(2027, 1, 10),
          1,
          10,
          12,
          1,
          'axf155-legacy'
        }
      ),
      ALT_CLS_FinancialScheduleService.previewScheduleKey(monthly)
    );
  }

  @IsTest
  static void invalidPeriodsAndOriginsAreRejectedBeforeWriting() {
    Account owner = holder('AXF155 inválidos');
    Account stranger = holder('AXF155 alheio');
    AXF_OBJ_BankAccount__c cash = wallet(owner.Id);
    AXF_OBJ_BankAccount__c foreign = wallet(stranger.Id);
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      owner.Id
    };
    Date first = Date.today().addDays(5);

    List<ALT_CLS_FinancialScheduleService.CreateInput> invalid = new List<ALT_CLS_FinancialScheduleService.CreateInput>{
      recurrence(owner.Id, first, 10, null, cash.Id, 'axf155-ten'),
      recurrence(owner.Id, first, 7, 1, cash.Id, 'axf155-both'),
      recurrence(owner.Id, first, 7, null, foreign.Id, 'axf155-foreign')
    };
    ALT_CLS_FinancialScheduleService.CreateInput twoOrigins = recurrence(
      owner.Id,
      first,
      7,
      null,
      cash.Id,
      'axf155-two'
    );
    twoOrigins.creditCardId = cash.Id;
    invalid.add(twoOrigins);
    ALT_CLS_FinancialScheduleService.CreateInput longText = recurrence(
      owner.Id,
      first,
      14,
      null,
      cash.Id,
      'axf155-long'
    );
    longText.description = 'x'.repeat(256);
    invalid.add(longText);
    for (ALT_CLS_FinancialScheduleService.CreateInput input : invalid) {
      Assert.areEqual(
        'INVALID',
        ALT_CLS_FinancialScheduleService.createSchedule(input).outcome
      );
    }
    Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_FinancialSchedule__c]);
  }

  @IsTest
  static void definitionRequiresExactlyOneValidPeriod() {
    Assert.isNull(AXF_CLS_SDFTriggerHandler.periodError(1, null));
    Assert.isNull(AXF_CLS_SDFTriggerHandler.periodError(120, null));
    Assert.isNull(AXF_CLS_SDFTriggerHandler.periodError(null, 7));
    Assert.isNull(AXF_CLS_SDFTriggerHandler.periodError(null, 14));
    Assert.isNotNull(AXF_CLS_SDFTriggerHandler.periodError(null, null));
    Assert.isNotNull(AXF_CLS_SDFTriggerHandler.periodError(1, 7));
    Assert.isNotNull(AXF_CLS_SDFTriggerHandler.periodError(null, 10));
    Assert.isNotNull(AXF_CLS_SDFTriggerHandler.periodError(null, 7.5));
    Assert.isNotNull(AXF_CLS_SDFTriggerHandler.periodError(0, null));
    Assert.isNotNull(AXF_CLS_SDFTriggerHandler.periodError(121, null));

    Account owner = holder('AXF155 definição');
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      owner.Id
    };
    ALT_CLS_FinancialScheduleService.CreateResult created = ALT_CLS_FinancialScheduleService.createSchedule(
      recurrence(owner.Id, Date.today().addDays(2), null, 1, null, 'axf155-def')
    );
    Assert.areEqual('CREATED', created.outcome, created.message);
    Database.SaveResult withoutPeriod = Database.insert(
      new AXF_OBJ_ScheduleDefinition__c(
        AXF_SDF_EXI_DefinitionKey__c = 'axf155-def-none',
        AXF_SDF_LKP_Schedule__c = created.scheduleId,
        AXF_SDF_NUM_Revision__c = 2,
        AXF_SDF_NUM_EffectiveSequence__c = 5,
        AXF_SDF_PKL_Method__c = 'ESTIMATED',
        AXF_SDF_NUM_FirstSequence__c = 1,
        AXF_SDF_DAT_FirstDueDate__c = Date.today(),
        AXF_SDF_NUM_AnchorDay__c = 10
      ),
      false
    );
    Assert.isFalse(withoutPeriod.isSuccess(), 'Sem periodicidade é recusado');

    // Evidência imutável: definição e recibo não são editados nem excluídos, e um recibo de
    // alteração registra a sequência a partir da qual vale.
    AXF_OBJ_ScheduleDefinition__c definition = [
      SELECT Id
      FROM AXF_OBJ_ScheduleDefinition__c
      WHERE AXF_SDF_LKP_Schedule__c = :created.scheduleId
    ];
    Assert.isFalse(
      Database.update(
          new AXF_OBJ_ScheduleDefinition__c(
            Id = definition.Id,
            AXF_SDF_NUM_AnchorDay__c = 3
          ),
          false
        )
        .isSuccess()
    );
    Assert.isFalse(Database.delete(definition.Id, false).isSuccess());
    AXF_OBJ_ScheduleChange__c receipt = [
      SELECT Id
      FROM AXF_OBJ_ScheduleChange__c
      WHERE AXF_SCH_LKP_Schedule__c = :created.scheduleId
    ];
    Assert.isFalse(
      Database.update(
          new AXF_OBJ_ScheduleChange__c(
            Id = receipt.Id,
            AXF_SCH_TAL_Reason__c = 'reescrito'
          ),
          false
        )
        .isSuccess()
    );
    Assert.isFalse(Database.delete(receipt.Id, false).isSuccess());
    ALT_CLS_FinancialScheduleService.writing = true;
    Database.SaveResult unsequenced = Database.insert(
      new AXF_OBJ_ScheduleChange__c(
        AXF_SCH_EXI_OperationKey__c = 'axf155-edit-unsequenced',
        AXF_SCH_TXT_PayloadHash__c = 'hash'.rightPad(64, '0'),
        AXF_SCH_LKP_Schedule__c = created.scheduleId,
        AXF_SCH_PKL_Operation__c = 'EDIT',
        AXF_SCH_NUM_Revision__c = 2,
        AXF_SCH_PKL_Scope__c = 'FROM_SEQUENCE'
      ),
      false
    );
    ALT_CLS_FinancialScheduleService.writing = false;
    Assert.isFalse(unsequenced.isSuccess(), 'EDIT sem sequência inicial');
  }

  @IsTest
  static void replenishmentAppliesTheOriginOfTheDefinition() {
    Account owner = holder('AXF155 reposição');
    AXF_OBJ_BankAccount__c cash = wallet(owner.Id);
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      owner.Id
    };
    ALT_CLS_ScheduleProjection.authorizedOverride = new Set<Id>{ owner.Id };
    ALT_CLS_FinancialScheduleService.CreateResult created = ALT_CLS_FinancialScheduleService.createSchedule(
      recurrence(
        owner.Id,
        Date.today().addDays(1),
        14,
        null,
        cash.Id,
        'axf155-replenish'
      )
    );
    Assert.areEqual('CREATED', created.outcome, created.message);
    List<AXF_OBJ_FinancialTransaction__c> rows = occurrencesOf(
      created.scheduleId
    );
    AXF_OBJ_FinancialTransaction__c last = rows[rows.size() - 1];
    delete last;

    Test.startTest();
    ALT_CLS_FinancialScheduleService.ReplenishmentRequest request = new ALT_CLS_FinancialScheduleService.ReplenishmentRequest();
    request.scheduleId = created.scheduleId;
    ALT_CLS_FinancialScheduleService.ReplenishmentResult result = ALT_CLS_FinancialScheduleService.replenishSchedule(
      request
    );
    Test.stopTest();

    Assert.areEqual('GENERATED', result.outcome, result.message);
    AXF_OBJ_FinancialTransaction__c regenerated = [
      SELECT
        AXF_FTX_LKP_BankAccount__c,
        AXF_FTX_TXT_Description__c,
        AXF_FTX_DAT_DueDate__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE
        AXF_FTX_LKP_Schedule__c = :created.scheduleId
        AND AXF_FTX_NUM_Sequence__c = :last.AXF_FTX_NUM_Sequence__c
    ];
    Assert.areEqual(cash.Id, regenerated.AXF_FTX_LKP_BankAccount__c);
    Assert.areEqual('Mão de obra', regenerated.AXF_FTX_TXT_Description__c);
    Assert.areEqual(
      last.AXF_FTX_DAT_DueDate__c,
      regenerated.AXF_FTX_DAT_DueDate__c
    );
  }

  @IsTest
  static void editAmountChangesOnlyFutureUnrealizedOccurrences() {
    System.runAs(actor()) {
      Account owner = holder('AXF155 editar');
      ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
        owner.Id
      };
      ALT_CLS_ScheduleProjection.authorizedOverride = new Set<Id>{ owner.Id };
      ALT_CLS_FinancialScheduleService.CreateResult created = ALT_CLS_FinancialScheduleService.createSchedule(
        recurrence(owner.Id, Date.today(), null, 1, null, 'axf155-edit')
      );
      Assert.areEqual('CREATED', created.outcome, created.message);
      List<AXF_OBJ_FinancialTransaction__c> rows = occurrencesOf(
        created.scheduleId
      );
      Assert.isTrue(rows.size() > 2);

      // A primeira ocorrência é conciliada (alocação AXF-25): fica protegida.
      ALT_CLS_RealizationService.Input realization = new ALT_CLS_RealizationService.Input();
      realization.targetId = rows[0].Id;
      realization.sourceKind = 'CASH';
      realization.amount = 300;
      realization.targetVersion = rows[0].AXF_FTX_NUM_Version__c;
      realization.operationKey = 'axf155-realize-1';
      realization.recognitionDate = Date.today();
      new ALT_CLS_RealizationService().apply(realization);

      Test.startTest();
      ALT_CLS_FinancialScheduleService.ChangeInput edit = change(
        created.scheduleId,
        'axf155-edit-350',
        0
      );
      edit.amount = 350;
      ALT_CLS_FinancialScheduleService.ChangeResult changed = ALT_CLS_FinancialScheduleService.editAmount(
        edit
      );
      ALT_CLS_FinancialScheduleService.ChangeResult replayed = ALT_CLS_FinancialScheduleService.editAmount(
        edit
      );
      ALT_CLS_FinancialScheduleService.ChangeInput stale = change(
        created.scheduleId,
        'axf155-edit-stale',
        0
      );
      stale.amount = 400;
      ALT_CLS_FinancialScheduleService.ChangeResult conflict = ALT_CLS_FinancialScheduleService.editAmount(
        stale
      );
      Test.stopTest();

      Assert.areEqual('UPDATED', changed.outcome, changed.message);
      Assert.areEqual(2, changed.fromSequence);
      Assert.areEqual(rows.size() - 1, changed.updatedCount);
      Assert.areEqual(1, changed.version);
      Assert.areEqual(1, changed.protectedCount, 'a conciliada de hoje');
      Assert.areEqual('REPLAY', replayed.outcome, replayed.message);
      Assert.isTrue(replayed.replay);
      Assert.areEqual(changed.updatedCount, replayed.updatedCount);
      Assert.areEqual('CONFLICT', conflict.outcome, conflict.message);

      List<AXF_OBJ_FinancialTransaction__c> after = occurrencesOf(
        created.scheduleId
      );
      Assert.areEqual(300.00, after[0].AXF_FTX_NUM_CurrentBasis__c);
      Assert.areEqual(300.00, after[0].AXF_FTX_NUM_Magnitude__c);
      for (Integer i = 1; i < after.size(); i++) {
        Assert.areEqual(350.00, after[i].AXF_FTX_NUM_CurrentBasis__c);
        Assert.areEqual(350.00, after[i].AXF_FTX_NUM_Magnitude__c);
        Assert.areEqual(
          changed.referenceId,
          after[i].AXF_FTX_LKP_ScheduleReference__c
        );
      }
      AXF_OBJ_FinancialSchedule__c root = [
        SELECT AXF_FSC_NUM_Version__c, AXF_FSC_LKP_ActiveReference__c
        FROM AXF_OBJ_FinancialSchedule__c
        WHERE Id = :created.scheduleId
      ];
      Assert.areEqual(1, root.AXF_FSC_NUM_Version__c.intValue());
      Assert.areEqual(changed.referenceId, root.AXF_FSC_LKP_ActiveReference__c);
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM AXF_OBJ_ScheduleChange__c
          WHERE
            AXF_SCH_LKP_Schedule__c = :created.scheduleId
            AND AXF_SCH_PKL_Operation__c = 'EDIT'
        ]
      );

      ALT_CLS_ScheduleProjection.ProjectionInput input = new ALT_CLS_ScheduleProjection.ProjectionInput();
      input.scheduleId = created.scheduleId;
      input.asOfDate = Date.today();
      ALT_CLS_ScheduleProjection.ProjectionResult projection = ALT_CLS_ScheduleProjection.project(
        input
      );
      Assert.areEqual('OK', projection.outcome, projection.message);
      for (ALT_CLS_ScheduleProjection.OccurrenceLine line : projection.lines) {
        if (line.sequence >= 2) {
          Assert.areEqual(350.00, line.amount, 'sequência ' + line.sequence);
        }
      }
    }
  }

  @IsTest
  static void terminateCancelsOnlyEligibleFutureOccurrences() {
    Account owner = holder('AXF155 encerrar');
    AXF_OBJ_BankAccount__c cash = wallet(owner.Id);
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      owner.Id
    };
    ALT_CLS_FinancialScheduleService.CreateResult created = ALT_CLS_FinancialScheduleService.createSchedule(
      recurrence(owner.Id, Date.today(), null, 1, cash.Id, 'axf155-end')
    );
    Assert.areEqual('CREATED', created.outcome, created.message);
    List<AXF_OBJ_FinancialTransaction__c> rows = occurrencesOf(
      created.scheduleId
    );
    Assert.isTrue(rows.size() > 3);
    // A terceira ocorrência foi conciliada antecipadamente.
    update new AXF_OBJ_FinancialTransaction__c(
      Id = rows[2].Id,
      AXF_FTX_PKL_Status__c = 'CONFIRMED',
      AXF_FTX_BOL_BasisFrozen__c = true
    );

    Test.startTest();
    ALT_CLS_FinancialScheduleService.ChangeInput terminate = change(
      created.scheduleId,
      'axf155-end-today',
      0
    );
    terminate.terminationDate = Date.today();
    ALT_CLS_FinancialScheduleService.ChangeResult ended = ALT_CLS_FinancialScheduleService.terminateSchedule(
      terminate
    );
    ALT_CLS_FinancialScheduleService.ChangeResult replayed = ALT_CLS_FinancialScheduleService.terminateSchedule(
      terminate
    );
    ALT_CLS_FinancialScheduleService.ChangeResult reactivate = ALT_CLS_FinancialScheduleService.terminateSchedule(
      change(created.scheduleId, 'axf155-end-again', 1)
    );
    ALT_CLS_FinancialScheduleService.ChangeInput edit = change(
      created.scheduleId,
      'axf155-edit-ended',
      1
    );
    edit.amount = 10;
    ALT_CLS_FinancialScheduleService.ChangeResult editEnded = ALT_CLS_FinancialScheduleService.editAmount(
      edit
    );
    Test.stopTest();

    Assert.areEqual('TERMINATED', ended.outcome, ended.message);
    Assert.areEqual(rows.size() - 2, ended.cancelledCount);
    Assert.areEqual(1, ended.protectedCount);
    Assert.areEqual(2, ended.fromSequence);
    Assert.areEqual('REPLAY', replayed.outcome);
    Assert.areEqual('INVALID', reactivate.outcome, 'sem data');
    Assert.areEqual('CONFLICT', editEnded.outcome, editEnded.message);

    List<AXF_OBJ_FinancialTransaction__c> after = occurrencesOf(
      created.scheduleId
    );
    Assert.areEqual('OPEN', after[0].AXF_FTX_PKL_ScheduleState__c);
    Assert.areEqual('OPEN', after[2].AXF_FTX_PKL_ScheduleState__c);
    Assert.areEqual('CONFIRMED', after[2].AXF_FTX_PKL_Status__c);
    for (Integer i = 1; i < after.size(); i++) {
      if (i != 2) {
        Assert.areEqual('CANCELLED', after[i].AXF_FTX_PKL_ScheduleState__c);
      }
    }
    AXF_OBJ_FinancialSchedule__c root = [
      SELECT
        AXF_FSC_PKL_State__c,
        AXF_FSC_DAT_TerminationDate__c,
        AXF_FSC_NUM_Version__c
      FROM AXF_OBJ_FinancialSchedule__c
      WHERE Id = :created.scheduleId
    ];
    Assert.areEqual('ENDED', root.AXF_FSC_PKL_State__c);
    Assert.areEqual(Date.today(), root.AXF_FSC_DAT_TerminationDate__c);
    Assert.areEqual(1, root.AXF_FSC_NUM_Version__c.intValue());

    ALT_CLS_FinancialScheduleService.ChangeInput again = change(
      created.scheduleId,
      'axf155-end-twice',
      1
    );
    again.terminationDate = Date.today();
    Assert.areEqual(
      'CONFLICT',
      ALT_CLS_FinancialScheduleService.terminateSchedule(again).outcome,
      'Um cronograma encerrado não é reativado nem reencerrado'
    );
  }

  @IsTest
  static void changeCommandsRejectInvalidOrForeignRequests() {
    Account owner = holder('AXF155 mudança inválida');
    Account stranger = holder('AXF155 mudança alheia');
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      owner.Id,
      stranger.Id
    };
    ALT_CLS_FinancialScheduleService.CreateResult estimated = ALT_CLS_FinancialScheduleService.createSchedule(
      recurrence(owner.Id, Date.today().addDays(4), null, 1, null, 'axf155-inv')
    );
    ALT_CLS_FinancialScheduleService.CreateResult calculated = ALT_CLS_FinancialScheduleService.createSchedule(
      request(owner.Id, 'PRICE', 6, 1, Date.today(), 'axf155-calc')
    );
    ALT_CLS_FinancialScheduleService.CreateResult foreign = ALT_CLS_FinancialScheduleService.createSchedule(
      recurrence(
        stranger.Id,
        Date.today().addDays(4),
        null,
        1,
        null,
        'axf155-foreign'
      )
    );
    Assert.areEqual('CREATED', estimated.outcome, estimated.message);
    Assert.areEqual('CREATED', calculated.outcome, calculated.message);
    Assert.areEqual('CREATED', foreign.outcome, foreign.message);

    ALT_CLS_FinancialScheduleService.ChangeInput missingKey = change(
      estimated.scheduleId,
      ' ',
      0
    );
    missingKey.amount = 10;
    ALT_CLS_FinancialScheduleService.ChangeInput missingVersion = change(
      estimated.scheduleId,
      'axf155-k1',
      null
    );
    missingVersion.amount = 10;
    ALT_CLS_FinancialScheduleService.ChangeInput badAmount = change(
      estimated.scheduleId,
      'axf155-k2',
      0
    );
    badAmount.amount = 1.234;
    ALT_CLS_FinancialScheduleService.ChangeInput zero = change(
      estimated.scheduleId,
      'axf155-k3',
      0
    );
    zero.amount = 0;
    for (
      ALT_CLS_FinancialScheduleService.ChangeInput input : new List<ALT_CLS_FinancialScheduleService.ChangeInput>{
        null,
        missingKey,
        missingVersion,
        badAmount,
        zero
      }
    ) {
      Assert.areEqual(
        'INVALID',
        ALT_CLS_FinancialScheduleService.editAmount(input).outcome
      );
    }

    ALT_CLS_FinancialScheduleService.ChangeInput onCalculated = change(
      calculated.scheduleId,
      'axf155-k4',
      0
    );
    onCalculated.amount = 10;
    Assert.areEqual(
      'UNSUPPORTED',
      ALT_CLS_FinancialScheduleService.editAmount(onCalculated).outcome
    );

    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      owner.Id
    };
    ALT_CLS_FinancialScheduleService.ChangeInput onForeign = change(
      foreign.scheduleId,
      'axf155-k5',
      0
    );
    onForeign.terminationDate = Date.today();
    Assert.areEqual(
      'FORBIDDEN',
      ALT_CLS_FinancialScheduleService.terminateSchedule(onForeign).outcome
    );
    ALT_CLS_FinancialScheduleService.ChangeInput missing = change(
      owner.Id,
      'axf155-k6',
      0
    );
    missing.terminationDate = Date.today();
    Assert.areEqual(
      'NOT_FOUND',
      ALT_CLS_FinancialScheduleService.terminateSchedule(missing).outcome
    );
  }

  private static ALT_CLS_ScheduleProjection.ProjectionResult projectToday(
    Id scheduleId
  ) {
    ALT_CLS_ScheduleProjection.ProjectionInput input = new ALT_CLS_ScheduleProjection.ProjectionInput();
    input.scheduleId = scheduleId;
    input.asOfDate = Date.today();
    return ALT_CLS_ScheduleProjection.project(input);
  }

  @IsTest
  static void editKeepsAProtectedOccurrenceAfterTheFirstMutableOne() {
    Account owner = holder('AXF155 protegida no meio');
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      owner.Id
    };
    ALT_CLS_FinancialScheduleService.CreateResult created = ALT_CLS_FinancialScheduleService.createSchedule(
      recurrence(owner.Id, Date.today().addDays(3), null, 1, null, 'axf155-mid')
    );
    Assert.areEqual('CREATED', created.outcome, created.message);
    List<AXF_OBJ_FinancialTransaction__c> rows = occurrencesOf(
      created.scheduleId
    );
    Assert.isTrue(rows.size() >= 4);
    Id initialReference = rows[2].AXF_FTX_LKP_ScheduleReference__c;
    // A sequência 3 foi conciliada antecipadamente; 2 e 4 continuam mutáveis.
    update new AXF_OBJ_FinancialTransaction__c(
      Id = rows[2].Id,
      AXF_FTX_PKL_Status__c = 'CONFIRMED'
    );

    Test.startTest();
    ALT_CLS_FinancialScheduleService.ChangeInput edit = change(
      created.scheduleId,
      'axf155-mid-edit',
      0
    );
    edit.amount = 350;
    ALT_CLS_FinancialScheduleService.ChangeResult changed = ALT_CLS_FinancialScheduleService.editAmount(
      edit
    );
    Test.stopTest();

    Assert.areEqual('UPDATED', changed.outcome, changed.message);
    Assert.areEqual(1, changed.fromSequence);
    Assert.areEqual(1, changed.protectedCount);
    Assert.areEqual(rows.size() - 1, changed.updatedCount);
    List<AXF_OBJ_FinancialTransaction__c> after = occurrencesOf(
      created.scheduleId
    );
    Assert.areEqual(300.00, after[2].AXF_FTX_NUM_CurrentBasis__c);
    Assert.areEqual(300.00, after[2].AXF_FTX_NUM_Magnitude__c);
    Assert.areEqual(
      initialReference,
      after[2].AXF_FTX_LKP_ScheduleReference__c
    );
    for (Integer index : new List<Integer>{ 1, 3 }) {
      Assert.areEqual(350.00, after[index].AXF_FTX_NUM_CurrentBasis__c);
      Assert.areEqual(350.00, after[index].AXF_FTX_NUM_Magnitude__c);
    }
    AXF_OBJ_ScheduleChange__c receipt = [
      SELECT AXF_SCH_TAL_ProtectedRangesJson__c
      FROM AXF_OBJ_ScheduleChange__c
      WHERE
        AXF_SCH_LKP_Schedule__c = :created.scheduleId
        AND AXF_SCH_PKL_Operation__c = 'EDIT'
    ];
    Assert.areEqual('[3]', receipt.AXF_SCH_TAL_ProtectedRangesJson__c);
  }

  @IsTest
  static void editFromTheFirstSequenceTwiceKeepsTheProjectionCurrent() {
    Account owner = holder('AXF155 edição dupla');
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      owner.Id
    };
    ALT_CLS_ScheduleProjection.authorizedOverride = new Set<Id>{ owner.Id };
    ALT_CLS_FinancialScheduleService.CreateResult created = ALT_CLS_FinancialScheduleService.createSchedule(
      recurrence(owner.Id, Date.today().addDays(3), null, 1, null, 'axf155-2x')
    );
    Assert.areEqual('CREATED', created.outcome, created.message);

    Test.startTest();
    ALT_CLS_FinancialScheduleService.ChangeInput first = change(
      created.scheduleId,
      'axf155-2x-a',
      0
    );
    first.amount = 350;
    ALT_CLS_FinancialScheduleService.ChangeResult firstResult = ALT_CLS_FinancialScheduleService.editAmount(
      first
    );
    ALT_CLS_ScheduleProjection.ProjectionResult afterFirst = projectToday(
      created.scheduleId
    );
    ALT_CLS_FinancialScheduleService.ChangeInput second = change(
      created.scheduleId,
      'axf155-2x-b',
      1
    );
    second.amount = 400;
    ALT_CLS_FinancialScheduleService.ChangeResult secondResult = ALT_CLS_FinancialScheduleService.editAmount(
      second
    );
    ALT_CLS_ScheduleProjection.ProjectionResult afterSecond = projectToday(
      created.scheduleId
    );
    Test.stopTest();

    Assert.areEqual('UPDATED', firstResult.outcome, firstResult.message);
    Assert.areEqual(1, firstResult.fromSequence);
    Assert.areEqual('OK', afterFirst.outcome, afterFirst.message);
    for (ALT_CLS_ScheduleProjection.OccurrenceLine line : afterFirst.lines) {
      Assert.areEqual(350.00, line.amount, 'sequência ' + line.sequence);
    }
    Assert.areEqual('UPDATED', secondResult.outcome, secondResult.message);
    Assert.areEqual(1, secondResult.fromSequence);
    Assert.areEqual('OK', afterSecond.outcome, afterSecond.message);
    Assert.isFalse(afterSecond.lines.isEmpty());
    for (ALT_CLS_ScheduleProjection.OccurrenceLine line : afterSecond.lines) {
      Assert.areEqual(400.00, line.amount, 'sequência ' + line.sequence);
    }
  }

  @IsTest
  static void replenishmentAfterAnEditUsesTheNewAmountAndEndedCreatesNothing() {
    Account owner = holder('AXF155 reposição editada');
    AXF_OBJ_BankAccount__c cash = wallet(owner.Id);
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      owner.Id
    };
    ALT_CLS_ScheduleProjection.authorizedOverride = new Set<Id>{ owner.Id };
    ALT_CLS_FinancialScheduleService.CreateResult created = ALT_CLS_FinancialScheduleService.createSchedule(
      recurrence(
        owner.Id,
        Date.today().addDays(1),
        14,
        null,
        cash.Id,
        'axf155-replenish-edit'
      )
    );
    Assert.areEqual('CREATED', created.outcome, created.message);
    ALT_CLS_FinancialScheduleService.ChangeInput edit = change(
      created.scheduleId,
      'axf155-replenish-edit-420',
      0
    );
    edit.amount = 420;
    Assert.areEqual(
      'UPDATED',
      ALT_CLS_FinancialScheduleService.editAmount(edit).outcome
    );
    List<AXF_OBJ_FinancialTransaction__c> rows = occurrencesOf(
      created.scheduleId
    );
    AXF_OBJ_FinancialTransaction__c last = rows[rows.size() - 1];
    delete last;
    ALT_CLS_FinancialScheduleService.ReplenishmentRequest request = new ALT_CLS_FinancialScheduleService.ReplenishmentRequest();
    request.scheduleId = created.scheduleId;

    Test.startTest();
    ALT_CLS_FinancialScheduleService.ReplenishmentResult generated = ALT_CLS_FinancialScheduleService.replenishSchedule(
      request
    );
    ALT_CLS_FinancialScheduleService.ChangeInput terminate = change(
      created.scheduleId,
      'axf155-replenish-end',
      1
    );
    terminate.terminationDate = Date.today();
    Assert.areEqual(
      'TERMINATED',
      ALT_CLS_FinancialScheduleService.terminateSchedule(terminate).outcome
    );
    delete [
      SELECT Id
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE
        AXF_FTX_LKP_Schedule__c = :created.scheduleId
        AND AXF_FTX_NUM_Sequence__c = :last.AXF_FTX_NUM_Sequence__c
    ];
    Integer before = occurrencesOf(created.scheduleId).size();
    ALT_CLS_FinancialScheduleService.ReplenishmentResult ended = ALT_CLS_FinancialScheduleService.replenishSchedule(
      request
    );
    Test.stopTest();

    Assert.areEqual('GENERATED', generated.outcome, generated.message);
    Assert.areEqual(1, generated.createdCount);
    Assert.areEqual('SKIPPED', ended.outcome, ended.message);
    Assert.areEqual(before, occurrencesOf(created.scheduleId).size());
    Assert.areEqual(0, ended.createdCount);
  }

  @IsTest
  static void regenerationAfterAnEditCarriesTheNewAmountAndTheOrigin() {
    Account owner = holder('AXF155 regeração');
    AXF_OBJ_BankAccount__c cash = wallet(owner.Id);
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      owner.Id
    };
    ALT_CLS_ScheduleProjection.authorizedOverride = new Set<Id>{ owner.Id };
    ALT_CLS_FinancialScheduleService.CreateResult created = ALT_CLS_FinancialScheduleService.createSchedule(
      recurrence(
        owner.Id,
        Date.today().addDays(1),
        14,
        null,
        cash.Id,
        'axf155-regenerate'
      )
    );
    ALT_CLS_FinancialScheduleService.ChangeInput edit = change(
      created.scheduleId,
      'axf155-regenerate-420',
      0
    );
    edit.amount = 420;
    ALT_CLS_FinancialScheduleService.ChangeResult changed = ALT_CLS_FinancialScheduleService.editAmount(
      edit
    );
    Assert.areEqual('UPDATED', changed.outcome, changed.message);
    List<AXF_OBJ_FinancialTransaction__c> rows = occurrencesOf(
      created.scheduleId
    );
    AXF_OBJ_FinancialTransaction__c last = rows[rows.size() - 1];
    delete last;
    ALT_CLS_FinancialScheduleService.ReplenishmentRequest request = new ALT_CLS_FinancialScheduleService.ReplenishmentRequest();
    request.scheduleId = created.scheduleId;

    Test.startTest();
    ALT_CLS_FinancialScheduleService.ReplenishmentResult generated = ALT_CLS_FinancialScheduleService.replenishSchedule(
      request
    );
    Test.stopTest();

    Assert.areEqual('GENERATED', generated.outcome, generated.message);
    AXF_OBJ_FinancialTransaction__c regenerated = [
      SELECT
        AXF_FTX_NUM_CurrentBasis__c,
        AXF_FTX_NUM_Magnitude__c,
        AXF_FTX_LKP_BankAccount__c,
        AXF_FTX_LKP_ScheduleReference__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE
        AXF_FTX_LKP_Schedule__c = :created.scheduleId
        AND AXF_FTX_NUM_Sequence__c = :last.AXF_FTX_NUM_Sequence__c
    ];
    Assert.areEqual(420.00, regenerated.AXF_FTX_NUM_CurrentBasis__c);
    Assert.areEqual(420.00, regenerated.AXF_FTX_NUM_Magnitude__c);
    Assert.areEqual(cash.Id, regenerated.AXF_FTX_LKP_BankAccount__c);
    Assert.areEqual(
      changed.referenceId,
      regenerated.AXF_FTX_LKP_ScheduleReference__c
    );
  }

  @IsTest
  static void legacyMonthlyPayloadHashIsUnchanged() {
    Account owner = holder('AXF155 payload legado');
    ALT_CLS_FinancialScheduleService.CreateInput monthly = request(
      owner.Id,
      'INSTALLMENT',
      12,
      1,
      Date.newInstance(2027, 1, 10),
      'axf155-legacy-payload'
    );
    Assert.areEqual(
      AXF_CLS_IdentityFraming.sha256Hex(
        AXF_CLS_IdentityFraming.frame(
          new List<Object>{
            'axf103-payload-v1',
            owner.Id,
            null,
            'DEBIT',
            'BRL',
            'INSTALLMENT',
            12,
            1,
            Date.newInstance(2027, 1, 10),
            1,
            10,
            1,
            12,
            360000.00,
            null,
            null,
            0.00,
            0.00,
            null,
            null,
            'axf155-legacy-payload'
          }
        )
      ),
      ALT_CLS_FinancialScheduleService.previewPayloadHash(monthly)
    );
  }

  @IsTest
  static void bimonthlyAndQuarterlyRecurrencesKeepTheirCalendar() {
    Account owner = holder('AXF155 bimestral e trimestral');
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      owner.Id
    };
    Date first = ALT_CLS_ScheduleCalendar.monthStart(Date.today()).addDays(9);
    for (Integer months : new List<Integer>{ 2, 3 }) {
      ALT_CLS_FinancialScheduleService.CreateResult created = ALT_CLS_FinancialScheduleService.createSchedule(
        recurrence(owner.Id, first, null, months, null, 'axf155-m' + months)
      );
      Assert.areEqual('CREATED', created.outcome, created.message);
      List<AXF_OBJ_FinancialTransaction__c> rows = occurrencesOf(
        created.scheduleId
      );
      Assert.isTrue(rows.size() >= 4, 'meses ' + months);
      for (Integer i = 0; i < rows.size(); i++) {
        Assert.areEqual(
          first.addMonths(months * i),
          rows[i].AXF_FTX_DAT_DueDate__c,
          'meses ' + months + ', ocorrência ' + i
        );
      }
    }
  }

  // --- AXF-156: EDIT de parcelamento e quitação antecipada -------------------

  private static ALT_CLS_FinancialScheduleService.CreateInput financing(
    Id accountId,
    String method,
    Integer total,
    Decimal principal,
    Decimal rate,
    Date firstDueDate,
    String legacyKey
  ) {
    ALT_CLS_FinancialScheduleService.CreateInput value = new ALT_CLS_FinancialScheduleService.CreateInput();
    value.accountId = accountId;
    value.direction = 'DEBIT';
    value.currencyIsoCode = 'BRL';
    value.method = method;
    value.totalInstallments = total;
    value.firstSequence = 1;
    value.firstDueDate = firstDueDate;
    value.periodMonths = 1;
    value.principal = principal;
    value.periodRate = rate;
    value.legacyGroupKey = legacyKey;
    value.description = 'Financiamento teste';
    value.generationEnabled = true;
    return value;
  }

  private static void confirm(Id scheduleId, Set<Integer> sequences) {
    List<AXF_OBJ_FinancialTransaction__c> updates = new List<AXF_OBJ_FinancialTransaction__c>();
    for (AXF_OBJ_FinancialTransaction__c row : occurrencesOf(scheduleId)) {
      if (sequences.contains(row.AXF_FTX_NUM_Sequence__c.intValue())) {
        updates.add(
          new AXF_OBJ_FinancialTransaction__c(
            Id = row.Id,
            AXF_FTX_PKL_Status__c = 'CONFIRMED'
          )
        );
      }
    }
    update updates;
  }

  @IsTest
  static void installmentEditCreatesARevisionAndKeepsRealizedInstallments() {
    Account owner = holder('AXF156 parcelamento');
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      owner.Id
    };
    ALT_CLS_ScheduleProjection.authorizedOverride = new Set<Id>{ owner.Id };
    ALT_CLS_FinancialScheduleService.todayOverride = Date.newInstance(
      2026,
      9,
      15
    );
    ALT_CLS_FinancialScheduleService.CreateResult created = ALT_CLS_FinancialScheduleService.createSchedule(
      financing(
        owner.Id,
        'INSTALLMENT',
        10,
        1000,
        null,
        Date.newInstance(2026, 5, 15),
        'axf156-inst'
      )
    );
    Assert.areEqual('CREATED', created.outcome, created.message);
    Assert.areEqual(10, created.occurrenceCount);
    confirm(created.scheduleId, new Set<Integer>{ 4, 6 });

    Test.startTest();
    ALT_CLS_FinancialScheduleService.ChangeInput edit = change(
      created.scheduleId,
      'axf156-edit-120',
      0
    );
    edit.amount = 120;
    ALT_CLS_FinancialScheduleService.ChangeResult changed = ALT_CLS_FinancialScheduleService.editAmount(
      edit
    );
    ALT_CLS_FinancialScheduleService.ChangeResult replayed = ALT_CLS_FinancialScheduleService.editAmount(
      edit
    );
    ALT_CLS_FinancialScheduleService.ChangeInput stale = change(
      created.scheduleId,
      'axf156-edit-stale',
      0
    );
    stale.amount = 130;
    ALT_CLS_FinancialScheduleService.ChangeResult conflict = ALT_CLS_FinancialScheduleService.editAmount(
      stale
    );
    Test.stopTest();

    Assert.areEqual('UPDATED', changed.outcome, changed.message);
    Assert.areEqual(5, changed.fromSequence);
    Assert.areEqual(5, changed.updatedCount, 'parcelas 5, 7, 8, 9 e 10');
    Assert.areEqual(1, changed.protectedCount, 'a 6ª paga antecipadamente');
    Assert.isNotNull(changed.definitionId);
    Assert.areEqual('REPLAY', replayed.outcome, replayed.message);
    Assert.areEqual('CONFLICT', conflict.outcome, conflict.message);

    AXF_OBJ_ScheduleDefinition__c revision = [
      SELECT
        AXF_SDF_NUM_Revision__c,
        AXF_SDF_NUM_EffectiveSequence__c,
        AXF_SDF_NUM_FixedValue__c,
        AXF_SDF_LKP_Predecessor__c,
        AXF_SDF_PKL_Method__c,
        AXF_SDF_TAL_InputCanonicalJson__c
      FROM AXF_OBJ_ScheduleDefinition__c
      WHERE Id = :changed.definitionId
    ];
    Assert.areEqual(2, revision.AXF_SDF_NUM_Revision__c.intValue());
    Assert.areEqual(5, revision.AXF_SDF_NUM_EffectiveSequence__c.intValue());
    Assert.areEqual(120.00, revision.AXF_SDF_NUM_FixedValue__c);
    Assert.areEqual('INSTALLMENT', revision.AXF_SDF_PKL_Method__c);
    Assert.isNotNull(revision.AXF_SDF_LKP_Predecessor__c);
    Assert.isTrue(
      revision.AXF_SDF_TAL_InputCanonicalJson__c.contains('Financiamento teste')
    );
    Assert.areEqual(
      changed.definitionId,
      [
        SELECT AXF_FSC_LKP_ActiveDefinition__c
        FROM AXF_OBJ_FinancialSchedule__c
        WHERE Id = :created.scheduleId
      ]
      .AXF_FSC_LKP_ActiveDefinition__c
    );
    for (
      AXF_OBJ_FinancialTransaction__c row : occurrencesOf(created.scheduleId)
    ) {
      Integer sequence = row.AXF_FTX_NUM_Sequence__c.intValue();
      Decimal expected = (sequence < 5 || sequence == 6) ? 100.00 : 120.00;
      Assert.areEqual(
        expected,
        row.AXF_FTX_NUM_CurrentBasis__c,
        'seq ' + sequence
      );
      Assert.areEqual(
        expected,
        row.AXF_FTX_NUM_Magnitude__c,
        'seq ' + sequence
      );
    }

    ALT_CLS_ScheduleProjection.ProjectionInput input = new ALT_CLS_ScheduleProjection.ProjectionInput();
    input.scheduleId = created.scheduleId;
    input.asOfDate = Date.newInstance(2026, 9, 15);
    ALT_CLS_ScheduleProjection.ProjectionResult projection = ALT_CLS_ScheduleProjection.project(
      input
    );
    Assert.areEqual('OK', projection.outcome, projection.message);
    Assert.areEqual(10, projection.lines.size());
  }

  @IsTest
  static void fixedValueRevisionProjectsTheNewAmountForVirtualInstallments() {
    AXF_OBJ_ScheduleDefinition__c definition = new AXF_OBJ_ScheduleDefinition__c(
      AXF_SDF_PKL_Method__c = 'INSTALLMENT',
      AXF_SDF_NUM_TotalInstallments__c = 4,
      AXF_SDF_NUM_FirstSequence__c = 1,
      AXF_SDF_DAT_FirstDueDate__c = Date.newInstance(2026, 1, 10),
      AXF_SDF_NUM_Principal__c = 100,
      AXF_SDF_NUM_FixedValue__c = 42.5,
      AXF_SDF_NUM_RecurringFee__c = 0,
      AXF_SDF_NUM_UpfrontFee__c = 0
    );
    List<ALT_CLS_AmortizationSchedule.Occurrence> occurrences = ALT_CLS_ScheduleProjection.generateOccurrences(
      definition
    );
    Assert.areEqual(4, occurrences.size());
    for (ALT_CLS_AmortizationSchedule.Occurrence occurrence : occurrences) {
      Assert.areEqual(42.50, occurrence.payment);
    }
    definition.AXF_SDF_NUM_FixedValue__c = null;
    Assert.areEqual(
      25.00,
      ALT_CLS_ScheduleProjection.generateOccurrences(definition)[0].payment,
      'sem valor fixo, a divisão original do parcelamento'
    );
  }

  @IsTest
  static void installmentEditWithoutRemainingInstallmentsIsRejected() {
    Account owner = holder('AXF156 parcelamento vencido');
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      owner.Id
    };
    ALT_CLS_FinancialScheduleService.todayOverride = Date.newInstance(
      2026,
      9,
      15
    );
    ALT_CLS_FinancialScheduleService.CreateResult created = ALT_CLS_FinancialScheduleService.createSchedule(
      financing(
        owner.Id,
        'INSTALLMENT',
        3,
        300,
        null,
        Date.newInstance(2026, 5, 15),
        'axf156-past'
      )
    );
    Assert.areEqual('CREATED', created.outcome, created.message);
    ALT_CLS_FinancialScheduleService.ChangeInput edit = change(
      created.scheduleId,
      'axf156-past-edit',
      0
    );
    edit.amount = 50;
    ALT_CLS_FinancialScheduleService.ChangeResult result = ALT_CLS_FinancialScheduleService.editAmount(
      edit
    );
    Assert.areEqual('INVALID', result.outcome, result.message);
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AXF_OBJ_ScheduleDefinition__c
        WHERE AXF_SDF_LKP_Schedule__c = :created.scheduleId
      ],
      'nada foi gravado'
    );
  }

  @IsTest
  static void settlementCreatesThePayoffEntryAndEndsTheScheduleAtomically() {
    Account owner = holder('AXF156 quitação');
    AXF_OBJ_BankAccount__c cash = wallet(owner.Id);
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      owner.Id
    };
    Date today = Date.newInstance(2026, 9, 15);
    ALT_CLS_FinancialScheduleService.todayOverride = today;
    ALT_CLS_FinancialScheduleService.CreateInput input = financing(
      owner.Id,
      'PRICE',
      12,
      12000,
      0.01,
      Date.newInstance(2026, 6, 15),
      'axf156-price'
    );
    input.bankAccountId = cash.Id;
    ALT_CLS_FinancialScheduleService.CreateResult created = ALT_CLS_FinancialScheduleService.createSchedule(
      input
    );
    Assert.areEqual('CREATED', created.outcome, created.message);
    Assert.areEqual(12, created.occurrenceCount);
    confirm(created.scheduleId, new Set<Integer>{ 1, 2, 3 });
    ALT_CLS_FinancialScheduleService.CreateResult estimated = ALT_CLS_FinancialScheduleService.createSchedule(
      recurrence(owner.Id, today, null, 1, null, 'axf156-est')
    );
    Assert.areEqual('CREATED', estimated.outcome, estimated.message);

    Test.startTest();
    ALT_CLS_FinancialScheduleService.ChangeInput zero = change(
      created.scheduleId,
      'axf156-settle-zero',
      0
    );
    zero.amount = 0;
    zero.terminationDate = today;
    ALT_CLS_FinancialScheduleService.ChangeInput onEstimated = change(
      estimated.scheduleId,
      'axf156-settle-est',
      0
    );
    onEstimated.amount = 10;
    onEstimated.terminationDate = today;
    ALT_CLS_FinancialScheduleService.ChangeInput payoff = change(
      created.scheduleId,
      'axf156-settle',
      0
    );
    payoff.amount = 9000.55;
    payoff.terminationDate = today;
    ALT_CLS_FinancialScheduleService.ChangeResult invalid = ALT_CLS_FinancialScheduleService.settleSchedule(
      zero
    );
    ALT_CLS_FinancialScheduleService.ChangeResult unsupported = ALT_CLS_FinancialScheduleService.settleSchedule(
      onEstimated
    );
    ALT_CLS_FinancialScheduleService.ChangeResult settled = ALT_CLS_FinancialScheduleService.settleSchedule(
      payoff
    );
    ALT_CLS_FinancialScheduleService.ChangeResult replayed = ALT_CLS_FinancialScheduleService.settleSchedule(
      payoff
    );
    Test.stopTest();

    Assert.areEqual('INVALID', invalid.outcome);
    Assert.areEqual('UNSUPPORTED', unsupported.outcome);
    Assert.areEqual('TERMINATED', settled.outcome, settled.message);
    Assert.areEqual(8, settled.cancelledCount, 'parcelas 5 a 12');
    Assert.isNotNull(settled.settlementTransactionId);
    Assert.areEqual('REPLAY', replayed.outcome, replayed.message);
    Assert.areEqual(
      settled.settlementTransactionId,
      replayed.settlementTransactionId
    );

    AXF_OBJ_FinancialTransaction__c entry = [
      SELECT
        AXF_FTX_NUM_Magnitude__c,
        AXF_FTX_DAT_DueDate__c,
        AXF_FTX_PKL_Status__c,
        AXF_FTX_LKP_Schedule__c,
        AXF_FTX_NUM_Sequence__c,
        AXF_FTX_LKP_BankAccount__c,
        AXF_FTX_LKP_Account__c,
        AXF_FTX_TXT_Description__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE Id = :settled.settlementTransactionId
    ];
    Assert.areEqual(9000.55, entry.AXF_FTX_NUM_Magnitude__c);
    Assert.areEqual(today, entry.AXF_FTX_DAT_DueDate__c);
    Assert.areEqual('PLANNED', entry.AXF_FTX_PKL_Status__c);
    Assert.isNull(entry.AXF_FTX_LKP_Schedule__c);
    Assert.isNull(entry.AXF_FTX_NUM_Sequence__c);
    Assert.areEqual(cash.Id, entry.AXF_FTX_LKP_BankAccount__c);
    Assert.areEqual(owner.Id, entry.AXF_FTX_LKP_Account__c);
    Assert.isTrue(
      entry.AXF_FTX_TXT_Description__c.contains('Financiamento teste')
    );

    AXF_OBJ_ScheduleChange__c receipt = [
      SELECT AXF_SCH_TAL_ResultJson__c, AXF_SCH_TAL_FieldPatchJson__c
      FROM AXF_OBJ_ScheduleChange__c
      WHERE
        AXF_SCH_LKP_Schedule__c = :created.scheduleId
        AND AXF_SCH_PKL_Operation__c = 'TERMINATE'
    ];
    Assert.isTrue(
      receipt.AXF_SCH_TAL_ResultJson__c.contains(
        String.valueOf(settled.settlementTransactionId)
      )
    );
    Assert.isTrue(receipt.AXF_SCH_TAL_FieldPatchJson__c.contains('9000.55'));
    Assert.areEqual(
      'ENDED',
      [
        SELECT AXF_FSC_PKL_State__c
        FROM AXF_OBJ_FinancialSchedule__c
        WHERE Id = :created.scheduleId
      ]
      .AXF_FSC_PKL_State__c
    );
    for (
      AXF_OBJ_FinancialTransaction__c row : occurrencesOf(created.scheduleId)
    ) {
      Integer sequence = row.AXF_FTX_NUM_Sequence__c.intValue();
      Assert.areEqual(
        sequence > 4 ? 'CANCELLED' : 'OPEN',
        row.AXF_FTX_PKL_ScheduleState__c,
        'seq ' + sequence
      );
    }
  }

  @IsTest
  static void installmentEditReachesProjectedAndReplenishedInstallments() {
    Account owner = holder('AXF156 parcelamento longo');
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      owner.Id
    };
    ALT_CLS_ScheduleProjection.authorizedOverride = new Set<Id>{ owner.Id };
    ALT_CLS_FinancialScheduleService.CreateResult created = ALT_CLS_FinancialScheduleService.createSchedule(
      financing(
        owner.Id,
        'INSTALLMENT',
        24,
        2400,
        null,
        ALT_CLS_ScheduleCalendar.monthStart(Date.today()).addDays(14),
        'axf156-long'
      )
    );
    Assert.areEqual('CREATED', created.outcome, created.message);
    Assert.isTrue(created.occurrenceCount < 24, 'parte das parcelas é virtual');
    ALT_CLS_FinancialScheduleService.ChangeInput edit = change(
      created.scheduleId,
      'axf156-long-edit',
      0
    );
    edit.amount = 120;
    ALT_CLS_FinancialScheduleService.ChangeResult changed = ALT_CLS_FinancialScheduleService.editAmount(
      edit
    );
    Assert.areEqual('UPDATED', changed.outcome, changed.message);

    ALT_CLS_ScheduleProjection.ProjectionResult projection = projectToday(
      created.scheduleId
    );
    Assert.areEqual('OK', projection.outcome, projection.message);
    Integer projected = 0;
    for (ALT_CLS_ScheduleProjection.OccurrenceLine line : projection.lines) {
      if (line.sequence >= changed.fromSequence) {
        Assert.areEqual(120.00, line.amount, 'parcela ' + line.sequence);
      }
      if (!line.persisted) {
        projected++;
        Assert.areEqual(changed.definitionId, line.definitionId);
      }
    }
    Assert.isTrue(projected > 0, 'parcelas virtuais seguem a revisão');

    // Uma parcela persistida some da janela e a reposição a recria pela revisão nova.
    AXF_OBJ_FinancialTransaction__c last = [
      SELECT Id, AXF_FTX_NUM_Sequence__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE AXF_FTX_LKP_Schedule__c = :created.scheduleId
      ORDER BY AXF_FTX_NUM_Sequence__c DESC
      LIMIT 1
    ];
    delete last;
    ALT_CLS_FinancialScheduleService.ReplenishmentRequest request = new ALT_CLS_FinancialScheduleService.ReplenishmentRequest();
    request.scheduleId = created.scheduleId;
    Test.startTest();
    ALT_CLS_FinancialScheduleService.ReplenishmentResult generated = ALT_CLS_FinancialScheduleService.replenishSchedule(
      request
    );
    Test.stopTest();
    Assert.areEqual('GENERATED', generated.outcome, generated.message);
    AXF_OBJ_FinancialTransaction__c recreated = [
      SELECT
        AXF_FTX_NUM_Magnitude__c,
        AXF_FTX_NUM_CurrentBasis__c,
        AXF_FTX_LKP_ScheduleDefinition__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE
        AXF_FTX_LKP_Schedule__c = :created.scheduleId
        AND AXF_FTX_NUM_Sequence__c = :last.AXF_FTX_NUM_Sequence__c
    ];
    Assert.areEqual(120.00, recreated.AXF_FTX_NUM_Magnitude__c);
    Assert.areEqual(120.00, recreated.AXF_FTX_NUM_CurrentBasis__c);
    Assert.areEqual(
      changed.definitionId,
      recreated.AXF_FTX_LKP_ScheduleDefinition__c
    );
  }

  @IsTest
  static void publicPortRejectsATerminationOrSettlementInThePast() {
    Account owner = holder('AXF156 porta passado');
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      owner.Id
    };
    ALT_CLS_FinancialScheduleService.CreateResult created = ALT_CLS_FinancialScheduleService.createSchedule(
      financing(
        owner.Id,
        'PRICE',
        6,
        6000,
        0.01,
        Date.today(),
        'axf156-past-port'
      )
    );
    Assert.areEqual('CREATED', created.outcome, created.message);
    ALT_CLS_FinancialScheduleService.ChangeInput terminate = change(
      created.scheduleId,
      'axf156-past-end',
      0
    );
    terminate.terminationDate = Date.today().addDays(-1);
    ALT_CLS_FinancialScheduleService.ChangeInput settle = change(
      created.scheduleId,
      'axf156-past-settle',
      0
    );
    settle.terminationDate = Date.today().addDays(-1);
    settle.amount = 100;
    Assert.areEqual(
      'INVALID',
      ALT_CLS_FinancialScheduleService.terminateSchedule(terminate).outcome
    );
    Assert.areEqual(
      'INVALID',
      ALT_CLS_FinancialScheduleService.settleSchedule(settle).outcome
    );
    Assert.areEqual(
      'ACTIVE',
      [
        SELECT AXF_FSC_PKL_State__c
        FROM AXF_OBJ_FinancialSchedule__c
        WHERE Id = :created.scheduleId
      ]
      .AXF_FSC_PKL_State__c
    );
  }
}
