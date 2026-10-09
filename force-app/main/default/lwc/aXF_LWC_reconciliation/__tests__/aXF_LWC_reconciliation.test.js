import { createElement } from "lwc";
import AXF_LWC_reconciliation from "c/aXF_LWC_reconciliation";
import getHolders from "@salesforce/apex/AXF_CLS_CTRL_Reconciliation.getHolders";
import getData from "@salesforce/apex/AXF_CLS_CTRL_Reconciliation.getData";
import reconcile from "@salesforce/apex/AXF_CLS_CTRL_Reconciliation.reconcile";
import unreconcile from "@salesforce/apex/AXF_CLS_CTRL_Reconciliation.unreconcile";
import ignoreTransactions from "@salesforce/apex/AXF_CLS_CTRL_Reconciliation.ignoreTransactions";
import createEntries from "@salesforce/apex/AXF_CLS_CTRL_Reconciliation.createEntries";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Reconciliation.getHolders",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Reconciliation.getData",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Reconciliation.reconcile",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Reconciliation.unreconcile",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Reconciliation.ignoreTransactions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Reconciliation.createEntries",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flushPromises = () =>
  Array.from({ length: 10 }).reduce(
    (chain) => chain.then(() => undefined),
    Promise.resolve()
  );

const data = {
  sources: [
    { id: "a1", name: "Conta", kind: "account" },
    { id: "c1", name: "Cartão", kind: "card" }
  ],
  entries: [
    {
      id: "e1",
      name: "Conta de luz",
      dueDate: "2026-10-10",
      amount: 100,
      currencyCode: "BRL",
      type: "Expense"
    },
    {
      id: "e2",
      name: "Notebook",
      dueDate: "2026-10-12",
      amount: 50,
      currencyCode: "BRL",
      type: "Expense",
      cardId: "c1"
    }
  ],
  transactions: [
    {
      id: "t1",
      source: "account",
      transactionDate: "2026-10-10",
      description: "Pagamento luz",
      amount: -100,
      currencyCode: "BRL",
      sourceId: "a1"
    },
    {
      id: "t2",
      source: "card",
      transactionDate: "2026-10-12",
      description: "NOTEBOOK",
      amount: -50,
      currencyCode: "BRL",
      sourceId: "c1"
    }
  ],
  suggestions: [
    { entryId: "e1", bankTransactionId: "t1", cardTransactionId: null }
  ],
  lastReconciledEntryId: "e9"
};

async function setup() {
  const element = createElement("c-a-x-f-l-w-c-reconciliation", {
    is: AXF_LWC_reconciliation
  });
  document.body.appendChild(element);
  await flushPromises();
  return element;
}

const rows = (element, table) =>
  Array.from(element.shadowRoot.querySelectorAll(`table.${table} tbody tr`));
const button = (element, name) => element.shadowRoot.querySelector(`.${name}`);

describe("c-a-x-f-l-w-c-reconciliation", () => {
  beforeEach(() => {
    getHolders.mockResolvedValue([{ id: "h1", name: "Michel" }]);
    getData.mockResolvedValue(data);
    reconcile.mockResolvedValue([{ success: true }]);
    unreconcile.mockResolvedValue([{ success: true }]);
    ignoreTransactions.mockResolvedValue([{ success: true }]);
    createEntries.mockResolvedValue([{ success: true }]);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.resetAllMocks();
  });

  it("loads the first holder and lists entries and transactions", async () => {
    const element = await setup();
    expect(getData).toHaveBeenCalledWith({
      holderId: "h1",
      month: expect.stringMatching(/^\d{4}-\d{2}$/)
    });
    expect(rows(element, "entries")).toHaveLength(2);
    expect(rows(element, "transactions")).toHaveLength(2);
    expect(rows(element, "entries")[0].className).toContain("suggested-row");
    expect(rows(element, "entries")[1].className).not.toContain(
      "suggested-row"
    );
    expect(button(element, "suggest-all").label).toBe(
      "Conciliar sugeridos (1)"
    );
  });

  it("blocks incompatible transactions once an entry is selected and reconciles the pair", async () => {
    const element = await setup();
    expect(button(element, "reconcile").disabled).toBe(true);
    rows(element, "entries")[1].click();
    await flushPromises();
    expect(rows(element, "transactions")[0].className).toContain("blocked-row");
    rows(element, "transactions")[0].click();
    await flushPromises();
    expect(button(element, "reconcile").disabled).toBe(true);
    rows(element, "transactions")[1].click();
    await flushPromises();
    expect(button(element, "reconcile").disabled).toBe(false);
    button(element, "reconcile").click();
    await flushPromises();
    expect(reconcile).toHaveBeenCalledWith({
      pairs: [
        { entryId: "e2", bankTransactionId: null, cardTransactionId: "t2" }
      ]
    });
    expect(getData).toHaveBeenCalledTimes(2);
  });

  it("reconciles every suggestion with one click", async () => {
    const element = await setup();
    button(element, "suggest-all").click();
    await flushPromises();
    expect(reconcile).toHaveBeenCalledWith({
      pairs: [
        { entryId: "e1", bankTransactionId: "t1", cardTransactionId: null }
      ]
    });
  });

  it("ignores and creates an entry from the selected transaction without needing an entry", async () => {
    const element = await setup();
    expect(button(element, "ignore").disabled).toBe(true);
    rows(element, "transactions")[0].click();
    await flushPromises();
    button(element, "ignore").click();
    await flushPromises();
    expect(ignoreTransactions).toHaveBeenCalledWith({
      bankIds: ["t1"],
      cardIds: []
    });
    rows(element, "transactions")[1].click();
    await flushPromises();
    button(element, "create-entry").click();
    await flushPromises();
    expect(createEntries).toHaveBeenCalledWith({
      bankIds: [],
      cardIds: ["t2"]
    });
  });

  it("undoes the last reconciliation", async () => {
    const element = await setup();
    button(element, "undo").click();
    await flushPromises();
    expect(unreconcile).toHaveBeenCalledWith({ entryIds: ["e9"] });
  });

  it("filters the lists by description", async () => {
    const element = await setup();
    const input = element.shadowRoot.querySelector(".text-filter");
    input.dispatchEvent(
      new CustomEvent("change", { detail: { value: "luz" } })
    );
    await flushPromises();
    expect(rows(element, "entries")).toHaveLength(1);
    expect(rows(element, "transactions")).toHaveLength(1);
  });

  it("reloads after an action that reports a failure", async () => {
    reconcile.mockResolvedValue([{ success: false, message: "Já conciliada" }]);
    const element = await setup();
    rows(element, "entries")[0].click();
    rows(element, "transactions")[0].click();
    await flushPromises();
    button(element, "reconcile").click();
    await flushPromises();
    expect(getData).toHaveBeenCalledTimes(2);
  });

  it("explains when there is no holder", async () => {
    getHolders.mockResolvedValue([]);
    const element = await setup();
    expect(element.shadowRoot.textContent).toContain("Nenhum titular");
    expect(getData).not.toHaveBeenCalled();
  });
});
