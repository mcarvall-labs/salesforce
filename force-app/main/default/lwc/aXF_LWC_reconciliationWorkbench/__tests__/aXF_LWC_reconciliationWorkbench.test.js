import { createElement } from "lwc";
import Workbench from "c/aXF_LWC_reconciliationWorkbench";
import getContext from "@salesforce/apex/AXF_CLS_CTRL_ReconciliationWorkbench.getContext";
import preview from "@salesforce/apex/AXF_CLS_CTRL_ReconciliationWorkbench.preview";
import confirm from "@salesforce/apex/AXF_CLS_CTRL_ReconciliationWorkbench.confirm";
import resolveResult from "@salesforce/apex/AXF_CLS_CTRL_ReconciliationWorkbench.resolveResult";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ReconciliationWorkbench.getContext",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ReconciliationWorkbench.preview",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ReconciliationWorkbench.confirm",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ReconciliationWorkbench.resolveResult",
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
  canConfirm: true,
  policyVersion: "AXF-MATCHING@1.0.0",
  holders: [{ accountId: "001A", label: "Ana", contextType: "PERSON" }]
};
const source = {
  factId: "a0B1",
  factKind: "BANK",
  label: "BAT-1",
  description: "Débito mercado",
  factDate: "2026-09-14",
  magnitude: 100,
  residual: 100,
  currencyIso: "BRL",
  direction: "DEBIT",
  version: 0
};
const candidate = {
  targetId: "a0C1",
  label: "FTX-1",
  description: "Aluguel",
  dueDate: "2026-09-20",
  magnitude: 60,
  available: 60,
  residual: 60,
  currencyIso: "BRL",
  direction: "DEBIT",
  version: 0,
  linkable: true,
  reasons: [],
  state: "CONSULTATIVE",
  evidence: [],
  identityExact: false,
  lowEvidence: false
};
const reviewedLine = {
  factKind: "BANK",
  factId: "a0B1",
  factLabel: "BAT-1",
  targetId: "a0C1",
  targetLabel: "FTX-1",
  amount: 60,
  available: 60,
  allocated: 0,
  residual: 0,
  sourceResidual: 40,
  currencyIso: "BRL",
  state: "CONFIRMED",
  reasons: []
};
const reviewView = {
  policyVersion: "AXF-MATCHING@1.0.0",
  state: "CONSULTATIVE",
  expectedVersion: 0,
  sources: [],
  candidates: [candidate],
  lines: [],
  source
};
const readyView = {
  ...reviewView,
  lines: [reviewedLine]
};

async function mount() {
  const element = createElement("c-a-x-f-_-l-w-c-_reconciliation-workbench", {
    is: Workbench
  });
  document.body.appendChild(element);
  getContext.emit(context);
  await flush();
  return element;
}
function byId(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}
/** Figures are rendered by lightning-formatted-number; the stub keeps the value it received. */
function numberValue(element, id) {
  const host = byId(element, id);
  return host.querySelector("lightning-formatted-number").value;
}
async function openReview(element) {
  preview.mockResolvedValueOnce({
    policyVersion: "AXF-MATCHING@1.0.0",
    sources: [source],
    candidates: []
  });
  byId(element, "holder").dispatchEvent(
    new CustomEvent("change", { detail: { value: "001A" } })
  );
  await flush();
  byId(element, "load").click();
  await flush();
  preview.mockResolvedValueOnce(reviewView);
  element.shadowRoot.querySelector('[data-index="0"]').click();
  await flush();
}

