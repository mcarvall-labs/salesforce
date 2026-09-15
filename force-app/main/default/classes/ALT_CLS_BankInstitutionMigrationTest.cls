/**
 * @description AXF-106 migration tests: simulation reports mapped/unresolved,
 * apply backfills only unambiguous (explicit bank-number mapping) null lookups and is
 * idempotent, never overwrites an existing lookup, and rollback clears only what
 * apply set. Provider text is never modified.
 */
@IsTest
private class ALT_CLS_BankInstitutionMigrationTest {
  static AXF_OBJ_BankInstitution__c bank(String bankNumber, String name) {
    return new AXF_OBJ_BankInstitution__c(
      Name = name,
      AXF_BI_EXI_Bank_Number__c = bankNumber
    );
  }

  @IsTest
  static void simulateCountsUnresolvedAndMapped() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection('ITEM_A');
    AXF_OBJ_BankAccount__c b = AXF_CLS_PluggyTestData.bankAccount(
      c.Id,
      'ACC-1',
      false
    );

    Test.startTest();
    ALT_CLS_BankInstitutionMigration.Report r = new ALT_CLS_BankInstitutionMigration()
      .simulate();
    Test.stopTest();

    System.assert(r.connectionsTotal >= 1);
    System.assert(r.connectionsUnresolved >= 1, 'null lookup = unresolved');
    System.assert(r.accountsUnresolved >= 1, 'null lookup = unresolved');
    System.assertEquals(0, r.backfilled, 'simulation is no-DML');
  }

  @IsTest
  static void applyBackfillsUnambiguousAndIsIdempotent() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection('ITEM_B');
    AXF_OBJ_BankAccount__c b = AXF_CLS_PluggyTestData.bankAccount(
      c.Id,
      'ACC-2',
      false
    );
    AXF_OBJ_BankInstitution__c inst = bank('260', 'Nubank');
    insert inst;

    Map<String, String> mapping = new Map<String, String>{
      'Test Bank' => '260'
    };

    Test.startTest();
    ALT_CLS_BankInstitutionMigration m = new ALT_CLS_BankInstitutionMigration();
    ALT_CLS_BankInstitutionMigration.Report first = m.apply(mapping);
    ALT_CLS_BankInstitutionMigration.Report second = m.apply(mapping);
    Test.stopTest();

    System.assert(first.backfilled >= 1, 'first apply backfills');
    System.assertEquals(
      0,
      second.backfilled,
      're-apply is idempotent (no null lookups left)'
    );

    AXF_OBJ_PluggyConnection__c conn = [
      SELECT AXF_CON_LKP_BankInstitution__c
      FROM AXF_OBJ_PluggyConnection__c
      WHERE Id = :c.Id
    ];
    System.assertEquals(inst.Id, conn.AXF_CON_LKP_BankInstitution__c);
  }

  @IsTest
  static void rollbackClearsOnlyBackfilledLookups() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection('ITEM_C');
    AXF_OBJ_BankInstitution__c inst = bank('260', 'Nubank');
    insert inst;
    Map<String, String> mapping = new Map<String, String>{
      'Test Bank' => '260'
    };

    ALT_CLS_BankInstitutionMigration m = new ALT_CLS_BankInstitutionMigration();
    m.apply(mapping);

    Test.startTest();
    ALT_CLS_BankInstitutionMigration.Report r = m.rollback(mapping);
    Test.stopTest();

    System.assert(r.rollbackCleared >= 1, 'rollback clears backfilled lookups');
    AXF_OBJ_PluggyConnection__c conn = [
      SELECT AXF_CON_LKP_BankInstitution__c
      FROM AXF_OBJ_PluggyConnection__c
      WHERE Id = :c.Id
    ];
    System.assertEquals(null, conn.AXF_CON_LKP_BankInstitution__c);
  }

  @IsTest
  static void neverOverwritesExistingManualLookup() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection('ITEM_D');
    AXF_OBJ_BankInstitution__c manual = bank('001', 'Banco do Brasil');
    AXF_OBJ_BankInstitution__c mapped = bank('260', 'Nubank');
    insert new List<AXF_OBJ_BankInstitution__c>{ manual, mapped };

    // Manually assign a DIFFERENT institution than the mapping would.
    c.AXF_CON_LKP_BankInstitution__c = manual.Id;
    update c;

    Map<String, String> mapping = new Map<String, String>{
      'Test Bank' => '260'
    };

    Test.startTest();
    new ALT_CLS_BankInstitutionMigration().apply(mapping);
    Test.stopTest();

    AXF_OBJ_PluggyConnection__c conn = [
      SELECT AXF_CON_LKP_BankInstitution__c
      FROM AXF_OBJ_PluggyConnection__c
      WHERE Id = :c.Id
    ];
    System.assertEquals(
      manual.Id,
      conn.AXF_CON_LKP_BankInstitution__c,
      'existing manual selection is never overwritten (AC8)'
    );
  }

  // ---- AC9: already-discovered sources, without requiring a new discovery ----

  static Id personRecordType() {
    return Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
      .getRecordTypeInfosByDeveloperName()
      .get('AXF_Person')
      .getRecordTypeId();
  }

  /** @description The framed identity key of AXF-85 (G6) — required on every ACH row. */
  static String framed(Id holderId, String kind, Id sourceId, String role) {
    return frame(String.valueOf(holderId)) +
      frame(kind) +
      frame(String.valueOf(sourceId)) +
      frame(role);
  }

  static String frame(String s) {
    return s.length() + ':' + s;
  }

  static Account holder(String name) {
    Account a = new Account(LastName = name, RecordTypeId = personRecordType());
    insert a;
    return [SELECT Id, OwnerId FROM Account WHERE Id = :a.Id];
  }

  /** @description A connection already carrying a usable canonical bank and holder. */
  static AXF_OBJ_PluggyConnection__c connectionWithReferences(
    String itemId,
    Id bankInstitutionId,
    Id holderId
  ) {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection(itemId);
    c.AXF_CON_LKP_BankInstitution__c = bankInstitutionId;
    c.AXF_CON_LKP_Account__c = holderId;
    update c;
    return c;
  }

  @IsTest
  static void compatibilityRunFillsBankAndReleasesAlreadyDiscoveredSources() {
    // the shared application runs under the AXF_CanConfigure gate, covered by
    // AXF_CLS_PluggyDiscoveryBankHolderTest#discoveryReportsForbiddenApplicationWithoutWriting
    ALT_CLS_SourceHolderConfirmation.canConfigureOverride = true;

    AXF_OBJ_BankInstitution__c inst = bank('260', 'Nubank');
    insert inst;
    Account h = holder('Compatibilidade');
    AXF_OBJ_PluggyConnection__c c = connectionWithReferences(
      'ITEM_AC9',
      inst.Id,
      h.Id
    );
    AXF_OBJ_BankAccount__c b = AXF_CLS_PluggyTestData.bankAccount(
      c.Id,
      'ACC-AC9',
      false
    );
    AXF_OBJ_CreditCard__c card = AXF_CLS_PluggyTestData.creditCard(
      c.Id,
      'CARD-AC9',
      false
    );

    ALT_CLS_BankInstitutionMigration m = new ALT_CLS_BankInstitutionMigration();

    // the dry run reports what the compatibility operation would do, with no DML
    Test.startTest();
    ALT_CLS_BankInstitutionMigration.Report sim = m.simulate();
    Test.stopTest();

    System.assertEquals(2, sim.discoveredSourcesTotal);
    System.assertEquals(
      2,
      sim.discoveredSourcesBankMapped,
      'bank fillable from the connection'
    );
    System.assertEquals(2, sim.discoveredSourcesReleasable, 'no holder yet');
    System.assertEquals(0, sim.discoveredSourcesConflicting);
    System.assertEquals(0, sim.discoveredSourcesPending);
    System.assertEquals(0, sim.backfilled, 'simulation is no-DML');
    System.assertEquals(
      0,
      [SELECT COUNT() FROM AXF_OBJ_AccountHolder__c],
      'simulation writes nothing'
    );

    // no name mapping at all: the connection's own canonical bank is the source
    ALT_CLS_BankInstitutionMigration.Report first = m.apply(
      new Map<String, String>()
    );

    System.assertEquals(
      2,
      first.discoveredSourcesApplied,
      first.notes.toString()
    );
    System.assertEquals(2, first.discoveredSourcesReleased);
    System.assertEquals(0, first.discoveredSourcesFailed);

    AXF_OBJ_BankAccount__c freshBank = [
      SELECT
        AXF_BA_LKP_BankInstitution__c,
        AXF_BA_LKP_Account__c,
        AXF_BA_PKL_AvailabilityState__c,
        AXF_BA_NUM_Version__c
      FROM AXF_OBJ_BankAccount__c
      WHERE Id = :b.Id
    ];
    System.assertEquals(
      inst.Id,
      freshBank.AXF_BA_LKP_BankInstitution__c,
      'the missing canonical bank is filled from the connection'
    );
    System.assertEquals(h.Id, freshBank.AXF_BA_LKP_Account__c);
    System.assertEquals('AVAILABLE', freshBank.AXF_BA_PKL_AvailabilityState__c);
    System.assertEquals(1, freshBank.AXF_BA_NUM_Version__c);

    AXF_OBJ_CreditCard__c freshCard = [
      SELECT
        AXF_CC_LKP_BankInstitution__c,
        AXF_CC_LKP_Account__c,
        AXF_CC_PKL_AvailabilityState__c
      FROM AXF_OBJ_CreditCard__c
      WHERE Id = :card.Id
    ];
    System.assertEquals(inst.Id, freshCard.AXF_CC_LKP_BankInstitution__c);
    System.assertEquals('AVAILABLE', freshCard.AXF_CC_PKL_AvailabilityState__c);
    System.assertEquals(
      2,
      [
        SELECT COUNT()
        FROM AXF_OBJ_AccountHolder__c
        WHERE
          AXF_ACH_PKL_Role__c = 'PRIMARY'
          AND AXF_ACH_PKL_State__c = 'CONFIRMED'
      ],
      'one definitive link per eligible source'
    );

    // repeatable: a second run writes nothing and adds no Version
    ALT_CLS_BankInstitutionMigration.Report second = m.apply(
      new Map<String, String>()
    );
    System.assertEquals(0, second.discoveredSourcesApplied, 'idempotent');
    System.assertEquals(0, second.backfilled);
    System.assertEquals(
      2,
      [SELECT COUNT() FROM AXF_OBJ_AccountHolder__c],
      'no duplicated link'
    );
    System.assertEquals(
      1,
      [
        SELECT AXF_BA_NUM_Version__c
        FROM AXF_OBJ_BankAccount__c
        WHERE Id = :b.Id
      ]
      .AXF_BA_NUM_Version__c,
      'no new Version on the released source'
    );
  }

  @IsTest
  static void compatibilityRunReportsPendingAndConflictingAndOverwritesNothing() {
    ALT_CLS_SourceHolderConfirmation.canConfigureOverride = true;

    AXF_OBJ_BankInstitution__c inst = bank('341', 'Itau');
    AXF_OBJ_BankInstitution__c storedBank = bank('001', 'Banco do Brasil');
    insert new List<AXF_OBJ_BankInstitution__c>{ inst, storedBank };
    Account h = holder('Conflito');
    Account other = holder('Outro Titular');

    // pending: a connection with a bank but no usable holder
    AXF_OBJ_PluggyConnection__c pendingConn = connectionWithReferences(
      'ITEM_PEND',
      inst.Id,
      null
    );
    AXF_OBJ_BankAccount__c pendingSource = AXF_CLS_PluggyTestData.bankAccount(
      pendingConn.Id,
      'ACC-PEND',
      false
    );

    // conflicting: another holder is already CONFIRMED on the source
    AXF_OBJ_PluggyConnection__c conflictConn = connectionWithReferences(
      'ITEM_CONF',
      inst.Id,
      h.Id
    );
    AXF_OBJ_BankAccount__c conflictSource = AXF_CLS_PluggyTestData.bankAccount(
      conflictConn.Id,
      'ACC-CONF',
      false
    );
    Database.insert(
      new AXF_OBJ_AccountHolder__c(
        OwnerId = other.OwnerId,
        AXF_ACH_LKP_Account__c = other.Id,
        AXF_ACH_LKP_BankAccount__c = conflictSource.Id,
        AXF_ACH_EXI_FramedKey__c = framed(
          other.Id,
          'BANK',
          conflictSource.Id,
          'PRIMARY'
        ),
        AXF_ACH_PKL_Role__c = 'PRIMARY',
        AXF_ACH_PKL_State__c = 'CONFIRMED',
        AXF_ACH_DAT_ValidFrom__c = Date.today(),
        AXF_ACH_NUM_Version__c = 1
      ),
      AccessLevel.SYSTEM_MODE
    );

    // conflicting: a canonical bank diverging from the connection's (AC8)
    AXF_OBJ_BankAccount__c bankDivergent = AXF_CLS_PluggyTestData.bankAccount(
      conflictConn.Id,
      'ACC-BANKDIV',
      false
    );
    bankDivergent.AXF_BA_LKP_BankInstitution__c = storedBank.Id;
    Database.update(bankDivergent, AccessLevel.SYSTEM_MODE);

    ALT_CLS_BankInstitutionMigration.Report sim = new ALT_CLS_BankInstitutionMigration()
      .simulate();

    System.assert(sim.discoveredSourcesPending >= 1, 'pending reported');
    // The divergent bank source has NO confirmed holder, so the holder axis still applies:
    // the dry run classifies it exactly as the execution treats it (AC9 coherence).
    System.assertEquals(
      1,
      sim.discoveredSourcesConflicting,
      'another confirmed holder is the only conflict'
    );
    System.assertEquals(
      1,
      sim.discoveredSourcesReleasable,
      'a divergent bank without a holder is still releasable: ' +
      sim.discoveredSourcesBankMapped
    );

    ALT_CLS_BankInstitutionMigration.Report applied = new ALT_CLS_BankInstitutionMigration()
      .apply(new Map<String, String>());

    System.assertEquals(0, applied.discoveredSourcesFailed);
    System.assertEquals(
      1,
      applied.discoveredSourcesReleased,
      'the dry run and the execution agree: ' + applied.notes.toString()
    );
    // the pending source keeps its custodian state and gets no link
    AXF_OBJ_BankAccount__c freshPending = [
      SELECT
        AXF_BA_PKL_AvailabilityState__c,
        AXF_BA_LKP_Account__c,
        AXF_BA_LKP_BankInstitution__c
      FROM AXF_OBJ_BankAccount__c
      WHERE Id = :pendingSource.Id
    ];
    System.assertEquals(
      'CUSTODY',
      freshPending.AXF_BA_PKL_AvailabilityState__c,
      'no usable holder keeps the source pending'
    );
    // the divergent holder is preserved
    System.assertEquals(
      other.Id,
      [
        SELECT AXF_ACH_LKP_Account__c
        FROM AXF_OBJ_AccountHolder__c
        WHERE AXF_ACH_LKP_BankAccount__c = :conflictSource.Id
      ]
      .AXF_ACH_LKP_Account__c,
      'the confirmed holder is never overwritten'
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM AXF_OBJ_AccountHolder__c
        WHERE AXF_ACH_LKP_BankAccount__c = :conflictSource.Id
      ],
      'no second link is created for a divergent source'
    );
    // the divergent canonical bank is preserved
    System.assertEquals(
      storedBank.Id,
      [
        SELECT AXF_BA_LKP_BankInstitution__c
        FROM AXF_OBJ_BankAccount__c
        WHERE Id = :bankDivergent.Id
      ]
      .AXF_BA_LKP_BankInstitution__c
    );
    // ...while the holder axis really released it, exactly as the dry run said
    AXF_OBJ_BankAccount__c freshDivergent = [
      SELECT AXF_BA_LKP_Account__c, AXF_BA_PKL_AvailabilityState__c
      FROM AXF_OBJ_BankAccount__c
      WHERE Id = :bankDivergent.Id
    ];
    System.assertEquals(h.Id, freshDivergent.AXF_BA_LKP_Account__c);
    System.assertEquals(
      'AVAILABLE',
      freshDivergent.AXF_BA_PKL_AvailabilityState__c
    );
  }

  /**
   * @description AC9 — the references are applied independently: an unusable bank never
   * refuses the batch and never blocks the holder application.
   */
  @IsTest
  static void unusableBankStillAppliesTheHolder() {
    ALT_CLS_SourceHolderConfirmation.canConfigureOverride = true;

    AXF_OBJ_BankInstitution__c inst = bank('260', 'Nubank');
    insert inst;
    Account h = holder('Sem banco utilizavel');
    AXF_OBJ_PluggyConnection__c c = connectionWithReferences(
      'ITEM_UNUSABLE_BANK',
      inst.Id,
      h.Id
    );
    AXF_OBJ_BankAccount__c b = AXF_CLS_PluggyTestData.bankAccount(
      c.Id,
      'ACC-UB',
      false
    );

    // The connection's bank cannot be used by this caller: the reference-usability probe is
    // injected because an Apex test cannot make a USER_MODE read hide an otherwise readable
    // institution (production never sets it).
    ALT_CLS_BankInstitutionMigration.usableBanksForTests = new Set<Id>();

    ALT_CLS_BankInstitutionMigration m = new ALT_CLS_BankInstitutionMigration();
    Test.startTest();
    ALT_CLS_BankInstitutionMigration.Report sim = m.simulate();
    ALT_CLS_BankInstitutionMigration.Report applied = m.apply(
      new Map<String, String>()
    );
    Test.stopTest();

    // the dry run says the same thing the execution does
    System.assertEquals(1, sim.discoveredSourcesReleasable);
    System.assertEquals(1, sim.discoveredSourcesBankUnresolved);
    System.assertEquals(
      0,
      applied.discoveredSourcesFailed,
      'an unusable bank never refuses the batch: ' + applied.notes.toString()
    );
    System.assertEquals(1, applied.discoveredSourcesReleased);

    AXF_OBJ_BankAccount__c fresh = [
      SELECT
        AXF_BA_LKP_Account__c,
        AXF_BA_LKP_BankInstitution__c,
        AXF_BA_PKL_AvailabilityState__c
      FROM AXF_OBJ_BankAccount__c
      WHERE Id = :b.Id
    ];
    System.assertEquals(
      h.Id,
      fresh.AXF_BA_LKP_Account__c,
      'the holder is applied without the unusable bank'
    );
    System.assertEquals(
      null,
      fresh.AXF_BA_LKP_BankInstitution__c,
      'an unusable reference is never applied'
    );
    System.assertEquals('AVAILABLE', fresh.AXF_BA_PKL_AvailabilityState__c);

    ALT_CLS_BankInstitutionMigration.usableBanksForTests = null;
  }

  /**
   * @description AC9/AC6 — a batch the operation refuses wrote nothing: every source it
   * carried is counted as a failure instead of leaving the counters at zero with a note.
   */
  @IsTest
  static void refusedBatchIsCountedAsFailure() {
    // The shared application is refused for this caller.
    ALT_CLS_SourceHolderConfirmation.canConfigureOverride = false;

    AXF_OBJ_BankInstitution__c inst = bank('341', 'Itau');
    insert inst;
    Account h = holder('Recusado');
    AXF_OBJ_PluggyConnection__c c = connectionWithReferences(
      'ITEM_REFUSED',
      inst.Id,
      h.Id
    );
    AXF_OBJ_BankAccount__c b = AXF_CLS_PluggyTestData.bankAccount(
      c.Id,
      'ACC-REF',
      false
    );
    AXF_CLS_PluggyTestData.creditCard(c.Id, 'CARD-REF', false);

    Test.startTest();
    ALT_CLS_BankInstitutionMigration.Report applied = new ALT_CLS_BankInstitutionMigration()
      .apply(new Map<String, String>());
    Test.stopTest();

    System.assertEquals(
      2,
      applied.discoveredSourcesFailed,
      'the refused batch is counted per source: ' + applied.notes.toString()
    );
    System.assertEquals(0, applied.discoveredSourcesApplied);
    System.assertEquals(0, applied.discoveredSourcesReleased);
    System.assert(
      applied.notes.toString().containsIgnoreCase('autoriza'),
      'the refusal cause is kept: ' + applied.notes.toString()
    );
    System.assertEquals(
      'CUSTODY',
      [
        SELECT AXF_BA_PKL_AvailabilityState__c
        FROM AXF_OBJ_BankAccount__c
        WHERE Id = :b.Id
      ]
      .AXF_BA_PKL_AvailabilityState__c,
      'a refused batch writes nothing'
    );
    System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_AccountHolder__c]);
  }

  @IsTest
  static void rollbackClearsTheConnectionDerivedBankAndKeepsTheRelease() {
    ALT_CLS_SourceHolderConfirmation.canConfigureOverride = true;

    AXF_OBJ_BankInstitution__c inst = bank('260', 'Nubank');
    insert inst;
    Account h = holder('Rollback');
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection(
      'ITEM_RB'
    );
    // the connection bank itself comes from the verified name mapping
    Map<String, String> mapping = new Map<String, String>{
      'Test Bank' => '260'
    };
    AXF_OBJ_BankAccount__c b = AXF_CLS_PluggyTestData.bankAccount(
      c.Id,
      'ACC-RB',
      false
    );
    c.AXF_CON_LKP_Account__c = h.Id;
    update c;

    ALT_CLS_BankInstitutionMigration m = new ALT_CLS_BankInstitutionMigration();
    m.apply(mapping);
    System.assertEquals(
      'AVAILABLE',
      [
        SELECT AXF_BA_PKL_AvailabilityState__c
        FROM AXF_OBJ_BankAccount__c
        WHERE Id = :b.Id
      ]
      .AXF_BA_PKL_AvailabilityState__c
    );

    Test.startTest();
    ALT_CLS_BankInstitutionMigration.Report r = m.rollback(mapping);
    Test.stopTest();

    System.assert(r.rollbackCleared >= 1);
    System.assertEquals(
      null,
      [
        SELECT AXF_CON_LKP_BankInstitution__c
        FROM AXF_OBJ_PluggyConnection__c
        WHERE Id = :c.Id
      ]
      .AXF_CON_LKP_BankInstitution__c,
      'the mapping-derived connection bank is cleared'
    );
    AXF_OBJ_BankAccount__c fresh = [
      SELECT
        AXF_BA_LKP_BankInstitution__c,
        AXF_BA_PKL_AvailabilityState__c,
        AXF_BA_LKP_Account__c
      FROM AXF_OBJ_BankAccount__c
      WHERE Id = :b.Id
    ];
    System.assertEquals(
      null,
      fresh.AXF_BA_LKP_BankInstitution__c,
      'the bank the source received from its connection is cleared too'
    );
    // documented rollback boundary: a released source is never sent back to custody
    System.assertEquals('AVAILABLE', fresh.AXF_BA_PKL_AvailabilityState__c);
    System.assertEquals(h.Id, fresh.AXF_BA_LKP_Account__c);
  }
}
