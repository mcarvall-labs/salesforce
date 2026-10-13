import { createElement } from "lwc";
import AXF_LWC_expenseWizard from "c/aXF_LWC_expenseWizard";
import getOptions from "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.getOptions";
import createStandalone from "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.createStandalone";
import createCategory from "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.createCategory";
import createRecurring from "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.createRecurring";
import previewRecurring from "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.previewRecurring";
import createInstallment from "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.createInstallment";
import previewInstallment from "@salesforce/apex/AXF_CLS_CTRL_ExpenseWizard.previewInstallment";

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

  it("asks the type first and only enables the standalone, recurring and installment expenses", async () => {
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
});
