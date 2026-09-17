import { createElement } from "lwc";
import ForecastComparison from "c/aXF_LWC_forecastComparison";
import getContext from "@salesforce/apex/AXF_CLS_CTRL_ForecastComparison.getContext";
import compare from "@salesforce/apex/AXF_CLS_CTRL_ForecastComparison.compare";
import { subscribe, unsubscribe } from "lightning/messageService";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ForecastComparison.getContext",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ForecastComparison.compare",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex",
  () => ({ refreshApex: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);

const flush = async () => {
  for (let i = 0; i < 8; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};

const context = {
  canCompare: true,
  horizons: [3, 6, 9, 12, 15, 18, 21, 24],
  policyVersion: "AXF-FORECASTING@1.0.0",
  holders: [{ accountId: "001A", name: "Ana" }]
};

function horizon(months, beyondOut) {
  return {
    horizonMonths: months,
    currencyIso: "BRL",
    confirmedIn: 100,
    confirmedOut: 60,
    probableIn: 0,
    probableOut: 30,
    uncertainIn: 10,
    uncertainOut: 0,
    conservativeNet: 40,
    intermediateNet: 10,
    optimisticNet: 20,
    beyondOut,
    beyondIn: 0,
    beyondCount: beyondOut > 0 ? 3 : 0
  };
}

const result = {
  policyVersion: "AXF-FORECASTING@1.0.0",
  engineVersion: "forecast-horizon@1.0.0",
  asOf: "2026-09-15",
  horizonMonths: 12,
  horizonEnd: "2027-08-31",
  scenario: "INTERMEDIATE",
  confidence: "DEGRADED",
  reasons: ["OBLIGATIONS_BEYOND_HORIZON", "OVERDUE_OBLIGATIONS"],
  allowedActions: ["REVIEW_SCHEDULES"],
  holders: [{ accountId: "001A", accountName: "Ana", state: "AUTHORIZED" }],
  exclusions: [],
  sources: [
    {
      kind: "SCHEDULE",
      sourceId: "a0S1",
      label: "FSC-1",
      currencyIso: "BRL",
      outcome: "OK",
      occurrenceCount: 356,
      coverageComplete: true,
      unbounded: false
    }
  ],
  currencies: ["BRL"],
  periods: [
    {
      periodKey: "2026-09",
      currencyIso: "BRL",
      confirmedIn: 100,
      confirmedOut: 60,
      probableIn: 0,
      probableOut: 30,
      uncertainIn: 10,
      uncertainOut: 0,
      count: 4
    }
  ],
  horizons: [3, 6, 9, 12, 15, 18, 21, 24].map((m) =>
    horizon(m, m < 24 ? 500 : 0)
  ),
  overdue: [{ currencyIso: "BRL", amountOut: 12.5, amountIn: 0, count: 1 }],
  unboundedCommitment: false
};

function build() {
  const element = createElement("c-a-x-f_-l-w-c_forecast-comparison", {
    is: ForecastComparison
  });
  document.body.appendChild(element);
  return element;
}

async function select(element) {
  element.shadowRoot
    .querySelector('[data-id="scope"]')
    .dispatchEvent(new CustomEvent("change", { detail: { value: ["001A"] } }));
  await flush();
}

describe("c-aXF_LWC_forecastComparison", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("compares with the chosen horizon and scenario, shows beyond-horizon and overdue, and switches scenario without a server call", async () => {
    compare.mockResolvedValue(result);
    const element = build();
    getContext.emit(context);
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="idle"]')).not.toBeNull();
    await select(element);
    element.shadowRoot.querySelector('[data-id="compare"]').click();
    await flush();
    const request = JSON.parse(compare.mock.calls[0][0].request);
    expect(request).toEqual({
      accountIds: ["001A"],
      horizonMonths: 12,
      scenario: "INTERMEDIATE",
      asOf: null
    });
    expect(
      element.shadowRoot.querySelector('[data-id="confidence"]').className
    ).toContain("slds-badge_warning");
    expect(
      element.shadowRoot.querySelectorAll('[data-id="horizons"] tbody tr')
        .length
    ).toBe(8);
    expect(
      element.shadowRoot.querySelector('[data-id="beyond"]')
    ).not.toBeNull();
    expect(
      element.shadowRoot.querySelector('[data-id="overdue"]')
    ).not.toBeNull();
    expect(
      element.shadowRoot.querySelectorAll('[data-id="reasons"] li').length
    ).toBe(2);
    // intermediate: 100 in, 90 out
    const net = element.shadowRoot.querySelector(
      '[data-period="2026-09"] [data-id="net"] lightning-formatted-number'
    );
    expect(net.value).toBe(10);
    element.shadowRoot
      .querySelector('[data-id="scenario"]')
      .dispatchEvent(
        new CustomEvent("change", { detail: { value: "OPTIMISTIC" } })
      );
    await flush();
    expect(compare).toHaveBeenCalledTimes(1);
    const optimistic = element.shadowRoot.querySelector(
      '[data-period="2026-09"] [data-id="net"] lightning-formatted-number'
    );
    expect(optimistic.value).toBe(20);
    expect(
      element.shadowRoot.querySelector('[data-id="announcer"]').textContent
    ).toContain("updated");
    // horizon change triggers a new comparison
    element.shadowRoot
      .querySelector('[data-id="horizon"]')
      .dispatchEvent(new CustomEvent("change", { detail: { value: "24" } }));
    await flush();
    expect(compare).toHaveBeenCalledTimes(2);
    expect(JSON.parse(compare.mock.calls[1][0].request).horizonMonths).toBe(24);
  });

  it("shows blocked results, sanitized errors with retry, and hides itself without the capability", async () => {
    compare
      .mockResolvedValueOnce({
        ...result,
        confidence: "BLOCKED",
        reasons: ["NO_AUTHORIZED_SCOPE"],
        allowedActions: [],
        periods: [],
        horizons: [],
        overdue: []
      })
      .mockRejectedValueOnce({ body: { message: "FORBIDDEN" } });
    const element = build();
    getContext.emit(context);
    await flush();
    await select(element);
    element.shadowRoot.querySelector('[data-id="compare"]').click();
    await flush();
    expect(
      element.shadowRoot.querySelector('[data-id="empty"]')
    ).not.toBeNull();
    // A BLOCKED result is explained, never rendered as a silent empty state.
    expect(
      element.shadowRoot.querySelector('[data-id="confidence"]').textContent
    ).toContain("confidenceBLOCKED");
    expect(
      element.shadowRoot.querySelector('[data-id="reasons"]').textContent
    ).toContain("reasonNO_AUTHORIZED_SCOPE");
    expect(element.shadowRoot.querySelector('[data-id="horizons"]')).toBeNull();
    element.shadowRoot.querySelector('[data-id="compare"]').click();
    await flush();
    expect(
      element.shadowRoot.querySelector('[data-id="error"]').textContent
    ).toContain("codeForbidden");
    element.shadowRoot.querySelector('[data-id="retry"]').click();
    await flush();
    expect(compare).toHaveBeenCalledTimes(3);

    const denied = build();
    getContext.emit({ ...context, canCompare: false, holders: [] });
    await flush();
    expect(denied.shadowRoot.querySelector("lightning-card")).toBeNull();
    expect(
      denied.shadowRoot.querySelector('[data-id="forbidden"]')
    ).not.toBeNull();
  });

  it("renders the category without an approved method as an explained reason", async () => {
    compare.mockResolvedValueOnce({
      ...result,
      confidence: "BLOCKED",
      reasons: ["NO_APPROVED_METHOD"],
      // The omitted occurrence is recorded against its holder, not dropped in silence.
      exclusions: [{ accountId: "001A", reason: "NO_APPROVED_METHOD" }],
      allowedActions: []
    });
    const element = build();
    getContext.emit(context);
    await flush();
    await select(element);
    element.shadowRoot.querySelector('[data-id="compare"]').click();
    await flush();
    const reasons = element.shadowRoot.querySelector(
      '[data-id="reasons"]'
    ).textContent;
    // The label, not the raw server code the fallback would print.
    expect(reasons).toContain(
      "AXF_ForecastComparison_reasonNO_APPROVED_METHOD"
    );
    const exclusions = element.shadowRoot.querySelector(
      '[data-id="exclusions"]'
    ).textContent;
    expect(exclusions).toContain(
      "AXF_ForecastComparison_reasonNO_APPROVED_METHOD"
    );
  });

  it("discards the previous context on a change and revalidates it on the server", async () => {
    // The revalidation is held open so the state between the event and the answer is observable.
    let answer;
    const pending = new Promise((resolve) => {
      answer = resolve;
    });
    compare.mockResolvedValueOnce(result).mockReturnValueOnce(pending);
    const { refreshApex } = require("@salesforce/apex");
    const element = build();
    getContext.emit(context);
    await flush();
    await select(element);
    element.shadowRoot.querySelector('[data-id="compare"]').click();
    await flush();
    const previousNet = element.shadowRoot.querySelector(
      '[data-period="2026-09"] [data-id="net"] lightning-formatted-number'
    );
    expect(previousNet.value).toBe(10);
    expect(
      element.shadowRoot.querySelector('[data-id="announcer"]').textContent
    ).toContain("updated");

    // The context changed: the displayed result must not survive the event, on screen or announced.
    subscribe.mock.calls[0][2]({ changeReason: "AUTHORIZATION_REVALIDATION" });
    await flush();
    expect(
      element.shadowRoot.querySelector('[data-id="confidence"]')
    ).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="periods"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="horizons"]')).toBeNull();
    expect(
      element.shadowRoot.querySelector('[data-id="announcer"]').textContent
    ).toBe("");
    // The reachable holder context was refreshed, not trusted, and the server was asked again.
    expect(refreshApex).toHaveBeenCalledTimes(1);
    expect(compare).toHaveBeenCalledTimes(2);

    // The revalidated answer replaces the whole unit; the previous total is never a fallback.
    answer({
      ...result,
      confidence: "BLOCKED",
      reasons: ["NO_AUTHORIZED_SCOPE"],
      allowedActions: [],
      exclusions: [{ accountId: "001A", reason: "NOT_AUTHORIZED" }],
      sources: [],
      periods: [],
      horizons: [],
      overdue: []
    });
    await flush();
    expect(
      element.shadowRoot.querySelector('[data-id="confidence"]').textContent
    ).toContain("confidenceBLOCKED");
    expect(
      element.shadowRoot.querySelector('[data-id="reasons"]').textContent
    ).toContain("reasonNO_AUTHORIZED_SCOPE");
    expect(element.shadowRoot.querySelector('[data-id="periods"]')).toBeNull();
    expect(
      element.shadowRoot.querySelector('[data-id="empty"]')
    ).not.toBeNull();
    expect(
      element.shadowRoot.querySelector('[data-id="announcer"]').textContent
    ).not.toBe("");

    document.body.removeChild(element);
    await flush();
    expect(unsubscribe).toHaveBeenCalled();
  });
});
