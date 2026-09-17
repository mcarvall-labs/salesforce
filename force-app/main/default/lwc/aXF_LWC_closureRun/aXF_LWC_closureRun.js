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
import title from "@salesforce/label/c.AXF_ClosureRun_title";
import intro from "@salesforce/label/c.AXF_ClosureRun_intro";
import holder from "@salesforce/label/c.AXF_ClosureRun_holder";
import legalHold from "@salesforce/label/c.AXF_ClosureRun_legalHold";
import start from "@salesforce/label/c.AXF_ClosureRun_start";
import runs from "@salesforce/label/c.AXF_ClosureRun_runs";
import noRuns from "@salesforce/label/c.AXF_ClosureRun_noRuns";
import statusFieldLabel from "@salesforce/label/c.AXF_ClosureRun_status";
import progress from "@salesforce/label/c.AXF_ClosureRun_progress";
import lastStage from "@salesforce/label/c.AXF_ClosureRun_lastStage";
import correlation from "@salesforce/label/c.AXF_ClosureRun_correlation";
import attempt from "@salesforce/label/c.AXF_ClosureRun_attempt";
import blockReason from "@salesforce/label/c.AXF_ClosureRun_blockReason";
import nextAction from "@salesforce/label/c.AXF_ClosureRun_nextAction";
import externalRevocation from "@salesforce/label/c.AXF_ClosureRun_externalRevocation";
import open from "@salesforce/label/c.AXF_ClosureRun_open";
import back from "@salesforce/label/c.AXF_ClosureRun_back";
import resume from "@salesforce/label/c.AXF_ClosureRun_resume";
import reconcileLabel from "@salesforce/label/c.AXF_ClosureRun_reconcile";
import attachEvidence from "@salesforce/label/c.AXF_ClosureRun_attachEvidence";
import evidenceRef from "@salesforce/label/c.AXF_ClosureRun_evidenceRef";
import stages from "@salesforce/label/c.AXF_ClosureRun_stages";
import stageFieldLabel from "@salesforce/label/c.AXF_ClosureRun_stage";
import impact from "@salesforce/label/c.AXF_ClosureRun_impact";
import effectKey from "@salesforce/label/c.AXF_ClosureRun_effectKey";
import completedAt from "@salesforce/label/c.AXF_ClosureRun_completedAt";
import closedBanner from "@salesforce/label/c.AXF_ClosureRun_closedBanner";
import unknownBanner from "@salesforce/label/c.AXF_ClosureRun_unknownBanner";
import blockedBanner from "@salesforce/label/c.AXF_ClosureRun_blockedBanner";
import loading from "@salesforce/label/c.AXF_ClosureRun_loading";
import errorLabel from "@salesforce/label/c.AXF_ClosureRun_error";
import codeForbidden from "@salesforce/label/c.AXF_ClosureRun_codeForbidden";
import codeNotAccessible from "@salesforce/label/c.AXF_ClosureRun_codeNotAccessible";
import codeConflict from "@salesforce/label/c.AXF_ClosureRun_codeConflict";
import codeTerminal from "@salesforce/label/c.AXF_ClosureRun_codeTerminal";
import codeReconcileFirst from "@salesforce/label/c.AXF_ClosureRun_codeReconcileFirst";
import codeNotReconcilable from "@salesforce/label/c.AXF_ClosureRun_codeNotReconcilable";
import codeInvalidInput from "@salesforce/label/c.AXF_ClosureRun_codeInvalidInput";
import stageEXPORT from "@salesforce/label/c.AXF_ClosureRun_stageEXPORT";
import stageREVOKE_ACCESS from "@salesforce/label/c.AXF_ClosureRun_stageREVOKE_ACCESS";
import stageSTOP_COLLECTION from "@salesforce/label/c.AXF_ClosureRun_stageSTOP_COLLECTION";
import stagePURGE from "@salesforce/label/c.AXF_ClosureRun_stagePURGE";
import stageRETAIN_EVIDENCE from "@salesforce/label/c.AXF_ClosureRun_stageRETAIN_EVIDENCE";
import stageNONE from "@salesforce/label/c.AXF_ClosureRun_stageNONE";
import actionATTACH_EXPORT_EVIDENCE from "@salesforce/label/c.AXF_ClosureRun_actionATTACH_EXPORT_EVIDENCE";
import actionRESUME from "@salesforce/label/c.AXF_ClosureRun_actionRESUME";
import actionRECONCILE from "@salesforce/label/c.AXF_ClosureRun_actionRECONCILE";
import actionRELEASE_LEGAL_HOLD from "@salesforce/label/c.AXF_ClosureRun_actionRELEASE_LEGAL_HOLD";
import actionRESOLVE_DEPENDENCIES from "@salesforce/label/c.AXF_ClosureRun_actionRESOLVE_DEPENDENCIES";
import actionNONE from "@salesforce/label/c.AXF_ClosureRun_actionNONE";
import noAccess from "@salesforce/label/c.AXF_ClosureRun_noAccess";
import confirmResumeTitle from "@salesforce/label/c.AXF_ClosureRun_confirmResumeTitle";
import confirmResumeBody from "@salesforce/label/c.AXF_ClosureRun_confirmResumeBody";
import confirm from "@salesforce/label/c.AXF_ClosureRun_confirm";
import cancel from "@salesforce/label/c.AXF_ClosureRun_cancel";
import releaseLegalHoldLabel from "@salesforce/label/c.AXF_ClosureRun_releaseLegalHold";
import legalHoldActive from "@salesforce/label/c.AXF_ClosureRun_legalHoldActive";
import evidenceRefLabel from "@salesforce/label/c.AXF_ClosureRun_evidenceRefLabel";
import lastCompletedAt from "@salesforce/label/c.AXF_ClosureRun_lastCompletedAt";
import actions from "@salesforce/label/c.AXF_ClosureRun_actions";
import conflictReloaded from "@salesforce/label/c.AXF_ClosureRun_conflictReloaded";
import codeCheckpointsCorrupt from "@salesforce/label/c.AXF_ClosureRun_codeCheckpointsCorrupt";
import statusREQUESTED from "@salesforce/label/c.AXF_ClosureRun_statusREQUESTED";
import statusRUNNING from "@salesforce/label/c.AXF_ClosureRun_statusRUNNING";
import statusBLOCKED from "@salesforce/label/c.AXF_ClosureRun_statusBLOCKED";
import statusRESULT_UNKNOWN from "@salesforce/label/c.AXF_ClosureRun_statusRESULT_UNKNOWN";
import statusCLOSED from "@salesforce/label/c.AXF_ClosureRun_statusCLOSED";
import statusDONE from "@salesforce/label/c.AXF_ClosureRun_statusDONE";
import statusRECONCILED from "@salesforce/label/c.AXF_ClosureRun_statusRECONCILED";
import statusRELEASED from "@salesforce/label/c.AXF_ClosureRun_statusRELEASED";
import statusFOLDED from "@salesforce/label/c.AXF_ClosureRun_statusFOLDED";
import reasonEXPORT_PENDING from "@salesforce/label/c.AXF_ClosureRun_reasonEXPORT_PENDING";
import reasonLEGAL_HOLD from "@salesforce/label/c.AXF_ClosureRun_reasonLEGAL_HOLD";
import reasonACTIVE_DEPENDENCIES from "@salesforce/label/c.AXF_ClosureRun_reasonACTIVE_DEPENDENCIES";
import reasonOPEN_REVIEW from "@salesforce/label/c.AXF_ClosureRun_reasonOPEN_REVIEW";
import reasonGRANTS_NOT_ACCESSIBLE from "@salesforce/label/c.AXF_ClosureRun_reasonGRANTS_NOT_ACCESSIBLE";
import reasonREVOCATION_FAILED from "@salesforce/label/c.AXF_ClosureRun_reasonREVOCATION_FAILED";
import reasonCOLLECTION_NOT_PAUSABLE from "@salesforce/label/c.AXF_ClosureRun_reasonCOLLECTION_NOT_PAUSABLE";
import reasonPURGE_INCOMPLETE from "@salesforce/label/c.AXF_ClosureRun_reasonPURGE_INCOMPLETE";
import reasonRESULT_UNKNOWN from "@salesforce/label/c.AXF_ClosureRun_reasonRESULT_UNKNOWN";
import reasonSTAGE_FAILED from "@salesforce/label/c.AXF_ClosureRun_reasonSTAGE_FAILED";
import externalNOT_APPLICABLE from "@salesforce/label/c.AXF_ClosureRun_externalNOT_APPLICABLE";
import externalNOT_CONFIRMED from "@salesforce/label/c.AXF_ClosureRun_externalNOT_CONFIRMED";
import externalCONFIRMED from "@salesforce/label/c.AXF_ClosureRun_externalCONFIRMED";

