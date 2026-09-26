import { createElement } from "lwc";
import CardStatement from "c/aXF_LWC_cardStatement";
import getContext from "@salesforce/apex/AXF_CLS_CTRL_CardStatement.getContext";
import listCards from "@salesforce/apex/AXF_CLS_CTRL_CardStatement.listCards";
import getInvoice from "@salesforce/apex/AXF_CLS_CTRL_CardStatement.getInvoice";
import listSuggestions from "@salesforce/apex/AXF_CLS_CTRL_CardStatement.listSuggestions";
import confirmSuggestion from "@salesforce/apex/AXF_CLS_CTRL_CardStatement.confirmSuggestion";
import defineClosing from "@salesforce/apex/AXF_CLS_CTRL_CardStatement.defineClosing";

const mockNavigate = jest.fn();
jest.mock("lightning/navigation", () => {
  const Navigate = Symbol("Navigate");
  const NavigationMixin = (Base) =>
    class extends Base {
      [Navigate](pageRef) {
        mockNavigate(pageRef);
      }
    };
  NavigationMixin.Navigate = Navigate;
  return { NavigationMixin, CurrentPageReference: jest.fn() };
});
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_CardStatement.getContext",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_CardStatement.listCards",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_CardStatement.getInvoice",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_CardStatement.listSuggestions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_CardStatement.confirmSuggestion",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_CardStatement.defineClosing",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const PLUGGY_CARD = {
  creditCardId: "a05000000000001",
  holderId: "001000000000001",
  holderLabel: "Ana",
  institutionName: "Banco A",
  brand: "VISA",
  lastFour: "1234",
  creditLimit: 5000,
  availableLimit: 3200,
  currencyIso: "BRL",
  hasConnection: true,
  hasCalendar: true,
  closingDay: 5,
  dueDay: 12,
  canDefineClosing: false
};
const MANUAL_CARD = {
  creditCardId: "a05000000000002",
  holderId: "001000000000001",
  holderLabel: "Ana",
  institutionName: "Banco B",
  brand: null,
  lastFour: "9876",
  creditLimit: null,
  availableLimit: null,
  currencyIso: "BRL",
  hasConnection: false,
  hasCalendar: false,
  closingDay: null,
  dueDay: null,
  canDefineClosing: true
};
const FACT = {
  lineKind: "FACT",
  recordId: "a06000000000001",
  lineDate: "2026-09-02",
  description: "Mercado",
  amount: 100,
  direction: "DEBIT",
  currencyIso: "BRL",
  origin: "PLUGGY",
  allocated: 0,
  residual: 100,
  status: "UNRECONCILED",
  version: 0,
  canSuggest: true
};
const DONE = {
  ...FACT,
  recordId: "a06000000000002",
  description: "Streaming",
  status: "RECONCILED",
  canSuggest: false
};
function invoiceOf(lines, extra = {}) {
  return {
    card: PLUGGY_CARD,
    year: 2026,
    month: 9,
    customPeriod: false,
    outcome: "RESOLVED",
    fromDate: "2026-08-06",
    toDate: "2026-09-05",
    closingDate: "2026-09-05",
    dueDate: "2026-09-14",
    total: 200,
    plannedTotal: 0,
    currencyIso: "BRL",
    canReconcile: true,
    truncated: false,
    lines,
    ...extra
  };
}
const SUGGESTION = {
  sourceId: "a06000000000001",
  sourceVersion: 0,
  targetId: "a03000000000001",
  targetVersion: 2,
  candidateId: "a03000000000001",
  candidateDate: "2026-09-08",
  candidateAmount: 104,
  description: "Previsto mercado",
  currencyIso: "BRL",
  amountDelta: 4,
  dayDelta: 6,
  allocationAmount: 100,
  tied: false
};

