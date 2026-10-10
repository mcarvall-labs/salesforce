import { createElement } from "lwc";
import AXF_LWC_dashboard from "c/aXF_LWC_dashboard";
import getHolders from "@salesforce/apex/AXF_CLS_CTRL_Dashboard.getHolders";
import getSummary from "@salesforce/apex/AXF_CLS_CTRL_Dashboard.getSummary";
import getBudget from "@salesforce/apex/AXF_CLS_CTRL_Dashboard.getBudget";

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
  cardForecast: 65,
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
    getBudget.mockResolvedValue({ ...budget, cardForecast: 0 });
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

  it("shows a goals error without hiding the indicators", async () => {
    getBudget.mockRejectedValue({ body: { message: "Sem acesso às metas" } });
    const element = await mount();
    expect(text(element, ".budget-error")).toContain("Sem acesso às metas");
    expect(element.shadowRoot.querySelector(".kpis")).not.toBeNull();
    expect(element.shadowRoot.querySelector(".budget")).toBeNull();
  });
});
