import { LightningElement, api } from "lwc";
import getContext from "@salesforce/apex/AXF_CLS_CTRL_EconomicAllocation.getContext";
import propose from "@salesforce/apex/AXF_CLS_CTRL_EconomicAllocation.propose";
import confirm from "@salesforce/apex/AXF_CLS_CTRL_EconomicAllocation.confirm";
import discard from "@salesforce/apex/AXF_CLS_CTRL_EconomicAllocation.discard";
import title from "@salesforce/label/c.AXF_EconomicAllocation_title";
import intro from "@salesforce/label/c.AXF_EconomicAllocation_intro";
import fact from "@salesforce/label/c.AXF_EconomicAllocation_fact";
import holder from "@salesforce/label/c.AXF_EconomicAllocation_holder";
import amount from "@salesforce/label/c.AXF_EconomicAllocation_amount";
import person from "@salesforce/label/c.AXF_EconomicAllocation_person";
import percent from "@salesforce/label/c.AXF_EconomicAllocation_percent";
import shareLabel from "@salesforce/label/c.AXF_EconomicAllocation_share";
import addShare from "@salesforce/label/c.AXF_EconomicAllocation_addShare";
import removeShare from "@salesforce/label/c.AXF_EconomicAllocation_removeShare";
import total from "@salesforce/label/c.AXF_EconomicAllocation_total";
import proposeLabel from "@salesforce/label/c.AXF_EconomicAllocation_propose";
import confirmLabel from "@salesforce/label/c.AXF_EconomicAllocation_confirm";
import confirmTitle from "@salesforce/label/c.AXF_EconomicAllocation_confirmTitle";
import confirmBody from "@salesforce/label/c.AXF_EconomicAllocation_confirmBody";
import yes from "@salesforce/label/c.AXF_EconomicAllocation_yes";
import cancel from "@salesforce/label/c.AXF_EconomicAllocation_cancel";
import revisions from "@salesforce/label/c.AXF_EconomicAllocation_revisions";
import revision from "@salesforce/label/c.AXF_EconomicAllocation_revision";
import stateFieldLabel from "@salesforce/label/c.AXF_EconomicAllocation_state";
import effectiveAt from "@salesforce/label/c.AXF_EconomicAllocation_effectiveAt";
import noSets from "@salesforce/label/c.AXF_EconomicAllocation_noSets";
import proposed from "@salesforce/label/c.AXF_EconomicAllocation_proposed";
import confirmed from "@salesforce/label/c.AXF_EconomicAllocation_confirmed";
import loading from "@salesforce/label/c.AXF_EconomicAllocation_loading";
import errorLabel from "@salesforce/label/c.AXF_EconomicAllocation_error";
import codeForbidden from "@salesforce/label/c.AXF_EconomicAllocation_codeForbidden";
import codeNotAccessible from "@salesforce/label/c.AXF_EconomicAllocation_codeNotAccessible";
import codeConflict from "@salesforce/label/c.AXF_EconomicAllocation_codeConflict";
import codeInvalidShares from "@salesforce/label/c.AXF_EconomicAllocation_codeInvalidShares";
import codeConfirmationRejected from "@salesforce/label/c.AXF_EconomicAllocation_codeConfirmationRejected";
import codeActiveSetExists from "@salesforce/label/c.AXF_EconomicAllocation_codeActiveSetExists";
import codeNotDraft from "@salesforce/label/c.AXF_EconomicAllocation_codeNotDraft";
import codeFactNotAllocatable from "@salesforce/label/c.AXF_EconomicAllocation_codeFactNotAllocatable";
import codeInvalidInput from "@salesforce/label/c.AXF_EconomicAllocation_codeInvalidInput";
import reasonNonPositive from "@salesforce/label/c.AXF_EconomicAllocation_reasonNonPositive";
import reasonDuplicate from "@salesforce/label/c.AXF_EconomicAllocation_reasonDuplicate";
import reasonUnauthorized from "@salesforce/label/c.AXF_EconomicAllocation_reasonUnauthorized";
import reasonTotalExceeds from "@salesforce/label/c.AXF_EconomicAllocation_reasonTotalExceeds";
import reasonTotalNot100 from "@salesforce/label/c.AXF_EconomicAllocation_reasonTotalNot100";
import reasonFactChanged from "@salesforce/label/c.AXF_EconomicAllocation_reasonFactChanged";
import reasonActiveExists from "@salesforce/label/c.AXF_EconomicAllocation_reasonActiveExists";
import codeRejected from "@salesforce/label/c.AXF_EconomicAllocation_codeRejected";
import codeLocked from "@salesforce/label/c.AXF_EconomicAllocation_codeLocked";
import reasonFactNotSettled from "@salesforce/label/c.AXF_EconomicAllocation_reasonFactNotSettled";
import reasonMagnitude from "@salesforce/label/c.AXF_EconomicAllocation_reasonMagnitude";
import readOnlyNotice from "@salesforce/label/c.AXF_EconomicAllocation_readOnlyNotice";
import discardLabel from "@salesforce/label/c.AXF_EconomicAllocation_discard";
import discarded from "@salesforce/label/c.AXF_EconomicAllocation_discarded";
import stateDRAFT from "@salesforce/label/c.AXF_EconomicAllocation_stateDRAFT";
import stateCONFIRMED from "@salesforce/label/c.AXF_EconomicAllocation_stateCONFIRMED";
import stateSUPERSEDED from "@salesforce/label/c.AXF_EconomicAllocation_stateSUPERSEDED";
import stateREVERSED from "@salesforce/label/c.AXF_EconomicAllocation_stateREVERSED";
import stateDISCARDED from "@salesforce/label/c.AXF_EconomicAllocation_stateDISCARDED";
import duplicateHolder from "@salesforce/label/c.AXF_EconomicAllocation_duplicateHolder";

