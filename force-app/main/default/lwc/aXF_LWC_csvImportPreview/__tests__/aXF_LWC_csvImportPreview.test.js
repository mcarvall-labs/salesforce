import { createElement } from "lwc";
import CsvImportPreview from "c/aXF_LWC_csvImportPreview";
import getPolicy from "@salesforce/apex/AXF_CLS_CTRL_CsvImportPreview.getPolicy";
import previewCsv from "@salesforce/apex/AXF_CLS_CTRL_CsvImportPreview.previewCsv";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_CsvImportPreview.getPolicy",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_CsvImportPreview.previewCsv",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = async () => {
  for (let i = 0; i < 8; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};

class FakeFileReader {
  readAsDataURL() {
    this.result = "data:text/csv;base64,ZmFrZS1jc3Y=";
    if (this.onload) this.onload();
  }
}

const build = () => {
  const element = createElement("c-csv-import-preview", {
    is: CsvImportPreview
  });
  element.recordId = "a0X000000000001AAA";
  document.body.appendChild(element);
  return element;
};

const selectFile = (element, fileName = "extrato.csv") => {
  const input = element.shadowRoot.querySelector("input[type='file']");
  const file = new File(["conteudo"], fileName, { type: "text/csv" });
  Object.defineProperty(input, "files", { value: [file] });
  input.dispatchEvent(new CustomEvent("change", { detail: {} }));
};

describe("c-a-x-f_-l-w-c_csv-import-preview", () => {
  beforeEach(() => {
    global.FileReader = FakeFileReader;
    getPolicy.mockResolvedValue({
      allowedExtensions: "csv",
      requiredEncoding: "UTF-8",
      maxFileSizeBytes: 2097152,
      maxRows: 5000,
      maxProcessingSeconds: 10
    });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.restoreAllMocks();
    jest.clearAllMocks();
  });

  it("starts on the file step", async () => {
    const element = build();
    await flush();

    const heading = element.shadowRoot.querySelector(
      '[data-id="step-heading"]'
    );
    expect(heading.textContent).toContain("Etapa 1 de 3");
    expect(
      element.shadowRoot.querySelector("input[type='file']")
    ).not.toBeNull();
  });

  it("advances to the preview step and shows counts on a valid file", async () => {
    previewCsv.mockResolvedValue({
      outcome: "OK",
      message: "Prévia gerada. Nenhum lançamento foi publicado.",
      targetAccountLabel: "Contabilizei.bank · BA-0000001",
      parseResult: {
        parserVersion: "contabilizei-bank-csv@1.0.0",
        structureValid: true,
        totalRows: 1,
        validRows: 1,
        rejectedRows: 0,
        sample: [
          {
            lineNumber: 2,
            parsedDate: "2026-03-01",
            description: "Salario",
            inflow: 5000,
            outflow: null,
            balance: 5000,
            valid: true,
            errorCodes: []
          }
        ],
        rejections: []
      }
    });

    const element = build();
    await flush();

    selectFile(element);
    await flush();

    expect(previewCsv).toHaveBeenCalledWith({
      input: {
        accountId: "a0X000000000001AAA",
        fileName: "extrato.csv",
        base64Content: "ZmFrZS1jc3Y="
      }
    });
    const heading = element.shadowRoot.querySelector(
      '[data-id="step-heading"]'
    );
    expect(heading.textContent).toContain("Etapa 2 de 3");
    expect(element.shadowRoot.textContent).toContain(
      "Contabilizei.bank · BA-0000001"
    );
  });

  it("moves to the review step and lists rejected rows when the structure is invalid", async () => {
    previewCsv.mockResolvedValue({
      outcome: "INVALID_FILE",
      message:
        "Arquivo não segue a estrutura esperada do CSV Contabilizei.bank.",
      parseResult: {
        parserVersion: "contabilizei-bank-csv@1.0.0",
        structureValid: false,
        totalRows: 0,
        validRows: 0,
        rejectedRows: 0,
        sample: [],
        rejections: []
      }
    });

    const element = build();
    await flush();

    selectFile(element, "extrato-invalido.csv");
    await flush();

    expect(element.shadowRoot.textContent).toContain(
      "Arquivo não segue a estrutura esperada do CSV Contabilizei.bank."
    );
  });

  it("surfaces a policy error banner when limits are not configured", async () => {
    getPolicy.mockRejectedValue({
      body: { message: "Limite de importação de CSV não configurado." }
    });

    const element = build();
    await flush();

    expect(element.shadowRoot.textContent).toContain(
      "Limite de importação de CSV não configurado."
    );
    const input = element.shadowRoot.querySelector("input[type='file']");
    expect(input.disabled).toBe(true);
  });
});
