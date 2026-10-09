import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import getInvoice from "@salesforce/apex/AXF_CLS_CTRL_InvoiceTransactions.getInvoice";

const STATUS_LABELS = { Open: "Aberta", Closed: "Fechada", Paid: "Paga" };

export default class AXF_LWC_invoiceTransactions extends NavigationMixin(
  LightningElement
) {
  // Id of the invoice Entry or of the invoice itself.
  @api recordId;
  invoice;
  isLoading = true;
  errorMessage;

  async connectedCallback() {
    try {
      this.invoice = await getInvoice({ recordId: this.recordId });
    } catch (error) {
      this.errorMessage =
        (error && error.body && error.body.message) ||
        "Não foi possível carregar a fatura.";
    } finally {
      this.isLoading = false;
    }
  }

  get hasInvoice() {
    return Boolean(this.invoice);
  }

  get hasLines() {
    return this.hasInvoice && this.invoice.lines.length > 0;
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
