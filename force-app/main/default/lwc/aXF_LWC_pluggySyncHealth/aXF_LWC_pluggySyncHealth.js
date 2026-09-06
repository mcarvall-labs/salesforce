import { LightningElement, api, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import health from "@salesforce/apex/AXF_CLS_CTRL_PluggySync.health";
import syncNow from "@salesforce/apex/AXF_CLS_CTRL_PluggySync.syncNow";
import LANG from "@salesforce/i18n/lang";

// Component-local i18n (org has no Translation Workbench). Axon ships PT-BR + EN
// only; the language follows the Salesforce user profile (@salesforce/i18n/lang).
const PT = {
  TITLE: "Sincronização de transações",
  HELP: "Sincroniza as transações das contas e cartões com titular confirmado. A sincronização diária roda no mesmo processamento.",
  SYNC_NOW: "Sincronizar agora",
  BUSY: "Iniciando…",
  EMPTY: "Nenhuma conta ou cartão com titular confirmado nesta conexão.",
  LOAD_ERROR: "Não foi possível carregar o estado da sincronização.",
  RETRY: "Tentar novamente",
  COL_SCOPE: "Conta / cartão",
  COL_STATE: "Estado",
  COL_THROUGH: "Completo até",
  COL_LAST: "Último sucesso",
  COL_NEXT: "Próxima ação",
  NEVER: "Ainda não sincronizado",
  KIND_BANK: "Conta",
  KIND_CARD: "Cartão",
  GENERIC_FAIL: "A operação não foi concluída. Nada foi alterado.",
  STATE_SUCCEEDED: "Concluída",
  STATE_RUNNING: "Em andamento",
  STATE_FAILED_RETRYABLE: "Falha temporária",
  STATE_FAILED_TERMINAL: "Falha — requer ação",
  STATE_RESULT_UNKNOWN: "Resultado desconhecido",
  STATE_WAITING: "Aguardando"
};

const EN = {
  TITLE: "Transaction sync",
  HELP: "Syncs transactions for accounts and cards with a confirmed holder. The daily schedule runs the same processing.",
  SYNC_NOW: "Sync now",
  BUSY: "Starting…",
  EMPTY: "No account or card with a confirmed holder on this connection.",
  LOAD_ERROR: "Could not load the sync status.",
  RETRY: "Try again",
  COL_SCOPE: "Account / card",
  COL_STATE: "State",
  COL_THROUGH: "Complete through",
  COL_LAST: "Last success",
  COL_NEXT: "Next action",
  NEVER: "Not synced yet",
  KIND_BANK: "Account",
  KIND_CARD: "Card",
  GENERIC_FAIL: "The operation did not complete. Nothing was changed.",
  STATE_SUCCEEDED: "Done",
  STATE_RUNNING: "In progress",
  STATE_FAILED_RETRYABLE: "Temporary failure",
  STATE_FAILED_TERMINAL: "Failed — needs action",
  STATE_RESULT_UNKNOWN: "Unknown result",
  STATE_WAITING: "Waiting"
};

const L = String(LANG || "")
  .toLowerCase()
  .startsWith("en")
  ? EN
  : PT;
const LOCALE = L === EN ? "en-US" : "pt-BR";

export default class AxfPluggySyncHealth extends LightningElement {
  @api recordId; // AXF_OBJ_PluggyConnection__c, when placed on its record page
  @api connectionId; // explicit override for app pages

  labels = L;
  rows = [];
  loadError = false;
  busy = false;
  feedback;
  _wired;

  get scopeId() {
    return this.connectionId || this.recordId;
  }

  @wire(health, { connectionId: "$scopeId" })
  wiredHealth(result) {
    this._wired = result;
    const { data, error } = result;
    if (error) {
      this.loadError = true;
      return;
    }
    if (!data) {
      return;
    }
    this.loadError = false;
    this.rows = data.map((r, i) => ({
      key: `${r.pluggyAccountId || i}`,
      scopeLabel: `${r.kind === "CARD" ? L.KIND_CARD : L.KIND_BANK} ····${(
        r.pluggyAccountId || ""
      ).slice(-4)}`,
      stateLabel: L[`STATE_${r.state || "WAITING"}`] || L.STATE_WAITING,
      completeThrough: r.completeThrough
        ? new Date(r.completeThrough).toLocaleDateString(LOCALE)
        : L.NEVER,
      lastSuccessAt: r.lastSuccessAt
        ? new Date(r.lastSuccessAt).toLocaleString(LOCALE)
        : L.NEVER,
      nextAction: r.nextAction,
      cause: r.cause
    }));
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  get isEmpty() {
    return !this.loadError && !this.busy && this.rows.length === 0;
  }

  get syncDisabled() {
    return this.busy || !this.scopeId;
  }

  async handleSyncNow() {
    this.busy = true;
    this.feedback = undefined;
    try {
      this.feedback = await syncNow({ connectionId: this.scopeId });
    } catch (e) {
      this.feedback = this.extractMessage(e);
    } finally {
      this.busy = false;
    }
    try {
      await refreshApex(this._wired);
    } catch (e) {
      // a stale board is not worth overriding the action feedback
    }
  }

  handleRetry() {
    this.loadError = false;
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
}
