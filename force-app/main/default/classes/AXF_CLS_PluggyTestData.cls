/**
 * @description Shared builders for the AXF-11 Pluggy tests. Grants the running user the
 * integration permission set so the services' USER_MODE queries/DML pass FLS on the
 * freshly deployed AXF_OBJ_PluggyConnection__c fields.
 */
@IsTest
public class AXF_CLS_PluggyTestData {
  public static void grantIntegrationAccess() {
    PermissionSet ps = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'AXF_PS_PluggyIntegration'
      LIMIT 1
    ];
    Id uid = UserInfo.getUserId();
    Integer existing = [
      SELECT COUNT()
      FROM PermissionSetAssignment
      WHERE AssigneeId = :uid AND PermissionSetId = :ps.Id
    ];
    if (existing > 0) {
      return;
    }
    User u = new User(Id = uid);
    System.runAs(u) {
      insert new PermissionSetAssignment(
        AssigneeId = uid,
        PermissionSetId = ps.Id
      );
    }
  }

  public static AXF_OBJ_PluggyConnection__c connection(String itemId) {
    grantIntegrationAccess();
    AXF_OBJ_PluggyConnection__c c = new AXF_OBJ_PluggyConnection__c(
      AXF_CON_EXI_PluggyItemId__c = itemId,
      AXF_CON_PKL_ConsentState__c = 'ACTIVE',
      AXF_CON_PKL_CollectionState__c = 'ACTIVE',
      AXF_CON_TXT_InstitutionName__c = 'Test Bank'
    );
    insert c;
    return c;
  }

  public static void config(
    Boolean globalPaused,
    String activeSlot,
    String rotationState
  ) {
    insert new AXF_PluggyIntegrationConfig__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      AXF_PIC_BOL_CollectionGloballyPaused__c = globalPaused,
      AXF_PIC_BOL_WebhookEnabled__c = true,
      AXF_PIC_TXT_ActiveSlot__c = activeSlot,
      AXF_PIC_TXT_RotationState__c = rotationState
    );
  }
}
