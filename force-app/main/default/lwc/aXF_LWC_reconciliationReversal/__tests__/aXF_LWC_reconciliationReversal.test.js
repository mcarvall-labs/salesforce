import { createElement } from "lwc";
import Reversal from "c/aXF_LWC_reconciliationReversal";
import getContext from "@salesforce/apex/AXF_CLS_CTRL_ReconciliationReversal.getContext";
import listAllocations from "@salesforce/apex/AXF_CLS_CTRL_ReconciliationReversal.listAllocations";
import reverse from "@salesforce/apex/AXF_CLS_CTRL_ReconciliationReversal.reverse";
import priorReversal from "@salesforce/apex/AXF_CLS_CTRL_ReconciliationReversal.priorReversal";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ReconciliationReversal.getContext",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ReconciliationReversal.listAllocations",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ReconciliationReversal.reverse",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ReconciliationReversal.priorReversal",
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
  policyVersion: "AXF-REVERSAL@1.0.0",
  reasons: [
    "USER_ERROR",
    "DUPLICATE_LINK",
    "WRONG_TARGET",
    "SOURCE_CHANGED",
    "OTHER"
  ],
  pageSize: 25,
  holders: [{ accountId: "001A", name: "Ana" }]
};
const open = {
  allocationId: "a0E1",
  kind: "APPLICATION",
  targetId: "a0C1",
  targetDescription: "Aluguel",
  planKind: "PLANNED",
  targetVersion: 1,
  scheduleLinked: true,
  amount: 60,
  currencyIso: "BRL",
  recognitionDate: "2026-09-14",
  sourceKind: "BANK",
  sourceId: "a0B1",
  fxState: "READY"
};
const reversed = {
  ...open,
  allocationId: "a0E2",
  reversalId: "a0E3",
  reversalReason: "USER_ERROR"
};

