import { createElement } from "lwc";
import AXF_LWC_timesheet from "c/aXF_LWC_timesheet";
import getMonth from "@salesforce/apex/AXF_CLS_CTRL_Timesheet.getMonth";
import saveDay from "@salesforce/apex/AXF_CLS_CTRL_Timesheet.saveDay";
import fillWorkdays from "@salesforce/apex/AXF_CLS_CTRL_Timesheet.fillWorkdays";
import createTimesheetPdf from "@salesforce/apex/AXF_CLS_CTRL_Timesheet.createTimesheetPdf";
import createInvoicePdf from "@salesforce/apex/AXF_CLS_CTRL_Timesheet.createInvoicePdf";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Timesheet.getMonth",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Timesheet.saveDay",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Timesheet.fillWorkdays",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

// Lets the pending promises settle (a macrotask via MessageChannel-free setImmediate substitute).
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Timesheet.createTimesheetPdf",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Timesheet.createInvoicePdf",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise(process.nextTick);

function month(overrides = {}) {
  const days = [];
  for (let d = 1; d <= 30; d++) {
    const weekday = new Date(2026, 8, d).getDay();
    days.push({
      workDate: `2026-09-${String(d).padStart(2, "0")}`,
      workingDay: weekday !== 0 && weekday !== 6,
      in1: null,
      out1: null,
      in2: null,
      out2: null,
      hours: 0
    });
  }
  days[0].in1 = "09:00:00.000";
  days[0].out1 = "17:00:00.000";
  return {
    competence: "2026-09-01",
    currencyCode: "BRL",
    hourlyRate: 50,
    dailyLimit: 8,
    monthlyLimit: 80,
    totalHours: 8,
    days,
    ...overrides
  };
}

async function setup(data = month()) {
  getMonth.mockResolvedValue(data);
  const element = createElement("c-axf-lwc-timesheet", {
    is: AXF_LWC_timesheet
  });
  element.recordId = "a00000000000001AAA";
  document.body.appendChild(element);
  await flush();
  return element;
}

function input(element, date, field) {
  return element.shadowRoot.querySelector(
    `lightning-input[data-date="${date}"][data-field="${field}"]`
  );
}

async function type(element, date, field, value) {
  const target = input(element, date, field);
  target.dispatchEvent(new CustomEvent("change", { detail: { value } }));
  await flush();
  target.dispatchEvent(new CustomEvent("blur"));
  await flush();
}

