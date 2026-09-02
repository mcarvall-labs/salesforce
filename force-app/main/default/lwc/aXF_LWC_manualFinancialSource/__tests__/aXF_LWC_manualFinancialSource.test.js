import { createElement } from "lwc";
import ManualSource from "c/aXF_LWC_manualFinancialSource";
import save from "@salesforce/apex/AXF_CLS_CTRL_ManualFinancialSource.save";
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ManualFinancialSource.save",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
const flush = () => Promise.resolve();
const build = () => {
  const element = createElement("c-manual", { is: ManualSource });
  document.body.appendChild(element);
  element.shadowRoot
    .querySelectorAll(
      "lightning-input, lightning-combobox, lightning-record-picker"
    )
    .forEach((field) => {
      field.checkValidity = jest.fn(() => true);
      field.reportValidity = jest.fn();
    });
  return element;
};
describe("c-a-x-f_-l-w-c_manual-financial-source", () => {
  beforeEach(() => {
    Object.defineProperty(globalThis, "crypto", {
      configurable: true,
      value: {
        randomUUID: jest.fn(() => "123e4567-e89b-42d3-a456-426614174000")
      }
    });
  });
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.restoreAllMocks();
    jest.clearAllMocks();
  });
  it("renders accessible bilingual labels", () => {
    const el = createElement("c-manual", { is: ManualSource });
    el.locale = "en";
    document.body.appendChild(el);
    expect(el.shadowRoot.querySelector("lightning-card").title).toBe(
      "Manual financial source"
    );
  });
  it("emits skip without creating a source", () => {
    const el = createElement("c-manual", { is: ManualSource });
    el.allowSkip = true;
    document.body.appendChild(el);
    const listener = jest.fn();
    el.addEventListener("skip", listener);
    el.shadowRoot.querySelectorAll("lightning-button")[1].click();
    expect(listener).toHaveBeenCalled();
    expect(save).not.toHaveBeenCalled();
  });
  it("reuses one UUID after transport failure and emits only on success", async () => {
    save.mockRejectedValueOnce(new Error("network")).mockResolvedValueOnce({
      outcome: "CREATED",
      sourceId: "a01",
      version: 1
    });
    const element = build();
    const listener = jest.fn();
    element.addEventListener("sourcesaved", listener);
    element.shadowRoot.querySelector("lightning-button").click();
    await flush();
    await flush();
    element.shadowRoot.querySelector("lightning-button").click();
    await flush();
    await flush();
    expect(save).toHaveBeenCalledTimes(2);
    expect(crypto.randomUUID).toHaveBeenCalledTimes(1);
    expect(save.mock.calls[0][0].input.manualKey).toBe(
      save.mock.calls[1][0].input.manualKey
    );
    expect(save.mock.calls[0][0].input).toMatchObject({
      kind: "BANK",
      currencyIsoCode: "BRL",
      sourceId: undefined,
      expectedVersion: undefined
    });
    expect(element.sourceId).toBe("a01");
    expect(element.expectedVersion).toBe(1);
    expect(listener).toHaveBeenCalledTimes(1);
    expect(element.shadowRoot.querySelector("lightning-spinner")).toBeNull();
    expect(
      element.shadowRoot.querySelector("[data-message]").textContent
    ).toContain("Fonte financeira criada.");
  });
  it("preserves edit state and emits no event for conflict", async () => {
    save.mockResolvedValue({
      outcome: "CONFLICT",
      sourceId: "other",
      version: 99
    });
    const element = build();
    element.sourceId = "a01existing";
    element.expectedVersion = 4;
    const listener = jest.fn();
    element.addEventListener("sourcesaved", listener);
    element.shadowRoot.querySelector("lightning-button").click();
    await flush();
    await flush();
    expect(listener).not.toHaveBeenCalled();
    expect(element.sourceId).toBe("a01existing");
    expect(element.expectedVersion).toBe(4);
  });
  it("stops client-invalid input before Apex", () => {
    const element = build();
    const field = element.shadowRoot.querySelector("lightning-input");
    field.checkValidity.mockReturnValue(false);
    element.shadowRoot.querySelector("lightning-button").click();
    expect(save).not.toHaveBeenCalled();
  });
});
