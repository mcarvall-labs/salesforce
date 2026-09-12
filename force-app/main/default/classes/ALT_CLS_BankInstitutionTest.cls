/**
 * @description AXF-106 — canonical Financial Institution directory creation.
 * Grants the real Gestor permission set so the service's USER_MODE reads/writes are
 * exercised with effective CRUD/FLS, not with an override.
 */
@IsTest(isParallel=false)
private class ALT_CLS_BankInstitutionTest {
  @TestSetup
  static void grantRealCrudAndFls() {
    Id permissionSetId = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'AXF_PS_GestorFinanceiro'
      LIMIT 1
    ]
    .Id;
    if (
      [
        SELECT COUNT()
        FROM PermissionSetAssignment
        WHERE
          AssigneeId = :UserInfo.getUserId()
          AND PermissionSetId = :permissionSetId
      ] == 0
    ) {
      insert new PermissionSetAssignment(
        AssigneeId = UserInfo.getUserId(),
        PermissionSetId = permissionSetId
      );
    }
  }

  private static ALT_CLS_BankInstitution.SaveInput input(
    String name,
    String bankNumber
  ) {
    ALT_CLS_BankInstitution.SaveInput i = new ALT_CLS_BankInstitution.SaveInput();
    i.name = name;
    i.bankNumber = bankNumber;
    return i;
  }

  @IsTest
  static void createsAndIsIdempotentOnBankNumber() {
    ALT_CLS_BankInstitution.canConfigureOverride = true;
    ALT_CLS_BankInstitution svc = new ALT_CLS_BankInstitution();

    Test.startTest();
    ALT_CLS_BankInstitution.SaveResult created = svc.save(
      input('Nubank', '260')
    );
    ALT_CLS_BankInstitution.SaveResult again = svc.save(
      input('Nubank renomeado', '260')
    );
    Test.stopTest();

    System.assertEquals(
      'CREATED',
      created.outcome,
      created.message + ' / ' + ALT_CLS_BankInstitution.lastFailure
    );
    System.assertNotEquals(null, created.institutionId, 'id returned');
    System.assertEquals(
      'ALREADY',
      again.outcome,
      'the bank number is the external identity — never duplicates'
    );
    System.assertEquals(
      created.institutionId,
      again.institutionId,
      'replay returns the existing record'
    );
    System.assertEquals(1, [SELECT COUNT() FROM AXF_OBJ_BankInstitution__c]);
    AXF_OBJ_BankInstitution__c saved = [
      SELECT Name, AXF_BI_EXI_Bank_Number__c
      FROM AXF_OBJ_BankInstitution__c
      WHERE Id = :created.institutionId
    ];
    System.assertEquals('Nubank', saved.Name, 'replay never renames');
    System.assertEquals('260', saved.AXF_BI_EXI_Bank_Number__c);
  }

  @IsTest
  static void requiresNameAndBankNumber() {
    ALT_CLS_BankInstitution.canConfigureOverride = true;
    ALT_CLS_BankInstitution svc = new ALT_CLS_BankInstitution();

    System.assertEquals('INVALID', svc.save(null).outcome, 'no input');
    System.assertEquals(
      'INVALID',
      svc.save(input(null, '001')).outcome,
      'name required'
    );
    System.assertEquals(
      'INVALID',
      svc.save(input('Banco sem codigo', null)).outcome,
      'bank number required'
    );
    System.assertEquals(
      'INVALID',
      svc.save(input('Banco', '123456789')).outcome,
      'bank number too long'
    );
    System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_BankInstitution__c]);
  }

  @IsTest
  static void forbiddenWithoutAuthorityCreatesNothing() {
    ALT_CLS_BankInstitution.canConfigureOverride = false;
    ALT_CLS_BankInstitution.SaveResult r = new ALT_CLS_BankInstitution()
      .save(input('Bloqueado', '111'));
    System.assertEquals('FORBIDDEN', r.outcome);
    System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_BankInstitution__c]);
  }
}
