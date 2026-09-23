/**
 * @description AXF-156: controller exclusivo da tela de Financiamentos. JSON estrito, DTOs da tela
 * e erros sanitizados como {code}.
 */
@IsTest(isParallel=false)
private class AXF_CLS_CTRL_FinancingsTest {
  private static final String GESTOR = 'axf156cg';

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
      Name = 'AXF156_TestControllerMirror',
      Label = 'AXF156 controller mirror'
    );
    insert mirror;
    Map<String, List<String>> readFields = new Map<String, List<String>>{
      'AXF_OBJ_ScheduleDefinition__c' => new List<String>{
        'AXF_SDF_NUM_PeriodDays__c',
        'AXF_SDF_NUM_PeriodMonths__c',
        'AXF_SDF_TAL_InputCanonicalJson__c',
        'AXF_SDF_NUM_Principal__c',
        'AXF_SDF_NUM_PeriodRate__c',
        'AXF_SDF_NUM_FixedValue__c',
        'AXF_SDF_NUM_RecurringFee__c',
        'AXF_SDF_NUM_UpfrontFee__c',
        'AXF_SDF_NUM_TotalInstallments__c'
      },
      'AXF_OBJ_FinancialSchedule__c' => new List<String>{
        'AXF_FSC_LKP_ActiveDefinition__c',
        'AXF_FSC_LKP_Contract__c',
        'AXF_FSC_DAT_TerminationDate__c'
      },
      'AXF_OBJ_ScheduleChange__c' => new List<String>{
        'AXF_SCH_TAL_ResultJson__c'
      },
      'AXF_OBJ_FinancialTransaction__c' => new List<String>{
        'AXF_FTX_LKP_Schedule__c',
        'AXF_FTX_LKP_Contract__c',
        'AXF_FTX_NUM_Sequence__c',
        'AXF_FTX_DAT_DueDate__c',
        'AXF_FTX_NUM_CurrentBasis__c',
        'AXF_FTX_PKL_ScheduleState__c',
        'AXF_FTX_PKL_Modality__c',
        'AXF_FTX_NUM_PrincipalPortion__c',
        'AXF_FTX_NUM_InterestPortion__c',
        'AXF_FTX_NUM_ClosingBalance__c',
        'AXF_FTX_TXT_ScheduleGroupKey__c',
        'AXF_FTX_TXT_Description__c'
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
  }
  private static Account holder() {
    Account owner = new Account(
      Name = 'Holder 156 ctrl',
      RecordTypeId = Account.SObjectType.getDescribe()
        .getRecordTypeInfosByDeveloperName()
        .get('AXF_Business')
        .getRecordTypeId()
    );
    insert owner;
    return owner;
  }

  private static Id installmentPlan(Id accountId) {
    ALT_CLS_FinancialScheduleService.CreateInput input = new ALT_CLS_FinancialScheduleService.CreateInput();
    input.accountId = accountId;
    input.direction = 'DEBIT';
    input.currencyIsoCode = 'BRL';
    input.method = 'INSTALLMENT';
    input.totalInstallments = 6;
    input.firstSequence = 1;
    input.firstDueDate = Date.today();
    input.periodMonths = 1;
    input.principal = 600;
    input.description = 'Celular';
    input.generationEnabled = true;
    ALT_CLS_FinancialScheduleService.CreateResult created = ALT_CLS_FinancialScheduleService.createSchedule(
      input
    );
    Assert.areEqual('CREATED', created.outcome, created.message);
    return created.scheduleId;
  }

  private static String code(Exception failure) {
    return failure.getMessage();
  }

  @IsTest
  static void coversTheScreenLifecycleThroughJson() {
    System.runAs(gestor()) {
      lifecycle();
    }
  }

  private static void lifecycle() {
    Id scheduleId = installmentPlan(holder().Id);

    Test.startTest();
    AXF_CLS_CTRL_Financings.Context context = AXF_CLS_CTRL_Financings.getContext();
    List<AXF_CLS_CTRL_Financings.Financing> listed = AXF_CLS_CTRL_Financings.listFinancings();
    AXF_CLS_CTRL_Financings.Detail detail = AXF_CLS_CTRL_Financings.getDetail(
      JSON.serialize(new Map<String, Object>{ 'scheduleId' => scheduleId })
    );
    AXF_CLS_CTRL_Financings.Result edited = AXF_CLS_CTRL_Financings.editAmount(
      JSON.serialize(
        new Map<String, Object>{
          'scheduleId' => scheduleId,
          'amount' => 110,
          'expectedVersion' => 0,
          'operationKey' => 'ctrl-edit'
        }
      )
    );
    AXF_CLS_CTRL_Financings.Preview preview = AXF_CLS_CTRL_Financings.previewSettlement(
      JSON.serialize(new Map<String, Object>{ 'scheduleId' => scheduleId })
    );
    AXF_CLS_CTRL_Financings.Result settled = AXF_CLS_CTRL_Financings.settle(
      JSON.serialize(
        new Map<String, Object>{
          'scheduleId' => scheduleId,
          'amount' => preview.suggestedAmount,
          'settlementDate' => String.valueOf(preview.maxDate),
          'expectedVersion' => preview.version,
          'operationKey' => 'ctrl-settle'
        }
      )
    );
    Test.stopTest();

    Assert.isTrue(context.canUse);
    Assert.isTrue(context.canManage);
    Assert.areEqual(1, listed.size());
    Assert.areEqual('Celular', listed[0].description);
    Assert.areEqual(600.00, listed[0].outstandingBalance);
    Assert.areEqual(6, detail.installments.size());
    Assert.areEqual('PLANNED', detail.installments[0].status);
    Assert.areEqual(6, edited.changedCount);
    Assert.areEqual(550.00, preview.suggestedAmount, 'parcelas após a data');
    Assert.isNotNull(settled.settlementTransactionId);
    Assert.areEqual(
      'SETTLED',
      AXF_CLS_CTRL_Financings.listFinancings()[0].state
    );
    try {
      AXF_CLS_CTRL_Financings.terminate(
        JSON.serialize(
          new Map<String, Object>{
            'scheduleId' => scheduleId,
            'terminationDate' => String.valueOf(Date.today()),
            'expectedVersion' => 2,
            'operationKey' => 'ctrl-end'
          }
        )
      );
      Assert.fail('encerrado não é alterado');
    } catch (AuraHandledException expected) {
      Assert.areEqual('NOT_ALLOWED', code(expected));
    }
  }

  @IsTest
  static void sanitizesInvalidRequestsAndFailures() {
    System.runAs(gestor()) {
      invalidRequests();
    }
  }

  private static void invalidRequests() {
    for (String request : new List<String>{ null, '', '{"unknown":1}' }) {
      try {
        AXF_CLS_CTRL_Financings.getDetail(request);
        Assert.fail('JSON inválido deve ser recusado');
      } catch (AuraHandledException expected) {
        Assert.areEqual('INVALID_INPUT', code(expected));
      }
    }
    try {
      AXF_CLS_CTRL_Financings.editAmount('{"scheduleId":null}');
      Assert.fail('sem cronograma');
    } catch (AuraHandledException expected) {
      Assert.areEqual('INVALID_INPUT', code(expected));
    }
    try {
      AXF_CLS_CTRL_Financings.terminate('not json');
      Assert.fail('JSON malformado');
    } catch (AuraHandledException expected) {
      Assert.areEqual('INVALID_INPUT', code(expected));
    }
    try {
      AXF_CLS_CTRL_Financings.settle('{"legacyKey":"gk-none"}');
      Assert.fail('grupo inexistente');
    } catch (AuraHandledException expected) {
      Assert.areEqual('NOT_ACCESSIBLE', code(expected));
    }
    try {
      AXF_CLS_CTRL_Financings.previewSettlement('{"legacyKey":"gk-none"}');
      Assert.fail('legado não é quitado');
    } catch (AuraHandledException expected) {
      Assert.areEqual('NOT_ALLOWED', code(expected));
    }
    Assert.areEqual(
      'NOT_ACCESSIBLE',
      AXF_CLS_CTRL_Financings.safe(new QueryException('detail')).getMessage()
    );
    Assert.areEqual(
      'REJECTED',
      AXF_CLS_CTRL_Financings.safe(new DmlException('detail')).getMessage()
    );
    Assert.areEqual(
      'UNEXPECTED',
      AXF_CLS_CTRL_Financings.safe(new MathException('detail')).getMessage()
    );
  }
}
