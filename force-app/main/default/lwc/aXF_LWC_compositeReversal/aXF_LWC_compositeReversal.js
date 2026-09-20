import { LightningElement, wire } from "lwc";
import getContext from "@salesforce/apex/AXF_CLS_CTRL_CompositeReversal.getContext";
import listReconciliations from "@salesforce/apex/AXF_CLS_CTRL_CompositeReversal.listReconciliations";
import listAllocations from "@salesforce/apex/AXF_CLS_CTRL_CompositeReversal.listAllocations";
import reverseComposite from "@salesforce/apex/AXF_CLS_CTRL_CompositeReversal.reverseComposite";
import redistribute from "@salesforce/apex/AXF_CLS_CTRL_CompositeReversal.redistribute";
import {
  parseFailure,
  code,
  newOperationKey,
  newCorrelationId
} from "./failures";

const STEP = { LIST: "LIST", ALLOCATIONS: "ALLOCATIONS", DONE: "DONE" };
const REASONS = [
  { label: "Erro do usuario", value: "USER_ERROR" },
  { label: "Vinculo duplicado", value: "DUPLICATE_LINK" },
  { label: "Alvo incorreto", value: "WRONG_TARGET" },
  { label: "Origem alterada", value: "SOURCE_CHANGED" },
  { label: "Outro", value: "OTHER" }
];
const KIND_LABEL = { BANK: "Banco", CARD: "Cartao", MANUAL: "Caixa" };
// A code other than CONFLICT that also means "this exact intention already has a durable
// outcome" (AXF-141's own divergent-payload guard) needs the same fresh-list reset as CONFLICT.
const RESET_ON_CODES = new Set(["CONFLICT", "ALREADY_REVERSED"]);

/** @description AXF-142: reversao composta (N allocations de um RCN) e redistribuicao. */
export default class AxfCompositeReversal extends LightningElement {
  step = STEP.LIST;
  context;
  holderOptions = [];
  reasonOptions = REASONS;
  holderId;
  reconciliations;
  selectedReconciliationId;
  rcnView;
  allocationsBeforeReversal = [];
  reasonCode;
  reasonNote = "";
  operationKey;
  result;
  redistributeOriginalId;
  redistributeTargetId;
  redistributeAmount;
  redistributeReasonCode;
  redistributeReasonNote = "";
  redistributeCorrelationId;
  redistributeIdempotencyKey;
  redistributeExpectedVersion;
  redistributeResult;
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
  get canRedistribute() {
    return this.context && this.context.canRedistribute === true;
  }
  get policyVersion() {
    return this.context ? this.context.policyVersion : "";
  }
  get isList() {
    return this.step === STEP.LIST;
  }
  get isAllocations() {
    return this.step === STEP.ALLOCATIONS;
  }
  get isDone() {
    return this.step === STEP.DONE;
  }
  get loadDisabled() {
    return this.busy || !this.holderId;
  }
  get hasReconciliations() {
    return !!this.reconciliations && this.reconciliations.length > 0;
  }
  get showEmpty() {
    return !!this.reconciliations && this.reconciliations.length === 0;
  }
  get reconciliationRows() {
    return (this.reconciliations || []).map((r, i) => ({
      ...r,
      index: i,
      key: r.reconciliationId
    }));
  }
  get redistributeOriginalOptions() {
    return this.allocationsBeforeReversal.map((a) => ({
      label: `${a.targetDescription || a.targetId} · ${a.amount}`,
      value: a.allocationId
    }));
  }
  get allocationRows() {
    return (this.rcnView ? this.rcnView.allocations : []).map((a) => ({
      ...a,
      key: a.allocationId,
      sourceKindLabel: KIND_LABEL[a.sourceKind] || a.sourceKind
    }));
  }
  get reverseDisabled() {
    return (
      this.busy || !this.reasonCode || (this.reasonNote || "").length > 255
    );
  }
  get reverseLabel() {
    return this.busy ? "Revertendo..." : "Reverter todas as alocacoes";
  }
  get redistributeDisabled() {
    return (
      this.busy ||
      !this.redistributeOriginalId ||
      !this.redistributeTargetId ||
      !this.redistributeAmount ||
      !this.redistributeReasonCode ||
      (this.redistributeReasonNote || "").length > 255
    );
  }

