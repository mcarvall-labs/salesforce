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
  selectedIndex = -1;
  lines = [];
  isLoading = true;
  isLoadingLines = false;
  errorMessage;

  async connectedCallback() {
    try {
      this.errorMessage = undefined;
      const invoices = await getInvoices({ creditCardId: this.recordId });
      this.invoices = [...invoices]
        .sort((a, b) => (a.period || "").localeCompare(b.period || ""))
        .map((invoice) => ({
          ...invoice,
          statusLabel: STATUS_LABELS[invoice.status] || invoice.status
        }));
      this.selectedIndex = this.defaultIndex();
    } catch {
      this.errorMessage = "Não foi possível carregar as faturas.";
    } finally {
      this.isLoading = false;
    }
    if (this.selectedIndex >= 0) {
      await this.loadLines();
    }
  }

  // Fatura do mês atual; sem ela, a mais próxima (anterior se existir, senão a primeira posterior).
  defaultIndex() {
    if (!this.invoices.length) {
      return -1;
    }
    const now = new Date();
    const current = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;
    let index = -1;
    this.invoices.forEach((invoice, i) => {
      if ((invoice.period || "") <= current) {
        index = i;
      }
    });
    return index >= 0 ? index : 0;
  }

  get hasInvoices() {
    return this.invoices.length > 0;
  }

  get selected() {
    return this.invoices[this.selectedIndex];
  }

  get hasLines() {
    return this.lines.length > 0;
  }

  get isFirst() {
    return this.selectedIndex <= 0;
  }

  get isLast() {
    return this.selectedIndex >= this.invoices.length - 1;
  }

  handlePrevious() {
    this.select(this.selectedIndex - 1);
  }

  handleNext() {
    this.select(this.selectedIndex + 1);
  }

  async select(index) {
    if (index < 0 || index >= this.invoices.length || this.isLoadingLines) {
      return;
    }
    this.selectedIndex = index;
    await this.loadLines();
  }

  async loadLines() {
    const invoiceId = this.selected.id;
    this.isLoadingLines = true;
    try {
      const lines = await getLines({ invoiceId });
      if (this.selected.id === invoiceId) {
        this.lines = lines;
        this.errorMessage = undefined;
      }
    } catch {
      this.lines = [];
      this.errorMessage = "Não foi possível carregar as transações.";
    } finally {
      this.isLoadingLines = false;
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
