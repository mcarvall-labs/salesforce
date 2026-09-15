import { createElement } from "lwc";
import ScheduleWizard from "c/aXF_LWC_scheduleWizard";
import planSchedule from "@salesforce/apex/AXF_CLS_CTRL_ScheduleWizard.planSchedule";
import saveSchedule from "@salesforce/apex/AXF_CLS_CTRL_ScheduleWizard.saveSchedule";
import authorizedContexts from "@salesforce/apex/AXF_CLS_CTRL_ScheduleWizard.authorizedContexts";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ScheduleWizard.planSchedule",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ScheduleWizard.saveSchedule",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ScheduleWizard.authorizedContexts",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = async () => {
  for (let i = 0; i < 8; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};

const PRICE_SCHEDULE = {
  outcome: "OK",
  modality: "PRICE",
  totalPrincipal: 1000.0,
  totalInterest: 50.5,
  totalFees: 0.0,
  occurrences: [
    {
      sequence: 1,
      dueDate: "2026-03-15",
      payment: 262.62,
      principalPortion: 242.62,
      interestPortion: 20.0,
      feePortion: 0.0,
      closingBalance: 757.38,
      roundingResidualApplied: false
    }
  ]
};

const build = () => {
  const el = createElement("c-schedule-wizard", { is: ScheduleWizard });
  document.body.appendChild(el);
  return el;
};

const clickButton = (el, label) =>
  [...el.shadowRoot.querySelectorAll("lightning-button")]
    .find((b) => b.label === label)
    .click();

describe("c-a-x-f_-l-w-c_schedule-wizard", () => {
  beforeEach(() => {
    authorizedContexts.mockResolvedValue([
      { accountId: "001000000000001AAA", label: "Titular Um" }
    ]);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("loads authorized contexts on connect", async () => {
    const el = build();
    await flush();
    const combos = el.shadowRoot.querySelectorAll("lightning-combobox");
    const accountCombo = [...combos].find(
      (c) => c.label === "Entidade titular"
    );
    expect(accountCombo.options).toEqual([
      { label: "Titular Um", value: "001000000000001AAA" }
    ]);
  });

  it("renders the generated schedule table on preview", async () => {
    planSchedule.mockResolvedValue(PRICE_SCHEDULE);
    const el = build();
    await flush();

    clickButton(el, "Gerar prévia");
    await flush();

    expect(planSchedule).toHaveBeenCalled();
    expect(el.shadowRoot.textContent).toContain("262.62");
    expect(el.shadowRoot.querySelectorAll("tbody tr")).toHaveLength(1);
  });

  it("saves the schedule and shows the outcome", async () => {
    planSchedule.mockResolvedValue(PRICE_SCHEDULE);
    saveSchedule.mockResolvedValue({
      outcome: "SAVED",
      message: "1 ocorrência(s) planejada(s).",
      occurrenceCount: 1
    });
    const el = build();
    await flush();

    const accountCombo = [
      ...el.shadowRoot.querySelectorAll("lightning-combobox")
    ].find((c) => c.label === "Entidade titular");
    accountCombo.value = "001000000000001AAA";
    accountCombo.dispatchEvent(new CustomEvent("change"));

    clickButton(el, "Gerar prévia");
    await flush();
    clickButton(el, "Salvar cronograma");
    await flush();

    expect(saveSchedule).toHaveBeenCalled();
    const call = saveSchedule.mock.calls[0][0];
    expect(call.accountId).toBe("001000000000001AAA");
    expect(call.groupKey.length).toBeLessThanOrEqual(24);
    expect(el.shadowRoot.textContent).toContain("Cronograma salvo");
  });

  it("shows the blocked message for consórcio", async () => {
    planSchedule.mockResolvedValue({
      outcome: "BLOCKED",
      message: "Consórcio não tem policy canônica — ver AXF-97.",
      occurrences: []
    });
    const el = build();
    await flush();

    clickButton(el, "Gerar prévia");
    await flush();

    expect(el.shadowRoot.textContent).toContain("AXF-97");
  });
});
