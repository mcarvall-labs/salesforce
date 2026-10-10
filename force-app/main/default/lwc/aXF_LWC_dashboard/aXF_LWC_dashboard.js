import { LightningElement } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import getHolders from "@salesforce/apex/AXF_CLS_CTRL_Dashboard.getHolders";
import getSummary from "@salesforce/apex/AXF_CLS_CTRL_Dashboard.getSummary";
import getEntries from "@salesforce/apex/AXF_CLS_CTRL_Dashboard.getEntries";
import getBudget from "@salesforce/apex/AXF_CLS_CTRL_Dashboard.getBudget";

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

const FILTER_TITLES = {
  OVERDUE: "Vencidos (todos os meses)",
  DUE_SOON: "A vencer no mês"
};

export default class AXF_LWC_dashboard extends NavigationMixin(
  LightningElement
) {
  holders = [];
  holderId = ALL;
  month = monthKey(new Date().getFullYear(), new Date().getMonth());
  summary;
  includeCard = false;
  isLoading = true;
  errorMessage;
  holdersError;
  requestId = 0;
  entries = [];
  entriesTruncated = false;
  entriesError;
  listFilter;
  budget;
  budgetError;
  budgetExpanded = false;

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

  async loadBudget(request) {
    this.budgetError = undefined;
    try {
      const budget = await getBudget({
        holderId: this.holderId || null,
        month: this.month
      });
      if (request === this.requestId) {
        this.budget = budget;
      }
    } catch (error) {
      if (request === this.requestId) {
        this.budget = undefined;
        this.budgetError = this.messageOf(
          error,
          "Não foi possível carregar as metas."
        );
      }
    }
  }

  async loadEntries(request) {
    this.entriesError = undefined;
    try {
      const result = await getEntries({
        holderId: this.holderId || null,
        month: this.month,
        filter: this.listFilter || null
      });
      if (request === this.requestId) {
        this.entries = result.rows || [];
        this.entriesTruncated = !!result.truncated;
      }
    } catch (error) {
      if (request === this.requestId) {
        this.entries = [];
        this.entriesTruncated = false;
        this.entriesError = this.messageOf(
          error,
          "Não foi possível carregar os lançamentos."
        );
      }
    }
  }

  async loadSummary() {
    const request = ++this.requestId;
    this.loadBudget(request);
    this.loadEntries(request);
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

  // Budget bars (E7-5): dark = realized, light = planned, 100 % = goal. Orange when the planned
  // passes the goal, red when the realized does. A category without goal has no bar.
  get hasBudget() {
    return !!this.budget;
  }

  get budgetRows() {
    if (!this.budget) {
      return [];
    }
    const rows = [this.budget.total, ...this.budget.rows];
    return rows.map((row, index) => this.barOf(row, index === 0));
  }

  barOf(row, isTotal) {
    const hasGoal = row.goal != null && row.goal > 0;
    const percent = (value) => {
      if (!hasGoal) {
        return 0;
      }
      return Math.max(0, Math.min(100, Math.round((value / row.goal) * 100)));
    };
    const over = hasGoal && row.realized > row.goal;
    const warning = hasGoal && row.planned > row.goal;
    return {
      key: isTotal ? "total" : row.categoryId || "none",
      name: row.name,
      hasGoal,
      isTotal,
      realizedText: this.money(row.realized),
      plannedText: this.money(row.planned),
      goalText: hasGoal
        ? `meta ${this.money(row.goal)} · ${Math.round((row.planned / row.goal) * 100)}%`
        : "sem meta",
      realizedStyle: `width: ${percent(row.realized)}%`,
      plannedStyle: `width: ${percent(row.planned)}%`,
      ratio: hasGoal ? row.planned / row.goal : 0,
      barClass: over
        ? "budget-bar over"
        : warning
          ? "budget-bar warning"
          : "budget-bar",
      alert: over
        ? "Realizado acima da meta"
        : warning
          ? "Previsto acima da meta"
          : undefined
    };
  }

  // Preview: the total and the three categories closest to their goal; the toggle shows all.
  get visibleBudgetRows() {
    const rows = this.budgetRows;
    if (this.budgetExpanded) {
      return rows;
    }
    const [total, ...categories] = rows;
    const closest = categories
      .filter((row) => row.hasGoal)
      .sort((a, b) => b.ratio - a.ratio || b.planned - a.planned)
      .slice(0, 3);
    return [total, ...closest];
  }

  get budgetToggleLabel() {
    return this.budgetExpanded ? "Ver menos" : "Ver todas as categorias";
  }

  // Same figure as the "incluir cartão previsto" switch (one source: the summary).
  get cardForecastLine() {
    return this.money(this.summary.cardForecast);
  }

  get showCardForecast() {
    return !!this.budget && !!this.summary && !!this.summary.cardForecast;
  }

  handleBudgetToggle() {
    this.budgetExpanded = !this.budgetExpanded;
  }

  // Clicking Vencidos or A vencer filters the month list; clicking it again clears the filter.
  handleOverdueClick(event) {
    event.preventDefault();
    this.toggleFilter("OVERDUE");
  }

  handleDueSoonClick(event) {
    event.preventDefault();
    this.toggleFilter("DUE_SOON");
  }

  toggleFilter(filter) {
    this.listFilter = this.listFilter === filter ? undefined : filter;
    this.loadEntries(this.requestId);
  }

  handleClearFilter() {
    this.listFilter = undefined;
    this.loadEntries(this.requestId);
  }

  get overdueKpiClass() {
    return this.kpiClass("OVERDUE", "kpi-overdue");
  }

  get dueSoonKpiClass() {
    return this.kpiClass("DUE_SOON", "kpi-due-soon");
  }

  kpiClass(filter, name) {
    const active = this.listFilter === filter ? " kpi-active" : "";
    return `kpi ${name} kpi-click slds-box slds-m-right_small${active}`;
  }

  get listTitle() {
    return FILTER_TITLES[this.listFilter] || "Lançamentos do mês";
  }

  get hasListFilter() {
    return !!this.listFilter;
  }

  get hasEntries() {
    return this.entries.length > 0;
  }

  get entryRows() {
    return this.entries.map((entry) => ({
      ...entry,
      key: entry.id,
      amountText: this.money(
        entry.type === "Expense" ? -entry.amount : entry.amount
      ),
      amountClass:
        entry.type === "Expense" ? "entry-amount out" : "entry-amount in",
      statusText: this.statusText(entry),
      detail: [entry.holderName, entry.categoryName].filter(Boolean).join(" · ")
    }));
  }

  statusText(entry) {
    if (entry.overdue) {
      return "Vencido";
    }
    if (entry.forecastCard) {
      return "Cartão previsto";
    }
    return entry.status === "Realized" ? "Realizado" : "Pendente";
  }

  get noEntriesMessage() {
    return !this.hasEntries && !this.entriesError
      ? "Nenhum lançamento neste filtro."
      : undefined;
  }

  get entriesCaption() {
    return this.entriesTruncated
      ? "Mostrando os primeiros lançamentos; refine pelo titular."
      : undefined;
  }

  // The invoice expense opens the Entry page, which carries the invoice detail (EP-06).
  handleEntryClick(event) {
    event.preventDefault();
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: event.currentTarget.dataset.id,
        objectApiName: "AXF_OBJ_Entry__c",
        actionName: "view"
      }
    });
  }

  handleNewExpense() {
    this.openNewEntry("Expense");
  }

  handleNewIncome() {
    this.openNewEntry("Income");
  }

  // The standard form opens with the Type and the filtered holder already filled in.
  openNewEntry(type) {
    const values = { AXF_ENT_PKL_Type__c: type };
    if (this.holderId) {
      values.AXF_ENT_MD_Holder__c = this.holderId;
    }
    this[NavigationMixin.Navigate]({
      type: "standard__objectPage",
      attributes: { objectApiName: "AXF_OBJ_Entry__c", actionName: "new" },
      state: {
        defaultFieldValues: Object.entries(values)
          .map(([field, value]) => `${field}=${encodeURIComponent(value)}`)
          .join(",")
      }
    });
  }
}
