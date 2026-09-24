import { LightningElement, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import LOCALE from "@salesforce/i18n/locale";
import getContext from "@salesforce/apex/AXF_CLS_CTRL_BankStatement.getContext";
import listAccounts from "@salesforce/apex/AXF_CLS_CTRL_BankStatement.listAccounts";
import getStatement from "@salesforce/apex/AXF_CLS_CTRL_BankStatement.getStatement";
import listSuggestions from "@salesforce/apex/AXF_CLS_CTRL_BankStatement.listSuggestions";
import confirmSuggestion from "@salesforce/apex/AXF_CLS_CTRL_BankStatement.confirmSuggestion";
import updateBalance from "@salesforce/apex/AXF_CLS_CTRL_BankStatement.updateBalance";
import refreshBalance from "@salesforce/apex/AXF_CLS_CTRL_BankStatement.refreshBalance";
import labels from "./labels";
import { parseFailure, format, newOperationKey } from "./failures";

const EMPTY_FILTERS = {
  fromDate: null,
  toDate: null,
  minAmount: null,
  maxAmount: null,
  term: ""
};

function parseIsoDate(value) {
  if (!value) {
    return null;
  }
  const [y, m, d] = String(value).split("-").map(Number);
  return new Date(y, m - 1, d);
}

export default class AxfLwcBankStatement extends NavigationMixin(
  LightningElement
) {
  labels = labels;
  context;
  loading = true;
  error;
  message;
  messageIsError = false;
  accounts = [];
  selectedId;
  statement;
  statementLoading = false;
  year;
  month;
  draftFilters = { ...EMPTY_FILTERS };
  filters = { ...EMPTY_FILTERS };
  expanded = {};
  suggestions = {};
  busyKey;
  editingId;
  balanceDraft;
  statementSeq = 0;

  @wire(getContext)
  wiredContext({ data, error }) {
    if (data) {
      this.context = data;
      if (data.canUse) {
        this.loadAccounts();
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
  get hasAccounts() {
    return this.accounts.length > 0;
  }
  get showNoAccounts() {
    return !this.loading && this.context?.canUse && !this.hasAccounts;
  }
  get messageClass() {
    return this.messageIsError
      ? "slds-notify slds-notify_alert slds-alert_error slds-var-m-bottom_small"
      : "slds-notify slds-notify_alert slds-alert_success slds-var-m-bottom_small";
  }

  accountName(account) {
    if (!account) {
      return "";
    }
    const base = account.wallet ? labels.wallet : account.institutionName || "";
    return [base, account.numberMasked].filter(Boolean).join(" ");
  }

  get accountRows() {
    return this.accounts.map((a) => {
      const name = this.accountName(a);
      const selected = a.bankAccountId === this.selectedId;
      const editing = a.bankAccountId === this.editingId;
      return {
        ...a,
        key: a.bankAccountId,
        name,
        hasBalance: a.currentBalance !== null && a.currentBalance !== undefined,
        selected,
        rowClass: selected ? "slds-is-selected" : "",
        editing,
        showEdit: a.canEditBalance && !editing,
        viewLabel: format(labels.viewStatementFor, name),
        refreshLabel: format(labels.refreshFor, name),
        editLabel: format(labels.editBalanceFor, name),
        busy: this.busyKey === a.bankAccountId
      };
    });
  }

  get selectedAccount() {
    return this.accounts.find((a) => a.bankAccountId === this.selectedId);
  }

  get periodLabel() {
    if (!this.statement) {
      return "";
    }
    if (this.statement.customPeriod) {
      return format(
        labels.customPeriod,
        this.formatDate(this.statement.fromDate),
        this.formatDate(this.statement.toDate)
      );
    }
    return new Intl.DateTimeFormat(LOCALE, {
      month: "long",
      year: "numeric"
    }).format(new Date(this.statement.year, this.statement.month - 1, 1));
  }

  get statementCaption() {
    return format(
      labels.statementCaption,
      this.accountName(this.selectedAccount),
      this.periodLabel
    );
  }

  get hasLines() {
    return Boolean(this.statement) && this.statement.lines.length > 0;
  }

  get showNoLines() {
    return Boolean(this.statement) && !this.statementLoading && !this.hasLines;
  }

  get lineRows() {
    if (!this.statement) {
      return [];
    }
    return this.statement.lines.map((line) => {
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
        signedAmount:
          line.amount === null || line.amount === undefined
            ? null
            : line.direction === "DEBIT"
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
        canSuggest: line.canSuggest && this.statement.canReconcile !== false,
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

  async loadAccounts() {
    this.loading = true;
    try {
      this.accounts = (await listAccounts()) || [];
      if (
        this.selectedId &&
        !this.accounts.some((a) => a.bankAccountId === this.selectedId)
      ) {
        this.selectedId = undefined;
        this.statement = undefined;
      }
    } catch (e) {
      this.showError(e);
      this.accounts = [];
    } finally {
      this.loading = false;
    }
  }

  async loadStatement() {
    if (!this.selectedId) {
      return;
    }
    this.statementLoading = true;
    this.expanded = {};
    this.suggestions = {};
    // Only the newest request may paint: a late answer to an older one is ignored.
    const seq = ++this.statementSeq;
    const request = {
      bankAccountId: this.selectedId,
      year: this.year,
      month: this.month,
      fromDate: this.filters.fromDate || null,
      toDate: this.filters.toDate || null,
      minAmount: this.numberOrNull(this.filters.minAmount),
      maxAmount: this.numberOrNull(this.filters.maxAmount),
      term: this.filters.term ? this.filters.term : null
    };
    try {
      const statement = await getStatement({
        request: JSON.stringify(request)
      });
      if (seq !== this.statementSeq) {
        return;
      }
      this.statement = statement;
      this.year = statement.year;
      this.month = statement.month;
    } catch (e) {
      if (seq === this.statementSeq) {
        this.showError(e);
      }
    } finally {
      if (seq === this.statementSeq) {
        this.statementLoading = false;
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
    const id = event.currentTarget.dataset.id;
    this.selectedId = id;
    this.message = undefined;
    const now = new Date();
    this.year = now.getFullYear();
    this.month = now.getMonth() + 1;
    this.filters = { ...EMPTY_FILTERS };
    this.draftFilters = { ...EMPTY_FILTERS };
    this.loadStatement();
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
    // Month paging leaves any custom period; the other filters stay applied.
    this.filters = { ...this.filters, fromDate: null, toDate: null };
    this.draftFilters = { ...this.draftFilters, fromDate: null, toDate: null };
    this.loadStatement();
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
    this.loadStatement();
  }

  handleClearFilters() {
    this.filters = { ...EMPTY_FILTERS };
    this.draftFilters = { ...EMPTY_FILTERS };
    this.loadStatement();
  }

  async handleToggleSuggestions(event) {
    const id = event.currentTarget.dataset.id;
    const line = this.statement.lines.find((l) => l.recordId === id);
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
          bankAccountId: this.selectedId,
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
          bankAccountId: this.selectedId,
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
    // Success or refusal: the statement is reloaded so every line shows its current state.
    await this.loadStatement();
    this.focusMessage();
  }

  handleEditBalance(event) {
    const id = event.currentTarget.dataset.id;
    const account = this.accounts.find((a) => a.bankAccountId === id);
    this.editingId = id;
    this.balanceDraft = account ? account.currentBalance : null;
  }

  handleBalanceChange(event) {
    this.balanceDraft = event.detail.value;
  }

  handleCancelBalance() {
    this.editingId = undefined;
    this.balanceDraft = undefined;
  }

  async handleSaveBalance(event) {
    const id = event.currentTarget.dataset.id;
    const account = this.accounts.find((a) => a.bankAccountId === id);
    const input = this.template.querySelector(
      `lightning-input[data-balance="${id}"]`
    );
    if (input && !input.reportValidity()) {
      return;
    }
    const balance = this.numberOrNull(this.balanceDraft);
    if (!account || balance === null) {
      return;
    }
    this.busyKey = id;
    try {
      const updated = await updateBalance({
        request: JSON.stringify({
          bankAccountId: id,
          balance,
          expectedVersion: account.version
        })
      });
      this.replaceAccount(updated);
      this.editingId = undefined;
      this.showSuccess(labels.balanceSaved);
    } catch (e) {
      this.showError(e);
      await this.loadAccounts();
    } finally {
      this.busyKey = undefined;
      this.focusMessage();
    }
  }

  async handleRefresh(event) {
    const id = event.currentTarget.dataset.id;
    this.busyKey = id;
    try {
      const result = await refreshBalance({
        request: JSON.stringify({ bankAccountId: id })
      });
      if (result.account) {
        this.replaceAccount(result.account);
      }
      if (result.state === "RUNNING") {
        this.showSuccess(labels.refreshRunning);
      } else if (result.complete) {
        this.showSuccess(labels.refreshDone);
      } else {
        this.showSuccess(labels.refreshPending);
      }
    } catch (e) {
      this.showError(e);
    } finally {
      this.busyKey = undefined;
      this.focusMessage();
    }
  }

  replaceAccount(updated) {
    if (!updated) {
      return;
    }
    this.accounts = this.accounts.map((a) => {
      return a.bankAccountId === updated.bankAccountId ? updated : a;
    });
  }

  handleNewEntry() {
    const account = this.selectedAccount;
    if (!account) {
      return;
    }
    this[NavigationMixin.Navigate]({
      type: "standard__navItemPage",
      attributes: { apiName: "AXF_EntryWizard" },
      state: {
        c__bankAccountId: account.bankAccountId,
        c__accountId: account.holderId
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
