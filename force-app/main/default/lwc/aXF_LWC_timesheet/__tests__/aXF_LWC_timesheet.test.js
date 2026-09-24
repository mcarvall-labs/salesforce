import { createElement } from "lwc";
import Timesheet from "c/aXF_LWC_timesheet";
import getContext from "@salesforce/apex/AXF_CLS_CTRL_Timesheet.getContext";
import listContracts from "@salesforce/apex/AXF_CLS_CTRL_Timesheet.listContracts";
import saveEntry from "@salesforce/apex/AXF_CLS_CTRL_Timesheet.saveEntry";
import submitEntry from "@salesforce/apex/AXF_CLS_CTRL_Timesheet.submitEntry";
import listEntries from "@salesforce/apex/AXF_CLS_CTRL_Timesheet.listEntries";
import getForecast from "@salesforce/apex/AXF_CLS_CTRL_Timesheet.getForecast";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Timesheet.getContext",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Timesheet.listContracts",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Timesheet.saveEntry",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Timesheet.submitEntry",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Timesheet.listEntries",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Timesheet.getForecast",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const CONTRACT = {
  contractId: "a05000000000001",
  label: "CTR-000001 · Consultoria",
  holderId: "001000000000001",
  holderLabel: "Ana",
  rate: 150,
  currencyIsoCode: "BRL"
};
const DRAFT = {
  workRecordId: "a06000000000001",
  recordNumber: "WR-00000001",
  workDate: "2026-09-10",
  contractId: CONTRACT.contractId,
  contractLabel: CONTRACT.label,
  times: "08:00-12:00 | 13:00-17:30",
  note: "Sprint review",
  hours: 8.5,
  rate: 150,
  currencyIsoCode: "BRL",
  totalAmount: 1275,
  status: "DRAFT",
  billingStatus: "UNBILLED",
  billedHours: 0,
  canSubmit: true,
  canEdit: true
};
const PARTIAL = {
  ...DRAFT,
  workRecordId: "a06000000000002",
  times: "Legacy entry",
  note: null,
  status: "APPROVED",
  billingStatus: "PARTIAL",
  billedHours: 5,
  canSubmit: false,
  canEdit: false
};
const BANK = {
  key: "a01000000000001",
  label: "Banco A ****1234",
  wallet: false
};
const NONE = { key: "NONE", label: null, wallet: false };
function forecastOf(groups, destinations = [BANK, NONE]) {
  return {
    year: 2026,
    month: 9,
    destinations,
    groups,
    totals: [
      {
        currencyIsoCode: "BRL",
        approvedHours: 10,
        approvedAmount: 1400,
        pendingHours: 4,
        pendingAmount: 600
      }
    ]
  };
}
const GROUP_A = {
  destination: BANK,
  lines: [
    {
      contractId: CONTRACT.contractId,
      contractLabel: CONTRACT.label,
      currencyIsoCode: "BRL",
      approvedHours: 8,
      approvedAmount: 1200,
      pendingHours: 4,
      pendingAmount: 600
    }
  ],
  totals: [
    {
      currencyIsoCode: "BRL",
      approvedHours: 8,
      approvedAmount: 1200,
      pendingHours: 4,
      pendingAmount: 600
    }
  ]
};
const GROUP_NONE = {
  destination: NONE,
  lines: [
    {
      contractId: "a05000000000002",
      contractLabel: "CTR-000002 · Suporte",
      currencyIsoCode: "BRL",
      approvedHours: 2,
      approvedAmount: 200,
      pendingHours: 0,
      pendingAmount: 0
    }
  ],
  totals: [{ currencyIsoCode: "BRL", approvedAmount: 200, pendingAmount: 0 }]
};

