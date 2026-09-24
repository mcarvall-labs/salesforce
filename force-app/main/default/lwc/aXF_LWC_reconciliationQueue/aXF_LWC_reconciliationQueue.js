import { LightningElement, wire } from "lwc";
import LOCALE from "@salesforce/i18n/locale";
import getContext from "@salesforce/apex/AXF_CLS_CTRL_ReconciliationQueue.getContext";
import listSources from "@salesforce/apex/AXF_CLS_CTRL_ReconciliationQueue.listSources";
import getQueue from "@salesforce/apex/AXF_CLS_CTRL_ReconciliationQueue.getQueue";
import listSuggestions from "@salesforce/apex/AXF_CLS_CTRL_ReconciliationQueue.listSuggestions";
import confirmSuggestion from "@salesforce/apex/AXF_CLS_CTRL_ReconciliationQueue.confirmSuggestion";
import labels from "./labels";
import { parseFailure, format, newOperationKey } from "./failures";

const EMPTY_FILTERS = {
  kind: "",
  fundingId: "",
  invoice: "",
  fromDate: null,
  toDate: null,
  minAmount: null,
  maxAmount: null,
  term: "",
  // The queue exists to close what is not matched yet: pending is the default view.
  status: "PENDING"
};
/** Invoice months offered around today: a year back and two months ahead. */
const INVOICE_MONTHS_BACK = 12;
const INVOICE_MONTHS_AHEAD = 2;

function parseIsoDate(value) {
  if (!value) {
    return null;
  }
  const [y, m, d] = String(value).split("-").map(Number);
  return new Date(y, m - 1, d);
}

function hasValue(value) {
  return value !== null && value !== undefined;
}

export default class AxfLwcReconciliationQueue extends LightningElement {
  labels = labels;
  context;
  error;
  message;
  messageIsError = false;
  sources = [];
  sourcesTruncated = false;
  sourcesLoaded = false;
  view;
  queueLoading = false;
  draftFilters = { ...EMPTY_FILTERS };
  filters = { ...EMPTY_FILTERS };
  expanded = {};
  suggestions = {};
  busyKey;
  showReconciled = false;
  queueSeq = 0;

  @wire(getContext)
  wiredContext({ data, error }) {
    if (data) {
      this.context = data;
      this.loadSources();
      this.loadQueue();
    } else if (error) {
      this.error = parseFailure(error);
    }
  }

  // ------------------------------------------------------------ getters

  get readOnly() {
    return Boolean(this.context) && !this.context.canReconcile;
  }

  get messageClass() {
    return this.messageIsError
      ? "slds-notify slds-notify_alert slds-alert_error slds-var-m-bottom_small"
      : "slds-notify slds-notify_alert slds-alert_success slds-var-m-bottom_small";
  }

  get showNoSources() {
    return Boolean(this.context) && this.sourcesLoaded && !this.sources.length;
  }

  get kindOptions() {
    return [
      { label: labels.kindAll, value: "" },
      { label: labels.kindBANK, value: "BANK" },
      { label: labels.kindCARD, value: "CARD" }
    ];
  }

  sourceName(source) {
    return source.holderLabel
      ? `${source.name} (${source.holderLabel})`
      : source.name;
  }

  get sourceOptions() {
    const kind = this.draftFilters.kind;
    const byHolderThenName = (a, b) =>
      (a.holderLabel || "").localeCompare(b.holderLabel || "", LOCALE) ||
      (a.name || "").localeCompare(b.name || "", LOCALE);
    return [{ label: labels.sourceAll, value: "" }].concat(
      this.sources
        .filter((s) => !kind || s.kind === kind)
        .sort(byHolderThenName)
        .map((s) => ({ label: this.sourceName(s), value: s.fundingId }))
    );
  }

  get draftSource() {
    return this.sources.find(
      (s) => s.fundingId === this.draftFilters.fundingId
    );
  }

  get invoiceDisabled() {
    const source = this.draftSource;
    return !source || source.kind !== "CARD";
  }

  get invoiceHelp() {
    return this.invoiceDisabled ? labels.invoiceNeedsCard : "";
  }

