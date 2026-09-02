import { createElement } from "lwc";
import Cmp from "c/aXF_LWC_onboardingWizard";
import canConfigure from "@salesforce/apex/AXF_CLS_CTRL_OnboardingProgress.canConfigure";
import getState from "@salesforce/apex/AXF_CLS_CTRL_OnboardingProgress.getState";
import confirmStep from "@salesforce/apex/AXF_CLS_CTRL_OnboardingProgress.confirmStep";
import skipStep from "@salesforce/apex/AXF_CLS_CTRL_OnboardingProgress.skipStep";
import complete from "@salesforce/apex/AXF_CLS_CTRL_OnboardingProgress.complete";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_OnboardingProgress.canConfigure",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_OnboardingProgress.getState",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_OnboardingProgress.confirmStep",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_OnboardingProgress.skipStep",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_OnboardingProgress.reopenStep",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_OnboardingProgress.complete",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const STEPS = (over = {}) => ({
  forbidden: false,
  version: 0,
  currentStep: "WELCOME_PREFS",
  staleDetected: false,
  status: "IN_PROGRESS",
  steps: [
    { stepKey: "WELCOME_PREFS", status: "NOT_STARTED", optional: false },
    { stepKey: "PLUGGY_CREDENTIALS", status: "NOT_STARTED", optional: false },
    { stepKey: "PLUGGY_DISCOVERY", status: "NOT_STARTED", optional: false },
    { stepKey: "ACCOUNT_HOLDERS", status: "NOT_STARTED", optional: false },
    { stepKey: "PEOPLE_ACCESS", status: "NOT_STARTED", optional: true },
    { stepKey: "MANUAL_SOURCES", status: "NOT_STARTED", optional: true },
    { stepKey: "CURRENCY_PREF", status: "NOT_STARTED", optional: false }
  ],
  ...over
});

const flush = async () => {
  for (let i = 0; i < 8; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};

function build() {
  const el = createElement("c-wizard", { is: Cmp });
  document.body.appendChild(el);
  return el;
}
const btn = (el, re) =>
  [...el.shadowRoot.querySelectorAll("lightning-button")].find((b) =>
    re.test(b.label)
  );

afterEach(() => {
  while (document.body.firstChild) {
    document.body.removeChild(document.body.firstChild);
  }
  jest.clearAllMocks();
});

describe("c-aXF_LWC_onboardingWizard", () => {
  it("shows the forbidden message without authority", async () => {
    canConfigure.mockResolvedValue(false);
    const el = build();
    await flush();
    await flush();
    expect(el.shadowRoot.textContent).toMatch(/autoriza|authorized/i);
  });

  it("resumes at the server step and confirms it", async () => {
    canConfigure.mockResolvedValue(true);
    getState.mockResolvedValue(
      STEPS({ currentStep: "PLUGGY_CREDENTIALS", version: 2 })
    );
    confirmStep.mockResolvedValue(
      STEPS({ currentStep: "PLUGGY_DISCOVERY", version: 3 })
    );
    const el = build();
    await flush();
    await flush();
    await flush();

    expect(el.shadowRoot.textContent).toMatch(/2 de 8|2 of 8/);
    btn(el, /Próximo|Next/).click();
    await flush();
    await flush();
    expect(confirmStep).toHaveBeenCalledTimes(1);
    expect(confirmStep.mock.calls[0][0].input).toEqual({
      stepKey: "PLUGGY_CREDENTIALS",
      expectedVersion: 2,
      evidenceRef: "wizard"
    });
  });

  it("offers skip on an optional step", async () => {
    canConfigure.mockResolvedValue(true);
    getState.mockResolvedValue(
      STEPS({ currentStep: "PEOPLE_ACCESS", version: 5 })
    );
    skipStep.mockResolvedValue(
      STEPS({ currentStep: "MANUAL_SOURCES", version: 6 })
    );
    const el = build();
    await flush();
    await flush();
    await flush();

    const skip = btn(el, /Pular|Skip/);
    expect(skip).toBeTruthy();
    skip.click();
    await flush();
    await flush();
    expect(skipStep).toHaveBeenCalledWith({
      stepKey: "PEOPLE_ACCESS",
      expectedVersion: 5
    });
  });

  it("gates finish on acknowledging pending items, then completes", async () => {
    canConfigure.mockResolvedValue(true);
    getState.mockResolvedValue(
      STEPS({
        currentStep: "REVIEW",
        version: 9,
        steps: STEPS().steps.map((s) =>
          s.stepKey === "CURRENCY_PREF" ? s : { ...s, status: "CONFIRMED" }
        )
      })
    );
    complete.mockResolvedValue(
      STEPS({ currentStep: "DONE", status: "COMPLETED", version: 10 })
    );
    const el = build();
    await flush();
    await flush();
    await flush();

    expect(btn(el, /Concluir|Finish/).disabled).toBe(true);

    const ack = el.shadowRoot.querySelector("lightning-input");
    ack.checked = true;
    ack.dispatchEvent(
      new CustomEvent("change", {
        detail: { checked: true },
        target: { checked: true }
      })
    );
    await flush();

    btn(el, /Concluir|Finish/).click();
    await flush();
    await flush();
    expect(complete).toHaveBeenCalledTimes(1);
    expect(el.shadowRoot.textContent).toMatch(/concluíd|finished/i);
  });
});
