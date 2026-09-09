/** @description AXF-17 opt-in, replay, administrative resolution and rollback contracts. */
@IsTest
private class ALT_CLS_ManualReviewServiceTest {
  private static void grants() {
    List<PermissionSetAssignment> grants = new List<PermissionSetAssignment>();
    for (PermissionSet p : [
      SELECT Id
      FROM PermissionSet
      WHERE
        Name IN (
          'AXF_PS_FinancialEntry',
          'AXF_PS_GestorFinanceiro',
          'AXF_PS_ReviewQueue'
        )
    ])
      grants.add(
        new PermissionSetAssignment(
          AssigneeId = UserInfo.getUserId(),
          PermissionSetId = p.Id
        )
      );
    insert grants;
  }
  private static AXF_CLS_FinancialEntryService.EntryInput entry(Boolean track) {
    grants();
    Account holder = new Account(
      Name = 'Manual review holder',
      RecordTypeId = Account.SObjectType.getDescribe()
        .getRecordTypeInfosByDeveloperName()
        .get('AXF_Business')
        .getRecordTypeId()
    );
    insert holder;
    AXF_CLS_FinancialEntryService.EntryInput input = new AXF_CLS_FinancialEntryService.EntryInput();
    input.accountId = holder.Id;
    input.direction = 'DEBIT';
    input.magnitude = 100;
    input.currencyIsoCode = 'BRL';
    input.purchaseDate = Date.today();
    input.clientRequestId = '11111111-1111-4111-8111-111111111111';
    input.trackConfirmation = track;
    return input;
  }
  @IsTest
  static void controllerRejectsUnavailableItem() {
    entry(false);
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Boolean rejected = false;
      Test.startTest();
      try {
        AXF_CLS_CTRL_ManualReview.confirm(null, 0, 'Checked receipt');
      } catch (AuraHandledException expected) {
        rejected = true;
      }
      Test.stopTest();
      Assert.isTrue(rejected, 'Unavailable items are rejected at the UI boundary');
      Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_ReviewItem__c], 'No evidence is fabricated');
    }
  }
  @IsTest
  static void cashWithoutOptInHasNoReview() {
    AXF_CLS_FinancialEntryService.EntryInput input = entry(false);
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Test.startTest();
      AXF_CLS_FinancialEntryService.EntryResult result = AXF_CLS_FinancialEntryService.createEntry(
        input
      );
      Test.stopTest();
      Assert.areEqual(
        'CREATED',
        result.outcome,
        'Cash is legitimate without a funding account'
      );
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM AXF_OBJ_ReviewItem__c],
        'No fabricated pendency'
      );
    }
  }
  @IsTest
  static void reviewPermissionFailureRollsBackEntry() {
    User actor=new User(Alias='axf17',Email='axf17@example.invalid',EmailEncodingKey='UTF-8',LastName='Manual review tester',LanguageLocaleKey='en_US',LocaleSidKey='en_US',TimeZoneSidKey='America/Sao_Paulo',ProfileId=[SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1].Id,Username='axf17.'+System.now().getTime()+'@example.invalid');
    insert actor;
    List<PermissionSetAssignment> permissions=new List<PermissionSetAssignment>();
    for(PermissionSet permission:[SELECT Id FROM PermissionSet WHERE Name IN ('AXF_PS_FinancialEntry','AXF_PS_GestorFinanceiro')]) { permissions.add(new PermissionSetAssignment(AssigneeId=actor.Id,PermissionSetId=permission.Id)); }
    insert permissions;
    System.runAs(actor) {
      Account holder=new Account(Name='No review access',RecordTypeId=Account.SObjectType.getDescribe().getRecordTypeInfosByDeveloperName().get('AXF_Business').getRecordTypeId());insert holder;
      AXF_CLS_FinancialEntryService.EntryInput input=new AXF_CLS_FinancialEntryService.EntryInput();
      input.accountId=holder.Id;input.direction='DEBIT';input.magnitude=100;input.currencyIsoCode='BRL';input.purchaseDate=Date.today();input.clientRequestId='33333333-3333-4333-8333-333333333333';input.trackConfirmation=true;
      Test.startTest();
      Assert.areEqual('INVALID',AXF_CLS_FinancialEntryService.createEntry(input).outcome,'Financial creation fails atomically when review evidence cannot be written');
      Test.stopTest();
      Assert.areEqual(0,[SELECT COUNT() FROM AXF_OBJ_FinancialTransaction__c]);
      Assert.areEqual(0,[SELECT COUNT() FROM AXF_OBJ_ReviewItem__c]);
    }
  }
  @IsTest
  static void confirmationDoesNotChangeFinancialEntry() {
    AXF_CLS_FinancialEntryService.EntryInput input = entry(true);
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Test.startTest();
      AXF_CLS_FinancialEntryService.EntryResult result = AXF_CLS_FinancialEntryService.createEntry(
        input
      );
      ALT_CLS_ManualReviewService service = new ALT_CLS_ManualReviewService();
      List<ALT_CLS_ReviewQueueService.ReviewViewDTO> items = service.listPending();
      Assert.isNotNull(
        AXF_CLS_CTRL_ManualReview.listPending(),
        'Controller serializes authorized rows'
      );
      Assert.areEqual(1, items.size(), 'Opt-in creates one item');
      Assert.isTrue(
        ((ALT_CLS_ReviewQueueService.ResultDTO) JSON.deserialize(
            AXF_CLS_CTRL_ManualReview.confirm(
              items[0].reviewItemId,
              0,
              'Checked receipt'
            ),
            ALT_CLS_ReviewQueueService.ResultDTO.class
          ))
          .success,
        'Administrative confirmation succeeds'
      );
      Assert.isTrue(
        service.confirm(items[0].reviewItemId, 0, 'Checked receipt').success,
        'Lost response replays once'
      );
      Assert.areEqual(
        'ALREADY',
        AXF_CLS_FinancialEntryService.createEntry(input).outcome,
        'Creation replay remains stable'
      );
      Test.stopTest();
      Assert.areEqual(
        0,
        service.listPending().size(),
        'Replay never reopens item'
      );
      AXF_OBJ_FinancialTransaction__c f = [
        SELECT AXF_FTX_NUM_Magnitude__c, AXF_FTX_PKL_Status__c
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE Id = :result.financialTransactionId
      ];
      Assert.areEqual(100, f.AXF_FTX_NUM_Magnitude__c, 'Amount preserved');
      Assert.areEqual(
        'CONFIRMED',
        f.AXF_FTX_PKL_Status__c,
        'Not financially settled'
      );
    }
  }
  @IsTest
  static void changedOptInConflicts() {
    AXF_CLS_FinancialEntryService.EntryInput input = entry(false);
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Test.startTest();
      AXF_CLS_FinancialEntryService.createEntry(input);
      input.trackConfirmation = true;
      Assert.areEqual(
        'CONFLICT',
        AXF_CLS_FinancialEntryService.createEntry(input).outcome,
        'Opt-in belongs to operation payload'
      );
      Test.stopTest();
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM AXF_OBJ_ReviewItem__c],
        'Conflict creates no item'
      );
    }
  }
  @IsTest
  static void dueDateChangeConflicts() {
    AXF_CLS_FinancialEntryService.EntryInput input = entry(false);
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Test.startTest();
      AXF_CLS_FinancialEntryService.createEntry(input);
      input.dueDate = Date.today().addDays(1);
      Assert.areEqual(
        'CONFLICT',
        AXF_CLS_FinancialEntryService.createEntry(input).outcome,
        'Due date belongs to operation payload'
      );
      Test.stopTest();
    }
  }
  @IsTest
  static void distinctEqualEntriesRemainDistinct() {
    AXF_CLS_FinancialEntryService.EntryInput input = entry(true);
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Test.startTest();
      AXF_CLS_FinancialEntryService.createEntry(input);
      input.clientRequestId = '22222222-2222-4222-8222-222222222222';
      Assert.areEqual(
        'CREATED',
        AXF_CLS_FinancialEntryService.createEntry(input).outcome,
        'Similar financial values do not imply replay'
      );
      Test.stopTest();
      Assert.areEqual(
        2,
        [SELECT COUNT() FROM AXF_OBJ_ReviewItem__c],
        'Each independent intent retains its item'
      );
    }
  }
}
