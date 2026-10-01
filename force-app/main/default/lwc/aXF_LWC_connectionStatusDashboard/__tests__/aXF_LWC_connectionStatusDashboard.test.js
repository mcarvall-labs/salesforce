import { createElement } from "lwc";
import AXF_LWC_connectionStatusDashboard from "c/aXF_LWC_connectionStatusDashboard";
import getDashboard from "@salesforce/apex/AXF_CLS_CTRL_ConnectionDashboard.getDashboard";
import syncConnection from "@salesforce/apex/AXF_CLS_CTRL_ConnectionDashboard.syncConnection";
import { refreshApex } from "@salesforce/apex";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ConnectionDashboard.getDashboard",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ConnectionDashboard.syncConnection",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex",
  () => ({ refreshApex: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);

const flush = () => Promise.resolve();

function setup() {
  const element = createElement("c-a-x-f_-l-w-c_connection-status-dashboard", {
    is: AXF_LWC_connectionStatusDashboard
  });
  document.body.appendChild(element);
  return element;
}

describe("c-a-x-f_-l-w-c_connection-status-dashboard", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("shows counters and the connection table", async () => {
    const element = setup();
    getDashboard.emit({
      active: 2,
      error: 1,
      paused: 0,
      rows: [
        {
          id: "a01",
          holder: "Michel",
          institution: "341 - Itaú Unibanco",
          status: "Error",
          errorMessage: "Falha"
        }
      ]
    });
    await flush();
    expect(
      element.shadowRoot.querySelector('[data-id="active"]').textContent
    ).toBe("2");
    expect(
      element.shadowRoot.querySelector('[data-id="error"]').textContent
    ).toBe("1");
    const table = element.shadowRoot.querySelector("lightning-datatable");
    expect(table.data[0].statusLabel).toBe("Erro");
  });

  it("shows the empty state without connections", async () => {
    const element = setup();
    getDashboard.emit({ active: 0, error: 0, paused: 0, rows: [] });
    await flush();
    expect(element.shadowRoot.querySelector("lightning-datatable")).toBeNull();
    expect(element.shadowRoot.textContent).toContain(
      "Nenhuma conexão cadastrada"
    );
  });

  it("shows an error message when loading fails", async () => {
    const element = setup();
    getDashboard.error();
    await flush();
    expect(element.shadowRoot.querySelector('[role="alert"]')).not.toBeNull();
  });

  it("syncs the chosen connection and refreshes the dashboard", async () => {
    syncConnection.mockResolvedValue({
      success: true,
      message: "Sincronização concluída. 2 contas e 1 cartões."
    });
    const element = setup();
    getDashboard.emit({
      active: 1,
      error: 0,
      paused: 0,
      rows: [{ id: "a01", holder: "Michel", status: "Active" }]
    });
    await flush();
    element.shadowRoot.querySelector("lightning-datatable").dispatchEvent(
      new CustomEvent("rowaction", {
        detail: { action: { name: "sync" }, row: { id: "a01" } }
      })
    );
    await flush();
    await flush();
    expect(syncConnection).toHaveBeenCalledWith({ connectionId: "a01" });
    expect(refreshApex).toHaveBeenCalledTimes(1);
    expect(
      element.shadowRoot.querySelector('[role="status"]').textContent
    ).toContain("Sincronização concluída");
  });

  it("shows an error when the sync call fails", async () => {
    syncConnection.mockRejectedValue(new Error("x"));
    const element = setup();
    getDashboard.emit({
      active: 1,
      error: 0,
      paused: 0,
      rows: [{ id: "a01", holder: "Michel", status: "Active" }]
    });
    await flush();
    element.shadowRoot.querySelector("lightning-datatable").dispatchEvent(
      new CustomEvent("rowaction", {
        detail: { action: { name: "sync" }, row: { id: "a01" } }
      })
    );
    await flush();
    await flush();
    expect(
      element.shadowRoot.querySelector('[role="status"]').textContent
    ).toBe("Não foi possível sincronizar a conexão.");
  });
});
