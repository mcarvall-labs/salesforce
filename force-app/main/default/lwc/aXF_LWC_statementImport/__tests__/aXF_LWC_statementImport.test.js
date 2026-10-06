import { createElement } from "lwc";
import AXF_LWC_statementImport from "c/aXF_LWC_statementImport";
import preview from "@salesforce/apex/AXF_CLS_CTRL_StatementImport.preview";
import importStatement from "@salesforce/apex/AXF_CLS_CTRL_StatementImport.importStatement";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_StatementImport.preview",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_StatementImport.importStatement",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flushPromises = () =>
  Array.from({ length: 10 }).reduce(
    (chain) => chain.then(() => undefined),
    Promise.resolve()
  );

const previewResult = {
  newCount: 1,
  duplicateCount: 1,
  errorCount: 0,
  lines: [
    { lineDate: "2026-09-10", description: "A", amount: -1, status: "NEW" },
    { lineDate: "2026-09-11", description: "B", amount: 2, status: "DUPLICATE" }
  ]
};

function setup() {
  const element = createElement("c-a-x-f-l-w-c-statement-import", {
    is: AXF_LWC_statementImport
  });
  element.recordId = "a00000000000001";
  document.body.appendChild(element);
  return element;
}

async function pickFile(element, name = "extrato.ofx") {
  const input = element.shadowRoot.querySelector("lightning-input");
  Object.defineProperty(input, "files", {
    value: [{ name, text: () => Promise.resolve("<OFX>") }]
  });
  input.dispatchEvent(new CustomEvent("change"));
  await flushPromises();
}

describe("c-a-x-f-l-w-c-statement-import", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("previews the chosen file with the status of each line", async () => {
    preview.mockResolvedValue(previewResult);
    const element = setup();
    await pickFile(element);
    expect(preview).toHaveBeenCalledWith({
      recordId: "a00000000000001",
      fileName: "extrato.ofx",
      content: "<OFX>"
    });
    expect(element.shadowRoot.querySelectorAll("tbody tr")).toHaveLength(2);
    expect(element.shadowRoot.textContent).toContain("Já importada");
  });

  it("imports the file after confirmation", async () => {
    preview.mockResolvedValue(previewResult);
    importStatement.mockResolvedValue({
      success: true,
      message: "Importação concluída.",
      imported: 1
    });
    const element = setup();
    await pickFile(element);
    element.shadowRoot.querySelector("lightning-button").click();
    await flushPromises();
    expect(importStatement).toHaveBeenCalledTimes(1);
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("Importação concluída.");
  });

  it("shows the server error when the preview fails", async () => {
    preview.mockRejectedValue({ body: { message: "Formato não suportado." } });
    const element = setup();
    await pickFile(element, "extrato.pdf");
    expect(element.shadowRoot.querySelector('[role="alert"]').textContent).toBe(
      "Formato não suportado."
    );
  });

  it("shows the cut warnings and the repeated line note of the preview", async () => {
    preview.mockResolvedValue({
      newCount: 2,
      duplicateCount: 0,
      errorCount: 0,
      warnings: [
        "Dia 14/09/2026 (limite do arquivo): já há 1 lançamentos importados e o arquivo traz 2."
      ],
      lines: [
        {
          lineDate: "2026-09-14",
          description: "A",
          amount: -3,
          status: "NEW",
          note: "Linha idêntica repetida: 2×"
        }
      ]
    });
    const element = setup();
    await pickFile(element);
    expect(
      element.shadowRoot.querySelector('[role="status"]').textContent
    ).toContain("limite do arquivo");
    expect(element.shadowRoot.querySelector("tbody").textContent).toContain(
      "Linha idêntica repetida: 2×"
    );
  });
});
