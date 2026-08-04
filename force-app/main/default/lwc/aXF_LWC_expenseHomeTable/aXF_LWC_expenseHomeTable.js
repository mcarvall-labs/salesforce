import { LightningElement, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import LightningConfirm from "lightning/confirm";
import ORG_CURRENCY_CODE from "@salesforce/i18n/currency";
import getMonthlyMovements from "@salesforce/apex/AXF_CLS_CTRL_ExpenseHomeTable.getMonthlyMovements";
import getReconciliationSuggestions from "@salesforce/apex/AXF_CLS_CTRL_ExpenseHomeTable.getReconciliationSuggestions";
import unreconcile from "@salesforce/apex/AXF_CLS_CTRL_ExpenseHomeTable.unreconcile";
import settleCashFlow from "@salesforce/apex/AXF_CLS_CTRL_ExpenseHomeTable.settleCashFlow";
import AXF_LBL_ExpensesHomeTitle from "@salesforce/label/c.AXF_LBL_ExpensesHomeTitle";
import AXF_LBL_DueDate from "@salesforce/label/c.AXF_LBL_DueDate";
import AXF_LBL_ColumnValue from "@salesforce/label/c.AXF_LBL_ColumnValue";
import AXF_LBL_Status from "@salesforce/label/c.AXF_LBL_Status";
import AXF_LBL_ColumnReconciled from "@salesforce/label/c.AXF_LBL_ColumnReconciled";
import AXF_LBL_StatusPending from "@salesforce/label/c.AXF_LBL_StatusPending";
import AXF_LBL_StatusPaid from "@salesforce/label/c.AXF_LBL_StatusPaid";
import AXF_LBL_StatusPaidLate from "@salesforce/label/c.AXF_LBL_StatusPaidLate";
import AXF_LBL_StatusOverdue from "@salesforce/label/c.AXF_LBL_StatusOverdue";
import AXF_LBL_SettleExpenseModalTitle from "@salesforce/label/c.AXF_LBL_SettleExpenseModalTitle";
import AXF_LBL_PaymentDate from "@salesforce/label/c.AXF_LBL_PaymentDate";
import AXF_LBL_ReconcileWithBankTransaction from "@salesforce/label/c.AXF_LBL_ReconcileWithBankTransaction";
import AXF_LBL_ReconcileWithCardTransaction from "@salesforce/label/c.AXF_LBL_ReconcileWithCardTransaction";
import AXF_LBL_SettleInCash from "@salesforce/label/c.AXF_LBL_SettleInCash";
import AXF_LBL_ModalSave from "@salesforce/label/c.AXF_LBL_ModalSave";
import AXF_LBL_ModalCancel from "@salesforce/label/c.AXF_LBL_ModalCancel";
import AXF_LBL_NoMovementsFound from "@salesforce/label/c.AXF_LBL_NoMovementsFound";
const RECORD_TYPE = "AXF_CF_RT_Expense";
const CATEGORY_RECORD_TYPE = "AXF_CAT_RT_Expense";
const STATUS_META = {
  PENDENTE: {
    icon: "utility:dislike",
    variant: "slds-icon-text-default",
    label: AXF_LBL_StatusPending
  },
  PAGA: {
    icon: "utility:like",
    variant: "slds-icon-text-success",
    label: AXF_LBL_StatusPaid
  },
  PAGA_EM_ATRASO: {
    icon: "utility:like",
    variant: "slds-icon-text-success",
    label: AXF_LBL_StatusPaidLate
  },
  VENCIDA: {
    icon: "utility:dislike",
    variant: "slds-icon-text-error",
    label: AXF_LBL_StatusOverdue
  }
};
export default class AXF_LWC_expenseHomeTable extends LightningElement {
  labels = {
    title: AXF_LBL_ExpensesHomeTitle,
    dueDate: AXF_LBL_DueDate,
    value: AXF_LBL_ColumnValue,
    status: AXF_LBL_Status,
    reconciled: AXF_LBL_ColumnReconciled,
    modalTitle: AXF_LBL_SettleExpenseModalTitle,
    paymentDate: AXF_LBL_PaymentDate,
    reconcileWithBank: AXF_LBL_ReconcileWithBankTransaction,
    reconcileWithCard: AXF_LBL_ReconcileWithCardTransaction,
    settleInCash: AXF_LBL_SettleInCash,
    save: AXF_LBL_ModalSave,
    cancel: AXF_LBL_ModalCancel,
    noMovementsFound: AXF_LBL_NoMovementsFound
  };
  currencyCode = ORG_CURRENCY_CODE;
  isLoading = true;
  rows = [];
  wiredResult;
  selectedCategoryId = "";
  categoryRecordType = CATEGORY_RECORD_TYPE;
  isModalOpen = false;
  selectedRowId;
  paymentDate = this.today();
  paidValue;
  bankMatches = [];
  cardMatches = [];
  selectedTransaction;
  handleCategoryFilterChange(event) {
    this.selectedCategoryId = event.detail.value;
  }
  @wire(getMonthlyMovements, {
    recordTypeDeveloperName: RECORD_TYPE,
    categoryId: "$selectedCategoryId"
  })
  wiredMovements(result) {
    this.wiredResult = result;
    this.isLoading = false;
    if (result.data)
      this.rows = result.data.map((row) => this.decorateRow(row));
  }
  get hasRows() {
    return this.rows && this.rows.length > 0;
  }
  get hasNoRows() {
    return !this.isLoading && !this.hasRows;
  }
  get hasNoSelection() {
    return !this.selectedTransaction;
  }
  get transactionMatches() {
    return [...this.bankMatches, ...this.cardMatches];
  }
  get hasMatches() {
    return this.transactionMatches.length > 0;
  }
  decorateRow(row) {
    const meta = STATUS_META[row.AXF_CF_PKL_Status__c] || STATUS_META.PENDENTE;
    const reconciled = !!(
      row.AXF_CF_LKP_BankAccountTransaction__c ||
      row.AXF_CF_LKP_CreditCardTransaction__c
    );
    return {
      id: row.Id,
      name: row.Name,
      dueDate: row.AXF_CF_DAT_DueDate__c,
      categoryName: row.AXF_CF_LKP_Category__r
        ? row.AXF_CF_LKP_Category__r.Name
        : "-",
      value: row.AXF_CF_CUR_Value__c,
      groupType: row.AXF_CF_LKP_InstallmentGroup__r?.AXF_IG_PKL_GroupType__c,
      groupBase:
        row.AXF_CF_LKP_InstallmentGroup__r?.AXF_IG_CUR_InstallmentAmount__c,
      adjustmentAnniversary:
        row.AXF_CF_LKP_InstallmentGroup__r?.AXF_IG_DAT_AdjustmentAnniversary__c,
      statusIcon: meta.icon,
      statusVariant: meta.variant,
      statusLabel: meta.label,
      reconciledIcon: reconciled ? "utility:link" : "utility:unlink",
      reconciledVariant: reconciled
        ? "slds-icon-text-success"
        : "slds-icon-text-default",
      canUnreconcile: reconciled
    };
  }
  today() {
    return new Date().toISOString().slice(0, 10);
  }
  async handleSettleClick(event) {
    this.selectedRowId = event.currentTarget.dataset.id;
    this.paymentDate = this.today();
    const row = this.rows.find((item) => item.id === this.selectedRowId);
    this.paidValue = row ? row.value : null;
    this.bankMatches = [];
    this.cardMatches = [];
    this.selectedTransaction = undefined;
    this.isModalOpen = true;
    try {
      const values = await getReconciliationSuggestions({
        cashFlowId: this.selectedRowId
      });
      const mapped = values.map((item) => ({
        id: item.transactionId,
        type: item.source === "BANK" ? "bank" : "card",
        amount: Math.abs(item.amount),
        transactionDate: item.transactionDate,
        label: `${item.confidence} · ${item.description || "-"} · ${item.transactionDate} · ${Math.abs(item.amount)}`
      }));
      this.bankMatches = mapped.filter((item) => item.type === "bank");
      this.cardMatches = mapped.filter((item) => item.type === "card");
    } catch (error) {
      this.showErrorToast(error);
    }
  }
  handleCloseModal() {
    this.isModalOpen = false;
  }
  handlePaymentDateChange(event) {
    this.paymentDate = event.detail.value;
  }
  handlePaidValueChange(event) {
    this.paidValue = event.detail.value;
  }
  handleSelectTransaction(event) {
    const id = event.currentTarget.dataset.id;
    const type = event.currentTarget.dataset.type;
    const match = this.transactionMatches.find((item) => item.id === id);
    this.selectedTransaction = { id, type };
    if (match) {
      this.paidValue = match.amount;
      this.paymentDate = match.transactionDate;
    }
  }
  async handleUnreconcile(event) {
    try {
      await unreconcile({ cashFlowId: event.currentTarget.dataset.id });
      await refreshApex(this.wiredResult);
    } catch (error) {
      this.showErrorToast(error);
    }
  }
  async handleSave() {
    await this.settle(
      this.selectedTransaction?.type === "bank"
        ? this.selectedTransaction.id
        : null,
      this.selectedTransaction?.type === "card"
        ? this.selectedTransaction.id
        : null
    );
  }
  async handleSettleInCash() {
    await this.settle(null, null);
  }
  async settle(bankTransactionId, creditCardTransactionId) {
    try {
      if (!this.paymentDate || !this.paidValue || Number(this.paidValue) <= 0)
        throw new Error("Informe uma data e um valor pago maior que zero.");
      const row = this.rows.find((item) => item.id === this.selectedRowId);
      const eligibleAdjustment =
        row?.groupType === "CONSORTIUM" &&
        Number(this.paidValue) > Number(row.groupBase) &&
        row.adjustmentAnniversary &&
        row.dueDate >= row.adjustmentAnniversary;
      const consortiumAdjustmentConfirmed = eligibleAdjustment
        ? await LightningConfirm.open({
            label: "Confirmar reajuste do consórcio",
            message:
              "O valor pago é maior que o valor-base. Deseja aplicar este reajuste às parcelas futuras não pagas?",
            variant: "header"
          })
        : false;
      await settleCashFlow({
        cashFlowId: this.selectedRowId,
        paidValue: Number(this.paidValue),
        paymentDate: this.paymentDate,
        bankTransactionId,
        creditCardTransactionId,
        consortiumAdjustmentConfirmed
      });
      this.isModalOpen = false;
      await refreshApex(this.wiredResult);
      this.dispatchEvent(
        new ShowToastEvent({
          variant: "success",
          title: this.labels.save,
          message: this.labels.modalTitle
        })
      );
    } catch (error) {
      this.showErrorToast(error);
    }
  }
  showErrorToast(error) {
    const detail = error?.body?.message || error?.message;
    this.dispatchEvent(
      new ShowToastEvent({
        variant: "error",
        title: "Erro",
        message: detail || "Erro desconhecido"
      })
    );
  }
}