  get invoiceOptions() {
    const now = new Date();
    const options = [{ label: labels.invoiceNone, value: "" }];
    const formatter = new Intl.DateTimeFormat(LOCALE, {
      month: "long",
      year: "numeric"
    });
    for (
      let shift = INVOICE_MONTHS_AHEAD;
      shift >= -INVOICE_MONTHS_BACK;
      shift--
    ) {
      const month = new Date(now.getFullYear(), now.getMonth() + shift, 1);
      const value = `${month.getFullYear()}-${String(month.getMonth() + 1).padStart(2, "0")}`;
      options.push({ label: formatter.format(month), value });
    }
    return options;
  }

  get statusOptions() {
    return [
      { label: labels.statusAll, value: "ALL" },
      { label: labels.statusPENDING, value: "PENDING" },
      { label: labels.statusUNRECONCILED, value: "UNRECONCILED" },
      { label: labels.statusPARTIAL, value: "PARTIAL" },
      { label: labels.statusRECONCILED, value: "RECONCILED" },
      { label: labels.statusUNVERIFIED, value: "UNVERIFIED" }
    ];
  }

  get counters() {
    if (!this.view) {
      return [];
    }
    return [
      ["UNRECONCILED", this.view.countUnreconciled],
      ["PARTIAL", this.view.countPartial],
      ["RECONCILED", this.view.countReconciled],
      ["UNVERIFIED", this.view.countUnverified]
    ].map(([status, count]) => ({
      key: status,
      label: labels[`status${status}`],
      count: count || 0
    }));
  }

  /** Invoice month, or the dates actually read (default window or custom period). */
  get periodText() {
    if (!this.view) {
      return "";
    }
    if (this.view.invoiceYear && !this.view.customPeriod) {
      return format(
        labels.period,
        new Intl.DateTimeFormat(LOCALE, {
          month: "long",
          year: "numeric"
        }).format(
          new Date(this.view.invoiceYear, this.view.invoiceMonth - 1, 1)
        )
      );
    }
    return format(
      labels.period,
      format(
        labels.customPeriod,
        this.formatDate(this.view.fromDate),
        this.formatDate(this.view.toDate)
      )
    );
  }

  get isBlocked() {
    return Boolean(this.view) && this.view.invoiceOutcome === "BLOCKED";
  }

  get isResolved() {
    return Boolean(this.view) && this.view.invoiceOutcome === "RESOLVED";
  }

  get windowText() {
    return this.isResolved
      ? format(
          labels.invoiceWindow,
          this.formatDate(this.view.invoiceFromDate),
          this.formatDate(this.view.invoiceToDate)
        )
      : "";
  }

  get closingText() {
    return this.isResolved
      ? format(labels.closingDate, this.formatDate(this.view.closingDate))
      : "";
  }

  get dueText() {
    return this.isResolved
      ? format(labels.dueDate, this.formatDate(this.view.dueDate))
      : "";
  }

  /** Pending first, then lines that cannot be verified, then the reconciled ones (collapsible). */
  get sections() {
    if (!this.view) {
      return [];
    }
    const pending = this.rows(this.view.pending);
    const unverified = this.rows(this.view.unverified);
    const reconciled = this.rows(this.view.reconciled);
    const result = [
      {
        key: "pending",
        heading: labels.pendingHeading,
        rows: pending,
        showTable: pending.length > 0,
        empty: !this.queueLoading && pending.length === 0,
        emptyText: labels.noPending,
        collapsible: false
      }
    ];
    if (unverified.length) {
      result.push({
        key: "unverified",
        heading: labels.statusUNVERIFIED,
        rows: unverified,
        showTable: true,
        empty: false,
        collapsible: false
      });
    }
    if (reconciled.length) {
      result.push({
        key: "reconciled",
        heading: labels.statusRECONCILED,
        rows: reconciled,
        showTable: this.showReconciled,
        empty: false,
        collapsible: true,
        toggleLabel: this.showReconciled
          ? labels.hideReconciled
          : format(labels.showReconciled, reconciled.length),
        ariaExpanded: this.showReconciled ? "true" : "false"
      });
    }
    return result.map((section) => ({
      ...section,
      headingId: `axf154-${section.key}-heading`,
      tableId: `axf154-${section.key}-table`
    }));
  }

