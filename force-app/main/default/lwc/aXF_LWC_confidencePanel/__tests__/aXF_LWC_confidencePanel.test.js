import { createElement } from "lwc";
import ConfidencePanel from "c/aXF_LWC_confidencePanel";
import { parseFailure } from "../failures";
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
jest.mock(
  "@salesforce/apex",
  () => ({ refreshApex: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/AXF_CanExplainConfidence",
  () => ({ default: true }),
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
  policyAuthority: ["AXF-FORECASTING@1.0.0", "AXF-MATCHING@1.0.0"],
  asOf: "2026-09-14T12:00:00.000Z",
  level: "DEGRADED",
  reasons: ["STALE_SOURCE", "FRESHNESS_EXCEEDED"],
  allowedActions: ["OPEN_SOURCE", "REVIEW_SOURCE_HEALTH"],
  fallbacks: ["FRESHNESS_LIMIT_DEFAULT"],
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
      element.shadowRoot.querySelectorAll('[data-id="gate-reasons"] li').length
    ).toBe(2);
    expect(
      element.shadowRoot.querySelectorAll('[data-id="actions"] li').length
    ).toBe(1);
    expect(parseFailure({ body: { message: "FORBIDDEN" } })).not.toBe(
      parseFailure({})
    );
    expect(parseFailure({ body: { message: "boom" } })).toBe(parseFailure({}));
  });

  it("renders a sanitized error with retry when explain fails and when holders fail", async () => {
    explain.mockRejectedValueOnce({ body: { message: "NOT_ACCESSIBLE" } });
    explain.mockResolvedValueOnce(panel);
    const element = build("001A");
    getHolders.emit(holders);
    await flush();
    const error = element.shadowRoot.querySelector('[data-id="error"]');
    expect(error).not.toBeNull();
    expect(error.textContent).toContain("codeNotAccessible");
    expect(
      element.shadowRoot.querySelector('[data-id="announcer"]').textContent
    ).toContain("codeNotAccessible");
    element.shadowRoot.querySelector('[data-id="retry"]').click();
    await flush();
    expect(explain).toHaveBeenCalledTimes(2);
    expect(element.shadowRoot.querySelector('[data-id="error"]')).toBeNull();
    expect(
      element.shadowRoot.querySelector('[data-id="level"]')
    ).not.toBeNull();

    // Changing the record re-explains the new scope.
    explain.mockResolvedValueOnce({ ...panel, level: "INFORMATIVE" });
    element.recordId = "001B";
    await flush();
    expect(explain).toHaveBeenLastCalledWith({ accountIds: ["001B"] });

    // A failing holder wire shows the same error region and retries the wire.
    const { refreshApex } = require("@salesforce/apex");
    const other = build();
    getHolders.error({ message: "FORBIDDEN" });
    await flush();
    expect(
      other.shadowRoot.querySelector('[data-id="error"]').textContent
    ).toContain("codeForbidden");
    other.shadowRoot.querySelector('[data-id="retry"]').click();
    await flush();
    expect(refreshApex).toHaveBeenCalled();
  });

  it("renders the canonical policy state, authority, coverage and fallbacks without recomputing the gate", async () => {
    explain.mockResolvedValue({
      ...panel,
      level: "INFORMATIVE",
      reasons: [],
      fallbacks: []
    });
    const element = build("001A");
    getHolders.emit(holders);
    await flush();
    const level = element.shadowRoot.querySelector('[data-id="level"]');
    expect(level.textContent).toContain("levelInformative");
    expect(level.className).toContain("slds-badge_success");
    // A stale row must never turn the server state into one derived here.
    expect(
      element.shadowRoot.querySelector('[data-source="a07S"] [data-freshness]')
        .dataset.freshness
    ).toBe("STALE");
    expect(
      element.shadowRoot.querySelector('[data-id="policy"]').textContent
    ).toContain("AXF-FORECASTING@1.0.0");
    const coverage = element.shadowRoot.querySelector(
      '[data-id="coverage"]'
    ).textContent;
    expect(coverage).toMatch(/2 \S*_included · 1 \S*_excluded/);
    expect(
      element.shadowRoot.querySelector('[data-id="gate-reasons"]')
    ).toBeNull();
    expect(
      element.shadowRoot.querySelector('[data-id="fallbacks"]')
    ).toBeNull();
    expect(
      element.shadowRoot.querySelector('[data-id="no-fallbacks"]').textContent
    ).toContain("noFallbacks");
  });

  it("shows the gate reason of the server state and names the fallback applied", async () => {
    explain.mockResolvedValue(panel);
    const element = build("001A");
    getHolders.emit(holders);
    await flush();
    expect(
      element.shadowRoot.querySelectorAll('[data-id="gate-reasons"] li').length
    ).toBe(2);
    const fallbacks = element.shadowRoot.querySelectorAll(
      '[data-id="fallbacks"] li'
    );
    expect(fallbacks.length).toBe(1);
    expect(fallbacks[0].textContent).toContain("fallbackFreshnessLimitDefault");
  });

  it("shows unknown FX and hides the currency when the server has none", async () => {
    explain.mockResolvedValueOnce({
      ...panel,
      currencies: [],
      sources: [{ ...panel.sources[0], currencyIso: null }]
    });
    const element = build("001A");
    getHolders.emit(holders);
    await flush();
    expect(
      element.shadowRoot.querySelector('[data-id="fx"]').textContent
    ).toContain("fxUnknown");
    expect(
      element.shadowRoot.querySelector('[data-source="a07C"] th').textContent
    ).not.toContain("(");
  });
});
