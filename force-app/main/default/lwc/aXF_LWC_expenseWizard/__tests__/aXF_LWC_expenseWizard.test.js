import { createElement } from "lwc";
import AXF_LWC_expenseWizard from "c/aXF_LWC_expenseWizard";
import getOptions from "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.getOptions";
import createStandalone from "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.createStandalone";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.getOptions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.createStandalone",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flushPromises = () =>
  Array.from({ length: 10 }).reduce(
    (chain) => chain.then(() => undefined),
    Promise.resolve()
  );

const options = {
  categories: [{ id: "c1", label: "Moradia" }],
  accounts: [{ id: "a1", label: "Conta" }],
  cards: [{ id: "k1", label: "Cartão" }]
};

async function mount(props = { holderId: "001A" }) {
  const element = createElement("c-a-x-f-l-w-c-expense-wizard", {
    is: AXF_LWC_expenseWizard
  });
  Object.assign(element, props);
  document.body.appendChild(element);
  await flushPromises();
  return element;
}

const $ = (element, selector) => element.shadowRoot.querySelector(selector);
const $$ = (element, selector) =>
  Array.from(element.shadowRoot.querySelectorAll(selector));

async function type(element, selector, value) {
  $(element, selector).dispatchEvent(
    new CustomEvent("change", { detail: { value } })
  );
  await flushPromises();
}

async function chooseStandalone(element) {
  $$(element, ".type-card")[0].click();
  await flushPromises();
}

async function fillStep1(element) {
  await type(element, ".field-description", "Conta de luz");
  await type(element, ".field-amount", "180");
  await type(element, ".field-due", "2026-10-20");
}

describe("c-a-x-f-l-w-c-expense-wizard", () => {
  beforeEach(() => {
    getOptions.mockResolvedValue(options);
    createStandalone.mockResolvedValue("a0X");
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("asks the type first and only enables the standalone expense", async () => {
    const element = await mount();
    expect($(element, ".wizard-title").textContent).toContain(
      "Que tipo de despesa é?"
    );
    const buttons = $$(element, ".type-card");
    expect(buttons).toHaveLength(5);
    expect(buttons.map((b) => b.disabled)).toEqual([
      false,
      true,
      true,
      true,
      true
    ]);
    expect(getOptions).toHaveBeenCalledWith({ holderId: "001A" });
  });

  it("only enables Próximo with the required fields filled", async () => {
    const element = await mount();
    await chooseStandalone(element);
    expect($(element, ".wizard-step").textContent).toContain(
      "Etapa 1 de 3 — Dados"
    );
    expect($(element, ".next").disabled).toBe(true);
    await type(element, ".field-description", "Conta de luz");
    await type(element, ".field-amount", "0");
    await type(element, ".field-due", "2026-10-20");
    expect($(element, ".next").disabled).toBe(true);
    await type(element, ".field-amount", "180");
    expect($(element, ".next").disabled).toBe(false);
  });

  it("asks for the payment date when the expense is realized", async () => {
    const element = await mount();
    await chooseStandalone(element);
    await fillStep1(element);
    expect($(element, ".field-payment-date")).toBeNull();
    await type(element, ".field-status", "Realized");
    expect($(element, ".field-payment-date")).not.toBeNull();
    expect($(element, ".next").disabled).toBe(true);
    await type(element, ".field-payment-date", "2026-10-05");
    expect($(element, ".next").disabled).toBe(false);
  });

  it("asks for the holder when none is filtered and reloads the options", async () => {
    const element = await mount({
      holderId: "",
      holders: [{ id: "001B", name: "Titular B" }]
    });
    // "Todos" arrives as an empty string; Apex needs a null, not an invalid Id.
    expect(getOptions).toHaveBeenCalledWith({ holderId: null });
    await chooseStandalone(element);
    await fillStep1(element);
    expect($(element, ".next").disabled).toBe(true);
    await type(element, ".field-holder", "001B");
    expect(getOptions).toHaveBeenLastCalledWith({ holderId: "001B" });
    expect($(element, ".next").disabled).toBe(false);
  });

  it("requires the account or card unless it is paid in cash, then reviews and concludes", async () => {
    const element = await mount();
    await chooseStandalone(element);
    await fillStep1(element);
    await type(element, ".field-category", "c1");
    $(element, ".next").click();
    await flushPromises();
    expect($(element, ".wizard-step").textContent).toContain(
      "Etapa 2 de 3 — Pagamento"
    );
    expect($(element, ".field-source")).toBeNull();
    await type(element, ".field-method", "account");
    expect($(element, ".next").disabled).toBe(true);
    await type(element, ".field-source", "a1");
    expect($(element, ".next").disabled).toBe(false);
    $(element, ".next").click();
    await flushPromises();
    expect($(element, ".review-line").textContent).toContain(
      "Conta de luz · Moradia · Conta bancária (Conta)"
    );
    expect($(element, ".review-summary").textContent).toContain(
      "Será criado 1 lançamento pendente · Vencimento 20/10/2026"
    );

    const saved = jest.fn();
    element.addEventListener("saved", saved);
    $(element, ".conclude").click();
    await flushPromises();
    expect(createStandalone).toHaveBeenCalledTimes(1);
    expect(JSON.parse(createStandalone.mock.calls[0][0].requestJson)).toEqual({
      holderId: "001A",
      description: "Conta de luz",
      amount: 180,
      dueDate: "2026-10-20",
      categoryId: "c1",
      status: "Pending",
      paymentDate: null,
      accountId: "a1",
      cardId: null
    });
    expect(saved).toHaveBeenCalledTimes(1);
  });

  it("goes back, changes the type and cancels", async () => {
    const element = await mount();
    await chooseStandalone(element);
    $(element, ".change-type").click();
    await flushPromises();
    expect($(element, ".wizard-title").textContent).toContain(
      "Que tipo de despesa é?"
    );
    await chooseStandalone(element);
    await fillStep1(element);
    $(element, ".next").click();
    await flushPromises();
    $(element, ".back").click();
    await flushPromises();
    expect($(element, ".wizard-step").textContent).toContain("Etapa 1 de 3");
    const closed = jest.fn();
    element.addEventListener("close", closed);
    $(element, ".cancel").click();
    expect(closed).toHaveBeenCalledTimes(1);
  });

  it("shows the server error and stays on the review step", async () => {
    createStandalone.mockRejectedValue({
      body: { message: "O valor deve ser maior que zero." }
    });
    const element = await mount();
    await chooseStandalone(element);
    await fillStep1(element);
    $(element, ".next").click();
    await flushPromises();
    $(element, ".next").click();
    await flushPromises();
    $(element, ".conclude").click();
    await flushPromises();
    expect($(element, ".wizard-error").textContent).toContain(
      "O valor deve ser maior que zero."
    );
    expect($(element, ".conclude")).not.toBeNull();
  });
});
