import { createElement } from "lwc";
import AXF_LWC_contractGenerate from "c/aXF_LWC_contractGenerate";
import generate from "@salesforce/apex/AXF_CLS_CTRL_ContractGeneration.generate";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_ContractGeneration.generate",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => Promise.resolve();

function setup() {
  const element = createElement("c-axf-lwc-contract-generate", {
    is: AXF_LWC_contractGenerate
  });
  element.recordId = "a00000000000001AAA";
  document.body.appendChild(element);
  const toasts = [];
  element.addEventListener("lightning__showtoast", (e) =>
    toasts.push(e.detail)
  );
  return { element, toasts };
}

describe("c-axf-lwc-contract-generate", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows a success toast with the counters", async () => {
    generate.mockResolvedValue({ created: 12, updated: 0, messages: [] });
    const { element, toasts } = setup();
    await element.invoke();
    await flush();
    expect(generate).toHaveBeenCalledWith({ contractId: "a00000000000001AAA" });
    expect(toasts[0].variant).toBe("success");
    expect(toasts[0].message).toContain("12 criado(s)");
  });

  it("warns when the contract was skipped", async () => {
    generate.mockResolvedValue({
      created: 0,
      updated: 0,
      messages: ["Contrato: informe o valor."]
    });
    const { element, toasts } = setup();
    await element.invoke();
    expect(toasts[0].variant).toBe("warning");
    expect(toasts[0].message).toContain("informe o valor");
  });

  it("shows the server error", async () => {
    generate.mockRejectedValue({ body: { message: "Sem permissão." } });
    const { element, toasts } = setup();
    await element.invoke();
    expect(toasts[0].variant).toBe("error");
    expect(toasts[0].message).toBe("Sem permissão.");
  });
});
