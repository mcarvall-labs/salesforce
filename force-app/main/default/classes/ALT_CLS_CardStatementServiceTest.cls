/**
 * @description AXF-152: credit-card screen. Authorized cards with limits and calendar days, the
 * closing defined inline (AXF-35 draft + activate), invoices derived from the calendar with total,
 * closing and due dates, filters inside the invoice, derived reconciliation status without
 * duplicating an allocated manual entry, the AXF-MATCHING@1.1.0 window and one-click confirmation
 * (card source), plus the read-only view of a user without the link capability.
 */
@IsTest(isParallel=false)
// API 62: AXON_DEV enforces FLS on plain test DML under runAs from API 67 onwards.
private class ALT_CLS_CardStatementServiceTest {
  private static final String GESTOR = 'axf152g';
  private static final String PEER = 'axf152p';
  private static final String READER = 'axf152r';
  private static final Date TODAY = Date.newInstance(2026, 9, 15);
  private static final List<String> RULE_FIELDS = new List<String>{
    'AXF_CBR_DAT_EffectiveTo__c',
    'AXF_CBR_NUM_ClosingDay__c',
    'AXF_CBR_NUM_DueDayOffset__c',
    'AXF_CBR_NUM_Version__c',
    'AXF_CBR_PKL_ClosingDayAdjustment__c',
    'AXF_CBR_PKL_DueDayAdjustment__c',
    'AXF_CBR_TXT_CalendarPolicyVersion__c'
  };
  private static final Map<String, List<String>> READ_FIELDS = new Map<String, List<String>>{
    'AXF_OBJ_CreditCard__c' => new List<String>{
      'AXF_CC_LKP_Account__c',
      'AXF_CC_TXT_InstitutionName__c',
      'AXF_CC_LKP_BankInstitution__c',
      'AXF_CC_TXT_LastFourMasked__c',
      'AXF_CC_TXT_Brand__c',
      'AXF_CC_CUR_CreditLimit__c',
      'AXF_CC_CUR_AvailableLimit__c',
      'AXF_CC_TXT_CurrencyIsoCode__c',
      'AXF_CC_LKP_Connection__c'
    },
    'AXF_OBJ_CreditCardTransaction__c' => new List<String>{
      'AXF_CCT_TXT_Description__c',
      'AXF_CCT_PKL_Status__c'
    },
    'AXF_OBJ_ReconciliationAllocation__c' => new List<String>{
      'AXF_RA_LKP_CardTransaction__c',
      'AXF_RA_LKP_FinancialTransaction__c',
      'AXF_RA_PKL_Kind__c',
      'AXF_RA_NUM_Magnitude__c'
    },
    'AXF_OBJ_CardBillingCycleRule__c' => RULE_FIELDS,
    'AXF_OBJ_FinancialTransaction__c' => new List<String>{
      'AXF_FTX_PKL_PlanKind__c'
    }
  };

  private static User byAlias(String alias) {
    return [SELECT Id FROM User WHERE Alias = :alias LIMIT 1];
  }

