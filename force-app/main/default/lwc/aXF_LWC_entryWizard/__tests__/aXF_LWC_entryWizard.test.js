import { createElement } from "lwc";
import Wizard from "c/aXF_LWC_entryWizard";
import getContexts from "@salesforce/apex/AXF_CLS_CTRL_AuthorizedContext.getContexts";
import getFundingSources from "@salesforce/apex/AXF_CLS_CTRL_FinancialEntry.getFundingSources";
import createEntry from "@salesforce/apex/AXF_CLS_CTRL_FinancialEntry.createEntry";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_AuthorizedContext.getContexts",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_FinancialEntry.getFundingSources",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_FinancialEntry.createEntry",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const CONTEXTS = [
  { accountId: "001000000000001", label: "Ana", contextType: "PERSON" },
  { accountId: "001000000000002", label: "Empresa X", contextType: "BUSINESS" }
];

function build() {
  const el = createElement("c-a-x-f_-l-w-c_entry-wizard", { is: Wizard });
  document.body.appendChild(el);
  return el;
}

const flush = () => Promise.resolve();
const settle = async () => {
  for (let i = 0; i < 5; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};

function btn(el, re) {
  return [...el.shadowRoot.querySelectorAll("lightning-button")].find((b) =>
    re.test(b.label)
  );
}

afterEach(() => {
  while (document.body.firstChild) {
    document.body.removeChild(document.body.firstChild);
  }
  jest.clearAllMocks();
});

describe("c-aXF_LWC_entryWizard", () => {
  it("shows a neutral message when there is no authorized context", async () => {
    const el = build();
    getContexts.emit([]);
    await flush();
    expect(el.shadowRoot.textContent).toMatch(
      /autorizada está disponível|authorized .* is available/i
    );
    expect(btn(el, /Próximo|Next/).disabled).toBe(true);
  });

  it("blocks advancing to details until a context is chosen", async () => {
    const el = build();
    getContexts.emit(CONTEXTS);
    await flush();
    expect(btn(el, /Próximo|Next/).disabled).toBe(true);

    el.shadowRoot
      .querySelector("lightning-combobox")
      .dispatchEvent(
        new CustomEvent("change", { detail: { value: CONTEXTS[1].accountId } })
      );
    await flush();
    expect(btn(el, /Próximo|Next/).disabled).toBe(false);
  });

  it("walks the four steps and confirms with the expected payload", async () => {
    createEntry.mockResolvedValue({
      outcome: "CREATED",
      financialTransactionId: "a0X000000000001"
    });
    const el = build();
    getContexts.emit(CONTEXTS);
    getFundingSources.emit([]);
    await flush();

    // step 1: context
    el.shadowRoot
      .querySelector("lightning-combobox")
      .dispatchEvent(
        new CustomEvent("change", { detail: { value: CONTEXTS[1].accountId } })
      );
    await flush();
    btn(el, /Próximo|Next/).click();
    await flush();

    // step 2: details
    const numberInput = el.shadowRoot.querySelector(
      "lightning-input[data-field='magnitude']"
    );
    numberInput.dispatchEvent(
      new CustomEvent("change", { detail: { value: "150.75" } })
    );
    await flush();
    btn(el, /Próximo|Next/).click();
    await flush();

    // step 3: source (cash is the default, always advanceable)
    btn(el, /Próximo|Next/).click();
    await flush();

    // step 4: review + confirm
    expect(el.shadowRoot.textContent).toMatch(/150\.75/);
    btn(el, /Confirmar|Confirm/).click();
    await settle();

    expect(createEntry).toHaveBeenCalledTimes(1);
    const call = createEntry.mock.calls[0][0].input;
    expect(call.accountId).toBe(CONTEXTS[1].accountId);
    expect(call.direction).toBe("DEBIT");
    expect(call.magnitude).toBe(150.75);
    expect(call.bankAccountId).toBeNull();
    expect(call.creditCardId).toBeNull();
    expect(typeof call.clientRequestId).toBe("string");
    expect(call.clientRequestId.length).toBe(36);

    expect(el.shadowRoot.textContent).toMatch(/criado|created/i);
  });

  it("surfaces a conflict without leaving the done state", async () => {
    createEntry.mockResolvedValue({ outcome: "CONFLICT" });
    const el = build();
    getContexts.emit([CONTEXTS[0]]);
    getFundingSources.emit([]);
    await flush(); // single context auto-selected

    btn(el, /Próximo|Next/).click();
    await flush();
    el.shadowRoot
      .querySelector("lightning-input[data-field='magnitude']")
      .dispatchEvent(new CustomEvent("change", { detail: { value: "10" } }));
    await flush();
    btn(el, /Próximo|Next/).click();
    await flush();
    btn(el, /Próximo|Next/).click();
    await flush();
    btn(el, /Confirmar|Confirm/).click();
    await settle();

    expect(el.shadowRoot.querySelector("[data-feedback]").textContent).toMatch(
      /outra tentativa|another attempt/i
    );
    expect(el.shadowRoot.querySelector("[role='status']")).toBeNull();
  });

  it("cancel resets the wizard without calling the server", async () => {
    const el = build();
    getContexts.emit(CONTEXTS);
    getFundingSources.emit([]);
    await flush();

    el.shadowRoot
      .querySelector("lightning-combobox")
      .dispatchEvent(
        new CustomEvent("change", { detail: { value: CONTEXTS[1].accountId } })
      );
    await flush();
    btn(el, /Próximo|Next/).click();
    await flush();

    btn(el, /Cancelar|Cancel/).click();
    await flush();

    expect(createEntry).not.toHaveBeenCalled();
    expect(el.shadowRoot.textContent).toMatch(/Contexto|Context/);
  });
});
