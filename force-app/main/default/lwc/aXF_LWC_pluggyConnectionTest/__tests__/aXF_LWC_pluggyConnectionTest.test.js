import { createElement } from "lwc";
import AXF_LWC_pluggyConnectionTest from "c/aXF_LWC_pluggyConnectionTest";
import testAndSync from "@salesforce/apex/AXF_CLS_CTRL_PluggyConnection.testAndSync";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_PluggyConnection.testAndSync",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

function setup() {
  const element = createElement("c-axf-lwc-pluggy-connection-test", {
    is: AXF_LWC_pluggyConnectionTest
  });
  element.recordId = "a00000000000001AAA";
  document.body.appendChild(element);
  const toasts = [];
  element.addEventListener("lightning__showtoast", (e) =>
    toasts.push(e.detail)
  );
  return { element, toasts };
}

describe("c-axf-lwc-pluggy-connection-test", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows a success toast with the counters", async () => {
    testAndSync.mockResolvedValue({
      success: true,
      message: "Conexão válida.",
      accounts: 2,
      cards: 1
    });
    const { element, toasts } = setup();
    await element.invoke();
    expect(testAndSync).toHaveBeenCalledWith({
      connectionId: "a00000000000001AAA"
    });
    expect(toasts[0].variant).toBe("success");
    expect(toasts[0].message).toContain("2 conta(s) e 1 cartão(ões)");
  });

  it("shows the failure message", async () => {
    testAndSync.mockResolvedValue({
      success: false,
      message: "Item Id não encontrado no Pluggy."
    });
    const { element, toasts } = setup();
    await element.invoke();
    expect(toasts[0].variant).toBe("error");
    expect(toasts[0].message).toContain("não encontrado");
  });

  it("shows the server error", async () => {
    testAndSync.mockRejectedValue({ body: { message: "Sem permissão." } });
    const { element, toasts } = setup();
    await element.invoke();
    expect(toasts[0].variant).toBe("error");
    expect(toasts[0].message).toBe("Sem permissão.");
  });
});
