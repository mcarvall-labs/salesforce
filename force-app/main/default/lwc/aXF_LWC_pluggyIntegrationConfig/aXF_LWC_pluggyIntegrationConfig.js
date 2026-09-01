import { LightningElement, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import canConfigure from "@salesforce/apex/AXF_CLS_CTRL_PluggyIntegrationConfig.canConfigure";
import getStatus from "@salesforce/apex/AXF_CLS_CTRL_PluggyIntegrationConfig.getStatus";
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
    "O Client ID e o Client Secret são informados apenas pelo Setup de Credenciais Externas do Salesforce. Esta tela nunca recebe nem armazena o segredo.",
  TEST_CANDIDATE: "Testar credencial candidata",
  PROMOTE: "Promover candidata",
  ROLLBACK: "Reverter rotação",
  PAUSE_GLOBAL: "Pausar coleta globalmente",
  RESUME_GLOBAL: "Retomar coleta global",
  GLOBAL_PAUSED: "A coleta Pluggy está pausada globalmente.",
  GLOBAL_ACTIVE: "A coleta Pluggy está ativa.",
  WEBHOOK_ON: "Webhook habilitado",
  WEBHOOK_OFF: "Webhook desabilitado",
  CACHE_TTL: "TTL do cache do apiKey (s)",
  CONNECTIONS: "Conexões",
  BLOCKED: "Conexões bloqueadas",
  PRIMARY_TEST: "Último teste — slot primário",
  CANDIDATE_TEST: "Último teste — slot candidato",
  BUSY: "Processando…",
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
  get webhookText() {
    return this.status && this.status.webhookEnabled
      ? L.WEBHOOK_ON
      : L.WEBHOOK_OFF;
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

  async run(fn) {
    this.busy = true;
    this.feedback = undefined;
    try {
      const res = await fn();
      const msg = res && res.message ? res.message : "Operação concluída.";
      const variant =
        res && res.candidateHealthy === false ? "warning" : "success";
      this.setFeedback(msg, variant);
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
      return { message: "Coleta pausada globalmente." };
    });
  }
  handleResumeGlobal() {
    this.run(async () => {
      await resumeGlobally();
      return { message: "Coleta global retomada." };
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
