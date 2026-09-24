/**
 * @description AXF-157: Apex->LWC boundary of the timesheet screen. Capability context, strict JSON
 * parsing, delegation, DTO conversion and sanitized {code} errors; never a stack trace or a foreign
 * record. The user holds only a mirror permission set created here.
 */
@IsTest
// API 62: AXON_DEV enforces FLS on plain test DML under runAs from API 67 onwards.
private class AXF_CLS_CTRL_TimesheetTest {
  private static User actor() {
    return [SELECT Id FROM User WHERE Alias = 'axf157c' LIMIT 1];
  }

  @TestSetup
  static void setup() {
    User user = new User(
      Alias = 'axf157c',
      Email = 'axf157c@example.invalid',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Timesheet Controller',
      LanguageLocaleKey = 'pt_BR',
      LocaleSidKey = 'pt_BR',
      TimeZoneSidKey = 'America/Sao_Paulo',
      ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
      .Id,
      Username = 'axf157c.' + System.now().getTime() + '@example.invalid'
    );
    insert user;
    PermissionSet mirror = new PermissionSet(
      Name = 'AXF157_TimesheetCtrlMirror',
      Label = 'AXF157 Timesheet controller mirror'
    );
    insert mirror;
    insert new List<ObjectPermissions>{
      new ObjectPermissions(
        ParentId = mirror.Id,
        SobjectType = 'AXF_OBJ_Contract__c',
        PermissionsRead = true
      ),
      new ObjectPermissions(
        ParentId = mirror.Id,
        SobjectType = 'AXF_OBJ_ContractTermVersion__c',
        PermissionsRead = true
      ),
      new ObjectPermissions(
        ParentId = mirror.Id,
        SobjectType = 'AXF_OBJ_BankAccount__c',
        PermissionsRead = true
      ),
      new ObjectPermissions(
        ParentId = mirror.Id,
        SobjectType = 'AXF_OBJ_WorkRecord__c',
        PermissionsRead = true,
        PermissionsCreate = true,
        PermissionsEdit = true
      )
    };
    List<FieldPermissions> fields = new List<FieldPermissions>();
    for (
      String field : new List<String>{
        'AXF_OBJ_Contract__c.AXF_CTR_LKP_ActiveTermVersion__c',
        'AXF_OBJ_Contract__c.AXF_CTR_DAT_StartDate__c',
        'AXF_OBJ_Contract__c.AXF_CTR_DAT_EndDate__c',
        'AXF_OBJ_Contract__c.AXF_CTR_DAT_TerminationEffectiveDate__c',
        'AXF_OBJ_ContractTermVersion__c.AXF_CTV_DAT_EffectiveTo__c',
        'AXF_OBJ_WorkRecord__c.AXF_WR_LKP_TermVersion__c',
        'AXF_OBJ_ContractTermVersion__c.AXF_CTV_CUR_Rate__c',
        'AXF_OBJ_ContractTermVersion__c.AXF_CTV_LKP_PreferredBankAccount__c',
        'AXF_OBJ_BankAccount__c.AXF_BA_TXT_InstitutionName__c',
        'AXF_OBJ_BankAccount__c.AXF_BA_TXT_NumberMasked__c',
        'AXF_OBJ_BankAccount__c.AXF_BA_TXT_Type__c',
        'AXF_OBJ_WorkRecord__c.AXF_WR_TXT_Description__c'
      }
    ) {
      fields.add(
        new FieldPermissions(
          ParentId = mirror.Id,
          SobjectType = field.substringBefore('.'),
          Field = field,
          PermissionsRead = true
        )
      );
    }
    insert fields;
    insert new PermissionSetAssignment(
      AssigneeId = user.Id,
      PermissionSetId = mirror.Id
    );
  }

