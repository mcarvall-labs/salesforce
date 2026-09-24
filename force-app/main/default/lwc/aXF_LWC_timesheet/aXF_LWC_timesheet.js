import { LightningElement, wire } from "lwc";
import LOCALE from "@salesforce/i18n/locale";
import getContext from "@salesforce/apex/AXF_CLS_CTRL_Timesheet.getContext";
import listContracts from "@salesforce/apex/AXF_CLS_CTRL_Timesheet.listContracts";
import saveEntry from "@salesforce/apex/AXF_CLS_CTRL_Timesheet.saveEntry";
import submitEntry from "@salesforce/apex/AXF_CLS_CTRL_Timesheet.submitEntry";
import listEntries from "@salesforce/apex/AXF_CLS_CTRL_Timesheet.listEntries";
import getForecast from "@salesforce/apex/AXF_CLS_CTRL_Timesheet.getForecast";
import labels from "./labels";
import { parseFailure, format } from "./failures";

const EMPTY_FILTERS = {
  fromDate: null,
  toDate: null,
  contractId: "",
  billingStatus: "",
  recordStatus: ""
};
const RECORD_STATUSES = [
  "DRAFT",
  "SUBMITTED",
  "APPROVED",
  "REJECTED",
  "SUPERSEDED"
];
const BILLING_STATUSES = ["BILLED", "PARTIAL", "UNBILLED", "NOT_BILLABLE"];
const NO_DESTINATION = "NONE";

function parseIsoDate(value) {
  if (!value) {
    return null;
  }
  const [y, m, d] = String(value).split("-").map(Number);
  return new Date(y, m - 1, d);
}

function todayIso() {
  const now = new Date();
  const pad = (n) => String(n).padStart(2, "0");
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
}

/** `HH:mm` of a lightning time value (`HH:mm:ss.SSS`); blank stays null. */
function clock(value) {
  return value ? String(value).slice(0, 5) : null;
}

function minutes(value) {
  const hhmm = clock(value);
  if (!hhmm) {
    return null;
  }
  const [h, m] = hhmm.split(":").map(Number);
  return h * 60 + m;
}

function emptyForm(contractId) {
  return {
    workDate: todayIso(),
    contractId: contractId || "",
    startTime: null,
    breakStart: null,
    breakEnd: null,
    endTime: null,
    note: ""
  };
}

export default class AxfLwcTimesheet extends LightningElement {
  labels = labels;
  context;
  loading = true;
  error;
  message;
  messageIsError = false;
  contracts = [];
  form = emptyForm();
  saving = false;
  year;
  month;
  draftFilters = { ...EMPTY_FILTERS };
  filters = { ...EMPTY_FILTERS };
  list;
  listLoading = false;
  listSeq = 0;
  forecast;
  forecastLoading = false;
  forecastSeq = 0;
  destination = "";
  busyId;
  /** DRAFT/REJECTED entry loaded into the form for correction. */
  editingId;

  @wire(getContext)
  wiredContext({ data, error }) {
    if (data) {
      this.context = data;
      const now = new Date();
      this.year = now.getFullYear();
      this.month = now.getMonth() + 1;
      this.loadContracts();
      this.loadEntries();
      this.loadForecast();
    } else if (error) {
      this.error = parseFailure(error);
      this.loading = false;
    }
  }

  // ------------------------------------------------------------ getters

  get maxWorkDate() {
    return todayIso();
  }
  get editingText() {
    const row =
      this.list &&
      this.list.entries.find((e) => e.workRecordId === this.editingId);
    return row ? format(labels.editing, this.formatDate(row.workDate)) : "";
  }

  get canRegister() {
    return Boolean(this.context && this.context.canRegister);
  }
  get showReadOnly() {
    return Boolean(this.context) && !this.context.canRegister;
  }
  get hasContracts() {
    return this.contracts.length > 0;
  }
  get showForm() {
    return this.canRegister && this.hasContracts;
  }
  get showNoContracts() {
    return this.canRegister && !this.loading && !this.hasContracts;
  }
  get messageClass() {
    return this.messageIsError
      ? "slds-notify slds-notify_alert slds-alert_error slds-var-m-bottom_small"
      : "slds-notify slds-notify_alert slds-alert_success slds-var-m-bottom_small";
  }

