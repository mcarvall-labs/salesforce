import { createElement } from "lwc";
import Realization from "c/aXF_LWC_realization";
import read from "@salesforce/apex/AXF_CLS_CTRL_Realization.read";
import apply from "@salesforce/apex/AXF_CLS_CTRL_Realization.apply";
import reverse from "@salesforce/apex/AXF_CLS_CTRL_Realization.reverse";
import retryFx from "@salesforce/apex/AXF_CLS_CTRL_Realization.retryFx";
import sourceVersion from "@salesforce/apex/AXF_CLS_CTRL_Realization.sourceVersion";
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Realization.read",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Realization.apply",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Realization.reverse",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Realization.retryFx",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Realization.sourceVersion",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
const flush = async () => {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
};
const state = {
  targetId: "target",
  version: 3,
  planned: 100,
  realized: 40,
  residual: 60,
  currencyIso: "USD",
  reportingAmount: null,
  pendingFx: true,
  allocations: [
    {
      Id: "allocation",
      Name: "RA-1",
      AXF_RA_PKL_Kind__c: "APPLICATION",
      AXF_RA_PKL_FxState__c: "PENDING_FX",
      AXF_RA_NUM_Magnitude__c: 40
    }
  ]
};
async function mount(data = state) {
  read.mockResolvedValue(JSON.stringify(data));
  const element = createElement("c-a-x-f-l-w-c-realization", {
    is: Realization
  });
  element.recordId = "target";
  document.body.appendChild(element);
  await flush();
  return element;
}
function button(element, suffix) {
  return [...element.shadowRoot.querySelectorAll("lightning-button")].find(
    (node) => node.label.endsWith(suffix)
  );
}
afterEach(() => {
  while (document.body.firstChild)
    document.body.removeChild(document.body.firstChild);
  jest.clearAllMocks();
});
test("shows pending FX without a converted total", async () => {
  const element = await mount();
  expect(element.shadowRoot.textContent).toContain("AXF_Realization_pending");
  expect(element.shadowRoot.textContent).not.toContain(
    "AXF_Realization_reporting:"
  );
});
test("failed refresh removes previously visible financial values", async () => {
  const element = await mount();
  read.mockRejectedValue(new Error("private detail"));
  button(element, "refresh").click();
  await flush();
  expect(element.shadowRoot.querySelector("dl")).toBeNull();
  expect(element.shadowRoot.textContent).not.toContain("private detail");
});
test("reversal sends the observed version and reuses its key after failure", async () => {
  const element = await mount();
  reverse.mockRejectedValue(new Error("network"));
  button(element, "reverse").click();
  await flush();
  const first = reverse.mock.calls[0][0];
  expect(first.expectedVersion).toBe(3);
  button(element, "reverse").click();
  await flush();
  expect(reverse.mock.calls[1][0].operationKey).toBe(first.operationKey);
});
test("FX recovery requests only the existing allocation", async () => {
  const element = await mount();
  retryFx.mockResolvedValue();
  button(element, "retry").click();
  await flush();
  expect(retryFx).toHaveBeenCalledWith({ allocationId: "allocation" });
  expect(apply).not.toHaveBeenCalled();
});
test("empty ledger is explicit", async () => {
  const element = await mount({ ...state, allocations: [] });
  expect(element.shadowRoot.textContent).toContain("AXF_Realization_empty");
});
test("source version is captured without a technical input", async () => {
  const element = await mount();
  const checkbox = [
    ...element.shadowRoot.querySelectorAll("lightning-input")
  ].find((node) => node.label.endsWith("existing"));
  checkbox.checked = true;
  checkbox.dispatchEvent(new CustomEvent("change"));
  await flush();
  sourceVersion.mockResolvedValue(7);
  const picker = element.shadowRoot.querySelector('[data-field="sourceId"]');
  picker.dispatchEvent(
    new CustomEvent("change", { detail: { recordId: "fact" } })
  );
  await flush();
  expect(sourceVersion).toHaveBeenCalledWith({
    sourceId: "fact",
    sourceKind: "CASH"
  });
  expect(
    element.shadowRoot.querySelector('[data-field="sourceVersion"]')
  ).toBeNull();
});

test("actual-only confirmation opens the new target and cannot repeat the old intent", async () => {
  read.mockResolvedValue(
    JSON.stringify({ ...state, targetId: "new-target", planned: 0 })
  );
  apply.mockResolvedValue({
    allocationId: "new-allocation",
    targetId: "new-target"
  });
  const element = createElement("c-a-x-f-l-w-c-realization", {
    is: Realization
  });
  document.body.appendChild(element);
  await flush();
  const mode = [...element.shadowRoot.querySelectorAll("lightning-input")].find(
    (node) => node.label.endsWith("actual")
  );
  mode.checked = true;
  mode.dispatchEvent(new CustomEvent("change"));
  await flush();
  element.shadowRoot
    .querySelector('[data-field="accountId"]')
    .dispatchEvent(
      new CustomEvent("change", { detail: { recordId: "holder" } })
    );
  element.shadowRoot
    .querySelector('[data-field="amount"]')
    .dispatchEvent(new CustomEvent("change", { detail: { value: "40" } }));
  await flush();
  for (const control of element.shadowRoot.querySelectorAll(
    "lightning-input,lightning-combobox,lightning-record-picker"
  ))
    control.reportValidity = jest.fn(() => true);
  button(element, "confirm").click();
  await flush();
  const request = JSON.parse(apply.mock.calls[0][0].request);
  expect(request.targetId).toBeNull();
  expect(request.accountId).toBe("holder");
  expect(request.amount).toBe(40);
  expect(read).toHaveBeenCalledWith({ targetId: "new-target" });
});
test("record pages load when recordId arrives after connection", async () => {
  read.mockResolvedValue(JSON.stringify(state));
  const element = createElement("c-a-x-f-l-w-c-realization", {
    is: Realization
  });
  document.body.appendChild(element);
  await flush();
  element.recordId = "late-target";
  await flush();
  expect(read).toHaveBeenCalledWith({ targetId: "late-target" });
});
