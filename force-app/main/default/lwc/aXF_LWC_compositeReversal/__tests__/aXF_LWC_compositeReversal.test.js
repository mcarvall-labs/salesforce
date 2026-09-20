import { createElement } from "lwc";
import CompositeReversal from "c/aXF_LWC_compositeReversal";
import getContext from "@salesforce/apex/AXF_CLS_CTRL_CompositeReversal.getContext";
import listReconciliations from "@salesforce/apex/AXF_CLS_CTRL_CompositeReversal.listReconciliations";
import listAllocations from "@salesforce/apex/AXF_CLS_CTRL_CompositeReversal.listAllocations";
import reverseComposite from "@salesforce/apex/AXF_CLS_CTRL_CompositeReversal.reverseComposite";
import redistribute from "@salesforce/apex/AXF_CLS_CTRL_CompositeReversal.redistribute";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_CompositeReversal.getContext",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_CompositeReversal.listReconciliations",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_CompositeReversal.listAllocations",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_CompositeReversal.reverseComposite",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_CompositeReversal.redistribute",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = async () => {
  for (let i = 0; i < 8; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};
const context = {
  canReverse: true,
  canRedistribute: true,
  policyVersion: "AXF-COMPOSITE-REVERSAL@1.0.0",
  redistributePolicyVersion: "reconciliation-v1",
  reasons: ["USER_ERROR", "WRONG_TARGET", "OTHER"],
  holders: [{ accountId: "001A", name: "Ana" }]
};
const rcnSummary = {
  reconciliationId: "a0R1",
  state: "CONFIRMED",
  version: 1,
  allocationCount: 2
};
const rcnView = {
  reconciliationId: "a0R1",
  state: "CONFIRMED",
  version: 1,
  allocations: [
    {
      allocationId: "a0E1",
      targetId: "a0C1",
      targetDescription: "Aluguel",
      amount: 60,
      currencyIso: "BRL",
      sourceKind: "BANK",
      sourceId: "a0B1",
      sourceDescription: "Fact 1"
    },
    {
      allocationId: "a0E2",
      targetId: "a0C2",
      targetDescription: "Condominio",
      amount: 40,
      currencyIso: "BRL",
      sourceKind: "BANK",
      sourceId: "a0B1",
      sourceDescription: "Fact 1"
    }
  ]
};

