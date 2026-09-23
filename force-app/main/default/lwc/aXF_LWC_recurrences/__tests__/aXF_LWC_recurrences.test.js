import { createElement } from "lwc";
import Recurrences from "c/aXF_LWC_recurrences";
import { CurrentPageReference } from "lightning/navigation";
import getContext from "@salesforce/apex/AXF_CLS_CTRL_Recurrences.getContext";
import getSources from "@salesforce/apex/AXF_CLS_CTRL_Recurrences.getSources";
import listRecurrences from "@salesforce/apex/AXF_CLS_CTRL_Recurrences.listRecurrences";
import getDetail from "@salesforce/apex/AXF_CLS_CTRL_Recurrences.getDetail";
import createRecurrence from "@salesforce/apex/AXF_CLS_CTRL_Recurrences.createRecurrence";
import editAmount from "@salesforce/apex/AXF_CLS_CTRL_Recurrences.editAmount";
import terminate from "@salesforce/apex/AXF_CLS_CTRL_Recurrences.terminate";

jest.mock("lightning/navigation", () => {
  const {
    createTestWireAdapter
  } = require("@salesforce/wire-service-jest-util");
  return { CurrentPageReference: createTestWireAdapter(jest.fn()) };
});
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Recurrences.getContext",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Recurrences.getSources",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Recurrences.listRecurrences",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Recurrences.getDetail",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Recurrences.createRecurrence",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Recurrences.editAmount",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Recurrences.terminate",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const HOLDER = { accountId: "001000000000001", label: "Ana" };
const WALLET = {
  bankAccountId: "a01000000000001",
  creditCardId: null,
  label: "Carteira",
  kind: "WALLET",
  currencyIsoCode: "BRL"
};
const CARD = {
  bankAccountId: null,
  creditCardId: "a02000000000001",
  label: "Cartao 1234",
  kind: "CREDIT_CARD",
  currencyIsoCode: "USD"
};

function isoOffset(days) {
  const d = new Date();
  d.setDate(d.getDate() + days);
  const pad = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}
const WEEKLY = {
  scheduleId: "a0S000000000001",
  holderId: HOLDER.accountId,
  holderLabel: "Ana",
  description: "Mão de obra",
  direction: "DEBIT",
  currencyIsoCode: "BRL",
  amount: 300,
  periodDays: 7,
  periodMonths: null,
  bankAccountId: WALLET.bankAccountId,
  sourceKind: "WALLET",
  sourceLabel: "Carteira",
  nextDueDate: "2026-10-02",
  state: "ACTIVE",
  version: 0,
  lastDueDate: isoOffset(60)
};
const ENDED = {
  ...WEEKLY,
  scheduleId: "a0S000000000002",
  description: "Aluguel",
  direction: "CREDIT",
  periodDays: null,
  periodMonths: 6,
  nextDueDate: null,
  state: "ENDED",
  terminationDate: "2026-09-20",
  version: 3
};
const MONTHLY = {
  ...WEEKLY,
  scheduleId: "a0S000000000003",
  description: "Luz",
  periodDays: null,
  periodMonths: 1
};
const DETAIL = {
  recurrence: WEEKLY,
  truncated: false,
  unverified: false,
  occurrences: [
    {
      transactionId: "a0X000000000001",
      sequence: 1,
      dueDate: "2026-10-02",
      amount: 300,
      status: "RECONCILED"
    },
    {
      transactionId: "a0X000000000002",
      sequence: 2,
      dueDate: "2026-10-09",
      amount: 350,
      status: "PLANNED"
    },
    {
      transactionId: "a0X000000000003",
      sequence: 3,
      dueDate: "2026-10-16",
      amount: 350,
      status: "CANCELLED"
    }
  ]
};

