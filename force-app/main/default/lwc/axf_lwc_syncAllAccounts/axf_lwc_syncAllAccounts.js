import { LightningElement, track, wire } from "lwc";
import performSync from "@salesforce/apex/AXF_CLS_ManualSyncController.performSync";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { CloseActionScreenEvent } from "lightning/actions";
import {
  IsConsoleNavigation,
  getFocusedTabInfo,
  closeTab
} from "lightning/platformWorkspaceApi";

import AXF_LBL_SyncAllAccountsTitle from "@salesforce/label/c.AXF_LBL_SyncAllAccountsTitle";
import AXF_LBL_SyncAllAccountsDesc from "@salesforce/label/c.AXF_LBL_SyncAllAccountsDesc";
import AXF_LBL_SyncingSpinner from "@salesforce/label/c.AXF_LBL_SyncingSpinner";
import AXF_LBL_SyncCompleted from "@salesforce/label/c.AXF_LBL_SyncCompleted";
import AXF_LBL_BankAccounts from "@salesforce/label/c.AXF_LBL_BankAccounts";
import AXF_LBL_CreditCards from "@salesforce/label/c.AXF_LBL_CreditCards";
import AXF_LBL_SyncError from "@salesforce/label/c.AXF_LBL_SyncError";
import AXF_LBL_ErrorDetails from "@salesforce/label/c.AXF_LBL_ErrorDetails";
import AXF_LBL_StartSyncNow from "@salesforce/label/c.AXF_LBL_StartSyncNow";
import AXF_LBL_TryAgain from "@salesforce/label/c.AXF_LBL_TryAgain";
import AXF_LBL_BackToList from "@salesforce/label/c.AXF_LBL_BackToList";
import AXF_LBL_CancelBack from "@salesforce/label/c.AXF_LBL_CancelBack";
import AXF_LBL_SuccessToastTitle from "@salesforce/label/c.AXF_LBL_SuccessToastTitle";
import AXF_LBL_WarningToastTitle from "@salesforce/label/c.AXF_LBL_WarningToastTitle";
import AXF_LBL_ErrorToastTitle from "@salesforce/label/c.AXF_LBL_ErrorToastTitle";
import AXF_LBL_UnexpectedSyncError from "@salesforce/label/c.AXF_LBL_UnexpectedSyncError";
import AXF_LBL_SyncingAccounts from "@salesforce/label/c.AXF_LBL_SyncingAccounts";

export default class Axf_lwc_syncAllAccounts extends LightningElement {
  @track isLoading = false;
  @track statusMessage = "";
  @track syncResult = null;

  @wire(IsConsoleNavigation) isConsoleNavigation;

  labels = {
    title: AXF_LBL_SyncAllAccountsTitle,
    desc: AXF_LBL_SyncAllAccountsDesc,
    syncingSpinner: AXF_LBL_SyncingSpinner,
    syncCompleted: AXF_LBL_SyncCompleted,
    bankAccounts: AXF_LBL_BankAccounts,
    creditCards: AXF_LBL_CreditCards,
    syncError: AXF_LBL_SyncError,
    errorDetails: AXF_LBL_ErrorDetails,
    startSyncNow: AXF_LBL_StartSyncNow,
    tryAgain: AXF_LBL_TryAgain,
    backToList: AXF_LBL_BackToList,
    cancelBack: AXF_LBL_CancelBack,
    syncingAccounts: AXF_LBL_SyncingAccounts
  };

  get cancelButtonLabel() {
    return this.syncResult ? this.labels.backToList : this.labels.cancelBack;
  }

  get hasDetailedErrors() {
    return (
      this.syncResult &&
      this.syncResult.errors &&
      this.syncResult.errors.length > 0
    );
  }

  handleStartSync() {
    this.isLoading = true;
    this.syncResult = null;
    this.statusMessage = this.labels.syncingSpinner;

    performSync()
      .then((result) => {
        this.isLoading = false;
        this.syncResult = result;

        if (result.isSuccess) {
          this.showToast(AXF_LBL_SuccessToastTitle, result.message, "success");
        } else {
          this.showToast(AXF_LBL_WarningToastTitle, result.message, "warning");
        }
      })
      .catch((error) => {
        this.isLoading = false;
        const errorMsg =
          error && error.body
            ? error.body.message
            : error.message || AXF_LBL_UnexpectedSyncError;
        this.syncResult = {
          isSuccess: false,
          message: errorMsg,
          bankAccountsSynced: 0,
          creditCardsSynced: 0,
          connectionsProcessed: 0,
          errors: [errorMsg]
        };
        this.showToast(AXF_LBL_ErrorToastTitle, errorMsg, "error");
      });
  }

  async handleCancel() {
    await this.navigateBack();
  }

  async navigateBack() {
    this.dispatchEvent(new CloseActionScreenEvent());
    if (this.isConsoleNavigation) {
      try {
        const tabInfo = await getFocusedTabInfo();
        if (tabInfo && tabInfo.tabId) {
          await closeTab(tabInfo.tabId);
          return;
        }
      } catch {
        // Ignore console API error fallback
      }
    }
    if (window.history.length > 1) {
      window.history.back();
    } else {
      window.location.href = "/lightning/o/AXF_OBJ_BankAccount__c/list";
    }
  }

  showToast(title, message, variant) {
    const evt = new ShowToastEvent({
      title: title,
      message: message,
      variant: variant
    });
    this.dispatchEvent(evt);
  }
}
