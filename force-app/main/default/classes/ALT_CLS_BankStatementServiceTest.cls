/**
 * @description AXF-151: current-account statement. Authorized accounts and wallets with balance,
 * month/period paging and combined filters, derived reconciliation status without duplicating an
 * allocated manual entry, AXF-MATCHING@1.1.0 suggestion window, one-click confirmation through the
 * link contract, manual balance under optimistic versioning and the Pluggy refresh boundary.
 */
@IsTest(isParallel=false)
// API 62: AXON_DEV enforces FLS on plain test DML under runAs from API 67 onwards.
private class ALT_CLS_BankStatementServiceTest {
  private static final String GESTOR = 'axf151g';
  private static final String PEER = 'axf151p';
  private static final String PARTICIPANT = 'axf151n';

  private static User byAlias(String alias) {
    return [SELECT Id FROM User WHERE Alias = :alias LIMIT 1];
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
        String name : new List<String>{
          'AXF_PS_GestorFinanceiro',
          'AXF_PS_FinancialEntry',
          'AXF_PS_Realization'
        }
      ) {
        assignments.add(
          new PermissionSetAssignment(
            AssigneeId = users[i].Id,
            PermissionSetId = permissionSets.get(name)
          )
        );
      }
    }
    for (
      String name : new List<String>{
        'AXF_PS_Participante',
        'AXF_PS_FinancialEntry',
        'AXF_PS_Realization'
      }
    ) {
      assignments.add(
        new PermissionSetAssignment(
          AssigneeId = users[2].Id,
          PermissionSetId = permissionSets.get(name)
        )
      );
    }
    // Check-only deploys do not apply the branch's permission-set changes to test users: the
    // read FLS this branch adds to AXF_PS_FinancialEntry is mirrored by a test set with no access
    // to AXF_OBJ_PluggyConnection__c, exactly as the participant bundle (AXF_PSG_Participante).
    assignments.add(
      new PermissionSetAssignment(
        AssigneeId = users[2].Id,
        PermissionSetId = financialEntryReadMirror()
      )
    );
    insert assignments;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert new AXF_ReportCurrencyPref__c(
        SetupOwnerId = UserInfo.getOrganizationId(),
        AXF_RCP_TXT_IsoCode__c = 'BRL'
      );
    }
  }

  /** Read FLS this branch adds to AXF_PS_FinancialEntry; no Pluggy connection object access. */
  private static Id financialEntryReadMirror() {
    PermissionSet mirror = new PermissionSet(
      Name = 'AXF151_FinancialEntryReadMirror',
      Label = 'AXF151 FinancialEntry read mirror'
    );
    insert mirror;
    List<ObjectPermissions> objects = new List<ObjectPermissions>();
    for (
      String name : new List<String>{
        'AXF_OBJ_BankAccount__c',
        'AXF_OBJ_BankAccountTransaction__c'
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
    insert objects;
    List<FieldPermissions> fields = new List<FieldPermissions>();
    for (
      String field : new List<String>{
        'AXF_OBJ_BankAccountTransaction__c.AXF_BAT_PKL_Status__c',
        'AXF_OBJ_BankAccount__c.AXF_BA_CUR_CurrentBalance__c',
        'AXF_OBJ_BankAccount__c.AXF_BA_LKP_Account__c',
        'AXF_OBJ_BankAccount__c.AXF_BA_LKP_Connection__c',
        'AXF_OBJ_BankAccount__c.AXF_BA_NUM_Version__c',
        'AXF_OBJ_BankAccount__c.AXF_BA_TXT_CurrencyIsoCode__c',
        'AXF_OBJ_BankAccount__c.AXF_BA_TXT_NumberMasked__c',
        'AXF_OBJ_BankAccount__c.AXF_BA_TXT_Type__c'
      }
    ) {
      fields.add(
        new FieldPermissions(
          ParentId = mirror.Id,
          SobjectType = field.substringBefore('.'),
          Field = field,
          PermissionsRead = true,
          PermissionsEdit = false
        )
      );
    }
    insert fields;
    return mirror.Id;
  }

  // ------------------------------------------------------------ fixture

  private static Date day(Integer dayOfMonth) {
    return Date.today().toStartOfMonth().addDays(dayOfMonth - 1);
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

  private static AXF_OBJ_BankAccount__c bank(
    Id holderId,
    String type,
    Id connectionId
  ) {
    AXF_OBJ_BankAccount__c result = new AXF_OBJ_BankAccount__c(
      AXF_BA_LKP_Account__c = holderId,
      AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_BA_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BA_TXT_InstitutionName__c = type == 'WALLET' ? null : 'Banco 151',
      AXF_BA_TXT_NumberMasked__c = type == 'WALLET' ? null : '****1510',
      AXF_BA_TXT_Type__c = type,
      AXF_BA_LKP_Connection__c = connectionId,
      AXF_BA_CUR_CurrentBalance__c = 10,
      AXF_BA_NUM_Version__c = 1
    );
    insert result;
    return result;
  }

  private static AXF_OBJ_BankAccountTransaction__c fact(
    Id bankId,
    Decimal amount,
    Date onDate,
    String description,
    String key
  ) {
    AXF_OBJ_BankAccountTransaction__c result = new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_MDR_BankAccount__c = bankId,
      AXF_BAT_NUM_Magnitude__c = amount,
      AXF_BAT_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BAT_PKL_Direction__c = 'DEBIT',
      AXF_BAT_DAT_Date__c = onDate,
      AXF_BAT_TXT_Description__c = description,
      AXF_BAT_EXI_SourceKey__c = 'axf151-' + key,
      AXF_BAT_PKL_Source__c = 'PLUGGY',
      AXF_BAT_PKL_Status__c = 'POSTED',
      AXF_BAT_NUM_Version__c = 0
    );
    insert result;
    return result;
  }

  private static AXF_OBJ_FinancialTransaction__c entry(
    Id holderId,
    Id bankId,
    Decimal amount,
    Date onDate,
    String key
  ) {
    AXF_OBJ_FinancialTransaction__c result = new AXF_OBJ_FinancialTransaction__c(
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
      AXF_FTX_EXI_ClientRequestId__c = 'ftx-151-' + key
    );
    insert result;
    return result;
  }

  private static ALT_CLS_BankStatementService.StatementQuery month(
    Id bankId,
    Date inMonth
  ) {
    ALT_CLS_BankStatementService.StatementQuery query = new ALT_CLS_BankStatementService.StatementQuery();
    query.bankAccountId = bankId;
    query.year = inMonth.year();
    query.month = inMonth.month();
    return query;
  }

  private static ALT_CLS_BankStatementService.LineView line(
    ALT_CLS_BankStatementService.StatementView view,
    Id recordId
  ) {
    for (ALT_CLS_BankStatementService.LineView l : view.lines) {
      if (l.recordId == recordId) {
        return l;
      }
    }
    return null;
  }

  private static ALT_CLS_BankStatementService.SuggestionPage suggest(
    Id bankId,
    String kind,
    Id recordId
  ) {
    ALT_CLS_BankStatementService.SuggestionQuery query = new ALT_CLS_BankStatementService.SuggestionQuery();
    query.bankAccountId = bankId;
    query.lineKind = kind;
    query.recordId = recordId;
    return new ALT_CLS_BankStatementService().suggest(query);
  }

  private static ALT_CLS_BankStatementService.ConfirmInput confirmOf(
    Id bankId,
    ALT_CLS_BankStatementService.SuggestionView s,
    String key
  ) {
    ALT_CLS_BankStatementService.ConfirmInput input = new ALT_CLS_BankStatementService.ConfirmInput();
    input.bankAccountId = bankId;
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
    } catch (ALT_CLS_BankStatementService.BankStatementException expected) {
      return expected.getMessage();
    }
    return 'NO_EXCEPTION';
  }

  private class StatementCall implements Callable {
    ALT_CLS_BankStatementService.StatementQuery query;
    StatementCall(ALT_CLS_BankStatementService.StatementQuery query) {
      this.query = query;
    }
    public Object call(String action, Map<String, Object> args) {
      return new ALT_CLS_BankStatementService().statement(query);
    }
  }

  private class BalanceCall implements Callable {
    ALT_CLS_BankStatementService.BalanceInput input;
    BalanceCall(Id bankId, Decimal balance, Decimal expectedVersion) {
      input = new ALT_CLS_BankStatementService.BalanceInput();
      input.bankAccountId = bankId;
      input.balance = balance;
      input.expectedVersion = expectedVersion;
    }
    public Object call(String action, Map<String, Object> args) {
      return new ALT_CLS_BankStatementService().updateBalance(input);
    }
  }

  private class RefreshCall implements Callable {
    Id bankId;
    RefreshCall(Id bankId) {
      this.bankId = bankId;
    }
    public Object call(String action, Map<String, Object> args) {
      return new ALT_CLS_BankStatementService().refresh(bankId);
    }
  }

  private class ConfirmCall implements Callable {
    ALT_CLS_BankStatementService.ConfirmInput input;
    ConfirmCall(ALT_CLS_BankStatementService.ConfirmInput input) {
      this.input = input;
    }
    public Object call(String action, Map<String, Object> args) {
      return new ALT_CLS_BankStatementService().confirm(input);
    }
  }

  private static AXF_OBJ_PluggyConnection__c connection(String itemId) {
    AXF_OBJ_PluggyConnection__c result = new AXF_OBJ_PluggyConnection__c(
      AXF_CON_EXI_PluggyItemId__c = itemId + '-' + System.now().getTime(),
      AXF_CON_PKL_ConsentState__c = 'ACTIVE',
      AXF_CON_PKL_CollectionState__c = 'ACTIVE',
      AXF_CON_TXT_InstitutionName__c = 'Banco 151'
    );
    insert result;
    return result;
  }

  // -------------------------------------------------------------- tests

  @IsTest
  static void listsAuthorizedAccountsAndWalletsWithBalance() {
    System.runAs(byAlias(GESTOR)) {
      Account owner = holder('Holder 151 list');
      AXF_OBJ_PluggyConnection__c link = connection('ITEM151L');
      AXF_OBJ_BankAccount__c connected = bank(owner.Id, 'CHECKING', link.Id);
      AXF_OBJ_BankAccount__c wallet = bank(owner.Id, 'WALLET', null);
      Test.startTest();
      List<ALT_CLS_BankStatementService.AccountView> views = new ALT_CLS_BankStatementService()
        .listAccounts();
      Test.stopTest();
      Assert.areEqual(2, views.size());
      Map<Id, ALT_CLS_BankStatementService.AccountView> byId = new Map<Id, ALT_CLS_BankStatementService.AccountView>();
      for (ALT_CLS_BankStatementService.AccountView v : views) {
        byId.put(v.bankAccountId, v);
      }
      ALT_CLS_BankStatementService.AccountView bankView = byId.get(
        connected.Id
      );
      ALT_CLS_BankStatementService.AccountView walletView = byId.get(wallet.Id);
      Assert.isTrue(bankView.hasConnection);
      Assert.isTrue(bankView.canRefresh, 'connected account refreshes');
      Assert.isFalse(bankView.canEditBalance);
      Assert.areEqual('Banco 151', bankView.institutionName);
      Assert.isTrue(walletView.wallet);
      Assert.isNull(walletView.institutionName, 'a wallet has no institution');
      Assert.isTrue(walletView.canEditBalance, 'a wallet balance is manual');
      Assert.isFalse(walletView.canRefresh);
      Assert.areEqual(10, walletView.currentBalance);
      Assert.areEqual('Holder 151 list', walletView.holderLabel);
    }
  }

  @IsTest
  static void foreignAccountsAndMissingCapabilityDiscloseNothing() {
    AXF_OBJ_BankAccount__c owned;
    System.runAs(byAlias(GESTOR)) {
      Account owner = holder('Holder 151 owner');
      owned = bank(owner.Id, 'CHECKING', null);
    }
    System.runAs(byAlias(PEER)) {
      Assert.areEqual(
        0,
        new ALT_CLS_BankStatementService().listAccounts().size()
      );
      Assert.areEqual(
        'NOT_ACCESSIBLE',
        failure(new StatementCall(month(owned.Id, Date.today())))
      );
      Assert.areEqual(
        'NOT_ACCESSIBLE',
        failure(new BalanceCall(owned.Id, 5, 1))
      );
    }
    System.runAs(byAlias(PARTICIPANT)) {
      Assert.areEqual(
        'NOT_ACCESSIBLE',
        failure(new StatementCall(month(owned.Id, Date.today())))
      );
    }
  }

  @IsTest
  static void pagesByMonthAndAppliesCustomPeriodAndCombinedFilters() {
    System.runAs(byAlias(GESTOR)) {
      Account owner = holder('Holder 151 page');
      AXF_OBJ_BankAccount__c account = bank(owner.Id, 'CHECKING', null);
      AXF_OBJ_BankAccountTransaction__c previous = fact(
        account.Id,
        50,
        day(1).addDays(-5),
        'Padaria anterior',
        'prev'
      );
      AXF_OBJ_BankAccountTransaction__c current = fact(
        account.Id,
        80,
        day(5),
        'Mercado central',
        'cur'
      );
      AXF_OBJ_BankAccountTransaction__c other = fact(
        account.Id,
        300,
        day(6),
        'Mercado grande',
        'cur2'
      );
      AXF_OBJ_BankAccountTransaction__c next = fact(
        account.Id,
        70,
        day(1).addMonths(1).addDays(3),
        'Farmacia seguinte',
        'next'
      );
      AXF_OBJ_FinancialTransaction__c manual = entry(
        owner.Id,
        account.Id,
        42,
        day(8),
        'page'
      );
      Test.startTest();
      ALT_CLS_BankStatementService service = new ALT_CLS_BankStatementService();
      ALT_CLS_BankStatementService.StatementView thisMonth = service.statement(
        month(account.Id, Date.today())
      );
      ALT_CLS_BankStatementService.StatementView before = service.statement(
        month(account.Id, day(1).addMonths(-1))
      );
      ALT_CLS_BankStatementService.StatementView after = service.statement(
        month(account.Id, day(1).addMonths(1))
      );
      ALT_CLS_BankStatementService.StatementQuery custom = month(
        account.Id,
        Date.today()
      );
      custom.fromDate = day(1).addDays(-10);
      custom.toDate = day(5);
      ALT_CLS_BankStatementService.StatementView period = service.statement(
        custom
      );
      ALT_CLS_BankStatementService.StatementQuery filtered = month(
        account.Id,
        Date.today()
      );
      filtered.minAmount = 60;
      filtered.maxAmount = 100;
      filtered.term = 'mercado';
      filtered.fromDate = day(1);
      filtered.toDate = day(7);
      ALT_CLS_BankStatementService.StatementView combined = service.statement(
        filtered
      );
      Test.stopTest();
      Assert.areEqual(3, thisMonth.lines.size(), 'two facts and one entry');
      Assert.areEqual(other.Id, thisMonth.lines[1].recordId);
      Assert.areEqual('ENTRY', thisMonth.lines[0].lineKind, 'newest first');
      Assert.areEqual(manual.Id, thisMonth.lines[0].recordId);
      Assert.areEqual('UNRECONCILED', thisMonth.lines[0].status);
      Assert.isTrue(thisMonth.lines[0].canSuggest);
      Assert.areEqual(1, before.lines.size());
      Assert.areEqual(previous.Id, before.lines[0].recordId);
      Assert.areEqual(1, after.lines.size());
      Assert.areEqual(next.Id, after.lines[0].recordId);
      Assert.isTrue(period.customPeriod);
      Assert.areEqual(2, period.lines.size(), 'period crosses the month');
      Assert.areEqual(1, combined.lines.size(), 'every filter applies');
      Assert.areEqual(current.Id, combined.lines[0].recordId);
      Assert.areEqual(
        'ALT_CLS_BankStatementService.BankStatementException',
        invalidPeriod(account.Id)
      );
    }
  }

  private static String invalidPeriod(Id bankId) {
    ALT_CLS_BankStatementService.StatementQuery query = month(
      bankId,
      Date.today()
    );
    query.fromDate = Date.today();
    query.toDate = Date.today().addDays(-1);
    try {
      new ALT_CLS_BankStatementService().statement(query);
    } catch (Exception expected) {
      Assert.areEqual('INVALID_INPUT', expected.getMessage());
      return expected.getTypeName();
    }
    return 'NO_EXCEPTION';
  }

  @IsTest
  static void suggestsOnlyInsideTheWindowAndConfirmsInOneClick() {
    System.runAs(byAlias(GESTOR)) {
      Account owner = holder('Holder 151 window');
      AXF_OBJ_BankAccount__c account = bank(owner.Id, 'CHECKING', null);
      AXF_OBJ_BankAccountTransaction__c source = fact(
        account.Id,
        100,
        day(10),
        'Mercado',
        'win'
      );
      AXF_OBJ_FinancialTransaction__c inside = entry(
        owner.Id,
        account.Id,
        104,
        day(16),
        'in'
      );
      entry(owner.Id, account.Id, 106, day(10), 'amount-out');
      entry(owner.Id, null, 100, day(18), 'date-out');
      Test.startTest();
      ALT_CLS_BankStatementService.SuggestionPage fromFact = suggest(
        account.Id,
        'FACT',
        source.Id
      );
      ALT_CLS_BankStatementService.SuggestionPage fromEntry = suggest(
        account.Id,
        'ENTRY',
        inside.Id
      );
      Assert.areEqual('AXF-MATCHING@1.1.0', fromFact.matchingPolicy);
      Assert.areEqual(1, fromFact.items.size(), 'only R$104 is suggested');
      Assert.areEqual(inside.Id, fromFact.items[0].targetId);
      Assert.areEqual(4, fromFact.items[0].amountDelta);
      Assert.areEqual(6, fromFact.items[0].dayDelta);
      Assert.areEqual(100, fromFact.items[0].allocationAmount);
      Assert.areEqual(1, fromEntry.items.size());
      Assert.areEqual(source.Id, fromEntry.items[0].sourceId);
      ALT_CLS_BankStatementService.ConfirmResult confirmed = new ALT_CLS_BankStatementService()
        .confirm(confirmOf(account.Id, fromFact.items[0], 'axf151-click-1'));
      String again = failure(
        new ConfirmCall(
          confirmOf(account.Id, fromFact.items[0], 'axf151-click-2')
        )
      );
      ALT_CLS_BankStatementService.StatementView view = new ALT_CLS_BankStatementService()
        .statement(month(account.Id, Date.today()));
      Test.stopTest();
      Assert.isNotNull(confirmed.allocationId);
      Assert.areEqual(100, confirmed.amount);
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM AXF_OBJ_ReconciliationAllocation__c
          WHERE
            AXF_RA_LKP_BankTransaction__c = :source.Id
            AND AXF_RA_LKP_FinancialTransaction__c = :inside.Id
        ]
      );
      Assert.areEqual('SOURCE_EXHAUSTED', again, 'no second allocation');
      Assert.areEqual('RECONCILED', line(view, source.Id).status);
      Assert.areEqual(0, line(view, source.Id).residual);
      Assert.isNull(
        line(view, inside.Id),
        'an allocated entry is shown only through its fact'
      );
    }
  }

  @IsTest
  static void partialAllocationAndRefusalsAreExplicit() {
    System.runAs(byAlias(GESTOR)) {
      Account owner = holder('Holder 151 partial');
      AXF_OBJ_BankAccount__c account = bank(owner.Id, 'CHECKING', null);
      AXF_OBJ_BankAccountTransaction__c source = fact(
        account.Id,
        100,
        day(12),
        'Conta de luz',
        'partial'
      );
      AXF_OBJ_FinancialTransaction__c target = entry(
        owner.Id,
        account.Id,
        96,
        day(12),
        'partial'
      );
      AXF_OBJ_FinancialTransaction__c far = entry(
        owner.Id,
        account.Id,
        300,
        day(28),
        'far'
      );
      Test.startTest();
      ALT_CLS_BankStatementService.SuggestionView s = suggest(
          account.Id,
          'FACT',
          source.Id
        )
        .items[0];
      ALT_CLS_BankStatementService.ConfirmInput stale = confirmOf(
        account.Id,
        s,
        'axf151-stale'
      );
      stale.sourceVersion = 99;
      String conflict = failure(new ConfirmCall(stale));
      ALT_CLS_BankStatementService.ConfirmInput outOfWindow = confirmOf(
        account.Id,
        s,
        'axf151-far'
      );
      outOfWindow.targetId = far.Id;
      String window = failure(new ConfirmCall(outOfWindow));
      new ALT_CLS_BankStatementService()
        .confirm(confirmOf(account.Id, s, 'axf151-partial'));
      ALT_CLS_BankStatementService.StatementView view = new ALT_CLS_BankStatementService()
        .statement(month(account.Id, Date.today()));
      Test.stopTest();
      Assert.areEqual('CONFLICT', conflict);
      Assert.areEqual('OUT_OF_WINDOW', window);
      ALT_CLS_BankStatementService.LineView partial = line(view, source.Id);
      Assert.areEqual('PARTIAL', partial.status);
      Assert.areEqual(96, partial.allocated);
      Assert.areEqual(4, partial.residual);
      Assert.isNull(line(view, target.Id));
      Assert.isNotNull(line(view, far.Id), 'unallocated entry stays visible');
    }
  }

  @IsTest
  static void manualBalanceIsVersionedAndRefusedOnConnectedAccounts() {
    System.runAs(byAlias(GESTOR)) {
      Account owner = holder('Holder 151 balance');
      AXF_OBJ_BankAccount__c wallet = bank(owner.Id, 'WALLET', null);
      AXF_OBJ_PluggyConnection__c link = connection('ITEM151B');
      AXF_OBJ_BankAccount__c connected = bank(owner.Id, 'CHECKING', link.Id);
      Test.startTest();
      ALT_CLS_BankStatementService.BalanceInput input = new ALT_CLS_BankStatementService.BalanceInput();
      input.bankAccountId = wallet.Id;
      input.balance = 250.75;
      input.expectedVersion = 1;
      ALT_CLS_BankStatementService.AccountView updated = new ALT_CLS_BankStatementService()
        .updateBalance(input);
      String stale = failure(new BalanceCall(wallet.Id, 10, 1));
      String pluggy = failure(new BalanceCall(connected.Id, 10, 1));
      String invalid = failure(new BalanceCall(wallet.Id, 1.234, 2));
      String walletRefresh = failure(new RefreshCall(wallet.Id));
      ALT_CLS_BankStatementService.canConfigureOverride = false;
      String gate = failure(new BalanceCall(wallet.Id, 10, 2));
      Test.stopTest();
      Assert.areEqual(250.75, updated.currentBalance);
      Assert.areEqual(2, updated.version);
      Assert.areEqual('CONFLICT', stale);
      Assert.areEqual('NOT_ALLOWED', pluggy);
      Assert.areEqual('INVALID_INPUT', invalid);
      Assert.areEqual('NOT_ALLOWED', walletRefresh);
      Assert.areEqual('UNAVAILABLE', gate);
      AXF_OBJ_BankAccount__c persisted = [
        SELECT AXF_BA_CUR_CurrentBalance__c, AXF_BA_NUM_Version__c
        FROM AXF_OBJ_BankAccount__c
        WHERE Id = :wallet.Id
      ];
      Assert.areEqual(250.75, persisted.AXF_BA_CUR_CurrentBalance__c);
      Assert.areEqual(2, persisted.AXF_BA_NUM_Version__c);
    }
  }

  /**
   * The Pluggy discovery reads its org-level settings, which only an administrator reaches in a
   * test (as in the Pluggy suites): the refresh tests run as the running user with the integration
   * grants and the configuration gate asserted through the test hooks.
   */
  private static AXF_OBJ_BankAccount__c connectedAccount(
    String itemId,
    String collectionState
  ) {
    AXF_CLS_PluggyTestData.grantIntegrationAccess();
    ALT_CLS_BankStatementService.canConfigureOverride = true;
    AXF_CLS_PluggyDiscoveryService.canDiscoverOverride = true;
    Account owner = holder('Holder 151 ' + itemId);
    AXF_OBJ_PluggyConnection__c link = connection(itemId);
    if (collectionState != null) {
      link.AXF_CON_PKL_CollectionState__c = collectionState;
      update link;
    }
    AXF_OBJ_BankAccount__c result = bank(owner.Id, 'CHECKING', link.Id);
    result.AXF_BA_EXI_PluggyAccountId__c = 'ACC-1';
    update result;
    return result;
  }

  @IsTest
  static void connectedAccountRefreshGoesThroughDiscovery() {
    AXF_OBJ_BankAccount__c connected = connectedAccount('ITEM151R', null);
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());
    Test.startTest();
    ALT_CLS_BankStatementService.RefreshResult result = new ALT_CLS_BankStatementService()
      .refresh(connected.Id);
    Test.stopTest();
    Assert.areEqual('SUCCEEDED', result.state);
    Assert.isTrue(result.complete);
    Assert.areEqual(connected.Id, result.account.bankAccountId);
    Assert.areEqual(
      100.55,
      result.account.currentBalance,
      'the provider balance of the mock account'
    );
  }

  @IsTest
  static void refreshWhileADiscoveryRunsAnswersRunning() {
    AXF_OBJ_BankAccount__c connected = connectedAccount('ITEM151C', null);
    Id connectionId = connected.AXF_BA_LKP_Connection__c;
    insert new AXF_OBJ_IntegrationRun__c(
      AXF_INR_EXI_RunKey__c = AXF_CLS_IdentityFraming.key(
        new List<Object>{ 'inr-v1', connectionId, 'ACCOUNTS' }
      ),
      AXF_INR_LKP_Connection__c = connectionId,
      AXF_INR_PKL_Product__c = 'ACCOUNTS',
      AXF_INR_PKL_State__c = 'RUNNING',
      AXF_INR_DT_Watermark__c = Datetime.now(),
      AXF_INR_NUM_Attempt__c = 1,
      AXF_INR_NUM_Version__c = 1
    );
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());
    Test.startTest();
    ALT_CLS_BankStatementService.RefreshResult result = new ALT_CLS_BankStatementService()
      .refresh(connected.Id);
    Test.stopTest();
    Assert.areEqual('RUNNING', result.state, 'CONFLICT becomes RUNNING');
    Assert.isFalse(result.complete);
    Assert.areEqual(10, result.account.currentBalance, 'nothing written');
  }

  @IsTest
  static void refreshOfAPausedConnectionIsBlocked() {
    AXF_OBJ_BankAccount__c connected = connectedAccount('ITEM151P', 'PAUSED');
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());
    Test.startTest();
    String code = failure(new RefreshCall(connected.Id));
    Test.stopTest();
    Assert.areEqual('REFRESH_BLOCKED', code);
  }

  @IsTest
  static void entryLineConfirmsWhenOnlyTheEntryWindowPasses() {
    System.runAs(byAlias(GESTOR)) {
      Account owner = holder('Holder 151 entry window');
      AXF_OBJ_BankAccount__c account = bank(owner.Id, 'CHECKING', null);
      AXF_OBJ_BankAccountTransaction__c source = fact(
        account.Id,
        100,
        day(10),
        'Academia',
        'entry-win'
      );
      AXF_OBJ_FinancialTransaction__c planned = entry(
        owner.Id,
        account.Id,
        105.20,
        day(10),
        'entry-win'
      );
      Test.startTest();
      ALT_CLS_BankStatementService.SuggestionPage fromFact = suggest(
        account.Id,
        'FACT',
        source.Id
      );
      ALT_CLS_BankStatementService.SuggestionPage fromEntry = suggest(
        account.Id,
        'ENTRY',
        planned.Id
      );
      ALT_CLS_BankStatementService.ConfirmResult confirmed = new ALT_CLS_BankStatementService()
        .confirm(confirmOf(account.Id, fromEntry.items[0], 'axf151-entry-win'));
      Test.stopTest();
      Assert.areEqual(0, fromFact.items.size(), '5.20 is above 5% of 100');
      Assert.areEqual(1, fromEntry.items.size(), '5.20 is within 5% of 105.20');
      Assert.areEqual(source.Id, fromEntry.items[0].sourceId);
      Assert.areEqual(100, fromEntry.items[0].allocationAmount);
      Assert.areEqual(100, confirmed.amount);
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM AXF_OBJ_ReconciliationAllocation__c
          WHERE
            AXF_RA_LKP_BankTransaction__c = :source.Id
            AND AXF_RA_LKP_FinancialTransaction__c = :planned.Id
        ]
      );
    }
  }

  @IsTest
  static void equidistantCandidatesAreExplicitTiesInIdOrder() {
    System.runAs(byAlias(GESTOR)) {
      Account owner = holder('Holder 151 ties');
      AXF_OBJ_BankAccount__c account = bank(owner.Id, 'CHECKING', null);
      AXF_OBJ_BankAccountTransaction__c source = fact(
        account.Id,
        100,
        day(10),
        'Posto',
        'ties'
      );
      AXF_OBJ_FinancialTransaction__c below = entry(
        owner.Id,
        account.Id,
        96,
        day(10),
        'tie-96'
      );
      AXF_OBJ_FinancialTransaction__c above = entry(
        owner.Id,
        account.Id,
        104,
        day(10),
        'tie-104'
      );
      AXF_OBJ_FinancialTransaction__c closest = entry(
        owner.Id,
        account.Id,
        102,
        day(12),
        'near-102'
      );
      Test.startTest();
      ALT_CLS_BankStatementService.SuggestionPage page = suggest(
        account.Id,
        'FACT',
        source.Id
      );
      Test.stopTest();
      Assert.areEqual(3, page.items.size());
      Assert.areEqual(
        closest.Id,
        page.items[0].targetId,
        'smallest amount delta first'
      );
      Assert.isFalse(page.items[0].tied);
      List<Id> tiedIds = new List<Id>{ below.Id, above.Id };
      tiedIds.sort();
      Assert.areEqual(tiedIds[0], page.items[1].targetId, 'ties in id order');
      Assert.areEqual(tiedIds[1], page.items[2].targetId);
      Assert.isTrue(page.items[1].tied);
      Assert.isTrue(page.items[2].tied);
    }
  }

  @IsTest
  static void participantReadsTheStatementButCannotReconcile() {
    System.runAs(byAlias(PARTICIPANT)) {
      Account owner = holder('Holder 151 participant');
      AXF_OBJ_BankAccount__c account = bank(owner.Id, 'CHECKING', null);
      // Without access to the connection object the connected flag is still derived.
      AXF_OBJ_BankAccount__c linked = bank(
        owner.Id,
        'CHECKING',
        connection('ITEM151N').Id
      );
      AXF_OBJ_BankAccountTransaction__c source = fact(
        account.Id,
        100,
        day(10),
        'Farmacia',
        'participant'
      );
      AXF_OBJ_FinancialTransaction__c planned = entry(
        owner.Id,
        account.Id,
        100,
        day(10),
        'participant'
      );
      Test.startTest();
      List<ALT_CLS_BankStatementService.AccountView> accounts = new ALT_CLS_BankStatementService()
        .listAccounts();
      ALT_CLS_BankStatementService.StatementView view = new ALT_CLS_BankStatementService()
        .statement(month(account.Id, Date.today()));
      String suggestCode = failure(new SuggestCall(account.Id, source.Id));
      ALT_CLS_BankStatementService.ConfirmInput input = new ALT_CLS_BankStatementService.ConfirmInput();
      input.bankAccountId = account.Id;
      input.sourceId = source.Id;
      input.sourceVersion = 0;
      input.targetId = planned.Id;
      input.targetVersion = 0;
      input.operationKey = 'axf151-participant';
      String confirmCode = failure(new ConfirmCall(input));
      Test.stopTest();
      Assert.areEqual(2, accounts.size());
      for (ALT_CLS_BankStatementService.AccountView v : accounts) {
        Assert.areEqual(v.bankAccountId == linked.Id, v.hasConnection);
        Assert.isFalse(v.canEditBalance, 'no configuration capability');
        Assert.isFalse(v.canRefresh, 'no configuration capability');
      }
      Assert.isFalse(view.account.hasConnection);
      Assert.isFalse(view.canReconcile);
      Assert.areEqual(2, view.lines.size(), 'fact and entry are readable');
      for (ALT_CLS_BankStatementService.LineView line : view.lines) {
        Assert.isFalse(line.canSuggest, 'no suggestion without the capability');
      }
      Assert.areEqual('UNRECONCILED', line(view, source.Id).status);
      Assert.areEqual('UNAVAILABLE', suggestCode);
      Assert.areEqual('UNAVAILABLE', confirmCode);
    }
  }

  private class SuggestCall implements Callable {
    Id bankId;
    Id factId;
    SuggestCall(Id bankId, Id factId) {
      this.bankId = bankId;
      this.factId = factId;
    }
    public Object call(String action, Map<String, Object> args) {
      return suggest(bankId, 'FACT', factId);
    }
  }

  @IsTest
  static void oldEntryStillFindsItsFactBehindRecentActivity() {
    System.runAs(byAlias(GESTOR)) {
      Account owner = holder('Holder 151 old');
      AXF_OBJ_BankAccount__c account = bank(owner.Id, 'CHECKING', null);
      AXF_OBJ_BankAccount__c busy = bank(owner.Id, 'SAVINGS', null);
      List<AXF_OBJ_BankAccountTransaction__c> recent = new List<AXF_OBJ_BankAccountTransaction__c>();
      for (Integer i = 0; i < 230; i++) {
        recent.add(
          new AXF_OBJ_BankAccountTransaction__c(
            AXF_BAT_MDR_BankAccount__c = busy.Id,
            AXF_BAT_NUM_Magnitude__c = 10 + i,
            AXF_BAT_TXT_CurrencyIsoCode__c = 'BRL',
            AXF_BAT_PKL_Direction__c = 'DEBIT',
            AXF_BAT_DAT_Date__c = Date.today(),
            AXF_BAT_TXT_Description__c = 'Recent ' + i,
            AXF_BAT_EXI_SourceKey__c = 'axf151-recent-' + i,
            AXF_BAT_PKL_Source__c = 'PLUGGY',
            AXF_BAT_PKL_Status__c = 'POSTED',
            AXF_BAT_NUM_Version__c = 0
          )
        );
      }
      insert recent;
      Date old = Date.today().addDays(-90);
      AXF_OBJ_BankAccountTransaction__c source = fact(
        account.Id,
        100,
        old,
        'Seguro antigo',
        'old'
      );
      AXF_OBJ_FinancialTransaction__c planned = entry(
        owner.Id,
        account.Id,
        101,
        old.addDays(2),
        'old'
      );
      Test.startTest();
      ALT_CLS_BankStatementService.SuggestionPage page = suggest(
        account.Id,
        'ENTRY',
        planned.Id
      );
      Test.stopTest();
      Assert.areEqual(1, page.items.size());
      Assert.areEqual(source.Id, page.items[0].sourceId);
      Assert.isFalse(page.truncated);
    }
  }

  @IsTest
  static void exhaustedFactsAreNeverOfferedToAnEntry() {
    System.runAs(byAlias(GESTOR)) {
      Account owner = holder('Holder 151 exhausted');
      AXF_OBJ_BankAccount__c account = bank(owner.Id, 'CHECKING', null);
      AXF_OBJ_BankAccountTransaction__c source = fact(
        account.Id,
        100,
        day(10),
        'Cinema',
        'exhausted'
      );
      AXF_OBJ_FinancialTransaction__c first = entry(
        owner.Id,
        account.Id,
        100,
        day(10),
        'exhausted-1'
      );
      AXF_OBJ_FinancialTransaction__c second = entry(
        owner.Id,
        account.Id,
        100,
        day(11),
        'exhausted-2'
      );
      Test.startTest();
      new ALT_CLS_BankStatementService()
        .confirm(
          confirmOf(
            account.Id,
            suggest(account.Id, 'ENTRY', first.Id).items[0],
            'axf151-exhaust'
          )
        );
      ALT_CLS_BankStatementService.SuggestionPage page = suggest(
        account.Id,
        'ENTRY',
        second.Id
      );
      Test.stopTest();
      Assert.areEqual(0, page.items.size(), 'the fact is already exhausted');
    }
  }

  // A projected (virtual) candidate ahead of a persisted one needs an active schedule projection
  // fixture; that ordering is covered by the code path (virtual candidates are skipped, never a
  // stop condition) and by ALT_CLS_SourceLinkServiceTest for the projection itself.

  @IsTest
  static void windowRuleIsTheRatifiedOne() {
    Assert.isTrue(
      ALT_CLS_BankStatementService.inWindow(100, day(10), 104, day(16))
    );
    Assert.isTrue(
      ALT_CLS_BankStatementService.inWindow(100, day(10), 95, day(3))
    );
    Assert.isFalse(
      ALT_CLS_BankStatementService.inWindow(100, day(10), 106, day(10))
    );
    Assert.isFalse(
      ALT_CLS_BankStatementService.inWindow(100, day(10), 100, day(18))
    );
    Assert.isFalse(
      ALT_CLS_BankStatementService.inWindow(null, day(10), 100, day(10))
    );
  }
}
