import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import ORG_CURRENCY_CODE from '@salesforce/i18n/currency';
import getInvoices from '@salesforce/apex/AXF_CLS_CTRL_CreditCardStatement.getInvoices';
import getStatement from '@salesforce/apex/AXF_CLS_CTRL_CreditCardStatement.getStatement';

import AXF_LBL_CreditCardStatementTitle from '@salesforce/label/c.AXF_LBL_CreditCardStatementTitle';
import AXF_LBL_Filters from '@salesforce/label/c.AXF_LBL_Filters';
import AXF_LBL_Invoice from '@salesforce/label/c.AXF_LBL_Invoice';
import AXF_LBL_ClosingDate from '@salesforce/label/c.AXF_LBL_ClosingDate';
import AXF_LBL_DueDate from '@salesforce/label/c.AXF_LBL_DueDate';
import AXF_LBL_Status from '@salesforce/label/c.AXF_LBL_Status';
import AXF_LBL_TotalAmount from '@salesforce/label/c.AXF_LBL_TotalAmount';
import AXF_LBL_DescriptionFilter from '@salesforce/label/c.AXF_LBL_DescriptionFilter';
import AXF_LBL_MinValue from '@salesforce/label/c.AXF_LBL_MinValue';
import AXF_LBL_MaxValue from '@salesforce/label/c.AXF_LBL_MaxValue';
import AXF_LBL_Apply from '@salesforce/label/c.AXF_LBL_Apply';
import AXF_LBL_ClearFilters from '@salesforce/label/c.AXF_LBL_ClearFilters';
import AXF_LBL_ColumnDate from '@salesforce/label/c.AXF_LBL_ColumnDate';
import AXF_LBL_ColumnCategory from '@salesforce/label/c.AXF_LBL_ColumnCategory';
import AXF_LBL_ColumnAmount from '@salesforce/label/c.AXF_LBL_ColumnAmount';
import AXF_LBL_NoTransactionsFound from '@salesforce/label/c.AXF_LBL_NoTransactionsFound';
import AXF_LBL_NoInvoicesFound from '@salesforce/label/c.AXF_LBL_NoInvoicesFound';
import AXF_LBL_ErrorLoadingInvoices from '@salesforce/label/c.AXF_LBL_ErrorLoadingInvoices';
import AXF_LBL_ErrorLoadingStatement from '@salesforce/label/c.AXF_LBL_ErrorLoadingStatement';
import AXF_LBL_ShowingTransactions from '@salesforce/label/c.AXF_LBL_ShowingTransactions';
import AXF_LBL_TotalCredits from '@salesforce/label/c.AXF_LBL_TotalCredits';
import AXF_LBL_TotalDebits from '@salesforce/label/c.AXF_LBL_TotalDebits';
import AXF_LBL_PeriodBalance from '@salesforce/label/c.AXF_LBL_PeriodBalance';

export default class AXF_LWC_creditCardStatement extends NavigationMixin(LightningElement) {
    @api recordId;

    currencyCode = ORG_CURRENCY_CODE;

    labels = {
        title: AXF_LBL_CreditCardStatementTitle,
        filters: AXF_LBL_Filters,
        invoice: AXF_LBL_Invoice,
        closingDate: AXF_LBL_ClosingDate,
        dueDate: AXF_LBL_DueDate,
        status: AXF_LBL_Status,
        totalAmount: AXF_LBL_TotalAmount,
        description: AXF_LBL_DescriptionFilter,
        minValue: AXF_LBL_MinValue,
        maxValue: AXF_LBL_MaxValue,
        apply: AXF_LBL_Apply,
        clearFilters: AXF_LBL_ClearFilters,
        columnDate: AXF_LBL_ColumnDate,
        columnCategory: AXF_LBL_ColumnCategory,
        columnAmount: AXF_LBL_ColumnAmount,
        noTransactionsFound: AXF_LBL_NoTransactionsFound,
        noInvoicesFound: AXF_LBL_NoInvoicesFound,
        errorLoadingInvoices: AXF_LBL_ErrorLoadingInvoices,
        errorLoadingStatement: AXF_LBL_ErrorLoadingStatement,
        showingTransactions: AXF_LBL_ShowingTransactions,
        totalCredits: AXF_LBL_TotalCredits,
        totalDebits: AXF_LBL_TotalDebits,
        periodBalance: AXF_LBL_PeriodBalance
    };

    invoices = [];
    selectedInvoiceId;
    selectedInvoice;

    descriptionFilter = '';
    valueMin;
    valueMax;

    isLoading = true;
    errorMessage;
    transactions = [];
    totalCredits = 0;
    totalDebits = 0;
    netBalance = 0;

    connectedCallback() {
        this.loadInvoices();
    }

    get hasInvoices() {
        return this.invoices && this.invoices.length > 0;
    }

    get hasTransactions() {
        return this.transactions && this.transactions.length > 0;
    }

