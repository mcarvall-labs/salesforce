import { createElement } from "lwc";
import Cmp from "c/aXF_LWC_onboardingWizard";
import canConfigure from "@salesforce/apex/AXF_CLS_CTRL_OnboardingProgress.canConfigure";
import getState from "@salesforce/apex/AXF_CLS_CTRL_OnboardingProgress.getState";
import confirmStep from "@salesforce/apex/AXF_CLS_CTRL_OnboardingProgress.confirmStep";
import skipStep from "@salesforce/apex/AXF_CLS_CTRL_OnboardingProgress.skipStep";
import complete from "@salesforce/apex/AXF_CLS_CTRL_OnboardingProgress.complete";
import getOverview from "@salesforce/apex/AXF_CLS_CTRL_SourceHolderConfirmation.getOverview";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_SourceHolderConfirmation.getOverview",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

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

// AXF-106 — the wizard decides by the server-side overview, never by a client guess.
const NO_HOLDER_WORK = {
  forbidden: false,
  pending: [],
  released: [],
  divergent: []
};
beforeEach(() => {
  getOverview.mockResolvedValue(NO_HOLDER_WORK);
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
    getState.mockResolvedValue(
      STEPS({ currentStep: "WELCOME_PREFS", version: 1 })
    );
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
    expect(el.shadowRoot.textContent).toMatch(
      /já está instalado|already installed/i
    );
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
    expect(step(el, "CURRENCY_PREF").className).toMatch(
      /wizard__step_upcoming/
    );
    expect(step(el, "HOLDERS").getAttribute("aria-label")).toMatch(
      /Pulada|Skipped/
    );
    expect(step(el, "CURRENCY_PREF").getAttribute("aria-label")).toMatch(
      /Não iniciada|Not started/
    );
  });

  it("marks a reopened step as outdated instead of done", async () => {
    canConfigure.mockResolvedValue(true);
    // a source still waiting for a holder keeps the confirmation step visible
    getOverview.mockResolvedValue({
      ...NO_HOLDER_WORK,
      pending: [{ sourceId: "a01", kind: "BANK", version: 0 }]
    });
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
    getState.mockResolvedValue(
      STEPS({ currentStep: "WELCOME_PREFS", version: 1 })
    );
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

  it("settles the holder step with confirmStep when there is nothing to resolve", async () => {
    canConfigure.mockResolvedValue(true);
    getState.mockResolvedValue(
      STEPS({ currentStep: "ACCOUNT_HOLDERS", version: 3 })
    );
    getOverview.mockResolvedValue({
      forbidden: false,
      pending: [],
      released: [{ sourceId: "a02", kind: "CARD", holderId: "001x" }],
      divergent: []
    });
    confirmStep.mockResolvedValue(
      STEPS({
        currentStep: "PEOPLE_ACCESS",
        version: 4,
        steps: STEPS().steps.map((s) => {
          return s.stepKey === "ACCOUNT_HOLDERS"
            ? { ...s, status: "CONFIRMED" }
            : s;
        })
      })
    );
    const el = build();
    await flush();
    await flush();
    await flush();
    await flush();

    expect(getOverview).toHaveBeenCalled();
    expect(confirmStep).toHaveBeenCalledWith({
      stepKey: "ACCOUNT_HOLDERS",
      expectedVersion: 3,
      evidenceRef: "wizard"
    });
    expect(skipStep).not.toHaveBeenCalled();
    // the confirmation surface never appears and the setup moved on by itself
    expect(
      el.shadowRoot.querySelector("c-a-x-f_-l-w-c_confirm-source-holders")
    ).toBeNull();
    expect(
      el.shadowRoot.querySelector("c-a-x-f_-l-w-c_add-person-access")
    ).not.toBeNull();
  });

  it("keeps the holder step when a source is pending or divergent", async () => {
    canConfigure.mockResolvedValue(true);
    getState.mockResolvedValue(
      STEPS({ currentStep: "ACCOUNT_HOLDERS", version: 3 })
    );
    getOverview.mockResolvedValue({
      forbidden: false,
      pending: [],
      released: [{ sourceId: "a02", kind: "CARD", holderId: "001x" }],
      divergent: [{ sourceId: "a02", kind: "CARD", holderId: "001x" }]
    });
    const el = build();
    await flush();
    await flush();
    await flush();

    expect(confirmStep).not.toHaveBeenCalled();
    expect(
      el.shadowRoot.querySelector("c-a-x-f_-l-w-c_confirm-source-holders")
    ).not.toBeNull();
  });

  it("never hides the holder step when the overview cannot be read", async () => {
    canConfigure.mockResolvedValue(true);
    getState.mockResolvedValue(
      STEPS({ currentStep: "ACCOUNT_HOLDERS", version: 3 })
    );
    getOverview.mockRejectedValue(new Error("no access"));
    const el = build();
    await flush();
    await flush();
    await flush();

    expect(confirmStep).not.toHaveBeenCalled();
    expect(
      el.shadowRoot.querySelector("c-a-x-f_-l-w-c_confirm-source-holders")
    ).not.toBeNull();
  });

  it("drops the holder step from the stepper once discovery is done and nothing is left", async () => {
    canConfigure.mockResolvedValue(true);
    // discovery is settled, so reaching ACCOUNT_HOLDERS means it has nothing left
    getState.mockResolvedValue(
      STEPS({
        currentStep: "ACCOUNT_HOLDERS",
        version: 3,
        steps: STEPS().steps.map((s) => {
          return s.stepKey === "PLUGGY_DISCOVERY"
            ? { ...s, status: "CONFIRMED" }
            : s;
        })
      })
    );
    getOverview.mockResolvedValue(NO_HOLDER_WORK);
    confirmStep.mockResolvedValue(
      STEPS({
        currentStep: "PEOPLE_ACCESS",
        version: 4,
        steps: STEPS().steps.map((s) => {
          return s.stepKey === "ACCOUNT_HOLDERS" ||
            s.stepKey === "PLUGGY_DISCOVERY"
            ? { ...s, status: "CONFIRMED" }
            : s;
        })
      })
    );
    const el = build();
    await flush();
    await flush();
    await flush();
    await flush();

    expect(confirmStep).toHaveBeenCalledTimes(1);
    expect(step(el, "ACCOUNT_HOLDERS")).toBeNull();
    expect(
      el.shadowRoot.querySelector("c-a-x-f_-l-w-c_confirm-source-holders")
    ).toBeNull();
    expect(step(el, "PEOPLE_ACCESS")).not.toBeNull();
  });

  it("keeps the holder step in the stepper while a source is pending", async () => {
    canConfigure.mockResolvedValue(true);
    getState.mockResolvedValue(
      STEPS({
        currentStep: "ACCOUNT_HOLDERS",
        version: 3,
        steps: STEPS().steps.map((s) => {
          return s.stepKey === "PLUGGY_DISCOVERY"
            ? { ...s, status: "CONFIRMED" }
            : s;
        })
      })
    );
    getOverview.mockResolvedValue({
      ...NO_HOLDER_WORK,
      pending: [{ sourceId: "a01", kind: "BANK", version: 0 }]
    });
    const el = build();
    await flush();
    await flush();
    await flush();

    expect(confirmStep).not.toHaveBeenCalled();
    expect(step(el, "ACCOUNT_HOLDERS")).not.toBeNull();
    expect(
      el.shadowRoot.querySelector("c-a-x-f_-l-w-c_confirm-source-holders")
    ).not.toBeNull();
  });

  it("never reports a forbidden overview as a resolved holder step", async () => {
    canConfigure.mockResolvedValue(true);
    getState.mockResolvedValue(
      STEPS({ currentStep: "ACCOUNT_HOLDERS", version: 3 })
    );
    getOverview.mockResolvedValue({
      forbidden: true,
      pending: [],
      released: [],
      divergent: []
    });
    const el = build();
    await flush();
    await flush();
    await flush();
    await flush();

    // A refusal is an unknown, never "nothing to resolve": the step is not settled and
    // never renders as resolved.
    expect(confirmStep).not.toHaveBeenCalled();
    expect(
      el.shadowRoot.querySelector("c-a-x-f_-l-w-c_confirm-source-holders")
    ).not.toBeNull();
    expect(el.shadowRoot.textContent).not.toMatch(
      /Nada a resolver|Nothing to resolve/i
    );
  });

  it("re-reads the overview when the administrator re-enters the holder step", async () => {
    canConfigure.mockResolvedValue(true);
    getState.mockResolvedValue(
      STEPS({ currentStep: "ACCOUNT_HOLDERS", version: 3 })
    );
    getOverview.mockResolvedValue({
      ...NO_HOLDER_WORK,
      pending: [{ sourceId: "a01", kind: "BANK", version: 0 }]
    });
    const el = build();
    await flush();
    await flush();
    await flush();
    const readsBefore = getOverview.mock.calls.length;

    // The sources were resolved while the administrator was on another step.
    getOverview.mockResolvedValue({
      ...NO_HOLDER_WORK,
      released: [{ sourceId: "a01", kind: "BANK", holderId: "001x" }]
    });
    confirmStep.mockResolvedValue(
      STEPS({
        currentStep: "PEOPLE_ACCESS",
        version: 4,
        steps: STEPS().steps.map((s) => {
          return s.stepKey === "ACCOUNT_HOLDERS"
            ? { ...s, status: "CONFIRMED" }
            : s;
        })
      })
    );

    step(el, "PLUGGY_DISCOVERY").click();
    await flush();
    await flush();
    step(el, "ACCOUNT_HOLDERS").click();
    await flush();
    await flush();
    await flush();
    await flush();

    // Re-entering re-reads the server instead of trusting the earlier verdict...
    expect(getOverview.mock.calls.length).toBeGreaterThan(readsBefore);
    // ...and the fresh answer is what settles the step.
    expect(confirmStep).toHaveBeenCalledWith({
      stepKey: "ACCOUNT_HOLDERS",
      expectedVersion: 3,
      evidenceRef: "wizard"
    });
  });

  // ---- AXF-106: an unknown or unsettled verdict never hides the step nor settles it ----

  it("keeps the holder step and settles nothing when the overview payload is null", async () => {
    canConfigure.mockResolvedValue(true);
    getState.mockResolvedValue(
      STEPS({
        currentStep: "ACCOUNT_HOLDERS",
        version: 3,
        steps: STEPS().steps.map((s) => {
          return s.stepKey === "PLUGGY_DISCOVERY"
            ? { ...s, status: "CONFIRMED" }
            : s;
        })
      })
    );
    // A null payload is an UNKNOWN answer, never "there is nothing to resolve".
    getOverview.mockResolvedValue(null);
    const el = build();
    await flush();
    await flush();
    await flush();
    await flush();

    expect(confirmStep).not.toHaveBeenCalled();
    expect(step(el, "ACCOUNT_HOLDERS")).not.toBeNull();
    expect(step(el, "ACCOUNT_HOLDERS").getAttribute("aria-current")).toBe(
      "step"
    );
    expect(
      el.shadowRoot.querySelector("c-a-x-f_-l-w-c_confirm-source-holders")
    ).not.toBeNull();
    expect(el.shadowRoot.textContent).not.toMatch(
      /Nada a resolver|Nothing to resolve/i
    );
  });

  it("treats an overview without the expected lists as unknown", async () => {
    canConfigure.mockResolvedValue(true);
    getState.mockResolvedValue(
      STEPS({
        currentStep: "ACCOUNT_HOLDERS",
        version: 3,
        steps: STEPS().steps.map((s) => {
          return s.stepKey === "PLUGGY_DISCOVERY"
            ? { ...s, status: "CONFIRMED" }
            : s;
        })
      })
    );
    getOverview.mockResolvedValue({ forbidden: false });
    const el = build();
    await flush();
    await flush();
    await flush();
    await flush();

    expect(confirmStep).not.toHaveBeenCalled();
    expect(step(el, "ACCOUNT_HOLDERS")).not.toBeNull();
    expect(
      el.shadowRoot.querySelector("c-a-x-f_-l-w-c_confirm-source-holders")
    ).not.toBeNull();
    // "Etapa N de M" keeps describing the step that is really on the screen.
    expect(el.shadowRoot.textContent).toMatch(/Etapa 5 de 9|Step 5 of 9/);
  });

  it("re-reads the overview after the discovery is confirmed, before deciding", async () => {
    canConfigure.mockResolvedValue(true);
    getState.mockResolvedValue(
      STEPS({ currentStep: "PLUGGY_DISCOVERY", version: 3 })
    );
    // Before the discovery runs the step has something to resolve...
    getOverview.mockResolvedValue({
      ...NO_HOLDER_WORK,
      pending: [{ sourceId: "a01", kind: "BANK", version: 0 }]
    });
    confirmStep
      .mockResolvedValueOnce(
        STEPS({
          currentStep: "ACCOUNT_HOLDERS",
          version: 4,
          steps: STEPS().steps.map((s) => {
            return s.stepKey === "PLUGGY_DISCOVERY"
              ? { ...s, status: "CONFIRMED" }
              : s;
          })
        })
      )
      .mockResolvedValueOnce(
        STEPS({
          currentStep: "PEOPLE_ACCESS",
          version: 5,
          steps: STEPS().steps.map((s) => {
            return s.stepKey === "PLUGGY_DISCOVERY" ||
              s.stepKey === "ACCOUNT_HOLDERS"
              ? { ...s, status: "CONFIRMED" }
              : s;
          })
        })
      );
    const el = build();
    await flush();
    await flush();
    await flush();
    const readsBefore = getOverview.mock.calls.length;

    // ...the discovery resolves everything it had left pending.
    getOverview.mockResolvedValue({
      ...NO_HOLDER_WORK,
      released: [{ sourceId: "a01", kind: "BANK", holderId: "001x" }]
    });

    btn(el, /Próximo|Next/).click();
    await flush();
    await flush();
    await flush();
    await flush();
    await flush();

    // The verdict comes from an answer taken AFTER the discovery: the stale one still
    // reported a pending source and could never settle the step.
    expect(getOverview.mock.calls.length).toBeGreaterThan(readsBefore + 1);
    expect(confirmStep).toHaveBeenCalledWith({
      stepKey: "PLUGGY_DISCOVERY",
      expectedVersion: 3,
      evidenceRef: "wizard"
    });
    expect(confirmStep).toHaveBeenCalledWith({
      stepKey: "ACCOUNT_HOLDERS",
      expectedVersion: 4,
      evidenceRef: "wizard"
    });
    expect(step(el, "ACCOUNT_HOLDERS")).toBeNull();
    expect(
      el.shadowRoot.querySelector("c-a-x-f_-l-w-c_add-person-access")
    ).not.toBeNull();
  });

  it("surfaces a conflicting settle and keeps the holder step", async () => {
    canConfigure.mockResolvedValue(true);
    getState.mockResolvedValue(
      STEPS({
        currentStep: "ACCOUNT_HOLDERS",
        version: 3,
        steps: STEPS().steps.map((s) => {
          return s.stepKey === "PLUGGY_DISCOVERY"
            ? { ...s, status: "CONFIRMED" }
            : s;
        })
      })
    );
    confirmStep.mockResolvedValue({ outcome: "CONFLICT" });
    const el = build();
    await flush();
    await flush();
    await flush();
    await flush();

    expect(confirmStep).toHaveBeenCalledWith({
      stepKey: "ACCOUNT_HOLDERS",
      expectedVersion: 3,
      evidenceRef: "wizard"
    });
    expect(el.shadowRoot.querySelector("[data-message]").textContent).toMatch(
      /mudou em outra sessão|changed in another session/i
    );
    // A refused settle is never a reason to take the surface away.
    expect(step(el, "ACCOUNT_HOLDERS")).not.toBeNull();
    expect(
      el.shadowRoot.querySelector("c-a-x-f_-l-w-c_confirm-source-holders")
    ).not.toBeNull();
  });

  it("keeps the holder step rendered when the settle rejects", async () => {
    canConfigure.mockResolvedValue(true);
    getState.mockResolvedValue(
      STEPS({
        currentStep: "ACCOUNT_HOLDERS",
        version: 3,
        steps: STEPS().steps.map((s) => {
          return s.stepKey === "PLUGGY_DISCOVERY"
            ? { ...s, status: "CONFIRMED" }
            : s;
        })
      })
    );
    confirmStep.mockRejectedValue({
      body: { message: "Não foi possível concluir a etapa." }
    });
    const el = build();
    await flush();
    await flush();
    await flush();
    await flush();

    // The rejection is surfaced as the step's message, never as an escaping rejection.
    expect(el.shadowRoot.querySelector("[data-message]").textContent).toMatch(
      /Não foi possível concluir a etapa/i
    );
    expect(step(el, "ACCOUNT_HOLDERS")).not.toBeNull();
    expect(
      el.shadowRoot.querySelector("c-a-x-f_-l-w-c_confirm-source-holders")
    ).not.toBeNull();
    // The wizard is still a working surface: the navigation is rendered.
    expect(btn(el, /Próximo|Next/)).toBeTruthy();

    // Re-entering the step settles it through a NON-awaited call: a rejection there is
    // still handled instead of becoming an unhandled rejection.
    step(el, "PLUGGY_DISCOVERY").click();
    await flush();
    step(el, "ACCOUNT_HOLDERS").click();
    await flush();
    await flush();
    await flush();

    expect(el.shadowRoot.querySelector("[data-message]").textContent).toMatch(
      /Não foi possível concluir a etapa/i
    );
    expect(
      el.shadowRoot.querySelector("c-a-x-f_-l-w-c_confirm-source-holders")
    ).not.toBeNull();
  });
});
