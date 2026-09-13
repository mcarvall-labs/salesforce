import { LightningElement, wire, track } from "lwc";
import canConfigure from "@salesforce/apex/AXF_CLS_CTRL_UserProvisioning.canConfigure";
import preflight from "@salesforce/apex/AXF_CLS_CTRL_UserProvisioning.preflight";
import findLinkableUsers from "@salesforce/apex/AXF_CLS_CTRL_UserProvisioning.findLinkableUsers";
import startProvisioning from "@salesforce/apex/AXF_CLS_CTRL_UserProvisioning.start";
import getStatus from "@salesforce/apex/AXF_CLS_CTRL_UserProvisioning.getStatus";
import resumeProvisioning from "@salesforce/apex/AXF_CLS_CTRL_UserProvisioning.resume";
import L from "./labels";

const STAGE = {
  FORM: "FORM",
  RUNNING: "RUNNING",
  DONE: "DONE",
  FAILED: "FAILED",
  STALLED: "STALLED"
};

// Outcomes that never resolve by waiting: the operation stopped for a reason the
// administrator must act on, so polling must not continue (AXF-107 AC4 / AC6).
const TERMINAL_OUTCOMES = [
  "FORBIDDEN",
  "INVALID",
  "CONFLICT",
  "NOT_FOUND",
  "BLOCKED_LICENSE"
];

export default class AxfLwcAddPersonAccess extends LightningElement {
  labels = L;
  canEdit = false;
  licensesFree = 0;
  stage = STAGE.FORM;
  stepIndex = 0;

  /**
   * Finite observation policy (AXF-107 AC5). The provisioning chain runs as
   * Queueables, so this component watches with a bounded budget plus a stall
   * window instead of polling forever. Reaching either limit never marks the
   * server job failed: it stops the spinner and offers an explicit resume, and it
   * never starts a second provisioning for the same request.
   */
  pollIntervalMs = 2500;
  stallWindowMs = 45000;
  observationBudgetMs = 180000;
  maxStatusFailures = 3;

  @track form = {
    personId: null,
    name: "",
    email: "",
    mode: "CREATE",
    scope: "OWN_DATA",
    existingUserId: null
  };
  userSearch = "";
  userResults = [];
  provisioningId = null;
  status = null;
  feedback = null;
  canRetry = false;
  _poll;
  _pollStartedAt = 0;
  _lastProgressAt = 0;
  _lastProgressKey = null;
  _statusFailures = 0;
  _statusBusy = false;
  _acting = false;

  @wire(canConfigure)
  wiredCanConfigure({ data }) {
    if (data !== undefined) {
      this.canEdit = data === true;
    }
  }

  @wire(preflight)
  wiredPreflight({ data }) {
    if (data) {
      this.licensesFree = data.salesforceLicensesFree;
    }
  }

  @wire(findLinkableUsers, { search: "$userSearch" })
  wiredUsers({ data }) {
    if (data) {
      this.userResults = data;
    }
  }

  // ---- getters ----
  get isForm() {
    return this.stage === STAGE.FORM;
  }
  get isRunning() {
    return this.stage === STAGE.RUNNING;
  }
  get isStalled() {
    return this.stage === STAGE.STALLED;
  }
  get isDone() {
    return this.stage === STAGE.DONE;
  }
  get isFailed() {
    return this.stage === STAGE.FAILED;
  }
  get isCreate() {
    return this.form.mode === "CREATE";
  }
  get isLink() {
    return this.form.mode === "LINK";
  }
  get onPerson() {
    return this.stepIndex === 0;
  }
  get onUser() {
    return this.stepIndex === 1;
  }
  get onScope() {
    return this.stepIndex === 2;
  }
  get onReview() {
    return this.stepIndex === 3;
  }
  get isFirstStep() {
    return this.stepIndex === 0;
  }
  get isLastStep() {
    return this.stepIndex === 3;
  }
  get licenseBlocked() {
    return this.form.mode === "CREATE" && this.licensesFree <= 0;
  }
  get modeOptions() {
    return [
      { label: L.modeCreate, value: "CREATE" },
      { label: L.modeLink, value: "LINK" }
    ];
  }
  get scopeOptions() {
    return [
      { label: L.scopeOwn, value: "OWN_DATA" },
      { label: L.scopeAll, value: "ALL_DATA" }
    ];
  }
  get userOptions() {
    return this.userResults.map((u) => ({
      label: `${u.name} — ${u.username}`,
      value: u.userId
    }));
  }
  get canAdvance() {
    if (this.stepIndex === 0) {
      return Boolean(this.form.personId);
    }
    if (this.stepIndex === 1) {
      return this.isCreate
        ? Boolean(this.form.email) && !this.licenseBlocked
        : Boolean(this.form.existingUserId);
    }
    return true;
  }
  get canAdvanceDisabled() {
    return !this.canAdvance;
  }
  // A retryable failure and an unknown (stalled) outcome both offer "resume"; a
  // terminal one only offers the way back to the form.
  get leaveLabel() {
    return this.canRetry ? L.leave : L.backToForm;
  }
  get linkedUserId() {
    return this.status ? this.status.linkedUserId : null;
  }
  get summaryName() {
    return this.form.name;
  }

