/**
 * @description AXF-152: Apex->LWC boundary of the credit-card screen. Capability context, JSON
 * parsing, delegation and sanitized {code} errors; never a stack trace or a foreign record.
 */
@IsTest(isParallel=false)
// API 62: AXON_DEV enforces FLS on plain test DML under runAs from API 67 onwards.
private class AXF_CLS_CTRL_CardStatementTest {
  private static User byAlias(String alias) {
    return [SELECT Id FROM User WHERE Alias = :alias LIMIT 1];
  }

  @TestSetup
  static void setup() {
    Id profileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
    .Id;
    List<User> users = new List<User>();
    for (String alias : new List<String>{ 'axf152c', 'axf152q' }) {
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
    // Mirrors the read-only cycle-rule access this branch adds to the permission sets (check-only deploys
    // do not apply the branch's permission-set changes to test users).
    PermissionSet ruleAccess = new PermissionSet(
      Name = 'AXF152_TestCtrlCycleRuleAccess',
      Label = 'AXF152 test ctrl cycle rule access'
    );
    insert ruleAccess;
    insert new ObjectPermissions(
      ParentId = ruleAccess.Id,
      SobjectType = 'AXF_OBJ_CardBillingCycleRule__c',
      PermissionsRead = true
    );
    List<FieldPermissions> fields = new List<FieldPermissions>();
    for (
      String field : new List<String>{
        'AXF_CBR_DAT_EffectiveTo__c',
        'AXF_CBR_NUM_ClosingDay__c',
        'AXF_CBR_NUM_DueDayOffset__c',
        'AXF_CBR_NUM_Version__c',
        'AXF_CBR_PKL_ClosingDayAdjustment__c',
        'AXF_CBR_PKL_DueDayAdjustment__c',
        'AXF_CBR_TXT_CalendarPolicyVersion__c'
      }
    ) {
      fields.add(
        new FieldPermissions(
          ParentId = ruleAccess.Id,
          SobjectType = 'AXF_OBJ_CardBillingCycleRule__c',
          Field = 'AXF_OBJ_CardBillingCycleRule__c.' + field,
          PermissionsRead = true
        )
      );
    }
    insert fields;
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
    assignments.add(
      new PermissionSetAssignment(
        AssigneeId = users[0].Id,
        PermissionSetId = ruleAccess.Id
      )
    );
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
      if (name == 'invoice') {
        return AXF_CLS_CTRL_CardStatement.getInvoice(request);
      }
      if (name == 'suggest') {
        return AXF_CLS_CTRL_CardStatement.listSuggestions(request);
      }
      if (name == 'confirm') {
        return AXF_CLS_CTRL_CardStatement.confirmSuggestion(request);
      }
      return AXF_CLS_CTRL_CardStatement.defineClosing(request);
    }
  }

  private static Id card() {
    Account owner = new Account(
      Name = 'Holder 152 ctrl',
      RecordTypeId = Account.SObjectType.getDescribe()
        .getRecordTypeInfosByDeveloperName()
        .get('AXF_Business')
        .getRecordTypeId()
    );
    insert owner;
    AXF_OBJ_CreditCard__c result = new AXF_OBJ_CreditCard__c(
      AXF_CC_LKP_Account__c = owner.Id,
      AXF_CC_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_CC_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_CC_TXT_InstitutionName__c = 'Banco 152'
    );
    insert result;
    return result.Id;
  }

  @IsTest
  static void contextReflectsTheCapabilities() {
    System.runAs(byAlias('axf152c')) {
      ALT_CLS_CardStatementService.canConfigureOverride = true;
      AXF_CLS_CTRL_CardStatement.Context context = AXF_CLS_CTRL_CardStatement.getContext();
      Assert.isTrue(context.canUse);
      Assert.isTrue(context.canConfigure);
      Assert.isTrue(context.canReconcile, 'gestor holds the link capability');
      Assert.areEqual('AXF-MATCHING@1.1.0', context.matchingPolicy);
      Assert.areEqual('CAL-1.0.0', context.calendarPolicy);
    }
    System.runAs(byAlias('axf152q')) {
      ALT_CLS_CardStatementService.canConfigureOverride = false;
      AXF_CLS_CTRL_CardStatement.Context context = AXF_CLS_CTRL_CardStatement.getContext();
      Assert.isTrue(context.canUse, 'reading needs only the context');
      Assert.isFalse(context.canConfigure);
      Assert.isFalse(context.canReconcile);
    }
  }