describe("c-a-x-f-_-l-w-c-_reconciliation-workbench", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("assembles lines from the service figures and confirms with one intention key", async () => {
    const element = await mount();
    await openReview(element);
    expect(byId(element, "sourceSummary").textContent).toContain("Débito mercado");
    expect(numberValue(element, "sourceResidual")).toBe(100);
    expect(byId(element, "sourceResidual").textContent).toContain("(BRL)");
    expect(byId(element, "candidateState").textContent).toContain(
      "c.AXF_ReconciliationWorkbench_stateCONSULTATIVE"
    );
    expect(byId(element, "noLines")).not.toBeNull();
    expect(byId(element, "confirm").disabled).toBe(true);

    const amount = byId(element, "amount");
    amount.value = "60";
    amount.dispatchEvent(new CustomEvent("change"));
    await flush();
    preview.mockResolvedValueOnce(readyView);
    byId(element, "add").click();
    await flush();

    expect(byId(element, "lines")).not.toBeNull();
    expect(numberValue(element, "lineAvailable")).toBe(60);
    expect(numberValue(element, "lineAllocated")).toBe(0);
    expect(numberValue(element, "lineResidual")).toBe(0);
    expect(byId(element, "lineCurrency").textContent).toContain("BRL");
    expect(byId(element, "lineState").textContent).toContain(
      "c.AXF_ReconciliationWorkbench_stateCONFIRMED"
    );
    expect(byId(element, "confirm").disabled).toBe(false);

    confirm.mockRejectedValueOnce({ body: { message: "UNEXPECTED" } });
    byId(element, "confirm").click();
    await flush();
    const firstRequest = JSON.parse(confirm.mock.calls[0][0].request);
    expect(firstRequest.lines).toEqual([
      { factKind: "BANK", factId: "a0B1", targetId: "a0C1", amount: 60 }
    ]);
    expect(firstRequest.expectedVersion).toBe(0);
    expect(firstRequest.idempotencyKey).toMatch(/^axf30-/);
    expect(firstRequest.correlationId).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
    );
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("c.AXF_ReconciliationWorkbench_codeUNEXPECTED");

    confirm.mockResolvedValueOnce({
      reconciliationId: "a0R1",
      reconciliationKey: "key1",
      state: "PARTIAL",
      replayed: true,
      version: 1,
      residualMagnitude: 40,
      residualCurrency: "BRL",
      allocatedTotal: 60,
      lines: [{ ...reviewedLine, residual: 0, sourceResidual: 40 }]
    });
    byId(element, "confirm").click();
    await flush();
    const retryRequest = JSON.parse(confirm.mock.calls[1][0].request);
    expect(retryRequest.idempotencyKey).toBe(firstRequest.idempotencyKey);
    expect(retryRequest.correlationId).toBe(firstRequest.correlationId);
    expect(byId(element, "done").textContent).toContain(
      "c.AXF_ReconciliationWorkbench_doneReplayed"
    );
    expect(byId(element, "state").textContent).toContain(
      "c.AXF_ReconciliationWorkbench_statePARTIAL"
    );
    expect(numberValue(element, "residual")).toBe(40);
    expect(byId(element, "aggregate").textContent).toContain("a0R1");
  });

  it("shows a blocked set as text and resolves it through the authoritative query", async () => {
    const element = await mount();
    await openReview(element);
    const amount = byId(element, "amount");
    amount.value = "60";
    amount.dispatchEvent(new CustomEvent("change"));
    await flush();
    preview.mockResolvedValueOnce(readyView);
    byId(element, "add").click();
    await flush();

    confirm.mockRejectedValueOnce({
      body: { message: JSON.stringify({ code: "CONFLICT", reasons: [] }) }
    });
    byId(element, "confirm").click();
    await flush();
    expect(byId(element, "confirm")).not.toBeNull();
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("c.AXF_ReconciliationWorkbench_codeCONFLICT");

    resolveResult.mockResolvedValueOnce({
      reconciliationId: "a0R2",
      reconciliationKey: "key2",
      state: "BLOCKED",
      unknownOutcome: true,
      expectedVersion: 2,
      residualMagnitude: null,
      residualCurrency: null,
      allocatedTotal: 60,
      lines: [{ ...reviewedLine, state: "BLOCKED", residual: 0 }]
    });
    byId(element, "resolve").click();
    await flush();
    const request = JSON.parse(resolveResult.mock.calls[0][0].request);
    expect(request.lines.length).toBe(1);
    expect(byId(element, "state").textContent).toContain(
      "c.AXF_ReconciliationWorkbench_stateBLOCKED"
    );
    expect(byId(element, "unknown").textContent).toContain(
      "c.AXF_ReconciliationWorkbench_doneUnknown"
    );
    expect(
      element.shadowRoot.querySelector('[data-id="residual"]').textContent
    ).toContain("c.AXF_ReconciliationWorkbench_doneUnknown");
  });

  it("hides everything without the capability", async () => {
    const denied = createElement("c-a-x-f-_-l-w-c-_reconciliation-workbench", {
      is: Workbench
    });
    document.body.appendChild(denied);
    getContext.emit({ ...context, canConfirm: false, holders: [] });
    await flush();
    expect(
      denied.shadowRoot.querySelector('[role="status"]').textContent
    ).toContain("c.AXF_ReconciliationWorkbench_noCapability");
    expect(byId(denied, "holder")).toBeNull();
  });
});
