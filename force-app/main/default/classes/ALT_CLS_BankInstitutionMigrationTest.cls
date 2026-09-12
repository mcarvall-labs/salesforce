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
}