const labels = {
  title,
  intro,
  fact,
  holder,
  amount,
  person,
  percent,
  share: shareLabel,
  addShare,
  removeShare,
  total,
  propose: proposeLabel,
  confirm: confirmLabel,
  confirmTitle,
  confirmBody,
  yes,
  cancel,
  revisions,
  revision,
  state: stateFieldLabel,
  effectiveAt,
  noSets,
  proposed,
  confirmed,
  loading,
  error: errorLabel,
  codeForbidden,
  codeNotAccessible,
  codeConflict,
  codeInvalidShares,
  codeConfirmationRejected,
  codeActiveSetExists,
  codeNotDraft,
  codeFactNotAllocatable,
  codeInvalidInput,
  reasonNonPositive,
  reasonDuplicate,
  reasonUnauthorized,
  reasonTotalExceeds,
  reasonTotalNot100,
  reasonFactChanged,
  reasonActiveExists,
  codeRejected,
  codeLocked,
  reasonFactNotSettled,
  reasonMagnitude,
  readOnlyNotice,
  discard: discardLabel,
  discarded,
  stateDRAFT,
  stateCONFIRMED,
  stateSUPERSEDED,
  stateREVERSED,
  stateDISCARDED,
  duplicateHolder
};

const CODE_LABELS = {
  FORBIDDEN: "codeForbidden",
  NOT_ACCESSIBLE: "codeNotAccessible",
  CONFLICT: "codeConflict",
  INVALID_SHARES: "codeInvalidShares",
  CONFIRMATION_REJECTED: "codeConfirmationRejected",
  ACTIVE_SET_EXISTS: "codeActiveSetExists",
  NOT_DRAFT: "codeNotDraft",
  FACT_NOT_ALLOCATABLE: "codeFactNotAllocatable",
  INVALID_INPUT: "codeInvalidInput",
  REJECTED: "codeRejected",
  LOCKED: "codeLocked",
  UNEXPECTED: "error"
};
const REASON_LABELS = {
  NON_POSITIVE_SHARE: "reasonNonPositive",
  DUPLICATE_ACCOUNT: "reasonDuplicate",
  UNAUTHORIZED_ACCOUNT: "reasonUnauthorized",
  TOTAL_EXCEEDS_100: "reasonTotalExceeds",
  TOTAL_NOT_100: "reasonTotalNot100",
  FACT_CHANGED: "reasonFactChanged",
  ACTIVE_SET_EXISTS: "reasonActiveExists",
  FACT_NOT_SETTLED: "reasonFactNotSettled",
  MAGNITUDE_NOT_CONSERVED: "reasonMagnitude"
};

