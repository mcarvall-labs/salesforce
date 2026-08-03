import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import refreshBalance from '@salesforce/apex/AXF_CLS_CTRL_RealTimeBalance.refreshBalance';

import BALANCE_FIELD from '@salesforce/schema/AXF_OBJ_BankAccount__c.AXF_BA_CUR_Balance__c';
import LAST_SYNC_FIELD from '@salesforce/schema/AXF_OBJ_BankAccount__c.AXF_BA_DAT_LastSync__c';
import CURRENCY_FIELD from '@salesforce/schema/AXF_OBJ_BankAccount__c.AXF_BA_PKL_Currency__c';

import AXF_LBL_SuccessToastTitle from '@salesforce/label/c.AXF_LBL_SuccessToastTitle';
import AXF_LBL_WarningToastTitle from '@salesforce/label/c.AXF_LBL_WarningToastTitle';
import AXF_LBL_ErrorToastTitle from '@salesforce/label/c.AXF_LBL_ErrorToastTitle';
import AXF_LBL_UnexpectedSyncError from '@salesforce/label/c.AXF_LBL_UnexpectedSyncError';

const FIELDS = [BALANCE_FIELD, LAST_SYNC_FIELD, CURRENCY_FIELD];

export default class AXF_LWC_realTimeBalance extends LightningElement {
    @api recordId;

    isLoading = false;
    justUpdated = false;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    account;

    get hasData() {
        return this.account && this.account.data;
    }

    get balance() {
        return this.hasData ? getFieldValue(this.account.data, BALANCE_FIELD) : null;
    }

    get currencyCode() {
        return (this.hasData && getFieldValue(this.account.data, CURRENCY_FIELD)) || 'BRL';
    }

    get lastSync() {
        return this.hasData ? getFieldValue(this.account.data, LAST_SYNC_FIELD) : null;
    }

    get hasLastSync() {
        return !!this.lastSync;
    }

    get cardCssClass() {
        return this.justUpdated
            ? 'slds-box slds-theme_success slds-m-bottom_small'
            : 'slds-box slds-theme_default slds-m-bottom_small';
    }

    handleRefresh() {
        this.isLoading = true;
        this.justUpdated = false;

        refreshBalance({ bankAccountId: this.recordId })
            .then((result) => {
                this.isLoading = false;
                if (result.isSuccess) {
                    this.justUpdated = true;
                    notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
                    this.showToast(AXF_LBL_SuccessToastTitle, result.message, 'success');
                } else {
                    this.showToast(AXF_LBL_WarningToastTitle, result.message, 'warning');
                }
            })
            .catch((error) => {
                this.isLoading = false;
                const errorMsg = (error && error.body && error.body.message) || error.message || AXF_LBL_UnexpectedSyncError;
                this.showToast(AXF_LBL_ErrorToastTitle, errorMsg, 'error');
            });
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
