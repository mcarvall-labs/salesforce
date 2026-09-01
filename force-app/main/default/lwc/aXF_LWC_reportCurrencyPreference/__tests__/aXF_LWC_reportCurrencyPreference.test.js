import { createElement } from "lwc";
import Pref from "c/aXF_LWC_reportCurrencyPreference";
import getState from "@salesforce/apex/AXF_CLS_CTRL_ReportCurrencyPref.getState";
import setPreference from "@salesforce/apex/AXF_CLS_CTRL_ReportCurrencyPref.setPreference";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ReportCurrencyPref.getState",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ReportCurrencyPref.setPreference",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const STATE = {
  options: [
    { isoCode: "BRL", label: "Real", suggestedDefault: true },
    { isoCode: "USD", label: "Dolar", suggestedDefault: false }
  ],
  currentIsoCode: null,
  hasPersonalPreference: false,
  suggestedIsoCode: "BRL"
};

const flush = () => Promise.resolve();
const combobox = (el) => el.shadowRoot.querySelector("lightning-combobox");
const button = (el, label) =>
  [...el.shadowRoot.querySelectorAll("lightning-button")].find(
    (b) => b.label === label
  );

function build() {
  const el = createElement("c-a-x-f_-l-w-c_report-currency-preference", {
    is: Pref
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

describe("c-aXF_LWC_reportCurrencyPreference", () => {
  it("shows a spinner before the wire resolves", () => {
    const el = build();
    expect(el.shadowRoot.querySelector("lightning-spinner")).not.toBeNull();
  });

  it("lists active currencies, marks the suggested one and preselects it", async () => {
    const el = build();
    getState.emit(STATE);
    await flush();

    const opts = combobox(el).options;
    expect(opts).toHaveLength(2);
    expect(opts[0].label).toMatch(/Sugerida/);
    expect(combobox(el).value).toBe("BRL");
  });

  it("explains it is presentation-only", async () => {
    const el = build();
    getState.emit(STATE);
    await flush();
    expect(el.shadowRoot.textContent).toMatch(/Não converte/i);
  });

  it("saves the chosen currency", async () => {
    setPreference.mockResolvedValue({
      applied: true,
      currentIsoCode: "USD",
      message: "Preferência de moeda salva."
    });
    const el = build();
    getState.emit(STATE);
    await flush();

    combobox(el).dispatchEvent(
      new CustomEvent("change", { detail: { value: "USD" } })
    );
    await flush();
    button(el, "Salvar").click();
    await flush();
    await flush();

    expect(setPreference).toHaveBeenCalledWith({
      isoCode: "USD",
      overwriteExisting: false
    });
    expect(
      el.shadowRoot.querySelector(
        "[aria-live='polite'] lightning-formatted-text"
      ).value
    ).toMatch(/salva/i);
  });

  it("asks to confirm when replacing an existing preference", async () => {
    setPreference
      .mockResolvedValueOnce({
        applied: false,
        confirmRequired: true,
        message: "ja existe (BRL)."
      })
      .mockResolvedValueOnce({ applied: true, currentIsoCode: "USD" });
    const el = build();
    getState.emit({
      ...STATE,
      currentIsoCode: "BRL",
      hasPersonalPreference: true
    });
    await flush();

    combobox(el).dispatchEvent(
      new CustomEvent("change", { detail: { value: "USD" } })
    );
    await flush();
    button(el, "Salvar").click();
    await flush();
    await flush();

    expect(el.shadowRoot.querySelector("[role='alertdialog']")).not.toBeNull();

    button(el, "Confirmar troca").click();
    await flush();
    await flush();

    expect(setPreference).toHaveBeenLastCalledWith({
      isoCode: "USD",
      overwriteExisting: true
    });
  });

  it("renders an error state with retry when the wire fails", async () => {
    const el = build();
    getState.error();
    await flush();
    expect(el.shadowRoot.querySelector("[role='alert']").textContent).toMatch(
      /Não foi possível carregar/i
    );
  });
});
