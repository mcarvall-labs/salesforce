/**
 * @description AXF-153: the manual-entries report controller parses JSON strictly, delegates to
 * ALT_CLS_ManualEntryService and only ever returns sanitized {code} failures.
 */
@IsTest
private class AXF_CLS_CTRL_ManualEntriesTest {
  @TestSetup
  static void grantAccess() {
    List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (PermissionSet p : [
      SELECT Id
      FROM PermissionSet
      WHERE
        Name IN (
          'AXF_PS_FinancialEntry',
          'AXF_PS_GestorFinanceiro',
          'AXF_PS_Realization'
        )
    ]) {
      assignments.add(
        new PermissionSetAssignment(
          AssigneeId = UserInfo.getUserId(),
          PermissionSetId = p.Id
        )
      );
    }
    insert assignments;
  }

  private static String failureOf(String request) {
    try {
      AXF_CLS_CTRL_ManualEntries.listEntries(request);
    } catch (AuraHandledException failure) {
      return failure.getMessage();
    }
    return 'NO_EXCEPTION';
  }

  @IsTest
  static void listsTheManualEntriesOfTheMonth() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Account holder = new Account(
        Name = 'Holder CTRL 153',
        RecordTypeId = Account.SObjectType.getDescribe()
          .getRecordTypeInfosByDeveloperName()
          .get('AXF_Business')
          .getRecordTypeId()
      );
      insert holder;
      AXF_OBJ_BankAccount__c account = new AXF_OBJ_BankAccount__c(
        AXF_BA_LKP_Account__c = holder.Id,
        AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
        AXF_BA_TXT_CurrencyIsoCode__c = 'BRL',
        AXF_BA_TXT_InstitutionName__c = 'Banco CTRL 153'
      );
      insert account;
      AXF_CLS_FinancialEntryService.EntryResult created = AXF_CLS_CTRL_FinancialEntry.createEntry(
        holder.Id,
        'CREDIT',
        70,
        'BRL',
        Date.today(),
        null,
        account.Id,
        null,
        '15315315-3153-1531-5315-315315315315',
        false
      );
      Test.startTest();
      ALT_CLS_ManualEntryService.ReportView view = AXF_CLS_CTRL_ManualEntries.listEntries(
        JSON.serialize(
          new Map<String, Object>{
            'year' => Date.today().year(),
            'month' => Date.today().month(),
            'direction' => 'CREDIT',
            'status' => 'UNRECONCILED'
          }
        )
      );
      Test.stopTest();
      System.assertEquals(1, view.entries.size());
      System.assertEquals(
        created.financialTransactionId,
        view.entries[0].recordId
      );
      System.assertEquals('Banco CTRL 153', view.entries[0].originLabel);
    }
  }

  @IsTest
  static void sanitizesInvalidRequests() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Test.startTest();
      String blank = failureOf(null);
      String unknown = failureOf('{"sort":"name"}');
      String malformed = failureOf('{');
      String badStatus = failureOf('{"status":"DONE"}');
      String tooLong = failureOf(
        '{"fromDate":"2025-01-01","toDate":"2026-06-01"}'
      );
      Test.stopTest();
      System.assertEquals('INVALID_INPUT', blank);
      System.assertEquals('INVALID_INPUT', unknown);
      System.assertEquals('INVALID_INPUT', malformed);
      System.assertEquals('INVALID_INPUT', badStatus);
      System.assertEquals('INVALID_INPUT', tooLong);
      System.assertEquals(
        'NOT_ACCESSIBLE',
        AXF_CLS_CTRL_ManualEntries.safe(new QueryException('x')).getMessage()
      );
      System.assertEquals(
        'UNEXPECTED',
        AXF_CLS_CTRL_ManualEntries.safe(new MathException('x')).getMessage()
      );
    }
  }
}
