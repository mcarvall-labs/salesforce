import { createElement } from "lwc";
import AXF_LWC_dashboard from "c/aXF_LWC_dashboard";
import getHolders from "@salesforce/apex/AXF_CLS_CTRL_Dashboard.getHolders";
import getSummary from "@salesforce/apex/AXF_CLS_CTRL_Dashboard.getSummary";
import getBudget from "@salesforce/apex/AXF_CLS_CTRL_Dashboard.getBudget";
import getEntries from "@salesforce/apex/AXF_CLS_CTRL_Dashboard.getEntries";
import getPending from "@salesforce/apex/AXF_CLS_CTRL_Dashboard.getPending";
import getSources from "@salesforce/apex/AXF_CLS_CTRL_Dashboard.getSources";
import getEntryCandidates from "@salesforce/apex/AXF_CLS_CTRL_Dashboard.getEntryCandidates";
import reconcile from "@salesforce/apex/AXF_CLS_CTRL_Reconciliation.reconcile";
import { updateRecord } from "lightning/uiRecordApi";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Dashboard.getHolders",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Dashboard.getSummary",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock("lightning/uiRecordApi", () => ({ updateRecord: jest.fn() }), {
  virtual: true
});
jest.mock(
  "lightning/platformShowToastEvent",
  () => ({
    ShowToastEvent: class extends CustomEvent {
      constructor(detail) {
        super("lightning__showtoast", { detail });
      }
    }
  }),
  { virtual: true }
);

