import { LightningElement, api, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import canConfigure from "@salesforce/apex/AXF_CLS_CTRL_CompanyResponsible.canConfigure";
import getResponsibilities from "@salesforce/apex/AXF_CLS_CTRL_CompanyResponsible.getResponsibilities";
import revokeResponsibility from "@salesforce/apex/AXF_CLS_CTRL_CompanyResponsible.revokeResponsibility";
import confirmResponsibility from "@salesforce/apex/AXF_CLS_CTRL_CompanyResponsible.confirmResponsibility";
import L from "./labels";

const STATUS = {
  GRANTED: { text: L.statusGranted, badge: "slds-theme_success" },
  RELATIONSHIP_ONLY: { text: L.statusPending, badge: "slds-badge" },
  FAILED: { text: L.statusFailed, badge: "slds-theme_warning" },
  REVOKED: { text: L.statusRevoked, badge: "slds-theme_default" }
};

function fmt(dt) {
  if (!dt) return "";
  const d = new Date(dt);
  return Number.isNaN(d.getTime()) ? String(dt) : d.toLocaleString();
}

export default class AxfLwcCompanyResponsibleAccess extends LightningElement {
  @api recordId;
  @api businessIdOverride;

  labels = L;
  canEdit = false;
  _wired;
  rawRows = [];
  loadError = false;
  loading = true;
  feedback;
  pendingRevoke;
  busy = false;

  get businessId() {
    return this.businessIdOverride || this.recordId || null;
  }

  @wire(canConfigure)
  wiredCanConfigure({ data }) {
    if (data !== undefined) {
      this.canEdit = data === true;
    }
  }

  @wire(getResponsibilities, { businessId: "$businessId" })
  wiredRows(result) {
    this._wired = result;
    const { data, error } = result;
    if (error) {
      this.loadError = true;
      this.loading = false;
      this.rawRows = [];
      return;
    }
    if (data === undefined) {
      return;
    }
    this.loadError = false;
    this.loading = false;
    this.rawRows = data;
  }

  // ---- state getters ----
  get isForbidden() {
    return !this.canEdit;
  }
  get hasNoBusiness() {
    return this.canEdit && !this.businessId;
  }
  get isLoading() {
    return this.canEdit && this.businessId && this.loading && !this.loadError;
  }
  get hasError() {
    return this.canEdit && this.loadError;
  }
  get isEmpty() {
    return (
      this.canEdit &&
      this.businessId &&
      !this.loading &&
      !this.loadError &&
      this.rawRows.length === 0
    );
  }
  get isReady() {
    return (
      this.canEdit &&
      !this.loading &&
      !this.loadError &&
      this.rawRows.length > 0
    );
  }

  get rows() {
    return this.rawRows.map((r) => {
      const s = STATUS[r.status] || STATUS.RELATIONSHIP_ONLY;
      const isRevoked = r.status === "REVOKED";
      const when = isRevoked
        ? r.revokedAt
          ? L.revokedOn.replace("{0}", fmt(r.revokedAt))
          : L.actionNone
        : r.grantedAt
          ? L.grantedOn.replace("{0}", fmt(r.grantedAt))
          : L.actionNone;
      let hint = "";
      if (r.status === "RELATIONSHIP_ONLY") hint = L.hintPending;
      else if (r.status === "REVOKED") hint = L.hintRevoked;
      else if (r.status === "FAILED")
        hint = L.hintFailedPrefix + (r.lastError || L.genericFail);
      return {
        craId: r.craId,
        version: r.version,
        personId: r.personId,
        personName: r.personName || "—",
        roleText:
          r.role === "PARTNER"
            ? L.rolePartner
            : r.role === "MANAGER"
              ? L.roleManager
              : r.role,
        role: r.role,
        statusText: s.text,
        badgeClass: `slds-badge ${s.badge}`,
        whenText: when,
        hint,
        canRevoke: r.status === "GRANTED",
        canRetry: r.status === "FAILED" && Boolean(r.personId),
        actionLabel:
          r.status === "GRANTED"
            ? L.actionRevoke
            : r.status === "FAILED" && r.personId
              ? L.actionRetry
              : ""
      };
    });
  }

  get confirmName() {
    return this.pendingRevoke ? this.pendingRevoke.personName : "";
  }

  // ---- a11y ----
  moveFocus(selector) {
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    window.requestAnimationFrame(() => {
      const el = this.template.querySelector(selector);
      if (el) el.focus();
    });
  }

  // ---- actions ----
  handleAction(event) {
    const row = this.rows.find((r) => r.craId === event.target.dataset.id);
    if (!row) return;
    if (row.canRevoke) {
      this.pendingRevoke = row;
      this.feedback = undefined;
      this.moveFocus("[data-confirm-cancel]");
    } else if (row.canRetry) {
      this.retryGrant(row);
    }
  }

  cancelRevoke() {
    const id = this.pendingRevoke && this.pendingRevoke.craId;
    this.pendingRevoke = undefined;
    if (id) this.moveFocus(`[data-action-id="${id}"]`);
  }

  handleDialogKey(event) {
    if (event.key === "Escape") {
      this.cancelRevoke();
    }
  }

  async confirmRevoke() {
    if (!this.pendingRevoke || this.busy) return;
    const target = this.pendingRevoke;
    this.busy = true;
    this.feedback = L.working;
    try {
      const res = await revokeResponsibility({
        craId: target.craId,
        expectedVersion: target.version
      });
      await this.settle(res, L.revokeDone);
    } catch (e) {
      this.feedback = this.messageOf(e);
    } finally {
      this.busy = false;
      this.pendingRevoke = undefined;
      this.moveFocus("[data-feedback]");
    }
  }

  async retryGrant(row) {
    if (this.busy) return;
    this.busy = true;
    this.feedback = L.working;
    try {
      const res = await confirmResponsibility({
        input: {
          businessId: this.businessId,
          personId: row.personId,
          role: row.role,
          expectedVersion: row.version
        }
      });
      await this.settle(res, L.retryDone);
    } catch (e) {
      this.feedback = this.messageOf(e);
    } finally {
      this.busy = false;
      this.moveFocus("[data-feedback]");
    }
  }

  async settle(res, okMessage) {
    await refreshApex(this._wired);
    if (res && res.outcome === "CONFLICT") {
      this.feedback = L.conflictReload;
    } else if (res && res.message) {
      this.feedback = res.message;
    } else {
      this.feedback = okMessage;
    }
  }

  messageOf(e) {
    return (e && e.body && e.body.message) || L.genericFail;
  }
}
