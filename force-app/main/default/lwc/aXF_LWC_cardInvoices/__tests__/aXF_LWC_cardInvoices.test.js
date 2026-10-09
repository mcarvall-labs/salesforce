import { createElement } from "lwc";
import AXF_LWC_cardInvoices from "c/aXF_LWC_cardInvoices";
import getInvoices from "@salesforce/apex/AXF_CLS_CTRL_CardInvoices.getInvoices";
import getLines from "@salesforce/apex/AXF_CLS_CTRL_CardInvoices.getLines";
import { publish } from "lightning/messageService";
import syncPeriod from "@salesforce/apex/AXF_CLS_CTRL_PluggySync.syncPeriod";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_CardInvoices.getInvoices",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_CardInvoices.getLines",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_PluggySync.syncPeriod",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const MONTHS = [
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
const label = (value) => {
  const [year, month] = value.split("-");
  return `${MONTHS[Number(month) - 1]}/${year}`;
};

const flushPromises = () =>
  Array.from({ length: 10 }).reduce(
    (chain) => chain.then(() => undefined),
    Promise.resolve()
  );

const period = (offset) => {
  const d = new Date();
  d.setDate(1);
  d.setMonth(d.getMonth() + offset);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
};

const makeInvoice = (id, offset) => ({
  id,
  period: period(offset),
  dueDate: "2026-10-05",
  totalAmount: 100,
  status: "Open",
  currencyCode: "BRL"
});

const previous = makeInvoice("a02000000000001", -1);
const current = makeInvoice("a02000000000002", 0);
const next = makeInvoice("a02000000000003", 1);

const line = (id, description) => ({
  id,
  transactionDate: "2026-09-10",
  description,
  amount: -50,
  amountBRL: -260,
  originalCurrency: "USD",
  installment: "1/3"
});

async function setup() {
  const element = createElement("c-a-x-f-l-w-c-card-invoices", {
    is: AXF_LWC_cardInvoices
  });
  element.recordId = "a03000000000001";
  document.body.appendChild(element);
  await flushPromises();
  return element;
}

const periodOf = (element) =>
  element.shadowRoot.querySelector(".invoice-period").textContent;

