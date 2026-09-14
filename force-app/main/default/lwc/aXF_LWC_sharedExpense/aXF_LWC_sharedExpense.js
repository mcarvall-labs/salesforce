import { LightningElement, api, wire } from "lwc";
import getCapabilities from "@salesforce/apex/AXF_CLS_CTRL_SharedExpense.getCapabilities";
import getCollaborators from "@salesforce/apex/AXF_CLS_CTRL_SharedExpense.getCollaborators";
import getGrants from "@salesforce/apex/AXF_CLS_CTRL_SharedExpense.getGrants";
import share from "@salesforce/apex/AXF_CLS_CTRL_SharedExpense.share";
import revoke from "@salesforce/apex/AXF_CLS_CTRL_SharedExpense.revoke";
import listShared from "@salesforce/apex/AXF_CLS_CTRL_SharedExpense.listShared";
import readShared from "@salesforce/apex/AXF_CLS_CTRL_SharedExpense.readShared";
import updateShared from "@salesforce/apex/AXF_CLS_CTRL_SharedExpense.updateShared";
import confirmRealization from "@salesforce/apex/AXF_CLS_CTRL_SharedExpense.confirmRealization";
import labels from "./labels";

const CODE_LABELS = {
  FORBIDDEN: "codeForbidden",
  NOT_ACCESSIBLE: "codeNotAccessible",
  CONFLICT: "codeConflict",
  INVALID_INPUT: "codeInvalidInput",
  REALIZATION_DENIED: "codeRealizationDenied",
  REJECTED: "codeRejected",
  COLLABORATOR_NOT_FOUND: "codeCollaboratorNotFound"
};

export function failureMessage(error) {
  const code = error?.body?.message;
  return labels[CODE_LABELS[code]] || labels.error;
}

