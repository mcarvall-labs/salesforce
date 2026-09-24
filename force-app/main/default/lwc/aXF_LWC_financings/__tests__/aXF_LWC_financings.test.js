import { createElement } from "lwc";
import Financings from "c/aXF_LWC_financings";
import getContext from "@salesforce/apex/AXF_CLS_CTRL_Financings.getContext";
import listFinancings from "@salesforce/apex/AXF_CLS_CTRL_Financings.listFinancings";
import getDetail from "@salesforce/apex/AXF_CLS_CTRL_Financings.getDetail";
import previewSettlement from "@salesforce/apex/AXF_CLS_CTRL_Financings.previewSettlement";
import editAmount from "@salesforce/apex/AXF_CLS_CTRL_Financings.editAmount";
import terminate from "@salesforce/apex/AXF_CLS_CTRL_Financings.terminate";
import settle from "@salesforce/apex/AXF_CLS_CTRL_Financings.settle";

const mockNavigate = jest.fn();
jest.mock("lightning/navigation", () => {
  const Navigate = Symbol("Navigate");
  const NavigationMixin = (Base) =>
    class extends Base {
      [Navigate](pageRef) {
        mockNavigate(pageRef);
      }
    };
  NavigationMixin.Navigate = Navigate;
  return { NavigationMixin };
});
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Financings.getContext",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Financings.listFinancings",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Financings.getDetail",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Financings.previewSettlement",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Financings.editAmount",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Financings.terminate",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Financings.settle",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

