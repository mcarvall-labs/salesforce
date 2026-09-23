/**
 * @description AXF-155: controller exclusivo da tela de Recorrências. JSON estrito, DTOs da tela e
 * erros sanitizados como {code}.
 */
@IsTest(isParallel=false)
// API 62: AXON_DEV enforces FLS on plain test DML under runAs from API 67 onwards.
private class AXF_CLS_CTRL_RecurrencesTest {
  private static final String GESTOR = 'axf155cg';

  private static User gestor() {
    return [SELECT Id FROM User WHERE Alias = :GESTOR LIMIT 1];
  }

  @TestSetup
  static void setup() {
    User user = new User(
      Alias = GESTOR,
      Email = GESTOR + '@example.invalid',
      EmailEncodingKey = 'UTF-8',
      LastName = 'User ' + GESTOR,
      LanguageLocaleKey = 'pt_BR',
      LocaleSidKey = 'pt_BR',
      TimeZoneSidKey = 'America/Sao_Paulo',
      ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
      .Id,
      Username = GESTOR + '.' + System.now().getTime() + '@example.invalid'
    );
    insert user;
    // Check-only deploys do not apply the branch's permission-set changes to test users.
    PermissionSet mirror = new PermissionSet(
      Name = 'AXF155_TestControllerMirror',
      Label = 'AXF155 controller mirror'
    );
    insert mirror;
    Map<String, List<String>> readFields = new Map<String, List<String>>{
      'AXF_OBJ_ScheduleDefinition__c' => new List<String>{
        'AXF_SDF_NUM_PeriodDays__c',
        'AXF_SDF_NUM_PeriodMonths__c',
        'AXF_SDF_TAL_InputCanonicalJson__c',
        'AXF_SDF_NUM_InitialReferenceAmount__c'
      },
      'AXF_OBJ_FinancialSchedule__c' => new List<String>{
        'AXF_FSC_LKP_ActiveDefinition__c',
        'AXF_FSC_LKP_ActiveReference__c',
        'AXF_FSC_LKP_Contract__c',
        'AXF_FSC_DAT_TerminationDate__c'
      },
      'AXF_OBJ_ScheduleReference__c' => new List<String>{
        'AXF_SRF_LKP_Compensates__c'
      },
      'AXF_OBJ_FinancialTransaction__c' => new List<String>{
        'AXF_FTX_LKP_Schedule__c',
        'AXF_FTX_NUM_Sequence__c',
        'AXF_FTX_DAT_DueDate__c',
        'AXF_FTX_NUM_CurrentBasis__c',
        'AXF_FTX_PKL_ScheduleState__c'
      },
      'AXF_OBJ_BankAccount__c' => new List<String>{
        'AXF_BA_LKP_Account__c',
        'AXF_BA_TXT_InstitutionName__c',
        'AXF_BA_LKP_BankInstitution__c',
        'AXF_BA_TXT_NumberMasked__c',
        'AXF_BA_TXT_Type__c',
        'AXF_BA_TXT_CurrencyIsoCode__c'
      }
    };
    List<ObjectPermissions> access = new List<ObjectPermissions>();
    List<FieldPermissions> fields = new List<FieldPermissions>();
    for (String objectName : readFields.keySet()) {
      Boolean schedule = objectName == 'AXF_OBJ_FinancialSchedule__c';
      access.add(
        new ObjectPermissions(
          ParentId = mirror.Id,
          SobjectType = objectName,
          PermissionsRead = true,
          PermissionsCreate = schedule,
          PermissionsEdit = schedule
        )
      );
      for (String field : readFields.get(objectName)) {
        fields.add(
          new FieldPermissions(
            ParentId = mirror.Id,
            SobjectType = objectName,
            Field = objectName + '.' + field,
            PermissionsRead = true
          )
        );
      }
    }
    insert access;
    insert fields;
    List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>{
      new PermissionSetAssignment(
        AssigneeId = user.Id,
        PermissionSetId = mirror.Id
      )
    };
    for (PermissionSet permission : [
      SELECT Id
      FROM PermissionSet
      WHERE Name IN ('AXF_PS_GestorFinanceiro', 'AXF_PS_FinancialEntry')
    ]) {
      assignments.add(
        new PermissionSetAssignment(
          AssigneeId = user.Id,
          PermissionSetId = permission.Id
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

  private static String code(Exception failure) {
    return failure.getMessage();
  }

  @IsTest
  static void coversTheScreenLifecycleThroughJson() {
    User user = gestor();
    System.runAs(user) {
      Account owner = new Account(
        Name = 'Holder 155 ctrl',
        RecordTypeId = Account.SObjectType.getDescribe()
          .getRecordTypeInfosByDeveloperName()
          .get('AXF_Business')
          .getRecordTypeId()
      );
      insert owner;
      AXF_OBJ_BankAccount__c cash = new AXF_OBJ_BankAccount__c(
        AXF_BA_LKP_Account__c = owner.Id,
        AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
        AXF_BA_TXT_CurrencyIsoCode__c = 'BRL',
        AXF_BA_TXT_Type__c = 'WALLET',
        AXF_BA_NUM_Version__c = 1
      );
      insert cash;

      AXF_CLS_CTRL_Recurrences.Context context = AXF_CLS_CTRL_Recurrences.getContext();
      Assert.isTrue(context.canUse);
      Assert.isTrue(context.canManage);
      Assert.isFalse(context.holders.isEmpty());
      List<AXF_CLS_CTRL_Recurrences.Source> sources = AXF_CLS_CTRL_Recurrences.getSources(
        JSON.serialize(new Map<String, Object>{ 'accountId' => owner.Id })
      );
      Assert.areEqual(1, sources.size());
      Assert.areEqual(cash.Id, sources[0].bankAccountId);

      Test.startTest();
      AXF_CLS_CTRL_Recurrences.Result created = AXF_CLS_CTRL_Recurrences.createRecurrence(
        JSON.serialize(
          new Map<String, Object>{
            'accountId' => owner.Id,
            'description' => 'Água',
            'direction' => 'DEBIT',
            'amount' => 80,
            'currencyIsoCode' => 'BRL',
            'firstDueDate' => String.valueOf(Date.today().addDays(5)),
            'periodMonths' => 1,
            'bankAccountId' => cash.Id,
            'operationKey' => 'ctrl-create'
          }
        )
      );
      List<AXF_CLS_CTRL_Recurrences.Recurrence> listed = AXF_CLS_CTRL_Recurrences.listRecurrences();
      AXF_CLS_CTRL_Recurrences.Detail detail = AXF_CLS_CTRL_Recurrences.getDetail(
        JSON.serialize(
          new Map<String, Object>{ 'scheduleId' => created.scheduleId }
        )
      );
      AXF_CLS_CTRL_Recurrences.Result edited = AXF_CLS_CTRL_Recurrences.editAmount(
        JSON.serialize(
          new Map<String, Object>{
            'scheduleId' => created.scheduleId,
            'amount' => 95.5,
            'expectedVersion' => 0,
            'operationKey' => 'ctrl-edit'
          }
        )
      );
      AXF_CLS_CTRL_Recurrences.Result ended = AXF_CLS_CTRL_Recurrences.terminate(
        JSON.serialize(
          new Map<String, Object>{
            'scheduleId' => created.scheduleId,
            'terminationDate' => String.valueOf(Date.today()),
            'expectedVersion' => 1,
            'operationKey' => 'ctrl-end'
          }
        )
      );
      Test.stopTest();

      Assert.isTrue(created.changedCount > 0);
      Assert.areEqual(1, listed.size());
      Assert.areEqual('Água', listed[0].description);
      Assert.areEqual(1, listed[0].periodMonths);
      Assert.areEqual(created.changedCount, detail.occurrences.size());
      Assert.areEqual('PLANNED', detail.occurrences[0].status);
      Assert.areEqual(created.changedCount, edited.changedCount);
      Assert.areEqual(created.changedCount, ended.changedCount);
      Assert.isFalse(ended.replay);
      Assert.areEqual(
        'ENDED',
        AXF_CLS_CTRL_Recurrences.listRecurrences()[0].state
      );
    }
  }

  @IsTest
  static void sanitizesInvalidRequestsAndFailures() {
    System.runAs(gestor()) {
      for (String request : new List<String>{ null, '', '{"unknown":1}' }) {
        try {
          AXF_CLS_CTRL_Recurrences.getDetail(request);
          Assert.fail('JSON inválido deve ser recusado');
        } catch (AuraHandledException expected) {
          Assert.areEqual('INVALID_INPUT', code(expected));
        }
      }
      try {
        AXF_CLS_CTRL_Recurrences.editAmount('{"scheduleId":null}');
        Assert.fail('sem cronograma');
      } catch (AuraHandledException expected) {
        Assert.areEqual('INVALID_INPUT', code(expected));
      }
      try {
        AXF_CLS_CTRL_Recurrences.terminate('not json');
        Assert.fail('JSON malformado');
      } catch (AuraHandledException expected) {
        Assert.areEqual('INVALID_INPUT', code(expected));
      }
      try {
        AXF_CLS_CTRL_Recurrences.createRecurrence('{"accountId":null}');
        Assert.fail('sem titular');
      } catch (AuraHandledException expected) {
        Assert.areEqual('INVALID_INPUT', code(expected));
      }
      try {
        AXF_CLS_CTRL_Recurrences.getSources('{"accountId":null}');
        Assert.fail('sem titular');
      } catch (AuraHandledException expected) {
        Assert.areEqual('INVALID_INPUT', code(expected));
      }
    }
    Assert.areEqual(
      'NOT_ACCESSIBLE',
      AXF_CLS_CTRL_Recurrences.safe(new QueryException('detail')).getMessage()
    );
    Assert.areEqual(
      'REJECTED',
      AXF_CLS_CTRL_Recurrences.safe(new DmlException('detail')).getMessage()
    );
    Assert.areEqual(
      'UNEXPECTED',
      AXF_CLS_CTRL_Recurrences.safe(new MathException('detail')).getMessage()
    );
  }
}
