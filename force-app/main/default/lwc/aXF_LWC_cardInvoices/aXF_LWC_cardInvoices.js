import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { MessageContext, publish } from "lightning/messageService";
import INVOICE_SELECTED from "@salesforce/messageChannel/AXF_MC_InvoiceSelected__c";
import getInvoices from "@salesforce/apex/AXF_CLS_CTRL_CardInvoices.getInvoices";
import getLines from "@salesforce/apex/AXF_CLS_CTRL_CardInvoices.getLines";
import syncPeriod from "@salesforce/apex/AXF_CLS_CTRL_PluggySync.syncPeriod";

const MONTH_NAMES = [
  "Janeiro",
  "Fevereiro",
  "Março",
  "Abril",
  "Maio",
  "Junho",
  "Julho",
  "Agosto",
  "Setembro",
  "Outubro",
  "Novembro",
  "Dezembro"
];
const STATUS_LABELS = { Open: "Aberta", Closed: "Fechada", Paid: "Paga" };

export default class AXF_LWC_cardInvoices extends NavigationMixin(
  LightningElement
) {
  @api recordId;

  @wire(MessageContext)
  messageContext;

  invoices = [];
  selectedIndex = -1;
  lines = [];
  isLoading = true;
  isLoadingLines = false;
  isSyncing = false;
  errorMessage;

  connectedCallback() {
    return this.reload(null);
  }

  // Keeps the invoice of keepPeriod selected when it still exists.
  async reload(keepPeriod) {
    try {
      this.errorMessage = undefined;
      const invoices = await getInvoices({ creditCardId: this.recordId });
      this.invoices = [...invoices]
        .sort((a, b) => (a.period || "").localeCompare(b.period || ""))
        .map((invoice) => ({
          ...invoice,
          statusLabel: STATUS_LABELS[invoice.status] || invoice.status
        }));
      const kept = this.invoices.findIndex(
        (invoice) => invoice.period === keepPeriod
      );
      this.selectedIndex = kept >= 0 ? kept : this.defaultIndex();
    } catch {
      this.errorMessage = "Não foi possível carregar as faturas.";
    } finally {
      this.isLoading = false;
    }
    if (this.selectedIndex >= 0) {
      this.publishSelection();
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

  get periodLabel() {
    const [year, month] = (this.selected.period || "").split("-");
    return MONTH_NAMES[Number(month) - 1]
      ? `${MONTH_NAMES[Number(month) - 1]}/${year}`
      : this.selected.period;
  }

  get lineCount() {
    return this.lines.length;
  }

  get syncLabel() {
    return this.isSyncing ? "Sincronizando…" : "Sincronizar Pluggy";
  }

  // Invoice of the due month plus the previous month, where its purchases start.
  get syncWindow() {
    const [year, month] = this.selected.period.split("-").map(Number);
    const pad = (value) => String(value).padStart(2, "0");
    const from = new Date(year, month - 2, 1);
    const last = new Date(year, month, 0).getDate();
    return {
      periodStart: `${from.getFullYear()}-${pad(from.getMonth() + 1)}-01`,
      periodEnd: `${year}-${pad(month)}-${pad(last)}`
    };
  }

  publishSelection() {
    if (this.selected) {
      publish(this.messageContext, INVOICE_SELECTED, {
        period: this.selected.period,
        dueDate: this.selected.dueDate,
        totalAmount: this.selected.totalAmount,
        currencyCode: this.selected.currencyCode,
        statusLabel: this.selected.statusLabel
      });
    }
  }

  async handleSync() {
    this.isSyncing = true;
    const period = this.selected && this.selected.period;
    try {
      const result = await syncPeriod({
        recordId: this.recordId,
        ...(this.selected
          ? this.syncWindow
          : { periodStart: this.currentMonthStart(), periodEnd: this.today() })
      });
      this.dispatchEvent(
        new ShowToastEvent({
          title: result.success
            ? "Sincronização concluída"
            : "Não foi possível sincronizar",
          message: result.success
            ? `${result.transactions} transações atualizadas.`
            : result.message,
          variant: result.success ? "success" : "error"
        })
      );
      if (result.success) {
        await this.reload(period);
      }
    } catch {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Não foi possível sincronizar",
          message: "Tente novamente em instantes.",
          variant: "error"
        })
      );
    } finally {
      this.isSyncing = false;
    }
  }

  currentMonthStart() {
    const now = new Date();
    return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-01`;
  }

  today() {
    const now = new Date();
    const pad = (value) => String(value).padStart(2, "0");
    return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
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
    this.publishSelection();
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
