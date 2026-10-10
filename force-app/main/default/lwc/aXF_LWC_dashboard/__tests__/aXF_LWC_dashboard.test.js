import { createElement } from "lwc";
import AXF_LWC_dashboard from "c/aXF_LWC_dashboard";
import getHolders from "@salesforce/apex/AXF_CLS_CTRL_Dashboard.getHolders";
import getSummary from "@salesforce/apex/AXF_CLS_CTRL_Dashboard.getSummary";
import getBudget from "@salesforce/apex/AXF_CLS_CTRL_Dashboard.getBudget";
import getEntries from "@salesforce/apex/AXF_CLS_CTRL_Dashboard.getEntries";
import getPending from "@salesforce/apex/AXF_CLS_CTRL_Dashboard.getPending";
import getSources from "@salesforce/apex/AXF_CLS_CTRL_Dashboard.getSources";

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
  projectedBalanceWithCard: -50
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
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("loads the current month for all holders and shows the four indicators", async () => {
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
    expect(rows[0].textContent).toContain("Vencido");
    expect(rows[0].textContent.replace(/\s+/g, " ")).toContain("-R$ 1.500,00");
    expect(rows[0].querySelector(".out")).not.toBeNull();
    expect(rows[1].textContent).toContain("Realizado");
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

  it("opens the new entry form with the type and the filtered holder", async () => {
    const element = await mount();
    element.shadowRoot.querySelector(".new-expense").click();
    expect(mockNavigate).toHaveBeenLastCalledWith({
      type: "standard__objectPage",
      attributes: { objectApiName: "AXF_OBJ_Entry__c", actionName: "new" },
      state: { defaultFieldValues: "AXF_ENT_PKL_Type__c=Expense" }
    });
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
});
