/**
 * @description AXF-19 / AXF-106 — the LWC boundary now takes primitive params because
 * Aura cannot populate an @AuraEnabled inner class of another top-level class, so this
 * test calls the controller exactly the way the LWC does.
 */
@IsTest
private class AXF_CLS_CTRL_FinancialEntryTest {
  @TestSetup
  static void grantAccess() {
    List<PermissionSet> ps = [
      SELECT Id
      FROM PermissionSet
      WHERE
        Name IN (
          'AXF_PS_FinancialEntry',
          'AXF_PS_GestorFinanceiro',
          'AXF_PS_Realization'
        )
    ];
    List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (PermissionSet p : ps) {
      assignments.add(
        new PermissionSetAssignment(
          AssigneeId = UserInfo.getUserId(),
          PermissionSetId = p.Id
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

  private static AXF_OBJ_BankAccount__c source(Id holderId, String type) {
    AXF_OBJ_BankAccount__c result = new AXF_OBJ_BankAccount__c(
      AXF_BA_LKP_Account__c = holderId,
      AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_BA_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BA_TXT_InstitutionName__c = type == 'WALLET' ? null : 'Banco CTRL',
      AXF_BA_TXT_Type__c = type
    );
    insert result;
    return result;
  }

  private static String failureOf(Callable call) {
    try {
      call.call('run', null);
    } catch (AuraHandledException failure) {
      return failure.getMessage();
    }
    return 'NO_EXCEPTION';
  }

  private class JsonCall implements Callable {
    String method;
    String request;
    JsonCall(String method, String request) {
      this.method = method;
      this.request = request;
    }
    public Object call(String action, Map<String, Object> args) {
      if (method == 'realize') {
        return AXF_CLS_CTRL_FinancialEntry.realizeEntry(request);
      }
      if (method == 'suggest') {
        return AXF_CLS_CTRL_FinancialEntry.listFactSuggestions(request);
      }
      if (method == 'search') {
        return AXF_CLS_CTRL_FinancialEntry.searchFacts(request);
      }
      return AXF_CLS_CTRL_FinancialEntry.confirmFact(request);
    }
  }

  private static Id rt(String dev) {
    return Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
      .getRecordTypeInfosByDeveloperName()
      .get(dev)
      .getRecordTypeId();
  }

  private static Account holder() {
    Account a = new Account(
      Name = 'Titular Controller FTX',
      RecordTypeId = rt('AXF_Business')
    );
    insert a;
    return a;
  }

  @IsTest
  static void createsEntryThroughPrimitiveControllerParams() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Account a = holder();
      AXF_OBJ_BankAccount__c account = source(a.Id, 'CHECKING');

      Test.startTest();
      AXF_CLS_FinancialEntryService.EntryResult r = AXF_CLS_CTRL_FinancialEntry.createEntry(
        a.Id,
        'DEBIT',
        100.50,
        'BRL',
        Date.today(),
        null,
        account.Id,
        null,
        '66666666-6666-6666-6666-666666666666',
        false
      );
      Test.stopTest();

      System.assertEquals(
        'CREATED',
        r.outcome,
        'unexpected outcome: ' + String.valueOf(r.message)
      );
      System.assertNotEquals(null, r.financialTransactionId);
    }
  }

  @IsTest
  static void exposesFundingSourcesThroughController() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Account a = holder();

      Test.startTest();
      List<AXF_CLS_FinancialEntryService.FundingSourceOption> sources = AXF_CLS_CTRL_FinancialEntry.getFundingSources(
        a.Id
      );
      Test.stopTest();

      System.assert(
        sources != null,
        'the controller must return the authorized funding sources'
      );
    }
  }

  @IsTest
  static void rejectsInvalidPayloadThroughController() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Account a = holder();

      Test.startTest();
      AXF_CLS_FinancialEntryService.EntryResult r = AXF_CLS_CTRL_FinancialEntry.createEntry(
        a.Id,
        'DEBIT',
        0,
        'BRL',
        Date.today(),
        null,
        null,
        null,
        '77777777-7777-7777-7777-777777777777',
        false
      );
      Test.stopTest();

