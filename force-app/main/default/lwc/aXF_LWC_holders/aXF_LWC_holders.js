import { LightningElement, wire, track } from "lwc";
import { refreshApex } from "@salesforce/apex";
import canConfigure from "@salesforce/apex/AXF_CLS_CTRL_Holder.canConfigure";
import listHolders from "@salesforce/apex/AXF_CLS_CTRL_Holder.listHolders";
import saveHolder from "@salesforce/apex/AXF_CLS_CTRL_Holder.saveHolder";
import L from "./labels";

const VIEW = { LIST: "LIST", FORM: "FORM" };

export default class AxfLwcHolders extends LightningElement {
  labels = L;
  view = VIEW.LIST;

  _wired;
  holders = [];
  loading = true;
  loadError = false;
  canEdit = false;
  search = "";

  // form state
  @track form = this.blankForm();
  editing = false;
  saving = false;
  feedback = null; // { variant, text }
  @track duplicates = [];

  columns = [
    {
      label: L.colName,
      fieldName: "name",
      type: "button",
      typeAttributes: {
        label: { fieldName: "name" },
        variant: "base",
        name: "open"
      }
    },
    { label: L.colType, fieldName: "typeLabel", type: "text", fixedWidth: 130 },
    { label: L.colOwner, fieldName: "ownerName", type: "text" }
  ];

  @wire(canConfigure)
  wiredCanConfigure({ data }) {
    if (data !== undefined) {
      this.canEdit = data === true;
    }
  }

  @wire(listHolders, { search: "$search" })
  wiredHolders(result) {
    this._wired = result;
    if (result.data) {
      this.holders = result.data.map((h) => ({
        ...h,
        typeLabel: h.type === "PERSON" ? L.typePerson : L.typeBusiness
      }));
      this.loading = false;
      this.loadError = false;
    } else if (result.error) {
      this.loading = false;
      this.loadError = true;
    }
  }

  blankForm() {
    return {
      accountId: null,
      type: "PERSON",
      firstName: "",
      lastName: "",
      name: "",
      expectedLastModifiedDate: null,
      confirmedDespiteDuplicates: false
    };
  }

  // ---- getters for template state ----
  get isList() {
    return this.view === VIEW.LIST;
  }
  get isForm() {
    return this.view === VIEW.FORM;
  }
  get showSpinner() {
    return this.loading;
  }
  get showError() {
    return !this.loading && this.loadError;
  }
  get showEmpty() {
    return !this.loading && !this.loadError && this.holders.length === 0;
  }
  get showTable() {
    return !this.loading && !this.loadError && this.holders.length > 0;
  }
  get isPerson() {
    return this.form.type === "PERSON";
  }
  get formTitle() {
    return this.editing ? L.editTitle : L.createTitle;
  }
  get saveLabel() {
    return this.saving ? L.saving : L.save;
  }
  get typeOptions() {
    return [
      { label: L.typePerson, value: "PERSON" },
      { label: L.typeBusiness, value: "BUSINESS" }
    ];
  }
  get hasDuplicates() {
    return this.duplicates.length > 0;
  }

  // ---- list actions ----
  handleSearch(event) {
    this.search = event.target.value || "";
  }

  handleRetry() {
    this.loading = true;
    this.loadError = false;
    refreshApex(this._wired);
  }

  handleNew() {
    this.form = this.blankForm();
    this.editing = false;
    this.duplicates = [];
    this.feedback = null;
    this.view = VIEW.FORM;
    this.moveFocus("[data-form-heading]");
  }

  handleRowAction(event) {
    const row = event.detail.row;
    this.form = {
      accountId: row.accountId,
      type: row.type,
      firstName: row.firstName || "",
      lastName: row.lastName || "",
      name: row.name || "",
      expectedLastModifiedDate: row.lastModifiedDate,
      confirmedDespiteDuplicates: false
    };
    this.editing = true;
    this.duplicates = [];
    this.feedback = null;
    this.view = VIEW.FORM;
    this.moveFocus("[data-form-heading]");
  }

  // ---- form actions ----
  handleFieldChange(event) {
    const field = event.target.dataset.field;
    this.form = { ...this.form, [field]: event.target.value };
  }

  handleCancel() {
    this.view = VIEW.LIST;
    this.feedback = null;
    this.duplicates = [];
    this.moveFocus("[data-search]");
  }

  async handleSave() {
    if (this.saving) {
      return;
    }
    this.saving = true;
    this.feedback = null;
    try {
      const result = await saveHolder({ input: this.form });
      this.applyResult(result);
    } catch (error) {
      this.feedback = {
        variant: "error",
        text: (error && error.body && error.body.message) || L.genericError
      };
    } finally {
      this.saving = false;
    }
  }

  handleConfirmDuplicate() {
    this.form = { ...this.form, confirmedDespiteDuplicates: true };
    this.handleSave();
  }

  applyResult(result) {
    switch (result.outcome) {
      case "SUCCEEDED":
        this.feedback = { variant: "success", text: L.saved };
        this.view = VIEW.LIST;
        this.duplicates = [];
        refreshApex(this._wired);
        this.moveFocus("[data-feedback]");
        break;
      case "DUPLICATE_WARNING":
        this.duplicates = (result.possibleDuplicates || []).map((d) => ({
          ...d,
          typeLabel: d.type === "PERSON" ? L.typePerson : L.typeBusiness
        }));
        this.feedback = { variant: "warning", text: L.dupBody };
        this.moveFocus("[data-feedback]");
        break;
      case "CONFLICT":
        this.feedback = { variant: "error", text: L.conflict };
        this.moveFocus("[data-feedback]");
        break;
      case "FORBIDDEN":
        this.feedback = { variant: "error", text: L.forbidden };
        this.moveFocus("[data-feedback]");
        break;
      case "NOT_FOUND":
      case "INVALID":
      case "FAILED":
      default:
        this.feedback = {
          variant: "error",
          text: result.message || L.genericError
        };
        this.moveFocus("[data-feedback]");
    }
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

  get feedbackClass() {
    if (!this.feedback) {
      return "";
    }
    const map = {
      success: "slds-text-color_success",
      error: "slds-text-color_error",
      warning: "slds-text-color_warning"
    };
    return map[this.feedback.variant] || "";
  }
}
