import { createElement } from "lwc";
import Cmp from "c/aXF_LWC_addPersonAccess";
import canConfigure from "@salesforce/apex/AXF_CLS_CTRL_UserProvisioning.canConfigure";
import preflight from "@salesforce/apex/AXF_CLS_CTRL_UserProvisioning.preflight";
import findLinkableUsers from "@salesforce/apex/AXF_CLS_CTRL_UserProvisioning.findLinkableUsers";
import startProvisioning from "@salesforce/apex/AXF_CLS_CTRL_UserProvisioning.start";

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
const btn = (el, re) =>
  [...el.shadowRoot.querySelectorAll("lightning-button")].find((b) =>
    re.test(b.label)
  );

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
    expect(el.shadowRoot.textContent).toMatch(/autoriza|authorized/i);
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
    expect(btn(el, /Voltar|Back/).disabled).toBe(true);
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
    btn(el, /Próximo|Next/).click();
    await flush();

    expect(el.shadowRoot.querySelector("[role='alert']").textContent).toMatch(
      /licença|license/i
    );
    expect(btn(el, /Próximo|Next/).disabled).toBe(true);
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
    btn(el, /Próximo|Next/).click();
    await flush();
    // step 1: email
    const email = el.shadowRoot.querySelector("[data-field='email']");
    email.value = "x@example.com";
    email.dispatchEvent(new CustomEvent("change"));
    await flush();
    btn(el, /Próximo|Next/).click();
    await flush(); // step 2 scope
    btn(el, /Próximo|Next/).click();
    await flush(); // step 3 review
    btn(el, /Confirmar|Confirm/).click();
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
    expect(el.shadowRoot.textContent).toMatch(/1 (de|of) 4/);

    // advancing updates the heading + the announcement
    el.shadowRoot
      .querySelector("lightning-record-picker")
      .dispatchEvent(
        new CustomEvent("change", { detail: { recordId: "001x" } })
      );
    await flush();
    btn(el, /Próximo|Next/).click();
    await flush();
    expect(el.shadowRoot.textContent).toMatch(/2 (de|of) 4/);
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
    btn(el, /Próximo|Next/).click();
    await flush();
    const email = el.shadowRoot.querySelector("[data-field='email']");
    email.value = "x@example.com";
    email.dispatchEvent(new CustomEvent("change"));
    await flush();
    btn(el, /Próximo|Next/).click();
    await flush();
    btn(el, /Próximo|Next/).click();
    await flush();

    const review = el.shadowRoot.querySelector("dl").textContent;
    expect(review).not.toMatch(/CREATE|OWN_DATA/);
    expect(review).toMatch(/Criar novo usuário|Create a new user/);
    expect(review).toMatch(/Participante|Participant/);
  });
});
