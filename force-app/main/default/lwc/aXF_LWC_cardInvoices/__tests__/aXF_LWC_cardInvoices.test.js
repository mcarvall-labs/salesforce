import { createElement } from "lwc";
import AXF_LWC_cardInvoices from "c/aXF_LWC_cardInvoices";
import getInvoices from "@salesforce/apex/AXF_CLS_CTRL_CardInvoices.getInvoices";
import getLines from "@salesforce/apex/AXF_CLS_CTRL_CardInvoices.getLines";

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

const flushPromises = () =>
  Array.from({ length: 10 }).reduce(
    (chain) => chain.then(() => undefined),
    Promise.resolve()
  );

const invoice = {
  id: "a02000000000001",
  period: "2026-10",
  dueDate: "2026-10-05",
  totalAmount: 100,
  status: "Open",
  currencyCode: "BRL"
};

async function setup() {
  const element = createElement("c-a-x-f-l-w-c-card-invoices", {
    is: AXF_LWC_cardInvoices
  });
  element.recordId = "a03000000000001";
  document.body.appendChild(element);
  await flushPromises();
  return element;
}

describe("c-a-x-f-l-w-c-card-invoices", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("lists the invoices of the card with the translated status", async () => {
    getInvoices.mockResolvedValue([invoice]);
    const element = await setup();
    expect(getInvoices).toHaveBeenCalledWith({
      creditCardId: "a03000000000001"
    });
    expect(element.shadowRoot.textContent).toContain("2026-10");
    expect(element.shadowRoot.textContent).toContain("Aberta");
  });

  it("expands an invoice to show its transactions", async () => {
    getInvoices.mockResolvedValue([invoice]);
    getLines.mockResolvedValue([
      {
        id: "a04000000000001",
        transactionDate: "2026-09-10",
        description: "Loja",
        amount: -50,
        amountBRL: -260,
        originalCurrency: "USD",
        installment: "1/3"
      }
    ]);
    const element = await setup();
    element.shadowRoot.querySelector(".invoice-toggle").click();
    await flushPromises();
    expect(getLines).toHaveBeenCalledWith({ invoiceId: "a02000000000001" });
    expect(element.shadowRoot.querySelectorAll("tbody tr")).toHaveLength(1);
    expect(element.shadowRoot.querySelector("tbody a").textContent).toBe(
      "Loja"
    );
  });

  it("shows an empty message without invoices", async () => {
    getInvoices.mockResolvedValue([]);
    const element = await setup();
    expect(element.shadowRoot.textContent).toContain("Nenhuma fatura");
  });

  it("shows an error when loading fails", async () => {
    getInvoices.mockRejectedValue(new Error("x"));
    const element = await setup();
    expect(element.shadowRoot.querySelector('[role="alert"]').textContent).toBe(
      "Não foi possível carregar as faturas."
    );
  });
});
