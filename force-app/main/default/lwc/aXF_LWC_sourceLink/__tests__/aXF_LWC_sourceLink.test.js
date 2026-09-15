import { createElement } from "lwc";
import SourceLink from "c/aXF_LWC_sourceLink";
import getContext from "@salesforce/apex/AXF_CLS_CTRL_SourceLink.getContext";
import listSources from "@salesforce/apex/AXF_CLS_CTRL_SourceLink.listSources";
import listCandidates from "@salesforce/apex/AXF_CLS_CTRL_SourceLink.listCandidates";
import confirm from "@salesforce/apex/AXF_CLS_CTRL_SourceLink.confirm";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_SourceLink.getContext",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_SourceLink.listSources",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_SourceLink.listCandidates",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_SourceLink.confirm",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = async () => {
  for (let i = 0; i < 8; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};

const context = {
  canLink: true,
  policyVersion: "AXF-SOURCE-LINK@1.0.0",
  pageSize: 25,
  holders: [{ accountId: "001A", name: "Ana" }]
};
const source = {
  sourceId: "a0B1",
  sourceKind: "BANK",
  accountId: "001A",
  fundingId: "a0A1",
  fundingLabel: "Banco ****1234",
  origin: "CSV",
  amount: 150,
  residual: 150,
  currencyIso: "BRL",
  direction: "DEBIT",
  factDate: "2026-09-14",
  description: "Aluguel",
  version: 0,
  eligible: true,
  reasons: []
};
const evidence = [
  {
    feature: "EXTERNAL_IDENTITY",
    relation: "UNKNOWN",
    explanation: "EXTERNAL_IDENTITY_UNKNOWN"
  },
  {
    feature: "SOURCE_IDENTITY",
    relation: "EXACT",
    sourceValue: "a0A1",
    candidateValue: "a0A1",
    explanation: "SOURCE_IDENTITY_EXACT"
  },
  { feature: "HOLDER", relation: "EXACT", explanation: "HOLDER_EXACT" },
  {
    feature: "CURRENCY",
    relation: "EXACT",
    sourceValue: "BRL",
    candidateValue: "BRL",
    explanation: "CURRENCY_EXACT"
  },
  {
    feature: "AMOUNT",
    relation: "DIFFERENT",
    sourceValue: "150.00",
    candidateValue: "200.00",
    delta: 50,
    explanation: "AMOUNT_DIFFERENT"
  },
  {
    feature: "RESIDUAL",
    relation: "COVERS",
    sourceValue: "150.00",
    candidateValue: "120.00",
    delta: -30,
    explanation: "RESIDUAL_COVERS"
  },
  {
    feature: "DATE",
    relation: "DIFFERENT",
    sourceValue: "2026-09-14",
    candidateValue: "2026-09-20",
    delta: 6,
    explanation: "DATE_AFTER"
  },
  {
    feature: "DESCRIPTION",
    relation: "CONTAINS",
    sourceValue: "Aluguel",
    candidateValue: "Aluguel set",
    explanation: "DESCRIPTION_CONTAINS"
  },
  {
    feature: "CATEGORY",
    relation: "REDACTED",
    explanation: "CATEGORY_REDACTED"
  }
];
const candidates = {
  matchingPolicy: "AXF-MATCHING@1.0.0",
  state: "CONSULTATIVE",
  evidenceCutoff: "2026-09-15T12:00:00.000Z",
  tieCount: 1,
  lowEvidenceCount: 0,
  source,
  suggestedAmount: 150,
  suggestedDate: "2026-09-14",
  pageNumber: 1,
  pageSize: 25,
  hasMore: false,
  scanTruncated: false,
  excludedCount: 1,
  virtualCount: 1,
  items: [
    {
      targetId: "a0C1",
      persisted: true,
      amount: 200,
      residual: 120,
      currencyIso: "BRL",
      direction: "DEBIT",
      dueDate: "2026-09-20",
      description: "Aluguel set",
      status: "PLANNED",
      version: 3,
      linkable: true,
      reasons: [],
      state: "CONSULTATIVE",
      evidence,
      tied: true,
      lowEvidence: false
    },
    {
      scheduleId: "a0D1",
      sequence: 4,
      persisted: false,
      amount: 150,
      residual: 150,
      currencyIso: "BRL",
      direction: "DEBIT",
      dueDate: "2026-10-20",
      description: "Cronograma",
      status: "ESTIMATED",
      version: null,
      linkable: false,
      reasons: ["MATERIALIZATION_REQUIRED"],
      state: "CONSULTATIVE",
      evidence: evidence.map((v) => ({
        ...v,
        relation: "UNKNOWN",
        explanation: `${v.feature}_UNKNOWN`,
        delta: null,
        sourceValue: null,
        candidateValue: null
      })),
      tied: false,
      lowEvidence: true
    }
  ]
};

async function mount() {
  const element = createElement("c-a-x-f-_-l-w-c-_source-link", {
    is: SourceLink
  });
  document.body.appendChild(element);
  getContext.emit(context);
  await flush();
  return element;
}
function byId(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}
async function reachReview(element) {
  listSources.mockResolvedValue({
    pageNumber: 1,
    pageSize: 25,
    hasMore: false,
    scannedCount: 3,
    excludedCount: 2,
    items: [source]
  });
  listCandidates.mockResolvedValue(candidates);
  byId(element, "holder").dispatchEvent(
    new CustomEvent("change", { detail: { value: "001A" } })
  );
  await flush();
  byId(element, "loadSources").click();
  await flush();
  element.shadowRoot.querySelector('[data-id="a0B1"]').click();
  await flush();
  element.shadowRoot.querySelector('[data-index="0"]').click();
  await flush();
}

describe("c-a-x-f-_-l-w-c-_source-link", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("lists eligible sources, shows candidates with the virtual badge and confirms with the suggestion", async () => {
    const element = await mount();
    await reachReview(element);
    expect(listSources).toHaveBeenCalledTimes(1);
    const sourcesRequest = JSON.parse(listSources.mock.calls[0][0].request);
    expect(sourcesRequest).toMatchObject({
      accountId: "001A",
      sourceKind: null,
      pageNumber: 1
    });
    expect(JSON.parse(listCandidates.mock.calls[0][0].request)).toMatchObject({
      sourceId: "a0B1",
      sourceKind: "BANK"
    });
    expect(byId(element, "targetSummary").textContent).toContain("Aluguel set");
    expect(byId(element, "changed")).toBeNull();
    confirm.mockResolvedValue({
      allocationId: "a0E1",
      targetId: "a0C1",
      replayed: false,
      createdActualOnly: false,
      amount: 120,
      currencyIso: "BRL"
    });
    byId(element, "confirm").click();
    await flush();
    const request = JSON.parse(confirm.mock.calls[0][0].request);
    expect(request).toMatchObject({
      sourceId: "a0B1",
      sourceKind: "BANK",
      sourceVersion: 0,
      targetId: "a0C1",
      targetVersion: 3,
      amount: 120,
      recognitionDate: "2026-09-14",
      changesReviewed: false
    });
    expect(request.operationKey).toMatch(/^axf134-/);
    expect(byId(element, "done")).not.toBeNull();
  });

  it("requires explicit review after changing the amount and keeps the draft with the same key on failure", async () => {
    const element = await mount();
    await reachReview(element);
    const amount = byId(element, "amount");
    amount.value = "100";
    amount.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(byId(element, "changed")).not.toBeNull();
    expect(byId(element, "confirm").disabled).toBe(true);
    const reviewed = byId(element, "reviewed");
    reviewed.checked = true;
    reviewed.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(byId(element, "confirm").disabled).toBe(false);
    confirm.mockRejectedValueOnce({ body: { message: "CONFLICT" } });
    byId(element, "confirm").click();
    await flush();
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("c.AXF_SourceLink_codeCONFLICT");
    expect(byId(element, "confirm")).not.toBeNull();
    const firstKey = JSON.parse(confirm.mock.calls[0][0].request).operationKey;
    // CONFLICT refreshed the draft (candidates reloaded, suggestion restored, same key).
    expect(listCandidates).toHaveBeenCalledTimes(2);
    expect(byId(element, "changed")).toBeNull();
    const again = byId(element, "amount");
    again.value = "100";
    again.dispatchEvent(new CustomEvent("change"));
    await flush();
    const reviewedAgain = byId(element, "reviewed");
    reviewedAgain.checked = true;
    reviewedAgain.dispatchEvent(new CustomEvent("change"));
    await flush();
    confirm.mockResolvedValueOnce({
      allocationId: "a0E1",
      targetId: "a0C1",
      replayed: true,
      createdActualOnly: false,
      amount: 100,
      currencyIso: "BRL"
    });
    byId(element, "confirm").click();
    await flush();
    const second = JSON.parse(confirm.mock.calls[1][0].request);
    expect(second.operationKey).toBe(firstKey);
    expect(second).toMatchObject({ amount: 100, changesReviewed: true });
    expect(byId(element, "done").textContent).toContain(
      "c.AXF_SourceLink_doneReplayed"
    );
  });

  it("shows independent evidence per candidate with explicit ties and no automatic selection", async () => {
    const element = await mount();
    const later = {
      targetId: "a0C0",
      persisted: true,
      amount: 90,
      residual: 90,
      currencyIso: "BRL",
      direction: "DEBIT",
      dueDate: "2026-09-01",
      description: "Condominio",
      status: "PLANNED",
      version: 0,
      linkable: true,
      reasons: [],
      state: "CONSULTATIVE",
      evidence: evidence.map((v) => ({ ...v })),
      tied: false,
      lowEvidence: false
    };
    listSources.mockResolvedValue({
      pageNumber: 1,
      pageSize: 25,
      hasMore: false,
      scannedCount: 1,
      excludedCount: 0,
      items: [source]
    });
    listCandidates.mockResolvedValue({
      ...candidates,
      items: [candidates.items[0], later, candidates.items[1]]
    });
    byId(element, "holder").dispatchEvent(
      new CustomEvent("change", { detail: { value: "001A" } })
    );
    await flush();
    byId(element, "loadSources").click();
    await flush();
    element.shadowRoot.querySelector('[data-id="a0B1"]').click();
    await flush();
    expect(byId(element, "evidenceIntro").textContent).toContain(
      "c.AXF_SourceLink_evIntro"
    );
    expect(byId(element, "tieText").textContent).toContain(
      "c.AXF_SourceLink_evTieCount"
    );
    const cells = element.shadowRoot.querySelectorAll(
      '[data-id="evidenceCell"]'
    );
    expect(cells.length).toBe(3);
    const chips = cells[0].querySelectorAll("span.slds-badge");
    expect(chips.length).toBe(9);
    expect(chips[4].textContent).toContain("c.AXF_SourceLink_evfAMOUNT");
    expect(chips[4].textContent).toContain("c.AXF_SourceLink_evrDIFFERENT");
    expect(chips[4].getAttribute("title")).toContain("150.00 → 200.00");
    expect(
      chips[4].querySelector(".slds-assistive-text").textContent
    ).toContain("150.00 → 200.00");
    expect(byId(element, "evidenceCutoff").value).toBe(
      "2026-09-15T12:00:00.000Z"
    );
    expect(chips[6].getAttribute("title")).toContain(
      "c.AXF_SourceLink_evxDATE_AFTER"
    );
    expect(chips[8].getAttribute("title")).toContain(
      "c.AXF_SourceLink_evxREDACTED"
    );
    expect(chips[8].getAttribute("title")).not.toContain("→");
    const badges = cells[0].querySelectorAll("lightning-badge");
    expect(badges[0].label).toBe("c.AXF_SourceLink_evConsultative");
    expect(badges[1].label).toBe("c.AXF_SourceLink_evTied");
    expect(cells[2].querySelectorAll("lightning-badge")[1].label).toBe(
      "c.AXF_SourceLink_evLowEvidence"
    );
    // Nothing is pre-selected: the review step is reached only through an explicit click.
    expect(byId(element, "confirm")).toBeNull();
    expect(byId(element, "targetSummary")).toBeNull();
    byId(element, "sortMode").dispatchEvent(
      new CustomEvent("change", { detail: { value: "DUE_DATE" } })
    );
    await flush();
    const rows = element.shadowRoot.querySelectorAll(
      '[data-id="candidateTable"] tbody tr'
    );
    expect(rows.length).toBe(3);
    // Policy order: a0C1 (09-20), a0C0 (09-01, later record id), virtual (10-20). By due date: a0C0 first.
    expect(rows[0].textContent).toContain("Condominio");
    expect(rows[1].textContent).toContain("Aluguel set");
    // Selecting after the re-sort still resolves the clicked candidate.
    rows[0].querySelector("[data-index]").click();
    await flush();
    expect(byId(element, "targetSummary").textContent).toContain("Condominio");
    confirm.mockResolvedValue({
      allocationId: "a0E7",
      targetId: "a0C0",
      replayed: false,
      createdActualOnly: false,
      amount: 90,
      currencyIso: "BRL"
    });
    byId(element, "confirm").click();
    await flush();
    expect(JSON.parse(confirm.mock.calls[0][0].request).targetId).toBe("a0C0");
  });

  it("treats a date change as a reviewed change, filters by kind and pages without duplicates", async () => {
    const element = await mount();
    listSources
      .mockResolvedValueOnce({
        pageNumber: 1,
        pageSize: 25,
        hasMore: true,
        scannedCount: 2,
        excludedCount: 0,
        scanTruncated: true,
        maxScan: 200,
        items: [source]
      })
      .mockResolvedValueOnce({
        pageNumber: 2,
        pageSize: 25,
        hasMore: false,
        scannedCount: 2,
        excludedCount: 0,
        items: [source, { ...source, sourceId: "a0B2", description: "Luz" }]
      });
    listCandidates.mockResolvedValue(candidates);
    byId(element, "holder").dispatchEvent(
      new CustomEvent("change", { detail: { value: "001A" } })
    );
    byId(element, "kind").dispatchEvent(
      new CustomEvent("change", { detail: { value: "CARD" } })
    );
    await flush();
    byId(element, "loadSources").click();
    await flush();
    expect(JSON.parse(listSources.mock.calls[0][0].request)).toMatchObject({
      sourceKind: "CARD",
      pageNumber: 1
    });
    expect(byId(element, "excludedSources").textContent).toContain(
      "c.AXF_SourceLink_scanTruncated"
    );
    byId(element, "moreSources").click();
    await flush();
    expect(JSON.parse(listSources.mock.calls[1][0].request).pageNumber).toBe(2);
    expect(
      element.shadowRoot.querySelectorAll('[data-id="sourceTable"] tbody tr')
        .length
    ).toBe(2);
    element.shadowRoot.querySelector('[data-id="a0B1"]').click();
    await flush();
    element.shadowRoot.querySelector('[data-index="0"]').click();
    await flush();
    const date = byId(element, "recognitionDate");
    date.value = "2026-09-15";
    date.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(byId(element, "changed")).not.toBeNull();
    expect(byId(element, "confirm").disabled).toBe(true);
    const amount = byId(element, "amount");
    amount.value = "10.005";
    amount.dispatchEvent(new CustomEvent("change"));
    await flush();
    const reviewed = byId(element, "reviewed");
    reviewed.checked = true;
    reviewed.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(byId(element, "confirm").disabled).toBe(true);
  });

  it("offers the no-forecast path and hides everything without the capability", async () => {
    const element = await mount();
    listSources.mockResolvedValue({
      pageNumber: 1,
      pageSize: 25,
      hasMore: false,
      scannedCount: 1,
      excludedCount: 0,
      items: [source]
    });
    listCandidates.mockResolvedValue({
      ...candidates,
      items: [],
      virtualCount: 0,
      excludedCount: 0
    });
    byId(element, "holder").dispatchEvent(
      new CustomEvent("change", { detail: { value: "001A" } })
    );
    await flush();
    byId(element, "loadSources").click();
    await flush();
    element.shadowRoot.querySelector('[data-id="a0B1"]').click();
    await flush();
    expect(byId(element, "noCandidates")).not.toBeNull();
    byId(element, "noForecast").click();
    await flush();
    expect(byId(element, "targetSummary").textContent).toContain(
      "c.AXF_SourceLink_targetNone"
    );
    confirm.mockResolvedValue({
      allocationId: "a0E2",
      targetId: "a0C9",
      replayed: false,
      createdActualOnly: true,
      amount: 150,
      currencyIso: "BRL"
    });
    byId(element, "confirm").click();
    await flush();
    expect(JSON.parse(confirm.mock.calls[0][0].request)).toMatchObject({
      targetId: null,
      targetVersion: null,
      amount: 150
    });
    expect(byId(element, "done").textContent).toContain(
      "c.AXF_SourceLink_doneActualOnly"
    );

    const denied = createElement("c-a-x-f-_-l-w-c-_source-link", {
      is: SourceLink
    });
    document.body.appendChild(denied);
    getContext.emit({ ...context, canLink: false, holders: [] });
    await flush();
    expect(
      denied.shadowRoot.querySelector('[role="status"]').textContent
    ).toContain("c.AXF_SourceLink_noCapability");
    expect(byId(denied, "holder")).toBeNull();
  });

  it("renders the server state, the separated conversion evidence and the explicit remainder", async () => {
    const element = await mount();
    const partial = {
      ...candidates.items[0],
      residual: 100.01,
      residualAfter: 0.01,
      state: "PARTIAL",
      linkable: true,
      conversion: undefined
    };
    const foreign = {
      ...candidates.items[0],
      targetId: "a0C2",
      amount: 100,
      residual: 100,
      currencyIso: "EUR",
      residualAfter: null,
      state: "BLOCKED",
      reasons: ["CURRENCY_MISMATCH"],
      linkable: false,
      conversion: {
        state: "UNAVAILABLE",
        originalAmount: 100,
        originalIso: "EUR",
        reportingIso: "BRL"
      }
    };
    const priced = {
      ...foreign,
      targetId: "a0C3",
      conversion: {
        state: "ESTIMATED",
        originalAmount: 100,
        originalIso: "USD",
        reportingIso: "BRL",
        rate: 5.05,
        provider: "BCB_PTAX",
        convertedAmount: 505
      }
    };
    const stale = {
      ...foreign,
      targetId: "a0C4",
      conversion: {
        state: "STALE",
        originalAmount: 100,
        originalIso: "GBP",
        reportingIso: "BRL",
        rate: 6.1,
        provider: "BCB_PTAX"
      }
    };
    const projected = {
      ...candidates.items[1],
      amount: 200,
      residual: 200,
      residualAfter: 50,
      reasons: ["MATERIALIZATION_REQUIRED"]
    };
    listSources.mockResolvedValue({
      pageNumber: 1,
      pageSize: 25,
      hasMore: false,
      scannedCount: 1,
      excludedCount: 0,
      items: [source]
    });
    listCandidates.mockResolvedValue({
      ...candidates,
      tieCount: 0,
      items: [partial, foreign, priced, stale, projected]
    });
    byId(element, "holder").dispatchEvent(
      new CustomEvent("change", { detail: { value: "001A" } })
    );
    await flush();
    byId(element, "loadSources").click();
    await flush();
    element.shadowRoot.querySelector('[data-id="a0B1"]').click();
    await flush();
    const rows = element.shadowRoot.querySelectorAll(
      '[data-id="candidateTable"] tbody tr'
    );
    expect(rows.length).toBe(5);
    // The state comes from the server: a non-zero remainder is PARTIAL, a blocked candidate is
    // never presented as consultative, and no raw server token reaches the user.
    expect(
      rows[0].querySelector('[data-id="evidenceCell"] lightning-badge').label
    ).toBe("c.AXF_SourceLink_evPartial");
    expect(
      rows[1].querySelector('[data-id="evidenceCell"] lightning-badge').label
    ).toBe("c.AXF_SourceLink_evBlocked");
    // A blocked candidate offers no draft allocation at all, and it states why it is blocked.
    expect(rows[0].querySelector("[data-index]")).not.toBeNull();
    for (const row of [rows[1], rows[2], rows[3]]) {
      expect(row.querySelector("[data-index]")).toBeNull();
    }
    expect(
      rows[1].querySelector('[data-id="candidateReasons"]').textContent
    ).toContain("c.AXF_SourceLink_codeCURRENCY_MISMATCH");
    expect(rows[0].querySelector('[data-id="candidateReasons"]')).toBeNull();
    // The remainder stays explicit: a non-zero residual is shown as it is, never zeroed.
    expect(
      rows[0].querySelector('[data-id="residualAfter"]').textContent
    ).toContain("c.AXF_SourceLink_factResidualAfter");
    expect(
      rows[0].querySelector('[data-id="residualAfter"]').textContent.trim()
    ).toBe("c.AXF_SourceLink_factResidualAfter 0.01 BRL");
    // A candidate without a rate states it, keeps its original amount and shows no remainder.
    expect(
      rows[1].querySelector('[data-id="conversion"]').textContent.trim()
    ).toBe("c.AXF_SourceLink_convUnavailableLine EUR/BRL");
    expect(rows[1].querySelector('[data-id="residualAfter"]')).toBeNull();
    // An indicative conversion names the original side, the rate, the provider and the result.
    expect(
      rows[2].querySelector('[data-id="conversion"]').textContent.trim()
    ).toBe(
      "c.AXF_SourceLink_convEstimatedLine 505 BRL · 1 USD = 5.05 BRL (BCB_PTAX)"
    );
    // A stale quote keeps the rate as a fact and never invents a converted amount.
    expect(
      rows[3].querySelector('[data-id="conversion"]').textContent.trim()
    ).toBe(
      "c.AXF_SourceLink_convStaleLine GBP/BRL · 1 GBP = 6.1 BRL (BCB_PTAX)"
    );
    // A projected occurrence is never left blank: it carries the same remainder fact and names what
    // it still needs before it can be linked.
    expect(
      rows[4].querySelector('[data-id="residualAfter"]').textContent.trim()
    ).toBe("c.AXF_SourceLink_factResidualAfter 50 BRL");
    expect(
      rows[4].querySelector('[data-id="candidateReasons"]').textContent
    ).toContain("c.AXF_SourceLink_codeMATERIALIZATION_REQUIRED");
    expect(
      rows[4].querySelector('[data-id="evidenceCell"] lightning-badge').label
    ).toBe("c.AXF_SourceLink_evConsultative");
  });
});
