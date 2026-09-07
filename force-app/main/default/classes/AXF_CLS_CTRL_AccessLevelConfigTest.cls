/**
 * @description Tests for AXF_CLS_CTRL_AccessLevelConfig: authorized vs forbidden listing,
 * DTO shape and the apply round-trip returning the recalculated current level. Uses the
 * canConfigureOverride seams on both the controller and the service. AXF-7.
 */
@IsTest
private class AXF_CLS_CTRL_AccessLevelConfigTest {
  private static User buildStandardUser() {
    Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
    String unique = 'axf7c' + String.valueOf(Datetime.now().getTime()) + Crypto.getRandomInteger();
    return new User(
      FirstName = 'Axon',
      LastName = 'CtrlTester',
      Alias = 'axf7c',
      Email = unique + '@axon.test',
      Username = unique + '@axon.test',
      ProfileId = p.Id,
      TimeZoneSidKey = 'America/Sao_Paulo',
      LocaleSidKey = 'pt_BR',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'pt_BR'
    );
  }

  private static void calculateGroups() {
    for (PermissionSetGroup psg : [
      SELECT Id, Status
      FROM PermissionSetGroup
      WHERE DeveloperName IN :new Set<String>{ 'AXF_PSG_GestorFinanceiro', 'AXF_PSG_Participante' }
    ]) {
      if (psg.Status != 'Updated') {
        Test.calculatePermissionSetGroup(psg.Id);
      }
    }
  }

  private static void authorize() {
    AXF_CLS_CTRL_AccessLevelConfig.canConfigureOverride = true;
    ALT_CLS_AxonAccessProvisioning.canConfigureOverride = true;
  }

  @IsTest
  static void canConfigureReflectsOverride() {
    AXF_CLS_CTRL_AccessLevelConfig.canConfigureOverride = false;
    System.assertEquals(false, AXF_CLS_CTRL_AccessLevelConfig.canConfigure(), 'forbidden');
    AXF_CLS_CTRL_AccessLevelConfig.canConfigureOverride = true;
    System.assertEquals(true, AXF_CLS_CTRL_AccessLevelConfig.canConfigure(), 'allowed');
  }

  @IsTest
  static void getEligibleUsersReturnsEmptyWhenForbidden() {
    AXF_CLS_CTRL_AccessLevelConfig.canConfigureOverride = false;
    System.assertEquals(
      0,
      AXF_CLS_CTRL_AccessLevelConfig.getEligibleUsers().size(),
      'forbidden -> empty list, not an exception'
    );
  }

  @IsTest
  static void getEligibleUsersListsUsersWithLevels() {
    authorize();
    User target = buildStandardUser();
    insert target;
    calculateGroups();

    Test.startTest();
    new ALT_CLS_AxonAccessProvisioning()
      .applyAccessLevel(target.Id, ALT_CLS_AxonAccessProvisioning.Tier.GESTOR);
    List<AXF_CLS_CTRL_AccessLevelConfig.UserAccessDTO> rows = AXF_CLS_CTRL_AccessLevelConfig.getEligibleUsers();
    Test.stopTest();

    Boolean sawTarget = false;
    for (AXF_CLS_CTRL_AccessLevelConfig.UserAccessDTO row : rows) {
      if (row.userId == target.Id) {
        sawTarget = true;
        System.assertEquals(ALT_CLS_AxonAccessProvisioning.LEVEL_GESTOR, row.currentLevel, 'level reported');
        System.assertEquals(target.Username, row.username, 'username on DTO');
        System.assertEquals(true, row.isActive, 'active flag');
      }
    }
    System.assert(sawTarget, 'target user present in the list');
  }

  @IsTest
  static void applyAccessLevelRoundTrip() {
    authorize();
    User target = buildStandardUser();
    insert target;
    calculateGroups();

    Test.startTest();
    AXF_CLS_CTRL_AccessLevelConfig.ApplyResultDTO out = AXF_CLS_CTRL_AccessLevelConfig.applyAccessLevel(
      target.Id,
      'participante'
    );
    Test.stopTest();

    System.assertEquals('SUCCEEDED', out.outcome, 'apply succeeds');
    System.assertEquals('participante', out.level, 'echoes requested level');
    System.assertEquals(ALT_CLS_AxonAccessProvisioning.LEVEL_PARTICIPANTE, out.currentLevel, 'recalculated level');
  }

  @IsTest
  static void applyAccessLevelRejectsGarbageLevel() {
    authorize();
    User target = buildStandardUser();
    insert target;

    Test.startTest();
    AXF_CLS_CTRL_AccessLevelConfig.ApplyResultDTO out = AXF_CLS_CTRL_AccessLevelConfig.applyAccessLevel(
      target.Id,
      'superadmin'
    );
    Test.stopTest();

    System.assertEquals('FAILED', out.outcome, 'unknown level -> FAILED');
  }

  @IsTest
  static void applyAccessLevelForbiddenWithoutAuthority() {
    AXF_CLS_CTRL_AccessLevelConfig.canConfigureOverride = true;
    ALT_CLS_AxonAccessProvisioning.canConfigureOverride = false;
    User target = buildStandardUser();
    insert target;

    Test.startTest();
    AXF_CLS_CTRL_AccessLevelConfig.ApplyResultDTO out = AXF_CLS_CTRL_AccessLevelConfig.applyAccessLevel(
      target.Id,
      'gestor'
    );
    Test.stopTest();

    System.assertEquals('FORBIDDEN', out.outcome, 'service authority is enforced');
  }
}
