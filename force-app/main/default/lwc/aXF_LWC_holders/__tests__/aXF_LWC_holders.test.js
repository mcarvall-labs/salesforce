import { createElement } from "lwc";
import AxfLwcHolders from "c/aXF_LWC_holders";
import canConfigure from "@salesforce/apex/AXF_CLS_CTRL_Holder.canConfigure";
import listHolders from "@salesforce/apex/AXF_CLS_CTRL_Holder.listHolders";
import saveHolder from "@salesforce/apex/AXF_CLS_CTRL_Holder.saveHolder";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Holder.canConfigure",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Holder.listHolders",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Holder.saveHolder",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Holder.getHolder",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const HOLDERS = [
  {
    accountId: "001x1",
    type: "BUSINESS",
    name: "Padaria AXF",
    firstName: null,
    lastName: null,
    isPersonAccount: false,
    ownerId: "005x1",
    ownerName: "Gestor",
    lastModifiedDate: "2026-08-31T12:00:00.000Z"
  }
];

function flush() {
  return Promise.resolve();
}

function build(canConfigureValue = false) {
  const el = createElement("c-a-x-f_-l-w-c_holders", { is: AxfLwcHolders });
  document.body.appendChild(el);
  canConfigure.emit(canConfigureValue);
  return el;
}

function byLabel(el, re) {
  return [...el.shadowRoot.querySelectorAll("lightning-button")].find((b) =>
    re.test(b.label)
  );
}

async function openCreateForm(el) {
  listHolders.emit([]);
  await flush();
  await flush();
  byLabel(el, /New holder|Novo titular/).click();
  await flush();
}

afterEach(() => {
  while (document.body.firstChild) {
    document.body.removeChild(document.body.firstChild);
  }
  jest.clearAllMocks();
});

describe("c-aXF_LWC_holders", () => {
  it("shows the datatable once holders arrive", async () => {
    const el = build(false);
    listHolders.emit(HOLDERS);
    await flush();

    const table = el.shadowRoot.querySelector("lightning-datatable");
    expect(table).not.toBeNull();
    expect(table.data).toHaveLength(1);
    expect(table.data[0].typeLabel).toBeDefined();
  });

  it("hides the New holder button without configure authority", async () => {
    const el = build(false);
    listHolders.emit([]);
    await flush();

    expect(byLabel(el, /New holder|Novo titular/)).toBeUndefined();
  });

  it("opens the create form when authorized", async () => {
    const el = build(true);
    await openCreateForm(el);

    expect(el.shadowRoot.querySelector("lightning-radio-group")).not.toBeNull();
    expect(
      el.shadowRoot.querySelector("[data-field='lastName']")
    ).not.toBeNull();
  });

  it("shows possible duplicates returned by the server and a confirm action", async () => {
    saveHolder.mockResolvedValue({
      outcome: "DUPLICATE_WARNING",
      possibleDuplicates: [
        { accountId: "001y", type: "PERSON", name: "Ana", ownerName: "G" }
      ]
    });
    const el = build(true);
    await openCreateForm(el);

    const lastName = el.shadowRoot.querySelector("[data-field='lastName']");
    lastName.dispatchEvent(
      new CustomEvent("change", { detail: { value: "Ana" } })
    );

    byLabel(el, /Save|Salvar/).click();
    await flush();
    await flush();

    expect(saveHolder).toHaveBeenCalled();
    expect(
      el.shadowRoot.querySelector("[role='alert']").textContent.trim().length
    ).toBeGreaterThan(0);
    expect(byLabel(el, /anyway|assim mesmo/i)).toBeDefined();
  });

  it("returns to the list on a successful save", async () => {
    saveHolder.mockResolvedValue({ outcome: "SUCCEEDED", accountId: "001z" });
    const el = build(true);
    await openCreateForm(el);

    el.shadowRoot
      .querySelector("[data-field='lastName']")
      .dispatchEvent(new CustomEvent("change", { detail: { value: "Braga" } }));

    byLabel(el, /Save|Salvar/).click();
    await flush();
    await flush();

    expect(el.shadowRoot.querySelector("lightning-radio-group")).toBeNull();
    expect(el.shadowRoot.querySelector("[data-feedback]")).not.toBeNull();
  });

  it("renders an error state with a retry button when the wire fails", async () => {
    const el = build(true);
    listHolders.error();
    await flush();

    expect(byLabel(el, /try again|Tentar novamente/i)).toBeDefined();
    expect(el.shadowRoot.querySelector("[role='alert']")).not.toBeNull();
  });
});
