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
  private static User cachedRecordTypeUser;

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
