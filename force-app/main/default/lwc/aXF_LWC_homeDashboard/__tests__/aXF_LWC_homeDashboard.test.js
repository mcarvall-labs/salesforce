import { createElement } from "lwc";
import HomeDashboard from "c/aXF_LWC_homeDashboard";
import getDashboard from "@salesforce/apex/AXF_CLS_CTRL_HomeDashboard.getDashboard";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_HomeDashboard.getDashboard",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = async () => {
  for (let i = 0; i < 6; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};

const HOLDER = "001000000000001AAA";

function entry(id, description, category, status = "OPEN") {
  return {
    recordId: id,
    description,
    category,
    holderLabel: "Michel",
    entryDate: "2026-09-10",
    amount: 100,
    realized: 0,
    residual: 100,
    currencyIso: "BRL",
    status
  };
}

function dashboard(overrides = {}) {
  return {
    holders: [{ holderId: HOLDER, label: "Michel" }],
    holderId: null,
    monthStart: "2026-09-01",
    currencyIso: "BRL",
    mixedCurrency: false,
    truncated: false,
    plannedRevenue: 1000,
    realizedRevenue: 0,
    plannedExpense: 350,
    realizedExpense: 0,
    plannedBalance: 650,
    realizedBalance: 0,
    overdueExpenses: [entry("a01", "Internet", "Internet/TV")],
    overdueExpenseTotal: 100,
    overdueRevenues: [],
    overdueRevenueTotal: 0,
    monthExpenses: [
      entry("a02", "Luz", "Energia"),
      entry("a03", "Mercado", "Alimentação", "SETTLED")
    ],
    monthRevenues: [entry("a04", "Salário", "Salário")],
    accounts: [
      {
        bankAccountId: "a05",
        name: "MICHEL - ITAU",
        balance: 500,
        currencyIso: "BRL"
      }
    ],
    accountsBalance: 500,
    monthSurplus: 650,
    projectedBalance: 1150,
    ...overrides
  };
}

function mount() {
  const element = createElement("c-a-x-f-l-w-c-home-dashboard", {
    is: HomeDashboard
  });
  document.body.appendChild(element);
  return element;
}

describe("c-a-x-f-l-w-c-home-dashboard", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("renders every panel for all holders", async () => {
    getDashboard.mockResolvedValue(dashboard());
    const element = mount();
    await flush();
    expect(getDashboard).toHaveBeenCalledWith({ holderId: null });
    const root = element.shadowRoot;
    expect(root.querySelector("[data-balance]")).not.toBeNull();
    expect(root.querySelectorAll("[data-tab]").length).toBe(2);
    expect(root.querySelector("[data-overdue-expenses]").textContent).toContain(
      "Internet"
    );
    expect(root.querySelector("[data-no-overdue-revenues]")).not.toBeNull();
    expect(root.querySelectorAll("[data-expense-row]").length).toBe(2);
    expect(root.querySelector("[data-projected]")).not.toBeNull();
  });

  it("applies the holder filter to the whole dashboard", async () => {
    getDashboard.mockResolvedValue(dashboard());
    const element = mount();
    await flush();
    getDashboard.mockResolvedValue(dashboard({ holderId: HOLDER }));
    element.shadowRoot.querySelector(`[data-id="${HOLDER}"]`).click();
    await flush();
    expect(getDashboard).toHaveBeenLastCalledWith({ holderId: HOLDER });
    expect(getDashboard).toHaveBeenCalledTimes(2);
  });

  it("filters the month's expenses by category", async () => {
    getDashboard.mockResolvedValue(dashboard());
    const element = mount();
    await flush();
    const input = element.shadowRoot.querySelector("[data-expense-category]");
    input.value = "ener";
    input.dispatchEvent(new CustomEvent("change"));
    await flush();
    const rows = element.shadowRoot.querySelectorAll("[data-expense-row]");
    expect(rows.length).toBe(1);
    expect(rows[0].textContent).toContain("Luz");
  });

  it("shows a sanitized error", async () => {
    getDashboard.mockRejectedValue({ body: { message: "NOT_ACCESSIBLE" } });
    const element = mount();
    await flush();
    const error = element.shadowRoot.querySelector("[data-error]");
    expect(error).not.toBeNull();
    expect(element.shadowRoot.querySelector("[data-balance]")).toBeNull();
  });
});
