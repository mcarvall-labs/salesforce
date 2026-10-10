import { LightningElement } from "lwc";
import getHolders from "@salesforce/apex/AXF_CLS_CTRL_Dashboard.getHolders";
import getSummary from "@salesforce/apex/AXF_CLS_CTRL_Dashboard.getSummary";

const ALL = "";
const MONTHS_AROUND = 6;
const MONTH_NAMES = [
  "Janeiro",
  "Fevereiro",
  "Março",
  "Abril",
  "Maio",
  "Junho",
  "Julho",
  "Agosto",
  "Setembro",
  "Outubro",
  "Novembro",
  "Dezembro"
];

const pad = (value) => String(value).padStart(2, "0");
const monthKey = (year, month) => `${year}-${pad(month + 1)}-01`;

export default class AXF_LWC_dashboard extends LightningElement {
  holders = [];
  holderId = ALL;
  month = monthKey(new Date().getFullYear(), new Date().getMonth());
  summary;
  includeCard = false;
  isLoading = true;
  errorMessage;
  holdersError;
  requestId = 0;

  connectedCallback() {
    this.loadHolders();
    this.loadSummary();
  }

  async loadHolders() {
    try {
      this.holders = (await getHolders()) || [];
    } catch (error) {
      this.holdersError = this.messageOf(
        error,
        "Não foi possível carregar os titulares."
      );
    }
  }

  async loadSummary() {
    const request = ++this.requestId;
    this.isLoading = true;
    this.errorMessage = undefined;
    try {
      const summary = await getSummary({
        holderId: this.holderId || null,
        month: this.month
      });
      if (request === this.requestId) {
        this.summary = summary;
      }
    } catch (error) {
      if (request === this.requestId) {
        this.summary = undefined;
        this.errorMessage = this.messageOf(
          error,
          "Não foi possível carregar o dashboard."
        );
      }
    } finally {
      if (request === this.requestId) {
        this.isLoading = false;
      }
    }
  }

  messageOf(error, fallback) {
    return (error && error.body && error.body.message) || fallback;
  }

  get holderOptions() {
    return [
      { label: "Todos", value: ALL },
      ...this.holders.map((holder) => ({
        label: holder.name,
        value: holder.id
      }))
    ];
  }

  // Six months before and after the current one, plus the selected month if it is outside.
  get monthOptions() {
    const now = new Date();
    const keys = new Set([this.month]);
    for (let offset = -MONTHS_AROUND; offset <= MONTHS_AROUND; offset++) {
      const date = new Date(now.getFullYear(), now.getMonth() + offset, 1);
      keys.add(monthKey(date.getFullYear(), date.getMonth()));
    }
    return [...keys].sort().map((key) => ({
      label: `${MONTH_NAMES[Number(key.slice(5, 7)) - 1]}/${key.slice(0, 4)}`,
      value: key
    }));
  }

  get currency() {
    return (this.summary && this.summary.currencyCode) || "BRL";
  }

  money(value) {
    try {
      return new Intl.NumberFormat("pt-BR", {
        style: "currency",
        currency: this.currency
      }).format(value || 0);
    } catch {
      return String(value || 0);
    }
  }

  get hasSummary() {
    return !!this.summary;
  }

  // Net to pay: expenses minus income. Positive (more to pay than to receive) is shown in red.
  get overdueNet() {
    return this.summary.overdueExpense - this.summary.overdueIncome;
  }

  get dueSoonNet() {
    return this.summary.dueSoonExpense - this.summary.dueSoonIncome;
  }

  get overdueTotal() {
    return this.money(this.overdueNet);
  }

  get overdueClass() {
    return this.overdueNet > 0 ? "kpi-value out" : "kpi-value";
  }

  get overdueCaption() {
    return `${this.summary.overdueCount} em aberto`;
  }

  get dueSoonTotal() {
    return this.money(this.dueSoonNet);
  }

  get dueSoonClass() {
    return this.dueSoonNet > 0 ? "kpi-value out" : "kpi-value";
  }

  get dueSoonCaption() {
    const count = this.summary.dueSoonCount;
    return `${count} ${count === 1 ? "lançamento" : "lançamentos"}`;
  }

  get incomeTotal() {
    return this.money(this.summary.incomeRealized);
  }

  get expenseTotal() {
    return this.money(this.summary.expenseRealized);
  }

  get plannedCaption() {
    return `previsto ${this.money(this.summary.income)} / ${this.money(this.summary.expense)}`;
  }

  get projectedValue() {
    const s = this.summary;
    const value = this.includeCard
      ? s.projectedBalanceWithCard
      : s.projectedBalance;
    return value == null ? 0 : value;
  }

  get projectedTotal() {
    return this.money(this.projectedValue);
  }

  get projectedClass() {
    return this.projectedValue < 0 ? "kpi-value out" : "kpi-value in";
  }

  get cardLabel() {
    return `Incluir cartão previsto (${this.money(this.summary.cardForecast)})`;
  }

  handleHolderChange(event) {
    this.holderId = event.detail.value;
    this.loadSummary();
  }

  handleMonthChange(event) {
    this.month = event.detail.value;
    this.loadSummary();
  }

  handlePreviousMonth() {
    this.shiftMonth(-1);
  }

  handleNextMonth() {
    this.shiftMonth(1);
  }

  shiftMonth(delta) {
    const year = Number(this.month.slice(0, 4));
    const month = Number(this.month.slice(5, 7)) - 1;
    const date = new Date(year, month + delta, 1);
    this.month = monthKey(date.getFullYear(), date.getMonth());
    this.loadSummary();
  }

  handleCardToggle(event) {
    this.includeCard = event.detail.checked;
  }
}