  @IsTest
  static void everyEndpointDelegatesAndStaysSanitized() {
    System.runAs(byAlias('axf152c')) {
      ALT_CLS_CardStatementService.canConfigureOverride = true;
      Id cardId = card();
      Test.startTest();
      List<ALT_CLS_CardStatementService.CardView> cards = AXF_CLS_CTRL_CardStatement.listCards();
      ALT_CLS_CardStatementService.InvoiceView invoice = AXF_CLS_CTRL_CardStatement.getInvoice(
        JSON.serialize(new Map<String, Object>{ 'creditCardId' => cardId })
      );
      ALT_CLS_CardStatementService.CardView closed = AXF_CLS_CTRL_CardStatement.defineClosing(
        JSON.serialize(
          new Map<String, Object>{
            'creditCardId' => cardId,
            'closingDay' => 5,
            'dueDay' => 12
          }
        )
      );
      ALT_CLS_CardStatementService.InvoiceView resolved = AXF_CLS_CTRL_CardStatement.getInvoice(
        JSON.serialize(new Map<String, Object>{ 'creditCardId' => cardId })
      );
      Test.stopTest();
      Assert.areEqual(1, cards.size());
      Assert.areEqual(cardId, invoice.card.creditCardId);
      Assert.areEqual('BLOCKED', invoice.outcome, 'no calendar yet');
      Assert.isTrue(closed.hasCalendar);
      Assert.areEqual(5, closed.closingDay);
      Assert.areEqual('RESOLVED', resolved.outcome);
    }
  }

  @IsTest
  static void malformedAndForeignRequestsReturnCodes() {
    Id cardId;
    System.runAs(byAlias('axf152c')) {
      cardId = card();
      Assert.areEqual('INVALID_INPUT', code(new Endpoint('invoice', '')));
      Assert.areEqual(
        'INVALID_INPUT',
        code(new Endpoint('invoice', '{"unknown":1}'))
      );
      Assert.areEqual(
        'INVALID_INPUT',
        code(
          new Endpoint(
            'suggest',
            JSON.serialize(
              new Map<String, Object>{
                'creditCardId' => cardId,
                'lineKind' => 'FACT',
                'recordId' => cardId
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
            JSON.serialize(new Map<String, Object>{ 'creditCardId' => cardId })
          )
        )
      );
    }
    System.runAs(byAlias('axf152q')) {
      ALT_CLS_CardStatementService.canConfigureOverride = false;
      Assert.areEqual(
        'NOT_ALLOWED',
        code(
          new Endpoint(
            'closing',
            JSON.serialize(
              new Map<String, Object>{
                'creditCardId' => cardId,
                'closingDay' => 5,
                'dueDay' => 12
              }
            )
          )
        )
      );
      Assert.areEqual(
        'NOT_ACCESSIBLE',
        code(
          new Endpoint(
            'invoice',
            JSON.serialize(new Map<String, Object>{ 'creditCardId' => cardId })
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
                'creditCardId' => cardId,
                'lineKind' => 'FACT',
                'recordId' => cardId
              }
            )
          )
        )
      );
    }
  }

  @IsTest
  static void platformFailuresAreSanitized() {
    Assert.areEqual(
      'NOT_ACCESSIBLE',
      AXF_CLS_CTRL_CardStatement.safe(new QueryException('secret')).getMessage()
    );
    Assert.areEqual(
      'REJECTED',
      AXF_CLS_CTRL_CardStatement.safe(new DmlException('secret')).getMessage()
    );
    Assert.areEqual(
      'UNEXPECTED',
      AXF_CLS_CTRL_CardStatement.safe(new MathException('secret')).getMessage()
    );
    Assert.areEqual(
      'CONFLICT',
      AXF_CLS_CTRL_CardStatement.safe(
          new ALT_CLS_CardStatementService.CardStatementException('CONFLICT')
        )
        .getMessage()
    );
  }
}
