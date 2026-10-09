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
  data;
  isLoading = true;
  isWorking = false;
  errorMessage;
  currentId;
  requestId = 0;

  // A new Entry reloads the card (the page can be reused while navigating).
  @api
  get recordId() {
    return this.currentId;
  }
  set recordId(value) {
    if (value !== this.currentId) {
      this.currentId = value;
      this.load();
    }
  }

  async load() {
    const request = ++this.requestId;
    this.isLoading = true;
    this.errorMessage = undefined;
    try {
      const data = await getEntryReconciliation({ entryId: this.currentId });
      if (request === this.requestId) {
        this.data = data;
      }
    } catch (error) {
      if (request === this.requestId) {
        this.data = undefined;
        this.errorMessage = this.messageOf(
          error,
          "Não foi possível carregar a conciliação."
        );
      }
    } finally {
      if (request === this.requestId) {
        this.isLoading = false;
      }
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

  get cannotUndo() {
    return this.isWorking || !this.data || !this.data.canUndo;
  }

  async handleUndo() {
    if (this.isWorking) {
      return;
    }
    this.isWorking = true;
    try {
      const outcome = (await unreconcile({ entryIds: [this.currentId] }))[0];
      if (outcome && outcome.success) {
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Conciliação desfeita.",
            variant: "success"
          })
        );
        // Refreshing the page data is best effort: the undo is already saved.
        try {
          await notifyRecordUpdateAvailable([{ recordId: this.currentId }]);
        } catch {
          // ignored on purpose
        }
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
