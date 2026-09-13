import { LightningElement, api, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import getStatus from "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.getStatus";
import getDiscovered from "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.getDiscovered";
import getConnections from "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.getConnections";
import startDiscovery from "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.startDiscovery";
import registerConnection from "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.registerConnection";
import updateReferences from "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.updateReferences";
import saveHolder from "@salesforce/apex/AXF_CLS_CTRL_Holder.saveHolder";
import createBankInstitution from "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.createBankInstitution";
import deleteConnection from "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.deleteConnection";
import LANG from "@salesforce/i18n/lang";

// Component-local i18n (org has no Translation Workbench). Axon ships PT-BR + EN
// only; the language follows the Salesforce user profile (@salesforce/i18n/lang).
const PT = {
  TITLE: "Descobrir contas e cartões",
  HELP: "Carrega as contas e cartões autorizados na aplicação Pluggy configurada. Não importa o histórico. O banco e o titular definidos na conexão são aplicados a cada fonte descoberta, que fica liberada para uso.",
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
    "Cada banco que você conectou no Pluggy tem um Item ID próprio. Registre cada conexão informando o Item ID, o banco e o titular: ao descobrir, o banco e o titular escolhidos aqui são aplicados a cada conta e cartão desta conexão, que ficam liberados para uso. A lista abaixo é somente para consulta.",
  ITEM_ID_LABEL: "Item ID da Pluggy",
  ITEM_ID_HELP:
    "Copie dentro da aplicação configurada no Dashboard da Pluggy: Aplicações → ▶ → conexão → ⋮ → Copiar Item ID. Não use o link do MeuPluggy.",
  REGISTER: "Registrar conexão",
  REGISTER_SAVE: "Registrar",
  REGISTER_TITLE: "Registrar conexão Pluggy",
  REGISTER_HELP:
    "O conector (por exemplo, MeuPluggy) não identifica o banco: selecione a instituição financeira correta e o titular. Ao descobrir, o banco e o titular escolhidos aqui são aplicados às contas e cartões desta conexão, que ficam liberados para uso. Um titular já confirmado e diferente nunca é sobrescrito — resolva a divergência em Confirmar titulares.",
  REGISTERING: "Registrando…",
  DISCOVER_ALL: "Descobrir agora",
  DISCOVERING: "Buscando contas e cartões em cada conexão…",
  NO_CONNECTIONS_YET: "Nenhuma conexão cadastrada ainda.",
  COL_ACTIONS: "Ações",
  COL_BANK: "Banco",
  COL_HOLDER: "Titular",
  COL_CONSENT: "Consentimento",
  COL_FOUND: "Encontrado",
  ACCOUNT_ONE: "1 conta",
  ACCOUNT_MANY: "{0} contas",
  CARD_ONE: "1 cartão de crédito",
  CARD_MANY: "{0} cartões de crédito",
  AND: "e",
  FOUND_ONE_F: "encontrada",
  FOUND_MANY_F: "encontradas",
  FOUND_ONE_M: "encontrado",
  FOUND_MANY_M: "encontrados",
  FOUND_NOTHING: "Nada encontrado",
  FOUND_WAITING: "Aguardando descoberta",
  NOT_SET: "Não vinculado",
  CONSENT_ACTIVE: "Ativo",
  CONSENT_STALE: "Desatualizado",
  CONSENT_REVOKED: "Revogado",
  RUN_PENDING: "Aguardando descoberta",
  RUN_OK: "Descoberta concluída",
  RUN_PARTIAL: "Descoberta incompleta",
  RUN_FAILED: "Falhou — tente de novo",
  DISCOVER_SUMMARY:
    "Descoberta concluída: {0} conta(s) e {1} cartão(ões) — {2} liberada(s) com titular, {3} pendente(s) e {4} divergente(s).",
  DISCOVER_PENDING_HINT:
    " Resolva as pendências e divergências em Confirmar titulares.",
  DISCOVER_NOTHING_RELEASED:
    " Nenhuma fonte foi liberada: confira o banco e o titular da conexão.",
  DISCOVER_CONFLICTS:
    " {0} fonte(s) com banco ou versão em conflito: o valor existente foi preservado para revisão.",
  DISCOVER_FAILED:
    " {0} fonte(s) não puderam ser gravadas: nada foi liberado nelas.",
  DISCOVER_PARTIAL:
    " {0} conexão(ões) não concluíram — revise o consentimento e tente de novo.",
  PENDING_BANK: "Selecionar banco…",
  PENDING_HOLDER: "Selecionar titular…",
  NEW_HOLDER: "Novo titular",
  REFERENCES_SAVED:
    "Banco e titular da conexão atualizados. Eles serão aplicados às contas e cartões desta conexão na próxima descoberta.",
  HOLDER_TYPE: "Tipo de titular",
  PERSON: "Pessoa",
  BUSINESS: "Empresa",
  FIRST_NAME: "Nome",
  LAST_NAME: "Sobrenome",
  BUSINESS_NAME: "Razão social / nome",
  CANCEL: "Cancelar",
  SAVE_HOLDER: "Salvar titular",
  SAVING_HOLDER: "Salvando…",
  CONFIRM_DUPLICATE: "Confirmar mesmo assim",
  HOLDER_SAVED: "Titular criado e definido nesta conexão.",
  HOLDER_REQUIRED: "Informe os dados do titular.",
  NEW_HOLDER_TITLE: "Cadastrar titular",
  NEW_BANK: "Novo banco",
  NEW_BANK_TITLE: "Cadastrar banco",
  BANK_NAME: "Nome da instituição",
  BANK_NUMBER: "Código bancário (COMPE)",
  SAVE_BANK: "Salvar banco",
  SAVING_BANK: "Salvando…",
  BANK_SAVED: "Banco cadastrado e definido nesta conexão.",
  CONNECTION_DETAILS: "Detalhes da conexão",
  EDIT_CONNECTION: "Editar conexão",
  ITEM_ID: "Item ID (mascarado)",
  PROVIDER: "Conector do provedor",
  DELETE_CONNECTION: "Excluir conexão",
  DELETE_TITLE: "Excluir conexão",
  DELETE_QUESTION: "Excluir a conexão {0}?",
  DELETE_WARNING:
    "Contas e cartões em custódia que ainda não estão em uso financeiro são removidos junto. Esta ação não pode ser desfeita.",
  CLOSE: "Fechar"
};

const EN = {
  TITLE: "Find accounts and cards",
  HELP: "Loads the accounts and cards authorized on the configured Pluggy application. It does not import history. The bank and holder set on the connection are applied to every discovered source, which becomes available for use.",
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
    "Each bank you connected on Pluggy has its own Item ID. Register each connection with its Item ID, bank and holder: on discovery, the bank and holder chosen here are applied to every account and card of this connection, which become available for use. The list below is read-only.",
  ITEM_ID_LABEL: "Pluggy Item ID",
  ITEM_ID_HELP:
    "Copy it inside the configured application in the Pluggy dashboard: Aplicações → ▶ → connection → ⋮ → Copiar Item ID. Do not use the MeuPluggy link.",
  REGISTER: "Register connection",
  REGISTER_SAVE: "Register",
  REGISTER_TITLE: "Register Pluggy connection",
  REGISTER_HELP:
    "The connector (for example, MeuPluggy) does not identify the bank: select the right financial institution and the holder. On discovery, the bank and holder chosen here are applied to this connection's accounts and cards, which become available for use. An already confirmed and different holder is never overwritten — resolve the divergence in Confirm holders.",
  REGISTERING: "Registering…",
  DISCOVER_ALL: "Discover now",
  DISCOVERING: "Fetching accounts and cards on each connection…",
  NO_CONNECTIONS_YET: "No connection registered yet.",
  COL_ACTIONS: "Actions",
  COL_BANK: "Bank",
  COL_HOLDER: "Holder",
  COL_CONSENT: "Consent",
  COL_FOUND: "Found",
  ACCOUNT_ONE: "1 account",
  ACCOUNT_MANY: "{0} accounts",
  CARD_ONE: "1 credit card",
  CARD_MANY: "{0} credit cards",
  AND: "and",
  FOUND_ONE_F: "found",
  FOUND_MANY_F: "found",
  FOUND_ONE_M: "found",
  FOUND_MANY_M: "found",
  FOUND_NOTHING: "Nothing found",
  FOUND_WAITING: "Waiting for discovery",
  NOT_SET: "Not linked",
  CONSENT_ACTIVE: "Active",
  CONSENT_STALE: "Stale",
  CONSENT_REVOKED: "Revoked",
  RUN_PENDING: "Waiting for discovery",
  RUN_OK: "Discovery complete",
  RUN_PARTIAL: "Discovery incomplete",
  RUN_FAILED: "Failed — try again",
  DISCOVER_SUMMARY:
    "Discovery complete: {0} account(s) and {1} card(s) — {2} released with a holder, {3} pending and {4} divergent.",
  DISCOVER_PENDING_HINT:
    " Resolve the pending items and divergences in Confirm holders.",
  DISCOVER_NOTHING_RELEASED:
    " No source was released: check the connection's bank and holder.",
  DISCOVER_CONFLICTS:
    " {0} source(s) with a bank or version conflict: the existing value was preserved for review.",
  DISCOVER_FAILED:
    " {0} source(s) could not be written: nothing was released on them.",
  DISCOVER_PARTIAL:
    " {0} connection(s) did not complete — review the consent and try again.",
  PENDING_BANK: "Select bank…",
  PENDING_HOLDER: "Select holder…",
  NEW_HOLDER: "New holder",
  REFERENCES_SAVED:
    "Connection bank and holder updated. They are applied to this connection's accounts and cards on the next discovery.",
  HOLDER_TYPE: "Holder type",
  PERSON: "Person",
  BUSINESS: "Business",
  FIRST_NAME: "First name",
  LAST_NAME: "Last name",
  BUSINESS_NAME: "Company name",
  CANCEL: "Cancel",
  SAVE_HOLDER: "Save holder",
  SAVING_HOLDER: "Saving…",
  CONFIRM_DUPLICATE: "Confirm anyway",
  HOLDER_SAVED: "Holder created and set on this connection.",
  HOLDER_REQUIRED: "Provide the holder details.",
  NEW_HOLDER_TITLE: "Register holder",
  NEW_BANK: "New bank",
  NEW_BANK_TITLE: "Register bank",
  BANK_NAME: "Institution name",
  BANK_NUMBER: "Bank number (COMPE)",
  SAVE_BANK: "Save bank",
  SAVING_BANK: "Saving…",
  BANK_SAVED: "Bank created and set on this connection.",
  CONNECTION_DETAILS: "Connection details",
  EDIT_CONNECTION: "Edit connection",
  ITEM_ID: "Item ID (masked)",
  PROVIDER: "Provider connector",
  DELETE_CONNECTION: "Delete connection",
  DELETE_TITLE: "Delete connection",
  DELETE_QUESTION: "Delete connection {0}?",
  DELETE_WARNING:
    "Accounts and cards in custody that are not yet in financial use are removed as well. This action cannot be undone.",
  CLOSE: "Close"
};

const L = String(LANG || "")
  .toLowerCase()
  .startsWith("en")
  ? EN
  : PT;

const STATE = { LOADING: "LOADING", READY: "READY", ERROR: "ERROR" };

// The "Novo banco"/"Novo titular" modals are shared by the registration form
// (the connection does not exist yet) and by the details modal (existing one).
const REGISTER_TARGET = "REGISTER";

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

function counted(one, many, count) {
  return count === 1 ? one : many.replace("{0}", count);
}

/**
 * Spells out what the last discovery run found on a connection ("1 conta e 1
 * cartão de crédito encontrados") instead of an opaque "1 + 1". Only the two
 * kinds the discovery actually imports exist: bank accounts and credit cards.
 */
function foundLabel(c) {
  const accounts = c.accountsFound || 0;
  const cards = c.cardsFound || 0;
  if (accounts + cards === 0) {
    return c.discovered === true ? L.FOUND_NOTHING : L.FOUND_WAITING;
  }
  const parts = [];
  if (accounts > 0) {
    parts.push(counted(L.ACCOUNT_ONE, L.ACCOUNT_MANY, accounts));
  }
  if (cards > 0) {
    parts.push(counted(L.CARD_ONE, L.CARD_MANY, cards));
  }
  const joined = parts.join(` ${L.AND} `);
  if (accounts > 0 && cards > 0) {
    return `${joined} ${L.FOUND_MANY_M}`;
  }
  if (accounts > 0) {
    return `${joined} ${accounts === 1 ? L.FOUND_ONE_F : L.FOUND_MANY_F}`;
  }
  return `${joined} ${cards === 1 ? L.FOUND_ONE_M : L.FOUND_MANY_M}`;
}

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
  feedback;
  feedbackVariant = "info";
  _wiredStatus;
  _wiredSources;
  _wiredConnections;

  // ---- register-connection modal (Item ID + bank + suggested holder) ----
  registerOpen = false;
  registerSaving = false;
  registerFeedback = "";
  registerForm = { itemId: "", bankInstitutionId: null, holderId: null };

  // ---- inline "Novo titular" modal state ----
  newHolderOpen = false;
  newHolderTarget = null;
  newHolderSaving = false;
  newHolderShowConfirm = false;
  newHolderFeedback = "";
  newHolder = { type: "PERSON", firstName: "", lastName: "", name: "" };

  // ---- inline "Novo banco" modal state ----
  newBankOpen = false;
  newBankTarget = null;
  newBankSaving = false;
  newBankFeedback = "";
  newBank = { name: "", bankNumber: "" };

  // ---- connection details (read-only facts + editable references) ----
  detailsOpen = false;
  detailsConnectionId = null;
  detailsSaving = false;
  detailsFeedback = "";
  detailsFeedbackIsError = false;

  // ---- delete confirmation ----
  deleteOpen = false;
  deleteTargetId = null;
  deleteSaving = false;
  deleteFeedback = "";

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
      institution: s.bankInstitutionName || s.institution,
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
      providerInstitution: c.institution,
      itemIdHint: c.itemIdHint,
      bankInstitutionId: c.bankInstitutionId,
      bankInstitutionName: c.bankInstitutionName,
      bankPending: !c.bankInstitutionId,
      // Provider text stays visible while the canonical bank is pending (AXF-106):
      // existing records never lose the information they already carried.
      bankLabel: c.bankInstitutionName || c.institution || L.NOT_SET,
      holderId: c.holderId,
      holderName: c.holderName,
      holderPending: !c.holderId,
      holderLabel: c.holderName || L.NOT_SET,
      consentLabel: CONSENT_LABEL[c.consentState] || c.consentState || "—",
      consentWarn: c.consentState && c.consentState !== "ACTIVE",
      runLabel: RUN_LABEL[c.runState] || L.RUN_PENDING,
      found: foundLabel(c),
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
  /**
   * The discovery summary must read as what really happened (AXF-106): an error or a
   * warning is never presented with the success styling. Mapped onto the SLDS text-colour
   * utilities already used in this repo.
   */
  get feedbackClass() {
    if (this.feedbackVariant === "error") {
      return "slds-text-color_error";
    }
    if (this.feedbackVariant === "warning") {
      return "slds-text-color_weak";
    }
    if (this.feedbackVariant === "success") {
      return "slds-text-color_success";
    }
    return "";
  }

  // ---- multi-connection (wizard) view ----
  get hasConnections() {
    return this.connections.length > 0;
  }
  get discoverAllDisabled() {
    return this.running || !this.hasConnections;
  }
  get holderTypeOptions() {
    return [
      { label: L.PERSON, value: "PERSON" },
      { label: L.BUSINESS, value: "BUSINESS" }
    ];
  }
  get newHolderIsPerson() {
    return this.newHolder.type === "PERSON";
  }
  get newHolderSaveLabel() {
    return this.newHolderSaving ? L.SAVING_HOLDER : L.SAVE_HOLDER;
  }

  // ---- register-connection modal ----
  get registerSaveLabel() {
    return this.registerSaving ? L.REGISTERING : L.REGISTER_SAVE;
  }
  get registerSaveDisabled() {
    return (
      this.registerSaving ||
      !this.registerForm.itemId ||
      this.registerForm.itemId.trim().length < 3
    );
  }
  openRegister() {
    this.registerForm = { itemId: "", bankInstitutionId: null, holderId: null };
    this.registerFeedback = "";
    this.registerOpen = true;
  }
  closeRegister() {
    this.registerOpen = false;
    this.registerFeedback = "";
  }
  handleRegisterInput(event) {
    this.registerForm = {
      ...this.registerForm,
      itemId: event.detail?.value ?? event.target.value
    };
  }
  handleRegisterBankChange(event) {
    this.registerForm = {
      ...this.registerForm,
      bankInstitutionId: event.detail.recordId || null
    };
  }
  handleRegisterHolderChange(event) {
    this.registerForm = {
      ...this.registerForm,
      holderId: event.detail.recordId || null
    };
  }
  async saveRegister() {
    this.registerSaving = true;
    this.registerFeedback = "";
    const bankInstitutionId = this.registerForm.bankInstitutionId;
    const holderId = this.registerForm.holderId;
    try {
      const res = await registerConnection({
        pluggyItemId: this.registerForm.itemId.trim()
      });
      // The references are a second, optional step: a failure here never hides
      // the fact that the connection was registered.
      let warning = "";
      if (res.connectionId && (bankInstitutionId || holderId)) {
        try {
          await updateReferences({
            connectionId: res.connectionId,
            bankInstitutionId: bankInstitutionId || null,
            holderId: holderId || null
          });
        } catch (refError) {
          warning = this.extractMessage(refError);
        }
      }
      await Promise.resolve(refreshApex(this._wiredConnections)).catch(
        () => {}
      );
      this.setFeedback(
        warning ? `${res.message} ${warning}` : res.message,
        warning ? "warning" : "success"
      );
      this.closeRegister();
    } catch (e) {
      this.registerFeedback = this.extractMessage(e);
    } finally {
      this.registerSaving = false;
    }
  }

  async handleDiscoverAll() {
    this.running = true;
    this.feedback = undefined;
    let accounts = 0;
    let cards = 0;
    // AXF-106 — what the connection's bank and holder did on the discovered sources.
    let released = 0;
    let pending = 0;
    let divergent = 0;
    // AXF-106 — a preserved bank divergence (AC8), a stale source and a refused write (AC6)
    // are outcomes of the run, never a silent success.
    let bankDivergent = 0;
    let conflicts = 0;
    let failed = 0;
    // An incomplete run is a failure of this discovery; a terminal/unknown state or a
    // thrown error is a hard failure. Both are counted, and the FIRST real cause is kept
    // so the summary below can never erase it (AXF-106).
    let incomplete = 0;
    let hardFailure = 0;
    let failureCause = "";
    // One connection per Apex transaction — a callout is never issued after a DML.
    for (const c of this.connections) {
      try {
        // eslint-disable-next-line no-await-in-loop
        const r = await startDiscovery({ connectionId: c.connectionId });
        accounts += r.accountsFound || 0;
        cards += r.cardsFound || 0;
        released += r.released || 0;
        pending += r.pending || 0;
        divergent += r.divergent || 0;
        bankDivergent += r.bankDivergent || 0;
        conflicts += r.conflicts || 0;
        failed += r.failed || 0;
        // A run that left something open — pending, divergent, a preserved bank, a stale
        // source or a refused write — states it in its own message, and that message is the
        // cause the summary must never discard (AXF-106).
        if (
          !failureCause &&
          r.message &&
          (r.complete !== true ||
            (r.pending || 0) > 0 ||
            (r.divergent || 0) > 0 ||
            (r.bankDivergent || 0) > 0 ||
            (r.conflicts || 0) > 0 ||
            (r.failed || 0) > 0)
        ) {
          failureCause = r.message;
        }
        if (r.complete !== true) {
          incomplete += 1;
          if (r.state === "FAILED_TERMINAL" || r.state === "RESULT_UNKNOWN") {
            hardFailure += 1;
          }
        }
      } catch (err) {
        incomplete += 1;
        hardFailure += 1;
        if (!failureCause) {
          failureCause = this.extractMessage(err);
        }
      }
    }

    const found = accounts + cards;
    // The style follows the real result, never the mere absence of a thrown error: a run
    // that found sources and released none of them is not a success (AXF-106).
    let variant = "success";
    if (hardFailure > 0 || failed > 0) {
      variant = "error";
    } else if (
      incomplete > 0 ||
      pending > 0 ||
      divergent > 0 ||
      bankDivergent > 0 ||
      conflicts > 0 ||
      (found > 0 && released === 0)
    ) {
      variant = "warning";
    }

    let summary = L.DISCOVER_SUMMARY.replace("{0}", accounts)
      .replace("{1}", cards)
      .replace("{2}", released)
      .replace("{3}", pending)
      .replace("{4}", divergent);
    if (found > 0 && released === 0) {
      summary += L.DISCOVER_NOTHING_RELEASED;
    }
    if (pending + divergent > 0) {
      summary += L.DISCOVER_PENDING_HINT;
    }
    if (bankDivergent + conflicts > 0) {
      summary += L.DISCOVER_CONFLICTS.replace("{0}", bankDivergent + conflicts);
    }
    if (failed > 0) {
      summary += L.DISCOVER_FAILED.replace("{0}", failed);
    }
    if (incomplete > 0) {
      summary += L.DISCOVER_PARTIAL.replace("{0}", incomplete);
    }
    // The service's own cause survives the summary.
    if (failureCause) {
      summary += ` ${failureCause}`;
    }
    this.setFeedback(summary, variant);
    await Promise.resolve(refreshApex(this._wiredConnections)).catch(() => {});
    this.running = false;
  }

  // ---- bank / holder references ----
  // `target` is either REGISTER_TARGET (the connection does not exist yet — keep
  // the choice in the form) or a connection Id (persist immediately).
  async applyReferences(target, bankInstitutionId, holderId) {
    if (target === REGISTER_TARGET) {
      this.registerForm = { ...this.registerForm, bankInstitutionId, holderId };
      return;
    }
    await updateReferences({
      connectionId: target,
      bankInstitutionId: bankInstitutionId || null,
      holderId: holderId || null
    });
    await Promise.resolve(refreshApex(this._wiredConnections)).catch(() => {});
  }
  setDetailsFeedback(message, isError) {
    this.detailsFeedback = message;
    this.detailsFeedbackIsError = isError === true;
    if (!isError && !this.detailsOpen) {
      this.setFeedback(message, "success");
    }
  }
  async handleDetailsBankChange(event) {
    const conn = this.detailsConnection;
    if (!conn) {
      return;
    }
    this.detailsSaving = true;
    this.detailsFeedback = "";
    try {
      await this.applyReferences(
        conn.connectionId,
        event.detail.recordId || null,
        conn.holderId
      );
      this.setDetailsFeedback(L.REFERENCES_SAVED, false);
    } catch (e) {
      this.setDetailsFeedback(this.extractMessage(e), true);
    } finally {
      this.detailsSaving = false;
    }
  }
  async handleDetailsHolderChange(event) {
    const conn = this.detailsConnection;
    if (!conn) {
      return;
    }
    this.detailsSaving = true;
    this.detailsFeedback = "";
    try {
      await this.applyReferences(
        conn.connectionId,
        conn.bankInstitutionId,
        event.detail.recordId || null
      );
      this.setDetailsFeedback(L.REFERENCES_SAVED, false);
    } catch (e) {
      this.setDetailsFeedback(this.extractMessage(e), true);
    } finally {
      this.detailsSaving = false;
    }
  }

  // ---- inline "Novo titular" ----
  openNewHolder(event) {
    this.newHolderTarget = event.currentTarget.dataset.target;
    this.newHolder = { type: "PERSON", firstName: "", lastName: "", name: "" };
    this.newHolderShowConfirm = false;
    this.newHolderFeedback = "";
    this.newHolderOpen = true;
  }
  closeNewHolder() {
    this.newHolderOpen = false;
    this.newHolderTarget = null;
    this.newHolderShowConfirm = false;
    this.newHolderFeedback = "";
  }
  handleHolderTypeChange(event) {
    this.newHolder = { ...this.newHolder, type: event.detail.value };
  }
  handleHolderInput(event) {
    this.newHolder = {
      ...this.newHolder,
      [event.target.dataset.field]: event.detail?.value ?? event.target.value
    };
  }
  handleSaveNewHolder() {
    this.saveNewHolder(false);
  }
  handleSaveNewHolderConfirm() {
    this.saveNewHolder(true);
  }
  async saveNewHolder(confirmDespiteDuplicates) {
    const target = this.newHolderTarget;
    this.newHolderSaving = true;
    this.newHolderFeedback = "";
    try {
      const res = await saveHolder({
        type: this.newHolder.type,
        firstName: this.newHolder.firstName,
        lastName: this.newHolder.lastName,
        name: this.newHolder.name,
        confirmedDespiteDuplicates: confirmDespiteDuplicates === true
      });
      if (res.outcome === "DUPLICATE_WARNING") {
        this.newHolderShowConfirm = true;
        this.newHolderFeedback = res.message || L.GENERIC_FAIL;
        return;
      }
      if (res.outcome !== "SUCCEEDED" || !res.accountId) {
        this.newHolderFeedback = res.message || L.GENERIC_FAIL;
        return;
      }
      const conn = this.connections.find((c) => c.connectionId === target);
      await this.applyReferences(
        target,
        conn ? conn.bankInstitutionId : null,
        res.accountId
      );
      this.setFeedback(L.HOLDER_SAVED, "success");
      if (this.detailsOpen) {
        this.setDetailsFeedback(L.HOLDER_SAVED, false);
      }
      this.closeNewHolder();
    } catch (e) {
      this.newHolderFeedback = this.extractMessage(e);
    } finally {
      this.newHolderSaving = false;
    }
  }

  // ---- inline "Novo banco" ----
  get newBankSaveLabel() {
    return this.newBankSaving ? L.SAVING_BANK : L.SAVE_BANK;
  }
  openNewBank(event) {
    this.newBankTarget = event.currentTarget.dataset.target;
    this.newBank = { name: "", bankNumber: "" };
    this.newBankFeedback = "";
    this.newBankOpen = true;
  }
  closeNewBank() {
    this.newBankOpen = false;
    this.newBankTarget = null;
    this.newBankFeedback = "";
  }
  handleNewBankInput(event) {
    this.newBank = {
      ...this.newBank,
      [event.target.dataset.field]: event.detail?.value ?? event.target.value
    };
  }
  async saveNewBank() {
    const target = this.newBankTarget;
    this.newBankSaving = true;
    this.newBankFeedback = "";
    try {
      const res = await createBankInstitution({
        name: this.newBank.name,
        bankNumber: this.newBank.bankNumber
      });
      if (res.outcome !== "CREATED" && res.outcome !== "ALREADY") {
        this.newBankFeedback = res.message || L.GENERIC_FAIL;
        return;
      }
      const conn = this.connections.find((c) => c.connectionId === target);
      await this.applyReferences(
        target,
        res.institutionId,
        conn ? conn.holderId : null
      );
      this.setFeedback(L.BANK_SAVED, "success");
      if (this.detailsOpen) {
        this.setDetailsFeedback(L.BANK_SAVED, false);
      }
      this.closeNewBank();
    } catch (e) {
      this.newBankFeedback = this.extractMessage(e);
    } finally {
      this.newBankSaving = false;
    }
  }

  // ---- connection details (read-only facts) ----
  get detailsConnection() {
    return this.connections.find(
      (c) => c.connectionId === this.detailsConnectionId
    );
  }
  openDetails(event) {
    this.detailsConnectionId = event.currentTarget.dataset.connection;
    this.detailsFeedback = "";
    this.detailsFeedbackIsError = false;
    this.detailsOpen = true;
  }
  closeDetails() {
    this.detailsOpen = false;
    this.detailsConnectionId = null;
    this.detailsFeedback = "";
    this.detailsFeedbackIsError = false;
  }

  // ---- delete confirmation ----
  get deleteTarget() {
    return this.connections.find((c) => c.connectionId === this.deleteTargetId);
  }
  get deleteQuestion() {
    const target = this.deleteTarget;
    const itemIdHint =
      target && target.itemIdHint ? target.itemIdHint : L.NOT_SET;
    return L.DELETE_QUESTION.replace("{0}", itemIdHint);
  }
  requestDelete(event) {
    this.deleteTargetId = event.currentTarget.dataset.connection;
    this.deleteFeedback = "";
    this.deleteOpen = true;
  }
  closeDeleteConfirm() {
    this.deleteOpen = false;
    this.deleteTargetId = null;
    this.deleteFeedback = "";
  }
  async confirmDelete() {
    const connectionId = this.deleteTargetId;
    this.deleteSaving = true;
    this.deleteFeedback = "";
    try {
      const res = await deleteConnection({ connectionId });
      if (res.outcome !== "DELETED") {
        // BLOCKED: the sources already carry financial facts or a confirmation.
        this.deleteFeedback = res.message || L.GENERIC_FAIL;
        return;
      }
      await Promise.resolve(refreshApex(this._wiredConnections)).catch(
        () => {}
      );
      this.setFeedback(res.message, "success");
      this.closeDeleteConfirm();
    } catch (e) {
      this.deleteFeedback = this.extractMessage(e);
    } finally {
      this.deleteSaving = false;
    }
  }

  // ---- single-connection actions ----
  /**
   * The single-connection summary must read as what really happened (AXF-106): a refused
   * write, a preserved bank divergence, a version conflict or a source that was found and
   * released by nobody is never presented with the success styling.
   */
  outcomeVariant(res) {
    const r = res || {};
    const found = (r.accountsFound || 0) + (r.cardsFound || 0);
    const unresolved =
      (r.pending || 0) +
      (r.divergent || 0) +
      (r.bankDivergent || 0) +
      (r.conflicts || 0);
    // A refused or blocked run is never a success; the previous contract (a run that did
    // not succeed is an error unless it is merely retryable) is preserved here.
    if (
      (r.failed || 0) > 0 ||
      r.state === "RUNNING" ||
      r.state === "FAILED_TERMINAL" ||
      r.state === "RESULT_UNKNOWN"
    ) {
      return "error";
    }
    if (
      r.complete !== true ||
      r.state === "FAILED_RETRYABLE" ||
      unresolved > 0 ||
      (found > 0 && (r.released || 0) === 0)
    ) {
      return "warning";
    }
    return "success";
  }

  /** @description The run's own message, plus what it left open. */
  outcomeMessage(res) {
    const r = res || {};
    let text = r.message || L.GENERIC_FAIL;
    if ((r.failed || 0) > 0) {
      text += L.DISCOVER_FAILED.replace("{0}", r.failed);
    }
    if ((r.pending || 0) + (r.divergent || 0) > 0) {
      text += L.DISCOVER_PENDING_HINT;
    }
    if ((r.bankDivergent || 0) + (r.conflicts || 0) > 0) {
      text += L.DISCOVER_CONFLICTS.replace(
        "{0}",
        (r.bankDivergent || 0) + (r.conflicts || 0)
      );
    }
    return text;
  }

  async handleStart() {
    this.running = true;
    this.feedback = undefined;
    try {
      const res = await startDiscovery({ connectionId: this.connectionId });
      this.status = res;
      // The variant comes from the real outcome of the run, never from the mere absence of
      // a thrown error (AXF-106).
      this.setFeedback(this.outcomeMessage(res), this.outcomeVariant(res));
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
