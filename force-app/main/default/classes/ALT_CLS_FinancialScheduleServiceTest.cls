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
    Assert.areEqual('MULTI_HOLDER', mixed[0].outcome, mixed[0].message);

    List<ALT_CLS_FinancialScheduleService.CreateResult> sameHolder = ALT_CLS_FinancialScheduleService.createSchedules(
      new List<ALT_CLS_FinancialScheduleService.CreateInput>{
        request(first.Id, 'INSTALLMENT', 12, 1, Date.today(), 'axf103-c'),
        request(first.Id, 'INSTALLMENT', 12, 1, Date.today(), 'axf103-d')
      }
    );
    Assert.areEqual('INVALID', sameHolder[0].outcome, sameHolder[0].message);

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
        AXF_SRF_NUM_EconomicSequence__c
      FROM AXF_OBJ_ScheduleReference__c
      WHERE Id = :result.referenceId
    ];
    Assert.areEqual('INITIAL', reference.AXF_SRF_PKL_Kind__c);
    Assert.areEqual(500.00, reference.AXF_SRF_NUM_RecurringAmount__c);
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
        AXF_FTX_LKP_ScheduleReference__c
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

    // Escritor legado AXF-20 ocupa o namespace `ScheduleGroupKey`.
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
    Assert.areEqual('SAVED', AXF_CLS_ScheduleService.save(legacy).outcome);

    // A via nova usa a MESMA chave legada como discriminador de identidade, mas não escreve no
    // campo de agrupamento do outro escritor.
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

    // O escritor legado continua enxergando apenas as próprias linhas: reenvio é ALREADY.
    Assert.areEqual('ALREADY', AXF_CLS_ScheduleService.save(legacy).outcome);
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
}
