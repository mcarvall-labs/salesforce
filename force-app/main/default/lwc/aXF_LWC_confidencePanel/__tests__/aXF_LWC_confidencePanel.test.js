import { createElement } from "lwc";
import ConfidencePanel from "c/aXF_LWC_confidencePanel";
import { parseFailure } from "../failures";
import getHolders from "@salesforce/apex/AXF_CLS_CTRL_ConfidencePanel.getHolders";
import explain from "@salesforce/apex/AXF_CLS_CTRL_ConfidencePanel.explain";
import { subscribe, unsubscribe } from "lightning/messageService";
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
  gatePolicy: "AXF-FORECASTING@1.0.0",
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

  it("renders the canonical state, its declaring policy, coverage and fallbacks without recomputing the gate", async () => {
    // Reachable DEGRADED payload whose included rows all look current: what degrades the panel is
    // the excluded holder, so a client deriving the state from the rows would show INFORMATIVE.
    explain.mockResolvedValue({
      ...panel,
      level: "DEGRADED",
      reasons: ["HOLDER_NOT_AUTHORIZED"],
      fallbacks: [],
      includedCount: 3,
      excludedCount: 0,
      sources: [
        { ...panel.sources[0], factCount: 0 },
        {
          ...panel.sources[1],
          freshness: "CURRENT",
          lastSuccessAt: "2026-09-14T11:00:00.000Z",
          factCount: 5,
          exceptions: []
        },
        {
          ...panel.sources[2],
          included: true,
          exclusionReason: undefined,
          freshness: "CURRENT",
          lastSuccessAt: "2026-09-14T11:30:00.000Z",
          factCount: 3,
          navigable: true
        }
      ]
    });
    const element = build("001A");
    getHolders.emit(holders);
    await flush();
    const level = element.shadowRoot.querySelector('[data-id="level"]');
    expect(level.textContent).toContain("levelDegraded");
    expect(level.className).toContain("slds-badge_warning");
    // Every rendered row is current, and the state is still the server's degraded one.
    const rows = element.shadowRoot.querySelectorAll("[data-freshness]");
    expect(rows.length).toBe(3);
    rows.forEach((row) => expect(row.dataset.freshness).toBe("CURRENT"));
    expect(
      element.shadowRoot.querySelector('[data-id="policy"]').textContent
    ).toContain("AXF-FORECASTING@1.0.0");
    // The matching policy declares other states and never enters this panel.
    expect(
      element.shadowRoot.querySelector('[data-id="policy"]').textContent
    ).not.toContain("AXF-MATCHING");
    const coverage = element.shadowRoot.querySelector(
      '[data-id="coverage"]'
    ).textContent;
    expect(coverage).toMatch(/3 \S*_included · 0 \S*_excluded/);
    expect(
      element.shadowRoot.querySelectorAll('[data-id="gate-reasons"] li').length
    ).toBe(1);
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

  it("names the IMPORT_DATE_MISSING fallback and exception instead of the internal code", async () => {
    // Reachable payload: one manual source without its own freshness limit whose hand-keyed facts
    // carry no import timestamp, so both fallbacks and the row exception are reported together.
    explain.mockResolvedValue({
      ...panel,
      level: "DEGRADED",
      reasons: ["IMPORT_DATE_MISSING"],
      fallbacks: ["FRESHNESS_LIMIT_DEFAULT", "IMPORT_DATE_MISSING"],
      exclusions: [],
      includedCount: 1,
      excludedCount: 0,
      currencies: ["BRL"],
      sources: [
        {
          ...panel.sources[0],
          origin: "MANUAL",
          freshness: "CURRENT",
          lastSuccessAt: "2026-09-14T11:00:00.000Z",
          factCount: 4,
          exceptions: ["IMPORT_DATE_MISSING"]
        }
      ]
    });
    const element = build("001A");
    getHolders.emit(holders);
    await flush();
    const fallbacks = element.shadowRoot.querySelectorAll(
      '[data-id="fallbacks"] li'
    );
    expect(fallbacks.length).toBe(2);
    expect(fallbacks[0].textContent).toContain("fallbackFreshnessLimitDefault");
    expect(fallbacks[1].textContent).toContain("exImportDateMissing");
    expect(fallbacks[1].textContent).not.toContain("IMPORT_DATE_MISSING");
    const exception = element.shadowRoot.querySelector(
      '[data-id="exceptions"] li'
    );
    expect(exception.textContent).toContain("exImportDateMissing");
    expect(exception.textContent).not.toContain("IMPORT_DATE_MISSING");
  });

  it("asserts no derivation it cannot know: no fallback claim on a blocked or older payload", async () => {
    explain.mockResolvedValue({
      ...panel,
      level: "BLOCKED",
      reasons: ["NO_READABLE_SOURCE"],
      allowedActions: [],
      sources: [],
      exclusions: [],
      currencies: [],
      fallbacks: [],
      includedCount: undefined,
      excludedCount: undefined
    });
    const blocked = build("001A");
    getHolders.emit(holders);
    await flush();
    // No result was derived, so "no fallback was needed" may not be asserted.
    expect(
      blocked.shadowRoot.querySelector('[data-id="no-fallbacks"]')
    ).toBeNull();
    const coverage = blocked.shadowRoot.querySelector(
      '[data-id="coverage"]'
    ).textContent;
    expect(coverage).toContain("coverageUnknown");
    expect(coverage).not.toContain("undefined");

    // An older response that omits the fallback list asserts nothing either.
    explain.mockResolvedValue({ ...panel, fallbacks: undefined });
    const older = build("001A");
    getHolders.emit(holders);
    await flush();
    expect(
      older.shadowRoot.querySelector('[data-id="no-fallbacks"]')
    ).toBeNull();
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

  it("discards the previous context on a change and revalidates it on the server", async () => {
    // The revalidation is held open so the state between the event and the answer is observable.
    let answer;
    const pending = new Promise((resolve) => {
      answer = resolve;
    });
    explain.mockResolvedValueOnce(panel).mockReturnValueOnce(pending);
    const { refreshApex } = require("@salesforce/apex");
    const element = build();
    getHolders.emit(holders);
    await flush();
    element.shadowRoot
      .querySelector('[data-id="scope"]')
      .dispatchEvent(new CustomEvent("change", { detail: { value: ["001A"] } }));
    await flush();
    element.shadowRoot.querySelector('[data-id="explain"]').click();
    await flush();
    expect(
      element.shadowRoot.querySelectorAll('[data-id="sources"] tbody tr')
        .length
    ).toBe(3);
    expect(
      element.shadowRoot.querySelector('[data-id="announcer"]').textContent
    ).toContain("levelDegraded");

    // The context changed: the derived panel must not survive the event, on screen or announced.
    subscribe.mock.calls[0][2]({ changeReason: "AUTHORIZATION_REVALIDATION" });
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="level"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="sources"]')).toBeNull();
    expect(
      element.shadowRoot.querySelector('[data-id="announcer"]').textContent
    ).toBe("");
    // The reachable holder cache was refreshed, not trusted, and the server was asked again.
    expect(refreshApex).toHaveBeenCalledTimes(1);
    expect(explain).toHaveBeenCalledTimes(2);
    expect(explain).toHaveBeenLastCalledWith({ accountIds: ["001A"] });

    // The revalidated answer replaces the whole unit; the previous one is never a fallback.
    answer({
      ...panel,
      level: "BLOCKED",
      reasons: ["NO_AUTHORIZED_SCOPE"],
      allowedActions: [],
      fallbacks: [],
      currencies: [],
      includedCount: 0,
      excludedCount: 0,
      exclusions: [],
      sources: []
    });
    await flush();
    expect(
      element.shadowRoot.querySelector('[data-id="level"]').textContent
    ).toContain("levelBlocked");
    expect(
      element.shadowRoot.querySelectorAll('[data-id="sources"] tbody tr')
        .length
    ).toBe(0);
    expect(
      element.shadowRoot.querySelector('[data-id="fx"]').textContent
    ).toContain("fxUnknown");
    expect(
      element.shadowRoot.querySelector('[data-id="announcer"]').textContent
    ).toContain("levelBlocked");

    document.body.removeChild(element);
    await flush();
    expect(unsubscribe).toHaveBeenCalled();
  });

  it("revalidates a fixed record scope through the refreshed holder wire", async () => {
    explain.mockResolvedValue(panel);
    const { refreshApex } = require("@salesforce/apex");
    const element = build("001A");
    getHolders.emit(holders);
    await flush();
    expect(explain).toHaveBeenCalledTimes(1);
    expect(
      element.shadowRoot.querySelector('[data-id="level"]')
    ).not.toBeNull();

    subscribe.mock.calls[0][2]({ changeReason: "AUTHORIZATION_REVALIDATION" });
    await flush();
    // The record scope is not reloaded by the handler itself, and nothing of the panel remains.
    expect(explain).toHaveBeenCalledTimes(1);
    expect(refreshApex).toHaveBeenCalledTimes(1);
    expect(element.shadowRoot.querySelector('[data-id="level"]')).toBeNull();
    expect(
      element.shadowRoot.querySelector('[data-id="announcer"]').textContent
    ).toBe("");

    // The refreshed holder wire re-applies the record scope and asks the server again.
    getHolders.emit(holders);
    await flush();
    expect(explain).toHaveBeenCalledTimes(2);
    expect(explain).toHaveBeenLastCalledWith({ accountIds: ["001A"] });
    expect(
      element.shadowRoot.querySelector('[data-id="level"]')
    ).not.toBeNull();
  });
});
