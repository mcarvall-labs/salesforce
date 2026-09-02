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
  FAILED: "FAILED"
};

export default class AxfLwcAddPersonAccess extends LightningElement {
  labels = L;
  canEdit = false;
  licensesFree = 0;
  stage = STAGE.FORM;
  stepIndex = 0;

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
  _poll;

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
    this.form = {
      ...this.form,
      [event.target.dataset.field]: event.target.value
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

  async handleConfirm() {
    this.stage = STAGE.RUNNING;
    this.feedback = L.starting;
    this.moveFocus("[data-feedback]");
    try {
      const r = await startProvisioning({ input: this.form });
      this.provisioningId = r.provisioningId;
      this.applyResult(r);
      this.poll();
    } catch (e) {
      this.stage = STAGE.FAILED;
      this.feedback = (e && e.body && e.body.message) || L.failed;
      this.moveFocus("[data-feedback]");
    }
  }

  async handleRetry() {
    this.stage = STAGE.RUNNING;
    this.feedback = L.running;
    this.moveFocus("[data-feedback]");
    try {
      const r = await resumeProvisioning({
        provisioningId: this.provisioningId
      });
      this.applyResult(r);
      this.poll();
    } catch (e) {
      this.stage = STAGE.FAILED;
      this.feedback = (e && e.body && e.body.message) || L.failed;
      this.moveFocus("[data-feedback]");
    }
  }

  poll() {
    this.clearPoll();
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this._poll = setInterval(() => this.refreshStatus(), 2500);
  }
  clearPoll() {
    if (this._poll) {
      clearInterval(this._poll);
      this._poll = undefined;
    }
  }
  disconnectedCallback() {
    this.clearPoll();
  }

  async refreshStatus() {
    if (!this.provisioningId) {
      return;
    }
    try {
      const r = await getStatus({ provisioningId: this.provisioningId });
      this.applyResult(r);
    } catch (error) {
      // transient — keep polling
      this.feedback =
        (error && error.body && error.body.message) || this.feedback;
    }
  }

  applyResult(r) {
    this.status = r;
    this.feedback = r.message;
    const wasStage = this.stage;
    if (r.currentStep === "DONE" || r.status === "SUCCEEDED") {
      this.stage = STAGE.DONE;
      this.feedback = L.done;
      this.clearPoll();
    } else if (
      r.status === "FAILED_TERMINAL" ||
      r.status === "FAILED_RETRYABLE" ||
      r.outcome === "FORBIDDEN" ||
      r.outcome === "INVALID" ||
      r.outcome === "BLOCKED_LICENSE" ||
      r.outcome === "CONFLICT"
    ) {
      this.stage = STAGE.FAILED;
      this.clearPoll();
    } else {
      this.stage = STAGE.RUNNING;
    }
    if (this.stage !== wasStage) {
      this.moveFocus("[data-feedback]");
    }
  }

  reset() {
    this.clearPoll();
    this.stage = STAGE.FORM;
    this.stepIndex = 0;
    this.provisioningId = null;
    this.status = null;
    this.feedback = null;
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
