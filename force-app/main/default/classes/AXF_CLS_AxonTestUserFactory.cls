/**
 * @description Shared test users for the Axon Configuration tests. Profile
 * lookups are locale-independent (the org may run in pt_BR) and Account record
 * types are exercised through a provisioned user (Standard profile + the real
 * AXF_PSG_GestorFinanceiro), because record type availability is enforced on
 * DML even in system mode and the org's admin profile is not guaranteed to have
 * the Axon Account record types assigned.
 */
@IsTest
public class AXF_CLS_AxonTestUserFactory {
  private static final Set<String> AXON_GROUPS = new Set<String>{
    'AXF_PSG_GestorFinanceiro',
    'AXF_PSG_Participante'
  };
  private static User cachedRecordTypeUser;
  private static Boolean axonGroupsCalculated = false;

  /**
   * Recalculates both Axon permission set groups once per test transaction.
   * When the groups are (re)defined by the same deploy that runs the tests,
   * their Status is not 'Updated' yet: permission set assignments are refused
   * and ALT_CLS_AxonAccessProvisioning reports the group as recalculating. The
   * Status read can also be stale, so the recalculation is unconditional.
   * Call it before Test.startTest().
   */
  public static void recalculateAxonGroups() {
    if (axonGroupsCalculated) {
      return;
    }
    for (PermissionSetGroup psg : [
      SELECT Id
      FROM PermissionSetGroup
      WHERE DeveloperName IN :AXON_GROUPS
    ]) {
      Test.calculatePermissionSetGroup(psg.Id);
    }
    axonGroupsCalculated = true;
  }

  /** @return the standard "Standard User" profile Id in en_US or pt_BR orgs. */
  public static Id standardProfileId() {
    return [
      SELECT Id
      FROM Profile
      WHERE
        UserType = 'Standard'
        AND Name IN ('Standard User', 'Usuário Padrão')
      LIMIT 1
    ]
    .Id;
  }

  /**
   * @return a cached Standard user carrying AXF_PSG_GestorFinanceiro (no role),
   * which has visibility of Account.AXF_Business and PersonAccount.
   */
  public static User recordTypeUser() {
    if (cachedRecordTypeUser != null) {
      return cachedRecordTypeUser;
    }
    recalculateAxonGroups();
    PermissionSetGroup psg = [
      SELECT Id
      FROM PermissionSetGroup
      WHERE DeveloperName = 'AXF_PSG_GestorFinanceiro'
      LIMIT 1
    ];
    User u = new User(
      ProfileId = standardProfileId(),
      LastName = 'Axon RT Owner',
      Email = 'axf.rtowner@example.com',
      Username = 'axf.rtowner.' +
        Crypto.getRandomInteger() +
        '@example.com.invalid',
      Alias = 'axfrto',
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
    cachedRecordTypeUser = u;
    return u;
  }

  /** Inserts records as {@link #recordTypeUser()} so Axon record types are valid. */
  public static void insertWithRecordTypeAccess(List<SObject> records) {
    System.runAs(recordTypeUser()) {
      insert records;
    }
  }
}
