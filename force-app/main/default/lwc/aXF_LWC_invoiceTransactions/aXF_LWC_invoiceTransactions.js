import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import getInvoice from "@salesforce/apex/AXF_CLS_CTRL_InvoiceTransactions.getInvoice";

const STATUS_LABELS = { Open: "Aberta", Closed: "Fechada", Paid: "Paga" };

export default class AXF_LWC_invoiceTransactions extends NavigationMixin(
  LightningElement
) {
  // On the Entry record page the card disappears when the Entry is not an invoice Entry.
  @api hideWhenNotInvoice = false;
  invoice;
  isLoading = true;
  errorMessage;
  currentId;
  requestId = 0;

  // Id of the invoice Entry or of the invoice itself; a new value reloads the component.
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
      const invoice = await getInvoice({ recordId: this.currentId });
      if (request === this.requestId) {
        this.invoice = invoice;
      }
    } catch (error) {
      if (request === this.requestId) {
        this.invoice = undefined;
        this.errorMessage =
          (error && error.body && error.body.message) ||
          "Não foi possível carregar a fatura.";
      }
    } finally {
      if (request === this.requestId) {
        this.isLoading = false;
      }
    }
  }

  get hasInvoice() {
    return Boolean(this.invoice);
  }

  get hasLines() {
    return this.hasInvoice && this.invoice.lines.length > 0;
  }

  get showCard() {
    return !(this.hideWhenNotInvoice && !this.hasInvoice && !this.errorMessage);
  }

  get showNoInvoice() {
    return !this.isLoading && !this.hasInvoice && !this.errorMessage;
  }

  get statusLabel() {
    return STATUS_LABELS[this.invoice.status] || this.invoice.status;
  }

  get lines() {
    return this.invoice.lines.map((line) => ({
      ...line,
      hasBRL:
        line.amountBRL !== null &&
        line.amountBRL !== undefined &&
        Boolean(line.originalCurrency) &&
        line.originalCurrency !== "BRL"
    }));
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
