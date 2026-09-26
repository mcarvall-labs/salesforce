import { LightningElement } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import LOCALE from "@salesforce/i18n/locale";
import getDashboard from "@salesforce/apex/AXF_CLS_CTRL_HomeDashboard.getDashboard";
import labels from "./labels";
import { parseFailure, format } from "./failures";

const ALL = "ALL";

function parseIsoDate(value) {
  const [y, m, d] = String(value).split("-").map(Number);
  return new Date(y, m - 1, d);
}

/**
 * Axon Finance home dashboard (production parity). One holder filter ("Geral" or one holder)
 * drives every panel: month balance, overdue lists, the month's expenses and income and the
 * projected balance. Everything is computed by AXF_CLS_CTRL_HomeDashboard; the UI only renders.
 */
export default class AxfLwcHomeDashboard extends NavigationMixin(
  LightningElement
) {
  labels = labels;
  data;
  error;
  loading = true;
  selectedHolder = ALL;
  expenseCategory = "";
  revenueCategory = "";
  loadSeq = 0;

  connectedCallback() {
    this.load();
  }

  async load() {
    const seq = ++this.loadSeq;
    this.loading = true;
    this.error = undefined;
    try {
      const result = await getDashboard({
        holderId: this.selectedHolder === ALL ? null : this.selectedHolder
      });
      if (seq === this.loadSeq) {
        this.data = result;
      }
    } catch (e) {
      if (seq === this.loadSeq) {
        this.error = parseFailure(e);
      }
    } finally {
      if (seq === this.loadSeq) {
        this.loading = false;
      }
    }
  }

  // ------------------------------------------------------------ getters

  get currency() {
    return (this.data && this.data.currencyIso) || "BRL";
  }

  get tabs() {
    const holders = (this.data && this.data.holders) || [];
    return [{ holderId: ALL, label: labels.filterAll }, ...holders].map((h) => {
      const selected = h.holderId === this.selectedHolder;
      return {
        key: h.holderId,
        label: h.label,
        itemClass: selected
          ? "slds-tabs_default__item slds-is-active"
          : "slds-tabs_default__item",
        ariaSelected: selected ? "true" : "false",
        tabIndex: selected ? "0" : "-1"
      };
    });
  }

  get monthLabel() {
    if (!this.data || !this.data.monthStart) {
      return "";
    }
    const text = new Intl.DateTimeFormat(LOCALE, {
      month: "long",
      year: "numeric"
    }).format(parseIsoDate(this.data.monthStart));
    return text.charAt(0).toUpperCase() + text.slice(1);
  }

  get plannedBoxClass() {
    return this.boxClass(this.data && this.data.plannedBalance);
  }

  get realizedBoxClass() {
    return this.boxClass(this.data && this.data.realizedBalance);
  }

  boxClass(value) {
    return value < 0
      ? "kpi-box kpi-box-negative slds-p-around_medium"
      : "kpi-box kpi-box-positive slds-p-around_medium";
  }

  get overdueExpensesTitle() {
    return format(labels.overdueExpenses, this.overdueExpenseRows.length);
  }

  get overdueRevenuesTitle() {
    return format(labels.overdueRevenues, this.overdueRevenueRows.length);
  }

  get overdueExpensesTotal() {
    return format(
      labels.overdueExpensesTotal,
      this.formatMoney(this.data && this.data.overdueExpenseTotal)
    );
  }

  get overdueRevenuesTotal() {
    return format(
      labels.overdueRevenuesTotal,
      this.formatMoney(this.data && this.data.overdueRevenueTotal)
    );
  }

  get overdueExpenseRows() {
    return this.rows(this.data && this.data.overdueExpenses, "");
  }

  get overdueRevenueRows() {
    return this.rows(this.data && this.data.overdueRevenues, "");
  }

  get monthExpenseRows() {
    return this.rows(
      this.data && this.data.monthExpenses,
      this.expenseCategory
    );
  }

  get monthRevenueRows() {
    return this.rows(
      this.data && this.data.monthRevenues,
      this.revenueCategory
    );
  }

  get hasOverdueExpenses() {
    return this.overdueExpenseRows.length > 0;
  }

  get hasOverdueRevenues() {
    return this.overdueRevenueRows.length > 0;
  }

  get hasMonthExpenses() {
    return this.monthExpenseRows.length > 0;
  }

  get hasMonthRevenues() {
    return this.monthRevenueRows.length > 0;
  }

  get overdueExpenseBadgeClass() {
    return this.hasOverdueExpenses
      ? "slds-icon_container slds-icon_container_circle alert-badge alert-badge-danger"
      : "slds-icon_container slds-icon_container_circle alert-badge alert-badge-success";
  }

  get overdueRevenueBadgeClass() {
    return this.hasOverdueRevenues
      ? "slds-icon_container slds-icon_container_circle alert-badge alert-badge-warning"
      : "slds-icon_container slds-icon_container_circle alert-badge alert-badge-success";
  }

  get accountRows() {
    return ((this.data && this.data.accounts) || []).map((a) => ({
      ...a,
      key: a.bankAccountId,
      openLabel: format(labels.openAccount, a.name)
    }));
  }

  get hasAccounts() {
    return this.accountRows.length > 0;
  }

  rows(list, categoryTerm) {
    const term = (categoryTerm || "").trim().toLowerCase();
    return (list || [])
      .filter((e) => !term || (e.category || "").toLowerCase().includes(term))
      .map((e) => ({
        ...e,
        key: e.recordId,
        dateLabel: this.formatDate(e.entryDate),
        amountLabel: this.formatMoney(e.amount, e.currencyIso),
        residualLabel: this.formatMoney(e.residual, e.currencyIso),
        statusLabel: labels["status" + e.status] || e.status
      }));
  }

  formatDate(value) {
    if (!value) {
      return "";
    }
    return new Intl.DateTimeFormat(LOCALE, { dateStyle: "medium" }).format(
      parseIsoDate(value)
    );
  }

  formatMoney(value, iso) {
    return new Intl.NumberFormat(LOCALE, {
      style: "currency",
      currency: iso || this.currency
    }).format(value || 0);
  }

  // ------------------------------------------------------------ handlers

  handleTab(event) {
    event.preventDefault();
    const id = event.currentTarget.dataset.id;
    if (id !== this.selectedHolder) {
      this.selectedHolder = id;
      this.load();
    }
  }

  handleRefresh() {
    this.load();
  }

  handleExpenseCategory(event) {
    this.expenseCategory = event.target.value;
  }

  handleRevenueCategory(event) {
    this.revenueCategory = event.target.value;
  }

  handleNewExpense() {
    this.openEntryWizard("DEBIT");
  }

  handleNewRevenue() {
    this.openEntryWizard("CREDIT");
  }

  openEntryWizard(direction) {
    const state = { c__direction: direction };
    if (this.selectedHolder !== ALL) {
      state.c__accountId = this.selectedHolder;
    }
    this[NavigationMixin.Navigate]({
      type: "standard__navItemPage",
      attributes: { apiName: "AXF_EntryWizard" },
      state
    });
  }

  handleOpenRecord(event) {
    event.preventDefault();
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: event.currentTarget.dataset.id,
        actionName: "view"
      }
    });
  }
}