export function failureCode(error) {
  try {
    return JSON.parse(error?.body?.message).code;
  } catch {
    return error?.body?.message;
  }
}
export function stateLabel(state) {
  return labels[`state${state}`] || state;
}

export function parseFailure(error) {
  const raw = error?.body?.message;
  try {
    const parsed = JSON.parse(raw);
    return {
      message: labels[CODE_LABELS[parsed.code]] || labels.error,
      reasons: (parsed.reasons || []).map((reason) => {
        const code = String(reason).split(":")[0];
        return labels[REASON_LABELS[code]] || reason;
      })
    };
  } catch {
    return { message: labels[CODE_LABELS[raw]] || labels.error, reasons: [] };
  }
}

function operationKey() {
  if (typeof crypto !== "undefined" && crypto.randomUUID) {
    return crypto.randomUUID();
  }
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
    const r = Math.floor(Math.random() * 16);
    return (c === "x" ? r : (r & 3) | 8).toString(16);
  });
}
function format(template, ...values) {
  return values.reduce(
    (text, value, index) => text.replace(`{${index}}`, value),
    template
  );
}

export default class EconomicAllocation extends LightningElement {
  _recordId;
  @api
  get recordId() {
    return this._recordId;
  }
  set recordId(value) {
    const changed = value !== this._recordId;
    this._recordId = value;
    if (changed && value && this.isConnected) this.load();
  }
  labels = labels;
  context = { canAllocate: false, factKind: "", holders: [], sets: [] };
  shares = [];
  busy = false;
  error;
  reasons = [];
  success;
  confirmation;
  proposeKey = operationKey();
  confirmKey = operationKey();

  connectedCallback() {
    if (this.recordId) this.load();
  }
  renderedCallback() {
    if (this.confirmation && !this.confirmation.focused) {
      this.confirmation = { ...this.confirmation, focused: true };
      const button = this.template.querySelector('[data-id="confirm-yes"]');
      if (button) button.focus();
    }
  }

  get holderOptions() {
    return (this.context.holders || []).map((row) => ({
      label: row.label,
      value: row.accountId
    }));
  }
  get sets() {
    const rows = this.context.sets || [];
    const hasConfirmed = rows.some((set) => set.state === "CONFIRMED");
    return rows.map((set) => ({
      ...set,
      stateLabel: stateLabel(set.state),
      // A draft is only actionable while no confirmed revision is active.
      isDraft:
        set.state === "DRAFT" && !hasConfirmed && this.context.canAllocate,
      isConfirmed: set.state === "CONFIRMED",
      totalPercentText: Number(set.totalPercent || 0).toFixed(2),
      shares: (set.shares || []).map((share) => ({
        ...share,
        percentText: Number(share.percent || 0).toFixed(2)
      }))
    }));
  }
  get readOnly() {
    return this.context && this.context.canAllocate === false;
  }
  get reasonRows() {
    return this.reasons.map((text, index) => ({ key: index, text }));
  }
  get activeDraft() {
    return this.sets.find((set) => set.isDraft);
  }
  get confirmedSet() {
    return this.sets.find((set) => set.isConfirmed);
  }
  get hasSets() {
    return this.sets.length > 0;
  }
  get showComposer() {
    return this.context.canAllocate && !this.activeDraft && !this.confirmedSet;
  }
  get shareRows() {
    return this.shares.map((share, index) => ({ ...share, index }));
  }
  get total() {
    return this.shares
      .reduce((sum, share) => sum + Number(share.percent || 0), 0)
      .toFixed(2);
  }
  get hasDuplicateHolder() {
    const ids = this.shares.map((share) => share.accountId).filter(Boolean);
    return new Set(ids).size !== ids.length;
  }
  get totalIs100() {
    return Number(this.total) === 100;
  }
  get totalClass() {
    return this.totalIs100 ? "axf-total_ok" : "axf-total_off";
  }
  get proposeDisabled() {
    return (
      this.busy ||
      this.shares.length === 0 ||
      this.hasDuplicateHolder ||
      Number(this.total) > 100 ||
      this.shares.some(
        (share) => !share.accountId || !(Number(share.percent) > 0)
      )
    );
  }
  get confirmationBody() {
    if (!this.confirmation?.set) return "";
    return format(
      labels.confirmBody,
      this.confirmation.set.revision,
      this.confirmation.set.factName
    );
  }
  handleDialogKey(event) {
    if (event.key === "Escape") this.cancelConfirmation();
  }
  get hasReasons() {
    return this.reasons.length > 0;
  }

