/**
 * @description AXF-151: Apex->LWC boundary of the current-account screen. Capability context,
 * JSON parsing, delegation and sanitized {code} errors; never a stack trace or a foreign record.
 */
@IsTest(isParallel=false)
// API 62: AXON_DEV enforces FLS on plain test DML under runAs from API 67 onwards.
private class AXF_CLS_CTRL_BankStatementTest {
  private static User byAlias(String alias) {
    return [SELECT Id FROM User WHERE Alias = :alias LIMIT 1];
  }

  @TestSetup
  static void setup() {
    Id profileId = [
      SELECT Id
      FROM Profile
      // The standard profile name is translated for a pt_BR running user.
      WHERE Name IN ('Standard User', 'Usuário Padrão')
      LIMIT 1
    ]
    .Id;
    List<User> users = new List<User>();
    for (String alias : new List<String>{ 'axf151c', 'axf151q' }) {
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

  private class Fixture {
    Account holder;
    AXF_OBJ_BankAccount__c wallet;
    AXF_OBJ_BankAccountTransaction__c fact;
    AXF_OBJ_FinancialTransaction__c planned;
  }

  private static Fixture fixture() {
    Fixture f = new Fixture();
    f.holder = new Account(
      Name = 'Holder CTRL 151',
      RecordTypeId = Account.SObjectType.getDescribe()
        .getRecordTypeInfosByDeveloperName()
        .get('AXF_Business')
        .getRecordTypeId()
    );
    insert f.holder;
    f.wallet = new AXF_OBJ_BankAccount__c(
      AXF_BA_LKP_Account__c = f.holder.Id,
      AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_BA_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BA_TXT_Type__c = 'WALLET',
      AXF_BA_CUR_CurrentBalance__c = 20,
      AXF_BA_NUM_Version__c = 1
    );
    insert f.wallet;
    f.fact = new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_MDR_BankAccount__c = f.wallet.Id,
      AXF_BAT_NUM_Magnitude__c = 30,
      AXF_BAT_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BAT_PKL_Direction__c = 'DEBIT',
      AXF_BAT_DAT_Date__c = Date.today(),
      AXF_BAT_TXT_Description__c = 'Feira',
      AXF_BAT_EXI_SourceKey__c = 'axf151c-fact',
      AXF_BAT_PKL_Source__c = 'MANUAL',
      AXF_BAT_PKL_Status__c = 'POSTED',
      AXF_BAT_NUM_Version__c = 0
    );
    insert f.fact;
    f.planned = new AXF_OBJ_FinancialTransaction__c(
      AXF_FTX_LKP_Account__c = f.holder.Id,
      AXF_FTX_LKP_BankAccount__c = f.wallet.Id,
      AXF_FTX_NUM_Magnitude__c = 30,
      AXF_FTX_PKL_Direction__c = 'DEBIT',
      AXF_FTX_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_FTX_DAT_PurchaseDate__c = Date.today(),
      AXF_FTX_DAT_DueDate__c = Date.today(),
      AXF_FTX_TXT_Description__c = 'Feira prevista',
      AXF_FTX_PKL_PlanKind__c = 'PLANNED',
      AXF_FTX_PKL_Status__c = 'PLANNED',
      AXF_FTX_NUM_Version__c = 0,
      AXF_FTX_EXI_ClientRequestId__c = 'ftx-151c'
    );
    insert f.planned;
    return f;
  }

  private static String codeOf(Exception e) {
    return e.getMessage();
  }

  private static String statementCode(String request) {
    try {
      AXF_CLS_CTRL_BankStatement.getStatement(request);
    } catch (AuraHandledException expected) {
      return expected.getMessage();
    }
    return 'NO_EXCEPTION';
  }

  @IsTest
  static void contextReflectsTheCapabilities() {
    AXF_CLS_CTRL_BankStatement.Context gestor;
    AXF_CLS_CTRL_BankStatement.Context participant;
    System.runAs(byAlias('axf151c')) {
      gestor = AXF_CLS_CTRL_BankStatement.getContext();
    }
    System.runAs(byAlias('axf151q')) {
      participant = AXF_CLS_CTRL_BankStatement.getContext();
      Assert.areEqual(
        0,
        AXF_CLS_CTRL_BankStatement.listAccounts().size(),
        'reading needs only the authorized context'
      );
      try {
        AXF_CLS_CTRL_BankStatement.listSuggestions(
          JSON.serialize(
            new Map<String, Object>{
              'bankAccountId' => AXF_OBJ_BankAccount__c.SObjectType.getDescribe()
                .getKeyPrefix() + '000000000000',
              'lineKind' => 'FACT',
              'recordId' => AXF_OBJ_BankAccountTransaction__c.SObjectType.getDescribe()
                .getKeyPrefix() + '000000000000'
            }
          )
        );
        Assert.fail('link capability required');
      } catch (AuraHandledException expected) {
        Assert.areEqual('UNAVAILABLE', codeOf(expected));
      }
    }
    Assert.isTrue(gestor.canUse);
    Assert.isTrue(gestor.canConfigure);
    Assert.isTrue(gestor.canReconcile);
    Assert.areEqual('AXF-MATCHING@1.1.0', gestor.matchingPolicy);
    Assert.isTrue(participant.canUse);
    Assert.isFalse(participant.canReconcile);
    Assert.isFalse(participant.canConfigure);
  }

  @IsTest
  static void everyEndpointDelegatesAndStaysSanitized() {
    System.runAs(byAlias('axf151c')) {
      Fixture f = fixture();
      Test.startTest();
      List<ALT_CLS_BankStatementService.AccountView> accounts = AXF_CLS_CTRL_BankStatement.listAccounts();
      ALT_CLS_BankStatementService.StatementView view = AXF_CLS_CTRL_BankStatement.getStatement(
        JSON.serialize(
          new Map<String, Object>{ 'bankAccountId' => f.wallet.Id }
        )
      );
      ALT_CLS_BankStatementService.SuggestionPage page = AXF_CLS_CTRL_BankStatement.listSuggestions(
        JSON.serialize(
          new Map<String, Object>{
            'bankAccountId' => f.wallet.Id,
            'lineKind' => 'FACT',
            'recordId' => f.fact.Id
          }
        )
      );
      ALT_CLS_BankStatementService.ConfirmResult confirmed = AXF_CLS_CTRL_BankStatement.confirmSuggestion(
        JSON.serialize(
          new Map<String, Object>{
            'bankAccountId' => f.wallet.Id,
            'sourceId' => page.items[0].sourceId,
            'sourceVersion' => page.items[0].sourceVersion,
            'targetId' => page.items[0].targetId,
            'targetVersion' => page.items[0].targetVersion,
            'operationKey' => 'axf151c-click'
          }
        )
      );
      ALT_CLS_BankStatementService.AccountView balance = AXF_CLS_CTRL_BankStatement.updateBalance(
        JSON.serialize(
          new Map<String, Object>{
            'bankAccountId' => f.wallet.Id,
            'balance' => 12.5,
            'expectedVersion' => 1
          }
        )
      );
      String refresh;
      try {
        AXF_CLS_CTRL_BankStatement.refreshBalance(
          JSON.serialize(
            new Map<String, Object>{ 'bankAccountId' => f.wallet.Id }
          )
        );
      } catch (AuraHandledException expected) {
        refresh = codeOf(expected);
      }
      String retry;
      try {
        AXF_CLS_CTRL_BankStatement.confirmSuggestion(
          JSON.serialize(
            new Map<String, Object>{
              'bankAccountId' => f.wallet.Id,
              'sourceId' => page.items[0].sourceId,
              'sourceVersion' => page.items[0].sourceVersion,
              'targetId' => page.items[0].targetId,
              'targetVersion' => page.items[0].targetVersion,
              'operationKey' => 'axf151c-click-2'
            }
          )
        );
      } catch (AuraHandledException expected) {
        retry = codeOf(expected);
      }
      Test.stopTest();
      Assert.areEqual(1, accounts.size());
      Assert.isTrue(accounts[0].wallet);
      Assert.areEqual(2, view.lines.size(), 'fact and unallocated entry');
      Assert.areEqual(1, page.items.size());
      Assert.areEqual(30, confirmed.amount);
      Assert.areEqual(12.5, balance.currentBalance);
      Assert.areEqual(2, balance.version);
      Assert.areEqual('NOT_ALLOWED', refresh, 'a wallet has no Pluggy');
      Assert.areEqual(
        'TARGET_REALIZED',
        retry,
        'a second click is refused, never doubled'
      );
      Assert.areEqual('INVALID_INPUT', statementCode(' '), 'blank request');
      Assert.areEqual('INVALID_INPUT', statementCode('{"bankAccountId":'));
      Assert.areEqual(
        'INVALID_INPUT',
        statementCode('{"unexpected":true}'),
        'strict parsing'
      );
      Assert.areEqual(
        'NOT_ACCESSIBLE',
        statementCode(
          JSON.serialize(
            new Map<String, Object>{
              'bankAccountId' => AXF_OBJ_BankAccount__c.SObjectType.getDescribe()
                .getKeyPrefix() + '000000000000'
            }
          )
        ),
        'a missing account answers like a foreign one'
      );
    }
  }

  @IsTest
  static void platformFailuresAreSanitized() {
    Assert.areEqual(
      'NOT_ACCESSIBLE',
      codeOf(AXF_CLS_CTRL_BankStatement.safe(new QueryException('detail')))
    );
    Assert.areEqual(
      'REJECTED',
      codeOf(AXF_CLS_CTRL_BankStatement.safe(new DmlException('detail')))
    );
    Assert.areEqual(
      'UNEXPECTED',
      codeOf(AXF_CLS_CTRL_BankStatement.safe(new MathException('detail')))
    );
    Assert.areEqual(
      'CONFLICT',
      codeOf(
        AXF_CLS_CTRL_BankStatement.safe(
          new ALT_CLS_SourceLinkService.SourceLinkException('CONFLICT')
        )
      )
    );
  }
}
