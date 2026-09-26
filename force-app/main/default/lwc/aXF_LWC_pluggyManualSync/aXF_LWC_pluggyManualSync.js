import { LightningElement, api, track } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import syncRecord from '@salesforce/apex/AXF_CLS_CTRL_PluggyManualSync.syncRecord';

import AXF_LBL_SuccessToastTitle from '@salesforce/label/c.AXF_LBL_SuccessToastTitle';
import AXF_LBL_WarningToastTitle from '@salesforce/label/c.AXF_LBL_WarningToastTitle';
import AXF_LBL_ErrorToastTitle from '@salesforce/label/c.AXF_LBL_ErrorToastTitle';
import AXF_LBL_UnexpectedSyncError from '@salesforce/label/c.AXF_LBL_UnexpectedSyncError';

export default class AXF_LWC_pluggyManualSync extends LightningElement {
    _recordId;
    _objectApiName;
    styleElement;

    /**
     * When true, renders as a plain inline "Sync" button (no modal card, no internal
     * date pickers) instead of the full quick-action screen. Used when this component is
     * embedded directly in a filter section (aXF_LWC_bankAccountStatement /
     * aXF_LWC_creditCardStatement) rather than launched as a record quick action.
     * In this mode, startDate/endDate are supplied by the parent and are not editable here.
     */
    @api compactMode = false;
    @api startDate;
    @api endDate;

    @track isLoading = false;
    @track syncResult = null;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
    }

    @api
    get objectApiName() {
        return this._objectApiName;
    }
    set objectApiName(value) {
        this._objectApiName = value;
    }

    connectedCallback() {
        if (!this.compactMode) {
            this.injectModalStyles();
            this.initializeDefaultPeriod();
        }
    }

    initializeDefaultPeriod() {
        const now = new Date();
        const firstDayOfCurrentMonth = new Date(now.getFullYear(), now.getMonth(), 1);
        const start = new Date(firstDayOfCurrentMonth.getFullYear(), firstDayOfCurrentMonth.getMonth() - 1, 1);
        const end = new Date(firstDayOfCurrentMonth.getFullYear(), firstDayOfCurrentMonth.getMonth() + 2, 0);
        this.startDate = this.toIsoDate(start);
        this.endDate = this.toIsoDate(end);
    }

    toIsoDate(date) {
        const year = date.getFullYear();
        const month = String(date.getMonth() + 1).padStart(2, '0');
        const day = String(date.getDate()).padStart(2, '0');
        return `${year}-${month}-${day}`;
    }

    handleStartDateChange(event) {
        this.startDate = event.target.value;
    }

    handleEndDateChange(event) {
        this.endDate = event.target.value;
    }

    disconnectedCallback() {
        this.removeModalStyles();
    }

    get title() {
        if (this._objectApiName === 'AXF_OBJ_BankAccount__c') {
            return 'Sincronizar Conta Bancária';
        }
        if (this._objectApiName === 'AXF_OBJ_CreditCard__c') {
            return 'Sincronizar Cartão de Crédito';
        }
        if (this._objectApiName === 'AXF_OBJ_CreditCardInvoice__c') {
            return 'Sincronizar Fatura';
        }
        return 'Sincronizar Registro';
    }

    get description() {
        if (this._objectApiName === 'AXF_OBJ_BankAccount__c') {
            return 'Iniciar sincronização das transações da conta com a Pluggy.';
        }
        if (this._objectApiName === 'AXF_OBJ_CreditCard__c') {
            return 'Iniciar sincronização das faturas e transações do cartão com a Pluggy.';
        }
        if (this._objectApiName === 'AXF_OBJ_CreditCardInvoice__c') {
            return 'Iniciar sincronização das transações da fatura com a Pluggy.';
        }
        return 'Iniciar sincronização dos dados com a Pluggy.';
    }

    get showBankStats() {
        return this._objectApiName === 'AXF_OBJ_BankAccount__c';
    }

    get showCreditStats() {
        return this._objectApiName === 'AXF_OBJ_CreditCard__c' || this._objectApiName === 'AXF_OBJ_CreditCardInvoice__c';
    }

    get hasDetailedErrors() {
        return this.syncResult && this.syncResult.errors && this.syncResult.errors.length > 0;
    }

    get cancelButtonLabel() {
        return this.syncResult ? 'Voltar para o Registro' : 'Cancelar / Voltar';
    }

    handleStartSync() {
        this.isLoading = true;
        this.syncResult = null;

        syncRecord({
            recordId: this._recordId,
            sObjectType: this._objectApiName,
            startDate: this.startDate,
            endDate: this.endDate
        })
            .then(result => {
                this.isLoading = false;
                this.syncResult = result;

                if (result.isSuccess) {
                    this.showToast(AXF_LBL_SuccessToastTitle, result.message, 'success');
                } else {
                    this.showToast(AXF_LBL_WarningToastTitle, result.message, 'warning');
                }
                this.dispatchEvent(new CustomEvent('syncdone', { detail: result }));
            })
            .catch(error => {
                this.isLoading = false;
                const errorMsg = error && error.body ? error.body.message : (error.message || AXF_LBL_UnexpectedSyncError);
                this.syncResult = {
                    isSuccess: false,
                    message: errorMsg,
                    bankAccountsSynced: 0,
                    creditCardsSynced: 0,
                    invoicesSynced: 0,
                    transactionsSynced: 0,
                    errors: [errorMsg]
                };
                this.dispatchEvent(new CustomEvent('syncdone', { detail: this.syncResult }));
                this.showToast(AXF_LBL_ErrorToastTitle, errorMsg, 'error');
            });
    }

    closeAction() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    injectModalStyles() {
        this.styleElement = document.createElement('style');
        this.styleElement.innerText = `
            .slds-modal__container {
                max-width: 620px !important;
                width: 95% !important;
            }
            .slds-modal__content {
                background-color: #0A192F !important;
                color: #FFFFFF !important;
                border-bottom-left-radius: 12px !important;
                border-bottom-right-radius: 12px !important;
            }
            .slds-modal__header {
                background-color: #0A192F !important;
                border-bottom: 0px none !important;
                border-top-left-radius: 12px !important;
                border-top-right-radius: 12px !important;
            }
            .slds-modal__footer {
                background-color: #0A192F !important;
                border-top: 0px none !important;
                border-bottom-left-radius: 12px !important;
                border-bottom-right-radius: 12px !important;
            }
            .slds-modal__title {
                color: #F8FAFC !important;
            }
            .slds-modal__close {
                color: #F8FAFC !important;
            }
            .slds-quick-action-panel {
                background-color: transparent !important;
                border: none !important;
                box-shadow: none !important;
            }
        `;
        document.head.appendChild(this.styleElement);
    }

    removeModalStyles() {
        if (this.styleElement) {
            this.styleElement.remove();
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}