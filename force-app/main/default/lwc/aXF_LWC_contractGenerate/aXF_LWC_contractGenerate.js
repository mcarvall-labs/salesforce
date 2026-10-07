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
      const text = `${summary.created} criado(s), ${summary.updated} atualizado(s).`;
      this.toast(
        problems.length ? "warning" : "success",
        problems.length ? `${text} ${problems.join(" ")}` : text
      );
      await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
    } catch (error) {
      this.toast(
        "error",
        error?.body?.message || "Não foi possível gerar os lançamentos."
      );
    }
  }

  toast(variant, message) {
    this.dispatchEvent(
      new ShowToastEvent({ title: "Gerar lançamentos", message, variant })
    );
  }
}
