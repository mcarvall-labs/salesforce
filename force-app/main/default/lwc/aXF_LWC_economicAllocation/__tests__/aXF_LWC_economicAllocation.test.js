import { createElement } from "lwc";
import EconomicAllocation, { parseFailure } from "c/aXF_LWC_economicAllocation";
import getContext from "@salesforce/apex/AXF_CLS_CTRL_EconomicAllocation.getContext";
import propose from "@salesforce/apex/AXF_CLS_CTRL_EconomicAllocation.propose";
import confirm from "@salesforce/apex/AXF_CLS_CTRL_EconomicAllocation.confirm";
import discard from "@salesforce/apex/AXF_CLS_CTRL_EconomicAllocation.discard";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_EconomicAllocation.getContext",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_EconomicAllocation.propose",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_EconomicAllocation.confirm",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_EconomicAllocation.discard",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = async () => {
  for (let i = 0; i < 6; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};

const holders = [
  { accountId: "001A", label: "Ana" },
  { accountId: "001B", label: "Empresa B" }
];
const draft = {
  setId: "eas1",
  name: "EAS-000001",
  factKind: "BANK",
  factId: "a0X1",
  factName: "BAT-1",
  holderAccountName: "Ana",
  revision: 1,
  state: "DRAFT",
  factMagnitude: 300,
  currencyIso: "BRL",
  totalPercent: 100,
  version: 1,
  shares: [
    {
      allocationId: "ea1",
      accountId: "001A",
      accountName: "Ana",
      percent: 70,
      magnitude: 210,
      currencyIso: "BRL"
    },
    {
      allocationId: "ea2",
      accountId: "001B",
      accountName: "Empresa B",
      percent: 30,
      magnitude: 90,
      currencyIso: "BRL"
    }
  ]
};

function build() {
  const element = createElement("c-a-x-f_-l-w-c_economic-allocation", {
    is: EconomicAllocation
  });
  element.recordId = "a0X1";
  document.body.appendChild(element);
  return element;
}

describe("c-aXF_LWC_economicAllocation", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("proposes shares with a running total and sends only account and percent", async () => {
    getContext
      .mockResolvedValueOnce({
        canAllocate: true,
        factKind: "BANK",
        holders,
        sets: []
      })
      .mockResolvedValue({
        canAllocate: true,
        factKind: "BANK",
        holders,
        sets: [draft]
      });
    propose.mockResolvedValue(draft);
    const element = build();
    await flush();
    expect(
      element.shadowRoot.querySelector('[data-id="no-sets"]')
    ).not.toBeNull();
    element.shadowRoot.querySelector('[data-id="add"]').click();
    await flush();
    element.shadowRoot.querySelector('[data-id="add"]').click();
    await flush();
    const combos = element.shadowRoot.querySelectorAll("lightning-combobox");
    combos[0].dispatchEvent(
      new CustomEvent("change", { detail: { value: "001A" } })
    );
    combos[1].dispatchEvent(
      new CustomEvent("change", { detail: { value: "001B" } })
    );
    const inputs = element.shadowRoot.querySelectorAll(
      'lightning-input[data-field="percent"]'
    );
    inputs[0].value = "70";
    inputs[0].dispatchEvent(new CustomEvent("change"));
    inputs[1].value = "30";
    inputs[1].dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(
      element.shadowRoot.querySelector('[data-id="total"]').textContent
    ).toBe("100.00%");
    element.shadowRoot.querySelector('[data-id="propose"]').click();
    await flush();
    const request = JSON.parse(propose.mock.calls[0][0].request);
    expect(request.factKind).toBe("BANK");
    expect(request.factId).toBe("a0X1");
    expect(request.shares).toEqual([
      { accountId: "001A", percent: 70 },
      { accountId: "001B", percent: 30 }
    ]);
    expect(request.operationKey).toMatch(/^[0-9a-f-]{36}$/);
    expect(
      element.shadowRoot.querySelector('[data-id="success"]')
    ).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="eas1"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="propose"]')).toBeNull();
  });

  it("confirms a draft only after the confirmation dialog and passes the expected version", async () => {
    getContext.mockResolvedValue({
      canAllocate: true,
      factKind: "BANK",
      holders,
      sets: [draft]
    });
    confirm.mockResolvedValue({ ...draft, state: "CONFIRMED", version: 2 });
    const element = build();
    await flush();
    [...element.shadowRoot.querySelectorAll("lightning-button")]
      .find((button) => button.dataset.id === "eas1")
      .click();
    await flush();
    expect(confirm).not.toHaveBeenCalled();
    expect(
      element.shadowRoot
        .querySelector('[data-id="confirmation"]')
        .getAttribute("role")
    ).toBe("dialog");
    element.shadowRoot.querySelector('[data-id="confirm-yes"]').click();
    await flush();
    expect(confirm.mock.calls[0][0]).toMatchObject({
      setId: "eas1",
      expectedVersion: 1
    });
    expect(
      element.shadowRoot.querySelector('[data-id="success"]')
    ).not.toBeNull();
  });

  it("shows sanitized failures with translated reasons", async () => {
    getContext.mockResolvedValue({
      canAllocate: true,
      factKind: "BANK",
      holders,
      sets: [draft]
    });
    confirm.mockRejectedValue({
      body: {
        message: JSON.stringify({
          code: "CONFIRMATION_REJECTED",
          reasons: ["TOTAL_NOT_100:90.000000", "UNAUTHORIZED_ACCOUNT:001Z"]
        })
      }
    });
    const element = build();
    await flush();
    [...element.shadowRoot.querySelectorAll("lightning-button")]
      .find((button) => button.dataset.id === "eas1")
      .click();
    await flush();
    element.shadowRoot.querySelector('[data-id="confirm-yes"]').click();
    await flush();
    const error = element.shadowRoot.querySelector('[data-id="error"]');
    const parsed = parseFailure({
      body: {
        message: JSON.stringify({
          code: "CONFIRMATION_REJECTED",
          reasons: ["TOTAL_NOT_100:90.000000", "UNAUTHORIZED_ACCOUNT:001Z"]
        })
      }
    });
    expect(error.textContent).toContain(parsed.message);
    expect(error.querySelectorAll("li").length).toBe(2);
    expect(parsed.reasons[0]).not.toContain("TOTAL_NOT_100");
    expect(parseFailure({ body: { message: "boom" } }).message).toBe(
      parseFailure({}).message
    );
  });
  it("hides the composer for read-only users, blocks duplicate holders and discards a draft", async () => {
    getContext.mockResolvedValueOnce({
      canAllocate: false,
      factKind: "BANK",
      holders,
      sets: [draft]
    });
    const readOnly = build();
    await flush();
    expect(
      readOnly.shadowRoot.querySelector('[data-id="read-only"]')
    ).not.toBeNull();
    expect(readOnly.shadowRoot.querySelector('[data-id="add"]')).toBeNull();
    expect(
      [...readOnly.shadowRoot.querySelectorAll("lightning-button")].find(
        (button) => button.dataset.id === "eas1"
      )
    ).toBeUndefined();
    document.body.removeChild(readOnly);

    getContext
      .mockResolvedValueOnce({
        canAllocate: true,
        factKind: "BANK",
        holders,
        sets: []
      })
      .mockResolvedValue({
        canAllocate: true,
        factKind: "BANK",
        holders,
        sets: [draft]
      });
    discard.mockResolvedValue({ ...draft, state: "DISCARDED" });
    const element = build();
    await flush();
    element.shadowRoot.querySelector('[data-id="add"]').click();
    await flush();
    element.shadowRoot.querySelector('[data-id="add"]').click();
    await flush();
    const combos = element.shadowRoot.querySelectorAll("lightning-combobox");
    combos[0].dispatchEvent(
      new CustomEvent("change", { detail: { value: "001A" } })
    );
    combos[1].dispatchEvent(
      new CustomEvent("change", { detail: { value: "001A" } })
    );
    const inputs = element.shadowRoot.querySelectorAll(
      'lightning-input[data-field="percent"]'
    );
    inputs[0].value = "50";
    inputs[0].dispatchEvent(new CustomEvent("change"));
    inputs[1].value = "50";
    inputs[1].dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(
      element.shadowRoot.querySelector('[data-id="propose"]').disabled
    ).toBe(true);
    // Escape closes the confirmation dialog; discard closes the draft.
    const cancel = [
      ...element.shadowRoot.querySelectorAll("lightning-button")
    ].find((button) => button.dataset.index === "1");
    cancel.click();
    await flush();
    combos[0].dispatchEvent(
      new CustomEvent("change", { detail: { value: "001B" } })
    );
    await flush();
    expect(
      element.shadowRoot.querySelector('[data-id="propose"]').disabled
    ).toBe(false);
    propose.mockResolvedValue(draft);
    element.shadowRoot.querySelector('[data-id="propose"]').click();
    await flush();
    const confirmButton = [
      ...element.shadowRoot.querySelectorAll("lightning-button")
    ].find((button) => button.dataset.id === "eas1" && !button.dataset.action);
    confirmButton.click();
    await flush();
    const dialog = element.shadowRoot.querySelector('[data-id="confirmation"]');
    dialog.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
    await flush();
    expect(
      element.shadowRoot.querySelector('[data-id="confirmation"]')
    ).toBeNull();
    [...element.shadowRoot.querySelectorAll("lightning-button")]
      .find((button) => button.dataset.action === "discard")
      .click();
    await flush();
    expect(discard).toHaveBeenCalledWith({ setId: "eas1", expectedVersion: 1 });
    expect(
      element.shadowRoot.querySelector('[data-id="success"]')
    ).not.toBeNull();
  });
});