  /** Read-only object access plus read FLS, and no custom permission at all. */
  private static PermissionSet readOnly(String name, Set<String> objects) {
    PermissionSet result = new PermissionSet(Name = name, Label = name);
    insert result;
    List<ObjectPermissions> access = new List<ObjectPermissions>();
    List<FieldPermissions> fields = new List<FieldPermissions>();
    for (String objectName : objects) {
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
    // Check-only deploys do not apply the branch's permission-set changes to test users: the
    // read-only cycle-rule access this branch grants is mirrored by test sets (never write).
    PermissionSet ruleRead = readOnly(
      'AXF152_TestCycleRuleRead',
      new Set<String>{ 'AXF_OBJ_CardBillingCycleRule__c' }
    );
    PermissionSet cardRead = readOnly(
      'AXF152_TestCardRead',
      new Set<String>{
        'AXF_OBJ_CreditCard__c',
        'AXF_OBJ_CreditCardTransaction__c',
        'AXF_OBJ_ReconciliationAllocation__c',
        'AXF_OBJ_CardBillingCycleRule__c',
        'AXF_OBJ_FinancialTransaction__c'
      }
    );
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
    for (Integer i = 0; i < 2; i++) {
      for (
        Id permissionSetId : new List<Id>{
          permissionSets.get('AXF_PS_GestorFinanceiro'),
          permissionSets.get('AXF_PS_FinancialEntry'),
          permissionSets.get('AXF_PS_Realization'),
          ruleRead.Id
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
    // The reader: FinancialEntry + Participante, no Realization (so no link capability).
    for (
      Id permissionSetId : new List<Id>{
        permissionSets.get('AXF_PS_FinancialEntry'),
        permissionSets.get('AXF_PS_Participante'),
        cardRead.Id
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

  /** Weekdays are business days: the tests never depend on the org calendar. */
  private class Weekdays implements ALT_CLS_CardInvoiceCalendar.BusinessDays {
    public Boolean isBusinessDay(Date onDate) {
      return !ALT_CLS_CardInvoiceCalendar.isWeekend(onDate);
    }
  }

  private static void configure(Boolean canConfigure) {
    ALT_CLS_CardStatementService.canConfigureOverride = canConfigure;
    ALT_CLS_CardStatementService.businessDaysOverride = new Weekdays();
    ALT_CLS_CardStatementService.todayOverride = TODAY;
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

  private static AXF_OBJ_CreditCard__c card(
    Id holderId,
    Decimal creditLimit,
    Decimal availableLimit
  ) {
    AXF_OBJ_CreditCard__c result = new AXF_OBJ_CreditCard__c(
      AXF_CC_LKP_Account__c = holderId,
      AXF_CC_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_CC_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_CC_TXT_InstitutionName__c = 'Banco 152',
      AXF_CC_TXT_LastFourMasked__c = '1520',
      AXF_CC_TXT_Brand__c = 'VISA',
      AXF_CC_CUR_CreditLimit__c = creditLimit,
      AXF_CC_CUR_AvailableLimit__c = availableLimit
    );
    insert result;
    return result;
  }

  private static AXF_OBJ_CardBillingCycleRule__c activeRule(
    Id cardId,
    Integer closingDay,
    Integer dueOffset
  ) {
    return activeRule(cardId, d(2025, 1, 1), null, closingDay, dueOffset);
  }

  private static AXF_OBJ_CardBillingCycleRule__c activeRule(
    Id cardId,
    Date effectiveFrom,
    Date effectiveTo,
    Integer closingDay,
    Integer dueOffset
  ) {
    AXF_OBJ_CardBillingCycleRule__c result = new AXF_OBJ_CardBillingCycleRule__c(
      AXF_CBR_LKP_CreditCard__c = cardId,
      AXF_CBR_PKL_State__c = 'ACTIVE',
      AXF_CBR_DAT_EffectiveFrom__c = effectiveFrom,
      AXF_CBR_DAT_EffectiveTo__c = effectiveTo,
      AXF_CBR_NUM_ClosingDay__c = closingDay,
      AXF_CBR_PKL_ClosingDayAdjustment__c = 'NONE',
      AXF_CBR_NUM_DueDayOffset__c = dueOffset,
      AXF_CBR_PKL_DueDayAdjustment__c = 'NONE',
      AXF_CBR_TXT_CalendarPolicyVersion__c = 'CAL-1.0.0',
      AXF_CBR_TXT_TimeZone__c = 'America/Sao_Paulo',
      AXF_CBR_NUM_Version__c = 1
    );
    insert result;
    return result;
  }

  private static AXF_OBJ_CreditCardTransaction__c fact(
    Id cardId,
    Decimal amount,
    Date onDate,
    String description,
    String key
  ) {
    return fact(cardId, amount, onDate, description, key, 'DEBIT');
  }

  private static AXF_OBJ_CreditCardTransaction__c fact(
    Id cardId,
    Decimal amount,
    Date onDate,
    String description,
    String key,
    String direction
  ) {
    AXF_OBJ_CreditCardTransaction__c result = newFact(
      cardId,
      amount,
      onDate,
      description,
      key
    );
    result.AXF_CCT_PKL_Direction__c = direction;
    insert result;
    return result;
  }

  private static AXF_OBJ_CreditCardTransaction__c newFact(
    Id cardId,
    Decimal amount,
    Date onDate,
    String description,
    String key
  ) {
    return new AXF_OBJ_CreditCardTransaction__c(
      AXF_CCT_MDR_CreditCard__c = cardId,
      AXF_CCT_NUM_Magnitude__c = amount,
      AXF_CCT_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_CCT_PKL_Direction__c = 'DEBIT',
      AXF_CCT_DAT_Date__c = onDate,
      AXF_CCT_TXT_Description__c = description,
      AXF_CCT_EXI_SourceKey__c = 'axf152-' + key,
      AXF_CCT_PKL_Source__c = 'PLUGGY',
      AXF_CCT_PKL_Status__c = 'POSTED',
      AXF_CCT_NUM_Version__c = 0
    );
  }

  private static AXF_OBJ_FinancialTransaction__c entry(
    Id holderId,
    Id cardId,
    Decimal amount,
    Date onDate,
    String key
  ) {
    return entry(holderId, cardId, amount, onDate, onDate, key);
  }

  private static AXF_OBJ_FinancialTransaction__c entry(
    Id holderId,
    Id cardId,
    Decimal amount,
    Date purchaseDate,
    Date dueDate,
    String key
  ) {
    AXF_OBJ_FinancialTransaction__c result = newEntry(
      holderId,
      cardId,
      amount,
      purchaseDate,
      dueDate,
      key
    );
    insert result;
    return result;
  }

  private static AXF_OBJ_FinancialTransaction__c newEntry(
    Id holderId,
    Id cardId,
    Decimal amount,
    Date purchaseDate,
    Date dueDate,
    String key
  ) {
    return new AXF_OBJ_FinancialTransaction__c(
      AXF_FTX_LKP_Account__c = holderId,
      AXF_FTX_LKP_CreditCard__c = cardId,
      AXF_FTX_NUM_Magnitude__c = amount,
      AXF_FTX_PKL_Direction__c = 'DEBIT',
      AXF_FTX_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_FTX_DAT_PurchaseDate__c = purchaseDate,
      AXF_FTX_DAT_DueDate__c = dueDate,
      AXF_FTX_TXT_Description__c = 'Entry ' + key,
      AXF_FTX_PKL_PlanKind__c = 'PLANNED',
      AXF_FTX_PKL_Status__c = 'PLANNED',
      AXF_FTX_NUM_Version__c = 0,
      AXF_FTX_EXI_ClientRequestId__c = 'ftx-152-' + key
    );
  }

  private static ALT_CLS_CardStatementService.InvoiceQuery month(
    Id cardId,
    Integer year,
    Integer month
  ) {
    ALT_CLS_CardStatementService.InvoiceQuery query = new ALT_CLS_CardStatementService.InvoiceQuery();
    query.creditCardId = cardId;
    query.year = year;
    query.month = month;
    return query;
  }

  private static ALT_CLS_BankStatementService.LineView line(
    ALT_CLS_CardStatementService.InvoiceView view,
    Id recordId
  ) {
    for (ALT_CLS_BankStatementService.LineView l : view.lines) {
      if (l.recordId == recordId) {
        return l;
      }
    }
    return null;
  }

  private static Map<Id, ALT_CLS_CardStatementService.CardView> cardsById() {
    Map<Id, ALT_CLS_CardStatementService.CardView> result = new Map<Id, ALT_CLS_CardStatementService.CardView>();
    for (
      ALT_CLS_CardStatementService.CardView v : new ALT_CLS_CardStatementService()
        .listCards()
    ) {
      result.put(v.creditCardId, v);
    }
    return result;
  }

  private static AXF_OBJ_CardBillingCycleRule__c ruleOf(Id cardId, Date since) {
    return [
      SELECT
        AXF_CBR_PKL_State__c,
        AXF_CBR_DAT_EffectiveFrom__c,
        AXF_CBR_DAT_EffectiveTo__c,
        AXF_CBR_NUM_ClosingDay__c,
        AXF_CBR_NUM_DueDayOffset__c,
        AXF_CBR_PKL_ClosingDayAdjustment__c,
        AXF_CBR_PKL_DueDayAdjustment__c,
        AXF_CBR_TXT_CalendarPolicyVersion__c,
        AXF_CBR_TXT_TimeZone__c
      FROM AXF_OBJ_CardBillingCycleRule__c
      WHERE
        AXF_CBR_LKP_CreditCard__c = :cardId
        AND AXF_CBR_DAT_EffectiveFrom__c >= :since
      ORDER BY AXF_CBR_DAT_EffectiveFrom__c DESC
      LIMIT 1
    ];
  }

  private static ALT_CLS_BankStatementService.SuggestionPage suggest(
    Id cardId,
    String kind,
    Id recordId
  ) {
    ALT_CLS_CardStatementService.SuggestionQuery query = new ALT_CLS_CardStatementService.SuggestionQuery();
    query.creditCardId = cardId;
    query.lineKind = kind;
    query.recordId = recordId;
    return new ALT_CLS_CardStatementService().suggest(query);
  }

  private static ALT_CLS_CardStatementService.ConfirmInput confirmOf(
    Id cardId,
    ALT_CLS_BankStatementService.SuggestionView s,
    String key
  ) {
    ALT_CLS_CardStatementService.ConfirmInput input = new ALT_CLS_CardStatementService.ConfirmInput();
    input.creditCardId = cardId;
    input.sourceId = s.sourceId;
    input.sourceVersion = s.sourceVersion;
    input.targetId = s.targetId;
    input.targetVersion = s.targetVersion;
    input.operationKey = key;
    return input;
  }

  private static ALT_CLS_CardStatementService.ClosingInput closing(
    Id cardId,
    Integer closingDay,
    Integer dueDay
  ) {
    ALT_CLS_CardStatementService.ClosingInput input = new ALT_CLS_CardStatementService.ClosingInput();
    input.creditCardId = cardId;
    input.closingDay = closingDay;
    input.dueDay = dueDay;
    return input;
  }

  private static String failure(Callable call) {
    try {
      call.call('run', null);
    } catch (ALT_CLS_CardStatementService.CardStatementException expected) {
      return expected.getMessage();
    }
    return 'NO_EXCEPTION';
  }

  private class InvoiceCall implements Callable {
    ALT_CLS_CardStatementService.InvoiceQuery query;
    InvoiceCall(ALT_CLS_CardStatementService.InvoiceQuery query) {
      this.query = query;
    }
    public Object call(String action, Map<String, Object> args) {
      return new ALT_CLS_CardStatementService().invoice(query);
    }
  }

  private class ClosingCall implements Callable {
    ALT_CLS_CardStatementService.ClosingInput input;
    ClosingCall(ALT_CLS_CardStatementService.ClosingInput input) {
      this.input = input;
    }
    public Object call(String action, Map<String, Object> args) {
      return new ALT_CLS_CardStatementService().defineClosing(input);
    }
  }

  private class ConfirmCall implements Callable {
    ALT_CLS_CardStatementService.ConfirmInput input;
    ConfirmCall(ALT_CLS_CardStatementService.ConfirmInput input) {
      this.input = input;
    }
    public Object call(String action, Map<String, Object> args) {
      return new ALT_CLS_CardStatementService().confirm(input);
    }
  }

  private class SuggestCall implements Callable {
    Id cardId;
    String kind;
    Id recordId;
    SuggestCall(Id cardId, String kind, Id recordId) {
      this.cardId = cardId;
      this.kind = kind;
      this.recordId = recordId;
    }
    public Object call(String action, Map<String, Object> args) {
      return suggest(cardId, kind, recordId);
    }
  }

  // -------------------------------------------------------------- tests

  @IsTest
  static void listsCardsWithLimitsAndCalendarDays() {
    System.runAs(byAlias(GESTOR)) {
      configure(true);
      Account owner = holder('Holder 152 list');
      AXF_OBJ_CreditCard__c pluggy = card(owner.Id, 5000, 3200);
      AXF_OBJ_CreditCard__c manual = card(owner.Id, null, null);
      AXF_OBJ_CreditCard__c future = card(owner.Id, null, null);
      AXF_OBJ_CreditCard__c unversioned = card(owner.Id, null, null);
      activeRule(pluggy.Id, 5, 7);
      activeRule(future.Id, d(2026, 10, 1), null, 5, 7);
      insert new AXF_OBJ_CardBillingCycleRule__c(
        AXF_CBR_LKP_CreditCard__c = unversioned.Id,
        AXF_CBR_PKL_State__c = 'ACTIVE',
        AXF_CBR_DAT_EffectiveFrom__c = d(2025, 1, 1),
        AXF_CBR_NUM_ClosingDay__c = 5,
        AXF_CBR_NUM_DueDayOffset__c = 7,
        AXF_CBR_TXT_TimeZone__c = 'America/Sao_Paulo'
      );
      Test.startTest();
      Map<Id, ALT_CLS_CardStatementService.CardView> byId = cardsById();
      Test.stopTest();
      Assert.areEqual(4, byId.size());
      ALT_CLS_CardStatementService.CardView withRule = byId.get(pluggy.Id);
      Assert.areEqual(5000, withRule.creditLimit);
      Assert.areEqual(3200, withRule.availableLimit);
      Assert.areEqual('Banco 152', withRule.institutionName);
      Assert.areEqual('VISA', withRule.brand);
      Assert.areEqual('1520', withRule.lastFour);
      Assert.areEqual('Holder 152 list', withRule.holderLabel);
      Assert.isTrue(withRule.hasCalendar);
      Assert.areEqual(5, withRule.closingDay);
      // 15/09 belongs to the October invoice: closing 05/10 + 7 = 12/10.
      Assert.areEqual(12, withRule.dueDay);
      Assert.isFalse(withRule.canDefineClosing, 'a rule in force is final');
      ALT_CLS_CardStatementService.CardView bare = byId.get(manual.Id);
      Assert.isNull(bare.creditLimit, 'a manual card has no limit');
      Assert.isNull(bare.availableLimit);
      Assert.isFalse(bare.hasCalendar);
      Assert.isNull(bare.closingDay);
      Assert.isTrue(bare.canDefineClosing);
      Assert.isFalse(byId.get(future.Id).hasCalendar);
      Assert.isFalse(
        byId.get(future.Id).canDefineClosing,
        'a future-dated ACTIVE rule would only conflict'
      );
      Assert.isFalse(byId.get(unversioned.Id).hasCalendar);
      Assert.isFalse(byId.get(unversioned.Id).canDefineClosing);
      Assert.areEqual(
        'CONFLICT',
        failure(new ClosingCall(closing(future.Id, 5, 12)))
      );
    }
  }

  @IsTest
  static void foreignCardsDiscloseNothing() {
    AXF_OBJ_CreditCard__c owned;
    System.runAs(byAlias(GESTOR)) {
      owned = card(holder('Holder 152 owner').Id, 100, 100);
    }
    System.runAs(byAlias(PEER)) {
      configure(true);
      Assert.areEqual(0, new ALT_CLS_CardStatementService().listCards().size());
      Assert.areEqual(
        'NOT_ACCESSIBLE',
        failure(new InvoiceCall(month(owned.Id, 2026, 9)))
      );
      Assert.areEqual(
        'NOT_ACCESSIBLE',
        failure(new ClosingCall(closing(owned.Id, 5, 12)))
      );
      Assert.areEqual(
        'NOT_ACCESSIBLE',
        failure(new SuggestCall(owned.Id, 'FACT', owned.Id))
      );
      Assert.areEqual(
        'INVALID_INPUT',
        failure(new InvoiceCall(month(null, 2026, 9)))
      );
    }
  }

  @IsTest
  static void definesTheClosingOfACardWithoutCalendar() {
    System.runAs(byAlias(GESTOR)) {
      configure(true);
      Account owner = holder('Holder 152 closing');
      AXF_OBJ_CreditCard__c target = card(owner.Id, null, null);
      AXF_OBJ_CreditCard__c empty = card(owner.Id, null, null);
      AXF_OBJ_CreditCardTransaction__c pending = newFact(
        target.Id,
        5,
        d(2026, 6, 1),
        'Pending',
        'pending'
      );
      pending.AXF_CCT_PKL_Status__c = 'PENDING';
      insert pending;
      fact(target.Id, 10, d(2026, 8, 6), 'Oldest posted', 'old');
      fact(target.Id, 20, d(2026, 9, 10), 'Newest', 'new');
      Test.startTest();
      // Read-only access to the rule object: the AXF-35 flow writes it, gated by configuration.
      Assert.isFalse(
        Schema.SObjectType.AXF_OBJ_CardBillingCycleRule__c.isCreateable()
      );
      ALT_CLS_CardStatementService.CardView view = new ALT_CLS_CardStatementService()
        .defineClosing(closing(target.Id, 5, 12));
      String again = failure(new ClosingCall(closing(target.Id, 6, 13)));
      new ALT_CLS_CardStatementService()
        .defineClosing(closing(empty.Id, 31, 10));
      Test.stopTest();
      Assert.isTrue(view.hasCalendar);
      Assert.areEqual(5, view.closingDay);
      // 15/09 is after the closing 07/09 (05/09 is a Saturday): October invoice, due 12/10.
      Assert.areEqual(12, view.dueDay);
      Assert.isFalse(view.canDefineClosing);
      Assert.areEqual('CONFLICT', again, 'a rule in force is never replaced');
      AXF_OBJ_CardBillingCycleRule__c rule = ruleOf(target.Id, d(2000, 1, 1));
      Assert.areEqual('ACTIVE', rule.AXF_CBR_PKL_State__c);
      Assert.areEqual(
        d(2026, 8, 6),
        rule.AXF_CBR_DAT_EffectiveFrom__c,
        'valid from the oldest posted purchase'
      );
      Assert.isNull(rule.AXF_CBR_DAT_EffectiveTo__c);
      Assert.areEqual(7, rule.AXF_CBR_NUM_DueDayOffset__c);
      Assert.areEqual('FOLLOWING', rule.AXF_CBR_PKL_ClosingDayAdjustment__c);
      Assert.areEqual('FOLLOWING', rule.AXF_CBR_PKL_DueDayAdjustment__c);
      Assert.areEqual('CAL-1.0.0', rule.AXF_CBR_TXT_CalendarPolicyVersion__c);
      Assert.areEqual('America/Sao_Paulo', rule.AXF_CBR_TXT_TimeZone__c);
      Assert.areEqual(
        d(2026, 9, 1),
        ruleOf(empty.Id, d(2000, 1, 1)).AXF_CBR_DAT_EffectiveFrom__c,
        'no purchase: the current month'
      );
      Assert.areEqual(
        2,
        [SELECT COUNT() FROM AXF_OBJ_CardBillingCycleRule__c],
        'the refused command left no draft behind'
      );
    }
  }

  @IsTest
  static void aNewClosingStartsWhereTheClosedRuleEnded() {
    System.runAs(byAlias(GESTOR)) {
      configure(true);
      Account owner = holder('Holder 152 closed rule');
      AXF_OBJ_CreditCard__c older = card(owner.Id, null, null);
      AXF_OBJ_CreditCard__c later = card(owner.Id, null, null);
      activeRule(older.Id, d(2025, 1, 1), d(2026, 8, 20), 5, 7);
      activeRule(later.Id, d(2025, 1, 1), d(2026, 5, 1), 5, 7);
      fact(older.Id, 10, d(2026, 3, 1), 'Before the end', 'closed-old');
      fact(later.Id, 10, d(2026, 7, 1), 'After the end', 'closed-new');
      Test.startTest();
      Map<Id, ALT_CLS_CardStatementService.CardView> before = cardsById();
      new ALT_CLS_CardStatementService()
        .defineClosing(closing(older.Id, 10, 20));
      new ALT_CLS_CardStatementService()
        .defineClosing(closing(later.Id, 10, 20));
      Test.stopTest();
      Assert.isTrue(before.get(older.Id).canDefineClosing, 'nothing in force');
      Assert.areEqual(
        d(2026, 8, 20),
        ruleOf(older.Id, d(2026, 1, 1)).AXF_CBR_DAT_EffectiveFrom__c
      );
      Assert.areEqual(
        d(2026, 5, 1),
        ruleOf(later.Id, d(2026, 1, 1)).AXF_CBR_DAT_EffectiveFrom__c,
        'no gap after the closed rule'
      );
      Assert.areEqual(
        4,
        [
          SELECT COUNT()
          FROM AXF_OBJ_CardBillingCycleRule__c
          WHERE AXF_CBR_PKL_State__c = 'ACTIVE'
        ]
      );
    }
  }

  @IsTest
  static void theDueOffsetDoesNotDependOnTheMonthOfTheSave() {
    System.runAs(byAlias(GESTOR)) {
      configure(true);
      Account owner = holder('Holder 152 offset');
      AXF_OBJ_CreditCard__c february = card(owner.Id, null, null);
      AXF_OBJ_CreditCard__c sameDays = card(owner.Id, null, null);
      AXF_OBJ_CreditCard__c january = card(owner.Id, null, null);
      Test.startTest();
      ALT_CLS_CardStatementService.todayOverride = d(2027, 2, 10);
      new ALT_CLS_CardStatementService()
        .defineClosing(closing(february.Id, 29, 30));
      ALT_CLS_CardStatementService.CardView feb = new ALT_CLS_CardStatementService()
        .defineClosing(closing(sameDays.Id, 25, 5));
      ALT_CLS_CardStatementService.todayOverride = d(2027, 1, 12);
      ALT_CLS_CardStatementService.CardView jan = new ALT_CLS_CardStatementService()
        .defineClosing(closing(january.Id, 25, 5));
      Test.stopTest();
      Assert.areEqual(
        1,
        ruleOf(february.Id, d(2000, 1, 1)).AXF_CBR_NUM_DueDayOffset__c,
        'closing 29, due 30 even when saved in February'
      );
      Assert.areEqual(
        10,
        ruleOf(sameDays.Id, d(2000, 1, 1)).AXF_CBR_NUM_DueDayOffset__c
      );
      Assert.areEqual(
        10,
        ruleOf(january.Id, d(2000, 1, 1)).AXF_CBR_NUM_DueDayOffset__c,
        'the same offset in a 31-day month'
      );
      // Shown due day = day of the due date derived for the current invoice.
      // February: closing 25/02 + 10 = 07/03 (Sunday) → 08/03.
      Assert.areEqual(8, feb.dueDay);
      // January: closing 25/01 + 10 = 04/02.
      Assert.areEqual(4, jan.dueDay);
    }
  }

  @IsTest
  static void refusesAnInvalidOrUnauthorizedClosing() {
    System.runAs(byAlias(GESTOR)) {
      Account owner = holder('Holder 152 refusal');
      AXF_OBJ_CreditCard__c target = card(owner.Id, null, null);
      configure(true);
      Assert.areEqual(
        'INVALID_INPUT',
        failure(new ClosingCall(closing(target.Id, 32, 12)))
      );
      Assert.areEqual(
        'INVALID_INPUT',
        failure(new ClosingCall(closing(target.Id, 5, 0)))
      );
      Assert.areEqual(
        'INVALID_INPUT',
        failure(new ClosingCall(closing(target.Id, null, 12)))
      );
      Assert.areEqual('INVALID_INPUT', failure(new ClosingCall(null)));
      configure(false);
      Assert.areEqual(
        'NOT_ALLOWED',
        failure(new ClosingCall(closing(target.Id, 5, 12)))
      );
      Assert.isFalse(cardsById().get(target.Id).canDefineClosing);
      Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_CardBillingCycleRule__c]);
    }
  }

  @IsTest
  static void buildsTheInvoiceFromTheCalendarWithTotalsAndFilters() {
    System.runAs(byAlias(GESTOR)) {
      configure(true);
      Account owner = holder('Holder 152 invoice');
      AXF_OBJ_CreditCard__c target = card(owner.Id, 1000, 800);
      activeRule(target.Id, 5, 7);
      AXF_OBJ_CreditCardTransaction__c before = fact(
        target.Id,
        50,
        d(2026, 8, 5),
        'Padaria agosto',
        'before'
      );
      AXF_OBJ_CreditCardTransaction__c first = fact(
        target.Id,
        80,
        d(2026, 8, 6),
        'Mercado central',
        'first'
      );
      AXF_OBJ_CreditCardTransaction__c last = fact(
        target.Id,
        300,
        d(2026, 9, 5),
        'Mercado grande',
        'last'
      );
      AXF_OBJ_CreditCardTransaction__c refund = fact(
        target.Id,
        20,
        d(2026, 8, 20),
        'Estorno loja',
        'refund',
        'CREDIT'
      );
      AXF_OBJ_CreditCardTransaction__c dollars = newFact(
        target.Id,
        999,
        d(2026, 8, 15),
        'Loja exterior',
        'usd'
      );
      dollars.AXF_CCT_TXT_CurrencyIsoCode__c = 'USD';
      insert dollars;
      AXF_OBJ_CreditCardTransaction__c after = fact(
        target.Id,
        70,
        d(2026, 9, 6),
        'Farmacia outubro',
        'after'
      );
      // Purchase inside the September invoice, due date after its closing.
      AXF_OBJ_FinancialTransaction__c manual = entry(
        owner.Id,
        target.Id,
        42,
        d(2026, 8, 25),
        d(2026, 9, 20),
        'manual'
      );
      Test.startTest();
      ALT_CLS_CardStatementService service = new ALT_CLS_CardStatementService();
      ALT_CLS_CardStatementService.InvoiceView sep = service.invoice(
        month(target.Id, 2026, 9)
      );
      ALT_CLS_CardStatementService.InvoiceView aug = service.invoice(
        month(target.Id, 2026, 8)
      );
      ALT_CLS_CardStatementService.InvoiceView oct = service.invoice(
        month(target.Id, 2026, 10)
      );
      ALT_CLS_CardStatementService.InvoiceQuery filtered = month(
        target.Id,
        2026,
        9
      );
      filtered.minAmount = 60;
      filtered.maxAmount = 100;
      filtered.term = 'MERCADO';
      ALT_CLS_CardStatementService.InvoiceView combined = service.invoice(
        filtered
      );
      ALT_CLS_CardStatementService.InvoiceQuery dated = month(
        target.Id,
        2026,
        9
      );
      dated.fromDate = d(2026, 9, 1);
      dated.toDate = d(2026, 9, 30);
      ALT_CLS_CardStatementService.InvoiceView inside = service.invoice(dated);
      Test.stopTest();
      Assert.areEqual('RESOLVED', sep.outcome);
      Assert.areEqual(d(2026, 8, 6), sep.fromDate, 'after C(ago)=05/08');
      Assert.areEqual(d(2026, 9, 5), sep.toDate, 'up to C(set)=05/09');
      Assert.areEqual(d(2026, 9, 5), sep.closingDate);
      Assert.areEqual(d(2026, 9, 12), sep.dueDate);
      Assert.areEqual(5, sep.lines.size(), 'four facts and one entry');
      Assert.areEqual(last.Id, sep.lines[0].recordId, 'newest first');
      Assert.areEqual(360, sep.total, '80 + 300 - 20 (refund), BRL only');
      Assert.isTrue(sep.mixedCurrency, 'the USD purchase is flagged');
      Assert.isFalse(sep.truncated);
      Assert.areEqual(42, sep.plannedTotal);
      Assert.areEqual('ENTRY', line(sep, manual.Id).lineKind);
      Assert.areEqual(d(2026, 8, 25), line(sep, manual.Id).lineDate);
      Assert.areEqual('UNRECONCILED', line(sep, first.Id).status);
      Assert.isNotNull(line(sep, refund.Id));
      Assert.areEqual(1, aug.lines.size());
      Assert.areEqual(before.Id, aug.lines[0].recordId);
      Assert.isFalse(aug.mixedCurrency);
      Assert.areEqual(1, oct.lines.size());
      Assert.areEqual(after.Id, oct.lines[0].recordId);
      Assert.areEqual(1, combined.lines.size(), 'every filter applies');
      Assert.areEqual(first.Id, combined.lines[0].recordId);
      Assert.areEqual(360, combined.total, 'the total ignores the filters');
      // The date filter narrows the September invoice; 06/09 (October) never appears.
      Assert.areEqual(1, inside.lines.size());
      Assert.areEqual(last.Id, inside.lines[0].recordId);
      Assert.isFalse(inside.customPeriod);
      Assert.areEqual('RESOLVED', inside.outcome);
      Assert.areEqual(d(2026, 8, 6), inside.fromDate);
      Assert.areEqual(d(2026, 9, 5), inside.closingDate);
      Assert.areEqual(d(2026, 9, 12), inside.dueDate);
    }
  }

  @IsTest
  static void anInvoiceAcrossARuleChangeFollowsEachPurchaseRule() {
    System.runAs(byAlias(GESTOR)) {
      configure(true);
      Account owner = holder('Holder 152 rule change');
      AXF_OBJ_CreditCard__c target = card(owner.Id, null, null);
      activeRule(target.Id, d(2025, 1, 1), d(2026, 8, 20), 5, 7);
      activeRule(target.Id, d(2026, 8, 20), null, 20, 10);
      AXF_OBJ_CreditCardTransaction__c early = fact(
        target.Id,
        30,
        d(2026, 8, 3),
        'Antes do fechamento antigo',
        'change-early'
      );
      AXF_OBJ_CreditCardTransaction__c oldRule = fact(
        target.Id,
        40,
        d(2026, 8, 10),
        'Regra antiga',
        'change-old'
      );
      AXF_OBJ_CreditCardTransaction__c newRule = fact(
        target.Id,
        50,
        d(2026, 8, 25),
        'Regra nova',
        'change-new'
      );
      Test.startTest();
      ALT_CLS_CardStatementService service = new ALT_CLS_CardStatementService();
      ALT_CLS_CardStatementService.InvoiceView sep = service.invoice(
        month(target.Id, 2026, 9)
      );
      ALT_CLS_CardStatementService.InvoiceView aug = service.invoice(
        month(target.Id, 2026, 8)
      );
      Test.stopTest();
      Assert.areEqual(d(2026, 9, 20), sep.closingDate);
      Assert.isNotNull(line(sep, oldRule.Id), '10/08 closes on 05/09');
      Assert.isNotNull(line(sep, newRule.Id));
      Assert.areEqual(2, sep.lines.size());
      Assert.areEqual(90, sep.total);
      Assert.areEqual(1, aug.lines.size());
      Assert.areEqual(early.Id, aug.lines[0].recordId);
    }
  }

  @IsTest
  static void withoutCalendarTheCivilMonthIsFlagged() {
    System.runAs(byAlias(GESTOR)) {
      configure(true);
      Account owner = holder('Holder 152 blocked');
      AXF_OBJ_CreditCard__c target = card(owner.Id, null, null);
      AXF_OBJ_CreditCardTransaction__c inside = fact(
        target.Id,
        15,
        d(2026, 9, 3),
        'Cafe',
        'blocked-in'
      );
      fact(target.Id, 25, d(2026, 8, 31), 'Cinema', 'blocked-out');
      Test.startTest();
      ALT_CLS_CardStatementService.InvoiceView sep = new ALT_CLS_CardStatementService()
        .invoice(month(target.Id, 2026, 9));
      Test.stopTest();
      Assert.areEqual('BLOCKED', sep.outcome);
      Assert.areEqual('NO_RULE', sep.blockedReason);
      Assert.areEqual(d(2026, 9, 1), sep.fromDate);
      Assert.areEqual(d(2026, 9, 30), sep.toDate);
      Assert.isNull(sep.closingDate, 'no cut-off date is invented');
      Assert.isNull(sep.dueDate);
      Assert.areEqual(1, sep.lines.size());
      Assert.areEqual(inside.Id, sep.lines[0].recordId);
    }
  }

  @IsTest
  static void rejectsInvalidInvoiceQueries() {
    System.runAs(byAlias(GESTOR)) {
      configure(true);
      AXF_OBJ_CreditCard__c target = card(
        holder('Holder 152 invalid').Id,
        null,
        null
      );
      ALT_CLS_CardStatementService.InvoiceQuery inverted = month(
        target.Id,
        2026,
        9
      );
      inverted.minAmount = 10;
      inverted.maxAmount = 5;
      ALT_CLS_CardStatementService.InvoiceQuery backwards = month(
        target.Id,
        2026,
        9
      );
      backwards.fromDate = d(2026, 9, 10);
      backwards.toDate = d(2026, 9, 1);
      ALT_CLS_CardStatementService.InvoiceQuery badMonth = month(
        target.Id,
        2026,
        13
      );
      Assert.areEqual('INVALID_INPUT', failure(new InvoiceCall(inverted)));
      Assert.areEqual('INVALID_INPUT', failure(new InvoiceCall(backwards)));
      Assert.areEqual('INVALID_INPUT', failure(new InvoiceCall(badMonth)));
      Assert.areEqual('INVALID_INPUT', failure(new InvoiceCall(null)));
    }
  }

  @IsTest
  static void suggestsOnlyInsideTheWindowAndConfirmsInOneClick() {
    System.runAs(byAlias(GESTOR)) {
      configure(true);
      Account owner = holder('Holder 152 window');
      AXF_OBJ_CreditCard__c target = card(owner.Id, null, null);
      activeRule(target.Id, 5, 7);
      AXF_OBJ_CreditCardTransaction__c source = fact(
        target.Id,
        100,
        d(2026, 8, 10),
        'Mercado',
        'win'
      );
      // Purchase +6 days; its due date (the invoice's) lies far outside the window.
      AXF_OBJ_FinancialTransaction__c inside = entry(
        owner.Id,
        target.Id,
        104,
        d(2026, 8, 16),
        d(2026, 9, 20),
        'in'
      );
      entry(owner.Id, target.Id, 106, d(2026, 8, 10), 'amount-out');
      entry(owner.Id, null, 100, d(2026, 8, 18), 'date-out');
      Test.startTest();
      ALT_CLS_BankStatementService.SuggestionPage fromFact = suggest(
        target.Id,
        'FACT',
        source.Id
      );
      ALT_CLS_BankStatementService.SuggestionPage fromEntry = suggest(
        target.Id,
        'ENTRY',
        inside.Id
      );
      Assert.areEqual('AXF-MATCHING@1.1.0', fromFact.matchingPolicy);
      Assert.areEqual(1, fromFact.items.size(), 'only R$104 is suggested');
      Assert.areEqual(inside.Id, fromFact.items[0].targetId);
      Assert.areEqual(4, fromFact.items[0].amountDelta);
      Assert.areEqual(6, fromFact.items[0].dayDelta);
      Assert.areEqual(d(2026, 8, 16), fromFact.items[0].candidateDate);
      Assert.areEqual(100, fromFact.items[0].allocationAmount);
      Assert.areEqual(1, fromEntry.items.size());
      Assert.areEqual(source.Id, fromEntry.items[0].sourceId);
      Assert.areEqual(6, fromEntry.items[0].dayDelta);
      ALT_CLS_BankStatementService.ConfirmResult confirmed = new ALT_CLS_CardStatementService()
        .confirm(confirmOf(target.Id, fromEntry.items[0], 'axf152-click-1'));
      String again = failure(
        new ConfirmCall(confirmOf(target.Id, fromFact.items[0], 'axf152-2'))
      );
      ALT_CLS_CardStatementService.InvoiceView view = new ALT_CLS_CardStatementService()
        .invoice(month(target.Id, 2026, 9));
      Test.stopTest();
      Assert.isNotNull(confirmed.allocationId);
      Assert.areEqual(100, confirmed.amount);
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM AXF_OBJ_ReconciliationAllocation__c
          WHERE
            AXF_RA_LKP_CardTransaction__c = :source.Id
            AND AXF_RA_LKP_FinancialTransaction__c = :inside.Id
        ]
      );
      Assert.areEqual('SOURCE_EXHAUSTED', again, 'no second allocation');
      Assert.areEqual('RECONCILED', line(view, source.Id).status);
      Assert.areEqual(0, line(view, source.Id).residual);
      Assert.isFalse(line(view, source.Id).canSuggest);
      Assert.isNull(
        line(view, inside.Id),
        'an allocated entry is shown only through its fact'
      );
    }
  }

  @IsTest
  static void refusesPairsOutsideTheWindowOrTheCard() {
    System.runAs(byAlias(GESTOR)) {
      configure(true);
      Account owner = holder('Holder 152 refusals');
      AXF_OBJ_CreditCard__c target = card(owner.Id, null, null);
      AXF_OBJ_CreditCard__c other = card(owner.Id, null, null);
      AXF_OBJ_CreditCardTransaction__c source = fact(
        target.Id,
        100,
        d(2026, 8, 10),
        'Mercado',
        'ref-src'
      );
      AXF_OBJ_CreditCardTransaction__c foreign = fact(
        other.Id,
        100,
        d(2026, 8, 10),
        'Outro',
        'ref-other'
      );
      // Due date inside the window, purchase date outside: the purchase decides.
      AXF_OBJ_FinancialTransaction__c far = entry(
        owner.Id,
        target.Id,
        100,
        d(2026, 8, 30),
        d(2026, 8, 11),
        'far'
      );
      ALT_CLS_BankStatementService.SuggestionView pair = new ALT_CLS_BankStatementService.SuggestionView();
      pair.sourceId = source.Id;
      pair.sourceVersion = 0;
      pair.targetId = far.Id;
      pair.targetVersion = 0;
      Assert.areEqual(
        'OUT_OF_WINDOW',
        failure(new ConfirmCall(confirmOf(target.Id, pair, 'axf152-far')))
      );
      Assert.areEqual(
        0,
        suggest(target.Id, 'FACT', source.Id).items.size(),
        'the due date never brings a card entry into the window'
      );
      pair.sourceId = foreign.Id;
      Assert.areEqual(
        'NOT_ACCESSIBLE',
        failure(new ConfirmCall(confirmOf(target.Id, pair, 'axf152-foreign')))
      );
      Assert.areEqual(
        'NOT_ACCESSIBLE',
        failure(new SuggestCall(other.Id, 'ENTRY', far.Id))
      );
      Assert.areEqual(
        'INVALID_INPUT',
        failure(new SuggestCall(target.Id, 'OTHER', far.Id))
      );
      Assert.areEqual(
        'INVALID_INPUT',
        failure(new SuggestCall(target.Id, 'FACT', far.Id))
      );
      Assert.areEqual(
        'INVALID_INPUT',
        failure(new ConfirmCall(confirmOf(target.Id, pair, null)))
      );
    }
  }

  @IsTest
  static void aReaderWithoutTheLinkCapabilitySeesTheDerivedStatus() {
    User reader = byAlias(READER);
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
    AXF_OBJ_CreditCard__c target;
    AXF_OBJ_CreditCardTransaction__c source;
    AXF_OBJ_FinancialTransaction__c kept;
    AXF_OBJ_FinancialTransaction__c reversed;
    System.runAs(self) {
      Account owner = new Account(
        Name = 'Holder 152 reader',
        OwnerId = reader.Id,
        RecordTypeId = Account.SObjectType.getDescribe()
          .getRecordTypeInfosByDeveloperName()
          .get('AXF_Business')
          .getRecordTypeId()
      );
      insert owner;
      target = new AXF_OBJ_CreditCard__c(
        OwnerId = reader.Id,
        AXF_CC_LKP_Account__c = owner.Id,
        AXF_CC_PKL_AvailabilityState__c = 'AVAILABLE',
        AXF_CC_TXT_CurrencyIsoCode__c = 'BRL',
        AXF_CC_TXT_InstitutionName__c = 'Banco 152'
      );
      insert target;
      source = newFact(target.Id, 100, d(2026, 8, 10), 'Mercado', 'reader');
      insert source;
      kept = newEntry(
        owner.Id,
        target.Id,
        60,
        d(2026, 8, 12),
        d(2026, 9, 12),
        'reader-kept'
      );
      reversed = newEntry(
        owner.Id,
        target.Id,
        40,
        d(2026, 8, 14),
        d(2026, 9, 12),
        'reader-reversed'
      );
      kept.OwnerId = reader.Id;
      reversed.OwnerId = reader.Id;
      insert new List<AXF_OBJ_FinancialTransaction__c>{ kept, reversed };
      ALT_CLS_RealizationService realize = new ALT_CLS_RealizationService();
      realize.apply(application(kept.Id, source.Id, 60, 'axf152-ro-kept'));
      ALT_CLS_RealizationService.Input second = application(
        reversed.Id,
        source.Id,
        40,
        'axf152-ro-reversed'
      );
      second.sourceVersion = realize.sourceVersion(source.Id, 'CARD');
      Id reversible = realize.apply(second);
      Decimal version = [
        SELECT AXF_FTX_NUM_Version__c
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE Id = :reversed.Id
      ]
      .AXF_FTX_NUM_Version__c;
      realize.reverse(reversible, version, 'axf152-ro-reverse');
      List<AXF_OBJ_ReconciliationAllocation__Share> shares = new List<AXF_OBJ_ReconciliationAllocation__Share>();
      for (AXF_OBJ_ReconciliationAllocation__c row : [
        SELECT Id, AXF_RA_PKL_Kind__c
        FROM AXF_OBJ_ReconciliationAllocation__c
      ]) {
        shares.add(
          new AXF_OBJ_ReconciliationAllocation__Share(
            ParentId = row.Id,
            UserOrGroupId = reader.Id,
            AccessLevel = 'Read',
            RowCause = 'Manual'
          )
        );
      }
      Assert.areEqual(3, shares.size(), 'two applications and a reversal');
      insert shares;
    }
    System.runAs(reader) {
      configure(false);
      Test.startTest();
      ALT_CLS_CardStatementService service = new ALT_CLS_CardStatementService();
      Assert.isFalse(service.canReconcile(), 'no link capability');
      ALT_CLS_CardStatementService.InvoiceView aug = service.invoice(
        month(target.Id, 2026, 8)
      );
      Test.stopTest();
      Assert.isFalse(aug.canReconcile);
      ALT_CLS_BankStatementService.LineView fact = line(aug, source.Id);
      Assert.areEqual('PARTIAL', fact.status, '60 applied after the reversal');
      Assert.areEqual(60, fact.allocated);
      Assert.areEqual(40, fact.residual);
      Assert.isFalse(fact.canSuggest, 'read-only: no suggestion');
      Assert.isNull(line(aug, kept.Id), 'allocated: shown through the fact');
      ALT_CLS_BankStatementService.LineView open = line(aug, reversed.Id);
      Assert.areEqual('UNRECONCILED', open.status, 'net zero after reversal');
      Assert.isFalse(open.canSuggest);
    }
  }

  private static ALT_CLS_RealizationService.Input application(
    Id targetId,
    Id sourceId,
    Decimal amount,
    String key
  ) {
    ALT_CLS_RealizationService.Input input = new ALT_CLS_RealizationService.Input();
    input.targetId = targetId;
    input.sourceId = sourceId;
    input.sourceKind = 'CARD';
    input.amount = amount;
    input.recognitionDate = d(2026, 8, 10);
    input.targetVersion = 0;
    input.sourceVersion = 0;
    input.operationKey = key;
    return input;
  }
}
