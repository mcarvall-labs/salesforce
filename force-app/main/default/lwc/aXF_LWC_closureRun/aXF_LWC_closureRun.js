import { LightningElement, wire } from "lwc";
import canClose from "@salesforce/apex/AXF_CLS_CTRL_ClosureRun.canClose";
import getHolders from "@salesforce/apex/AXF_CLS_CTRL_ClosureRun.getHolders";
import listRuns from "@salesforce/apex/AXF_CLS_CTRL_ClosureRun.listRuns";
import request from "@salesforce/apex/AXF_CLS_CTRL_ClosureRun.request";
import advance from "@salesforce/apex/AXF_CLS_CTRL_ClosureRun.advance";
import reconcile from "@salesforce/apex/AXF_CLS_CTRL_ClosureRun.reconcile";
import attachExportEvidence from "@salesforce/apex/AXF_CLS_CTRL_ClosureRun.attachExportEvidence";
import read from "@salesforce/apex/AXF_CLS_CTRL_ClosureRun.read";
import releaseLegalHold from "@salesforce/apex/AXF_CLS_CTRL_ClosureRun.releaseLegalHold";
import labels from "./labels";

const CODE_LABELS = {
  FORBIDDEN: "codeForbidden",
  NOT_ACCESSIBLE: "codeNotAccessible",
  CONFLICT: "codeConflict",
  TERMINAL: "codeTerminal",
  RECONCILE_FIRST: "codeReconcileFirst",
  NOT_RECONCILABLE: "codeNotReconcilable",
  INVALID_INPUT: "codeInvalidInput",
  CHECKPOINTS_CORRUPT: "codeCheckpointsCorrupt"
};

export function failureCode(error) {
  return error?.body?.message;
}
export function statusLabel(status) {
  return labels[`status${status}`] || status || "";
}
export function reasonLabel(reason) {
  if (!reason) return "";
  const base = reason.split(":")[0];
  const label = labels[`reason${base}`] || base;
  return reason.includes(":") ? `${label} (${reason.split(":")[1]})` : label;
}
export function externalLabel(value) {
  return labels[`external${value}`] || value || "";
}
function format(template, ...values) {
  return values.reduce(
    (text, value, index) => text.replace(`{${index}}`, value),
    template
  );
}

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
  info;
  confirmation;
  allowedLoaded = false;
  form = { accountId: "", legalHold: false, evidenceRef: "" };

  @wire(canClose)
  wiredAllowed({ data, error }) {
    this.allowedLoaded = true;
    if (error) {
      this.error = failureMessage(error);
      return;
    }
    this.allowed = data === true;
    if (this.allowed) this.loadRuns();
  }
  @wire(getHolders)
  wiredHolders({ data, error }) {
    if (error) {
      this.error = failureMessage(error);
      return;
    }
    if (data) this.holders = data;
  }
  get noAccess() {
    return this.allowedLoaded && !this.allowed;
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
      stageLabel: stageLabel(row.lastCompletedStage),
      statusLabel: statusLabel(row.status)
    }));
  }
  get detail() {
    if (!this.run) return undefined;
    return {
      ...this.run,
      stageLabel: stageLabel(this.run.lastCompletedStage),
      statusLabel: statusLabel(this.run.status),
      reasonLabel: reasonLabel(this.run.blockReason),
      externalLabel: externalLabel(this.run.externalRevocation),
      // Shown apart from the run's own next action: this step happens at the provider. The
      // server emits it only for a closed run whose revocation the provider has not confirmed,
      // so a blocked run never announces "Axon closed" while its own stage is still pending.
      externalActionLabel: this.run.externalRevocationAction
        ? actionLabel(this.run.externalRevocationAction)
        : "—",
      externalRevocationPending: Boolean(this.run.externalRevocationAction),
      actionLabel: actionLabel(this.run.nextAction),
      canReleaseHold: this.run.legalHold === true && !this.run.closed,
      checkpoints: (this.run.checkpoints || []).map((checkpoint, index) => ({
        ...checkpoint,
        key: `${checkpoint.stage}-${index}`,
        stageLabel: stageLabel(checkpoint.stage),
        statusLabel: statusLabel(checkpoint.status),
        reasonLabel: reasonLabel(checkpoint.reason),
        impactText: Object.entries(checkpoint.impact || {})
          .map(([name, value]) => `${name}=${value}`)
          .join(", ")
      }))
    };
  }
  get confirmationBody() {
    return this.confirmation
      ? format(labels.confirmResumeBody, this.run?.accountName || "")
      : "";
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
  askAdvance() {
    this.error = undefined;
    this.confirmation = { kind: "RESUME" };
  }
  cancelConfirmation() {
    this.confirmation = undefined;
  }
  handleDialogKey(event) {
    if (event.key === "Escape") this.cancelConfirmation();
  }
  async acceptConfirmation() {
    const pending = this.confirmation;
    this.confirmation = undefined;
    if (pending?.kind === "RESUME") {
      await this.handleAdvance();
    }
  }
  async handleAdvance() {
    await this.call(() =>
      advance({ runId: this.run.runId, expectedVersion: this.run.version })
    );
  }
  async handleReleaseHold() {
    await this.call(() =>
      releaseLegalHold({
        runId: this.run.runId,
        expectedVersion: this.run.version
      })
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
    if (!this.error) {
      this.form = { ...this.form, evidenceRef: "" };
    }
  }
  async call(action) {
    this.error = undefined;
    this.info = undefined;
    this.busy = true;
    try {
      this.run = await action();
    } catch (failure) {
      this.error = failureMessage(failure);
      if (failureCode(failure) === "CONFLICT" && this.run) {
        // Stale version: reload so the next action carries the current state.
        try {
          this.run = await read({ runId: this.run.runId });
          this.info = labels.conflictReloaded;
        } catch (reload) {
          this.error = failureMessage(reload);
        }
      }
    } finally {
      this.busy = false;
    }
  }
}
