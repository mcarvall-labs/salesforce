/**
 * @description Local pause/resume of Pluggy collection and the gate that every material
 * collection unit must pass. AXF-11 AC4/AC5, decision 2026-08-28 (local pause, no DELETE).
 *
 *  - Pause blocks new units (enqueue / callout / publish) in the affected scope. It does
 *    NOT revoke consent, delete history, or remove the shared application credential.
 *  - Resume requires AXF_CanConfigure AND a successful consent revalidation.
 *  - assertCollectionAllowed / revalidatePending are the hooks AXF-12 jobs call before
 *    each new unit, including already-queued jobs.
 */
public with sharing class AXF_CLS_PluggyCollectionControlService {
  @TestVisible
  private static Boolean canConfigureOverride;

  @TestVisible
  private AXF_CLS_PluggyConsentService consentServiceForTests;

  private Boolean callerCanConfigure() {
    if (canConfigureOverride != null) {
      return canConfigureOverride;
    }
    return FeatureManagement.checkPermission('AXF_CanConfigure');
  }

  private AXF_CLS_PluggyConsentService consentService() {
    return consentServiceForTests != null
      ? consentServiceForTests
      : new AXF_CLS_PluggyConsentService();
  }

  public class BlockReason {
    public Boolean allowed;
    public String code; // GLOBAL_PAUSE | LOCAL_PAUSE | CONSENT_STALE | CONSENT_REVOKED | OK
    public String message;
  }

  /**
   * @description Non-throwing check used by the UI and by jobs that prefer to branch.
   */
  public BlockReason evaluate(Id connectionId) {
    return evaluate(
      [
        SELECT AXF_CON_PKL_CollectionState__c, AXF_CON_PKL_ConsentState__c
        FROM AXF_OBJ_PluggyConnection__c
        WHERE Id = :connectionId
        WITH USER_MODE
        LIMIT 1
      ]
    );
  }

  public BlockReason evaluate(AXF_OBJ_PluggyConnection__c c) {
    BlockReason r = new BlockReason();
    r.allowed = true;
    r.code = 'OK';

    if (AXF_CLS_PluggySettings.collectionGloballyPaused()) {
      r.allowed = false;
      r.code = 'GLOBAL_PAUSE';
      r.message = 'A coleta Pluggy esta pausada globalmente.';
      return r;
    }

    if (c.AXF_CON_PKL_CollectionState__c == 'PAUSED') {
      r.allowed = false;
      r.code = 'LOCAL_PAUSE';
      r.message = 'A coleta desta conexao esta pausada.';
    } else if (c.AXF_CON_PKL_ConsentState__c == 'REVOKED') {
      r.allowed = false;
      r.code = 'CONSENT_REVOKED';
      r.message = 'Consentimento revogado. Reautorize no provedor para retomar.';
    } else if (c.AXF_CON_PKL_ConsentState__c == 'STALE') {
      r.allowed = false;
      r.code = 'CONSENT_STALE';
      r.message = 'Consentimento expirado ou dados desatualizados. Reautorize para retomar.';
    }
    return r;
  }

  public Boolean isCollectionAllowed(Id connectionId) {
    return evaluate(connectionId).allowed;
  }

  /**
   * @description Hard gate for AXF-12: call before enqueuing a job, before a callout, and
   * before publishing collected data. Throws with a sanitized reason when blocked.
   */
  public void assertCollectionAllowed(Id connectionId) {
    BlockReason r = evaluate(connectionId);
    if (!r.allowed) {
      throw new AXF_CLS_PluggyCollectionBlockedException(r.message);
    }
  }

  public void pauseConnection(Id connectionId) {
    requireAuthority();
    AXF_OBJ_PluggyConnection__c c = [
      SELECT AXF_CON_PKL_CollectionState__c
      FROM AXF_OBJ_PluggyConnection__c
      WHERE Id = :connectionId
      WITH USER_MODE
      LIMIT 1
    ];
    if (c.AXF_CON_PKL_CollectionState__c == 'PAUSED') {
      return; // idempotent
    }
    c.AXF_CON_PKL_CollectionState__c = 'PAUSED';
    c.AXF_CON_DT_PausedAt__c = Datetime.now();
    c.AXF_CON_LKP_PausedBy__c = UserInfo.getUserId();
    update as user c;
  }

  /**
   * @description Resume requires a successful consent revalidation. If consent is not
   * ACTIVE after the refresh, the connection stays paused and the caller is told why.
   */
  public AXF_CLS_PluggyConsentService.ConsentSnapshot resumeConnection(
    Id connectionId
  ) {
    requireAuthority();
    AXF_CLS_PluggyConsentService.ConsentSnapshot snap = consentService()
      .refresh(connectionId);
    if (snap.consentState != 'ACTIVE') {
      throw new AXF_CLS_PluggyCollectionBlockedException(
        'Nao e possivel retomar: ' +
        (snap.message != null ? snap.message : 'consentimento nao esta ativo.')
      );
    }
    AXF_OBJ_PluggyConnection__c c = new AXF_OBJ_PluggyConnection__c(
      Id = connectionId,
      AXF_CON_PKL_CollectionState__c = 'ACTIVE',
      AXF_CON_DT_PausedAt__c = null,
      AXF_CON_LKP_PausedBy__c = null
    );
    update as user c;
    return snap;
  }

  public void pauseGlobally() {
    requireAuthority();
    AXF_PluggyIntegrationConfig__c cfg = AXF_CLS_PluggySettings.currentOrgDefaultForUpdate();
    cfg.AXF_PIC_BOL_CollectionGloballyPaused__c = true;
    cfg.AXF_PIC_DT_GlobalPauseAt__c = Datetime.now();
    AXF_CLS_PluggySettings.save(cfg);
  }

  public void resumeGlobally() {
    requireAuthority();
    AXF_PluggyIntegrationConfig__c cfg = AXF_CLS_PluggySettings.currentOrgDefaultForUpdate();
    cfg.AXF_PIC_BOL_CollectionGloballyPaused__c = false;
    AXF_CLS_PluggySettings.save(cfg);
  }

  /**
   * @description Re-evaluates every connection so pending jobs see the current state.
   * Returns the count currently blocked. Consent is NOT re-fetched here (no callout);
   * that is done by the webhook queueable and by the scheduled scan (AXF-12).
   */
  public Integer revalidatePending() {
    Integer blocked = 0;
    for (AXF_OBJ_PluggyConnection__c c : [
      SELECT AXF_CON_PKL_CollectionState__c, AXF_CON_PKL_ConsentState__c
      FROM AXF_OBJ_PluggyConnection__c
      WITH USER_MODE
    ]) {
      if (!evaluate(c).allowed) {
        blocked++;
      }
    }
    return blocked;
  }

  private void requireAuthority() {
    if (!callerCanConfigure()) {
      throw new AXF_CLS_PluggyConfigException(
        'Voce nao tem autorizacao para pausar ou retomar a coleta Pluggy.'
      );
    }
  }
}
