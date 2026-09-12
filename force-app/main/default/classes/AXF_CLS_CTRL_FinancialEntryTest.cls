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
      WHERE Name IN ('AXF_PS_FinancialEntry', 'AXF_PS_GestorFinanceiro')
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

      Test.startTest();
      AXF_CLS_FinancialEntryService.EntryResult r = AXF_CLS_CTRL_FinancialEntry.createEntry(
        a.Id,
        'DEBIT',
        100.50,
        'BRL',
        Date.today(),
        null,
        null,
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
}
