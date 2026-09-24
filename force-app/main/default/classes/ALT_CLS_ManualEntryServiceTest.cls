/**
 * @description AXF-153: manual expense/income entries. Realization of a wallet or unconnected
 * source (ACTUAL_ONLY + MANUAL fact), realization against a chosen Pluggy fact (blocked without
 * one), AXF-MATCHING@1.1.0 suggestions for bank and card sources, manual search, one-click
 * confirmation, authorized-context isolation and the manual-entries report with derived status.
 */
@IsTest(isParallel=false)
// API 62: AXON_DEV enforces FLS on plain test DML under runAs from API 67 onwards.
private class ALT_CLS_ManualEntryServiceTest {
  private static final String GESTOR = 'axf153g';
  private static final String PEER = 'axf153p';
  private static final String PARTICIPANT = 'axf153n';

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
    // read FLS AXF-151/AXF-153 add to AXF_PS_FinancialEntry is mirrored by a test set with no
    // access to AXF_OBJ_PluggyConnection__c, exactly as the participant bundle.
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

  /** Read FLS the branch adds to AXF_PS_FinancialEntry; no Pluggy connection object access. */
  private static Id financialEntryReadMirror() {
    PermissionSet mirror = new PermissionSet(
      Name = 'AXF153_FinancialEntryReadMirror',
      Label = 'AXF153 FinancialEntry read mirror'
    );
    insert mirror;
    List<ObjectPermissions> objects = new List<ObjectPermissions>();
    for (
      String name : new List<String>{
        'AXF_OBJ_BankAccount__c',
        'AXF_OBJ_BankAccountTransaction__c',
        'AXF_OBJ_CreditCard__c',
        'AXF_OBJ_FinancialTransaction__c'
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
        'AXF_OBJ_BankAccount__c.AXF_BA_TXT_Type__c',
        'AXF_OBJ_CreditCard__c.AXF_CC_LKP_Account__c',
        'AXF_OBJ_CreditCard__c.AXF_CC_LKP_Connection__c',
        'AXF_OBJ_CreditCard__c.AXF_CC_TXT_InstitutionName__c',
        'AXF_OBJ_CreditCard__c.AXF_CC_TXT_LastFourMasked__c',
        'AXF_OBJ_FinancialTransaction__c.AXF_FTX_LKP_Contract__c',
        'AXF_OBJ_FinancialTransaction__c.AXF_FTX_PKL_PlanKind__c'
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

  private static AXF_OBJ_PluggyConnection__c connection(String itemId) {
    AXF_OBJ_PluggyConnection__c result = new AXF_OBJ_PluggyConnection__c(
      AXF_CON_EXI_PluggyItemId__c = itemId + '-' + System.now().getTime(),
      AXF_CON_PKL_ConsentState__c = 'ACTIVE',
      AXF_CON_PKL_CollectionState__c = 'ACTIVE',
      AXF_CON_TXT_InstitutionName__c = 'Banco 153'
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
      AXF_BA_TXT_InstitutionName__c = type == 'WALLET' ? null : 'Banco 153',
      AXF_BA_TXT_NumberMasked__c = type == 'WALLET' ? null : '****1530',
      AXF_BA_TXT_Type__c = type,
      AXF_BA_LKP_Connection__c = connectionId,
      AXF_BA_NUM_Version__c = 1
    );
    insert result;
    return result;
  }

  private static AXF_OBJ_CreditCard__c card(Id holderId, Id connectionId) {
    AXF_OBJ_CreditCard__c result = new AXF_OBJ_CreditCard__c(
      AXF_CC_LKP_Account__c = holderId,
      AXF_CC_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_CC_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_CC_TXT_InstitutionName__c = 'Cartao 153',
      AXF_CC_TXT_LastFourMasked__c = '1530',
      AXF_CC_LKP_Connection__c = connectionId
    );
    insert result;
    return result;
  }

  private static AXF_OBJ_BankAccountTransaction__c fact(
    Id bankId,
    Decimal amount,
    Date onDate,
    String source,
    String key
  ) {
    AXF_OBJ_BankAccountTransaction__c result = new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_MDR_BankAccount__c = bankId,
      AXF_BAT_NUM_Magnitude__c = amount,
      AXF_BAT_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BAT_PKL_Direction__c = 'DEBIT',
      AXF_BAT_DAT_Date__c = onDate,
      AXF_BAT_TXT_Description__c = 'Fact ' + key,
      AXF_BAT_EXI_SourceKey__c = 'axf153-' + key,
      AXF_BAT_PKL_Source__c = source,
      AXF_BAT_PKL_Status__c = 'POSTED',
      AXF_BAT_NUM_Version__c = 0
    );
    insert result;
    return result;
  }

  private static AXF_OBJ_CreditCardTransaction__c cardFact(
    Id cardId,
    Decimal amount,
    Date onDate,
    String key
  ) {
    AXF_OBJ_CreditCardTransaction__c result = new AXF_OBJ_CreditCardTransaction__c(
      AXF_CCT_MDR_CreditCard__c = cardId,
      AXF_CCT_NUM_Magnitude__c = amount,
      AXF_CCT_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_CCT_PKL_Direction__c = 'DEBIT',
      AXF_CCT_DAT_Date__c = onDate,
      AXF_CCT_TXT_Description__c = 'Card ' + key,
      AXF_CCT_EXI_SourceKey__c = 'axf153-card-' + key,
      AXF_CCT_PKL_Source__c = 'PLUGGY',
      AXF_CCT_PKL_Status__c = 'POSTED',
      AXF_CCT_NUM_Version__c = 0
    );
    insert result;
    return result;
  }

  /** A planned entry exactly as the wizard creates it (AXF-19 service). */
  private static Id planned(
    Id holderId,
    Id bankId,
    Id cardId,
    Decimal amount,
    Date onDate,
    String key
  ) {
    AXF_CLS_FinancialEntryService.EntryInput input = new AXF_CLS_FinancialEntryService.EntryInput();
    input.accountId = holderId;
    input.direction = 'DEBIT';
    input.magnitude = amount;
    input.currencyIsoCode = 'BRL';
    input.purchaseDate = onDate;
    input.bankAccountId = bankId;
    input.creditCardId = cardId;
    input.clientRequestId = ('153' +
      key +
      '-0000-0000-0000-000000000000')
      .left(36)
      .rightPad(36, '0');
    AXF_CLS_FinancialEntryService.EntryResult result = AXF_CLS_FinancialEntryService.createEntry(
      input
    );
    Assert.areEqual('CREATED', result.outcome, 'entry: ' + result.message);
    return result.financialTransactionId;
  }

  private static ALT_CLS_ManualEntryService.Draft draft(
    Id holderId,
    Id bankId,
    Id cardId,
    Decimal amount,
    Date onDate
  ) {
    ALT_CLS_ManualEntryService.Draft result = new ALT_CLS_ManualEntryService.Draft();
    result.accountId = holderId;
    result.bankAccountId = bankId;
    result.creditCardId = cardId;
    result.direction = 'DEBIT';
    result.amount = amount;
    result.currencyIsoCode = 'BRL';
    result.entryDate = onDate;
    return result;
  }

  private static ALT_CLS_ManualEntryService.Draft saved(Id targetId) {
    ALT_CLS_ManualEntryService.Draft result = new ALT_CLS_ManualEntryService.Draft();
    result.targetId = targetId;
    return result;
  }

  private static ALT_CLS_ManualEntryService.RealizeInput realizeOf(
    ALT_CLS_ManualEntryService.Draft entry,
    Id factId,
    String key
  ) {
    ALT_CLS_ManualEntryService.RealizeInput input = new ALT_CLS_ManualEntryService.RealizeInput();
    input.entry = entry;
    input.factId = factId;
    input.factVersion = factId == null ? null : 0;
    input.operationKey = key;
    return input;
  }

  private static ALT_CLS_ManualEntryService.EntryView entryOf(
    ALT_CLS_ManualEntryService.ReportView view,
    Id recordId
  ) {
    for (ALT_CLS_ManualEntryService.EntryView v : view.entries) {
      if (v.recordId == recordId) {
        return v;
      }
    }
    return null;
  }

  private static ALT_CLS_ManualEntryService.ReportQuery thisMonth() {
    ALT_CLS_ManualEntryService.ReportQuery query = new ALT_CLS_ManualEntryService.ReportQuery();
    query.year = Date.today().year();
    query.month = Date.today().month();
    return query;
  }

  private static String failure(Callable call) {
    try {
      call.call('run', null);
    } catch (ALT_CLS_ManualEntryService.ManualEntryException expected) {
      return expected.getMessage();
    }
    return 'NO_EXCEPTION';
  }

  private class RealizeCall implements Callable {
    ALT_CLS_ManualEntryService.RealizeInput input;
    RealizeCall(ALT_CLS_ManualEntryService.RealizeInput input) {
      this.input = input;
    }
    public Object call(String action, Map<String, Object> args) {
      return new ALT_CLS_ManualEntryService().realize(input);
    }
  }

  private class SuggestCall implements Callable {
    ALT_CLS_ManualEntryService.Draft input;
    SuggestCall(ALT_CLS_ManualEntryService.Draft input) {
      this.input = input;
    }
    public Object call(String action, Map<String, Object> args) {
      return new ALT_CLS_ManualEntryService().suggest(input);
    }
  }

  private class SearchCall implements Callable {
    ALT_CLS_ManualEntryService.SearchQuery input;
    SearchCall(ALT_CLS_ManualEntryService.SearchQuery input) {
      this.input = input;
    }
    public Object call(String action, Map<String, Object> args) {
      return new ALT_CLS_ManualEntryService().search(input);
    }
  }

  private class ConfirmCall implements Callable {
    ALT_CLS_ManualEntryService.ConfirmInput input;
    ConfirmCall(ALT_CLS_ManualEntryService.ConfirmInput input) {
      this.input = input;
    }
    public Object call(String action, Map<String, Object> args) {
      return new ALT_CLS_ManualEntryService().confirm(input);
    }
  }

  private class ReportCall implements Callable {
    ALT_CLS_ManualEntryService.ReportQuery input;
    ReportCall(ALT_CLS_ManualEntryService.ReportQuery input) {
      this.input = input;
    }
    public Object call(String action, Map<String, Object> args) {
      return new ALT_CLS_ManualEntryService().listEntries(input);
    }
  }

  // -------------------------------------------------------------- tests

  @IsTest
  static void realizedWalletEntryCreatesActualOnlyWithManualFact() {
    System.runAs(byAlias(GESTOR)) {
      Account owner = holder('Holder 153 wallet');
      AXF_OBJ_BankAccount__c wallet = bank(owner.Id, 'WALLET', null);
      Test.startTest();
      ALT_CLS_ManualEntryService.RealizeResult result = new ALT_CLS_ManualEntryService()
        .realize(
          realizeOf(
            draft(owner.Id, wallet.Id, null, 42.5, day(5)),
            null,
            'axf153-wallet'
          )
        );
      Test.stopTest();
      Assert.isFalse(result.linkedToFact);
      Assert.areEqual(42.5, result.amount);
      AXF_OBJ_FinancialTransaction__c ftx = [
        SELECT AXF_FTX_PKL_PlanKind__c, AXF_FTX_NUM_Magnitude__c
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE Id = :result.financialTransactionId
      ];
      Assert.areEqual('ACTUAL_ONLY', ftx.AXF_FTX_PKL_PlanKind__c);
      AXF_OBJ_BankAccountTransaction__c manual = [
        SELECT AXF_BAT_PKL_Source__c, AXF_BAT_MDR_BankAccount__c
        FROM AXF_OBJ_BankAccountTransaction__c
        WHERE AXF_BAT_MDR_BankAccount__c = :wallet.Id
      ];
      Assert.areEqual('MANUAL', manual.AXF_BAT_PKL_Source__c);
      AXF_OBJ_ReconciliationAllocation__c allocation = [
        SELECT AXF_RA_LKP_BankTransaction__c, AXF_RA_LKP_FinancialTransaction__c
        FROM AXF_OBJ_ReconciliationAllocation__c
        WHERE Id = :result.allocationId
      ];
      Assert.areEqual(manual.Id, allocation.AXF_RA_LKP_BankTransaction__c);
      // The report shows it reconciled, on the wallet derived from its fact.
      ALT_CLS_ManualEntryService.EntryView row = entryOf(
        new ALT_CLS_ManualEntryService().listEntries(thisMonth()),
        result.financialTransactionId
      );
      Assert.areEqual(ALT_CLS_ManualEntryService.STATUS_RECONCILED, row.status);
      Assert.areEqual(wallet.Id, row.originId);
      Assert.areEqual(ALT_CLS_ManualEntryService.ORIGIN_WALLET, row.originKind);
      Assert.areEqual(Label.AXF_BankStatement_wallet, row.originLabel);
    }
  }

  @IsTest
  static void realizedUnconnectedAccountAndCardCreateManualFacts() {
    System.runAs(byAlias(GESTOR)) {
      Account owner = holder('Holder 153 manual');
      AXF_OBJ_BankAccount__c manualBank = bank(owner.Id, 'CHECKING', null);
      AXF_OBJ_CreditCard__c manualCard = card(owner.Id, null);
      Test.startTest();
      ALT_CLS_ManualEntryService service = new ALT_CLS_ManualEntryService();
      ALT_CLS_ManualEntryService.RealizeResult onBank = service.realize(
        realizeOf(
          draft(owner.Id, manualBank.Id, null, 10, day(3)),
          null,
          'axf153-manual-bank'
        )
      );
      ALT_CLS_ManualEntryService.RealizeResult onCard = service.realize(
        realizeOf(
          draft(owner.Id, null, manualCard.Id, 11, day(3)),
          null,
          'axf153-manual-card'
        )
      );
      // Same key, same payload: the recorded result is replayed, never duplicated.
      ALT_CLS_ManualEntryService.RealizeResult replay = service.realize(
        realizeOf(
          draft(owner.Id, manualBank.Id, null, 10, day(3)),
          null,
          'axf153-manual-bank'
        )
      );
      Test.stopTest();
      Assert.areEqual(onBank.allocationId, replay.allocationId);
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM AXF_OBJ_BankAccountTransaction__c
          WHERE
            AXF_BAT_MDR_BankAccount__c = :manualBank.Id
            AND AXF_BAT_PKL_Source__c = 'MANUAL'
        ]
      );
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM AXF_OBJ_CreditCardTransaction__c
          WHERE
            AXF_CCT_MDR_CreditCard__c = :manualCard.Id
            AND AXF_CCT_PKL_Source__c = 'MANUAL'
        ]
      );
      Assert.areNotEqual(
        onBank.financialTransactionId,
        onCard.financialTransactionId
      );
      ALT_CLS_ManualEntryService.EntryView cardRow = entryOf(
        service.listEntries(thisMonth()),
        onCard.financialTransactionId
      );
      Assert.areEqual(manualCard.Id, cardRow.originId);
      Assert.areEqual(
        ALT_CLS_ManualEntryService.ORIGIN_CREDIT_CARD,
        cardRow.originKind
      );
      ALT_CLS_ManualEntryService.ReportQuery byCard = thisMonth();
      byCard.originId = manualCard.Id;
      ALT_CLS_ManualEntryService.ReportView cardOnly = service.listEntries(
        byCard
      );
      Assert.areEqual(1, cardOnly.entries.size());
      Assert.areEqual(
        onCard.financialTransactionId,
        cardOnly.entries[0].recordId
      );
    }
  }

  @IsTest
  static void connectedRealizationTakesTheSmallerFactAmount() {
    System.runAs(byAlias(GESTOR)) {
      Account owner = holder('Holder 153 smaller');
      AXF_OBJ_BankAccount__c connected = bank(
        owner.Id,
        'CHECKING',
        connection('ITEM153M').Id
      );
      AXF_OBJ_BankAccountTransaction__c pluggy = fact(
        connected.Id,
        96,
        day(10),
        'PLUGGY',
        'smaller'
      );
      Test.startTest();
      ALT_CLS_ManualEntryService.RealizeResult result = new ALT_CLS_ManualEntryService()
        .realize(
          realizeOf(
            draft(owner.Id, connected.Id, null, 100, day(10)),
            pluggy.Id,
            'axf153-smaller'
          )
        );
      Test.stopTest();
      Assert.isTrue(result.linkedToFact);
      Assert.areEqual(96, result.amount);
      AXF_OBJ_FinancialTransaction__c ftx = [
        SELECT AXF_FTX_PKL_PlanKind__c, AXF_FTX_NUM_Magnitude__c
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE Id = :result.financialTransactionId
      ];
      Assert.areEqual('ACTUAL_ONLY', ftx.AXF_FTX_PKL_PlanKind__c);
      Assert.areEqual(96, ftx.AXF_FTX_NUM_Magnitude__c);
      Assert.areEqual(
        ALT_CLS_ManualEntryService.STATUS_RECONCILED,
        entryOf(
            new ALT_CLS_ManualEntryService().listEntries(thisMonth()),
            result.financialTransactionId
          )
          .status
      );
    }
  }

  @IsTest
  static void connectedRealizationRefusesAFactOfAnotherNature() {
    System.runAs(byAlias(GESTOR)) {
      Account owner = holder('Holder 153 mismatch');
      AXF_OBJ_BankAccount__c connected = bank(
        owner.Id,
        'CHECKING',
        connection('ITEM153X').Id
      );
      AXF_OBJ_BankAccountTransaction__c debit = fact(
        connected.Id,
        100,
        day(10),
        'PLUGGY',
        'mismatch'
      );
      ALT_CLS_ManualEntryService.Draft credit = draft(
        owner.Id,
        connected.Id,
        null,
        100,
        day(10)
      );
      credit.direction = 'CREDIT';
      Integer before = [SELECT COUNT() FROM AXF_OBJ_FinancialTransaction__c];
      Test.startTest();
      String code = failure(
        new RealizeCall(realizeOf(credit, debit.Id, 'axf153-mismatch'))
      );
      Test.stopTest();
      Assert.areEqual('FACT_MISMATCH', code);
      Assert.areEqual(
        before,
        [SELECT COUNT() FROM AXF_OBJ_FinancialTransaction__c],
        'nothing is written for a mismatched fact'
      );
    }
  }

  @IsTest
  static void partialConfirmationIsReportedAsPartial() {
    System.runAs(byAlias(GESTOR)) {
      Account owner = holder('Holder 153 partial');
      AXF_OBJ_BankAccount__c connected = bank(
        owner.Id,
        'CHECKING',
        connection('ITEM153P').Id
      );
      AXF_OBJ_BankAccountTransaction__c smaller = fact(
        connected.Id,
        60,
        day(10),
        'PLUGGY',
        'partial'
      );
      Id target = planned(owner.Id, connected.Id, null, 100, day(10), 'prt');
      ALT_CLS_ManualEntryService.ConfirmInput input = new ALT_CLS_ManualEntryService.ConfirmInput();
      input.targetId = target;
      input.targetVersion = 0;
      input.sourceId = smaller.Id;
      input.sourceVersion = 0;
      input.operationKey = 'axf153-partial';
      Test.startTest();
      ALT_CLS_ManualEntryService.ConfirmResult confirmed = new ALT_CLS_ManualEntryService()
        .confirm(input);
      ALT_CLS_ManualEntryService.ReportQuery partial = thisMonth();
      partial.status = ALT_CLS_ManualEntryService.STATUS_PARTIAL;
      ALT_CLS_ManualEntryService.ReportView view = new ALT_CLS_ManualEntryService()
        .listEntries(partial);
      ALT_CLS_ManualEntryService.FactPage after = new ALT_CLS_ManualEntryService()
        .suggest(saved(target));
      Test.stopTest();
      Assert.areEqual(60, confirmed.amount);
      ALT_CLS_ManualEntryService.EntryView row = entryOf(view, target);
      Assert.isNotNull(row, 'the PARTIAL filter returns it');
      Assert.areEqual(ALT_CLS_ManualEntryService.STATUS_PARTIAL, row.status);
      Assert.areEqual(60, row.allocated);
      Assert.areEqual(40, row.residual);
      Assert.areEqual(40, after.available, 'the entry still has 40 to settle');
    }
  }

  @IsTest
  static void connectedSourceNeedsAChosenFactAndIsBornReconciled() {
    System.runAs(byAlias(GESTOR)) {
      Account owner = holder('Holder 153 connected');
      AXF_OBJ_BankAccount__c connected = bank(
        owner.Id,
        'CHECKING',
        connection('ITEM153C').Id
      );
      AXF_OBJ_BankAccountTransaction__c pluggy = fact(
        connected.Id,
        100,
        day(10),
        'PLUGGY',
        'connected'
      );
      AXF_OBJ_BankAccountTransaction__c manual = fact(
        connected.Id,
        100,
        day(10),
        'MANUAL',
        'connected-manual'
      );
      Integer before = [SELECT COUNT() FROM AXF_OBJ_FinancialTransaction__c];
      Test.startTest();
      Assert.areEqual(
        'FACT_REQUIRED',
        failure(
          new RealizeCall(
            realizeOf(
              draft(owner.Id, connected.Id, null, 100, day(10)),
              null,
              'axf153-nofact'
            )
          )
        )
      );
      Assert.areEqual(
        before,
        [SELECT COUNT() FROM AXF_OBJ_FinancialTransaction__c],
        'nothing is written without a fact'
      );
      Assert.areEqual(
        'NOT_ACCESSIBLE',
        failure(
          new RealizeCall(
            realizeOf(
              draft(owner.Id, connected.Id, null, 100, day(10)),
              manual.Id,
              'axf153-manualfact'
            )
          )
        ),
        'only a Pluggy fact can be chosen'
      );
      ALT_CLS_ManualEntryService.RealizeResult result = new ALT_CLS_ManualEntryService()
        .realize(
          realizeOf(
            draft(owner.Id, connected.Id, null, 98, day(12)),
            pluggy.Id,
            'axf153-withfact'
          )
        );
      Test.stopTest();
      Assert.isTrue(result.linkedToFact);
      Assert.areEqual(98, result.amount);
      AXF_OBJ_ReconciliationAllocation__c allocation = [
        SELECT AXF_RA_LKP_BankTransaction__c, AXF_RA_LKP_FinancialTransaction__c
        FROM AXF_OBJ_ReconciliationAllocation__c
        WHERE Id = :result.allocationId
      ];
      Assert.areEqual(pluggy.Id, allocation.AXF_RA_LKP_BankTransaction__c);
      Assert.areEqual(
        'ACTUAL_ONLY',
        [
          SELECT AXF_FTX_PKL_PlanKind__c
          FROM AXF_OBJ_FinancialTransaction__c
          WHERE Id = :result.financialTransactionId
        ]
        .AXF_FTX_PKL_PlanKind__c
      );
      ALT_CLS_ManualEntryService.EntryView row = entryOf(
        new ALT_CLS_ManualEntryService().listEntries(thisMonth()),
        result.financialTransactionId
      );
      Assert.areEqual(ALT_CLS_ManualEntryService.STATUS_RECONCILED, row.status);
      Assert.areEqual(connected.Id, row.originId);
    }
  }

  @IsTest
  static void suggestsOnlyPluggyFactsInsideTheWindowAndConfirmsOneClick() {
    System.runAs(byAlias(GESTOR)) {
      Account owner = holder('Holder 153 window');
      AXF_OBJ_BankAccount__c connected = bank(
        owner.Id,
        'CHECKING',
        connection('ITEM153W').Id
      );
      AXF_OBJ_BankAccountTransaction__c inWindow = fact(
        connected.Id,
        104,
        day(16),
        'PLUGGY',
        'w104'
      );
      fact(connected.Id, 106, day(10), 'PLUGGY', 'w106');
      fact(connected.Id, 100, day(18), 'PLUGGY', 'w100late');
      fact(connected.Id, 100, day(10), 'MANUAL', 'w100manual');
      Id target = planned(owner.Id, connected.Id, null, 100, day(10), 'win');
      Test.startTest();
      ALT_CLS_ManualEntryService.FactPage page = new ALT_CLS_ManualEntryService()
        .suggest(saved(target));
      Assert.areEqual('AXF-MATCHING@1.1.0', page.matchingPolicy);
      Assert.isTrue(page.connected);
      Assert.areEqual(target, page.targetId);
      Assert.areEqual(0, page.targetVersion);
      Assert.areEqual(1, page.items.size(), 'only the R$104 fact is inside');
      ALT_CLS_ManualEntryService.FactView only = page.items[0];
      Assert.areEqual(inWindow.Id, only.sourceId);
      Assert.areEqual(4, only.amountDelta);
      Assert.areEqual(6, only.dayDelta);
      Assert.areEqual(100, only.allocationAmount);
      // The same window works for a draft (realize mode) before anything is saved.
      Assert.areEqual(
        1,
        new ALT_CLS_ManualEntryService()
          .suggest(draft(owner.Id, connected.Id, null, 100, day(10)))
          .items.size()
      );
      ALT_CLS_ManualEntryService.ConfirmInput input = new ALT_CLS_ManualEntryService.ConfirmInput();
      input.targetId = target;
      input.targetVersion = 0;
      input.sourceId = only.sourceId;
      input.sourceVersion = only.sourceVersion;
      input.operationKey = 'axf153-confirm';
      ALT_CLS_ManualEntryService.ConfirmResult confirmed = new ALT_CLS_ManualEntryService()
        .confirm(input);
      Test.stopTest();
      Assert.areEqual(100, confirmed.amount);
      Assert.areEqual(
        target,
        [
          SELECT AXF_RA_LKP_FinancialTransaction__c
          FROM AXF_OBJ_ReconciliationAllocation__c
          WHERE Id = :confirmed.allocationId
        ]
        .AXF_RA_LKP_FinancialTransaction__c
      );
      ALT_CLS_ManualEntryService.ReportQuery reconciled = thisMonth();
      reconciled.status = ALT_CLS_ManualEntryService.STATUS_RECONCILED;
      Assert.isNotNull(
        entryOf(
          new ALT_CLS_ManualEntryService().listEntries(reconciled),
          target
        )
      );
      // A second click on the same pair is refused by the link contract.
      input.operationKey = 'axf153-confirm-again';
      String code = failure(new ConfirmCall(input));
      Assert.isTrue(
        code == 'TARGET_REALIZED' ||
          code == 'ALREADY_LINKED' ||
          code == 'CONFLICT',
        code
      );
    }
  }

  @IsTest
  static void ordersTiesExplicitlyAndSkipsExhaustedFacts() {
    System.runAs(byAlias(GESTOR)) {
      Account owner = holder('Holder 153 ties');
      AXF_OBJ_BankAccount__c connected = bank(
        owner.Id,
        'CHECKING',
        connection('ITEM153T').Id
      );
      AXF_OBJ_BankAccountTransaction__c early = fact(
        connected.Id,
        102,
        day(8),
        'PLUGGY',
        't-early'
      );
      AXF_OBJ_BankAccountTransaction__c late = fact(
        connected.Id,
        102,
        day(12),
        'PLUGGY',
        't-late'
      );
      AXF_OBJ_BankAccountTransaction__c exact = fact(
        connected.Id,
        100,
        day(13),
        'PLUGGY',
        't-exact'
      );
      AXF_OBJ_BankAccountTransaction__c drained = fact(
        connected.Id,
        100,
        day(10),
        'PLUGGY',
        't-drained'
      );
      new ALT_CLS_ManualEntryService()
        .realize(
          realizeOf(
            draft(owner.Id, connected.Id, null, 100, day(10)),
            drained.Id,
            'axf153-drain'
          )
        );
      Test.startTest();
      ALT_CLS_ManualEntryService.FactPage page = new ALT_CLS_ManualEntryService()
        .suggest(draft(owner.Id, connected.Id, null, 100, day(10)));
      Test.stopTest();
      Assert.areEqual(
        3,
        page.items.size(),
        'the exhausted fact is not offered'
      );
      Assert.areEqual(exact.Id, page.items[0].sourceId);
      Assert.isFalse(page.items[0].tied);
      Assert.isTrue(page.items[1].tied, 'same Δamount and Δdays');
      Assert.isTrue(page.items[2].tied);
      Set<Id> tiedIds = new Set<Id>{
        page.items[1].sourceId,
        page.items[2].sourceId
      };
      Assert.isTrue(tiedIds.contains(early.Id) && tiedIds.contains(late.Id));
    }
  }

  @IsTest
  static void suggestsCardFactsForAConnectedCard() {
    System.runAs(byAlias(GESTOR)) {
      Account owner = holder('Holder 153 card');
      AXF_OBJ_CreditCard__c connectedCard = card(
        owner.Id,
        connection('ITEM153K').Id
      );
      AXF_OBJ_CreditCardTransaction__c purchase = cardFact(
        connectedCard.Id,
        50,
        day(9),
        'k50'
      );
      cardFact(connectedCard.Id, 80, day(9), 'k80');
      Id target = planned(owner.Id, null, connectedCard.Id, 50, day(8), 'card');
      Test.startTest();
      ALT_CLS_ManualEntryService.FactPage page = new ALT_CLS_ManualEntryService()
        .suggest(saved(target));
      ALT_CLS_ManualEntryService.ConfirmInput input = new ALT_CLS_ManualEntryService.ConfirmInput();
      input.targetId = target;
      input.targetVersion = 0;
      input.sourceId = page.items[0].sourceId;
      input.sourceVersion = page.items[0].sourceVersion;
      input.operationKey = 'axf153-card-confirm';
      ALT_CLS_ManualEntryService.ConfirmResult confirmed = new ALT_CLS_ManualEntryService()
        .confirm(input);
      Test.stopTest();
      Assert.areEqual(1, page.items.size());
      Assert.areEqual(purchase.Id, page.items[0].sourceId);
      Assert.areEqual(50, confirmed.amount);
    }
  }

  @IsTest
  static void manualSearchFindsPeriodFactsWithoutTheAmountWindow() {
    System.runAs(byAlias(GESTOR)) {
      Account owner = holder('Holder 153 search');
      AXF_OBJ_BankAccount__c connected = bank(
        owner.Id,
        'CHECKING',
        connection('ITEM153S').Id
      );
      AXF_OBJ_BankAccountTransaction__c far = fact(
        connected.Id,
        300,
        day(25),
        'PLUGGY',
        'far'
      );
      fact(connected.Id, 100, day(2), 'MANUAL', 'far-manual');
      Id target = planned(owner.Id, connected.Id, null, 100, day(1), 'search');
      ALT_CLS_ManualEntryService.SearchQuery query = new ALT_CLS_ManualEntryService.SearchQuery();
      query.entry = saved(target);
      Test.startTest();
      ALT_CLS_ManualEntryService.FactPage monthPage = new ALT_CLS_ManualEntryService()
        .search(query);
      query.fromDate = day(20);
      query.toDate = day(26);
      query.term = 'far';
      ALT_CLS_ManualEntryService.FactPage termPage = new ALT_CLS_ManualEntryService()
        .search(query);
      query.term = 'nothing like it';
      ALT_CLS_ManualEntryService.FactPage emptyPage = new ALT_CLS_ManualEntryService()
        .search(query);
      query.term = null;
      query.fromDate = day(1).addDays(-400);
      query.toDate = day(1);
      String tooLong = failure(new SearchCall(query));
      Test.stopTest();
      Assert.areEqual(1, monthPage.items.size(), 'default: the entry month');
      Assert.areEqual(far.Id, monthPage.items[0].sourceId);
      Assert.isFalse(monthPage.items[0].inWindow);
      Assert.areEqual(day(1).toStartOfMonth(), monthPage.fromDate);
      Assert.areEqual(1, termPage.items.size());
      Assert.areEqual(0, emptyPage.items.size());
      Assert.areEqual('INVALID_INPUT', tooLong);
    }
  }

  @IsTest
  static void anotherHoldersSourceOrFactIsNeverExposed() {
    Id foreignBank;
    Id foreignFact;
    Id foreignEntry;
    System.runAs(byAlias(PEER)) {
      Account other = holder('Holder 153 foreign');
      AXF_OBJ_BankAccount__c peerBank = bank(
        other.Id,
        'CHECKING',
        connection('ITEM153F').Id
      );
      foreignBank = peerBank.Id;
      foreignFact = fact(peerBank.Id, 100, day(10), 'PLUGGY', 'foreign').Id;
      foreignEntry = planned(other.Id, peerBank.Id, null, 100, day(10), 'frg');
    }
    System.runAs(byAlias(GESTOR)) {
      Account owner = holder('Holder 153 own');
      AXF_OBJ_BankAccount__c ownBank = bank(
        owner.Id,
        'CHECKING',
        connection('ITEM153O').Id
      );
      Test.startTest();
      Assert.areEqual(
        'NOT_ACCESSIBLE',
        failure(
          new SuggestCall(draft(owner.Id, foreignBank, null, 100, day(10)))
        )
      );
      Assert.areEqual(
        'NOT_ACCESSIBLE',
        failure(new SuggestCall(saved(foreignEntry)))
      );
      Assert.areEqual(
        'NOT_ACCESSIBLE',
        failure(
          new RealizeCall(
            realizeOf(
              draft(owner.Id, ownBank.Id, null, 100, day(10)),
              foreignFact,
              'axf153-foreign'
            )
          )
        )
      );
      ALT_CLS_ManualEntryService.ReportView report = new ALT_CLS_ManualEntryService()
        .listEntries(thisMonth());
      Test.stopTest();
      Assert.isNull(entryOf(report, foreignEntry));
      for (ALT_CLS_ManualEntryService.OriginOption o : report.origins) {
        Assert.areNotEqual(foreignBank, o.originId);
      }
    }
  }

  @IsTest
  static void reportFiltersByStatusNatureOriginAndPeriod() {
    System.runAs(byAlias(GESTOR)) {
      Account owner = holder('Holder 153 report');
      AXF_OBJ_BankAccount__c manualBank = bank(owner.Id, 'CHECKING', null);
      AXF_OBJ_BankAccount__c wallet = bank(owner.Id, 'WALLET', null);
      Id open = planned(owner.Id, manualBank.Id, null, 30, day(4), 'open');
      Id lastMonth = planned(
        owner.Id,
        manualBank.Id,
        null,
        31,
        day(4).addMonths(-1),
        'prev'
      );
      Id realized = new ALT_CLS_ManualEntryService()
        .realize(
          realizeOf(
            draft(owner.Id, wallet.Id, null, 12, day(6)),
            null,
            'axf153-report'
          )
        )
        .financialTransactionId;
      Test.startTest();
      ALT_CLS_ManualEntryService service = new ALT_CLS_ManualEntryService();
      ALT_CLS_ManualEntryService.ReportView all = service.listEntries(
        thisMonth()
      );
      ALT_CLS_ManualEntryService.ReportQuery unreconciled = thisMonth();
      unreconciled.status = ALT_CLS_ManualEntryService.STATUS_UNRECONCILED;
      ALT_CLS_ManualEntryService.ReportView open1 = service.listEntries(
        unreconciled
      );
      ALT_CLS_ManualEntryService.ReportQuery credit = thisMonth();
      credit.direction = 'CREDIT';
      ALT_CLS_ManualEntryService.ReportQuery byWallet = thisMonth();
      byWallet.originId = wallet.Id;
      ALT_CLS_ManualEntryService.ReportQuery custom = new ALT_CLS_ManualEntryService.ReportQuery();
      custom.fromDate = day(1).addMonths(-1);
      custom.toDate = day(1).addDays(-1);
      ALT_CLS_ManualEntryService.ReportView previous = service.listEntries(
        custom
      );
      ALT_CLS_ManualEntryService.ReportQuery tooLong = new ALT_CLS_ManualEntryService.ReportQuery();
      tooLong.fromDate = day(1).addDays(-400);
      tooLong.toDate = day(1);
      ALT_CLS_ManualEntryService.ReportQuery badStatus = thisMonth();
      badStatus.status = 'DONE';
      Test.stopTest();
      Assert.areEqual(2, all.entries.size());
      Assert.areEqual(
        'PLANNED',
        entryOf(all, open).planKind,
        'a wizard entry is a planned manual entry'
      );
      Assert.areEqual(
        ALT_CLS_ManualEntryService.ORIGIN_BANK_ACCOUNT,
        entryOf(all, open).originKind
      );
      Assert.areEqual(1, open1.entries.size());
      Assert.areEqual(open, open1.entries[0].recordId);
      Assert.areEqual(0, service.listEntries(credit).entries.size());
      ALT_CLS_ManualEntryService.ReportView walletOnly = service.listEntries(
        byWallet
      );
      Assert.areEqual(1, walletOnly.entries.size());
      Assert.areEqual(realized, walletOnly.entries[0].recordId);
      Assert.isTrue(previous.customPeriod);
      Assert.areEqual(1, previous.entries.size());
      Assert.areEqual(lastMonth, previous.entries[0].recordId);
      Assert.areEqual('INVALID_INPUT', failure(new ReportCall(tooLong)));
      Assert.areEqual('INVALID_INPUT', failure(new ReportCall(badStatus)));
      Assert.isTrue(all.origins.size() >= 2);
    }
  }

  @IsTest
  static void participantReadsTheReportButCannotReconcile() {
    Id target;
    Id bankId;
    System.runAs(byAlias(PARTICIPANT)) {
      Account owner = holder('Holder 153 participant');
      AXF_OBJ_BankAccount__c manualBank = bank(owner.Id, 'CHECKING', null);
      bankId = manualBank.Id;
      // Without access to the connection object the connected flag is still derived.
      AXF_OBJ_CreditCard__c linkedCard = card(
        owner.Id,
        connection('ITEM153N').Id
      );
      target = planned(owner.Id, manualBank.Id, null, 20, day(7), 'part');
      // An entry posted as realized carries an APPLICATION allocation to its manual fact.
      Id realized = new ALT_CLS_ManualEntryService()
        .realize(
          realizeOf(
            draft(owner.Id, manualBank.Id, null, 15, day(8)),
            null,
            'axf153-participant'
          )
        )
        .financialTransactionId;
      Test.startTest();
      ALT_CLS_ManualEntryService.ReportView report = new ALT_CLS_ManualEntryService()
        .listEntries(thisMonth());
      String denied = failure(new SuggestCall(saved(target)));
      List<AXF_CLS_FinancialEntryService.FundingSourceOption> sources = AXF_CLS_FinancialEntryService.getFundingSources(
        owner.Id
      );
      Test.stopTest();
      Assert.areEqual(2, sources.size());
      for (AXF_CLS_FinancialEntryService.FundingSourceOption o : sources) {
        Assert.areEqual(o.creditCardId == linkedCard.Id, o.connected);
      }
      Assert.isFalse(ALT_CLS_ManualEntryService.canReconcile());
      Assert.isNotNull(entryOf(report, target));
      Assert.areEqual(
        ALT_CLS_ManualEntryService.STATUS_UNRECONCILED,
        entryOf(report, target).status
      );
      ALT_CLS_ManualEntryService.EntryView posted = entryOf(report, realized);
      Assert.areEqual(
        ALT_CLS_ManualEntryService.STATUS_RECONCILED,
        posted.status
      );
      Assert.areEqual(15, posted.allocated);
      Assert.areEqual(0, posted.residual);
      Assert.areEqual('UNAVAILABLE', denied);
    }
  }

  @IsTest
  static void rejectsInvalidRequests() {
    System.runAs(byAlias(GESTOR)) {
      Account owner = holder('Holder 153 invalid');
      AXF_OBJ_BankAccount__c wallet = bank(owner.Id, 'WALLET', null);
      ALT_CLS_ManualEntryService.Draft bad = draft(
        owner.Id,
        wallet.Id,
        null,
        10.555,
        day(3)
      );
      ALT_CLS_ManualEntryService.Draft both = draft(
        owner.Id,
        wallet.Id,
        wallet.Id,
        10,
        day(3)
      );
      ALT_CLS_ManualEntryService.ConfirmInput missing = new ALT_CLS_ManualEntryService.ConfirmInput();
      Test.startTest();
      Assert.areEqual(
        'INVALID_INPUT',
        failure(new RealizeCall(realizeOf(bad, null, 'axf153-bad')))
      );
      Assert.areEqual(
        'INVALID_INPUT',
        failure(new RealizeCall(realizeOf(both, null, 'axf153-both')))
      );
      Assert.areEqual(
        'INVALID_INPUT',
        failure(
          new RealizeCall(
            realizeOf(
              draft(owner.Id, wallet.Id, null, 10, day(3)),
              wallet.Id,
              'axf153-factonwallet'
            )
          )
        )
      );
      Assert.areEqual('INVALID_INPUT', failure(new ConfirmCall(missing)));
      Assert.areEqual('INVALID_INPUT', failure(new ReportCall(null)));
      // A wallet has no Pluggy facts: nothing is suggested.
      Assert.isFalse(
        new ALT_CLS_ManualEntryService()
          .suggest(draft(owner.Id, wallet.Id, null, 10, day(3)))
          .connected
      );
      Test.stopTest();
    }
  }
}