  /** Active service contract (REVENUE, HOURLY 120/BRL) without destination account. */
  private static Id serviceContract() {
    Account holder = new Account(
      Name = 'Titular CTRL 157',
      RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
        .get('AXF_Business')
        .getRecordTypeId()
    );
    insert holder;
    AXF_OBJ_Counterparty__c cpty = new AXF_OBJ_Counterparty__c(
      Name = 'Cliente CTRL 157',
      AXF_CPTY_TXT_DisplayName__c = 'Cliente CTRL 157',
      AXF_CPTY_TXT_LegalName__c = 'Cliente CTRL 157 LTDA',
      AXF_CPTY_TXT_Country__c = 'BR',
      AXF_CPTY_PKL_Kind__c = 'ORGANIZATION',
      AXF_CPTY_PKL_Status__c = 'ACTIVE',
      AXF_CPTY_EXI_CounterpartyKey__c = AXF_CLS_IdentityFraming.key(
        new List<Object>{ 'CPTY', 'Cliente CTRL 157 LTDA', 'BR' }
      ),
      AXF_CPTY_NUM_Version__c = 1
    );
    insert cpty;
    AXF_OBJ_CounterpartyEntityRelationship__c rel = new AXF_OBJ_CounterpartyEntityRelationship__c(
      AXF_CER_LKP_Counterparty__c = cpty.Id,
      AXF_CER_LKP_Account__c = holder.Id,
      AXF_CER_PKL_Role__c = 'CLIENT',
      AXF_CER_PKL_Status__c = 'ACTIVE',
      AXF_CER_TXT_EntitySpecificDisplay__c = 'Cliente',
      AXF_CER_EXI_RelationshipKey__c = AXF_CLS_IdentityFraming.key(
        new List<Object>{ 'CER', cpty.Id, holder.Id, 'CLIENT' }
      ),
      AXF_CER_NUM_Version__c = 1
    );
    insert rel;
    AXF_OBJ_Contract__c ctr = new AXF_OBJ_Contract__c(
      AXF_CTR_LKP_Account__c = holder.Id,
      AXF_CTR_LKP_Relationship__c = rel.Id,
      AXF_CTR_LKP_Counterparty__c = cpty.Id,
      AXF_CTR_TXT_ContractCode__c = 'SVC-CTRL',
      AXF_CTR_EXI_ContractKey__c = AXF_CLS_IdentityFraming.key(
        new List<Object>{ 'CONTRACT', holder.Id, 'SVC-CTRL' }
      ),
      AXF_CTR_TXT_Title__c = 'Consultoria',
      AXF_CTR_PKL_Lifecycle__c = 'ACTIVE',
      AXF_CTR_PKL_Type__c = 'REVENUE',
      AXF_CTR_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_CTR_NUM_Version__c = 1
    );
    insert ctr;
    AXF_OBJ_ContractTermVersion__c term = new AXF_OBJ_ContractTermVersion__c(
      AXF_CTV_LKP_Contract__c = ctr.Id,
      AXF_CTV_NUM_Revision__c = 1,
      AXF_CTV_PKL_Status__c = 'ACTIVE',
      AXF_CTV_PKL_RemunerationModel__c = 'HOURLY',
      AXF_CTV_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_CTV_DAT_EffectiveFrom__c = Date.newInstance(2026, 1, 1),
      AXF_CTV_CUR_Rate__c = 120,
      AXF_CTV_EXI_TermKey__c = 'TERM-SVC-CTRL',
      AXF_CTV_NUM_Version__c = 1
    );
    insert term;
    ctr.AXF_CTR_LKP_ActiveTermVersion__c = term.Id;
    update ctr;
    return ctr.Id;
  }

  private static String codeOf(Exception failure) {
    return failure.getMessage();
  }

