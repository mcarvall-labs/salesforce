import { createElement } from "lwc";
import Config from "c/aXF_LWC_pluggyIntegrationConfig";
import canConfigure from "@salesforce/apex/AXF_CLS_CTRL_PluggyIntegrationConfig.canConfigure";
import getStatus from "@salesforce/apex/AXF_CLS_CTRL_PluggyIntegrationConfig.getStatus";
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
  webhookEnabled: true,
  cacheTtlSeconds: 5400,
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

  it("shows the status and the secret-entry hint when authorized", async () => {
    const el = build();
    canConfigure.emit(true);
    getStatus.emit(STATUS);
    await flush();

    expect(el.shadowRoot.textContent).toMatch(/Setup de Credenciais Externas/i);
    expect(el.shadowRoot.textContent).toMatch(/PRIMARY/);
  });

  it("enables Promover only when rotationState is TESTED_OK", async () => {
    const el = build();
    canConfigure.emit(true);
    getStatus.emit({ ...STATUS, rotationState: "NONE" });
    await flush();

    const promote = [
      ...el.shadowRoot.querySelectorAll("lightning-button")
    ].find((b) => b.label === "Promover candidata");
    expect(promote.disabled).toBe(true);
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

    const testBtn = [
      ...el.shadowRoot.querySelectorAll("lightning-button")
    ].find((b) => b.label === "Testar credencial candidata");
    testBtn.click();
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
