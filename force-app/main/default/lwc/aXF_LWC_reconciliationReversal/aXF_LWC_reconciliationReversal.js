import { LightningElement, wire } from "lwc";
import getContext from "@salesforce/apex/AXF_CLS_CTRL_ReconciliationReversal.getContext";
import listAllocations from "@salesforce/apex/AXF_CLS_CTRL_ReconciliationReversal.listAllocations";
import reverse from "@salesforce/apex/AXF_CLS_CTRL_ReconciliationReversal.reverse";
import priorReversal from "@salesforce/apex/AXF_CLS_CTRL_ReconciliationReversal.priorReversal";
import title from "@salesforce/label/c.AXF_ReconciliationReversal_title";
import intro from "@salesforce/label/c.AXF_ReconciliationReversal_intro";
import noCapability from "@salesforce/label/c.AXF_ReconciliationReversal_noCapability";
import holder from "@salesforce/label/c.AXF_ReconciliationReversal_holder";
import holderPlaceholder from "@salesforce/label/c.AXF_ReconciliationReversal_holderPlaceholder";
import load from "@salesforce/label/c.AXF_ReconciliationReversal_load";
import loadMore from "@salesforce/label/c.AXF_ReconciliationReversal_loadMore";
import loading from "@salesforce/label/c.AXF_ReconciliationReversal_loading";
import empty from "@salesforce/label/c.AXF_ReconciliationReversal_empty";
import colDate from "@salesforce/label/c.AXF_ReconciliationReversal_colDate";
import colTarget from "@salesforce/label/c.AXF_ReconciliationReversal_colTarget";
import colRole from "@salesforce/label/c.AXF_ReconciliationReversal_colRole";
import colSource from "@salesforce/label/c.AXF_ReconciliationReversal_colSource";
import colAmount from "@salesforce/label/c.AXF_ReconciliationReversal_colAmount";
import colStatus from "@salesforce/label/c.AXF_ReconciliationReversal_colStatus";
import colAction from "@salesforce/label/c.AXF_ReconciliationReversal_colAction";
import statusOpen from "@salesforce/label/c.AXF_ReconciliationReversal_statusOpen";
import statusReversed from "@salesforce/label/c.AXF_ReconciliationReversal_statusReversed";
import scheduleLinked from "@salesforce/label/c.AXF_ReconciliationReversal_scheduleLinked";
import select from "@salesforce/label/c.AXF_ReconciliationReversal_select";
import reviewIntro from "@salesforce/label/c.AXF_ReconciliationReversal_reviewIntro";
import selected from "@salesforce/label/c.AXF_ReconciliationReversal_selected";
import reason from "@salesforce/label/c.AXF_ReconciliationReversal_reason";
import reasonPlaceholder from "@salesforce/label/c.AXF_ReconciliationReversal_reasonPlaceholder";
import reasonUSER_ERROR from "@salesforce/label/c.AXF_ReconciliationReversal_reasonUSER_ERROR";
import reasonDUPLICATE_LINK from "@salesforce/label/c.AXF_ReconciliationReversal_reasonDUPLICATE_LINK";
import reasonWRONG_TARGET from "@salesforce/label/c.AXF_ReconciliationReversal_reasonWRONG_TARGET";
import reasonSOURCE_CHANGED from "@salesforce/label/c.AXF_ReconciliationReversal_reasonSOURCE_CHANGED";
import reasonOTHER from "@salesforce/label/c.AXF_ReconciliationReversal_reasonOTHER";
import note from "@salesforce/label/c.AXF_ReconciliationReversal_note";
import confirm from "@salesforce/label/c.AXF_ReconciliationReversal_confirm";
import confirming from "@salesforce/label/c.AXF_ReconciliationReversal_confirming";
import back from "@salesforce/label/c.AXF_ReconciliationReversal_back";
import done from "@salesforce/label/c.AXF_ReconciliationReversal_done";
import doneReplayed from "@salesforce/label/c.AXF_ReconciliationReversal_doneReplayed";
import doneActualOnly from "@salesforce/label/c.AXF_ReconciliationReversal_doneActualOnly";
import doneCompensation from "@salesforce/label/c.AXF_ReconciliationReversal_doneCompensation";
import doneOriginal from "@salesforce/label/c.AXF_ReconciliationReversal_doneOriginal";
import doneNet from "@salesforce/label/c.AXF_ReconciliationReversal_doneNet";
import boundaryAXF104_OBLIGATION_ADJUSTMENT_PENDING from "@salesforce/label/c.AXF_ReconciliationReversal_boundaryAXF104_OBLIGATION_ADJUSTMENT_PENDING";
import newReversal from "@salesforce/label/c.AXF_ReconciliationReversal_newReversal";
import policy from "@salesforce/label/c.AXF_ReconciliationReversal_policy";
import errorLabel from "@salesforce/label/c.AXF_ReconciliationReversal_error";
import codeUNAVAILABLE from "@salesforce/label/c.AXF_ReconciliationReversal_codeUNAVAILABLE";
import codeNOT_ACCESSIBLE from "@salesforce/label/c.AXF_ReconciliationReversal_codeNOT_ACCESSIBLE";
import codeINVALID_INPUT from "@salesforce/label/c.AXF_ReconciliationReversal_codeINVALID_INPUT";
import codeINVALID from "@salesforce/label/c.AXF_ReconciliationReversal_codeINVALID";
import codeINVALID_REASON from "@salesforce/label/c.AXF_ReconciliationReversal_codeINVALID_REASON";
import codeINVALID_TARGET from "@salesforce/label/c.AXF_ReconciliationReversal_codeINVALID_TARGET";
import codeALREADY_REVERSED from "@salesforce/label/c.AXF_ReconciliationReversal_codeALREADY_REVERSED";
import codeCONFLICT from "@salesforce/label/c.AXF_ReconciliationReversal_codeCONFLICT";
import codeREPORTING_CURRENCY_REQUIRED from "@salesforce/label/c.AXF_ReconciliationReversal_codeREPORTING_CURRENCY_REQUIRED";
import kindBANK from "@salesforce/label/c.AXF_ReconciliationReversal_kindBANK";
import kindCARD from "@salesforce/label/c.AXF_ReconciliationReversal_kindCARD";
import kindCASH from "@salesforce/label/c.AXF_ReconciliationReversal_kindCASH";
import doneRealized from "@salesforce/label/c.AXF_ReconciliationReversal_doneRealized";
import doneRemaining from "@salesforce/label/c.AXF_ReconciliationReversal_doneRemaining";
import doneSourceRemaining from "@salesforce/label/c.AXF_ReconciliationReversal_doneSourceRemaining";
import doneSourceUnknown from "@salesforce/label/c.AXF_ReconciliationReversal_doneSourceUnknown";

