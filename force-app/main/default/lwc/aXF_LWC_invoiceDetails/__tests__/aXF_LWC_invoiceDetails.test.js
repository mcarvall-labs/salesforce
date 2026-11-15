import { createElement } from "lwc";
import AXF_LWC_invoiceDetails from "c/aXF_LWC_invoiceDetails";
import { subscribe } from "lightning/messageService";

const flushPromises = () =>
  Array.from({ length: 10 }).reduce(
    (chain) => chain.then(() => undefined),
    Promise.resolve()
  );

describe("c-a-x-f-l-w-c-invoice-details", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("starts empty and shows the invoice published by the invoices component", async () => {
    const element = createElement("c-a-x-f-l-w-c-invoice-details", {
      is: AXF_LWC_invoiceDetails
    });
    let handler;
    subscribe.mockImplementation((context, channel, callback) => {
      handler = callback;
      return {};
    });
    document.body.appendChild(element);
    expect(element.shadowRoot.querySelector(".invoice-due")).toBeNull();
    handler({
      period: "2026-09",
      dueDate: "2026-09-27",
      totalAmount: 1880,
      currencyCode: "BRL",
      statusLabel: "Aberta"
    });
    await flushPromises();
    expect(
      element.shadowRoot.querySelector(".invoice-period").textContent.trim()
    ).toBe("2026-09");
    expect(element.shadowRoot.querySelector(".invoice-due")).not.toBeNull();
  });
});
