import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { notifyRecordUpdateAvailable } from "lightning/uiRecordApi";
import testAndSync from "@salesforce/apex/AXF_CLS_CTRL_PluggyConnection.testAndSync";

export default class AXF_LWC_pluggyConnectionTest extends LightningElement {
  @api recordId;

  @api async invoke() {
    try {
      const result = await testAndSync({ connectionId: this.recordId });
      if (result.success) {
        this.toast(
          "success",
          `${result.message} ${result.accounts} conta(s) e ${result.cards} cartão(ões) importados.`
        );
      } else {
        this.toast("error", result.message);
      }
      await this.refresh();
    } catch (error) {
      this.toast(
        "error",
        error?.body?.message || "Não foi possível testar a conexão."
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
      new ShowToastEvent({ title: "Conexão Pluggy", message, variant })
    );
  }
}
