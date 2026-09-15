/**
 * @description AXF-106 — connection bank/holder references. updateReferences sets or
 * clears the canonical bank and holder without touching provider evidence, validates the
 * holder record type, is explicit-only and never overwrites an existing selection.
 * overview() exposes bank and holder names. Discovery applies the connection's bank and
 * holder to the sources it discovers, releases the eligible ones and reports what stayed
 * pending or divergent.
 */
@IsTest
private class AXF_CLS_PluggyDiscoveryBankHolderTest {
  static AXF_OBJ_BankInstitution__c bank(String bankNumber, String name) {
    return new AXF_OBJ_BankInstitution__c(
      Name = name,
      AXF_BI_EXI_Bank_Number__c = bankNumber
    );
  }

  static Id holderId() {
    return holderId('Ana', 'Souza');
  }

  static Id holderId(String firstName, String lastName) {
    ALT_CLS_AxonHolder.canConfigureOverride = true;
    ALT_CLS_AxonHolder.SaveInput si = new ALT_CLS_AxonHolder.SaveInput();
    si.type = 'PERSON';
    si.firstName = firstName;
    si.lastName = lastName;
    return new ALT_CLS_AxonHolder().saveHolder(si).accountId;
  }

  static AXF_CLS_PluggyDiscoveryService svc() {
    AXF_CLS_PluggyDiscoveryService.canDiscoverOverride = true;
    // the discovery application runs under the same AXF_CanConfigure gate as discovery
    ALT_CLS_SourceHolderConfirmation.canConfigureOverride = true;
    return new AXF_CLS_PluggyDiscoveryService();
  }

  static AXF_OBJ_BankAccount__c discoveredBank(Id connectionId) {
    return [
      SELECT
        Id,
        OwnerId,
        AXF_BA_LKP_Account__c,
        AXF_BA_LKP_BankInstitution__c,
        AXF_BA_PKL_AvailabilityState__c,
        AXF_BA_NUM_Version__c,
        AXF_BA_TXT_InstitutionName__c,
        AXF_BA_TXT_ConnectorId__c,
        AXF_BA_TXT_CurrencyIsoCode__c,
        AXF_BA_TXT_NumberMasked__c,
        AXF_BA_CUR_CurrentBalance__c
      FROM AXF_OBJ_BankAccount__c
      WHERE AXF_BA_LKP_Connection__c = :connectionId
    ];
  }

  static AXF_OBJ_CreditCard__c discoveredCard(Id connectionId) {
    return [
      SELECT
        Id,
        OwnerId,
        AXF_CC_LKP_Account__c,
        AXF_CC_LKP_BankInstitution__c,
        AXF_CC_PKL_AvailabilityState__c,
        AXF_CC_NUM_Version__c,
        AXF_CC_TXT_Level__c
      FROM AXF_OBJ_CreditCard__c
      WHERE AXF_CC_LKP_Connection__c = :connectionId
    ];
  }

  static AXF_OBJ_BankAccount__c reloadBank(Id sourceId) {
    return [
      SELECT
        Id,
        OwnerId,
        AXF_BA_LKP_Account__c,
        AXF_BA_LKP_BankInstitution__c,
        AXF_BA_PKL_AvailabilityState__c,
        AXF_BA_NUM_Version__c
      FROM AXF_OBJ_BankAccount__c
      WHERE Id = :sourceId
    ];
  }

  /** @description The AXF-85 confirmation input for a source already known to the test. */
  static ALT_CLS_SourceHolderConfirmation.ConfirmInput confirmInput(
    Id sourceId,
    String kind,
    Id holderId,
    Integer version
  ) {
    ALT_CLS_SourceHolderConfirmation.ConfirmInput i = new ALT_CLS_SourceHolderConfirmation.ConfirmInput();
    i.sourceId = sourceId;
    i.kind = kind;
    i.holderId = holderId;
    i.expectedVersion = version;
    return i;
  }

