import { createElement } from "lwc";
import ArchiveExplorer from "c/aXF_LWC_archiveExplorer";
import getContext from "@salesforce/apex/AXF_CLS_CTRL_ArchiveExplorer.getContext";
import read from "@salesforce/apex/AXF_CLS_CTRL_ArchiveExplorer.read";
import startArchive from "@salesforce/apex/AXF_CLS_CTRL_ArchiveExplorer.startArchive";
import listRuns from "@salesforce/apex/AXF_CLS_CTRL_ArchiveExplorer.listRuns";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ArchiveExplorer.getContext",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ArchiveExplorer.read",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ArchiveExplorer.startArchive",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ArchiveExplorer.listRuns",
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
  canRead: true,
  canArchive: true,
  hotWindowStart: "2024-09-01",
  policyVersion: "archive-policy@1.0.0",
  holders: [{ accountId: "001A", name: "Ana" }]
};

function row(key, date) {
  return {
    archiveKey: key,
    family: "BAT",
    bookingDate: date,
    magnitude: 12.5,
    direction: "DEBIT",
    currencyIso: "BRL",
    status: "POSTED",
    description: "Mercado",
    institutionLabel: "Banco a",
    archived: true
  };
}

function build() {
  const element = createElement("c-a-x-f_-l-w-c_archive-explorer", {
    is: ArchiveExplorer
  });
  document.body.appendChild(element);
  return element;
}

async function selectHolder(element) {
  element.shadowRoot
    .querySelector('[data-id="holder"]')
    .dispatchEvent(new CustomEvent("change", { detail: { value: "001A" } }));
  await flush();
}

