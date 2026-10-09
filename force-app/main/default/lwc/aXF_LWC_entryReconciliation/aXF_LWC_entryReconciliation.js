import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { notifyRecordUpdateAvailable } from "lightning/uiRecordApi";
import getEntryReconciliation from "@salesforce/apex/AXF_CLS_CTRL_Reconciliation.getEntryReconciliation";
import unreconcile from "@salesforce/apex/AXF_CLS_CTRL_Reconciliation.unreconcile";

const SOURCE_LABELS = {
  account: "Transação da conta",
  card: "Transação do cartão"
};

export default class AXF_LWC_entryReconciliation extends NavigationMixin(
  LightningElement
) {
  @api recordId;
  data;
  isLoading = true;
  isWorking = false;
  errorMessage;

  connectedCallback() {
    return this.load();
  }

  async load() {
    this.isLoading = true;
    this.errorMessage = undefined;
    try {
      this.data = await getEntryReconciliation({ entryId: this.recordId });
    } catch (error) {
      this.data = undefined;
      this.errorMessage = this.messageOf(
        error,
        "Não foi possível carregar a conciliação."
      );
    } finally {
      this.isLoading = false;
    }
  }

  messageOf(error, fallback) {
    return (error && error.body && error.body.message) || fallback;
  }

  get isReconciled() {
    return Boolean(this.data) && this.data.reconciled;
  }

  get showPending() {
    return !this.isLoading && Boolean(this.data) && !this.data.reconciled;
  }

  get sourceLabel() {
    return SOURCE_LABELS[this.data.source];
  }

  get hasBRL() {
    return (
      this.data.amountBRL !== null &&
      this.data.amountBRL !== undefined &&
      this.data.currencyCode !== "BRL"
    );
  }

  async handleUndo() {
    this.isWorking = true;
    try {
      const outcome = (await unreconcile({ entryIds: [this.recordId] }))[0];
      if (outcome && outcome.success) {
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Conciliação desfeita.",
            variant: "success"
          })
        );
        await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        await this.load();
      } else {
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Não foi possível desconciliar",
            message: outcome && outcome.message,
            variant: "error"
          })
        );
      }
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Não foi possível desconciliar",
          message: this.messageOf(error, "Tente novamente em instantes."),
          variant: "error"
        })
      );
    } finally {
      this.isWorking = false;
    }
  }

  handleOpen(event) {
    event.preventDefault();
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: event.currentTarget.dataset.id,
        actionName: "view"
      }
    });
  }
}
