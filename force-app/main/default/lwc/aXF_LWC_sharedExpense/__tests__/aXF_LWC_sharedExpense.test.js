import { createElement } from "lwc";
import SharedExpense, { failureMessage } from "c/aXF_LWC_sharedExpense";
import getCapabilities from "@salesforce/apex/AXF_CLS_CTRL_SharedExpense.getCapabilities";
import getCollaborators from "@salesforce/apex/AXF_CLS_CTRL_SharedExpense.getCollaborators";
import getGrants from "@salesforce/apex/AXF_CLS_CTRL_SharedExpense.getGrants";
import share from "@salesforce/apex/AXF_CLS_CTRL_SharedExpense.share";
import revoke from "@salesforce/apex/AXF_CLS_CTRL_SharedExpense.revoke";
import listShared from "@salesforce/apex/AXF_CLS_CTRL_SharedExpense.listShared";
import readShared from "@salesforce/apex/AXF_CLS_CTRL_SharedExpense.readShared";
import updateShared from "@salesforce/apex/AXF_CLS_CTRL_SharedExpense.updateShared";
import confirmRealization from "@salesforce/apex/AXF_CLS_CTRL_SharedExpense.confirmRealization";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_SharedExpense.getCapabilities",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_SharedExpense.getCollaborators",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_SharedExpense.getGrants",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_SharedExpense.share",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_SharedExpense.revoke",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_SharedExpense.listShared",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_SharedExpense.readShared",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_SharedExpense.updateShared",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_SharedExpense.confirmRealization",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = async () => {
  for (let i = 0; i < 6; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};

function build(recordId) {
  const element = createElement("c-a-x-f_-l-w-c_shared-expense", {
    is: SharedExpense
  });
  if (recordId) element.recordId = recordId;
  document.body.appendChild(element);
  return element;
}

const shared = [
  {
    financialTransactionId: "ftx1",
    name: "FTX-1",
    description: "Internet",
    userCategory: "Office",
    amount: 120,
    currencyIso: "BRL",
    dueDate: "2026-09-20",
    status: "PLANNED",
    version: 0,
    permission: "EDIT",
    canEdit: true,
    canRealize: true
  }
];

