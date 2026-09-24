import { createElement } from "lwc";
import Wizard from "c/aXF_LWC_entryWizard";
import getContexts from "@salesforce/apex/AXF_CLS_CTRL_AuthorizedContext.getContexts";
import getFundingSources from "@salesforce/apex/AXF_CLS_CTRL_FinancialEntry.getFundingSources";
import getCapabilities from "@salesforce/apex/AXF_CLS_CTRL_FinancialEntry.getCapabilities";
import createEntry from "@salesforce/apex/AXF_CLS_CTRL_FinancialEntry.createEntry";
import realizeEntry from "@salesforce/apex/AXF_CLS_CTRL_FinancialEntry.realizeEntry";
import listFactSuggestions from "@salesforce/apex/AXF_CLS_CTRL_FinancialEntry.listFactSuggestions";
import searchFacts from "@salesforce/apex/AXF_CLS_CTRL_FinancialEntry.searchFacts";
import confirmFact from "@salesforce/apex/AXF_CLS_CTRL_FinancialEntry.confirmFact";
import { CurrentPageReference } from "lightning/navigation";

const mockNavigate = jest.fn();
jest.mock("lightning/navigation", () => {
  const {
    createTestWireAdapter
  } = require("@salesforce/wire-service-jest-util");
  const Navigate = Symbol("Navigate");
  const NavigationMixin = (Base) =>
    class extends Base {
      [Navigate](pageRef) {
        mockNavigate(pageRef);
      }
    };
  NavigationMixin.Navigate = Navigate;
  return {
    NavigationMixin,
    CurrentPageReference: createTestWireAdapter(jest.fn())
  };
});
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_AuthorizedContext.getContexts",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_FinancialEntry.getFundingSources",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_FinancialEntry.getCapabilities",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_FinancialEntry.createEntry",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_FinancialEntry.realizeEntry",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_FinancialEntry.listFactSuggestions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_FinancialEntry.searchFacts",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_FinancialEntry.confirmFact",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const CONTEXTS = [
  { accountId: "001000000000001", label: "Ana", contextType: "PERSON" },
  { accountId: "001000000000002", label: "Empresa X", contextType: "BUSINESS" }
];
const MANUAL_BANK = {
  kind: "BANK_ACCOUNT",
  bankAccountId: "a01000000000001",
  label: "Banco A",
  wallet: false,
  connected: false
};
const CONNECTED_BANK = {
  kind: "BANK_ACCOUNT",
  bankAccountId: "a01000000000003",
  label: "Banco Pluggy",
  wallet: false,
  connected: true
};
const WALLET = {
  kind: "BANK_ACCOUNT",
  bankAccountId: "a01000000000002",
  label: "Carteira (dinheiro)",
  wallet: true,
  connected: false
};
const CARD = {
  kind: "CREDIT_CARD",
  creditCardId: "a02000000000001",
  label: "Cartao X 1234",
  wallet: false,
  connected: true
};
const FACT = {
  sourceId: "a03000000000001",
  sourceVersion: 2,
  factDate: "2026-09-10",
  description: "PADARIA",
  amount: 104,
  residual: 104,
  currencyIso: "BRL",
  tied: false
};

function build() {
  const el = createElement("c-a-x-f_-l-w-c_entry-wizard", { is: Wizard });
  document.body.appendChild(el);
  return el;
}

