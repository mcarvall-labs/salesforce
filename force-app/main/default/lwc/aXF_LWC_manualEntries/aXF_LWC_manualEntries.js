import { LightningElement } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import LOCALE from "@salesforce/i18n/locale";
import listEntries from "@salesforce/apex/AXF_CLS_CTRL_ManualEntries.listEntries";
import labels from "./labels";

const STATUSES = ["UNRECONCILED", "PARTIAL", "RECONCILED", "UNVERIFIED"];
const MAX_PERIOD_DAYS = 366;
const EMPTY_FILTERS = {
  fromDate: null,
  toDate: null,
  status: "",
  direction: "",
  originId: ""
};
const CODE_LABEL = {
  NOT_ACCESSIBLE: labels.codeNOT_ACCESSIBLE,
  UNAVAILABLE: labels.codeUNAVAILABLE,
  INVALID_INPUT: labels.codeINVALID_INPUT
};

function parseIsoDate(value) {
  if (!value) {
    return null;
  }
  const [y, m, d] = String(value).split("-").map(Number);
  return new Date(y, m - 1, d);
}

function format(template, ...args) {
  return String(template).replace(/\{(\d+)\}/g, (match, index) => {
    const value = args[index];
    return value === undefined || value === null ? "" : value;
  });
}

/**
 * AXF-153: manual expenses and income of the authorized holders ("Despesas e receitas") with the
 * reconciliation status derived on the server, filtered by status, period, nature and origin.
 */
export default class AxfLwcManualEntries extends NavigationMixin(
  LightningElement
) {
  labels = labels;
  report;
  loading = true;
  message;
  year;
  month;
  draftFilters = { ...EMPTY_FILTERS };
  filters = { ...EMPTY_FILTERS };
  seq = 0;

  connectedCallback() {
    const now = new Date();
    this.year = now.getFullYear();
    this.month = now.getMonth() + 1;
    this.load();
  }

  // ------------------------------------------------------------ getters

  get statusOptions() {
    return [
      { label: labels.all, value: "" },
      ...STATUSES.map((s) => ({ label: labels[`status${s}`], value: s }))
    ];
  }

  get natureOptions() {
    return [
      { label: labels.all, value: "" },
      { label: labels.natureDEBIT, value: "DEBIT" },
      { label: labels.natureCREDIT, value: "CREDIT" }
    ];
  }

  get originOptions() {
    const origins = (this.report && this.report.origins) || [];
    return [
      { label: labels.all, value: "" },
      ...origins.map((o) => ({ label: o.label, value: o.originId }))
    ];
  }

  get periodLabel() {
    if (!this.report) {
      return "";
    }
    if (this.report.customPeriod) {
      return format(
        labels.customPeriod,
        this.formatDate(this.report.fromDate),
        this.formatDate(this.report.toDate)
      );
    }
    return new Intl.DateTimeFormat(LOCALE, {
      month: "long",
      year: "numeric"
    }).format(new Date(this.report.year, this.report.month - 1, 1));
  }

  get caption() {
    return format(labels.caption, this.periodLabel);
  }

  get hasEntries() {
    return Boolean(this.report) && this.report.entries.length > 0;
  }

  get showNoEntries() {
    return Boolean(this.report) && !this.loading && !this.hasEntries;
  }

  get truncated() {
    return Boolean(this.report && this.report.truncated);
  }

  get rows() {
    if (!this.report) {
      return [];
    }
    return this.report.entries.map((e) => ({
      ...e,
      key: e.recordId,
      dateText: this.formatDate(e.entryDate),
      descriptionText: e.description || labels.noDescription,
      natureLabel: labels[`nature${e.direction}`] || e.direction,
      situationLabel: labels[`kind${e.planKind}`] || e.planKind,
      originText: e.originLabel || labels.noOrigin,
      signedAmount:
        e.amount === null || e.amount === undefined
          ? null
          : e.direction === "DEBIT"
            ? -e.amount
            : e.amount,
      statusLabel: labels[`status${e.status}`] || e.status,
      statusClass:
        e.status === "RECONCILED"
          ? "slds-badge slds-theme_success"
          : e.status === "PARTIAL"
            ? "slds-badge slds-theme_warning"
            : "slds-badge"
    }));
  }

  formatDate(value) {
    const date = parseIsoDate(value);
    return date ? new Intl.DateTimeFormat(LOCALE).format(date) : "";
  }

  // ------------------------------------------------------------ loading

  async load() {
    this.loading = true;
    // Only the newest request may paint: a late answer to an older one is ignored.
    const seq = ++this.seq;
    const request = {
      year: this.year,
      month: this.month,
      fromDate: this.filters.fromDate || null,
      toDate: this.filters.toDate || null,
      status: this.filters.status || null,
      direction: this.filters.direction || null,
      originId: this.filters.originId || null
    };
    try {
      const report = await listEntries({ request: JSON.stringify(request) });
      if (seq !== this.seq) {
        return;
      }
      this.report = report;
      this.year = report.year;
      this.month = report.month;
      this.message = undefined;
    } catch (e) {
      if (seq === this.seq) {
        const code = e && e.body && e.body.message;
        this.message = CODE_LABEL[code] || labels.error;
      }
    } finally {
      if (seq === this.seq) {
        this.loading = false;
      }
    }
  }

  // ------------------------------------------------------------ handlers

  shiftMonth(delta) {
    let month = this.month + delta;
    let year = this.year;
    if (month < 1) {
      month = 12;
      year -= 1;
    } else if (month > 12) {
      month = 1;
      year += 1;
    }
    this.month = month;
    this.year = year;
    // Month paging leaves any custom period; the other filters stay applied.
    this.filters = { ...this.filters, fromDate: null, toDate: null };
    this.draftFilters = { ...this.draftFilters, fromDate: null, toDate: null };
    this.load();
  }

  handlePrevious() {
    this.shiftMonth(-1);
  }

  handleNext() {
    this.shiftMonth(1);
  }

  handleFilterChange(event) {
    const field = event.target.dataset.field;
    this.draftFilters = { ...this.draftFilters, [field]: event.detail.value };
  }

  /** The server enforces the same rules; an invalid period never leaves the client. */
  periodError() {
    const { fromDate, toDate } = this.draftFilters;
    if (Boolean(fromDate) !== Boolean(toDate)) {
      return {
        field: fromDate ? "toDate" : "fromDate",
        text: labels.filterPeriodIncomplete
      };
    }
    if (fromDate && toDate) {
      const days = Math.round(
        (parseIsoDate(toDate) - parseIsoDate(fromDate)) / 86400000
      );
      if (days < 0) {
        return { field: "toDate", text: labels.filterPeriodOrder };
      }
      if (days >= MAX_PERIOD_DAYS) {
        return { field: "toDate", text: labels.filterPeriodTooLong };
      }
    }
    return null;
  }

  handleApplyFilters() {
    const error = this.periodError();
    const inputs = [
      ...this.template.querySelectorAll("lightning-input[data-filter]")
    ];
    inputs.forEach((input) => {
      input.setCustomValidity(
        error && error.field === input.dataset.field ? error.text : ""
      );
      input.reportValidity();
    });
    if (error) {
      return;
    }
    this.filters = { ...this.draftFilters };
    this.load();
  }

  handleClearFilters() {
    this.filters = { ...EMPTY_FILTERS };
    this.draftFilters = { ...EMPTY_FILTERS };
    this.load();
  }

  handleNewEntry() {
    this[NavigationMixin.Navigate]({
      type: "standard__navItemPage",
      attributes: { apiName: "AXF_EntryWizard" }
    });
  }
}
