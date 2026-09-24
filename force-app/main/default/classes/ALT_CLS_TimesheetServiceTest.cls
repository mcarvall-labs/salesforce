/**
 * @description AXF-157: timesheet over the AXF-56 WorkRecord engine — hours from clock times with
 * the active term's rate, idempotent resubmission, distinct shifts, eligibility and authorized
 * context, submission, filtered listing with billing status and the monthly revenue forecast per
 * destination account. Users hold only a mirror permission set created here, independent of the
 * shared org permission sets.
 */
@IsTest
// API 62: AXON_DEV enforces FLS on plain test DML under runAs from API 67 onwards.
private class ALT_CLS_TimesheetServiceTest {
  private static final Date DAY = Date.newInstance(2026, 9, 10);
  /** Fixed "today" of the service so the tests never depend on the run date. */
  private static final Date TODAY = Date.newInstance(2026, 9, 30);
  /** EffectiveTo of the next term created by contract(); consumed once. */
  private static Date nextTermEffectiveTo;

  private class Fixture {
    Account holder;
    Id counterpartyId;
    Id relationshipId;
    AXF_OBJ_BankAccount__c bank;
  }

  private static User byAlias(String alias) {
    return [SELECT Id FROM User WHERE Alias = :alias LIMIT 1];
  }

  @TestSetup
  static void setup() {
    Id profileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
    .Id;
    List<User> users = new List<User>();
    for (String alias : new List<String>{ 'axf157a', 'axf157o', 'axf157r' }) {
      users.add(
        new User(
          Alias = alias,
          Email = alias + '@example.invalid',
          EmailEncodingKey = 'UTF-8',
          LastName = 'User ' + alias,
          LanguageLocaleKey = 'en_US',
          LocaleSidKey = 'en_US',
          TimeZoneSidKey = 'America/Sao_Paulo',
          ProfileId = profileId,
          Username = alias + '.' + System.now().getTime() + '@example.invalid'
        )
      );
    }
    insert users;
    Id mirror = mirrorPermissionSet('AXF157_TimesheetMirror', true);
    insert new List<PermissionSetAssignment>{
      new PermissionSetAssignment(
        AssigneeId = users[2].Id,
        PermissionSetId = mirrorPermissionSet(
          'AXF157_TimesheetReadMirror',
          false
        )
      ),
      new PermissionSetAssignment(
        AssigneeId = users[0].Id,
        PermissionSetId = mirror
      ),
      new PermissionSetAssignment(
        AssigneeId = users[1].Id,
        PermissionSetId = mirror
      )
    };
  }

  /** Read access the timesheet needs plus, when writable, WorkRecord create/edit; nothing else. */
  private static Id mirrorPermissionSet(String psName, Boolean writable) {
    PermissionSet mirror = new PermissionSet(Name = psName, Label = psName);
    insert mirror;
    List<ObjectPermissions> objects = new List<ObjectPermissions>();
    for (
      String name : new List<String>{
        'AXF_OBJ_Contract__c',
        'AXF_OBJ_ContractTermVersion__c',
        'AXF_OBJ_BankAccount__c'
      }
    ) {
      objects.add(
        new ObjectPermissions(
          ParentId = mirror.Id,
          SobjectType = name,
          PermissionsRead = true
        )
      );
    }
    objects.add(
      new ObjectPermissions(
        ParentId = mirror.Id,
        SobjectType = 'AXF_OBJ_WorkRecord__c',
        PermissionsRead = true,
        PermissionsCreate = writable,
        PermissionsEdit = writable
      )
    );
    insert objects;
    List<FieldPermissions> fields = new List<FieldPermissions>();
    for (
      String field : new List<String>{
        'AXF_OBJ_Contract__c.AXF_CTR_LKP_ActiveTermVersion__c',
        'AXF_OBJ_Contract__c.AXF_CTR_DAT_StartDate__c',
        'AXF_OBJ_Contract__c.AXF_CTR_DAT_EndDate__c',
        'AXF_OBJ_Contract__c.AXF_CTR_DAT_TerminationEffectiveDate__c',
        'AXF_OBJ_ContractTermVersion__c.AXF_CTV_DAT_EffectiveTo__c',
        'AXF_OBJ_WorkRecord__c.AXF_WR_LKP_TermVersion__c',
        'AXF_OBJ_ContractTermVersion__c.AXF_CTV_CUR_Rate__c',
        'AXF_OBJ_ContractTermVersion__c.AXF_CTV_LKP_PreferredBankAccount__c',
        'AXF_OBJ_BankAccount__c.AXF_BA_TXT_InstitutionName__c',
        'AXF_OBJ_BankAccount__c.AXF_BA_TXT_NumberMasked__c',
        'AXF_OBJ_BankAccount__c.AXF_BA_TXT_Type__c',
        'AXF_OBJ_WorkRecord__c.AXF_WR_TXT_Description__c'
      }
    ) {
      fields.add(
        new FieldPermissions(
          ParentId = mirror.Id,
          SobjectType = field.substringBefore('.'),
          Field = field,
          PermissionsRead = true,
          PermissionsEdit = writable &&
            field == 'AXF_OBJ_WorkRecord__c.AXF_WR_TXT_Description__c'
        )
      );
    }
    insert fields;
    return mirror.Id;
  }

  // ---------------------------------------------------------------- fixture

