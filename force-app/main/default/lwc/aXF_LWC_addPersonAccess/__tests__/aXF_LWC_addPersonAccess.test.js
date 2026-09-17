import { createElement } from "lwc";
import Cmp from "c/aXF_LWC_addPersonAccess";
import canConfigure from "@salesforce/apex/AXF_CLS_CTRL_UserProvisioning.canConfigure";
import preflight from "@salesforce/apex/AXF_CLS_CTRL_UserProvisioning.preflight";
import findLinkableUsers from "@salesforce/apex/AXF_CLS_CTRL_UserProvisioning.findLinkableUsers";
import startProvisioning from "@salesforce/apex/AXF_CLS_CTRL_UserProvisioning.start";
import getStatus from "@salesforce/apex/AXF_CLS_CTRL_UserProvisioning.getStatus";
import resumeProvisioning from "@salesforce/apex/AXF_CLS_CTRL_UserProvisioning.resume";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_UserProvisioning.canConfigure",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_UserProvisioning.preflight",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_UserProvisioning.findLinkableUsers",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_UserProvisioning.start",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_UserProvisioning.getStatus",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_UserProvisioning.resume",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
// sfdx-lwc-jest stubs every un-mocked @salesforce/label import with its own
// resource path (e.g. "c.AXF_AddPersonAccess_next"); see labelPath() below.
// This one drives the step-of-4 interpolation, so it gets a real templated
// value instead.
jest.mock(
  "@salesforce/label/c.AXF_AddPersonAccess_stepOf",
  () => ({ default: "Step {0} of {1}" }),
  { virtual: true }
);

function build(config = true, licensesFree = 3) {
  const el = createElement("c-a-x-f_-l-w-c_add-person-access", { is: Cmp });
  document.body.appendChild(el);
  canConfigure.emit(config);
  preflight.emit({
    canConfigure: config,
    salesforceLicensesFree: licensesFree
  });
  findLinkableUsers.emit([]);
  return el;
}
const flush = () => Promise.resolve();
// Flushes the microtask queue of the async handlers under test.
const settle = () =>
  Promise.resolve()
    .then(() => {})
    .then(() => {})
    .then(() => {})
    .then(() => {})
    .then(() => {})
    .then(() => {});
// Mirrors the observation policy declared by the component (AXF-107 AC5); the
// component's own fields are private, so the test drives the same windows.
const POLL_MS = 2500;
const STALL_MS = 45000;
// One fake-time window of the observation loop, then its microtasks.
const tick = async (ms) => {
  jest.advanceTimersByTime(ms);
  await settle();
};
// Custom Label imports resolve in Jest to their own resource path
// (e.g. "c.AXF_AddPersonAccess_next"), not the real translated text; that
// resource path is how these tests verify the right label is wired in.
const LABEL_PREFIX = "c.AXF_AddPersonAccess_";
const labelPath = (key) => `${LABEL_PREFIX}${key}`;
const btn = (el, key) =>
  [...el.shadowRoot.querySelectorAll("lightning-button")].find(
    (b) => b.label === labelPath(key)
  );

const startedResult = () => ({
  provisioningId: "a0Tx",
  outcome: "STARTED",
  status: "PENDING",
  currentStep: "CREATE_OR_LINK_PERSON",
  message: "Provisionamento iniciado.",
  linkedUserId: null
});
const runningResult = () => ({
  provisioningId: "a0Tx",
  outcome: null,
  status: "RUNNING",
  currentStep: "CREATE_OR_LINK_USER",
  message: "Pessoa confirmada.",
  linkedUserId: null
});

// Walks the four wizard steps up to the review step.
async function advanceToReview(el) {
  el.shadowRoot
    .querySelector("lightning-record-picker")
    .dispatchEvent(new CustomEvent("change", { detail: { recordId: "001x" } }));
  await flush();
  btn(el, "next").click();
  await flush();
  const email = el.shadowRoot.querySelector("[data-field='email']");
  email.value = "x@example.com";
  email.dispatchEvent(new CustomEvent("change"));
  await flush();
  btn(el, "next").click();
  await flush();
  btn(el, "next").click();
  await flush();
}

// Confirms the request with a given start response.
async function confirm(el, response) {
  startProvisioning.mockResolvedValue(response);
  await advanceToReview(el);
  btn(el, "confirm").click();
  await settle();
}

beforeEach(() => jest.useFakeTimers());
afterEach(() => {
  jest.clearAllTimers();
  jest.useRealTimers();
  while (document.body.firstChild) {
    document.body.removeChild(document.body.firstChild);
  }
  jest.clearAllMocks();
});

