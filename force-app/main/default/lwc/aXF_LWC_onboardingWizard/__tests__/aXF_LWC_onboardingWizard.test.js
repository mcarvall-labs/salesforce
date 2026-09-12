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
    { stepKey: "HOLDERS", status: "NOT_STARTED", optional: true },
    { stepKey: "PLUGGY_CREDENTIALS", status: "NOT_STARTED", optional: false },
    { stepKey: "PLUGGY_DISCOVERY", status: "NOT_STARTED", optional: false },
    { stepKey: "ACCOUNT_HOLDERS", status: "NOT_STARTED", optional: false },
    { stepKey: "PEOPLE_ACCESS", status: "NOT_STARTED", optional: true },
    { stepKey: "MANUAL_SOURCES", status: "NOT_STARTED", optional: true },
    { stepKey: "CURRENCY_PREF", status: "NOT_STARTED", optional: false },
    { stepKey: "REVIEW", status: "NOT_STARTED", optional: false }
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
const step = (el, key) =>
  el.shadowRoot.querySelector(`.wizard__step[data-step="${key}"]`);
const doneSteps = (el) =>
  [...el.shadowRoot.querySelectorAll(".wizard__step_done")].map((s) =>
    s.getAttribute("data-step")
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

  it("disables Next on PLUGGY_CREDENTIALS until credential is configured, then confirms", async () => {
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

    // HOLDERS (optional) is step 2, so Pluggy credentials is step 3 of 9 (AXF-106).
    expect(el.shadowRoot.textContent).toMatch(/3 de 9|3 of 9/);
    const nextBtn = btn(el, /Próximo|Next/);
    expect(nextBtn.disabled).toBe(true);
    expect(el.shadowRoot.textContent).toMatch(
      /Configure e salve as credenciais|Configure and save/i
    );

    // Simulate child component notifying that credential is now active
    const pluggyCmp = el.shadowRoot.querySelector(
      "c-a-x-f_-l-w-c_pluggy-integration-config"
    );
    pluggyCmp.dispatchEvent(
      new CustomEvent("statuschange", {
        detail: { hasActiveCredential: true }
      })
    );
    await flush();

    expect(nextBtn.disabled).toBe(false);
    nextBtn.click();
    await flush();
    await flush();
    expect(confirmStep).toHaveBeenCalledTimes(1);
    expect(confirmStep.mock.calls[0][0]).toEqual({
      stepKey: "PLUGGY_CREDENTIALS",
      expectedVersion: 2,
      evidenceRef: "wizard"
    });
  });

  it("opens the Pluggy guide in a dialog and closes it", async () => {
    canConfigure.mockResolvedValue(true);
    getState.mockResolvedValue(
      STEPS({ currentStep: "PLUGGY_CREDENTIALS", version: 2 })
    );
    const el = build();
    await flush();
    await flush();
    await flush();

    const dlg = () => el.shadowRoot.querySelector('[role="dialog"]');
    expect(dlg()).toBeNull();
    expect(
      el.shadowRoot.querySelector("c-a-x-f_-l-w-c_pluggy-guide")
    ).toBeNull();

    btn(el, /o que você|what you/i).click();
    await flush();
    expect(dlg()).not.toBeNull();
    expect(dlg().querySelector("c-a-x-f_-l-w-c_pluggy-guide")).not.toBeNull();

    el.shadowRoot.querySelector(".wizard__modal-close").click();
    await flush();
    expect(dlg()).toBeNull();
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

  it("lets the administrator move forward and backwards through the stepper", async () => {
    canConfigure.mockResolvedValue(true);
    getState.mockResolvedValue(STEPS({ currentStep: "WELCOME_PREFS", version: 1 }));
    const el = build();
    await flush();
    await flush();
    await flush();

    // Nothing was validated yet, so nothing may show as done — even the steps
    // behind the current one.
    expect(doneSteps(el)).toEqual([]);

    // Forward: straight to a step that Next would only reach after 7 confirmations.
    step(el, "CURRENCY_PREF").click();
    await flush();
    expect(
      el.shadowRoot.querySelector("c-a-x-f_-l-w-c_report-currency-preference")
    ).not.toBeNull();
    expect(step(el, "CURRENCY_PREF").getAttribute("aria-current")).toBe("step");
    expect(doneSteps(el)).toEqual([]);

    // Backwards: one click back to the beginning.
    step(el, "WELCOME_PREFS").click();
    await flush();
    expect(el.shadowRoot.textContent).toMatch(/já está instalado|already installed/i);
    expect(doneSteps(el)).toEqual([]);
  });

  it("ticks only the steps the server recorded as settled", async () => {
    canConfigure.mockResolvedValue(true);
    getState.mockResolvedValue(
      STEPS({
        currentStep: "PLUGGY_CREDENTIALS",
        version: 4,
        steps: STEPS().steps.map((s) => {
          if (s.stepKey === "WELCOME_PREFS") {
            return { ...s, status: "CONFIRMED" };
          }
          if (s.stepKey === "HOLDERS") {
            return { ...s, status: "SKIPPED" };
          }
          return s;
        })
      })
    );
    const el = build();
    await flush();
    await flush();
    await flush();

    expect(doneSteps(el)).toEqual(["WELCOME_PREFS", "HOLDERS"]);
    // The current step is not done, and neither is anything after it.
    expect(step(el, "PLUGGY_CREDENTIALS").className).toMatch(
      /wizard__step_current/
    );
    expect(step(el, "PLUGGY_CREDENTIALS").className).not.toMatch(
      /wizard__step_done/
    );
    expect(step(el, "CURRENCY_PREF").className).toMatch(/wizard__step_upcoming/);
    expect(step(el, "HOLDERS").getAttribute("aria-label")).toMatch(
      /Pulada|Skipped/
    );
    expect(step(el, "CURRENCY_PREF").getAttribute("aria-label")).toMatch(
      /Não iniciada|Not started/
    );
  });

  it("marks a reopened step as outdated instead of done", async () => {
    canConfigure.mockResolvedValue(true);
    getState.mockResolvedValue(
      STEPS({
        currentStep: "ACCOUNT_HOLDERS",
        version: 6,
        staleDetected: true,
        steps: STEPS().steps.map((s) => {
          if (s.stepKey === "PLUGGY_DISCOVERY") {
            return { ...s, status: "STALE" };
          }
          if (s.stepKey === "WELCOME_PREFS") {
            return { ...s, status: "CONFIRMED" };
          }
          return s;
        })
      })
    );
    const el = build();
    await flush();
    await flush();
    await flush();

    const stale = step(el, "PLUGGY_DISCOVERY");
    expect(stale.className).toMatch(/wizard__step_stale/);
    expect(stale.className).not.toMatch(/wizard__step_done/);
    expect(stale.querySelector(".wizard__step-dot").textContent).toMatch(/!/);
    expect(stale.getAttribute("aria-label")).toMatch(/Desatualizada|Outdated/);
    expect(doneSteps(el)).toEqual(["WELCOME_PREFS"]);
  });

  it("keeps the reader in place when a step ahead of the order is confirmed", async () => {
    canConfigure.mockResolvedValue(true);
    getState.mockResolvedValue(STEPS({ currentStep: "WELCOME_PREFS", version: 1 }));
    // The server resumes at the first unsettled step — which is still step 1.
    confirmStep.mockResolvedValue(
      STEPS({
        currentStep: "WELCOME_PREFS",
        version: 2,
        steps: STEPS().steps.map((s) => {
          if (s.stepKey === "CURRENCY_PREF") {
            return { ...s, status: "CONFIRMED" };
          }
          return s;
        })
      })
    );
    const el = build();
    await flush();
    await flush();
    await flush();

    step(el, "CURRENCY_PREF").click();
    await flush();
    btn(el, /Próximo|Next/).click();
    await flush();
    await flush();
    await flush();

    expect(confirmStep.mock.calls[0][0].stepKey).toBe("CURRENCY_PREF");
    // It advanced to the review page instead of snapping back to step 1.
    expect(el.shadowRoot.textContent).toMatch(/Revisão|Review/);
    expect(el.shadowRoot.textContent).not.toMatch(
      /já está instalado|already installed/i
    );
  });

  it("gates finish on acknowledging pending items, then completes", async () => {
    canConfigure.mockResolvedValue(true);
    getState.mockResolvedValue(
      STEPS({
        currentStep: "REVIEW",
        version: 9,
        steps: STEPS().steps.map((s) => {
          if (s.stepKey === "CURRENCY_PREF") {
            return s;
          }
          return { ...s, status: "CONFIRMED" };
        })
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