describe("c-aXF_LWC_sharedExpense", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("owner mode lists grants, shares and revokes with version", async () => {
    getGrants.mockResolvedValueOnce([]).mockResolvedValue([
      {
        grantId: "seg1",
        collaboratorId: "005A",
        collaboratorName: "Ana",
        permission: "VIEW",
        status: "ACTIVE",
        version: 1
      }
    ]);
    share.mockResolvedValue({});
    revoke.mockResolvedValue({});
    const element = build("a0X1");
    getCapabilities.emit({ canShare: true, canCollaborate: false });
    getCollaborators.emit([{ userId: "005A", name: "Ana" }]);
    await flush();
    expect(
      element.shadowRoot.querySelector('[data-id="no-grants"]')
    ).not.toBeNull();
    const combo = element.shadowRoot.querySelector('[data-id="collaborator"]');
    combo.dispatchEvent(
      new CustomEvent("change", { detail: { value: "005A" } })
    );
    await flush();
    element.shadowRoot.querySelector('[data-id="share"]').click();
    await flush();
    const request = JSON.parse(share.mock.calls[0][0].request);
    expect(request).toMatchObject({
      financialTransactionId: "a0X1",
      collaboratorId: "005A",
      permission: "VIEW"
    });
    expect(request.clientRequestId).toMatch(/^[0-9a-f-]{36}$/);
    expect(
      element.shadowRoot.querySelector('[data-id="success"]')
    ).not.toBeNull();
    const revokeButton = [
      ...element.shadowRoot.querySelectorAll("lightning-button")
    ].find((button) => button.dataset.id === "seg1");
    revokeButton.click();
    await flush();
    expect(revoke).toHaveBeenCalledWith({
      grantId: "seg1",
      expectedVersion: 1
    });
  });

  it("collaborator opens a shared expense, confirms before saving and sends only permitted fields", async () => {
    listShared.mockResolvedValue(shared);
    readShared.mockResolvedValue(shared[0]);
    updateShared.mockResolvedValue({
      ...shared[0],
      description: "Internet + phone",
      version: 1
    });
    const element = build();
    getCapabilities.emit({ canShare: false, canCollaborate: true });
    await flush();
    const open = [
      ...element.shadowRoot.querySelectorAll("lightning-button")
    ].find((button) => button.dataset.id === "ftx1");
    open.click();
    await flush();
    expect(
      element.shadowRoot.querySelector('[data-id="detail-title"]').textContent
    ).toContain("FTX-1");
    expect(element.shadowRoot.textContent).not.toContain("Account");
    const description = element.shadowRoot.querySelector(
      '[data-id="description"]'
    );
    description.value = "Internet + phone";
    description.dispatchEvent(new CustomEvent("change"));
    element.shadowRoot.querySelector('[data-id="save"]').click();
    await flush();
    expect(updateShared).not.toHaveBeenCalled();
    const dialog = element.shadowRoot.querySelector('[data-id="confirmation"]');
    expect(dialog.getAttribute("role")).toBe("dialog");
    expect(dialog.textContent).toContain("confirmBody");
    element.shadowRoot.querySelector('[data-id="confirm-yes"]').click();
    await flush();
    const request = JSON.parse(updateShared.mock.calls[0][0].request);
    expect(Object.keys(request).sort()).toEqual([
      "clientRequestId",
      "description",
      "expectedVersion",
      "financialTransactionId",
      "userCategory"
    ]);
    expect(request.expectedVersion).toBe(0);
    expect(
      element.shadowRoot.querySelector('[data-id="success"]')
    ).not.toBeNull();
  });

  it("collaborator with view-only access cannot edit and sees sanitized errors", async () => {
    listShared.mockResolvedValue([
      { ...shared[0], permission: "VIEW", canEdit: false, canRealize: false }
    ]);
    readShared.mockResolvedValue({
      ...shared[0],
      permission: "VIEW",
      canEdit: false,
      canRealize: false
    });
    const element = build();
    getCapabilities.emit({ canShare: false, canCollaborate: true });
    await flush();
    [...element.shadowRoot.querySelectorAll("lightning-button")]
      .find((button) => button.dataset.id === "ftx1")
      .click();
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="save"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="realize"]')).toBeNull();
    expect(
      element.shadowRoot.querySelector('[data-id="description"]').disabled
    ).toBe(true);
    readShared.mockRejectedValue({ body: { message: "NOT_ACCESSIBLE" } });
    element.shadowRoot.querySelector('[data-id="back"]').click();
    await flush();
    [...element.shadowRoot.querySelectorAll("lightning-button")]
      .find((button) => button.dataset.id === "ftx1")
      .click();
    await flush();
    expect(
      element.shadowRoot.querySelector('[data-id="error"]').textContent
    ).toBe(failureMessage({ body: { message: "NOT_ACCESSIBLE" } }));
    expect(failureMessage({ body: { message: "???" } })).toBe(
      failureMessage({})
    );
  });

  it("collaborator confirms realization through the confirmation dialog", async () => {
    listShared.mockResolvedValue(shared);
    readShared.mockResolvedValue(shared[0]);
    confirmRealization.mockResolvedValue("ra1");
    const element = build();
    getCapabilities.emit({ canShare: false, canCollaborate: true });
    await flush();
    [...element.shadowRoot.querySelectorAll("lightning-button")]
      .find((button) => button.dataset.id === "ftx1")
      .click();
    await flush();
    element.shadowRoot.querySelector('[data-id="realize"]').click();
    await flush();
    element.shadowRoot.querySelector('[data-id="confirm-yes"]').click();
    await flush();
    const request = JSON.parse(confirmRealization.mock.calls[0][0].request);
    expect(request.amount).toBe(120);
    expect(request.financialTransactionId).toBe("ftx1");
    expect(readShared).toHaveBeenCalledTimes(2);
  });
});
