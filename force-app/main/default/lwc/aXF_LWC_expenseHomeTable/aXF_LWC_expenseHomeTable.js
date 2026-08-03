import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import ORG_CURRENCY_CODE from '@salesforce/i18n/currency';

import getMonthlyMovements from '@salesforce/apex/AXF_CLS_CTRL_ExpenseHomeTable.getMonthlyMovements';
import searchBankTransactions from '@salesforce/apex/AXF_CLS_CTRL_ExpenseHomeTable.searchBankTransactions';
import searchCreditCardTransactions from '@salesforce/apex/AXF_CLS_CTRL_ExpenseHomeTable.searchCreditCardTransactions';
import settleCashFlow from '@salesforce/apex/AXF_CLS_CTRL_ExpenseHomeTable.settleCashFlow';

import AXF_LBL_ExpensesHomeTitle from '@salesforce/label/c.AXF_LBL_ExpensesHomeTitle';
import AXF_LBL_DueDate from '@salesforce/label/c.AXF_LBL_DueDate';
import AXF_LBL_ColumnValue from '@salesforce/label/c.AXF_LBL_ColumnValue';
import AXF_LBL_Status from '@salesforce/label/c.AXF_LBL_Status';
import AXF_LBL_ColumnReconciled from '@salesforce/label/c.AXF_LBL_ColumnReconciled';
import AXF_LBL_StatusPending from '@salesforce/label/c.AXF_LBL_StatusPending';
import AXF_LBL_StatusPaid from '@salesforce/label/c.AXF_LBL_StatusPaid';
import AXF_LBL_StatusPaidLate from '@salesforce/label/c.AXF_LBL_StatusPaidLate';
import AXF_LBL_StatusOverdue from '@salesforce/label/c.AXF_LBL_StatusOverdue';
import AXF_LBL_SettleExpenseModalTitle from '@salesforce/label/c.AXF_LBL_SettleExpenseModalTitle';
import AXF_LBL_PaymentDate from '@salesforce/label/c.AXF_LBL_PaymentDate';
import AXF_LBL_ReconcileWithBankTransaction from '@salesforce/label/c.AXF_LBL_ReconcileWithBankTransaction';
import AXF_LBL_ReconcileWithCardTransaction from '@salesforce/label/c.AXF_LBL_ReconcileWithCardTransaction';
import AXF_LBL_SettleInCash from '@salesforce/label/c.AXF_LBL_SettleInCash';
import AXF_LBL_SearchTransactionPlaceholder from '@salesforce/label/c.AXF_LBL_SearchTransactionPlaceholder';
import AXF_LBL_ModalSave from '@salesforce/label/c.AXF_LBL_ModalSave';
import AXF_LBL_ModalCancel from '@salesforce/label/c.AXF_LBL_ModalCancel';
import AXF_LBL_NoMovementsFound from '@salesforce/label/c.AXF_LBL_NoMovementsFound';

const RECORD_TYPE = 'AXF_CF_RT_Expense';
const CATEGORY_RECORD_TYPE = 'AXF_CAT_RT_Expense';