describe("c-axf-lwc-timesheet", () => {
  beforeEach(() => {
    jest.useFakeTimers({
      doNotFake: ["setTimeout", "nextTick", "setImmediate"]
    });
    jest.setSystemTime(new Date(2026, 8, 10, 12, 0, 0));
    saveDay.mockResolvedValue({ dayHours: 4, monthHours: 12, amount: 600 });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    jest.useRealTimers();
  });

  it("loads the current month and shows one row per day with the totals", async () => {
    const element = await setup();
    expect(getMonth).toHaveBeenCalledWith({
      contractId: "a00000000000001AAA",
      year: 2026,
      month: 9
    });
    expect(element.shadowRoot.querySelector(".month-label").textContent).toBe(
      "setembro de 2026"
    );
    expect(element.shadowRoot.querySelectorAll("tbody tr")).toHaveLength(30);
    expect(element.shadowRoot.querySelector(".total-hours").textContent).toBe(
      "8,00 h"
    );
    expect(element.shadowRoot.querySelector(".missing-hours").textContent).toBe(
      "72,00 h"
    );
  });

  it("shows the planner from the contract calendar", async () => {
    const element = await setup();
    // Today is 10/09/2026 (Thursday): 8 h so far, 72 h left over 14 working days after today.
    expect(
      element.shadowRoot.querySelector(".planner-until-today").textContent
    ).toBe("8,00 h");
    expect(element.shadowRoot.querySelector(".planner-days").textContent).toBe(
      "14"
    );
    expect(
      element.shadowRoot.querySelector(".planner-remaining").textContent
    ).toBe("72,00 h");
    expect(
      element.shadowRoot.querySelector(".planner-average").textContent
    ).toBe("5,14 h");
    expect(element.shadowRoot.querySelector(".planner-alert")).toBeNull();
  });

  it("alerts when the needed average passes the daily limit", async () => {
    const element = await setup(month({ dailyLimit: 4 }));
    expect(
      element.shadowRoot.querySelector(".planner-alert").textContent
    ).toContain("passa do limite diário");
  });

  it("saves the day when the user leaves the field", async () => {
    const element = await setup();
    await type(element, "2026-09-02", "in1", "09:00:00.000");
    // Half filled period: nothing is sent yet.
    expect(saveDay).not.toHaveBeenCalled();
    await type(element, "2026-09-02", "out1", "13:00:00.000");
    expect(saveDay).toHaveBeenCalledWith({
      contractId: "a00000000000001AAA",
      workDate: "2026-09-02",
      in1: "09:00:00.000",
      out1: "13:00:00.000",
      in2: null,
      out2: null
    });
    expect(element.shadowRoot.querySelector(".total-hours").textContent).toBe(
      "12,00 h"
    );
  });

  it("blocks a day above the daily limit without calling the server", async () => {
    const element = await setup();
    await type(element, "2026-09-02", "in1", "08:00:00.000");
    await type(element, "2026-09-02", "out1", "19:00:00.000");
    expect(saveDay).not.toHaveBeenCalled();
    expect(
      element.shadowRoot.querySelector(".row-error").textContent
    ).toContain("limite diário");
  });

  it("shows the server error on the row", async () => {
    saveDay.mockRejectedValue({
      body: { message: "O mês passa do limite mensal." }
    });
    const element = await setup();
    await type(element, "2026-09-02", "in1", "09:00:00.000");
    await type(element, "2026-09-02", "out1", "12:00:00.000");
    expect(element.shadowRoot.querySelector(".row-error").textContent).toBe(
      "O mês passa do limite mensal."
    );
  });

  it("fills the working days", async () => {
    const element = await setup();
    const filled = month();
    filled.days.forEach((d) => {
      if (d.workingDay) {
        d.in1 = "09:00:00.000";
        d.out1 = "17:00:00.000";
      }
    });
    fillWorkdays.mockResolvedValue(filled);
    element.shadowRoot
      .querySelector("lightning-button")
      .dispatchEvent(new CustomEvent("click"));
    await flush();
    expect(fillWorkdays).toHaveBeenCalledWith({
      contractId: "a00000000000001AAA",
      year: 2026,
      month: 9
    });
    expect(element.shadowRoot.querySelector(".total-hours").textContent).toBe(
      "176,00 h"
    );
  });

  it("moves to the next month", async () => {
    const element = await setup();
    element.shadowRoot
      .querySelector(".next-month")
      .dispatchEvent(new CustomEvent("click"));
    await flush();
    expect(getMonth).toHaveBeenLastCalledWith({
      contractId: "a00000000000001AAA",
      year: 2026,
      month: 10
    });
  });

  it("shows the load error", async () => {
    getMonth.mockRejectedValue({
      body: { message: "O contrato não está ativo." }
    });
    const element = createElement("c-axf-lwc-timesheet", {
      is: AXF_LWC_timesheet
    });
    element.recordId = "a00000000000001AAA";
    document.body.appendChild(element);
    await flush();
    expect(
      element.shadowRoot.querySelector("[role=alert]").textContent
    ).toContain("não está ativo");
    expect(element.shadowRoot.querySelector("table")).toBeNull();
  });

  it("does not count a rejected day in the totals", async () => {
    const element = await setup();
    await type(element, "2026-09-02", "in1", "08:00:00.000");
    await type(element, "2026-09-02", "out1", "19:00:00.000");
    expect(element.shadowRoot.querySelector(".row-error")).not.toBeNull();
    expect(element.shadowRoot.querySelector(".total-hours").textContent).toBe(
      "8,00 h"
    );
  });

  it("does not leave the month while a day is unsaved", async () => {
    const element = await setup();
    await type(element, "2026-09-02", "in1", "08:00:00.000");
    await type(element, "2026-09-02", "out1", "19:00:00.000");
    getMonth.mockClear();
    element.shadowRoot
      .querySelector(".next-month")
      .dispatchEvent(new CustomEvent("click"));
    await flush();
    expect(getMonth).not.toHaveBeenCalled();
    expect(element.shadowRoot.querySelector(".notice").textContent).toContain(
      "antes de mudar de mês"
    );
  });

  it("keeps the day dirty when it was edited during the save and saves it again", async () => {
    let release;
    saveDay.mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          release = () => resolve({ entryLocked: false });
        })
    );
    const element = await setup();
    await type(element, "2026-09-02", "in1", "09:00:00.000");
    const first = type(element, "2026-09-02", "out1", "12:00:00.000");
    await flush();
    // The user changes the out time while the first call is still running.
    input(element, "2026-09-02", "out1").dispatchEvent(
      new CustomEvent("change", { detail: { value: "13:00:00.000" } })
    );
    await flush();
    release();
    await first;
    await flush();
    await flush();
    expect(saveDay).toHaveBeenCalledTimes(2);
    expect(saveDay).toHaveBeenLastCalledWith(
      expect.objectContaining({ workDate: "2026-09-02", out1: "13:00:00.000" })
    );
  });

  it("saves a day left while another save was running", async () => {
    let release;
    saveDay.mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          release = () => resolve({ entryLocked: false });
        })
    );
    const element = await setup();
    await type(element, "2026-09-02", "in1", "09:00:00.000");
    const first = type(element, "2026-09-02", "out1", "12:00:00.000");
    await flush();
    await type(element, "2026-09-03", "in1", "09:00:00.000");
    await type(element, "2026-09-03", "out1", "12:00:00.000");
    expect(saveDay).toHaveBeenCalledTimes(1);
    release();
    await first;
    await flush();
    await flush();
    expect(saveDay).toHaveBeenCalledTimes(2);
    expect(saveDay).toHaveBeenLastCalledWith(
      expect.objectContaining({ workDate: "2026-09-03" })
    );
  });

  it("tells the user when the month entry is already realized", async () => {
    saveDay.mockResolvedValue({ entryLocked: true });
    const element = await setup();
    await type(element, "2026-09-02", "in1", "09:00:00.000");
    await type(element, "2026-09-02", "out1", "12:00:00.000");
    expect(element.shadowRoot.querySelector(".notice").textContent).toContain(
      "já foi realizado"
    );
  });

  it("shows the expected amount and how many days the fill skipped", async () => {
    const element = await setup();
    expect(element.shadowRoot.querySelector(".amount").textContent).toMatch(
      /400,00/
    );
    const filled = month();
    filled.filledDays = 3;
    filled.skippedDays = 2;
    fillWorkdays.mockResolvedValue(filled);
    element.shadowRoot
      .querySelector("lightning-button")
      .dispatchEvent(new CustomEvent("click"));
    await flush();
    expect(element.shadowRoot.querySelector(".notice").textContent).toContain(
      "2 não couberam no limite mensal"
    );
  });

  it("generates the timesheet PDF, tells where it was saved and opens the download", async () => {
    createTimesheetPdf.mockResolvedValue({
      documentId: "069000000000001AAA",
      title: "Timesheet-202609.pdf",
      newVersion: false
    });
    const element = await setup();
    element.shadowRoot
      .querySelector(".timesheet-pdf")
      .dispatchEvent(new CustomEvent("click"));
    await flush();
    expect(createTimesheetPdf).toHaveBeenCalledWith({
      contractId: "a00000000000001AAA",
      year: 2026,
      month: 9
    });
    expect(element.shadowRoot.querySelector(".notice").textContent).toContain(
      "Timesheet-202609.pdf salvo no lançamento do mês"
    );
  });

  it("offers the invoice only for a currency other than BRL", async () => {
    const real = await setup();
    expect(real.shadowRoot.querySelector(".invoice-pdf")).toBeNull();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    const euro = await setup(month({ currencyCode: "EUR" }));
    createInvoicePdf.mockResolvedValue({
      documentId: "069000000000002AAA",
      title: "Invoice-202609.pdf",
      newVersion: false
    });
    euro.shadowRoot
      .querySelector(".invoice-pdf")
      .dispatchEvent(new CustomEvent("click"));
    await flush();
    expect(createInvoicePdf).toHaveBeenCalledTimes(1);
  });

  it("shows the server error when the document cannot be generated", async () => {
    createTimesheetPdf.mockRejectedValue({
      body: { message: "Não há lançamento neste mês." }
    });
    const element = await setup();
    element.shadowRoot
      .querySelector(".timesheet-pdf")
      .dispatchEvent(new CustomEvent("click"));
    await flush();
    expect(
      element.shadowRoot.querySelector("[role=alert]").textContent
    ).toContain("Não há lançamento");
  });

  it("does not generate a document with unsaved hours", async () => {
    const element = await setup();
    await type(element, "2026-09-02", "in1", "08:00:00.000");
    await type(element, "2026-09-02", "out1", "19:00:00.000");
    element.shadowRoot
      .querySelector(".timesheet-pdf")
      .dispatchEvent(new CustomEvent("click"));
    await flush();
    expect(createTimesheetPdf).not.toHaveBeenCalled();
  });
});
