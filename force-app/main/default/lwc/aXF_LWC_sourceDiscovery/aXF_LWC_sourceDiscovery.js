import { LightningElement, api, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import getStatus from "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.getStatus";
import getDiscovered from "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.getDiscovered";
import startDiscovery from "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.startDiscovery";

// PT-BR literals for the MVP (D-86). Move to Custom Labels when i18n infra exists.
const L = {
  TITLE: "Descobrir contas e cartões",
  HELP: "Carrega as contas e cartões autorizados na aplicação Pluggy configurada. Não importa o histórico e não escolhe o titular.",
  START: "Descobrir agora",
  RESUME: "Continuar descoberta",
  BUSY: "Consultando a Pluggy…",
  NONE: "Nenhuma conta ou cartão encontrado nas conexões informadas. Autorize na aplicação correta.",
  INCOMPLETE: "Descoberta incompleta — não representa o catálogo completo.",
  LOAD_ERROR: "Não foi possível carregar o estado da descoberta.",
  RETRY: "Tentar novamente",
  COL_KIND: "Tipo",
  COL_INSTITUTION: "Instituição",
  COL_CURRENCY: "Moeda",
  COL_STATUS: "Situação",
  CUSTODY: "Em custódia — aguardando confirmação do titular",
  AVAILABLE: "Disponível",
  BANK: "Conta",
  CARD: "Cartão",
  GENERIC_FAIL: "A descoberta não foi concluída."
};

const STATE = { LOADING: "LOADING", READY: "READY", ERROR: "ERROR" };

export default class AxfSourceDiscovery extends LightningElement {
  @api recordId;
  @api connectionIdOverride;

  get connectionId() {
    return this.connectionIdOverride || this.recordId;
  }
  labels = L;
  uiState = STATE.LOADING;
  status;
  sources = [];
  running = false;
  feedback;
  feedbackVariant = "info";
  _wiredStatus;
  _wiredSources;

  @wire(getStatus, { connectionId: "$connectionId" })
  wiredStatus(result) {
    this._wiredStatus = result;
    const { data, error } = result;
    if (error) {
      this.uiState = STATE.ERROR;
      return;
    }
    if (data === undefined) {
      return;
    }
    this.status = data;
    this.uiState = STATE.READY;
  }

  @wire(getDiscovered, { connectionId: "$connectionId" })
  wiredSources(result) {
    this._wiredSources = result;
    const { data } = result;
    if (!data) {
      return;
    }
    this.sources = data.map((s) => ({
      key: s.recordId,
      kindLabel: s.kind === "CARD" ? L.CARD : L.BANK,
      institution: s.institution,
      currencyIsoCode: s.currencyIsoCode,
      statusLabel: s.availability === "AVAILABLE" ? L.AVAILABLE : L.CUSTODY
    }));
  }

  get isLoading() {
    return this.uiState === STATE.LOADING;
  }
  get isError() {
    return this.uiState === STATE.ERROR;
  }
  get isReady() {
    return this.uiState === STATE.READY;
  }
  get runState() {
    return this.status && this.status.state;
  }
  get isComplete() {
    return this.status && this.status.complete === true;
  }
  get isRetryable() {
    return this.runState === "FAILED_RETRYABLE";
  }
  get isTerminal() {
    return (
      this.runState === "FAILED_TERMINAL" || this.runState === "RESULT_UNKNOWN"
    );
  }
  get hasNoSources() {
    return (
      this.isComplete &&
      (this.status.accountsFound || 0) + (this.status.cardsFound || 0) === 0
    );
  }
  get startLabel() {
    return this.isRetryable ? L.RESUME : L.START;
  }
  get startDisabled() {
    return this.running || !this.connectionId || this.runState === "RUNNING";
  }
  get showSources() {
    return this.sources.length > 0;
  }
  get statusMessage() {
    return this.status && this.status.message;
  }

  async handleStart() {
    this.running = true;
    this.feedback = undefined;
    try {
      const res = await startDiscovery({ connectionId: this.connectionId });
      this.status = res;
      const variant =
        res.state === "SUCCEEDED"
          ? "success"
          : res.state === "FAILED_RETRYABLE"
            ? "warning"
            : "error";
      this.setFeedback(res.message || L.GENERIC_FAIL, variant);
      await this.refresh();
    } catch (e) {
      this.setFeedback(this.extractMessage(e), "error");
    } finally {
      this.running = false;
    }
  }

  async refresh() {
    await Promise.all([
      Promise.resolve(refreshApex(this._wiredStatus)).catch(() => {}),
      Promise.resolve(refreshApex(this._wiredSources)).catch(() => {})
    ]);
  }
  handleRetry() {
    this.uiState = STATE.LOADING;
    this.refresh();
  }
  extractMessage(e) {
    return e?.body?.message || e?.message || L.GENERIC_FAIL;
  }
  setFeedback(message, variant) {
    this.feedback = message;
    this.feedbackVariant = variant;
  }
}
