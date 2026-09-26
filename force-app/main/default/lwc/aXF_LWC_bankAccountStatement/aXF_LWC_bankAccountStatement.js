import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import ORG_CURRENCY_CODE from '@salesforce/i18n/currency';
import getStatement from '@salesforce/apex/AXF_CLS_CTRL_BankAccountStatement.getStatement';

import AXF_LBL_BankStatementTitle from '@salesforce/label/c.AXF_LBL_BankStatementTitle';
import AXF_LBL_Filters from '@salesforce/label/c.AXF_LBL_Filters';
import AXF_LBL_Period from '@salesforce/label/c.AXF_LBL_Period';
import AXF_LBL_PeriodStart from '@salesforce/label/c.AXF_LBL_PeriodStart';
import AXF_LBL_PeriodEnd from '@salesforce/label/c.AXF_LBL_PeriodEnd';
import AXF_LBL_DescriptionFilter from '@salesforce/label/c.AXF_LBL_DescriptionFilter';
import AXF_LBL_MinValue from '@salesforce/label/c.AXF_LBL_MinValue';
import AXF_LBL_MaxValue from '@salesforce/label/c.AXF_LBL_MaxValue';
import AXF_LBL_Apply from '@salesforce/label/c.AXF_LBL_Apply';
import AXF_LBL_ClearFilters from '@salesforce/label/c.AXF_LBL_ClearFilters';
import AXF_LBL_TotalCredits from '@salesforce/label/c.AXF_LBL_TotalCredits';
import AXF_LBL_TotalDebits from '@salesforce/label/c.AXF_LBL_TotalDebits';
import AXF_LBL_PeriodBalance from '@salesforce/label/c.AXF_LBL_PeriodBalance';
import AXF_LBL_ColumnDate from '@salesforce/label/c.AXF_LBL_ColumnDate';
import AXF_LBL_ColumnCategory from '@salesforce/label/c.AXF_LBL_ColumnCategory';
import AXF_LBL_ColumnAmount from '@salesforce/label/c.AXF_LBL_ColumnAmount';
import AXF_LBL_ColumnBalance from '@salesforce/label/c.AXF_LBL_ColumnBalance';
import AXF_LBL_NoTransactionsFound from '@salesforce/label/c.AXF_LBL_NoTransactionsFound';
import AXF_LBL_ErrorLoadingStatement from '@salesforce/label/c.AXF_LBL_ErrorLoadingStatement';
import AXF_LBL_CurrentMonth from '@salesforce/label/c.AXF_LBL_CurrentMonth';
import AXF_LBL_LastMonth from '@salesforce/label/c.AXF_LBL_LastMonth';
import AXF_LBL_CustomPeriod from '@salesforce/label/c.AXF_LBL_CustomPeriod';
import AXF_LBL_AllTransactions from '@salesforce/label/c.AXF_LBL_AllTransactions';
import AXF_LBL_ShowingTransactions from '@salesforce/label/c.AXF_LBL_ShowingTransactions';

const QUICK_PERIOD_CURRENT_MONTH = 'CURRENT_MONTH';
const QUICK_PERIOD_LAST_MONTH = 'LAST_MONTH';
const QUICK_PERIOD_ALL = 'ALL';
const QUICK_PERIOD_CUSTOM = 'CUSTOM';

export default class AXF_LWC_bankAccountStatement extends NavigationMixin(LightningElement) {
    @api recordId;

    currencyCode = ORG_CURRENCY_CODE;

    labels = {
        title: AXF_LBL_BankStatementTitle,
        filters: AXF_LBL_Filters,
        period: AXF_LBL_Period,
        periodStart: AXF_LBL_PeriodStart,
        periodEnd: AXF_LBL_PeriodEnd,
        description: AXF_LBL_DescriptionFilter,
        minValue: AXF_LBL_MinValue,
        maxValue: AXF_LBL_MaxValue,
        apply: AXF_LBL_Apply,
        clearFilters: AXF_LBL_ClearFilters,
        totalCredits: AXF_LBL_TotalCredits,
        totalDebits: AXF_LBL_TotalDebits,
        periodBalance: AXF_LBL_PeriodBalance,
        columnDate: AXF_LBL_ColumnDate,
        columnCategory: AXF_LBL_ColumnCategory,
        columnAmount: AXF_LBL_ColumnAmount,
        columnBalance: AXF_LBL_ColumnBalance,
        noTransactionsFound: AXF_LBL_NoTransactionsFound,
        errorLoadingStatement: AXF_LBL_ErrorLoadingStatement,
        showingTransactions: AXF_LBL_ShowingTransactions
    };