    get hasNoTransactions() {
        return !this.isLoading && !this.errorMessage && this.hasInvoices && !this.hasTransactions;
    }

    get hasNoInvoices() {
        return !this.isLoading && !this.errorMessage && !this.hasInvoices;
    }

    get transactionCount() {
        return this.transactions.length;
    }

    /**
     * dateFrom/dateTo for the manual sync button: the selected invoice's closing date
     * minus/plus 30 days, per US-090's requirement that credit card sync be scoped to
     * the selected invoice's window rather than the statement filter's own date fields
     * (this component has no period filter — only Bank Account statement does).
     */
    get syncStartDate() {
        return this.offsetIsoDate(this.selectedInvoice && this.selectedInvoice.AXF_CCI_DAT_ClosingDate__c, -30);
    }

    get syncEndDate() {
        return this.offsetIsoDate(this.selectedInvoice && this.selectedInvoice.AXF_CCI_DAT_ClosingDate__c, 30);
    }

    offsetIsoDate(isoDateString, days) {
        if (!isoDateString) {
            return undefined;
        }
        const date = new Date(isoDateString);
        date.setUTCDate(date.getUTCDate() + days);
        return date.toISOString().substring(0, 10);
    }

    handleSyncDone() {
        this.loadStatement();
    }

    get invoiceOptions() {
        return this.invoices.map((inv) => {
            const statusLabel = inv.AXF_CCI_PKL_Status__c ? ` (${inv.AXF_CCI_PKL_Status__c})` : '';
            return {
                label: `${inv.AXF_CCI_TXT_Period__c}${statusLabel}`,
                value: inv.Id
            };
        });
    }

    handleInvoiceChange(event) {
        this.selectedInvoiceId = event.detail.value;
        this.selectedInvoice = this.invoices.find((inv) => inv.Id === this.selectedInvoiceId);
        this.loadStatement();
    }

    handleDescriptionChange(event) {
        this.descriptionFilter = event.detail.value;
    }

    handleValueMinChange(event) {
        this.valueMin = event.detail.value;
    }

    handleValueMaxChange(event) {
        this.valueMax = event.detail.value;
    }

    handleApplyFilters() {
        this.loadStatement();
    }

    handleRowClick(event) {
        const transactionId = event.currentTarget.dataset.id;
        if (!transactionId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: transactionId,
                objectApiName: 'AXF_OBJ_CreditCardTransaction__c',
                actionName: 'view'
            }
        });
    }

    handleClearFilters() {
        this.descriptionFilter = '';
        this.valueMin = undefined;
        this.valueMax = undefined;
        if (this.invoices.length > 0) {
            this.selectedInvoiceId = this.invoices[0].Id;
            this.selectedInvoice = this.invoices[0];
        }
        this.loadStatement();
    }

    async loadInvoices() {
        this.isLoading = true;
        this.errorMessage = undefined;

        try {
            const result = await getInvoices({ creditCardId: this.recordId });
            this.invoices = result;

            if (result && result.length > 0) {
                this.selectedInvoiceId = result[0].Id;
                this.selectedInvoice = result[0];
                await this.loadStatement();
            } else {
                this.isLoading = false;
            }
        } catch (error) {
            const detail = error && error.body ? error.body.message : error && error.message;
            this.errorMessage = this.labels.errorLoadingInvoices + (detail ? ' ' + detail : '');
            this.isLoading = false;
        }
    }

    async loadStatement() {
        if (!this.selectedInvoiceId) {
            return;
        }

        this.isLoading = true;
        this.errorMessage = undefined;

        try {
            const result = await getStatement({
                invoiceId: this.selectedInvoiceId,
                description: this.descriptionFilter || null,
                valueMin: this.valueMin === '' || this.valueMin === undefined ? null : this.valueMin,
                valueMax: this.valueMax === '' || this.valueMax === undefined ? null : this.valueMax
            });

            this.transactions = result.transactions.map((row) => {
                const lines = row.description ? row.description.split('-').map((line) => line.trim()) : [''];
                return {
                    ...row,
                    descriptionLines: lines.map((line, index) => ({
                        text: line,
                        isLast: index === lines.length - 1,
                        key: `${row.id}-desc-${index}`
                    })),
                    categoryDisplay: row.categoryName || '—',
                    amountClass: row.isCredit ? 'slds-text-color_success' : 'slds-text-color_error',
                    // Credit card payments decrease the balance, so we display them as green with '- ' or similar.
                    amountPrefix: row.isCredit ? '' : '+ '
                };
            });

            this.totalCredits = result.totalCredits;
            this.totalDebits = result.totalDebits;
            this.netBalance = result.netBalance;
        } catch (error) {
            const detail = error && error.body ? error.body.message : error && error.message;
            this.errorMessage = this.labels.errorLoadingStatement + (detail ? ' ' + detail : '');
            this.transactions = [];
        } finally {
            this.isLoading = false;
        }
    }
}