  @IsTest
  static void registersSubmitsListsAndForecasts() {
    System.runAs(actor()) {
      Id contractId = serviceContract();

      Test.startTest();
      AXF_CLS_CTRL_Timesheet.Context context = AXF_CLS_CTRL_Timesheet.getContext();
      List<AXF_CLS_CTRL_Timesheet.ContractOption> contracts = AXF_CLS_CTRL_Timesheet.listContracts();
      AXF_CLS_CTRL_Timesheet.EntryResult saved = AXF_CLS_CTRL_Timesheet.saveEntry(
        JSON.serialize(
          new Map<String, Object>{
            'contractId' => contractId,
            'workDate' => '2026-09-10',
            'startTime' => '09:00',
            'breakStart' => '12:00',
            'breakEnd' => '12:30',
            'endTime' => '18:00',
            'note' => 'Workshop'
          }
        )
      );
      AXF_CLS_CTRL_Timesheet.EntryResult submitted = AXF_CLS_CTRL_Timesheet.submitEntry(
        JSON.serialize(
          new Map<String, Object>{ 'workRecordId' => saved.workRecordId }
        )
      );
      AXF_CLS_CTRL_Timesheet.EntryList entries = AXF_CLS_CTRL_Timesheet.listEntries(
        '{"year":2026,"month":9}'
      );
      AXF_CLS_CTRL_Timesheet.Forecast projection = AXF_CLS_CTRL_Timesheet.getForecast(
        '{"year":2026,"month":9,"destination":null}'
      );
      Test.stopTest();

      Assert.isTrue(context.canUse);
      Assert.isTrue(context.canRegister);
      Assert.isTrue(context.canSubmit);
      Assert.areEqual(1, contracts.size());
      Assert.areEqual(120, contracts[0].rate);
      Assert.areEqual(8.5, saved.hours);
      Assert.areEqual('DRAFT', saved.status);
      Assert.isTrue(saved.created);
      Assert.areEqual('SUBMITTED', submitted.status);
      Assert.areEqual(1, entries.entries.size());
      Assert.areEqual('09:00-12:00 | 12:30-18:00', entries.entries[0].times);
      Assert.areEqual('Workshop', entries.entries[0].note);
      Assert.isFalse(entries.entries[0].canSubmit);
      Assert.isFalse(entries.entries[0].canEdit);
      Assert.areEqual('NOT_BILLABLE', entries.entries[0].billingStatus);
      Assert.areEqual(1, projection.groups.size());
      Assert.areEqual('NONE', projection.groups[0].destination.key);
      Assert.areEqual(1020, projection.groups[0].lines[0].pendingAmount);
      Assert.areEqual(0, projection.groups[0].lines[0].approvedAmount);
      Assert.areEqual(1, projection.totals.size());
      Assert.areEqual(8.5, projection.totals[0].pendingHours);
    }
  }

  @IsTest
  static void refusesMalformedRequestsWithSanitizedCodes() {
    System.runAs(actor()) {
      Id contractId = serviceContract();
      List<String> codes = new List<String>();

      Test.startTest();
      try {
        AXF_CLS_CTRL_Timesheet.saveEntry('');
      } catch (AuraHandledException failure) {
        codes.add(codeOf(failure));
      }
      try {
        AXF_CLS_CTRL_Timesheet.listEntries('{"year":2026,"hack":true}');
      } catch (AuraHandledException failure) {
        codes.add(codeOf(failure));
      }
      try {
        AXF_CLS_CTRL_Timesheet.getForecast('{"destination":"x"}');
      } catch (AuraHandledException failure) {
        codes.add(codeOf(failure));
      }
      try {
        AXF_CLS_CTRL_Timesheet.saveEntry(
          JSON.serialize(
            new Map<String, Object>{
              'contractId' => contractId,
              'workDate' => '2026-09-10',
              'startTime' => '09:00',
              'breakStart' => '12:00',
              'endTime' => '18:00'
            }
          )
        );
      } catch (AuraHandledException failure) {
        codes.add(codeOf(failure));
      }
      try {
        AXF_CLS_CTRL_Timesheet.submitEntry('{"workRecordId":"not-an-id"}');
      } catch (AuraHandledException failure) {
        codes.add(codeOf(failure));
      }
      Test.stopTest();

      Assert.areEqual(
        new List<String>{
          'INVALID_INPUT',
          'INVALID_INPUT',
          'INVALID_INPUT',
          'INVALID_INPUT',
          'INVALID_INPUT'
        },
        codes
      );
      Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_WorkRecord__c]);
    }
  }

  @IsTest
  static void sanitizesPlatformFailures() {
    Assert.areEqual(
      'NOT_ACCESSIBLE',
      AXF_CLS_CTRL_Timesheet.safe(new QueryException('secret detail'))
        .getMessage()
    );
    Assert.areEqual(
      'REJECTED',
      AXF_CLS_CTRL_Timesheet.safe(new DmlException('secret detail'))
        .getMessage()
    );
    Assert.areEqual(
      'UNEXPECTED',
      AXF_CLS_CTRL_Timesheet.safe(new NullPointerException()).getMessage()
    );
    Assert.areEqual(
      'INVALID_STATE',
      AXF_CLS_CTRL_Timesheet.safe(
          new ALT_CLS_TimesheetService.TimesheetException('INVALID_STATE')
        )
        .getMessage()
    );
  }
}
