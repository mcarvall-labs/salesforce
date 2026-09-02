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
  pickHolder: "Selecione o titular antes de confirmar."
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
  pickHolder: "Select the holder before confirming."
};
const L = String(LANG || "")
  .toLowerCase()
  .startsWith("en")
  ? EN
  : PT;

export default class AxfLwcConfirmSourceHolders extends LightningElement {
  labels = L;
  forbidden = false;
  @track pending = [];
  @track released = [];
  @track selection = {};
  message = null;
  _wired;

  @wire(getOverview)
  wiredOverview(result) {
    this._wired = result;
    if (result.data) {
      this.forbidden = result.data.forbidden === true;
      this.pending = (result.data.pending || []).map((s) => this.decorate(s));
      this.released = (result.data.released || []).map((s) => this.decorate(s));
    }
  }

  decorate(s) {
    return {
      ...s,
      kindLabel: s.kind === "BANK" ? L.bank : L.card,
      rowClass: "slds-box slds-box_x-small slds-var-m-bottom_x-small"
    };
  }

  get hasPending() {
    return this.pending.length > 0;
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
    const sourceId = event.target.dataset.source;
    const kind = event.target.dataset.kind;
    const version = Number(event.target.dataset.version);
    const holderId = this.selection[sourceId];
    if (!holderId) {
      this.message = L.pickHolder;
      this.moveFocusToStatus();
      return;
    }
    try {
      const r = await confirmHolder({
        input: { sourceId, kind, holderId, expectedVersion: version }
      });
      this.message = r.message;
      await refreshApex(this._wired);
    } catch (e) {
      this.message = (e && e.body && e.body.message) || String(e);
    }
    this.moveFocusToStatus();
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