const mockNavigate = jest.fn();
jest.mock(
  "lightning/navigation",
  () => {
    const Navigate = Symbol("Navigate");
    const NavigationMixin = (Base) =>
      class extends Base {
        [Navigate](pageReference) {
          mockNavigate(pageReference);
        }
      };
    NavigationMixin.Navigate = Navigate;
    return { NavigationMixin };
  },
  { virtual: true }
);
jest.mock(
  "lightning/pageReferenceUtils",
  () => ({
    encodeDefaultFieldValues: jest.fn((values) =>
      Object.entries(values)
        .map(([field, value]) => `${field}=${value}`)
        .join(",")
    )
  }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Dashboard.getPending",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Dashboard.getSources",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Dashboard.getEntries",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Dashboard.getBudget",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Dashboard.getEntryCandidates",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Reconciliation.reconcile",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flushPromises = () =>
  Array.from({ length: 10 }).reduce(
    (chain) => chain.then(() => undefined),
    Promise.resolve()
  );

const summary = {
  currencyCode: "BRL",
  overdueExpense: 40,
  overdueIncome: 10,
  overdueCount: 2,
  dueSoonExpense: 100,
  dueSoonIncome: 300,
  dueSoonCount: 3,
  income: 311,
  expense: 120,
  incomeRealized: 11,
  expenseRealized: 20,
  cardForecast: 65,
  projectedBalance: 1167,
  projectedBalanceWithCard: -50,
  realizedCount: 4
};

const budget = {
  total: { name: "Total de despesas", realized: 90, planned: 140, goal: 500 },
  rows: [
    {
      categoryId: "c1",
      name: "Mercado",
      realized: 60,
      planned: 130,
      goal: 120
    },
    { categoryId: "c2", name: "Lazer", realized: 130, planned: 130, goal: 100 },
    { categoryId: "c3", name: "Casa", realized: 10, planned: 20, goal: 200 },
    { categoryId: "c4", name: "Saúde", realized: 5, planned: 10, goal: 100 },
    {
      categoryId: "c5",
      name: "Transporte",
      realized: 8,
      planned: 8,
      goal: 400
    },
    {
      categoryId: null,
      name: "Sem categoria",
      realized: 0,
      planned: 10,
      goal: null
    }
  ]
};

const entryList = {
  truncated: false,
  rows: [
    {
      id: "e1",
      name: "Aluguel",
      dueDate: "2026-10-05",
      amount: 1500,
      type: "Expense",
      status: "Pending",
      holderName: "Michel",
      categoryName: "Casa",
      overdue: true,
      forecastCard: false,
      invoice: false
    },
    {
      id: "e2",
      name: "Salário",
      dueDate: "2026-10-10",
      amount: 5000,
      type: "Income",
      status: "Realized",
      holderName: "Gisele",
      categoryName: null,
      overdue: false,
      forecastCard: false,
      invoice: false
    },
    {
      id: "e3",
      name: "Streaming",
      dueDate: "2026-10-12",
      amount: 30,
      type: "Expense",
      status: "Pending",
      holderName: "Michel",
      categoryName: "Lazer",
      overdue: false,
      forecastCard: true,
      invoice: false
    }
  ]
};

const pending = {
  total: 12,
  suggestions: 2,
  truncated: false,
  items: [
    {
      id: "t1",
      source: "account",
      transactionDate: "2026-10-09",
      description: "Mercado Livre",
      amount: -89.9,
      suggested: true
    },
    {
      id: "t2",
      source: "card",
      transactionDate: "2026-10-08",
      description: "Streaming",
      amount: -30,
      suggested: false
    }
  ]
};

const sources = {
  accounts: [
    {
      id: "a1",
      name: "Inter ••1234",
      kind: "account",
      value: 4230.55,
      holderName: "Michel"
    }
  ],
  cards: [
    {
      id: "c1",
      name: "Mercado Pago ••5678",
      kind: "card",
      value: 6120,
      limitTotal: 8000,
      holderName: "Michel"
    }
  ]
};

const holders = [
  { id: "001A", name: "Michel" },
  { id: "001B", name: "Gisele" }
];

async function mount() {
  const element = createElement("c-a-x-f-l-w-c-dashboard", {
    is: AXF_LWC_dashboard
  });
  document.body.appendChild(element);
  await flushPromises();
  return element;
}

const text = (element, selector) =>
  element.shadowRoot.querySelector(selector).textContent.replace(/\s+/g, " ");

describe("c-a-x-f-l-w-c-dashboard", () => {
  beforeEach(() => {
    getHolders.mockResolvedValue(holders);
    getSummary.mockResolvedValue(summary);
    getBudget.mockResolvedValue(budget);
    getEntries.mockResolvedValue(entryList);
    getPending.mockResolvedValue(pending);
    getSources.mockResolvedValue(sources);
    getEntryCandidates.mockResolvedValue([]);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("loads the current month for all holders and shows the five indicators", async () => {
    const element = await mount();
    const call = getSummary.mock.calls[0][0];
    expect(call.holderId).toBeNull();
    expect(call.month).toMatch(/^\d{4}-\d{2}-01$/);
    expect(text(element, ".kpi-overdue")).toContain("R$ 30,00");
    expect(text(element, ".kpi-overdue")).not.toContain("-R$");
    expect(
      element.shadowRoot.querySelector(".kpi-overdue .out")
    ).not.toBeNull();
    expect(text(element, ".kpi-overdue")).toContain("2 em aberto");
    expect(text(element, ".kpi-due-soon")).toContain("-R$ 200,00");
    expect(text(element, ".kpi-due-soon")).toContain("3 lançamentos");
    expect(element.shadowRoot.querySelector(".kpi-due-soon .out")).toBeNull();
    expect(text(element, ".kpi-flow")).toContain("R$ 11,00");
    expect(text(element, ".kpi-flow")).toContain("despesas R$ 20,00");
    expect(text(element, ".planned")).toContain(
      "previsto R$ 311,00 / R$ 120,00"
    );
    expect(text(element, ".kpi-projected")).toContain("1.167,00");
    expect(text(element, ".kpi-realized")).toContain("Pago / recebido");
    expect(text(element, ".kpi-realized")).toContain("-R$ 9,00");
    expect(text(element, ".kpi-realized")).toContain("4 lançamentos");
  });

  it("lists Todos plus the holders returned by Apex", async () => {
    const element = await mount();
    const combo = element.shadowRoot.querySelector(".holder-filter");
    expect(combo.options.map((option) => option.label)).toEqual([
      "Todos",
      "Michel",
      "Gisele"
    ]);
  });

  it("reloads with the chosen holder", async () => {
    const element = await mount();
    element.shadowRoot
      .querySelector(".holder-filter")
      .dispatchEvent(new CustomEvent("change", { detail: { value: "001B" } }));
    await flushPromises();
    expect(getSummary).toHaveBeenCalledTimes(2);
    expect(getSummary.mock.calls[1][0].holderId).toBe("001B");
  });

  it("moves the month with the arrows and keeps it in the selector", async () => {
    const element = await mount();
    const first = getSummary.mock.calls[0][0].month;
    element.shadowRoot.querySelector(".next-month").click();
    await flushPromises();
    element.shadowRoot.querySelector(".previous-month").click();
    element.shadowRoot.querySelector(".previous-month").click();
    await flushPromises();
    const months = getSummary.mock.calls.map((call) => call[0].month);
    expect(months[1]).not.toBe(first);
    expect(months[3]).not.toBe(first);
    expect(months[3] < first).toBe(true);
    const combo = element.shadowRoot.querySelector(".month-select");
    expect(combo.options.map((option) => option.value)).toContain(months[3]);
  });

  it("subtracts the forecast card only when the switch is on", async () => {
    const element = await mount();
    const toggle = element.shadowRoot.querySelector(".card-toggle");
    expect(toggle.label).toContain("65,00");
    toggle.dispatchEvent(
      new CustomEvent("change", { detail: { checked: true } })
    );
    await flushPromises();
    expect(text(element, ".kpi-projected")).toContain("50,00");
    expect(
      element.shadowRoot.querySelector(".kpi-projected .out")
    ).not.toBeNull();
    expect(getSummary).toHaveBeenCalledTimes(1);
  });

  it("shows the Apex error and no indicators when the summary fails", async () => {
    getSummary.mockRejectedValue({ body: { message: "Sem acesso" } });
    const element = await mount();
    expect(text(element, ".error")).toContain("Sem acesso");
    expect(element.shadowRoot.querySelector(".kpis")).toBeNull();
  });

  it("ignores a stale response when the filter changes quickly", async () => {
    let resolveFirst;
    getSummary.mockImplementationOnce(
      () => new Promise((resolve) => (resolveFirst = resolve))
    );
    const element = await mount();
    getSummary.mockResolvedValueOnce({ ...summary, incomeRealized: 999 });
    element.shadowRoot
      .querySelector(".holder-filter")
      .dispatchEvent(new CustomEvent("change", { detail: { value: "001A" } }));
    await flushPromises();
    resolveFirst({ ...summary, incomeRealized: 1 });
    await flushPromises();
    expect(text(element, ".kpi-flow")).toContain("999,00");
  });

  it("shows the holders error and keeps it when the summary reloads", async () => {
    getHolders.mockRejectedValue({ body: { message: "Sem titulares" } });
    const element = await mount();
    expect(text(element, ".holders-error")).toContain("Sem titulares");
    element.shadowRoot.querySelector(".next-month").click();
    await flushPromises();
    expect(text(element, ".holders-error")).toContain("Sem titulares");
    expect(element.shadowRoot.querySelector(".kpis")).not.toBeNull();
  });

  it("copes with Apex returning no holders", async () => {
    getHolders.mockResolvedValue(null);
    const element = await mount();
    const combo = element.shadowRoot.querySelector(".holder-filter");
    expect(combo.options.map((option) => option.label)).toEqual(["Todos"]);
  });

  it("rolls the year over with the month arrows", async () => {
    jest.useFakeTimers().setSystemTime(new Date(2026, 11, 15));
    const element = await mount();
    expect(getSummary.mock.calls[0][0].month).toBe("2026-12-01");
    element.shadowRoot.querySelector(".next-month").click();
    await flushPromises();
    expect(getSummary.mock.calls[1][0].month).toBe("2027-01-01");
    element.shadowRoot.querySelector(".previous-month").click();
    element.shadowRoot.querySelector(".previous-month").click();
    await flushPromises();
    expect(getSummary.mock.calls[3][0].month).toBe("2026-11-01");
    const combo = element.shadowRoot.querySelector(".month-select");
    expect(combo.options.map((option) => option.value)).toContain("2027-01-01");
    jest.useRealTimers();
  });

  it("ignores a stale rejection", async () => {
    let rejectFirst;
    getSummary.mockImplementationOnce(
      () => new Promise((resolve, reject) => (rejectFirst = reject))
    );
    const element = await mount();
    getSummary.mockResolvedValueOnce({ ...summary, incomeRealized: 555 });
    element.shadowRoot
      .querySelector(".holder-filter")
      .dispatchEvent(new CustomEvent("change", { detail: { value: "001A" } }));
    await flushPromises();
    rejectFirst({ body: { message: "Antigo" } });
    await flushPromises();
    expect(element.shadowRoot.querySelector(".error")).toBeNull();
    expect(text(element, ".kpi-flow")).toContain("555,00");
  });

  it("shows the total and the three categories closest to the goal", async () => {
    const element = await mount();
    const names = [...element.shadowRoot.querySelectorAll(".budget-name")].map(
      (node) => node.textContent
    );
    expect(names).toEqual(["Total de despesas", "Lazer", "Mercado", "Casa"]);
    expect(getBudget.mock.calls[0][0].holderId).toBeNull();
  });

  it("expands to every category, including the ones without goal", async () => {
    const element = await mount();
    element.shadowRoot.querySelector(".budget-toggle").click();
    await flushPromises();
    const names = [...element.shadowRoot.querySelectorAll(".budget-name")].map(
      (node) => node.textContent
    );
    expect(names).toHaveLength(7);
    expect(names).toContain("Sem categoria");
    const rows = element.shadowRoot.querySelectorAll(".budget-row");
    const noGoal = [...rows].find((row) =>
      row.textContent.includes("Sem categoria")
    );
    expect(noGoal.textContent).toContain("sem meta");
    expect(noGoal.querySelector(".budget-bar")).toBeNull();
  });

  it("marks the planned above the goal in orange and the realized above it in red", async () => {
    const element = await mount();
    const rows = [...element.shadowRoot.querySelectorAll(".budget-row")];
    const of = (name) => rows.find((row) => row.textContent.includes(name));
    expect(of("Mercado").querySelector(".budget-bar.warning")).not.toBeNull();
    expect(of("Mercado").textContent).toContain("Previsto acima da meta");
    expect(of("Lazer").querySelector(".budget-bar.over")).not.toBeNull();
    expect(of("Lazer").textContent).toContain("Realizado acima da meta");
    expect(of("Casa").querySelector(".budget-alert")).toBeNull();
    expect(
      of("Total").querySelector(".budget-bar.warning, .budget-bar.over")
    ).toBeNull();
  });

  it("caps the bar at 100% and sizes realized and planned against the goal", async () => {
    const element = await mount();
    const rows = [...element.shadowRoot.querySelectorAll(".budget-row")];
    const lazer = rows.find((row) => row.textContent.includes("Lazer"));
    expect(
      lazer.querySelector(".realized-fill").getAttribute("style")
    ).toContain("100%");
    const total = rows[0];
    expect(
      total.querySelector(".realized-fill").getAttribute("style")
    ).toContain("18%");
    expect(
      total.querySelector(".planned-fill").getAttribute("style")
    ).toContain("28%");
  });

  it("shows the forecast card line only when there is one", async () => {
    let element = await mount();
    expect(text(element, ".card-forecast-line")).toContain("R$ 65,00");
    document.body.removeChild(element);
    getSummary.mockResolvedValue({ ...summary, cardForecast: 0 });
    element = await mount();
    expect(element.shadowRoot.querySelector(".card-forecast-line")).toBeNull();
  });

  it("reloads the goals with the holder and the month", async () => {
    const element = await mount();
    element.shadowRoot
      .querySelector(".holder-filter")
      .dispatchEvent(new CustomEvent("change", { detail: { value: "001B" } }));
    await flushPromises();
    expect(getBudget.mock.calls[1][0].holderId).toBe("001B");
    element.shadowRoot.querySelector(".next-month").click();
    await flushPromises();
    expect(getBudget.mock.calls[2][0].month).toBe(
      getSummary.mock.calls[2][0].month
    );
  });

  it("shows the percentage of the goal used next to each bar", async () => {
    const element = await mount();
    expect(text(element, ".budget-values")).toContain("meta R$ 500,00 · 28%");
  });

  it("ignores a stale goals response", async () => {
    let resolveFirst;
    getBudget.mockImplementationOnce(
      () => new Promise((resolve) => (resolveFirst = resolve))
    );
    const element = await mount();
    getBudget.mockResolvedValueOnce({
      ...budget,
      total: { ...budget.total, name: "Novo total" }
    });
    element.shadowRoot
      .querySelector(".holder-filter")
      .dispatchEvent(new CustomEvent("change", { detail: { value: "001A" } }));
    await flushPromises();
    resolveFirst({
      ...budget,
      total: { ...budget.total, name: "Velho total" }
    });
    await flushPromises();
    expect(text(element, ".budget-name")).toContain("Novo total");
  });

  it("shows a goals error without hiding the indicators", async () => {
    getBudget.mockRejectedValue({ body: { message: "Sem acesso às metas" } });
    const element = await mount();
    expect(text(element, ".budget-error")).toContain("Sem acesso às metas");
    expect(element.shadowRoot.querySelector(".kpis")).not.toBeNull();
    expect(element.shadowRoot.querySelector(".budget")).toBeNull();
  });

  it("lists the month entries with sign, status and holder", async () => {
    const element = await mount();
    expect(getEntries.mock.calls[0][0].filter).toBeNull();
    expect(text(element, ".entries-title")).toContain("Lançamentos do mês");
    const rows = [...element.shadowRoot.querySelectorAll(".entry-row")];
    expect(rows).toHaveLength(3);
    expect(rows[0].textContent).toContain("Aluguel");
    expect(rows[0].textContent).toContain("Atrasado");
    expect(rows[0].textContent.replace(/\s+/g, " ")).toContain("-R$ 1.500,00");
    expect(rows[0].querySelector(".out")).not.toBeNull();
    expect(rows[1].textContent).toContain("Recebido");
    expect(rows[1].querySelector(".in")).not.toBeNull();
    expect(rows[2].textContent).toContain("Cartão previsto");
  });

  it("filters the list when a deadline indicator is clicked and clears it", async () => {
    const element = await mount();
    element.shadowRoot.querySelector(".kpi-overdue").click();
    await flushPromises();
    expect(getEntries.mock.calls[1][0].filter).toBe("OVERDUE");
    expect(text(element, ".entries-title")).toContain(
      "Vencidos (todos os meses)"
    );
    expect(
      element.shadowRoot.querySelector(".kpi-overdue.kpi-active")
    ).not.toBeNull();
    element.shadowRoot.querySelector(".kpi-due-soon").click();
    await flushPromises();
    expect(getEntries.mock.calls[2][0].filter).toBe("DUE_SOON");
    expect(text(element, ".entries-title")).toContain("A vencer no mês");
    element.shadowRoot.querySelector(".clear-filter").click();
    await flushPromises();
    expect(getEntries.mock.calls[3][0].filter).toBeNull();
    expect(element.shadowRoot.querySelector(".clear-filter")).toBeNull();
    element.shadowRoot.querySelector(".kpi-overdue").click();
    await flushPromises();
    element.shadowRoot.querySelector(".kpi-overdue").click();
    await flushPromises();
    expect(getEntries.mock.calls[5][0].filter).toBeNull();
  });

  it("keeps the filter when the holder or month changes", async () => {
    const element = await mount();
    element.shadowRoot.querySelector(".kpi-due-soon").click();
    await flushPromises();
    element.shadowRoot
      .querySelector(".holder-filter")
      .dispatchEvent(new CustomEvent("change", { detail: { value: "001B" } }));
    await flushPromises();
    const last = getEntries.mock.calls[getEntries.mock.calls.length - 1][0];
    expect(last.filter).toBe("DUE_SOON");
    expect(last.holderId).toBe("001B");
  });

  it("opens the entry record when a row is clicked", async () => {
    const element = await mount();
    element.shadowRoot.querySelector(".entry-link").click();
    expect(mockNavigate).toHaveBeenCalledWith({
      type: "standard__recordPage",
      attributes: {
        recordId: "e1",
        objectApiName: "AXF_OBJ_Entry__c",
        actionName: "view"
      }
    });
  });

  it("opens the expense wizard from + Despesa and the standard form from + Receita", async () => {
    mockNavigate.mockClear();
    const element = await mount();
    expect(
      element.shadowRoot.querySelector("c-a-x-f_-l-w-c_expense-wizard")
    ).toBeNull();
    element.shadowRoot.querySelector(".new-expense").click();
    await flushPromises();
    const wizard = element.shadowRoot.querySelector(
      "c-a-x-f_-l-w-c_expense-wizard"
    );
    expect(wizard).not.toBeNull();
    expect(mockNavigate).not.toHaveBeenCalled();
    expect(wizard.holderId).toBe("");
    expect(wizard.holders).toEqual(holders);
    wizard.dispatchEvent(new CustomEvent("close"));
    await flushPromises();
    expect(
      element.shadowRoot.querySelector("c-a-x-f_-l-w-c_expense-wizard")
    ).toBeNull();
    element.shadowRoot
      .querySelector(".holder-filter")
      .dispatchEvent(new CustomEvent("change", { detail: { value: "001B" } }));
    await flushPromises();
    element.shadowRoot.querySelector(".new-income").click();
    expect(mockNavigate).toHaveBeenLastCalledWith({
      type: "standard__objectPage",
      attributes: { objectApiName: "AXF_OBJ_Entry__c", actionName: "new" },
      state: {
        defaultFieldValues:
          "AXF_ENT_PKL_Type__c=Income,AXF_ENT_MD_Holder__c=001B"
      }
    });
  });

  it("closes the wizard and reloads the summary when an expense is saved", async () => {
    const element = await mount();
    const calls = getSummary.mock.calls.length;
    element.shadowRoot.querySelector(".new-expense").click();
    await flushPromises();
    element.shadowRoot
      .querySelector("c-a-x-f_-l-w-c_expense-wizard")
      .dispatchEvent(new CustomEvent("saved"));
    await flushPromises();
    expect(
      element.shadowRoot.querySelector("c-a-x-f_-l-w-c_expense-wizard")
    ).toBeNull();
    expect(getSummary.mock.calls.length).toBeGreaterThan(calls);
  });

  it("shows the empty, truncated and error states of the list", async () => {
    getEntries.mockResolvedValue({ rows: [], truncated: false });
    let element = await mount();
    expect(text(element, ".entries-empty")).toContain("Nenhum lançamento");
    document.body.removeChild(element);
    getEntries.mockResolvedValue({ ...entryList, truncated: true });
    element = await mount();
    expect(text(element, ".entries-caption")).toContain("primeiros");
    document.body.removeChild(element);
    getEntries.mockRejectedValue({ body: { message: "Sem acesso" } });
    element = await mount();
    expect(text(element, ".entries-error")).toContain("Sem acesso");
    expect(element.shadowRoot.querySelector(".entry-row")).toBeNull();
    expect(element.shadowRoot.querySelector(".entries-empty")).toBeNull();
  });

  it("ignores an older list response after quick filter clicks", async () => {
    let resolveFirst;
    const element = await mount();
    getEntries.mockImplementationOnce(
      () => new Promise((resolve) => (resolveFirst = resolve))
    );
    element.shadowRoot.querySelector(".kpi-overdue").click();
    getEntries.mockResolvedValueOnce({
      truncated: false,
      rows: [{ ...entryList.rows[1], name: "Resposta nova" }]
    });
    element.shadowRoot.querySelector(".kpi-due-soon").click();
    await flushPromises();
    resolveFirst({
      truncated: false,
      rows: [{ ...entryList.rows[0], name: "Resposta velha" }]
    });
    await flushPromises();
    expect(text(element, ".entries")).toContain("Resposta nova");
    expect(text(element, ".entries")).not.toContain("Resposta velha");
  });

  it("copes with a missing amount, an unknown type and an unknown status", async () => {
    getEntries.mockResolvedValue({
      truncated: false,
      rows: [
        { id: "x1", name: "Sem valor", type: "Expense", status: "Pending" },
        {
          id: "x2",
          name: "Transferência",
          amount: 10,
          type: "Transfer",
          status: "Canceled"
        }
      ]
    });
    const element = await mount();
    const rows = [...element.shadowRoot.querySelectorAll(".entry-row")];
    expect(rows[0].textContent).not.toContain("NaN");
    expect(rows[1].querySelector(".in")).toBeNull();
    expect(rows[1].querySelector(".out")).toBeNull();
    expect(rows[1].textContent).toContain("Canceled");
  });

  it("keeps the list visible when the summary fails", async () => {
    getSummary.mockRejectedValue({ body: { message: "Falha no resumo" } });
    const element = await mount();
    expect(element.shadowRoot.querySelectorAll(".entry-row")).toHaveLength(3);
  });

  it("marks the active indicator as pressed for assistive technology", async () => {
    const element = await mount();
    const overdue = element.shadowRoot.querySelector(".kpi-overdue");
    expect(overdue.getAttribute("aria-pressed")).toBe("false");
    overdue.click();
    await flushPromises();
    expect(
      element.shadowRoot
        .querySelector(".kpi-overdue")
        .getAttribute("aria-pressed")
    ).toBe("true");
  });

  it("keeps the filter and sends the new month when the month changes", async () => {
    const element = await mount();
    element.shadowRoot.querySelector(".kpi-due-soon").click();
    await flushPromises();
    element.shadowRoot.querySelector(".next-month").click();
    await flushPromises();
    const last = getEntries.mock.calls[getEntries.mock.calls.length - 1][0];
    expect(last.filter).toBe("DUE_SOON");
    expect(last.month).toBe(
      getSummary.mock.calls[getSummary.mock.calls.length - 1][0].month
    );
    expect(last.month).not.toBe(getEntries.mock.calls[0][0].month);
  });

  it("shows the count, the suggestions and the three most recent open transactions", async () => {
    const element = await mount();
    expect(text(element, ".pending-title")).toContain("A conciliar (12)");
    expect(text(element, ".pending-caption")).toContain("2 com sugestões");
    const rows = [...element.shadowRoot.querySelectorAll(".pending-row")];
    expect(rows).toHaveLength(2);
    expect(rows[0].textContent).toContain("Mercado Livre");
    expect(rows[0].textContent).toContain("sugestão");
    expect(rows[0].textContent.replace(/\s+/g, " ")).toContain("-R$ 89,90");
    expect(rows[1].textContent).toContain("Cartão");
    expect(getPending.mock.calls[0][0].holderId).toBeNull();
  });

  it("opens the Conciliação tab from the preview", async () => {
    const element = await mount();
    element.shadowRoot.querySelector(".pending-title").click();
    expect(mockNavigate).toHaveBeenLastCalledWith({
      type: "standard__navItemPage",
      attributes: { apiName: "AXF_CT_Reconciliation" }
    });
    element.shadowRoot.querySelector(".pending-open").click();
    expect(mockNavigate).toHaveBeenCalledTimes(2);
  });

  it("shows balance and available limit and opens the account, the card and their tabs", async () => {
    const element = await mount();
    const rows = [...element.shadowRoot.querySelectorAll(".source-row")];
    expect(rows).toHaveLength(2);
    expect(rows[0].textContent.replace(/\s+/g, " ")).toContain(
      "Saldo R$ 4.230,55"
    );
    expect(rows[1].textContent.replace(/\s+/g, " ")).toContain(
      "Limite disp. R$ 6.120,00"
    );
    rows[0].querySelector(".source-link").click();
    expect(mockNavigate).toHaveBeenLastCalledWith({
      type: "standard__recordPage",
      attributes: {
        recordId: "a1",
        objectApiName: "AXF_OBJ_BankAccount__c",
        actionName: "view"
      }
    });
    element.shadowRoot.querySelector(".open-cards").click();
    expect(mockNavigate).toHaveBeenLastCalledWith({
      type: "standard__objectPage",
      attributes: {
        objectApiName: "AXF_OBJ_CreditCard__c",
        actionName: "list"
      },
      state: { filterName: "Recent" }
    });
    element.shadowRoot.querySelector(".open-accounts").click();
    expect(
      mockNavigate.mock.calls[mockNavigate.mock.calls.length - 1][0].attributes
        .objectApiName
    ).toBe("AXF_OBJ_BankAccount__c");
  });

  it("reloads the previews with the holder and the month", async () => {
    const element = await mount();
    element.shadowRoot
      .querySelector(".holder-filter")
      .dispatchEvent(new CustomEvent("change", { detail: { value: "001B" } }));
    await flushPromises();
    expect(getPending.mock.calls[1][0].holderId).toBe("001B");
    expect(getSources.mock.calls[1][0].holderId).toBe("001B");
    element.shadowRoot.querySelector(".next-month").click();
    await flushPromises();
    expect(getPending.mock.calls[2][0].month).toBe(
      getSummary.mock.calls[2][0].month
    );
  });

  it("shows the empty states and the truncation mark", async () => {
    getPending.mockResolvedValue({
      total: 0,
      suggestions: 0,
      truncated: false,
      items: []
    });
    getSources.mockResolvedValue({ accounts: [], cards: [] });
    let element = await mount();
    expect(text(element, ".pending-empty")).toContain("Nada a conciliar");
    expect(text(element, ".sources-empty")).toContain(
      "Nenhuma conta ou cartão"
    );
    document.body.removeChild(element);
    getPending.mockResolvedValue({ ...pending, truncated: true });
    element = await mount();
    expect(text(element, ".pending-title")).toContain("A conciliar (12+)");
  });

  it("shows an error per preview without hiding the other one or the indicators", async () => {
    getPending.mockRejectedValue({
      body: { message: "Sem acesso às pendências" }
    });
    const element = await mount();
    expect(text(element, ".pending-error")).toContain(
      "Sem acesso às pendências"
    );
    expect(element.shadowRoot.querySelector(".pending-card")).toBeNull();
    expect(element.shadowRoot.querySelectorAll(".source-row")).toHaveLength(2);
    expect(element.shadowRoot.querySelector(".kpis")).not.toBeNull();
    document.body.removeChild(element);
    getPending.mockResolvedValue(pending);
    getSources.mockRejectedValue({ body: { message: "Sem acesso às contas" } });
    const second = await mount();
    expect(text(second, ".sources-error")).toContain("Sem acesso às contas");
    expect(second.shadowRoot.querySelectorAll(".pending-row")).toHaveLength(2);
  });

  it("ignores an older previews response", async () => {
    let resolveFirst;
    getPending.mockImplementationOnce(
      () => new Promise((resolve) => (resolveFirst = resolve))
    );
    const element = await mount();
    getPending.mockResolvedValueOnce({ ...pending, total: 99 });
    element.shadowRoot
      .querySelector(".holder-filter")
      .dispatchEvent(new CustomEvent("change", { detail: { value: "001A" } }));
    await flushPromises();
    resolveFirst({ ...pending, total: 1 });
    await flushPromises();
    expect(text(element, ".pending-title")).toContain("(99)");
  });

  it("marks partial suggestions and shows the owner of each source for all holders", async () => {
    getPending.mockResolvedValue({ ...pending, suggestionsPartial: true });
    const element = await mount();
    expect(text(element, ".pending-caption")).toContain("(parcial)");
    expect(text(element, ".source-link")).toContain("Inter ••1234 · Michel");
    element.shadowRoot
      .querySelector(".holder-filter")
      .dispatchEvent(new CustomEvent("change", { detail: { value: "001B" } }));
    await flushPromises();
    expect(text(element, ".source-link")).not.toContain("· Michel");
  });

  it("shows a dash when a balance or limit is missing", async () => {
    getSources.mockResolvedValue({
      accounts: [{ id: "a2", name: "Sem saldo", kind: "account", value: null }],
      cards: []
    });
    const element = await mount();
    expect(text(element, ".source-row")).toContain("Saldo —");
    expect(text(element, ".source-row")).not.toContain("R$ 0,00");
  });

  it("puts the indicators above the grid, the month list in the centre and the previews on the right", async () => {
    const element = await mount();
    const root = element.shadowRoot;
    const grid = root.querySelector(".dashboard-grid");
    const main = grid.querySelector(".main-column");
    const side = grid.querySelector(".side-column");
    const kpis = root.querySelector(".kpis");
    expect(grid.contains(kpis)).toBe(false);
    expect(
      kpis.compareDocumentPosition(grid) & Node.DOCUMENT_POSITION_FOLLOWING
    ).toBeTruthy();
    expect(main.querySelector(".entries")).not.toBeNull();
    expect(main.querySelector(".pending-card")).toBeNull();
    expect(side.querySelector(".pending-card")).not.toBeNull();
    expect(side.querySelector(".sources-card")).not.toBeNull();
  });

  it("keeps the goals card in the right column below Contas e cartões", async () => {
    const element = await mount();
    const side = element.shadowRoot.querySelector(".side-column");
    const goalsCard = side.querySelector(".budget");
    const sourcesCard = side.querySelector(".sources-card");
    expect(goalsCard).not.toBeNull();
    expect(
      sourcesCard.compareDocumentPosition(goalsCard) &
        Node.DOCUMENT_POSITION_FOLLOWING
    ).toBeTruthy();
    expect(element.shadowRoot.querySelector(".main-column .budget")).toBeNull();
  });

  it("gives every card a highlighted title", async () => {
    const element = await mount();
    const titles = [...element.shadowRoot.querySelectorAll(".card-title")].map(
      (node) => node.textContent.replace(/\s+/g, " ").trim()
    );
    expect(titles).toEqual([
      "Lançamentos do mês",
      "A conciliar (12)",
      "Contas e cartões",
      "Metas de despesa"
    ]);
  });

  it("offers mark as realized only on pending non-forecast rows", async () => {
    const element = await mount();
    const buttons = element.shadowRoot.querySelectorAll(".mark-realized");
    expect(buttons).toHaveLength(1);
    expect(buttons[0].dataset.id).toBe("e1");
  });

  it("opens the popup with due date and amount suggested and saves the edited values", async () => {
    updateRecord.mockResolvedValue({});
    const element = await mount();
    getSummary.mockClear();
    getEntries.mockClear();
    const toasts = [];
    element.addEventListener("lightning__showtoast", (e) => toasts.push(e));
    element.shadowRoot.querySelector(".mark-realized").click();
    await flushPromises();
    const date = element.shadowRoot.querySelector(".realize-date");
    const amount = element.shadowRoot.querySelector(".realize-amount");
    expect(date.value).toBe("2026-10-05");
    expect(amount.value).toBe(1500);
    date.dispatchEvent(
      new CustomEvent("change", { detail: { value: "2026-10-07" } })
    );
    amount.dispatchEvent(
      new CustomEvent("change", { detail: { value: "1450.5" } })
    );
    element.shadowRoot.querySelector(".realize-confirm").click();
    await flushPromises();
    expect(updateRecord).toHaveBeenCalledWith({
      fields: {
        Id: "e1",
        AXF_ENT_PKL_Status__c: "Realized",
        AXF_ENT_DAT_PaymentDate__c: "2026-10-07",
        AXF_ENT_NUM_RealizedAmountBRL__c: 1450.5
      }
    });
    expect(element.shadowRoot.querySelector(".realize-modal")).toBeNull();
    expect(getSummary).toHaveBeenCalled();
    expect(getEntries).toHaveBeenCalled();
    expect(toasts).toHaveLength(1);
    expect(toasts[0].detail.variant).toBe("success");
  });

  it("cancels the popup without saving and shows save errors", async () => {
    const element = await mount();
    element.shadowRoot.querySelector(".mark-realized").click();
    await flushPromises();
    element.shadowRoot.querySelector(".realize-cancel").click();
    await flushPromises();
    expect(element.shadowRoot.querySelector(".realize-modal")).toBeNull();
    expect(updateRecord).not.toHaveBeenCalled();

    updateRecord.mockRejectedValueOnce({ body: { message: "Sem permissão" } });
    element.shadowRoot.querySelector(".mark-realized").click();
    await flushPromises();
    element.shadowRoot.querySelector(".realize-confirm").click();
    await flushPromises();
    expect(text(element, ".realize-error")).toContain("Sem permissão");
    expect(element.shadowRoot.querySelector(".realize-modal")).not.toBeNull();
  });

  it("blocks saving without a date", async () => {
    const element = await mount();
    element.shadowRoot.querySelector(".mark-realized").click();
    await flushPromises();
    element.shadowRoot
      .querySelector(".realize-date")
      .dispatchEvent(new CustomEvent("change", { detail: { value: "" } }));
    element.shadowRoot.querySelector(".realize-confirm").click();
    await flushPromises();
    expect(updateRecord).not.toHaveBeenCalled();
    expect(text(element, ".realize-error")).toContain("Informe");
  });

  it("blocks a zero or negative amount", async () => {
    const element = await mount();
    element.shadowRoot.querySelector(".mark-realized").click();
    await flushPromises();
    element.shadowRoot
      .querySelector(".realize-amount")
      .dispatchEvent(new CustomEvent("change", { detail: { value: "-5" } }));
    element.shadowRoot.querySelector(".realize-confirm").click();
    await flushPromises();
    expect(updateRecord).not.toHaveBeenCalled();
    expect(text(element, ".realize-error")).toContain("maior que zero");
  });

  it("saves once on a double click and ignores Cancel while saving", async () => {
    let resolveSave;
    updateRecord.mockImplementationOnce(
      () => new Promise((resolve) => (resolveSave = resolve))
    );
    const element = await mount();
    element.shadowRoot.querySelector(".mark-realized").click();
    await flushPromises();
    const confirm = element.shadowRoot.querySelector(".realize-confirm");
    confirm.click();
    confirm.click();
    await flushPromises();
    element.shadowRoot.querySelector(".realize-cancel").click();
    expect(updateRecord).toHaveBeenCalledTimes(1);
    expect(element.shadowRoot.querySelector(".realize-modal")).not.toBeNull();
    resolveSave({});
    await flushPromises();
    expect(element.shadowRoot.querySelector(".realize-modal")).toBeNull();
  });

  it("closes the popup with Escape", async () => {
    const element = await mount();
    element.shadowRoot.querySelector(".mark-realized").click();
    await flushPromises();
    element.shadowRoot
      .querySelector(".realize-modal")
      .dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
    await flushPromises();
    expect(element.shadowRoot.querySelector(".realize-modal")).toBeNull();
  });

  it("offers mark as realized in the Vencidos list too", async () => {
    const element = await mount();
    getEntries.mockResolvedValueOnce({
      truncated: false,
      rows: [entryList.rows[0]]
    });
    element.shadowRoot.querySelector(".kpi-overdue").click();
    await flushPromises();
    expect(element.shadowRoot.querySelectorAll(".mark-realized")).toHaveLength(
      1
    );
  });

  describe("status badges and chips", () => {
    const iso = (offset) => {
      const date = new Date();
      date.setDate(date.getDate() + offset);
      const pad = (value) => String(value).padStart(2, "0");
      return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
    };
    const row = (id, over) => ({
      id,
      name: `L${id}`,
      amount: 10,
      type: "Expense",
      status: "Pending",
      overdue: false,
      forecastCard: false,
      ...over
    });
    const scenarioRows = () => [
      row("s1", { dueDate: iso(1) }),
      row("s5", { dueDate: iso(5) }),
      row("s0", { dueDate: iso(0) }),
      row("o6", { dueDate: iso(6) }),
      row("l3", { dueDate: iso(-3), overdue: true }),
      row("l1", { dueDate: iso(-1), overdue: true }),
      row("p1", {
        dueDate: iso(-5),
        status: "Realized",
        paymentDate: "2026-10-04"
      }),
      row("p2", {
        dueDate: iso(-5),
        status: "Realized",
        type: "Income"
      }),
      row("f1", { dueDate: iso(2), forecastCard: true })
    ];
    const rowOf = (element, name) =>
      [...element.shadowRoot.querySelectorAll(".entry-row")].find((node) =>
        node.textContent.includes(name)
      );
    const squash = (node) => node.textContent.replace(/\s+/g, " ");
    // Pill label and sub-text are separate elements: join them with a space.
    const pillText = (node) =>
      [...node.querySelectorAll(".pill, .pill-sub")]
        .map((part) => part.firstChild.textContent.trim())
        .join(" ");

    it("labels each row by due date, with colour class and sub-text", async () => {
      getEntries.mockResolvedValue({ truncated: false, rows: scenarioRows() });
      const element = await mount();
      expect(pillText(rowOf(element, "Ls1"))).toContain(
        "Vence em breve amanhã"
      );
      expect(pillText(rowOf(element, "Ls5"))).toContain(
        "Vence em breve em 5 dias"
      );
      expect(pillText(rowOf(element, "Ls0"))).toContain("Vence em breve hoje");
      expect(pillText(rowOf(element, "Lo6"))).toContain("Em aberto em 6 dias");
      expect(pillText(rowOf(element, "Ll3"))).toContain("Atrasado 3 dias");
      expect(pillText(rowOf(element, "Ll1"))).toContain("Atrasado 1 dia");
      expect(pillText(rowOf(element, "Lp1"))).toContain("Pago em 04/10");
      expect(pillText(rowOf(element, "Lp2"))).toContain("Recebido");
      expect(pillText(rowOf(element, "Lf1"))).toContain("Cartão previsto");
      expect(rowOf(element, "Ls1").querySelector(".pill-soon")).not.toBeNull();
      expect(rowOf(element, "Lo6").querySelector(".pill-open")).not.toBeNull();
      expect(rowOf(element, "Ll3").querySelector(".pill-late")).not.toBeNull();
      expect(rowOf(element, "Lp1").querySelector(".pill-paid")).not.toBeNull();
    });

    it("counts the chips from the loaded list and filters client-side", async () => {
      getEntries.mockResolvedValue({ truncated: false, rows: scenarioRows() });
      const element = await mount();
      const chips = () => [...element.shadowRoot.querySelectorAll(".chip")];
      expect(chips().map((chip) => squash(chip).trim())).toEqual([
        "Todos9",
        "Pagos2",
        "Em aberto5",
        "Atrasados2"
      ]);
      getEntries.mockClear();
      chips()[3].click();
      await flushPromises();
      expect(element.shadowRoot.querySelectorAll(".entry-row")).toHaveLength(2);
      expect(getEntries).not.toHaveBeenCalled();
      chips()[2].click();
      await flushPromises();
      expect(element.shadowRoot.querySelectorAll(".entry-row")).toHaveLength(5);
      chips()[1].click();
      await flushPromises();
      expect(element.shadowRoot.querySelectorAll(".entry-row")).toHaveLength(2);
      expect(chips()[1].getAttribute("aria-pressed")).toBe("true");
      chips()[0].click();
      await flushPromises();
      expect(element.shadowRoot.querySelectorAll(".entry-row")).toHaveLength(9);
    });

    it("offers Pagar on expenses and Receber on income", async () => {
      getEntries.mockResolvedValue({
        truncated: false,
        rows: [
          row("a", { dueDate: iso(3) }),
          row("b", { dueDate: iso(3), type: "Income" })
        ]
      });
      const element = await mount();
      const labels = [
        ...element.shadowRoot.querySelectorAll(".mark-realized")
      ].map((button) => button.alternativeText);
      expect(labels).toEqual(["Pagar", "Receber"]);
    });

    it("shows the empty message and resets the chip when the month changes", async () => {
      getEntries.mockResolvedValue({
        truncated: false,
        rows: scenarioRows().filter((item) => item.status === "Realized")
      });
      const element = await mount();
      const chips = () => [...element.shadowRoot.querySelectorAll(".chip")];
      chips()[3].click();
      await flushPromises();
      expect(element.shadowRoot.querySelectorAll(".entry-row")).toHaveLength(0);
      expect(text(element, ".entries-empty")).toContain("Nenhum lançamento");
      element.shadowRoot.querySelector(".next-month").click();
      await flushPromises();
      expect(chips()[0].getAttribute("aria-pressed")).toBe("true");
    });
  });

  describe("Pagar/Receber popup with Pluggy reconciliation", () => {
    const candidates = [
      {
        id: "b1",
        source: "account",
        description: "DEB ENEL",
        transactionDate: "2026-10-04",
        amount: -1500,
        currencyCode: "BRL",
        accountName: "Itaú",
        daysApart: 1,
        amountGap: 0,
        tag: "BEST"
      },
      {
        id: "c1",
        source: "card",
        description: "ENEL CARTAO",
        transactionDate: "2026-10-06",
        amount: -1510,
        currencyCode: "BRL",
        accountName: "Nubank",
        daysApart: 1,
        amountGap: 10,
        tag: "VALUE"
      }
    ];

    const open = async (element) => {
      element.shadowRoot.querySelector(".mark-realized").click();
      await flushPromises();
    };
    const pairOf = () => JSON.parse(reconcile.mock.calls[0][0].pairsJson);

    it("lists the candidates with the best one preselected, tags and effect", async () => {
      getEntryCandidates.mockResolvedValue(candidates);
      const element = await mount();
      await open(element);
      const root = element.shadowRoot;
      expect(getEntryCandidates).toHaveBeenCalledWith({ entryId: "e1" });
      expect(text(element, ".slds-modal__title")).toContain("Pagar");
      expect(text(element, ".tab-pluggy")).toContain(
        "2 transações compatíveis"
      );
      const rows = [...root.querySelectorAll(".candidate")];
      expect(rows).toHaveLength(2);
      expect(rows[0].textContent).toContain("Melhor correspondência");
      expect(rows[1].textContent).toContain("Valor próximo");
      expect(rows[1].textContent).toContain("diferença");
      expect(root.querySelector(".candidate-selected").textContent).toContain(
        "DEB ENEL"
      );
      expect(text(element, ".candidate-effect")).toContain(
        "Pago em 04/10/2026 com R$ 1.500,00"
      );
      expect(root.querySelector(".realize-confirm").label).toBe(
        "Pagar e conciliar"
      );
      expect(text(element, ".reconciliation-hint")).toContain("Conciliação");
    });

    it("reconciles the chosen bank transaction and reloads the page", async () => {
      getEntryCandidates.mockResolvedValue(candidates);
      reconcile.mockResolvedValue([
        { entryId: "e1", transactionId: "b1", success: true }
      ]);
      const element = await mount();
      const toasts = [];
      element.addEventListener("lightning__showtoast", (e) => toasts.push(e));
      await open(element);
      getSummary.mockClear();
      element.shadowRoot.querySelector(".realize-confirm").click();
      await flushPromises();
      expect(pairOf()).toEqual([{ entryId: "e1", bankTransactionId: "b1" }]);
      expect(updateRecord).not.toHaveBeenCalled();
      expect(element.shadowRoot.querySelector(".realize-modal")).toBeNull();
      expect(getSummary).toHaveBeenCalled();
      expect(toasts[0].detail.variant).toBe("success");
    });

    it("sends a card transaction as cardTransactionId", async () => {
      getEntryCandidates.mockResolvedValue(candidates);
      reconcile.mockResolvedValue([{ entryId: "e1", success: true }]);
      const element = await mount();
      await open(element);
      const radios = element.shadowRoot.querySelectorAll(".candidate-radio");
      radios[1].dispatchEvent(new CustomEvent("change"));
      await flushPromises();
      expect(
        element.shadowRoot.querySelector(".candidate-selected").textContent
      ).toContain("ENEL CARTAO");
      element.shadowRoot.querySelector(".realize-confirm").click();
      await flushPromises();
      expect(pairOf()).toEqual([{ entryId: "e1", cardTransactionId: "c1" }]);
    });

    it("shows the outcome message and keeps the popup when the reconciliation fails", async () => {
      getEntryCandidates.mockResolvedValue(candidates);
      reconcile.mockResolvedValue([
        { entryId: "e1", success: false, message: "Transação já conciliada." }
      ]);
      const element = await mount();
      await open(element);
      element.shadowRoot.querySelector(".realize-confirm").click();
      await flushPromises();
      expect(text(element, ".realize-error")).toContain(
        "Transação já conciliada."
      );
      expect(element.shadowRoot.querySelector(".realize-modal")).not.toBeNull();
    });

    it("shows a thrown error of the reconciliation", async () => {
      getEntryCandidates.mockResolvedValue(candidates);
      reconcile.mockRejectedValue({ body: { message: "Sem acesso." } });
      const element = await mount();
      await open(element);
      element.shadowRoot.querySelector(".realize-confirm").click();
      await flushPromises();
      expect(text(element, ".realize-error")).toContain("Sem acesso.");
    });

    it("opens straight on the manual tab when there is no candidate", async () => {
      getEntryCandidates.mockResolvedValue([]);
      const element = await mount();
      await open(element);
      const root = element.shadowRoot;
      expect(root.querySelector(".manual-panel")).not.toBeNull();
      expect(root.querySelector(".realize-date").value).toBe("2026-10-05");
      expect(text(element, ".tab-pluggy")).toContain(
        "nenhuma transação encontrada"
      );
      root.querySelector(".tab-pluggy").click();
      await flushPromises();
      expect(text(element, ".candidates-empty")).toContain(
        "Nenhuma transação encontrada"
      );
    });

    it("falls back to the manual tab with a message when the search fails", async () => {
      getEntryCandidates.mockRejectedValue({ body: { message: "Falhou." } });
      const element = await mount();
      await open(element);
      expect(element.shadowRoot.querySelector(".manual-panel")).not.toBeNull();
      expect(text(element, ".realize-error")).toContain("Falhou.");
    });

    it("lets the user switch to the manual tab and saves as before", async () => {
      getEntryCandidates.mockResolvedValue(candidates);
      updateRecord.mockResolvedValue({});
      const element = await mount();
      await open(element);
      element.shadowRoot.querySelector(".open-manual").click();
      await flushPromises();
      expect(text(element, ".manual-effect")).toContain("Sem conciliação");
      expect(element.shadowRoot.querySelector(".realize-confirm").label).toBe(
        "Confirmar pagamento"
      );
      element.shadowRoot.querySelector(".realize-confirm").click();
      await flushPromises();
      expect(reconcile).not.toHaveBeenCalled();
      expect(updateRecord).toHaveBeenCalledWith({
        fields: {
          Id: "e1",
          AXF_ENT_PKL_Status__c: "Realized",
          AXF_ENT_DAT_PaymentDate__c: "2026-10-05",
          AXF_ENT_NUM_RealizedAmountBRL__c: 1500
        }
      });
    });

    it("points to the Conciliação tab and closes the popup", async () => {
      getEntryCandidates.mockResolvedValue(candidates);
      const element = await mount();
      await open(element);
      element.shadowRoot.querySelector(".open-reconciliation").click();
      await flushPromises();
      expect(element.shadowRoot.querySelector(".realize-modal")).toBeNull();
      expect(mockNavigate).toHaveBeenCalledWith({
        type: "standard__navItemPage",
        attributes: { apiName: "AXF_CT_Reconciliation" }
      });
    });

    it("reconciles once on a double click", async () => {
      let resolveReconcile;
      reconcile.mockImplementationOnce(
        () => new Promise((resolve) => (resolveReconcile = resolve))
      );
      getEntryCandidates.mockResolvedValue(candidates);
      const element = await mount();
      await open(element);
      const confirm = element.shadowRoot.querySelector(".realize-confirm");
      confirm.click();
      confirm.click();
      await flushPromises();
      expect(reconcile).toHaveBeenCalledTimes(1);
      resolveReconcile([{ entryId: "e1", success: true }]);
      await flushPromises();
      expect(element.shadowRoot.querySelector(".realize-modal")).toBeNull();
    });

    it("ignores a late candidates response after the popup was closed", async () => {
      let resolveCandidates;
      getEntryCandidates.mockImplementationOnce(
        () => new Promise((resolve) => (resolveCandidates = resolve))
      );
      const element = await mount();
      await open(element);
      element.shadowRoot.querySelector(".realize-cancel").click();
      await flushPromises();
      resolveCandidates(candidates);
      await flushPromises();
      expect(element.shadowRoot.querySelector(".realize-modal")).toBeNull();
    });
  });
});