  handleHolder(event) {
    this.holderId = event.detail.value;
    this.reconciliations = undefined;
    this.error = undefined;
  }
  async handleLoad() {
    if (!this.holderId) {
      return;
    }
    this.busy = true;
    this.error = undefined;
    try {
      this.reconciliations = await listReconciliations({
        accountId: this.holderId
      });
    } catch (e) {
      this.error = parseFailure(e);
    } finally {
      this.busy = false;
    }
  }
  async handleSelectReconciliation(event) {
    const row = this.reconciliations[Number(event.currentTarget.dataset.index)];
    if (!row) {
      return;
    }
    this.busy = true;
    this.error = undefined;
    try {
      this.selectedReconciliationId = row.reconciliationId;
      this.rcnView = await listAllocations({
        reconciliationId: row.reconciliationId
      });
      this.reasonCode = undefined;
      this.reasonNote = "";
      this.operationKey = newOperationKey();
      this.step = STEP.ALLOCATIONS;
    } catch (e) {
      this.error = parseFailure(e);
    } finally {
      this.busy = false;
    }
  }
  handleReason(event) {
    this.reasonCode = event.detail.value;
  }
  handleNote(event) {
    this.reasonNote = event.target.value;
  }
  /** One correlationId/idempotencyKey/expectedVersion per redistribution attempt, generated once
   * when the attempt starts and reused on every retry — same pattern as the reversal's operationKey. */
  startRedistributeAttempt() {
    this.redistributeOriginalId = undefined;
    this.redistributeTargetId = undefined;
    this.redistributeAmount = undefined;
    this.redistributeReasonCode = undefined;
    this.redistributeReasonNote = "";
    this.redistributeCorrelationId = newCorrelationId();
    this.redistributeIdempotencyKey = newOperationKey();
    this.redistributeExpectedVersion = 0;
  }
  handleBack() {
    this.step = STEP.LIST;
    this.error = undefined;
    this.rcnView = undefined;
    this.handleLoad();
  }
  async handleReverse() {
    if (this.reverseDisabled) {
      return;
    }
    this.busy = true;
    this.error = undefined;
    try {
      this.result = await reverseComposite({
        request: JSON.stringify({
          reconciliationId: this.selectedReconciliationId,
          expectedVersion: this.rcnView.version,
          reasonCode: this.reasonCode,
          reasonNote: this.reasonNote || null,
          operationKey: this.operationKey
        })
      });
      // Preserved so the redistribution picker can offer the fact/target of a reverted line.
      this.allocationsBeforeReversal = this.rcnView.allocations;
      this.redistributeResult = undefined;
      this.startRedistributeAttempt();
      this.step = STEP.DONE;
    } catch (e) {
      this.error = parseFailure(e);
      if (RESET_ON_CODES.has(code(e))) {
        // Stale version, or the same intention already has a durable outcome under a divergent
        // payload: either way the RCN moved and a fresh list is the only safe next step.
        this.step = STEP.LIST;
        this.rcnView = undefined;
        await this.handleLoad();
        // handleLoad() clears the banner on entry; the failure is still the reason we are here.
        this.error = parseFailure(e);
      }
    } finally {
      this.busy = false;
    }
  }
  handleRedistributeOriginal(event) {
    this.redistributeOriginalId = event.detail.value;
  }
  handleRedistributeTarget(event) {
    this.redistributeTargetId = event.target.value;
  }
  handleRedistributeAmount(event) {
    this.redistributeAmount = event.target.value;
  }
  handleRedistributeReason(event) {
    this.redistributeReasonCode = event.detail.value;
  }
  handleRedistributeNote(event) {
    this.redistributeReasonNote = event.target.value;
  }
  async handleRedistribute() {
    if (this.redistributeDisabled) {
      return;
    }
    const original = this.allocationsBeforeReversal.find(
      (a) => a.allocationId === this.redistributeOriginalId
    );
    if (!original) {
      return;
    }
    this.busy = true;
    this.error = undefined;
    try {
      this.redistributeResult = await redistribute({
        request: JSON.stringify({
          originalAllocationId: this.redistributeOriginalId,
          lines: [
            {
              factKind: original.sourceKind,
              factId: original.sourceId,
              targetId: this.redistributeTargetId,
              amount: Number(this.redistributeAmount)
            }
          ],
          expectedVersion: this.redistributeExpectedVersion,
          reasonCode: this.redistributeReasonCode,
          reasonNote: this.redistributeReasonNote || null,
          correlationId: this.redistributeCorrelationId,
          idempotencyKey: this.redistributeIdempotencyKey
        })
      });
      // The original just redistributed is no longer eligible: drop it locally so the picker
      // cannot offer it again before the next full reload.
      this.allocationsBeforeReversal = this.allocationsBeforeReversal.filter(
        (a) => a.allocationId !== this.redistributeOriginalId
      );
      this.startRedistributeAttempt();
    } catch (e) {
      this.error = parseFailure(e);
    } finally {
      this.busy = false;
    }
  }
  handleNew() {
    this.step = STEP.LIST;
    this.selectedReconciliationId = undefined;
    this.rcnView = undefined;
    this.allocationsBeforeReversal = [];
    this.result = undefined;
    this.redistributeResult = undefined;
    this.operationKey = undefined;
    this.error = undefined;
    this.reconciliations = undefined;
  }
}
