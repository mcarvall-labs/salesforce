import { createElement } from "lwc";
import AXF_LWC_invoiceTransactions from "c/aXF_LWC_invoiceTransactions";
import getInvoice from "@salesforce/apex/AXF_CLS_CTRL_InvoiceTransactions.getInvoice";

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
  "@salesforce/apex/AXF_CLS_CTRL_InvoiceTransactions.getInvoice",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flushPromises = () =>
  Array.from({ length: 10 }).reduce(
    (chain) => chain.then(() => undefined),
    Promise.resolve()
  );

const invoice = {
  id: "i1",
  cardName: "Cartão Teste",
  period: "2026-10",
  closingDate: "2026-10-01",
  dueDate: "2026-10-10",
  totalAmount: 300,
  currencyCode: "BRL",
  status: "Open",
  lines: [
    {
      id: "t1",
      transactionDate: "2026-09-12",
      description: "Notebook",
      amount: -200,
      amountBRL: -200,
      originalCurrency: "BRL",
      installment: "3/10"
    },
    {
      id: "t2",
      transactionDate: "2026-09-15",
      description: "Streaming US$ 20",
      amount: -20,
      amountBRL: -100,
      originalCurrency: "USD"
    }
  ]
};

async function setup() {
  const element = createElement("c-a-x-f-l-w-c-invoice-transactions", {
    is: AXF_LWC_invoiceTransactions
  });
  element.recordId = "e1";
  document.body.appendChild(element);
  await flushPromises();
  return element;
}

const rows = (element) =>
  element.shadowRoot.querySelectorAll("table.lines tbody tr");

describe("c-a-x-f-l-w-c-invoice-transactions", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.resetAllMocks();
  });

  it("shows the invoice data and one row per transaction", async () => {
    getInvoice.mockResolvedValue(invoice);
    const element = await setup();
    expect(getInvoice).toHaveBeenCalledWith({ recordId: "e1" });
    expect(element.shadowRoot.querySelector(".card-name").textContent).toBe(
      "Cartão Teste"
    );
    expect(element.shadowRoot.querySelector(".period").textContent).toBe(
      "2026-10"
    );
    expect(element.shadowRoot.querySelector(".status").textContent).toBe(
      "Aberta"
    );
    expect(rows(element)).toHaveLength(2);
    expect(element.shadowRoot.querySelector(".no-invoice")).toBeNull();
  });

  it("shows the BRL amount only for purchases in another currency", async () => {
    getInvoice.mockResolvedValue(invoice);
    const element = await setup();
    const cells = Array.from(rows(element)).map(
      (row) => row.querySelectorAll("td")[4].children.length
    );
    expect(cells).toEqual([0, 1]);
  });

  it("links every description to its transaction", async () => {
    getInvoice.mockResolvedValue(invoice);
    const element = await setup();
    const links = element.shadowRoot.querySelectorAll("table.lines a");
    expect(links).toHaveLength(2);
    expect(links[0].dataset.id).toBe("t1");
    expect(links[1].dataset.id).toBe("t2");
  });

  it("explains when the entry is not an invoice entry", async () => {
    getInvoice.mockResolvedValue(null);
    const element = await setup();
    expect(element.shadowRoot.querySelector(".no-invoice")).not.toBeNull();
    expect(element.shadowRoot.querySelector("table.lines")).toBeNull();
  });

  it("shows an empty message for an invoice without transactions", async () => {
    getInvoice.mockResolvedValue({ ...invoice, lines: [] });
    const element = await setup();
    expect(element.shadowRoot.textContent).toContain("Nenhuma transação");
  });

  it("shows the error message and no invoice hint", async () => {
    getInvoice.mockRejectedValue({ body: { message: "Sem acesso à fatura." } });
    const element = await setup();
    expect(element.shadowRoot.querySelector("[role=alert]").textContent).toBe(
      "Sem acesso à fatura."
    );
    expect(element.shadowRoot.querySelector(".no-invoice")).toBeNull();
  });

  it("shows the closing date, due date and the total in BRL", async () => {
    getInvoice.mockResolvedValue(invoice);
    const element = await setup();
    const dates = element.shadowRoot.querySelectorAll(
      "dl.invoice-data lightning-formatted-date-time"
    );
    expect(dates[0].value).toBe("2026-10-01");
    expect(dates[1].value).toBe("2026-10-10");
    const total = element.shadowRoot.querySelector(
      "dl.invoice-data lightning-formatted-number"
    );
    expect(total.value).toBe(300);
    expect(total.currencyCode).toBe("BRL");
  });

  it("labels the closed and paid statuses", async () => {
    getInvoice.mockResolvedValue({ ...invoice, status: "Closed" });
    let element = await setup();
    expect(element.shadowRoot.querySelector(".status").textContent).toBe(
      "Fechada"
    );
    document.body.removeChild(element);
    getInvoice.mockResolvedValue({ ...invoice, status: "Paid" });
    element = await setup();
    expect(element.shadowRoot.querySelector(".status").textContent).toBe(
      "Paga"
    );
  });

  it("navigates to the clicked transaction", async () => {
    getInvoice.mockResolvedValue(invoice);
    const element = await setup();
    element.shadowRoot.querySelectorAll("table.lines a")[1].click();
    const pageReference = mockNavigate.mock.calls[0][0];
    expect(pageReference.type).toBe("standard__recordPage");
    expect(pageReference.attributes.recordId).toBe("t2");
    expect(pageReference.attributes.actionName).toBe("view");
  });

  it("reloads when the record changes", async () => {
    getInvoice.mockResolvedValue(invoice);
    const element = await setup();
    getInvoice.mockResolvedValue({ ...invoice, period: "2026-11" });
    element.recordId = "e2";
    await flushPromises();
    expect(getInvoice).toHaveBeenLastCalledWith({ recordId: "e2" });
    expect(element.shadowRoot.querySelector(".period").textContent).toBe(
      "2026-11"
    );
  });

  it("hides the whole card for a non-invoice entry when asked to", async () => {
    getInvoice.mockResolvedValue(null);
    const element = createElement("c-a-x-f-l-w-c-invoice-transactions", {
      is: AXF_LWC_invoiceTransactions
    });
    element.recordId = "e1";
    element.hideWhenNotInvoice = true;
    document.body.appendChild(element);
    await flushPromises();
    expect(element.shadowRoot.querySelector("lightning-card")).toBeNull();
  });

  it("keeps the card for an invoice entry even when set to hide", async () => {
    getInvoice.mockResolvedValue(invoice);
    const element = createElement("c-a-x-f-l-w-c-invoice-transactions", {
      is: AXF_LWC_invoiceTransactions
    });
    element.recordId = "e1";
    element.hideWhenNotInvoice = true;
    document.body.appendChild(element);
    await flushPromises();
    expect(element.shadowRoot.querySelector("lightning-card")).not.toBeNull();
  });

  it("does not show the card while loading when it is set to hide", async () => {
    let release;
    getInvoice.mockImplementation(
      () => new Promise((resolve) => (release = () => resolve(null)))
    );
    const element = createElement("c-a-x-f-l-w-c-invoice-transactions", {
      is: AXF_LWC_invoiceTransactions
    });
    element.recordId = "e1";
    element.hideWhenNotInvoice = true;
    document.body.appendChild(element);
    await flushPromises();
    expect(element.shadowRoot.querySelector("lightning-card")).toBeNull();
    release();
    await flushPromises();
    expect(element.shadowRoot.querySelector("lightning-card")).toBeNull();
  });
});
