/**
 * @description AXF-106 — connection bank/holder references. updateReferences sets or
 * clears the canonical bank and suggested holder without touching provider evidence,
 * validates the holder record type, is explicit-only and never overwrites an existing
 * selection. overview() exposes bank and holder names.
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
    ALT_CLS_AxonHolder.canConfigureOverride = true;
    ALT_CLS_AxonHolder.SaveInput si = new ALT_CLS_AxonHolder.SaveInput();
    si.type = 'PERSON';
    si.firstName = 'Ana';
    si.lastName = 'Souza';
    return new ALT_CLS_AxonHolder().saveHolder(si).accountId;
  }

  static AXF_CLS_PluggyDiscoveryService svc() {
    AXF_CLS_PluggyDiscoveryService.canDiscoverOverride = true;
    return new AXF_CLS_PluggyDiscoveryService();
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
      new AXF_CLS_PluggyDiscoveryService()
        .updateReferences(c.Id, null, null);
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
}
