/**
 * @description Controller exclusivo do LWC aXF_LWC_sharedExpense (AXF-6). Erros sanitizados
 * como {code}: nunca stack trace, PII ou existencia de registros nao autorizados.
 */
public with sharing class AXF_CLS_CTRL_SharedExpense {
  public class Capabilities {
    @AuraEnabled
    public Boolean canShare;
    @AuraEnabled
    public Boolean canCollaborate;
  }

  public class CollaboratorOption {
    @AuraEnabled
    public Id userId;
    @AuraEnabled
    public String name;
  }

  @AuraEnabled(cacheable=true)
  public static Capabilities getCapabilities() {
    Capabilities result = new Capabilities();
    result.canShare = FeatureManagement.checkPermission(
      ALT_CLS_SharedExpenseService.CP_SHARE
    );
    result.canCollaborate = FeatureManagement.checkPermission(
      ALT_CLS_SharedExpenseService.CP_COLLABORATE
    );
    return result;
  }

  /** Eligible collaborators: active users assigned to the Participante permission set group. */
  @AuraEnabled(cacheable=true)
  public static List<CollaboratorOption> getCollaborators() {
    try {
      Map<Id, CollaboratorOption> result = new Map<Id, CollaboratorOption>();
      for (PermissionSetAssignment assignment : [
        SELECT AssigneeId, Assignee.Name, Assignee.IsActive
        FROM PermissionSetAssignment
        WHERE
          PermissionSetGroup.DeveloperName = 'AXF_PSG_Participante'
          AND Assignee.IsActive = TRUE
          AND AssigneeId != :UserInfo.getUserId()
        WITH USER_MODE
        ORDER BY Assignee.Name
        LIMIT 200
      ]) {
        CollaboratorOption option = new CollaboratorOption();
        option.userId = assignment.AssigneeId;
        option.name = assignment.Assignee.Name;
        result.put(option.userId, option);
      }
      return result.values();
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static List<ALT_CLS_SharedExpenseService.GrantView> getGrants(
    Id financialTransactionId
  ) {
    try {
      return new ALT_CLS_SharedExpenseService()
        .listGrants(financialTransactionId);
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_SharedExpenseService.GrantView share(String request) {
    try {
      return new ALT_CLS_SharedExpenseService()
        .share(
          (ALT_CLS_SharedExpenseService.GrantInput) JSON.deserializeStrict(
            request,
            ALT_CLS_SharedExpenseService.GrantInput.class
          )
        );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_SharedExpenseService.GrantView revoke(
    Id grantId,
    Decimal expectedVersion
  ) {
    try {
      return new ALT_CLS_SharedExpenseService()
        .revoke(grantId, expectedVersion);
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static List<ALT_CLS_SharedExpenseService.SharedView> listShared() {
    try {
      return new ALT_CLS_SharedExpenseService().listShared();
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_SharedExpenseService.SharedView readShared(
    Id financialTransactionId
  ) {
    try {
      return new ALT_CLS_SharedExpenseService()
        .readShared(financialTransactionId);
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_SharedExpenseService.SharedView updateShared(
    String request
  ) {
    try {
      return new ALT_CLS_SharedExpenseService()
        .updateShared(
          (ALT_CLS_SharedExpenseService.UpdateInput) JSON.deserializeStrict(
            request,
            ALT_CLS_SharedExpenseService.UpdateInput.class
          )
        );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static Id confirmRealization(String request) {
    try {
      return new ALT_CLS_SharedExpenseService()
        .confirmRealization(
          (ALT_CLS_SharedExpenseService.RealizeInput) JSON.deserializeStrict(
            request,
            ALT_CLS_SharedExpenseService.RealizeInput.class
          )
        );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  private static AuraHandledException safe(Exception failure) {
    String code = 'UNEXPECTED';
    if (
      failure instanceof ALT_CLS_SharedExpenseService.SharedExpenseException
    ) {
      code = ((ALT_CLS_SharedExpenseService.SharedExpenseException) failure)
        .code;
    } else if (failure instanceof JSONException) {
      code = 'INVALID_INPUT';
    } else if (
      failure instanceof System.QueryException ||
      failure instanceof System.SecurityException ||
      failure instanceof System.NoAccessException
    ) {
      code = 'NOT_ACCESSIBLE';
    } else if (failure instanceof DmlException) {
      code = 'REJECTED';
    }
    AuraHandledException result = new AuraHandledException(code);
    result.setMessage(code);
    return result;
  }
}
