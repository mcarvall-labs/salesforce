import { createElement } from "lwc";
import InternalTransfer from "c/aXF_LWC_internalTransfer";
import getContext from "@salesforce/apex/AXF_CLS_CTRL_InternalTransfer.getContext";
import listPending from "@salesforce/apex/AXF_CLS_CTRL_InternalTransfer.listPending";
import confirmTransfer from "@salesforce/apex/AXF_CLS_CTRL_InternalTransfer.confirm";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_InternalTransfer.getContext",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_InternalTransfer.listPending",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_InternalTransfer.confirm",
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
  canConfirm: true,
  policyVersion: "AXF32-INTERNAL-TRANSFER@1.0.0",
  reasons: [
    "USER_ERROR",
    "DUPLICATE_LINK",
    "WRONG_TARGET",
    "SOURCE_CHANGED",
    "OTHER"
  ]
};

const pendingItem = {
  internalTransferId: "a0T1",
  reviewItemId: "a0R1",
  state: "CANDIDATE",
  version: 0,
  debit: {
    transactionId: "a0B1",
    description: "Transferencia enviada",
    amount: 175,
    currencyIso: "BRL",
    onDate: "2026-09-15",
    accountName: "Ana"
  },
  credit: {
    transactionId: "a0B2",
    description: "Transferencia recebida",
    amount: 175,
    currencyIso: "BRL",
    onDate: "2026-09-15",
    accountName: "Ana"
  }
};

function mount() {
  const element = createElement("c-a-x-f-_-l-w-c-_internal-transfer", {
    is: InternalTransfer
  });
  document.body.appendChild(element);
  return element;
}

afterEach(() => {
  while (document.body.firstChild) {
    document.body.removeChild(document.body.firstChild);
  }
  jest.clearAllMocks();
});

describe("c-aXF_LWC_internalTransfer", () => {
  it("shows the no-capability message when the user cannot confirm", async () => {
    const element = mount();
    getContext.emit({ ...context, canConfirm: false });
    await flush();
    expect(
      element.shadowRoot.querySelector('[role="status"]').textContent
    ).toBeTruthy();
    expect(listPending).not.toHaveBeenCalled();
  });

  it("loads pending suggestions and renders both legs", async () => {
    listPending.mockResolvedValue([pendingItem]);
    const element = mount();
    getContext.emit(context);
    await flush();
    expect(listPending).toHaveBeenCalled();
    const row = element.shadowRoot.querySelector('[data-id="row"]');
    expect(row).not.toBeNull();
    expect(row.textContent).toContain("Transferencia enviada");
    expect(row.textContent).toContain("Transferencia recebida");
  });

  it("confirms a pending suggestion and shows the result", async () => {
    listPending.mockResolvedValue([pendingItem]);
    confirmTransfer.mockResolvedValue({
      internalTransferId: "a0T1",
      state: "CONFIRMED",
      replayed: false
    });
    const element = mount();
    getContext.emit(context);
    await flush();

    const button = element.shadowRoot.querySelector('[data-id="confirm"]');
    button.click();
    await flush();

    expect(confirmTransfer).toHaveBeenCalledTimes(1);
    const call = JSON.parse(confirmTransfer.mock.calls[0][0].request);
    expect(call.internalTransferId).toBe("a0T1");
    expect(call.expectedVersion).toBe(0);
    expect(
      element.shadowRoot.querySelector('[data-id="result"]')
    ).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="confirm"]')).toBeNull();
  });

  it("shows a sanitized row error when confirmation fails", async () => {
    listPending.mockResolvedValue([pendingItem]);
    confirmTransfer.mockRejectedValue({ body: { message: "CONFLICT" } });
    const element = mount();
    getContext.emit(context);
    await flush();

    element.shadowRoot.querySelector('[data-id="confirm"]').click();
    await flush();

    expect(
      element.shadowRoot.querySelector('[data-id="rowError"]')
    ).not.toBeNull();
  });
});
