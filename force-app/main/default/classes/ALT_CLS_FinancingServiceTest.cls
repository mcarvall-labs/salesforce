/**
 * @description AXF-156: financiamentos e parcelamentos. Lista com progresso e saldo devedor
 * (inclusive parcelas virtuais), detalhe com status, legados somente leitura, editar valor só do
 * parcelamento, cancelar e quitar antecipado afetando só parcelas futuras não realizadas;
 * Participante só lê; ID alheio não revela nada.
 */
@IsTest(isParallel=false)
private class ALT_CLS_FinancingServiceTest {
  private static final String GESTOR = 'axf156g';
  private static final String PEER = 'axf156p';
  private static final String READER = 'axf156r';
  private static final Date TODAY = Date.newInstance(2026, 9, 15);
  private static final Map<String, List<String>> READ_FIELDS = new Map<String, List<String>>{
    'AXF_OBJ_ScheduleDefinition__c' => new List<String>{
      'AXF_SDF_NUM_PeriodDays__c',
      'AXF_SDF_NUM_PeriodMonths__c',
      'AXF_SDF_TAL_InputCanonicalJson__c',
      'AXF_SDF_NUM_Principal__c',
      'AXF_SDF_NUM_PeriodRate__c',
      'AXF_SDF_NUM_FixedValue__c',
      'AXF_SDF_NUM_RecurringFee__c',
      'AXF_SDF_NUM_UpfrontFee__c',
      'AXF_SDF_NUM_TotalInstallments__c'
    },
    'AXF_OBJ_FinancialSchedule__c' => new List<String>{
      'AXF_FSC_LKP_ActiveDefinition__c',
      'AXF_FSC_LKP_Contract__c',
      'AXF_FSC_DAT_TerminationDate__c'
    },
    'AXF_OBJ_ScheduleChange__c' => new List<String>{
      'AXF_SCH_TAL_ResultJson__c'
    },
    'AXF_OBJ_FinancialTransaction__c' => new List<String>{
      'AXF_FTX_LKP_Schedule__c',
      'AXF_FTX_LKP_Contract__c',
      'AXF_FTX_NUM_Sequence__c',
      'AXF_FTX_DAT_DueDate__c',
      'AXF_FTX_NUM_CurrentBasis__c',
      'AXF_FTX_PKL_ScheduleState__c',
      'AXF_FTX_PKL_Modality__c',
      'AXF_FTX_NUM_PrincipalPortion__c',
      'AXF_FTX_NUM_InterestPortion__c',
      'AXF_FTX_NUM_ClosingBalance__c',
      'AXF_FTX_TXT_ScheduleGroupKey__c',
      'AXF_FTX_TXT_Description__c'
    }
  };

  private static User byAlias(String alias) {
    return [SELECT Id FROM User WHERE Alias = :alias LIMIT 1];
  }

  /** Check-only deploys do not apply the branch's permission-set changes to test users. */
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
    PermissionSet manage = mirror('AXF156_TestManage', true);
    PermissionSet read = mirror('AXF156_TestRead', false);
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

  private static Id financing(
    Id accountId,
    String method,
    Integer total,
    Decimal principal,
    Decimal rate,
    String description
  ) {
    ALT_CLS_FinancialScheduleService.CreateInput input = new ALT_CLS_FinancialScheduleService.CreateInput();
    input.accountId = accountId;
    input.direction = 'DEBIT';
    input.currencyIsoCode = 'BRL';
    input.method = method;
    input.totalInstallments = total;
    input.firstSequence = 1;
    input.firstDueDate = Date.newInstance(2026, 6, 15);
    input.periodMonths = 1;
    input.principal = principal;
    input.periodRate = rate;
    input.description = description;
    input.generationEnabled = true;
    input.legacyGroupKey = description;
    ALT_CLS_FinancialScheduleService.CreateResult created = ALT_CLS_FinancialScheduleService.createSchedule(
      input
    );
    Assert.areEqual('CREATED', created.outcome, created.message);
    return created.scheduleId;
  }

