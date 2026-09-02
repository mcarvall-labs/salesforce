import { createElement } from "lwc";
import Cmp from "c/aXF_LWC_confirmSourceHolders";
import getOverview from "@salesforce/apex/AXF_CLS_CTRL_SourceHolderConfirmation.getOverview";
import confirmHolder from "@salesforce/apex/AXF_CLS_CTRL_SourceHolderConfirmation.confirmHolder";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_SourceHolderConfirmation.getOverview",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_SourceHolderConfirmation.confirmHolder",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex",
  () => ({ refreshApex: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);

const flush = () => Promise.resolve();

function build() {
  const el = createElement("c-confirm", { is: Cmp });
  document.body.appendChild(el);
  return el;
}

afterEach(() => {
  while (document.body.firstChild) {
    document.body.removeChild(document.body.firstChild);
  }
  jest.clearAllMocks();
});

describe("c-aXF_LWC_confirmSourceHolders", () => {
  it("shows the forbidden message with no authority", async () => {
    const el = build();
    getOverview.emit({ forbidden: true, pending: [], released: [] });
    await flush();
    expect(el.shadowRoot.textContent).toMatch(/autoriza|authorized/i);
    expect(el.shadowRoot.querySelector("lightning-record-picker")).toBeNull();
  });

  it("lists pending sources and released count", async () => {
    const el = build();
    getOverview.emit({
      forbidden: false,
      pending: [
        {
          sourceId: "a01",
          kind: "BANK",
          institutionName: "Banco X",
          maskedNumber: "****1",
          currencyIsoCode: "BRL",
          version: 0
        }
      ],
      released: [{ sourceId: "a02", kind: "CARD" }]
    });
    await flush();
    expect(
      el.shadowRoot.querySelectorAll("lightning-record-picker").length
    ).toBe(1);
    expect(el.shadowRoot.textContent).toMatch(/Banco X/);
    expect(el.shadowRoot.textContent).toMatch(/1/);
  });

  it("requires a holder before confirming and then calls Apex", async () => {
    confirmHolder.mockResolvedValue({
      outcome: "CONFIRMED",
      message: "Titular confirmado."
    });
    const el = build();
    getOverview.emit({
      forbidden: false,
      pending: [
        {
          sourceId: "a01",
          kind: "BANK",
          institutionName: "Banco X",
          maskedNumber: "1",
          currencyIsoCode: "BRL",
          version: 3
        }
      ],
      released: []
    });
    await flush();

    const btn = el.shadowRoot.querySelector("lightning-button");
    btn.click();
    await flush();
    expect(confirmHolder).not.toHaveBeenCalled();
    expect(el.shadowRoot.querySelector("[data-status]").textContent).toMatch(
      /Selecione|Select/
    );

    el.shadowRoot
      .querySelector("lightning-record-picker")
      .dispatchEvent(
        new CustomEvent("change", { detail: { recordId: "001x" } })
      );
    await flush();
    btn.click();
    await flush();
    await flush();

    expect(confirmHolder).toHaveBeenCalledTimes(1);
    expect(confirmHolder.mock.calls[0][0].input).toEqual({
      sourceId: "a01",
      kind: "BANK",
      holderId: "001x",
      expectedVersion: 3
    });
  });
});
