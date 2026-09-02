/**
 * @description Tests for AXF_CLS_CTRL_CompanyResponsible (AXF-83): the controller
 * only delegates and runs the account search.
 */
@IsTest(isParallel=false)
private class AXF_CLS_CTRL_CompanyResponsibleTest {
  private static void allow() {
    ALT_CLS_AxonCompanyResponsible.canConfigureOverride = true;
    AXF_CLS_CTRL_CompanyResponsible.canConfigureOverride = true;
  }

  private static Id rt(String dev) {
    return Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
      .getRecordTypeInfosByDeveloperName()
      .get(dev)
      .getRecordTypeId();
  }

  @IsTest
  static void canConfigureReflectsCaller() {
    AXF_CLS_CTRL_CompanyResponsible.canConfigureOverride = false;
    System.assertEquals(false, AXF_CLS_CTRL_CompanyResponsible.canConfigure());
    AXF_CLS_CTRL_CompanyResponsible.canConfigureOverride = true;
    System.assertEquals(true, AXF_CLS_CTRL_CompanyResponsible.canConfigure());
  }

  @IsTest
  static void findAccountsFiltersByRecordType() {
    allow();
    insert new Account(
      Name = 'Acme Comercio',
      RecordTypeId = rt('AXF_Business')
    );
    insert new Account(
      LastName = 'Acme Pessoa',
      RecordTypeId = rt('AXF_Person')
    );
    Test.startTest();
    List<AXF_CLS_CTRL_CompanyResponsible.AccountOption> biz = AXF_CLS_CTRL_CompanyResponsible.findAccounts(
      'Acme',
      'BUSINESS'
    );
    List<AXF_CLS_CTRL_CompanyResponsible.AccountOption> ppl = AXF_CLS_CTRL_CompanyResponsible.findAccounts(
      'Acme',
      'PERSON'
    );
    Test.stopTest();
    System.assertEquals(1, biz.size());
    System.assertEquals('Acme Comercio', biz[0].name);
    System.assertEquals(1, ppl.size());
  }

  @IsTest
  static void findAccountsRejectsUnsafeEnumerationAndSupportsApostrophe() {
    allow();
    insert new Account(
      Name = 'Comércio D\'Ávila',
      RecordTypeId = rt('AXF_Business')
    );
    System.assertEquals(
      0,
      AXF_CLS_CTRL_CompanyResponsible.findAccounts(null, 'BUSINESS').size()
    );
    System.assertEquals(
      0,
      AXF_CLS_CTRL_CompanyResponsible.findAccounts(' ', 'BUSINESS').size()
    );
    System.assertEquals(
      0,
      AXF_CLS_CTRL_CompanyResponsible.findAccounts('x', 'BUSINESS').size()
    );
    System.assertEquals(
      0,
      AXF_CLS_CTRL_CompanyResponsible.findAccounts('D\'Á', null).size()
    );
    System.assertEquals(
      0,
      AXF_CLS_CTRL_CompanyResponsible.findAccounts('D\'Á', 'OTHER').size()
    );
    System.assertEquals(
      1,
      AXF_CLS_CTRL_CompanyResponsible.findAccounts('D\'Á', 'BUSINESS').size()
    );
    for (String wildcard : new List<String>{ '%', '_', '\\', '%%', '__' }) {
      System.assertEquals(
        0,
        AXF_CLS_CTRL_CompanyResponsible.findAccounts(wildcard, 'BUSINESS')
          .size(),
        'wildcards must never enumerate Accounts'
      );
    }
  }

  @IsTest
  static void delegatesConfirmGetAndRevoke() {
    allow();
    Account b = new Account(
      Name = 'Empresa Ctrl',
      RecordTypeId = rt('AXF_Business')
    );
    insert b;
    Account p = new Account(
      LastName = 'Pessoa Ctrl',
      RecordTypeId = rt('AXF_Person')
    );
    insert p;

    ALT_CLS_AxonCompanyResponsible.ConfirmInput input = new ALT_CLS_AxonCompanyResponsible.ConfirmInput();
    input.businessId = b.Id;
    input.personId = p.Id;
    input.role = 'PARTNER';

    Test.startTest();
    ALT_CLS_AxonCompanyResponsible.ResponsibilityView v = AXF_CLS_CTRL_CompanyResponsible.confirmResponsibility(
      input
    );
    System.assertEquals('RELATIONSHIP_ONLY', v.outcome);

    List<ALT_CLS_AxonCompanyResponsible.ResponsibilityView> rows = AXF_CLS_CTRL_CompanyResponsible.getResponsibilities(
      b.Id
    );
    System.assertEquals(1, rows.size());

    ALT_CLS_AxonCompanyResponsible.ResponsibilityView r = AXF_CLS_CTRL_CompanyResponsible.revokeResponsibility(
      v.craId,
      rows[0].version
    );
    Test.stopTest();
    System.assertEquals('REVOKED', r.outcome);
  }

  @IsTest
  static void forbiddenWithoutAuthority() {
    AXF_CLS_CTRL_CompanyResponsible.canConfigureOverride = false;
    ALT_CLS_AxonCompanyResponsible.canConfigureOverride = false;
    Test.startTest();
    System.assertEquals(
      0,
      AXF_CLS_CTRL_CompanyResponsible.findAccounts('x', 'BUSINESS').size()
    );
    ALT_CLS_AxonCompanyResponsible.ConfirmInput input = new ALT_CLS_AxonCompanyResponsible.ConfirmInput();
    input.businessId = null;
    System.assertEquals(
      'FORBIDDEN',
      AXF_CLS_CTRL_CompanyResponsible.confirmResponsibility(input).outcome
    );
    Test.stopTest();
  }
}
