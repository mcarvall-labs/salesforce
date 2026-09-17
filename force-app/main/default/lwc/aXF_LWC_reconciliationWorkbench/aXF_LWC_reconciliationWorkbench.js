import { LightningElement, wire } from "lwc";
import getContext from "@salesforce/apex/AXF_CLS_CTRL_ReconciliationWorkbench.getContext";
import preview from "@salesforce/apex/AXF_CLS_CTRL_ReconciliationWorkbench.preview";
import confirm from "@salesforce/apex/AXF_CLS_CTRL_ReconciliationWorkbench.confirm";
import resolveResult from "@salesforce/apex/AXF_CLS_CTRL_ReconciliationWorkbench.resolveResult";
import labels from "./labels";
import {
  parseFailure,
  failureCode,
  newOperationKey,
  newCorrelationId
} from "./failures";

const STEP = { LIST: "LIST", REVIEW: "REVIEW", DONE: "DONE" };
const KIND_LABEL = { BANK: "kindBANK", CARD: "kindCARD", MANUAL: "kindMANUAL" };
const STATE_LABEL = {
  CONFIRMED: "stateCONFIRMED",
  PARTIAL: "statePARTIAL",
  BLOCKED: "stateBLOCKED",
  FAILED: "stateFAILED",
  CONSULTATIVE: "stateCONSULTATIVE",
  CONFIRMING: "stateCONFIRMING",
  DRAFT: "stateDRAFT"
};

export default class AxfReconciliationWorkbench extends LightningElement {
  labels = labels;
  step = STEP.LIST;
  context;
  holderOptions = [];
  holderId;
  sources = [];
  selected;
  view;
  drafts = [];
  amounts = {};
  operationKey;
  correlationId;
  result;
  busy = false;
  error;
  errorCode;

  @wire(getContext)
  wiredContext({ data, error }) {
    if (data) {
      this.context = data;
      this.holderOptions = (data.holders || []).map((h) => ({
        label: h.label,
        value: h.accountId
      }));
      this.error = undefined;
    } else if (error) {
      this.context = undefined;
      this.error = parseFailure(error);
    }
  }

