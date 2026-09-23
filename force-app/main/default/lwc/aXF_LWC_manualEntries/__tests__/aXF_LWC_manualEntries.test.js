import { createElement } from "lwc";
import ManualEntries from "c/aXF_LWC_manualEntries";
import listEntries from "@salesforce/apex/AXF_CLS_CTRL_ManualEntries.listEntries";

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
  return { NavigationMixin, CurrentPageReference: jest.fn() };
});
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ManualEntries.listEntries",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const REPORT = {
  year: 2026,
  month: 9,
  fromDate: "2026-09-01",
  toDate: "2026-09-30",
  customPeriod: false,
  truncated: false,
  origins: [
    { originId: "a01000000000001", kind: "BANK_ACCOUNT", label: "Banco A" },
    {
      originId: "a01000000000002",
      kind: "WALLET",
      label: "Carteira (dinheiro)"
    }
  ],
  entries: [
    {
      recordId: "a0X000000000001",
      holderLabel: "Ana",
      entryDate: "2026-09-10",
      description: null,
      amount: 100,
      direction: "DEBIT",
      currencyIso: "BRL",
      planKind: "PLANNED",
      originId: "a01000000000001",
      originKind: "BANK_ACCOUNT",
      originLabel: "Banco A",
      status: "UNRECONCILED"
    },
    {
      recordId: "a0X000000000002",
      holderLabel: "Ana",
      entryDate: "2026-09-05",
      description: "Feira",
      amount: 42.5,
      direction: "CREDIT",
      currencyIso: "BRL",
      planKind: "ACTUAL_ONLY",
      originId: null,
      originKind: "NONE",
      originLabel: null,
      status: "RECONCILED"
    }
  ]
};

const flush = async () => {
  for (let i = 0; i < 6; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};

function build() {
  const el = createElement("c-a-x-f_-l-w-c_manual-entries", {
    is: ManualEntries
  });
  document.body.appendChild(el);
  return el;
}

function request(call) {
  return JSON.parse(listEntries.mock.calls[call][0].request);
}

function button(el, action) {
  return el.shadowRoot.querySelector(`[data-action='${action}']`);
}

afterEach(() => {
  while (document.body.firstChild) {
    document.body.removeChild(document.body.firstChild);
  }
  jest.clearAllMocks();
});

describe("c-aXF_LWC_manualEntries", () => {
  it("lists the entries of the current month with their derived status", async () => {
    listEntries.mockResolvedValue(REPORT);
    const el = build();
    await flush();

    const now = new Date();
    expect(request(0)).toMatchObject({
      year: now.getFullYear(),
      month: now.getMonth() + 1,
      fromDate: null,
      status: null
    });
    const rows = el.shadowRoot.querySelectorAll("tr[data-entry]");
    expect(rows).toHaveLength(2);
    expect(rows[0].textContent).toMatch(/AXF_ManualEntries_noDescription/);
    expect(rows[0].textContent).toMatch(/Banco A/);
    expect(rows[0].textContent).toMatch(/AXF_ManualEntries_kindPLANNED/);
    expect(rows[0].querySelector("[data-status]").textContent).toMatch(
      /AXF_BankStatement_statusUNRECONCILED/
    );
    expect(rows[1].textContent).toMatch(/AXF_ManualEntries_noOrigin/);
    expect(rows[1].textContent).toMatch(/AXF_ManualEntries_natureCREDIT/);
    expect(el.shadowRoot.querySelector("table caption")).not.toBeNull();
    const origin = [
      ...el.shadowRoot.querySelectorAll("lightning-combobox")
    ].find((c) => c.dataset.field === "originId");
    expect(origin.options.map((o) => o.value)).toEqual([
      "",
      "a01000000000001",
      "a01000000000002"
    ]);
  });

  it("pages months and applies the status, nature and origin filters", async () => {
    listEntries.mockResolvedValue(REPORT);
    const el = build();
    await flush();

    button(el, "previous").click();
    await flush();
    expect(request(1)).toMatchObject({ year: 2026, month: 8 });

    const combos = [...el.shadowRoot.querySelectorAll("lightning-combobox")];
    const set = (field, value) =>
      combos
        .find((c) => c.dataset.field === field)
        .dispatchEvent(new CustomEvent("change", { detail: { value } }));
    set("status", "UNRECONCILED");
    set("direction", "DEBIT");
    set("originId", "a01000000000002");
    await flush();
    button(el, "apply-filters").click();
    await flush();
    expect(request(2)).toMatchObject({
      status: "UNRECONCILED",
      direction: "DEBIT",
      originId: "a01000000000002"
    });

    button(el, "clear-filters").click();
    await flush();
    expect(request(3)).toMatchObject({
      status: null,
      direction: null,
      originId: null
    });
  });

  it("refuses a custom period longer than 366 days on the client", async () => {
    listEntries.mockResolvedValue(REPORT);
    const el = build();
    await flush();
    const inputs = [...el.shadowRoot.querySelectorAll("lightning-input")];
    const from = inputs.find((i) => i.dataset.field === "fromDate");
    const to = inputs.find((i) => i.dataset.field === "toDate");
    from.dispatchEvent(
      new CustomEvent("change", { detail: { value: "2025-01-01" } })
    );
    to.dispatchEvent(
      new CustomEvent("change", { detail: { value: "2026-06-01" } })
    );
    await flush();
    button(el, "apply-filters").click();
    await flush();
    expect(listEntries).toHaveBeenCalledTimes(1);

    to.dispatchEvent(
      new CustomEvent("change", { detail: { value: "2025-01-31" } })
    );
    await flush();
    button(el, "apply-filters").click();
    await flush();
    expect(request(1)).toMatchObject({
      fromDate: "2025-01-01",
      toDate: "2025-01-31"
    });
  });

  it("shows an empty state and a sanitized failure", async () => {
    listEntries.mockResolvedValueOnce({ ...REPORT, entries: [] });
    const el = build();
    await flush();
    expect(el.shadowRoot.querySelector("[data-no-entries]")).not.toBeNull();

    listEntries.mockRejectedValueOnce({ body: { message: "INVALID_INPUT" } });
    button(el, "next").click();
    await flush();
    expect(el.shadowRoot.querySelector("[data-message]").textContent).toMatch(
      /AXF_BankStatement_codeINVALID_INPUT/
    );
  });

  it("opens the entry wizard for a new entry", async () => {
    listEntries.mockResolvedValue(REPORT);
    const el = build();
    await flush();
    button(el, "new-entry").click();
    expect(mockNavigate).toHaveBeenCalledWith({
      type: "standard__navItemPage",
      attributes: { apiName: "AXF_EntryWizard" }
    });
  });
});
