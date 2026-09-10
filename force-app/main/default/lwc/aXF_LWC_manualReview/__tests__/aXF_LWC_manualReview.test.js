import { createElement } from "lwc";
import Review from "c/aXF_LWC_manualReview";
import listPending from "@salesforce/apex/AXF_CLS_CTRL_ManualReview.listPending";
import confirm from "@salesforce/apex/AXF_CLS_CTRL_ManualReview.confirm";
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ManualReview.listPending",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ManualReview.confirm",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
const flush = async () => {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
};
const item = {
  reviewItemId: "a01000000000001",
  financialTransactionId: "a02000000000001",
  accountId: "001000000000001",
  version: 3,
  name: "RVI-1"
};
function build() {
  const el = createElement("c-manual-review", { is: Review });
  document.body.appendChild(el);
  return el;
}
afterEach(() => {
  while (document.body.firstChild)
    document.body.removeChild(document.body.firstChild);
  jest.clearAllMocks();
});
it("shows empty state", async () => {
  listPending.mockResolvedValue("[]");
  const el = build();
  await flush();
  expect(el.shadowRoot.textContent).toMatch(/Nenhuma|No pending/);
});
it("confirms using observed version and note", async () => {
  listPending.mockResolvedValue(JSON.stringify([item]));
  confirm.mockResolvedValue(JSON.stringify({ success: true }));
  const el = build();
  await flush();
  const note = el.shadowRoot.querySelector("lightning-textarea");
  note.value = "Checked receipt";
  note.dispatchEvent(new CustomEvent("change"));
  el.shadowRoot.querySelector("lightning-button[data-id]").click();
  await flush();
  expect(confirm).toHaveBeenCalledWith({
    itemId: item.reviewItemId,
    version: 3,
    note: "Checked receipt"
  });
  expect(el.shadowRoot.querySelector("section")).toBeNull();
});
it("keeps pending item after conflict", async () => {
  listPending.mockResolvedValue(JSON.stringify([item]));
  confirm.mockResolvedValue(JSON.stringify({ success: false }));
  const el = build();
  await flush();
  const note = el.shadowRoot.querySelector("lightning-textarea");
  note.value = "Checked";
  note.dispatchEvent(new CustomEvent("change"));
  el.shadowRoot.querySelector("lightning-button[data-id]").click();
  await flush();
  expect(el.shadowRoot.querySelector("section")).not.toBeNull();
});
it("requires a reason without submitting", async () => {
  listPending.mockResolvedValue(JSON.stringify([item]));
  const el = build();
  await flush();
  el.shadowRoot.querySelector("lightning-button[data-id]").click();
  await flush();
  expect(confirm).not.toHaveBeenCalled();
});
it("clears private rows when loading fails", async () => {
  listPending.mockRejectedValue(new Error("denied"));
  const el = build();
  await flush();
  expect(el.shadowRoot.querySelector("section")).toBeNull();
  expect(el.shadowRoot.textContent).toMatch(/Não foi possível|Unable/);
});