  allLines() {
    if (!this.view) {
      return [];
    }
    return [
      ...this.view.pending,
      ...this.view.unverified,
      ...this.view.reconciled
    ];
  }

  rows(lines) {
    const canReconcile = Boolean(this.view && this.view.canReconcile);
    return lines.map((line) => {
      const expanded = Boolean(this.expanded[line.recordId]);
      const state = this.suggestions[line.recordId] || {};
      const items = (state.items || []).map((s, index) => ({
        ...s,
        key: `${line.recordId}-${s.candidateId}`,
        index,
        text: format(
          labels.suggestionAction,
          s.description || "",
          this.formatMoney(s.candidateAmount, s.currencyIso),
          this.formatDate(s.candidateDate)
        ),
        busy: this.busyKey === `${line.recordId}-${s.candidateId}`
      }));
      return {
        ...line,
        key: line.recordId,
        subKey: `${line.recordId}-suggestions`,
        dateText: this.formatDate(line.lineDate),
        kindLabel: labels[`kind${line.kind}`] || line.kind,
        // Money flow across accounts and cards: an outflow (DEBIT) is negative.
        signedAmount: !hasValue(line.amount)
          ? null
          : line.direction === "DEBIT"
            ? -line.amount
            : line.amount,
        statusLabel: labels[`status${line.status}`] || line.status,
        statusClass:
          line.status === "RECONCILED"
            ? "slds-badge slds-theme_success"
            : line.status === "PARTIAL"
              ? "slds-badge slds-theme_warning"
              : "slds-badge",
        canSuggest: Boolean(line.canSuggest) && canReconcile,
        expanded,
        ariaExpanded: expanded ? "true" : "false",
        toggleLabel: format(labels.showSuggestionsFor, line.description || ""),
        suggestionsId: `sugg-${line.recordId}`,
        suggestionsLoading: Boolean(state.loading),
        suggestionItems: items,
        noSuggestions: !state.loading && state.items && items.length === 0,
        suggestionsTruncated: Boolean(state.truncated)
      };
    });
  }

  formatDate(value) {
    const date = parseIsoDate(value);
    return date ? new Intl.DateTimeFormat(LOCALE).format(date) : "";
  }

