import { LightningElement, track, wire } from "lwc";
import getOverdueExpenses from "@salesforce/apex/AXF_CLS_CTRL_OverdueExpensesAlert.getOverdueExpenses";
import settleEntry from "@salesforce/apex/AXF_CLS_CTRL_OverdueExpensesAlert.settleEntry";
import { refreshApex } from "@salesforce/apex";
import { ShowToastEvent } from "lightning/platformShowToastEvent";

export default class AXF_LWC_overdueExpensesAlert extends LightningElement {
  @track records = [];
  @track isModalOpen = false;
  @track isLoading = false;
  @track selectedId = null;
  @track selectedRecordName = "";
  @track paymentDate = "";

  wiredExpensesResult;

  connectedCallback() {
    this.paymentDate = new Date().toISOString().substring(0, 10);
  }

  @wire(getOverdueExpenses)
  wiredExpenses(result) {
    this.wiredExpensesResult = result;
    if (result.data) {
      this.records = result.data.map((item) => ({
        ...item,
        categoryName: item.AXF_CF_LKP_Category__r
          ? item.AXF_CF_LKP_Category__r.Name
          : "-"
      }));
    } else if (result.error) {
      this.records = [];
    }
  }

  get count() {
    return this.records.length;
  }

  get hasRecords() {
    return this.records.length > 0;
  }

  get headerBadgeClass() {
    return this.hasRecords
      ? "slds-avatar slds-avatar_circle alert-badge-danger"
      : "slds-avatar slds-avatar_circle alert-badge-success";
  }

  get totalFormatted() {
    const total = this.records.reduce(
      (acc, curr) => acc + (curr.AXF_CF_CUR_Value__c || 0),
      0
    );
    return new Intl.NumberFormat("pt-BR", {
      style: "currency",
      currency: "BRL"
    }).format(total);
  }

  handleOpenSettleModal(event) {
    this.selectedId = event.currentTarget.dataset.id;
    this.selectedRecordName = event.currentTarget.dataset.name;
    this.paymentDate = new Date().toISOString().substring(0, 10);
    this.isModalOpen = true;
  }

  handleCloseModal() {
    this.isModalOpen = false;
  }

  handleDateChange(event) {
    this.paymentDate = event.target.value;
  }

  async handleConfirmSettle() {
    if (!this.selectedId || !this.paymentDate) return;
    this.isLoading = true;
    try {
      await settleEntry({
        cashFlowId: this.selectedId,
        paymentDate: this.paymentDate,
        targetStatus: "PAGA"
      });
      this.showToast(
        "Sucesso",
        `Despesa "${this.selectedRecordName}" liquidada com sucesso!`,
        "success"
      );
      this.isModalOpen = false;
      await refreshApex(this.wiredExpensesResult);
      this.dispatchEvent(
        new CustomEvent("refreshdata", { bubbles: true, composed: true })
      );
    } catch (error) {
      const msg = error.body ? error.body.message : error.message;
      this.showToast("Erro ao liquidar", msg, "error");
    } finally {
      this.isLoading = false;
    }
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
