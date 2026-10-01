/**
 * @description Test helper: creates a Standard User holding the Axon permission sets
 * (Configuração and Usuário), so user-mode reads and writes on
 * AXF_OBJ_PluggyConnection__c run with the same access as a real user. The permission
 * sets come from the deployed metadata, so no permission DML is needed.
 */
@IsTest
public class ALT_CLS_ConnectionTestUser {
  public static User create(String alias) {
    User u = new User(
      Alias = alias,
      Email = alias + '@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = alias,
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
      .Id,
      TimeZoneSidKey = 'America/Sao_Paulo',
      Username = alias + System.currentTimeMillis() + '@example.com'
    );
    insert u;
    List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (PermissionSet ps : [
      SELECT Id
      FROM PermissionSet
      WHERE Name IN ('AXF_PS_Configuracao', 'AXF_PS_Usuario')
    ]) {
      assignments.add(
        new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id)
      );
    }
    insert assignments;
    return u;
  }

  public static User find(String alias) {
    return [SELECT Id FROM User WHERE Alias = :alias LIMIT 1];
  }
}