    quickPeriodOptions = [
        { label: AXF_LBL_CurrentMonth, value: QUICK_PERIOD_CURRENT_MONTH },
        { label: AXF_LBL_LastMonth, value: QUICK_PERIOD_LAST_MONTH },
        { label: AXF_LBL_CustomPeriod, value: QUICK_PERIOD_CUSTOM },
        { label: AXF_LBL_AllTransactions, value: QUICK_PERIOD_ALL }
    ];

    quickPeriod = QUICK_PERIOD_CURRENT_MONTH;
    periodStart;
    periodEnd;
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
        this.applyQuickPeriod(QUICK_PERIOD_CURRENT_MONTH);
        this.loadStatement();
    }

    get isPeriodInputDisabled() {
        return this.quickPeriod !== QUICK_PERIOD_CUSTOM;
    }

    get hasTransactions() {
        return this.transactions && this.transactions.length > 0;
    }

    get hasNoTransactions() {
        return !this.isLoading && !this.errorMessage && !this.hasTransactions;
    }

    get transactionCount() {
        return this.transactions.length;
    }

    handleQuickPeriodChange(event) {
        this.applyQuickPeriod(event.detail.value);
    }

    handlePeriodStartChange(event) {
        this.periodStart = event.detail.value;
    }

    handlePeriodEndChange(event) {
        this.periodEnd = event.detail.value;
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

    handleSyncDone() {
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
                objectApiName: 'AXF_OBJ_BankAccountTransaction__c',
                actionName: 'view'
            }
        });
    }

    handleClearFilters() {
        this.descriptionFilter = '';
        this.valueMin = undefined;
        this.valueMax = undefined;
        this.applyQuickPeriod(QUICK_PERIOD_CURRENT_MONTH);
        this.loadStatement();
    }

    applyQuickPeriod(quickPeriod) {
        this.quickPeriod = quickPeriod;

        const today = new Date();

        if (quickPeriod === QUICK_PERIOD_CURRENT_MONTH) {
            this.periodStart = this.toIsoDate(new Date(today.getFullYear(), today.getMonth(), 1));
            this.periodEnd = this.toIsoDate(new Date(today.getFullYear(), today.getMonth() + 1, 0));
        } else if (quickPeriod === QUICK_PERIOD_LAST_MONTH) {
            this.periodStart = this.toIsoDate(new Date(today.getFullYear(), today.getMonth() - 1, 1));
            this.periodEnd = this.toIsoDate(new Date(today.getFullYear(), today.getMonth(), 0));
        } else if (quickPeriod === QUICK_PERIOD_ALL) {
            this.periodStart = undefined;
            this.periodEnd = undefined;
        }
        // QUICK_PERIOD_CUSTOM keeps the user-selected dates untouched.
    }

    toIsoDate(date) {
        return date.toISOString().slice(0, 10);
    }

    async loadStatement() {
        this.isLoading = true;
        this.errorMessage = undefined;

        try {
            const result = await getStatement({
                bankAccountId: this.recordId,
                periodStart: this.periodStart || null,
                periodEnd: this.periodEnd || null,
                description: this.descriptionFilter || null,
                valueMin: this.valueMin === '' || this.valueMin === undefined ? null : this.valueMin,
                valueMax: this.valueMax === '' || this.valueMax === undefined ? null : this.valueMax
            });

            this.transactions = result.transactions.map((row) => {
                // Quebra a descricao em uma nova linha a cada hifen (segmentos tipicos do
                // extrato, ex: "PIX RECEBIDO - JOAO DA SILVA"), aparadando espacos nas pontas.
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
                    amountPrefix: row.isCredit ? '+ ' : ''
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