const labels = {
  title,
  intro,
  holder,
  legalHold,
  start,
  runs,
  noRuns,
  status: statusFieldLabel,
  progress,
  lastStage,
  correlation,
  attempt,
  blockReason,
  nextAction,
  externalRevocation,
  open,
  back,
  resume,
  reconcile: reconcileLabel,
  attachEvidence,
  evidenceRef,
  stages,
  stage: stageFieldLabel,
  impact,
  effectKey,
  completedAt,
  closedBanner,
  unknownBanner,
  blockedBanner,
  loading,
  error: errorLabel,
  codeForbidden,
  codeNotAccessible,
  codeConflict,
  codeTerminal,
  codeReconcileFirst,
  codeNotReconcilable,
  codeInvalidInput,
  stageEXPORT,
  stageREVOKE_ACCESS,
  stageSTOP_COLLECTION,
  stagePURGE,
  stageRETAIN_EVIDENCE,
  stageNONE,
  actionATTACH_EXPORT_EVIDENCE,
  actionRESUME,
  actionRECONCILE,
  actionRELEASE_LEGAL_HOLD,
  actionRESOLVE_DEPENDENCIES,
  actionNONE,
  noAccess,
  confirmResumeTitle,
  confirmResumeBody,
  confirm,
  cancel,
  releaseLegalHold: releaseLegalHoldLabel,
  legalHoldActive,
  evidenceRefLabel,
  lastCompletedAt,
  actions,
  conflictReloaded,
  codeCheckpointsCorrupt,
  statusREQUESTED,
  statusRUNNING,
  statusBLOCKED,
  statusRESULT_UNKNOWN,
  statusCLOSED,
  statusDONE,
  statusRECONCILED,
  statusRELEASED,
  statusFOLDED,
  reasonEXPORT_PENDING,
  reasonLEGAL_HOLD,
  reasonACTIVE_DEPENDENCIES,
  reasonOPEN_REVIEW,
  reasonGRANTS_NOT_ACCESSIBLE,
  reasonREVOCATION_FAILED,
  reasonCOLLECTION_NOT_PAUSABLE,
  reasonPURGE_INCOMPLETE,
  reasonRESULT_UNKNOWN,
  reasonSTAGE_FAILED,
  externalNOT_APPLICABLE,
  externalNOT_CONFIRMED,
  externalCONFIRMED
};

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
