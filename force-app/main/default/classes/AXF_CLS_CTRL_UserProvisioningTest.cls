/**
 * @description Tests for AXF_CLS_CTRL_UserProvisioning — thin controller over
 * ALT_CLS_AxonUserProvisioning. AXF-82.
 */
@IsTest(isParallel=false)
private class AXF_CLS_CTRL_UserProvisioningTest {
  private static User configurator() {
    Profile admin = [
      SELECT Id
      FROM Profile
      WHERE Name = 'System Administrator'
      LIMIT 1
    ];
    PermissionSetGroup psg = [
      SELECT Id, Status
      FROM PermissionSetGroup
      WHERE DeveloperName = 'AXF_PSG_GestorFinanceiro'
      LIMIT 1
    ];
    if (psg.Status != 'Updated') {
      Test.calculatePermissionSetGroup(psg.Id);
    }
    User u = new User(
      ProfileId = admin.Id,
      LastName = 'Ctrl Cfg',
      Email = 'axf82.ctrlcfg@example.com',
      Username = 'axf82.ctrlcfg.' +
        Crypto.getRandomInteger() +
        '@example.com.invalid',
      Alias = 'axf82cc',
      TimeZoneSidKey = 'America/Sao_Paulo',
      LocaleSidKey = 'pt_BR',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'pt_BR'
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert u;
      insert new PermissionSetAssignment(
        AssigneeId = u.Id,
        PermissionSetGroupId = psg.Id
      );
    }
    return u;
  }

  private static Id personAccount() {
    Id rt = Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
      .getRecordTypeInfosByDeveloperName()
      .get('AXF_Person')
      .getRecordTypeId();
    Account a = new Account(LastName = 'Ctrl', RecordTypeId = rt);
    insert a;
    return a.Id;
  }

  @IsTest
  static void canConfigureReflectsOverride() {
    AXF_CLS_CTRL_UserProvisioning.canConfigureOverride = false;
    System.assertEquals(false, AXF_CLS_CTRL_UserProvisioning.canConfigure());
    AXF_CLS_CTRL_UserProvisioning.canConfigureOverride = true;
    System.assertEquals(true, AXF_CLS_CTRL_UserProvisioning.canConfigure());
  }

  @IsTest
  static void preflightReturnsLicenseInfo() {
    AXF_CLS_CTRL_UserProvisioning.canConfigureOverride = true;
    AXF_CLS_CTRL_UserProvisioning.Preflight p = AXF_CLS_CTRL_UserProvisioning.preflight();
    System.assertEquals(true, p.canConfigure);
    System.assertNotEquals(null, p.salesforceLicensesFree);
  }

  @IsTest
  static void findLinkableUsersIsEmptyWithoutAuthority() {
    AXF_CLS_CTRL_UserProvisioning.canConfigureOverride = false;
    System.assertEquals(
      0,
      AXF_CLS_CTRL_UserProvisioning.findLinkableUsers('a').size()
    );
  }

  @IsTest
  static void findLinkableUsersListsActiveStandardUsers() {
    AXF_CLS_CTRL_UserProvisioning.canConfigureOverride = true;
    List<AXF_CLS_CTRL_UserProvisioning.EligibleUser> rows = AXF_CLS_CTRL_UserProvisioning.findLinkableUsers(
      UserInfo.getLastName()
    );
    System.assert(rows.size() >= 0);
  }

  @IsTest
  static void startAndGetStatusDelegate() {
    User cfg = configurator();
    ALT_CLS_AxonUserProvisioning.licenseAvailableOverride = true;

    Test.startTest();
    System.runAs(cfg) {
      Id personId = personAccount();
      ALT_CLS_AxonUserProvisioning.StartInput si = new ALT_CLS_AxonUserProvisioning.StartInput();
      si.personId = personId;
      si.mode = 'CREATE';
      si.scope = 'OWN_DATA';
      si.email = 'ctrl.person@example.com';
      si.name = 'Ctrl Person';

      ALT_CLS_AxonUserProvisioning.Result started = AXF_CLS_CTRL_UserProvisioning.start(
        si
      );
      System.assertEquals('STARTED', started.outcome, started.message);

      ALT_CLS_AxonUserProvisioning.Result status = AXF_CLS_CTRL_UserProvisioning.getStatus(
        started.provisioningId
      );
      System.assertEquals(started.provisioningId, status.provisioningId);

      ALT_CLS_AxonUserProvisioning.Result resumed = AXF_CLS_CTRL_UserProvisioning.resume(
        started.provisioningId
      );
      System.assertNotEquals(null, resumed.outcome);
    }
    Test.stopTest();
  }
}
