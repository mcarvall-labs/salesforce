import { createElement } from "lwc";
import BillingComposer, {
  contentKey,
  parseFailure,
  reasonLabel
} from "c/aXF_LWC_billingComposer";
import getAuthorizedEntities from "@salesforce/apex/AXF_CLS_CTRL_BillingComposer.getAuthorizedEntities";
import getContracts from "@salesforce/apex/AXF_CLS_CTRL_BillingComposer.getContracts";
import getCandidates from "@salesforce/apex/AXF_CLS_CTRL_BillingComposer.getCandidates";
import getApprovedWork from "@salesforce/apex/AXF_CLS_CTRL_BillingComposer.getApprovedWork";
import compose from "@salesforce/apex/AXF_CLS_CTRL_BillingComposer.compose";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_BillingComposer.getAuthorizedEntities",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_BillingComposer.getContracts",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_BillingComposer.getCandidates",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_BillingComposer.getApprovedWork",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_BillingComposer.compose",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = async () => {
  for (let i = 0; i < 6; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};

const entities = [
  { accountId: "001A", label: "Empresa A", contextType: "BUSINESS" }
];
const contracts = [
  {
    contractId: "ctrA",
    label: "CTR-1 - Suporte",
    counterpartyId: "cptyA",
    counterpartyName: "Cliente A",
    currencyIso: "BRL"
  }
];
const candidates = [
  {
    financialTransactionId: "ftx1",
    snapshotId: "cas1",
    name: "FTX-1",
    amount: 1000,
    currencyIso: "BRL",
    serviceDate: "2026-09-10",
    lineType: "HOURLY",
    snapshotName: "CAS-1",
    eligible: true,
    reasons: []
  },
  {
    financialTransactionId: "ftx2",
    snapshotId: null,
    name: "FTX-2",
    amount: 500,
    currencyIso: "USD",
    serviceDate: "2026-09-12",
    lineType: null,
    snapshotName: null,
    eligible: false,
    reasons: ["BLOCKED_FX", "SNAPSHOT_MISSING"]
  }
];
const work = [
  {
    workRecordId: "wr1",
    name: "WR-1",
    approvedQuantity: 50,
    allocatedQuantity: 20,
    remainingQuantity: 30
  }
];

function build() {
  const element = createElement("c-a-x-f_-l-w-c_billing-composer", {
    is: BillingComposer
  });
  document.body.appendChild(element);
  getAuthorizedEntities.emit(entities);
  return element;
}

async function fillFrame(element) {
  const combos = () =>
    element.shadowRoot.querySelectorAll("lightning-combobox");
  combos()[0].dispatchEvent(
    new CustomEvent("change", { detail: { value: "001A" } })
  );
  await flush();
  combos()[1].dispatchEvent(
    new CustomEvent("change", { detail: { value: "ctrA" } })
  );
  await flush();
  const inputs = element.shadowRoot.querySelectorAll("lightning-input");
  for (const input of inputs) {
    if (input.name === "seriesKey") {
      input.value = "2026-09";
      input.dispatchEvent(new CustomEvent("change"));
    }
    if (input.name === "periodStart") {
      input.value = "2026-09-01";
      input.dispatchEvent(new CustomEvent("change"));
    }
    if (input.name === "periodEnd") {
      input.value = "2026-09-30";
      input.dispatchEvent(new CustomEvent("change"));
    }
  }
  await flush();
}

