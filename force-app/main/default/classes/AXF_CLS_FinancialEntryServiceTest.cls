/**
 * @description AXF-19. Authority (must be an authorized context), validation, idempotent
 * replay (same clientRequestId + same payload), conflict (same key + different payload), and
 * funding-source visibility (AVAILABLE only, G5-5).
 */
@IsTest
private class AXF_CLS_FinancialEntryServiceTest {
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

  static Id rt(String dev) {
    return Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
      .getRecordTypeInfosByDeveloperName()
      .get(dev)
      .getRecordTypeId();
  }

  static Account holder() {
    Account a = new Account(
      Name = 'Titular Teste',
      RecordTypeId = rt('AXF_Business')
    );
    insert a;
    return a;
  }

  static AXF_OBJ_BankAccount__c bankAccount(Id holderId, String availability) {
    AXF_OBJ_BankAccount__c ba = new AXF_OBJ_BankAccount__c(
      AXF_BA_LKP_Account__c = holderId,
      AXF_BA_PKL_AvailabilityState__c = availability,
      AXF_BA_TXT_InstitutionName__c = 'Banco Teste',
      AXF_BA_TXT_NumberMasked__c = '****1234'
    );
    insert ba;
    return ba;
  }

  static AXF_CLS_FinancialEntryService.EntryInput input(
    Id accountId,
    String clientRequestId
  ) {
    AXF_CLS_FinancialEntryService.EntryInput i = new AXF_CLS_FinancialEntryService.EntryInput();
    i.accountId = accountId;
    i.direction = 'DEBIT';
    i.magnitude = 100.50;
    i.currencyIsoCode = 'BRL';
    i.purchaseDate = Date.today();
    i.clientRequestId = clientRequestId;
    return i;
  }

  @IsTest
  static void deniesWhenNoAccountIsProvided() {
    // Authorized-context membership itself (AXF-3, cross-user sharing) is covered by
    // AXF_CLS_AuthorizedContextServiceTest; this asserts the service's own guard never
    // proceeds without a resolvable, authorized accountId.
    AXF_CLS_FinancialEntryService.EntryInput i = input(
      null,
      '11111111-1111-1111-1111-111111111111'
    );

    Test.startTest();
    AXF_CLS_FinancialEntryService.EntryResult r = AXF_CLS_FinancialEntryService.createEntry(
      i
    );
    Test.stopTest();

    System.assertEquals('FORBIDDEN', r.outcome);
    System.assertEquals(
      0,
      [SELECT COUNT() FROM AXF_OBJ_FinancialTransaction__c],
      'a denied attempt never persists a partial record'
    );
  }

  @IsTest
  static void rejectsInvalidMagnitudeWithoutTouchingTheDatabase() {
    Account a = holder();
    AXF_CLS_FinancialEntryService.EntryInput i = input(
      a.Id,
      '22222222-2222-2222-2222-222222222222'
    );
    i.magnitude = 0;

    Test.startTest();
    AXF_CLS_FinancialEntryService.EntryResult r = AXF_CLS_FinancialEntryService.createEntry(
      i
    );
    Test.stopTest();

    System.assertEquals('INVALID', r.outcome);
    System.assertEquals(
      0,
      [SELECT COUNT() FROM AXF_OBJ_FinancialTransaction__c]
    );
  }

  @IsTest
  static void rejectsBothBankAccountAndCreditCard() {
    Account a = holder();
    AXF_OBJ_BankAccount__c ba = bankAccount(a.Id, 'AVAILABLE');
    AXF_CLS_FinancialEntryService.EntryInput i = input(
      a.Id,
      '33333333-3333-3333-3333-333333333333'
    );
    i.bankAccountId = ba.Id;
    i.creditCardId = ba.Id; // any non-null Id; XOR check happens before FK resolution

    Test.startTest();
    AXF_CLS_FinancialEntryService.EntryResult r = AXF_CLS_FinancialEntryService.createEntry(
      i
    );
    Test.stopTest();

    System.assertEquals('INVALID', r.outcome);
  }

