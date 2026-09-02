/**
 * @description Dedicated controller for aXF_LWC_pluggyIntegrationConfig (PROJECT_RULES §3).
 * Thin entry point: validates authority, delegates to the Pluggy services, returns typed
 * DTOs, never returns a secret or a stack trace. AXF-11.
 *
 * The Client ID / Secret are entered here by the org configurator (a System Administrator)
 * and forwarded straight to the native External Credential via AXF_CLS_PluggyCredentialWriter
 * — never persisted or logged. The screen also drives connectivity testing, rotation
 * (slot-pointer flip) and global pause.
 */
public with sharing class AXF_CLS_CTRL_PluggyIntegrationConfig {
  @TestVisible
  private static Boolean canConfigureOverride;

  private static Boolean callerCanConfigure() {
    if (canConfigureOverride != null) {
      return canConfigureOverride;
    }
    return FeatureManagement.checkPermission('AXF_CanConfigure');
  }

  public class StatusDTO {
    @AuraEnabled
    public Boolean canConfigure;
    @AuraEnabled
    public String activeSlot;
    @AuraEnabled
    public String rotationState;
    @AuraEnabled
    public String primarySlotTestResult;
    @AuraEnabled
    public Datetime primarySlotTestedAt;
    @AuraEnabled
    public String candidateSlotTestResult;
    @AuraEnabled
    public Datetime candidateSlotTestedAt;
    @AuraEnabled
    public Boolean collectionGloballyPaused;
    @AuraEnabled
    public Integer connectionCount;
    @AuraEnabled
    public Integer blockedConnectionCount;
  }

  @AuraEnabled(cacheable=true)
  public static Boolean canConfigure() {
    return callerCanConfigure();
  }

  @AuraEnabled(cacheable=true)
  public static StatusDTO getStatus() {
    StatusDTO d = new StatusDTO();
    d.canConfigure = callerCanConfigure();
    if (!d.canConfigure) {
      return d; // UI renders FORBIDDEN cleanly
    }
    AXF_PluggyIntegrationConfig__c cfg = AXF_PluggyIntegrationConfig__c.getOrgDefaults();
    d.activeSlot = AXF_CLS_PluggySettings.activeSlot();
    d.rotationState = AXF_CLS_PluggySettings.rotationState();
    d.collectionGloballyPaused = AXF_CLS_PluggySettings.collectionGloballyPaused();
    if (cfg != null) {
      d.primarySlotTestResult = cfg.AXF_PIC_TXT_PrimarySlotTestResult__c;
      d.primarySlotTestedAt = cfg.AXF_PIC_DT_PrimarySlotTestedAt__c;
      d.candidateSlotTestResult = cfg.AXF_PIC_TXT_CandidateSlotTestResult__c;
      d.candidateSlotTestedAt = cfg.AXF_PIC_DT_CandidateSlotTestedAt__c;
    }
    d.connectionCount = [
      SELECT COUNT()
      FROM AXF_OBJ_PluggyConnection__c
      WITH USER_MODE
    ];
    d.blockedConnectionCount = new AXF_CLS_PluggyCollectionControlService()
      .revalidatePending();
    return d;
  }

  /**
   * @description Forwards the active-slot Client ID / Secret to the native External
   * Credential. The values are never stored or logged here. Requires AXF_CanConfigure
   * (the configurator) plus, at the platform level, "Manage Named Credentials".
   */
  @AuraEnabled
  public static AXF_CLS_PluggyCredentialWriter.Result setPrincipalCredential(
    String clientId,
    String clientSecret
  ) {
    if (!callerCanConfigure()) {
      AXF_CLS_PluggyCredentialWriter.Result forbidden = new AXF_CLS_PluggyCredentialWriter.Result();
      forbidden.message = 'Voce nao tem autorizacao para configurar credenciais Pluggy.';
      return forbidden;
    }
    return new AXF_CLS_PluggyCredentialWriter()
      .write('AXF_EXC_Pluggy', 'AXF_Pluggy_Principal', clientId, clientSecret);
  }

  /**
   * @description Stages a candidate credential into the inactive slot, ready for
   * testCandidate(). Never touches the active credential.
   */
  @AuraEnabled
  public static AXF_CLS_PluggyCredentialWriter.Result stageCandidateCredential(
    String clientId,
    String clientSecret
  ) {
    if (!callerCanConfigure()) {
      AXF_CLS_PluggyCredentialWriter.Result forbidden = new AXF_CLS_PluggyCredentialWriter.Result();
      forbidden.message = 'Voce nao tem autorizacao para configurar credenciais Pluggy.';
      return forbidden;
    }
    return new AXF_CLS_PluggyCredentialRotationService()
      .stageCandidate(clientId, clientSecret);
  }

  @AuraEnabled
  public static AXF_CLS_PluggyCredentialRotationService.RotationResult testCandidate() {
    return new AXF_CLS_PluggyCredentialRotationService().testCandidate();
  }

  @AuraEnabled
  public static AXF_CLS_PluggyCredentialRotationService.RotationResult promoteCandidate() {
    return new AXF_CLS_PluggyCredentialRotationService().promote();
  }

  @AuraEnabled
  public static AXF_CLS_PluggyCredentialRotationService.RotationResult rollbackRotation() {
    return new AXF_CLS_PluggyCredentialRotationService().rollback();
  }

  @AuraEnabled
  public static void pauseGlobally() {
    new AXF_CLS_PluggyCollectionControlService().pauseGlobally();
  }

  @AuraEnabled
  public static void resumeGlobally() {
    new AXF_CLS_PluggyCollectionControlService().resumeGlobally();
  }
}
