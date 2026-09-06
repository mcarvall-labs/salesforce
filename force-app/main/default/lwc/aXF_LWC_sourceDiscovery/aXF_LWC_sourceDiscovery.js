import { LightningElement, api, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import getStatus from "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.getStatus";
import getDiscovered from "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.getDiscovered";
import getConnections from "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.getConnections";
import startDiscovery from "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.startDiscovery";
import registerConnection from "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.registerConnection";
import LANG from "@salesforce/i18n/lang";

// Component-local i18n (org has no Translation Workbench). Axon ships PT-BR + EN
// only; the language follows the Salesforce user profile (@salesforce/i18n/lang).
const PT = {
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
  GENERIC_FAIL: "A descoberta não foi concluída.",
  MULTI_INTRO:
    "Cada banco que você conectou no Pluggy tem um Item ID próprio. Cadastre o Item ID de cada conexão e depois clique em Descobrir agora para carregar as contas e cartões de todas.",
  ITEM_ID_LABEL: "Item ID da Pluggy",
  ITEM_ID_HELP:
    "Copie dentro da aplicação configurada no Dashboard da Pluggy: Aplicações → ▶ → conexão → ⋮ → Copiar Item ID. Não use o link do MeuPluggy.",
  REGISTER: "Registrar conexão",
  REGISTERING: "Registrando a conexão…",
  DISCOVER_ALL: "Descobrir agora",
  DISCOVERING: "Buscando contas e cartões em cada conexão…",
  NO_CONNECTIONS_YET: "Nenhuma conexão cadastrada ainda.",
  COL_CONN: "Conexão",
  COL_CONSENT: "Consentimento",
  COL_FOUND: "Encontrado",
  CONSENT_ACTIVE: "Ativo",
  CONSENT_STALE: "Desatualizado",
  CONSENT_REVOKED: "Revogado",
  RUN_PENDING: "Aguardando descoberta",
  RUN_OK: "Descoberta concluída",
  RUN_PARTIAL: "Descoberta incompleta",
  RUN_FAILED: "Falhou — tente de novo",
  DISCOVER_SUMMARY:
    "Descoberta concluída: {0} conta(s) e {1} cartão(ões) em custódia.",
  DISCOVER_PARTIAL:
    " {0} conexão(ões) não concluíram — revise o consentimento e tente de novo."
};

const EN = {
  TITLE: "Find accounts and cards",
  HELP: "Loads the accounts and cards authorized on the configured Pluggy application. It does not import history and does not choose the holder.",
  START: "Discover now",
  RESUME: "Resume discovery",
  BUSY: "Querying Pluggy…",
  NONE: "No account or card found on the informed connections. Authorize it on the right application.",
  INCOMPLETE: "Discovery incomplete — this is not the full catalogue.",
  LOAD_ERROR: "Could not load the discovery status.",
  RETRY: "Try again",
  COL_KIND: "Type",
  COL_INSTITUTION: "Institution",
  COL_CURRENCY: "Currency",
  COL_STATUS: "Status",
  CUSTODY: "In custody — waiting for holder confirmation",
  AVAILABLE: "Available",
  BANK: "Account",
  CARD: "Card",
  GENERIC_FAIL: "Discovery did not complete.",
  MULTI_INTRO:
    "Each bank you connected on Pluggy has its own Item ID. Register each connection's Item ID and then click Discover now to load the accounts and cards of all of them.",
  ITEM_ID_LABEL: "Pluggy Item ID",
  ITEM_ID_HELP:
    "Copy it inside the configured application in the Pluggy dashboard: Aplicações → ▶ → connection → ⋮ → Copiar Item ID. Do not use the MeuPluggy link.",
  REGISTER: "Register connection",
  REGISTERING: "Registering the connection…",
  DISCOVER_ALL: "Discover now",
  DISCOVERING: "Fetching accounts and cards on each connection…",
  NO_CONNECTIONS_YET: "No connection registered yet.",
  COL_CONN: "Connection",
  COL_CONSENT: "Consent",
  COL_FOUND: "Found",
  CONSENT_ACTIVE: "Active",
  CONSENT_STALE: "Stale",
  CONSENT_REVOKED: "Revoked",
  RUN_PENDING: "Waiting for discovery",
  RUN_OK: "Discovery complete",
  RUN_PARTIAL: "Discovery incomplete",
  RUN_FAILED: "Failed — try again",
  DISCOVER_SUMMARY:
    "Discovery complete: {0} account(s) and {1} card(s) in custody.",
  DISCOVER_PARTIAL:
    " {0} connection(s) did not complete — review the consent and try again."
};

const L = String(LANG || "")
  .toLowerCase()
  .startsWith("en")
  ? EN
  : PT;

const STATE = { LOADING: "LOADING", READY: "READY", ERROR: "ERROR" };

const CONSENT_LABEL = {
  ACTIVE: L.CONSENT_ACTIVE,
  STALE: L.CONSENT_STALE,
  REVOKED: L.CONSENT_REVOKED
};
const RUN_LABEL = {
  SUCCEEDED: L.RUN_OK,
  FAILED_RETRYABLE: L.RUN_PARTIAL,
  FAILED_TERMINAL: L.RUN_FAILED,
  RESULT_UNKNOWN: L.RUN_FAILED,
  RUNNING: L.DISCOVERING
};

export default class AxfSourceDiscovery extends LightningElement {
  @api recordId;
  @api connectionIdOverride;

  get connectionId() {
    return this.connectionIdOverride || this.recordId;
  }
  // In the onboarding wizard there is no record context: manage many connections.
  get multiMode() {
    return !this.recordId && !this.connectionIdOverride;
  }

  labels = L;
  uiState = STATE.LOADING;
  status;
  sources = [];
  connections = [];
  running = false;
  registering = false;
  itemId = "";
  feedback;
  feedbackVariant = "info";
  _wiredStatus;
  _wiredSources;
  _wiredConnections;

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

  @wire(getConnections)
  wiredConnections(result) {
    this._wiredConnections = result;
    const { data } = result;
    if (!data) {
      return;
    }
    this.connections = data.map((c) => ({
      key: c.connectionId,
      connectionId: c.connectionId,
      name: c.institution || c.itemIdHint || "Conexão",
      itemIdHint: c.itemIdHint,
      consentLabel: CONSENT_LABEL[c.consentState] || c.consentState || "—",
      consentWarn: c.consentState && c.consentState !== "ACTIVE",
      runLabel: RUN_LABEL[c.runState] || L.RUN_PENDING,
      found: `${c.accountsFound || 0} + ${c.cardsFound || 0}`,
      discovered: c.discovered === true
    }));
  }

  // ---- single-connection (record page) view ----
  get singleMode() {
    return !this.multiMode;
  }
  get isLoading() {
    return (
      this.singleMode && this.uiState === STATE.LOADING && !!this.connectionId
    );
  }
  get isError() {
    return this.singleMode && this.uiState === STATE.ERROR;
  }
  get isReady() {
    return this.singleMode && this.uiState === STATE.READY;
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

  // ---- multi-connection (wizard) view ----
  get hasConnections() {
    return this.connections.length > 0;
  }
  get registerDisabled() {
    return this.registering || !this.itemId || this.itemId.trim().length < 3;
  }
  get discoverAllDisabled() {
    return this.running || !this.hasConnections;
  }
  handleItemIdChange(event) {
    this.itemId = event.target.value;
  }
  async handleRegister() {
    this.registering = true;
    this.feedback = undefined;
    try {
      const res = await registerConnection({ pluggyItemId: this.itemId });
      this.itemId = "";
      this.setFeedback(res.message, "success");
      await Promise.resolve(refreshApex(this._wiredConnections)).catch(
        () => {}
      );
    } catch (e) {
      this.setFeedback(this.extractMessage(e), "error");
    } finally {
      this.registering = false;
    }
  }
  async handleDiscoverAll() {
    this.running = true;
    this.feedback = undefined;
    let accounts = 0;
    let cards = 0;
    let failed = 0;
    // One connection per Apex transaction — a callout is never issued after a DML.
    for (const c of this.connections) {
      try {
        // eslint-disable-next-line no-await-in-loop
        const r = await startDiscovery({ connectionId: c.connectionId });
        accounts += r.accountsFound || 0;
        cards += r.cardsFound || 0;
        if (r.complete !== true) {
          failed += 1;
        }
      } catch (err) {
        this.feedback = this.extractMessage(err);
        failed += 1;
      }
    }
    let summary = L.DISCOVER_SUMMARY.replace("{0}", accounts).replace(
      "{1}",
      cards
    );
    if (failed > 0) {
      summary += L.DISCOVER_PARTIAL.replace("{0}", failed);
    }
    this.setFeedback(summary, failed > 0 ? "warning" : "success");
    await Promise.resolve(refreshApex(this._wiredConnections)).catch(() => {});
    this.running = false;
  }

  // ---- single-connection actions ----
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
