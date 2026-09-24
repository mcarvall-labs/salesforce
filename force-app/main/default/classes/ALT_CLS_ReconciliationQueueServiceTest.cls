/**
 * @description AXF-154: cross-account reconciliation queue. Pluggy facts only (bank and card) of
 * the authorized context, pending lines first with counters, every filter alone and combined, the
 * invoice filter derived by the AXF-152 calendar, the unchanged AXF-151/152 suggestion and
 * confirmation engine, the truncated flag and the read-only view without the link capability.
 */
@IsTest(isParallel=false)
// API 62: AXON_DEV enforces FLS on plain test DML under runAs from API 67 onwards.
private class ALT_CLS_ReconciliationQueueServiceTest {
  private static final String GESTOR = 'axf154g';
  private static final String PEER = 'axf154p';
  private static final String PARTICIPANT = 'axf154n';
  private static final Map<String, List<String>> READ_FIELDS = new Map<String, List<String>>{
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
      'AXF_CC_TXT_LastFourMasked__c',
      'AXF_CC_TXT_Brand__c',
      'AXF_CC_TXT_CurrencyIsoCode__c'
    },
    'AXF_OBJ_BankAccountTransaction__c' => new List<String>{
      'AXF_BAT_TXT_Description__c',
      'AXF_BAT_PKL_Status__c'
    },
    'AXF_OBJ_CreditCardTransaction__c' => new List<String>{
      'AXF_CCT_TXT_Description__c',
      'AXF_CCT_PKL_Status__c'
    },
    'AXF_OBJ_ReconciliationAllocation__c' => new List<String>{
      'AXF_RA_LKP_BankTransaction__c',
      'AXF_RA_LKP_CardTransaction__c',
      'AXF_RA_PKL_Kind__c',
      'AXF_RA_NUM_Magnitude__c'
    },
    'AXF_OBJ_CardBillingCycleRule__c' => new List<String>{
      'AXF_CBR_DAT_EffectiveTo__c',
      'AXF_CBR_NUM_ClosingDay__c',
      'AXF_CBR_NUM_DueDayOffset__c',
      'AXF_CBR_NUM_Version__c',
      'AXF_CBR_PKL_ClosingDayAdjustment__c',
      'AXF_CBR_PKL_DueDayAdjustment__c',
      'AXF_CBR_TXT_CalendarPolicyVersion__c'
    }
  };

  private static User byAlias(String alias) {
    return [SELECT Id FROM User WHERE Alias = :alias LIMIT 1];
  }

  /**
   * Check-only deploys do not apply the stack's permission-set changes to test users: the read
   * access the stack grants in AXF_PS_FinancialEntry is mirrored here (read only, never write).
   */
  private static Id readMirror() {
    PermissionSet result = new PermissionSet(
      Name = 'AXF154_TestQueueRead',
      Label = 'AXF154 test queue read'
    );
    insert result;
    List<ObjectPermissions> access = new List<ObjectPermissions>();
    List<FieldPermissions> fields = new List<FieldPermissions>();
    for (String objectName : READ_FIELDS.keySet()) {
      access.add(
        new ObjectPermissions(
          ParentId = result.Id,
          SobjectType = objectName,
          PermissionsRead = true
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
    return result.Id;
  }

  @TestSetup
  static void setup() {
    Id profileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
    .Id;
    List<User> users = new List<User>();
    for (String alias : new List<String>{ GESTOR, PEER, PARTICIPANT }) {
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
    Id mirror = readMirror();
    Map<String, Id> permissionSets = new Map<String, Id>();
    for (PermissionSet permission : [
      SELECT Id, Name
      FROM PermissionSet
      WHERE
        Name IN (
          'AXF_PS_GestorFinanceiro',
          'AXF_PS_FinancialEntry',
          'AXF_PS_Realization',
          'AXF_PS_Participante'
        )
    ]) {
      permissionSets.put(permission.Name, permission.Id);
    }
    Assert.areEqual(4, permissionSets.size(), 'permission sets must exist');
    List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (Integer i = 0; i < 3; i++) {
      List<Id> granted = new List<Id>{
        i < 2
          ? permissionSets.get('AXF_PS_GestorFinanceiro')
          : permissionSets.get('AXF_PS_Participante'),
        permissionSets.get('AXF_PS_FinancialEntry'),
        permissionSets.get('AXF_PS_Realization'),
        mirror
      };
      for (Id permissionSetId : granted) {
        assignments.add(
          new PermissionSetAssignment(
            AssigneeId = users[i].Id,
            PermissionSetId = permissionSetId
          )
        );
      }
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

  /** Weekdays are business days: the tests never depend on the org calendar. */
  private class Weekdays implements ALT_CLS_CardInvoiceCalendar.BusinessDays {
    public Boolean isBusinessDay(Date onDate) {
      return !ALT_CLS_CardInvoiceCalendar.isWeekend(onDate);
    }
  }

  /** A day in the past, inside the default window of the queue (the last 366 days). */
  private static Date ago(Integer days) {
    return Date.today().addDays(-days);
  }

  private static Date d(Integer y, Integer m, Integer dd) {
    return Date.newInstance(y, m, dd);
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

  private static AXF_OBJ_BankAccount__c bank(Id holderId, String masked) {
    AXF_OBJ_BankAccount__c result = new AXF_OBJ_BankAccount__c(
      AXF_BA_LKP_Account__c = holderId,
      AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_BA_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BA_TXT_InstitutionName__c = 'Banco 154',
      AXF_BA_TXT_NumberMasked__c = masked,
      AXF_BA_TXT_Type__c = 'CHECKING',
      AXF_BA_NUM_Version__c = 1
    );
    insert result;
    return result;
  }

  private static AXF_OBJ_CreditCard__c card(Id holderId) {
    AXF_OBJ_CreditCard__c result = new AXF_OBJ_CreditCard__c(
      AXF_CC_LKP_Account__c = holderId,
      AXF_CC_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_CC_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_CC_TXT_InstitutionName__c = 'Banco 154',
      AXF_CC_TXT_LastFourMasked__c = '1540',
      AXF_CC_TXT_Brand__c = 'VISA'
    );
    insert result;
    return result;
  }

  private static AXF_OBJ_BankAccountTransaction__c newBankFact(
    Id bankId,
    Decimal amount,
    Date onDate,
    String description,
    String key,
    String source
  ) {
    return new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_MDR_BankAccount__c = bankId,
      AXF_BAT_NUM_Magnitude__c = amount,
      AXF_BAT_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BAT_PKL_Direction__c = 'DEBIT',
      AXF_BAT_DAT_Date__c = onDate,
      AXF_BAT_TXT_Description__c = description,
      AXF_BAT_EXI_SourceKey__c = 'axf154-' + key,
      AXF_BAT_PKL_Source__c = source,
      AXF_BAT_PKL_Status__c = 'POSTED',
      AXF_BAT_NUM_Version__c = 0
    );
  }

  private static AXF_OBJ_BankAccountTransaction__c bankFact(
    Id bankId,
    Decimal amount,
    Date onDate,
    String description,
    String key
  ) {
    AXF_OBJ_BankAccountTransaction__c result = newBankFact(
      bankId,
      amount,
      onDate,
      description,
      key,
      'PLUGGY'
    );
    insert result;
    return result;
  }

  private static AXF_OBJ_CreditCardTransaction__c cardFact(
    Id cardId,
    Decimal amount,
    Date onDate,
    String description,
    String key
  ) {
    AXF_OBJ_CreditCardTransaction__c result = new AXF_OBJ_CreditCardTransaction__c(
      AXF_CCT_MDR_CreditCard__c = cardId,
      AXF_CCT_NUM_Magnitude__c = amount,
      AXF_CCT_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_CCT_PKL_Direction__c = 'DEBIT',
      AXF_CCT_DAT_Date__c = onDate,
      AXF_CCT_TXT_Description__c = description,
      AXF_CCT_EXI_SourceKey__c = 'axf154-' + key,
      AXF_CCT_PKL_Source__c = 'PLUGGY',
      AXF_CCT_PKL_Status__c = 'POSTED',
      AXF_CCT_NUM_Version__c = 0
    );
    insert result;
    return result;
  }

  private static AXF_OBJ_FinancialTransaction__c entry(
    Id holderId,
    Id bankId,
    Id cardId,
    Decimal amount,
    Date onDate,
    String key
  ) {
    AXF_OBJ_FinancialTransaction__c result = new AXF_OBJ_FinancialTransaction__c(
      AXF_FTX_LKP_Account__c = holderId,
      AXF_FTX_LKP_BankAccount__c = bankId,
      AXF_FTX_LKP_CreditCard__c = cardId,
      AXF_FTX_NUM_Magnitude__c = amount,
      AXF_FTX_PKL_Direction__c = 'DEBIT',
      AXF_FTX_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_FTX_DAT_PurchaseDate__c = onDate,
      AXF_FTX_DAT_DueDate__c = onDate,
      AXF_FTX_TXT_Description__c = 'Entry ' + key,
      AXF_FTX_PKL_PlanKind__c = 'PLANNED',
      AXF_FTX_PKL_Status__c = 'PLANNED',
      AXF_FTX_NUM_Version__c = 0,
      AXF_FTX_EXI_ClientRequestId__c = 'ftx-154-' + key
    );
    insert result;
    return result;
  }

  private static void rule(Id cardId, Integer closingDay, Integer dueOffset) {
    insert new AXF_OBJ_CardBillingCycleRule__c(
      AXF_CBR_LKP_CreditCard__c = cardId,
      AXF_CBR_PKL_State__c = 'ACTIVE',
      AXF_CBR_DAT_EffectiveFrom__c = d(2025, 1, 1),
      AXF_CBR_NUM_ClosingDay__c = closingDay,
      AXF_CBR_PKL_ClosingDayAdjustment__c = 'NONE',
      AXF_CBR_NUM_DueDayOffset__c = dueOffset,
      AXF_CBR_PKL_DueDayAdjustment__c = 'NONE',
      AXF_CBR_TXT_CalendarPolicyVersion__c = 'CAL-1.0.0',
      AXF_CBR_TXT_TimeZone__c = 'America/Sao_Paulo',
      AXF_CBR_NUM_Version__c = 1
    );
  }

  private static ALT_CLS_ReconciliationQueueService.QueueView queue(
    ALT_CLS_ReconciliationQueueService.QueueQuery query
  ) {
    return new ALT_CLS_ReconciliationQueueService().queue(query);
  }

  /** Every status (the default view is PENDING). */
  private static ALT_CLS_ReconciliationQueueService.QueueQuery all() {
    ALT_CLS_ReconciliationQueueService.QueueQuery query = new ALT_CLS_ReconciliationQueueService.QueueQuery();
    query.status = 'ALL';
    return query;
  }

  /** Confirmation of a known pair at its initial versions, without the suggestion read. */
  private static ALT_CLS_ReconciliationQueueService.ConfirmInput direct(
    Id fundingId,
    Id sourceId,
    Id targetId,
    String key
  ) {
    ALT_CLS_ReconciliationQueueService.ConfirmInput input = new ALT_CLS_ReconciliationQueueService.ConfirmInput();
    input.fundingId = fundingId;
    input.sourceId = sourceId;
    input.sourceVersion = 0;
    input.targetId = targetId;
    input.targetVersion = 0;
    input.operationKey = key;
    return input;
  }

  private static Set<Id> ids(
    ALT_CLS_ReconciliationQueueService.QueueView view
  ) {
    Set<Id> result = new Set<Id>();
    for (
      List<ALT_CLS_ReconciliationQueueService.QueueLine> section : new List<List<ALT_CLS_ReconciliationQueueService.QueueLine>>{
        view.pending,
        view.unverified,
        view.reconciled
      }
    ) {
      for (ALT_CLS_ReconciliationQueueService.QueueLine line : section) {
        result.add(line.recordId);
      }
    }
    return result;
  }

  private static Set<Id> idsOf(
    List<ALT_CLS_ReconciliationQueueService.QueueLine> lines
  ) {
    Set<Id> result = new Set<Id>();
    for (ALT_CLS_ReconciliationQueueService.QueueLine line : lines) {
      result.add(line.recordId);
    }
    return result;
  }

  private static ALT_CLS_BankStatementService.SuggestionPage suggest(
    Id fundingId,
    Id recordId
  ) {
    ALT_CLS_ReconciliationQueueService.SuggestionQuery query = new ALT_CLS_ReconciliationQueueService.SuggestionQuery();
    query.fundingId = fundingId;
    query.recordId = recordId;
    return new ALT_CLS_ReconciliationQueueService().suggest(query);
  }

  private static ALT_CLS_ReconciliationQueueService.ConfirmInput confirmOf(
    Id fundingId,
    ALT_CLS_BankStatementService.SuggestionView s,
    String key
  ) {
    ALT_CLS_ReconciliationQueueService.ConfirmInput input = new ALT_CLS_ReconciliationQueueService.ConfirmInput();
    input.fundingId = fundingId;
    input.sourceId = s.sourceId;
    input.sourceVersion = s.sourceVersion;
    input.targetId = s.targetId;
    input.targetVersion = s.targetVersion;
    input.operationKey = key;
    return input;
  }

  private static String failure(Callable call) {
    try {
      call.call('run', null);
    } catch (ALT_CLS_ReconciliationQueueService.ReconciliationQueueException expected) {
      return expected.getMessage();
    }
    return 'NO_EXCEPTION';
  }

  private class QueueCall implements Callable {
    ALT_CLS_ReconciliationQueueService.QueueQuery query;
    QueueCall(ALT_CLS_ReconciliationQueueService.QueueQuery query) {
      this.query = query;
    }
    public Object call(String action, Map<String, Object> args) {
      return queue(query);
    }
  }

  private class SuggestCall implements Callable {
    Id fundingId;
    Id recordId;
    SuggestCall(Id fundingId, Id recordId) {
      this.fundingId = fundingId;
      this.recordId = recordId;
    }
    public Object call(String action, Map<String, Object> args) {
      return suggest(fundingId, recordId);
    }
  }

  private class ConfirmCall implements Callable {
    ALT_CLS_ReconciliationQueueService.ConfirmInput input;
    ConfirmCall(ALT_CLS_ReconciliationQueueService.ConfirmInput input) {
      this.input = input;
    }
    public Object call(String action, Map<String, Object> args) {
      return new ALT_CLS_ReconciliationQueueService().confirm(input);
    }
  }

  // -------------------------------------------------------------- tests

  @IsTest
  static void opensWithPendingFirstAndOnlyPluggyFacts() {
    System.runAs(byAlias(GESTOR)) {
      Account owner = holder('Holder 154 open');
      AXF_OBJ_BankAccount__c account = bank(owner.Id, '****1541');
      AXF_OBJ_CreditCard__c creditCard = card(owner.Id);
      AXF_OBJ_BankAccountTransaction__c open = bankFact(
        account.Id,
        100,
        ago(5),
        'Mercado',
        'open'
      );
      AXF_OBJ_BankAccountTransaction__c done = bankFact(
        account.Id,
        50,
        ago(3),
        'Farmacia',
        'done'
      );
      AXF_OBJ_BankAccountTransaction__c manual = newBankFact(
        account.Id,
        30,
        ago(4),
        'Manual',
        'manual',
        'MANUAL'
      );
      insert manual;
      AXF_OBJ_CreditCardTransaction__c purchase = cardFact(
        creditCard.Id,
        80,
        ago(6),
        'Livraria',
        'purchase'
      );
      AXF_OBJ_FinancialTransaction__c planned = entry(
        owner.Id,
        account.Id,
        null,
        50,
        ago(3),
        'done'
      );
      Test.startTest();
      ALT_CLS_BankStatementService.SuggestionPage page = suggest(
        account.Id,
        done.Id
      );
      Assert.areEqual(1, page.items.size());
      Assert.areEqual(planned.Id, page.items[0].targetId);
      new ALT_CLS_ReconciliationQueueService()
        .confirm(confirmOf(account.Id, page.items[0], 'axf154-open-1'));
      ALT_CLS_ReconciliationQueueService.QueueView view = queue(all());
      Test.stopTest();
      Assert.isTrue(view.canReconcile);
      Assert.areEqual('AXF-MATCHING@1.1.0', view.matchingPolicy);
      Assert.areEqual('ALL', view.status);
      Assert.areEqual(Date.today(), view.toDate);
      Assert.areEqual(Date.today().addDays(-365), view.fromDate);
      Assert.areEqual(
        new Set<Id>{ open.Id, purchase.Id },
        idsOf(view.pending),
        'bank and card pending facts together'
      );
      Assert.areEqual(open.Id, view.pending[0].recordId, 'newest first');
      Assert.areEqual('BANK', view.pending[0].kind);
      Assert.areEqual('Banco 154 ****1541', view.pending[0].fundingName);
      Assert.areEqual('Holder 154 open', view.pending[0].holderLabel);
      Assert.isTrue(view.pending[0].canSuggest);
      Assert.areEqual('CARD', view.pending[1].kind);
      Assert.areEqual('Banco 154 VISA 1540', view.pending[1].fundingName);
      Assert.areEqual(new Set<Id>{ done.Id }, idsOf(view.reconciled));
      Assert.areEqual('RECONCILED', view.reconciled[0].status);
      Assert.isFalse(view.reconciled[0].canSuggest);
      Assert.isFalse(ids(view).contains(manual.Id), 'MANUAL facts never');
      Assert.areEqual(2, view.countUnreconciled);
      Assert.areEqual(1, view.countReconciled);
      Assert.areEqual(0, view.countPartial);
      Assert.areEqual(0, view.countUnverified);
      Assert.isFalse(view.truncated);
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM AXF_OBJ_ReconciliationAllocation__c
          WHERE
            AXF_RA_LKP_BankTransaction__c = :done.Id
            AND AXF_RA_LKP_FinancialTransaction__c = :planned.Id
        ],
        'the delegated engine created the allocation'
      );
    }
  }

  @IsTest
  static void eachStatusFilterSelectsExactlyItsLines() {
    System.runAs(byAlias(GESTOR)) {
      Account owner = holder('Holder 154 mixed');
      AXF_OBJ_BankAccount__c account = bank(owner.Id, '****1549');
      AXF_OBJ_BankAccountTransaction__c reconciled = bankFact(
        account.Id,
        100,
        ago(3),
        'Reconciled',
        'mixed-rec'
      );
      AXF_OBJ_BankAccountTransaction__c partial = bankFact(
        account.Id,
        100,
        ago(20),
        'Partial',
        'mixed-par'
      );
      AXF_OBJ_BankAccountTransaction__c open = bankFact(
        account.Id,
        30,
        ago(40),
        'Open',
        'mixed-open'
      );
      AXF_OBJ_FinancialTransaction__c full = entry(
        owner.Id,
        account.Id,
        null,
        100,
        ago(3),
        'mixed-full'
      );
      AXF_OBJ_FinancialTransaction__c part = entry(
        owner.Id,
        account.Id,
        null,
        96,
        ago(20),
        'mixed-part'
      );
      // The engine's own confirmation (no suggestion round-trip) runs before the measured
      // transaction: only the queue reads count against the limits below.
      ALT_CLS_ReconciliationQueueService service = new ALT_CLS_ReconciliationQueueService();
      service.confirm(
        direct(account.Id, reconciled.Id, full.Id, 'axf154-mixed-1')
      );
      service.confirm(
        direct(account.Id, partial.Id, part.Id, 'axf154-mixed-2')
      );
      Test.startTest();
      Integer before = Limits.getQueries();
      ALT_CLS_ReconciliationQueueService.QueueView byDefault = queue(
        new ALT_CLS_ReconciliationQueueService.QueueQuery()
      );
      Map<String, ALT_CLS_ReconciliationQueueService.QueueView> byStatus = new Map<String, ALT_CLS_ReconciliationQueueService.QueueView>();
      for (
        String status : new List<String>{
          'PENDING',
          'PARTIAL',
          'RECONCILED',
          'UNRECONCILED',
          'ALL'
        }
      ) {
        ALT_CLS_ReconciliationQueueService.QueueQuery query = new ALT_CLS_ReconciliationQueueService.QueueQuery();
        query.status = status;
        byStatus.put(status, queue(query));
      }
      Integer perCall = (Limits.getQueries() - before) / 6;
      Test.stopTest();
      Assert.isTrue(
        perCall <= 12,
        'a queue read stays well under the SOQL limit: ' + perCall
      );
      Assert.areEqual('PENDING', byDefault.status, 'pending by default');
      Assert.areEqual(new Set<Id>{ partial.Id, open.Id }, ids(byDefault));
      Assert.areEqual(1, byDefault.countReconciled);
      Assert.areEqual(1, byDefault.countPartial);
      Assert.areEqual(1, byDefault.countUnreconciled);
      Assert.areEqual(
        new Set<Id>{ partial.Id, open.Id },
        ids(byStatus.get('PENDING'))
      );
      Assert.areEqual(new Set<Id>{ partial.Id }, ids(byStatus.get('PARTIAL')));
      Assert.areEqual(96, byStatus.get('PARTIAL').pending[0].allocated);
      Assert.areEqual(4, byStatus.get('PARTIAL').pending[0].residual);
      Assert.areEqual(
        new Set<Id>{ reconciled.Id },
        ids(byStatus.get('RECONCILED'))
      );
      Assert.areEqual(
        new Set<Id>{ reconciled.Id },
        idsOf(byStatus.get('RECONCILED').reconciled)
      );
      Assert.areEqual(
        new Set<Id>{ open.Id },
        ids(byStatus.get('UNRECONCILED'))
      );
      Assert.areEqual(
        new Set<Id>{ reconciled.Id, partial.Id, open.Id },
        ids(byStatus.get('ALL'))
      );
    }
  }

  @IsTest
  static void olderPendingFactsAppearInTheDefaultView() {
    System.runAs(byAlias(GESTOR)) {
      Account owner = holder('Holder 154 backlog');
      AXF_OBJ_BankAccount__c account = bank(owner.Id, '****1550');
      AXF_OBJ_BankAccountTransaction__c old = bankFact(
        account.Id,
        70,
        Date.today().toStartOfMonth().addMonths(-5),
        'Antigo',
        'backlog-old'
      );
      AXF_OBJ_BankAccountTransaction__c tooOld = bankFact(
        account.Id,
        70,
        Date.today().addDays(-400),
        'Fora da janela',
        'backlog-too-old'
      );
      Test.startTest();
      ALT_CLS_ReconciliationQueueService.QueueView view = queue(
        new ALT_CLS_ReconciliationQueueService.QueueQuery()
      );
      Test.stopTest();
      Assert.areEqual(new Set<Id>{ old.Id }, idsOf(view.pending));
      Assert.isFalse(ids(view).contains(tooOld.Id), 'last 366 days only');
    }
  }

  @IsTest
  static void unavailableSourcesAndUnpostedFactsNeverAppear() {
    System.runAs(byAlias(GESTOR)) {
      Account owner = holder('Holder 154 negative');
      AXF_OBJ_BankAccount__c available = bank(owner.Id, '****1551');
      AXF_OBJ_BankAccount__c custody = bank(owner.Id, '****1552');
      custody.AXF_BA_PKL_AvailabilityState__c = 'CUSTODY';
      update custody;
      AXF_OBJ_CreditCard__c custodyCard = card(owner.Id);
      custodyCard.AXF_CC_PKL_AvailabilityState__c = 'CUSTODY';
      update custodyCard;
      AXF_OBJ_BankAccountTransaction__c visible = bankFact(
        available.Id,
        10,
        ago(2),
        'Visivel',
        'neg-visible'
      );
      AXF_OBJ_BankAccountTransaction__c unposted = newBankFact(
        available.Id,
        11,
        ago(2),
        'Pendente',
        'neg-unposted',
        'PLUGGY'
      );
      unposted.AXF_BAT_PKL_Status__c = 'PENDING';
      insert unposted;
      AXF_OBJ_BankAccountTransaction__c onCustody = bankFact(
        custody.Id,
        12,
        ago(2),
        'Custodia',
        'neg-custody'
      );
      AXF_OBJ_CreditCardTransaction__c onCustodyCard = cardFact(
        custodyCard.Id,
        13,
        ago(2),
        'Cartao custodia',
        'neg-custody-card'
      );
      Test.startTest();
      ALT_CLS_ReconciliationQueueService.QueueView everything = queue(all());
      ALT_CLS_ReconciliationQueueService.QueueView pending = queue(
        new ALT_CLS_ReconciliationQueueService.QueueQuery()
      );
      ALT_CLS_ReconciliationQueueService.SourceList sources = new ALT_CLS_ReconciliationQueueService()
        .listSources();
      ALT_CLS_ReconciliationQueueService.QueueQuery onUnavailable = all();
      onUnavailable.fundingId = custody.Id;
      String custodyCode = failure(new QueueCall(onUnavailable));
      Test.stopTest();
      Assert.areEqual(new Set<Id>{ visible.Id }, ids(everything));
      Assert.areEqual(new Set<Id>{ visible.Id }, ids(pending));
      Set<Id> listed = new Set<Id>();
      for (ALT_CLS_ReconciliationQueueService.SourceView v : sources.items) {
        listed.add(v.fundingId);
      }
      Assert.areEqual(new Set<Id>{ available.Id }, listed);
      Assert.areEqual('NOT_ACCESSIBLE', custodyCode);
      Assert.isFalse(ids(everything).contains(unposted.Id));
      Assert.isFalse(ids(everything).contains(onCustody.Id));
      Assert.isFalse(ids(everything).contains(onCustodyCard.Id));
    }
  }

  @IsTest
  static void everyFilterRestrictsAloneAndCombined() {
    System.runAs(byAlias(GESTOR)) {
      Account owner = holder('Holder 154 filters');
      AXF_OBJ_BankAccount__c x = bank(owner.Id, '****1542');
      AXF_OBJ_BankAccount__c y = bank(owner.Id, '****1543');
      AXF_OBJ_CreditCard__c creditCard = card(owner.Id);
      AXF_OBJ_BankAccountTransaction__c onX = bankFact(
        x.Id,
        120,
        ago(5),
        'Padaria 50%_off',
        'x'
      );
      AXF_OBJ_BankAccountTransaction__c onY = bankFact(
        y.Id,
        40,
        ago(6),
        'Padaria centro',
        'y'
      );
      AXF_OBJ_BankAccountTransaction__c older = bankFact(
        x.Id,
        120,
        ago(60),
        'Padaria antiga',
        'older'
      );
      AXF_OBJ_CreditCardTransaction__c onCard = cardFact(
        creditCard.Id,
        120,
        ago(7),
        'Padaria cartao',
        'card'
      );
      Test.startTest();
      ALT_CLS_ReconciliationQueueService.QueueQuery byKind = all();
      byKind.kind = 'CARD';
      Set<Id> cardsOnly = ids(queue(byKind));
      byKind.kind = 'BANK';
      Set<Id> banksOnly = ids(queue(byKind));
      ALT_CLS_ReconciliationQueueService.QueueQuery byAccount = all();
      byAccount.fundingId = x.Id;
      Set<Id> accountOnly = ids(queue(byAccount));
      ALT_CLS_ReconciliationQueueService.QueueQuery byPeriod = all();
      byPeriod.fromDate = ago(10);
      byPeriod.toDate = Date.today();
      Set<Id> periodOnly = ids(queue(byPeriod));
      ALT_CLS_ReconciliationQueueService.QueueQuery combined = all();
      combined.fromDate = ago(90);
      combined.toDate = Date.today();
      combined.minAmount = 100;
      combined.maxAmount = 130;
      combined.term = 'padaria';
      Set<Id> combinedIds = ids(queue(combined));
      combined.kind = 'BANK';
      combined.fundingId = x.Id;
      Set<Id> narrowest = ids(queue(combined));
      ALT_CLS_ReconciliationQueueService.QueueQuery literal = all();
      literal.term = '50%_';
      Set<Id> literalIds = ids(queue(literal));
      ALT_CLS_ReconciliationQueueService.QueueQuery byStatus = all();
      byStatus.status = 'RECONCILED';
      ALT_CLS_ReconciliationQueueService.QueueView reconciledOnly = queue(
        byStatus
      );
      byStatus.status = 'PENDING';
      ALT_CLS_ReconciliationQueueService.QueueView pendingOnly = queue(
        byStatus
      );
      Test.stopTest();
      Assert.areEqual(new Set<Id>{ onCard.Id }, cardsOnly);
      Assert.areEqual(new Set<Id>{ onX.Id, onY.Id, older.Id }, banksOnly);
      Assert.areEqual(new Set<Id>{ onX.Id, older.Id }, accountOnly);
      Assert.areEqual(new Set<Id>{ onX.Id, onY.Id, onCard.Id }, periodOnly);
      Assert.areEqual(
        new Set<Id>{ onX.Id, older.Id, onCard.Id },
        combinedIds,
        'period + amount + description together'
      );
      Assert.areEqual(new Set<Id>{ onX.Id, older.Id }, narrowest);
      Assert.areEqual(
        new Set<Id>{ onX.Id },
        literalIds,
        'wildcards are escaped'
      );
      Assert.areEqual(0, ids(reconciledOnly).size());
      Assert.areEqual(4, reconciledOnly.countUnreconciled, 'counters stay');
      Assert.areEqual(4, pendingOnly.pending.size());
    }
  }

  @IsTest
  static void invalidFiltersAreRefused() {
    System.runAs(byAlias(GESTOR)) {
      Account owner = holder('Holder 154 invalid');
      AXF_OBJ_BankAccount__c account = bank(owner.Id, '****1544');
      AXF_OBJ_CreditCard__c creditCard = card(owner.Id);
      ALT_CLS_ReconciliationQueueService.QueueQuery tooLong = all();
      // 01/01/2026..01/01/2027 is 366 days inclusive (allowed); one more day is refused.
      tooLong.fromDate = d(2026, 1, 1);
      tooLong.toDate = d(2027, 1, 2);
      ALT_CLS_ReconciliationQueueService.QueueQuery halfPeriod = all();
      halfPeriod.fromDate = d(2026, 1, 1);
      ALT_CLS_ReconciliationQueueService.QueueQuery invoiceNoCard = all();
      invoiceNoCard.invoiceYear = 2026;
      invoiceNoCard.invoiceMonth = 9;
      ALT_CLS_ReconciliationQueueService.QueueQuery invoiceOnBank = all();
      invoiceOnBank.fundingId = account.Id;
      invoiceOnBank.invoiceYear = 2026;
      invoiceOnBank.invoiceMonth = 9;
      ALT_CLS_ReconciliationQueueService.QueueQuery mismatch = all();
      mismatch.kind = 'BANK';
      mismatch.fundingId = creditCard.Id;
      ALT_CLS_ReconciliationQueueService.QueueQuery badKind = all();
      badKind.kind = 'LOAN';
      ALT_CLS_ReconciliationQueueService.QueueQuery badStatus = all();
      badStatus.status = 'DONE';
      ALT_CLS_ReconciliationQueueService.QueueQuery amounts = all();
      amounts.minAmount = 10;
      amounts.maxAmount = 5;
      ALT_CLS_ReconciliationQueueService.QueueQuery foreignType = all();
      foreignType.fundingId = owner.Id;
      for (
        ALT_CLS_ReconciliationQueueService.QueueQuery query : new List<ALT_CLS_ReconciliationQueueService.QueueQuery>{
          tooLong,
          halfPeriod,
          invoiceNoCard,
          invoiceOnBank,
          mismatch,
          badKind,
          badStatus,
          amounts,
          foreignType,
          null
        }
      ) {
        Assert.areEqual('INVALID_INPUT', failure(new QueueCall(query)));
      }
    }
  }

  @IsTest
  static void foreignSourcesDiscloseNothing() {
    AXF_OBJ_BankAccount__c owned;
    AXF_OBJ_CreditCard__c ownedCard;
    AXF_OBJ_BankAccountTransaction__c fact;
    System.runAs(byAlias(GESTOR)) {
      Account owner = holder('Holder 154 owner');
      owned = bank(owner.Id, '****1545');
      ownedCard = card(owner.Id);
      fact = bankFact(owned.Id, 10, ago(3), 'Alheio', 'foreign');
    }
    System.runAs(byAlias(PEER)) {
      ALT_CLS_ReconciliationQueueService.QueueView view = queue(all());
      Assert.areEqual(0, ids(view).size());
      Assert.areEqual(
        0,
        new ALT_CLS_ReconciliationQueueService().listSources().items.size()
      );
      ALT_CLS_ReconciliationQueueService.QueueQuery foreign = all();
      foreign.fundingId = owned.Id;
      Assert.areEqual('NOT_ACCESSIBLE', failure(new QueueCall(foreign)));
      foreign.fundingId = ownedCard.Id;
      Assert.areEqual('NOT_ACCESSIBLE', failure(new QueueCall(foreign)));
      Assert.areEqual(
        'NOT_ACCESSIBLE',
        failure(new SuggestCall(owned.Id, fact.Id))
      );
      Assert.areEqual(
        'INVALID_INPUT',
        failure(new SuggestCall(fact.Id, fact.Id))
      );
    }
  }

  @IsTest
  static void invoiceFilterUsesTheCardCalendar() {
    System.runAs(byAlias(GESTOR)) {
      ALT_CLS_ReconciliationQueueService.businessDaysOverride = new Weekdays();
      Account owner = holder('Holder 154 invoice');
      AXF_OBJ_CreditCard__c withRule = card(owner.Id);
      AXF_OBJ_CreditCard__c bare = card(owner.Id);
      rule(withRule.Id, 5, 7);
      AXF_OBJ_CreditCardTransaction__c first = cardFact(
        withRule.Id,
        10,
        d(2026, 8, 6),
        'Primeira',
        'inv-first'
      );
      AXF_OBJ_CreditCardTransaction__c last = cardFact(
        withRule.Id,
        20,
        d(2026, 9, 5),
        'Ultima',
        'inv-last'
      );
      AXF_OBJ_CreditCardTransaction__c next = cardFact(
        withRule.Id,
        30,
        d(2026, 9, 6),
        'Proxima',
        'inv-next'
      );
      AXF_OBJ_CreditCardTransaction__c civil = cardFact(
        bare.Id,
        40,
        d(2026, 9, 20),
        'Sem calendario',
        'inv-civil'
      );
      Test.startTest();
      ALT_CLS_ReconciliationQueueService.QueueQuery query = all();
      query.fundingId = withRule.Id;
      query.invoiceYear = 2026;
      query.invoiceMonth = 9;
      ALT_CLS_ReconciliationQueueService.QueueView september = queue(query);
      query.status = null;
      ALT_CLS_ReconciliationQueueService.QueueView pendingInvoice = queue(
        query
      );
      query.status = 'ALL';
      query.fromDate = d(2026, 9, 1);
      query.toDate = d(2026, 9, 30);
      ALT_CLS_ReconciliationQueueService.QueueView narrowed = queue(query);
      ALT_CLS_ReconciliationQueueService.QueueQuery blocked = all();
      blocked.fundingId = bare.Id;
      blocked.kind = 'CARD';
      blocked.invoiceYear = 2026;
      blocked.invoiceMonth = 9;
      ALT_CLS_ReconciliationQueueService.QueueView civilMonth = queue(blocked);
      Test.stopTest();
      Assert.areEqual('RESOLVED', september.invoiceOutcome);
      Assert.areEqual(d(2026, 8, 6), september.fromDate);
      Assert.areEqual(d(2026, 9, 5), september.toDate);
      Assert.areEqual(d(2026, 8, 6), september.invoiceFromDate);
      Assert.areEqual(d(2026, 9, 5), september.invoiceToDate);
      Assert.areEqual(d(2026, 9, 5), september.closingDate);
      Assert.areEqual(d(2026, 9, 12), september.dueDate);
      Assert.areEqual(new Set<Id>{ first.Id, last.Id }, ids(september));
      Assert.isFalse(ids(september).contains(next.Id), 'next invoice');
      Assert.areEqual(
        new Set<Id>{ first.Id, last.Id },
        ids(pendingInvoice),
        'the pending view keeps the invoice window'
      );
      Assert.areEqual(
        new Set<Id>{ last.Id },
        ids(narrowed),
        'the period narrows inside the invoice'
      );
      Assert.isTrue(narrowed.customPeriod);
      Assert.areEqual(d(2026, 9, 1), narrowed.fromDate, 'narrowed dates');
      Assert.areEqual(d(2026, 9, 5), narrowed.toDate);
      Assert.areEqual(d(2026, 8, 6), narrowed.invoiceFromDate);
      Assert.areEqual(d(2026, 9, 5), narrowed.invoiceToDate);
      Assert.areEqual('BLOCKED', civilMonth.invoiceOutcome);
      Assert.areEqual(d(2026, 9, 1), civilMonth.fromDate);
      Assert.areEqual(d(2026, 9, 30), civilMonth.toDate);
      Assert.areEqual(new Set<Id>{ civil.Id }, ids(civilMonth));
    }
  }

  @IsTest
  static void cardFactReconcilesThroughTheCardEngine() {
    System.runAs(byAlias(GESTOR)) {
      Account owner = holder('Holder 154 card');
      AXF_OBJ_CreditCard__c creditCard = card(owner.Id);
      AXF_OBJ_CreditCardTransaction__c purchase = cardFact(
        creditCard.Id,
        100,
        ago(16),
        'Restaurante',
        'card-confirm'
      );
      AXF_OBJ_FinancialTransaction__c inside = entry(
        owner.Id,
        null,
        creditCard.Id,
        104,
        ago(10),
        'card-in'
      );
      entry(owner.Id, null, creditCard.Id, 106, ago(16), 'card-amount-out');
      Test.startTest();
      ALT_CLS_BankStatementService.SuggestionPage page = suggest(
        creditCard.Id,
        purchase.Id
      );
      Assert.areEqual(1, page.items.size(), 'only R$104 is suggested');
      Assert.areEqual(inside.Id, page.items[0].targetId);
      ALT_CLS_BankStatementService.ConfirmResult confirmed = new ALT_CLS_ReconciliationQueueService()
        .confirm(confirmOf(creditCard.Id, page.items[0], 'axf154-card-1'));
      String again = failure(
        new ConfirmCall(
          confirmOf(creditCard.Id, page.items[0], 'axf154-card-2')
        )
      );
      ALT_CLS_ReconciliationQueueService.QueueView view = queue(all());
      Test.stopTest();
      Assert.isNotNull(confirmed.allocationId);
      Assert.areEqual(100, confirmed.amount);
      Assert.areEqual('SOURCE_EXHAUSTED', again, 'engine codes pass through');
      Assert.areEqual(0, view.pending.size());
      Assert.areEqual(new Set<Id>{ purchase.Id }, idsOf(view.reconciled));
    }
  }

  @IsTest
  static void staleVersionIsAConflict() {
    System.runAs(byAlias(GESTOR)) {
      Account owner = holder('Holder 154 stale');
      AXF_OBJ_BankAccount__c account = bank(owner.Id, '****1546');
      AXF_OBJ_BankAccountTransaction__c source = bankFact(
        account.Id,
        100,
        ago(12),
        'Luz',
        'stale'
      );
      entry(owner.Id, account.Id, null, 96, ago(12), 'stale');
      Test.startTest();
      ALT_CLS_BankStatementService.SuggestionView s = suggest(
          account.Id,
          source.Id
        )
        .items[0];
      ALT_CLS_ReconciliationQueueService.ConfirmInput stale = confirmOf(
        account.Id,
        s,
        'axf154-stale'
      );
      stale.sourceVersion = 99;
      String conflict = failure(new ConfirmCall(stale));
      Test.stopTest();
      Assert.areEqual('CONFLICT', conflict);
      Assert.areEqual(
        'INVALID_INPUT',
        failure(
          new ConfirmCall(new ALT_CLS_ReconciliationQueueService.ConfirmInput())
        )
      );
      Assert.areEqual('INVALID_INPUT', failure(new SuggestCall(null, null)));
    }
  }

  @IsTest
  static void participantReadsButCannotReconcile() {
    System.runAs(byAlias(PARTICIPANT)) {
      Account owner = holder('Holder 154 participant');
      AXF_OBJ_BankAccount__c account = bank(owner.Id, '****1547');
      AXF_OBJ_BankAccountTransaction__c source = bankFact(
        account.Id,
        100,
        ago(10),
        'Farmacia',
        'participant'
      );
      AXF_OBJ_FinancialTransaction__c planned = entry(
        owner.Id,
        account.Id,
        null,
        100,
        ago(10),
        'participant'
      );
      Test.startTest();
      ALT_CLS_ReconciliationQueueService.QueueView view = queue(
        new ALT_CLS_ReconciliationQueueService.QueueQuery()
      );
      String suggestCode = failure(new SuggestCall(account.Id, source.Id));
      ALT_CLS_ReconciliationQueueService.ConfirmInput input = new ALT_CLS_ReconciliationQueueService.ConfirmInput();
      input.fundingId = account.Id;
      input.sourceId = source.Id;
      input.sourceVersion = 0;
      input.targetId = planned.Id;
      input.targetVersion = 0;
      input.operationKey = 'axf154-participant';
      String confirmCode = failure(new ConfirmCall(input));
      Test.stopTest();
      Assert.isFalse(view.canReconcile);
      Assert.areEqual(new Set<Id>{ source.Id }, idsOf(view.pending));
      Assert.areEqual('UNRECONCILED', view.pending[0].status);
      Assert.isFalse(view.pending[0].canSuggest, 'no action');
      Assert.areEqual('UNAVAILABLE', suggestCode);
      Assert.areEqual('UNAVAILABLE', confirmCode);
    }
  }

  /**
   * The participant (no link capability) derives the status from the allocations it can see:
   * 60 applied, 40 applied and reversed. A capped allocation read leaves the fact unverified.
   */
  @IsTest
  static void participantNetsVisibleAllocationsAndFlagsACappedRead() {
    User participant = byAlias(PARTICIPANT);
    User self = new User(Id = UserInfo.getUserId());
    // The fixture is realized by the running user through AXF-25 (never a direct allocation).
    System.runAs(self) {
      Id realization = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = 'AXF_PS_Realization'
      ]
      .Id;
      if (
        [
          SELECT COUNT()
          FROM PermissionSetAssignment
          WHERE AssigneeId = :self.Id AND PermissionSetId = :realization
        ] == 0
      ) {
        insert new PermissionSetAssignment(
          AssigneeId = self.Id,
          PermissionSetId = realization
        );
      }
    }
    AXF_OBJ_BankAccountTransaction__c source;
    System.runAs(self) {
      Account owner = new Account(
        Name = 'Holder 154 nets',
        OwnerId = participant.Id,
        RecordTypeId = Account.SObjectType.getDescribe()
          .getRecordTypeInfosByDeveloperName()
          .get('AXF_Business')
          .getRecordTypeId()
      );
      insert owner;
      AXF_OBJ_BankAccount__c account = new AXF_OBJ_BankAccount__c(
        OwnerId = participant.Id,
        AXF_BA_LKP_Account__c = owner.Id,
        AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
        AXF_BA_TXT_CurrencyIsoCode__c = 'BRL',
        AXF_BA_TXT_InstitutionName__c = 'Banco 154',
        AXF_BA_TXT_Type__c = 'CHECKING',
        AXF_BA_NUM_Version__c = 1
      );
      insert account;
      source = newBankFact(
        account.Id,
        100,
        ago(8),
        'Mercado',
        'nets',
        'PLUGGY'
      );
      insert source;
      AXF_OBJ_FinancialTransaction__c kept = newEntry(
        owner.Id,
        account.Id,
        60,
        ago(8),
        'nets-kept'
      );
      AXF_OBJ_FinancialTransaction__c reversed = newEntry(
        owner.Id,
        account.Id,
        40,
        ago(8),
        'nets-reversed'
      );
      kept.OwnerId = participant.Id;
      reversed.OwnerId = participant.Id;
      insert new List<AXF_OBJ_FinancialTransaction__c>{ kept, reversed };
      ALT_CLS_RealizationService realize = new ALT_CLS_RealizationService();
      realize.apply(application(kept.Id, source, 60, 'axf154-nets-kept'));
      ALT_CLS_RealizationService.Input second = application(
        reversed.Id,
        source,
        40,
        'axf154-nets-reversed'
      );
      second.sourceVersion = realize.sourceVersion(source.Id, 'BANK');
      Id reversible = realize.apply(second);
      Decimal version = [
        SELECT AXF_FTX_NUM_Version__c
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE Id = :reversed.Id
      ]
      .AXF_FTX_NUM_Version__c;
      realize.reverse(reversible, version, 'axf154-nets-reverse');
      List<AXF_OBJ_ReconciliationAllocation__Share> shares = new List<AXF_OBJ_ReconciliationAllocation__Share>();
      for (AXF_OBJ_ReconciliationAllocation__c row : [
        SELECT Id
        FROM AXF_OBJ_ReconciliationAllocation__c
        WHERE AXF_RA_LKP_BankTransaction__c = :source.Id
      ]) {
        shares.add(
          new AXF_OBJ_ReconciliationAllocation__Share(
            ParentId = row.Id,
            UserOrGroupId = participant.Id,
            AccessLevel = 'Read',
            RowCause = 'Manual'
          )
        );
      }
      Assert.areEqual(3, shares.size(), 'two applications and a reversal');
      insert shares;
    }
    System.runAs(participant) {
      Test.startTest();
      ALT_CLS_ReconciliationQueueService.QueueView everything = queue(all());
      ALT_CLS_ReconciliationQueueService.QueueView pending = queue(
        new ALT_CLS_ReconciliationQueueService.QueueQuery()
      );
      ALT_CLS_ReconciliationQueueService.allocationCapOverride = 3;
      ALT_CLS_ReconciliationQueueService.QueueView capped = queue(all());
      Test.stopTest();
      Assert.isFalse(everything.canReconcile);
      Assert.areEqual(new Set<Id>{ source.Id }, idsOf(everything.pending));
      ALT_CLS_ReconciliationQueueService.QueueLine line = everything.pending[0];
      Assert.areEqual('PARTIAL', line.status, '60 applied after the reversal');
      Assert.areEqual(60, line.allocated);
      Assert.areEqual(40, line.residual);
      Assert.isFalse(line.canSuggest);
      Assert.areEqual(
        new Set<Id>{ source.Id },
        idsOf(pending.pending),
        'an allocated but partial fact stays in the default view'
      );
      Assert.areEqual(new Set<Id>{ source.Id }, idsOf(capped.unverified));
      Assert.areEqual('UNVERIFIED', capped.unverified[0].status);
      Assert.areEqual(0, capped.pending.size());
      Assert.areEqual(1, capped.countUnverified);
    }
  }

  private static AXF_OBJ_FinancialTransaction__c newEntry(
    Id holderId,
    Id bankId,
    Decimal amount,
    Date onDate,
    String key
  ) {
    return new AXF_OBJ_FinancialTransaction__c(
      AXF_FTX_LKP_Account__c = holderId,
      AXF_FTX_LKP_BankAccount__c = bankId,
      AXF_FTX_NUM_Magnitude__c = amount,
      AXF_FTX_PKL_Direction__c = 'DEBIT',
      AXF_FTX_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_FTX_DAT_PurchaseDate__c = onDate,
      AXF_FTX_DAT_DueDate__c = onDate,
      AXF_FTX_TXT_Description__c = 'Entry ' + key,
      AXF_FTX_PKL_PlanKind__c = 'PLANNED',
      AXF_FTX_PKL_Status__c = 'PLANNED',
      AXF_FTX_NUM_Version__c = 0,
      AXF_FTX_EXI_ClientRequestId__c = 'ftx-154-' + key
    );
  }

  private static ALT_CLS_RealizationService.Input application(
    Id targetId,
    AXF_OBJ_BankAccountTransaction__c source,
    Decimal amount,
    String key
  ) {
    ALT_CLS_RealizationService.Input input = new ALT_CLS_RealizationService.Input();
    input.targetId = targetId;
    input.sourceId = source.Id;
    input.sourceKind = 'BANK';
    input.amount = amount;
    input.recognitionDate = source.AXF_BAT_DAT_Date__c;
    input.targetVersion = 0;
    input.sourceVersion = 0;
    input.operationKey = key;
    return input;
  }

  @IsTest
  static void aCappedReadIsFlaggedTruncated() {
    System.runAs(byAlias(GESTOR)) {
      Account owner = holder('Holder 154 cap');
      AXF_OBJ_BankAccount__c account = bank(owner.Id, '****1548');
      List<AXF_OBJ_BankAccountTransaction__c> rows = new List<AXF_OBJ_BankAccountTransaction__c>();
      for (
        Integer i = 0; i <= ALT_CLS_ReconciliationQueueService.MAX_FACTS; i++
      ) {
        rows.add(
          newBankFact(
            account.Id,
            10 + i,
            ago(1),
            'Bulk ' + i,
            'bulk-' + i,
            'PLUGGY'
          )
        );
      }
      insert rows;
      Test.startTest();
      ALT_CLS_ReconciliationQueueService.QueueView view = queue(
        new ALT_CLS_ReconciliationQueueService.QueueQuery()
      );
      Test.stopTest();
      Assert.isTrue(view.truncated, 'never cut silently');
      Assert.areEqual(
        ALT_CLS_ReconciliationQueueService.MAX_FACTS,
        view.pending.size()
      );
    }
  }
}
