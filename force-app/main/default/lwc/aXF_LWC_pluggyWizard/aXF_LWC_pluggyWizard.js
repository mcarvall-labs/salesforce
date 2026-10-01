import { LightningElement } from "lwc";
import getState from "@salesforce/apex/AXF_CLS_CTRL_PluggyWizard.getState";
import saveCredentials from "@salesforce/apex/AXF_CLS_CTRL_PluggyWizard.saveCredentials";
import testCredentials from "@salesforce/apex/AXF_CLS_CTRL_PluggyWizard.testCredentials";

export default class AXF_LWC_pluggyWizard extends LightningElement {
  hasCredentials = false;
  isLoading = true;
  isSaving = false;
  clientId = "";
  clientSecret = "";
  resultMessage;
  resultSuccess = false;

  async connectedCallback() {
    try {
      const state = await getState();
      this.hasCredentials = state.hasCredentials;
    } catch {
      this.showResult(
        false,
        "Não foi possível carregar o estado do assistente."
      );
    } finally {
      this.isLoading = false;
    }
  }

  get currentStep() {
    return this.hasCredentials ? "2" : "1";
  }

  get saveDisabled() {
    return this.isSaving || !this.clientId || !this.clientSecret;
  }

  get resultClass() {
    return this.resultSuccess
      ? "slds-text-color_success"
      : "slds-text-color_error";
  }

  handleClientId(event) {
    this.clientId = event.target.value;
  }

  handleClientSecret(event) {
    this.clientSecret = event.target.value;
  }

  async handleSaveAndTest() {
    this.isSaving = true;
    this.resultMessage = undefined;
    try {
      const saved = await saveCredentials({
        clientId: this.clientId,
        clientSecret: this.clientSecret
      });
      if (!saved.success) {
        this.showResult(false, saved.message);
        return;
      }
      const tested = await testCredentials();
      this.showResult(tested.success, tested.message);
      this.hasCredentials = tested.success || this.hasCredentials;
      if (tested.success) {
        this.clientSecret = "";
      }
    } catch {
      this.showResult(
        false,
        "Não foi possível salvar e testar as credenciais."
      );
    } finally {
      this.isSaving = false;
    }
  }

  showResult(success, message) {
    this.resultSuccess = success;
    this.resultMessage = message;
  }
}
