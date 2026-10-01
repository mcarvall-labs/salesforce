import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import getStatement from "@salesforce/apex/AXF_CLS_CTRL_BankStatement.getStatement";

export default class AXF_LWC_bankStatement extends NavigationMixin(
  LightningElement
) {
  @api recordId;
  statement;
  isLoading = true;
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

  get monthOptions() {
    return this.statement.months.map((m) => ({ label: m, value: m }));
  }

  get hasRows() {
    return this.statement && this.statement.rows.length > 0;
  }

  get hasMonths() {
    return this.statement && this.statement.months.length > 0;
  }

  handleMonth(event) {
    this.load(event.detail.value);
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
