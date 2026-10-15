import { createElement } from "lwc";
import AXF_LWC_contractEdit from "c/aXF_LWC_contractEdit";
import { getRecord } from "lightning/uiRecordApi";
import preview from "@salesforce/apex/AXF_CLS_CTRL_ContractScope.preview";
import save from "@salesforce/apex/AXF_CLS_CTRL_ContractScope.save";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ContractScope.preview",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ContractScope.save",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "lightning/actions",
  () => ({
    CloseActionScreenEvent: class extends CustomEvent {
      constructor() {
        super("lightning__actionsclosescreen");
      }
    }
  }),
  { virtual: true }
);

const RECORD_ID = "a00000000000001AAA";
const flush = async () => {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
};

const record = (typeName = "AXF_Consortium") => ({
  fields: {
    Name: { value: "Carta 1" },
    AXF_CTR_CUR_Amount__c: { value: 780 },
    AXF_CTR_CUR_FinancedAmount__c: { value: null },
    AXF_CTR_NUM_DueDay__c: { value: null },
    AXF_CTR_DAT_FirstDueDate__c: { value: "2026-05-10" },
    AXF_CTR_NUM_InstallmentCount__c: { value: 12 },
    AXF_CTR_LKP_Category__c: { value: null },
    AXF_CTR_LKP_BankAccount__c: { value: null },
    AXF_CTR_LKP_CreditCard__c: { value: null },
    AXF_CTR_TXT_Counterparty__c: { value: "Sicoob" },
    RecordType: { value: { fields: { DeveloperName: { value: typeName } } } }
  }
});

const PREVIEW = {
  updated: 1,
  kept: 1,
  preserved: 1,
  missing: 0,
  rows: [
    {
      entryId: "e1",
      ordinal: 1,
      status: "Realized",
      outcome: "PRESERVED",
      name: "Carta 1 1/12",
      newName: "Carta 1 1/12",
      dueDate: "2026-05-10",
      newDueDate: "2026-05-10",
      amount: 780,
      newAmount: 780
    },
    {
      entryId: "e2",
      ordinal: 2,
      status: "Pending",
      outcome: "UPDATE",
      name: "Carta 1 2/12",
      newName: "Carta 1 2/12",
      dueDate: "2026-06-10",
      newDueDate: "2026-06-10",
      amount: 780,
      newAmount: 800
    }
  ]
};

async function setup(typeName) {
  const element = createElement("c-axf-lwc-contract-edit", {
    is: AXF_LWC_contractEdit
  });
  element.recordId = RECORD_ID;
  document.body.appendChild(element);
  const toasts = [];
  const closed = jest.fn();
  element.addEventListener("lightning__showtoast", (e) =>
    toasts.push(e.detail)
  );
  element.addEventListener("lightning__actionsclosescreen", closed);
  getRecord.emit(record(typeName));
  await flush();
  return { element, toasts, closed };
}

const root = (element) => element.shadowRoot;
const input = (element, api) =>
  root(element).querySelector(`lightning-input[data-api="${api}"]`);
const button = (element, label) =>
  [...root(element).querySelectorAll("lightning-button")].find(
    (b) => b.label === label
  );

async function typeInto(element, api, value) {
  input(element, api).dispatchEvent(
    new CustomEvent("change", { detail: { value } })
  );
  await flush();
}

