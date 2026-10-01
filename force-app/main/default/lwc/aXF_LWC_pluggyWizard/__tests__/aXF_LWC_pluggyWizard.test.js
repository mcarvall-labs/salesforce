import { createElement } from "lwc";
import AXF_LWC_pluggyWizard from "c/aXF_LWC_pluggyWizard";
import getState from "@salesforce/apex/AXF_CLS_CTRL_PluggyWizard.getState";
import saveCredentials from "@salesforce/apex/AXF_CLS_CTRL_PluggyWizard.saveCredentials";
import testCredentials from "@salesforce/apex/AXF_CLS_CTRL_PluggyWizard.testCredentials";

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
  "@salesforce/apex/AXF_CLS_CTRL_PluggyWizard.testCredentials",
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);

const flushPromises = () =>
  Array.from({ length: 10 }).reduce(
    (chain) => chain.then(() => undefined),
    Promise.resolve()
  );

async function setup(hasCredentials = false) {
  getState.mockResolvedValue({ hasCredentials });
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
});