  // ---- accessibility helpers ----
  get stepTitle() {
    return [L.stepPerson, L.stepUser, L.stepScope, L.stepReview][
      this.stepIndex
    ];
  }
  get stepOfLabel() {
    return String(L.stepOf)
      .replace("{0}", this.stepIndex + 1)
      .replace("{1}", "4");
  }
  get modeLabelText() {
    return this.isCreate ? L.modeCreate : L.modeLink;
  }
  get scopeLabelText() {
    return this.form.scope === "ALL_DATA" ? L.scopeAll : L.scopeOwn;
  }

  moveFocus(selector) {
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    window.requestAnimationFrame(() => {
      const el = this.template.querySelector(selector);
      if (el) {
        el.focus();
      }
    });
  }

  // ---- form handlers ----
  handlePerson(event) {
    this.form = { ...this.form, personId: event.detail.recordId || null };
  }
  handleField(event) {
    // lightning-radio-group delivers the selection in detail.value; lightning-input
    // in target.value. Reading only target.value left radio fields undefined (AXF-106).
    this.form = {
      ...this.form,
      [event.target.dataset.field]: event.detail?.value ?? event.target.value
    };
  }
  handleUserSearch(event) {
    this.userSearch = event.target.value || "";
  }

  handleBack() {
    if (this.stepIndex > 0) {
      this.stepIndex -= 1;
      this.moveFocus("[data-step-heading]");
    }
  }
  handleNext() {
    if (this.stepIndex < 3) {
      this.stepIndex += 1;
      this.moveFocus("[data-step-heading]");
    }
  }
  handleCancel() {
    this.reset();
    this.moveFocus("[data-step-heading]");
  }

  /**
   * Leaves the running view without claiming success (AXF-107 AC7). The optional
   * step stays unsettled and the same request can be resumed later from the
   * configuration entry point.
   */
  handleLeave() {
    this.clearPoll();
    this.stage = STAGE.FORM;
    this.feedback = null;
    this.canRetry = false;
    this.moveFocus("[data-step-heading]");
  }

  async handleConfirm() {
    if (this._acting) {
      return; // no duplicate provisioning from a double click
    }
    this._acting = true;
    this.stage = STAGE.RUNNING;
    this.feedback = L.starting;
    this.moveFocus("[data-feedback]");
    try {
      const r = await startProvisioning({ ...this.form });
      this.provisioningId = (r && r.provisioningId) || null;
      this.watch(r);
    } catch (e) {
      this.failWith((e && e.body && e.body.message) || L.failed, true);
      this.moveFocus("[data-feedback]");
    } finally {
      this._acting = false;
    }
  }

  async handleRetry() {
    if (this._acting || !this.provisioningId) {
      return;
    }
    this._acting = true;
    this.stage = STAGE.RUNNING;
    this.feedback = L.running;
    this.moveFocus("[data-feedback]");
    try {
      const r = await resumeProvisioning({
        provisioningId: this.provisioningId
      });
      this.watch(r);
    } catch (e) {
      this.failWith((e && e.body && e.body.message) || L.failed, true);
      this.moveFocus("[data-feedback]");
    } finally {
      this._acting = false;
    }
  }

  /**
   * Applies a start/resume/status response and keeps watching only while the
   * operation is genuinely nonterminal: a terminal response never restarts
   * polling, and every watch cycle clears the previous timer first (AC6).
   */
  watch(r) {
    const wasStage = this.stage;
    this.applyResult(r);
    if (this.stage === STAGE.RUNNING) {
      this.startPoll();
    } else {
      this.clearPoll();
    }
    if (this.stage !== wasStage) {
      this.moveFocus("[data-feedback]");
    }
  }