  private static Fixture fixture(String name) {
    Fixture f = new Fixture();
    f.holder = new Account(
      Name = name,
      RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
        .get('AXF_Business')
        .getRecordTypeId()
    );
    insert f.holder;
    AXF_OBJ_Counterparty__c cpty = new AXF_OBJ_Counterparty__c(
      Name = 'Cliente ' + name,
      AXF_CPTY_TXT_DisplayName__c = 'Cliente ' + name,
      AXF_CPTY_TXT_LegalName__c = 'Cliente ' + name + ' LTDA',
      AXF_CPTY_TXT_Country__c = 'BR',
      AXF_CPTY_PKL_Kind__c = 'ORGANIZATION',
      AXF_CPTY_PKL_Status__c = 'ACTIVE',
      AXF_CPTY_EXI_CounterpartyKey__c = AXF_CLS_IdentityFraming.key(
        new List<Object>{ 'CPTY', 'Cliente ' + name + ' LTDA', 'BR' }
      ),
      AXF_CPTY_NUM_Version__c = 1
    );
    insert cpty;
    f.counterpartyId = cpty.Id;
    AXF_OBJ_CounterpartyEntityRelationship__c rel = new AXF_OBJ_CounterpartyEntityRelationship__c(
      AXF_CER_LKP_Counterparty__c = cpty.Id,
      AXF_CER_LKP_Account__c = f.holder.Id,
      AXF_CER_PKL_Role__c = 'CLIENT',
      AXF_CER_PKL_Status__c = 'ACTIVE',
      AXF_CER_TXT_EntitySpecificDisplay__c = name,
      AXF_CER_EXI_RelationshipKey__c = AXF_CLS_IdentityFraming.key(
        new List<Object>{ 'CER', cpty.Id, f.holder.Id, 'CLIENT' }
      ),
      AXF_CER_NUM_Version__c = 1
    );
    insert rel;
    f.relationshipId = rel.Id;
    f.bank = new AXF_OBJ_BankAccount__c(
      AXF_BA_LKP_Account__c = f.holder.Id,
      AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_BA_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BA_TXT_Type__c = 'CHECKING',
      AXF_BA_TXT_InstitutionName__c = 'Banco A',
      AXF_BA_TXT_NumberMasked__c = '****1234',
      AXF_BA_NUM_Version__c = 1
    );
    insert f.bank;
    return f;
  }

  private static AXF_OBJ_Contract__c contract(
    Fixture f,
    String code,
    String type,
    String lifecycle,
    String model,
    Decimal rate,
    String iso,
    Id destination
  ) {
    AXF_OBJ_Contract__c ctr = new AXF_OBJ_Contract__c(
      AXF_CTR_LKP_Account__c = f.holder.Id,
      AXF_CTR_LKP_Relationship__c = f.relationshipId,
      AXF_CTR_LKP_Counterparty__c = f.counterpartyId,
      AXF_CTR_TXT_ContractCode__c = code,
      AXF_CTR_EXI_ContractKey__c = AXF_CLS_IdentityFraming.key(
        new List<Object>{ 'CONTRACT', f.holder.Id, code }
      ),
      AXF_CTR_TXT_Title__c = 'Servico ' + code,
      AXF_CTR_PKL_Lifecycle__c = lifecycle,
      AXF_CTR_PKL_Type__c = type,
      AXF_CTR_TXT_CurrencyIsoCode__c = iso,
      AXF_CTR_DAT_StartDate__c = Date.newInstance(2026, 1, 1),
      AXF_CTR_NUM_Version__c = 1
    );
    insert ctr;
    AXF_OBJ_ContractTermVersion__c term = new AXF_OBJ_ContractTermVersion__c(
      AXF_CTV_LKP_Contract__c = ctr.Id,
      AXF_CTV_NUM_Revision__c = 1,
      AXF_CTV_PKL_Status__c = 'ACTIVE',
      AXF_CTV_PKL_RemunerationModel__c = model,
      AXF_CTV_TXT_CurrencyIsoCode__c = iso,
      AXF_CTV_DAT_EffectiveFrom__c = Date.newInstance(2026, 1, 1),
      AXF_CTV_CUR_Rate__c = rate,
      AXF_CTV_DAT_EffectiveTo__c = nextTermEffectiveTo,
      AXF_CTV_CUR_ContractedAmount__c = 1000,
      AXF_CTV_LKP_PreferredBankAccount__c = destination,
      AXF_CTV_EXI_TermKey__c = 'TERM-' + code,
      AXF_CTV_NUM_Version__c = 1
    );
    insert term;
    nextTermEffectiveTo = null;
    ctr.AXF_CTR_LKP_ActiveTermVersion__c = term.Id;
    update ctr;
    return ctr;
  }

  private static AXF_OBJ_Contract__c serviceContract(Fixture f, String code) {
    return contract(
      f,
      code,
      'REVENUE',
      'ACTIVE',
      'HOURLY',
      150,
      'BRL',
      f.bank.Id
    );
  }

  private static ALT_CLS_TimesheetService.EntryRequest entry(
    Id contractId,
    String startTime,
    String breakStart,
    String breakEnd,
    String endTime
  ) {
    ALT_CLS_TimesheetService.EntryRequest request = new ALT_CLS_TimesheetService.EntryRequest();
    request.contractId = contractId;
    request.workDate = DAY;
    request.startTime = startTime;
    request.breakStart = breakStart;
    request.breakEnd = breakEnd;
    request.endTime = endTime;
    return request;
  }

  private static String failureOf(
    ALT_CLS_TimesheetService.EntryRequest request
  ) {
    try {
      new ALT_CLS_TimesheetService().register(request);
      return null;
    } catch (ALT_CLS_TimesheetService.TimesheetException failure) {
      return failure.getMessage();
    }
  }

  private static String submitFailure(Id workRecordId) {
    ALT_CLS_TimesheetService.SubmitRequest request = new ALT_CLS_TimesheetService.SubmitRequest();
    request.workRecordId = workRecordId;
    try {
      new ALT_CLS_TimesheetService().submit(request);
      return null;
    } catch (ALT_CLS_TimesheetService.TimesheetException failure) {
      return failure.getMessage();
    }
  }

  private static ALT_CLS_TimesheetService.EntryResult submit(Id workRecordId) {
    ALT_CLS_TimesheetService.SubmitRequest request = new ALT_CLS_TimesheetService.SubmitRequest();
    request.workRecordId = workRecordId;
    return new ALT_CLS_TimesheetService().submit(request);
  }

  private static Id approved(Id contractId, Date day, Decimal hours) {
    ALT_CLS_WorkRecordService engine = new ALT_CLS_WorkRecordService();
    Id id = work(contractId, day, hours);
    engine.submitWorkRecord(id);
    engine.decideWorkRecord(id, true, 'OK');
    return id;
  }

