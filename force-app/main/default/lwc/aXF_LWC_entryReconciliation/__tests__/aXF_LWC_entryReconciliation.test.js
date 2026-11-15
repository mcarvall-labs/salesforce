import { createElement } from "lwc";
import AXF_LWC_entryReconciliation from "c/aXF_LWC_entryReconciliation";
import getEntryReconciliation from "@salesforce/apex/AXF_CLS_CTRL_Reconciliation.getEntryReconciliation";
import unreconcile from "@salesforce/apex/AXF_CLS_CTRL_Reconciliation.unreconcile";
import { notifyRecordUpdateAvailable } from "lightning/uiRecordApi";

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
  "lightning/uiRecordApi",
  () => ({ notifyRecordUpdateAvailable: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Reconciliation.getEntryReconciliation",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Reconciliation.unreconcile",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flushPromises = () =>
  Array.from({ length: 10 }).reduce(
    (chain) => chain.then(() => undefined),
    Promise.resolve()
  );

const reconciled = {
  reconciled: true,
  source: "card",
  transactionId: "t1",
  transactionDate: "2026-10-06",
  description: "Streaming",
  amount: -20,
  amountBRL: -105.5,
  currencyCode: "USD",
  realizedAmountBRL: 105.5,
  canUndo: true
};

async function setup() {
  const element = createElement("c-a-x-f-l-w-c-entry-reconciliation", {
    is: AXF_LWC_entryReconciliation
  });
  element.recordId = "e1";
  document.body.appendChild(element);
  await flushPromises();
  return element;
}

describe("c-a-x-f-l-w-c-entry-reconciliation", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    getEntryReconciliation.mockReset();
    unreconcile.mockReset();
  });

  it("shows the transaction the entry is reconciled with", async () => {
    getEntryReconciliation.mockResolvedValue(reconciled);
    const element = await setup();
    expect(getEntryReconciliation).toHaveBeenCalledWith({ entryId: "e1" });
    expect(element.shadowRoot.querySelector(".source").textContent).toBe(
      "Transação do cartão"
    );
    expect(
      element.shadowRoot.querySelector(".open-transaction").textContent
    ).toBe("Streaming");
    expect(element.shadowRoot.querySelector(".brl")).not.toBeNull();
    expect(element.shadowRoot.querySelector(".undo")).not.toBeNull();
    expect(element.shadowRoot.querySelector(".pending")).toBeNull();
  });

  it("does not repeat the BRL amount for a BRL transaction", async () => {
    getEntryReconciliation.mockResolvedValue({
      ...reconciled,
      source: "account",
      currencyCode: "BRL"
    });
    const element = await setup();
    expect(element.shadowRoot.querySelector(".source").textContent).toBe(
      "Transação da conta"
    );
    expect(element.shadowRoot.querySelector(".brl")).toBeNull();
  });

  it("opens the transaction when its name is clicked", async () => {
    getEntryReconciliation.mockResolvedValue(reconciled);
    const element = await setup();
    element.shadowRoot.querySelector(".open-transaction").click();
    const pageReference = mockNavigate.mock.calls[0][0];
    expect(pageReference.attributes.recordId).toBe("t1");
    expect(pageReference.type).toBe("standard__recordPage");
  });

  it("tells that an unreconciled entry has nothing to undo", async () => {
    getEntryReconciliation.mockResolvedValue({ reconciled: false });
    const element = await setup();
    expect(element.shadowRoot.querySelector(".pending")).not.toBeNull();
    expect(element.shadowRoot.querySelector(".undo")).toBeNull();
  });

  it("undoes the reconciliation, refreshes the record and reloads", async () => {
    getEntryReconciliation
      .mockResolvedValueOnce(reconciled)
      .mockResolvedValueOnce({ reconciled: false });
    unreconcile.mockResolvedValue([{ success: true }]);
    const element = await setup();
    element.shadowRoot.querySelector(".undo").click();
    await flushPromises();
    expect(unreconcile).toHaveBeenCalledWith({ entryIds: ["e1"] });
    expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([
      { recordId: "e1" }
    ]);
    expect(getEntryReconciliation).toHaveBeenCalledTimes(2);
    expect(element.shadowRoot.querySelector(".pending")).not.toBeNull();
  });

  it("keeps the data and re-enables the button when undoing fails", async () => {
    getEntryReconciliation.mockResolvedValue(reconciled);
    unreconcile.mockResolvedValue([{ success: false, message: "Já desfeita" }]);
    const element = await setup();
    element.shadowRoot.querySelector(".undo").click();
    await flushPromises();
    expect(getEntryReconciliation).toHaveBeenCalledTimes(1);
    expect(notifyRecordUpdateAvailable).not.toHaveBeenCalled();
    expect(element.shadowRoot.querySelector(".undo").disabled).toBe(false);
  });

  it("shows an error when the data cannot be loaded", async () => {
    getEntryReconciliation.mockRejectedValue({
      body: { message: "Sem acesso para concluir esta ação." }
    });
    const element = await setup();
    expect(element.shadowRoot.querySelector("[role=alert]").textContent).toBe(
      "Sem acesso para concluir esta ação."
    );
  });

  it("shows the dates and amounts of the transaction and the realized value", async () => {
    getEntryReconciliation.mockResolvedValue(reconciled);
    const element = await setup();
    const dates = element.shadowRoot.querySelectorAll(
      "dl.reconciled lightning-formatted-date-time"
    );
    expect(dates[0].value).toBe("2026-10-06");
    const numbers = element.shadowRoot.querySelectorAll(
      "dl.reconciled lightning-formatted-number"
    );
    expect(numbers[0].value).toBe(-20);
    expect(numbers[0].currencyCode).toBe("USD");
    expect(numbers[1].value).toBe(-105.5);
    expect(numbers[numbers.length - 1].value).toBe(105.5);
    expect(numbers[numbers.length - 1].currencyCode).toBe("BRL");
  });

  it("disables the undo button when the entry cannot be undone", async () => {
    getEntryReconciliation.mockResolvedValue({ ...reconciled, canUndo: false });
    const element = await setup();
    expect(element.shadowRoot.querySelector(".undo").disabled).toBe(true);
  });

  it("reports the failure message in a toast", async () => {
    getEntryReconciliation.mockResolvedValue(reconciled);
    unreconcile.mockResolvedValue([{ success: false, message: "Já desfeita" }]);
    const element = await setup();
    const toasts = [];
    element.addEventListener("lightning__showtoast", (event) =>
      toasts.push(event.detail)
    );
    element.shadowRoot.querySelector(".undo").click();
    await flushPromises();
    expect(toasts).toHaveLength(1);
    expect(toasts[0].variant).toBe("error");
    expect(toasts[0].message).toBe("Já desfeita");
  });

  it("shows a toast when the undo call itself fails", async () => {
    getEntryReconciliation.mockResolvedValue(reconciled);
    unreconcile.mockRejectedValue({ body: { message: "Sem acesso" } });
    const element = await setup();
    const toasts = [];
    element.addEventListener("lightning__showtoast", (event) =>
      toasts.push(event.detail)
    );
    element.shadowRoot.querySelector(".undo").click();
    await flushPromises();
    expect(toasts[0].message).toBe("Sem acesso");
    expect(element.shadowRoot.querySelector(".undo").disabled).toBe(false);
  });

  it("still reloads when refreshing the page data fails after a saved undo", async () => {
    getEntryReconciliation
      .mockResolvedValueOnce(reconciled)
      .mockResolvedValueOnce({ reconciled: false });
    unreconcile.mockResolvedValue([{ success: true }]);
    notifyRecordUpdateAvailable.mockRejectedValueOnce(new Error("refresh"));
    const element = await setup();
    element.shadowRoot.querySelector(".undo").click();
    await flushPromises();
    expect(element.shadowRoot.querySelector(".pending")).not.toBeNull();
  });

  it("ignores a second click while the undo is running", async () => {
    getEntryReconciliation.mockResolvedValue(reconciled);
    let release;
    unreconcile.mockImplementation(
      () =>
        new Promise((resolve) => (release = () => resolve([{ success: true }])))
    );
    const element = await setup();
    const button = element.shadowRoot.querySelector(".undo");
    button.click();
    button.click();
    release();
    await flushPromises();
    expect(unreconcile).toHaveBeenCalledTimes(1);
  });

  it("reloads for the new entry when the record changes", async () => {
    getEntryReconciliation.mockResolvedValue(reconciled);
    const element = await setup();
    getEntryReconciliation.mockResolvedValue({ reconciled: false });
    element.recordId = "e2";
    await flushPromises();
    expect(getEntryReconciliation).toHaveBeenLastCalledWith({ entryId: "e2" });
    expect(element.shadowRoot.querySelector(".pending")).not.toBeNull();
  });

  it("uses a default message when the load error has no text", async () => {
    getEntryReconciliation.mockRejectedValue({});
    const element = await setup();
    expect(element.shadowRoot.querySelector("[role=alert]").textContent).toBe(
      "Não foi possível carregar a conciliação."
    );
  });
});
