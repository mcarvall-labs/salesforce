import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import getInvoices from "@salesforce/apex/AXF_CLS_CTRL_CardInvoices.getInvoices";
import getLines from "@salesforce/apex/AXF_CLS_CTRL_CardInvoices.getLines";

const STATUS_LABELS = { Open: "Aberta", Closed: "Fechada", Paid: "Paga" };

export default class AXF_LWC_cardInvoices extends NavigationMixin(
  LightningElement
) {
  @api recordId;
  invoices = [];
  isLoading = true;
  errorMessage;

  async connectedCallback() {
    try {
      const invoices = await getInvoices({ creditCardId: this.recordId });
      this.invoices = invoices.map((invoice) => ({
        ...invoice,
        statusLabel: STATUS_LABELS[invoice.status] || invoice.status,
        expanded: false,
        lines: [],
        iconName: "utility:chevronright"
      }));
    } catch {
      this.errorMessage = "Não foi possível carregar as faturas.";
    } finally {
      this.isLoading = false;
    }
  }

  get hasInvoices() {
    return this.invoices.length > 0;
  }

  async handleToggle(event) {
    const id = event.currentTarget.dataset.id;
    const invoice = this.invoices.find((i) => i.id === id);
    if (!invoice.expanded) {
      try {
        invoice.lines = await getLines({ invoiceId: id });
      } catch {
        this.errorMessage = "Não foi possível carregar as transações.";
        return;
      }
    }
    invoice.expanded = !invoice.expanded;
    invoice.iconName = invoice.expanded
      ? "utility:chevrondown"
      : "utility:chevronright";
    this.invoices = [...this.invoices];
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