  /** A WorkRecord registered outside this screen (free description, contract rate 150/BRL). */
  private static Id work(Id contractId, Date day, Decimal hours) {
    AXF_OBJ_Contract__c ctr = [
      SELECT
        AXF_CTR_LKP_ActiveTermVersion__r.AXF_CTV_CUR_Rate__c,
        AXF_CTR_LKP_ActiveTermVersion__r.AXF_CTV_TXT_CurrencyIsoCode__c
      FROM AXF_OBJ_Contract__c
      WHERE Id = :contractId
    ];
    ALT_CLS_WorkRecordService.WorkRecordInputDTO input = new ALT_CLS_WorkRecordService.WorkRecordInputDTO();
    input.contractId = contractId;
    input.startDate = day;
    input.endDate = day;
    input.quantity = hours;
    input.rate = ctr.AXF_CTR_LKP_ActiveTermVersion__r.AXF_CTV_CUR_Rate__c;
    input.currencyIsoCode = ctr.AXF_CTR_LKP_ActiveTermVersion__r.AXF_CTV_TXT_CurrencyIsoCode__c;
    input.source = 'API';
    input.description = 'Legacy entry';
    return new ALT_CLS_WorkRecordService()
      .registerWorkRecord(input)
      .workRecordId;
  }

  private static ALT_CLS_TimesheetService.ListView listOf(
    Id contractId,
    String billingStatus,
    String recordStatus
  ) {
    ALT_CLS_TimesheetService.ListQuery query = new ALT_CLS_TimesheetService.ListQuery();
    query.year = DAY.year();
    query.month = DAY.month();
    query.contractId = contractId;
    query.billingStatus = billingStatus;
    query.recordStatus = recordStatus;
    return new ALT_CLS_TimesheetService().entries(query);
  }

  private static ALT_CLS_TimesheetService.ForecastView forecast(
    String destination
  ) {
    ALT_CLS_TimesheetService.ForecastQuery query = new ALT_CLS_TimesheetService.ForecastQuery();
    query.year = DAY.year();
    query.month = DAY.month();
    query.destination = destination;
    return new ALT_CLS_TimesheetService().forecast(query);
  }

  // ------------------------------------------------------------------ tests

  @IsTest
  static void registersDayFromClockTimesWithActiveTermRate() {
    System.runAs(byAlias('axf157a')) {
      Fixture f = fixture('Titular 157');
      AXF_OBJ_Contract__c ctr = serviceContract(f, 'SVC-1');
      work(ctr.Id, DAY, 1);
      ALT_CLS_TimesheetService.todayOverride = TODAY;
      ALT_CLS_TimesheetService.EntryRequest full = entry(
        ctr.Id,
        '08:00',
        '12:00',
        '13:00',
        '17:30'
      );
      full.note = ' Sprint review ';

      Test.startTest();
      ALT_CLS_TimesheetService.EntryResult created = new ALT_CLS_TimesheetService()
        .register(full);
      ALT_CLS_TimesheetService.EntryResult replay = new ALT_CLS_TimesheetService()
        .register(full);
      full.note = 'Retro';
      ALT_CLS_TimesheetService.EntryResult renoted = new ALT_CLS_TimesheetService()
        .register(full);
      ALT_CLS_TimesheetService.EntryResult evening = new ALT_CLS_TimesheetService()
        .register(entry(ctr.Id, '18:00', null, null, '20:00'));
      ALT_CLS_TimesheetService.EntryRequest otherDay = entry(
        ctr.Id,
        '09:00',
        '',
        '',
        '13:00'
      );
      otherDay.workDate = DAY.addDays(-1);
      ALT_CLS_TimesheetService.EntryResult noBreak = new ALT_CLS_TimesheetService()
        .register(otherDay);
      String overlap = failureOf(entry(ctr.Id, '10:00', null, null, '14:00'));
      Test.stopTest();

      Assert.areEqual(8.5, created.hours);
      Assert.areEqual('DRAFT', created.status);
      Assert.isTrue(created.created);
      Assert.areEqual(
        created.workRecordId,
        replay.workRecordId,
        'Identical resubmission is idempotent.'
      );
      Assert.isFalse(replay.created);
      Assert.areEqual(created.workRecordId, renoted.workRecordId);
      Assert.isFalse(renoted.created);
      Assert.areNotEqual(
        created.workRecordId,
        evening.workRecordId,
        'Two shifts of one day never collapse.'
      );
      Assert.areEqual(2, evening.hours);
      Assert.areEqual(4, noBreak.hours);
      Assert.areEqual('INVALID_INPUT', overlap, 'Overlapping shift refused.');
      AXF_OBJ_WorkRecord__c record = [
        SELECT
          AXF_WR_CUR_Rate__c,
          AXF_WR_TXT_CurrencyIsoCode__c,
          AXF_WR_LKP_TermVersion__c,
          AXF_WR_DAT_StartDate__c,
          AXF_WR_DAT_EndDate__c,
          AXF_WR_CUR_TotalAmount__c,
          AXF_WR_TXT_Source__c,
          AXF_WR_TXT_Description__c
        FROM AXF_OBJ_WorkRecord__c
        WHERE Id = :created.workRecordId
      ];
      Assert.areEqual(150, record.AXF_WR_CUR_Rate__c);
      Assert.areEqual('BRL', record.AXF_WR_TXT_CurrencyIsoCode__c);
      Assert.areEqual(
        [
          SELECT AXF_CTR_LKP_ActiveTermVersion__c
          FROM AXF_OBJ_Contract__c
          WHERE Id = :ctr.Id
        ]
        .AXF_CTR_LKP_ActiveTermVersion__c,
        record.AXF_WR_LKP_TermVersion__c
      );
      Assert.areEqual(DAY, record.AXF_WR_DAT_StartDate__c);
      Assert.areEqual(DAY, record.AXF_WR_DAT_EndDate__c);
      Assert.areEqual(1275, record.AXF_WR_CUR_TotalAmount__c);
      Assert.areEqual('MANUAL', record.AXF_WR_TXT_Source__c);
      Assert.areEqual(
        '08:00-12:00 | 13:00-17:30 · Retro',
        record.AXF_WR_TXT_Description__c,
        'Resubmitting the same shift updates the note of the draft.'
      );
      Assert.areEqual(
        4,
        [SELECT COUNT() FROM AXF_OBJ_WorkRecord__c],
        'A legacy entry without screen times never blocks a shift.'
      );
    }
  }

