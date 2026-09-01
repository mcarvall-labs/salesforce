import { LightningElement, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import getSources from "@salesforce/apex/AXF_CLS_CTRL_SourceHealth.getSources";
import pauseConnection from "@salesforce/apex/AXF_CLS_CTRL_SourceHealth.pauseConnection";
import resumeConnection from "@salesforce/apex/AXF_CLS_CTRL_SourceHealth.resumeConnection";
import refreshConsent from "@salesforce/apex/AXF_CLS_CTRL_SourceHealth.refreshConsent";

// PT-BR literals for the MVP (D-86). Move to Custom Labels when i18n infra exists.
const L = {
  TITLE: "Saúde das fontes",
  EMPTY: "Nenhuma fonte conectada.",
  LOAD_ERROR: "Não foi possível carregar a saúde das fontes.",
  RETRY: "Tentar novamente",
  COL_INSTITUTION: "Instituição",
  COL_CONSENT: "Consentimento",
  COL_COLLECTION: "Coleta",
  COL_LAST_SUCCESS: "Último sucesso",
  COL_STATUS: "Estado",
  COL_IMPACT: "Impacto",
  PAUSE: "Pausar",
  RESUME: "Retomar",
  REAUTHORIZE: "Reautorizar no provedor",
  BUSY: "Processando…",
  GENERIC_FAIL: "A operação não foi concluída. Nada foi alterado.",
  NEVER: "Sem sucesso registrado"
};

const CONSENT_LABEL = {
  ACTIVE: "Ativo",
  STALE: "Desatualizado",
  REVOKED: "Revogado"
};
const COLLECTION_LABEL = { ACTIVE: "Ativa", PAUSED: "Pausada" };

const STATE = {
  LOADING: "LOADING",
  READY: "READY",
  EMPTY: "EMPTY",
  ERROR: "ERROR"
};

export default class AxfSourceHealth extends LightningElement {
  labels = L;
  state = STATE.LOADING;
  rows = [];
  busyId;
  feedback;
  feedbackVariant = "info";
  _wired;

  @wire(getSources)
  wiredSources(result) {
    this._wired = result;
    const { data, error } = result;
    if (error) {
      this.state = STATE.ERROR;
      return;
    }
    if (!data) {
      return;
    }
    this.rows = data.map((s) => ({
      ...s,
      consentLabel: CONSENT_LABEL[s.consentState] || s.consentState,
      collectionLabel: COLLECTION_LABEL[s.collectionState] || s.collectionState,
      lastSuccessLabel: s.lastSuccessAt
        ? new Date(s.lastSuccessAt).toLocaleString("pt-BR")
        : L.NEVER,
      isReauthorize: s.permittedAction === "REAUTHORIZE",
      isPause: s.permittedAction === "PAUSE",
      isResume: s.permittedAction === "RESUME",
      rowBusy: this.busyId === s.connectionId
    }));
    this.state = this.rows.length ? STATE.READY : STATE.EMPTY;
  }

  get isLoading() {
    return this.state === STATE.LOADING;
  }
  get isEmpty() {
    return this.state === STATE.EMPTY;
  }
  get isError() {
    return this.state === STATE.ERROR;
  }
  get isReady() {
    return this.state === STATE.READY;
  }

  async act(connectionId, fn) {
    this.busyId = connectionId;
    this.feedback = undefined;
    try {
      const res = await fn(connectionId);
      const msg = res && res.message ? res.message : "Operação concluída.";
      this.setFeedback(msg, "success");
      await refreshApex(this._wired);
    } catch (e) {
      this.setFeedback(this.extractMessage(e), "error");
    } finally {
      this.busyId = undefined;
      await refreshApex(this._wired);
    }
  }

  handlePause(event) {
    this.act(event.target.dataset.id, (id) =>
      pauseConnection({ connectionId: id })
    );
  }
  handleResume(event) {
    this.act(event.target.dataset.id, (id) =>
      resumeConnection({ connectionId: id })
    );
  }
  handleRefresh(event) {
    this.act(event.target.dataset.id, (id) =>
      refreshConsent({ connectionId: id })
    );
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
