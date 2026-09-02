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

// PT-BR literals for the MVP (D-86: PT-BR only). Move to Custom Labels + Translation
// Workbench when that i18n infrastructure is set up (same convention as aXF_LWC_accessLevelConfig).
const L = {
  TITLE: "Credenciais e consentimento Pluggy",
  FORBIDDEN: "Você não tem autorização para configurar a integração Pluggy.",
  LOAD_ERROR: "Não foi possível carregar a configuração da integração.",
  RETRY: "Tentar novamente",
  ACTIVE_SLOT: "Slot de credencial ativo",
  ROTATION_STATE: "Estado da rotação",
  SECRET_HINT:
    "O Client ID e o Client Secret são encaminhados direto para a Credencial Externa nativa e descartados. Nunca são gravados nem exibidos aqui.",
  CLIENT_ID: "Client ID",
  CLIENT_SECRET: "Client Secret",
  SAVE_ACTIVE: "Salvar credencial ativa",
  STAGE_CANDIDATE: "Preparar candidata (rotação)",
  TEST_CANDIDATE: "Testar credencial candidata",
  PROMOTE: "Promover candidata",
  ROLLBACK: "Reverter rotação",
  PAUSE_GLOBAL: "Pausar coleta globalmente",
  RESUME_GLOBAL: "Retomar coleta global",
  GLOBAL_PAUSED: "A coleta Pluggy está pausada globalmente.",
  GLOBAL_ACTIVE: "A coleta Pluggy está ativa.",
  CONNECTIONS: "Conexões",
  BLOCKED: "Conexões bloqueadas",
  PRIMARY_TEST: "Último teste — slot primário",
  CANDIDATE_TEST: "Último teste — slot candidato",
  BUSY: "Processando…",
  FILL_BOTH: "Informe o Client ID e o Client Secret.",
  GENERIC_FAIL: "A operação não foi concluída. Nada foi alterado."
};

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
    return (
      this.busy ||
      !this.status ||
      ["NONE", "PROMOTED"].includes(this.status.rotationState)
    );
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
