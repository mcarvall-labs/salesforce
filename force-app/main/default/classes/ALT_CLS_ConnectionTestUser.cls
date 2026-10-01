/**
 * @description Test helper: creates a Standard User with CRUD/FLS on
 * AXF_OBJ_PluggyConnection__c through a permission set, so user-mode reads and
 * writes can be exercised under System.runAs.
 */
@IsTest
public class ALT_CLS_ConnectionTestUser {
  public static User create(String alias) {
    PermissionSet ps = new PermissionSet(
      Label = 'Connection Test ' + alias,
      Name = 'AXF_ConnectionTest_' + alias
    );
    insert ps;
    insert new ObjectPermissions(
      ParentId = ps.Id,
      SobjectType = 'AXF_OBJ_PluggyConnection__c',
      PermissionsCreate = true,
      PermissionsRead = true,
      PermissionsEdit = true,
      PermissionsDelete = true
    );
    List<FieldPermissions> fields = new List<FieldPermissions>();
    for (
      String field : new List<String>{
        'AXF_CON_EXI_PluggyItemId__c',
        'AXF_CON_PKL_Status__c',
        'AXF_CON_DT_LastSyncDatetime__c',
        'AXF_CON_TAL_SyncErrorMessage__c'
      }
    ) {
      fields.add(
        new FieldPermissions(
          ParentId = ps.Id,
          SobjectType = 'AXF_OBJ_PluggyConnection__c',
          Field = 'AXF_OBJ_PluggyConnection__c.' + field,
          PermissionsRead = true,
          PermissionsEdit = true
        )
      );
    }
    insert fields;
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
    insert new PermissionSetAssignment(
      AssigneeId = u.Id,
      PermissionSetId = ps.Id
    );
    return u;
  }
}
