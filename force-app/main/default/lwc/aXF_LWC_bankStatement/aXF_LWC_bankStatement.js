import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getStatement from "@salesforce/apex/AXF_CLS_CTRL_BankStatement.getStatement";
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

export default class AXF_LWC_bankStatement extends NavigationMixin(
  LightningElement
) {
  @api recordId;
  statement;
  isLoading = true;
  isSyncing = false;
  errorMessage;

  connectedCallback() {
    this.load(null);
  }

  async load(month) {
    this.isLoading = true;
    this.errorMessage = undefined;
    try {
      this.statement = await getStatement({
        bankAccountId: this.recordId,
        month
      });
    } catch {
      this.errorMessage = "Não foi possível carregar o extrato.";
    } finally {
      this.isLoading = false;
    }
  }

  get syncLabel() {
    return this.isSyncing ? "Sincronizando…" : "Sincronizar Pluggy";
  }

  get hasRows() {
    return this.statement && this.statement.rows.length > 0;
  }

  get hasMonths() {
    return this.statement && this.statement.months.length > 0;
  }

  // months come newest first: older is the next index.
  get monthIndex() {
    return this.statement.months.indexOf(this.statement.month);
  }

  get isOldest() {
    return this.monthIndex >= this.statement.months.length - 1;
  }

  get isNewest() {
    return this.monthIndex <= 0;
  }

  get monthLabel() {
    const [year, month] = (this.statement.month || "").split("-");
    return MONTH_NAMES[Number(month) - 1]
      ? `${MONTH_NAMES[Number(month) - 1]}/${year}`
      : this.statement.month;
  }

  get totalIn() {
    return this.sum((amount) => amount > 0);
  }

  get totalOut() {
    return this.sum((amount) => amount < 0);
  }

  get rowCount() {
    return this.statement.rows.length;
  }

  sum(filter) {
    return this.statement.rows
      .map((row) => row.amount)
      .filter(filter)
      .reduce((total, amount) => total + amount, 0);
  }

  handlePrevious() {
    this.load(this.statement.months[this.monthIndex + 1]);
  }

  handleNext() {
    this.load(this.statement.months[this.monthIndex - 1]);
  }

  // Month of the selected statement, or the current month when none exists yet.
  get period() {
    const now = new Date();
    const [year, month] =
      this.statement && this.statement.month
        ? this.statement.month.split("-").map(Number)
        : [now.getFullYear(), now.getMonth() + 1];
    const pad = (value) => String(value).padStart(2, "0");
    const last = new Date(year, month, 0).getDate();
    return {
      periodStart: `${year}-${pad(month)}-01`,
      periodEnd: `${year}-${pad(month)}-${pad(last)}`,
      month: this.statement && this.statement.month
    };
  }

  async handleSync() {
    this.isSyncing = true;
    const { periodStart, periodEnd, month } = this.period;
    try {
      const result = await syncPeriod({
        recordId: this.recordId,
        periodStart,
        periodEnd
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
        await this.load(month);
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
