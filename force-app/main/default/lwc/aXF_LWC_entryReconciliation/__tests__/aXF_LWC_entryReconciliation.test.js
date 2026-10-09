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
  realizedAmountBRL: 105.5
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
});
