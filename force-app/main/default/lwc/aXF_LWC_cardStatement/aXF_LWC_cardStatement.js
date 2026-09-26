import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import LOCALE from "@salesforce/i18n/locale";
import getContext from "@salesforce/apex/AXF_CLS_CTRL_CardStatement.getContext";
import listCards from "@salesforce/apex/AXF_CLS_CTRL_CardStatement.listCards";
import getInvoice from "@salesforce/apex/AXF_CLS_CTRL_CardStatement.getInvoice";
import listSuggestions from "@salesforce/apex/AXF_CLS_CTRL_CardStatement.listSuggestions";
import confirmSuggestion from "@salesforce/apex/AXF_CLS_CTRL_CardStatement.confirmSuggestion";
import defineClosing from "@salesforce/apex/AXF_CLS_CTRL_CardStatement.defineClosing";
import labels from "./labels";
import { parseFailure, format, newOperationKey } from "./failures";

const EMPTY_FILTERS = {
  fromDate: null,
  toDate: null,
  minAmount: null,
  maxAmount: null,
  term: ""
};
const EMPTY_CLOSING = { closingDay: null, dueDay: null };

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

export default class AxfLwcCardStatement extends NavigationMixin(
  LightningElement
) {
  // Record page: scoped to the record being viewed.
  @api recordId;
  labels = labels;
  context;
  loading = true;
  error;
  message;
  messageIsError = false;
  cards = [];
  selectedId;
  invoice;
  invoiceLoading = false;
  year;
  month;
  draftFilters = { ...EMPTY_FILTERS };
  filters = { ...EMPTY_FILTERS };
  expanded = {};
  suggestions = {};
  busyKey;
  closingId;
  closingDraft = { ...EMPTY_CLOSING };
  invoiceSeq = 0;

  @wire(getContext)
  wiredContext({ data, error }) {
    if (data) {
      this.context = data;
      if (data.canUse) {
        this.loadCards();
      } else {
        this.loading = false;
      }
    } else if (error) {
      this.error = parseFailure(error);
      this.loading = false;
    }
  }

  // ------------------------------------------------------------ getters

  get noCapability() {
    return Boolean(this.context) && !this.context.canUse;
  }
  get hasCards() {
    return this.cards.length > 0;
  }
  get showNoCards() {
    return !this.loading && this.context?.canUse && !this.hasCards;
  }
  get messageClass() {
    return this.messageIsError
      ? "slds-notify slds-notify_alert slds-alert_error slds-var-m-bottom_small"
      : "slds-notify slds-notify_alert slds-alert_success slds-var-m-bottom_small";
  }

  cardName(card) {
    if (!card) {
      return "";
    }
    return [card.institutionName, card.brand, card.lastFour]
      .filter(Boolean)
      .join(" ");
  }

  get cardRows() {
    return this.cards.map((c) => {
      const name = this.cardName(c);
      const selected = c.creditCardId === this.selectedId;
      const editing = c.creditCardId === this.closingId;
      return {
        ...c,
        key: c.creditCardId,
        name,
        hasCreditLimit: hasValue(c.creditLimit),
        hasAvailableLimit: hasValue(c.availableLimit),
        closingText: hasValue(c.closingDay)
          ? String(c.closingDay)
          : labels.notAvailable,
        dueText: hasValue(c.dueDay) ? String(c.dueDay) : labels.notAvailable,
        selected,
        rowClass: selected ? "slds-is-selected" : "",
        editing,
        showDefine: c.canDefineClosing && !editing,
        viewLabel: format(labels.viewInvoiceFor, name),
        defineLabel: format(labels.defineClosingFor, name),
        busy: this.busyKey === c.creditCardId
      };
    });
  }

  get selectedCard() {
    return this.cards.find((c) => c.creditCardId === this.selectedId);
  }

  get periodLabel() {
    if (!this.invoice) {
      return "";
    }
    if (this.invoice.customPeriod) {
      return format(
        labels.customPeriod,
        this.formatDate(this.invoice.fromDate),
        this.formatDate(this.invoice.toDate)
      );
    }
    return new Intl.DateTimeFormat(LOCALE, {
      month: "long",
      year: "numeric"
    }).format(new Date(this.invoice.year, this.invoice.month - 1, 1));
  }

  get invoiceCaption() {
    return format(
      labels.invoiceCaption,
      this.cardName(this.selectedCard),
      this.periodLabel
    );
  }

  get isBlocked() {
    return Boolean(this.invoice) && this.invoice.outcome === "BLOCKED";
  }

  get isResolved() {
    return Boolean(this.invoice) && this.invoice.outcome === "RESOLVED";
  }

  get windowText() {
    if (!this.invoice || this.invoice.customPeriod) {
      return "";
    }
    return format(
      labels.invoiceWindow,
      this.formatDate(this.invoice.fromDate),
      this.formatDate(this.invoice.toDate)
    );
  }

  get closingText() {
    return this.isResolved
      ? format(labels.closingDate, this.formatDate(this.invoice.closingDate))
      : "";
  }

  get dueText() {
    return this.isResolved
      ? format(labels.dueDate, this.formatDate(this.invoice.dueDate))
      : "";
  }

  get invoiceCurrency() {
    return (
      (this.invoice && this.invoice.currencyIso) ||
      (this.selectedCard && this.selectedCard.currencyIso) ||
      "BRL"
    );
  }

  get hasPlanned() {
    return Boolean(this.invoice) && Number(this.invoice.plannedTotal) !== 0;
  }

  get hasLines() {
    return Boolean(this.invoice) && this.invoice.lines.length > 0;
  }

  get showNoLines() {
    return Boolean(this.invoice) && !this.invoiceLoading && !this.hasLines;
  }

  get lineRows() {
    if (!this.invoice) {
      return [];
    }
    return this.invoice.lines.map((line) => {
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
        // On a card a purchase (DEBIT) raises the invoice; a refund (CREDIT) lowers it.
        signedAmount: !hasValue(line.amount)
          ? null
          : line.direction === "CREDIT"
            ? -line.amount
            : line.amount,
        originLabel: labels[`origin${line.origin}`] || line.origin || "",
        statusLabel: labels[`status${line.status}`] || line.status,
        statusClass:
          line.status === "RECONCILED"
            ? "slds-badge slds-theme_success"
            : line.status === "PARTIAL"
              ? "slds-badge slds-theme_warning"
              : "slds-badge",
        canSuggest: line.canSuggest && this.invoice.canReconcile !== false,
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

  async loadCards() {
    this.loading = true;
    try {
      this.cards = (await listCards()) || [];
      if (this.recordId) {
        this.cards = this.cards.filter((r) => r.creditCardId === this.recordId);
        if (this.cards.length && this.selectedId !== this.recordId) {
          this.selectRecord(this.recordId);
        }
      }
      if (
        this.selectedId &&
        !this.cards.some((c) => c.creditCardId === this.selectedId)
      ) {
        this.selectedId = undefined;
        this.invoice = undefined;
      }
    } catch (e) {
      this.showError(e);
      this.cards = [];
    } finally {
      this.loading = false;
    }
  }

  async loadInvoice() {
    if (!this.selectedId) {
      return;
    }
    this.invoiceLoading = true;
    this.expanded = {};
    this.suggestions = {};
    // Only the newest request may paint: a late answer to an older one is ignored.
    const seq = ++this.invoiceSeq;
    const request = {
      creditCardId: this.selectedId,
      year: this.year,
      month: this.month,
      fromDate: this.filters.fromDate || null,
      toDate: this.filters.toDate || null,
      minAmount: this.numberOrNull(this.filters.minAmount),
      maxAmount: this.numberOrNull(this.filters.maxAmount),
      term: this.filters.term ? this.filters.term : null
    };
    try {
      const invoice = await getInvoice({ request: JSON.stringify(request) });
      if (seq !== this.invoiceSeq) {
        return;
      }
      this.invoice = invoice;
      this.year = invoice.year;
      this.month = invoice.month;
    } catch (e) {
      if (seq === this.invoiceSeq) {
        // Never leave another card's or month's invoice under the new selection.
        this.invoice = undefined;
        this.showError(e);
      }
    } finally {
      if (seq === this.invoiceSeq) {
        this.invoiceLoading = false;
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

  handleSelect(event) {
    this.selectRecord(event.currentTarget.dataset.id);
  }

  selectRecord(id) {
    this.selectedId = id;
    this.message = undefined;
    const now = new Date();
    this.year = now.getFullYear();
    this.month = now.getMonth() + 1;
    this.filters = { ...EMPTY_FILTERS };
    this.draftFilters = { ...EMPTY_FILTERS };
    this.loadInvoice();
  }

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
    // Invoice paging leaves any custom period; the other filters stay applied.
    this.filters = { ...this.filters, fromDate: null, toDate: null };
    this.draftFilters = { ...this.draftFilters, fromDate: null, toDate: null };
    this.loadInvoice();
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
    this.loadInvoice();
  }

  handleClearFilters() {
    this.filters = { ...EMPTY_FILTERS };
    this.draftFilters = { ...EMPTY_FILTERS };
    this.loadInvoice();
  }

  async handleToggleSuggestions(event) {
    const id = event.currentTarget.dataset.id;
    const line = this.invoice.lines.find((l) => l.recordId === id);
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
          creditCardId: this.selectedId,
          lineKind: line.lineKind,
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
    const state = this.suggestions[lineId];
    const suggestion = state && state.items && state.items[index];
    if (!suggestion || this.busyKey) {
      return;
    }
    this.busyKey = `${lineId}-${suggestion.candidateId}`;
    try {
      await confirmSuggestion({
        request: JSON.stringify({
          creditCardId: this.selectedId,
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
    // Success or refusal: the invoice is reloaded so every line shows its current state.
    await this.loadInvoice();
    this.focusMessage();
  }

  handleDefineClosing(event) {
    this.closingId = event.currentTarget.dataset.id;
    this.closingDraft = { ...EMPTY_CLOSING };
  }

  handleClosingChange(event) {
    const field = event.target.dataset.closing;
    this.closingDraft = { ...this.closingDraft, [field]: event.detail.value };
  }

  handleCancelClosing() {
    this.closingId = undefined;
    this.closingDraft = { ...EMPTY_CLOSING };
  }

  async handleSaveClosing(event) {
    const id = event.currentTarget.dataset.id;
    const inputs = [
      ...this.template.querySelectorAll(`lightning-input[data-card="${id}"]`)
    ];
    const valid = inputs.reduce((ok, input) => {
      const day = this.numberOrNull(this.closingDraft[input.dataset.closing]);
      const inRange = day !== null && Number.isInteger(day) && day >= 1;
      input.setCustomValidity(inRange && day <= 31 ? "" : labels.dayRange);
      input.reportValidity();
      return input.checkValidity() && ok;
    }, true);
    if (!valid) {
      return;
    }
    this.busyKey = id;
    try {
      const updated = await defineClosing({
        request: JSON.stringify({
          creditCardId: id,
          closingDay: this.numberOrNull(this.closingDraft.closingDay),
          dueDay: this.numberOrNull(this.closingDraft.dueDay)
        })
      });
      this.replaceCard(updated);
      this.closingId = undefined;
      this.closingDraft = { ...EMPTY_CLOSING };
      this.showSuccess(labels.closingSaved);
      if (id === this.selectedId) {
        await this.loadInvoice();
      }
    } catch (e) {
      this.showError(e);
      await this.loadCards();
    } finally {
      this.busyKey = undefined;
      this.focusMessage();
    }
  }

  replaceCard(updated) {
    if (!updated) {
      return;
    }
    this.cards = this.cards.map((c) => {
      return c.creditCardId === updated.creditCardId ? updated : c;
    });
  }

  handleNewExpense() {
    const card = this.selectedCard;
    if (!card) {
      return;
    }
    this[NavigationMixin.Navigate]({
      type: "standard__navItemPage",
      attributes: { apiName: "AXF_EntryWizard" },
      state: {
        c__creditCardId: card.creditCardId,
        c__accountId: card.holderId
      }
    });
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