  get contractOptions() {
    return this.contracts.map((c) => ({
      label: c.holderLabel ? `${c.label} (${c.holderLabel})` : c.label,
      value: c.contractId
    }));
  }
  get filterContractOptions() {
    return [{ label: labels.allContracts, value: "" }, ...this.contractOptions];
  }
  get billingOptions() {
    return [
      { label: labels.allStatuses, value: "" },
      ...BILLING_STATUSES.map((s) => ({
        label: labels[`billing${s}`],
        value: s
      }))
    ];
  }
  get recordStatusOptions() {
    return [
      { label: labels.allStatuses, value: "" },
      ...RECORD_STATUSES.map((s) => ({ label: labels[`status${s}`], value: s }))
    ];
  }

  get selectedContract() {
    return this.contracts.find((c) => c.contractId === this.form.contractId);
  }
  get rateInfo() {
    const c = this.selectedContract;
    return c
      ? format(labels.rateInfo, this.formatMoney(c.rate, c.currencyIsoCode))
      : "";
  }

  /** Same rule the server applies: (End − Start) − (Return − Break), same day, ordered. */
  get computed() {
    const start = minutes(this.form.startTime);
    const end = minutes(this.form.endTime);
    const breakStart = minutes(this.form.breakStart);
    const breakEnd = minutes(this.form.breakEnd);
    if ((breakStart === null) !== (breakEnd === null)) {
      return { error: labels.breakIncomplete, field: "breakEnd" };
    }
    if (start === null || end === null) {
      return {};
    }
    let worked;
    if (breakStart === null) {
      if (!(start < end)) {
        return { error: labels.timeOrder, field: "endTime" };
      }
      worked = end - start;
    } else {
      if (!(start < breakStart && breakStart < breakEnd && breakEnd < end)) {
        return { error: labels.timeOrder, field: "endTime" };
      }
      worked = end - start - (breakEnd - breakStart);
    }
    return { hours: Math.round((worked / 60) * 100) / 100 };
  }
  get computedText() {
    const hours = this.computed.hours;
    return hours === undefined
      ? ""
      : format(labels.computedHours, this.formatHours(hours));
  }

  get periodLabel() {
    if (this.filters.fromDate && this.filters.toDate) {
      return format(
        labels.customPeriod,
        this.formatDate(this.filters.fromDate),
        this.formatDate(this.filters.toDate)
      );
    }
    return this.monthLabel;
  }
  get monthLabel() {
    if (!this.year) {
      return "";
    }
    return new Intl.DateTimeFormat(LOCALE, {
      month: "long",
      year: "numeric"
    }).format(new Date(this.year, this.month - 1, 1));
  }
  get entriesCaption() {
    return format(labels.entriesCaption, this.periodLabel);
  }

  get hasEntries() {
    return Boolean(this.list) && this.list.entries.length > 0;
  }
  get showNoEntries() {
    return Boolean(this.list) && !this.listLoading && !this.hasEntries;
  }
  get entryRows() {
    if (!this.list) {
      return [];
    }
    return this.list.entries.map((e) => {
      const dateText = this.formatDate(e.workDate);
      return {
        ...e,
        key: e.workRecordId,
        dateText,
        hoursText: this.formatHours(e.hours),
        statusLabel: labels[`status${e.status}`] || e.status,
        billingLabel: labels[`billing${e.billingStatus}`] || e.billingStatus,
        billingClass:
          e.billingStatus === "BILLED"
            ? "slds-badge slds-theme_success"
            : e.billingStatus === "PARTIAL"
              ? "slds-badge slds-theme_warning"
              : "slds-badge",
        submitLabel: format(labels.submitFor, dateText),
        editLabel: format(labels.editFor, dateText),
        busy: this.busyId === e.workRecordId
      };
    });
  }

  get forecastIntro() {
    return format(labels.forecastIntro, this.monthLabel);
  }
  get forecastCaption() {
    return format(labels.forecastCaption, this.monthLabel);
  }
  destinationLabel(d) {
    if (!d || d.key === NO_DESTINATION) {
      return labels.noDestination;
    }
    return d.wallet ? labels.wallet : d.label || "";
  }
  get destinationOptions() {
    const destinations = (this.forecast && this.forecast.destinations) || [];
    return [
      { label: labels.allDestinations, value: "" },
      ...destinations.map((d) => ({
        label: this.destinationLabel(d),
        value: d.key
      }))
    ];
  }
  get hasForecast() {
    return Boolean(this.forecast) && this.forecast.groups.length > 0;
  }
  get showNoForecast() {
    return Boolean(this.forecast) && !this.forecastLoading && !this.hasForecast;
  }
  get forecastGroups() {
    if (!this.forecast) {
      return [];
    }
    return this.forecast.groups.map((g) => ({
      key: g.destination.key,
      headingId: `axf157-group-${g.destination.key}`,
      label: this.destinationLabel(g.destination),
      lines: g.lines.map((l) => ({
        ...l,
        key: `${l.contractId}-${l.currencyIsoCode}`,
        approvedHoursText: this.formatHours(l.approvedHours),
        pendingHoursText: this.formatHours(l.pendingHours)
      })),
      totals: g.totals.map((t) => this.totalRow(t))
    }));
  }
  get grandTotals() {
    return ((this.forecast && this.forecast.totals) || []).map((t) =>
      this.totalRow(t)
    );
  }
  totalRow(total) {
    return {
      ...total,
      key: total.currencyIsoCode,
      approvedHoursText: this.formatHours(total.approvedHours),
      pendingHoursText: this.formatHours(total.pendingHours)
    };
  }