  @IsTest
  static void rejectsCustodyBankAccountAsAFundingSource() {
    Account a = holder();
    AXF_OBJ_BankAccount__c custody = bankAccount(a.Id, 'CUSTODY');
    AXF_CLS_FinancialEntryService.EntryInput i = input(
      a.Id,
      '44444444-4444-4444-4444-444444444444'
    );
    i.bankAccountId = custody.Id;

    Test.startTest();
    AXF_CLS_FinancialEntryService.EntryResult r = AXF_CLS_FinancialEntryService.createEntry(
      i
    );
    Test.stopTest();

    System.assertEquals('INVALID', r.outcome);
  }

  @IsTest
  static void createsAConfirmedEntryForAnAuthorizedAccount() {
    Account a = holder();
    AXF_CLS_FinancialEntryService.EntryInput i = input(
      a.Id,
      '55555555-5555-5555-5555-555555555555'
    );

    Test.startTest();
    AXF_CLS_FinancialEntryService.EntryResult r = AXF_CLS_FinancialEntryService.createEntry(
      i
    );
    Test.stopTest();

    System.assertEquals('CREATED', r.outcome);
    AXF_OBJ_FinancialTransaction__c ftx = [
      SELECT
        AXF_FTX_PKL_Status__c,
        AXF_FTX_CHK_IsEstimated__c,
        AXF_FTX_PKL_Direction__c,
        AXF_FTX_NUM_Magnitude__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE Id = :r.financialTransactionId
    ];
    System.assertEquals('CONFIRMED', ftx.AXF_FTX_PKL_Status__c);
    System.assertEquals(false, ftx.AXF_FTX_CHK_IsEstimated__c);
    System.assertEquals('DEBIT', ftx.AXF_FTX_PKL_Direction__c);
    System.assertEquals(100.50, ftx.AXF_FTX_NUM_Magnitude__c);
  }

  @IsTest
  static void replayWithSamePayloadIsIdempotent() {
    Account a = holder();
    String key = '66666666-6666-6666-6666-666666666666';

    Test.startTest();
    AXF_CLS_FinancialEntryService.EntryResult first = AXF_CLS_FinancialEntryService.createEntry(
      input(a.Id, key)
    );
    AXF_CLS_FinancialEntryService.EntryResult replay = AXF_CLS_FinancialEntryService.createEntry(
      input(a.Id, key)
    );
    Test.stopTest();

    System.assertEquals('CREATED', first.outcome);
    System.assertEquals('ALREADY', replay.outcome);
    System.assertEquals(
      first.financialTransactionId,
      replay.financialTransactionId
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM AXF_OBJ_FinancialTransaction__c],
      'replay never duplicates'
    );
  }

  @IsTest
  static void sameKeyDifferentPayloadIsConflict() {
    Account a = holder();
    String key = '77777777-7777-7777-7777-777777777777';

    Test.startTest();
    AXF_CLS_FinancialEntryService.createEntry(input(a.Id, key));
    AXF_CLS_FinancialEntryService.EntryInput divergent = input(a.Id, key);
    divergent.magnitude = 999;
    AXF_CLS_FinancialEntryService.EntryResult r = AXF_CLS_FinancialEntryService.createEntry(
      divergent
    );
    Test.stopTest();

    System.assertEquals('CONFLICT', r.outcome);
    System.assertEquals(
      1,
      [SELECT COUNT() FROM AXF_OBJ_FinancialTransaction__c],
      'a conflicting replay never overwrites or duplicates'
    );
  }

  @IsTest
  static void fundingSourcesListsOnlyAvailableOnes() {
    Account a = holder();
    bankAccount(a.Id, 'AVAILABLE');
    bankAccount(a.Id, 'CUSTODY');

    Test.startTest();
    List<AXF_CLS_FinancialEntryService.FundingSourceOption> options = AXF_CLS_FinancialEntryService.getFundingSources(
      a.Id
    );
    Test.stopTest();

    System.assertEquals(1, options.size());
    System.assertEquals('BANK_ACCOUNT', options[0].kind);
  }
}