  @IsTest
  static void setsBankAndHolderWithoutTouchingProviderEvidence() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection('ITEM_A');
    AXF_OBJ_BankInstitution__c inst = bank('260', 'Nubank');
    insert inst;
    Id holder = holderId();

    Test.startTest();
    AXF_CLS_PluggyDiscoveryService.UpdateReferencesResult r = svc()
      .updateReferences(c.Id, inst.Id, holder);
    Test.stopTest();

    System.assertEquals(c.Id, r.connectionId);
    AXF_OBJ_PluggyConnection__c reloaded = [
      SELECT
        Id,
        AXF_CON_LKP_BankInstitution__c,
        AXF_CON_LKP_Account__c,
        AXF_CON_TXT_InstitutionName__c,
        AXF_CON_TXT_ConnectorId__c
      FROM AXF_OBJ_PluggyConnection__c
      WHERE Id = :c.Id
    ];
    System.assertEquals(inst.Id, reloaded.AXF_CON_LKP_BankInstitution__c);
    System.assertEquals(holder, reloaded.AXF_CON_LKP_Account__c);
    System.assertEquals(
      'Test Bank',
      reloaded.AXF_CON_TXT_InstitutionName__c,
      'provider institution text is preserved'
    );
  }

  @IsTest
  static void overviewExposesBankAndHolderNames() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection('ITEM_B');
    AXF_OBJ_BankInstitution__c inst = bank('001', 'Banco do Brasil');
    insert inst;
    Id holder = holderId();
    svc().updateReferences(c.Id, inst.Id, holder);

    Test.startTest();
    List<AXF_CLS_PluggyDiscoveryService.ConnectionOverviewDTO> rows = svc()
      .overview();
    Test.stopTest();

    AXF_CLS_PluggyDiscoveryService.ConnectionOverviewDTO found;
    for (AXF_CLS_PluggyDiscoveryService.ConnectionOverviewDTO d : rows) {
      if (d.connectionId == c.Id) {
        found = d;
      }
    }
    System.assertNotEquals(null, found, 'connection present in overview');
    System.assertEquals('Banco do Brasil', found.bankInstitutionName);
    System.assertEquals('Ana Souza', found.holderName);
    System.assertEquals(inst.Id, found.bankInstitutionId);
    System.assertEquals(holder, found.holderId);
  }

  @IsTest
  static void clearingReferencesIsExplicit() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection('ITEM_C');
    AXF_OBJ_BankInstitution__c inst = bank('001', 'Banco do Brasil');
    insert inst;
    Id holder = holderId();
    svc().updateReferences(c.Id, inst.Id, holder);

    Test.startTest();
    svc().updateReferences(c.Id, null, null);
    Test.stopTest();

    AXF_OBJ_PluggyConnection__c reloaded = [
      SELECT AXF_CON_LKP_BankInstitution__c, AXF_CON_LKP_Account__c
      FROM AXF_OBJ_PluggyConnection__c
      WHERE Id = :c.Id
    ];
    System.assertEquals(null, reloaded.AXF_CON_LKP_BankInstitution__c);
    System.assertEquals(null, reloaded.AXF_CON_LKP_Account__c);
  }

  @IsTest
  static void preservesBankWhenOnlyHolderChanges() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection('ITEM_D');
    AXF_OBJ_BankInstitution__c inst = bank('001', 'Banco do Brasil');
    insert inst;
    Id holder = holderId();
    svc().updateReferences(c.Id, inst.Id, holder);

    Test.startTest();
    svc().updateReferences(c.Id, null, null);
    svc().updateReferences(c.Id, null, holder);
    Test.stopTest();

    AXF_OBJ_PluggyConnection__c reloaded = [
      SELECT AXF_CON_LKP_BankInstitution__c, AXF_CON_LKP_Account__c
      FROM AXF_OBJ_PluggyConnection__c
      WHERE Id = :c.Id
    ];
    System.assertEquals(null, reloaded.AXF_CON_LKP_BankInstitution__c);
    System.assertEquals(holder, reloaded.AXF_CON_LKP_Account__c);
  }

  @IsTest
  static void rejectsInaccessibleHolder() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection('ITEM_E');
    AXF_OBJ_BankInstitution__c inst = bank('001', 'Banco do Brasil');
    insert inst;
    // A syntactically valid but non-existent Account Id.
    String bogusId = '001000000000000';

    try {
      svc().updateReferences(c.Id, inst.Id, (Id) bogusId);
      System.assert(false, 'inaccessible holder must be rejected');
    } catch (AXF_CLS_PluggyDiscoveryException e) {
      System.assert(
        e.getMessage().containsIgnoreCase('inacessivel'),
        e.getMessage()
      );
    }
  }

  @IsTest
  static void unauthorizedCallerIsDenied() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection('ITEM_F');
    AXF_CLS_PluggyDiscoveryService.canDiscoverOverride = false;
    try {
      new AXF_CLS_PluggyDiscoveryService().updateReferences(c.Id, null, null);
      System.assert(false, 'unauthorized reference edit must fail');
    } catch (AXF_CLS_PluggyDiscoveryException e) {
      System.assert(e.getMessage().containsIgnoreCase('autoriza'));
    }
  }

  @IsTest
  static void deletesConnectionWithUnusedCustodySources() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection(
      'ITEM_DEL'
    );
    AXF_CLS_PluggyTestData.bankAccount(c.Id, 'ACC-DEL', false);

    Test.startTest();
    AXF_CLS_PluggyDiscoveryService.DeleteResult r = svc()
      .deleteConnection(c.Id);
    Test.stopTest();

    System.assertEquals('DELETED', r.outcome, r.message);
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM AXF_OBJ_PluggyConnection__c
        WHERE Id = :c.Id
      ],
      'connection removed'
    );
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM AXF_OBJ_BankAccount__c
        WHERE AXF_BA_LKP_Connection__c = :c.Id
      ],
      'unused custody source removed with it'
    );
  }

  @IsTest
  static void blocksDeleteWhenSourceIsInFinancialUse() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection(
      'ITEM_BLK'
    );
    AXF_CLS_PluggyTestData.bankAccount(c.Id, 'ACC-BLK', true);

    Test.startTest();
    AXF_CLS_PluggyDiscoveryService.DeleteResult r = svc()
      .deleteConnection(c.Id);
    Test.stopTest();

    System.assertEquals('BLOCKED', r.outcome, r.message);
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM AXF_OBJ_PluggyConnection__c
        WHERE Id = :c.Id
      ],
      'connection preserved while a source is in use'
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM AXF_OBJ_BankAccount__c
        WHERE AXF_BA_LKP_Connection__c = :c.Id
      ],
      'financial source preserved'
    );
  }

  // ============ AXF-106 — discovery applies the connection's bank and holder ============

  @IsTest
  static void discoveryAppliesBankAndHolderAndReleasesSources() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection(
      'ITEM_APPLY'
    );
    AXF_OBJ_BankInstitution__c inst = bank('260', 'Nubank');
    insert inst;
    Id holder = holderId();
    c.AXF_CON_TXT_ConnectorId__c = '201';
    update c;
    svc().updateReferences(c.Id, inst.Id, holder);
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());

    Test.startTest();
    AXF_CLS_PluggyDiscoveryService.DiscoveryResult r = svc()
      .startOrResume(c.Id);
    Test.stopTest();

    System.assertEquals('SUCCEEDED', r.state, r.message);
    System.assertEquals(2, r.applied, r.message);
    System.assertEquals(2, r.released, r.message);
    System.assertEquals(0, r.pending);

    AXF_OBJ_BankAccount__c ba = discoveredBank(c.Id);
    System.assertEquals('AVAILABLE', ba.AXF_BA_PKL_AvailabilityState__c);
    System.assertEquals(holder, ba.AXF_BA_LKP_Account__c);
    System.assertEquals(inst.Id, ba.AXF_BA_LKP_BankInstitution__c);
    System.assertEquals(1, ba.AXF_BA_NUM_Version__c);
    System.assertEquals(
      [
        SELECT OwnerId
        FROM Account
        WHERE Id = :holder
      ]
      .OwnerId,
      ba.OwnerId,
      'owner synced with the holder (G2-2)'
    );
    // provider evidence is preserved by the application
    System.assertEquals('Test Bank', ba.AXF_BA_TXT_InstitutionName__c);
    System.assertEquals('201', ba.AXF_BA_TXT_ConnectorId__c);
    System.assertEquals('BRL', ba.AXF_BA_TXT_CurrencyIsoCode__c);
    System.assertEquals('****5678', ba.AXF_BA_TXT_NumberMasked__c);
    System.assertEquals(100.55, ba.AXF_BA_CUR_CurrentBalance__c);

    AXF_OBJ_CreditCard__c card = discoveredCard(c.Id);
    System.assertEquals('AVAILABLE', card.AXF_CC_PKL_AvailabilityState__c);
    System.assertEquals(holder, card.AXF_CC_LKP_Account__c);
    System.assertEquals('GOLD', card.AXF_CC_TXT_Level__c);

    System.assertEquals(
      2,
      [
        SELECT COUNT()
        FROM AXF_OBJ_AccountHolder__c
        WHERE
          AXF_ACH_PKL_Role__c = 'PRIMARY'
          AND AXF_ACH_PKL_State__c = 'CONFIRMED'
          AND AXF_ACH_LKP_Account__c = :holder
      ],
      'one definitive link per discovered source'
    );
  }

  @IsTest
  static void discoveryWithoutHolderAppliesTheBankAndKeepsCustody() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection(
      'ITEM_NO_HOLDER'
    );
    AXF_OBJ_BankInstitution__c inst = bank('001', 'Banco do Brasil');
    insert inst;
    svc().updateReferences(c.Id, inst.Id, null);
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());

    Test.startTest();
    AXF_CLS_PluggyDiscoveryService.DiscoveryResult r = svc()
      .startOrResume(c.Id);
    Test.stopTest();

    System.assertEquals('SUCCEEDED', r.state, r.message);
    System.assertEquals(0, r.released, r.message);
    System.assertEquals(2, r.pending, r.message);
    System.assert(r.message.containsIgnoreCase('pendente'), r.message);

    AXF_OBJ_BankAccount__c ba = discoveredBank(c.Id);
    System.assertEquals('CUSTODY', ba.AXF_BA_PKL_AvailabilityState__c);
    System.assertEquals(
      inst.Id,
      ba.AXF_BA_LKP_BankInstitution__c,
      'bank applied'
    );
    System.assertEquals(null, ba.AXF_BA_LKP_Account__c);
    System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_AccountHolder__c]);
  }

  @IsTest
  static void discoveryWithoutBankStillLinksAndReleases() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection(
      'ITEM_NO_BANK'
    );
    Id holder = holderId();
    svc().updateReferences(c.Id, null, holder);
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());

    Test.startTest();
    AXF_CLS_PluggyDiscoveryService.DiscoveryResult r = svc()
      .startOrResume(c.Id);
    Test.stopTest();

    System.assertEquals('SUCCEEDED', r.state, r.message);
    System.assertEquals(2, r.released, r.message);
    System.assertEquals(0, r.pending);
    AXF_OBJ_BankAccount__c ba = discoveredBank(c.Id);
    System.assertEquals('AVAILABLE', ba.AXF_BA_PKL_AvailabilityState__c);
    System.assertEquals(holder, ba.AXF_BA_LKP_Account__c);
    System.assertEquals(
      null,
      ba.AXF_BA_LKP_BankInstitution__c,
      'the bank stays null and visible as pending'
    );
  }

  @IsTest
  static void rediscoveryKeepsReleasedSourcesAvailableWithoutANewLink() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection(
      'ITEM_REPLAY'
    );
    AXF_OBJ_BankInstitution__c inst = bank('260', 'Nubank');
    insert inst;
    Id holder = holderId();
    svc().updateReferences(c.Id, inst.Id, holder);
    // The bank was discovered and released by an earlier run: same provider id the mock
    // returns (ACC-1), already linked and with the connection bank applied.
    AXF_OBJ_BankAccount__c prior = AXF_CLS_PluggyTestData.bankAccount(
      c.Id,
      'ACC-1',
      false
    );
    new ALT_CLS_SourceHolderConfirmation()
      .confirmHolder(confirmInput(prior.Id, 'BANK', holder, 0));
    Database.update(
      new AXF_OBJ_BankAccount__c(
        Id = prior.Id,
        AXF_BA_LKP_BankInstitution__c = inst.Id
      ),
      AccessLevel.SYSTEM_MODE
    );
    AXF_OBJ_BankAccount__c released = reloadBank(prior.Id);
    System.assertEquals('AVAILABLE', released.AXF_BA_PKL_AvailabilityState__c);
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());

    Test.startTest();
    AXF_CLS_PluggyDiscoveryService.DiscoveryResult r = svc()
      .startOrResume(c.Id);
    Test.stopTest();

    System.assertEquals('SUCCEEDED', r.state, r.message);
    System.assertEquals(
      1,
      r.applied,
      'only the newly discovered card had something to write'
    );
    // The counters report this run's action, not the state it inherited: the replayed
    // source was already AVAILABLE, so only the card counts as released (AXF-106).
    System.assertEquals(
      1,
      r.released,
      'only the source this run released is counted'
    );
    System.assertEquals(
      0,
      r.pending,
      'the replayed source is not pending either'
    );
    AXF_OBJ_BankAccount__c fresh = reloadBank(prior.Id);
    System.assertEquals(
      'AVAILABLE',
      fresh.AXF_BA_PKL_AvailabilityState__c,
      'a released source is never returned to custody'
    );
    System.assertEquals(
      released.AXF_BA_NUM_Version__c,
      fresh.AXF_BA_NUM_Version__c,
      'no new Version on rediscovery'
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM AXF_OBJ_BankAccount__c
        WHERE AXF_BA_LKP_Connection__c = :c.Id
      ],
      'no duplicated source'
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM AXF_OBJ_AccountHolder__c
        WHERE AXF_ACH_LKP_BankAccount__c = :prior.Id
      ],
      'no duplicated link'
    );
  }

  /**
   * @description AC6 — the upsert key is GLOBALLY unique, so a source already released on
   * ANOTHER connection must never be repointed to this one, sent back to custody nor
   * released again when the same provider id reappears in this discovery.
   */
  @IsTest
  static void rediscoveryNeverStealsASourceFromAnotherConnection() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection(
      'ITEM_OWN'
    );
    AXF_OBJ_PluggyConnection__c other = AXF_CLS_PluggyTestData.connection(
      'ITEM_OTHER'
    );
    AXF_OBJ_BankInstitution__c inst = bank('260', 'Nubank');
    insert inst;
    Id holder = holderId('Ana', 'Souza');
    Id otherHolder = holderId('Bruno', 'Lima');
    // The other connection already owns and released the sources the mock returns.
    svc().updateReferences(other.Id, inst.Id, otherHolder);
    AXF_OBJ_BankAccount__c foreignBank = AXF_CLS_PluggyTestData.bankAccount(
      other.Id,
      'ACC-1',
      false
    );
    new ALT_CLS_SourceHolderConfirmation()
      .confirmHolder(confirmInput(foreignBank.Id, 'BANK', otherHolder, 0));
    AXF_OBJ_CreditCard__c foreignCard = AXF_CLS_PluggyTestData.creditCard(
      other.Id,
      'ACC-2',
      false
    );
    new ALT_CLS_SourceHolderConfirmation()
      .confirmHolder(confirmInput(foreignCard.Id, 'CARD', otherHolder, 0));
    AXF_OBJ_BankAccount__c releasedBank = reloadBank(foreignBank.Id);
    System.assertEquals(
      'AVAILABLE',
      releasedBank.AXF_BA_PKL_AvailabilityState__c,
      'the source of the other connection starts released'
    );

    // This connection carries its own bank and holder.
    svc().updateReferences(c.Id, inst.Id, holder);
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());

    Test.startTest();
    AXF_CLS_PluggyDiscoveryService.DiscoveryResult r = svc()
      .startOrResume(c.Id);
    Test.stopTest();

    System.assertEquals('SUCCEEDED', r.state, r.message);
    System.assertEquals(
      2,
      r.accountsFound + r.cardsFound,
      'the provider really returned both sources'
    );
    System.assertEquals(0, r.applied, r.message);
    System.assertEquals(
      0,
      r.released,
      'a source of another connection is never released by THIS run: ' +
      r.message
    );
    System.assert(
      r.message.containsIgnoreCase('outra conexao'),
      'the foreign sources are reported: ' + r.message
    );

    AXF_OBJ_BankAccount__c freshBank = reloadBank(foreignBank.Id);
    System.assertEquals(
      other.Id,
      [
        SELECT AXF_BA_LKP_Connection__c
        FROM AXF_OBJ_BankAccount__c
        WHERE Id = :foreignBank.Id
      ]
      .AXF_BA_LKP_Connection__c,
      'the original connection is preserved'
    );
    System.assertEquals(
      'AVAILABLE',
      freshBank.AXF_BA_PKL_AvailabilityState__c,
      'never sent back to custody'
    );
    System.assertEquals(
      otherHolder,
      freshBank.AXF_BA_LKP_Account__c,
      'the original holder is preserved'
    );
    System.assertEquals(
      releasedBank.AXF_BA_NUM_Version__c,
      freshBank.AXF_BA_NUM_Version__c,
      'nothing was written on the preserved source'
    );
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM AXF_OBJ_BankAccount__c
        WHERE AXF_BA_LKP_Connection__c = :c.Id
      ],
      'no source is created for this connection from a foreign id'
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM AXF_OBJ_AccountHolder__c
        WHERE AXF_ACH_LKP_BankAccount__c = :foreignBank.Id
      ],
      'no second link is created'
    );

    AXF_OBJ_CreditCard__c freshCard = [
      SELECT
        AXF_CC_LKP_Connection__c,
        AXF_CC_PKL_AvailabilityState__c,
        AXF_CC_LKP_Account__c
      FROM AXF_OBJ_CreditCard__c
      WHERE Id = :foreignCard.Id
    ];
    System.assertEquals(other.Id, freshCard.AXF_CC_LKP_Connection__c);
    System.assertEquals('AVAILABLE', freshCard.AXF_CC_PKL_AvailabilityState__c);
    System.assertEquals(otherHolder, freshCard.AXF_CC_LKP_Account__c);
  }

  @IsTest
  static void discoveryReportsTheDivergentSourceAndWritesNothing() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection(
      'ITEM_DIVERGENT'
    );
    AXF_OBJ_BankInstitution__c inst = bank('260', 'Nubank');
    insert inst;
    Id confirmed = holderId('Ana', 'Souza');
    Id fromConnection = holderId('Bruno', 'Lima');
    svc().updateReferences(c.Id, inst.Id, fromConnection);
    // The bank (ACC-1) is already confirmed to someone else while the connection now
    // points at a different holder; the card (ACC-2) is brand new.
    AXF_OBJ_BankAccount__c prior = AXF_CLS_PluggyTestData.bankAccount(
      c.Id,
      'ACC-1',
      false
    );
    new ALT_CLS_SourceHolderConfirmation()
      .confirmHolder(confirmInput(prior.Id, 'BANK', confirmed, 0));
    AXF_OBJ_BankAccount__c released = reloadBank(prior.Id);
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());

    Test.startTest();
    AXF_CLS_PluggyDiscoveryService.DiscoveryResult r = svc()
      .startOrResume(c.Id);
    Test.stopTest();

    System.assertEquals('SUCCEEDED', r.state, r.message);
    System.assertEquals(1, r.divergent, r.message);
    System.assert(r.message.containsIgnoreCase('divergente'), r.message);

    AXF_OBJ_BankAccount__c fresh = reloadBank(prior.Id);
    System.assertEquals(
      confirmed,
      fresh.AXF_BA_LKP_Account__c,
      'the source keeps its confirmed holder'
    );
    System.assertEquals(
      released.AXF_BA_NUM_Version__c,
      fresh.AXF_BA_NUM_Version__c,
      'nothing was written on a divergent source'
    );
    System.assertEquals(
      null,
      fresh.AXF_BA_LKP_BankInstitution__c,
      'not even the connection bank is applied to a divergent source'
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM AXF_OBJ_AccountHolder__c
        WHERE AXF_ACH_LKP_BankAccount__c = :prior.Id
      ]
    );
  }

  @IsTest
  static void overviewExposesDivergenceFromTheConnectionHolder() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection(
      'ITEM_OVERVIEW_DIV'
    );
    Id confirmed = holderId('Ana', 'Souza');
    Id fromConnection = holderId('Bruno', 'Lima');
    svc().updateReferences(c.Id, null, fromConnection);
    AXF_OBJ_BankAccount__c b = AXF_CLS_PluggyTestData.bankAccount(
      c.Id,
      'ACC-OV',
      false
    );
    new ALT_CLS_SourceHolderConfirmation()
      .confirmHolder(confirmInput(b.Id, 'BANK', confirmed, 0));

    Test.startTest();
    ALT_CLS_SourceHolderConfirmation.Overview o = new ALT_CLS_SourceHolderConfirmation()
      .overview();
    Test.stopTest();

    System.assertEquals(
      1,
      o.divergent.size(),
      'the confirmed holder differs from the connection holder'
    );
    System.assertEquals(
      confirmed,
      o.divergent[0].holderId,
      'the confirmed holder is what the source keeps'
    );
  }

  /**
   * @description Discovery is authorized but the ownership application is not: nothing is
   * written and the summary says so instead of reporting a released source.
   */
  @IsTest
  static void discoveryReportsForbiddenApplicationWithoutWriting() {
    AXF_OBJ_PluggyConnection__c c = AXF_CLS_PluggyTestData.connection(
      'ITEM_FORBIDDEN'
    );
    AXF_OBJ_BankInstitution__c inst = bank('077', 'Banco Inter');
    insert inst;
    Id holder = holderId();
    svc().updateReferences(c.Id, inst.Id, holder);
    AXF_CLS_PluggyDiscoveryService.canDiscoverOverride = true;
    ALT_CLS_SourceHolderConfirmation.canConfigureOverride = false;
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());

    Test.startTest();
    AXF_CLS_PluggyDiscoveryService.DiscoveryResult r = new AXF_CLS_PluggyDiscoveryService()
      .startOrResume(c.Id);
    Test.stopTest();

    System.assertEquals('SUCCEEDED', r.state, r.message);
    System.assertEquals(0, r.released, r.message);
    System.assertEquals(0, r.applied, r.message);
    System.assert(
      r.message.containsIgnoreCase('autoriza'),
      'the refusal is stated: ' + r.message
    );
    System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_AccountHolder__c]);
    System.assertEquals(
      'CUSTODY',
      discoveredBank(c.Id).AXF_BA_PKL_AvailabilityState__c,
      'an unauthorized application never releases'
    );
  }
}