async function mount() {
  const element = createElement("c-a-x-f-_-l-w-c-_composite-reversal", {
    is: CompositeReversal
  });
  document.body.appendChild(element);
  getContext.emit(context);
  await flush();
  return element;
}
function byId(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

describe("c-a-x-f-_-l-w-c-_composite-reversal", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("lists composite reconciliations, reverses all lines and offers redistribution", async () => {
    const element = await mount();
    listReconciliations.mockResolvedValue([rcnSummary]);
    byId(element, "holder").dispatchEvent(
      new CustomEvent("change", { detail: { value: "001A" } })
    );
    await flush();
    byId(element, "load").click();
    await flush();
    expect(listReconciliations).toHaveBeenCalledWith({ accountId: "001A" });
    const select = element.shadowRoot.querySelector("[data-index]");
    expect(select).not.toBeNull();

    listAllocations.mockResolvedValue(rcnView);
    select.click();
    await flush();
    expect(listAllocations).toHaveBeenCalledWith({
      reconciliationId: "a0R1"
    });
    expect(byId(element, "allocationsTable").textContent).toContain("Aluguel");
    expect(byId(element, "reverse").disabled).toBe(true);
    byId(element, "reason").dispatchEvent(
      new CustomEvent("change", { detail: { value: "WRONG_TARGET" } })
    );
    await flush();
    expect(byId(element, "reverse").disabled).toBe(false);

    reverseComposite.mockResolvedValue({
      reconciliationId: "a0R1",
      state: "REVERSED",
      version: 3,
      replayed: false,
      lines: [
        { allocationId: "a0E1", reversalId: "a0E9", replayed: false },
        { allocationId: "a0E2", reversalId: "a0E8", replayed: false }
      ]
    });
    byId(element, "reverse").click();
    await flush();
    const request = JSON.parse(reverseComposite.mock.calls[0][0].request);
    expect(request).toMatchObject({
      reconciliationId: "a0R1",
      expectedVersion: 1,
      reasonCode: "WRONG_TARGET"
    });
    expect(request.operationKey).toMatch(/^axf142-/);
    expect(byId(element, "done").textContent).toContain("REVERSED");

    byId(element, "redistributeOriginal").dispatchEvent(
      new CustomEvent("change", { detail: { value: "a0E1" } })
    );
    const targetField = byId(element, "redistributeTarget");
    targetField.value = "a0C9";
    targetField.dispatchEvent(new CustomEvent("change"));
    const amountField = byId(element, "redistributeAmount");
    amountField.value = "60";
    amountField.dispatchEvent(new CustomEvent("change"));
    byId(element, "redistributeReason").dispatchEvent(
      new CustomEvent("change", { detail: { value: "WRONG_TARGET" } })
    );
    await flush();
    expect(byId(element, "redistributeSubmit").disabled).toBe(false);

    // First attempt fails transiently; the retry must reuse the same idempotencyKey/correlationId
    // instead of minting a new one, so the server sees a replay rather than a duplicate.
    redistribute.mockRejectedValueOnce({ body: { message: "UNAVAILABLE" } });
    byId(element, "redistributeSubmit").click();
    await flush();
    const firstAttempt = JSON.parse(redistribute.mock.calls[0][0].request);
    expect(firstAttempt.originalAllocationId).toBe("a0E1");
    expect(firstAttempt.expectedVersion).toBe(0);
    expect(firstAttempt.reasonCode).toBe("WRONG_TARGET");
    expect(firstAttempt.lines[0]).toMatchObject({
      factKind: "BANK",
      factId: "a0B1",
      targetId: "a0C9",
      amount: 60
    });

    redistribute.mockResolvedValueOnce({
      reconciliationId: "a0R2",
      state: "CONFIRMED"
    });
    byId(element, "redistributeSubmit").click();
    await flush();
    const retryAttempt = JSON.parse(redistribute.mock.calls[1][0].request);
    expect(retryAttempt.correlationId).toBe(firstAttempt.correlationId);
    expect(retryAttempt.idempotencyKey).toBe(firstAttempt.idempotencyKey);
    expect(byId(element, "redistributeResult").textContent).toContain("a0R2");

    // The just-redistributed original is dropped from the picker without a manual reload.
    const remainingOptions =
      byId(element, "redistributeOriginal").options || [];
    expect(remainingOptions.some((o) => o.value === "a0E1")).toBe(false);
  });

  it("reloads the list on ALREADY_REVERSED just like a stale version conflict", async () => {
    const element = await mount();
    listReconciliations.mockResolvedValue([rcnSummary]);
    byId(element, "holder").dispatchEvent(
      new CustomEvent("change", { detail: { value: "001A" } })
    );
    await flush();
    byId(element, "load").click();
    await flush();
    listAllocations.mockResolvedValue(rcnView);
    element.shadowRoot.querySelector('[data-index="0"]').click();
    await flush();
    byId(element, "reason").dispatchEvent(
      new CustomEvent("change", { detail: { value: "OTHER" } })
    );
    await flush();
    reverseComposite.mockRejectedValueOnce({
      body: { message: "ALREADY_REVERSED" }
    });
    byId(element, "reverse").click();
    await flush();
    expect(listReconciliations).toHaveBeenCalledTimes(2);
    expect(byId(element, "reverse")).toBeNull();
  });

  it("reloads the list on a stale version conflict", async () => {
    const element = await mount();
    listReconciliations.mockResolvedValue([rcnSummary]);
    byId(element, "holder").dispatchEvent(
      new CustomEvent("change", { detail: { value: "001A" } })
    );
    await flush();
    byId(element, "load").click();
    await flush();
    listAllocations.mockResolvedValue(rcnView);
    element.shadowRoot.querySelector('[data-index="0"]').click();
    await flush();
    byId(element, "reason").dispatchEvent(
      new CustomEvent("change", { detail: { value: "OTHER" } })
    );
    await flush();
    reverseComposite.mockRejectedValueOnce({ body: { message: "CONFLICT" } });
    byId(element, "reverse").click();
    await flush();
    expect(listReconciliations).toHaveBeenCalledTimes(2);
    expect(byId(element, "reverse")).toBeNull();
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("A versao mudou");
  });

  it("hides everything without the capability", async () => {
    const element = createElement("c-a-x-f-_-l-w-c-_composite-reversal", {
      is: CompositeReversal
    });
    document.body.appendChild(element);
    getContext.emit({ ...context, canReverse: false, holders: [] });
    await flush();
    expect(
      element.shadowRoot.querySelector('[role="status"]').textContent
    ).toContain("permissao");
    expect(byId(element, "holder")).toBeNull();
  });
});
