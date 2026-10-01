import { createElement } from "lwc";
import AXF_LWC_bankStatement from "c/aXF_LWC_bankStatement";
import getStatement from "@salesforce/apex/AXF_CLS_CTRL_BankStatement.getStatement";

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

  it("reloads the statement when the month changes", async () => {
    getStatement.mockResolvedValue(statement);
    const element = await setup();
    element.shadowRoot
      .querySelector("lightning-combobox")
      .dispatchEvent(
        new CustomEvent("change", { detail: { value: "2026-09" } })
      );
    await flushPromises();
    expect(getStatement).toHaveBeenLastCalledWith({
      bankAccountId: "a00000000000001",
      month: "2026-09"
    });
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
});