  get canConfirm() {
    return this.context && this.context.canConfirm === true;
  }
  get cannotConfirm() {
    return this.context && this.context.canConfirm !== true;
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
  get showEmpty() {
    return this.isList && !this.busy && this.sources.length === 0;
  }
  get sourceRows() {
    return this.sources.map((s, index) => ({
      ...s,
      index,
      key: s.factId,
      kindLabel: labels[KIND_LABEL[s.factKind]] || s.factKind,
      description: s.description || s.label
    }));
  }
  get candidateRows() {
    const candidates = (this.view && this.view.candidates) || [];
    return candidates.map((c, index) => ({
      ...c,
      index,
      key: c.targetId,
      amount: this.amounts[c.targetId],
      addDisabled: c.linkable !== true || this.busy,
      evidenceLabel: c.identityExact
        ? labels.evidenceExact
        : labels.evidenceConsultative,
      stateLabel: labels[STATE_LABEL[c.state]] || c.state,
      reasonLabels: (c.reasons || []).map((r) => ({
        key: r,
        text: labels["reason" + r] || r
      })),
      showLowEvidence: c.lowEvidence === true
    }));
  }
  get lineRows() {
    const lines = (this.view && this.view.lines) || [];
    return lines.map((line, index) => ({
      ...line,
      index,
      key: `${line.factId}-${line.targetId}`,
      kindLabel: labels[KIND_LABEL[line.factKind]] || line.factKind,
      stateLabel: labels[STATE_LABEL[line.state]] || line.state,
      reasonLabels: (line.reasons || []).map((r) => ({
        key: r,
        text: labels["reason" + r] || r
      }))
    }));
  }
  get hasLines() {
    return this.lineRows.length > 0;
  }
  get reviewDisabled() {
    return this.busy || !this.hasLines;
  }
  get resolveLabel() {
    return this.busy ? labels.resolving : labels.resolve;
  }
  get confirmLabel() {
    return this.busy ? labels.confirming : labels.confirm;
  }
  get sourceResidual() {
    if (!this.view || !this.view.source) {
      return null;
    }
    return this.view.source.residual;
  }
  get sourceCurrency() {
    return this.view && this.view.source
      ? this.view.source.currencyIso
      : null;
  }
  get selectedKindLabel() {
    return this.selected
      ? labels[KIND_LABEL[this.selected.factKind]] || this.selected.factKind
      : "";
  }
  get resultStateLabel() {
    return this.result
      ? labels[STATE_LABEL[this.result.state]] || this.result.state
      : "";
  }
  get resultUnknown() {
    return this.result && this.result.unknownOutcome === true;
  }
  get resultRows() {
    const lines = (this.result && this.result.lines) || [];
    return lines.map((line, index) => ({
      ...line,
      index,
      key: line.allocationId || `${index}`,
      kindLabel: labels[KIND_LABEL[line.factKind]] || line.factKind,
      stateLabel: labels[STATE_LABEL[line.state]] || line.state
    }));
  }
  get resultAggregate() {
    return this.result
      ? this.result.reconciliationId || this.result.reconciliationKey
      : "";
  }
  get hasResultResidual() {
    return (
      !!this.result &&
      this.result.residualMagnitude !== null &&
      this.result.residualMagnitude !== undefined
    );
  }
  get resultCurrency() {
    return this.result ? this.result.residualCurrency : null;
  }
  get showResolve() {
    return this.errorCode === "CONFLICT" || this.errorCode === "LOCKED";
  }

  handleHolder(event) {
    this.holderId = event.detail.value;
    this.sources = [];
    this.error = undefined;
  }
  async load() {
    if (!this.holderId) {
      return;
    }
    this.busy = true;
    this.error = undefined;
    try {
      const view = await preview({
        request: JSON.stringify({ accountId: this.holderId })
      });
      this.view = view;
      this.sources = view.sources || [];
    } catch (e) {
      this.error = parseFailure(e);
      this.errorCode = failureCode(e);
    } finally {
      this.busy = false;
    }
  }
  handleLoad() {
    this.load();
  }
  async handleSelect(event) {
    const row = this.sources[Number(event.currentTarget.dataset.index)];
    if (!row) {
      return;
    }
    this.selected = row;
    this.drafts = [];
    this.amounts = {};
    this.result = undefined;
    this.error = undefined;
    // One key and one correlation id per human intention: a retry replays, never duplicates.
    this.operationKey = newOperationKey();
    this.correlationId = newCorrelationId();
    this.step = STEP.REVIEW;
    await this.refresh();
  }
  async refresh() {
    if (!this.selected) {
      return;
    }
    this.busy = true;
    try {
      this.view = await preview({
        request: JSON.stringify({
          factKind: this.selected.factKind,
          factId: this.selected.factId,
          correlationId: this.correlationId,
          lines: this.drafts
        })
      });
      this.error = undefined;
      this.errorCode = undefined;
    } catch (e) {
      this.error = parseFailure(e);
      this.errorCode = failureCode(e);
    } finally {
      this.busy = false;
    }
  }
  handleAmount(event) {
    this.amounts = {
      ...this.amounts,
      [event.target.dataset.target]: event.target.value
    };
  }
  async handleAdd(event) {
    const targetId = event.currentTarget.dataset.target;
    const amount = this.amounts[targetId];
    if (!amount || !this.selected) {
      return;
    }
    this.drafts = [
      ...this.drafts,
      {
        factKind: this.selected.factKind,
        factId: this.selected.factId,
        targetId,
        amount: Number(amount)
      }
    ];
    this.amounts = { ...this.amounts, [targetId]: undefined };
    await this.refresh();
  }
  async handleRemove(event) {
    const index = Number(event.currentTarget.dataset.index);
    this.drafts = this.drafts.filter((line, i) => i !== index);
    await this.refresh();
  }
  handleBack() {
    this.step = STEP.LIST;
    this.selected = undefined;
    this.drafts = [];
    this.amounts = {};
    this.view = undefined;
    this.error = undefined;
    this.errorCode = undefined;
  }
  async handleConfirm() {
    if (this.reviewDisabled) {
      return;
    }
    this.busy = true;
    this.error = undefined;
    this.errorCode = undefined;
    try {
      this.result = await confirm({
        request: JSON.stringify({
          lines: this.drafts,
          expectedVersion:
            this.view && this.view.expectedVersion !== undefined
              ? this.view.expectedVersion
              : 0,
          idempotencyKey: this.operationKey,
          correlationId: this.correlationId
        })
      });
      this.step = STEP.DONE;
    } catch (e) {
      // The draft stays reviewable; the same correlationId and key replay on retry.
      this.error = parseFailure(e);
      this.errorCode = failureCode(e);
    } finally {
      this.busy = false;
    }
  }
  /** GF-75: the authoritative query, never a blind retry of the command. */
  async handleResolve() {
    if (!this.correlationId) {
      return;
    }
    this.busy = true;
    try {
      const view = await resolveResult({
        request: JSON.stringify({
          correlationId: this.correlationId,
          lines: this.drafts
        })
      });
      this.result = view;
      this.error = undefined;
      this.errorCode = undefined;
      this.step = STEP.DONE;
    } catch (e) {
      this.error = parseFailure(e);
      this.errorCode = failureCode(e);
    } finally {
      this.busy = false;
    }
  }
  handleNew() {
    this.step = STEP.LIST;
    this.selected = undefined;
    this.view = undefined;
    this.result = undefined;
    this.drafts = [];
    this.amounts = {};
    this.operationKey = undefined;
    this.correlationId = undefined;
    this.error = undefined;
    this.errorCode = undefined;
    this.sources = [];
  }
}