  // ------------------------------------------------------------ formatting

  formatDate(value) {
    const date = parseIsoDate(value);
    return date ? new Intl.DateTimeFormat(LOCALE).format(date) : "";
  }

  formatHours(value) {
    if (value === null || value === undefined) {
      return "";
    }
    return new Intl.NumberFormat(LOCALE, { maximumFractionDigits: 2 }).format(
      value
    );
  }

  formatMoney(value, iso) {
    if (value === null || value === undefined) {
      return "";
    }
    try {
      return new Intl.NumberFormat(LOCALE, {
        style: "currency",
        currency: iso || "BRL"
      }).format(value);
    } catch {
      return String(value);
    }
  }

  // ------------------------------------------------------------ loading

  async loadContracts() {
    this.loading = true;
    try {
      this.contracts = (await listContracts()) || [];
      if (!this.selectedContract) {
        this.form = {
          ...this.form,
          contractId:
            this.contracts.length === 1 ? this.contracts[0].contractId : ""
        };
      }
    } catch (e) {
      this.contracts = [];
      this.showError(e);
    } finally {
      this.loading = false;
    }
  }

  async loadEntries() {
    this.listLoading = true;
    // Only the newest request may paint: a late answer to an older one is ignored.
    const seq = ++this.listSeq;
    const f = this.filters;
    const request = {
      year: this.year,
      month: this.month,
      fromDate: f.fromDate || null,
      toDate: f.toDate || null,
      contractId: f.contractId || null,
      billingStatus: f.billingStatus || null,
      recordStatus: f.recordStatus || null
    };
    try {
      const list = await listEntries({ request: JSON.stringify(request) });
      if (seq === this.listSeq) {
        this.list = list;
      }
    } catch (e) {
      if (seq === this.listSeq) {
        this.showError(e);
      }
    } finally {
      if (seq === this.listSeq) {
        this.listLoading = false;
      }
    }
  }

  async loadForecast() {
    this.forecastLoading = true;
    const seq = ++this.forecastSeq;
    const request = {
      year: this.year,
      month: this.month,
      destination: this.destination || null
    };
    try {
      const forecast = await getForecast({ request: JSON.stringify(request) });
      if (seq === this.forecastSeq) {
        this.forecast = forecast;
        // A destination absent from this month is no longer an option: show every account.
        if (
          this.destination &&
          !(forecast.destinations || []).some((d) => d.key === this.destination)
        ) {
          this.destination = "";
          this.loadForecast();
        }
      }
    } catch (e) {
      if (seq === this.forecastSeq) {
        this.showError(e);
      }
    } finally {
      if (seq === this.forecastSeq) {
        this.forecastLoading = false;
      }
    }
  }

  showError(e) {
    this.message = parseFailure(e);
    this.messageIsError = true;
  }

  showSuccess(text) {
    this.message = text;
    this.messageIsError = false;
  }

  focusMessage() {
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    window.requestAnimationFrame(() => {
      const el = this.template.querySelector("[data-message]");
      if (el) {
        el.focus();
      }
    });
  }

  // ------------------------------------------------------------ form

  handleFormField(event) {
    const field = event.target.dataset.field;
    this.form = { ...this.form, [field]: event.detail.value };
  }

