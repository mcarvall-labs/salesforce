import { createElement } from "lwc";
import ConsolidationPanel from "c/aXF_LWC_consolidationPanel";
import getContext from "@salesforce/apex/AXF_CLS_CTRL_ConsolidationPanel.getContext";
import consolidate from "@salesforce/apex/AXF_CLS_CTRL_ConsolidationPanel.consolidate";
import { subscribe, unsubscribe } from "lightning/messageService";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ConsolidationPanel.getContext",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ConsolidationPanel.consolidate",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex",
  () => ({ refreshApex: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);

const flush = async () => {
  for (let i = 0; i < 6; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};

const context = {
  canConsolidate: true,
  policyVersion: "consolidation-scope@1.0.0",
  holders: [
    { accountId: "001A", name: "Ana" },
    { accountId: "001B", name: "Empresa B" }
  ],
  currencies: [
    {
      isoCode: "BRL",
      label: "Real",
      suggestedDefault: true
    },
    { isoCode: "USD", label: "Dolar", suggestedDefault: false }
  ],
  defaultReportingIso: "BRL"
};

/** Fixture arithmetic: BRL 900 - 200 = 700, USD 20 - 0 = 20 -> 20 x 5.0033 = 100.07. */
const result = {
  policyVersion: "consolidation-scope@1.0.0",
  asOf: "2026-09-14T12:00:00.000Z",
  fromDate: null,
  toDate: null,
  confidence: "DEGRADED",
  reasons: ["COVERAGE_UNVERIFIED"],
  holders: [
    {
      accountId: "001A",
      accountName: "Ana",
      state: "AUTHORIZED",
      coverage: "FULL"
    },
    {
      accountId: "001B",
      accountName: "Empresa B",
      state: "UNKNOWN",
      coverage: "UNVERIFIED"
    }
  ],
  exclusions: [{ accountId: "001Z", reason: "NOT_AUTHORIZED", count: 2 }],
  contributions: [],
  totals: [
    {
      currencyIso: "BRL",
      inflow: 900,
      outflow: 200,
      net: 700,
      factCount: 3,
      holderCount: 2,
      conversionState: "SAME_CURRENCY"
    },
    {
      currencyIso: "USD",
      inflow: 20,
      outflow: 0,
      net: 20,
      factCount: 1,
      holderCount: 1,
      conversionState: "ESTIMATED",
      rateInflow: 5.0033,
      rateProvider: "BCB_PTAX",
      reportingInflow: 100.07,
      reportingOutflow: 0,
      reportingNet: 100.07
    }
  ],
  reportingIso: "BRL",
  comparableTotal: {
    currencyIso: "BRL",
    inflow: 1000.07,
    outflow: 200,
    net: 800.07,
    factCount: 4,
    holderCount: 2
  }
};

/** The withholding case of AXF-123: one currency without a usable quote, no comparable figure. */
const withheld = {
  ...result,
  reasons: ["MISSING_MATERIAL_FX"],
  totals: [
    result.totals[0],
    {
      ...result.totals[1],
      conversionState: "UNAVAILABLE",
      rateInflow: null,
      reportingInflow: null,
      reportingOutflow: null,
      reportingNet: null
    }
  ],
  comparableTotal: null
};

function build() {
  const element = createElement("c-a-x-f_-l-w-c_consolidation-panel", {
    is: ConsolidationPanel
  });
  document.body.appendChild(element);
  return element;
}

/** Selects a scope and derives the view, the way the presented surface is used. */
async function derive(element, scope = ["001A", "001B"]) {
  element.shadowRoot
    .querySelector('[data-id="scope"]')
    .dispatchEvent(new CustomEvent("change", { detail: { value: scope } }));
  await flush();
  element.shadowRoot.querySelector('[data-id="consolidate"]').click();
  await flush();
}

describe("c-aXF_LWC_consolidationPanel", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("renders the five information groups the acceptance criteria name, with semantics", async () => {
    consolidate.mockResolvedValue(result);
    const element = build();

    // Loading is announced while nothing has been derived yet.
    expect(element.shadowRoot.querySelector('[role="status"]')).not.toBeNull();
    getContext.emit(context);
    await flush();
    await derive(element);

    expect(consolidate).toHaveBeenCalledWith({
      accountIds: ["001A", "001B"],
      reportingIso: "BRL"
    });

    // Selected people/companies, with their access and coverage as text.
    const holders = element.shadowRoot.querySelectorAll(
      '[data-id="holders"] tbody tr'
    );
    expect(holders.length).toBe(2);
    expect(holders[0].textContent).toContain("Ana");
    expect(holders[1].textContent).toContain("Empresa B");
    expect(holders[1].textContent).toContain("holderUnknown");
    expect(holders[1].textContent).toContain("coverageUnverified");

    // Currency: every total states its own ISO, and the comparable section names the one used.
    const totals = element.shadowRoot.querySelectorAll(
      '[data-id="totals"] tbody tr'
    );
    expect(totals.length).toBe(2);
    expect(totals[0].textContent).toContain("BRL");
    expect(totals[1].textContent).toContain("USD");
    expect(totals[1].textContent).toContain("fxESTIMATED");
    expect(
      element.shadowRoot.querySelector('[data-id="comparable-state"]')
        .textContent
    ).toContain("fxESTIMATED");
    expect(
      element.shadowRoot.querySelector('[data-id="comparable"]').textContent
    ).toContain("BRL");

    // Freshness: an announced instant plus the declaring policy, and an unbounded period said so.
    const asOf = element.shadowRoot.querySelector('[data-id="as-of"]');
    expect(asOf.querySelector("lightning-formatted-date-time")).not.toBeNull();
    expect(asOf.textContent).toContain("consolidation-scope@1.0.0");
    expect(
      element.shadowRoot.querySelector('[data-id="period"]').textContent
    ).toContain("periodOpen");

    // Confidence: the badge carries its own words, never colour alone.
    const confidence = element.shadowRoot.querySelector(
      '[data-id="confidence"]'
    );
    expect(confidence.textContent).toContain("confidenceDEGRADED");
    expect(confidence.className).toContain("slds-badge_warning");
    expect(
      element.shadowRoot.querySelectorAll('[data-id="reasons"] li').length
    ).toBe(1);

    // Exclusions: the reason, the selection it belongs to and the count when it says something.
    const exclusions = element.shadowRoot.querySelectorAll(
      '[data-id="exclusions"] li'
    );
    expect(exclusions.length).toBe(1);
    expect(exclusions[0].textContent).toContain("exNotAuthorized");
    expect(exclusions[0].textContent).toContain("001Z");
    expect(exclusions[0].textContent).toContain("2");

    // The comparison column exists because the server compared something.
    expect(
      element.shadowRoot.querySelector('[data-id="totals"] thead').textContent
    ).toContain("conversion");
    // A scrollable table stays reachable from the keyboard.
    element.shadowRoot
      .querySelectorAll(".slds-scrollable_x")
      .forEach((wrapper) => {
        expect(wrapper.getAttribute("tabindex")).toBe("0");
      });

    // Structural accessibility: every section is a labelled region pointing at its own heading.
    const regions = element.shadowRoot.querySelectorAll(
      'section[role="region"]'
    );
    expect(regions.length).toBe(5);
    regions.forEach((region) => {
      const labelledBy = region.getAttribute("aria-labelledby");
      expect(labelledBy).toBeTruthy();
      expect(
        element.shadowRoot.querySelector('[id="' + labelledBy + '"]')
      ).not.toBeNull();
    });
    expect(
      element.shadowRoot.querySelectorAll('th[scope="col"]').length
    ).toBeGreaterThan(0);
    expect(element.shadowRoot.querySelectorAll('th[scope="row"]').length).toBe(
      4
    );
    expect(
      element.shadowRoot.querySelector('[data-id="announcer"]').textContent
    ).not.toBe("");
    expect(
      element.shadowRoot
        .querySelector('[data-id="announcer"]')
        .getAttribute("aria-live")
    ).toBe("polite");
    // Nothing is hidden behind a hover-only disclosure or a clipped cell.
    expect(element.shadowRoot.querySelectorAll(".slds-truncate").length).toBe(
      0
    );
  });

  it("withholds the comparable indicator and names the currency that has no quote", async () => {
    consolidate.mockResolvedValue(withheld);
    const element = build();
    getContext.emit(context);
    await flush();
    await derive(element);

    expect(
      element.shadowRoot.querySelector('[data-id="comparable"]')
    ).toBeNull();
    const statement = element.shadowRoot.querySelector(
      '[data-id="comparable-withheld"]'
    );
    expect(statement.textContent).toContain("comparableWithheld");
    expect(statement.textContent).toContain("USD");
    expect(
      element.shadowRoot.querySelector('[data-id="comparable-state"]')
    ).toBeNull();
    // The reason is visible, and the original totals are all still on screen.
    expect(
      element.shadowRoot.querySelector('[data-id="reasons"]').textContent
    ).toContain("reasonMissingFx");
    const totals = element.shadowRoot.querySelectorAll(
      '[data-id="totals"] tbody tr'
    );
    expect(totals.length).toBe(2);
    expect(totals[1].textContent).toContain("fxUNAVAILABLE");
    // The original magnitudes of every currency are still presented.
    const numbers = element.shadowRoot.querySelectorAll(
      '[data-id="totals"] lightning-formatted-number'
    );
    expect(numbers[0].value).toBe(900);
    expect(numbers[1].value).toBe(200);
    expect(numbers[3].value).toBe(20);

    // A quote outside its validity window blocks the indicator the same way and is named the same
    // way: the reader is never told only that something could not be converted.
    element.shadowRoot
      .querySelector('[data-id="scope"]')
      .dispatchEvent(
        new CustomEvent("change", { detail: { value: ["001A"] } })
      );
    await flush();
    consolidate.mockResolvedValueOnce({
      ...withheld,
      totals: [
        withheld.totals[0],
        { ...withheld.totals[1], conversionState: "STALE" }
      ]
    });
    element.shadowRoot.querySelector('[data-id="consolidate"]').click();
    await flush();
    const stale = element.shadowRoot.querySelector(
      '[data-id="comparable-withheld"]'
    );
    expect(stale.textContent).toContain("USD");
    expect(
      element.shadowRoot.querySelector('[data-id="totals"] tbody').textContent
    ).toContain("fxSTALE");
  });

  it("renders a blocked result with its reasons and states that there is no authorized total", async () => {
    consolidate.mockResolvedValue({
      ...result,
      confidence: "BLOCKED",
      reasons: ["VOLUME_EXCEEDED"],
      holders: [],
      totals: [],
      exclusions: [],
      comparableTotal: null,
      reportingIso: null
    });
    const element = build();
    getContext.emit(context);
    await flush();
    await derive(element);

    const confidence = element.shadowRoot.querySelector(
      '[data-id="confidence"]'
    );
    expect(confidence.textContent).toContain("confidenceBLOCKED");
    expect(confidence.className).toContain("slds-badge_error");
    expect(
      element.shadowRoot.querySelector('[data-id="reasons"]').textContent
    ).toContain("reasonVolumeExceeded");
    expect(
      element.shadowRoot.querySelector('[data-id="no-totals"]').textContent
    ).toContain("noTotals");
    expect(
      element.shadowRoot.querySelector('[data-id="no-holders"]').textContent
    ).toContain("noHolders");
    expect(
      element.shadowRoot.querySelector('[data-id="no-exclusions"]').textContent
    ).toContain("noExclusions");
    // The reader chose BRL, so the absence of a comparable total is not reported as "no currency
    // was chosen": nothing was consolidated at all.
    expect(
      element.shadowRoot.querySelector('[data-id="comparable-blocked"]')
        .textContent
    ).toContain("comparableBlocked");
    expect(
      element.shadowRoot.querySelector('[data-id="no-comparison"]')
    ).toBeNull();
  });

  it("renders nothing for a user without the capability", async () => {
    const element = build();
    getContext.emit({ ...context, canConsolidate: false, holders: [] });
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="scope"]')).toBeNull();
    expect(
      element.shadowRoot.querySelector('[data-id="consolidate"]')
    ).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="error"]')).toBeNull();
    expect(consolidate).not.toHaveBeenCalled();
  });

  it("never leaks a field name when the field access is missing", async () => {
    consolidate.mockResolvedValue({
      ...result,
      confidence: "BLOCKED",
      reasons: ["FIELD_ACCESS:AXF_BAT_NUM_Magnitude__c"],
      holders: [],
      totals: [],
      exclusions: [],
      comparableTotal: null,
      reportingIso: null
    });
    const element = build();
    getContext.emit(context);
    await flush();
    await derive(element);

    const reasons = element.shadowRoot.querySelector('[data-id="reasons"]');
    expect(reasons.textContent).toContain("reasonFieldAccess");
    expect(reasons.textContent).not.toContain("AXF_BAT_NUM_Magnitude__c");
  });

  it("states an exact comparable total when no conversion was needed", async () => {
    consolidate.mockResolvedValue({
      ...result,
      totals: result.totals.map((row) => ({
        ...row,
        conversionState: "SAME_CURRENCY"
      })),
      comparableTotal: { ...result.comparableTotal }
    });
    const element = build();
    getContext.emit(context);
    await flush();
    await derive(element);

    expect(
      element.shadowRoot.querySelector('[data-id="comparable-state"]')
        .textContent
    ).toContain("fxSAME_CURRENCY");
    expect(
      element.shadowRoot.querySelectorAll(
        '[data-id="totals"] lightning-formatted-number'
      ).length
    ).toBe(6);
  });

  it("states that no comparison was requested and leaves the column out", async () => {
    consolidate.mockResolvedValue({
      ...result,
      totals: result.totals.map((row) => ({
        ...row,
        conversionState: null
      })),
      comparableTotal: null,
      reportingIso: null,
      reasons: []
    });
    const element = build();
    getContext.emit(context);
    await flush();
    // No presentation currency is chosen on this surface.
    element.shadowRoot
      .querySelector('[data-id="reporting-currency"]')
      .dispatchEvent(new CustomEvent("change", { detail: { value: "" } }));
    await flush();
    await derive(element);

    expect(
      element.shadowRoot.querySelector('[data-id="no-comparison"]').textContent
    ).toContain("noComparison");
    expect(
      element.shadowRoot.querySelector('[data-id="comparable-blocked"]')
    ).toBeNull();
    expect(
      element.shadowRoot.querySelector('[data-id="totals"] thead').textContent
    ).not.toContain("conversion");
  });

  it("renders a sanitized error with retry, for the derivation and for the context wire", async () => {
    consolidate.mockRejectedValueOnce({ body: { message: "FORBIDDEN" } });
    consolidate.mockResolvedValueOnce(result);
    const element = build();
    getContext.emit(context);
    await flush();
    await derive(element);

    const error = element.shadowRoot.querySelector('[data-id="error"]');
    expect(error).not.toBeNull();
    expect(error.textContent).toContain("codeForbidden");
    expect(
      element.shadowRoot.querySelector('[data-id="announcer"]').textContent
    ).toContain("codeForbidden");
    element.shadowRoot.querySelector('[data-id="retry"]').click();
    await flush();
    expect(consolidate).toHaveBeenCalledTimes(2);
    expect(element.shadowRoot.querySelector('[data-id="error"]')).toBeNull();
    expect(
      element.shadowRoot.querySelector('[data-id="confidence"]')
    ).not.toBeNull();

    // A failing context wire shows the same error region and retries the wire instead.
    const { refreshApex } = require("@salesforce/apex");
    const other = build();
    getContext.error({ message: "NOT_ACCESSIBLE" });
    await flush();
    expect(
      other.shadowRoot.querySelector('[data-id="error"]').textContent
    ).toContain("codeNotAccessible");
    other.shadowRoot.querySelector('[data-id="retry"]').click();
    await flush();
    expect(refreshApex).toHaveBeenCalled();
  });

  it("stays empty until a scope is selected", async () => {
    consolidate.mockResolvedValue(result);
    const element = build();
    expect(element.shadowRoot.querySelector('[role="status"]')).not.toBeNull();
    getContext.emit(context);
    await flush();
    expect(
      element.shadowRoot.querySelector('[data-id="consolidate"]').disabled
    ).toBe(true);
    expect(
      element.shadowRoot.querySelector('[data-id="empty"]').textContent
    ).toContain("empty");
    expect(consolidate).not.toHaveBeenCalled();
  });

  it("discards the previous view on a context change and derives it again on the server", async () => {
    consolidate.mockResolvedValue(result);
    const element = build();
    getContext.emit(context);
    await flush();
    await derive(element);
    expect(
      element.shadowRoot.querySelector('[data-id="totals"]')
    ).not.toBeNull();

    consolidate.mockResolvedValue({
      ...result,
      confidence: "FULL",
      reasons: []
    });
    subscribe.mock.calls[0][2]();
    await flush();

    // The previous context's view never stands in for the new one, and the server is asked again.
    expect(consolidate).toHaveBeenCalledTimes(2);
    expect(
      element.shadowRoot.querySelector('[data-id="confidence"]').textContent
    ).toContain("confidenceFULL");
    const { refreshApex } = require("@salesforce/apex");
    expect(refreshApex.mock.calls[0][0].data).toBe(context);
    expect(unsubscribe).not.toHaveBeenCalled();
  });

  it("empties the cached holder list and shows only what the refreshed wire returns", async () => {
    consolidate.mockResolvedValue(result);
    const element = build();
    getContext.emit(context);
    await flush();
    await derive(element);

    subscribe.mock.calls[0][2]();
    await flush();
    const options =
      element.shadowRoot.querySelector('[data-id="scope"]').options;
    expect(options.length).toBe(0);

    // The wire answers with the surviving holder only; that is what the picker offers.
    getContext.emit({ ...context, holders: [context.holders[0]] });
    await flush();
    expect(
      element.shadowRoot.querySelector('[data-id="scope"]').options.length
    ).toBe(1);
  });

  it("rejects an answer that started before the context changed", async () => {
    let resolveFirst;
    consolidate.mockReturnValueOnce(
      new Promise((resolve) => {
        resolveFirst = resolve;
      })
    );
    consolidate.mockResolvedValue(result);
    const element = build();
    getContext.emit(context);
    await flush();
    await derive(element);

    // A second derivation is in flight when the context changes.
    element.shadowRoot.querySelector('[data-id="consolidate"]').click();
    await flush();
    subscribe.mock.calls[0][2]();
    await flush();
    resolveFirst({ ...result, confidence: "FULL", reasons: [] });
    await flush();

    // The stale answer never becomes the displayed view of the new context.
    expect(
      element.shadowRoot.querySelector('[data-id="confidence"]').textContent
    ).toContain("confidenceDEGRADED");
  });

  it("rejects an answer still in flight when the context changes with no scope", async () => {
    let resolveFirst;
    consolidate.mockReturnValueOnce(
      new Promise((resolve) => {
        resolveFirst = resolve;
      })
    );
    const element = build();
    getContext.emit(context);
    await flush();
    await derive(element, ["001A"]);

    // The scope is cleared while an answer is in flight, and the context then changes: this arm
    // issues no server call of its own, so only the invalidation of the handler can reject it.
    element.shadowRoot
      .querySelector('[data-id="scope"]')
      .dispatchEvent(new CustomEvent("change", { detail: { value: [] } }));
    await flush();
    subscribe.mock.calls[0][2]();
    await flush();
    resolveFirst(result);
    await flush();

    expect(
      element.shadowRoot.querySelector('[data-id="empty"]')
    ).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="totals"]')).toBeNull();
  });

  it("discards the displayed view as soon as the scope changes", async () => {
    consolidate.mockResolvedValue(result);
    const element = build();
    getContext.emit(context);
    await flush();
    await derive(element);
    expect(
      element.shadowRoot.querySelector('[data-id="totals"]')
    ).not.toBeNull();

    element.shadowRoot
      .querySelector('[data-id="scope"]')
      .dispatchEvent(
        new CustomEvent("change", { detail: { value: ["001A"] } })
      );
    await flush();

    // The previous scope's totals and its announcement are gone, not kept as a fallback.
    expect(element.shadowRoot.querySelector('[data-id="totals"]')).toBeNull();
    expect(
      element.shadowRoot.querySelector('[data-id="empty"]')
    ).not.toBeNull();
    expect(
      element.shadowRoot.querySelector('[data-id="announcer"]').textContent
    ).toBe("");
  });

  it("rejects an answer still in flight when the scope changes", async () => {
    let resolveFirst;
    consolidate.mockReturnValueOnce(
      new Promise((resolve) => {
        resolveFirst = resolve;
      })
    );
    const element = build();
    getContext.emit(context);
    await flush();
    await derive(element, ["001A"]);

    // The scope moves on while the derivation is in flight: the answer belongs to the scope that
    // was asked for, so it must not be presented for the new one.
    element.shadowRoot
      .querySelector('[data-id="scope"]')
      .dispatchEvent(
        new CustomEvent("change", { detail: { value: ["001B"] } })
      );
    await flush();
    resolveFirst(result);
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="totals"]')).toBeNull();
    expect(
      element.shadowRoot.querySelector('[data-id="empty"]')
    ).not.toBeNull();
  });

  it("derives the view again when the presentation currency changes", async () => {
    consolidate.mockResolvedValue(result);
    const element = build();
    getContext.emit(context);
    await flush();
    await derive(element);
    expect(consolidate).toHaveBeenCalledTimes(1);

    element.shadowRoot
      .querySelector('[data-id="reporting-currency"]')
      .dispatchEvent(new CustomEvent("change", { detail: { value: "USD" } }));
    await flush();

    expect(consolidate).toHaveBeenCalledTimes(2);
    expect(consolidate).toHaveBeenLastCalledWith({
      accountIds: ["001A", "001B"],
      reportingIso: "USD"
    });
    expect(
      element.shadowRoot.querySelector('[data-id="comparable-state"]')
    ).not.toBeNull();
  });

  it("keeps the chosen presentation currency when the context wire refreshes", async () => {
    consolidate.mockResolvedValue(result);
    const element = build();
    getContext.emit(context);
    await flush();
    element.shadowRoot
      .querySelector('[data-id="reporting-currency"]')
      .dispatchEvent(new CustomEvent("change", { detail: { value: "USD" } }));
    await flush();

    getContext.emit(context);
    await flush();
    await derive(element);

    expect(consolidate).toHaveBeenLastCalledWith({
      accountIds: ["001A", "001B"],
      reportingIso: "USD"
    });
  });
});