const settle = async () => {
  for (let i = 0; i < 6; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};

async function build(
  context = { canUse: true, canRegister: true, canSubmit: true }
) {
  const el = createElement("c-a-x-f_-l-w-c_timesheet", { is: Timesheet });
  document.body.appendChild(el);
  getContext.emit(context);
  await settle();
  return el;
}

function q(el, selector) {
  return el.shadowRoot.querySelector(selector);
}

function field(el, name, scope = "[data-form]") {
  return q(el, `${scope}[data-field="${name}"]`);
}

async function type(el, name, value, scope) {
  const input = field(el, name, scope);
  input.value = value;
  input.dispatchEvent(new CustomEvent("change", { detail: { value } }));
  await settle();
}

/** Stub inputs have no validity: honor only the custom message the component sets. */
function trackValidity(el) {
  el.shadowRoot
    .querySelectorAll("lightning-input, lightning-combobox")
    .forEach((input) => {
      let message = "";
      input.setCustomValidity = jest.fn((text) => {
        message = text;
      });
      input.reportValidity = jest.fn();
      input.checkValidity = jest.fn(() => !message);
    });
}

function lastRequest(mock) {
  const calls = mock.mock.calls;
  return JSON.parse(calls[calls.length - 1][0].request);
}

beforeEach(() => {
  listContracts.mockResolvedValue([CONTRACT]);
  listEntries.mockResolvedValue({
    year: 2026,
    month: 9,
    fromDate: "2026-09-01",
    toDate: "2026-09-30",
    customPeriod: false,
    truncated: false,
    entries: [DRAFT, PARTIAL]
  });
  getForecast.mockResolvedValue(forecastOf([GROUP_A, GROUP_NONE]));
});

afterEach(() => {
  while (document.body.firstChild) {
    document.body.removeChild(document.body.firstChild);
  }
  jest.clearAllMocks();
});

describe("c-aXF_LWC_timesheet", () => {
  it("computes the hours from the clock times and saves the day", async () => {
    saveEntry.mockResolvedValue({
      workRecordId: DRAFT.workRecordId,
      hours: 8.5,
      status: "DRAFT",
      created: true
    });
    const el = await build();
    expect(field(el, "contractId").value).toBe(CONTRACT.contractId);
    const now = new Date();
    const pad = (n) => String(n).padStart(2, "0");
    expect(field(el, "workDate").max).toBe(
      `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`
    );
    expect(q(el, "[data-rate]").textContent).toContain(
      "AXF_Timesheet_rateInfo"
    );
    await type(el, "workDate", "2026-09-10");
    await type(el, "startTime", "08:00:00.000");
    await type(el, "breakStart", "12:00:00.000");
    await type(el, "breakEnd", "13:00:00.000");
    await type(el, "endTime", "17:30:00.000");
    await type(el, "note", " Sprint review ");
    expect(q(el, "[data-hours]").textContent).toContain(
      "AXF_Timesheet_computedHours"
    );

    trackValidity(el);
    q(el, '[data-action="save"]').click();
    await settle();

    expect(saveEntry).toHaveBeenCalledTimes(1);
    expect(lastRequest(saveEntry)).toEqual({
      workRecordId: null,
      contractId: CONTRACT.contractId,
      workDate: "2026-09-10",
      startTime: "08:00",
      breakStart: "12:00",
      breakEnd: "13:00",
      endTime: "17:30",
      note: "Sprint review"
    });
    expect(q(el, "[data-message]").textContent).toContain(
      "AXF_Timesheet_saved"
    );
    expect(listEntries).toHaveBeenCalledTimes(2);
    expect(getForecast).toHaveBeenCalledTimes(2);
    expect(field(el, "startTime").value).toBeNull();
  });

  it("refuses a break without return before calling the server", async () => {
    const el = await build();
    await type(el, "startTime", "08:00:00.000");
    await type(el, "breakStart", "12:00:00.000");
    await type(el, "endTime", "17:00:00.000");

    trackValidity(el);
    q(el, '[data-action="save"]').click();
    await settle();

    expect(saveEntry).not.toHaveBeenCalled();
    expect(field(el, "breakEnd").setCustomValidity).toHaveBeenCalledWith(
      expect.stringContaining("AXF_Timesheet_breakIncomplete")
    );
    expect(q(el, "[data-hours]").textContent.trim()).toBe("");
  });

  it("shows the sanitized server failure", async () => {
    saveEntry.mockRejectedValue({ body: { message: "NOT_ACCESSIBLE" } });
    const el = await build();
    await type(el, "startTime", "09:00:00.000");
    await type(el, "endTime", "13:00:00.000");

    trackValidity(el);
    q(el, '[data-action="save"]').click();
    await settle();

    expect(q(el, "[data-message]").textContent).toContain(
      "AXF_Timesheet_codeNOT_ACCESSIBLE"
    );
  });

  it("hides the form without permission to register", async () => {
    const el = await build({
      canUse: true,
      canRegister: false,
      canSubmit: false
    });
    expect(q(el, "[data-read-only]")).not.toBeNull();
    expect(q(el, "[data-form-section]")).toBeNull();
    expect(q(el, "[data-entries]")).not.toBeNull();
  });

  it("explains when no service contract is available", async () => {
    listContracts.mockResolvedValue([]);
    const el = await build();
    expect(q(el, "[data-no-contracts]")).not.toBeNull();
    expect(q(el, "[data-form-section]")).toBeNull();
  });

  it("lists entries with times, record and billing status", async () => {
    const el = await build();
    const rows = el.shadowRoot.querySelectorAll("[data-entries] tbody tr");
    expect(rows).toHaveLength(2);
    expect(rows[0].textContent).toContain("08:00-12:00 | 13:00-17:30");
    expect(rows[0].textContent).toContain("Sprint review");
    expect(rows[0].querySelector("[data-status]").textContent).toContain(
      "AXF_Timesheet_statusDRAFT"
    );
    expect(rows[0].querySelector("[data-billing]").textContent).toContain(
      "AXF_Timesheet_billingUNBILLED"
    );
    expect(rows[1].textContent).toContain("Legacy entry");
    expect(rows[1].querySelector("[data-billing]").className).toContain(
      "slds-theme_warning"
    );
    expect(rows[1].querySelector('[data-action="submit"]')).toBeNull();
  });

  it("submits a draft and reloads the entries and the forecast", async () => {
    submitEntry.mockResolvedValue({
      workRecordId: DRAFT.workRecordId,
      hours: 8.5,
      status: "SUBMITTED"
    });
    const el = await build();
    q(el, `[data-action="submit"][data-id="${DRAFT.workRecordId}"]`).click();
    await settle();

    expect(lastRequest(submitEntry)).toEqual({
      workRecordId: DRAFT.workRecordId
    });
    expect(q(el, "[data-message]").textContent).toContain(
      "AXF_Timesheet_submitted"
    );
    expect(listEntries).toHaveBeenCalledTimes(2);
    expect(getForecast).toHaveBeenCalledTimes(2);
  });

  it("applies the period, contract and status filters", async () => {
    const el = await build();
    await type(el, "fromDate", "2026-08-01", "[data-filter]");
    await type(el, "toDate", "2026-08-31", "[data-filter]");
    for (const [name, value] of [
      ["contractId", CONTRACT.contractId],
      ["billingStatus", "PARTIAL"],
      ["recordStatus", "APPROVED"]
    ]) {
      const box = q(
        el,
        `lightning-combobox[data-field="${name}"]:not([data-form])`
      );
      box.dispatchEvent(new CustomEvent("change", { detail: { value } }));
    }
    await settle();

    trackValidity(el);
    q(el, '[data-action="apply-filters"]').click();
    await settle();

    expect(lastRequest(listEntries)).toEqual({
      year: 2026,
      month: 8,
      fromDate: "2026-08-01",
      toDate: "2026-08-31",
      contractId: CONTRACT.contractId,
      billingStatus: "PARTIAL",
      recordStatus: "APPROVED"
    });
    expect(lastRequest(getForecast)).toMatchObject({ year: 2026, month: 8 });
  });

  it("refuses an incomplete custom period", async () => {
    const el = await build();
    await type(el, "fromDate", "2026-08-01", "[data-filter]");

    trackValidity(el);
    q(el, '[data-action="apply-filters"]').click();
    await settle();

    expect(listEntries).toHaveBeenCalledTimes(1);
  });

  it("pages months and ignores a late answer to an older request", async () => {
    const el = await build();
    let resolveOld;
    listEntries.mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          resolveOld = resolve;
        })
    );
    listEntries.mockResolvedValueOnce({
      year: 2026,
      month: 11,
      entries: [],
      truncated: false
    });
    q(el, '[data-action="next"]').click();
    q(el, '[data-action="next"]').click();
    await settle();
    resolveOld({ year: 2026, month: 10, entries: [DRAFT], truncated: false });
    await settle();

    expect(q(el, "[data-no-entries]")).not.toBeNull();
    expect(q(el, "[data-entries]")).toBeNull();
    const request = lastRequest(listEntries);
    expect(request.fromDate).toBeNull();
    expect(request.month - lastRequest(getForecast).month).toBe(0);
  });

  it("groups the forecast by destination and filters by account", async () => {
    const el = await build();
    const groups = el.shadowRoot.querySelectorAll("[data-group]");
    expect(groups).toHaveLength(2);
    expect(groups[0].textContent).toContain("Banco A ****1234");
    expect(groups[1].textContent).toContain("AXF_Timesheet_noDestination");
    expect(q(el, "[data-grand-total]")).not.toBeNull();

    getForecast.mockResolvedValue(forecastOf([GROUP_A]));
    const box = q(el, 'lightning-combobox[data-field="destination"]');
    expect(box.options.map((o) => o.value)).toEqual(["", BANK.key, "NONE"]);
    box.dispatchEvent(
      new CustomEvent("change", { detail: { value: BANK.key } })
    );
    await settle();

    expect(lastRequest(getForecast).destination).toBe(BANK.key);
    expect(el.shadowRoot.querySelectorAll("[data-group]")).toHaveLength(1);
  });

  it("loads a draft into the form and saves the correction", async () => {
    saveEntry.mockResolvedValue({
      workRecordId: DRAFT.workRecordId,
      hours: 3,
      status: "DRAFT",
      created: false
    });
    const el = await build();
    expect(
      q(el, `[data-action="edit"][data-id="${PARTIAL.workRecordId}"]`)
    ).toBeNull();
    q(el, `[data-action="edit"][data-id="${DRAFT.workRecordId}"]`).click();
    await settle();

    expect(q(el, "[data-editing]").textContent).toContain(
      "AXF_Timesheet_editing"
    );
    expect(field(el, "startTime").value).toBe("08:00");
    expect(field(el, "breakStart").value).toBe("12:00");
    expect(field(el, "breakEnd").value).toBe("13:00");
    expect(field(el, "endTime").value).toBe("17:30");
    expect(field(el, "note").value).toBe("Sprint review");
    await type(el, "breakStart", null);
    await type(el, "breakEnd", null);
    await type(el, "endTime", "11:00:00.000");

    trackValidity(el);
    q(el, '[data-action="save"]').click();
    await settle();

    expect(lastRequest(saveEntry)).toEqual({
      workRecordId: DRAFT.workRecordId,
      contractId: CONTRACT.contractId,
      workDate: DRAFT.workDate,
      startTime: "08:00",
      breakStart: null,
      breakEnd: null,
      endTime: "11:00",
      note: "Sprint review"
    });
    expect(q(el, "[data-message]").textContent).toContain(
      "AXF_Timesheet_updated"
    );
    expect(q(el, "[data-editing]")).toBeNull();
  });

  it("cancels an edit", async () => {
    const el = await build();
    q(el, `[data-action="edit"][data-id="${DRAFT.workRecordId}"]`).click();
    await settle();
    q(el, '[data-action="cancel-edit"]').click();
    await settle();
    expect(q(el, "[data-editing]")).toBeNull();
    expect(field(el, "startTime").value).toBeNull();
  });

  it("explains an already registered shift", async () => {
    saveEntry.mockRejectedValue({ body: { message: "ALREADY_REGISTERED" } });
    const el = await build();
    await type(el, "startTime", "09:00:00.000");
    await type(el, "endTime", "13:00:00.000");
    trackValidity(el);
    q(el, '[data-action="save"]').click();
    await settle();
    expect(q(el, "[data-message]").textContent).toContain(
      "AXF_Timesheet_codeALREADY_REGISTERED"
    );
  });

  it("offers the not billable status and shows the truncation banner", async () => {
    listEntries.mockResolvedValue({
      year: 2026,
      month: 9,
      truncated: true,
      entries: [DRAFT]
    });
    const el = await build();
    expect(q(el, "[data-truncated]")).not.toBeNull();
    const box = q(el, 'lightning-combobox[data-field="billingStatus"]');
    expect(box.options.map((o) => o.value)).toContain("NOT_BILLABLE");
  });

  it("clears the period validity when clearing the filters", async () => {
    const el = await build();
    await type(el, "fromDate", "2026-08-01", "[data-filter]");
    trackValidity(el);
    q(el, '[data-action="apply-filters"]').click();
    await settle();
    const from = field(el, "fromDate", "[data-filter]");
    const to = field(el, "toDate", "[data-filter]");
    expect(to.setCustomValidity).toHaveBeenLastCalledWith(
      expect.stringContaining("AXF_Timesheet_filterPeriodIncomplete")
    );
    q(el, '[data-action="clear-filters"]').click();
    await settle();
    expect(from.setCustomValidity).toHaveBeenLastCalledWith("");
    expect(to.setCustomValidity).toHaveBeenLastCalledWith("");
  });

  it("shows wallet destinations and hours in the totals", async () => {
    const wallet = { key: "a01000000000009", label: null, wallet: true };
    getForecast.mockResolvedValue(
      forecastOf([{ ...GROUP_A, destination: wallet }], [wallet])
    );
    const el = await build();
    const group = q(el, "[data-group]");
    expect(group.textContent).toContain("AXF_Timesheet_wallet");
    expect(q(el, "[data-total-hours]").textContent).toContain("8");
    expect(q(el, "[data-grand-hours]").textContent).toContain("10");
  });

  it("resets a destination absent from the new month", async () => {
    const el = await build();
    const box = q(el, 'lightning-combobox[data-field="destination"]');
    box.dispatchEvent(
      new CustomEvent("change", { detail: { value: BANK.key } })
    );
    await settle();
    getForecast.mockResolvedValue(forecastOf([GROUP_NONE], [NONE]));
    q(el, '[data-action="next"]').click();
    await settle();
    await settle();

    expect(lastRequest(getForecast).destination).toBeNull();
    expect(box.value).toBe("");
  });

  it("explains an empty forecast", async () => {
    getForecast.mockResolvedValue(forecastOf([], []));
    const el = await build();
    expect(q(el, "[data-no-forecast]")).not.toBeNull();
  });
});