      System.assertEquals('INVALID', r.outcome);
    }
  }

  @IsTest
  static void deniesWithoutAuthorizedAccountThroughController() {
    Test.startTest();
    AXF_CLS_FinancialEntryService.EntryResult r = AXF_CLS_CTRL_FinancialEntry.createEntry(
      null,
      'DEBIT',
      10.00,
      'BRL',
      Date.today(),
      null,
      null,
      null,
      '88888888-8888-8888-8888-888888888888',
      false
    );
    Test.stopTest();

    System.assertEquals('FORBIDDEN', r.outcome);
  }

  @IsTest
  static void requiresAnOriginThroughController() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Account a = holder();

      Test.startTest();
      AXF_CLS_FinancialEntryService.EntryResult r = AXF_CLS_CTRL_FinancialEntry.createEntry(
        a.Id,
        'DEBIT',
        10.00,
        'BRL',
        Date.today(),
        null,
        null,
        null,
        '99999999-9999-9999-9999-999999999999',
        false
      );
      Test.stopTest();

      System.assertEquals('INVALID', r.outcome);
      System.assertEquals(Label.AXF_ManualEntry_originRequired, r.message);
      System.assertEquals(
        0,
        [SELECT COUNT() FROM AXF_OBJ_FinancialTransaction__c]
      );
    }
  }

  @IsTest
  static void exposesCapabilities() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Test.startTest();
      AXF_CLS_CTRL_FinancialEntry.Capabilities result = AXF_CLS_CTRL_FinancialEntry.getCapabilities();
      Test.stopTest();
      System.assertEquals(true, result.canRealize);
      System.assertEquals(true, result.canReconcile);
      System.assertEquals('AXF-MATCHING@1.1.0', result.matchingPolicy);
    }
  }

  @IsTest
  static void realizesAWalletEntryThroughJson() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Account a = holder();
      AXF_OBJ_BankAccount__c wallet = source(a.Id, 'WALLET');
      Map<String, Object> entry = new Map<String, Object>{
        'accountId' => a.Id,
        'bankAccountId' => wallet.Id,
        'direction' => 'DEBIT',
        'amount' => 15.5,
        'currencyIsoCode' => 'BRL',
        'entryDate' => String.valueOf(Date.today())
      };

      Test.startTest();
      ALT_CLS_ManualEntryService.RealizeResult result = AXF_CLS_CTRL_FinancialEntry.realizeEntry(
        JSON.serialize(
          new Map<String, Object>{
            'entry' => entry,
            'operationKey' => 'ctrl-153-wallet'
          }
        )
      );
      ALT_CLS_ManualEntryService.FactPage suggestions = AXF_CLS_CTRL_FinancialEntry.listFactSuggestions(
        JSON.serialize(entry)
      );
      ALT_CLS_ManualEntryService.FactPage search = AXF_CLS_CTRL_FinancialEntry.searchFacts(
        JSON.serialize(new Map<String, Object>{ 'entry' => entry })
      );
      Test.stopTest();

      System.assertNotEquals(null, result.financialTransactionId);
      System.assertEquals(false, result.linkedToFact);
      System.assertEquals(false, suggestions.connected);
      System.assertEquals(0, search.items.size());
    }
  }

  @IsTest
  static void sanitizesInvalidJsonAndServiceFailures() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Test.startTest();
      String blank = failureOf(new JsonCall('realize', ''));
      String unknown = failureOf(new JsonCall('suggest', '{"unknown":1}'));
      String malformed = failureOf(new JsonCall('search', '{not json'));
      String incomplete = failureOf(new JsonCall('confirm', '{}'));
      Test.stopTest();
      System.assertEquals('INVALID_INPUT', blank);
      System.assertEquals('INVALID_INPUT', unknown);
      System.assertEquals('INVALID_INPUT', malformed);
      System.assertEquals('INVALID_INPUT', incomplete);
      System.assertEquals(
        'NOT_ACCESSIBLE',
        AXF_CLS_CTRL_FinancialEntry.safe(new QueryException('x')).getMessage()
      );
      System.assertEquals(
        'REJECTED',
        AXF_CLS_CTRL_FinancialEntry.safe(new DmlException('x')).getMessage()
      );
      System.assertEquals(
        'UNEXPECTED',
        AXF_CLS_CTRL_FinancialEntry.safe(new MathException('x')).getMessage()
      );
      System.assertEquals(
        'CONFLICT',
        AXF_CLS_CTRL_FinancialEntry.safe(
            new ALT_CLS_SourceLinkService.SourceLinkException('CONFLICT')
          )
          .getMessage()
      );
    }
  }
}
