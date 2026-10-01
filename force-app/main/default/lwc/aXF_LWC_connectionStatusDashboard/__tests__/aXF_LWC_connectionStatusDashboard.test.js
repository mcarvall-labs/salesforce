import { createElement } from "lwc";
import AXF_LWC_connectionStatusDashboard from "c/aXF_LWC_connectionStatusDashboard";
import getDashboard from "@salesforce/apex/AXF_CLS_CTRL_ConnectionDashboard.getDashboard";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ConnectionDashboard.getDashboard",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
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
});