describe("c-aXF_LWC_billingComposer", () => {
  beforeEach(() => {
    getContracts.mockResolvedValue(contracts);
    getCandidates.mockResolvedValue(candidates);
    getApprovedWork.mockResolvedValue(work);
  });
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("fills counterparty and currency from the contract and enables loading", async () => {
    const element = build();
    await flush();
    const load = element.shadowRoot.querySelector('[data-id="load"]');
    expect(load.disabled).toBe(true);
    await fillFrame(element);
    expect(getContracts).toHaveBeenCalledWith({ accountId: "001A" });
    const readOnly = [...element.shadowRoot.querySelectorAll("lightning-input")]
      .filter((input) => input.readOnly)
      .map((input) => input.value);
    expect(readOnly).toEqual(["Cliente A", "BRL"]);
    expect(element.shadowRoot.querySelector('[data-id="load"]').disabled).toBe(
      false
    );
  });

  it("lists candidates, explains incompatibilities and keeps them unselectable", async () => {
    const element = build();
    await flush();
    await fillFrame(element);
    element.shadowRoot.querySelector('[data-id="load"]').click();
    await flush();
    expect(getCandidates).toHaveBeenCalledWith({
      contractId: "ctrA",
      periodStart: "2026-09-01",
      periodEnd: "2026-09-30",
      currencyIso: "BRL"
    });
    const rows = element.shadowRoot.querySelectorAll("tbody tr.axf-row");
    expect(rows.length).toBe(2);
    const checkboxes = element.shadowRoot.querySelectorAll(
      "lightning-input[data-id]"
    );
    expect(checkboxes[0].disabled).toBe(false);
    expect(checkboxes[1].disabled).toBe(true);
    const reasons = [...rows[1].querySelectorAll("li")].map(
      (item) => item.textContent
    );
    expect(reasons).toEqual([
      reasonLabel("BLOCKED_FX"),
      reasonLabel("SNAPSHOT_MISSING")
    ]);
    expect(
      element.shadowRoot.querySelector('[data-id="compose"]').disabled
    ).toBe(true);
  });

  it("composes the selected lines with work allocations and shows the fixed summary", async () => {
    compose.mockResolvedValue({
      documentId: "bdo1",
      documentName: "BDO-000001",
      versionId: "bdv1",
      revision: 1,
      state: "DRAFT",
      lifecycle: "OPEN",
      presentationState: "DRAFT",
      accountName: "Empresa A",
      contractName: "CTR-1",
      counterpartyName: "Cliente A",
      currencyIso: "BRL",
      periodStart: "2026-09-01",
      periodEnd: "2026-09-30",
      totalAmount: 1000,
      linesTotal: 1000,
      lineCount: 1,
      lines: [
        {
          lineId: "bdl1",
          lineNumber: 1,
          lineType: "HOURLY",
          financialTransactionName: "FTX-1",
          snapshotName: "CAS-1",
          serviceDate: "2026-09-10",
          amount: 1000,
          currencyIso: "BRL",
          workAllocations: [
            { workRecordId: "wr1", workRecordName: "WR-1", quantity: 10 }
          ]
        }
      ]
    });
    const element = build();
    await flush();
    await fillFrame(element);
    element.shadowRoot.querySelector('[data-id="load"]').click();
    await flush();
    const checkbox = element.shadowRoot.querySelector(
      'lightning-input[data-id="ftx1"]'
    );
    checkbox.checked = true;
    checkbox.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(
      element.shadowRoot.querySelector('[data-id="count"]').textContent.trim()
    ).toBe("1");
    expect(
      element.shadowRoot.querySelector('[data-id="total"]').textContent
    ).toContain("1000.00");
    const addButton = [
      ...element.shadowRoot.querySelectorAll("lightning-button")
    ].find((button) => button.dataset.id === "ftx1" && !button.dataset.index);
    addButton.click();
    await flush();
    const quantity = element.shadowRoot.querySelector(
      'lightning-input[data-field="quantity"]'
    );
    // Production path: base components emit the value in event.detail.
    quantity.dispatchEvent(
      new CustomEvent("change", { detail: { value: "10" } })
    );
    await flush();
    element.shadowRoot.querySelector('[data-id="compose"]').click();
    await flush();
    const request = JSON.parse(compose.mock.calls[0][0].request);
    expect(request.contractId).toBe("ctrA");
    expect(request.counterpartyId).toBe("cptyA");
    expect(request.lines).toEqual([
      {
        financialTransactionId: "ftx1",
        snapshotId: "cas1",
        workAllocations: [{ workRecordId: "wr1", quantity: 10 }]
      }
    ]);
    expect(request.clientRequestId).toMatch(/^[0-9a-f-]{36}-[0-9a-f]{1,8}$/);
    const draftTitle = element.shadowRoot.querySelector(
      '[data-id="draft-title"]'
    );
    expect(draftTitle.textContent).toContain("BDO-000001");
    expect(element.shadowRoot.querySelectorAll("tbody tr").length).toBe(1);
    expect(element.shadowRoot.textContent).toContain("WR-1: 10");
  });

  it("shows sanitized failures per line and keeps nothing composed", async () => {
    compose.mockRejectedValue({
      body: {
        message: JSON.stringify({
          code: "INCOMPATIBLE_LINES",
          issues: [{ financialTransactionId: "ftx1", reason: "ALREADY_BILLED" }]
        })
      }
    });
    const element = build();
    await flush();
    await fillFrame(element);
    element.shadowRoot.querySelector('[data-id="load"]').click();
    await flush();
    const checkbox = element.shadowRoot.querySelector(
      'lightning-input[data-id="ftx1"]'
    );
    checkbox.checked = true;
    checkbox.dispatchEvent(new CustomEvent("change"));
    await flush();
    element.shadowRoot.querySelector('[data-id="compose"]').click();
    await flush();
    const alert = element.shadowRoot.querySelector('[role="alert"]');
    expect(alert.textContent).toBe(
      parseFailure({ body: { message: '{"code":"INCOMPATIBLE_LINES"}' } })
        .message
    );
    const firstRow = element.shadowRoot.querySelector("tbody tr.axf-row");
    expect(firstRow.textContent).toContain(reasonLabel("ALREADY_BILLED"));
    expect(
      element.shadowRoot.querySelector('[data-id="draft-title"]')
    ).toBeNull();
  });

  it("maps unknown failures to the generic message", () => {
    expect(parseFailure({ body: { message: "boom" } }).message).toBe(
      parseFailure({}).message
    );
    expect(parseFailure({ body: { message: "CONFLICT" } }).message).not.toBe(
      parseFailure({}).message
    );
  });
  it("derives the idempotency key from the payload and validates allocations before composing", async () => {
    compose.mockResolvedValue({ documentId: "bdo1", lines: [] });
    const element = build();
    await flush();
    await fillFrame(element);
    element.shadowRoot.querySelector('[data-id="load"]').click();
    await flush();
    const checkbox = element.shadowRoot.querySelector(
      'lightning-input[data-id="ftx1"]'
    );
    checkbox.checked = true;
    checkbox.dispatchEvent(new CustomEvent("change"));
    await flush();
    const addButton = [
      ...element.shadowRoot.querySelectorAll("lightning-button")
    ].find((button) => button.dataset.id === "ftx1" && !button.dataset.index);
    addButton.click();
    await flush();
    // Untouched allocation row: rejected client-side, no round trip.
    element.shadowRoot.querySelector('[data-id="compose"]').click();
    await flush();
    expect(compose).not.toHaveBeenCalled();
    expect(element.shadowRoot.textContent).toContain(
      "c.AXF_BillingComposer_quantityRequired"
    );
    const quantity = element.shadowRoot.querySelector(
      'lightning-input[data-field="quantity"]'
    );
    quantity.dispatchEvent(
      new CustomEvent("change", { detail: { value: "5" } })
    );
    await flush();
    element.shadowRoot.querySelector('[data-id="compose"]').click();
    await flush();
    const first = JSON.parse(compose.mock.calls[0][0].request);
    expect(first.lines[0].workAllocations[0].quantity).toBe(5);
    expect(first.clientRequestId).toMatch(/^[0-9a-f-]{36}-[0-9a-f]{1,8}$/);
    const payload = { a: 1, lines: [{ q: 5 }] };
    expect(contentKey("s", payload)).toBe(contentKey("s", payload));
    expect(contentKey("s", payload)).not.toBe(
      contentKey("s", { a: 1, lines: [{ q: 6 }] })
    );
  });

  it("rejects an inverted period client-side", async () => {
    const element = build();
    await flush();
    await fillFrame(element);
    const end = [
      ...element.shadowRoot.querySelectorAll("lightning-input")
    ].find((input) => input.name === "periodEnd");
    end.value = "2026-08-01";
    end.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="load"]').disabled).toBe(
      true
    );
    expect(element.shadowRoot.textContent).toContain(
      "c.AXF_BillingComposer_periodInvalid"
    );
  });
});
