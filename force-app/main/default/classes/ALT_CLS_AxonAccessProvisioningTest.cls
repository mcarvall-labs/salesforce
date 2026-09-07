/**
 * @description Tests for ALT_CLS_AxonAccessProvisioning. Covers authority, invalid level,
 * missing/inactive user, happy path per tier, idempotency, tier switch and current-level
 * reporting. Uses the canConfigureOverride seam for the authority paths. AXF-7.
 */
@IsTest
private class ALT_CLS_AxonAccessProvisioningTest {
  private static final String GESTOR_ROLE = 'Axon_Gestor_Financeiro';
  private static final String GESTOR_PSG = 'AXF_PSG_GestorFinanceiro';
  private static final String PARTICIPANTE_PSG = 'AXF_PSG_Participante';

  private static User buildStandardUser() {
    Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
    String unique = 'axf7' + String.valueOf(Datetime.now().getTime()) + Crypto.getRandomInteger();
    return new User(
      FirstName = 'Axon',
      LastName = 'Tester',
      Alias = 'axf7t',
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
      WHERE DeveloperName IN :new Set<String>{ GESTOR_PSG, PARTICIPANTE_PSG }
    ]) {
      if (psg.Status != 'Updated') {
        Test.calculatePermissionSetGroup(psg.Id);
      }
    }
  }

  @IsTest
  static void parseLevelHandlesValidAndInvalid() {
    System.assertEquals(
      ALT_CLS_AxonAccessProvisioning.Tier.GESTOR,
      ALT_CLS_AxonAccessProvisioning.parseLevel('GESTOR'),
      'upper case should parse'
    );
    System.assertEquals(
      ALT_CLS_AxonAccessProvisioning.Tier.PARTICIPANTE,
      ALT_CLS_AxonAccessProvisioning.parseLevel('  participante '),
      'trimmed lower case should parse'
    );
    System.assertEquals(null, ALT_CLS_AxonAccessProvisioning.parseLevel('admin'), 'unknown -> null');
    System.assertEquals(null, ALT_CLS_AxonAccessProvisioning.parseLevel(null), 'null -> null');
    System.assertEquals(null, ALT_CLS_AxonAccessProvisioning.parseLevel('  '), 'blank -> null');
  }

  @IsTest
  static void forbiddenWhenCallerCannotConfigure() {
    ALT_CLS_AxonAccessProvisioning.canConfigureOverride = false;
    ALT_CLS_AxonAccessProvisioning.Result r = new ALT_CLS_AxonAccessProvisioning()
      .applyAccessLevel(UserInfo.getUserId(), ALT_CLS_AxonAccessProvisioning.Tier.GESTOR);
    System.assertEquals(
      ALT_CLS_AxonAccessProvisioning.Outcome.FORBIDDEN,
      r.outcome,
      'no AXF_CanConfigure -> FORBIDDEN'
    );
  }

  @IsTest
  static void invalidLevelIsRejected() {
    ALT_CLS_AxonAccessProvisioning.canConfigureOverride = true;
    ALT_CLS_AxonAccessProvisioning.Result r = new ALT_CLS_AxonAccessProvisioning()
      .applyAccessLevel(UserInfo.getUserId(), null);
    System.assertEquals(ALT_CLS_AxonAccessProvisioning.Outcome.FAILED, r.outcome, 'null level -> FAILED');
  }

  @IsTest
  static void missingUserIsRejected() {
    ALT_CLS_AxonAccessProvisioning.canConfigureOverride = true;
    Id fakeUserId = Id.valueOf('005000000000000AAA');
    ALT_CLS_AxonAccessProvisioning.Result r = new ALT_CLS_AxonAccessProvisioning()
      .applyAccessLevel(fakeUserId, ALT_CLS_AxonAccessProvisioning.Tier.GESTOR);
    System.assertEquals(ALT_CLS_AxonAccessProvisioning.Outcome.FAILED, r.outcome, 'unknown user -> FAILED');
  }

  @IsTest
  static void appliesGestorThenIsIdempotent() {
    ALT_CLS_AxonAccessProvisioning.canConfigureOverride = true;
    User u = buildStandardUser();
    insert u;
    calculateGroups();

    Test.startTest();
    ALT_CLS_AxonAccessProvisioning svc = new ALT_CLS_AxonAccessProvisioning();
    ALT_CLS_AxonAccessProvisioning.Result first = svc.applyAccessLevel(
      u.Id,
      ALT_CLS_AxonAccessProvisioning.Tier.GESTOR
    );
    ALT_CLS_AxonAccessProvisioning.Result second = svc.applyAccessLevel(
      u.Id,
      ALT_CLS_AxonAccessProvisioning.Tier.GESTOR
    );
    Test.stopTest();

    System.assertEquals(
      ALT_CLS_AxonAccessProvisioning.Outcome.SUCCEEDED,
      first.outcome,
      'first apply succeeds'
    );
    System.assertEquals(
      ALT_CLS_AxonAccessProvisioning.Outcome.ALREADY_APPLIED,
      second.outcome,
      'second apply is a no-op'
    );

    UserRole role = [SELECT Id FROM UserRole WHERE DeveloperName = :GESTOR_ROLE LIMIT 1];
    User after = [SELECT UserRoleId FROM User WHERE Id = :u.Id];
    System.assertEquals(role.Id, after.UserRoleId, 'role assigned');

    List<PermissionSetAssignment> psas = [
      SELECT PermissionSetGroup.DeveloperName
      FROM PermissionSetAssignment
      WHERE AssigneeId = :u.Id
      AND PermissionSetGroupId != NULL
    ];
    System.assertEquals(1, psas.size(), 'exactly one PSG');
    System.assertEquals(GESTOR_PSG, psas[0].PermissionSetGroup.DeveloperName, 'Gestor PSG assigned');
  }

  @IsTest
  static void switchesFromGestorToParticipante() {
    ALT_CLS_AxonAccessProvisioning.canConfigureOverride = true;
    User u = buildStandardUser();
    insert u;
    calculateGroups();

    Test.startTest();
    ALT_CLS_AxonAccessProvisioning svc = new ALT_CLS_AxonAccessProvisioning();
    svc.applyAccessLevel(u.Id, ALT_CLS_AxonAccessProvisioning.Tier.GESTOR);
    ALT_CLS_AxonAccessProvisioning.Result switched = svc.applyAccessLevel(
      u.Id,
      ALT_CLS_AxonAccessProvisioning.Tier.PARTICIPANTE
    );
    Test.stopTest();

    System.assertEquals(
      ALT_CLS_AxonAccessProvisioning.Outcome.SUCCEEDED,
      switched.outcome,
      'switch succeeds'
    );
    List<PermissionSetAssignment> psas = [
      SELECT PermissionSetGroup.DeveloperName
      FROM PermissionSetAssignment
      WHERE AssigneeId = :u.Id
      AND PermissionSetGroupId != NULL
    ];
    System.assertEquals(1, psas.size(), 'only one Axon PSG after switch');
    System.assertEquals(
      PARTICIPANTE_PSG,
      psas[0].PermissionSetGroup.DeveloperName,
      'Participante PSG assigned, Gestor removed'
    );
  }

  @IsTest
  static void inactiveUserIsRejected() {
    ALT_CLS_AxonAccessProvisioning.canConfigureOverride = true;
    User u = buildStandardUser();
    insert u;
    u.IsActive = false;
    update u;

    ALT_CLS_AxonAccessProvisioning.Result r = new ALT_CLS_AxonAccessProvisioning()
      .applyAccessLevel(u.Id, ALT_CLS_AxonAccessProvisioning.Tier.GESTOR);
    System.assertEquals(
      ALT_CLS_AxonAccessProvisioning.Outcome.FAILED,
      r.outcome,
      'inactive user -> FAILED'
    );
  }

  @IsTest
  static void currentLevelsReportsAssignedAndNone() {
    ALT_CLS_AxonAccessProvisioning.canConfigureOverride = true;
    User u = buildStandardUser();
    insert u;
    calculateGroups();

    ALT_CLS_AxonAccessProvisioning svc = new ALT_CLS_AxonAccessProvisioning();

    Test.startTest();
    Map<Id, String> before = svc.currentLevels(new Set<Id>{ u.Id });
    svc.applyAccessLevel(u.Id, ALT_CLS_AxonAccessProvisioning.Tier.PARTICIPANTE);
    Map<Id, String> after = svc.currentLevels(new Set<Id>{ u.Id });
    Test.stopTest();

    System.assertEquals(ALT_CLS_AxonAccessProvisioning.LEVEL_NONE, before.get(u.Id), 'no level before');
    System.assertEquals(ALT_CLS_AxonAccessProvisioning.LEVEL_PARTICIPANTE, after.get(u.Id), 'Participante after');
  }
}
