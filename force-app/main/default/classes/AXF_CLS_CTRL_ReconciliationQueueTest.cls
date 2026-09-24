/**
 * @description AXF-154: Apex->LWC boundary of the reconciliation queue. Capability context, JSON
 * parsing, delegation and sanitized {code} errors; never a stack trace or a foreign record.
 */
@IsTest(isParallel=false)
// API 62: AXON_DEV enforces FLS on plain test DML under runAs from API 67 onwards.
private class AXF_CLS_CTRL_ReconciliationQueueTest {
  private static User byAlias(String alias) {
    return [SELECT Id FROM User WHERE Alias = :alias LIMIT 1];
  }

  @TestSetup
  static void setup() {
    Id profileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
    .Id;
    List<User> users = new List<User>();
    for (String alias : new List<String>{ 'axf154c', 'axf154q' }) {
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
    List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (
      String name : new List<String>{
        'AXF_PS_GestorFinanceiro',
        'AXF_PS_FinancialEntry',
        'AXF_PS_Realization'
      }
    ) {
      assignments.add(
        new PermissionSetAssignment(
          AssigneeId = users[0].Id,
          PermissionSetId = permissionSets.get(name)
        )
      );
    }
    for (
      String name : new List<String>{
        'AXF_PS_Participante',
        'AXF_PS_FinancialEntry'
      }
    ) {
      assignments.add(
        new PermissionSetAssignment(
          AssigneeId = users[1].Id,
          PermissionSetId = permissionSets.get(name)
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

  private static String code(Callable call) {
    try {
      call.call('run', null);
    } catch (AuraHandledException expected) {
      return expected.getMessage();
    }
    return 'NO_EXCEPTION';
  }

  private class Endpoint implements Callable {
    String name;
    String request;
    Endpoint(String name, String request) {
      this.name = name;
      this.request = request;
    }
    public Object call(String action, Map<String, Object> args) {
      if (name == 'queue') {
        return AXF_CLS_CTRL_ReconciliationQueue.getQueue(request);
      }
      if (name == 'suggest') {
        return AXF_CLS_CTRL_ReconciliationQueue.listSuggestions(request);
      }
      return AXF_CLS_CTRL_ReconciliationQueue.confirmSuggestion(request);
    }
  }

  private static AXF_OBJ_BankAccount__c bank() {
    Account owner = new Account(
      Name = 'Holder 154 ctrl',
      RecordTypeId = Account.SObjectType.getDescribe()
        .getRecordTypeInfosByDeveloperName()
        .get('AXF_Business')
        .getRecordTypeId()
    );
    insert owner;
    AXF_OBJ_BankAccount__c result = new AXF_OBJ_BankAccount__c(
      AXF_BA_LKP_Account__c = owner.Id,
      AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_BA_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BA_TXT_InstitutionName__c = 'Banco 154',
      AXF_BA_TXT_Type__c = 'CHECKING',
      AXF_BA_NUM_Version__c = 1
    );
    insert result;
    return result;
  }

  private static AXF_OBJ_BankAccountTransaction__c fact(Id bankId) {
    AXF_OBJ_BankAccountTransaction__c result = new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_MDR_BankAccount__c = bankId,
      AXF_BAT_NUM_Magnitude__c = 100,
      AXF_BAT_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BAT_PKL_Direction__c = 'DEBIT',
      AXF_BAT_DAT_Date__c = Date.today().toStartOfMonth(),
      AXF_BAT_TXT_Description__c = 'Ctrl 154',
      AXF_BAT_EXI_SourceKey__c = 'axf154-ctrl',
      AXF_BAT_PKL_Source__c = 'PLUGGY',
      AXF_BAT_PKL_Status__c = 'POSTED',
      AXF_BAT_NUM_Version__c = 0
    );
    insert result;
    return result;
  }

  @IsTest
  static void contextReflectsTheLinkCapability() {
    System.runAs(byAlias('axf154c')) {
      AXF_CLS_CTRL_ReconciliationQueue.Context context = AXF_CLS_CTRL_ReconciliationQueue.getContext();
      Assert.isTrue(context.canReconcile, 'gestor holds the link capability');
      Assert.areEqual('AXF-MATCHING@1.1.0', context.matchingPolicy);
    }
    System.runAs(byAlias('axf154q')) {
      Assert.isFalse(
        AXF_CLS_CTRL_ReconciliationQueue.getContext().canReconcile
      );
    }
  }

  @IsTest
  static void everyEndpointDelegates() {
    System.runAs(byAlias('axf154c')) {
      AXF_OBJ_BankAccount__c account = bank();
      AXF_OBJ_BankAccountTransaction__c source = fact(account.Id);
      Test.startTest();
      ALT_CLS_ReconciliationQueueService.SourceList sources = AXF_CLS_CTRL_ReconciliationQueue.listSources();
      ALT_CLS_ReconciliationQueueService.QueueView view = AXF_CLS_CTRL_ReconciliationQueue.getQueue(
        JSON.serialize(new Map<String, Object>{ 'kind' => 'BANK' })
      );
      ALT_CLS_BankStatementService.SuggestionPage page = AXF_CLS_CTRL_ReconciliationQueue.listSuggestions(
        JSON.serialize(
          new Map<String, Object>{
            'fundingId' => account.Id,
            'recordId' => source.Id
          }
        )
      );
      Test.stopTest();
      Assert.areEqual(1, sources.items.size());
      Assert.areEqual('BANK', sources.items[0].kind);
      Assert.areEqual(1, view.pending.size());
      Assert.areEqual(source.Id, view.pending[0].recordId);
      Assert.areEqual(0, page.items.size(), 'no planned entry to suggest');
    }
  }

  @IsTest
  static void malformedForeignAndUnauthorizedRequestsReturnCodes() {
    AXF_OBJ_BankAccount__c account;
    AXF_OBJ_BankAccountTransaction__c source;
    System.runAs(byAlias('axf154c')) {
      account = bank();
      source = fact(account.Id);
      Assert.areEqual('INVALID_INPUT', code(new Endpoint('queue', '')));
      Assert.areEqual(
        'INVALID_INPUT',
        code(new Endpoint('queue', '{"unknown":1}'))
      );
      Assert.areEqual(
        'INVALID_INPUT',
        code(
          new Endpoint(
            'queue',
            JSON.serialize(
              new Map<String, Object>{
                'invoiceYear' => 2026,
                'invoiceMonth' => 9
              }
            )
          )
        )
      );
      Assert.areEqual(
        'INVALID_INPUT',
        code(
          new Endpoint(
            'confirm',
            JSON.serialize(new Map<String, Object>{ 'fundingId' => account.Id })
          )
        )
      );
    }
    System.runAs(byAlias('axf154q')) {
      Assert.areEqual(
        'NOT_ACCESSIBLE',
        code(
          new Endpoint(
            'queue',
            JSON.serialize(new Map<String, Object>{ 'fundingId' => account.Id })
          )
        )
      );
      Assert.areEqual(
        'UNAVAILABLE',
        code(
          new Endpoint(
            'suggest',
            JSON.serialize(
              new Map<String, Object>{
                'fundingId' => account.Id,
                'recordId' => source.Id
              }
            )
          )
        )
      );
      Assert.areEqual(
        'UNAVAILABLE',
        code(
          new Endpoint(
            'confirm',
            JSON.serialize(new Map<String, Object>{ 'fundingId' => account.Id })
          )
        )
      );
    }
  }

  @IsTest
  static void platformFailuresAreSanitized() {
    Assert.areEqual(
      'NOT_ACCESSIBLE',
      AXF_CLS_CTRL_ReconciliationQueue.safe(new QueryException('secret'))
        .getMessage()
    );
    Assert.areEqual(
      'REJECTED',
      AXF_CLS_CTRL_ReconciliationQueue.safe(new DmlException('secret'))
        .getMessage()
    );
    Assert.areEqual(
      'UNEXPECTED',
      AXF_CLS_CTRL_ReconciliationQueue.safe(new MathException('secret'))
        .getMessage()
    );
    Assert.areEqual(
      'CONFLICT',
      AXF_CLS_CTRL_ReconciliationQueue.safe(
          new ALT_CLS_ReconciliationQueueService.ReconciliationQueueException(
            'CONFLICT'
          )
        )
        .getMessage()
    );
  }
}