describe("c-aXF_LWC_addPersonAccess", () => {
  it("shows the forbidden message without configure authority", async () => {
    const el = build(false);
    await flush();
    expect(
      el.shadowRoot.querySelector("lightning-progress-indicator")
    ).toBeNull();
    expect(el.shadowRoot.textContent).toContain(labelPath("forbidden"));
  });

  it("renders the wizard for an authorized configurator", async () => {
    const el = build(true);
    await flush();
    expect(
      el.shadowRoot.querySelector("lightning-progress-indicator")
    ).not.toBeNull();
    expect(
      el.shadowRoot.querySelector("lightning-record-picker")
    ).not.toBeNull();
    expect(btn(el, "back").disabled).toBe(true);
  });

  it("blocks CREATE when no Salesforce license is free", async () => {
    const el = build(true, 0);
    await flush();
    // step 0 -> pick a person, advance to step 1
    el.shadowRoot
      .querySelector("lightning-record-picker")
      .dispatchEvent(
        new CustomEvent("change", { detail: { recordId: "001x" } })
      );
    await flush();
    btn(el, "next").click();
    await flush();

    expect(el.shadowRoot.querySelector("[role='alert']").textContent).toContain(
      labelPath("licenseWarn")
    );
    expect(btn(el, "next").disabled).toBe(true);
  });

  it("calls start and begins polling on confirm", async () => {
    startProvisioning.mockResolvedValue({
      provisioningId: "a0Tx",
      outcome: "STARTED",
      status: "PENDING",
      currentStep: "CREATE_OR_LINK_PERSON",
      message: "Provisionamento iniciado."
    });
    const el = build(true, 3);
    await flush();

    el.shadowRoot
      .querySelector("lightning-record-picker")
      .dispatchEvent(
        new CustomEvent("change", { detail: { recordId: "001x" } })
      );
    await flush();
    btn(el, "next").click();
    await flush();
    // step 1: email
    const email = el.shadowRoot.querySelector("[data-field='email']");
    email.value = "x@example.com";
    email.dispatchEvent(new CustomEvent("change"));
    await flush();
    btn(el, "next").click();
    await flush(); // step 2 scope
    btn(el, "next").click();
    await flush(); // step 3 review
    btn(el, "confirm").click();
    await flush();
    await flush();

    expect(startProvisioning).toHaveBeenCalledTimes(1);
    expect(el.shadowRoot.querySelector("lightning-spinner")).not.toBeNull();
    // the running region is focusable so focus lands on the status update
    expect(
      el.shadowRoot.querySelector("[data-feedback]").getAttribute("tabindex")
    ).toBe("-1");
  });

  it("has a focusable step heading and a 'step X of 4' announcement", async () => {
    const el = build(true);
    await flush();
    const heading = el.shadowRoot.querySelector("[data-step-heading]");
    expect(heading).not.toBeNull();
    expect(heading.getAttribute("tabindex")).toBe("-1");
    expect(heading.textContent.trim().length).toBeGreaterThan(0);
    expect(el.shadowRoot.textContent).toMatch(/Step 1 of 4/);

    // advancing updates the heading + the announcement
    el.shadowRoot
      .querySelector("lightning-record-picker")
      .dispatchEvent(
        new CustomEvent("change", { detail: { recordId: "001x" } })
      );
    await flush();
    btn(el, "next").click();
    await flush();
    expect(el.shadowRoot.textContent).toMatch(/Step 2 of 4/);
  });

  it("shows human-readable labels on the review step", async () => {
    const el = build(true, 3);
    await flush();
    el.shadowRoot
      .querySelector("lightning-record-picker")
      .dispatchEvent(
        new CustomEvent("change", { detail: { recordId: "001x" } })
      );
    await flush();
    btn(el, "next").click();
    await flush();
    const email = el.shadowRoot.querySelector("[data-field='email']");
    email.value = "x@example.com";
    email.dispatchEvent(new CustomEvent("change"));
    await flush();
    btn(el, "next").click();
    await flush();
    btn(el, "next").click();
    await flush();

    const review = el.shadowRoot.querySelector("dl").textContent;
    expect(review).not.toMatch(/CREATE|OWN_DATA/);
    expect(review).toContain(labelPath("modeCreate"));
    expect(review).toContain(labelPath("scopeOwn"));
  });

  // ---- AXF-107 ----

  it("removes the spinner and confirms linkage when the chain reaches DONE", async () => {
    const el = build(true, 3);
    await flush();
    await confirm(el, startedResult());
    expect(el.shadowRoot.querySelector("lightning-spinner")).not.toBeNull();

    getStatus.mockResolvedValue({
      provisioningId: "a0Tx",
      outcome: null,
      status: "SUCCEEDED",
      currentStep: "DONE",
      message: "Acesso concluído.",
      linkedUserId: "005xLinked"
    });
    await tick(POLL_MS);

    expect(el.shadowRoot.querySelector("lightning-spinner")).toBeNull();
    expect(el.shadowRoot.textContent).toContain(labelPath("done"));
    // the confirmed linkage is displayed, not only a success sentence
    expect(el.shadowRoot.textContent).toContain("005xLinked");
    expect(el.shadowRoot.textContent).toContain(labelPath("linkedUser"));

    // polling stopped: no further status fetch after a terminal outcome
    getStatus.mockClear();
    await tick(30000);
    expect(getStatus).not.toHaveBeenCalled();
  });

  it("does not poll when the start response is already terminal", async () => {
    const el = build(true, 3);
    await flush();
    await confirm(el, {
      provisioningId: null,
      outcome: "INVALID",
      status: null,
      currentStep: null,
      message: "Selecione uma pessoa (Person Account) ja cadastrada."
    });

    expect(el.shadowRoot.querySelector("lightning-spinner")).toBeNull();
    expect(el.shadowRoot.querySelector("[role='alert']")).not.toBeNull();
    // a terminal outcome offers no resume, only the way back to the form
    expect(btn(el, "retry")).toBeUndefined();
    expect(btn(el, "backToForm")).toBeDefined();

    await tick(30000);
    expect(getStatus).not.toHaveBeenCalled();
    expect(resumeProvisioning).not.toHaveBeenCalled();
  });

  it("exits indefinite loading when the operation stalls in RUNNING", async () => {
    const el = build(true, 3);
    await flush();
    await confirm(el, startedResult());

    getStatus.mockResolvedValue(runningResult());
    await tick(POLL_MS);
    expect(el.shadowRoot.querySelector("lightning-spinner")).not.toBeNull();

    // the persisted step never changes: the bounded observation must end
    await tick(STALL_MS);

    expect(el.shadowRoot.querySelector("lightning-spinner")).toBeNull();
    expect(el.shadowRoot.textContent).toContain(labelPath("stalled"));
    expect(btn(el, "retry")).toBeDefined();
    // the unknown outcome is not reported as a failure
    expect(el.shadowRoot.querySelector("[role='alert']")).toBeNull();

    getStatus.mockClear();
    await tick(30000);
    expect(getStatus).not.toHaveBeenCalled();
  });

  it("stops loading and offers recovery after repeated status failures", async () => {
    const el = build(true, 3);
    await flush();
    await confirm(el, startedResult());

    getStatus.mockRejectedValue({
      body: { message: "Serviço de provisionamento indisponível." }
    });
    await tick(POLL_MS);
    await tick(POLL_MS);
    await tick(POLL_MS);

    expect(getStatus).toHaveBeenCalledTimes(3);
    expect(el.shadowRoot.querySelector("lightning-spinner")).toBeNull();
    // the server-provided error detail is real text, not a label
    expect(el.shadowRoot.textContent).toMatch(/indispon/i);
    expect(btn(el, "retry")).toBeDefined();
    // the UI limit never claims the server job failed nor provisions again
    expect(startProvisioning).toHaveBeenCalledTimes(1);

    const calls = getStatus.mock.calls.length;
    await tick(30000);
    expect(getStatus).toHaveBeenCalledTimes(calls);
  });

  it("resumes on retry without leaving duplicate timers", async () => {
    const el = build(true, 3);
    await flush();
    await confirm(el, startedResult());

    getStatus.mockResolvedValue(runningResult());
    await tick(POLL_MS);
    // the persisted step stops changing: the bounded observation reaches its stall
    await tick(STALL_MS);
    expect(el.shadowRoot.querySelector("lightning-spinner")).toBeNull();

    resumeProvisioning.mockResolvedValue({
      provisioningId: "a0Tx",
      outcome: "RESUMED",
      status: "RUNNING",
      currentStep: "CREATE_OR_LINK_USER",
      message: "Provisionamento retomado da etapa pendente."
    });
    btn(el, "retry").click();
    await settle();

    expect(resumeProvisioning).toHaveBeenCalledTimes(1);
    expect(el.shadowRoot.querySelector("lightning-spinner")).not.toBeNull();
    // one interval per watch cycle: a single window fetches exactly once
    getStatus.mockClear();
    await tick(POLL_MS);
    expect(getStatus).toHaveBeenCalledTimes(1);

    // a second stall followed by a terminal resume response stops the polling
    await tick(STALL_MS);
    resumeProvisioning.mockResolvedValue({
      provisioningId: "a0Tx",
      outcome: "ALREADY_DONE",
      status: "SUCCEEDED",
      currentStep: "DONE",
      message: "Acesso concluído.",
      linkedUserId: "005xLinked"
    });
    btn(el, "retry").click();
    await settle();

    expect(el.shadowRoot.querySelector("lightning-spinner")).toBeNull();
    getStatus.mockClear();
    await tick(30000);
    expect(getStatus).not.toHaveBeenCalled();
  });

  it("offers resume for a retryable failure and only the form for a terminal one", async () => {
    const el = build(true, 3);
    await flush();
    await confirm(el, startedResult());

    getStatus.mockResolvedValue({
      provisioningId: "a0Tx",
      outcome: null,
      status: "FAILED_RETRYABLE",
      currentStep: "ASSIGN_PSG",
      message: "O nivel de acesso ainda nao esta efetivo. Retome."
    });
    await tick(POLL_MS);
    expect(el.shadowRoot.querySelector("lightning-spinner")).toBeNull();
    expect(el.shadowRoot.querySelector("[role='alert']")).not.toBeNull();
    expect(btn(el, "retry")).toBeDefined();

    resumeProvisioning.mockResolvedValue({
      provisioningId: "a0Tx",
      outcome: "CONFLICT",
      status: "FAILED_TERMINAL",
      currentStep: "CREATE_OR_LINK_USER",
      message: "Esse usuario ja esta vinculado a outra pessoa."
    });
    btn(el, "retry").click();
    await settle();

    expect(btn(el, "retry")).toBeUndefined();
    expect(btn(el, "backToForm")).toBeDefined();
    getStatus.mockClear();
    await tick(30000);
    expect(getStatus).not.toHaveBeenCalled();
  });

  it("clears polling when the component disconnects", async () => {
    const el = build(true, 3);
    await flush();
    await confirm(el, startedResult());

    getStatus.mockResolvedValue(runningResult());
    await tick(POLL_MS);
    expect(getStatus).toHaveBeenCalledTimes(1);

    // the wizard skips the optional step or the user navigates away
    document.body.removeChild(el);
    getStatus.mockClear();
    await tick(30000);
    expect(getStatus).not.toHaveBeenCalled();
  });

  it("leaves the optional step without reporting provisioning as successful", async () => {
    const el = build(true, 3);
    await flush();
    await confirm(el, startedResult());

    getStatus.mockResolvedValue(runningResult());
    await tick(POLL_MS);

    btn(el, "leave").click();
    await flush();

    expect(el.shadowRoot.querySelector("lightning-spinner")).toBeNull();
    expect(el.shadowRoot.textContent).not.toContain(labelPath("done"));
    // back on the form, so the entry point can resume the same request
    expect(
      el.shadowRoot.querySelector("lightning-progress-indicator")
    ).not.toBeNull();
    getStatus.mockClear();
    await tick(30000);
    expect(getStatus).not.toHaveBeenCalled();

    startProvisioning.mockResolvedValue({
      provisioningId: "a0Tx",
      outcome: "RESUMED",
      status: "RUNNING",
      currentStep: "CREATE_OR_LINK_USER",
      message: "Provisionamento retomado da etapa pendente."
    });
    btn(el, "confirm").click();
    await settle();
    expect(startProvisioning).toHaveBeenCalledTimes(2);
  });

  it("shows a human-readable step name instead of the raw checkpoint enum", async () => {
    const el = build(true, 3);
    await flush();
    await confirm(el, startedResult());

    getStatus.mockResolvedValue(runningResult()); // currentStep: CREATE_OR_LINK_USER
    await tick(POLL_MS);
    await tick(STALL_MS);

    expect(el.shadowRoot.textContent).not.toMatch(/CREATE_OR_LINK_USER/);
    expect(el.shadowRoot.textContent).toContain(
      labelPath("stepNameCreateOrLinkUser")
    );
  });

  it("explains what Resume and Leave each do once a resume is offered", async () => {
    const el = build(true, 3);
    await flush();
    await confirm(el, startedResult());

    getStatus.mockResolvedValue(runningResult());
    await tick(POLL_MS);
    await tick(STALL_MS);

    expect(el.shadowRoot.textContent).toContain(labelPath("resumeHint"));
    expect(el.shadowRoot.textContent).toContain(labelPath("leaveHint"));
  });

  it("lets another person be added right after a completed provisioning", async () => {
    const el = build(true, 3);
    await flush();
    await confirm(el, startedResult());

    getStatus.mockResolvedValue({
      provisioningId: "a0Tx",
      outcome: null,
      status: "SUCCEEDED",
      currentStep: "DONE",
      message: "Acesso concluído.",
      linkedUserId: "005xLinked"
    });
    await tick(POLL_MS);

    const addAnother = btn(el, "close");
    expect(addAnother).toBeDefined();
    addAnother.click();
    await flush();

    expect(
      el.shadowRoot.querySelector("lightning-record-picker")
    ).not.toBeNull();
    expect(el.shadowRoot.textContent).toMatch(/Step 1 of 4/);
  });
});