const settle = async () => {
  for (let i = 0; i < 6; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};

async function build(
  context = { canUse: true, canConfigure: true, canReconcile: true }
) {
  const el = createElement("c-a-x-f_-l-w-c_card-statement", {
    is: CardStatement
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

async function openInvoice(el, id) {
  action(el, "view", id).click();
  await settle();
}

function row(el, id) {
  return el.shadowRoot.querySelector(`[data-card-row="${id}"]`);
}

beforeEach(() => {
  listCards.mockResolvedValue([PLUGGY_CARD, MANUAL_CARD]);
  getInvoice.mockResolvedValue(invoiceOf([FACT, DONE]));
});

afterEach(() => {
  while (document.body.firstChild) {
    document.body.removeChild(document.body.firstChild);
  }
  jest.clearAllMocks();
});

describe("c-aXF_LWC_cardStatement", () => {
  it("shows only the no-capability message without the capability", async () => {
    const el = await build({ canUse: false, canConfigure: false });
    expect(el.shadowRoot.querySelector("[data-no-capability]")).not.toBeNull();
    expect(listCards).not.toHaveBeenCalled();
    expect(el.shadowRoot.querySelector("[data-cards]")).toBeNull();
  });

  it("lists cards with limits, closing and due days and the closing action", async () => {
    const el = await build();
    const table = el.shadowRoot.querySelector("[data-cards]");
    expect(table.querySelector("caption").textContent).toContain(
      "AXF_CardStatement_cardsCaption"
    );
    expect(table.querySelectorAll("tbody tr")).toHaveLength(2);
    const pluggy = row(el, PLUGGY_CARD.creditCardId);
    expect(pluggy.textContent).toContain("Banco A VISA 1234");
    expect(
      pluggy.querySelector("[data-credit-limit] lightning-formatted-number")
        .value
    ).toBe(5000);
    expect(pluggy.querySelector("[data-closing-day]").textContent).toBe("5");
    expect(pluggy.querySelector("[data-due-day]").textContent).toBe("12");
    const manual = row(el, MANUAL_CARD.creditCardId);
    expect(manual.querySelector("[data-credit-limit]").textContent).toContain(
      "AXF_CardStatement_notAvailable"
    );
    expect(
      manual.querySelector("[data-available-limit]").textContent
    ).toContain("AXF_CardStatement_notAvailable");
    expect(action(el, "define-closing", PLUGGY_CARD.creditCardId)).toBeNull();
    expect(
      action(el, "define-closing", MANUAL_CARD.creditCardId)
    ).not.toBeNull();
  });

  it("shows the empty state when no card is available", async () => {
    listCards.mockResolvedValue([]);
    const el = await build();
    expect(el.shadowRoot.querySelector("[data-no-cards]")).not.toBeNull();
  });

  it("defines the closing of a card without a calendar in one command", async () => {
    defineClosing.mockResolvedValue({
      ...MANUAL_CARD,
      hasCalendar: true,
      closingDay: 5,
      dueDay: 12,
      canDefineClosing: false
    });
    const el = await build();
    action(el, "define-closing", MANUAL_CARD.creditCardId).click();
    await settle();
    const inputs = [
      ...el.shadowRoot.querySelectorAll(
        `lightning-input[data-card="${MANUAL_CARD.creditCardId}"]`
      )
    ];
    expect(inputs).toHaveLength(2);
    const values = { closingDay: "5", dueDay: "12" };
    inputs.forEach((input) => {
      input.checkValidity = jest.fn(() => true);
      input.reportValidity = jest.fn();
      input.setCustomValidity = jest.fn();
      input.dispatchEvent(
        new CustomEvent("change", {
          detail: { value: values[input.dataset.closing] }
        })
      );
    });
    await settle();
    action(el, "save-closing", MANUAL_CARD.creditCardId).click();
    await settle();
    expect(JSON.parse(defineClosing.mock.calls[0][0].request)).toEqual({
      creditCardId: MANUAL_CARD.creditCardId,
      closingDay: 5,
      dueDay: 12
    });
    const manual = row(el, MANUAL_CARD.creditCardId);
    expect(manual.querySelector("[data-closing-day]").textContent).toBe("5");
    expect(manual.querySelector("[data-due-day]").textContent).toBe("12");
    expect(action(el, "define-closing", MANUAL_CARD.creditCardId)).toBeNull();
    expect(el.shadowRoot.querySelector("[data-message]").textContent).toContain(
      "AXF_CardStatement_closingSaved"
    );
  });

  it("rejects a closing day outside 1-31 without calling the server", async () => {
    const el = await build();
    action(el, "define-closing", MANUAL_CARD.creditCardId).click();
    await settle();
    const inputs = [
      ...el.shadowRoot.querySelectorAll(
        `lightning-input[data-card="${MANUAL_CARD.creditCardId}"]`
      )
    ];
    const validity = {};
    inputs.forEach((input) => {
      input.setCustomValidity = jest.fn((text) => {
        validity[input.dataset.closing] = text;
      });
      input.reportValidity = jest.fn();
      input.checkValidity = jest.fn(() => !validity[input.dataset.closing]);
      input.dispatchEvent(
        new CustomEvent("change", {
          detail: {
            value: input.dataset.closing === "closingDay" ? "32" : "10"
          }
        })
      );
    });
    await settle();
    action(el, "save-closing", MANUAL_CARD.creditCardId).click();
    await settle();
    expect(defineClosing).not.toHaveBeenCalled();
    expect(validity.closingDay).toBe("c.AXF_CardStatement_dayRange");
    expect(validity.dueDay).toBe("");
  });

  it("surfaces a refused closing as a sanitized message", async () => {
    defineClosing.mockRejectedValue({ body: { message: "NOT_ALLOWED" } });
    const el = await build();
    action(el, "define-closing", MANUAL_CARD.creditCardId).click();
    await settle();
    el.shadowRoot
      .querySelectorAll(
        `lightning-input[data-card="${MANUAL_CARD.creditCardId}"]`
      )
      .forEach((input) => {
        input.checkValidity = jest.fn(() => true);
        input.reportValidity = jest.fn();
        input.setCustomValidity = jest.fn();
        input.dispatchEvent(
          new CustomEvent("change", { detail: { value: "7" } })
        );
      });
    await settle();
    action(el, "save-closing", MANUAL_CARD.creditCardId).click();
    await settle();
    expect(el.shadowRoot.querySelector("[data-message]").textContent).toContain(
      "AXF_CardStatement_codeNOT_ALLOWED"
    );
    expect(listCards).toHaveBeenCalledTimes(2);
  });

  it("loads the invoice with window, closing, due and total and pages by month", async () => {
    const el = await build();
    await openInvoice(el, PLUGGY_CARD.creditCardId);
    const first = JSON.parse(getInvoice.mock.calls[0][0].request);
    expect(first.creditCardId).toBe(PLUGGY_CARD.creditCardId);
    expect(first.fromDate).toBeNull();
    expect(el.shadowRoot.querySelector("[data-window]").textContent).toContain(
      "AXF_CardStatement_invoiceWindow"
    );
    expect(el.shadowRoot.querySelector("[data-closing]")).not.toBeNull();
    expect(el.shadowRoot.querySelector("[data-due]")).not.toBeNull();
    expect(
      el.shadowRoot.querySelector("[data-total] lightning-formatted-number")
        .value
    ).toBe(200);
    expect(el.shadowRoot.querySelector("[data-no-calendar]")).toBeNull();
    const table = el.shadowRoot.querySelector("[data-lines]");
    expect(table.querySelector("caption")).not.toBeNull();
    expect(table.querySelectorAll("tbody tr[data-line]")).toHaveLength(2);
    expect(
      el.shadowRoot.querySelector(
        `[data-line="${DONE.recordId}"] [data-status]`
      ).textContent
    ).toContain("AXF_BankStatement_statusRECONCILED");

    getInvoice.mockResolvedValue(invoiceOf([FACT], { month: 8 }));
    action(el, "previous").click();
    await settle();
    const previous = JSON.parse(getInvoice.mock.calls[1][0].request);
    expect(previous).toMatchObject({ year: 2026, month: 8 });
    action(el, "next").click();
    await settle();
    expect(JSON.parse(getInvoice.mock.calls[2][0].request)).toMatchObject({
      year: 2026,
      month: 9
    });
  });

  it("flags an invoice without a calendar", async () => {
    getInvoice.mockResolvedValue(
      invoiceOf([FACT], {
        card: MANUAL_CARD,
        outcome: "BLOCKED",
        blockedReason: "NO_RULE",
        fromDate: "2026-09-01",
        toDate: "2026-09-30",
        closingDate: null,
        dueDate: null
      })
    );
    const el = await build();
    await openInvoice(el, MANUAL_CARD.creditCardId);
    expect(
      el.shadowRoot.querySelector("[data-no-calendar]").textContent
    ).toContain("AXF_CardStatement_noCalendar");
    expect(el.shadowRoot.querySelector("[data-closing]")).toBeNull();
    expect(el.shadowRoot.querySelector("[data-due]")).toBeNull();
  });

  it("applies description, amount and date filters together", async () => {
    const el = await build();
    await openInvoice(el, PLUGGY_CARD.creditCardId);
    const inputs = [
      ...el.shadowRoot.querySelectorAll("lightning-input[data-filter]")
    ];
    inputs.forEach((input) => {
      input.checkValidity = jest.fn(() => true);
      input.reportValidity = jest.fn();
      input.setCustomValidity = jest.fn();
    });
    const values = {
      fromDate: "2026-08-10",
      toDate: "2026-09-05",
      minAmount: "50",
      maxAmount: "150",
      term: "merc"
    };
    inputs.forEach((input) => {
      input.dispatchEvent(
        new CustomEvent("change", {
          detail: { value: values[input.dataset.field] }
        })
      );
    });
    await settle();
    action(el, "apply-filters").click();
    await settle();
    expect(JSON.parse(getInvoice.mock.calls[1][0].request)).toMatchObject({
      creditCardId: PLUGGY_CARD.creditCardId,
      fromDate: "2026-08-10",
      toDate: "2026-09-05",
      minAmount: 50,
      maxAmount: 150,
      term: "merc"
    });
    // The filter narrows lines inside the invoice: its window, closing and due stay shown.
    expect(el.shadowRoot.querySelector("[data-window]")).not.toBeNull();
    expect(el.shadowRoot.querySelector("[data-closing]")).not.toBeNull();
    expect(el.shadowRoot.querySelector("[data-due]")).not.toBeNull();
    expect(el.shadowRoot.querySelector("[data-period]").textContent).not.toBe(
      ""
    );
  });

  it("flags a partial total and other currencies left out of it", async () => {
    getInvoice.mockResolvedValue(
      invoiceOf([FACT], { truncated: true, mixedCurrency: true })
    );
    const el = await build();
    await openInvoice(el, PLUGGY_CARD.creditCardId);
    expect(
      el.shadowRoot.querySelector("[data-total-partial]").textContent
    ).toContain("AXF_CardStatement_totalPartial");
    expect(
      el.shadowRoot.querySelector("[data-mixed-currency]").textContent
    ).toContain("AXF_CardStatement_mixedCurrency");
  });

  it("clears the previous invoice when the new one fails to load", async () => {
    const el = await build();
    await openInvoice(el, PLUGGY_CARD.creditCardId);
    expect(el.shadowRoot.querySelector("[data-lines]")).not.toBeNull();
    getInvoice.mockRejectedValueOnce({ body: { message: "NOT_ACCESSIBLE" } });
    action(el, "view", MANUAL_CARD.creditCardId).click();
    await settle();
    expect(el.shadowRoot.querySelector("[data-lines]")).toBeNull();
    expect(el.shadowRoot.querySelector("[data-total]")).toBeNull();
    expect(el.shadowRoot.querySelector("[data-message]").textContent).toContain(
      "AXF_CardStatement_codeNOT_ACCESSIBLE"
    );
  });

  it("blocks an inverted amount range on the client", async () => {
    const el = await build();
    await openInvoice(el, PLUGGY_CARD.creditCardId);
    const validity = {};
    const inputs = [
      ...el.shadowRoot.querySelectorAll("lightning-input[data-filter]")
    ];
    inputs.forEach((input) => {
      input.setCustomValidity = jest.fn((text) => {
        validity[input.dataset.field] = text;
      });
      input.reportValidity = jest.fn();
      input.checkValidity = jest.fn(() => !validity[input.dataset.field]);
      const value = { minAmount: "200", maxAmount: "100" }[input.dataset.field];
      if (value) {
        input.dispatchEvent(new CustomEvent("change", { detail: { value } }));
      }
    });
    await settle();
    action(el, "apply-filters").click();
    await settle();
    expect(getInvoice).toHaveBeenCalledTimes(1);
    expect(validity.maxAmount).toBe("c.AXF_BankStatement_filterAmountOrder");
  });

  it("confirms a suggestion with one click and reloads the invoice", async () => {
    listSuggestions.mockResolvedValue({
      items: [SUGGESTION],
      truncated: false
    });
    confirmSuggestion.mockResolvedValue({ allocationId: "a04" });
    const el = await build();
    await openInvoice(el, PLUGGY_CARD.creditCardId);
    action(el, "toggle-suggestions", FACT.recordId).click();
    await settle();
    expect(JSON.parse(listSuggestions.mock.calls[0][0].request)).toEqual({
      creditCardId: PLUGGY_CARD.creditCardId,
      lineKind: "FACT",
      recordId: FACT.recordId
    });
    getInvoice.mockResolvedValue(
      invoiceOf([{ ...FACT, status: "RECONCILED", canSuggest: false }])
    );
    action(el, "confirm-suggestion").click();
    await settle();
    const payload = JSON.parse(confirmSuggestion.mock.calls[0][0].request);
    expect(payload).toMatchObject({
      creditCardId: PLUGGY_CARD.creditCardId,
      sourceId: SUGGESTION.sourceId,
      sourceVersion: 0,
      targetId: SUGGESTION.targetId,
      targetVersion: 2
    });
    expect(typeof payload.operationKey).toBe("string");
    expect(getInvoice).toHaveBeenCalledTimes(2);
    expect(el.shadowRoot.querySelector("[data-message]").textContent).toContain(
      "AXF_BankStatement_confirmed"
    );
    expect(
      el.shadowRoot.querySelector(
        `[data-line="${FACT.recordId}"] [data-status]`
      ).textContent
    ).toContain("AXF_BankStatement_statusRECONCILED");
  });

  it("turns a refused confirmation into a message and reloads the invoice", async () => {
    listSuggestions.mockResolvedValue({
      items: [SUGGESTION],
      truncated: false
    });
    confirmSuggestion.mockRejectedValue({
      body: { message: "ALREADY_LINKED" }
    });
    const el = await build();
    await openInvoice(el, PLUGGY_CARD.creditCardId);
    action(el, "toggle-suggestions", FACT.recordId).click();
    await settle();
    action(el, "confirm-suggestion").click();
    await settle();
    expect(el.shadowRoot.querySelector("[data-message]").textContent).toContain(
      "AXF_BankStatement_codeALREADY_LINKED"
    );
    expect(getInvoice).toHaveBeenCalledTimes(2);
  });

  it("shows an explicit empty suggestion list", async () => {
    listSuggestions.mockResolvedValue({ items: [], truncated: false });
    const el = await build();
    await openInvoice(el, PLUGGY_CARD.creditCardId);
    action(el, "toggle-suggestions", FACT.recordId).click();
    await settle();
    expect(el.shadowRoot.querySelector("[data-no-suggestions]")).not.toBeNull();
  });

  it("hides suggestions when the invoice is read-only", async () => {
    getInvoice.mockResolvedValue(invoiceOf([FACT], { canReconcile: false }));
    const el = await build();
    await openInvoice(el, PLUGGY_CARD.creditCardId);
    expect(action(el, "toggle-suggestions", FACT.recordId)).toBeNull();
  });

  it("opens the entry wizard with the selected card", async () => {
    const el = await build();
    await openInvoice(el, PLUGGY_CARD.creditCardId);
    action(el, "new-expense").click();
    expect(mockNavigate).toHaveBeenCalledWith({
      type: "standard__navItemPage",
      attributes: { apiName: "AXF_EntryWizard" },
      state: {
        c__creditCardId: PLUGGY_CARD.creditCardId,
        c__accountId: PLUGGY_CARD.holderId
      }
    });
  });

  it("ignores a late answer to an older invoice request", async () => {
    let resolveOld;
    const el = await build();
    getInvoice.mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          resolveOld = resolve;
        })
    );
    action(el, "view", PLUGGY_CARD.creditCardId).click();
    await settle();
    getInvoice.mockResolvedValueOnce(invoiceOf([DONE]));
    action(el, "view", MANUAL_CARD.creditCardId).click();
    await settle();
    resolveOld(invoiceOf([FACT, DONE]));
    await settle();
    expect(
      el.shadowRoot.querySelectorAll("[data-lines] tbody tr[data-line]")
    ).toHaveLength(1);
  });
});
