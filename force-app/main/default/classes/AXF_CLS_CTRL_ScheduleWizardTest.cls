/**
 * @description AXF-156: the schedule planner controller hands the origin and description over to
 * the managed schedule and keeps the AXF-20 save outcomes.
 */
@IsTest(isParallel=false)
private class AXF_CLS_CTRL_ScheduleWizardTest {
  private static Account holder() {
    Account result = new Account(
      Name = 'Holder 156 wizard',
      RecordTypeId = Account.SObjectType.getDescribe()
        .getRecordTypeInfosByDeveloperName()
        .get('AXF_Business')
        .getRecordTypeId()
    );
    insert result;
    return result;
  }

  private static String planJson(String modality) {
    return JSON.serialize(
      new Map<String, Object>{
        'modality' => modality,
        'principal' => 1200,
        'installments' => 12,
        'periodRate' => modality == 'INSTALLMENT' ? null : 0.01,
        'firstDueDate' => String.valueOf(Date.today())
      }
    );
  }

  @IsTest
  static void savesAManagedFinancingWithOriginAndDescription() {
    Account owner = holder();
    AXF_CLS_ScheduleService.authorizedOverride = new Set<Id>{ owner.Id };
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      owner.Id
    };
    AXF_OBJ_BankAccount__c cash = new AXF_OBJ_BankAccount__c(
      AXF_BA_LKP_Account__c = owner.Id,
      AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_BA_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BA_TXT_Type__c = 'WALLET',
      AXF_BA_NUM_Version__c = 1
    );
    insert cash;

    Test.startTest();
    AXF_CLS_ScheduleService.SaveResult saved = AXF_CLS_CTRL_ScheduleWizard.saveSchedule(
      planJson('SAC'),
      owner.Id,
      'DEBIT',
      'BRL',
      'sch-ctrl-156-0001',
      cash.Id,
      null,
      'Moto'
    );
    AXF_CLS_ScheduleService.SaveResult again = AXF_CLS_CTRL_ScheduleWizard.saveSchedule(
      planJson('SAC'),
      owner.Id,
      'DEBIT',
      'BRL',
      'sch-ctrl-156-0001',
      cash.Id,
      null,
      'Moto'
    );
    AXF_CLS_ScheduleService.SaveResult other = AXF_CLS_CTRL_ScheduleWizard.saveSchedule(
      planJson('INSTALLMENT'),
      owner.Id,
      'DEBIT',
      'BRL',
      'sch-ctrl-156-0001',
      null,
      null,
      null
    );
    Test.stopTest();

    Assert.areEqual('SAVED', saved.outcome, saved.message);
    Assert.areEqual('ALREADY', again.outcome, again.message);
    Assert.areEqual('CONFLICT', other.outcome, other.message);
    Assert.areEqual(12, saved.occurrenceCount);
    Integer rows = 0;
    for (AXF_OBJ_FinancialTransaction__c row : [
      SELECT AXF_FTX_LKP_BankAccount__c, AXF_FTX_TXT_Description__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE AXF_FTX_LKP_Schedule__c = :saved.scheduleId
    ]) {
      Assert.areEqual(cash.Id, row.AXF_FTX_LKP_BankAccount__c);
      Assert.areEqual('Moto', row.AXF_FTX_TXT_Description__c);
      rows++;
    }
    Assert.areEqual(12, rows);
  }

  @IsTest
  static void foreignOriginIsRejectedWithoutWriting() {
    Account owner = holder();
    Account other = holder();
    AXF_CLS_ScheduleService.authorizedOverride = new Set<Id>{ owner.Id };
    ALT_CLS_FinancialScheduleService.authorizedOverride = new Set<Id>{
      owner.Id
    };
    AXF_OBJ_BankAccount__c foreign = new AXF_OBJ_BankAccount__c(
      AXF_BA_LKP_Account__c = other.Id,
      AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_BA_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BA_TXT_Type__c = 'WALLET',
      AXF_BA_NUM_Version__c = 1
    );
    insert foreign;

    AXF_CLS_ScheduleService.SaveResult rejected = AXF_CLS_CTRL_ScheduleWizard.saveSchedule(
      planJson('PRICE'),
      owner.Id,
      'DEBIT',
      'BRL',
      'sch-ctrl-156-0002',
      foreign.Id,
      null,
      null
    );

    Assert.areEqual('INVALID', rejected.outcome);
    Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_FinancialSchedule__c]);
  }
}
