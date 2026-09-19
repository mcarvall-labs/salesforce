/**
 * @description AXF-32: suggestion is idempotent by NeutralityKey, confirmation neutralizes the
 * principal only after a human decision (never automatically), an incompatible/missing leg lands
 * on UNILATERAL without neutralizing, and reversal always appends a new REVERSED row pointing to
 * the original -- nothing confirmed is ever edited or deleted.
 */
@IsTest(isParallel=false)
// API 62: AXON_DEV enforces FLS on plain test DML under runAs from API 67 onwards.
private class ALT_CLS_InternalTransferServiceTest {
  private static User byAlias(String alias) {
    return [SELECT Id FROM User WHERE Alias = :alias LIMIT 1];
  }

  @TestSetup
  static void setup() {
    Id profileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
    .Id;
    List<User> users = new List<User>();
    for (String alias : new List<String>{ 'axf32g', 'axf32p', 'axf32n' }) {
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
          'AXF_PS_ReviewQueue',
          'AXF_PS_Participante'
        )
    ]) {
      permissionSets.put(permission.Name, permission.Id);
    }
    Assert.areEqual(3, permissionSets.size(), 'permission sets must exist');
    List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (Integer i = 0; i < 2; i++) {
      for (
        String name : new List<String>{
          'AXF_PS_GestorFinanceiro',
          'AXF_PS_ReviewQueue'
        }
      ) {
        assignments.add(
          new PermissionSetAssignment(
            AssigneeId = users[i].Id,
            PermissionSetId = permissionSets.get(name)
          )
        );
      }
    }
    assignments.add(
      new PermissionSetAssignment(
        AssigneeId = users[2].Id,
        PermissionSetId = permissionSets.get('AXF_PS_Participante')
      )
    );
    insert assignments;
  }

  private class Fixture {
    public Account holder;
    public AXF_OBJ_BankAccount__c bankA;
    public AXF_OBJ_BankAccount__c bankB;
    public AXF_OBJ_BankAccountTransaction__c debit;
    public AXF_OBJ_BankAccountTransaction__c credit;
  }

  /** Holder with two available banks and one exact opposite pair (100 BRL) between them. */
  private static Fixture fixture(String key, Decimal amount) {
    Fixture f = new Fixture();
    f.holder = new Account(
      Name = 'Holder 32 ' + key,
      RecordTypeId = Account.SObjectType.getDescribe()
        .getRecordTypeInfosByDeveloperName()
        .get('AXF_Business')
        .getRecordTypeId()
    );
    insert f.holder;
    f.bankA = new AXF_OBJ_BankAccount__c(
      AXF_BA_LKP_Account__c = f.holder.Id,
      AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_BA_TXT_CurrencyIsoCode__c = 'BRL'
    );
    f.bankB = new AXF_OBJ_BankAccount__c(
      AXF_BA_LKP_Account__c = f.holder.Id,
      AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_BA_TXT_CurrencyIsoCode__c = 'BRL'
    );
    insert new List<AXF_OBJ_BankAccount__c>{ f.bankA, f.bankB };
    f.debit = new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_MDR_BankAccount__c = f.bankA.Id,
      AXF_BAT_NUM_Magnitude__c = amount,
      AXF_BAT_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BAT_PKL_Direction__c = 'DEBIT',
      AXF_BAT_DAT_Date__c = Date.today(),
      AXF_BAT_TXT_Description__c = 'Transfer out ' + key,
      AXF_BAT_EXI_SourceKey__c = 'axf32-debit-' + key,
      AXF_BAT_PKL_Source__c = 'CSV',
      AXF_BAT_PKL_Status__c = 'POSTED',
      AXF_BAT_NUM_Version__c = 0
    );
    f.credit = new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_MDR_BankAccount__c = f.bankB.Id,
      AXF_BAT_NUM_Magnitude__c = amount,
      AXF_BAT_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BAT_PKL_Direction__c = 'CREDIT',
      AXF_BAT_DAT_Date__c = Date.today(),
      AXF_BAT_TXT_Description__c = 'Transfer in ' + key,
      AXF_BAT_EXI_SourceKey__c = 'axf32-credit-' + key,
      AXF_BAT_PKL_Source__c = 'CSV',
      AXF_BAT_PKL_Status__c = 'POSTED',
      AXF_BAT_NUM_Version__c = 0
    );
    insert new List<AXF_OBJ_BankAccountTransaction__c>{ f.debit, f.credit };
    return f;
  }

  private static ALT_CLS_InternalTransferService.SuggestInput suggestInput(
    Fixture f
  ) {
    ALT_CLS_InternalTransferService.SuggestInput i = new ALT_CLS_InternalTransferService.SuggestInput();
    i.debitTransactionId = f.debit.Id;
    i.creditTransactionId = f.credit.Id;
    return i;
  }

  private static ALT_CLS_InternalTransferService.ConfirmInput confirmInput(
    Id transferId,
    Decimal version,
    String key
  ) {
    ALT_CLS_InternalTransferService.ConfirmInput i = new ALT_CLS_InternalTransferService.ConfirmInput();
    i.internalTransferId = transferId;
    i.expectedVersion = version;
    i.operationKey = 'axf32-' + key;
    return i;
  }

  private static ALT_CLS_InternalTransferService.ReverseInput reverseInput(
    Id transferId,
    Decimal version,
    String reason,
    String note,
    String key
  ) {
    ALT_CLS_InternalTransferService.ReverseInput i = new ALT_CLS_InternalTransferService.ReverseInput();
    i.internalTransferId = transferId;
    i.expectedVersion = version;
    i.reasonCode = reason;
    i.reasonNote = note;
    i.operationKey = 'axf32-' + key;
    return i;
  }

  @IsTest
  static void suggestIsIdempotentAndNeverLinksWithoutConfirmation() {
    System.runAs(byAlias('axf32g')) {
      Fixture f = fixture('suggest', 100);
      ALT_CLS_InternalTransferService service = new ALT_CLS_InternalTransferService();
      Test.startTest();
      Id first = service.suggest(suggestInput(f));
      Id replay = service.suggest(suggestInput(f));
      Test.stopTest();

      Assert.areEqual(first, replay, 'same pair never duplicates');
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM AXF_OBJ_InternalTransfer__c],
        'no duplicate ITR'
      );
      ALT_CLS_InternalTransferService.TransferView view = service.read(first);
      Assert.areEqual(
        'CANDIDATE',
        view.state,
        'never linked without human confirmation'
      );
      List<AXF_OBJ_ReviewItem__c> items = [
        SELECT
          AXF_RVI_PKL_Type__c,
          AXF_RVI_PKL_State__c,
          AXF_RVI_LKP_InternalTransfer__c
        FROM AXF_OBJ_ReviewItem__c
      ];
      Assert.areEqual(
        1,
        items.size(),
        'one review item, not duplicated by replay'
      );
      Assert.areEqual('TRANSFER_SUGGESTION', items[0].AXF_RVI_PKL_Type__c);
      Assert.areEqual('OPEN', items[0].AXF_RVI_PKL_State__c);
      Assert.areEqual(first, items[0].AXF_RVI_LKP_InternalTransfer__c);
    }
  }

  @IsTest
  static void confirmNeutralizesOnlyOnceAndReplaysAreIdempotent() {
    System.runAs(byAlias('axf32g')) {
      Fixture f = fixture('confirm', 150);
      ALT_CLS_InternalTransferService service = new ALT_CLS_InternalTransferService();
      Id transferId = service.suggest(suggestInput(f));

      Test.startTest();
      ALT_CLS_InternalTransferService.TransferView confirmed = service.confirm(
        confirmInput(transferId, 0, 'c1')
      );
      ALT_CLS_InternalTransferService.TransferView replayed = service.confirm(
        confirmInput(transferId, 0, 'c1')
      );
      // Same operationKey, different expectedVersion: the payload fingerprint diverges.
      ALT_CLS_InternalTransferService.ConfirmInput divergent = confirmInput(
        transferId,
        0,
        'c1'
      );
      divergent.expectedVersion = 99;
      String conflictOnDivergentVersion;
      try {
        service.confirm(divergent);
        Assert.fail('divergent operation must conflict');
      } catch (ALT_CLS_InternalTransferService.TransferException expected) {
        conflictOnDivergentVersion = expected.getMessage();
      }
      String alreadyDecidedOnDifferentKey;
      try {
        service.confirm(confirmInput(transferId, 1, 'c2'));
        Assert.fail(
          'a different operation key over an already-confirmed pair must fail'
        );
      } catch (ALT_CLS_InternalTransferService.TransferException expected) {
        alreadyDecidedOnDifferentKey = expected.getMessage();
      }
      Test.stopTest();

      Assert.isFalse(confirmed.replayed);
      Assert.areEqual('CONFIRMED', confirmed.state);
      Assert.isNotNull(confirmed.confirmedAt);
      Assert.areEqual(
        150,
        confirmed.debit.amount,
        'leg preserved as an independent fact'
      );
      Assert.areEqual(f.debit.Id, confirmed.debit.transactionId);
      Assert.areEqual(f.credit.Id, confirmed.credit.transactionId);
      Assert.isTrue(replayed.replayed);
      Assert.areEqual('CONFIRMED', replayed.state);
      Assert.areEqual('CONFLICT', conflictOnDivergentVersion);
      Assert.areEqual('ALREADY_DECIDED', alreadyDecidedOnDifferentKey);
      List<AXF_OBJ_BankAccountTransaction__c> facts = [
        SELECT Id, AXF_BAT_NUM_Magnitude__c
        FROM AXF_OBJ_BankAccountTransaction__c
        ORDER BY AXF_BAT_PKL_Direction__c
      ];
      Assert.areEqual(2, facts.size(), 'both legs remain independent facts');
      List<AXF_OBJ_ReviewItem__c> items = [
        SELECT AXF_RVI_PKL_State__c
        FROM AXF_OBJ_ReviewItem__c
      ];
      Assert.areEqual(
        'RESOLVED',
        items[0].AXF_RVI_PKL_State__c,
        'suggestion resolved on confirm'
      );
    }
  }

  @IsTest
  static void incompatibleLegLandsUnilateralAndNeverNeutralizes() {
    System.runAs(byAlias('axf32g')) {
      Fixture f = fixture('unilateral', 200);
      ALT_CLS_InternalTransferService service = new ALT_CLS_InternalTransferService();
      Id transferId = service.suggest(suggestInput(f));
      // The credit leg's value changes after the suggestion (e.g. a source correction).
      f.credit.AXF_BAT_NUM_Magnitude__c = 999;
      update f.credit;

      Test.startTest();
      ALT_CLS_InternalTransferService.TransferView result = service.confirm(
        confirmInput(transferId, 0, 'u1')
      );
      Test.stopTest();

      Assert.areEqual('UNILATERAL', result.state);
      Assert.isNull(result.confirmedAt, 'principal never neutralized');
      Assert.areEqual(
        'UNILATERAL',
        [
          SELECT AXF_ITR_PKL_State__c
          FROM AXF_OBJ_InternalTransfer__c
          WHERE Id = :transferId
        ]
        .AXF_ITR_PKL_State__c
      );
      Assert.areEqual(
        'OPEN',
        [SELECT AXF_RVI_PKL_State__c FROM AXF_OBJ_ReviewItem__c]
        .AXF_RVI_PKL_State__c,
        'review item stays revisable, not resolved, when confirm lands UNILATERAL'
      );
    }
  }

  @IsTest
  static void unilateralCorrectedLaterBecomesConfirmed() {
    System.runAs(byAlias('axf32g')) {
      Fixture f = fixture('u-then-c', 300);
      ALT_CLS_InternalTransferService service = new ALT_CLS_InternalTransferService();
      Id transferId = service.suggest(suggestInput(f));
      f.credit.AXF_BAT_NUM_Magnitude__c = 999;
      update f.credit;
      ALT_CLS_InternalTransferService.TransferView unilateral = service.confirm(
        confirmInput(transferId, 0, 'first-try')
      );
      Assert.areEqual('UNILATERAL', unilateral.state);

      Test.startTest();
      // The leg is corrected after the fact (e.g. the source re-syncs the right amount).
      f.credit.AXF_BAT_NUM_Magnitude__c = 300;
      update f.credit;
      ALT_CLS_InternalTransferService.TransferView corrected = service.confirm(
        confirmInput(transferId, unilateral.version, 'second-try')
      );
      Test.stopTest();

      Assert.areEqual('CONFIRMED', corrected.state);
      Assert.isNotNull(
        corrected.confirmedAt,
        'a corrected leg neutralizes the principal on the next confirm'
      );
      Assert.areEqual(
        'RESOLVED',
        [SELECT AXF_RVI_PKL_State__c FROM AXF_OBJ_ReviewItem__c]
        .AXF_RVI_PKL_State__c,
        'review item resolves once the pair actually confirms'
      );
    }
  }

  @IsTest
  static void legAlreadyLinkedGuardBlocksReuseAcrossStates() {
    System.runAs(byAlias('axf32g')) {
      ALT_CLS_InternalTransferService service = new ALT_CLS_InternalTransferService();

      Fixture candidateFixture = fixture('leg-candidate', 40);
      Id candidateId = service.suggest(suggestInput(candidateFixture));

      Fixture confirmedFixture = fixture('leg-confirmed', 50);
      Id confirmedId = service.suggest(suggestInput(confirmedFixture));
      service.confirm(confirmInput(confirmedId, 0, 'leg-confirmed-op'));

      Fixture unilateralFixture = fixture('leg-unilateral', 60);
      Id unilateralId = service.suggest(suggestInput(unilateralFixture));
      unilateralFixture.credit.AXF_BAT_NUM_Magnitude__c = 999;
      update unilateralFixture.credit;
      service.confirm(confirmInput(unilateralId, 0, 'leg-unilateral-op'));

      Map<String, Fixture> byState = new Map<String, Fixture>{
        'CANDIDATE' => candidateFixture,
        'CONFIRMED' => confirmedFixture,
        'UNILATERAL' => unilateralFixture
      };

      Test.startTest();
      for (String state : byState.keySet()) {
        Fixture linked = byState.get(state);
        // A fresh, otherwise-valid opposite leg on the same holder/amount as the linked debit.
        AXF_OBJ_BankAccountTransaction__c freshCredit = new AXF_OBJ_BankAccountTransaction__c(
          AXF_BAT_MDR_BankAccount__c = linked.bankB.Id,
          AXF_BAT_NUM_Magnitude__c = linked.debit.AXF_BAT_NUM_Magnitude__c,
          AXF_BAT_TXT_CurrencyIsoCode__c = 'BRL',
          AXF_BAT_PKL_Direction__c = 'CREDIT',
          AXF_BAT_DAT_Date__c = Date.today(),
          AXF_BAT_TXT_Description__c = 'Fresh credit ' + state,
          AXF_BAT_EXI_SourceKey__c = 'axf32-leg-fresh-' + state,
          AXF_BAT_PKL_Source__c = 'CSV',
          AXF_BAT_PKL_Status__c = 'POSTED',
          AXF_BAT_NUM_Version__c = 0
        );
        insert freshCredit;
        ALT_CLS_InternalTransferService.SuggestInput reuse = new ALT_CLS_InternalTransferService.SuggestInput();
        reuse.debitTransactionId = linked.debit.Id;
        reuse.creditTransactionId = freshCredit.Id;
        try {
          service.suggest(reuse);
          Assert.fail(
            'a leg already linked in ' + state + ' must block a new pair'
          );
        } catch (ALT_CLS_InternalTransferService.TransferException expected) {
          Assert.areEqual(
            'LEG_ALREADY_LINKED',
            expected.getMessage(),
            'state ' + state
          );
        }
      }
      Test.stopTest();
    }
  }

  @IsTest
  static void reverseAppendsCompensationAndNeverEditsTheConfirmedRow() {
    System.runAs(byAlias('axf32g')) {
      Fixture f = fixture('reverse', 250);
      ALT_CLS_InternalTransferService service = new ALT_CLS_InternalTransferService();
      Id transferId = service.suggest(suggestInput(f));
      service.confirm(confirmInput(transferId, 0, 'r-confirm'));

      Test.startTest();
      ALT_CLS_InternalTransferService.TransferView reversed = service.reverse(
        reverseInput(transferId, 1, 'WRONG_TARGET', '  wrong pair  ', 'r1')
      );
      ALT_CLS_InternalTransferService.TransferView replayed = service.reverse(
        reverseInput(transferId, 1, 'WRONG_TARGET', '  wrong pair  ', 'r1')
      );
      String alreadyReversed;
      try {
        service.reverse(
          reverseInput(transferId, 1, 'OTHER', null, 'different-key')
        );
        Assert.fail(
          'a different operation key over an already-reversed pair must fail'
        );
      } catch (ALT_CLS_InternalTransferService.TransferException expected) {
        alreadyReversed = expected.getMessage();
      }
      Test.stopTest();

      Assert.isFalse(reversed.replayed);
      Assert.areEqual('REVERSED', reversed.state);
      Assert.areEqual(transferId, reversed.originalTransferId);
      Assert.areEqual('WRONG_TARGET', reversed.reasonCode);
      Assert.areEqual('wrong pair', reversed.reasonNote, 'trimmed');
      Assert.isTrue(replayed.replayed);
      Assert.areEqual(reversed.internalTransferId, replayed.internalTransferId);
      Assert.areEqual('ALREADY_REVERSED', alreadyReversed);
      List<AXF_OBJ_InternalTransfer__c> rows = [
        SELECT Id, AXF_ITR_PKL_State__c, AXF_ITR_LKP_OriginalTransfer__c
        FROM AXF_OBJ_InternalTransfer__c
        ORDER BY CreatedDate
      ];
      Assert.areEqual(
        2,
        rows.size(),
        'candidate/confirmed row plus one compensation'
      );
      Assert.areEqual(transferId, rows[0].Id);
      Assert.areEqual(
        'CONFIRMED',
        rows[0].AXF_ITR_PKL_State__c,
        'original untouched'
      );
      Assert.isNull(rows[0].AXF_ITR_LKP_OriginalTransfer__c);
      Assert.areEqual('REVERSED', rows[1].AXF_ITR_PKL_State__c);
      Assert.areEqual(transferId, rows[1].AXF_ITR_LKP_OriginalTransfer__c);
    }
  }

  @IsTest
  static void guardsFailClosedWithoutRevealingExistence() {
    Fixture f;
    System.runAs(byAlias('axf32g')) {
      f = fixture('guards', 100);
    }
    Id transferId;
    System.runAs(byAlias('axf32g')) {
      transferId = new ALT_CLS_InternalTransferService()
        .suggest(suggestInput(f));
    }
    Test.startTest();
    System.runAs(byAlias('axf32n')) {
      try {
        new ALT_CLS_InternalTransferService().read(transferId);
        Assert.fail('capability missing');
      } catch (ALT_CLS_InternalTransferService.TransferException expected) {
        Assert.areEqual('UNAVAILABLE', expected.getMessage());
      }
    }
    System.runAs(byAlias('axf32p')) {
      try {
        new ALT_CLS_InternalTransferService().read(transferId);
        Assert.fail('foreign holder is indistinguishable from missing');
      } catch (ALT_CLS_InternalTransferService.TransferException expected) {
        Assert.areEqual('UNAVAILABLE', expected.getMessage());
      }
    }
    System.runAs(byAlias('axf32g')) {
      try {
        new ALT_CLS_InternalTransferService()
          .confirm(confirmInput(transferId, null, 'missing-version'));
        Assert.fail('expected version is required, not a silent CONFLICT');
      } catch (ALT_CLS_InternalTransferService.TransferException expected) {
        Assert.areEqual('INVALID', expected.getMessage());
      }
      ALT_CLS_InternalTransferService.ConfirmInput noKey = confirmInput(
        transferId,
        0,
        'k'
      );
      noKey.operationKey = null;
      try {
        new ALT_CLS_InternalTransferService().confirm(noKey);
        Assert.fail('operation key is required');
      } catch (ALT_CLS_InternalTransferService.TransferException expected) {
        Assert.areEqual('INVALID', expected.getMessage());
      }
      try {
        new ALT_CLS_InternalTransferService()
          .reverse(reverseInput(transferId, 0, 'NOT_A_REASON', null, 'x'));
        Assert.fail('unknown reason must be rejected');
      } catch (ALT_CLS_InternalTransferService.TransferException expected) {
        Assert.areEqual('INVALID_REASON', expected.getMessage());
      }
      try {
        new ALT_CLS_InternalTransferService()
          .reverse(
            reverseInput(transferId, 0, 'OTHER', null, 'still-candidate')
          );
        Assert.fail('only a CONFIRMED transfer can be reversed');
      } catch (ALT_CLS_InternalTransferService.TransferException expected) {
        Assert.areEqual('INVALID_TARGET', expected.getMessage());
      }
    }
    Test.stopTest();
  }
}
