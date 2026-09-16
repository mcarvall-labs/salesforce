import { createElement } from "lwc";
import SyncHealth from "c/aXF_LWC_pluggySyncHealth";
import health from "@salesforce/apex/AXF_CLS_CTRL_PluggySync.health";
import syncNow from "@salesforce/apex/AXF_CLS_CTRL_PluggySync.syncNow";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_PluggySync.health",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_PluggySync.syncNow",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock("@salesforce/i18n/lang", () => ({ default: "pt-BR" }), {
  virtual: true
});

function mount() {
  const el = createElement("c-a-x-f_-l-w-c_pluggy-sync-health", {
    is: SyncHealth
  });
  el.connectionId = "a00000000000001";
  document.body.appendChild(el);
  return el;
}

const flush = () => Promise.resolve();

afterEach(() => {
  while (document.body.firstChild) {
    document.body.removeChild(document.body.firstChild);
  }
  jest.clearAllMocks();
});

describe("aXF_LWC_pluggySyncHealth", () => {
  it("renders one row per scope with a translated state", async () => {
    const el = mount();
    health.emit([
      {
        pluggyAccountId: "acc-999888",
        kind: "BANK",
        state: "SUCCEEDED",
        attempts: 0,
        completeThrough: "2026-09-04T23:59:59.000Z",
        lastSuccessAt: "2026-09-05T03:00:00.000Z",
        recordsWritten: 12,
        cause: "12 lancamento(s)",
        nextAction: "Nenhuma acao necessaria."
      }
    ]);
    await flush();
    await flush();

    const items = el.shadowRoot.querySelectorAll("li.slds-item");
    expect(items.length).toBe(1);
    expect(el.shadowRoot.textContent).toContain("Concluída");
    expect(el.shadowRoot.textContent).toContain("····9888");
  });

  it("shows the empty state when no scope has a holder", async () => {
    const el = mount();
    health.emit([]);
    await flush();
    await flush();
    expect(el.shadowRoot.textContent).toContain(
      "Nenhuma conta ou cartão com titular confirmado"
    );
  });

  it("'Sincronizar agora' calls syncNow and shows the returned message", async () => {
    syncNow.mockResolvedValue("2 escopo(s) em sincronizacao.");
    const el = mount();
    health.emit([]);
    await flush();

    const btn = [...el.shadowRoot.querySelectorAll("lightning-button")].find(
      (b) => /sincronizar/i.test(b.label)
    );
    btn.click();
    await flush();
    await flush();
    await flush();
    await flush();

    expect(syncNow).toHaveBeenCalledWith({ connectionId: "a00000000000001" });
    const fb = el.shadowRoot.querySelector("lightning-formatted-text");
    expect(fb.value).toBe("2 escopo(s) em sincronizacao.");
  });

  it("surfaces a load error with a retry", async () => {
    const el = mount();
    health.error();
    await flush();
    await flush();
    expect(el.shadowRoot.textContent).toContain(
      "Não foi possível carregar o estado da sincronização"
    );
  });
});