  async load() {
    this.busy = true;
    this.error = undefined;
    try {
      this.context = await getContext({ factId: this.recordId });
    } catch (failure) {
      const parsed = parseFailure(failure);
      this.error = parsed.message;
      this.reasons = parsed.reasons;
    } finally {
      this.busy = false;
    }
  }
  addShare() {
    this.shares = [...this.shares, { accountId: "", percent: "" }];
  }
  removeShare(event) {
    const index = Number(event.target.dataset.index);
    this.shares = this.shares.filter((share, i) => i !== index);
  }
  handleShareField(event) {
    const { index, field } = event.target.dataset;
    const value = event.detail?.value ?? event.target.value;
    this.shares = this.shares.map((share, i) => {
      return i === Number(index) ? { ...share, [field]: value } : share;
    });
  }
  async handlePropose() {
    this.reset();
    this.busy = true;
    try {
      await propose({
        request: JSON.stringify({
          factKind: this.context.factKind,
          factId: this.recordId,
          operationKey: this.proposeKey,
          shares: this.shares.map((share) => ({
            accountId: share.accountId,
            percent: Number(share.percent)
          }))
        })
      });
      this.success = labels.proposed;
      this.proposeKey = operationKey();
      this.shares = [];
      await this.load();
    } catch (failure) {
      const parsed = parseFailure(failure);
      this.error = parsed.message;
      this.reasons = parsed.reasons;
      if (failureCode(failure) === "CONFLICT") {
        // The key was consumed by a different payload: rotate it for the next attempt.
        this.proposeKey = operationKey();
        await this.load();
      }
    } finally {
      this.busy = false;
    }
  }
  askConfirm(event) {
    this.reset();
    const set = this.sets.find((row) => row.setId === event.target.dataset.id);
    if (!set) return;
    this.confirmation = { set, trigger: event.target };
  }
  cancelConfirmation() {
    const trigger = this.confirmation?.trigger;
    this.confirmation = undefined;
    if (trigger && typeof trigger.focus === "function") trigger.focus();
  }
  async handleDiscard(event) {
    this.reset();
    const set = this.sets.find((row) => row.setId === event.target.dataset.id);
    if (!set) return;
    this.busy = true;
    try {
      await discard({ setId: set.setId, expectedVersion: set.version });
      this.success = labels.discarded;
      await this.load();
    } catch (failure) {
      const parsed = parseFailure(failure);
      this.error = parsed.message;
      this.reasons = parsed.reasons;
    } finally {
      this.busy = false;
    }
  }
  async acceptConfirmation() {
    const set = this.confirmation?.set;
    this.confirmation = undefined;
    if (!set) return;
    this.busy = true;
    try {
      await confirm({
        setId: set.setId,
        expectedVersion: set.version,
        operationKey: this.confirmKey
      });
      this.success = labels.confirmed;
      this.confirmKey = operationKey();
      await this.load();
    } catch (failure) {
      const parsed = parseFailure(failure);
      this.error = parsed.message;
      this.reasons = parsed.reasons;
    } finally {
      this.busy = false;
    }
  }
  reset() {
    this.error = undefined;
    this.reasons = [];
    this.success = undefined;
  }
}