const STATUS_META = {
    PENDENTE: { icon: 'utility:dislike', variant: 'slds-icon-text-default', label: AXF_LBL_StatusPending },
    PAGA: { icon: 'utility:like', variant: 'slds-icon-text-success', label: AXF_LBL_StatusPaid },
    PAGA_EM_ATRASO: { icon: 'utility:like', variant: 'slds-icon-text-success', label: AXF_LBL_StatusPaidLate },
    VENCIDA: { icon: 'utility:dislike', variant: 'slds-icon-text-error', label: AXF_LBL_StatusOverdue }
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
        searchPlaceholder: AXF_LBL_SearchTransactionPlaceholder,
        save: AXF_LBL_ModalSave,
        cancel: AXF_LBL_ModalCancel,
        noMovementsFound: AXF_LBL_NoMovementsFound
    };

    currencyCode = ORG_CURRENCY_CODE;
    isLoading = true;
    rows = [];
    wiredResult;

    selectedCategoryId = '';
    categoryRecordType = CATEGORY_RECORD_TYPE;

    isModalOpen = false;
    selectedRowId;
    paymentDate = this.today();
    paidValue;
    searchTerm = '';
    bankMatches = [];
    cardMatches = [];
    selectedTransaction;

    handleCategoryFilterChange(event) {
        this.selectedCategoryId = event.detail.value;
    }

    @wire(getMonthlyMovements, { recordTypeDeveloperName: RECORD_TYPE, categoryId: '$selectedCategoryId' })
    wiredMovements(result) {
        this.wiredResult = result;
        this.isLoading = false;
        if (result.data) {
            this.rows = result.data.map((row) => this.decorateRow(row));
        }
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

    decorateRow(row) {
        const meta = STATUS_META[row.AXF_CF_PKL_Status__c] || STATUS_META.PENDENTE;
        const reconciled = !!(row.AXF_CF_LKP_BankAccountTransaction__c || row.AXF_CF_LKP_CreditCardTransaction__c);
        return {
            id: row.Id,
            name: row.Name,
            dueDate: row.AXF_CF_DAT_DueDate__c,
            categoryName: row.AXF_CF_LKP_Category__r ? row.AXF_CF_LKP_Category__r.Name : '-',
            value: row.AXF_CF_CUR_Value__c,
            statusIcon: meta.icon,
            statusVariant: meta.variant,
            statusLabel: meta.label,
            reconciledIcon: reconciled ? 'utility:link' : 'utility:unlink',
            reconciledVariant: reconciled ? 'slds-icon-text-success' : 'slds-icon-text-default',
            canSettle: row.AXF_CF_PKL_Status__c === 'PENDENTE' || row.AXF_CF_PKL_Status__c === 'VENCIDA'
        };
    }

    today() {
        return new Date().toISOString().slice(0, 10);
    }

    handleSettleClick(event) {
        this.selectedRowId = event.currentTarget.dataset.id;
        this.paymentDate = this.today();
        const selectedRow = this.rows.find((row) => row.id === this.selectedRowId);
        this.paidValue = selectedRow ? selectedRow.value : null;
        this.searchTerm = '';
        this.bankMatches = [];
        this.cardMatches = [];
        this.selectedTransaction = undefined;
        this.isModalOpen = true;
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

    async handleSearchChange(event) {
        this.searchTerm = event.detail.value;
        this.selectedTransaction = undefined;

        if (!this.searchTerm || this.searchTerm.length < 2) {
            this.bankMatches = [];
            this.cardMatches = [];
            return;
        }

        try {
            const [bankResults, cardResults] = await Promise.all([
                searchBankTransactions({ searchTerm: this.searchTerm }),
                searchCreditCardTransactions({ searchTerm: this.searchTerm })
            ]);
            this.bankMatches = bankResults.map((r) => ({
                id: r.Id,
                label: `${r.AXF_BAT_TXT_Description__c} — ${r.AXF_BAT_CUR_Amount__c}`,
                type: 'bank'
            }));
            this.cardMatches = cardResults.map((r) => ({
                id: r.Id,
                label: `${r.AXF_CCT_TXT_Description__c} — ${r.AXF_CCT_CUR_Amount__c}`,
                type: 'card'
            }));
        } catch (error) {
            this.showErrorToast(error);
        }
    }

    get transactionMatches() {
        return [...this.bankMatches, ...this.cardMatches];
    }

    get hasMatches() {
        return this.transactionMatches.length > 0;
    }

    handleSelectTransaction(event) {
        const id = event.currentTarget.dataset.id;
        const type = event.currentTarget.dataset.type;
        this.selectedTransaction = { id, type };
    }

    async handleSave() {
        await this.settle(
            this.selectedTransaction && this.selectedTransaction.type === 'bank' ? this.selectedTransaction.id : null,
            this.selectedTransaction && this.selectedTransaction.type === 'card' ? this.selectedTransaction.id : null
        );
    }

    async handleSettleInCash() {
        await this.settle(null, null);
    }

    async settle(bankTransactionId, creditCardTransactionId) {
        try {
            if (!this.paymentDate || !this.paidValue || Number(this.paidValue) <= 0) {
                throw new Error('Informe uma data e um valor pago maior que zero.');
            }
            await settleCashFlow({
                cashFlowId: this.selectedRowId,
                paidValue: Number(this.paidValue),
                paymentDate: this.paymentDate,
                bankTransactionId,
                creditCardTransactionId
            });
            this.isModalOpen = false;
            await refreshApex(this.wiredResult);
            this.dispatchEvent(
                new ShowToastEvent({
                    variant: 'success',
                    title: this.labels.save,
                    message: this.labels.modalTitle
                })
            );
        } catch (error) {
            this.showErrorToast(error);
        }
    }

    showErrorToast(error) {
        const detail = error && error.body ? error.body.message : error && error.message;
        this.dispatchEvent(
            new ShowToastEvent({
                variant: 'error',
                title: 'Error',
                message: detail || 'Unknown error'
            })
        );
    }
}
