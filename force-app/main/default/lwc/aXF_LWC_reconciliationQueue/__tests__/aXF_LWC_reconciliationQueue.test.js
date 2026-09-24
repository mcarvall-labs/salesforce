import { createElement } from "lwc";
import ReconciliationQueue from "c/aXF_LWC_reconciliationQueue";
import getContext from "@salesforce/apex/AXF_CLS_CTRL_ReconciliationQueue.getContext";
import listSources from "@salesforce/apex/AXF_CLS_CTRL_ReconciliationQueue.listSources";
import getQueue from "@salesforce/apex/AXF_CLS_CTRL_ReconciliationQueue.getQueue";
import listSuggestions from "@salesforce/apex/AXF_CLS_CTRL_ReconciliationQueue.listSuggestions";
import confirmSuggestion from "@salesforce/apex/AXF_CLS_CTRL_ReconciliationQueue.confirmSuggestion";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ReconciliationQueue.getContext",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ReconciliationQueue.listSources",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ReconciliationQueue.getQueue",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ReconciliationQueue.listSuggestions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ReconciliationQueue.confirmSuggestion",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const BANK = {
  kind: "BANK",
  fundingId: "a01000000000001",
  holderId: "001000000000001",
  holderLabel: "Ana",
  name: "Banco A ****1234",
  currencyIso: "BRL"
};
const CARD = {
  kind: "CARD",
  fundingId: "a05000000000001",
  holderId: "001000000000001",
  holderLabel: "Ana",
  name: "Banco A VISA 9876",
  currencyIso: "BRL"
};
const BANK_LINE = {
  kind: "BANK",
  lineKind: "FACT",
  fundingId: BANK.fundingId,
  fundingName: BANK.name,
  holderLabel: "Ana",
  recordId: "a02000000000001",
  lineDate: "2026-09-10",
  description: "Mercado",
  amount: 100,
  direction: "DEBIT",
  currencyIso: "BRL",
  allocated: 0,
  residual: 100,
  status: "UNRECONCILED",
  version: 0,
  canSuggest: true
};
const CARD_LINE = {
  ...BANK_LINE,
  kind: "CARD",
  fundingId: CARD.fundingId,
  fundingName: CARD.name,
  recordId: "a06000000000001",
  description: "Livraria",
  status: "PARTIAL",
  allocated: 20,
  residual: 80
};
const DONE_LINE = {
  ...BANK_LINE,
  recordId: "a02000000000002",
  description: "Farmacia",
  status: "RECONCILED",
  canSuggest: false
};
const SUGGESTION = {
  sourceId: BANK_LINE.recordId,
  sourceVersion: 0,
  targetId: "a03000000000001",
  targetVersion: 2,
  candidateId: "a03000000000001",
  candidateDate: "2026-09-12",
  candidateAmount: 104,
  description: "Previsto mercado",
  currencyIso: "BRL",
  amountDelta: 4,
  dayDelta: 2,
  allocationAmount: 100,
  tied: false
};

function viewOf(extra = {}) {
  return {
    matchingPolicy: "AXF-MATCHING@1.1.0",
    canReconcile: true,
    fromDate: "2026-09-01",
    toDate: "2026-09-30",
    customPeriod: false,
    invoiceOutcome: null,
    truncated: false,
    countReconciled: 1,
    countPartial: 1,
    countUnreconciled: 1,
    countUnverified: 0,
    pending: [BANK_LINE, CARD_LINE],
    unverified: [],
    reconciled: [DONE_LINE],
    ...extra
  };
}

