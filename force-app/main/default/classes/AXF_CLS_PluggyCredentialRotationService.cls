/**
 * @description Credential rotation without destroying the active credential. AXF-11 AC2,
 * Fechamento G4-2 and the "two pre-installed NC/EC sets" design from the G4 investigation.
 *
 * The active and candidate secrets both live in External Credentials, populated by an admin
 * through the native Setup UI (install step). This service only:
 *   1. tests the candidate slot end to end (auth + light read + existing connections still
 *      reachable) WITHOUT touching the active slot or its apiKey cache;
 *   2. promotes by flipping the active-slot pointer (pure DML) once every check passed;
 *   3. rolls back / preserves the active slot on any failure.
 *
 * RotationState on the config setting doubles as a concurrency token: a second test while
 * one is TESTING gets CONFLICT. A promotion that times out leaves RESULT_UNKNOWN and blocks
 * further automatic steps until an authorized user reconciles.
 */
public with sharing class AXF_CLS_PluggyCredentialRotationService {
  @TestVisible
  private static Boolean canConfigureOverride;

  @TestVisible
  private static AXF_CLS_PluggyHttpClient candidateClientForTests;

  public class RotationResult {
    @AuraEnabled
    public String state;
    @AuraEnabled
    public Boolean candidateHealthy;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Integer connectionsChecked;
  }

  private Boolean callerCanConfigure() {
    if (canConfigureOverride != null) {
      return canConfigureOverride;
    }
    return FeatureManagement.checkPermission('AXF_CanConfigure');
  }

  private void requireAuthority() {
    if (!callerCanConfigure()) {
      throw new AXF_CLS_PluggyConfigException(
        'Voce nao tem autorizacao para girar as credenciais Pluggy.'
      );
    }
  }

  private String candidateNamedCredential() {
    return AXF_CLS_PluggySettings.activeSlot() == 'PRIMARY'
      ? AXF_CLS_PluggySettings.NC_CANDIDATE
      : AXF_CLS_PluggySettings.NC_PRIMARY;
  }

  private AXF_CLS_PluggyHttpClient candidateClient() {
    return candidateClientForTests != null
      ? candidateClientForTests
      : new AXF_CLS_PluggyHttpClient(candidateNamedCredential());
  }

  /**
   * @description Tests the candidate slot. Never promotes. Writes a sanitized result to the
   * config setting. Preserves the active credential in every branch.
   */
  public RotationResult testCandidate() {
    requireAuthority();

    if (AXF_CLS_PluggySettings.rotationState() == 'TESTING') {
      throw new AXF_CLS_PluggyConfigException(
        'Ja existe um teste de rotacao em andamento (CONFLICT). Aguarde ou reconcilie o estado.'
      );
    }

    RotationResult r = new RotationResult();
    r.connectionsChecked = 0;
    String candidateSlot = AXF_CLS_PluggySettings.activeSlot() == 'PRIMARY'
      ? 'CANDIDATE'
      : 'PRIMARY';

    // Read the connections up front: no DML before the callouts (would abort them),
    // and no unbounded callouts after a SOQL loop.
    List<AXF_OBJ_PluggyConnection__c> conns = [
      SELECT AXF_CON_EXI_PluggyItemId__c
      FROM AXF_OBJ_PluggyConnection__c
      WHERE AXF_CON_PKL_ConsentState__c != 'REVOKED'
      WITH USER_MODE
      LIMIT 50
    ];

    try {
      AXF_CLS_PluggyHttpClient client = candidateClient();

      // 1. auth + 2. light read
      AXF_CLS_PluggyHttpClient.PluggyResponse connectors = client.getJson(
        '/connectors'
      );
      if (!connectors.isSuccess) {
        return finishTest(
          r,
          candidateSlot,
          false,
          AXF_CLS_PluggyHttpClient.sanitizedError(
            'GET /connectors (candidata)',
            connectors.statusCode,
            connectors.correlationId
          )
        );
      }

      // 3. existing connections still reachable with the candidate credential
      for (AXF_OBJ_PluggyConnection__c c : conns) {
        AXF_CLS_PluggyHttpClient.PluggyResponse itemRes = client.getJson(
          '/items/' + c.AXF_CON_EXI_PluggyItemId__c
        );
        r.connectionsChecked++;
        if (itemRes.statusCode == 401 || itemRes.statusCode == 403) {
          return finishTest(
            r,
            candidateSlot,
            false,
            'A credencial candidata nao consegue acessar uma conexao existente. Ativa preservada.'
          );
        }
      }

      return finishTest(
        r,
        candidateSlot,
        true,
        'Candidata validada. Pronta para promover.'
      );
    } catch (Exception e) {
      return finishTest(
        r,
        candidateSlot,
        false,
        e instanceof AXF_CLS_PluggyIntegrationException
          ? e.getMessage()
          : 'Falha ao testar a credencial candidata. Ativa preservada.'
      );
    }
  }

  private RotationResult finishTest(
    RotationResult r,
    String candidateSlot,
    Boolean healthy,
    String message
  ) {
    r.candidateHealthy = healthy;
    r.message = message;
    r.state = healthy ? 'TESTED_OK' : 'ROLLED_BACK';

    AXF_PluggyIntegrationConfig__c cfg = AXF_CLS_PluggySettings.currentOrgDefaultForUpdate();
    cfg.AXF_PIC_TXT_RotationState__c = r.state;
    cfg.AXF_PIC_DT_RotationStartedAt__c = Datetime.now();
    if (candidateSlot == 'PRIMARY') {
      cfg.AXF_PIC_TXT_PrimarySlotTestResult__c = truncate(message);
      cfg.AXF_PIC_DT_PrimarySlotTestedAt__c = Datetime.now();
    } else {
      cfg.AXF_PIC_TXT_CandidateSlotTestResult__c = truncate(message);
      cfg.AXF_PIC_DT_CandidateSlotTestedAt__c = Datetime.now();
    }
    AXF_CLS_PluggySettings.save(cfg);
    return r;
  }

  /**
   * @description Promotes the candidate by flipping the active-slot pointer. Only allowed
   * right after a passing test. Invalidates the apiKey cache. Never deletes a secret.
   */
  public RotationResult promote() {
    requireAuthority();

    RotationResult r = new RotationResult();
    if (AXF_CLS_PluggySettings.rotationState() != 'TESTED_OK') {
      throw new AXF_CLS_PluggyConfigException(
        'Promova apenas apos um teste da candidata bem-sucedido.'
      );
    }

    String newSlot = AXF_CLS_PluggySettings.activeSlot() == 'PRIMARY'
      ? 'CANDIDATE'
      : 'PRIMARY';
    AXF_PluggyIntegrationConfig__c cfg = AXF_CLS_PluggySettings.currentOrgDefaultForUpdate();
    cfg.AXF_PIC_TXT_ActiveSlot__c = newSlot;
    cfg.AXF_PIC_TXT_RotationState__c = 'PROMOTED';
    AXF_CLS_PluggySettings.save(cfg);

    AXF_CLS_PluggyAuthService.invalidateCache();

    r.state = 'PROMOTED';
    r.candidateHealthy = true;
    r.message =
      'Credencial promovida. Slot ativo: ' +
      newSlot +
      '. A anterior permanece preenchida.';
    return r;
  }

  public RotationResult rollback() {
    requireAuthority();
    setRotationState('ROLLED_BACK', false);
    RotationResult r = new RotationResult();
    r.state = 'ROLLED_BACK';
    r.candidateHealthy = false;
    r.message = 'Rotacao revertida. A credencial ativa nao foi alterada.';
    return r;
  }

  private void setRotationState(String state, Boolean stampStart) {
    AXF_PluggyIntegrationConfig__c cfg = AXF_CLS_PluggySettings.currentOrgDefaultForUpdate();
    cfg.AXF_PIC_TXT_RotationState__c = state;
    if (stampStart) {
      cfg.AXF_PIC_DT_RotationStartedAt__c = Datetime.now();
    }
    AXF_CLS_PluggySettings.save(cfg);
  }

  private static String truncate(String s) {
    if (s == null) {
      return null;
    }
    return s.length() > 255 ? s.substring(0, 255) : s;
  }
}
