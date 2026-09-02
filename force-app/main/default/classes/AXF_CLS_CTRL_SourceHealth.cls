/**
 * @description Dedicated controller for aXF_LWC_sourceHealth ("Saude das fontes"),
 * desktop/mobile. AXF-11 AC7: shows institution, affected accounts, consent, last success,
 * impact and the permitted action. Never exposes a secret. PROJECT_RULES §3.
 */
public with sharing class AXF_CLS_CTRL_SourceHealth {
  @TestVisible
  private static Boolean canManageOverride;

  private static Boolean callerCanManage() {
    if (canManageOverride != null) {
      return canManageOverride;
    }
    return FeatureManagement.checkPermission('AXF_CanConfigure');
  }

  public class SourceDTO {
    @AuraEnabled
    public Id connectionId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String institution;
    @AuraEnabled
    public String consentState; // ACTIVE | STALE | REVOKED
    @AuraEnabled
    public String collectionState; // ACTIVE | PAUSED
    @AuraEnabled
    public Datetime consentExpiresAt;
    @AuraEnabled
    public Datetime lastSuccessAt;
    @AuraEnabled
    public String lastStatusCode;
    @AuraEnabled
    public String lastStatusDetail;
    @AuraEnabled
    public String impact; // human, sanitized
    @AuraEnabled
    public String permittedAction; // PAUSE | RESUME | REAUTHORIZE | NONE
    @AuraEnabled
    public Boolean canManage;
  }

  @AuraEnabled(cacheable=true)
  public static List<SourceDTO> getSources() {
    Boolean manage = callerCanManage();
    List<SourceDTO> out = new List<SourceDTO>();
    for (AXF_OBJ_PluggyConnection__c c : [
      SELECT
        Id,
        Name,
        AXF_CON_TXT_InstitutionName__c,
        AXF_CON_PKL_ConsentState__c,
        AXF_CON_PKL_CollectionState__c,
        AXF_CON_DT_ConsentExpiresAt__c,
        AXF_CON_DT_LastSuccessAt__c,
        AXF_CON_TXT_LastStatusCode__c,
        AXF_CON_TXT_LastStatusDetail__c
      FROM AXF_OBJ_PluggyConnection__c
      WITH USER_MODE
      ORDER BY AXF_CON_TXT_InstitutionName__c NULLS LAST
      LIMIT 200
    ]) {
      SourceDTO d = new SourceDTO();
      d.connectionId = c.Id;
      d.name = c.Name;
      d.institution = c.AXF_CON_TXT_InstitutionName__c;
      d.consentState = c.AXF_CON_PKL_ConsentState__c;
      d.collectionState = c.AXF_CON_PKL_CollectionState__c;
      d.consentExpiresAt = c.AXF_CON_DT_ConsentExpiresAt__c;
      d.lastSuccessAt = c.AXF_CON_DT_LastSuccessAt__c;
      d.lastStatusCode = c.AXF_CON_TXT_LastStatusCode__c;
      d.lastStatusDetail = c.AXF_CON_TXT_LastStatusDetail__c;
      d.canManage = manage;
      d.impact = impactText(c);
      d.permittedAction = permittedAction(c, manage);
      out.add(d);
    }
    return out;
  }

  @AuraEnabled
  public static void pauseConnection(Id connectionId) {
    new AXF_CLS_PluggyCollectionControlService().pauseConnection(connectionId);
  }

  @AuraEnabled
  public static AXF_CLS_PluggyConsentService.ConsentSnapshot resumeConnection(
    Id connectionId
  ) {
    return new AXF_CLS_PluggyCollectionControlService()
      .resumeConnection(connectionId);
  }

  @AuraEnabled
  public static AXF_CLS_PluggyConsentService.ConsentSnapshot refreshConsent(
    Id connectionId
  ) {
    return new AXF_CLS_PluggyConsentService().refresh(connectionId);
  }

  private static String impactText(AXF_OBJ_PluggyConnection__c c) {
    if (c.AXF_CON_PKL_ConsentState__c == 'REVOKED') {
      return 'Consentimento revogado. Os dados ja coletados continuam visiveis como desatualizados; nao ha nova coleta ate reautorizar no provedor.';
    }
    if (c.AXF_CON_PKL_ConsentState__c == 'STALE') {
      return 'Consentimento expirado ou dados desatualizados na origem. Coleta bloqueada ate reautorizar.';
    }
    if (c.AXF_CON_PKL_CollectionState__c == 'PAUSED') {
      return 'Coleta pausada localmente. Consentimento e historico preservados; retomar exige revalidacao.';
    }
    return 'Coleta ativa.';
  }

  private static String permittedAction(
    AXF_OBJ_PluggyConnection__c c,
    Boolean manage
  ) {
    if (!manage) {
      return 'NONE';
    }
    if (
      c.AXF_CON_PKL_ConsentState__c == 'REVOKED' ||
      c.AXF_CON_PKL_ConsentState__c == 'STALE'
    ) {
      return 'REAUTHORIZE';
    }
    return c.AXF_CON_PKL_CollectionState__c == 'PAUSED' ? 'RESUME' : 'PAUSE';
  }
}
