import { LightningElement } from "lwc";
import getState from "@salesforce/apex/AXF_CLS_CTRL_PluggyWizard.getState";
import saveCredentials from "@salesforce/apex/AXF_CLS_CTRL_PluggyWizard.saveCredentials";
import createConnection from "@salesforce/apex/AXF_CLS_CTRL_PluggyWizard.createConnection";
import testCredentials from "@salesforce/apex/AXF_CLS_CTRL_PluggyWizard.testCredentials";
import syncConnection from "@salesforce/apex/AXF_CLS_CTRL_PluggyWizard.syncConnection";
import getLinked from "@salesforce/apex/AXF_CLS_CTRL_PluggyWizard.getLinked";

export default class AXF_LWC_pluggyWizard extends LightningElement {
  hasCredentials = false;
  connectionCount = 0;
  holderId;
  institution;
  itemId = "";
  isCreating = false;
  connectionMessage;
  connectionSuccess = false;
  connectionId;
  linkedItems = [];
  isSyncing = false;
  syncMessage;
  syncSuccess = false;
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
      this.connectionCount = state.connectionCount;
      this.connectionId = state.latestConnectionId;
      if (this.connectionId) {
        this.linkedItems = await getLinked({ connectionId: this.connectionId });
      }
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
    if (this.connectionCount > 0) {
      return "3";
    }
    return this.hasCredentials ? "2" : "1";
  }

  get connectionDisabled() {
    return (
      this.isCreating || !this.holderId || !this.institution || !this.itemId
    );
  }

  get connectionClass() {
    return this.connectionSuccess
      ? "slds-text-color_success"
      : "slds-text-color_error";
  }

  handleHolder(event) {
    this.holderId = event.detail.recordId;
  }

  handleInstitution(event) {
    this.institution = event.detail.value;
  }

  handleItemId(event) {
    this.itemId = event.target.value;
  }

  async handleCreateConnection() {
    this.isCreating = true;
    this.connectionMessage = undefined;
    try {
      const result = await createConnection({
        holderId: this.holderId,
        institution: this.institution,
        itemId: this.itemId
      });
      this.connectionSuccess = result.success;
      this.connectionMessage = result.message;
      if (result.success) {
        this.connectionCount += 1;
        this.connectionId = result.connectionId;
        this.linkedItems = [];
        this.syncMessage = undefined;
        this.itemId = "";
      }
    } catch {
      this.connectionSuccess = false;
      this.connectionMessage = "Não foi possível criar a conexão.";
    } finally {
      this.isCreating = false;
    }
  }

  get syncDisabled() {
    return this.isSyncing || !this.connectionId;
  }

  get syncClass() {
    return this.syncSuccess
      ? "slds-text-color_success"
      : "slds-text-color_error";
  }

  get hasLinkedItems() {
    return this.linkedItems.length > 0;
  }

  async handleSync() {
    this.isSyncing = true;
    this.syncMessage = undefined;
    try {
      const result = await syncConnection({ connectionId: this.connectionId });
      this.syncSuccess = result.success;
      this.syncMessage = result.message;
      this.linkedItems = result.items;
    } catch {
      this.syncSuccess = false;
      this.syncMessage = "Não foi possível sincronizar contas e cartões.";
    } finally {
      this.isSyncing = false;
    }
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