describe("c-axf-lwc-contract-edit", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("step 1 shows the fields of the contract type and blocks Continue until something changes", async () => {
    const { element } = await setup();
    expect(input(element, "Name").value).toBe("Carta 1");
    expect(input(element, "AXF_CTR_NUM_InstallmentCount__c")).not.toBeNull();
    expect(input(element, "AXF_CTR_NUM_DueDay__c")).toBeNull();
    expect(button(element, "Continuar").disabled).toBe(true);
    await typeInto(element, "Name", "Carta 2");
    expect(button(element, "Continuar").disabled).toBe(false);
    await typeInto(element, "Name", "");
    expect(button(element, "Continuar").disabled).toBe(true);
  });

  it("recurring contracts edit the due day instead of the first due date", async () => {
    const { element } = await setup("AXF_Recurring");
    expect(input(element, "AXF_CTR_NUM_DueDay__c")).not.toBeNull();
    expect(input(element, "AXF_CTR_DAT_FirstDueDate__c")).toBeNull();
  });

  it("step 2 previews with one scope selector per changed field and sends the choices", async () => {
    preview.mockResolvedValue(PREVIEW);
    const { element } = await setup();
    await typeInto(element, "Name", "Carta 2");
    await typeInto(element, "AXF_CTR_CUR_Amount__c", "800");
    button(element, "Continuar").click();
    await flush();
    expect(preview).toHaveBeenCalledWith({
      contractId: RECORD_ID,
      values: { Name: "Carta 2", AXF_CTR_CUR_Amount__c: "800" },
      scopes: {
        NAME: { scope: "FUTURE", fromNumber: null },
        AMOUNT: { scope: "FUTURE", fromNumber: null }
      }
    });
    const selectors = root(element).querySelectorAll("lightning-combobox");
    expect(selectors).toHaveLength(2);
    expect(root(element).querySelectorAll("tbody tr")).toHaveLength(2);
    expect(root(element).textContent).toContain("preservados");

    preview.mockClear();
    selectors[1].dispatchEvent(
      new CustomEvent("change", { detail: { value: "FROM" } })
    );
    await flush();
    expect(preview).not.toHaveBeenCalled();
    const from = [...root(element).querySelectorAll("lightning-input")].find(
      (item) => item.label === "Parcela inicial"
    );
    expect(from).toBeDefined();
    from.dispatchEvent(new CustomEvent("change", { detail: { value: "3" } }));
    await flush();
    expect(preview.mock.calls[0][0].scopes.AMOUNT).toEqual({
      scope: "FROM",
      fromNumber: "3"
    });
    expect(preview.mock.calls[0][0].scopes.NAME.scope).toBe("FUTURE");
  });

  it("Aplicar saves, toasts and closes", async () => {
    preview.mockResolvedValue(PREVIEW);
    save.mockResolvedValue({ updated: 4, created: 0 });
    const { element, toasts, closed } = await setup();
    await typeInto(element, "AXF_CTR_CUR_Amount__c", "800");
    button(element, "Continuar").click();
    await flush();
    button(element, "Aplicar").click();
    await flush();
    expect(save).toHaveBeenCalledTimes(1);
    expect(toasts[0].variant).toBe("success");
    expect(toasts[0].message).toBe(
      "Contrato salvo. 4 Lançamento(s) atualizado(s)."
    );
    expect(closed).toHaveBeenCalled();
  });

  it("shows the server error in a toast and stays open", async () => {
    preview.mockResolvedValue(PREVIEW);
    save.mockRejectedValue({
      body: { message: "Não foi possível atualizar o lançamento X." }
    });
    const { element, toasts, closed } = await setup();
    await typeInto(element, "AXF_CTR_CUR_Amount__c", "800");
    button(element, "Continuar").click();
    await flush();
    button(element, "Aplicar").click();
    await flush();
    expect(toasts[0].variant).toBe("error");
    expect(toasts[0].message).toContain("Não foi possível atualizar");
    expect(closed).not.toHaveBeenCalled();
  });

  it("Cancelar does not save", async () => {
    preview.mockResolvedValue(PREVIEW);
    const { element, closed } = await setup();
    await typeInto(element, "AXF_CTR_CUR_Amount__c", "800");
    button(element, "Continuar").click();
    await flush();
    button(element, "Cancelar").click();
    await flush();
    expect(save).not.toHaveBeenCalled();
    expect(closed).toHaveBeenCalled();
  });

  it("Voltar returns to the form", async () => {
    preview.mockResolvedValue(PREVIEW);
    const { element } = await setup();
    await typeInto(element, "AXF_CTR_CUR_Amount__c", "800");
    button(element, "Continuar").click();
    await flush();
    button(element, "Voltar").click();
    await flush();
    expect(input(element, "AXF_CTR_CUR_Amount__c")).not.toBeNull();
    expect(input(element, "AXF_CTR_CUR_Amount__c").value).toBe("800");
  });
});
