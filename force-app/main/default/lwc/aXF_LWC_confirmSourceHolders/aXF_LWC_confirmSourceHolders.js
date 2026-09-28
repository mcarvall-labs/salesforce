import { LightningElement, track, wire } from "lwc";
import LANG from "@salesforce/i18n/lang";
import getOverview from "@salesforce/apex/AXF_CLS_CTRL_SourceHolderConfirmation.getOverview";
import confirmHolder from "@salesforce/apex/AXF_CLS_CTRL_SourceHolderConfirmation.confirmHolder";
import { refreshApex } from "@salesforce/apex";

const PT = {
  title: "Confirmar titulares das contas e cartões",
  subtitle:
    "Relacione cada conta ou cartão descoberto à pessoa ou empresa correta. O titular já usado na conexão vem pré-selecionado; corrija o que estiver errado e confirme tudo de uma vez. Só fontes com titular confirmado ficam disponíveis para uso.",
  forbidden: "Você não tem autorização para confirmar titulares.",
  pending: "Fontes pendentes",
  released: "Fontes liberadas",
  none: "Nenhuma fonte pendente.",
  holder: "Titular (pessoa ou empresa)",
  confirmAll: "Confirmar",
  bank: "Conta bancária",
  card: "Cartão",
  allDone: "Todas as fontes descobertas têm titular confirmado.",
  pickAtLeastOne:
    "Selecione o titular de ao menos uma fonte antes de confirmar.",
  empty:
    "Nenhuma fonte descoberta ainda. Descubra as contas e cartões para confirmar os titulares.",
  noReleased: "Nenhuma fonte liberada ainda.",
  loadError: "Não foi possível carregar as fontes. Tente novamente.",
  retry: "Tentar novamente",
  currentHolder: "Titular atual",
  unlinked: "Sem titular vinculado",
  divergent: "Divergente do titular da conexão",
  fixHelp:
    "Trocar o titular mantém o vínculo anterior no histórico e libera a fonte para o novo titular.",
  confirmedOne: "1 titular confirmado.",
  confirmedMany: "{0} titulares confirmados.",
  genericFail: "Não foi possível confirmar os titulares selecionados."
};
const EN = {
  title: "Confirm the account and card holders",
  subtitle:
    "Link every discovered account or card to the right person or company. The holder already used on the connection comes pre-selected; fix whatever is wrong and confirm everything at once. Only sources with a confirmed holder become usable.",
  forbidden: "You are not authorized to confirm holders.",
  pending: "Pending sources",
  released: "Released sources",
  none: "No pending source.",
  holder: "Holder (person or company)",
  confirmAll: "Confirm",
  bank: "Bank account",
  card: "Credit card",
  allDone: "Every discovered source has a confirmed holder.",
  pickAtLeastOne: "Select the holder of at least one source before confirming.",
  empty:
    "No source discovered yet. Discover the accounts and cards to confirm their holders.",
  noReleased: "No released source yet.",
  loadError: "Could not load the sources. Try again.",
  retry: "Try again",
  currentHolder: "Current holder",
  unlinked: "No holder linked",
  divergent: "Diverges from the connection holder",
  fixHelp:
    "Changing the holder keeps the previous link in history and releases the source to the new holder.",
  confirmedOne: "1 holder confirmed.",
  confirmedMany: "{0} holders confirmed.",
  genericFail: "Could not confirm the selected holders."
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
  busy = false;
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
    const rawPending = result.data.pending || [];
    const rawReleased = result.data.released || [];
    const rawDivergent = result.data.divergent || [];
    // Seed the picker with the suggested holder the first time a source is seen —
    // a value the administrator already picked, or already confirmed on a prior
    // partial submit, is never clobbered by a fresh read of the overview.
    const seeded = { ...this.selection };
    [...rawPending, ...rawReleased].forEach((s) => {
      if (!(s.sourceId in seeded)) {
        seeded[s.sourceId] = s.suggestedHolderId || null;
      }
    });
    this.selection = seeded;
    this.pending = rawPending.map((s) => this.decorate(s));
    this.released = rawReleased.map((s) => this.decorate(s));
    this.divergent = rawDivergent.map((s) => this.decorate(s));
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
      pickerValue: this.selection[s.sourceId] || null
    };
  }

  get hasPending() {
    return this.pending.length > 0;
  }

  get hasReleased() {
    return this.released.length > 0;
  }

  get hasAnySource() {
    return this.hasPending || this.hasReleased;
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

  get confirmDisabled() {
    return this.busy || !this.hasAnySource;
  }

  handleHolder(event) {
    const sourceId = event.target.dataset.source;
    this.selection = {
      ...this.selection,
      [sourceId]: event.detail.recordId || null
    };
    this.pending = this.pending.map((s) => this.decorate(s));
    this.released = this.released.map((s) => this.decorate(s));
  }

  // A single confirmation for every change made on this screen (pending sources
  // that got a holder — suggested or picked — and released sources whose holder
  // was corrected). A row whose picker still matches its current holder is a
  // no-op and is never submitted.
  async handleConfirmAll() {
    if (this.busy) {
      return;
    }
    const rows = [...this.pending, ...this.released];
    const toSubmit = rows.filter((s) => {
      const chosen = this.selection[s.sourceId];
      return !!chosen && chosen !== s.holderId;
    });
    if (toSubmit.length === 0) {
      this.message = L.pickAtLeastOne;
      this.moveFocusToStatus();
      return;
    }
    this.busy = true;
    this.message = null;
    let okCount = 0;
    let failMessage = null;
    // Sequential: each confirmation is its own transaction, and a failure on one
    // source must never block the others from being submitted.
    for (const s of toSubmit) {
      try {
        // eslint-disable-next-line no-await-in-loop
        const r = await confirmHolder({
          sourceId: s.sourceId,
          kind: s.kind,
          holderId: this.selection[s.sourceId],
          expectedVersion: s.version
        });
        if (
          r.outcome === "CONFIRMED" ||
          r.outcome === "CORRECTED" ||
          r.outcome === "ALREADY"
        ) {
          okCount += 1;
        } else if (!failMessage) {
          failMessage = r.message;
        }
      } catch (e) {
        if (!failMessage) {
          failMessage = this.extractMessage(e);
        }
      }
    }
    this.busy = false;
    await refreshApex(this._wired);
    this.message = failMessage
      ? failMessage
      : okCount === 1
        ? L.confirmedOne
        : L.confirmedMany.replace("{0}", String(okCount));
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

  extractMessage(e) {
    return (e && e.body && e.body.message) || L.genericFail;
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
