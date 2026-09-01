import { createElement } from "lwc";
import Config from "c/aXF_LWC_pluggyIntegrationConfig";
import canConfigure from "@salesforce/apex/AXF_CLS_CTRL_PluggyIntegrationConfig.canConfigure";
import getStatus from "@salesforce/apex/AXF_CLS_CTRL_PluggyIntegrationConfig.getStatus";
import setPrincipalCredential from "@salesforce/apex/AXF_CLS_CTRL_PluggyIntegrationConfig.setPrincipalCredential";
import testCandidate from "@salesforce/apex/AXF_CLS_CTRL_PluggyIntegrationConfig.testCandidate";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_PluggyIntegrationConfig.canConfigure",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_PluggyIntegrationConfig.getStatus",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_PluggyIntegrationConfig.setPrincipalCredential",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_PluggyIntegrationConfig.stageCandidateCredential",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_PluggyIntegrationConfig.testCandidate",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_PluggyIntegrationConfig.promoteCandidate",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_PluggyIntegrationConfig.rollbackRotation",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_PluggyIntegrationConfig.pauseGlobally",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_PluggyIntegrationConfig.resumeGlobally",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const STATUS = {
  canConfigure: true,
  activeSlot: "PRIMARY",
  rotationState: "TESTED_OK",
  primarySlotTestResult: "ok",
  candidateSlotTestResult: "Candidata validada.",
  collectionGloballyPaused: false,
  connectionCount: 2,
  blockedConnectionCount: 0
};

const flush = () => Promise.resolve();

function build() {
  const el = createElement("c-a-x-f_-l-w-c_pluggy-integration-config", {
    is: Config
  });
  document.body.appendChild(el);
  return el;
}

const input = (el, label) =>
  [...el.shadowRoot.querySelectorAll("lightning-input")].find((i) =>
    new RegExp(label, "i").test(i.label)
  );
const button = (el, label) =>
  [...el.shadowRoot.querySelectorAll("lightning-button")].find(
    (b) => b.label === label
  );

afterEach(() => {
  while (document.body.firstChild) {
    document.body.removeChild(document.body.firstChild);
  }
  jest.clearAllMocks();
});

describe("c-aXF_LWC_pluggyIntegrationConfig", () => {
  it("renders FORBIDDEN when the caller cannot configure", async () => {
    const el = build();
    canConfigure.emit(false);
    getStatus.emit({ canConfigure: false });
    await flush();
    expect(el.shadowRoot.querySelector("[role='status']").textContent).toMatch(
      /não tem autorização/i
    );
  });

  it("shows the status and the credential hint when authorized", async () => {
    const el = build();
    canConfigure.emit(true);
    getStatus.emit(STATUS);
    await flush();

    expect(el.shadowRoot.textContent).toMatch(
      /encaminhados direto para a Credencial Externa/i
    );
    expect(el.shadowRoot.textContent).toMatch(/PRIMARY/);
    expect(input(el, "Client ID")).toBeDefined();
  });

  it("keeps the credential buttons disabled until both fields are filled", async () => {
    const el = build();
    canConfigure.emit(true);
    getStatus.emit(STATUS);
    await flush();

    expect(button(el, "Salvar credencial ativa").disabled).toBe(true);

    const id = input(el, "Client ID");
    id.value = "cid";
    id.dispatchEvent(new CustomEvent("change"));
    const sec = input(el, "Client Secret");
    sec.value = "csec";
    sec.dispatchEvent(new CustomEvent("change"));
    await flush();

    expect(button(el, "Salvar credencial ativa").disabled).toBe(false);
  });

  it("forwards the credential to setPrincipalCredential and clears the inputs", async () => {
    setPrincipalCredential.mockResolvedValue({
      applied: true,
      message: "Credencial salva no mecanismo nativo."
    });
    const el = build();
    canConfigure.emit(true);
    getStatus.emit(STATUS);
    await flush();

    input(el, "Client ID").value = "cid";
    input(el, "Client ID").dispatchEvent(new CustomEvent("change"));
    input(el, "Client Secret").value = "csec";
    input(el, "Client Secret").dispatchEvent(new CustomEvent("change"));
    await flush();

    button(el, "Salvar credencial ativa").click();
    await flush();
    await flush();
    await flush();

    expect(setPrincipalCredential).toHaveBeenCalledWith({
      clientId: "cid",
      clientSecret: "csec"
    });
    const feedback = el.shadowRoot.querySelector(
      "[aria-live='polite'] lightning-formatted-text"
    );
    expect(feedback.value).toMatch(/salva/i);
    expect(input(el, "Client ID").value).toBe("");
  });

  it("enables Promover only when rotationState is TESTED_OK", async () => {
    const el = build();
    canConfigure.emit(true);
    getStatus.emit({ ...STATUS, rotationState: "NONE" });
    await flush();

    expect(button(el, "Promover candidata").disabled).toBe(true);
  });

  it("runs the candidate test", async () => {
    testCandidate.mockResolvedValue({
      state: "TESTED_OK",
      candidateHealthy: true,
      message: "Candidata validada."
    });
    const el = build();
    canConfigure.emit(true);
    getStatus.emit(STATUS);
    await flush();

    button(el, "Testar credencial candidata").click();
    await flush();
    await flush();
    await flush();
    await flush();

    expect(testCandidate).toHaveBeenCalled();
    const feedback = el.shadowRoot.querySelector(
      "[aria-live='polite'] lightning-formatted-text"
    );
    expect(feedback.value).toMatch(/validada/i);
  });

  it("shows an error state with retry when the status wire fails", async () => {
    const el = build();
    canConfigure.emit(true);
    getStatus.error();
    await flush();
    expect(el.shadowRoot.querySelector("[role='alert']").textContent).toMatch(
      /Não foi possível carregar/i
    );
  });
});
