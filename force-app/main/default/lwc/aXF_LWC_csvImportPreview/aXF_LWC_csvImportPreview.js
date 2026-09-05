import { LightningElement, api } from "lwc";
import getPolicy from "@salesforce/apex/AXF_CLS_CTRL_CsvImportPreview.getPolicy";
import previewCsv from "@salesforce/apex/AXF_CLS_CTRL_CsvImportPreview.previewCsv";
import confirmCsv from "@salesforce/apex/AXF_CLS_CTRL_CsvImportPreview.confirmCsv";

const ERROR_LABELS = {
  EMPTY_FILE: "O arquivo está vazio.",
  UNSUPPORTED_STRUCTURE:
    "O arquivo não tem as colunas esperadas (Data, Descrição, Entrada, Saída, Saldo).",
  ROW_LIMIT_EXCEEDED: "O arquivo tem mais linhas do que o permitido.",
  INVALID_DATE: "Data inválida.",
  INVALID_AMOUNT: "Valor de entrada ou saída inválido.",
  MISSING_AMOUNT: "Faltam os valores de entrada e saída.",
  MISSING_BALANCE: "Falta o saldo.",
  INVALID_BALANCE: "Saldo inválido.",
  BALANCE_NOT_CONSERVED:
    "O saldo não confere com o saldo anterior mais entrada/saída."
};

const STEP_LABELS = {
  FILE: "Etapa 1 de 5: Arquivo",
  PREVIEW: "Etapa 2 de 5: Prévia",
  REVIEW: "Etapa 3 de 5: Revisão",
  CONFIRM: "Etapa 4 de 5: Confirmação",
  RESULT: "Etapa 5 de 5: Resultado"
};

export default class AXF_LWC_csvImportPreview extends LightningElement {
  @api recordId;

  step = "FILE";
  policy;
  policyError;
  fileName;
  errorMessage;
  loading = false;
  previewResult;
  confirmResult;
  acknowledge = false;
  pendingContent;
  pendingFileName;
  focusStepHeading = false;

  connectedCallback() {
    getPolicy()
      .then((data) => {
        this.policy = data;
        this.policyError = undefined;
      })
      .catch((error) => {
        this.policy = undefined;
        this.policyError =
          (error.body && error.body.message) ||
          "Não foi possível carregar os limites de importação.";
      });
  }

  renderedCallback() {
    if (this.focusStepHeading) {
      this.focusStepHeading = false;
      const heading = this.template.querySelector('[data-id="step-heading"]');
      if (heading) {
        heading.focus();
      }
    }
  }

  get stepLabel() {
    return STEP_LABELS[this.step];
  }

  get isFileStep() {
    return this.step === "FILE";
  }

  get isPreviewStep() {
    return this.step === "PREVIEW";
  }

  get isReviewStep() {
    return this.step === "REVIEW";
  }

  get isConfirmStep() {
    return this.step === "CONFIRM";
  }

  get isResultStep() {
    return this.step === "RESULT";
  }

  get acceptedFormats() {
    return this.policy ? "." + this.policy.allowedExtensions : ".csv";
  }

  get disableUpload() {
    return this.loading || !!this.policyError;
  }

  get hasSample() {
    return !!(
      this.previewResult &&
      this.previewResult.parseResult &&
      this.previewResult.parseResult.sample.length
    );
  }

  get sampleRows() {
    if (!this.hasSample) return [];
    return this.previewResult.parseResult.sample.map((row) =>
      this.decorateRow(row)
    );
  }

  get rejectionRows() {
    if (!this.previewResult || !this.previewResult.parseResult) return [];
    return this.previewResult.parseResult.rejections.map((row) =>
      this.decorateRow(row)
    );
  }

  get hasRejections() {
    return this.rejectionRows.length > 0;
  }

  get summaryCounts() {
    const pr = this.previewResult && this.previewResult.parseResult;
    if (!pr) return null;
    return {
      total: pr.totalRows,
      valid: pr.validRows,
      rejected: pr.rejectedRows
    };
  }

  get confirmDisabled() {
    return this.loading || (this.hasRejections && !this.acknowledge);
  }

  decorateRow(row) {
    return {
      ...row,
      errorText: (row.errorCodes || [])
        .map((code) => ERROR_LABELS[code] || code)
        .join(" ")
    };
  }

  async handleFileChange(event) {
    this.errorMessage = undefined;
    const inputEl = event.target;
    const file = inputEl.files && inputEl.files[0];
    if (!file) return;
    this.fileName = file.name;

    if (
      this.policy &&
      this.policy.maxFileSizeBytes &&
      file.size > this.policy.maxFileSizeBytes
    ) {
      this.errorMessage = "Arquivo excede o tamanho máximo permitido.";
      return;
    }

    this.loading = true;
    try {
      const base64Content = await this.readAsBase64(file);
      const result = await previewCsv({
        input: {
          accountId: this.recordId,
          fileName: file.name,
          base64Content
        }
      });
      this.previewResult = result;
      if (result.outcome === "OK") {
        this.pendingContent = base64Content;
        this.pendingFileName = file.name;
        this.goToStep("PREVIEW");
      } else {
        this.errorMessage =
          result.message || "Não foi possível processar o arquivo.";
        if (result.parseResult) {
          this.goToStep("REVIEW");
        }
      }
    } catch (e) {
      this.errorMessage =
        (e.body && e.body.message) || "Não foi possível processar o arquivo.";
    } finally {
      this.loading = false;
      if (inputEl) {
        inputEl.value = null;
      }
    }
  }

  handleGoToReview() {
    this.goToStep("REVIEW");
  }

  handleGoToConfirm() {
    this.errorMessage = undefined;
    this.goToStep("CONFIRM");
  }

  handleAcknowledgeChange(event) {
    this.acknowledge = event.target.checked;
  }

  handleBackToFile() {
    this.previewResult = undefined;
    this.confirmResult = undefined;
    this.pendingContent = undefined;
    this.acknowledge = false;
    this.errorMessage = undefined;
    this.goToStep("FILE");
  }

  handleBackToPreview() {
    this.errorMessage = undefined;
    this.goToStep("PREVIEW");
  }

  async handleConfirm() {
    this.errorMessage = undefined;
    this.loading = true;
    try {
      const result = await confirmCsv({
        input: {
          accountId: this.recordId,
          fileName: this.pendingFileName,
          base64Content: this.pendingContent,
          expectedParserVersion: this.previewResult.parseResult.parserVersion,
          acknowledgeRejections: this.acknowledge
        }
      });
      this.confirmResult = result;
      if (result.outcome === "PUBLISHED") {
        this.goToStep("RESULT");
      } else if (result.outcome === "NEEDS_ACKNOWLEDGE") {
        this.errorMessage = result.message;
      } else if (result.outcome === "STALE_PREVIEW") {
        this.errorMessage = result.message;
        this.goToStep("FILE");
      } else {
        this.errorMessage =
          result.message || "Não foi possível concluir a importação.";
      }
    } catch (e) {
      this.errorMessage =
        (e.body && e.body.message) || "Não foi possível concluir a importação.";
    } finally {
      this.loading = false;
    }
  }

  goToStep(step) {
    this.step = step;
    this.focusStepHeading = true;
  }

  readAsBase64(file) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => {
        const result = reader.result || "";
        const commaIndex = result.indexOf(",");
        resolve(commaIndex >= 0 ? result.substring(commaIndex + 1) : result);
      };
      reader.onerror = () => reject(reader.error);
      reader.readAsDataURL(file);
    });
  }
}
