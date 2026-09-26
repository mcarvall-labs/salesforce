import { LightningElement, track, wire } from "lwc";
import LANG from "@salesforce/i18n/lang";
import getOverview from "@salesforce/apex/AXF_CLS_CTRL_SourceHolderConfirmation.getOverview";
import confirmHolder from "@salesforce/apex/AXF_CLS_CTRL_SourceHolderConfirmation.confirmHolder";
import { refreshApex } from "@salesforce/apex";

const PT = {
  title: "Confirmar titulares das contas e cartões",
  subtitle:
    "Relacione cada conta ou cartão descoberto à pessoa ou empresa correta. Só fontes com titular confirmado ficam disponíveis para uso.",
  forbidden: "Você não tem autorização para confirmar titulares.",
  pending: "Fontes pendentes",
  released: "Fontes liberadas",
  none: "Nenhuma fonte pendente.",
  holder: "Titular (pessoa ou empresa)",
  confirm: "Confirmar titular",
  bank: "Conta bancária",
  card: "Cartão",
  allDone: "Todas as fontes descobertas têm titular confirmado.",
  pickHolder: "Selecione o titular antes de confirmar.",
  empty:
    "Nenhuma fonte descoberta ainda. Descubra as contas e cartões para confirmar os titulares.",
  noReleased: "Nenhuma fonte liberada ainda.",
  loadError: "Não foi possível carregar as fontes. Tente novamente.",
  retry: "Tentar novamente",
  currentHolder: "Titular atual",
  unlinked: "Sem titular vinculado",
  divergent: "Divergente do titular da conexão",
  fix: "Corrigir titular",
  fixHelp:
    "Trocar o titular mantém o vínculo anterior no histórico e libera a fonte para o novo titular."
};
const EN = {
  title: "Confirm the account and card holders",
  subtitle:
    "Link every discovered account or card to the right person or company. Only sources with a confirmed holder become usable.",
  forbidden: "You are not authorized to confirm holders.",
  pending: "Pending sources",
  released: "Released sources",
  none: "No pending source.",
  holder: "Holder (person or company)",
  confirm: "Confirm holder",
  bank: "Bank account",
  card: "Credit card",
  allDone: "Every discovered source has a confirmed holder.",
  pickHolder: "Select the holder before confirming.",
  empty:
    "No source discovered yet. Discover the accounts and cards to confirm their holders.",
  noReleased: "No released source yet.",
  loadError: "Could not load the sources. Try again.",
  retry: "Try again",
  currentHolder: "Current holder",
  unlinked: "No holder linked",
  divergent: "Diverges from the connection holder",
  fix: "Fix holder",
  fixHelp:
    "Changing the holder keeps the previous link in history and releases the source to the new holder."
};
const L = String(LANG || "")
  .toLowerCase()
  .startsWith("en")
  ? EN
  : PT;

export default class AxfLwcConfirmSourceHolders extends LightningElement {
  labels = L;
  forbidden = false;
  loading = true;
  loadError = false;
  @track pending = [];
  @track released = [];
  @track divergent = [];
  @track selection = {};
  message = null;
  busySourceId = null;
  _wired;

  @wire(getOverview)
  wiredOverview(result) {
    this._wired = result;
    if (result.error) {
      this.loadError = true;
      this.forbidden = false;
      this.loading = false;
      return;
    }
    if (!result.data) {
      return;
    }
    this.loadError = false;
    this.forbidden = result.data.forbidden === true;
    this.pending = (result.data.pending || []).map((s) => this.decorate(s));
    this.released = (result.data.released || []).map((s) => this.decorate(s));
    this.divergent = (result.data.divergent || []).map((s) => this.decorate(s));
    this.loading = false;
  }

  decorate(s) {
    return {
      ...s,
      kindLabel: s.kind === "BANK" ? L.bank : L.card,
      // Canonical institution name when confirmed, provider text otherwise (AXF-106).
      // Computed here because templates cannot hold logical expressions (LWC1060).
      institutionLabel: s.bankInstitutionName || s.institutionName,
      currentHolderLabel: s.holderName || L.unlinked,
      rowClass: "slds-box slds-box_x-small slds-var-m-bottom_x-small",
      busy: this.busySourceId === s.sourceId
    };
  }

  get hasPending() {
    return this.pending.length > 0;
  }

  get hasReleased() {
    return this.released.length > 0;
  }

  get isEmpty() {
    return (
      !this.loading &&
      !this.forbidden &&
      !this.loadError &&
      this.pending.length === 0 &&
      this.released.length === 0
    );
  }

  get releasedCount() {
    return this.released.length;
  }

  handleHolder(event) {
    const sourceId = event.target.dataset.source;
    this.selection = {
      ...this.selection,
      [sourceId]: event.detail.recordId || null
    };
  }

  async handleConfirm(event) {
    await this.submit(event.target);
  }

  async handleFix(event) {
    await this.submit(event.target);
  }

  // Same contract for a pending confirmation and for fixing an already released
  // source: the holder, the source version read by the overview and the primitive
  // controller signature. Correcting supersedes the previous link (AXF-85 AC5).
  async submit(button) {
    const sourceId = button.dataset.source;
    const kind = button.dataset.kind;
    const version = Number(button.dataset.version);
    const holderId = this.selection[sourceId];
    if (!holderId) {
      this.message = L.pickHolder;
      this.moveFocusToStatus();
      return;
    }
    this.busySourceId = sourceId;
    // Both lists are re-decorated so the row being submitted — pending or released —
    // takes the busy flag immediately and its button is disabled on the template while
    // the server call is in flight (review patch: no double submit).
    this.pending = this.pending.map((s) => this.decorate(s));
    this.released = this.released.map((s) => this.decorate(s));
    try {
      // Primitive params: the controller does not accept the service's inner DTO.
      const r = await confirmHolder({
        sourceId,
        kind,
        holderId,
        expectedVersion: version
      });
      this.message = r.message;
      await refreshApex(this._wired);
    } catch (e) {
      this.message = (e && e.body && e.body.message) || String(e);
    } finally {
      // Clearing the busy source must also clear the per-row flag in the same pass,
      // otherwise the row stays disabled until the next wire emission (review patch).
      this.busySourceId = null;
      this.pending = this.pending.map((s) => this.decorate(s));
      this.released = this.released.map((s) => this.decorate(s));
    }
    this.moveFocusToStatus();
  }

  handleRetry() {
    this.loading = true;
    this.loadError = false;
    refreshApex(this._wired).catch(() => {
      this.loadError = true;
      this.loading = false;
    });
  }

  moveFocusToStatus() {
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    window.requestAnimationFrame(() => {
      const el = this.template.querySelector("[data-status]");
      if (el) {
        el.focus();
      }
    });
  }
}