  @IsTest
  static void rejectsInvalidClockTimesAndInput() {
    System.runAs(byAlias('axf157a')) {
      Fixture f = fixture('Titular Invalido');
      Id ctr = serviceContract(f, 'SVC-INV').Id;
      ALT_CLS_TimesheetService.todayOverride = TODAY;
      ALT_CLS_TimesheetService.EntryRequest longNote = entry(
        ctr,
        '08:00',
        null,
        null,
        '09:00'
      );
      longNote.note = 'x'.repeat(201);
      ALT_CLS_TimesheetService.EntryRequest noDate = entry(
        ctr,
        '08:00',
        null,
        null,
        '09:00'
      );
      noDate.workDate = null;
      ALT_CLS_TimesheetService.EntryRequest foreignEntry = entry(
        ctr,
        '08:00',
        null,
        null,
        '09:00'
      );
      foreignEntry.workRecordId = ctr;

      Test.startTest();
      List<String> codes = new List<String>{
        failureOf(entry(ctr, '08:00', '12:00', null, '17:00')),
        failureOf(entry(ctr, '08:00', null, '13:00', '17:00')),
        failureOf(entry(ctr, '17:00', null, null, '08:00')),
        failureOf(entry(ctr, '08:00', null, null, '08:00')),
        failureOf(entry(ctr, '08:00', '13:00', '12:00', '17:00')),
        failureOf(entry(ctr, '08:00', '07:00', '09:00', '17:00')),
        failureOf(entry(ctr, '08:00', '12:00', '18:00', '17:00')),
        failureOf(entry(ctr, '8:00', null, null, '17:00')),
        failureOf(entry(ctr, '08:00', null, null, '24:00')),
        failureOf(entry(ctr, null, null, null, '17:00')),
        failureOf(entry(f.holder.Id, '08:00', null, null, '17:00')),
        failureOf(longNote),
        failureOf(noDate),
        failureOf(foreignEntry),
        failureOf(null)
      };
      Test.stopTest();

      for (String code : codes) {
        Assert.areEqual('INVALID_INPUT', code);
      }
      Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_WorkRecord__c]);
    }
  }

  @IsTest
  static void refusesDatesOutsideTodayContractAndTerm() {
    System.runAs(byAlias('axf157a')) {
      Fixture f = fixture('Titular Janela');
      Id open = serviceContract(f, 'SVC-OPEN').Id;
      AXF_OBJ_Contract__c terminated = serviceContract(f, 'SVC-END');
      terminated.AXF_CTR_DAT_EndDate__c = DAY.addDays(30);
      terminated.AXF_CTR_DAT_TerminationEffectiveDate__c = DAY.addDays(-5);
      update terminated;
      nextTermEffectiveTo = DAY.addDays(-3);
      Id shortTerm = serviceContract(f, 'SVC-TERM').Id;
      ALT_CLS_TimesheetService.todayOverride = DAY;

      Test.startTest();
      String future = failureOf(dated(open, DAY.addDays(1)));
      String beforeStart = failureOf(
        dated(open, Date.newInstance(2025, 12, 31))
      );
      String afterTermination = failureOf(
        dated(terminated.Id, DAY.addDays(-4))
      );
      String atTermination = failureOf(dated(terminated.Id, DAY.addDays(-5)));
      String afterTerm = failureOf(dated(shortTerm, DAY.addDays(-2)));
      String atTermEnd = failureOf(dated(shortTerm, DAY.addDays(-3)));
      String onToday = failureOf(dated(open, DAY));
      Test.stopTest();

      Assert.areEqual('INVALID_INPUT', future);
      Assert.areEqual('INVALID_INPUT', beforeStart);
      Assert.areEqual('INVALID_INPUT', afterTermination);
      Assert.isNull(atTermination);
      Assert.areEqual('INVALID_INPUT', afterTerm);
      Assert.isNull(atTermEnd);
      Assert.isNull(onToday);
    }
  }

  private static ALT_CLS_TimesheetService.EntryRequest dated(
    Id contractId,
    Date day
  ) {
    ALT_CLS_TimesheetService.EntryRequest request = entry(
      contractId,
      '08:00',
      null,
      null,
      '09:00'
    );
    request.workDate = day;
    return request;
  }

  @IsTest
  static void ineligibleAndForeignContractsAreNotAccessible() {
    User outsider = byAlias('axf157o');
    Id eligible;
    Id workId;
    System.runAs(byAlias('axf157a')) {
      Fixture f = fixture('Titular Elegivel');
      eligible = serviceContract(f, 'SVC-OK').Id;
      Id expense = contract(
          f,
          'EXP-1',
          'EXPENSE',
          'ACTIVE',
          'HOURLY',
          150,
          'BRL',
          null
        )
        .Id;
      Id monthly = contract(
          f,
          'MON-1',
          'REVENUE',
          'ACTIVE',
          'MONTHLY',
          150,
          'BRL',
          null
        )
        .Id;
      Id draft = contract(
          f,
          'DRF-1',
          'REVENUE',
          'DRAFT',
          'HOURLY',
          150,
          'BRL',
          null
        )
        .Id;
      ALT_CLS_TimesheetService.todayOverride = TODAY;

      List<ALT_CLS_TimesheetService.ContractOption> options = new ALT_CLS_TimesheetService()
        .contracts();
      Assert.areEqual(1, options.size(), 'Only the active service contract.');
      Assert.areEqual(eligible, options[0].contractId);
      Assert.areEqual(150, options[0].rate);
      Assert.areEqual('BRL', options[0].currencyIsoCode);
      Assert.areEqual('Titular Elegivel', options[0].holderLabel);
      Assert.isTrue(options[0].label.endsWith('Servico SVC-OK'));
      for (Id ineligible : new List<Id>{ expense, monthly, draft }) {
        Assert.areEqual(
          'NOT_ACCESSIBLE',
          failureOf(entry(ineligible, '08:00', null, null, '12:00'))
        );
      }
      workId = new ALT_CLS_TimesheetService()
        .register(entry(eligible, '08:00', null, null, '12:00'))
        .workRecordId;
    }

    Test.startTest();
    System.runAs(outsider) {
      Assert.isTrue(new ALT_CLS_TimesheetService().contracts().isEmpty());
      Assert.areEqual(
        'NOT_ACCESSIBLE',
        failureOf(entry(eligible, '14:00', null, null, '18:00'))
      );
      Assert.areEqual('NOT_ACCESSIBLE', submitFailure(workId));
      Assert.isTrue(listOf(null, null, null).entries.isEmpty());
      Assert.isTrue(forecast(null).groups.isEmpty());
    }
    Test.stopTest();
  }

  @IsTest
  static void readOnlyUserCannotRegisterOrSubmit() {
    System.runAs(byAlias('axf157r')) {
      Fixture f = fixture('Titular Leitura');
      Id ctr = serviceContract(f, 'SVC-RO').Id;
      Id workId = work(ctr, DAY, 2);
      ALT_CLS_TimesheetService.todayOverride = TODAY;

      Test.startTest();
      AXF_CLS_CTRL_Timesheet.Context context = AXF_CLS_CTRL_Timesheet.getContext();
      Integer listed = new ALT_CLS_TimesheetService().contracts().size();
      String registerCode = failureOf(entry(ctr, '08:00', null, null, '12:00'));
      String submitCode = submitFailure(workId);
      Test.stopTest();

      Assert.isFalse(context.canRegister);
      Assert.isFalse(context.canSubmit);
      Assert.areEqual(1, listed, 'The eligible contract is readable.');
      Assert.areEqual('NOT_ACCESSIBLE', registerCode);
      Assert.areEqual('NOT_ACCESSIBLE', submitCode);
      Assert.areEqual(1, [SELECT COUNT() FROM AXF_OBJ_WorkRecord__c]);
      Assert.areEqual(
        'DRAFT',
        [
          SELECT AXF_WR_PKL_Status__c
          FROM AXF_OBJ_WorkRecord__c
          WHERE Id = :workId
        ]
        .AXF_WR_PKL_Status__c
      );
    }
  }

  @IsTest
  static void submitsAndCorrectsDraftAndRejectedOnly() {
    System.runAs(byAlias('axf157a')) {
      Fixture f = fixture('Titular Submissao');
      Id ctr = serviceContract(f, 'SVC-SUB').Id;
      Id other = serviceContract(f, 'SVC-SUB2').Id;
      ALT_CLS_TimesheetService.todayOverride = TODAY;
      Id workId = new ALT_CLS_TimesheetService()
        .register(entry(ctr, '08:00', null, null, '12:00'))
        .workRecordId;

      Test.startTest();
      Assert.areEqual('SUBMITTED', submit(workId).status);
      Assert.areEqual('INVALID_STATE', submitFailure(workId));
      Assert.areEqual(
        'ALREADY_REGISTERED',
        failureOf(entry(ctr, '08:00', null, null, '12:00')),
        'A submitted shift is never registered again.'
      );
      ALT_CLS_TimesheetService.EntryRequest correction = entry(
        ctr,
        '08:00',
        null,
        null,
        '11:00'
      );
      correction.workRecordId = workId;
      Assert.areEqual('INVALID_STATE', failureOf(correction));
      new ALT_CLS_WorkRecordService()
        .decideWorkRecord(workId, false, 'Horas erradas');
      correction.contractId = other;
      Assert.areEqual('INVALID_INPUT', failureOf(correction));
      correction.contractId = ctr;
      correction.note = 'Corrigido';
      ALT_CLS_TimesheetService.EntryResult corrected = new ALT_CLS_TimesheetService()
        .register(correction);
      Assert.areEqual(workId, corrected.workRecordId);
      Assert.isFalse(corrected.created);
      Assert.areEqual(3, corrected.hours);
      Assert.areEqual('REJECTED', corrected.status);
      Assert.areEqual('SUBMITTED', submit(workId).status);
      new ALT_CLS_WorkRecordService().decideWorkRecord(workId, true, 'OK');
      Assert.areEqual('INVALID_STATE', submitFailure(workId));
      Assert.areEqual('INVALID_INPUT', submitFailure(null));
      Assert.areEqual('INVALID_INPUT', submitFailure(ctr));
      Test.stopTest();

      AXF_OBJ_WorkRecord__c record = [
        SELECT AXF_WR_NUM_Quantity__c, AXF_WR_TXT_Description__c
        FROM AXF_OBJ_WorkRecord__c
        WHERE Id = :workId
      ];
      Assert.areEqual(3, record.AXF_WR_NUM_Quantity__c);
      Assert.areEqual(
        '08:00-11:00 · Corrigido',
        record.AXF_WR_TXT_Description__c
      );
      Assert.areEqual(1, [SELECT COUNT() FROM AXF_OBJ_WorkRecord__c]);
    }
  }

  @IsTest
  static void listsEntriesByPeriodContractAndStatus() {
    System.runAs(byAlias('axf157a')) {
      Fixture f = fixture('Titular Lista');
      Id first = serviceContract(f, 'SVC-L1').Id;
      Id second = serviceContract(f, 'SVC-L2').Id;
      ALT_CLS_TimesheetService.todayOverride = TODAY;
      ALT_CLS_TimesheetService.EntryRequest shift = entry(
        first,
        '08:00',
        '12:00',
        '13:00',
        '17:00'
      );
      shift.note = 'Kickoff';
      Id draftId = new ALT_CLS_TimesheetService().register(shift).workRecordId;
      Id approvedId = approved(second, DAY.addDays(1), 3);
      approved(first, DAY.addMonths(1), 2);

      Test.startTest();
      ALT_CLS_TimesheetService.ListView month = listOf(null, null, null);
      ALT_CLS_TimesheetService.ListView byContract = listOf(second, null, null);
      ALT_CLS_TimesheetService.ListView drafts = listOf(null, null, 'DRAFT');
      ALT_CLS_TimesheetService.ListView unbilled = listOf(
        null,
        'UNBILLED',
        null
      );
      ALT_CLS_TimesheetService.ListView notBillable = listOf(
        null,
        'NOT_BILLABLE',
        null
      );
      ALT_CLS_TimesheetService.ListView billed = listOf(null, 'BILLED', null);
      ALT_CLS_TimesheetService.ListQuery custom = queryOf(
        DAY,
        DAY.addMonths(2),
        null,
        null
      );
      ALT_CLS_TimesheetService.ListView period = new ALT_CLS_TimesheetService()
        .entries(custom);
      ALT_CLS_TimesheetService.ListQuery combined = queryOf(
        DAY,
        DAY.addMonths(2),
        'UNBILLED',
        null
      );
      combined.contractId = first;
      ALT_CLS_TimesheetService.ListView combinedView = new ALT_CLS_TimesheetService()
        .entries(combined);
      ALT_CLS_TimesheetService.maxRowsOverride = 1;
      ALT_CLS_TimesheetService.ListView truncated = new ALT_CLS_TimesheetService()
        .entries(custom);
      Test.stopTest();

      Assert.areEqual(2, month.entries.size());
      Assert.areEqual(Date.newInstance(2026, 9, 1), month.fromDate);
      Assert.areEqual(Date.newInstance(2026, 9, 30), month.toDate);
      Assert.isFalse(month.customPeriod);
      Assert.isFalse(month.truncated);
      ALT_CLS_TimesheetService.EntryView newest = month.entries[0];
      Assert.areEqual(approvedId, newest.workRecordId, 'Newest day first.');
      Assert.areEqual('Legacy entry', newest.times);
      Assert.isNull(newest.note);
      Assert.areEqual('APPROVED', newest.status);
      Assert.areEqual('UNBILLED', newest.billingStatus);
      Assert.isFalse(newest.canSubmit);
      Assert.isFalse(newest.canEdit);
      ALT_CLS_TimesheetService.EntryView draft = month.entries[1];
      Assert.areEqual(draftId, draft.workRecordId);
      Assert.areEqual('08:00-12:00 | 13:00-17:00', draft.times);
      Assert.areEqual('Kickoff', draft.note);
      Assert.areEqual(8, draft.hours);
      Assert.areEqual(150, draft.rate);
      Assert.areEqual(1200, draft.totalAmount);
      Assert.areEqual('BRL', draft.currencyIsoCode);
      Assert.areEqual('NOT_BILLABLE', draft.billingStatus);
      Assert.isTrue(draft.canSubmit);
      Assert.isTrue(draft.canEdit);
      Assert.isTrue(draft.contractLabel.contains('SVC-L1'));
      Assert.areEqual(1, byContract.entries.size());
      Assert.areEqual(approvedId, byContract.entries[0].workRecordId);
      Assert.areEqual(1, drafts.entries.size());
      Assert.areEqual(draftId, drafts.entries[0].workRecordId);
      Assert.areEqual(
        1,
        unbilled.entries.size(),
        'Only approved work is unbilled.'
      );
      Assert.areEqual(approvedId, unbilled.entries[0].workRecordId);
      Assert.areEqual(1, notBillable.entries.size());
      Assert.areEqual(draftId, notBillable.entries[0].workRecordId);
      Assert.isTrue(billed.entries.isEmpty());
      Assert.isTrue(period.customPeriod);
      Assert.areEqual(3, period.entries.size());
      Assert.areEqual(1, combinedView.entries.size());
      Assert.areEqual(DAY.addMonths(1), combinedView.entries[0].workDate);
      Assert.isTrue(truncated.truncated);
      Assert.areEqual(1, truncated.entries.size());

      for (
        ALT_CLS_TimesheetService.ListQuery invalid : new List<ALT_CLS_TimesheetService.ListQuery>{
          null,
          queryOf(DAY, DAY.addDays(366), null, null),
          queryOf(DAY, null, null, null),
          queryOf(DAY.addDays(1), DAY, null, null),
          queryOf(null, null, 'PAID', null),
          queryOf(null, null, null, 'OPEN')
        }
      ) {
        try {
          new ALT_CLS_TimesheetService().entries(invalid);
          Assert.fail('Invalid query must be refused.');
        } catch (ALT_CLS_TimesheetService.TimesheetException expected) {
          Assert.areEqual('INVALID_INPUT', expected.getMessage());
        }
      }
    }
  }

  private static ALT_CLS_TimesheetService.ListQuery queryOf(
    Date fromDate,
    Date toDate,
    String billingStatus,
    String recordStatus
  ) {
    ALT_CLS_TimesheetService.ListQuery query = new ALT_CLS_TimesheetService.ListQuery();
    query.fromDate = fromDate;
    query.toDate = toDate;
    query.billingStatus = billingStatus;
    query.recordStatus = recordStatus;
    return query;
  }

  @IsTest
  static void forecastsMonthRevenuePerDestinationAccount() {
    System.runAs(byAlias('axf157a')) {
      Fixture f = fixture('Titular Previsao');
      Id withAccount = serviceContract(f, 'SVC-A').Id;
      Id withoutAccount = contract(
          f,
          'SVC-B',
          'REVENUE',
          'ACTIVE',
          'HOURLY',
          100,
          'BRL',
          null
        )
        .Id;
      Id foreign = contract(
          f,
          'SVC-C',
          'REVENUE',
          'ACTIVE',
          'HOURLY',
          50,
          'USD',
          null
        )
        .Id;
      approved(withAccount, DAY, 8);
      new ALT_CLS_WorkRecordService()
        .submitWorkRecord(work(withAccount, DAY.addDays(1), 4));
      work(withAccount, DAY.addDays(2), 5);
      approved(withoutAccount, DAY, 2);
      approved(foreign, DAY, 1);
      approved(withAccount, DAY.addMonths(1), 10);

      Test.startTest();
      ALT_CLS_TimesheetService.ForecastView all = forecast(null);
      ALT_CLS_TimesheetService.ForecastView onlyA = forecast(f.bank.Id);
      ALT_CLS_TimesheetService.ForecastView onlyNone = forecast('NONE');
      Test.stopTest();

      Assert.areEqual(2, all.groups.size());
      Assert.areEqual(2, all.destinations.size());
      ALT_CLS_TimesheetService.ForecastGroup groupA = all.groups[0];
      Assert.areEqual(String.valueOf(f.bank.Id), groupA.destination.key);
      Assert.areEqual('Banco A ****1234', groupA.destination.label);
      Assert.isFalse(groupA.destination.wallet);
      Assert.areEqual(1, groupA.lines.size());
      Assert.areEqual(8, groupA.lines[0].approvedHours);
      Assert.areEqual(1200, groupA.lines[0].approvedAmount);
      Assert.areEqual(4, groupA.lines[0].pendingHours);
      Assert.areEqual(600, groupA.lines[0].pendingAmount);
      Assert.areEqual(8, groupA.totals[0].approvedHours);
      Assert.areEqual(4, groupA.totals[0].pendingHours);
      ALT_CLS_TimesheetService.ForecastGroup none = all.groups[1];
      Assert.areEqual('NONE', none.destination.key);
      Assert.isNull(none.destination.label);
      Assert.areEqual(2, none.lines.size());
      Assert.areEqual(2, none.totals.size(), 'BRL and USD are never summed.');
      Assert.areEqual('BRL', none.totals[0].currencyIsoCode);
      Assert.areEqual(200, none.totals[0].approvedAmount);
      Assert.areEqual('USD', none.totals[1].currencyIsoCode);
      Assert.areEqual(50, none.totals[1].approvedAmount);
      Assert.areEqual(2, all.totals.size());
      Assert.areEqual(1400, all.totals[0].approvedAmount);
      Assert.areEqual(10, all.totals[0].approvedHours);
      Assert.areEqual(600, all.totals[0].pendingAmount);
      Assert.areEqual(1, onlyA.groups.size());
      Assert.areEqual(
        String.valueOf(f.bank.Id),
        onlyA.groups[0].destination.key
      );
      Assert.areEqual(2, onlyA.destinations.size());
      Assert.areEqual(1, onlyA.totals.size());
      Assert.areEqual(1, onlyNone.groups.size());
      Assert.areEqual('NONE', onlyNone.groups[0].destination.key);

      for (String invalid : new List<String>{ 'xyz', f.holder.Id }) {
        try {
          forecast(invalid);
          Assert.fail('Invalid destination must be refused.');
        } catch (ALT_CLS_TimesheetService.TimesheetException expected) {
          Assert.areEqual('INVALID_INPUT', expected.getMessage());
        }
      }
    }
  }

  @IsTest
  static void forecastKeepsTheAccountOfTheEntryTerm() {
    System.runAs(byAlias('axf157a')) {
      Fixture f = fixture('Titular Termo');
      AXF_OBJ_Contract__c ctr = serviceContract(f, 'SVC-T');
      ALT_CLS_TimesheetService.todayOverride = TODAY;
      Id screenEntry = new ALT_CLS_TimesheetService()
        .register(entry(ctr.Id, '08:00', null, null, '12:00'))
        .workRecordId;
      ALT_CLS_WorkRecordService engine = new ALT_CLS_WorkRecordService();
      engine.submitWorkRecord(screenEntry);
      engine.decideWorkRecord(screenEntry, true, 'OK');
      AXF_OBJ_BankAccount__c wallet = new AXF_OBJ_BankAccount__c(
        AXF_BA_LKP_Account__c = f.holder.Id,
        AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
        AXF_BA_TXT_CurrencyIsoCode__c = 'BRL',
        AXF_BA_TXT_Type__c = 'WALLET',
        AXF_BA_NUM_Version__c = 1
      );
      insert wallet;
      AXF_OBJ_ContractTermVersion__c revised = new AXF_OBJ_ContractTermVersion__c(
        AXF_CTV_LKP_Contract__c = ctr.Id,
        AXF_CTV_NUM_Revision__c = 2,
        AXF_CTV_PKL_Status__c = 'ACTIVE',
        AXF_CTV_PKL_RemunerationModel__c = 'HOURLY',
        AXF_CTV_TXT_CurrencyIsoCode__c = 'BRL',
        AXF_CTV_DAT_EffectiveFrom__c = Date.newInstance(2026, 1, 1),
        AXF_CTV_CUR_Rate__c = 150,
        AXF_CTV_LKP_PreferredBankAccount__c = wallet.Id,
        AXF_CTV_EXI_TermKey__c = 'TERM-SVC-T-2',
        AXF_CTV_NUM_Version__c = 1
      );
      insert revised;
      ctr.AXF_CTR_LKP_ActiveTermVersion__c = revised.Id;
      update ctr;
      approved(ctr.Id, DAY.addDays(1), 1);

      Test.startTest();
      ALT_CLS_TimesheetService.ForecastView view = forecast(null);
      Test.stopTest();

      Assert.areEqual(2, view.groups.size());
      Map<String, ALT_CLS_TimesheetService.ForecastGroup> byKey = new Map<String, ALT_CLS_TimesheetService.ForecastGroup>();
      for (ALT_CLS_TimesheetService.ForecastGroup item : view.groups) {
        byKey.put(item.destination.key, item);
      }
      Assert.areEqual(
        4,
        byKey.get(String.valueOf(f.bank.Id)).lines[0].approvedHours,
        'Past revenue stays on the account of its own term.'
      );
      ALT_CLS_TimesheetService.ForecastGroup walletGroup = byKey.get(
        String.valueOf(wallet.Id)
      );
      Assert.isTrue(walletGroup.destination.wallet);
      Assert.isNull(walletGroup.destination.label);
      Assert.areEqual(
        1,
        walletGroup.lines[0].approvedHours,
        'An entry without term falls back to the active term.'
      );
    }
  }

  // ------------------------------------------------------ billing status

  private static AXF_OBJ_FinancialTransaction__c plannedOccurrence(
    Fixture f,
    Id contractId,
    Id termId,
    String key
  ) {
    AXF_OBJ_FinancialTransaction__c ftx = new AXF_OBJ_FinancialTransaction__c(
      AXF_FTX_LKP_Account__c = f.holder.Id,
      AXF_FTX_LKP_Contract__c = contractId,
      AXF_FTX_NUM_Magnitude__c = 1000,
      AXF_FTX_PKL_Direction__c = 'CREDIT',
      AXF_FTX_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_FTX_DAT_PurchaseDate__c = Date.today(),
      AXF_FTX_DAT_DueDate__c = Date.today(),
      AXF_FTX_PKL_Status__c = 'PLANNED',
      AXF_FTX_TXT_ScheduleGroupKey__c = key,
      AXF_FTX_NUM_Sequence__c = 1,
      AXF_FTX_EXI_ClientRequestId__c = 'ftx-157-' + key,
      AXF_FTX_EXI_PlanIdentityHash__c = AXF_CLS_IdentityFraming.key(
        new List<Object>{ 'ftx-plan-v1', 'axf157-' + key, 1 }
      )
    );
    insert ftx;
    ALT_CLS_ContractSnapshotService.SnapshotInputDTO input = new ALT_CLS_ContractSnapshotService.SnapshotInputDTO();
    input.financialTransactionId = ftx.Id;
    input.termVersionId = termId;
    new ALT_CLS_ContractSnapshotService().applyToOccurrence(input);
    return [
      SELECT Id, AXF_FTX_LKP_ContractApplicationSnapshot__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE Id = :ftx.Id
    ];
  }

  private static Id compose(
    Fixture f,
    Id contractId,
    AXF_OBJ_FinancialTransaction__c fact,
    String key,
    Map<Id, Decimal> allocations
  ) {
    ALT_CLS_BillingDraftService.ComposeInput input = new ALT_CLS_BillingDraftService.ComposeInput();
    input.accountId = f.holder.Id;
    input.contractId = contractId;
    input.counterpartyId = f.counterpartyId;
    input.documentKind = 'GENERIC_INVOICE';
    input.seriesKey = key;
    input.periodStart = Date.today().toStartOfMonth();
    input.periodEnd = Date.today().toStartOfMonth().addMonths(1).addDays(-1);
    input.currencyIso = 'BRL';
    input.clientRequestId = 'req-157-' + key;
    ALT_CLS_BillingDraftService.LineInput line = new ALT_CLS_BillingDraftService.LineInput();
    line.financialTransactionId = fact.Id;
    line.snapshotId = fact.AXF_FTX_LKP_ContractApplicationSnapshot__c;
    line.workAllocations = new List<ALT_CLS_BillingDraftService.WorkAllocationInput>();
    for (Id workId : allocations.keySet()) {
      ALT_CLS_BillingDraftService.WorkAllocationInput allocation = new ALT_CLS_BillingDraftService.WorkAllocationInput();
      allocation.workRecordId = workId;
      allocation.quantity = allocations.get(workId);
      line.workAllocations.add(allocation);
    }
    input.lines = new List<ALT_CLS_BillingDraftService.LineInput>{ line };
    return new ALT_CLS_BillingDraftService().compose(input);
  }

  /** Runs as the test owner: billing composition needs the full billing access. */
  @IsTest
  static void billingStatusFollowsEffectiveAllocations() {
    Fixture f = fixture('Titular Faturamento');
    AXF_OBJ_Contract__c ctr = serviceContract(f, 'SVC-BILL');
    Id termId = [
      SELECT AXF_CTR_LKP_ActiveTermVersion__c
      FROM AXF_OBJ_Contract__c
      WHERE Id = :ctr.Id
    ]
    .AXF_CTR_LKP_ActiveTermVersion__c;
    Id partialId = approved(ctr.Id, Date.today(), 8);
    Id cancelledId = approved(ctr.Id, Date.today(), 4);
    Id billedId = approved(ctr.Id, Date.today(), 2);
    Id reviewed = compose(
      f,
      ctr.Id,
      plannedOccurrence(f, ctr.Id, termId, 'b1'),
      'axf157-1',
      new Map<Id, Decimal>{ partialId => 5, billedId => 2 }
    );
    Id cancelled = compose(
      f,
      ctr.Id,
      plannedOccurrence(f, ctr.Id, termId, 'b2'),
      'axf157-2',
      new Map<Id, Decimal>{ cancelledId => 4 }
    );
    ALT_CLS_BillingGuard.beginWrite();
    try {
      update new AXF_OBJ_BillingDocumentVersion__c(
        Id = new ALT_CLS_BillingDraftService().read(reviewed).versionId,
        AXF_BDV_PKL_State__c = 'REVIEWED'
      );
      update new AXF_OBJ_BillingDocument__c(
        Id = cancelled,
        AXF_BDO_PKL_Lifecycle__c = 'CANCELLED'
      );
    } finally {
      ALT_CLS_BillingGuard.endWrite();
    }

    Test.startTest();
    ALT_CLS_TimesheetService.ListQuery query = new ALT_CLS_TimesheetService.ListQuery();
    ALT_CLS_TimesheetService.ListView all = new ALT_CLS_TimesheetService()
      .entries(query);
    query.billingStatus = 'PARTIAL';
    ALT_CLS_TimesheetService.ListView partial = new ALT_CLS_TimesheetService()
      .entries(query);
    Test.stopTest();

    Map<Id, ALT_CLS_TimesheetService.EntryView> byId = new Map<Id, ALT_CLS_TimesheetService.EntryView>();
    for (ALT_CLS_TimesheetService.EntryView view : all.entries) {
      byId.put(view.workRecordId, view);
    }
    Assert.areEqual('PARTIAL', byId.get(partialId).billingStatus);
    Assert.areEqual(5, byId.get(partialId).billedHours);
    Assert.areEqual('BILLED', byId.get(billedId).billingStatus);
    Assert.areEqual(
      'UNBILLED',
      byId.get(cancelledId).billingStatus,
      'A cancelled document releases its allocation.'
    );
    Assert.areEqual(1, partial.entries.size());
    Assert.areEqual(partialId, partial.entries[0].workRecordId);
  }
}
