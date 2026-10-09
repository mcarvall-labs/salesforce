/**
 * @description Test helper: creates a System Administrator with CRUD and FLS on every permissionable
 * field of the given Axon objects through a permission set, so syncs can be exercised under
 * System.runAs. Edit is always granted: describe reports fields as read-only for the running
 * user until FLS exists.
 */
@IsTest
public class ALT_CLS_SyncTestUser {
  public static User create(String alias, List<String> objectNames) {
    return create(alias, objectNames, UserInfo.getUserId());
  }

  // Same permission set, assigned to the given user (for example a restricted one, to exercise
  // sharing and enforcement).
  public static User create(
    String alias,
    List<String> objectNames,
    Id assigneeId
  ) {
    PermissionSet ps = new PermissionSet(
      Label = 'Sync Test ' + alias,
      Name = 'AXF_SyncTest_' + alias
    );
    insert ps;
    List<ObjectPermissions> objects = new List<ObjectPermissions>();
    List<FieldPermissions> fields = new List<FieldPermissions>();
    for (String objectName : objectNames) {
      objects.add(
        new ObjectPermissions(
          ParentId = ps.Id,
          SobjectType = objectName,
          PermissionsCreate = true,
          PermissionsRead = true,
          PermissionsEdit = true,
          PermissionsDelete = true
        )
      );
      for (
        Schema.SObjectField field : Schema.getGlobalDescribe()
          .get(objectName)
          .getDescribe()
          .fields.getMap()
          .values()
      ) {
        Schema.DescribeFieldResult describe = field.getDescribe();
        if (describe.isCustom() && describe.isPermissionable()) {
          fields.add(
            new FieldPermissions(
              ParentId = ps.Id,
              SobjectType = objectName,
              Field = objectName + '.' + describe.getName(),
              PermissionsRead = true,
              PermissionsEdit = !describe.isCalculated()
            )
          );
        }
      }
    }
    insert objects;
    insert fields;
    insert new PermissionSetAssignment(
      AssigneeId = assigneeId,
      PermissionSetId = ps.Id
    );
    return new User(Id = assigneeId);
  }
}
