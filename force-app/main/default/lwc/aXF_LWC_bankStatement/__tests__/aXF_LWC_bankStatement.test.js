import { createElement } from "lwc";
import AXF_LWC_bankStatement from "c/aXF_LWC_bankStatement";
import getStatement from "@salesforce/apex/AXF_CLS_CTRL_BankStatement.getStatement";

import syncPeriod from "@salesforce/apex/AXF_CLS_CTRL_PluggySync.syncPeriod";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_PluggySync.syncPeriod",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_BankStatement.getStatement",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flushPromises = () =>
  Array.from({ length: 10 }).reduce(
    (chain) => chain.then(() => undefined),
    Promise.resolve()
  );

const statement = {
  balance: 1000,
  currencyCode: "BRL",
  month: "2026-10",
  months: ["2026-10", "2026-09"],
  rows: [
    {
      id: "a01000000000001",
      transactionDate: "2026-10-02",
      description: "Mercado",
      amount: -200,
      runningBalance: 1000
    }
  ]
};

async function setup() {
  const element = createElement("c-a-x-f-l-w-c-bank-statement", {
    is: AXF_LWC_bankStatement
  });
  element.recordId = "a00000000000001";
  document.body.appendChild(element);
  await flushPromises();
  return element;
}

describe("c-a-x-f-l-w-c-bank-statement", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("loads the latest month and shows a row per transaction", async () => {
    getStatement.mockResolvedValue(statement);
    const element = await setup();
    expect(getStatement).toHaveBeenCalledWith({
      bankAccountId: "a00000000000001",
      month: null
    });
    expect(element.shadowRoot.querySelectorAll("tbody tr")).toHaveLength(1);
    expect(element.shadowRoot.querySelector("tbody a").textContent).toBe(
      "Mercado"
    );
  });

  it("shows an empty message without transactions", async () => {
    getStatement.mockResolvedValue({ ...statement, months: [], rows: [] });
    const element = await setup();
    expect(element.shadowRoot.querySelector("table")).toBeNull();
    expect(element.shadowRoot.textContent).toContain("Nenhuma transação");
  });

  it("shows an error when loading fails", async () => {
    getStatement.mockRejectedValue(new Error("x"));
    const element = await setup();
    expect(element.shadowRoot.querySelector('[role="alert"]').textContent).toBe(
      "Não foi possível carregar o extrato."
    );
  });

  it("warns when the statement was truncated", async () => {
    getStatement.mockResolvedValue({ ...statement, truncated: true });
    const element = await setup();
    expect(element.shadowRoot.querySelector('[role="status"]')).not.toBeNull();
  });
  it("navigates to the older month with the arrows", async () => {
    getStatement.mockResolvedValue(statement);
    const element = await setup();
    expect(element.shadowRoot.querySelector(".month-label").textContent).toBe(
      "Outubro/2026"
    );
    expect(element.shadowRoot.querySelector(".month-next").disabled).toBe(true);
    element.shadowRoot.querySelector(".month-previous").click();
    expect(getStatement).toHaveBeenLastCalledWith({
      bankAccountId: "a00000000000001",
      month: "2026-09"
    });
  });

  it("syncs the displayed month with Pluggy and reloads it", async () => {
    getStatement.mockResolvedValue(statement);
    syncPeriod.mockResolvedValue({ success: true, transactions: 2 });
    const element = await setup();
    element.shadowRoot.querySelector(".sync-button").click();
    await flushPromises();
    expect(syncPeriod).toHaveBeenCalledWith({
      recordId: "a00000000000001",
      periodStart: "2026-10-01",
      periodEnd: "2026-10-31"
    });
    expect(getStatement).toHaveBeenLastCalledWith({
      bankAccountId: "a00000000000001",
      month: "2026-10"
    });
    expect(getStatement).toHaveBeenCalledTimes(2);
  });

  it("keeps the statement when the sync fails", async () => {
    getStatement.mockResolvedValue(statement);
    syncPeriod.mockResolvedValue({ success: false, message: "Pluggy fora" });
    const element = await setup();
    element.shadowRoot.querySelector(".sync-button").click();
    await flushPromises();
    expect(getStatement).toHaveBeenCalledTimes(1);
  });
});
