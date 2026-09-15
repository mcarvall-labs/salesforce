import { createElement } from "lwc";
import ConfidencePanel, { parseFailure } from "c/aXF_LWC_confidencePanel";
import getHolders from "@salesforce/apex/AXF_CLS_CTRL_ConfidencePanel.getHolders";
import explain from "@salesforce/apex/AXF_CLS_CTRL_ConfidencePanel.explain";
import { __navigate } from "lightning/navigation";

jest.mock(
  "lightning/navigation",
  () => {
    const navigate = jest.fn();
    const Navigate = Symbol("Navigate");
    const NavigationMixin = (Base) =>
      class extends Base {
        [Navigate](pageReference) {
          navigate(pageReference);
        }
      };
    NavigationMixin.Navigate = Navigate;
    return { NavigationMixin, __navigate: navigate };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ConfidencePanel.getHolders",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ConfidencePanel.explain",
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
  { accountId: "001A", name: "Ana" },
  { accountId: "001B", name: "Empresa B" }
];

const panel = {
  policyVersion: "confidence-panel@1.0.0",
  asOf: "2026-09-14T12:00:00.000Z",
  level: "DEGRADED",
  reasons: ["STALE_SOURCE", "FRESHNESS_EXCEEDED"],
  allowedActions: ["OPEN_SOURCE", "REVIEW_SOURCE_HEALTH"],
  currencies: ["BRL", "USD"],
  includedCount: 2,
  excludedCount: 1,
  exclusions: [{ accountId: "001Z", reason: "NOT_AUTHORIZED", count: 1 }],
  sources: [
    {
      sourceId: "a07C",
      kind: "BANK",
      label: "Banco c ****c",
      holderId: "001A",
      holderName: "Ana",
      origin: "PLUGGY",
      currencyIso: "BRL",
      lastSuccessAt: "2026-09-14T10:00:00.000Z",
      freshnessLimitHours: 48,
      freshness: "CURRENT",
      included: true,
      factCount: 0,
      navigable: true,
      exceptions: []
    },
    {
      sourceId: "a07S",
      kind: "BANK",
      label: "Banco s ****s",
      holderId: "001A",
      holderName: "Ana",
      origin: "PLUGGY",
      currencyIso: "USD",
      lastSuccessAt: "2026-09-13T06:00:00.000Z",
      freshnessLimitHours: 24,
      freshness: "STALE",
      included: true,
      factCount: 12,
      navigable: true,
      exceptions: ["FRESHNESS_EXCEEDED"]
    },
    {
      sourceId: "a07K",
      kind: "BANK",
      label: "Banco k ****k",
      holderId: "001A",
      holderName: "Ana",
      origin: "MANUAL",
      currencyIso: "BRL",
      lastSuccessAt: null,
      freshnessLimitHours: 48,
      freshness: "UNKNOWN",
      included: false,
      exclusionReason: "CUSTODY",
      factCount: 3,
      navigable: false,
      exceptions: []
    }
  ]
};

function build(recordId) {
  const element = createElement("c-a-x-f_-l-w-c_confidence-panel", {
    is: ConfidencePanel
  });
  if (recordId) {
    element.recordId = recordId;
  }
  document.body.appendChild(element);
  return element;
}

describe("c-aXF_LWC_confidencePanel", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("renders the server level, stale sources as not current, exclusions and actions", async () => {
    explain.mockResolvedValue(panel);
    const element = build();
    getHolders.emit(holders);
    await flush();
    expect(
      element.shadowRoot.querySelector('[data-id="empty"]')
    ).not.toBeNull();
    const scope = element.shadowRoot.querySelector('[data-id="scope"]');
    scope.dispatchEvent(
      new CustomEvent("change", { detail: { value: ["001A"] } })
    );
    await flush();
    element.shadowRoot.querySelector('[data-id="explain"]').click();
    await flush();
    expect(explain).toHaveBeenCalledWith({ accountIds: ["001A"] });
    const level = element.shadowRoot.querySelector('[data-id="level"]');
    expect(level.className).toContain("slds-badge_warning");
    const rows = element.shadowRoot.querySelectorAll(
      '[data-id="sources"] tbody tr'
    );
    expect(rows.length).toBe(3);
    const stale = element.shadowRoot.querySelector(
      '[data-source="a07S"] [data-freshness]'
    );
    expect(stale.dataset.freshness).toBe("STALE");
    expect(stale.className).toContain("slds-badge_warning");
    expect(stale.className).not.toContain("slds-badge_success");
    expect(
      element.shadowRoot.querySelector('[data-source="a07C"] [data-freshness]')
        .dataset.freshness
    ).toBe("CURRENT");
    expect(
      element.shadowRoot.querySelectorAll('[data-id="exclusions"] li').length
    ).toBe(1);
    expect(
      element.shadowRoot.querySelectorAll('[data-id="exceptions"] li').length
    ).toBe(1);
    expect(
      element.shadowRoot.querySelectorAll('[data-id="actions"] li').length
    ).toBe(2);
    expect(
      element.shadowRoot.querySelector('[data-id="fx"]').textContent
    ).toContain("fxMulti");
    expect(
      element.shadowRoot.querySelector('[data-id="announcer"]').textContent
    ).not.toBe("");
  });

  it("navigates to a source only when it is navigable", async () => {
    explain.mockResolvedValue(panel);
    const element = build("001A");
    getHolders.emit(holders);
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="scope"]')).toBeNull();
    expect(explain).toHaveBeenCalledWith({ accountIds: ["001A"] });
    const buttons = element.shadowRoot.querySelectorAll('[data-id="open"]');
    expect(buttons.length).toBe(2);
    expect(
      element.shadowRoot.querySelector('[data-source="a07K"] [data-id="open"]')
    ).toBeNull();
    buttons[1].click();
    await flush();
    expect(__navigate).toHaveBeenCalledTimes(1);
    const pageReference = __navigate.mock.calls[0][0];
    expect(pageReference.type).toBe("standard__recordPage");
    expect(pageReference.attributes.recordId).toBe("a07S");
  });

  it("shows blocked reasons and sanitized failures", async () => {
    explain.mockResolvedValueOnce({
      ...panel,
      level: "BLOCKED",
      reasons: ["NO_AUTHORIZED_SCOPE", "FIELD_ACCESS:AXF_BAT_NUM_Magnitude__c"],
      allowedActions: [],
      sources: [],
      exclusions: [],
      currencies: []
    });
    const element = build("001A");
    getHolders.emit(holders);
    await flush();
    expect(
      element.shadowRoot.querySelector('[data-id="level"]').className
    ).toContain("slds-badge_error");
    expect(
      element.shadowRoot.querySelectorAll('[data-id="blocked-reasons"] li')
        .length
    ).toBe(2);
    expect(
      element.shadowRoot.querySelectorAll('[data-id="actions"] li').length
    ).toBe(1);
    explain.mockRejectedValueOnce({ body: { message: "FORBIDDEN" } });
    element.shadowRoot.querySelector('[data-id="explain"]');
    await element.handleRetry?.();
    expect(parseFailure({ body: { message: "FORBIDDEN" } })).not.toBe(
      parseFailure({})
    );
    expect(parseFailure({ body: { message: "boom" } })).toBe(parseFailure({}));
  });
});
