/**
 * @description AXF-155: despesas/receitas recorrentes sem fim. Criação ESTIMATED com
 * periodicidade semanal/quinzenal/mensal e origem obrigatória aplicada às ocorrências; lista e
 * detalhe com status derivado; edição de valor e encerramento que só alteram ocorrências futuras
 * não realizadas; Participante só lê; ID alheio não revela nada.
 */
@IsTest(isParallel=false)
// API 62: AXON_DEV enforces FLS on plain test DML under runAs from API 67 onwards.
private class ALT_CLS_RecurrenceServiceTest {
  private static final String GESTOR = 'axf155g';
  private static final String PEER = 'axf155p';
  private static final String READER = 'axf155r';
  private static final Map<String, List<String>> READ_FIELDS = new Map<String, List<String>>{
    'AXF_OBJ_ScheduleDefinition__c' => new List<String>{
      'AXF_SDF_NUM_PeriodDays__c',
      'AXF_SDF_NUM_PeriodMonths__c',
      'AXF_SDF_TAL_InputCanonicalJson__c',
      'AXF_SDF_NUM_InitialReferenceAmount__c'
    },
    'AXF_OBJ_FinancialSchedule__c' => new List<String>{
      'AXF_FSC_LKP_ActiveDefinition__c',
      'AXF_FSC_LKP_ActiveReference__c',
      'AXF_FSC_LKP_Contract__c',
      'AXF_FSC_DAT_TerminationDate__c'
    },
    'AXF_OBJ_ScheduleReference__c' => new List<String>{
      'AXF_SRF_LKP_Compensates__c'
    },
    'AXF_OBJ_FinancialTransaction__c' => new List<String>{
      'AXF_FTX_LKP_Schedule__c',
      'AXF_FTX_NUM_Sequence__c',
      'AXF_FTX_DAT_DueDate__c',
      'AXF_FTX_NUM_CurrentBasis__c',
      'AXF_FTX_PKL_ScheduleState__c',
      'AXF_FTX_LKP_BankAccount__c',
      'AXF_FTX_LKP_CreditCard__c',
      'AXF_FTX_TXT_Description__c'
    },
    'AXF_OBJ_BankAccount__c' => new List<String>{
      'AXF_BA_LKP_Account__c',
      'AXF_BA_TXT_InstitutionName__c',
      'AXF_BA_LKP_BankInstitution__c',
      'AXF_BA_TXT_NumberMasked__c',
      'AXF_BA_TXT_Type__c',
      'AXF_BA_TXT_CurrencyIsoCode__c'
    },
    'AXF_OBJ_CreditCard__c' => new List<String>{
      'AXF_CC_LKP_Account__c',
      'AXF_CC_TXT_InstitutionName__c',
      'AXF_CC_LKP_BankInstitution__c',
      'AXF_CC_TXT_LastFourMasked__c'
    }
  };

  private static User byAlias(String alias) {
    return [SELECT Id FROM User WHERE Alias = :alias LIMIT 1];
  }

  /**
   * Check-only deploys do not apply the branch's permission-set changes to test users: the read
   * access this branch grants (PeriodDays and the now optional PeriodMonths) is mirrored here.
   */
  private static PermissionSet mirror(String name, Boolean manage) {
    PermissionSet result = new PermissionSet(Name = name, Label = name);
    insert result;
    List<ObjectPermissions> access = new List<ObjectPermissions>();
    List<FieldPermissions> fields = new List<FieldPermissions>();
    for (String objectName : READ_FIELDS.keySet()) {
      Boolean schedule = manage && objectName == 'AXF_OBJ_FinancialSchedule__c';
      access.add(
        new ObjectPermissions(
          ParentId = result.Id,
          SobjectType = objectName,
          PermissionsRead = true,
          PermissionsCreate = schedule,
          PermissionsEdit = schedule
        )
      );
      for (String field : READ_FIELDS.get(objectName)) {
        fields.add(
          new FieldPermissions(
            ParentId = result.Id,
            SobjectType = objectName,
            Field = objectName + '.' + field,
            PermissionsRead = true
          )
        );
      }
    }
    insert access;
    insert fields;
    return result;
  }

