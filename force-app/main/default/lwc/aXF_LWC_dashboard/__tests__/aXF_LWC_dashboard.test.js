import { createElement } from "lwc";
import AXF_LWC_dashboard from "c/aXF_LWC_dashboard";
import getHolders from "@salesforce/apex/AXF_CLS_CTRL_Dashboard.getHolders";
import getSummary from "@salesforce/apex/AXF_CLS_CTRL_Dashboard.getSummary";

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
  cardForecast: 65,
  projectedBalance: 1167,
  projectedBalanceWithCard: -50
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
    expect(text(element, ".kpi-overdue")).toContain("30,00");
    expect(text(element, ".kpi-overdue")).toContain("2 em aberto");
    expect(text(element, ".kpi-due-soon")).toContain("200,00");
    expect(text(element, ".kpi-flow")).toContain("311,00");
    expect(text(element, ".kpi-flow")).toContain("120,00");
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
    getSummary.mockResolvedValueOnce({ ...summary, income: 999 });
    element.shadowRoot
      .querySelector(".holder-filter")
      .dispatchEvent(new CustomEvent("change", { detail: { value: "001A" } }));
    await flushPromises();
    resolveFirst({ ...summary, income: 1 });
    await flushPromises();
    expect(text(element, ".kpi-flow")).toContain("999,00");
  });
});
