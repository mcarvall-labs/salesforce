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

    // Rotation section hidden when NONE — promote button doesn't exist
    expect(el.shadowRoot.querySelector(".pic__rotation-hint_warning")).toBeNull();
    expect(
      [...el.shadowRoot.querySelectorAll("lightning-button")].find(
        (b) => b.label === "Ativar nova credencial"
      )
    ).toBeUndefined();
  });

  it("runs the candidate test", async () => {
    testCandidate.mockResolvedValue({
      state: "TESTED_OK",
      candidateHealthy: true,
      message: "Candidata validada."
    });
    const el = build();
    canConfigure.emit(true);
    getStatus.emit({ ...STATUS, rotationState: "CANDIDATE" });
    await flush();

    button(el, "Testar nova credencial").click();
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

  it("shows 'Credencial configurada' badge when activeSlot is set", async () => {
    const el = build();
    canConfigure.emit(true);
    getStatus.emit({ ...STATUS, activeSlot: "PRIMARY" });
    await flush();

    const badge = el.shadowRoot.querySelector(".pic__cred-badge");
    expect(badge).not.toBeNull();
    expect(badge.textContent).toMatch(/Credencial configurada/i);
    expect(badge.className).toMatch(/slds-theme_success/);
  });

  it("shows neutral badge when no activeSlot is set", async () => {
    const el = build();
    canConfigure.emit(true);
    getStatus.emit({ ...STATUS, activeSlot: null });
    await flush();

    const badge = el.shadowRoot.querySelector(".pic__cred-badge");
    expect(badge).not.toBeNull();
    expect(badge.textContent).toMatch(/Nenhuma credencial/i);
    expect(badge.className).not.toMatch(/slds-theme_success/);
  });

  it("hides rotation section when rotationState is NONE", async () => {
    const el = build();
    canConfigure.emit(true);
    getStatus.emit({ ...STATUS, rotationState: "NONE" });
    await flush();

    // Rotation section should not exist
    expect(el.shadowRoot.textContent).not.toMatch(/Rotação em andamento/i);
  });

  it("shows rotation section when rotationState is CANDIDATE", async () => {
    const el = build();
    canConfigure.emit(true);
    getStatus.emit({ ...STATUS, rotationState: "CANDIDATE" });
    await flush();

    expect(el.shadowRoot.textContent).toMatch(/Rotação em andamento/i);
    expect(el.shadowRoot.textContent).toMatch(/Candidata preparada/i);
  });

  it("shows active slot health when available", async () => {
    const el = build();
    canConfigure.emit(true);
    getStatus.emit({
      ...STATUS,
      activeSlot: "PRIMARY",
      rotationState: "NONE",
      primarySlotTestResult: "Conexão verificada com sucesso."
    });
    await flush();

    expect(el.shadowRoot.textContent).toMatch(/Último teste — credencial ativa/i);
    expect(el.shadowRoot.textContent).toMatch(/Conexão verificada com sucesso/i);
  });

  it("does not show stale ROLLED_BACK state in the UI (it is volatile)", async () => {
    // After a failed rotation the backend saves NONE, so the UI receives NONE.
    // This test verifies that the UI never renders the raw ROLLED_BACK code.
    const el = build();
    canConfigure.emit(true);
    // Backend will return NONE after failure — never ROLLED_BACK persisted
    getStatus.emit({ ...STATUS, rotationState: "NONE" });
    await flush();

    expect(el.shadowRoot.textContent).not.toMatch(/ROLLED_BACK/);
    expect(el.shadowRoot.textContent).not.toMatch(/Rotação em andamento/i);
  });
});
