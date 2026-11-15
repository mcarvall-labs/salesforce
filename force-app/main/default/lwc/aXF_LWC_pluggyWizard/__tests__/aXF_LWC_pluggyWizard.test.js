import { createElement } from "lwc";
import AXF_LWC_pluggyWizard from "c/aXF_LWC_pluggyWizard";
import getState from "@salesforce/apex/AXF_CLS_CTRL_PluggyWizard.getState";
import saveCredentials from "@salesforce/apex/AXF_CLS_CTRL_PluggyWizard.saveCredentials";
import createConnection from "@salesforce/apex/AXF_CLS_CTRL_PluggyWizard.createConnection";
import testCredentials from "@salesforce/apex/AXF_CLS_CTRL_PluggyWizard.testCredentials";
import getConnections from "@salesforce/apex/AXF_CLS_CTRL_PluggyWizard.getConnections";
import getLinked from "@salesforce/apex/AXF_CLS_CTRL_PluggyWizard.getLinked";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_PluggyWizard.getState",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_PluggyWizard.saveCredentials",
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_PluggyWizard.createConnection",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_PluggyWizard.testCredentials",
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_PluggyWizard.getConnections",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_PluggyWizard.getLinked",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flushPromises = () =>
  Array.from({ length: 10 }).reduce(
    (chain) => chain.then(() => undefined),
    Promise.resolve()
  );

async function setup(hasCredentials = false, connectionCount = 0) {
  getState.mockResolvedValue({ hasCredentials, connectionCount });
  const element = createElement("c-a-x-f-l-w-c-pluggy-wizard", {
    is: AXF_LWC_pluggyWizard
  });
  document.body.appendChild(element);
  await flushPromises();
  return element;
}

function type(element, label, value) {
  const input = Array.from(
    element.shadowRoot.querySelectorAll("lightning-input")
  ).find((i) => i.label === label);
  input.value = value;
  input.dispatchEvent(new CustomEvent("change"));
}

describe("c-a-x-f-l-w-c-pluggy-wizard", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("starts at step 1 without credentials and at step 2 with them", async () => {
    let element = await setup(false);
    expect(
      element.shadowRoot.querySelector("lightning-progress-indicator")
        .currentStep
    ).toBe("1");
    document.body.removeChild(element);
    element = await setup(true);
    expect(
      element.shadowRoot.querySelector("lightning-progress-indicator")
        .currentStep
    ).toBe("2");
  });

  it("saves then tests the credentials and shows the result", async () => {
    saveCredentials.mockResolvedValue({
      success: true,
      message: "Credenciais salvas."
    });
    testCredentials.mockResolvedValue({
      success: true,
      message: "Autenticação com o Pluggy realizada com sucesso."
    });
    const element = await setup(false);
    type(element, "Client Id", "id");
    type(element, "Client Secret", "secret");
    await flushPromises();
    element.shadowRoot.querySelector("lightning-button").click();
    await flushPromises();
    expect(saveCredentials).toHaveBeenCalledWith({
      clientId: "id",
      clientSecret: "secret"
    });
    expect(testCredentials).toHaveBeenCalledTimes(1);
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("sucesso");
  });

  it("shows the error and skips the test when saving fails", async () => {
    saveCredentials.mockResolvedValue({
      success: false,
      message: "Sem permissão."
    });
    const element = await setup(false);
    type(element, "Client Id", "id");
    type(element, "Client Secret", "secret");
    await flushPromises();
    element.shadowRoot.querySelector("lightning-button").click();
    await flushPromises();
    expect(testCredentials).not.toHaveBeenCalled();
    expect(element.shadowRoot.querySelector('[role="alert"]').textContent).toBe(
      "Sem permissão."
    );
  });

  it("creates the connection from step 2 and advances to step 3", async () => {
    createConnection.mockResolvedValue({
      success: true,
      message: "Conexão criada.",
      connectionId: "a00000000000009"
    });
    getConnections.mockResolvedValue([{ id: "a00000000000009", label: "Ana" }]);
    getLinked.mockResolvedValue([]);
    const element = await setup(true, 0);
    element.shadowRoot
      .querySelector("lightning-record-picker")
      .dispatchEvent(
        new CustomEvent("change", { detail: { recordId: "001000000000001" } })
      );
    element.shadowRoot
      .querySelector("c-a-x-f_-l-w-c_bank-institution-picker")
      .dispatchEvent(new CustomEvent("change", { detail: { value: "341" } }));
    const itemInput = Array.from(
      element.shadowRoot.querySelectorAll("lightning-input")
    ).find((i) => i.label === "Item Id");
    itemInput.value = "item-1";
    itemInput.dispatchEvent(new CustomEvent("change"));
    await flushPromises();
    const create = Array.from(
      element.shadowRoot.querySelectorAll("lightning-button")
    ).find((b) => b.label === "Criar conexão");
    create.click();
    await flushPromises();
    expect(createConnection).toHaveBeenCalledWith({
      holderId: "001000000000001",
      institution: "341",
      itemId: "item-1"
    });
    expect(
      element.shadowRoot.querySelector("lightning-progress-indicator")
        .currentStep
    ).toBe("3");
    expect(getLinked).toHaveBeenCalledWith({ connectionId: "a00000000000009" });
    expect(element.shadowRoot.querySelector("lightning-combobox").value).toBe(
      "a00000000000009"
    );
  });

  it("lists the linked accounts and cards of the connection chosen on step 3", async () => {
    getConnections.mockResolvedValue([
      { id: "a00000000000001", label: "Ana" },
      { id: "a00000000000002", label: "Bia" }
    ]);
    getLinked.mockResolvedValue([
      {
        id: "a01",
        holder: "Bia",
        kind: "Conta",
        name: "Conta Corrente",
        detail: "0001 / 123"
      }
    ]);
    const element = await setup(true, 2);
    expect(getLinked).not.toHaveBeenCalled();
    element.shadowRoot
      .querySelector("lightning-combobox")
      .dispatchEvent(
        new CustomEvent("change", { detail: { value: "a00000000000002" } })
      );
    await flushPromises();
    expect(getLinked).toHaveBeenCalledWith({ connectionId: "a00000000000002" });
    expect(element.shadowRoot.querySelectorAll("tbody tr")).toHaveLength(1);
    expect(element.shadowRoot.querySelector("tbody").textContent).toContain(
      "Bia"
    );
  });

  it("has no sync button on step 3", async () => {
    getConnections.mockResolvedValue([{ id: "a00000000000001", label: "x" }]);
    const element = await setup(true, 1);
    const labels = Array.from(
      element.shadowRoot.querySelectorAll("lightning-button")
    ).map((b) => b.label);
    expect(labels).not.toContain("Sincronizar contas e cartões");
  });
});
