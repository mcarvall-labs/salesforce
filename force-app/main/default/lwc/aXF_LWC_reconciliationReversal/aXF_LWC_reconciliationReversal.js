import { LightningElement, wire } from "lwc";
import getContext from "@salesforce/apex/AXF_CLS_CTRL_ReconciliationReversal.getContext";
import listAllocations from "@salesforce/apex/AXF_CLS_CTRL_ReconciliationReversal.listAllocations";
import reverse from "@salesforce/apex/AXF_CLS_CTRL_ReconciliationReversal.reverse";
import labels from "./labels";
import { parseFailure, format, newOperationKey } from "./failures";

const STEP = { LIST: "LIST", REVIEW: "REVIEW", DONE: "DONE" };

export default class AxfReconciliationReversal extends LightningElement {
  labels = labels;
  step = STEP.LIST;
  context;
  holderOptions = [];
  reasonOptions = [];
  holderId;
  items = [];
  page;
  selected;
  reasonCode;
  reasonNote = "";
  operationKey;
  result;
  busy = false;
  error;

  @wire(getContext, { search: "" })
  wiredContext({ data, error }) {
    if (data) {
      this.context = data;
      this.holderOptions = (data.holders || []).map((h) => ({
        label: h.name,
        value: h.accountId
      }));
      this.reasonOptions = (data.reasons || []).map((r) => ({
        label: labels["reason" + r] || r,
        value: r
      }));
      this.error = undefined;
    } else if (error) {
      this.context = undefined;
      this.error = parseFailure(error);
    }
  }

  get canReverse() {
    return this.context && this.context.canReverse === true;
  }
  get cannotReverse() {
    return this.context && this.context.canReverse !== true;
  }
  get policyVersion() {
    return this.context ? this.context.policyVersion : "";
  }
  get isList() {
    return this.step === STEP.LIST;
  }
  get isReview() {
    return this.step === STEP.REVIEW;
  }
  get isDone() {
    return this.step === STEP.DONE;
  }
  get loadDisabled() {
    return this.busy || !this.holderId;
  }
  get rows() {
    return this.items.map((a, i) => ({
      ...a,
      index: i,
      key: a.allocationId,
      reversed: !!a.reversalId,
      statusLabel: a.reversalId
        ? format(
            labels.statusReversed,
            labels["reason" + a.reversalReason] || a.reversalReason
          )
        : labels.statusOpen,
      sourceLabel: `${a.sourceKind} ${a.sourceId}`
    }));
  }
  get hasRows() {
    return this.items.length > 0;
  }
  get showEmpty() {
    return this.page && this.items.length === 0;
  }
  get hasMore() {
    return this.page && this.page.hasMore === true;
  }
  get confirmDisabled() {
    return (
      this.busy || !this.reasonCode || (this.reasonNote || "").length > 255
    );
  }
  get confirmLabel() {
    return this.busy ? labels.confirming : labels.confirm;
  }
  get selectedSummary() {
    if (!this.selected) {
      return "";
    }
    const s = this.selected;
    return `${s.targetDescription || s.targetId} · ${s.planKind} · ${s.amount} ${s.currencyIso} · ${s.recognitionDate} · ${s.sourceKind}`;
  }
  get resultNet() {
    if (!this.result) {
      return "";
    }
    const r = this.result;
    return format(
      labels.doneNet,
      r.realizedAfter,
      r.residualAfter,
      r.stateAfter,
      r.sourceResidualAfter
    );
  }
  get resultBoundaries() {
    return ((this.result && this.result.boundaries) || []).map((b) => ({
      key: b,
      label: labels["boundary" + b] || b
    }));
  }
  get resultReplayed() {
    return this.result && this.result.replayed === true;
  }
  get resultActualOnly() {
    return this.result && this.result.actualOnly === true;
  }

  handleHolder(event) {
    this.holderId = event.detail.value;
    this.items = [];
    this.page = undefined;
    this.error = undefined;
  }
  async load(more) {
    if (!this.holderId) {
      return;
    }
    this.busy = true;
    this.error = undefined;
    const pageNumber = more && this.page ? this.page.pageNumber + 1 : 1;
    try {
      const page = await listAllocations({
        request: JSON.stringify({
          accountId: this.holderId,
          pageNumber,
          pageSize: this.context ? this.context.pageSize : null
        })
      });
      this.page = page;
      this.items = more ? [...this.items, ...page.items] : [...page.items];
    } catch (e) {
      this.error = parseFailure(e);
    } finally {
      this.busy = false;
    }
  }
  handleLoad() {
    this.load(false);
  }
  handleMore() {
    this.load(true);
  }
  handleSelect(event) {
    const row = this.items[Number(event.currentTarget.dataset.index)];
    if (!row || row.reversalId) {
      return;
    }
    this.selected = row;
    this.reasonCode = undefined;
    this.reasonNote = "";
    this.operationKey = newOperationKey();
    this.error = undefined;
    this.step = STEP.REVIEW;
  }
  handleReason(event) {
    this.reasonCode = event.detail.value;
  }
  handleNote(event) {
    this.reasonNote = event.target.value;
  }
  handleBack() {
    this.step = STEP.LIST;
    this.error = undefined;
  }
  async handleConfirm() {
    if (this.confirmDisabled) {
      return;
    }
    this.busy = true;
    this.error = undefined;
    try {
      this.result = await reverse({
        request: JSON.stringify({
          allocationId: this.selected.allocationId,
          expectedVersion: this.selected.targetVersion,
          reasonCode: this.reasonCode,
          reasonNote: this.reasonNote || null,
          operationKey: this.operationKey
        })
      });
      this.step = STEP.DONE;
    } catch (e) {
      // The draft stays reviewable; the same operation key replays on retry.
      this.error = parseFailure(e);
    } finally {
      this.busy = false;
    }
  }
  handleNew() {
    this.step = STEP.LIST;
    this.selected = undefined;
    this.result = undefined;
    this.operationKey = undefined;
    this.error = undefined;
    this.items = [];
    this.page = undefined;
  }
}