const flush = () => Promise.resolve();
const settle = async () => {
  for (let i = 0; i < 6; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};

function btn(el, re) {
  return [...el.shadowRoot.querySelectorAll("lightning-button")].find((b) =>
    re.test(b.label)
  );
}

function next(el) {
  return btn(el, /Próximo|Next/);
}

async function chooseSource(el, kind, id) {
  el.shadowRoot
    .querySelectorAll("lightning-radio-group")[0]
    .dispatchEvent(new CustomEvent("change", { detail: { value: kind } }));
  await flush();
  el.shadowRoot
    .querySelector("lightning-combobox[data-source]")
    .dispatchEvent(new CustomEvent("change", { detail: { value: id } }));
  await flush();
}

async function toDetails(el, amount = "20") {
  next(el).click();
  await flush();
  el.shadowRoot
    .querySelector("lightning-input[data-field='magnitude']")
    .dispatchEvent(new CustomEvent("change", { detail: { value: amount } }));
  await flush();
}

afterEach(() => {
  while (document.body.firstChild) {
    document.body.removeChild(document.body.firstChild);
  }
  jest.clearAllMocks();
});

describe("c-aXF_LWC_entryWizard", () => {
  it("shows a neutral message when there is no authorized context", async () => {
    const el = build();
    getContexts.emit([]);
    await flush();
    expect(el.shadowRoot.textContent).toMatch(
      /autorizada está disponível|authorized .* is available/i
    );
    expect(next(el).disabled).toBe(true);
  });

  it("blocks advancing to details until a context is chosen", async () => {
    const el = build();
    getContexts.emit(CONTEXTS);
    await flush();
    expect(next(el).disabled).toBe(true);

    el.shadowRoot
      .querySelector("lightning-combobox")
      .dispatchEvent(
        new CustomEvent("change", { detail: { value: CONTEXTS[1].accountId } })
      );
    await flush();
    expect(next(el).disabled).toBe(false);
  });

  it("walks the four steps and confirms with the expected payload", async () => {
    createEntry.mockResolvedValue({
      outcome: "CREATED",
      financialTransactionId: "a0X000000000001"
    });
    const el = build();
    getContexts.emit(CONTEXTS);
    getFundingSources.emit([MANUAL_BANK, WALLET]);
    await flush();

    el.shadowRoot
      .querySelector("lightning-combobox")
      .dispatchEvent(
        new CustomEvent("change", { detail: { value: CONTEXTS[1].accountId } })
      );
    await flush();
    await toDetails(el, "150.75");
    next(el).click();
    await flush();

    // step 3: the origin is mandatory
    expect(next(el).disabled).toBe(true);
    await chooseSource(el, "BANK_ACCOUNT", MANUAL_BANK.bankAccountId);
    expect(next(el).disabled).toBe(false);
    next(el).click();
    await flush();

    // step 4: review + confirm
    expect(el.shadowRoot.textContent).toMatch(/150\.75/);
    const tracking = [
      ...el.shadowRoot.querySelectorAll("lightning-input")
    ].find((input) => input.type === "checkbox");
    tracking.checked = true;
    tracking.dispatchEvent(new CustomEvent("change"));
    await flush();
    btn(el, /Confirmar|Confirm/).click();
    await settle();

    expect(createEntry).toHaveBeenCalledTimes(1);
    const call = createEntry.mock.calls[0][0];
    expect(call.accountId).toBe(CONTEXTS[1].accountId);
    expect(call.direction).toBe("DEBIT");
    expect(call.magnitude).toBe(150.75);
    expect(call.bankAccountId).toBe(MANUAL_BANK.bankAccountId);
    expect(call.creditCardId).toBeNull();
    expect(call.trackConfirmation).toBe(true);
    expect(call.clientRequestId.length).toBe(36);
    expect(el.shadowRoot.textContent).toMatch(/criado|created/i);
    // An unconnected origin has no Pluggy facts to offer.
    expect(listFactSuggestions).not.toHaveBeenCalled();
    expect(el.shadowRoot.querySelector("[data-fact-panel]")).toBeNull();
  });

  it("offers only the wallets under the wallet origin and posts on the card", async () => {
    createEntry.mockResolvedValue({ outcome: "CREATED" });
    const el = build();
    getContexts.emit([CONTEXTS[0]]);
    getFundingSources.emit([MANUAL_BANK, WALLET, CARD]);
    await flush();
    await toDetails(el);
    next(el).click();
    await flush();

    el.shadowRoot
      .querySelectorAll("lightning-radio-group")[0]
      .dispatchEvent(
        new CustomEvent("change", { detail: { value: "WALLET" } })
      );
    await flush();
    const walletBox = el.shadowRoot.querySelector(
      "lightning-combobox[data-source]"
    );
    expect(walletBox.options.map((o) => o.value)).toEqual([
      WALLET.bankAccountId
    ]);

    await chooseSource(el, "CREDIT_CARD", CARD.creditCardId);
    next(el).click();
    await flush();
    btn(el, /Confirmar|Confirm/).click();
    await settle();
    const call = createEntry.mock.calls[0][0];
    expect(call.creditCardId).toBe(CARD.creditCardId);
    expect(call.bankAccountId).toBeNull();
  });

  it("shows consortium disabled with the AXF-97 notice", async () => {
    const el = build();
    getContexts.emit([CONTEXTS[0]]);
    await flush();
    next(el).click();
    await flush();
    const consortium = el.shadowRoot.querySelector(
      "input[data-type='CONSORTIUM']"
    );
    expect(consortium.disabled).toBe(true);
    expect(
      el.shadowRoot.querySelector("[data-consortium-note]").textContent
    ).toMatch(/AXF_ManualEntry_consortiumUnavailable/);
  });

  it("redirects installments to the schedule planner with the details", async () => {
    const el = build();
    getContexts.emit([CONTEXTS[0]]);
    getFundingSources.emit([MANUAL_BANK]);
    await flush();
    await toDetails(el, "900");
    const installment = el.shadowRoot.querySelector(
      "input[data-type='INSTALLMENT']"
    );
    installment.checked = true;
    installment.dispatchEvent(new CustomEvent("change"));
    await flush();
    next(el).click();
    await flush();
    // A scheduled entry does not need an origin: the planner does not take one.
    expect(next(el).disabled).toBe(false);
    expect(el.shadowRoot.textContent).not.toMatch(
      /AXF_ManualEntry_originRequired/
    );
    next(el).click();
    await flush();

    expect(btn(el, /Confirmar|Confirm/)).toBeUndefined();
    btn(el, /AXF_ManualEntry_continueSchedule/).click();
    await flush();
    expect(createEntry).not.toHaveBeenCalled();
    expect(mockNavigate).toHaveBeenCalledTimes(1);
    const ref = mockNavigate.mock.calls[0][0];
    expect(ref.attributes.apiName).toBe("AXF_ScheduleWizard");
    expect(ref.state).toMatchObject({
      c__modality: "INSTALLMENT",
      c__direction: "DEBIT",
      c__accountId: CONTEXTS[0].accountId,
      c__amount: "900",
      c__currencyIsoCode: "BRL"
    });
    expect(ref.state.c__firstDueDate).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });

  it("realizes a wallet entry at once through the realization endpoint", async () => {
    realizeEntry.mockResolvedValue({
      financialTransactionId: "a0X000000000009",
      linkedToFact: false
    });
    const el = build();
    getCapabilities.emit({ canRealize: true, canReconcile: true });
    getContexts.emit([CONTEXTS[0]]);
    getFundingSources.emit([WALLET]);
    await flush();
    await toDetails(el, "42.5");
    const toggle = el.shadowRoot.querySelector(
      "lightning-input[data-realized]"
    );
    toggle.checked = true;
    toggle.dispatchEvent(new CustomEvent("change"));
    await flush();
    next(el).click();
    await flush();
    await chooseSource(el, "WALLET", WALLET.bankAccountId);
    next(el).click();
    await flush();

    expect(btn(el, /Confirmar|Confirm/).disabled).toBe(false);
    btn(el, /Confirmar|Confirm/).click();
    await settle();
    expect(createEntry).not.toHaveBeenCalled();
    const request = JSON.parse(realizeEntry.mock.calls[0][0].request);
    expect(request.entry.bankAccountId).toBe(WALLET.bankAccountId);
    expect(request.entry.amount).toBe(42.5);
    expect(request.factId).toBeNull();
    expect(request.operationKey.length).toBe(36);
    expect(el.shadowRoot.textContent).toMatch(/AXF_ManualEntry_realizedDone/);
  });

  it("blocks saving a realized connected entry until a Pluggy fact is chosen", async () => {
    listFactSuggestions.mockResolvedValue({ items: [FACT], truncated: false });
    realizeEntry.mockResolvedValue({ linkedToFact: true });
    const el = build();
    getCapabilities.emit({ canRealize: true, canReconcile: true });
    getContexts.emit([CONTEXTS[0]]);
    getFundingSources.emit([CONNECTED_BANK]);
    await flush();
    await toDetails(el, "100");
    const toggle = el.shadowRoot.querySelector(
      "lightning-input[data-realized]"
    );
    toggle.checked = true;
    toggle.dispatchEvent(new CustomEvent("change"));
    await flush();
    next(el).click();
    await flush();
    await chooseSource(el, "BANK_ACCOUNT", CONNECTED_BANK.bankAccountId);
    next(el).click();
    await settle();

    const draft = JSON.parse(listFactSuggestions.mock.calls[0][0].request);
    expect(draft.bankAccountId).toBe(CONNECTED_BANK.bankAccountId);
    expect(draft.amount).toBe(100);
    expect(btn(el, /Confirmar|Confirm/).disabled).toBe(true);
    expect(el.shadowRoot.querySelector("[data-fact-required]")).not.toBeNull();

    btn(el, /AXF_ManualEntry_select$/).click();
    await flush();
    expect(btn(el, /Confirmar|Confirm/).disabled).toBe(false);
    btn(el, /Confirmar|Confirm/).click();
    await settle();
    const request = JSON.parse(realizeEntry.mock.calls[0][0].request);
    expect(request.factId).toBe(FACT.sourceId);
    expect(request.factVersion).toBe(FACT.sourceVersion);
    expect(el.shadowRoot.textContent).toMatch(
      /AXF_ManualEntry_realizedLinkedDone/
    );
  });

  it("shows the sanitized reason when the chosen fact is already linked", async () => {
    listFactSuggestions.mockResolvedValue({ items: [FACT] });
    realizeEntry.mockRejectedValue({ body: { message: "ALREADY_LINKED" } });
    const el = build();
    getCapabilities.emit({ canRealize: true, canReconcile: true });
    getContexts.emit([CONTEXTS[0]]);
    getFundingSources.emit([CONNECTED_BANK]);
    await flush();
    await toDetails(el, "100");
    const toggle = el.shadowRoot.querySelector(
      "lightning-input[data-realized]"
    );
    toggle.checked = true;
    toggle.dispatchEvent(new CustomEvent("change"));
    await flush();
    next(el).click();
    await flush();
    await chooseSource(el, "BANK_ACCOUNT", CONNECTED_BANK.bankAccountId);
    next(el).click();
    await settle();
    btn(el, /AXF_ManualEntry_select$/).click();
    await flush();
    btn(el, /Confirmar|Confirm/).click();
    await settle();
    expect(el.shadowRoot.querySelector("[data-feedback]").textContent).toMatch(
      /AXF_ManualEntry_codeALREADY_LINKED/
    );
  });

  it("offers Pluggy facts after saving a planned entry and reconciles in one click", async () => {
    createEntry.mockResolvedValue({
      outcome: "CREATED",
      financialTransactionId: "a0X000000000005"
    });
    listFactSuggestions.mockResolvedValue({
      items: [],
      targetId: "a0X000000000005",
      targetVersion: 0
    });
    searchFacts.mockResolvedValue({
      items: [FACT],
      targetId: "a0X000000000005",
      targetVersion: 0
    });
    confirmFact.mockResolvedValue({ allocationId: "a04000000000001" });
    const el = build();
    getCapabilities.emit({ canRealize: true, canReconcile: true });
    getContexts.emit([CONTEXTS[0]]);
    getFundingSources.emit([CONNECTED_BANK]);
    await flush();
    await toDetails(el, "100");
    next(el).click();
    await flush();
    await chooseSource(el, "BANK_ACCOUNT", CONNECTED_BANK.bankAccountId);
    next(el).click();
    await flush();
    btn(el, /Confirmar|Confirm/).click();
    await settle();

    expect(JSON.parse(listFactSuggestions.mock.calls[0][0].request)).toEqual({
      targetId: "a0X000000000005"
    });
    expect(el.shadowRoot.querySelector("[data-no-suggestions]")).not.toBeNull();

    // No suggestion: the manual search finds a fact of the period.
    const term = el.shadowRoot.querySelector(
      "lightning-input[data-field='term']"
    );
    term.dispatchEvent(
      new CustomEvent("change", { detail: { value: "padaria" } })
    );
    await flush();
    btn(el, /AXF_ManualEntry_searchAction/).click();
    await settle();
    const search = JSON.parse(searchFacts.mock.calls[0][0].request);
    expect(search.entry).toEqual({ targetId: "a0X000000000005" });
    expect(search.term).toBe("padaria");

    btn(el, /AXF_ManualEntry_reconcileAction/).click();
    await settle();
    const confirm = JSON.parse(confirmFact.mock.calls[0][0].request);
    expect(confirm.targetId).toBe("a0X000000000005");
    expect(confirm.targetVersion).toBe(0);
    expect(confirm.sourceId).toBe(FACT.sourceId);
    expect(el.shadowRoot.textContent).toMatch(/AXF_ManualEntry_reconciled/);
    expect(el.shadowRoot.querySelector("[data-fact-panel]")).toBeNull();
  });

  it("rejects a search period longer than 366 days without calling the server", async () => {
    listFactSuggestions.mockResolvedValue({ items: [] });
    const el = build();
    getCapabilities.emit({ canRealize: true, canReconcile: true });
    getContexts.emit([CONTEXTS[0]]);
    getFundingSources.emit([CONNECTED_BANK]);
    await flush();
    await toDetails(el, "100");
    const toggle = el.shadowRoot.querySelector(
      "lightning-input[data-realized]"
    );
    toggle.checked = true;
    toggle.dispatchEvent(new CustomEvent("change"));
    await flush();
    next(el).click();
    await flush();
    await chooseSource(el, "BANK_ACCOUNT", CONNECTED_BANK.bankAccountId);
    next(el).click();
    await settle();
    el.shadowRoot
      .querySelector("lightning-input[data-field='fromDate']")
      .dispatchEvent(
        new CustomEvent("change", { detail: { value: "2025-01-01" } })
      );
    el.shadowRoot
      .querySelector("lightning-input[data-field='toDate']")
      .dispatchEvent(
        new CustomEvent("change", { detail: { value: "2026-06-01" } })
      );
    await flush();
    btn(el, /AXF_ManualEntry_searchAction/).click();
    await settle();
    expect(searchFacts).not.toHaveBeenCalled();
  });

  it("warns instead of saving when the user cannot reconcile a connected origin", async () => {
    const el = build();
    getCapabilities.emit({ canRealize: true, canReconcile: false });
    getContexts.emit([CONTEXTS[0]]);
    getFundingSources.emit([CONNECTED_BANK]);
    await flush();
    await toDetails(el, "100");
    const toggle = el.shadowRoot.querySelector(
      "lightning-input[data-realized]"
    );
    toggle.checked = true;
    toggle.dispatchEvent(new CustomEvent("change"));
    await flush();
    next(el).click();
    await flush();
    await chooseSource(el, "BANK_ACCOUNT", CONNECTED_BANK.bankAccountId);
    next(el).click();
    await settle();
    expect(el.shadowRoot.querySelector("[data-no-reconcile]")).not.toBeNull();
    expect(btn(el, /Confirmar|Confirm/).disabled).toBe(true);
    expect(listFactSuggestions).not.toHaveBeenCalled();
  });

  it("surfaces a conflict without leaving the form", async () => {
    createEntry.mockResolvedValue({ outcome: "CONFLICT" });
    const el = build();
    getContexts.emit([CONTEXTS[0]]);
    getFundingSources.emit([MANUAL_BANK]);
    await flush(); // single context auto-selected

    await toDetails(el, "10");
    next(el).click();
    await flush();
    await chooseSource(el, "BANK_ACCOUNT", MANUAL_BANK.bankAccountId);
    next(el).click();
    await flush();
    btn(el, /Confirmar|Confirm/).click();
    await settle();

    expect(el.shadowRoot.querySelector("[data-feedback]").textContent).toMatch(
      /outra tentativa|another attempt/i
    );
    expect(el.shadowRoot.querySelector("[role='status']")).toBeNull();
  });

  it("cancel resets the wizard without calling the server", async () => {
    const el = build();
    getContexts.emit(CONTEXTS);
    getFundingSources.emit([]);
    await flush();

    el.shadowRoot
      .querySelector("lightning-combobox")
      .dispatchEvent(
        new CustomEvent("change", { detail: { value: CONTEXTS[1].accountId } })
      );
    await flush();
    next(el).click();
    await flush();

    btn(el, /Cancelar|Cancel/).click();
    await flush();

    expect(createEntry).not.toHaveBeenCalled();
    expect(el.shadowRoot.textContent).toMatch(/Contexto|Context/);
  });

  it("pre-selects the account handed over by the current-account screen", async () => {
    createEntry.mockResolvedValue({ outcome: "CREATED" });
    const el = build();
    CurrentPageReference.emit({
      type: "standard__navItemPage",
      attributes: { apiName: "AXF_EntryWizard" },
      state: {
        c__bankAccountId: WALLET.bankAccountId,
        c__accountId: CONTEXTS[1].accountId
      }
    });
    getContexts.emit(CONTEXTS);
    await flush();
    getFundingSources.emit([MANUAL_BANK, WALLET]);
    await flush();

    await toDetails(el);
    next(el).click();
    await flush();
    // The source step is already filled (as a wallet): no second question.
    expect(next(el).disabled).toBe(false);
    next(el).click();
    await flush();
    btn(el, /Confirmar|Confirm/).click();
    await settle();

    const call = createEntry.mock.calls[0][0];
    expect(call.accountId).toBe(CONTEXTS[1].accountId);
    expect(call.bankAccountId).toBe(WALLET.bankAccountId);
  });

  it("ignores a handed-over account that is not a source of the holder", async () => {
    const el = build();
    CurrentPageReference.emit({
      state: { c__bankAccountId: "a01000000000999" }
    });
    getContexts.emit([CONTEXTS[0]]);
    getFundingSources.emit([MANUAL_BANK]);
    await flush();

    await toDetails(el);
    next(el).click();
    await flush();
    expect(next(el).disabled).toBe(true);
    next(el).click();
    await flush();
    expect(btn(el, /Confirmar|Confirm/)).toBeUndefined();
  });

  it("pre-selects the card handed over by the credit-card screen", async () => {
    createEntry.mockResolvedValue({ outcome: "CREATED" });
    const manualCard = { ...CARD, connected: false };
    const el = build();
    CurrentPageReference.emit({
      type: "standard__navItemPage",
      attributes: { apiName: "AXF_EntryWizard" },
      state: {
        c__creditCardId: manualCard.creditCardId,
        c__accountId: CONTEXTS[1].accountId
      }
    });
    getContexts.emit(CONTEXTS);
    await flush();
    getFundingSources.emit([MANUAL_BANK, manualCard]);
    await flush();

    await toDetails(el);
    next(el).click();
    await flush();
    // The source step is already filled with the card: no second question.
    expect(next(el).disabled).toBe(false);
    next(el).click();
    await flush();
    btn(el, /Confirmar|Confirm/).click();
    await settle();

    const call = createEntry.mock.calls[0][0];
    expect(call.accountId).toBe(CONTEXTS[1].accountId);
    expect(call.creditCardId).toBe(manualCard.creditCardId);
    expect(call.bankAccountId).toBeNull();
  });

  it("ignores a handed-over card that is not a source of the holder", async () => {
    const el = build();
    CurrentPageReference.emit({
      state: { c__creditCardId: "a02000000000999" }
    });
    getContexts.emit([CONTEXTS[0]]);
    getFundingSources.emit([MANUAL_BANK, CARD]);
    await flush();

    await toDetails(el);
    next(el).click();
    await flush();
    expect(next(el).disabled).toBe(true);
  });

  it("follows a new hand-over when the reused tab shows another holder", async () => {
    createEntry.mockResolvedValue({ outcome: "CREATED" });
    const el = build();
    getContexts.emit(CONTEXTS);
    await flush();
    el.shadowRoot
      .querySelector("lightning-combobox")
      .dispatchEvent(
        new CustomEvent("change", { detail: { value: CONTEXTS[0].accountId } })
      );
    await flush();
    CurrentPageReference.emit({
      state: {
        c__bankAccountId: MANUAL_BANK.bankAccountId,
        c__accountId: CONTEXTS[1].accountId
      }
    });
    await flush();
    getFundingSources.emit([MANUAL_BANK]);
    await flush();

    await toDetails(el);
    next(el).click();
    await flush();
    next(el).click();
    await flush();
    btn(el, /Confirmar|Confirm/).click();
    await settle();
    const call = createEntry.mock.calls[0][0];
    expect(call.accountId).toBe(CONTEXTS[1].accountId);
    expect(call.bankAccountId).toBe(MANUAL_BANK.bankAccountId);
  });

  it("never takes the source after a manual holder change", async () => {
    const el = build();
    getContexts.emit(CONTEXTS);
    CurrentPageReference.emit({
      state: {
        c__bankAccountId: MANUAL_BANK.bankAccountId,
        c__accountId: CONTEXTS[1].accountId
      }
    });
    await flush();
    el.shadowRoot
      .querySelector("lightning-combobox")
      .dispatchEvent(
        new CustomEvent("change", { detail: { value: CONTEXTS[0].accountId } })
      );
    await flush();
    getFundingSources.emit([MANUAL_BANK]);
    await flush();

    await toDetails(el);
    next(el).click();
    await flush();
    expect(next(el).disabled).toBe(true);
  });

  async function savePlannedOnConnected(el) {
    getCapabilities.emit({ canRealize: true, canReconcile: true });
    getContexts.emit([CONTEXTS[0]]);
    getFundingSources.emit([CONNECTED_BANK]);
    await flush();
    await toDetails(el, "100");
    next(el).click();
    await flush();
    await chooseSource(el, "BANK_ACCOUNT", CONNECTED_BANK.bankAccountId);
    next(el).click();
    await flush();
    btn(el, /Confirmar|Confirm/).click();
    await settle();
  }

  it("keeps the panel open when one click settles only part of the entry", async () => {
    createEntry.mockResolvedValue({
      outcome: "CREATED",
      financialTransactionId: "a0X000000000006"
    });
    const small = { ...FACT, sourceId: "a03000000000060", amount: 60 };
    const rest = { ...FACT, sourceId: "a03000000000040", amount: 40 };
    listFactSuggestions
      .mockResolvedValueOnce({
        items: [small],
        targetVersion: 0,
        available: 100
      })
      .mockResolvedValueOnce({
        items: [rest],
        targetVersion: 1,
        available: 40
      });
    confirmFact
      .mockResolvedValueOnce({ amount: 60 })
      .mockResolvedValueOnce({ amount: 40 });
    const el = build();
    await savePlannedOnConnected(el);

    btn(el, /AXF_ManualEntry_reconcileAction/).click();
    await settle();
    expect(el.shadowRoot.textContent).toMatch(
      /AXF_ManualEntry_partiallyReconciled/
    );
    expect(el.shadowRoot.querySelector("[data-fact-panel]")).not.toBeNull();
    expect(listFactSuggestions).toHaveBeenCalledTimes(2);

    btn(el, /AXF_ManualEntry_reconcileAction/).click();
    await settle();
    const second = JSON.parse(confirmFact.mock.calls[1][0].request);
    expect(second.sourceId).toBe(rest.sourceId);
    expect(second.targetVersion).toBe(1);
    expect(el.shadowRoot.textContent).toMatch(/AXF_ManualEntry_reconciled/);
    expect(el.shadowRoot.querySelector("[data-fact-panel]")).toBeNull();
  });

  it("clears the search spinner when a newer lookup discards the search", async () => {
    createEntry.mockResolvedValue({
      outcome: "CREATED",
      financialTransactionId: "a0X000000000007"
    });
    listFactSuggestions.mockResolvedValue({
      items: [FACT],
      targetVersion: 0,
      available: 100
    });
    let resolveSearch;
    searchFacts.mockReturnValue(
      new Promise((resolve) => {
        resolveSearch = resolve;
      })
    );
    confirmFact.mockRejectedValue({ body: { message: "CONFLICT" } });
    const el = build();
    await savePlannedOnConnected(el);

    btn(el, /AXF_ManualEntry_searchAction/).click();
    await flush();
    const spinners = () =>
      el.shadowRoot.querySelectorAll("[data-fact-panel] lightning-spinner")
        .length;
    expect(spinners()).toBe(1);
    // A failed click reloads the suggestions, which supersedes the pending search.
    btn(el, /AXF_ManualEntry_reconcileAction/).click();
    await settle();
    resolveSearch({ items: [FACT] });
    await settle();
    expect(spinners()).toBe(0);
  });
});