  async handleSave() {
    const computed = this.computed;
    const inputs = [...this.template.querySelectorAll("[data-form]")];
    const valid = inputs.reduce((ok, input) => {
      if (input.setCustomValidity) {
        input.setCustomValidity(
          computed.field === input.dataset.field ? computed.error : ""
        );
      }
      input.reportValidity();
      return input.checkValidity() && ok;
    }, true);
    if (!valid || computed.hours === undefined || this.saving) {
      return;
    }
    this.saving = true;
    try {
      const result = await saveEntry({
        request: JSON.stringify({
          workRecordId: this.editingId || null,
          contractId: this.form.contractId,
          workDate: this.form.workDate,
          startTime: clock(this.form.startTime),
          breakStart: clock(this.form.breakStart),
          breakEnd: clock(this.form.breakEnd),
          endTime: clock(this.form.endTime),
          note: this.form.note ? this.form.note.trim() : null
        })
      });
      this.form = {
        ...emptyForm(this.form.contractId),
        workDate: this.form.workDate
      };
      this.editingId = undefined;
      this.showSuccess(
        result && result.created ? labels.saved : labels.updated
      );
      this.loadEntries();
      this.loadForecast();
    } catch (e) {
      this.showError(e);
    } finally {
      this.saving = false;
      this.focusMessage();
    }
  }

  /** Loads a DRAFT/REJECTED entry of this screen into the form; saving corrects it. */
  handleEdit(event) {
    const row = this.list.entries.find(
      (e) => e.workRecordId === event.currentTarget.dataset.id
    );
    if (!row) {
      return;
    }
    const [first, second] = row.times.split(" | ");
    const [startTime, firstEnd] = first.split("-");
    const [breakEnd, endTime] = second ? second.split("-") : [null, firstEnd];
    this.editingId = row.workRecordId;
    this.form = {
      workDate: row.workDate,
      contractId: row.contractId,
      startTime,
      breakStart: second ? firstEnd : null,
      breakEnd,
      endTime,
      note: row.note || ""
    };
    this.message = undefined;
  }

  handleCancelEdit() {
    this.editingId = undefined;
    this.form = emptyForm(this.form.contractId);
  }

  // ------------------------------------------------------------ entries

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
    this.loadEntries();
    this.loadForecast();
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

  /** Cross-field rules the server also enforces; an invalid set never leaves the client. */
  filterErrors() {
    const f = this.draftFilters;
    const errors = {};
    if (Boolean(f.fromDate) !== Boolean(f.toDate)) {
      errors[f.fromDate ? "toDate" : "fromDate"] =
        labels.filterPeriodIncomplete;
    } else if (f.fromDate && f.toDate) {
      const days = Math.round(
        (parseIsoDate(f.toDate) - parseIsoDate(f.fromDate)) / 86400000
      );
      if (days < 0) {
        errors.toDate = labels.filterPeriodOrder;
      } else if (days >= 366) {
        errors.toDate = labels.filterPeriodTooLong;
      }
    }
    return errors;
  }

  handleApplyFilters() {
    const errors = this.filterErrors();
    const inputs = [
      ...this.template.querySelectorAll("lightning-input[data-filter]")
    ];
    const valid = inputs.reduce((ok, input) => {
      input.setCustomValidity(errors[input.dataset.field] || "");
      input.reportValidity();
      return input.checkValidity() && ok;
    }, true);
    if (!valid) {
      return;
    }
    const monthChanged = this.applyPeriodMonth(this.draftFilters.fromDate);
    this.filters = { ...this.draftFilters };
    this.message = undefined;
    this.loadEntries();
    if (monthChanged) {
      this.loadForecast();
    }
  }

  /** A custom period moves the forecast to the month where it starts. */
  applyPeriodMonth(fromDate) {
    const from = parseIsoDate(fromDate);
    if (
      !from ||
      (from.getFullYear() === this.year && from.getMonth() + 1 === this.month)
    ) {
      return false;
    }
    this.year = from.getFullYear();
    this.month = from.getMonth() + 1;
    return true;
  }

  handleClearFilters() {
    this.template
      .querySelectorAll("lightning-input[data-filter]")
      .forEach((input) => {
        input.setCustomValidity("");
        input.reportValidity();
      });
    this.filters = { ...EMPTY_FILTERS };
    this.draftFilters = { ...EMPTY_FILTERS };
    this.loadEntries();
  }

  async handleSubmit(event) {
    const id = event.currentTarget.dataset.id;
    if (this.busyId) {
      return;
    }
    this.busyId = id;
    try {
      await submitEntry({ request: JSON.stringify({ workRecordId: id }) });
      this.showSuccess(labels.submitted);
    } catch (e) {
      this.showError(e);
    } finally {
      this.busyId = undefined;
    }
    // Success or refusal: reload so every row shows its current state.
    this.loadEntries();
    this.loadForecast();
    this.focusMessage();
  }

  // ------------------------------------------------------------ forecast

  handleDestinationChange(event) {
    this.destination = event.detail.value;
    this.loadForecast();
  }
}
