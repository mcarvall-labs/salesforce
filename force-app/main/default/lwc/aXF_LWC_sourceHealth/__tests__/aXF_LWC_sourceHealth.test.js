import { createElement } from "lwc";
import SourceHealth from "c/aXF_LWC_sourceHealth";
import getSources from "@salesforce/apex/AXF_CLS_CTRL_SourceHealth.getSources";
import pauseConnection from "@salesforce/apex/AXF_CLS_CTRL_SourceHealth.pauseConnection";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_SourceHealth.getSources",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_SourceHealth.pauseConnection",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_SourceHealth.resumeConnection",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_SourceHealth.refreshConsent",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const SOURCES = [
  {
    connectionId: "a01000000000001",
    name: "CON-00001",
    institution: "Banco Teste",
    consentState: "ACTIVE",
    collectionState: "ACTIVE",
    lastSuccessAt: "2026-08-30T12:00:00.000Z",
    lastStatusCode: "OK",
    lastStatusDetail: null,
    impact: "Coleta ativa.",
    permittedAction: "PAUSE",
    canManage: true
  },
  {
    connectionId: "a01000000000002",
    name: "CON-00002",
    institution: "Banco Revogado",
    consentState: "REVOKED",
    collectionState: "ACTIVE",
    lastSuccessAt: null,
    lastStatusCode: "LOGIN_ERROR",
    lastStatusDetail: "Erro de login na origem.",
    impact: "Consentimento revogado.",
    permittedAction: "REAUTHORIZE",
    canManage: true
  }
];

const flush = () => Promise.resolve();

function build() {
  const el = createElement("c-a-x-f_-l-w-c_source-health", {
    is: SourceHealth
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

describe("c-aXF_LWC_sourceHealth", () => {
  it("shows a spinner before the wire resolves", () => {
    const el = build();
    expect(el.shadowRoot.querySelector("lightning-spinner")).not.toBeNull();
  });

  it("renders the empty state with no sources", async () => {
    const el = build();
    getSources.emit([]);
    await flush();
    expect(el.shadowRoot.querySelector("[role='status']").textContent).toMatch(
      /Nenhuma fonte conectada/i
    );
  });

  it("lists each source with institution, consent and impact text (no colour-only signal)", async () => {
    const el = build();
    getSources.emit(SOURCES);
    await flush();

    const items = el.shadowRoot.querySelectorAll("li.slds-item");
    expect(items).toHaveLength(2);
    expect(el.shadowRoot.textContent).toMatch(/Banco Teste/);
    expect(el.shadowRoot.textContent).toMatch(/Revogado/);
    // impact is rendered as text, associated to the row
    expect(el.shadowRoot.querySelector("[role='note']").textContent).toMatch(
      /Coleta ativa/
    );
  });

  it("offers Pausar for an active source and Reautorizar for a revoked one", async () => {
    const el = build();
    getSources.emit(SOURCES);
    await flush();

    const labels = [...el.shadowRoot.querySelectorAll("lightning-button")].map(
      (b) => b.label
    );
    expect(labels).toContain("Pausar");
    expect(labels).toContain("Reautorizar no provedor");
  });

  it("calls pauseConnection with the row id", async () => {
    pauseConnection.mockResolvedValue(undefined);
    const el = build();
    getSources.emit(SOURCES);
    await flush();

    const pauseBtn = [
      ...el.shadowRoot.querySelectorAll("lightning-button")
    ].find((b) => b.label === "Pausar");
    pauseBtn.click();
    await flush();

    expect(pauseConnection).toHaveBeenCalledWith({
      connectionId: "a01000000000001"
    });
  });

  it("renders an error state with retry when the wire fails", async () => {
    const el = build();
    getSources.error();
    await flush();
    expect(el.shadowRoot.querySelector("[role='alert']").textContent).toMatch(
      /Não foi possível carregar/i
    );
  });
});