  /** Paid installments: CONFIRMED rows, written by the test user outside the persona. */
  private static void confirm(Id scheduleId, Integer throughSequence) {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      List<AXF_OBJ_FinancialTransaction__c> updates = new List<AXF_OBJ_FinancialTransaction__c>();
      for (AXF_OBJ_FinancialTransaction__c row : [
        SELECT Id
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE
          AXF_FTX_LKP_Schedule__c = :scheduleId
          AND AXF_FTX_NUM_Sequence__c <= :throughSequence
      ]) {
        updates.add(
          new AXF_OBJ_FinancialTransaction__c(
            Id = row.Id,
            AXF_FTX_PKL_Status__c = 'CONFIRMED'
          )
        );
      }
      update updates;
    }
  }

  private static void confirmOnly(Id scheduleId, Set<Integer> sequences) {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      List<AXF_OBJ_FinancialTransaction__c> updates = new List<AXF_OBJ_FinancialTransaction__c>();
      for (AXF_OBJ_FinancialTransaction__c row : [
        SELECT Id
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE
          AXF_FTX_LKP_Schedule__c = :scheduleId
          AND AXF_FTX_NUM_Sequence__c IN :sequences
      ]) {
        updates.add(
          new AXF_OBJ_FinancialTransaction__c(
            Id = row.Id,
            AXF_FTX_PKL_Status__c = 'CONFIRMED'
          )
        );
      }
      update updates;
    }
  }

  private static ALT_CLS_FinancingService.FinancingView find(Id scheduleId) {
    for (
      ALT_CLS_FinancingService.FinancingView view : new ALT_CLS_FinancingService()
        .listFinancings()
    ) {
      if (view.scheduleId == scheduleId) {
        return view;
      }
    }
    return null;
  }

  private static ALT_CLS_FinancingService.DetailView detailOf(Id scheduleId) {
    ALT_CLS_FinancingService.DetailQuery query = new ALT_CLS_FinancingService.DetailQuery();
    query.scheduleId = scheduleId;
    return new ALT_CLS_FinancingService().detail(query);
  }

  private static String failure(Callable call) {
    try {
      call.call('run', null);
    } catch (ALT_CLS_FinancingService.FinancingException expected) {
      return expected.getMessage();
    }
    return null;
  }

  private class EditCall implements Callable {
    ALT_CLS_FinancingService.EditRequest request = new ALT_CLS_FinancingService.EditRequest();
    EditCall(Id scheduleId, String legacyKey, Decimal amount, Long version) {
      request.scheduleId = scheduleId;
      request.legacyKey = legacyKey;
      request.amount = amount;
      request.expectedVersion = version;
      request.operationKey = 'edit-' + scheduleId + legacyKey + amount;
    }
    public Object call(String action, Map<String, Object> args) {
      return new ALT_CLS_FinancingService().editAmount(request);
    }
  }

  private class TerminateCall implements Callable {
    ALT_CLS_FinancingService.TerminateRequest request = new ALT_CLS_FinancingService.TerminateRequest();
    TerminateCall(Id scheduleId, Date terminationDate, Long version) {
      request.scheduleId = scheduleId;
      request.terminationDate = terminationDate;
      request.expectedVersion = version;
      request.operationKey = 'end-' + scheduleId + terminationDate;
    }
    public Object call(String action, Map<String, Object> args) {
      return new ALT_CLS_FinancingService().terminate(request);
    }
  }

  private class SettleCall implements Callable {
    ALT_CLS_FinancingService.SettleRequest request = new ALT_CLS_FinancingService.SettleRequest();
    SettleCall(
      Id scheduleId,
      Decimal amount,
      Date settlementDate,
      Long version
    ) {
      request.scheduleId = scheduleId;
      request.amount = amount;
      request.settlementDate = settlementDate;
      request.expectedVersion = version;
      request.operationKey = 'settle-' + scheduleId + amount + settlementDate;
    }
    public Object call(String action, Map<String, Object> args) {
      return new ALT_CLS_FinancingService().settle(request);
    }
  }

  private class DetailCall implements Callable {
    ALT_CLS_FinancingService.DetailQuery query = new ALT_CLS_FinancingService.DetailQuery();
    DetailCall(Id scheduleId, String legacyKey) {
      query.scheduleId = scheduleId;
      query.legacyKey = legacyKey;
    }
    public Object call(String action, Map<String, Object> args) {
      return new ALT_CLS_FinancingService().detail(query);
    }
  }

  // -------------------------------------------------------------- tests

  @IsTest
  static void listsProgressAndBalanceIncludingProjectedInstallments() {
    User gestor = byAlias(GESTOR);
    ALT_CLS_FinancialScheduleService.todayOverride = TODAY;
    Id price;
    Id installment;
    Id shortPlan;
    System.runAs(gestor) {
      Account owner = holder('Holder 156 list', gestor.Id);
      price = financing(owner.Id, 'PRICE', 12, 12000, 0.01, 'Carro');
      installment = financing(owner.Id, 'INSTALLMENT', 24, 2400, null, 'Sofa');
      shortPlan = financing(owner.Id, 'INSTALLMENT', 10, 1000, null, 'TV');
    }
    confirm(price, 3);
    confirm(installment, 4);
    confirm(shortPlan, 4);

    System.runAs(gestor) {
      Test.startTest();
      ALT_CLS_FinancingService.FinancingView priceView = find(price);
      ALT_CLS_FinancingService.FinancingView installmentView = find(
        installment
      );
      ALT_CLS_FinancingService.FinancingView shortView = find(shortPlan);
      ALT_CLS_FinancingService.DetailView detail = detailOf(installment);
      ALT_CLS_FinancingService.DetailView priceDetail = detailOf(price);
      Test.stopTest();

      Assert.areEqual('Carro', priceView.description);
      Assert.areEqual('PRICE', priceView.method);
      Assert.areEqual(3, priceView.paidCount);
      Assert.areEqual(12, priceView.totalInstallments);
      Assert.areEqual('ACTIVE', priceView.state);
      Assert.isTrue(priceView.canChange);
      Assert.isFalse(priceView.canEdit, 'PRICE não edita valor');
      Assert.areEqual(
        priceDetail.installments[2].closingBalance,
        priceView.outstandingBalance,
        'saldo = ClosingBalance da 3ª paga'
      );
      Assert.areEqual(Date.newInstance(2026, 9, 15), priceView.nextDueDate);
      Assert.areEqual(priceDetail.installments[3].amount, priceView.nextAmount);
      Assert.isNotNull(priceDetail.installments[0].interestPortion);

      Assert.areEqual(600.00, shortView.outstandingBalance, '10x100, 4 pagas');
      Assert.areEqual(4, shortView.paidCount);
      Assert.isTrue(shortView.canEdit);

      Assert.areEqual(24, detail.installments.size());
      Assert.areEqual(2000.00, installmentView.outstandingBalance);
      Integer projected = 0;
      for (
        ALT_CLS_FinancingService.InstallmentView line : detail.installments
      ) {
        if (line.projected) {
          projected++;
          Assert.isNull(line.transactionId);
          Assert.areEqual('PLANNED', line.status);
          Assert.areEqual(100.00, line.amount);
        }
      }
      Assert.isTrue(projected > 0, 'parcelas além da janela são virtuais');
      Assert.areEqual('PAID', detail.installments[0].status);
      Assert.areEqual('PLANNED', detail.installments[4].status);
      Assert.isNull(detail.installments[0].interestPortion);
    }
  }

  @IsTest
  static void editsInstallmentAmountButNotPriceAndKeepsPaidOnes() {
    User gestor = byAlias(GESTOR);
    ALT_CLS_FinancialScheduleService.todayOverride = TODAY;
    Id installment;
    Id price;
    System.runAs(gestor) {
      Account owner = holder('Holder 156 edit', gestor.Id);
      installment = financing(
        owner.Id,
        'INSTALLMENT',
        10,
        1000,
        null,
        'Geladeira'
      );
      price = financing(owner.Id, 'PRICE', 6, 6000, 0.01, 'Moto');
    }
    confirm(installment, 4);
    System.runAs(gestor) {
      Test.startTest();
      ALT_CLS_FinancingService.EditRequest request = new ALT_CLS_FinancingService.EditRequest();
      request.scheduleId = installment;
      request.amount = 120;
      request.expectedVersion = 0;
      request.operationKey = 'axf156-edit';
      ALT_CLS_FinancingService.CommandResult edited = new ALT_CLS_FinancingService()
        .editAmount(request);
      String stale = failure(new EditCall(installment, null, 130, 0));
      String onPrice = failure(new EditCall(price, null, 10, 0));
      Test.stopTest();

      Assert.areEqual(6, edited.changedCount, 'parcelas 5 a 10');
      Assert.areEqual('CONFLICT', stale);
      Assert.areEqual('NOT_ALLOWED', onPrice);
      ALT_CLS_FinancingService.DetailView detail = detailOf(installment);
      for (
        ALT_CLS_FinancingService.InstallmentView line : detail.installments
      ) {
        Assert.areEqual(
          line.sequence <= 4 ? 100.00 : 120.00,
          line.amount,
          'parcela ' + line.sequence
        );
      }
      Assert.areEqual(720.00, find(installment).outstandingBalance);
    }
  }

  @IsTest
  static void editedInstallmentAmountReachesProjectedInstallments() {
    User gestor = byAlias(GESTOR);
    ALT_CLS_FinancialScheduleService.todayOverride = TODAY;
    Id plan;
    System.runAs(gestor) {
      Account owner = holder('Holder 156 long edit', gestor.Id);
      plan = financing(owner.Id, 'INSTALLMENT', 24, 2400, null, 'Cozinha');
    }
    confirm(plan, 3);
    System.runAs(gestor) {
      Test.startTest();
      new ALT_CLS_FinancingService()
        .editAmount(new EditCall(plan, null, 120, 0).request);
      Test.stopTest();
      ALT_CLS_FinancingService.DetailView detail = detailOf(plan);
      Assert.areEqual(24, detail.installments.size());
      Integer projected = 0;
      for (
        ALT_CLS_FinancingService.InstallmentView line : detail.installments
      ) {
        Assert.areEqual(
          line.sequence <= 3 ? 100.00 : 120.00,
          line.amount,
          'parcela ' + line.sequence
        );
        if (line.projected) {
          projected++;
        }
      }
      Assert.isTrue(projected > 0);
      Assert.areEqual(21 * 120.00, find(plan).outstandingBalance);
    }
  }

  @IsTest
  static void settlesEarlyWithoutChargingTheSameDayInstallmentTwice() {
    User gestor = byAlias(GESTOR);
    ALT_CLS_FinancialScheduleService.todayOverride = TODAY;
    Id price;
    Id other;
    System.runAs(gestor) {
      Account owner = holder('Holder 156 settle', gestor.Id);
      price = financing(owner.Id, 'PRICE', 12, 12000, 0.01, 'Carro quitado');
      other = financing(owner.Id, 'SAC', 12, 12000, 0.01, 'Casa');
    }
    confirm(price, 3);
    System.runAs(gestor) {
      ALT_CLS_FinancingService service = new ALT_CLS_FinancingService();
      List<ALT_CLS_FinancingService.InstallmentView> lines = detailOf(price)
        .installments;
      ALT_CLS_FinancingService.SettlementQuery query = new ALT_CLS_FinancingService.SettlementQuery();
      query.scheduleId = price;
      ALT_CLS_FinancingService.SettlementPreview preview = service.settlementPreview(
        query
      );
      ALT_CLS_FinancingService.FinancingView before = find(price);
      Assert.areEqual(
        lines[2].closingBalance,
        before.outstandingBalance,
        'saldo = ClosingBalance da parcela anterior à primeira não paga'
      );
      Assert.areEqual(
        lines[3].closingBalance,
        preview.suggestedAmount,
        'a 4ª vence na data e continua devida: não entra de novo na quitação'
      );
      Assert.areEqual(TODAY, preview.minDate);
      Assert.areEqual(TODAY, preview.maxDate);
      Assert.areEqual(TODAY, preview.settlementDate);

      Test.startTest();
      Assert.areEqual(
        'INVALID_INPUT',
        failure(new SettleCall(price, 0, TODAY, 0)),
        'valor ≤ 0'
      );
      Assert.areEqual(
        'INVALID_INPUT',
        failure(new SettleCall(price, 100, TODAY.addDays(1), 0)),
        'além do próximo vencimento não pago'
      );
      SettleCall payoff = new SettleCall(
        price,
        preview.suggestedAmount,
        TODAY,
        0
      );
      ALT_CLS_FinancingService.CommandResult settled = service.settle(
        payoff.request
      );
      ALT_CLS_FinancingService.CommandResult retried = service.settle(
        payoff.request
      );
      Assert.areEqual(
        'INVALID_INPUT',
        failure(new TerminateCall(other, TODAY.addDays(-1), 0)),
        'cancelar no passado'
      );
      TerminateCall ending = new TerminateCall(other, TODAY, 0);
      ALT_CLS_FinancingService.CommandResult ended = service.terminate(
        ending.request
      );
      ALT_CLS_FinancingService.CommandResult endRetried = service.terminate(
        ending.request
      );
      Test.stopTest();

      Assert.isNotNull(settled.settlementTransactionId);
      Assert.areEqual(8, settled.changedCount);
      Assert.isTrue(retried.replay, 'reenvio após encerrar é replay');
      Assert.areEqual(
        settled.settlementTransactionId,
        retried.settlementTransactionId
      );
      Assert.isTrue(endRetried.replay);
      ALT_CLS_FinancingService.FinancingView after = find(price);
      Assert.areEqual('SETTLED', after.state);
      Assert.areEqual(
        lines[3].amount,
        after.outstandingBalance,
        'só a 4ª, que vence na data, continua devida'
      );
      Assert.areEqual(TODAY, after.nextDueDate);
      Assert.areEqual(
        settled.settlementTransactionId,
        after.settlementTransactionId
      );
      Assert.isFalse(after.canChange);
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM AXF_OBJ_FinancialTransaction__c
          WHERE Id = :settled.settlementTransactionId
        ]
      );
      for (
        ALT_CLS_FinancingService.InstallmentView line : detailOf(price)
          .installments
      ) {
        String expected = line.sequence <= 3
          ? 'PAID'
          : (line.sequence == 4 ? 'PLANNED' : 'CANCELLED');
        Assert.areEqual(expected, line.status, 'parcela ' + line.sequence);
      }
      Assert.areEqual('ENDED', find(other).state);
      Assert.isTrue(ended.changedCount > 0);
      Assert.areEqual(
        'NOT_ALLOWED',
        failure(new SettleCall(price, 10, TODAY, 1)),
        'sem reativação'
      );
    }
  }

  @IsTest
  static void settlementKeepsOverdueUnpaidInstallmentsOutOfThePayoff() {
    User gestor = byAlias(GESTOR);
    ALT_CLS_FinancialScheduleService.todayOverride = TODAY;
    Id price;
    System.runAs(gestor) {
      Account owner = holder('Holder 156 overdue', gestor.Id);
      price = financing(owner.Id, 'PRICE', 12, 12000, 0.01, 'Carro atrasado');
    }
    confirm(price, 2);
    System.runAs(gestor) {
      ALT_CLS_FinancingService service = new ALT_CLS_FinancingService();
      List<ALT_CLS_FinancingService.InstallmentView> lines = detailOf(price)
        .installments;
      ALT_CLS_FinancingService.SettlementQuery query = new ALT_CLS_FinancingService.SettlementQuery();
      query.scheduleId = price;
      query.settlementDate = TODAY;
      ALT_CLS_FinancingService.SettlementPreview preview = service.settlementPreview(
        query
      );
      Assert.areEqual(lines[1].closingBalance, find(price).outstandingBalance);
      Assert.areEqual(lines[3].closingBalance, preview.suggestedAmount);

      Test.startTest();
      ALT_CLS_FinancingService.CommandResult settled = service.settle(
        new SettleCall(price, preview.suggestedAmount, TODAY, 0).request
      );
      Test.stopTest();

      Assert.areEqual(8, settled.changedCount);
      ALT_CLS_FinancingService.FinancingView after = find(price);
      Assert.areEqual('SETTLED', after.state);
      Assert.areEqual(
        lines[2].amount + lines[3].amount,
        after.outstandingBalance,
        'a 3ª vencida e a 4ª do dia continuam devidas'
      );
      Assert.areEqual(lines[2].dueDate, after.nextDueDate);
    }
  }

  @IsTest
  static void settlesAnInstallmentPlanWithTheInstallmentsAfterTheDate() {
    User gestor = byAlias(GESTOR);
    ALT_CLS_FinancialScheduleService.todayOverride = TODAY;
    Id plan;
    Id sac;
    System.runAs(gestor) {
      Account owner = holder('Holder 156 settle plan', gestor.Id);
      plan = financing(owner.Id, 'INSTALLMENT', 10, 1000, null, 'Sofa');
      sac = financing(owner.Id, 'SAC', 12, 12000, 0.01, 'Terreno');
    }
    confirm(plan, 4);
    confirm(sac, 3);
    confirmOnly(sac, new Set<Integer>{ 6 });
    System.runAs(gestor) {
      ALT_CLS_FinancingService service = new ALT_CLS_FinancingService();
      ALT_CLS_FinancingService.FinancingView sacView = find(sac);
      Assert.areEqual(4, sacView.paidCount, '1-3 e a 6ª antecipada');
      Assert.areEqual(
        9000.00,
        sacView.outstandingBalance,
        'saldo antes da primeira não paga (4ª), mesmo com a 6ª paga'
      );
      Assert.areEqual('SAC', sacView.method);

      Date october = Date.newInstance(2026, 10, 15);
      ALT_CLS_FinancingService.SettlementQuery query = new ALT_CLS_FinancingService.SettlementQuery();
      query.scheduleId = plan;
      query.settlementDate = october;
      ALT_CLS_FinancingService.SettlementPreview preview = service.settlementPreview(
        query
      );
      Assert.areEqual(october, preview.maxDate);
      Assert.areEqual(500.00, preview.suggestedAmount, 'parcelas 6 a 10');

      Test.startTest();
      ALT_CLS_FinancingService.CommandResult settled = service.settle(
        new SettleCall(plan, 500, october, 0).request
      );
      Test.stopTest();

      Assert.areEqual(5, settled.changedCount);
      ALT_CLS_FinancingService.FinancingView after = find(plan);
      Assert.areEqual('SETTLED', after.state);
      Assert.areEqual(100.00, after.outstandingBalance, 'a 5ª continua devida');
      Assert.areEqual(october, after.nextDueDate);
    }
  }

  @IsTest
  static void legacyGroupsAreReadOnlyWithProgress() {
    User gestor = byAlias(GESTOR);
    Account owner;
    System.runAs(gestor) {
      owner = holder('Holder 156 legacy', gestor.Id);
    }
    System.runAs(new User(Id = UserInfo.getUserId())) {
      List<AXF_OBJ_FinancialTransaction__c> rows = new List<AXF_OBJ_FinancialTransaction__c>();
      for (Integer sequence = 1; sequence <= 4; sequence++) {
        rows.add(
          new AXF_OBJ_FinancialTransaction__c(
            OwnerId = gestor.Id,
            AXF_FTX_LKP_Account__c = owner.Id,
            AXF_FTX_PKL_Direction__c = 'DEBIT',
            AXF_FTX_NUM_Magnitude__c = 300,
            AXF_FTX_TXT_CurrencyIsoCode__c = 'BRL',
            AXF_FTX_DAT_DueDate__c = TODAY.addMonths(sequence - 2),
            AXF_FTX_DAT_PurchaseDate__c = TODAY.addMonths(sequence - 2),
            AXF_FTX_PKL_Status__c = sequence == 1 ? 'CONFIRMED' : 'PLANNED',
            AXF_FTX_EXI_ClientRequestId__c = 'gk-legacy-156-' + sequence,
            AXF_FTX_TXT_ScheduleGroupKey__c = 'gk-legacy-156',
            AXF_FTX_NUM_Sequence__c = sequence,
            AXF_FTX_PKL_Modality__c = 'SAC',
            AXF_FTX_NUM_PrincipalPortion__c = 250,
            AXF_FTX_NUM_InterestPortion__c = 50,
            AXF_FTX_NUM_ClosingBalance__c = 1000 - 250 * sequence
          )
        );
      }
      insert rows;
    }
    System.runAs(gestor) {
      ALT_CLS_FinancingService.FinancingView legacy;
      for (
        ALT_CLS_FinancingService.FinancingView view : new ALT_CLS_FinancingService()
          .listFinancings()
      ) {
        if (view.legacy) {
          legacy = view;
        }
      }
      Assert.isNotNull(legacy);
      Assert.areEqual('gk-legacy-156', legacy.legacyKey);
      Assert.areEqual(1, legacy.paidCount);
      Assert.areEqual(4, legacy.totalInstallments);
      Assert.areEqual(750.00, legacy.outstandingBalance);
      Assert.isFalse(legacy.canChange);
      ALT_CLS_FinancingService.DetailView detail = (ALT_CLS_FinancingService.DetailView) new DetailCall(
          null,
          'gk-legacy-156'
        )
        .call('run', null);
      Assert.areEqual(4, detail.installments.size());
      Assert.areEqual('PAID', detail.installments[0].status);
      Assert.areEqual(
        'NOT_ALLOWED',
        failure(new EditCall(null, 'gk-legacy-156', 10, 0))
      );
      Assert.areEqual(
        'NOT_ACCESSIBLE',
        failure(new EditCall(null, 'gk-unknown', 10, 0))
      );
      Assert.areEqual(
        'INVALID_INPUT',
        failure(new DetailCall(null, null)),
        'nem cronograma nem chave'
      );
    }
  }

  @IsTest
  static void participantReadsAndForeignIdsDiscloseNothing() {
    User gestor = byAlias(GESTOR);
    User reader = byAlias(READER);
    User peer = byAlias(PEER);
    ALT_CLS_FinancialScheduleService.todayOverride = TODAY;
    Id scheduleId;
    System.runAs(gestor) {
      Account owner = holder('Holder 156 shared', gestor.Id);
      scheduleId = financing(owner.Id, 'SAC', 6, 600, 0.01, 'Notebook');
      insert new AccountShare(
        AccountId = owner.Id,
        UserOrGroupId = reader.Id,
        AccountAccessLevel = 'Read',
        OpportunityAccessLevel = 'None',
        CaseAccessLevel = 'None'
      );
    }
    System.runAs(new User(Id = UserInfo.getUserId())) {
      List<SObject> shares = new List<SObject>{
        new AXF_OBJ_FinancialSchedule__Share(
          ParentId = scheduleId,
          UserOrGroupId = reader.Id,
          AccessLevel = 'Read',
          RowCause = 'Manual'
        )
      };
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
      ALT_CLS_FinancingService service = new ALT_CLS_FinancingService();
      Assert.isFalse(service.canManage(), 'Participante só lê');
      ALT_CLS_FinancingService.FinancingView view = find(scheduleId);
      Assert.isNotNull(view);
      Assert.isFalse(view.canChange);
      Assert.areEqual(6, detailOf(scheduleId).installments.size());
      Assert.areEqual(
        'NOT_ALLOWED',
        failure(new TerminateCall(scheduleId, TODAY, 0))
      );
      Assert.areEqual(
        'NOT_ALLOWED',
        failure(new SettleCall(scheduleId, 10, TODAY, 0))
      );
    }
    System.runAs(peer) {
      Assert.isNull(find(scheduleId));
      Assert.areEqual(
        'NOT_ACCESSIBLE',
        failure(new DetailCall(scheduleId, null))
      );
      Assert.areEqual(
        'NOT_ACCESSIBLE',
        failure(new SettleCall(scheduleId, 10, TODAY, 0))
      );
    }
  }

  @IsTest
  static void statusAndOutcomeMappingsAreStable() {
    AXF_OBJ_FinancialTransaction__c open = new AXF_OBJ_FinancialTransaction__c(
      AXF_FTX_PKL_Status__c = 'PLANNED'
    );
    Assert.areEqual(
      'PLANNED',
      ALT_CLS_FinancingService.installmentStatus(open, 100, null)
    );
    Assert.areEqual(
      'PARTIAL',
      ALT_CLS_FinancingService.installmentStatus(open, 100, 40)
    );
    Assert.areEqual(
      'PAID',
      ALT_CLS_FinancingService.installmentStatus(open, 100, 100)
    );
    open.AXF_FTX_PKL_Status__c = 'CONFIRMED';
    Assert.areEqual(
      'PAID',
      ALT_CLS_FinancingService.installmentStatus(open, 100, null)
    );
    open.AXF_FTX_PKL_ScheduleState__c = 'CANCELLED';
    Assert.areEqual(
      'CANCELLED',
      ALT_CLS_FinancingService.installmentStatus(open, 100, 100)
    );
    Map<String, String> expected = new Map<String, String>{
      'INVALID' => 'INVALID_INPUT',
      'UNSUPPORTED' => 'NOT_ALLOWED',
      'FORBIDDEN' => 'NOT_ACCESSIBLE',
      'NOT_FOUND' => 'NOT_ACCESSIBLE',
      'CONFLICT' => 'CONFLICT',
      'UNAVAILABLE' => 'UNAVAILABLE',
      'FAILED' => 'REJECTED'
    };
    for (String outcome : expected.keySet()) {
      try {
        ALT_CLS_FinancingService.requireSuccess(outcome);
        Assert.fail('desfecho sem sucesso: ' + outcome);
      } catch (ALT_CLS_FinancingService.FinancingException mapped) {
        Assert.areEqual(expected.get(outcome), mapped.getMessage());
      }
    }
    ALT_CLS_FinancingService.requireSuccess('TERMINATED');
  }
}
