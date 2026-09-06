import { LightningElement, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import canConfigure from "@salesforce/apex/AXF_CLS_CTRL_PluggyIntegrationConfig.canConfigure";
import getStatus from "@salesforce/apex/AXF_CLS_CTRL_PluggyIntegrationConfig.getStatus";
import setPrincipalCredential from "@salesforce/apex/AXF_CLS_CTRL_PluggyIntegrationConfig.setPrincipalCredential";
import stageCandidateCredential from "@salesforce/apex/AXF_CLS_CTRL_PluggyIntegrationConfig.stageCandidateCredential";
import testCandidate from "@salesforce/apex/AXF_CLS_CTRL_PluggyIntegrationConfig.testCandidate";
import promoteCandidate from "@salesforce/apex/AXF_CLS_CTRL_PluggyIntegrationConfig.promoteCandidate";
import rollbackRotation from "@salesforce/apex/AXF_CLS_CTRL_PluggyIntegrationConfig.rollbackRotation";
import pauseGlobally from "@salesforce/apex/AXF_CLS_CTRL_PluggyIntegrationConfig.pauseGlobally";
import resumeGlobally from "@salesforce/apex/AXF_CLS_CTRL_PluggyIntegrationConfig.resumeGlobally";
import LANG from "@salesforce/i18n/lang";

// Component-local i18n (org has no Translation Workbench). Axon ships PT-BR + EN
// only; the language follows the Salesforce user profile (@salesforce/i18n/lang).
const PT = {
  TITLE: "Credenciais e consentimento Pluggy",
  FORBIDDEN: "Você não tem autorização para configurar a integração Pluggy.",
  LOAD_ERROR: "Não foi possível carregar a configuração da integração.",
  RETRY: "Tentar novamente",
  ACTIVE_SLOT: "Slot de credencial ativo",
  ROTATION_STATE: "Estado",
  SECRET_HINT:
    "O Client ID e o Client Secret são encaminhados direto para a Credencial Externa nativa e descartados. Nunca são gravados nem exibidos aqui.",
  CLIENT_ID: "Client ID",
  CLIENT_SECRET: "Client Secret",

  SAVE_ACTIVE: "Salvar credencial ativa",
  SAVE_ACTIVE_TITLE:
    "Salva o Client ID e Client Secret como a credencial principal da integração Pluggy. Use ao configurar pela primeira vez ou ao renovar credenciais expiradas. A credencial anterior é substituída imediatamente.",

  STAGE_CANDIDATE: "Iniciar rotação de credencial",
  STAGE_CANDIDATE_TITLE:
    "Prepara uma nova credencial sem desativar a atual — a integração continua funcionando normalmente. Depois de preparar, você pode testá-la e só então ativá-la. Use quando precisar trocar credenciais sem interromper a coleta.",

  TEST_CANDIDATE: "Testar nova credencial",
  TEST_CANDIDATE_TITLE:
    "Verifica se a nova credencial consegue se autenticar na Pluggy e acessar todas as conexões existentes. Execute antes de ativar. Se o teste falhar, a credencial atual permanece ativa.",

  PROMOTE: "Ativar nova credencial",
  PROMOTE_TITLE:
    "Ativa a nova credencial como principal. Só disponível após um teste bem-sucedido. A credencial anterior permanece armazenada como backup, mas deixa de ser usada.",

  ROLLBACK: "Cancelar rotação",
  ROLLBACK_TITLE:
    "Abandona o processo de troca de credencial em andamento. A nova credencial é descartada e a credencial ativa permanece inalterada. Use se desistir da troca ou quiser recomeçar com credenciais diferentes.",

  PAUSE_GLOBAL: "Pausar coleta de dados",
  PAUSE_GLOBAL_TITLE:
    "Pausa temporariamente a sincronização automática de contas e cartões de todos os usuários. Use durante manutenção ou ao trocar credenciais. Nenhum dado é perdido — a coleta retoma do ponto onde parou.",

  RESUME_GLOBAL: "Retomar coleta de dados",
  RESUME_GLOBAL_TITLE:
    "Reativa a sincronização automática após uma pausa. As conexões serão atualizadas na próxima execução agendada.",

  GLOBAL_PAUSED: "⏸ Coleta de dados pausada.",
  GLOBAL_ACTIVE: "▶ Coleta de dados ativa.",
  CONNECTIONS: "Conexões",
  BLOCKED: "Conexões bloqueadas",
  ACTIVE_TEST: "Último teste — credencial ativa",
  CANDIDATE_TEST: "Último teste — candidata",
  ROTATION_IN_PROGRESS: "Rotação em andamento",
  BUSY: "Processando…",
  FILL_BOTH: "Informe o Client ID e o Client Secret.",
  GENERIC_FAIL: "A operação não foi concluída. Nada foi alterado.",
  CREDENTIAL_ACTIVE: "Credencial configurada — coleta ativa",
  CREDENTIAL_NONE: "Nenhuma credencial configurada ainda",
  ROT_CANDIDATE: "Candidata preparada — aguardando teste",
  ROT_TESTING: "Testando candidata…",
  ROT_TESTED_OK: "✅ Candidata aprovada — pronta para promover"
};

const EN = {
  TITLE: "Pluggy credentials and consent",
  FORBIDDEN: "You are not authorized to configure the Pluggy integration.",
  LOAD_ERROR: "Could not load the integration configuration.",
  RETRY: "Try again",
  ACTIVE_SLOT: "Active credential slot",
  ROTATION_STATE: "State",
  SECRET_HINT:
    "The Client ID and Client Secret are sent straight to the native External Credential and discarded. They are never stored or shown here.",
  CLIENT_ID: "Client ID",
  CLIENT_SECRET: "Client Secret",

  SAVE_ACTIVE: "Save active credential",
  SAVE_ACTIVE_TITLE:
    "Saves the Client ID and Client Secret as the Pluggy integration's primary credential. Use it on first setup or when renewing expired credentials. The previous credential is replaced immediately.",

  STAGE_CANDIDATE: "Start credential rotation",
  STAGE_CANDIDATE_TITLE:
    "Prepares a new credential without disabling the current one — the integration keeps working. After preparing it you can test it and only then activate it. Use it to rotate credentials without interrupting collection.",

  TEST_CANDIDATE: "Test new credential",
  TEST_CANDIDATE_TITLE:
    "Checks whether the new credential can authenticate with Pluggy and reach every existing connection. Run it before activating. If the test fails, the current credential stays active.",

  PROMOTE: "Activate new credential",
  PROMOTE_TITLE:
    "Activates the new credential as the primary one. Only available after a successful test. The previous credential is kept as a backup but is no longer used.",

  ROLLBACK: "Cancel rotation",
  ROLLBACK_TITLE:
    "Abandons the credential rotation in progress. The new credential is discarded and the active credential is left unchanged. Use it if you give up the swap or want to restart with different credentials.",

  PAUSE_GLOBAL: "Pause data collection",
  PAUSE_GLOBAL_TITLE:
    "Temporarily pauses the automatic sync of every user's accounts and cards. Use it during maintenance or a credential swap. No data is lost — collection resumes from where it stopped.",

  RESUME_GLOBAL: "Resume data collection",
  RESUME_GLOBAL_TITLE:
    "Re-enables the automatic sync after a pause. Connections are refreshed on the next scheduled run.",

  GLOBAL_PAUSED: "⏸ Data collection paused.",
  GLOBAL_ACTIVE: "▶ Data collection active.",
  CONNECTIONS: "Connections",
  BLOCKED: "Blocked connections",
  ACTIVE_TEST: "Last test — active credential",
  CANDIDATE_TEST: "Last test — candidate",
  ROTATION_IN_PROGRESS: "Rotation in progress",
  BUSY: "Working…",
  FILL_BOTH: "Enter the Client ID and the Client Secret.",
  GENERIC_FAIL: "The operation did not complete. Nothing was changed.",
  CREDENTIAL_ACTIVE: "Credential configured — collection active",
  CREDENTIAL_NONE: "No credential configured yet",
  ROT_CANDIDATE: "Candidate prepared — waiting for test",
  ROT_TESTING: "Testing candidate…",
  ROT_TESTED_OK: "✅ Candidate approved — ready to promote"
};

const L = String(LANG || "")
  .toLowerCase()
  .startsWith("en")
  ? EN
  : PT;

const STATE = {
  LOADING: "LOADING",
  READY: "READY",
  FORBIDDEN: "FORBIDDEN",
  ERROR: "ERROR"
};

export default class AxfPluggyIntegrationConfig extends LightningElement {
  labels = L;
  state = STATE.LOADING;
  status;
  busy = false;
  feedback;
  feedbackVariant = "info";
  clientId = "";
  clientSecret = "";
  _wired;

  @wire(canConfigure)
  wiredCanConfigure({ data, error }) {
    if (error) {
      this.state = STATE.ERROR;
    } else if (data === false) {
      this.state = STATE.FORBIDDEN;
    }
  }

  @wire(getStatus)
  wiredStatus(result) {
    this._wired = result;
    const { data, error } = result;
    if (error) {
      this.state = STATE.ERROR;
      return;
    }
    if (!data) {
      return;
    }
    this.status = data;
    if (this.state === STATE.FORBIDDEN || data.canConfigure === false) {
      this.state = STATE.FORBIDDEN;
      return;
    }
    this.state = STATE.READY;
    this.notifyStatusChange();
  }

  notifyStatusChange() {
    this.dispatchEvent(
      new CustomEvent("statuschange", {
        detail: {
          hasActiveCredential: this.hasActiveCredential,
          activeSlot: this.status && this.status.activeSlot
        },
        bubbles: true,
        composed: true
      })
    );
  }

  get isLoading() {
    return this.state === STATE.LOADING;
  }
  get isForbidden() {
    return this.state === STATE.FORBIDDEN;
  }
  get isError() {
    return this.state === STATE.ERROR;
  }
  get isReady() {
    return this.state === STATE.READY;
  }
  get globalPaused() {
    return this.status && this.status.collectionGloballyPaused === true;
  }
  get globalStateText() {
    return this.globalPaused ? L.GLOBAL_PAUSED : L.GLOBAL_ACTIVE;
  }
  get credentialButtonsDisabled() {
    return this.busy || !this.clientId || !this.clientSecret;
  }
  get promoteDisabled() {
    return (
      this.busy || !this.status || this.status.rotationState !== "TESTED_OK"
    );
  }
  get rollbackDisabled() {
    // Only makes sense when a rotation is explicitly in progress
    return (
      this.busy ||
      !this.status ||
      !["CANDIDATE", "TESTED_OK"].includes(this.status.rotationState)
    );
  }
  /** True when a credential has been saved (slot pointer is set). */
  get hasActiveCredential() {
    return !!(this.status && this.status.activeSlot);
  }
  get credentialStatusLabel() {
    return this.hasActiveCredential ? L.CREDENTIAL_ACTIVE : L.CREDENTIAL_NONE;
  }
  get credentialBadgeClass() {
    const base =
      "slds-box slds-p-around_x-small slds-text-body_small pic__cred-badge";
    return this.hasActiveCredential
      ? `${base} slds-theme_success`
      : `${base} slds-theme_shade`;
  }
  get credentialBadgeIcon() {
    return this.hasActiveCredential ? "utility:check" : "utility:warning";
  }
  /**
   * The last known health of the **active** slot — shown so the user knows
   * whether the current credential is reachable, not the candidate's test result.
   * Only populated after an explicit test action; never shows stale candidate data.
   */
  get activeSlotHealth() {
    if (!this.status) return null;
    const slot = this.status.activeSlot;
    if (!slot) return null;
    return slot === "PRIMARY"
      ? this.status.primarySlotTestResult
      : this.status.candidateSlotTestResult;
  }
  /**
   * True only while a rotation is explicitly in progress.
   * NONE (and the DB-erased ROLLED_BACK/PROMOTED) collapse to false so the
   * rotation section doesn't appear when there is nothing to act on.
   */
  get hasActiveRotation() {
    const code = this.status && this.status.rotationState;
    return ["CANDIDATE", "TESTING", "TESTED_OK"].includes(code);
  }
  get rotationStateLabel() {
    if (!this.status) return "";
    const labels = {
      CANDIDATE: L.ROT_CANDIDATE,
      TESTING: L.ROT_TESTING,
      TESTED_OK: L.ROT_TESTED_OK
    };
    return labels[this.status.rotationState] || "";
  }

  handleClientIdChange(event) {
    this.clientId = event.target.value;
  }
  handleClientSecretChange(event) {
    this.clientSecret = event.target.value;
  }

  clearCredentialInputs() {
    this.clientId = "";
    this.clientSecret = "";
    const inputs = this.template.querySelectorAll("lightning-input");
    inputs.forEach((i) => {
      i.value = "";
    });
  }

  async run(fn, { clearCreds = false } = {}) {
    this.busy = true;
    this.feedback = undefined;
    try {
      const res = await fn();
      const msg = res && res.message ? res.message : "Operação concluída.";
      const ok =
        !res ||
        res.applied === true ||
        res.candidateHealthy === true ||
        res.state === "PROMOTED" ||
        res.state === "ROLLED_BACK";
      const variant =
        res && (res.applied === false || res.candidateHealthy === false)
          ? "warning"
          : ok
            ? "success"
            : "info";
      this.setFeedback(msg, variant);
      if (clearCreds) {
        this.clearCredentialInputs();
      }
      this.refresh();
    } catch (e) {
      this.setFeedback(this.extractMessage(e), "error");
    } finally {
      this.busy = false;
    }
  }

  refresh() {
    if (this._wired) {
      Promise.resolve(refreshApex(this._wired)).catch(() => {
        /* stale view is acceptable; the action itself already reported its outcome */
      });
    }
  }

  handleSaveActive() {
    if (!this.clientId || !this.clientSecret) {
      this.setFeedback(L.FILL_BOTH, "warning");
      return;
    }
    this.run(
      () =>
        setPrincipalCredential({
          clientId: this.clientId,
          clientSecret: this.clientSecret
        }),
      { clearCreds: true }
    );
  }
  handleStageCandidate() {
    if (!this.clientId || !this.clientSecret) {
      this.setFeedback(L.FILL_BOTH, "warning");
      return;
    }
    this.run(
      () =>
        stageCandidateCredential({
          clientId: this.clientId,
          clientSecret: this.clientSecret
        }),
      { clearCreds: true }
    );
  }
  handleTest() {
    this.run(() => testCandidate());
  }
  handlePromote() {
    this.run(() => promoteCandidate());
  }
  handleRollback() {
    this.run(() => rollbackRotation());
  }
  handlePauseGlobal() {
    this.run(async () => {
      await pauseGlobally();
      return { message: "Coleta pausada globalmente.", applied: true };
    });
  }
  handleResumeGlobal() {
    this.run(async () => {
      await resumeGlobally();
      return { message: "Coleta global retomada.", applied: true };
    });
  }
  handleRetry() {
    this.state = STATE.LOADING;
    refreshApex(this._wired);
  }

  extractMessage(e) {
    return (
      e?.body?.message ||
      e?.body?.pageErrors?.[0]?.message ||
      e?.message ||
      L.GENERIC_FAIL
    );
  }

  setFeedback(message, variant) {
    this.feedback = message;
    this.feedbackVariant = variant;
  }
}