const labels = {
  title,
  intro,
  noCapability,
  holder,
  holderPlaceholder,
  load,
  loadMore,
  loading,
  empty,
  colDate,
  colTarget,
  colRole,
  colSource,
  colAmount,
  colStatus,
  colAction,
  statusOpen,
  statusReversed,
  scheduleLinked,
  select,
  reviewIntro,
  selected,
  reason,
  reasonPlaceholder,
  reasonUSER_ERROR,
  reasonDUPLICATE_LINK,
  reasonWRONG_TARGET,
  reasonSOURCE_CHANGED,
  reasonOTHER,
  note,
  confirm,
  confirming,
  back,
  done,
  doneReplayed,
  doneActualOnly,
  doneCompensation,
  doneOriginal,
  doneNet,
  boundaryAXF104_OBLIGATION_ADJUSTMENT_PENDING,
  newReversal,
  policy,
  error: errorLabel,
  codeUNAVAILABLE,
  codeNOT_ACCESSIBLE,
  codeINVALID_INPUT,
  codeINVALID,
  codeINVALID_REASON,
  codeINVALID_TARGET,
  codeALREADY_REVERSED,
  codeCONFLICT,
  codeREPORTING_CURRENCY_REQUIRED,
  kindBANK,
  kindCARD,
  kindCASH,
  doneRealized,
  doneRemaining,
  doneSourceRemaining,
  doneSourceUnknown
};
import { parseFailure, format, newOperationKey } from "./failures";

const STEP = { LIST: "LIST", REVIEW: "REVIEW", DONE: "DONE" };
const KIND_LABEL = { BANK: "kindBANK", CARD: "kindCARD", CASH: "kindCASH" };
function code(error) {
  return error && error.body && error.body.message;
}

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
      sourceKindLabel: labels[KIND_LABEL[a.sourceKind]] || a.sourceKind,
      hasSourceDescription: !!a.sourceDescription
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
  get selectedTarget() {
    return this.selected
      ? this.selected.targetDescription || this.selected.targetId
      : "";
  }
  get selectedSourceKind() {
    return this.selected
      ? labels[KIND_LABEL[this.selected.sourceKind]] || this.selected.sourceKind
      : "";
  }
  get resultStateLabel() {
    return this.result ? this.result.stateAfter : "";
  }
  get hasSourceResidual() {
    return (
      !!this.result &&
      this.result.sourceResidualAfter !== null &&
      this.result.sourceResidualAfter !== undefined
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
      if (more) {
        const seen = new Set(this.items.map((i) => i.allocationId));
        this.items = [
          ...this.items,
          ...page.items.filter((i) => !seen.has(i.allocationId))
        ];
      } else {
        this.items = [...page.items];
      }
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
    this.selected = undefined;
    // Versions may have moved while reviewing: never offer a stale row again.
    this.load(false);
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
      const failure = code(e);
      if (failure === "ALREADY_REVERSED") {
        // The prior compensation is the answer: show it instead of a dead end.
        try {
          const prior = await priorReversal({
            allocationId: this.selected.allocationId
          });
          if (prior) {
            this.result = prior;
            this.error = undefined;
            this.step = STEP.DONE;
          }
        } catch {
          // keep the sanitized error already shown
        }
      } else if (failure === "CONFLICT") {
        // Stale plan version: go back to a fresh list; the draft cannot succeed as is.
        this.step = STEP.LIST;
        this.selected = undefined;
        await this.load(false);
        this.error = parseFailure(e);
      }
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
