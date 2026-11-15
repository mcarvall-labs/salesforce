/**
 * @description Test helper for Axon access: creates a Standard User holding the Axon
 * permission sets (Configuração and Usuário), so user-mode reads and writes run with
 * the same access as a real user, and grants the same sets to any user (for example the
 * deploy user, which has no Axon access in production). The permission sets come from
 * the deployed metadata; only their assignments are inserted.
 */
@IsTest
public class ALT_CLS_ConnectionTestUser {
  // The standard profile is named per org language: 'Standard User' (en) or 'Usuário Padrão' (pt-BR, UAT).
  public static Id standardProfileId() {
    return [
      SELECT Id
      FROM Profile
      WHERE Name IN ('Standard User', 'Usuário Padrão')
      LIMIT 1
    ]
    .Id;
  }

  public static User create(String alias) {
    User u = new User(
      Alias = alias,
      Email = alias + '@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = alias,
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = standardProfileId(),
      TimeZoneSidKey = 'America/Sao_Paulo',
      Username = alias + System.currentTimeMillis() + '@example.com'
    );
    insert u;
    grantAxonAccess(u.Id);
    return u;
  }

  /**
   * @description Assigns AXF_PS_Usuario and AXF_PS_Configuracao to the given user,
   * skipping a permission set the user already holds directly (no DUPLICATE in orgs
   * where the admin already has it). For the running user, the access only applies
   * inside a System.runAs opened after this call. It inserts setup objects, so call it
   * before any non-setup DML of the transaction (typically in @TestSetup).
   */
  public static void grantAxonAccess(Id userId) {
    Set<String> names = new Set<String>{
      'AXF_PS_Configuracao',
      'AXF_PS_Usuario'
    };
    Map<Id, PermissionSet> sets = new Map<Id, PermissionSet>(
      [SELECT Id FROM PermissionSet WHERE Name IN :names]
    );
    Assert.areEqual(
      names.size(),
      sets.size(),
      'Axon permission sets must exist: ' + names
    );
    for (PermissionSetAssignment existing : [
      SELECT PermissionSetId
      FROM PermissionSetAssignment
      WHERE
        AssigneeId = :userId
        AND PermissionSetGroupId = NULL
        AND PermissionSetId IN :sets.keySet()
    ]) {
      sets.remove(existing.PermissionSetId);
    }
    List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (Id psId : sets.keySet()) {
      assignments.add(
        new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = psId)
      );
    }
    insert assignments;
  }

  public static User find(String alias) {
    return [SELECT Id FROM User WHERE Alias = :alias LIMIT 1];
  }

  @IsTest
  static void grantingAgainAssignsEachAxonSetOnceDirectly() {
    User u = create('axfgrnt');
    grantAxonAccess(u.Id);
    System.assertEquals(
      2,
      [
        SELECT COUNT()
        FROM PermissionSetAssignment
        WHERE
          AssigneeId = :u.Id
          AND PermissionSetGroupId = NULL
          AND PermissionSet.Name IN ('AXF_PS_Configuracao', 'AXF_PS_Usuario')
      ]
    );
  }
}
