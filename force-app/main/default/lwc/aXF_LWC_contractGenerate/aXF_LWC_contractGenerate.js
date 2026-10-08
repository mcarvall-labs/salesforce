import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { notifyRecordUpdateAvailable } from "lightning/uiRecordApi";
import generate from "@salesforce/apex/AXF_CLS_CTRL_ContractGeneration.generate";

export default class AXF_LWC_contractGenerate extends LightningElement {
  @api recordId;

  @api async invoke() {
    try {
      const summary = await generate({ contractId: this.recordId });
      const problems = summary.messages || [];
      const text = `${summary.created ?? 0} criado(s), ${summary.updated ?? 0} atualizado(s).`;
      this.toast(
        problems.length ? "warning" : "success",
        problems.length ? `${text} ${problems.join(" ")}` : text
      );
      await this.refresh();
    } catch (error) {
      this.toast(
        "error",
        error?.body?.message || "Não foi possível gerar os lançamentos."
      );
    }
  }

  async refresh() {
    try {
      await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
    } catch {
      // The toast already reported the result; a failed refresh is not an error.
    }
  }

  toast(variant, message) {
    this.dispatchEvent(
      new ShowToastEvent({ title: "Gerar lançamentos", message, variant })
    );
  }
}
