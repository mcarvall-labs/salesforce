import { createElement } from "lwc";
import ContextBar from "c/aXF_LWC_contextBar";
import getContexts from "@salesforce/apex/AXF_CLS_CTRL_AuthorizedContext.getContexts";
import { publish } from "lightning/messageService";
import CONTEXT_CHANGED from "@salesforce/messageChannel/AXF_ContextChanged__c";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_AuthorizedContext.getContexts",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true },
);

const flush = () => Promise.resolve();
const contexts = [
  {
    accountId: "001000000000001",
    label: "Ana",
    contextType: "PERSON",
    presentationCurrency: "BRL",
  },
  {
    accountId: "001000000000002",
    label: "Axon Ltda",
    contextType: "BUSINESS",
    presentationCurrency: "BRL",
  },
];

function build() {
  const element = createElement("c-a-x-f_-l-w-c_context-bar", {
    is: ContextBar,
  });
  document.body.appendChild(element);
  return element;
}

afterEach(() => {
  while (document.body.firstChild)
    document.body.removeChild(document.body.firstChild);
  jest.clearAllMocks();
});

describe("c-aXF_LWC_contextBar", () => {
  it("renders only contexts returned by the secure controller", async () => {
    const element = build();
    getContexts.emit(contexts);
    await flush();
    expect(
      element.shadowRoot.querySelector("lightning-combobox").options,
    ).toHaveLength(2);
  });

  it("publishes and announces an authorized context change", async () => {
    const element = build();
    getContexts.emit(contexts);
    await flush();
    const picker = element.shadowRoot.querySelector("lightning-combobox");
    picker.dispatchEvent(
      new CustomEvent("change", { detail: { value: contexts[1].accountId } }),
    );
    await flush();
    expect(publish).toHaveBeenCalledWith(
      undefined,
      CONTEXT_CHANGED,
      expect.objectContaining({
        accountId: contexts[1].accountId,
        contextType: "BUSINESS",
      }),
    );
    expect(
      element.shadowRoot.querySelector("[aria-live='polite']").textContent,
    ).toMatch(/Axon Ltda/);
  });

  it("shows a neutral empty state", async () => {
    const element = build();
    getContexts.emit([]);
    await flush();
    expect(
      element.shadowRoot.querySelector("[role='status']").textContent,
    ).toMatch(/Nenhuma pessoa ou empresa autorizada/);
  });

  it("shows a sanitized error with retry", async () => {
    const element = build();
    getContexts.error();
    await flush();
    expect(
      element.shadowRoot.querySelector("[role='alert']").textContent,
    ).toMatch(/Não foi possível carregar/);
  });
});
