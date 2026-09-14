import { LightningElement, wire } from "lwc";
import canClose from "@salesforce/apex/AXF_CLS_CTRL_ClosureRun.canClose";
import getHolders from "@salesforce/apex/AXF_CLS_CTRL_ClosureRun.getHolders";
import listRuns from "@salesforce/apex/AXF_CLS_CTRL_ClosureRun.listRuns";
import request from "@salesforce/apex/AXF_CLS_CTRL_ClosureRun.request";
import advance from "@salesforce/apex/AXF_CLS_CTRL_ClosureRun.advance";
import reconcile from "@salesforce/apex/AXF_CLS_CTRL_ClosureRun.reconcile";
import attachExportEvidence from "@salesforce/apex/AXF_CLS_CTRL_ClosureRun.attachExportEvidence";
import read from "@salesforce/apex/AXF_CLS_CTRL_ClosureRun.read";
import labels from "./labels";

const CODE_LABELS = {
  FORBIDDEN: "codeForbidden",
  NOT_ACCESSIBLE: "codeNotAccessible",
  CONFLICT: "codeConflict",
  TERMINAL: "codeTerminal",
  RECONCILE_FIRST: "codeReconcileFirst",
  NOT_RECONCILABLE: "codeNotReconcilable",
  INVALID_INPUT: "codeInvalidInput"
};

export function failureMessage(error) {
  const code = error?.body?.message;
  return labels[CODE_LABELS[code]] || labels.error;
}
export function stageLabel(stage) {
  return labels[`stage${stage}`] || stage;
}
export function actionLabel(action) {
  return labels[`action${action}`] || action || "";
}

export default class ClosureRun extends LightningElement {
  labels = labels;
  allowed = false;
  holders = [];
  runs = [];
  run;
  busy = false;
  error;
  form = { accountId: "", legalHold: false, evidenceRef: "" };

  @wire(canClose)
  wiredAllowed({ data }) {
    this.allowed = data === true;
    if (this.allowed) this.loadRuns();
  }
  @wire(getHolders)
  wiredHolders({ data }) {
    if (data) this.holders = data;
  }

  get holderOptions() {
    return this.holders.map((row) => ({
      label: row.label,
      value: row.accountId
    }));
  }
  get startDisabled() {
    return this.busy || !this.form.accountId;
  }
  get hasRuns() {
    return this.runs.length > 0;
  }
  get runRows() {
    return this.runs.map((row) => ({
      ...row,
      stageLabel: stageLabel(row.lastCompletedStage)
    }));
  }
  get detail() {
    if (!this.run) return undefined;
    return {
      ...this.run,
      stageLabel: stageLabel(this.run.lastCompletedStage),
      actionLabel: actionLabel(this.run.nextAction),
      checkpoints: (this.run.checkpoints || []).map((checkpoint, index) => ({
        ...checkpoint,
        key: `${checkpoint.stage}-${index}`,
        stageLabel: stageLabel(checkpoint.stage),
        impactText: Object.entries(checkpoint.impact || {})
          .map(([name, value]) => `${name}=${value}`)
          .join(", ")
      }))
    };
  }
  get isBlocked() {
    return this.run?.status === "BLOCKED";
  }
  get isUnknown() {
    return this.run?.status === "RESULT_UNKNOWN";
  }
  get needsExportEvidence() {
    return this.isBlocked && this.run?.blockReason === "EXPORT_PENDING";
  }
  get attachDisabled() {
    return this.busy || !this.form.evidenceRef;
  }

  async loadRuns() {
    this.busy = true;
    try {
      this.runs = await listRuns();
    } catch (failure) {
      this.error = failureMessage(failure);
    } finally {
      this.busy = false;
    }
  }
  handleField(event) {
    const { name, type, checked, value } = event.target;
    this.form = {
      ...this.form,
      [name]: type === "checkbox" ? checked : (event.detail?.value ?? value)
    };
  }
  async handleStart() {
    await this.call(() =>
      request({
        accountId: this.form.accountId,
        legalHold: this.form.legalHold
      })
    );
  }
  async handleOpen(event) {
    await this.call(() => read({ runId: event.target.dataset.id }));
  }
  handleBack() {
    this.run = undefined;
    this.error = undefined;
    this.loadRuns();
  }
  async handleAdvance() {
    await this.call(() =>
      advance({ runId: this.run.runId, expectedVersion: this.run.version })
    );
  }
  async handleReconcile() {
    await this.call(() =>
      reconcile({ runId: this.run.runId, expectedVersion: this.run.version })
    );
  }
  async handleAttach() {
    await this.call(() =>
      attachExportEvidence({
        runId: this.run.runId,
        evidenceRef: this.form.evidenceRef,
        expectedVersion: this.run.version
      })
    );
  }
  async call(action) {
    this.error = undefined;
    this.busy = true;
    try {
      this.run = await action();
    } catch (failure) {
      this.error = failureMessage(failure);
    } finally {
      this.busy = false;
    }
  }
}
