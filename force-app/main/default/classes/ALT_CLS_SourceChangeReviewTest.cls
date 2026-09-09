/** @description Regression tests for immutable source evidence and terminal replay. */
@IsTest
private class ALT_CLS_SourceChangeReviewTest {
  private static User reviewer() {
    Profile standard = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Standard User'
      LIMIT 1
    ];
    User user = new User(
      ProfileId = standard.Id,
      Username = 'source-review-' + System.now().getTime() + '@example.test',
      Email = 'source-review@example.test',
      LastName = 'Source reviewer',
      Alias = 'srcrev',
      TimeZoneSidKey = 'America/Sao_Paulo',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    insert user;
    PermissionSet queue = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'AXF_PS_ReviewQueue'
      LIMIT 1
    ];
    insert new PermissionSetAssignment(
      AssigneeId = user.Id,
      PermissionSetId = queue.Id
    );
    return user;
  }

  @IsTest
  static void shouldHideSharedReviewWhenSourcePermissionIsMissing() {
    User user = reviewer();
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Id bankId = bank().Id;
      AXF_OBJ_BankAccountTransaction__c source = fact(bankId, 'denied', 10);
      insert source;
      new ALT_CLS_SourceChangeReview()
        .reconcile(new List<SObject>{ fact(bankId, 'denied', 12) });
      AXF_OBJ_ReviewItem__c item = [
        SELECT Id
        FROM AXF_OBJ_ReviewItem__c
        LIMIT 1
      ];
      insert new AXF_OBJ_ReviewItem__Share(
        ParentId = item.Id,
        UserOrGroupId = user.Id,
        AccessLevel = 'Read',
        RowCause = Schema.AXF_OBJ_ReviewItem__Share.RowCause.Manual
      );
      System.runAs(user) {
        Test.startTest();
        ALT_CLS_ReviewQueueService.ReviewViewDTO view = new ALT_CLS_ReviewQueueService()
          .open(item.Id);
        List<ALT_CLS_ReviewQueueService.ReviewViewDTO> visible = new ALT_CLS_ReviewQueueService()
          .listOpen();
        Test.stopTest();
        Assert.isNull(view, 'Sharing the review does not grant source access.');
        Assert.areEqual(
          0,
          visible.size(),
          'No existence or evidence leaks through listing.'
        );
      }
    }
  }

  @IsTest
  static void shouldAllowStandardReviewerWithReferencedAccountAccess() {
    User user = reviewer();
    System.runAs(user) {
      Account account = new Account(Name = 'Reviewer owned account');
      insert account;
      ALT_CLS_ReviewQueueService.CreateInputDTO input = new ALT_CLS_ReviewQueueService.CreateInputDTO();
      input.type = 'HOLDER_CONFIRMATION';
      input.reviewKey = 'standard-review';
      input.accountId = account.Id;
      Test.startTest();
      ALT_CLS_ReviewQueueService.ResultDTO created = new ALT_CLS_ReviewQueueService()
        .createItem(input);
      ALT_CLS_ReviewQueueService.ReviewViewDTO view = new ALT_CLS_ReviewQueueService()
        .open(created.reviewItemId);
      Test.stopTest();
      Assert.isTrue(
        created.success,
        'Current CRUD/FLS and record access authorize creation.'
      );
      Assert.areEqual(
        0,
        view.version,
        'Version is available for a subsequent decision.'
      );
    }
  }

  private static AXF_OBJ_BankAccount__c bank() {
    AXF_CLS_PluggyTestData.grantIntegrationAccess();
    AXF_OBJ_PluggyConnection__c connection = AXF_CLS_PluggyTestData.connection(
      'review-item'
    );
    return AXF_CLS_PluggyTestData.bankAccount(
      connection.Id,
      'review-bank',
      true
    );
  }

  @IsTest
  static void shouldRejectWrongParentWithoutPoisoningTheValidRow() {
    Id bankId = bank().Id;
    Id connectionId = [SELECT Id FROM AXF_OBJ_PluggyConnection__c LIMIT 1].Id;
    Id unrelated = AXF_CLS_PluggyTestData.bankAccount(
        connectionId,
        'unrelated-bank',
        true
      )
      .Id;
    AXF_OBJ_BankAccountTransaction__c source = fact(bankId, 'lineage', 10);
    insert source;
    ALT_CLS_ReviewQueueService.CreateInputDTO input = new ALT_CLS_ReviewQueueService.CreateInputDTO();
    input.type = 'SOURCE_CHANGE';
    input.reviewKey = 'lineage-review';
    input.bankAccountTransactionId = source.Id;
    input.bankAccountId = unrelated;
    input.evidenceRef = 'lineage-ref';
    input.observedAt = System.now();
    ALT_CLS_ReviewQueueService.CreateInputDTO valid = (ALT_CLS_ReviewQueueService.CreateInputDTO) JSON.deserialize(
      JSON.serialize(input),
      ALT_CLS_ReviewQueueService.CreateInputDTO.class
    );
    valid.bankAccountId = bankId;
    valid.reviewKey = 'valid-lineage-review';
    Test.startTest();
    List<ALT_CLS_ReviewQueueService.ResultDTO> results = new ALT_CLS_ReviewQueueService()
      .createItems(
        new List<ALT_CLS_ReviewQueueService.CreateInputDTO>{ valid, input }
      );
    Test.stopTest();
    Assert.isTrue(
      results[0].success,
      'Another row with incorrect lineage cannot hide valid evidence.'
    );
    Assert.isFalse(
      results[1].success,
      'Accessible records must still have the actual source relationship.'
    );
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM AXF_OBJ_ReviewItem__c],
      'Only the valid row publishes evidence.'
    );
  }

  @IsTest
  static void shouldBlockDirectReviewInsertion() {
    Account account = new Account(Name = 'Direct insert');
    insert account;
    AXF_OBJ_ReviewItem__c item = new AXF_OBJ_ReviewItem__c(
      AXF_RVI_PKL_Type__c = 'HOLDER_CONFIRMATION',
      AXF_RVI_PKL_State__c = 'OPEN',
      AXF_RVI_EXI_ReviewKey__c = 'direct-insert',
      AXF_RVI_LKP_Account__c = account.Id
    );
    Test.startTest();
    Database.SaveResult result = Database.insert(item, false);
    Test.stopTest();
    Assert.isFalse(
      result.isSuccess(),
      'API insertion cannot bypass producer authorization.'
    );
  }

  @IsTest
  static void shouldReplayTheSameTerminalDecision() {
    Id bankId = bank().Id;
    insert new List<AXF_OBJ_BankAccountTransaction__c>{
      fact(bankId, 'terminal-decision', 10)
    };
    new ALT_CLS_SourceChangeReview()
      .reconcile(new List<SObject>{ fact(bankId, 'terminal-decision', 12) });
    Id itemId = [SELECT Id FROM AXF_OBJ_ReviewItem__c LIMIT 1].Id;
    ALT_CLS_ReviewQueueService.ResolveInputDTO decision = new ALT_CLS_ReviewQueueService.ResolveInputDTO();
    decision.reviewItemId = itemId;
    decision.expectedVersion = 0;
    decision.decision = 'DISMISSED';
    decision.note = 'Evidence reviewed';
    Test.startTest();
    ALT_CLS_ReviewQueueService.ResultDTO first = new ALT_CLS_ReviewQueueService()
      .resolve(decision);
    ALT_CLS_ReviewQueueService.ResultDTO replay = new ALT_CLS_ReviewQueueService()
      .resolve(decision);
    decision.note = 'Different request';
    ALT_CLS_ReviewQueueService.ResultDTO conflict = new ALT_CLS_ReviewQueueService()
      .resolve(decision);
    Test.stopTest();
    Assert.isTrue(first.success, 'Initial decision succeeds.');
    Assert.isTrue(
      replay.success,
      'Same decision payload and original version replay safely.'
    );
    Assert.isFalse(conflict.success, 'Different terminal payload conflicts.');
    Assert.areEqual(
      1,
      [
        SELECT AXF_RVI_NUM_Version__c
        FROM AXF_OBJ_ReviewItem__c
        WHERE Id = :itemId
      ]
      .AXF_RVI_NUM_Version__c,
      'Replay never increments the version.'
    );
  }

  @IsTest
  static void shouldReviewBankAndCardChangesWithoutUpdatingEither() {
    Id bankId = bank().Id;
    Id connectionId = [SELECT Id FROM AXF_OBJ_PluggyConnection__c LIMIT 1].Id;
    Id cardId = AXF_CLS_PluggyTestData.creditCard(
        connectionId,
        'review-card',
        true
      )
      .Id;
    AXF_OBJ_BankAccountTransaction__c bankFact = fact(bankId, 'mixed-bank', 10);
    AXF_OBJ_CreditCardTransaction__c cardFact = new AXF_OBJ_CreditCardTransaction__c(
      AXF_CCT_MDR_CreditCard__c = cardId,
      AXF_CCT_EXI_SourceKey__c = 'mixed-card',
      AXF_CCT_PKL_Source__c = 'PLUGGY',
      AXF_CCT_NUM_Magnitude__c = 20,
      AXF_CCT_DAT_Date__c = Date.today(),
      AXF_CCT_TXT_Description__c = 'Card original',
      AXF_CCT_PKL_Direction__c = 'DEBIT',
      AXF_CCT_PKL_Status__c = 'PENDING',
      AXF_CCT_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_CCT_TXT_EvidenceRef__c = 'mixed-observation'
    );
    insert bankFact;
    insert cardFact;
    AXF_OBJ_CreditCardTransaction__c proposed = cardFact.clone(
      false,
      true,
      false,
      false
    );
    proposed.AXF_CCT_PKL_Status__c = 'POSTED';
    Test.startTest();
    Map<String, Object> bankResult = new ALT_CLS_SourceChangeReview()
      .reconcile(new List<SObject>{ fact(bankId, 'mixed-bank', 11) });
    Map<String, Object> cardResult = new ALT_CLS_SourceChangeReview()
      .reconcile(new List<SObject>{ proposed });
    Test.stopTest();
    Assert.areEqual(0, bankResult.get('bad'), 'Bank evidence accepted.');
    Assert.areEqual(0, cardResult.get('bad'), 'Card evidence accepted.');
    Assert.areEqual(
      2,
      [SELECT COUNT() FROM AXF_OBJ_ReviewItem__c],
      'Both source types produce reviews.'
    );
    Assert.areEqual(
      'PENDING',
      [
        SELECT AXF_CCT_PKL_Status__c
        FROM AXF_OBJ_CreditCardTransaction__c
        WHERE Id = :cardFact.Id
      ]
      .AXF_CCT_PKL_Status__c,
      'Published card status remains immutable.'
    );
  }

  @IsTest
  static void shouldKeepLocalFactForConfirmedDeletionReplay() {
    Id bankId = bank().Id;
    AXF_OBJ_BankAccountTransaction__c source = fact(bankId, 'deleted', 10);
    insert source;
    Test.startTest();
    Map<String, Object> first = new ALT_CLS_SourceChangeReview()
      .reviewDeleted(new List<SObject>{ source }, 'verified-delete');
    Map<String, Object> second = new ALT_CLS_SourceChangeReview()
      .reviewDeleted(new List<SObject>{ source }, 'verified-delete-retry');
    Test.stopTest();
    Assert.areEqual(
      0,
      first.get('bad'),
      'Confirmed deletion records evidence.'
    );
    Assert.areEqual(
      0,
      second.get('bad'),
      'Deletion replay succeeds idempotently.'
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AXF_OBJ_BankAccountTransaction__c
        WHERE Id = :source.Id
      ],
      'Provider deletion never removes the local fact.'
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AXF_OBJ_ReviewItem__c
        WHERE AXF_RVI_PKL_Type__c = 'SOURCE_DELETE'
      ],
      'Only one deletion review survives replay.'
    );
  }

  private static AXF_OBJ_BankAccountTransaction__c fact(
    Id bankId,
    String key,
    Decimal amount
  ) {
    return new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_MDR_BankAccount__c = bankId,
      AXF_BAT_EXI_SourceKey__c = key,
      AXF_BAT_PKL_Source__c = 'PLUGGY',
      AXF_BAT_NUM_Magnitude__c = amount,
      AXF_BAT_DAT_Date__c = Date.today(),
      AXF_BAT_TXT_Description__c = 'Original',
      AXF_BAT_TXT_NormalizedDescription__c = 'KEEP NORMALIZATION',
      AXF_BAT_PKL_Direction__c = 'DEBIT',
      AXF_BAT_PKL_Status__c = 'POSTED',
      AXF_BAT_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BAT_TXT_EvidenceRef__c = 'observation-1'
    );
  }

  @IsTest
  static void shouldPreserve251FactsAndDeduplicateChanges() {
    Id bankId = bank().Id;
    List<SObject> original = new List<SObject>();
    List<SObject> changed = new List<SObject>();
    for (Integer i = 0; i < 251; i++) {
      original.add(fact(bankId, 'bulk-' + i, 10));
      changed.add(fact(bankId, 'bulk-' + i, 12));
    }
    insert original;
    Test.startTest();
    Map<String, Object> result = new ALT_CLS_SourceChangeReview()
      .reconcile(changed);
    Map<String, Object> replay = new ALT_CLS_SourceChangeReview()
      .reconcile(changed);
    Test.stopTest();
    Assert.areEqual(
      0,
      result.get('bad'),
      'Every material change has durable evidence.'
    );
    Assert.areEqual(
      0,
      replay.get('bad'),
      'Replaying the same evidence succeeds.'
    );
    Assert.areEqual(
      251,
      [SELECT COUNT() FROM AXF_OBJ_ReviewItem__c],
      'Exactly one review per delta.'
    );
    Assert.areEqual(
      251,
      [
        SELECT COUNT()
        FROM AXF_OBJ_BankAccountTransaction__c
        WHERE
          AXF_BAT_NUM_Magnitude__c = 10
          AND AXF_BAT_TXT_NormalizedDescription__c = 'KEEP NORMALIZATION'
      ],
      'Original values and normalization survive.'
    );
  }

  @IsTest
  static void shouldSkipIdenticalReplay() {
    Id bankId = bank().Id;
    insert new List<AXF_OBJ_BankAccountTransaction__c>{
      fact(bankId, 'replay', 10)
    };
    Test.startTest();
    Map<String, Object> result = new ALT_CLS_SourceChangeReview()
      .reconcile(new List<SObject>{ fact(bankId, 'replay', 10) });
    Test.stopTest();
    Assert.areEqual(0, result.get('ok'), 'Replay issues no fact write.');
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM AXF_OBJ_ReviewItem__c],
      'Identical values produce no review.'
    );
  }

  @IsTest
  static void shouldRetainDismissedEvidenceAndTerminalKey() {
    Id bankId = bank().Id;
    insert new List<AXF_OBJ_BankAccountTransaction__c>{
      fact(bankId, 'dismiss', 10)
    };
    new ALT_CLS_SourceChangeReview()
      .reconcile(new List<SObject>{ fact(bankId, 'dismiss', 12) });
    AXF_OBJ_ReviewItem__c item = [SELECT Id FROM AXF_OBJ_ReviewItem__c LIMIT 1];
    ALT_CLS_ReviewQueueService.ResolveInputDTO decision = new ALT_CLS_ReviewQueueService.ResolveInputDTO();
    decision.reviewItemId = item.Id;
    decision.note = 'Reviewed with source evidence';
    decision.expectedVersion = 0;
    decision.decision = 'DISMISSED';
    Test.startTest();
    ALT_CLS_ReviewQueueService.ResultDTO result = new ALT_CLS_ReviewQueueService()
      .resolve(decision);
    Map<String, Object> replay = new ALT_CLS_SourceChangeReview()
      .reconcile(new List<SObject>{ fact(bankId, 'dismiss', 12) });
    Test.stopTest();
    Assert.isTrue(result.success, 'Dismissal records the decision.');
    Assert.areEqual(
      0,
      replay.get('bad'),
      'Terminal replay remains idempotent.'
    );
    item = [
      SELECT
        AXF_RVI_NUM_PriorAmount__c,
        AXF_RVI_NUM_ProposedAmount__c,
        AXF_RVI_PKL_State__c
      FROM AXF_OBJ_ReviewItem__c
      WHERE Id = :item.Id
    ];
    Assert.areEqual(
      10,
      item.AXF_RVI_NUM_PriorAmount__c,
      'Retain original evidence.'
    );
    Assert.areEqual(
      12,
      item.AXF_RVI_NUM_ProposedAmount__c,
      'Retain proposed evidence.'
    );
    Assert.areEqual(
      'DISMISSED',
      item.AXF_RVI_PKL_State__c,
      'Replay never reopens a terminal item.'
    );
  }

  @IsTest
  static void shouldRejectSourceResolutionWithoutFinancialHandler() {
    Id bankId = bank().Id;
    insert new List<AXF_OBJ_BankAccountTransaction__c>{
      fact(bankId, 'unavailable', 10)
    };
    new ALT_CLS_SourceChangeReview()
      .reconcile(new List<SObject>{ fact(bankId, 'unavailable', 12) });
    AXF_OBJ_ReviewItem__c item = [SELECT Id FROM AXF_OBJ_ReviewItem__c LIMIT 1];
    ALT_CLS_ReviewQueueService.ResolveInputDTO decision = new ALT_CLS_ReviewQueueService.ResolveInputDTO();
    decision.reviewItemId = item.Id;
    decision.note = 'Reviewed with source evidence';
    decision.expectedVersion = 0;
    decision.decision = 'RESOLVED';
    Test.startTest();
    ALT_CLS_ReviewQueueService.ResultDTO result = new ALT_CLS_ReviewQueueService()
      .resolve(decision);
    Test.stopTest();
    Assert.isFalse(
      result.success,
      'Producer cannot apply a financial decision.'
    );
    Assert.isTrue(
      result.message.startsWith('SOURCE_RESOLUTION_UNAVAILABLE'),
      'Expose a stable reason.'
    );
    Assert.areEqual(
      'OPEN',
      [
        SELECT AXF_RVI_PKL_State__c
        FROM AXF_OBJ_ReviewItem__c
        WHERE Id = :item.Id
      ]
      .AXF_RVI_PKL_State__c,
      'Blocked decision preserves OPEN state.'
    );
  }

  @IsTest
  static void shouldBlockDirectEvidenceEdit() {
    Id bankId = bank().Id;
    insert new List<AXF_OBJ_BankAccountTransaction__c>{
      fact(bankId, 'protected', 10)
    };
    new ALT_CLS_SourceChangeReview()
      .reconcile(new List<SObject>{ fact(bankId, 'protected', 12) });
    AXF_OBJ_ReviewItem__c item = [SELECT Id FROM AXF_OBJ_ReviewItem__c LIMIT 1];
    item.AXF_RVI_NUM_ProposedAmount__c = 99;
    Test.startTest();
    Database.SaveResult result = Database.update(item, false);
    Test.stopTest();
    Assert.isFalse(result.isSuccess(), 'Direct evidence tampering is denied.');
  }
}
