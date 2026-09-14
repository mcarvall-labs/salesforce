import { createElement } from "lwc";
import ClosureRun, {
  failureMessage,
  stageLabel,
  actionLabel
} from "c/aXF_LWC_closureRun";
import canClose from "@salesforce/apex/AXF_CLS_CTRL_ClosureRun.canClose";
import getHolders from "@salesforce/apex/AXF_CLS_CTRL_ClosureRun.getHolders";
import listRuns from "@salesforce/apex/AXF_CLS_CTRL_ClosureRun.listRuns";
import request from "@salesforce/apex/AXF_CLS_CTRL_ClosureRun.request";
import advance from "@salesforce/apex/AXF_CLS_CTRL_ClosureRun.advance";
import reconcile from "@salesforce/apex/AXF_CLS_CTRL_ClosureRun.reconcile";
import attachExportEvidence from "@salesforce/apex/AXF_CLS_CTRL_ClosureRun.attachExportEvidence";
import read from "@salesforce/apex/AXF_CLS_CTRL_ClosureRun.read";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ClosureRun.canClose",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ClosureRun.getHolders",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ClosureRun.listRuns",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ClosureRun.request",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ClosureRun.advance",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ClosureRun.reconcile",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ClosureRun.attachExportEvidence",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ClosureRun.read",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = async () => {
  for (let i = 0; i < 6; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};

const blocked = {
  runId: "clr1",
  name: "CLR-000001",
  accountName: "Empresa A",
  status: "BLOCKED",
  lastCompletedStage: "NONE",
  progressPercent: 0,
  correlationId: "closure-abc",
  attempt: 1,
  blockReason: "EXPORT_PENDING",
  nextAction: "ATTACH_EXPORT_EVIDENCE",
  externalRevocation: "NOT_APPLICABLE",
  version: 2,
  closed: false,
  canAdvance: true,
  canReconcile: false,
  checkpoints: [
    {
      stage: "EXPORT",
      status: "BLOCKED",
      attempt: 1,
      effectKey: "EXPORT:1",
      reason: "EXPORT_PENDING",
      impact: {}
    }
  ]
};

function build() {
  const element = createElement("c-a-x-f_-l-w-c_closure-run", {
    is: ClosureRun
  });
  document.body.appendChild(element);
  canClose.emit(true);
  getHolders.emit([{ accountId: "001A", label: "Empresa A" }]);
  return element;
}

describe("c-aXF_LWC_closureRun", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("requests a closure for the selected holder and shows the blocked state with next action", async () => {
    listRuns.mockResolvedValue([]);
    request.mockResolvedValue(blocked);
    const element = build();
    await flush();
    expect(
      element.shadowRoot.querySelector('[data-id="no-runs"]')
    ).not.toBeNull();
    element.shadowRoot
      .querySelector('[data-id="holder"]')
      .dispatchEvent(new CustomEvent("change", { detail: { value: "001A" } }));
    await flush();
    element.shadowRoot.querySelector('[data-id="start"]').click();
    await flush();
    expect(request).toHaveBeenCalledWith({
      accountId: "001A",
      legalHold: false
    });
    expect(
      element.shadowRoot.querySelector('[data-id="status"]').textContent
    ).toBe("BLOCKED");
    expect(
      element.shadowRoot.querySelector('[data-id="blocked"]')
    ).not.toBeNull();
    expect(
      element.shadowRoot.querySelector('[data-id="next-action"]').textContent
    ).toBe(actionLabel("ATTACH_EXPORT_EVIDENCE"));
    expect(element.shadowRoot.querySelectorAll("tbody tr").length).toBe(1);
    expect(element.shadowRoot.textContent).toContain(stageLabel("EXPORT"));
  });

  it("attaches export evidence, resumes and reconciles an unknown result", async () => {
    listRuns.mockResolvedValue([blocked]);
    read.mockResolvedValue(blocked);
    attachExportEvidence.mockResolvedValue({
      ...blocked,
      status: "REQUESTED",
      blockReason: null
    });
    advance.mockResolvedValue({
      ...blocked,
      status: "RESULT_UNKNOWN",
      canAdvance: false,
      canReconcile: true,
      blockReason: "RESULT_UNKNOWN",
      nextAction: "RECONCILE"
    });
    reconcile.mockResolvedValue({ ...blocked, status: "REQUESTED" });
    const element = build();
    await flush();
    [...element.shadowRoot.querySelectorAll("lightning-button")]
      .find((button) => button.dataset.id === "clr1")
      .click();
    await flush();
    const evidence = element.shadowRoot.querySelector('[data-id="evidence"]');
    evidence.value = "069x";
    evidence.dispatchEvent(new CustomEvent("change"));
    await flush();
    element.shadowRoot.querySelector('[data-id="attach"]').click();
    await flush();
    expect(attachExportEvidence).toHaveBeenCalledWith({
      runId: "clr1",
      evidenceRef: "069x",
      expectedVersion: 2
    });
    element.shadowRoot.querySelector('[data-id="advance"]').click();
    await flush();
    expect(advance).toHaveBeenCalledWith({ runId: "clr1", expectedVersion: 2 });
    expect(
      element.shadowRoot.querySelector('[data-id="unknown"]')
    ).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="advance"]')).toBeNull();
    element.shadowRoot.querySelector('[data-id="reconcile"]').click();
    await flush();
    expect(reconcile).toHaveBeenCalled();
    expect(
      element.shadowRoot.querySelector('[data-id="status"]').textContent
    ).toBe("REQUESTED");
  });

  it("shows sanitized errors and the closed banner", async () => {
    listRuns.mockResolvedValue([blocked]);
    read.mockRejectedValueOnce({ body: { message: "NOT_ACCESSIBLE" } });
    const element = build();
    await flush();
    [...element.shadowRoot.querySelectorAll("lightning-button")]
      .find((button) => button.dataset.id === "clr1")
      .click();
    await flush();
    expect(
      element.shadowRoot.querySelector('[data-id="error"]').textContent
    ).toBe(failureMessage({ body: { message: "NOT_ACCESSIBLE" } }));
    read.mockResolvedValueOnce({
      ...blocked,
      status: "CLOSED",
      closed: true,
      canAdvance: false,
      progressPercent: 100,
      lastCompletedStage: "RETAIN_EVIDENCE",
      blockReason: null,
      nextAction: "NONE"
    });
    [...element.shadowRoot.querySelectorAll("lightning-button")]
      .find((button) => button.dataset.id === "clr1")
      .click();
    await flush();
    expect(
      element.shadowRoot.querySelector('[data-id="closed"]')
    ).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="advance"]')).toBeNull();
    expect(failureMessage({ body: { message: "???" } })).toBe(
      failureMessage({})
    );
  });
});
