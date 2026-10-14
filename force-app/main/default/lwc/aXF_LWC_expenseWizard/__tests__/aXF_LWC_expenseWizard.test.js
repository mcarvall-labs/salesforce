import { createElement } from "lwc";
import AXF_LWC_expenseWizard from "c/aXF_LWC_expenseWizard";
import getOptions from "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.getOptions";
import createStandalone from "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.createStandalone";
import createCategory from "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.createCategory";
import createRecurring from "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.createRecurring";
import previewRecurring from "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.previewRecurring";
import createInstallment from "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.createInstallment";
import previewInstallment from "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.previewInstallment";
import createConsortium from "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.createConsortium";
import previewConsortium from "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.previewConsortium";
import createFinancing from "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.createFinancing";
import previewFinancing from "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.previewFinancing";

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

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.createRecurring",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.previewRecurring",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.createInstallment",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.previewInstallment",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.createCategory",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.createConsortium",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.previewConsortium",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.createFinancing",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.previewFinancing",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flushPromises = () =>
  Array.from({ length: 10 }).reduce(
    (chain) => chain.then(() => undefined),
    Promise.resolve()
  );

const options = {
  categories: [
    { id: "c1", label: "Moradia" },
    { id: "c2", label: "Energia", parentId: "c1" }
  ],
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
    createRecurring.mockResolvedValue("a0C");
    createInstallment.mockResolvedValue("a0I");
    createConsortium.mockResolvedValue("a0K");
    createFinancing.mockResolvedValue("a0F");
    previewFinancing.mockResolvedValue([
      { dueDate: "2026-11-10", amount: 112, interest: 12 },
      { dueDate: "2026-12-10", amount: 111, interest: 11 },
      { dueDate: "2027-01-10", amount: 110, interest: 10 }
    ]);
    previewConsortium.mockResolvedValue([
      { dueDate: "2026-11-15", amount: 1200 },
      { dueDate: "2026-12-15", amount: 1200 },
      { dueDate: "2027-01-15", amount: 1200 }
    ]);
    previewInstallment.mockResolvedValue([
      { dueDate: "2026-11-10", amount: 333.33 },
      { dueDate: "2026-12-10", amount: 333.33 },
      { dueDate: "2027-01-10", amount: 333.34 }
    ]);
    previewRecurring.mockResolvedValue([
      { dueDate: "2026-11-05", amount: 2500 },
      { dueDate: "2026-12-05", amount: 2500 },
      { dueDate: "2027-01-05", amount: 2500 }
    ]);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("asks the type first and enables every expense type", async () => {
    const element = await mount();
    expect($(element, ".wizard-title").textContent).toContain(
      "Que tipo de despesa é?"
    );
    const buttons = $$(element, ".type-card");
    expect(buttons).toHaveLength(5);
    expect(buttons.map((b) => b.disabled)).toEqual([
      false,
      false,
      false,
      false,
      false
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

  it("creates a recurring expense with its contract in one call", async () => {
    const element = await mount();
    $$(element, ".type-card")[1].click();
    await flushPromises();
    expect($(element, ".wizard-title").textContent).toContain(
      "Despesa recorrente"
    );
    expect($(element, ".field-status")).toBeNull();
    await type(element, ".field-description", "Aluguel");
    await type(element, ".field-amount", "2500");
    await type(element, ".field-due", "2026-11-05");
    await type(element, ".field-variable", "yes");
    await type(element, ".field-due-day", "5");
    await type(element, ".field-end-date", "2027-01-05");
    $(element, ".next").click();
    await flushPromises();
    $(element, ".next").click();
    await flushPromises();
    expect(previewRecurring).toHaveBeenCalledTimes(1);
    expect($(element, ".review-summary").textContent).toContain(
      "1 Contrato (Recorrente) e 3 lançamentos pendentes"
    );
    expect($(element, ".review-preview").textContent).toContain("05/11/2026");
    expect($(element, ".review-more").textContent).toContain("mais 1");

    const saved = jest.fn();
    element.addEventListener("saved", saved);
    $(element, ".conclude").click();
    await flushPromises();
    expect(createRecurring).toHaveBeenCalledTimes(1);
    expect(JSON.parse(createRecurring.mock.calls[0][0].requestJson)).toEqual({
      base: {
        holderId: "001A",
        description: "Aluguel",
        amount: 2500,
        dueDate: "2026-11-05",
        categoryId: null,
        accountId: null,
        cardId: null
      },
      variableAmount: true,
      dueDay: 5,
      endDate: "2027-01-05"
    });
    expect(createStandalone).not.toHaveBeenCalled();
    expect(saved).toHaveBeenCalledTimes(1);
  });

  it("blocks a recurring expense with an invalid day or an end before the start", async () => {
    const element = await mount();
    $$(element, ".type-card")[1].click();
    await flushPromises();
    await type(element, ".field-description", "Aluguel");
    await type(element, ".field-amount", "2500");
    await type(element, ".field-due", "2026-11-05");
    expect($(element, ".next").disabled).toBe(false);
    await type(element, ".field-due-day", "32");
    expect($(element, ".next").disabled).toBe(true);
    await type(element, ".field-due-day", "5");
    await type(element, ".field-end-date", "2026-10-01");
    expect($(element, ".next").disabled).toBe(true);
    await type(element, ".field-end-date", "2026-12-01");
    expect($(element, ".next").disabled).toBe(false);
  });

  it("stays on the payment step when the preview fails", async () => {
    previewRecurring.mockRejectedValue({
      body: { message: "O valor deve ser maior que zero." }
    });
    const element = await mount();
    $$(element, ".type-card")[1].click();
    await flushPromises();
    await type(element, ".field-description", "Aluguel");
    await type(element, ".field-amount", "2500");
    await type(element, ".field-due", "2026-11-05");
    $(element, ".next").click();
    await flushPromises();
    $(element, ".next").click();
    await flushPromises();
    expect($(element, ".wizard-error").textContent).toContain(
      "O valor deve ser maior que zero."
    );
    expect($(element, ".wizard-step").textContent).toContain("Etapa 2 de 3");
  });

  it("sends the account or card of a recurring expense and blocks a fractional day", async () => {
    const element = await mount();
    $$(element, ".type-card")[1].click();
    await flushPromises();
    await type(element, ".field-description", "Assinatura");
    await type(element, ".field-amount", "40");
    await type(element, ".field-due", "2026-11-05");
    await type(element, ".field-due-day", "5.5");
    expect($(element, ".next").disabled).toBe(true);
    await type(element, ".field-due-day", "5");
    $(element, ".next").click();
    await flushPromises();
    await type(element, ".field-method", "card");
    await type(element, ".field-source", "k1");
    $(element, ".next").click();
    await flushPromises();
    $(element, ".conclude").click();
    await flushPromises();
    const base = JSON.parse(createRecurring.mock.calls[0][0].requestJson).base;
    expect(base.cardId).toBe("k1");
    expect(base.accountId).toBeNull();
  });

  it("creates an installment expense from the total with a card", async () => {
    const element = await mount();
    $$(element, ".type-card")[2].click();
    await flushPromises();
    expect($(element, ".wizard-title").textContent).toContain(
      "Despesa parcelada"
    );
    expect($(element, ".field-status")).toBeNull();
    await type(element, ".field-description", "Geladeira");
    await type(element, ".field-amount", "1000");
    await type(element, ".field-due", "2026-11-10");
    expect($(element, ".next").disabled).toBe(true);
    await type(element, ".field-installment-count", "1");
    expect($(element, ".next").disabled).toBe(true);
    await type(element, ".field-installment-count", "3");
    expect($(element, ".next").disabled).toBe(false);
    $(element, ".next").click();
    await flushPromises();
    await type(element, ".field-method", "card");
    await type(element, ".field-source", "k1");
    $(element, ".next").click();
    await flushPromises();
    expect(previewInstallment).toHaveBeenCalledTimes(1);
    expect($(element, ".review-summary").textContent).toContain(
      "1 Contrato (Parcelado) e 3 lançamentos pendentes"
    );
    expect($(element, ".review-summary").textContent).toContain("1.000,00");

    const saved = jest.fn();
    element.addEventListener("saved", saved);
    $(element, ".conclude").click();
    await flushPromises();
    expect(createInstallment).toHaveBeenCalledTimes(1);
    expect(JSON.parse(createInstallment.mock.calls[0][0].requestJson)).toEqual({
      base: {
        holderId: "001A",
        description: "Geladeira",
        amount: 1000,
        dueDate: "2026-11-10",
        categoryId: null,
        accountId: null,
        cardId: "k1"
      },
      amountIsTotal: true,
      count: 3
    });
    expect(createRecurring).not.toHaveBeenCalled();
    expect(createStandalone).not.toHaveBeenCalled();
    expect(saved).toHaveBeenCalledTimes(1);
  });

  it("sends the installment value when that is what the user informs", async () => {
    const element = await mount();
    $$(element, ".type-card")[2].click();
    await flushPromises();
    await type(element, ".field-amount-kind", "installment");
    expect($(element, ".field-amount").label).toBe("Valor da parcela");
    await type(element, ".field-description", "Geladeira");
    await type(element, ".field-amount", "300");
    await type(element, ".field-due", "2026-11-10");
    await type(element, ".field-installment-count", "10");
    $(element, ".next").click();
    await flushPromises();
    $(element, ".next").click();
    await flushPromises();
    $(element, ".conclude").click();
    await flushPromises();
    const request = JSON.parse(createInstallment.mock.calls[0][0].requestJson);
    expect(request.amountIsTotal).toBe(false);
    expect(request.count).toBe(10);
  });

  it("shows the parent and the child in the review and creates a new category from the picker", async () => {
    createCategory.mockResolvedValue({ id: "c3", label: "Pet" });
    const element = await mount();
    await chooseStandalone(element);
    await fillStep1(element);
    await type(element, ".field-category", "c2");
    $(element, ".next").click();
    await flushPromises();
    $(element, ".next").click();
    await flushPromises();
    expect($(element, ".review-line").textContent).toContain(
      "Moradia › Energia"
    );
    $(element, ".back").click();
    await flushPromises();
    $(element, ".back").click();
    await flushPromises();
    $(element, ".field-category").dispatchEvent(
      new CustomEvent("createcategory", { detail: { name: "Pet" } })
    );
    await flushPromises();
    expect(createCategory).toHaveBeenCalledWith({
      name: "Pet",
      parentId: null
    });
    expect($(element, ".field-category").value).toBe("c3");
  });

  it("shows the error when the category cannot be created", async () => {
    createCategory.mockRejectedValue({
      body: { message: "Informe o nome da categoria." }
    });
    const element = await mount();
    await chooseStandalone(element);
    $(element, ".field-category").dispatchEvent(
      new CustomEvent("createcategory", { detail: { name: " " } })
    );
    await flushPromises();
    expect($(element, ".wizard-error").textContent).toContain(
      "Informe o nome da categoria."
    );
  });

  it("creates the category once when the picker asks twice", async () => {
    let resolve;
    createCategory.mockReturnValue(
      new Promise((r) => {
        resolve = r;
      })
    );
    const element = await mount();
    await chooseStandalone(element);
    const ask = () =>
      $(element, ".field-category").dispatchEvent(
        new CustomEvent("createcategory", { detail: { name: "Pet" } })
      );
    ask();
    ask();
    await flushPromises();
    expect(createCategory).toHaveBeenCalledTimes(1);
    resolve({ id: "c3", label: "Pet" });
    await flushPromises();
    expect($(element, ".field-category").value).toBe("c3");
    expect(
      $(element, ".field-category").options.filter((o) => o.id === "c3")
    ).toHaveLength(1);
  });

  it("shows the error and stays on review when the recurring contract cannot be saved", async () => {
    createRecurring.mockRejectedValue({
      body: { message: "Nenhum lançamento seria gerado para este período." }
    });
    const element = await mount();
    $$(element, ".type-card")[1].click();
    await flushPromises();
    await type(element, ".field-description", "Aluguel");
    await type(element, ".field-amount", "2500");
    await type(element, ".field-due", "2026-11-05");
    $(element, ".next").click();
    await flushPromises();
    $(element, ".next").click();
    await flushPromises();
    const saved = jest.fn();
    element.addEventListener("saved", saved);
    $(element, ".conclude").click();
    await flushPromises();
    expect($(element, ".wizard-error").textContent).toContain(
      "Nenhum lançamento seria gerado"
    );
    expect(saved).not.toHaveBeenCalled();
    expect($(element, ".conclude").disabled).toBe(false);
  });

  it("forgets what was typed for one type when the type is changed", async () => {
    const element = await mount();
    $$(element, ".type-card")[1].click();
    await flushPromises();
    await type(element, ".field-description", "Aluguel");
    await type(element, ".field-amount", "2500");
    await type(element, ".field-due", "2026-11-05");
    await type(element, ".field-variable", "yes");
    await type(element, ".field-due-day", "7");
    await type(element, ".field-end-date", "2027-01-05");
    $(element, ".change-type").click();
    await flushPromises();
    $$(element, ".type-card")[1].click();
    await flushPromises();
    expect($(element, ".field-variable").value).toBe("no");
    expect($(element, ".field-due-day").value).toBeUndefined();
    expect($(element, ".field-end-date").value).toBeUndefined();
  });

  it("needs the first due date before an end date counts as valid, and says 1 lançamento in the singular", async () => {
    previewRecurring.mockResolvedValue([
      { dueDate: "2026-11-05", amount: 2500 }
    ]);
    const element = await mount();
    $$(element, ".type-card")[1].click();
    await flushPromises();
    await type(element, ".field-description", "Aluguel");
    await type(element, ".field-amount", "2500");
    await type(element, ".field-end-date", "2027-01-05");
    expect($(element, ".next").disabled).toBe(true);
    await type(element, ".field-due", "2026-11-05");
    expect($(element, ".next").disabled).toBe(false);
    $(element, ".next").click();
    await flushPromises();
    $(element, ".next").click();
    await flushPromises();
    expect($(element, ".review-summary").textContent).toContain(
      "1 lançamento pendente"
    );
    expect($(element, ".review-summary").textContent).not.toContain(
      "1 lançamentos"
    );
  });

  it("sends the account of an installment expense and blocks a count with an exponent", async () => {
    const element = await mount();
    $$(element, ".type-card")[2].click();
    await flushPromises();
    await type(element, ".field-description", "Geladeira");
    await type(element, ".field-amount", "1000");
    await type(element, ".field-due", "2026-11-10");
    await type(element, ".field-installment-count", "1e1");
    expect($(element, ".next").disabled).toBe(true);
    await type(element, ".field-installment-count", "3");
    $(element, ".next").click();
    await flushPromises();
    await type(element, ".field-method", "account");
    await type(element, ".field-source", "a1");
    $(element, ".next").click();
    await flushPromises();
    $(element, ".conclude").click();
    await flushPromises();
    const base = JSON.parse(
      createInstallment.mock.calls[0][0].requestJson
    ).base;
    expect(base.accountId).toBe("a1");
    expect(base.cardId).toBeNull();
  });

  it("shows the error of the installment preview and of saving it", async () => {
    previewInstallment.mockRejectedValueOnce({
      body: {
        message: "O valor total é pequeno demais para este número de parcelas."
      }
    });
    const element = await mount();
    $$(element, ".type-card")[2].click();
    await flushPromises();
    await type(element, ".field-description", "Geladeira");
    await type(element, ".field-amount", "1");
    await type(element, ".field-due", "2026-11-10");
    await type(element, ".field-installment-count", "120");
    $(element, ".next").click();
    await flushPromises();
    $(element, ".next").click();
    await flushPromises();
    expect($(element, ".wizard-error").textContent).toContain("pequeno demais");
    expect($(element, ".wizard-step").textContent).toContain("Etapa 2 de 3");

    createInstallment.mockRejectedValueOnce({
      body: { message: "Não foi possível gerar todas as parcelas." }
    });
    $(element, ".next").click();
    await flushPromises();
    expect($(element, ".wizard-step").textContent).toContain("Etapa 3 de 3");
    $(element, ".conclude").click();
    await flushPromises();
    expect($(element, ".wizard-error").textContent).toContain(
      "Não foi possível gerar todas as parcelas."
    );
    expect($(element, ".conclude").disabled).toBe(false);
  });

  it("forgets the installment kind and count when the type is changed", async () => {
    const element = await mount();
    $$(element, ".type-card")[2].click();
    await flushPromises();
    await type(element, ".field-amount-kind", "installment");
    await type(element, ".field-installment-count", "12");
    $(element, ".change-type").click();
    await flushPromises();
    $$(element, ".type-card")[2].click();
    await flushPromises();
    expect($(element, ".field-amount-kind").value).toBe("total");
    expect($(element, ".field-installment-count").value).toBeUndefined();
  });

  it("creates a consortium with the administrator and the award date", async () => {
    const element = await mount();
    $$(element, ".type-card")[3].click();
    await flushPromises();
    expect($(element, ".wizard-title").textContent).toContain("Consórcio");
    expect($(element, ".field-status")).toBeNull();
    expect($(element, ".field-amount-kind")).toBeNull();
    expect($(element, ".field-amount").label).toBe("Valor da parcela");
    expect($(element, ".field-installment-count").max).toBe(240);
    await type(element, ".field-description", "Consórcio do carro");
    await type(element, ".field-administrator", "Administradora X");
    await type(element, ".field-amount", "1200");
    await type(element, ".field-due", "2026-11-15");
    await type(element, ".field-awarded-on", "2027-05-01");
    await type(element, ".field-installment-count", "241");
    expect($(element, ".next").disabled).toBe(true);
    await type(element, ".field-installment-count", "60");
    expect($(element, ".next").disabled).toBe(false);
    $(element, ".next").click();
    await flushPromises();
    $(element, ".next").click();
    await flushPromises();
    expect(previewConsortium).toHaveBeenCalledTimes(1);
    expect(
      $(element, ".review-summary").textContent.replace(/\u00a0/g, " ")
    ).toContain(
      "1 Contrato (Consórcio) e 3 lançamentos pendentes. Total R$ 3.600,00."
    );

    const saved = jest.fn();
    element.addEventListener("saved", saved);
    $(element, ".conclude").click();
    await flushPromises();
    expect(JSON.parse(createConsortium.mock.calls[0][0].requestJson)).toEqual({
      base: {
        holderId: "001A",
        description: "Consórcio do carro",
        amount: 1200,
        dueDate: "2026-11-15",
        categoryId: null,
        accountId: null,
        cardId: null
      },
      count: 60,
      administrator: "Administradora X",
      awardedOn: "2027-05-01"
    });
    expect(createInstallment).not.toHaveBeenCalled();
    expect(createRecurring).not.toHaveBeenCalled();
    expect(saved).toHaveBeenCalledTimes(1);
  });

  it("sends null for an empty administrator and award date, and shows the save error", async () => {
    createConsortium.mockRejectedValueOnce({
      body: { message: "Não foi possível gerar todas as parcelas." }
    });
    const element = await mount();
    $$(element, ".type-card")[3].click();
    await flushPromises();
    await type(element, ".field-description", "Consórcio");
    await type(element, ".field-amount", "500");
    await type(element, ".field-due", "2026-11-15");
    await type(element, ".field-installment-count", "12");
    $(element, ".next").click();
    await flushPromises();
    $(element, ".next").click();
    await flushPromises();
    $(element, ".conclude").click();
    await flushPromises();
    const request = JSON.parse(createConsortium.mock.calls[0][0].requestJson);
    expect(request.administrator).toBeNull();
    expect(request.awardedOn).toBeNull();
    expect($(element, ".wizard-error").textContent).toContain(
      "Não foi possível gerar todas as parcelas."
    );
  });

  it("forgets the consortium fields when the type is changed", async () => {
    const element = await mount();
    $$(element, ".type-card")[3].click();
    await flushPromises();
    await type(element, ".field-administrator", "Administradora X");
    await type(element, ".field-awarded-on", "2027-05-01");
    await type(element, ".field-installment-count", "60");
    $(element, ".change-type").click();
    await flushPromises();
    $$(element, ".type-card")[3].click();
    await flushPromises();
    expect($(element, ".field-administrator").value).toBe("");
    expect($(element, ".field-awarded-on").value).toBeUndefined();
    expect($(element, ".field-installment-count").value).toBeUndefined();
  });

  it("shows the administrator and the award date in the review of a consortium", async () => {
    const element = await mount();
    $$(element, ".type-card")[3].click();
    await flushPromises();
    await type(element, ".field-description", "Consórcio do carro");
    await type(element, ".field-administrator", "Administradora X");
    await type(element, ".field-amount", "1200");
    await type(element, ".field-due", "2026-11-15");
    await type(element, ".field-awarded-on", "2027-05-01");
    await type(element, ".field-installment-count", "60");
    expect($(element, ".field-administrator").maxLength).toBe("120");
    $(element, ".next").click();
    await flushPromises();
    $(element, ".next").click();
    await flushPromises();
    expect($(element, ".review-details").textContent).toContain(
      "Administradora: Administradora X · Contemplado em 01/05/2027"
    );
  });

  it("hides the details line when a consortium has neither administrator nor award date", async () => {
    const element = await mount();
    $$(element, ".type-card")[3].click();
    await flushPromises();
    await type(element, ".field-description", "Consórcio");
    await type(element, ".field-amount", "500");
    await type(element, ".field-due", "2026-11-15");
    await type(element, ".field-installment-count", "1");
    expect($(element, ".next").disabled).toBe(true);
    await type(element, ".field-installment-count", "12");
    $(element, ".next").click();
    await flushPromises();
    $(element, ".next").click();
    await flushPromises();
    expect($(element, ".review-details")).toBeNull();
  });

  it("sends the account of a consortium and shows the preview error", async () => {
    previewConsortium.mockRejectedValueOnce({
      body: { message: "O número de parcelas deve ser de 2 a 240." }
    });
    const element = await mount();
    $$(element, ".type-card")[3].click();
    await flushPromises();
    await type(element, ".field-description", "Consórcio");
    await type(element, ".field-amount", "500");
    await type(element, ".field-due", "2026-11-15");
    await type(element, ".field-installment-count", "12");
    $(element, ".next").click();
    await flushPromises();
    await type(element, ".field-method", "account");
    await type(element, ".field-source", "a1");
    $(element, ".next").click();
    await flushPromises();
    expect($(element, ".wizard-error").textContent).toContain("de 2 a 240");
    expect($(element, ".wizard-step").textContent).toContain("Etapa 2 de 3");
    $(element, ".next").click();
    await flushPromises();
    $(element, ".conclude").click();
    await flushPromises();
    const base = JSON.parse(createConsortium.mock.calls[0][0].requestJson).base;
    expect(base.accountId).toBe("a1");
    expect(base.cardId).toBeNull();
  });

  it("ignores a second click on Concluir while the first is saving", async () => {
    let resolve;
    createConsortium.mockReturnValueOnce(
      new Promise((r) => {
        resolve = r;
      })
    );
    const element = await mount();
    $$(element, ".type-card")[3].click();
    await flushPromises();
    await type(element, ".field-description", "Consórcio");
    await type(element, ".field-amount", "500");
    await type(element, ".field-due", "2026-11-15");
    await type(element, ".field-installment-count", "12");
    $(element, ".next").click();
    await flushPromises();
    $(element, ".next").click();
    await flushPromises();
    const concluded = $(element, ".conclude");
    concluded.click();
    concluded.click();
    await flushPromises();
    expect(createConsortium).toHaveBeenCalledTimes(1);
    resolve("a0K");
    await flushPromises();
  });

  async function fillFinancing(element, rate = "1", count = "12") {
    $$(element, ".type-card")[4].click();
    await flushPromises();
    await type(element, ".field-description", "Financiamento do apartamento");
    await type(element, ".field-creditor", "Banco Y");
    await type(element, ".field-amount", "1200");
    await type(element, ".field-rate", rate);
    await type(element, ".field-installment-count", count);
    await type(element, ".field-due", "2026-11-10");
  }

  const plain = (element, selector) =>
    $(element, selector).textContent.replace(/\u00a0/g, " ");

  it("shows the first installment while typing, for PRICE and for SAC", async () => {
    const element = await mount();
    await fillFinancing(element, "1", "12");
    // PRICE: 1200 * 0.01 / (1 - 1.01^-12) = 106,62
    expect(plain(element, ".first-installment")).toContain(
      "1ª parcela ≈ R$ 106,62 (PRICE)"
    );
    await type(element, ".field-system", "SAC");
    // SAC: 1200 / 12 + 1200 * 0.01 = 112,00
    expect(plain(element, ".first-installment")).toContain(
      "1ª parcela ≈ R$ 112,00 (SAC)"
    );
    await type(element, ".field-rate", "0");
    expect(plain(element, ".first-installment")).toContain(
      "1ª parcela ≈ R$ 100,00 (SAC)"
    );
  });

  it("creates a financing with the creditor, the rate and the system", async () => {
    const element = await mount();
    await fillFinancing(element, "0.9", "36");
    expect($(element, ".wizard-title").textContent).toContain("Financiamento");
    expect($(element, ".field-amount").label).toBe("Valor financiado");
    expect($(element, ".field-installment-count").max).toBe(480);
    await type(element, ".field-system", "SAC");
    $(element, ".next").click();
    await flushPromises();
    $(element, ".next").click();
    await flushPromises();
    expect(previewFinancing).toHaveBeenCalledTimes(1);
    expect(plain(element, ".review-summary")).toContain(
      "1 Contrato (Financiamento) e 3 lançamentos pendentes. Total previsto R$ 333,00."
    );
    expect(plain(element, ".review-details")).toContain(
      "Credor: Banco Y · Juros totais R$ 33,00"
    );
    expect($(element, ".review-preview").textContent).toContain("juros");

    const saved = jest.fn();
    element.addEventListener("saved", saved);
    $(element, ".conclude").click();
    await flushPromises();
    expect(JSON.parse(createFinancing.mock.calls[0][0].requestJson)).toEqual({
      base: {
        holderId: "001A",
        description: "Financiamento do apartamento",
        amount: 1200,
        dueDate: "2026-11-10",
        categoryId: null,
        accountId: null,
        cardId: null
      },
      count: 36,
      monthlyRate: 0.9,
      installmentAmount: null,
      amortizationSystem: "SAC",
      creditor: "Banco Y",
      insurance: null,
      adminFee: null,
      otherCharges: null,
      upfrontCosts: null
    });
    expect(createConsortium).not.toHaveBeenCalled();
    expect(saved).toHaveBeenCalledTimes(1);
  });

  it("adds the monthly charges to the first installment hint", async () => {
    const element = await mount();
    await fillFinancing(element, "1", "12");
    await type(element, ".field-insurance", "10");
    await type(element, ".field-admin-fee", "5");
    // PRICE 106,62 + 15,00 of charges
    expect(plain(element, ".first-installment")).toContain(
      "1ª parcela ≈ R$ 121,62 (PRICE)"
    );
  });

  it("sends the informed installment and the charges, without rate or system choice", async () => {
    const element = await mount();
    await fillFinancing(element, "1", "12");
    await type(element, ".field-financing-mode", "installment");
    expect($(element, ".field-rate")).toBeNull();
    expect($(element, ".field-system")).toBeNull();
    expect($(element, ".next").disabled).toBe(true);
    await type(element, ".field-installment-amount", "120");
    await type(element, ".field-insurance", "10");
    await type(element, ".field-upfront", "200");
    expect($(element, ".next").disabled).toBe(false);
    expect(plain(element, ".first-installment")).toContain(
      "Parcela R$ 130,00 com encargos"
    );
    $(element, ".next").click();
    await flushPromises();
    $(element, ".next").click();
    await flushPromises();
    $(element, ".conclude").click();
    await flushPromises();
    const request = JSON.parse(createFinancing.mock.calls[0][0].requestJson);
    expect(request.monthlyRate).toBeNull();
    expect(request.installmentAmount).toBe(120);
    expect(request.amortizationSystem).toBe("PRICE");
    expect(request.insurance).toBe(10);
    expect(request.upfrontCosts).toBe(200);
  });

  it("needs an informed installment that pays the financed amount back", async () => {
    const element = await mount();
    await fillFinancing(element, "1", "12");
    await type(element, ".field-financing-mode", "installment");
    await type(element, ".field-installment-amount", "50");
    expect($(element, ".next").disabled).toBe(true);
    await type(element, ".field-installment-amount", "100");
    expect($(element, ".next").disabled).toBe(false);
    await type(element, ".field-upfront", "100");
    expect($(element, ".next").disabled).toBe(true);
  });

  it("does not accept negative charges", async () => {
    const element = await mount();
    await fillFinancing(element, "1", "12");
    await type(element, ".field-other-charges", "-1");
    expect($(element, ".next").disabled).toBe(true);
    await type(element, ".field-other-charges", "0");
    expect($(element, ".next").disabled).toBe(false);
  });

  it("needs a valid rate and count before going on", async () => {
    const element = await mount();
    await fillFinancing(element, "1", "481");
    expect($(element, ".next").disabled).toBe(true);
    await type(element, ".field-installment-count", "480");
    expect($(element, ".next").disabled).toBe(false);
    await type(element, ".field-rate", "100.5");
    expect($(element, ".next").disabled).toBe(true);
    await type(element, ".field-rate", "");
    expect($(element, ".next").disabled).toBe(true);
    await type(element, ".field-rate", "0");
    expect($(element, ".next").disabled).toBe(false);
  });

  it("sends the card of a financing, null creditor when empty, and shows the save error", async () => {
    createFinancing.mockRejectedValueOnce({
      body: { message: "Não foi possível gerar todas as parcelas." }
    });
    const element = await mount();
    await fillFinancing(element);
    await type(element, ".field-creditor", " ");
    $(element, ".next").click();
    await flushPromises();
    await type(element, ".field-method", "card");
    await type(element, ".field-source", "k1");
    $(element, ".next").click();
    await flushPromises();
    expect($(element, ".review-details").textContent).not.toContain("Credor");
    $(element, ".conclude").click();
    await flushPromises();
    const request = JSON.parse(createFinancing.mock.calls[0][0].requestJson);
    expect(request.creditor).toBeNull();
    expect(request.base.cardId).toBe("k1");
    expect(request.base.accountId).toBeNull();
    expect($(element, ".wizard-error").textContent).toContain(
      "Não foi possível gerar todas as parcelas."
    );
  });

  it("forgets the financing fields when the type is changed", async () => {
    const element = await mount();
    await fillFinancing(element, "1.5", "24");
    await type(element, ".field-system", "SAC");
    $(element, ".change-type").click();
    await flushPromises();
    $$(element, ".type-card")[4].click();
    await flushPromises();
    expect($(element, ".field-creditor").value).toBe("");
    expect($(element, ".field-rate").value).toBeUndefined();
    expect($(element, ".field-system").value).toBe("PRICE");
    expect($(element, ".first-installment")).toBeNull();
  });

  it("shows no first installment while the rate is empty or the amount is below one cent", async () => {
    const element = await mount();
    await fillFinancing(element, "1", "12");
    expect($(element, ".first-installment")).not.toBeNull();
    await type(element, ".field-rate", "");
    expect($(element, ".first-installment")).toBeNull();
    await type(element, ".field-rate", "1");
    await type(element, ".field-amount", "0.001");
    expect($(element, ".first-installment")).toBeNull();
    expect($(element, ".next").disabled).toBe(true);
    await type(element, ".field-amount", "0.01");
    expect($(element, ".first-installment")).not.toBeNull();
    expect($(element, ".first-installment").getAttribute("aria-live")).toBe(
      "polite"
    );
  });

  it("sends a missing rate as null instead of zero", async () => {
    const element = await mount();
    await fillFinancing(element, "1", "12");
    await type(element, ".field-rate", "");
    expect($(element, ".next").disabled).toBe(true);
    await type(element, ".field-rate", "0");
    $(element, ".next").click();
    await flushPromises();
    $(element, ".next").click();
    await flushPromises();
    $(element, ".conclude").click();
    await flushPromises();
    const request = JSON.parse(createFinancing.mock.calls[0][0].requestJson);
    expect(request.monthlyRate).toBe(0);
  });
});
