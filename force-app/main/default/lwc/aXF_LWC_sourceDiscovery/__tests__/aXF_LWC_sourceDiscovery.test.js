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