const settle = async () => {
  for (let i = 0; i < 6; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};

async function build(context = { canReconcile: true }) {
  const el = createElement("c-a-x-f_-l-w-c_reconciliation-queue", {
    is: ReconciliationQueue
  });
  document.body.appendChild(el);
  getContext.emit(context);
  await settle();
  return el;
}

function action(el, name, id) {
  const selector = id
    ? `[data-action="${name}"][data-id="${id}"]`
    : `[data-action="${name}"]`;
  return el.shadowRoot.querySelector(selector);
}

function field(el, name) {
  return el.shadowRoot.querySelector(`[data-field="${name}"]`);
}

function change(input, value) {
  input.dispatchEvent(new CustomEvent("change", { detail: { value } }));
}

function stubValidity(el) {
  el.shadowRoot
    .querySelectorAll("lightning-input[data-filter]")
    .forEach((i) => {
      i.setCustomValidity = jest.fn();
      i.reportValidity = jest.fn();
      i.checkValidity = jest.fn(() => true);
    });
}

function lastRequest() {
  const calls = getQueue.mock.calls;
  return JSON.parse(calls[calls.length - 1][0].request);
}

beforeEach(() => {
  listSources.mockResolvedValue({ truncated: false, items: [BANK, CARD] });
  getQueue.mockResolvedValue(viewOf());
});

afterEach(() => {
  while (document.body.firstChild) {
    document.body.removeChild(document.body.firstChild);
  }
  jest.clearAllMocks();
});

describe("c-aXF_LWC_reconciliationQueue", () => {
  it("shows pending lines on top with counters and the reconciled collapsed", async () => {
    const el = await build();
    expect(lastRequest()).toEqual({
      kind: null,
      fundingId: null,
      invoiceYear: null,
      invoiceMonth: null,
      fromDate: null,
      toDate: null,
      minAmount: null,
      maxAmount: null,
      term: null,
      status: "PENDING"
    });
    const sections = [
      ...el.shadowRoot.querySelectorAll("section[data-section]")
    ].map((s) => s.dataset.section);
    expect(sections).toEqual(["pending", "reconciled"]);
    const pending = el.shadowRoot.querySelector('[data-lines="pending"]');
    expect(pending.querySelector("caption").textContent).toContain(
      "AXF_ReconciliationQueue_pendingHeading"
    );
    const rows = pending.querySelectorAll("tbody tr[data-line]");
    expect(rows).toHaveLength(2);
    expect(rows[0].textContent).toContain("Banco A ****1234");
    expect(rows[0].textContent).toContain("AXF_ReconciliationQueue_kindBANK");
    expect(rows[1].textContent).toContain("AXF_ReconciliationQueue_kindCARD");
    expect(rows[0].querySelector("lightning-formatted-number").value).toBe(
      -100
    );
    expect(
      el.shadowRoot.querySelector('[data-counter="UNRECONCILED"]').textContent
    ).toContain("1");
    expect(el.shadowRoot.querySelector('[data-lines="reconciled"]')).toBeNull();
    const toggle = action(el, "toggle-reconciled");
    expect(toggle.getAttribute("aria-expanded")).toBe("false");
    toggle.click();
    await settle();
    expect(
      el.shadowRoot.querySelectorAll('[data-lines="reconciled"] tbody tr')
    ).toHaveLength(1);
    expect(action(el, "toggle-reconciled").getAttribute("aria-expanded")).toBe(
      "true"
    );
  });

  it("sends every filter combined and restricts sources by type", async () => {
    const el = await build();
    change(field(el, "kind"), "CARD");
    await settle();
    const sourceOptions = field(el, "fundingId").options.map((o) => o.value);
    expect(sourceOptions).toEqual(["", CARD.fundingId]);
    expect(field(el, "invoice").disabled).toBe(true);
    change(field(el, "fundingId"), CARD.fundingId);
    await settle();
    expect(field(el, "invoice").disabled).toBe(false);
    change(field(el, "invoice"), "2026-09");
    change(field(el, "fromDate"), "2026-09-01");
    change(field(el, "toDate"), "2026-09-30");
    change(field(el, "minAmount"), "10");
    change(field(el, "maxAmount"), "200");
    change(field(el, "term"), "livraria");
    change(field(el, "status"), "PENDING");
    await settle();
    stubValidity(el);
    action(el, "apply-filters").click();
    await settle();
    expect(lastRequest()).toEqual({
      kind: "CARD",
      fundingId: CARD.fundingId,
      invoiceYear: 2026,
      invoiceMonth: 9,
      fromDate: "2026-09-01",
      toDate: "2026-09-30",
      minAmount: 10,
      maxAmount: 200,
      term: "livraria",
      status: "PENDING"
    });
    change(field(el, "fundingId"), "");
    await settle();
    expect(field(el, "invoice").value).toBe("");
    action(el, "clear-filters").click();
    await settle();
    expect(lastRequest().kind).toBeNull();
    expect(lastRequest().status).toBe("PENDING");
  });

  it("clears an account that does not match the new type", async () => {
    const el = await build();
    change(field(el, "fundingId"), BANK.fundingId);
    await settle();
    change(field(el, "kind"), "CARD");
    await settle();
    expect(field(el, "fundingId").value).toBe("");
    stubValidity(el);
    action(el, "apply-filters").click();
    await settle();
    expect(lastRequest().kind).toBe("CARD");
    expect(lastRequest().fundingId).toBeNull();
  });

  it("sorts the account and card options by holder, then name", async () => {
    listSources.mockResolvedValue({
      truncated: false,
      items: [
        { ...CARD, holderLabel: "Bruno", name: "Z card" },
        { ...BANK, holderLabel: "Ana", name: "Y bank" },
        {
          ...BANK,
          fundingId: "a01000000000009",
          holderLabel: "Ana",
          name: "X bank"
        }
      ]
    });
    const el = await build();
    expect(field(el, "fundingId").options.map((o) => o.value)).toEqual([
      "",
      "a01000000000009",
      BANK.fundingId,
      CARD.fundingId
    ]);
  });

  it("renders lines that cannot be verified between pending and reconciled", async () => {
    getQueue.mockResolvedValue(
      viewOf({
        unverified: [
          {
            ...BANK_LINE,
            recordId: "a02000000000009",
            status: "UNVERIFIED",
            canSuggest: false
          }
        ],
        countUnverified: 1
      })
    );
    const el = await build();
    const sections = [
      ...el.shadowRoot.querySelectorAll("section[data-section]")
    ].map((s) => s.dataset.section);
    expect(sections).toEqual(["pending", "unverified", "reconciled"]);
    const rows = el.shadowRoot.querySelectorAll(
      '[data-lines="unverified"] tbody tr[data-line]'
    );
    expect(rows).toHaveLength(1);
    expect(rows[0].textContent).toContain("AXF_BankStatement_statusUNVERIFIED");
  });

  it("shows the narrowed period of an invoice read with a custom period", async () => {
    getQueue.mockResolvedValue(
      viewOf({
        invoiceOutcome: "RESOLVED",
        invoiceYear: 2026,
        invoiceMonth: 9,
        customPeriod: true,
        fromDate: "2026-09-01",
        toDate: "2026-09-05",
        invoiceFromDate: "2026-08-06",
        invoiceToDate: "2026-09-05",
        closingDate: "2026-09-05",
        dueDate: "2026-09-12"
      })
    );
    const el = await build();
    const period = el.shadowRoot.querySelector("[data-period]").textContent;
    expect(period).toContain("AXF_ReconciliationQueue_period");
    const windowText = el.shadowRoot.querySelector("[data-window]").textContent;
    expect(windowText).toContain("AXF_CardStatement_invoiceWindow");
  });

  it("keeps an invalid period on the client", async () => {
    const el = await build();
    const calls = getQueue.mock.calls.length;
    change(field(el, "fromDate"), "2026-01-01");
    change(field(el, "toDate"), "2027-01-10");
    await settle();
    const inputs = [
      ...el.shadowRoot.querySelectorAll("lightning-input[data-filter]")
    ];
    inputs.forEach((i) => {
      i.reportValidity = jest.fn();
      i.setCustomValidity = jest.fn((msg) => {
        i.invalid = Boolean(msg);
      });
      i.checkValidity = jest.fn(() => !i.invalid);
    });
    action(el, "apply-filters").click();
    await settle();
    expect(getQueue.mock.calls.length).toBe(calls);
    const to = inputs.find((i) => i.dataset.field === "toDate");
    expect(to.setCustomValidity).toHaveBeenCalledWith(
      expect.stringContaining("AXF_BankStatement_filterPeriodTooLong")
    );
  });

  it("shows the invoice window or the no-calendar warning", async () => {
    getQueue.mockResolvedValue(
      viewOf({
        invoiceOutcome: "RESOLVED",
        fromDate: "2026-08-06",
        toDate: "2026-09-05",
        closingDate: "2026-09-05",
        dueDate: "2026-09-12"
      })
    );
    let el = await build();
    expect(el.shadowRoot.querySelector("[data-window]")).not.toBeNull();
    expect(el.shadowRoot.querySelector("[data-no-calendar]")).toBeNull();
    document.body.removeChild(el);
    getQueue.mockResolvedValue(viewOf({ invoiceOutcome: "BLOCKED" }));
    el = await build();
    expect(el.shadowRoot.querySelector("[data-no-calendar]")).not.toBeNull();
  });

  it("confirms a suggestion in one click and reloads the queue", async () => {
    listSuggestions.mockResolvedValue({
      truncated: false,
      items: [SUGGESTION]
    });
    confirmSuggestion.mockResolvedValue({ allocationId: "a0R000000000001" });
    const el = await build();
    action(el, "toggle-suggestions", BANK_LINE.recordId).click();
    await settle();
    expect(JSON.parse(listSuggestions.mock.calls[0][0].request)).toEqual({
      fundingId: BANK.fundingId,
      recordId: BANK_LINE.recordId
    });
    const before = getQueue.mock.calls.length;
    el.shadowRoot.querySelector('[data-action="confirm-suggestion"]').click();
    await settle();
    const sent = JSON.parse(confirmSuggestion.mock.calls[0][0].request);
    expect(sent).toMatchObject({
      fundingId: BANK.fundingId,
      sourceId: SUGGESTION.sourceId,
      sourceVersion: 0,
      targetId: SUGGESTION.targetId,
      targetVersion: 2
    });
    expect(sent.operationKey).toBeTruthy();
    expect(getQueue.mock.calls.length).toBe(before + 1);
    expect(el.shadowRoot.querySelector("[data-message]").textContent).toContain(
      "AXF_BankStatement_confirmed"
    );
  });

  it("turns a refused confirmation into its message and reloads", async () => {
    listSuggestions.mockResolvedValue({
      truncated: false,
      items: [SUGGESTION]
    });
    confirmSuggestion.mockRejectedValue({ body: { message: "CONFLICT" } });
    const el = await build();
    action(el, "toggle-suggestions", CARD_LINE.recordId).click();
    await settle();
    expect(JSON.parse(listSuggestions.mock.calls[0][0].request).fundingId).toBe(
      CARD.fundingId
    );
    const before = getQueue.mock.calls.length;
    el.shadowRoot.querySelector('[data-action="confirm-suggestion"]').click();
    await settle();
    expect(getQueue.mock.calls.length).toBe(before + 1);
    expect(el.shadowRoot.querySelector("[data-message]").textContent).toContain(
      "AXF_BankStatement_codeCONFLICT"
    );
  });

  it("hides every action without the reconcile permission", async () => {
    getQueue.mockResolvedValue(viewOf({ canReconcile: false }));
    const el = await build({ canReconcile: false });
    expect(el.shadowRoot.querySelector("[data-read-only]")).not.toBeNull();
    expect(
      el.shadowRoot.querySelectorAll('[data-lines="pending"] tbody tr')
    ).toHaveLength(2);
    expect(action(el, "toggle-suggestions")).toBeNull();
  });

  it("ignores a late answer to an older request", async () => {
    const el = await build();
    let resolveOld;
    getQueue.mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          resolveOld = resolve;
        })
    );
    getQueue.mockResolvedValueOnce(
      viewOf({ pending: [], countUnreconciled: 0 })
    );
    stubValidity(el);
    action(el, "apply-filters").click();
    action(el, "clear-filters").click();
    await settle();
    resolveOld(viewOf());
    await settle();
    expect(
      el.shadowRoot.querySelector('[data-empty="pending"]')
    ).not.toBeNull();
  });

  it("flags truncation and shows empty states", async () => {
    listSources.mockResolvedValue({ truncated: true, items: [] });
    getQueue.mockResolvedValue(
      viewOf({ truncated: true, pending: [], reconciled: [] })
    );
    const el = await build();
    expect(el.shadowRoot.querySelector("[data-truncated]")).not.toBeNull();
    expect(
      el.shadowRoot.querySelector("[data-sources-truncated]")
    ).not.toBeNull();
    expect(el.shadowRoot.querySelector("[data-no-sources]")).not.toBeNull();
    expect(
      el.shadowRoot.querySelector('[data-empty="pending"]')
    ).not.toBeNull();
  });

  it("shows the sanitized message when the queue fails", async () => {
    getQueue.mockRejectedValue({ body: { message: "NOT_ACCESSIBLE" } });
    const el = await build();
    expect(el.shadowRoot.querySelector("[data-message]").textContent).toContain(
      "AXF_BankStatement_codeNOT_ACCESSIBLE"
    );
    expect(el.shadowRoot.querySelector("section[data-section]")).toBeNull();
  });
});