  @TestSetup
  static void setup() {
    Id profileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
    .Id;
    List<User> users = new List<User>();
    for (String alias : new List<String>{ GESTOR, PEER, READER }) {
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
    PermissionSet manage = mirror('AXF155_TestManage', true);
    PermissionSet read = mirror('AXF155_TestRead', false);
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
      for (
        Id permissionSetId : new List<Id>{
          permissionSets.get('AXF_PS_GestorFinanceiro'),
          permissionSets.get('AXF_PS_FinancialEntry'),
          manage.Id
        }
      ) {
        assignments.add(
          new PermissionSetAssignment(
            AssigneeId = users[i].Id,
            PermissionSetId = permissionSetId
          )
        );
      }
    }
    for (
      Id permissionSetId : new List<Id>{
        permissionSets.get('AXF_PS_FinancialEntry'),
        permissionSets.get('AXF_PS_Participante'),
        read.Id
      }
    ) {
      assignments.add(
        new PermissionSetAssignment(
          AssigneeId = users[2].Id,
          PermissionSetId = permissionSetId
        )
      );
    }
    insert assignments;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert new AXF_ReportCurrencyPref__c(
        SetupOwnerId = UserInfo.getOrganizationId(),
        AXF_RCP_TXT_IsoCode__c = 'BRL'
      );
    }
  }

  // ------------------------------------------------------------ fixture

  private static Account holder(String name, Id ownerId) {
    Account result = new Account(
      Name = name,
      OwnerId = ownerId,
      RecordTypeId = Account.SObjectType.getDescribe()
        .getRecordTypeInfosByDeveloperName()
        .get('AXF_Business')
        .getRecordTypeId()
    );
    insert result;
    return result;
  }

  private static AXF_OBJ_BankAccount__c wallet(Id holderId, Id ownerId) {
    AXF_OBJ_BankAccount__c result = new AXF_OBJ_BankAccount__c(
      OwnerId = ownerId,
      AXF_BA_LKP_Account__c = holderId,
      AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_BA_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BA_TXT_Type__c = 'WALLET',
      AXF_BA_NUM_Version__c = 1
    );
    insert result;
    return result;
  }

  private static ALT_CLS_RecurrenceService.CreateRequest create(
    Id accountId,
    Id bankAccountId,
    Date firstDueDate,
    Integer periodDays,
    Integer periodMonths,
    String key
  ) {
    ALT_CLS_RecurrenceService.CreateRequest request = new ALT_CLS_RecurrenceService.CreateRequest();
    request.accountId = accountId;
    request.description = 'Luz';
    request.direction = 'DEBIT';
    request.amount = 300;
    request.currencyIsoCode = 'BRL';
    request.firstDueDate = firstDueDate;
    request.periodDays = periodDays;
    request.periodMonths = periodMonths;
    request.bankAccountId = bankAccountId;
    request.operationKey = key;
    return request;
  }

  private static String failure(Callable call) {
    try {
      call.call('run', null);
    } catch (ALT_CLS_RecurrenceService.RecurrenceException expected) {
      return expected.getMessage();
    }
    return null;
  }

  private class CreateCall implements Callable {
    ALT_CLS_RecurrenceService.CreateRequest request;
    CreateCall(ALT_CLS_RecurrenceService.CreateRequest request) {
      this.request = request;
    }
    public Object call(String action, Map<String, Object> args) {
      return new ALT_CLS_RecurrenceService().create(request);
    }
  }

  private class DetailCall implements Callable {
    Id scheduleId;
    DetailCall(Id scheduleId) {
      this.scheduleId = scheduleId;
    }
    public Object call(String action, Map<String, Object> args) {
      ALT_CLS_RecurrenceService.DetailQuery query = new ALT_CLS_RecurrenceService.DetailQuery();
      query.scheduleId = scheduleId;
      return new ALT_CLS_RecurrenceService().detail(query);
    }
  }

  private class EditCall implements Callable {
    ALT_CLS_RecurrenceService.EditRequest request;
    EditCall(Id scheduleId, Decimal amount, Long version, String key) {
      request = new ALT_CLS_RecurrenceService.EditRequest();
      request.scheduleId = scheduleId;
      request.amount = amount;
      request.expectedVersion = version;
      request.operationKey = key;
    }
    public Object call(String action, Map<String, Object> args) {
      return new ALT_CLS_RecurrenceService().editAmount(request);
    }
  }

  private class TerminateCall implements Callable {
    ALT_CLS_RecurrenceService.TerminateRequest request;
    TerminateCall(Id scheduleId, Long version, String key) {
      request = new ALT_CLS_RecurrenceService.TerminateRequest();
      request.scheduleId = scheduleId;
      request.expectedVersion = version;
      request.operationKey = key;
    }
    public Object call(String action, Map<String, Object> args) {
      return new ALT_CLS_RecurrenceService().terminate(request);
    }
  }

  private class SourcesCall implements Callable {
    Id accountId;
    SourcesCall(Id accountId) {
      this.accountId = accountId;
    }
    public Object call(String action, Map<String, Object> args) {
      ALT_CLS_RecurrenceService.SourceQuery query = new ALT_CLS_RecurrenceService.SourceQuery();
      query.accountId = accountId;
      return new ALT_CLS_RecurrenceService().sources(query);
    }
  }

  // -------------------------------------------------------------- tests

  @IsTest
  static void createsAWeeklyRecurrenceListedWithItsOrigin() {
    User gestor = byAlias(GESTOR);
    System.runAs(gestor) {
      Account owner = holder('Holder 155 weekly', gestor.Id);
      AXF_OBJ_BankAccount__c cash = wallet(owner.Id, gestor.Id);
      Date first = Date.today().addDays(9);
      ALT_CLS_RecurrenceService service = new ALT_CLS_RecurrenceService();
      Assert.isTrue(service.canManage());
      Boolean listed = false;
      for (ALT_CLS_RecurrenceService.HolderOption option : service.holders()) {
        listed = listed || option.accountId == owner.Id;
      }
      Assert.isTrue(listed, 'o titular autorizado é oferecido');
      ALT_CLS_RecurrenceService.SourceQuery sourceQuery = new ALT_CLS_RecurrenceService.SourceQuery();
      sourceQuery.accountId = owner.Id;
      List<ALT_CLS_RecurrenceService.SourceOption> sources = service.sources(
        sourceQuery
      );
      Assert.areEqual(1, sources.size());
      Assert.areEqual('WALLET', sources[0].kind);

      Test.startTest();
      ALT_CLS_RecurrenceService.CommandResult created = service.create(
        create(owner.Id, cash.Id, first, 7, null, 'axf155-weekly')
      );
      ALT_CLS_RecurrenceService.CommandResult again = service.create(
        create(owner.Id, cash.Id, first, 7, null, 'axf155-weekly')
      );
      Test.stopTest();

      Assert.isNotNull(created.scheduleId);
      Assert.isTrue(created.changedCount > 1 && created.changedCount <= 50);
      Assert.isTrue(again.replay, 'o reenvio com a mesma chave é replay');
      Assert.areEqual(created.scheduleId, again.scheduleId);

      List<ALT_CLS_RecurrenceService.RecurrenceView> views = service.listRecurrences();
      Assert.areEqual(1, views.size());
      ALT_CLS_RecurrenceService.RecurrenceView view = views[0];
      Assert.areEqual('Luz', view.description);
      Assert.areEqual(7, view.periodDays);
      Assert.isNull(view.periodMonths);
      Assert.areEqual(300.00, view.amount);
      Assert.areEqual('DEBIT', view.direction);
      Assert.areEqual('BRL', view.currencyIsoCode);
      Assert.areEqual(cash.Id, view.bankAccountId);
      Assert.areEqual('WALLET', view.sourceKind);
      Assert.areEqual(System.Label.AXF_BankStatement_wallet, view.sourceLabel);
      Assert.areEqual(first, view.nextDueDate);
      Assert.areEqual('ACTIVE', view.state);
      Assert.areEqual(0, view.version);
      Assert.areEqual('Holder 155 weekly', view.holderLabel);

      ALT_CLS_RecurrenceService.DetailQuery query = new ALT_CLS_RecurrenceService.DetailQuery();
      query.scheduleId = created.scheduleId;
      ALT_CLS_RecurrenceService.DetailView detail = service.detail(query);
      Assert.areEqual(created.changedCount, detail.occurrences.size());
      for (Integer i = 0; i < detail.occurrences.size(); i++) {
        Assert.areEqual(first.addDays(7 * i), detail.occurrences[i].dueDate);
        Assert.areEqual('PLANNED', detail.occurrences[i].status);
        Assert.areEqual(300.00, detail.occurrences[i].amount);
      }
      for (AXF_OBJ_FinancialTransaction__c row : [
        SELECT AXF_FTX_LKP_BankAccount__c, AXF_FTX_TXT_Description__c
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE AXF_FTX_LKP_Schedule__c = :created.scheduleId
      ]) {
        Assert.areEqual(cash.Id, row.AXF_FTX_LKP_BankAccount__c);
        Assert.areEqual('Luz', row.AXF_FTX_TXT_Description__c);
      }
    }
  }

  @IsTest
  static void rejectsInvalidPeriodsAndOrigins() {
    User gestor = byAlias(GESTOR);
    User peer = byAlias(PEER);
    Account foreignHolder;
    AXF_OBJ_BankAccount__c foreignWallet;
    System.runAs(peer) {
      foreignHolder = holder('Holder 155 peer', peer.Id);
      foreignWallet = wallet(foreignHolder.Id, peer.Id);
    }
    System.runAs(gestor) {
      Account owner = holder('Holder 155 invalid', gestor.Id);
      AXF_OBJ_BankAccount__c cash = wallet(owner.Id, gestor.Id);
      Date first = Date.today().addDays(3);
      Assert.areEqual(
        'INVALID_INPUT',
        failure(
          new CreateCall(create(owner.Id, cash.Id, first, 10, null, 'k1'))
        ),
        'período de 10 dias'
      );
      Assert.areEqual(
        'INVALID_INPUT',
        failure(new CreateCall(create(owner.Id, cash.Id, first, 7, 1, 'k2'))),
        'as duas periodicidades'
      );
      Assert.areEqual(
        'INVALID_INPUT',
        failure(
          new CreateCall(create(owner.Id, cash.Id, first, null, null, 'k3'))
        ),
        'nenhuma periodicidade'
      );
      Assert.areEqual(
        'INVALID_INPUT',
        failure(new CreateCall(create(owner.Id, null, first, null, 1, 'k4'))),
        'sem origem'
      );
      Assert.areEqual(
        'INVALID_INPUT',
        failure(
          new CreateCall(
            create(owner.Id, foreignWallet.Id, first, null, 1, 'k5')
          )
        ),
        'origem de outro titular'
      );
      ALT_CLS_RecurrenceService.CreateRequest noName = create(
        owner.Id,
        cash.Id,
        first,
        null,
        1,
        'k6'
      );
      noName.description = ' ';
      Assert.areEqual('INVALID_INPUT', failure(new CreateCall(noName)));
      ALT_CLS_RecurrenceService.CreateRequest badAmount = create(
        owner.Id,
        cash.Id,
        first,
        null,
        1,
        'k7'
      );
      badAmount.amount = 0;
      Assert.areEqual('INVALID_INPUT', failure(new CreateCall(badAmount)));
      Assert.areEqual(
        'NOT_ACCESSIBLE',
        failure(
          new CreateCall(
            create(foreignHolder.Id, foreignWallet.Id, first, null, 1, 'k8')
          )
        )
      );
      Assert.areEqual(
        'NOT_ACCESSIBLE',
        failure(new SourcesCall(foreignHolder.Id))
      );
      Assert.areEqual('INVALID_INPUT', failure(new SourcesCall(null)));
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM AXF_OBJ_FinancialSchedule__c],
        'nada foi gravado'
      );
    }
  }

  @IsTest
  static void editAndTerminateOnlyTouchFutureUnrealizedOccurrences() {
    User gestor = byAlias(GESTOR);
    System.runAs(gestor) {
      Account owner = holder('Holder 155 edit', gestor.Id);
      AXF_OBJ_BankAccount__c cash = wallet(owner.Id, gestor.Id);
      ALT_CLS_RecurrenceService service = new ALT_CLS_RecurrenceService();
      ALT_CLS_RecurrenceService.CommandResult created = service.create(
        create(owner.Id, cash.Id, Date.today(), null, 1, 'axf155-monthly')
      );
      List<AXF_OBJ_FinancialTransaction__c> rows = [
        SELECT Id
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE AXF_FTX_LKP_Schedule__c = :created.scheduleId
        ORDER BY AXF_FTX_NUM_Sequence__c
      ];
      Assert.isTrue(rows.size() > 3);
      // A primeira ocorrência já foi conciliada: fica intocada. O fixture é gravado pelo
      // usuário do teste, fora da persona.
      System.runAs(new User(Id = UserInfo.getUserId())) {
        update new AXF_OBJ_FinancialTransaction__c(
          Id = rows[0].Id,
          AXF_FTX_PKL_Status__c = 'CONFIRMED'
        );
      }

      Test.startTest();
      ALT_CLS_RecurrenceService.EditRequest edit = new ALT_CLS_RecurrenceService.EditRequest();
      edit.scheduleId = created.scheduleId;
      edit.amount = 350;
      edit.expectedVersion = 0;
      edit.operationKey = 'axf155-edit';
      ALT_CLS_RecurrenceService.CommandResult edited = service.editAmount(edit);
      String stale = failure(
        new EditCall(created.scheduleId, 360, 0, 'axf155-edit-stale')
      );
      ALT_CLS_RecurrenceService.DetailQuery query = new ALT_CLS_RecurrenceService.DetailQuery();
      query.scheduleId = created.scheduleId;
      ALT_CLS_RecurrenceService.DetailView afterEdit = service.detail(query);
      Assert.areEqual(350.00, service.listRecurrences()[0].amount);

      ALT_CLS_RecurrenceService.TerminateRequest terminate = new ALT_CLS_RecurrenceService.TerminateRequest();
      terminate.scheduleId = created.scheduleId;
      terminate.expectedVersion = 1;
      terminate.operationKey = 'axf155-end';
      ALT_CLS_RecurrenceService.CommandResult ended = service.terminate(
        terminate
      );
      ALT_CLS_RecurrenceService.CommandResult replayed = service.terminate(
        terminate
      );
      Test.stopTest();

      Assert.areEqual(rows.size() - 1, edited.changedCount);
      Assert.areEqual('CONFLICT', stale, 'versão antiga');
      Assert.areEqual('RECONCILED', afterEdit.occurrences[0].status);
      Assert.areEqual(300.00, afterEdit.occurrences[0].amount);
      for (Integer i = 1; i < afterEdit.occurrences.size(); i++) {
        Assert.areEqual(350.00, afterEdit.occurrences[i].amount);
        Assert.areEqual('PLANNED', afterEdit.occurrences[i].status);
      }

      Assert.areEqual(rows.size() - 1, ended.changedCount);
      Assert.isTrue(replayed.replay);
      ALT_CLS_RecurrenceService.DetailView afterEnd = service.detail(query);
      Assert.areEqual('ENDED', afterEnd.recurrence.state);
      Assert.areEqual(Date.today(), afterEnd.recurrence.terminationDate);
      Assert.isNull(afterEnd.recurrence.nextDueDate);
      Assert.areEqual('RECONCILED', afterEnd.occurrences[0].status);
      for (Integer i = 1; i < afterEnd.occurrences.size(); i++) {
        Assert.areEqual('CANCELLED', afterEnd.occurrences[i].status);
      }
      Assert.areEqual(
        'CONFLICT',
        failure(new TerminateCall(created.scheduleId, 2, 'axf155-again')),
        'sem reativação nem reencerramento'
      );
    }
  }

  @IsTest
  static void participantReadsAndForeignIdsDiscloseNothing() {
    User gestor = byAlias(GESTOR);
    User reader = byAlias(READER);
    User peer = byAlias(PEER);
    Id scheduleId;
    System.runAs(gestor) {
      Account owner = holder('Holder 155 shared', gestor.Id);
      AXF_OBJ_BankAccount__c cash = wallet(owner.Id, gestor.Id);
      scheduleId = new ALT_CLS_RecurrenceService()
        .create(
          create(owner.Id, cash.Id, Date.today().addDays(2), 14, null, 'shared')
        )
        .scheduleId;
      insert new AccountShare(
        AccountId = owner.Id,
        UserOrGroupId = reader.Id,
        AccountAccessLevel = 'Read',
        OpportunityAccessLevel = 'None',
        CaseAccessLevel = 'None'
      );
    }
    System.runAs(new User(Id = UserInfo.getUserId())) {
      List<SObject> shares = new List<SObject>();
      shares.add(
        new AXF_OBJ_FinancialSchedule__Share(
          ParentId = scheduleId,
          UserOrGroupId = reader.Id,
          AccessLevel = 'Read',
          RowCause = 'Manual'
        )
      );
      for (AXF_OBJ_ScheduleDefinition__c definition : [
        SELECT Id
        FROM AXF_OBJ_ScheduleDefinition__c
        WHERE AXF_SDF_LKP_Schedule__c = :scheduleId
      ]) {
        shares.add(
          new AXF_OBJ_ScheduleDefinition__Share(
            ParentId = definition.Id,
            UserOrGroupId = reader.Id,
            AccessLevel = 'Read',
            RowCause = 'Manual'
          )
        );
      }
      for (AXF_OBJ_ScheduleReference__c reference : [
        SELECT Id
        FROM AXF_OBJ_ScheduleReference__c
        WHERE AXF_SRF_LKP_Schedule__c = :scheduleId
      ]) {
        shares.add(
          new AXF_OBJ_ScheduleReference__Share(
            ParentId = reference.Id,
            UserOrGroupId = reader.Id,
            AccessLevel = 'Read',
            RowCause = 'Manual'
          )
        );
      }
      for (AXF_OBJ_FinancialTransaction__c row : [
        SELECT Id
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE AXF_FTX_LKP_Schedule__c = :scheduleId
      ]) {
        shares.add(
          new AXF_OBJ_FinancialTransaction__Share(
            ParentId = row.Id,
            UserOrGroupId = reader.Id,
            AccessLevel = 'Read',
            RowCause = 'Manual'
          )
        );
      }
      insert shares;
    }
    System.runAs(reader) {
      ALT_CLS_RecurrenceService service = new ALT_CLS_RecurrenceService();
      Assert.isFalse(service.canManage(), 'Participante só lê');
      Assert.areEqual(1, service.listRecurrences().size());
      ALT_CLS_RecurrenceService.DetailQuery query = new ALT_CLS_RecurrenceService.DetailQuery();
      query.scheduleId = scheduleId;
      Assert.isFalse(service.detail(query).occurrences.isEmpty());
      Assert.areEqual(
        'NOT_ALLOWED',
        failure(new EditCall(scheduleId, 10, 0, 'reader-edit'))
      );
      Assert.areEqual(
        'NOT_ALLOWED',
        failure(new TerminateCall(scheduleId, 0, 'reader-end'))
      );
    }
    System.runAs(peer) {
      Assert.areEqual(
        0,
        new ALT_CLS_RecurrenceService().listRecurrences().size()
      );
      Assert.areEqual('NOT_ACCESSIBLE', failure(new DetailCall(scheduleId)));
      Assert.areEqual(
        'NOT_ACCESSIBLE',
        failure(new EditCall(scheduleId, 10, 0, 'peer-edit'))
      );
      Assert.areEqual(
        'NOT_ACCESSIBLE',
        failure(new TerminateCall(scheduleId, 0, 'peer-end'))
      );
      Assert.areEqual('INVALID_INPUT', failure(new DetailCall(null)));
    }
  }

  @IsTest
  static void createAndEndDatesStayInsideTheirWindows() {
    User gestor = byAlias(GESTOR);
    System.runAs(gestor) {
      Account owner = holder('Holder 155 windows', gestor.Id);
      AXF_OBJ_BankAccount__c cash = wallet(owner.Id, gestor.Id);
      Date monthStart = ALT_CLS_ScheduleCalendar.monthStart(Date.today());
      Assert.areEqual(
        'INVALID_INPUT',
        failure(
          new CreateCall(
            create(owner.Id, cash.Id, monthStart.addDays(-1), 7, null, 'w1')
          )
        ),
        'antes do mês corrente: nada retroage'
      );
      Assert.areEqual(
        'INVALID_INPUT',
        failure(
          new CreateCall(
            create(
              owner.Id,
              cash.Id,
              ALT_CLS_ScheduleCalendar.monthEndShifted(Date.today(), 10)
                .addDays(1),
              7,
              null,
              'w2'
            )
          )
        ),
        'além do horizonte semanal'
      );
      ALT_CLS_RecurrenceService.CreateRequest otherCurrency = create(
        owner.Id,
        cash.Id,
        Date.today(),
        null,
        1,
        'w3'
      );
      otherCurrency.currencyIsoCode = 'USD';
      Assert.areEqual(
        'INVALID_INPUT',
        failure(new CreateCall(otherCurrency)),
        'a moeda é a da origem'
      );

      ALT_CLS_RecurrenceService service = new ALT_CLS_RecurrenceService();
      ALT_CLS_RecurrenceService.CommandResult created = service.create(
        create(owner.Id, cash.Id, monthStart, 14, null, 'w4')
      );
      ALT_CLS_RecurrenceService.RecurrenceView view = service.listRecurrences()[0];
      Assert.isNotNull(view.lastDueDate);

      ALT_CLS_RecurrenceService.TerminateRequest past = new ALT_CLS_RecurrenceService.TerminateRequest();
      past.scheduleId = created.scheduleId;
      past.expectedVersion = 0;
      past.operationKey = 'w-past';
      past.terminationDate = Date.today().addDays(-1);
      Assert.areEqual(
        'INVALID_INPUT',
        failure(new TerminateRequestCall(past)),
        'o passado não é encerrado'
      );
      ALT_CLS_RecurrenceService.TerminateRequest beyond = new ALT_CLS_RecurrenceService.TerminateRequest();
      beyond.scheduleId = created.scheduleId;
      beyond.expectedVersion = 0;
      beyond.operationKey = 'w-beyond';
      beyond.terminationDate = view.lastDueDate.addDays(1);
      Assert.areEqual(
        'INVALID_INPUT',
        failure(new TerminateRequestCall(beyond)),
        'além da última ocorrência persistida'
      );
      ALT_CLS_RecurrenceService.TerminateRequest valid = new ALT_CLS_RecurrenceService.TerminateRequest();
      valid.scheduleId = created.scheduleId;
      valid.expectedVersion = 0;
      valid.operationKey = 'w-valid';
      valid.terminationDate = view.lastDueDate;
      Assert.areEqual(0, service.terminate(valid).changedCount);
      Assert.areEqual('ENDED', service.listRecurrences()[0].state);
    }
  }

  private class TerminateRequestCall implements Callable {
    ALT_CLS_RecurrenceService.TerminateRequest request;
    TerminateRequestCall(ALT_CLS_RecurrenceService.TerminateRequest request) {
      this.request = request;
    }
    public Object call(String action, Map<String, Object> args) {
      return new ALT_CLS_RecurrenceService().terminate(request);
    }
  }

  @IsTest
  static void statusAndOutcomeMappingsAreStable() {
    AXF_OBJ_FinancialTransaction__c open = new AXF_OBJ_FinancialTransaction__c(
      AXF_FTX_PKL_Status__c = 'PLANNED'
    );
    Assert.areEqual(
      'PLANNED',
      ALT_CLS_RecurrenceService.occurrenceStatus(open, 100, null)
    );
    Assert.areEqual(
      'PARTIAL',
      ALT_CLS_RecurrenceService.occurrenceStatus(open, 100, 40)
    );
    Assert.areEqual(
      'RECONCILED',
      ALT_CLS_RecurrenceService.occurrenceStatus(open, 100, 100)
    );
    open.AXF_FTX_PKL_ScheduleState__c = 'CANCELLED';
    Assert.areEqual(
      'CANCELLED',
      ALT_CLS_RecurrenceService.occurrenceStatus(open, 100, 100)
    );
    Map<String, String> expected = new Map<String, String>{
      'INVALID' => 'INVALID_INPUT',
      'UNSUPPORTED' => 'INVALID_INPUT',
      'TOO_LARGE' => 'TOO_LARGE',
      'FORBIDDEN' => 'NOT_ACCESSIBLE',
      'CONFLICT' => 'CONFLICT',
      'UNAVAILABLE' => 'UNAVAILABLE',
      'FAILED' => 'REJECTED'
    };
    for (String outcome : expected.keySet()) {
      try {
        ALT_CLS_RecurrenceService.requireSuccess(outcome);
        Assert.fail('desfecho sem sucesso: ' + outcome);
      } catch (ALT_CLS_RecurrenceService.RecurrenceException mapped) {
        Assert.areEqual(expected.get(outcome), mapped.getMessage());
      }
    }
    ALT_CLS_RecurrenceService.requireSuccess('CREATED');
  }
}