const settle = async () => {
  for (let i = 0; i < 8; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};

async function build(context = { canUse: true, canManage: true }) {
  const el = createElement("c-a-x-f_-l-w-c_recurrences", {
    is: Recurrences
  });
  document.body.appendChild(el);
  getContext.emit({ holders: [HOLDER], ...context });
  await settle();
  return el;
}

function action(el, name, id) {
  const selector = id
    ? `[data-action="${name}"][data-id="${id}"]`
    : `[data-action="${name}"]`;
  return el.shadowRoot.querySelector(selector);
}

function row(el, id) {
  return el.shadowRoot.querySelector(`[data-recurrence-row="${id}"]`);
}

function field(el, name) {
  return el.shadowRoot.querySelector(`[data-field="${name}"]`);
}

function change(target, value) {
  target.value = value;
  target.dispatchEvent(new CustomEvent("change", { detail: { value } }));
}

function lastRequest(mock) {
  const calls = mock.mock.calls;
  return JSON.parse(calls[calls.length - 1][0].request);
}

describe("c-a-x-f_-l-w-c_recurrences", () => {
  beforeEach(() => {
    listRecurrences.mockResolvedValue([WEEKLY, ENDED, MONTHLY]);
    getSources.mockResolvedValue([WALLET, CARD]);
    getDetail.mockResolvedValue(DETAIL);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("lists recurrences with frequency, nature, origin and state from labels", async () => {
    const el = await build();
    const weekly = row(el, WEEKLY.scheduleId);
    expect(weekly.querySelector("[data-period]").textContent).toMatch(
      /AXF_Recurrences_periodWEEKLY/
    );
    expect(weekly.querySelector("[data-nature]").textContent).toMatch(
      /AXF_Recurrences_natureDEBIT/
    );
    expect(weekly.querySelector("[data-source]").textContent).toBe("Carteira");
    expect(weekly.querySelector("[data-state]").textContent).toMatch(
      /AXF_Recurrences_stateACTIVE/
    );
    const ended = row(el, ENDED.scheduleId);
    expect(ended.querySelector("[data-period]").textContent).toMatch(
      /AXF_Recurrences_periodEveryMonths/
    );
    expect(ended.querySelector("[data-nature]").textContent).toMatch(
      /AXF_Recurrences_natureCREDIT/
    );
    expect(ended.querySelector("[data-state]").textContent).toMatch(
      /AXF_Recurrences_stateENDED/
    );
    expect(ended.querySelector("[data-next-due]").textContent).toMatch(
      /AXF_Recurrences_notAvailable/
    );
    expect(
      row(el, MONTHLY.scheduleId).querySelector("[data-period]").textContent
    ).toMatch(/AXF_Recurrences_periodMONTHLY/);
    // An ended recurrence can be read but never edited or ended again.
    expect(action(el, "edit", ENDED.scheduleId)).toBeNull();
    expect(action(el, "end", ENDED.scheduleId)).toBeNull();
    expect(action(el, "edit", WEEKLY.scheduleId)).not.toBeNull();
  });

  it("shows the empty state and the missing capability", async () => {
    listRecurrences.mockResolvedValue([]);
    const el = await build();
    expect(el.shadowRoot.querySelector("[data-empty]")).not.toBeNull();

    const blocked = await build({ canUse: false, canManage: false });
    expect(
      blocked.shadowRoot.querySelector("[data-no-capability]")
    ).not.toBeNull();
  });

  it("is read-only for a participant", async () => {
    const el = await build({ canUse: true, canManage: false });
    expect(el.shadowRoot.querySelector("[data-read-only]")).not.toBeNull();
    expect(el.shadowRoot.querySelector("[data-new]")).toBeNull();
    expect(action(el, "edit", WEEKLY.scheduleId)).toBeNull();
    expect(action(el, "end", WEEKLY.scheduleId)).toBeNull();
    expect(action(el, "view", WEEKLY.scheduleId)).not.toBeNull();
  });

  it("creates a weekly recurrence with its origin", async () => {
    createRecurrence.mockResolvedValue({
      scheduleId: "a0S000000000009",
      changedCount: 48,
      protectedCount: 0,
      replay: false
    });
    const el = await build();
    el.shadowRoot.querySelector("[data-new]").click();
    await settle();
    expect(getSources).toHaveBeenCalledWith({
      request: JSON.stringify({ accountId: HOLDER.accountId })
    });
    change(field(el, "description"), "Mão de obra");
    change(field(el, "amount"), "300");
    change(field(el, "firstDueDate"), isoOffset(7));
    change(field(el, "periodicity"), "WEEKLY");
    change(field(el, "sourceKey"), `BANK:${WALLET.bankAccountId}`);
    await settle();
    action(el, "create").click();
    await settle();

    const request = lastRequest(createRecurrence);
    expect(request).toMatchObject({
      accountId: HOLDER.accountId,
      description: "Mão de obra",
      direction: "DEBIT",
      amount: 300,
      currencyIsoCode: "BRL",
      firstDueDate: isoOffset(7),
      periodDays: 7,
      periodMonths: null,
      bankAccountId: WALLET.bankAccountId,
      creditCardId: null
    });
    expect(request.operationKey).toBeTruthy();
    expect(el.shadowRoot.querySelector("[data-message]").textContent).toMatch(
      /AXF_Recurrences_created/
    );
    expect(el.shadowRoot.querySelector("[data-form]")).toBeNull();
    expect(listRecurrences).toHaveBeenCalledTimes(2);
  });

  it("sends a custom interval in months and a card origin", async () => {
    createRecurrence.mockResolvedValue({ changedCount: 4 });
    const el = await build();
    el.shadowRoot.querySelector("[data-new]").click();
    await settle();
    change(field(el, "description"), "Seguro");
    change(field(el, "direction"), "CREDIT");
    change(field(el, "amount"), "120.50");
    change(field(el, "periodicity"), "CUSTOM");
    await settle();
    change(field(el, "periodMonths"), "6");
    change(field(el, "sourceKey"), `CARD:${CARD.creditCardId}`);
    action(el, "create").click();
    await settle();
    expect(lastRequest(createRecurrence)).toMatchObject({
      currencyIsoCode: "USD",
      direction: "CREDIT",
      amount: 120.5,
      periodDays: null,
      periodMonths: 6,
      bankAccountId: null,
      creditCardId: CARD.creditCardId
    });
  });

  it("refuses an incomplete form on the client and shows server codes", async () => {
    const el = await build();
    el.shadowRoot.querySelector("[data-new]").click();
    await settle();
    change(field(el, "description"), "Água");
    change(field(el, "amount"), "80");
    action(el, "create").click();
    await settle();
    expect(createRecurrence).not.toHaveBeenCalled();
    expect(
      el.shadowRoot.querySelector("[data-form-error]").textContent
    ).toMatch(/AXF_Recurrences_formInvalid/);

    createRecurrence.mockRejectedValue({ body: { message: "TOO_LARGE" } });
    change(field(el, "sourceKey"), `BANK:${WALLET.bankAccountId}`);
    action(el, "create").click();
    await settle();
    expect(
      el.shadowRoot.querySelector("[data-form-error]").textContent
    ).toMatch(/AXF_Recurrences_codeTOO_LARGE/);

    action(el, "cancel-form").click();
    await settle();
    expect(el.shadowRoot.querySelector("[data-form]")).toBeNull();
  });

  it("opens pre-filled from the entry wizard hand-over", async () => {
    const el = await build();
    CurrentPageReference.emit({
      state: {
        c__accountId: HOLDER.accountId,
        c__direction: "CREDIT",
        c__amount: "900",
        c__firstDueDate: "2026-11-05",
        c__currencyIsoCode: "BRL",
        c__creditCardId: CARD.creditCardId,
        c__description: "Aluguel"
      }
    });
    await settle();
    expect(el.shadowRoot.querySelector("[data-form]")).not.toBeNull();
    expect(field(el, "accountId").value).toBe(HOLDER.accountId);
    expect(field(el, "direction").value).toBe("CREDIT");
    expect(Number(field(el, "amount").value)).toBe(900);
    expect(field(el, "firstDueDate").value).toBe("2026-11-05");
    expect(field(el, "sourceKey").value).toBe(`CARD:${CARD.creditCardId}`);
    expect(field(el, "description").value).toBe("Aluguel");
    expect(field(el, "currencyIsoCode").value).toBe("USD");
    expect(field(el, "firstDueDate").min).toMatch(/^\d{4}-\d{2}-01$/);
    expect(field(el, "firstDueDate").max).toBeTruthy();
  });

  it("shows the occurrences of a recurrence with their status", async () => {
    const el = await build();
    action(el, "view", WEEKLY.scheduleId).click();
    await settle();
    expect(getDetail).toHaveBeenCalledWith({
      request: JSON.stringify({ scheduleId: WEEKLY.scheduleId })
    });
    const statuses = Array.from(
      el.shadowRoot.querySelectorAll("[data-occurrence-status]")
    ).map((node) => node.textContent);
    expect(statuses[0]).toMatch(/AXF_Recurrences_occRECONCILED/);
    expect(statuses[1]).toMatch(/AXF_Recurrences_occPLANNED/);
    expect(statuses[2]).toMatch(/AXF_Recurrences_occCANCELLED/);

    action(el, "close-detail").click();
    await settle();
    expect(el.shadowRoot.querySelector("[data-detail]")).toBeNull();
  });

  it("edits the amount with the optimistic version and an operation key", async () => {
    editAmount.mockResolvedValue({ changedCount: 3, protectedCount: 1 });
    const el = await build();
    action(el, "view", WEEKLY.scheduleId).click();
    await settle();
    action(el, "edit", WEEKLY.scheduleId).click();
    await settle();
    const input = el.shadowRoot.querySelector("[data-edit-amount]");
    change(input, "350");
    action(el, "save-amount").click();
    await settle();

    const request = lastRequest(editAmount);
    expect(request).toMatchObject({
      scheduleId: WEEKLY.scheduleId,
      amount: 350,
      expectedVersion: 0
    });
    expect(request.operationKey).toBeTruthy();
    expect(el.shadowRoot.querySelector("[data-message]").textContent).toMatch(
      /AXF_Recurrences_amountSaved/
    );
    expect(getDetail).toHaveBeenCalledTimes(2);
  });

  it("ends a recurrence and reloads on a conflict", async () => {
    terminate.mockRejectedValueOnce({ body: { message: "CONFLICT" } });
    terminate.mockResolvedValueOnce({ changedCount: 5, protectedCount: 0 });
    const el = await build();
    action(el, "end", WEEKLY.scheduleId).click();
    await settle();
    const date = el.shadowRoot.querySelector("[data-end-date]");
    change(date, isoOffset(1));
    action(el, "confirm-end").click();
    await settle();
    expect(lastRequest(terminate)).toMatchObject({
      scheduleId: WEEKLY.scheduleId,
      terminationDate: isoOffset(1),
      expectedVersion: 0
    });
    expect(el.shadowRoot.querySelector("[data-message]").textContent).toMatch(
      /AXF_Recurrences_codeCONFLICT/
    );
    expect(listRecurrences).toHaveBeenCalledTimes(2);

    action(el, "end", WEEKLY.scheduleId).click();
    await settle();
    action(el, "confirm-end").click();
    await settle();
    expect(el.shadowRoot.querySelector("[data-message]").textContent).toMatch(
      /AXF_Recurrences_ended/
    );
  });

  it("refuses a first due date outside the creation window", async () => {
    const el = await build();
    el.shadowRoot.querySelector("[data-new]").click();
    await settle();
    change(field(el, "description"), "Água");
    change(field(el, "amount"), "80");
    change(field(el, "sourceKey"), `BANK:${WALLET.bankAccountId}`);
    change(field(el, "firstDueDate"), "2020-01-01");
    action(el, "create").click();
    await settle();
    change(field(el, "firstDueDate"), isoOffset(800));
    action(el, "create").click();
    await settle();
    expect(createRecurrence).not.toHaveBeenCalled();
    expect(
      el.shadowRoot.querySelector("[data-form-error]").textContent
    ).toMatch(/AXF_Recurrences_formInvalid/);
  });

  it("only ends between today and the last persisted occurrence", async () => {
    terminate.mockResolvedValue({ changedCount: 1, protectedCount: 0 });
    const el = await build();
    action(el, "end", WEEKLY.scheduleId).click();
    await settle();
    const date = el.shadowRoot.querySelector("[data-end-date]");
    expect(date.max).toBe(WEEKLY.lastDueDate);
    change(date, "2020-01-01");
    action(el, "confirm-end").click();
    await settle();
    change(date, isoOffset(61));
    action(el, "confirm-end").click();
    await settle();
    expect(terminate).not.toHaveBeenCalled();
    expect(el.shadowRoot.querySelector("[data-message]").textContent).toMatch(
      /AXF_Recurrences_codeINVALID_INPUT/
    );
    change(date, WEEKLY.lastDueDate);
    action(el, "confirm-end").click();
    await settle();
    expect(lastRequest(terminate).terminationDate).toBe(WEEKLY.lastDueDate);
  });

  it("refuses an invalid new amount without calling the server", async () => {
    const el = await build();
    action(el, "edit", WEEKLY.scheduleId).click();
    await settle();
    change(el.shadowRoot.querySelector("[data-edit-amount]"), "1.234");
    action(el, "save-amount").click();
    await settle();
    expect(editAmount).not.toHaveBeenCalled();
    expect(el.shadowRoot.querySelector("[data-message]").textContent).toMatch(
      /AXF_Recurrences_codeINVALID_INPUT/
    );
    action(el, "cancel-change").click();
    await settle();
    expect(el.shadowRoot.querySelector("[data-edit-amount]")).toBeNull();
  });
});
