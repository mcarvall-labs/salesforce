import { LightningElement, track, wire } from 'lwc';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import createCashFlowSeries from '@salesforce/apex/AXF_CLS_CTRL_QuickFlowActions.createCashFlowSeries';
import getRecentBankAccounts from '@salesforce/apex/AXF_CLS_CTRL_QuickFlowActions.getRecentBankAccounts';
import getRecentCreditCards from '@salesforce/apex/AXF_CLS_CTRL_QuickFlowActions.getRecentCreditCards';
import CASH_FLOW_OBJECT from '@salesforce/schema/AXF_OBJ_CashFlow__c';
import PAYMENT_METHOD_FIELD from '@salesforce/schema/AXF_OBJ_CashFlow__c.AXF_CF_PKL_PaymentMethod__c';

const BANK_METHODS = new Set(['DEBITO_CONTA', 'TRANSFERENCIA_PIX']);

export default class AXF_LWC_quickFlowActions extends LightningElement {
    @track isModalOpen = false;
    @track isLoading = false;
    @track entryType = 'DESPESA';
    @track form = {};
    amountDisplay = '';
    paidValueDisplay = '';
    bankAccountOptions = [];
    creditCardOptions = [];

    @wire(getObjectInfo, { objectApiName: CASH_FLOW_OBJECT })
    cashFlowObjectInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$cashFlowObjectInfo.data.defaultRecordTypeId',
        fieldApiName: PAYMENT_METHOD_FIELD
    })
    paymentMethodPicklist;

    connectedCallback() {
        this.resetForm();
    }

    get categoryRecordType() {
        return this.entryType === 'DESPESA' ? 'AXF_CAT_RT_Expense' : 'AXF_CAT_RT_Revenue';
    }

    get paymentModeOptions() {
        return [
            { label: 'À vista', value: 'A_VISTA' },
            { label: 'Parcelado / Financiamento', value: 'FINANCIAMENTO' },
            { label: 'Financiamento Imobiliário', value: 'FINANCIAMENTO_SAC' },
            { label: 'Consórcio', value: 'CONSORCIO' },
            { label: 'Recorrente', value: 'RECORRENTE' }
        ];
    }

    get paymentMethodOptions() {
        return this.paymentMethodPicklist.data?.values || [];
    }

    get recurringTypeOptions() {
        return [
            { label: 'Valor Fixo', value: 'FIXO' },
            { label: 'Valor Variável', value: 'VARIAVEL' }
        ];
    }

    get provisioningStrategyOptions() {
        return [
            { label: 'Média Móvel', value: 'MEDIA_MOVEL' },
            { label: 'Repetir Último Valor', value: 'ULTIMO_VALOR' },
            { label: 'Manter Valor Base', value: 'VALOR_BASE' }
        ];
    }

    get financingTypeOptions() {
        return [
            { label: 'PRICE', value: 'PRICE' },
            { label: 'SAC', value: 'SAC' }
        ];
    }

    get valueTypeOptions() {
        return [
            { label: 'Valor da Parcela', value: 'PARCELA' },
            { label: 'Valor Total', value: 'TOTAL' }
        ];
    }

    get showBankAccount() {
        return BANK_METHODS.has(this.form.paymentMethod);
    }

    get showCreditCard() {
        return this.form.paymentMethod === 'CARTAO_CREDITO';
    }

    get showRecurringFields() {
        return this.form.paymentMode === 'RECORRENTE';
    }

    get showProvisioningStrategy() {
        return this.showRecurringFields && this.form.recurringType === 'VARIAVEL';
    }

    get showInstallmentCount() {
        return this.showInstallmentFields;
    }

    get showInstallmentFields() {
        return ['FINANCIAMENTO', 'FINANCIAMENTO_SAC', 'CONSORCIO'].includes(this.form.paymentMode);
    }

    get showFinancingFields() {
        return ['FINANCIAMENTO', 'FINANCIAMENTO_SAC'].includes(this.form.paymentMode);
    }

    get showSacRate() {
        return this.form.financingType === 'SAC';
    }

    get showConsortiumFields() {
        return this.form.paymentMode === 'CONSORCIO';
    }

    get isPastDueOpen() {
        return !this.form.isPaid && this.form.firstDueDate && this.form.firstDueDate < new Date().toISOString().substring(0, 10);
    }

    get settlementIconName() {
        return this.form.isPaid ? 'utility:like' : 'utility:dislike';
    }

    get settlementIconVariant() {
        if (this.form.isPaid) {
            return 'success';
        }
        return this.isPastDueOpen ? 'error' : null;
    }

    get settlementLabel() {
        if (this.form.isPaid) {
            return this.entryType === 'DESPESA' ? 'Paga' : 'Recebida';
        }
        return this.isPastDueOpen ? 'Vencida — clique para liquidar' : 'Em aberto';
    }
    get paidValueLabel() {
        return this.entryType === 'DESPESA' ? 'Valor Pago' : 'Valor Recebido';
    }

    get paymentDateLabel() {
        return this.entryType === 'DESPESA' ? 'Data do Pagamento' : 'Data do Recebimento';
    }

    get showPaidFields() {
        return this.form.isPaid;
    }

    get financialLookupDisabled() {
        return !this.form.accountId;
    }


    get isSinglePayment() {
        return this.form.paymentMode === 'A_VISTA';
    }

    get amountLabel() {
        if (this.isSinglePayment) {
            return 'Valor (R$)';
        }
        return this.form.valueType === 'TOTAL' ? 'Valor Total (R$)' : 'Valor da Parcela (R$)';
    }

    get modalTitle() {
        return this.entryType === 'DESPESA' ? 'Nova Despesa' : 'Nova Receita';
    }

    get modalHeaderClass() {
        return this.entryType === 'DESPESA'
            ? 'slds-modal__header slds-theme_error slds-theme_alert-texture'
            : 'slds-modal__header slds-theme_success slds-theme_alert-texture';
    }

    get modalIcon() {
        return this.entryType === 'DESPESA' ? 'utility:monthly_bills' : 'utility:moneybag';
    }

    get saveButtonClass() {
        return this.entryType === 'DESPESA'
            ? 'slds-button slds-button_destructive'
            : 'slds-button slds-button_success';
    }

    handleOpenExpenseModal() {
        this.openModal('DESPESA');
    }

    handleOpenRevenueModal() {
        this.openModal('RECEITA');
    }

    openModal(entryType) {
        this.entryType = entryType;
        this.resetForm();
        this.isModalOpen = true;
    }

    handleCloseModal() {
        this.isModalOpen = false;
    }

    resetForm() {
        const today = new Date().toISOString().substring(0, 10);
        this.amountDisplay = '';
        this.paidValueDisplay = '';
        this.bankAccountOptions = [];
        this.creditCardOptions = [];
        this.form = {
            paymentMode: 'A_VISTA',
            paymentMethod: '',
            description: '',
            categoryId: '',
            accountId: '',
            bankAccountId: '',
            creditCardId: '',
            purchaseDate: today,
            firstDueDate: today,
            valueType: 'PARCELA',
            amount: null,
            totalInstallments: 1,
            recurringType: '',
            provisioningStrategy: '',
            financingType: '',
            monthlyAdjustmentRate: null,
            adjustmentAnniversary: '',
            isPaid: false,
            paidValue: null,
            paymentDate: '',
            pastDueConfirmed: false
        };
    }

    handleCategoryChange(event) {
        this.form.categoryId = event.detail.value || '';
    }

    async handleAccountChange(event) {
        this.form.accountId = event.detail?.value || '';
        this.clearFinancialAccounts();
        await this.loadFinancialAccountOptions();
    }

    async loadFinancialAccountOptions() {
        if (!this.form.accountId) {
            this.bankAccountOptions = [];
            this.creditCardOptions = [];
            return;
        }
        try {
            [this.bankAccountOptions, this.creditCardOptions] = await Promise.all([
                getRecentBankAccounts({ accountId: this.form.accountId }),
                getRecentCreditCards({ accountId: this.form.accountId })
            ]);
        } catch (error) {
            this.bankAccountOptions = [];
            this.creditCardOptions = [];
            this.showToast('Erro ao carregar contas', this.errorMessage(error), 'error');
        }
    }

    handleFinancialAccountChange(event) {
        this.form[event.detail.name] = event.detail.value || '';
    }

    handleInputChange(event) {
        const { name, type } = event.target;
        this.form[name] = type === 'checkbox' ? event.target.checked : event.target.value;

        if (name === 'paymentMethod') {
            this.clearFinancialAccounts();
        }
        if (name === 'paymentMode') {
            this.resetModalityFields();
        }
        if (name === 'financingType' && this.form.financingType !== 'SAC') {
            this.form.monthlyAdjustmentRate = null;
        }
        if (name === 'firstDueDate') {
            this.form.pastDueConfirmed = false;
        }
        if (name === 'isPaid' && !this.form.isPaid) {
            this.form.paidValue = null;
            this.form.paymentDate = '';
        }
    }

    handleSettlementToggle() {
        this.form.isPaid = !this.form.isPaid;
        this.form.pastDueConfirmed = false;
        if (!this.form.isPaid) {
            this.form.paidValue = null;
            this.form.paymentDate = '';
        }
    }
    clearFinancialAccounts() {
        this.form.bankAccountId = '';
        this.form.creditCardId = '';
    }

    resetModalityFields() {
        this.form.recurringType = '';
        this.form.provisioningStrategy = '';
        this.form.financingType = this.form.paymentMode === 'FINANCIAMENTO_SAC' ? 'SAC' : '';
        this.form.monthlyAdjustmentRate = null;
        this.form.adjustmentAnniversary = '';
        if (this.isSinglePayment) {
            this.form.totalInstallments = 1;
        }
    }

    syncVisibleFormValues() {
        const currencyFields = new Set(['amount', 'paidValue']);
        this.template.querySelectorAll('lightning-input').forEach((input) => {
            const fieldName = input.name;
            if (!fieldName || !Object.prototype.hasOwnProperty.call(this.form, fieldName)) {
                return;
            }
            if (currencyFields.has(fieldName)) {
                const digits = String(input.value || '').replace(/\D/g, '');
                this.form[fieldName] = digits ? Number(digits) / 100 : null;
                return;
            }
            this.form[fieldName] = input.type === 'checkbox' ? input.checked : input.value;
        });
    }

    validateForm() {
        this.syncVisibleFormValues();
        const inputs = [...this.template.querySelectorAll('lightning-input, lightning-combobox')];
        const validInputs = inputs.reduce((valid, input) => {
            input.reportValidity();
            return valid && input.checkValidity();
        }, true);
        if (!validInputs || !this.form.accountId) {
            throw new Error('Preencha todos os campos obrigatórios.');
        }
        if (this.showBankAccount && !this.form.bankAccountId) {
            throw new Error('Selecione uma Conta Corrente.');
        }
        if (this.showCreditCard && !this.form.creditCardId) {
            throw new Error('Selecione um Cartão de Crédito.');
        }
    }

    async handleSave() {
        try {
            this.validateForm();
            if (this.isPastDueOpen) {
                const confirmed = await LightningConfirm.open({
                    label: 'Confirmar lançamento vencido',
                    message: 'Este lançamento continuará em aberto e será criado com status Vencida. Deseja continuar?',
                    variant: 'headerless'
                });
                if (!confirmed) {
                    return;
                }
                this.form.pastDueConfirmed = true;
            }
            this.isLoading = true;            await createCashFlowSeries({ dto: this.buildDto() });
            this.showToast('Sucesso', this.modalTitle + ' registrada com sucesso!', 'success');
            this.isModalOpen = false;
            this.dispatchEvent(new CustomEvent('refreshdata', { bubbles: true, composed: true }));
        } catch (error) {
            this.showToast('Erro ao salvar', this.errorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    buildDto() {
        return {
            type: this.entryType,
            description: this.form.description,
            categoryId: this.form.categoryId || null,
            accountId: this.form.accountId,
            purchaseDate: this.form.purchaseDate,
            firstDueDate: this.showInstallmentFields ? this.form.firstDueDate : this.form.purchaseDate,
            paymentMode: this.form.paymentMode,
            amount: Number(this.form.amount),
            isTotalAmount: this.form.valueType === 'TOTAL',
            totalInstallments: Number(this.form.totalInstallments) || 1,
            paymentMethod: this.form.paymentMethod,
            bankAccountId: this.showBankAccount ? this.form.bankAccountId : null,
            creditCardId: this.showCreditCard ? this.form.creditCardId : null,
            recurringType: this.showRecurringFields ? this.form.recurringType : null,
            provisioningStrategy: this.showRecurringFields ? this.form.provisioningStrategy : null,
            financingType: this.showFinancingFields ? this.form.financingType : null,
            monthlyAdjustmentRate: this.showSacRate ? this.toOptionalNumber(this.form.monthlyAdjustmentRate) : null,
            adjustmentAnniversary: this.showConsortiumFields ? this.form.adjustmentAnniversary : null,
            isPaid: this.form.isPaid,
            paidValue: this.form.isPaid ? Number(this.form.paidValue) : null,
            paymentDate: this.form.isPaid ? this.form.paymentDate : null,
            pastDueConfirmed: this.isPastDueOpen ? this.form.pastDueConfirmed : false
        };
    }

    toOptionalNumber(value) {
        return value === '' || value === null || value === undefined ? null : Number(value);
    }

    errorMessage(error) {
        return error?.body?.message || error?.message || 'Não foi possível salvar o lançamento.';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