  formatMoney(value, iso) {
    if (!hasValue(value)) {
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

  async loadSources() {
    try {
      const result = await listSources();
      this.sources = (result && result.items) || [];
      this.sourcesTruncated = Boolean(result && result.truncated);
    } catch (e) {
      this.sources = [];
      this.showError(e);
    } finally {
      this.sourcesLoaded = true;
    }
  }

  buildRequest() {
    const f = this.filters;
    const [year, month] = f.invoice ? f.invoice.split("-").map(Number) : [];
    return {
      kind: f.kind || null,
      fundingId: f.fundingId || null,
      invoiceYear: f.invoice ? year : null,
      invoiceMonth: f.invoice ? month : null,
      fromDate: f.fromDate || null,
      toDate: f.toDate || null,
      minAmount: this.numberOrNull(f.minAmount),
      maxAmount: this.numberOrNull(f.maxAmount),
      term: f.term ? f.term : null,
      status: f.status || null
    };
  }

  async loadQueue() {
    this.queueLoading = true;
    this.expanded = {};
    this.suggestions = {};
    // Only the newest request may paint: a late answer to an older one is ignored.
    const seq = ++this.queueSeq;
    try {
      const view = await getQueue({
        request: JSON.stringify(this.buildRequest())
      });
      if (seq !== this.queueSeq) {
        return;
      }
      this.view = view;
    } catch (e) {
      if (seq === this.queueSeq) {
        // Never leave the result of other filters under the new ones.
        this.view = undefined;
        this.showError(e);
      }
    } finally {
      if (seq === this.queueSeq) {
        this.queueLoading = false;
      }
    }
  }

  numberOrNull(value) {
    if (value === null || value === undefined || value === "") {
      return null;
    }
    const parsed = Number(value);
    return Number.isNaN(parsed) ? null : parsed;
  }

  showError(e) {
    this.message = parseFailure(e);
    this.messageIsError = true;
  }

  showSuccess(text) {
    this.message = text;
    this.messageIsError = false;
  }

  // ------------------------------------------------------------ handlers

  handleFilterChange(event) {
    const field = event.target.dataset.field;
    const next = { ...this.draftFilters, [field]: event.detail.value };
    if (field === "kind" && next.fundingId) {
      const source = this.sources.find((s) => s.fundingId === next.fundingId);
      if (next.kind && source && source.kind !== next.kind) {
        next.fundingId = "";
      }
    }
    const source = this.sources.find((s) => s.fundingId === next.fundingId);
    if (!source || source.kind !== "CARD") {
      // An invoice exists only for one card.
      next.invoice = "";
    }
    this.draftFilters = next;
  }

  /** Cross-field rules the server also enforces; an invalid set never leaves the client. */
  filterErrors() {
    const f = this.draftFilters;
    const errors = {};
    if (Boolean(f.fromDate) !== Boolean(f.toDate)) {
      errors[f.fromDate ? "toDate" : "fromDate"] =
        labels.filterPeriodIncomplete;
    } else if (f.fromDate && f.toDate) {
      const from = parseIsoDate(f.fromDate);
      const to = parseIsoDate(f.toDate);
      const days = Math.round((to - from) / 86400000);
      if (days < 0) {
        errors.toDate = labels.filterPeriodOrder;
      } else if (days >= 366) {
        errors.toDate = labels.filterPeriodTooLong;
      }
    }
    const min = this.numberOrNull(f.minAmount);
    const max = this.numberOrNull(f.maxAmount);
    if (min !== null && max !== null && min > max) {
      errors.maxAmount = labels.filterAmountOrder;
    }
    return errors;
  }

  handleApplyFilters() {
    const inputs = [
      ...this.template.querySelectorAll("lightning-input[data-filter]")
    ];
    const errors = this.filterErrors();
    const valid = inputs.reduce((ok, input) => {
      input.setCustomValidity(errors[input.dataset.field] || "");
      input.reportValidity();
      return input.checkValidity() && ok;
    }, true);
    if (!valid) {
      return;
    }
    this.filters = { ...this.draftFilters };
    this.message = undefined;
    this.loadQueue();
  }

  handleClearFilters() {
    this.filters = { ...EMPTY_FILTERS };
    this.draftFilters = { ...EMPTY_FILTERS };
    this.message = undefined;
    this.loadQueue();
  }

  handleToggleReconciled() {
    this.showReconciled = !this.showReconciled;
  }

  async handleToggleSuggestions(event) {
    const id = event.currentTarget.dataset.id;
    const line = this.allLines().find((l) => l.recordId === id);
    if (!line) {
      return;
    }
    const open = !this.expanded[id];
    this.expanded = { ...this.expanded, [id]: open };
    if (!open) {
      return;
    }
    this.suggestions = { ...this.suggestions, [id]: { loading: true } };
    try {
      const page = await listSuggestions({
        request: JSON.stringify({
          fundingId: line.fundingId,
          recordId: line.recordId
        })
      });
      this.suggestions = {
        ...this.suggestions,
        [id]: { loading: false, items: page.items, truncated: page.truncated }
      };
    } catch (e) {
      this.suggestions = {
        ...this.suggestions,
        [id]: { loading: false, items: [] }
      };
      this.showError(e);
    }
  }

  async handleConfirm(event) {
    const lineId = event.currentTarget.dataset.line;
    const index = Number(event.currentTarget.dataset.index);
    const line = this.allLines().find((l) => l.recordId === lineId);
    const state = this.suggestions[lineId];
    const suggestion = state && state.items && state.items[index];
    if (!line || !suggestion || this.busyKey) {
      return;
    }
    this.busyKey = `${lineId}-${suggestion.candidateId}`;
    try {
      await confirmSuggestion({
        request: JSON.stringify({
          fundingId: line.fundingId,
          sourceId: suggestion.sourceId,
          sourceVersion: suggestion.sourceVersion,
          targetId: suggestion.targetId,
          targetVersion: suggestion.targetVersion,
          operationKey: newOperationKey()
        })
      });
      this.showSuccess(labels.confirmed);
    } catch (e) {
      this.showError(e);
    } finally {
      this.busyKey = undefined;
    }
    // Success or refusal: the queue is reloaded so every line shows its current state.
    await this.loadQueue();
    this.focusMessage();
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
}