  startPoll() {
    this.clearPoll();
    const now = Date.now();
    this._pollStartedAt = now;
    this._lastProgressAt = now;
    this._statusFailures = 0;
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this._poll = setInterval(() => this.refreshStatus(), this.pollIntervalMs);
  }

  clearPoll() {
    if (this._poll) {
      clearInterval(this._poll);
      this._poll = undefined;
    }
  }

  disconnectedCallback() {
    // AC6: skipping the step, navigating away or changing tab stops the polling.
    this.clearPoll();
    this._statusBusy = false;
  }

  async refreshStatus() {
    if (!this.provisioningId || this._statusBusy) {
      return; // never overlap uncontrolled status requests
    }
    if (Date.now() - this._pollStartedAt >= this.observationBudgetMs) {
      this.stopForUnknown(L.watchLimit);
      return;
    }
    this._statusBusy = true;
    try {
      const r = await getStatus({ provisioningId: this.provisioningId });
      this._statusFailures = 0;
      const wasStage = this.stage;
      this.applyResult(r);
      if (this.stage !== wasStage) {
        this.moveFocus("[data-feedback]");
      }
      if (this.stage !== STAGE.RUNNING) {
        return;
      }
      if (Date.now() - this._lastProgressAt >= this.stallWindowMs) {
        this.stopForUnknown(L.stalled);
      }
    } catch (error) {
      this._statusFailures += 1;
      const detail = (error && error.body && error.body.message) || null;
      this.feedback = detail || L.statusUnavailable;
      if (this._statusFailures >= this.maxStatusFailures) {
        // The server job may still be running: report an unknown outcome with an
        // explicit resume instead of failing it or provisioning twice.
        this.stopForUnknown(
          detail ? `${detail} ${L.statusUnavailable}` : L.statusUnavailable
        );
      }
    } finally {
      this._statusBusy = false;
    }
  }

  applyResult(r) {
    if (!r) {
      return;
    }
    this.status = r;
    if (r.message) {
      this.feedback = r.message;
    }
    const key = `${r.currentStep}|${r.status}`;
    if (key !== this._lastProgressKey) {
      // Progress is a CHANGE of the persisted step/state pair, not a response.
      this._lastProgressKey = key;
      this._lastProgressAt = Date.now();
    }
    if (
      r.currentStep === "DONE" ||
      r.status === "SUCCEEDED" ||
      r.outcome === "ALREADY_DONE"
    ) {
      this.stage = STAGE.DONE;
      this.canRetry = false;
      this.feedback = L.done;
      this.clearPoll();
      return;
    }
    if (r.status === "FAILED_TERMINAL") {
      this.failWith(r.message || L.failed, false);
      return;
    }
    if (TERMINAL_OUTCOMES.includes(r.outcome)) {
      // Freeing a license is the one terminal outcome that is actionable again.
      this.failWith(r.message || L.failed, r.outcome === "BLOCKED_LICENSE");
      return;
    }
    if (r.status === "FAILED_RETRYABLE") {
      this.failWith(r.message || L.failed, true);
      return;
    }
    // PENDING / RUNNING / RESUMED / STARTED — still nonterminal
    this.stage = STAGE.RUNNING;
    this.canRetry = false;
  }

  failWith(message, retryable) {
    this.stage = STAGE.FAILED;
    this.canRetry = retryable === true;
    this.feedback = message;
    this.clearPoll();
  }

  /**
   * Ends the bounded observation with an UNKNOWN outcome: the server job may
   * still be running, so the status is neither failed nor reset, and the only
   * offered action is an explicit resume of the same request.
   */
  stopForUnknown(message) {
    this.clearPoll();
    this.stage = STAGE.STALLED;
    this.canRetry = true;
    this.feedback = message;
    this.moveFocus("[data-feedback]");
  }

  reset() {
    this.clearPoll();
    this.stage = STAGE.FORM;
    this.stepIndex = 0;
    this.provisioningId = null;
    this.status = null;
    this.feedback = null;
    this.canRetry = false;
    this._lastProgressKey = null;
    this._statusFailures = 0;
    this._pollStartedAt = 0;
    this._lastProgressAt = 0;
    this.form = {
      personId: null,
      name: "",
      email: "",
      mode: "CREATE",
      scope: "OWN_DATA",
      existingUserId: null
    };
  }
}