function isoOffset(days) {
  const d = new Date();
  d.setDate(d.getDate() + days);
  const pad = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

const PRICE = {
  scheduleId: "a0S000000000001",
  legacy: false,
  holderLabel: "Ana",
  description: "Carro",
  method: "PRICE",
  currencyIsoCode: "BRL",
  principal: 12000,
  totalInstallments: 12,
  paidCount: 3,
  nextDueDate: isoOffset(10),
  nextAmount: 1066.19,
  outstandingBalance: 9160.73,
  state: "ACTIVE",
  lastDueDate: isoOffset(300),
  version: 2,
  canEdit: false,
  canChange: true
};
const INSTALLMENT = {
  ...PRICE,
  scheduleId: "a0S000000000002",
  description: "Geladeira",
  method: "INSTALLMENT",
  totalInstallments: 10,
  paidCount: 4,
  nextAmount: 100,
  outstandingBalance: 600,
  canEdit: true,
  version: 0
};
const LEGACY = {
  scheduleId: null,
  legacyKey: "sch-legacy",
  legacy: true,
  holderLabel: "Ana",
  description: null,
  method: "SAC",
  currencyIsoCode: "BRL",
  totalInstallments: 4,
  paidCount: 1,
  outstandingBalance: 900,
  state: "ACTIVE",
  canEdit: false,
  canChange: false
};
const SETTLED = {
  ...PRICE,
  scheduleId: "a0S000000000003",
  description: "Moto",
  state: "SETTLED",
  outstandingBalance: 0,
  nextDueDate: null,
  nextAmount: null,
  canChange: false
};

const flush = async () => {
  for (let i = 0; i < 6; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};

function build() {
  const el = createElement("c-axf-lwc-financings", { is: Financings });
  document.body.appendChild(el);
  return el;
}

function row(el, key) {
  return el.shadowRoot.querySelector(`[data-financing-row="${key}"]`);
}

function action(scope, name) {
  return scope.querySelector(`[data-action="${name}"]`);
}

function setValue(el, selector, value) {
  const input = el.shadowRoot.querySelector(selector);
  input.value = value;
  input.dispatchEvent(new CustomEvent("change", { detail: { value } }));
}

async function load(el, context, rows) {
  listFinancings.mockResolvedValue(rows);
  getContext.emit(context);
  await flush();
}

describe("c-axf-lwc-financings", () => {
  beforeEach(() => {
    window.requestAnimationFrame = (cb) => cb();
  });
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("lists financings with progress, balance, state and read-only legacy plans", async () => {
    const el = build();
    await load(el, { canUse: true, canManage: true }, [
      PRICE,
      INSTALLMENT,
      LEGACY,
      SETTLED
    ]);

    const price = row(el, PRICE.scheduleId);
    expect(price.querySelector("[data-progress]").textContent).toContain(
      "AXF_Financings_progress"
    );
    expect(price.querySelector("[data-method]").textContent).toContain(
      "AXF_Financings_methodPRICE"
    );
    expect(
      price.querySelector("[data-balance] lightning-formatted-number").value
    ).toBe(9160.73);
    expect(action(price, "settle")).not.toBeNull();
    expect(action(price, "end")).not.toBeNull();
    expect(action(price, "edit")).toBeNull();
    expect(action(row(el, INSTALLMENT.scheduleId), "edit")).not.toBeNull();

    const legacy = row(el, "legacy:sch-legacy");
    expect(legacy.querySelector("[data-legacy]")).not.toBeNull();
    expect(action(legacy, "settle")).toBeNull();
    expect(action(legacy, "view")).not.toBeNull();

    const settled = row(el, SETTLED.scheduleId);
    expect(settled.querySelector("[data-state]").textContent).toContain(
      "AXF_Financings_stateSETTLED"
    );
    expect(action(settled, "end")).toBeNull();
  });

  it("opens the planner for a new financing", async () => {
    const el = build();
    await load(el, { canUse: true, canManage: true }, []);
    expect(el.shadowRoot.querySelector("[data-empty]")).not.toBeNull();
    el.shadowRoot.querySelector("[data-new]").click();
    expect(mockNavigate).toHaveBeenCalledWith({
      type: "standard__navItemPage",
      attributes: { apiName: "AXF_ScheduleWizard" }
    });
  });

  it("is read-only without the management capability", async () => {
    const el = build();
    await load(el, { canUse: true, canManage: false }, [
      { ...PRICE, canChange: true, canEdit: true }
    ]);
    expect(el.shadowRoot.querySelector("[data-read-only]")).not.toBeNull();
    expect(el.shadowRoot.querySelector("[data-new]")).toBeNull();
    const price = row(el, PRICE.scheduleId);
    expect(action(price, "settle")).toBeNull();
    expect(action(price, "edit")).toBeNull();
  });

  it("shows the installments with their status, including projected ones", async () => {
    getDetail.mockResolvedValue({
      financing: PRICE,
      truncated: false,
      unverified: true,
      installments: [
        {
          transactionId: "a0T1",
          sequence: 1,
          dueDate: "2026-09-01",
          amount: 1066.19,
          interestPortion: 120,
          principalPortion: 946.19,
          closingBalance: 11053.81,
          status: "PAID",
          projected: false
        },
        {
          transactionId: null,
          sequence: 13,
          dueDate: "2027-09-01",
          amount: 1066.19,
          interestPortion: null,
          principalPortion: null,
          closingBalance: null,
          status: "PLANNED",
          projected: true
        }
      ]
    });
    const el = build();
    await load(el, { canUse: true, canManage: true }, [PRICE, LEGACY]);
    action(row(el, PRICE.scheduleId), "view").click();
    await flush();

    expect(getDetail).toHaveBeenCalledWith({
      request: JSON.stringify({ scheduleId: PRICE.scheduleId })
    });
    const statuses = [
      ...el.shadowRoot.querySelectorAll("[data-installment-status]")
    ].map((cell) => cell.textContent);
    expect(statuses[0]).toContain("AXF_Financings_instPAID");
    expect(statuses[1]).toContain("AXF_Financings_instPLANNED");
    expect(el.shadowRoot.querySelectorAll("[data-projected]").length).toBe(1);
    expect(el.shadowRoot.querySelector("[data-unverified]")).not.toBeNull();

    action(el.shadowRoot, "close-detail").click();
    await flush();
    expect(el.shadowRoot.querySelector("[data-detail]")).toBeNull();

    getDetail.mockResolvedValue({ financing: LEGACY, installments: [] });
    action(row(el, "legacy:sch-legacy"), "view").click();
    await flush();
    expect(getDetail).toHaveBeenLastCalledWith({
      request: JSON.stringify({ legacyKey: "sch-legacy" })
    });
    expect(
      el.shadowRoot.querySelector("[data-no-installments]")
    ).not.toBeNull();
  });

  it("edits the installment amount with an idempotency key and the version", async () => {
    editAmount.mockResolvedValue({ changedCount: 6, protectedCount: 0 });
    const el = build();
    await load(el, { canUse: true, canManage: true }, [INSTALLMENT]);
    action(row(el, INSTALLMENT.scheduleId), "edit").click();
    await flush();
    setValue(el, "[data-edit-amount]", "abc");
    action(el.shadowRoot, "save-amount").click();
    await flush();
    expect(editAmount).not.toHaveBeenCalled();
    expect(el.shadowRoot.querySelector("[data-message]").textContent).toContain(
      "AXF_Financings_codeINVALID_INPUT"
    );

    setValue(el, "[data-edit-amount]", "120");
    action(el.shadowRoot, "save-amount").click();
    await flush();
    const request = JSON.parse(editAmount.mock.calls[0][0].request);
    expect(request).toMatchObject({
      scheduleId: INSTALLMENT.scheduleId,
      amount: 120,
      expectedVersion: 0
    });
    expect(request.operationKey).toBeTruthy();
    expect(listFinancings).toHaveBeenCalledTimes(2);
  });

  it("cancels a financing inside the allowed date window", async () => {
    terminate.mockResolvedValue({ changedCount: 8, protectedCount: 1 });
    const el = build();
    await load(el, { canUse: true, canManage: true }, [PRICE]);
    action(row(el, PRICE.scheduleId), "end").click();
    await flush();
    setValue(el, "[data-end-date]", isoOffset(-1));
    action(el.shadowRoot, "confirm-end").click();
    await flush();
    expect(terminate).not.toHaveBeenCalled();

    setValue(el, "[data-end-date]", isoOffset(0));
    action(el.shadowRoot, "confirm-end").click();
    await flush();
    const request = JSON.parse(terminate.mock.calls[0][0].request);
    expect(request.terminationDate).toBe(isoOffset(0));
    expect(request.expectedVersion).toBe(2);
  });

  it("previews and confirms an early payoff with an adjusted amount", async () => {
    previewSettlement.mockResolvedValue({
      scheduleId: PRICE.scheduleId,
      suggestedAmount: 9160.73,
      minDate: isoOffset(0),
      maxDate: isoOffset(10),
      currencyIsoCode: "BRL",
      version: 2
    });
    settle.mockResolvedValue({
      changedCount: 9,
      protectedCount: 0,
      settlementTransactionId: "a0T9"
    });
    const el = build();
    await load(el, { canUse: true, canManage: true }, [PRICE]);
    action(row(el, PRICE.scheduleId), "settle").click();
    await flush();

    expect(el.shadowRoot.querySelector("[data-settle-amount]").value).toBe(
      9160.73
    );
    setValue(el, "[data-settle-date]", isoOffset(20));
    action(el.shadowRoot, "confirm-settle").click();
    await flush();
    expect(settle).not.toHaveBeenCalled();

    previewSettlement.mockResolvedValueOnce({
      scheduleId: PRICE.scheduleId,
      suggestedAmount: 8100.2,
      minDate: isoOffset(0),
      maxDate: isoOffset(10),
      settlementDate: isoOffset(5),
      currencyIsoCode: "BRL",
      version: 2
    });
    setValue(el, "[data-settle-date]", isoOffset(5));
    await flush();
    expect(
      JSON.parse(previewSettlement.mock.calls[1][0].request)
    ).toMatchObject({
      scheduleId: PRICE.scheduleId,
      settlementDate: isoOffset(5)
    });
    expect(el.shadowRoot.querySelector("[data-settle-amount]").value).toBe(
      8100.2
    );
    setValue(el, "[data-settle-amount]", "9000.5");
    action(el.shadowRoot, "confirm-settle").click();
    await flush();
    const request = JSON.parse(settle.mock.calls[0][0].request);
    expect(request).toMatchObject({
      scheduleId: PRICE.scheduleId,
      amount: 9000.5,
      settlementDate: isoOffset(5),
      expectedVersion: 2
    });
    expect(el.shadowRoot.querySelector("[data-message]").textContent).toContain(
      "AXF_Financings_settled"
    );
  });

  it("reloads after a conflict and maps failure codes to labels", async () => {
    terminate.mockRejectedValue({ body: { message: "CONFLICT" } });
    const el = build();
    await load(el, { canUse: true, canManage: true }, [PRICE]);
    action(row(el, PRICE.scheduleId), "end").click();
    await flush();
    action(el.shadowRoot, "confirm-end").click();
    await flush();
    expect(el.shadowRoot.querySelector("[data-message]").textContent).toContain(
      "AXF_Financings_codeCONFLICT"
    );
    expect(listFinancings).toHaveBeenCalledTimes(2);
    expect(el.shadowRoot.querySelector("[data-end-date]")).toBeNull();
  });

  it("reports a load failure and a missing capability", async () => {
    listFinancings.mockRejectedValue({ body: { message: "SOMETHING" } });
    const el = build();
    getContext.emit({ canUse: true, canManage: false });
    await flush();
    expect(el.shadowRoot.querySelector("[data-error]").textContent).toContain(
      "AXF_Financings_error"
    );

    const other = build();
    getContext.emit({ canUse: false, canManage: false });
    await flush();
    expect(
      other.shadowRoot.querySelector("[data-no-capability]")
    ).not.toBeNull();

    const failed = build();
    getContext.error();
    await flush();
    expect(failed.shadowRoot.querySelector("[data-error]")).not.toBeNull();
  });
});
