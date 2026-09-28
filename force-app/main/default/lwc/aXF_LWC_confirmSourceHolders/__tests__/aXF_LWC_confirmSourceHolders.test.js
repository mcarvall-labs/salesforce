import { createElement } from "lwc";
import Cmp from "c/aXF_LWC_confirmSourceHolders";
import getOverview from "@salesforce/apex/AXF_CLS_CTRL_SourceHolderConfirmation.getOverview";
import confirmHolder from "@salesforce/apex/AXF_CLS_CTRL_SourceHolderConfirmation.confirmHolder";
import { refreshApex } from "@salesforce/apex";

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

  it("shows a real error state with retry when the overview fails", async () => {
    const el = build();
    getOverview.error();
    await flush();
    expect(el.shadowRoot.querySelector("[role='alert']").textContent).toMatch(
      /Não foi possível carregar|Could not load/i
    );
    expect(el.shadowRoot.querySelector("lightning-spinner")).toBeNull();
  });

  it("shows an empty state when nothing was discovered yet", async () => {
    const el = build();
    getOverview.emit({
      forbidden: false,
      pending: [],
      released: [],
      divergent: []
    });
    await flush();
    expect(el.shadowRoot.textContent).toMatch(
      /Nenhuma fonte descoberta|No source discovered/i
    );
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
    ).toBe(2);
    expect(el.shadowRoot.textContent).toMatch(/Banco X/);
    expect(el.shadowRoot.textContent).toMatch(/1/);
  });

  it("pre-selects the picker from the connection's suggested holder and confirms with one button", async () => {
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
          version: 3,
          suggestedHolderId: "001sugg"
        }
      ],
      released: []
    });
    await flush();

    // Pre-filled from the connection's already-linked sibling — no manual pick needed.
    expect(el.shadowRoot.querySelector("lightning-record-picker").value).toBe(
      "001sugg"
    );

    const confirmBtn = el.shadowRoot.querySelector("lightning-button");
    confirmBtn.click();
    await flush();

    expect(confirmHolder).toHaveBeenCalledTimes(1);
    expect(confirmHolder.mock.calls[0][0]).toEqual({
      sourceId: "a01",
      kind: "BANK",
      holderId: "001sugg",
      expectedVersion: 3
    });
  });

  it("requires at least one holder before confirming when nothing is suggested", async () => {
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

    const confirmBtn = el.shadowRoot.querySelector("lightning-button");
    confirmBtn.click();
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
    confirmBtn.click();
    await flush();

    expect(confirmHolder).toHaveBeenCalledTimes(1);
    expect(confirmHolder.mock.calls[0][0]).toEqual({
      sourceId: "a01",
      kind: "BANK",
      holderId: "001x",
      expectedVersion: 3
    });
  });

  it("lists released sources pre-filled with their current holder and corrects it", async () => {
    confirmHolder.mockResolvedValue({
      outcome: "CORRECTED",
      message: "Titular corrigido."
    });
    const el = build();
    getOverview.emit({
      forbidden: false,
      pending: [],
      released: [
        {
          sourceId: "a02",
          kind: "CARD",
          institutionName: "Cartão X",
          maskedNumber: "7788",
          currencyIsoCode: "BRL",
          holderId: "001old",
          holderName: "Ana Souza",
          suggestedHolderId: "001old",
          version: 1
        }
      ],
      divergent: []
    });
    await flush();

    expect(el.shadowRoot.textContent).toMatch(/Ana Souza/);
    const picker = el.shadowRoot.querySelector("lightning-record-picker");
    expect(picker.value).toBe("001old");

    const confirmBtn = el.shadowRoot.querySelector("lightning-button");
    // Unchanged from the current holder: a no-op, nothing to submit.
    confirmBtn.click();
    await flush();
    expect(confirmHolder).not.toHaveBeenCalled();

    picker.dispatchEvent(
      new CustomEvent("change", { detail: { recordId: "001new" } })
    );
    await flush();
    confirmBtn.click();
    await flush();
    await flush();
    await flush();

    expect(confirmHolder).toHaveBeenCalledTimes(1);
    expect(confirmHolder.mock.calls[0][0]).toEqual({
      sourceId: "a02",
      kind: "CARD",
      holderId: "001new",
      expectedVersion: 1
    });
    expect(el.shadowRoot.querySelector("[data-status]").textContent).toMatch(
      /confirmado|confirmed/i
    );
  });

  it("flags a source whose holder diverges from the connection", async () => {
    const el = build();
    getOverview.emit({
      forbidden: false,
      pending: [],
      released: [
        {
          sourceId: "a02",
          kind: "BANK",
          institutionName: "Banco X",
          holderId: "001old",
          holderName: "Ana Souza",
          version: 1,
          divergent: true
        }
      ],
      divergent: [
        {
          sourceId: "a02",
          kind: "BANK",
          institutionName: "Banco X",
          holderId: "001old",
          holderName: "Ana Souza",
          version: 1,
          divergent: true
        }
      ]
    });
    await flush();
    expect(el.shadowRoot.textContent).toMatch(
      /Divergente do titular da conexão|Diverges from the connection holder/
    );
  });

  it("re-calls the overview wire when the administrator retries", async () => {
    const el = build();
    getOverview.error();
    await flush();
    const retry = el.shadowRoot.querySelector("lightning-button");
    expect(retry).not.toBeNull();

    retry.click();
    await flush();

    // Retry is a real server re-read: the wire is refreshed, never a replayed cached
    // imperative answer.
    expect(refreshApex).toHaveBeenCalledTimes(1);

    getOverview.emit({
      forbidden: false,
      pending: [],
      released: [],
      divergent: []
    });
    await flush();
    expect(el.shadowRoot.querySelector("[role='alert']")).toBeNull();
    expect(el.shadowRoot.textContent).toMatch(
      /Nenhuma fonte descoberta|No source discovered/i
    );
  });

  it("disables the confirm button while the batch confirmation is in flight", async () => {
    let resolveConfirm;
    confirmHolder.mockImplementation(
      () =>
        new Promise((resolve) => {
          resolveConfirm = resolve;
        })
    );
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
          version: 0,
          suggestedHolderId: "001x"
        }
      ],
      released: [],
      divergent: []
    });
    await flush();

    const confirmButton = () => el.shadowRoot.querySelector("lightning-button");
    expect(confirmButton().disabled).toBeFalsy();

    confirmButton().click();
    await flush();

    // A double submit cannot happen: the button is disabled while the batch is in flight.
    expect(confirmButton().disabled).toBe(true);
    expect(confirmHolder).toHaveBeenCalledTimes(1);

    resolveConfirm({ outcome: "CONFIRMED", message: "Titular confirmado." });
    await flush();
    await flush();

    // ...and it clears once the batch settles, without waiting for a new wire payload.
    expect(confirmButton().disabled).toBeFalsy();
  });
});