async function mount() {
  const element = createElement("c-a-x-f-_-l-w-c-_reconciliation-reversal", {
    is: Reversal
  });
  document.body.appendChild(element);
  getContext.emit(context);
  await flush();
  return element;
}
function byId(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

describe("c-a-x-f-_-l-w-c-_reconciliation-reversal", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("lists applications, requires a reason and reverses with one key per draft", async () => {
    const element = await mount();
    listAllocations.mockResolvedValue({
      pageNumber: 1,
      pageSize: 25,
      hasMore: false,
      items: [open, reversed]
    });
    byId(element, "holder").dispatchEvent(
      new CustomEvent("change", { detail: { value: "001A" } })
    );
    await flush();
    byId(element, "load").click();
    await flush();
    const buttons = element.shadowRoot.querySelectorAll("[data-index]");
    expect(buttons.length).toBe(1);
    expect(buttons[0].dataset.index).toBe("0");
    buttons[0].click();
    await flush();
    expect(byId(element, "selectedSummary").textContent).toContain("Aluguel");
    expect(byId(element, "confirm").disabled).toBe(true);
    byId(element, "reason").dispatchEvent(
      new CustomEvent("change", { detail: { value: "WRONG_TARGET" } })
    );
    const note = byId(element, "note");
    note.value = "wrong invoice";
    note.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(byId(element, "confirm").disabled).toBe(false);
    reverse.mockRejectedValueOnce({ body: { message: "UNEXPECTED" } });
    byId(element, "confirm").click();
    await flush();
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("c.AXF_ReconciliationReversal_error");
    const first = JSON.parse(reverse.mock.calls[0][0].request);
    expect(first).toMatchObject({
      allocationId: "a0E1",
      expectedVersion: 1,
      reasonCode: "WRONG_TARGET",
      reasonNote: "wrong invoice"
    });
    expect(first.operationKey).toMatch(/^axf141-/);
    reverse.mockResolvedValueOnce({
      reversalId: "a0E9",
      originalId: "a0E1",
      replayed: true,
      actualOnly: false,
      realizedAfter: 0,
      residualAfter: 100,
      stateAfter: "NONE",
      sourceResidualAfter: 100,
      boundaries: ["AXF104_OBLIGATION_ADJUSTMENT_PENDING"]
    });
    byId(element, "confirm").click();
    await flush();
    expect(JSON.parse(reverse.mock.calls[1][0].request).operationKey).toBe(
      first.operationKey
    );
    expect(byId(element, "done").textContent).toContain(
      "c.AXF_ReconciliationReversal_doneReplayed"
    );
    expect(byId(element, "net").textContent).toContain(
      "c.AXF_ReconciliationReversal_doneRealized"
    );
    expect(byId(element, "net").textContent).toContain(
      "c.AXF_ReconciliationReversal_doneSourceRemaining"
    );
    expect(byId(element, "boundary").textContent).toContain(
      "c.AXF_ReconciliationReversal_boundaryAXF104_OBLIGATION_ADJUSTMENT_PENDING"
    );
  });

  it("shows the prior compensation on ALREADY_REVERSED and reloads the list on CONFLICT", async () => {
    const element = await mount();
    listAllocations.mockResolvedValue({
      pageNumber: 1,
      pageSize: 25,
      hasMore: false,
      items: [open]
    });
    byId(element, "holder").dispatchEvent(
      new CustomEvent("change", { detail: { value: "001A" } })
    );
    await flush();
    byId(element, "load").click();
    await flush();
    element.shadowRoot.querySelector('[data-index="0"]').click();
    await flush();
    byId(element, "reason").dispatchEvent(
      new CustomEvent("change", { detail: { value: "OTHER" } })
    );
    await flush();
    reverse.mockRejectedValueOnce({ body: { message: "CONFLICT" } });
    byId(element, "confirm").click();
    await flush();
    expect(listAllocations).toHaveBeenCalledTimes(2);
    expect(byId(element, "confirm")).toBeNull();
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("c.AXF_ReconciliationReversal_codeCONFLICT");
    element.shadowRoot.querySelector('[data-index="0"]').click();
    await flush();
    byId(element, "reason").dispatchEvent(
      new CustomEvent("change", { detail: { value: "OTHER" } })
    );
    await flush();
    reverse.mockRejectedValueOnce({ body: { message: "ALREADY_REVERSED" } });
    priorReversal.mockResolvedValueOnce({
      reversalId: "a0E3",
      originalId: "a0E1",
      replayed: true,
      reasonCode: "USER_ERROR",
      reasonNote: "typo",
      actualOnly: false,
      realizedAfter: 0,
      residualAfter: 100,
      stateAfter: "NONE",
      sourceResidualAfter: null,
      currencyIso: "BRL",
      boundaries: []
    });
    byId(element, "confirm").click();
    await flush();
    expect(byId(element, "done").textContent).toContain("a0E3");
    expect(byId(element, "note").textContent).toContain("typo");
    expect(byId(element, "net").textContent).toContain(
      "c.AXF_ReconciliationReversal_doneSourceUnknown"
    );
  });

  it("announces the actual-only outcome and hides everything without the capability", async () => {
    const element = await mount();
    listAllocations.mockResolvedValue({
      pageNumber: 1,
      pageSize: 25,
      hasMore: false,
      items: [{ ...open, planKind: "ACTUAL_ONLY", scheduleLinked: false }]
    });
    byId(element, "holder").dispatchEvent(
      new CustomEvent("change", { detail: { value: "001A" } })
    );
    await flush();
    byId(element, "load").click();
    await flush();
    element.shadowRoot.querySelector('[data-index="0"]').click();
    await flush();
    byId(element, "reason").dispatchEvent(
      new CustomEvent("change", { detail: { value: "DUPLICATE_LINK" } })
    );
    await flush();
    reverse.mockResolvedValue({
      reversalId: "a0E9",
      originalId: "a0E1",
      replayed: false,
      actualOnly: true,
      realizedAfter: 0,
      residualAfter: 0,
      stateAfter: "NONE",
      sourceResidualAfter: 100,
      boundaries: []
    });
    byId(element, "confirm").click();
    await flush();
    expect(JSON.parse(reverse.mock.calls[0][0].request).reasonNote).toBeNull();
    expect(byId(element, "actualOnly")).not.toBeNull();
    expect(byId(element, "boundary")).toBeNull();

    const denied = createElement("c-a-x-f-_-l-w-c-_reconciliation-reversal", {
      is: Reversal
    });
    document.body.appendChild(denied);
    getContext.emit({ ...context, canReverse: false, holders: [] });
    await flush();
    expect(
      denied.shadowRoot.querySelector('[role="status"]').textContent
    ).toContain("c.AXF_ReconciliationReversal_noCapability");
    expect(byId(denied, "holder")).toBeNull();
  });
});
