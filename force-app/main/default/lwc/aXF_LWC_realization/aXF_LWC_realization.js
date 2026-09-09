import { LightningElement, api } from "lwc";
import read from "@salesforce/apex/AXF_CLS_CTRL_Realization.read";
import apply from "@salesforce/apex/AXF_CLS_CTRL_Realization.apply";
import reverse from "@salesforce/apex/AXF_CLS_CTRL_Realization.reverse";
import retryFx from "@salesforce/apex/AXF_CLS_CTRL_Realization.retryFx";
import sourceVersion from "@salesforce/apex/AXF_CLS_CTRL_Realization.sourceVersion";
import labels from "./labels";

function message(error) {
  switch (error?.body?.message) {
    case "CURRENCY_MISMATCH":
      return labels.currencyMismatch;
    case "CONFLICT":
      return labels.conflict;
    case "UNAVAILABLE_AMOUNT":
      return labels.unavailableAmount;
    case "REPORTING_CURRENCY_REQUIRED":
      return labels.reportingCurrencyRequired;
    default:
      return labels.error;
  }
}
function operationKey() {
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
    const r = Math.floor(Math.random() * 16);
    return (c === "x" ? r : (r & 3) | 8).toString(16);
  });
}
export default class Realization extends LightningElement {
  _recordId;
  @api
  get recordId() {
    return this._recordId;
  }
  set recordId(value) {
    const changed = value !== this._recordId;
    this._recordId = value;
    if (changed && value && this.isConnected) this.refresh();
  }
  labels = labels;
  selectedTarget;
  state;
  busy = false;
  error;
  success;
  actualOnly = false;
  useExisting = false;
  key = operationKey();
  reversalKeys = {};
  form = {
    sourceKind: "CASH",
    amount: null,
    recognitionDate: new Date().toISOString().slice(0, 10),
    currencyIso: "BRL",
    direction: "DEBIT",
    sourceVersion: 0
  };
  connectedCallback() {
    if (this.targetId) this.refresh();
  }
  get targetId() {
    return this.recordId || this.selectedTarget;
  }
  get standalone() {
    return !this.recordId;
  }
  get hasTarget() {
    return !!this.targetId;
  }
  get showTarget() {
    return this.standalone && !this.actualOnly;
  }
  get showFunding() {
    return this.form.sourceKind !== "CASH" && !this.useExisting;
  }
  get fundingObject() {
    return this.form.sourceKind === "BANK"
      ? "AXF_OBJ_BankAccount__c"
      : "AXF_OBJ_CreditCard__c";
  }
  get factObject() {
    return this.form.sourceKind === "BANK"
      ? "AXF_OBJ_BankAccountTransaction__c"
      : this.form.sourceKind === "CARD"
        ? "AXF_OBJ_CreditCardTransaction__c"
        : "AXF_OBJ_FinancialTransaction__c";
  }
  get sources() {
    return ["CASH", "BANK", "CARD"].map((value, i) => ({
      value,
      label: [labels.cash, labels.bank, labels.card][i]
    }));
  }
  get directions() {
    return [
      { value: "DEBIT", label: labels.debit },
      { value: "CREDIT", label: labels.credit }
    ];
  }
  get rows() {
    return (this.state?.allocations || []).map((row) => ({
      ...row,
      sourceUrl:
        "/" +
        (row.AXF_RA_LKP_BankTransaction__c ||
          row.AXF_RA_LKP_CardTransaction__c ||
          row.AXF_RA_LKP_ManualTransaction__c),
      sourceLabel: row.AXF_RA_LKP_BankTransaction__c
        ? labels.bank
        : row.AXF_RA_LKP_CardTransaction__c
          ? labels.card
          : labels.cash,
      isApplication: row.AXF_RA_PKL_Kind__c === "APPLICATION",
      pending: row.AXF_RA_PKL_FxState__c === "PENDING_FX",
      effect:
        row.AXF_RA_PKL_Kind__c === "APPLICATION"
          ? labels.application
          : labels.reversal
    }));
  }
  get empty() {
    return this.state && !this.rows.length;
  }
  get disabled() {
    return this.busy || (!this.actualOnly && !this.state);
  }
  handleTarget(event) {
    this.selectedTarget = event.detail.recordId;
    this.state = null;
    this.key = operationKey();
    if (this.targetId) this.refresh();
  }
  handleMode(event) {
    this.actualOnly = event.target.checked;
    this.selectedTarget = null;
    this.state = null;
    this.key = operationKey();
  }
  handleExisting(event) {
    this.useExisting = event.target.checked;
    this.form = { ...this.form, sourceId: null, fundingId: null };
    this.key = operationKey();
  }
  async handleChange(event) {
    const field = event.target.dataset.field;
    this.form = {
      ...this.form,
      [field]:
        event.detail?.recordId ?? event.detail?.value ?? event.target.value
    };
    if (field === "sourceKind")
      this.form = { ...this.form, sourceId: null, fundingId: null };
    this.key = operationKey();
    this.success = null;
    if (field === "sourceId" && this.form.sourceId) {
      this.busy = true;
      try {
        this.form = {
          ...this.form,
          sourceVersion: await sourceVersion({
            sourceId: this.form.sourceId,
            sourceKind: this.form.sourceKind
          })
        };
      } catch {
        this.form = { ...this.form, sourceId: null };
        this.error = labels.error;
      } finally {
        this.busy = false;
      }
    }
  }
  async refresh() {
    if (!this.targetId) return;
    this.busy = true;
    this.error = null;
    this.state = null;
    try {
      this.state = JSON.parse(await read({ targetId: this.targetId }));
    } catch (error) {
      this.error = message(error);
    } finally {
      this.busy = false;
    }
  }
  async confirm() {
    const controls = [
      ...this.template.querySelectorAll(
        "lightning-input, lightning-combobox, lightning-record-picker"
      )
    ];
    if (!controls.every((control) => control.reportValidity())) return;
    this.busy = true;
    this.error = null;
    this.success = null;
    try {
      const request = {
        ...this.form,
        amount: Number(this.form.amount),
        sourceVersion: this.useExisting
          ? Number(this.form.sourceVersion)
          : null,
        sourceId: this.useExisting ? this.form.sourceId : null,
        fundingId: this.showFunding ? this.form.fundingId : null,
        targetId: this.actualOnly ? null : this.targetId,
        targetVersion: this.actualOnly ? null : this.state.version,
        operationKey: this.key
      };
      const result = await apply({ request: JSON.stringify(request) });
      // The controller returns the durable allocation and target for ACTUAL_ONLY navigation.
      if (result?.targetId) this.selectedTarget = result.targetId;
      this.key = operationKey();
      this.success = labels.success;
      if (this.targetId) {
        this.actualOnly = false;
        await this.refresh();
      }
    } catch (error) {
      this.error = message(error);
    } finally {
      this.busy = false;
    }
  }
  async reverse(event) {
    const allocationId = event.target.dataset.id;
    this.reversalKeys[allocationId] ||= operationKey();
    this.busy = true;
    this.error = null;
    try {
      await reverse({
        allocationId,
        expectedVersion: this.state.version,
        operationKey: this.reversalKeys[allocationId]
      });
      this.success = labels.success;
      await this.refresh();
    } catch (error) {
      this.error = message(error);
    } finally {
      this.busy = false;
    }
  }
  async retry(event) {
    this.busy = true;
    this.error = null;
    try {
      await retryFx({ allocationId: event.target.dataset.id });
      await this.refresh();
    } catch (error) {
      this.error = message(error);
    } finally {
      this.busy = false;
    }
  }
}
