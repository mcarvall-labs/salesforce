import { createElement } from "lwc";
import Disc from "c/aXF_LWC_sourceDiscovery";
import getStatus from "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.getStatus";
import getDiscovered from "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.getDiscovered";
import startDiscovery from "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.startDiscovery";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.getStatus",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.getDiscovered",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.startDiscovery",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.registerConnection",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.getConnections",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
import registerConnection from "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.registerConnection";
import getConnections from "@salesforce/apex/AXF_CLS_CTRL_SourceDiscovery.getConnections";

jest.mock("@salesforce/i18n/lang", () => ({ default: "pt-BR" }), {
  virtual: true
});

const flush = () => Promise.resolve();
const button = (el, re) =>
  [...el.shadowRoot.querySelectorAll("lightning-button")].find((b) =>
    re.test(b.label)
  );

function build() {
  const el = createElement("c-a-x-f_-l-w-c_source-discovery", { is: Disc });
  el.recordId = "a01000000000001";
  document.body.appendChild(el);
  return el;
}

afterEach(() => {
  while (document.body.firstChild) {
    document.body.removeChild(document.body.firstChild);
  }
  jest.clearAllMocks();
});

describe("c-aXF_LWC_sourceDiscovery", () => {
  it("shows a spinner before the status wire resolves", () => {
    const el = build();
    expect(el.shadowRoot.querySelector("lightning-spinner")).not.toBeNull();
  });

  it("wizard mode: no spinner, shows the Item ID form and the empty-list note", async () => {
    const el = createElement("c-a-x-f_-l-w-c_source-discovery", { is: Disc });
    document.body.appendChild(el);
    getConnections.emit([]);
    await flush();
    expect(el.shadowRoot.querySelector("lightning-spinner")).toBeNull();
    expect(el.shadowRoot.querySelector("lightning-input")).not.toBeNull();
    expect(el.shadowRoot.textContent).toMatch(/Nenhuma conexão cadastrada/i);
  });

  it("wizard mode: registers an Item ID and lists the connection", async () => {
    registerConnection.mockResolvedValue({
      connectionId: "a01000000000009",
      institution: "Banco X",
      created: true,
      message: "Conexão registrada."
    });
    const el = createElement("c-a-x-f_-l-w-c_source-discovery", { is: Disc });
    document.body.appendChild(el);
    getConnections.emit([]);
    await flush();

    const input = el.shadowRoot.querySelector("lightning-input");
    input.value = "abc123def456";
    input.dispatchEvent(new CustomEvent("change"));
    await flush();

    button(el, /Registrar conexão/).click();
    await flush();
    await flush();
    expect(registerConnection).toHaveBeenCalledWith({
      pluggyItemId: "abc123def456"
    });

    getConnections.emit([
      {
        connectionId: "a01000000000009",
        institution: "Banco X",
        itemIdHint: "…def456",
        consentState: "ACTIVE",
        runState: null,
        accountsFound: 0,
        cardsFound: 0,
        discovered: false
      }
    ]);
    await flush();
    expect(el.shadowRoot.textContent).toMatch(/Banco X/);
    expect(button(el, /Descobrir agora/)).toBeDefined();
  });

  it("wizard mode: 'Descobrir agora' runs discovery for every connection", async () => {
    startDiscovery.mockResolvedValue({
      state: "SUCCEEDED",
      complete: true,
      accountsFound: 1,
      cardsFound: 0
    });
    const el = createElement("c-a-x-f_-l-w-c_source-discovery", { is: Disc });
    document.body.appendChild(el);
    getConnections.emit([
      {
        connectionId: "c1",
        institution: "Banco A",
        itemIdHint: "…1",
        consentState: "ACTIVE"
      },
      {
        connectionId: "c2",
        institution: "Banco B",
        itemIdHint: "…2",
        consentState: "ACTIVE"
      }
    ]);
    await flush();

    button(el, /Descobrir agora/).click();
    await flush();
    await flush();
    await flush();

    expect(startDiscovery).toHaveBeenCalledWith({ connectionId: "c1" });
    expect(startDiscovery).toHaveBeenCalledWith({ connectionId: "c2" });
  });

  it("offers 'Descobrir agora' and explains no history / no holder", async () => {
    const el = build();
    getStatus.emit({ state: null, complete: false });
    getDiscovered.emit([]);
    await flush();
    expect(button(el, /Descobrir agora/)).toBeDefined();
    expect(el.shadowRoot.textContent).toMatch(/Não importa o histórico/i);
  });

  it("shows the 'none found' message when discovery completes with zero sources", async () => {
    const el = build();
    getStatus.emit({
      state: "SUCCEEDED",
      complete: true,
      accountsFound: 0,
      cardsFound: 0,
      message: "Nenhuma conta ou cartão encontrado nas conexões informadas."
    });
    getDiscovered.emit([]);
    await flush();
    expect(el.shadowRoot.textContent).toMatch(/Nenhuma conta ou cartão/i);
  });

  it("lists discovered sources with custody status (AC3/AC7)", async () => {
    const el = build();
    getStatus.emit({
      state: "SUCCEEDED",
      complete: true,
      accountsFound: 1,
      cardsFound: 1
    });
    getDiscovered.emit([
      {
        recordId: "b1",
        kind: "BANK",
        institution: "Banco X",
        currencyIsoCode: "BRL",
        availability: "CUSTODY"
      },
      {
        recordId: "c1",
        kind: "CARD",
        institution: "Banco X",
        currencyIsoCode: "BRL",
        availability: "CUSTODY"
      }
    ]);
    await flush();

    const rows = el.shadowRoot.querySelectorAll("tbody tr");
    expect(rows).toHaveLength(2);
    expect(el.shadowRoot.textContent).toMatch(/Em custódia/i);
  });

  it("flags an incomplete run as not the full catalogue (AC5)", async () => {
    const el = build();
    getStatus.emit({ state: "FAILED_RETRYABLE", complete: false });
    getDiscovered.emit([]);
    await flush();
    expect(el.shadowRoot.querySelector("[role='note']").textContent).toMatch(
      /não representa o catálogo completo/i
    );
    expect(button(el, /Continuar descoberta/)).toBeDefined();
  });

  it("runs discovery and surfaces the result message", async () => {
    startDiscovery.mockResolvedValue({
      state: "SUCCEEDED",
      complete: true,
      message: "1 conta(s) e 1 cartão(ões) em custódia."
    });
    const el = build();
    getStatus.emit({ state: null, complete: false });
    getDiscovered.emit([]);
    await flush();

    button(el, /Descobrir agora/).click();
    await flush();
    await flush();
    await flush();

    expect(startDiscovery).toHaveBeenCalledWith({
      connectionId: "a01000000000001"
    });
    expect(
      el.shadowRoot.querySelector(
        "[aria-live='polite'] lightning-formatted-text"
      ).value
    ).toMatch(/custódia/i);
  });

  it("renders an error state with retry when the status wire fails", async () => {
    const el = build();
    getStatus.error();
    await flush();
    expect(el.shadowRoot.querySelector("[role='alert']").textContent).toMatch(
      /Não foi possível carregar/i
    );
  });
});
