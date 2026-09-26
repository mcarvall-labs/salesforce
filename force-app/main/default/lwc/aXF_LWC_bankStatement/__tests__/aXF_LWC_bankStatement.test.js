import { createElement } from "lwc";
import BankStatement from "c/aXF_LWC_bankStatement";
import getContext from "@salesforce/apex/AXF_CLS_CTRL_BankStatement.getContext";
import listAccounts from "@salesforce/apex/AXF_CLS_CTRL_BankStatement.listAccounts";
import getStatement from "@salesforce/apex/AXF_CLS_CTRL_BankStatement.getStatement";
import listSuggestions from "@salesforce/apex/AXF_CLS_CTRL_BankStatement.listSuggestions";
import confirmSuggestion from "@salesforce/apex/AXF_CLS_CTRL_BankStatement.confirmSuggestion";
import updateBalance from "@salesforce/apex/AXF_CLS_CTRL_BankStatement.updateBalance";
import refreshBalance from "@salesforce/apex/AXF_CLS_CTRL_BankStatement.refreshBalance";

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
  "@salesforce/apex/AXF_CLS_CTRL_BankStatement.getContext",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_BankStatement.listAccounts",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_BankStatement.getStatement",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_BankStatement.listSuggestions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_BankStatement.confirmSuggestion",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_BankStatement.updateBalance",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_BankStatement.refreshBalance",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const BANK = {
  bankAccountId: "a01000000000001",
  holderId: "001000000000001",
  holderLabel: "Ana",
  institutionName: "Banco A",
  numberMasked: "****1234",
  wallet: false,
  hasConnection: true,
  currentBalance: 1500,
  currencyIso: "BRL",
  version: 3,
  canEditBalance: false,
  canRefresh: true
};
const WALLET = {
  bankAccountId: "a01000000000002",
  holderId: "001000000000001",
  holderLabel: "Ana",
  institutionName: null,
  numberMasked: null,
  wallet: true,
  hasConnection: false,
  currentBalance: 80,
  currencyIso: "BRL",
  version: 1,
  canEditBalance: true,
  canRefresh: false
};
const FACT = {
  lineKind: "FACT",
  recordId: "a02000000000001",
  lineDate: "2026-09-10",
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
  recordId: "a02000000000002",
  description: "Aluguel",
  status: "RECONCILED",
  canSuggest: false
};
function statementOf(lines, extra = {}) {
  return {
    account: WALLET,
    year: 2026,
    month: 9,
    fromDate: "2026-09-01",
    toDate: "2026-09-30",
    customPeriod: false,
    truncated: false,
    lines,
    ...extra
  };
}
const SUGGESTION = {
  sourceId: "a02000000000001",
  sourceVersion: 0,
  targetId: "a03000000000001",
  targetVersion: 2,
  candidateId: "a03000000000001",
  candidateDate: "2026-09-16",
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

async function build(context = { canUse: true, canConfigure: true }) {
  const el = createElement("c-a-x-f_-l-w-c_bank-statement", {
    is: BankStatement
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

async function openStatement(el, id) {
  action(el, "view", id).click();
  await settle();
}

beforeEach(() => {
  listAccounts.mockResolvedValue([BANK, WALLET]);
  getStatement.mockResolvedValue(statementOf([FACT, DONE]));
});

afterEach(() => {
  while (document.body.firstChild) {
    document.body.removeChild(document.body.firstChild);
  }
  jest.clearAllMocks();
});

describe("c-aXF_LWC_bankStatement", () => {
  it("shows only the no-capability message without the capability", async () => {
    const el = await build({ canUse: false, canConfigure: false });
    expect(el.shadowRoot.querySelector("[data-no-capability]")).not.toBeNull();
    expect(listAccounts).not.toHaveBeenCalled();
    expect(el.shadowRoot.querySelector("[data-accounts]")).toBeNull();
  });

  it("lists bank accounts and wallets with the right balance action", async () => {
    const el = await build();
    const table = el.shadowRoot.querySelector("[data-accounts]");
    expect(table.querySelector("caption").textContent).toContain(
      "AXF_BankStatement_accountsCaption"
    );
    const rows = table.querySelectorAll("tbody tr");
    expect(rows).toHaveLength(2);
    expect(rows[0].textContent).toContain("Banco A ****1234");
    expect(rows[1].textContent).toContain("AXF_BankStatement_wallet");
    expect(action(el, "refresh", BANK.bankAccountId)).not.toBeNull();
    expect(action(el, "edit-balance", BANK.bankAccountId)).toBeNull();
    expect(action(el, "refresh", WALLET.bankAccountId)).toBeNull();
    expect(action(el, "edit-balance", WALLET.bankAccountId)).not.toBeNull();
  });

  it("shows the empty state when no account is available", async () => {
    listAccounts.mockResolvedValue([]);
    const el = await build();
    expect(el.shadowRoot.querySelector("[data-no-accounts]")).not.toBeNull();
  });

  it("loads the statement, pages by month and applies combined filters", async () => {
    const el = await build();
    await openStatement(el, WALLET.bankAccountId);
    const first = JSON.parse(getStatement.mock.calls[0][0].request);
    expect(first.bankAccountId).toBe(WALLET.bankAccountId);
    expect(first.fromDate).toBeNull();
    const table = el.shadowRoot.querySelector("[data-lines]");
    expect(table.querySelector("caption")).not.toBeNull();
    expect(table.querySelectorAll("tbody tr[data-line]")).toHaveLength(2);
    expect(
      el.shadowRoot.querySelector('[data-line="a02000000000002"] [data-status]')
        .textContent
    ).toContain("AXF_BankStatement_statusRECONCILED");

    action(el, "previous").click();
    await settle();
    const previous = JSON.parse(getStatement.mock.calls[1][0].request);
    expect(previous.year).toBe(2026);
    expect(previous.month).toBe(8);

    getStatement.mockResolvedValue(statementOf([FACT], { month: 8 }));
    const inputs = [
      ...el.shadowRoot.querySelectorAll("lightning-input[data-filter]")
    ];
    inputs.forEach((input) => {
      input.checkValidity = jest.fn(() => true);
      input.reportValidity = jest.fn();
    });
    const values = {
      fromDate: "2026-09-05",
      toDate: "2026-09-20",
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
    const filtered = JSON.parse(getStatement.mock.calls[2][0].request);
    expect(filtered).toMatchObject({
      fromDate: "2026-09-05",
      toDate: "2026-09-20",
      minAmount: 50,
      maxAmount: 150,
      term: "merc"
    });
  });

  it("confirms a suggestion with one click and reloads the statement", async () => {
    listSuggestions.mockResolvedValue({
      items: [SUGGESTION],
      truncated: false
    });
    confirmSuggestion.mockResolvedValue({ allocationId: "a04" });
    const el = await build();
    await openStatement(el, WALLET.bankAccountId);
    action(el, "toggle-suggestions", FACT.recordId).click();
    await settle();
    const request = JSON.parse(listSuggestions.mock.calls[0][0].request);
    expect(request).toEqual({
      bankAccountId: WALLET.bankAccountId,
      lineKind: "FACT",
      recordId: FACT.recordId
    });
    const button = action(el, "confirm-suggestion");
    expect(button.label).toContain("AXF_BankStatement_suggestionAction");
    getStatement.mockResolvedValue(
      statementOf([{ ...FACT, status: "RECONCILED", canSuggest: false }])
    );
    button.click();
    await settle();
    const payload = JSON.parse(confirmSuggestion.mock.calls[0][0].request);
    expect(payload).toMatchObject({
      bankAccountId: WALLET.bankAccountId,
      sourceId: SUGGESTION.sourceId,
      sourceVersion: 0,
      targetId: SUGGESTION.targetId,
      targetVersion: 2
    });
    expect(typeof payload.operationKey).toBe("string");
    expect(getStatement).toHaveBeenCalledTimes(2);
    expect(el.shadowRoot.querySelector("[data-message]").textContent).toContain(
      "AXF_BankStatement_confirmed"
    );
    expect(
      el.shadowRoot.querySelector(
        `[data-line="${FACT.recordId}"] [data-status]`
      ).textContent
    ).toContain("AXF_BankStatement_statusRECONCILED");
  });

  it("turns a refused confirmation into a message and reloads the line", async () => {
    listSuggestions.mockResolvedValue({
      items: [SUGGESTION],
      truncated: false
    });
    confirmSuggestion.mockRejectedValue({ body: { message: "CONFLICT" } });
    const el = await build();
    await openStatement(el, WALLET.bankAccountId);
    action(el, "toggle-suggestions", FACT.recordId).click();
    await settle();
    action(el, "confirm-suggestion").click();
    await settle();
    expect(el.shadowRoot.querySelector("[data-message]").textContent).toContain(
      "AXF_BankStatement_codeCONFLICT"
    );
    expect(getStatement).toHaveBeenCalledTimes(2);
  });

  it("shows an explicit empty suggestion list", async () => {
    listSuggestions.mockResolvedValue({ items: [], truncated: false });
    const el = await build();
    await openStatement(el, WALLET.bankAccountId);
    action(el, "toggle-suggestions", FACT.recordId).click();
    await settle();
    expect(el.shadowRoot.querySelector("[data-no-suggestions]")).not.toBeNull();
  });

  it("edits a wallet balance with the expected version", async () => {
    updateBalance.mockResolvedValue({
      ...WALLET,
      currentBalance: 55,
      version: 2
    });
    const el = await build();
    action(el, "edit-balance", WALLET.bankAccountId).click();
    await settle();
    const input = el.shadowRoot.querySelector(
      `lightning-input[data-balance="${WALLET.bankAccountId}"]`
    );
    input.reportValidity = jest.fn(() => true);
    input.dispatchEvent(new CustomEvent("change", { detail: { value: "55" } }));
    await settle();
    action(el, "save-balance", WALLET.bankAccountId).click();
    await settle();
    expect(JSON.parse(updateBalance.mock.calls[0][0].request)).toEqual({
      bankAccountId: WALLET.bankAccountId,
      balance: 55,
      expectedVersion: 1
    });
    expect(el.shadowRoot.querySelector("[data-message]").textContent).toContain(
      "AXF_BankStatement_balanceSaved"
    );
  });

  it("reloads the accounts when the balance version is stale", async () => {
    updateBalance.mockRejectedValue({ body: { message: "CONFLICT" } });
    const el = await build();
    action(el, "edit-balance", WALLET.bankAccountId).click();
    await settle();
    const input = el.shadowRoot.querySelector(
      `lightning-input[data-balance="${WALLET.bankAccountId}"]`
    );
    input.reportValidity = jest.fn(() => true);
    input.dispatchEvent(new CustomEvent("change", { detail: { value: "10" } }));
    await settle();
    action(el, "save-balance", WALLET.bankAccountId).click();
    await settle();
    expect(listAccounts).toHaveBeenCalledTimes(2);
    expect(el.shadowRoot.querySelector("[data-message]").textContent).toContain(
      "AXF_BankStatement_codeCONFLICT"
    );
  });

  it("refreshes a connected account from Pluggy", async () => {
    refreshBalance.mockResolvedValue({
      state: "SUCCEEDED",
      complete: true,
      account: { ...BANK, currentBalance: 1600 }
    });
    const el = await build();
    action(el, "refresh", BANK.bankAccountId).click();
    await settle();
    expect(JSON.parse(refreshBalance.mock.calls[0][0].request)).toEqual({
      bankAccountId: BANK.bankAccountId
    });
    expect(el.shadowRoot.querySelector("[data-message]").textContent).toContain(
      "AXF_BankStatement_refreshDone"
    );
  });

  it("opens the entry wizard with the selected account", async () => {
    const el = await build();
    await openStatement(el, WALLET.bankAccountId);
    action(el, "new-entry").click();
    expect(mockNavigate).toHaveBeenCalledWith({
      type: "standard__navItemPage",
      attributes: { apiName: "AXF_EntryWizard" },
      state: {
        c__bankAccountId: WALLET.bankAccountId,
        c__accountId: WALLET.holderId
      }
    });
  });

  async function typeFilters(el, values) {
    const inputs = [
      ...el.shadowRoot.querySelectorAll("lightning-input[data-filter]")
    ];
    inputs.forEach((input) => {
      let message = "";
      input.setCustomValidity = jest.fn((m) => {
        message = m;
      });
      input.checkValidity = jest.fn(() => !message);
      input.reportValidity = jest.fn();
    });
    inputs.forEach((input) => {
      input.dispatchEvent(
        new CustomEvent("change", {
          detail: { value: values[input.dataset.field] ?? null }
        })
      );
    });
    await settle();
    return inputs;
  }

  it.each([
    [{ fromDate: "2026-09-05" }, "toDate", "filterPeriodIncomplete"],
    [
      { fromDate: "2026-09-20", toDate: "2026-09-05" },
      "toDate",
      "filterPeriodOrder"
    ],
    [
      { fromDate: "2025-09-01", toDate: "2026-09-02" },
      "toDate",
      "filterPeriodTooLong"
    ],
    [{ minAmount: "200", maxAmount: "100" }, "maxAmount", "filterAmountOrder"]
  ])("keeps invalid filters %j on the client", async (values, field, label) => {
    const el = await build();
    await openStatement(el, WALLET.bankAccountId);
    const inputs = await typeFilters(el, values);
    action(el, "apply-filters").click();
    await settle();
    expect(getStatement).toHaveBeenCalledTimes(1);
    const target = inputs.find((i) => i.dataset.field === field);
    expect(target.setCustomValidity).toHaveBeenCalledWith(
      `c.AXF_BankStatement_${label}`
    );
    expect(el.shadowRoot.querySelector("[data-lines]")).not.toBeNull();
  });

  it("ignores a late answer to an older statement request", async () => {
    const el = await build();
    await openStatement(el, WALLET.bankAccountId);
    let resolveOld;
    getStatement.mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          resolveOld = resolve;
        })
    );
    getStatement.mockResolvedValueOnce(statementOf([DONE], { month: 10 }));
    action(el, "previous").click();
    action(el, "next").click();
    await settle();
    resolveOld(statementOf([FACT], { month: 8 }));
    await settle();
    const rows = el.shadowRoot.querySelectorAll("tbody tr[data-line]");
    expect(rows).toHaveLength(1);
    expect(rows[0].dataset.line).toBe(DONE.recordId);
  });

  it("hides suggestions when the statement is read-only", async () => {
    getStatement.mockResolvedValue(
      statementOf([FACT], { canReconcile: false })
    );
    const el = await build();
    await openStatement(el, WALLET.bankAccountId);
    expect(el.shadowRoot.querySelector("[data-lines]")).not.toBeNull();
    expect(action(el, "toggle-suggestions")).toBeNull();
  });

  it("scopes to the record and opens its statement on a record page", async () => {
    const el = createElement("c-a-x-f_-l-w-c_bank-statement", {
      is: BankStatement
    });
    el.recordId = WALLET.bankAccountId;
    document.body.appendChild(el);
    getContext.emit({ canUse: true, canConfigure: true });
    await settle();
    expect(el.shadowRoot.querySelectorAll('[data-action="view"]').length).toBe(
      1
    );
    expect(getStatement).toHaveBeenCalledWith(
      expect.objectContaining({
        request: expect.stringContaining(WALLET.bankAccountId)
      })
    );
  });
});