describe("c-aXF_LWC_archiveExplorer", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("reads archived rows asynchronously, badges them and paginates with the server cursor", async () => {
    listRuns.mockResolvedValue([]);
    read
      .mockResolvedValueOnce({
        rows: [row("k1", "2023-03-15"), row("k2", "2023-03-15")],
        hasMore: true,
        nextCursorDate: "2023-03-15",
        nextCursorKey: "k2"
      })
      .mockResolvedValueOnce({
        rows: [row("k3", "2023-03-14")],
        hasMore: false
      });
    const element = build();
    getContext.emit(context);
    await flush();
    // Label stubs carry no {0}; the hot-window sentence is rendered from the server date.
    expect(
      element.shadowRoot.querySelector('[data-id="hot-window"]').textContent
    ).toContain("hotWindow");
    expect(element.shadowRoot.querySelector('[data-id="from"]').max).toBe(
      "2024-08-31"
    );
    expect(element.shadowRoot.querySelector('[data-id="idle"]')).not.toBeNull();
    await selectHolder(element);
    element.shadowRoot.querySelector('[data-id="search"]').click();
    await flush();
    const first = JSON.parse(read.mock.calls[0][0].request);
    expect(first.accountId).toBe("001A");
    expect(first.cursorDate).toBeNull();
    expect(
      element.shadowRoot.querySelectorAll('[data-id="rows"] tbody tr').length
    ).toBe(2);
    expect(
      element.shadowRoot.querySelectorAll('[data-id="archived-badge"]').length
    ).toBe(2);
    expect(
      element.shadowRoot.querySelector('[data-id="read-only"]')
    ).not.toBeNull();
    element.shadowRoot.querySelector('[data-id="load-more"]').click();
    await flush();
    const second = JSON.parse(read.mock.calls[1][0].request);
    expect(second.cursorDate).toBe("2023-03-15");
    expect(second.cursorKey).toBe("k2");
    expect(
      element.shadowRoot.querySelectorAll('[data-id="rows"] tbody tr').length
    ).toBe(3);
    expect(
      element.shadowRoot.querySelector('[data-id="load-more"]')
    ).toBeNull();
  });

  it("shows an empty state, a sanitized error with retry and never edits rows", async () => {
    listRuns.mockResolvedValue([]);
    read
      .mockResolvedValueOnce({ rows: [], hasMore: false })
      .mockRejectedValueOnce({ body: { message: "NOT_ACCESSIBLE" } })
      .mockResolvedValueOnce({
        rows: [row("k1", "2023-01-02")],
        hasMore: false
      });
    const element = build();
    getContext.emit(context);
    await flush();
    await selectHolder(element);
    element.shadowRoot.querySelector('[data-id="search"]').click();
    await flush();
    expect(
      element.shadowRoot.querySelector('[data-id="empty"]')
    ).not.toBeNull();
    element.shadowRoot.querySelector('[data-id="search"]').click();
    await flush();
    const error = element.shadowRoot.querySelector('[data-id="error"]');
    expect(error.textContent).toContain("codeNotAccessible");
    element.shadowRoot.querySelector('[data-id="retry"]').click();
    await flush();
    expect(
      element.shadowRoot.querySelectorAll('[data-id="rows"] tbody tr').length
    ).toBe(1);
    expect(
      element.shadowRoot.querySelectorAll('[data-id="rows"] lightning-input')
        .length
    ).toBe(0);
  });

  it("starts the three family runs after confirmation and lists their phases", async () => {
    listRuns.mockResolvedValueOnce([]).mockResolvedValue([
      {
        runId: "a01",
        family: "BAT",
        phase: "HOT_RETAINED",
        scanned: 3,
        archived: 3,
        verified: 3,
        watermark: "2023-03-15",
        hotRemoval: "BLOCKED:HOT_REMOVAL_NOT_AUTHORIZED",
        lastCheckpointAt: "2026-09-15T00:00:00.000Z"
      }
    ]);
    startArchive.mockResolvedValue({ runId: "a01", phase: "SCANNING" });
    const element = build();
    getContext.emit(context);
    await flush();
    await selectHolder(element);
    expect(
      element.shadowRoot.querySelector('[data-id="no-runs"]')
    ).not.toBeNull();
    element.shadowRoot.querySelector('[data-id="start"]').click();
    await flush();
    expect(
      element.shadowRoot.querySelector('[data-id="confirm"]')
    ).not.toBeNull();
    element.shadowRoot.querySelector('[data-id="confirm-start"]').click();
    await flush();
    expect(startArchive).toHaveBeenCalledTimes(3);
    expect(startArchive.mock.calls.map((call) => call[0].family)).toEqual([
      "BAT",
      "CCT",
      "FTX"
    ]);
    const phase = element.shadowRoot.querySelector(
      '[data-run="a01"] [data-phase]'
    );
    expect(phase.dataset.phase).toBe("HOT_RETAINED");
    expect(
      element.shadowRoot.querySelector('[data-run="a01"]').textContent
    ).toContain("hotBlocked");
  });

  it("reports a failing family without hiding the others, refreshes the wire on retry and hides everything without capability", async () => {
    listRuns.mockResolvedValue([]);
    startArchive
      .mockResolvedValueOnce({ runId: "a01" })
      .mockRejectedValueOnce({ body: { message: "RUN_IN_PROGRESS" } })
      .mockResolvedValueOnce({ runId: "a03" });
    const element = build();
    getContext.emit(context);
    await flush();
    await selectHolder(element);
    element.shadowRoot.querySelector('[data-id="start"]').click();
    await flush();
    element.shadowRoot.querySelector('[data-id="confirm-cancel"]').click();
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="confirm"]')).toBeNull();
    expect(startArchive).not.toHaveBeenCalled();
    element.shadowRoot.querySelector('[data-id="start"]').click();
    await flush();
    element.shadowRoot.querySelector('[data-id="confirm-start"]').click();
    await flush();
    expect(startArchive).toHaveBeenCalledTimes(3);
    const runsError = element.shadowRoot.querySelector(
      '[data-id="runs-error"]'
    );
    expect(runsError.textContent).toContain("codeRunInProgress");
    expect(runsError.textContent).toContain("familyCCT");
    expect(element.shadowRoot.querySelector('[data-id="error"]')).toBeNull();

    const { refreshApex } = require("@salesforce/apex");
    const failing = build();
    getContext.error({ message: "FORBIDDEN" });
    await flush();
    expect(
      failing.shadowRoot.querySelector('[data-id="error"]').textContent
    ).toContain("codeForbidden");
    failing.shadowRoot.querySelector('[data-id="retry"]').click();
    await flush();
    expect(refreshApex).toHaveBeenCalled();

    const denied = build();
    getContext.emit({ ...context, canRead: false, canArchive: false });
    await flush();
    expect(denied.shadowRoot.querySelector("lightning-card")).toBeNull();
    expect(
      denied.shadowRoot.querySelector('[data-id="forbidden"]')
    ).not.toBeNull();

    const blocked = build();
    getContext.emit({
      ...context,
      hotWindowStart: null,
      policyVersion: "POLICY_MISSING"
    });
    await flush();
    expect(
      blocked.shadowRoot.querySelector('[data-id="policy-blocked"]')
    ).not.toBeNull();
  });

  it("hides the start button without the archive capability", async () => {
    listRuns.mockResolvedValue([]);
    const element = build();
    getContext.emit({ ...context, canArchive: false });
    await flush();
    await selectHolder(element);
    expect(element.shadowRoot.querySelector('[data-id="start"]')).toBeNull();
    expect(
      element.shadowRoot.querySelector('[data-id="search"]').disabled
    ).toBe(false);
  });
});