function requestKey() {
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

export default class SharedExpense extends LightningElement {
  @api recordId;
  labels = labels;
  capabilities = { canShare: false, canCollaborate: false };
  collaborators = [];
  grants = [];
  shared = [];
  detail;
  busy = false;
  error;
  success;
  confirmation;
  shareForm = { collaboratorId: "", permission: "VIEW" };
  editForm = { description: "", userCategory: "" };
  realizeForm = { amount: "", recognitionDate: "" };
  requestId = requestKey();
  realizeRequestId = requestKey();

  @wire(getCapabilities)
  wiredCapabilities({ data, error }) {
    if (data) {
      this.capabilities = data;
      if (this.isOwnerMode) {
        this.loadGrants();
      } else if (data.canCollaborate) {
        this.loadShared();
      }
    } else if (error) {
      this.error = failureMessage(error);
    }
  }

  @wire(getCollaborators)
  wiredCollaborators({ data }) {
    if (data) {
      this.collaborators = data;
    }
  }

  get isOwnerMode() {
    return Boolean(this.recordId) && this.capabilities.canShare;
  }
  get isCollaboratorMode() {
    return !this.recordId && this.capabilities.canCollaborate;
  }
  get collaboratorOptions() {
    return this.collaborators.map((row) => ({
      label: row.name,
      value: row.userId
    }));
  }
  get permissionOptions() {
    return [
      { label: labels.canView, value: "VIEW" },
      { label: labels.canEdit, value: "EDIT" }
    ];
  }
  get grantRows() {
    return this.grants.map((grant) => ({
      ...grant,
      permissionLabel:
        grant.permission === "EDIT" ? labels.canEdit : labels.canView,
      statusLabel: grant.status === "ACTIVE" ? labels.active : labels.revoked,
      isActive: grant.status === "ACTIVE"
    }));
  }
  get hasGrants() {
    return this.grants.length > 0;
  }
  get hasShared() {
    return this.shared.length > 0;
  }
  get shareDisabled() {
    return this.busy || !this.shareForm.collaboratorId;
  }
  get accessText() {
    return this.detail?.canEdit ? labels.editAllowed : labels.viewOnly;
  }
  get saveDisabled() {
    return this.busy || !this.detail?.canEdit;
  }
  get realizeDisabled() {
    return (
      this.busy ||
      !this.detail?.canRealize ||
      !this.realizeForm.amount ||
      Number(this.realizeForm.amount) <= 0
    );
  }
  get confirmationBody() {
    if (!this.confirmation) return "";
    if (this.confirmation.kind === "REALIZE") {
      return format(
        labels.confirmRealizeBody,
        this.detail?.name,
        `${this.realizeForm.amount} ${this.detail?.currencyIso || ""}`
      );
    }
    return format(labels.confirmBody, this.detail?.name);
  }

  renderedCallback() {
    if (this.confirmation && !this.confirmation.focused) {
      this.confirmation = { ...this.confirmation, focused: true };
      const button = this.template.querySelector('[data-id="confirm-yes"]');
      if (button) button.focus();
    }
  }

  // ---------------------------------------------------------------- owner

  async loadGrants() {
    this.busy = true;
    try {
      this.grants = await getGrants({ financialTransactionId: this.recordId });
    } catch (failure) {
      this.error = failureMessage(failure);
    } finally {
      this.busy = false;
    }
  }
  handleShareField(event) {
    const { name } = event.target;
    this.shareForm = { ...this.shareForm, [name]: event.detail.value };
  }
  async handleShare() {
    this.reset();
    this.busy = true;
    try {
      await share({
        request: JSON.stringify({
          financialTransactionId: this.recordId,
          collaboratorId: this.shareForm.collaboratorId,
          permission: this.shareForm.permission,
          clientRequestId: this.requestId
        })
      });
      this.success = labels.shared;
      this.requestId = requestKey();
      this.shareForm = { collaboratorId: "", permission: "VIEW" };
      await this.loadGrants();
    } catch (failure) {
      this.error = failureMessage(failure);
    } finally {
      this.busy = false;
    }
  }
  async handleRevoke(event) {
    const { id, version } = event.target.dataset;
    this.reset();
    this.busy = true;
    try {
      await revoke({ grantId: id, expectedVersion: Number(version) });
      this.success = labels.revokedDone;
      await this.loadGrants();
    } catch (failure) {
      this.error = failureMessage(failure);
    } finally {
      this.busy = false;
    }
  }

  // ---------------------------------------------------------------- collaborator

  async loadShared() {
    this.busy = true;
    try {
      this.shared = await listShared();
    } catch (failure) {
      this.error = failureMessage(failure);
    } finally {
      this.busy = false;
    }
  }
  async handleOpen(event) {
    this.reset();
    this.busy = true;
    try {
      this.detail = await readShared({
        financialTransactionId: event.target.dataset.id
      });
      this.editForm = {
        description: this.detail.description || "",
        userCategory: this.detail.userCategory || ""
      };
      this.realizeForm = {
        amount: this.detail.amount ?? "",
        recognitionDate: new Date().toISOString().slice(0, 10)
      };
      this.requestId = requestKey();
      this.realizeRequestId = requestKey();
    } catch (failure) {
      this.error = failureMessage(failure);
      this.detail = undefined;
    } finally {
      this.busy = false;
    }
  }
  handleBack() {
    this.detail = undefined;
    this.confirmation = undefined;
    this.loadShared();
  }
  handleEditField(event) {
    const { name, value } = event.target;
    this.editForm = { ...this.editForm, [name]: value };
  }
  handleRealizeField(event) {
    const { name, value } = event.target;
    this.realizeForm = { ...this.realizeForm, [name]: value };
  }
  askSave() {
    this.reset();
    this.confirmation = { kind: "SAVE" };
  }
  askRealize() {
    this.reset();
    this.confirmation = { kind: "REALIZE" };
  }
  cancelConfirmation() {
    this.confirmation = undefined;
  }
  async acceptConfirmation() {
    const kind = this.confirmation?.kind;
    this.confirmation = undefined;
    if (kind === "SAVE") {
      await this.save();
    } else if (kind === "REALIZE") {
      await this.realize();
    }
  }
  async save() {
    this.busy = true;
    try {
      this.detail = await updateShared({
        request: JSON.stringify({
          financialTransactionId: this.detail.financialTransactionId,
          description: this.editForm.description,
          userCategory: this.editForm.userCategory,
          expectedVersion: this.detail.version,
          clientRequestId: this.requestId
        })
      });
      this.success = labels.saved;
      this.requestId = requestKey();
    } catch (failure) {
      this.error = failureMessage(failure);
    } finally {
      this.busy = false;
    }
  }
  async realize() {
    this.busy = true;
    try {
      await confirmRealization({
        request: JSON.stringify({
          financialTransactionId: this.detail.financialTransactionId,
          amount: Number(this.realizeForm.amount),
          recognitionDate: this.realizeForm.recognitionDate,
          expectedVersion: this.detail.version,
          clientRequestId: this.realizeRequestId
        })
      });
      this.success = labels.realized;
      this.realizeRequestId = requestKey();
      this.detail = await readShared({
        financialTransactionId: this.detail.financialTransactionId
      });
    } catch (failure) {
      this.error = failureMessage(failure);
    } finally {
      this.busy = false;
    }
  }
  reset() {
    this.error = undefined;
    this.success = undefined;
  }
}