describe("c-a-x-f-l-w-c-card-invoices", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.resetAllMocks();
  });

  it("selects the invoice of the current month and loads its transactions", async () => {
    getInvoices.mockResolvedValue([next, current, previous]);
    getLines.mockResolvedValue([line("a04000000000001", "Loja")]);
    const element = await setup();
    expect(getInvoices).toHaveBeenCalledWith({
      creditCardId: "a03000000000001"
    });
    expect(periodOf(element).trim()).toBe(label(current.period));
    expect(element.shadowRoot.querySelector(".invoice-status").label).toBe(
      "Aberta"
    );
    expect(publish).toHaveBeenLastCalledWith(
      undefined,
      expect.anything(),
      expect.objectContaining({ period: current.period, statusLabel: "Aberta" })
    );
    expect(getLines).toHaveBeenCalledWith({ invoiceId: current.id });
    expect(element.shadowRoot.querySelector("tbody a").textContent).toBe(
      "Loja"
    );
  });

  it("navigates to the previous and next invoices loading their transactions", async () => {
    getInvoices.mockResolvedValue([previous, current, next]);
    getLines.mockImplementation(({ invoiceId }) =>
      Promise.resolve([line("a04" + invoiceId, "Linha " + invoiceId)])
    );
    const element = await setup();
    element.shadowRoot.querySelector(".invoice-previous").click();
    await flushPromises();
    expect(periodOf(element).trim()).toBe(label(previous.period));
    expect(getLines).toHaveBeenLastCalledWith({ invoiceId: previous.id });
    expect(element.shadowRoot.querySelector(".invoice-previous").disabled).toBe(
      true
    );
    element.shadowRoot.querySelector(".invoice-next").click();
    await flushPromises();
    element.shadowRoot.querySelector(".invoice-next").click();
    await flushPromises();
    expect(periodOf(element).trim()).toBe(label(next.period));
    expect(getLines).toHaveBeenLastCalledWith({ invoiceId: next.id });
    expect(element.shadowRoot.querySelector(".invoice-next").disabled).toBe(
      true
    );
  });

  it("falls back to the latest past invoice when the current month has none", async () => {
    getInvoices.mockResolvedValue([
      makeInvoice("a02000000000009", -3),
      previous
    ]);
    getLines.mockResolvedValue([]);
    const element = await setup();
    expect(periodOf(element).trim()).toBe(label(previous.period));
    expect(element.shadowRoot.textContent).toContain("Nenhuma transação");
  });

  it("shows an empty message without invoices", async () => {
    getInvoices.mockResolvedValue([]);
    const element = await setup();
    expect(element.shadowRoot.textContent).toContain("Nenhuma fatura");
    expect(getLines).not.toHaveBeenCalled();
  });

  it("shows an error when loading fails", async () => {
    getInvoices.mockRejectedValue(new Error("x"));
    const element = await setup();
    expect(element.shadowRoot.querySelector('[role="alert"]').textContent).toBe(
      "Não foi possível carregar as faturas."
    );
  });

  it("shows an error when the transactions of an invoice fail to load", async () => {
    getInvoices.mockResolvedValue([current]);
    getLines.mockRejectedValue(new Error("x"));
    const element = await setup();
    expect(element.shadowRoot.querySelector('[role="alert"]').textContent).toBe(
      "Não foi possível carregar as transações."
    );
    expect(element.shadowRoot.querySelector("tbody")).toBeNull();
  });
  it("syncs the selected invoice window with Pluggy and reloads", async () => {
    getInvoices.mockResolvedValue([current]);
    getLines.mockResolvedValue([]);
    syncPeriod.mockResolvedValue({ success: true, transactions: 4 });
    const element = await setup();
    element.shadowRoot.querySelector(".sync-button").click();
    await flushPromises();
    const [year, month] = current.period.split("-").map(Number);
    const previousMonth = new Date(year, month - 2, 1);
    expect(syncPeriod).toHaveBeenCalledWith({
      recordId: "a03000000000001",
      periodStart: `${previousMonth.getFullYear()}-${String(previousMonth.getMonth() + 1).padStart(2, "0")}-01`,
      periodEnd: `${year}-${String(month).padStart(2, "0")}-${new Date(year, month, 0).getDate()}`
    });
    expect(getInvoices).toHaveBeenCalledTimes(2);
  });

  it("does not reload when the sync fails", async () => {
    getInvoices.mockResolvedValue([current]);
    getLines.mockResolvedValue([]);
    syncPeriod.mockResolvedValue({ success: false, message: "Pluggy fora" });
    const element = await setup();
    element.shadowRoot.querySelector(".sync-button").click();
    await flushPromises();
    expect(getInvoices).toHaveBeenCalledTimes(1);
  });
  it("shows projected invoices from their own lines without loading them", async () => {
    getInvoices.mockResolvedValue([
      {
        ...next,
        id: null,
        status: "Projected",
        projected: true,
        lines: [
          {
            description: "KABUM",
            amount: -100,
            amountBRL: -100,
            installment: "4/5",
            projected: true
          }
        ]
      },
      current
    ]);
    getLines.mockResolvedValue([]);
    const element = await setup();
    element.shadowRoot.querySelector(".invoice-next").click();
    await flushPromises();
    expect(element.shadowRoot.querySelector(".invoice-status").label).toBe(
      "Prevista"
    );
    expect(getLines).toHaveBeenCalledTimes(1);
    expect(element.shadowRoot.querySelector(".projected-note")).not.toBeNull();
    expect(element.shadowRoot.querySelector("tbody a")).toBeNull();
    expect(element.shadowRoot.querySelector("tbody").textContent).toContain(
      "KABUM"
    );
  });
});
