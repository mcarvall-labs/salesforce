import { LightningElement, api } from "lwc";
import preview from "@salesforce/apex/AXF_CLS_CTRL_StatementImport.preview";
import importStatement from "@salesforce/apex/AXF_CLS_CTRL_StatementImport.importStatement";

const STATUS_LABELS = {
  NEW: "Nova",
  DUPLICATE: "Já importada",
  ERROR: "Erro"
};

export default class AXF_LWC_statementImport extends LightningElement {
  @api recordId;
  fileName;
  content;
  summary;
  rows = [];
  isBusy = false;
  message;
  success = false;

  get confirmDisabled() {
    return this.isBusy || !this.summary || this.summary.newCount === 0;
  }

  get messageClass() {
    return this.success ? "slds-text-color_success" : "slds-text-color_error";
  }

  async handleFile(event) {
    const file = event.target.files[0];
    this.reset();
    if (!file) {
      return;
    }
    this.fileName = file.name;
    this.content = await file.text();
    this.isBusy = true;
    try {
      const result = await preview({
        recordId: this.recordId,
        fileName: this.fileName,
        content: this.content
      });
      this.summary = result;
      this.rows = result.lines.map((line, index) => ({
        ...line,
        key: index,
        statusLabel: STATUS_LABELS[line.status] || line.status
      }));
    } catch (error) {
      this.showMessage(false, error.body ? error.body.message : error.message);
    } finally {
      this.isBusy = false;
    }
  }

  async handleConfirm() {
    this.isBusy = true;
    try {
      const result = await importStatement({
        recordId: this.recordId,
        fileName: this.fileName,
        content: this.content
      });
      this.showMessage(
        result.success,
        result.success
          ? `${result.message} ${result.imported} transações. Atualize a página para ver o resultado.`
          : result.message
      );
      if (result.success) {
        this.summary = undefined;
        this.rows = [];
        this.content = undefined;
      }
    } catch (error) {
      this.showMessage(false, error.body ? error.body.message : error.message);
    } finally {
      this.isBusy = false;
    }
  }

  reset() {
    this.summary = undefined;
    this.rows = [];
    this.message = undefined;
    this.content = undefined;
  }

  showMessage(success, message) {
    this.success = success;
    this.message = message;
  }
}
