import { LightningElement, track, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getInvestmentCapacityMetrics from "@salesforce/apex/AXF_CLS_CTRL_InvestmentCapacityKPI.getInvestmentCapacityMetrics";
import triggerSyncAllConnections from "@salesforce/apex/AXF_CLS_CTRL_InvestmentCapacityKPI.triggerSyncAllConnections";

export default class AXF_LWC_investmentCapacityKpi extends NavigationMixin(
  LightningElement
) {
  @track metrics = {
    bankAccountsBalance: 0,
    monthProjectedSurplus: 0,
    totalInvestmentCapacity: 0,
    positiveBankAccounts: [],
    accountHolders: []
  };

  selectedAccountId = "ALL";
  isLoading = false;

  connectedCallback() {
    this.loadMetrics();
  }

  loadMetrics() {
    return getInvestmentCapacityMetrics({
      selectedAccountId: this.selectedAccountId
    })
      .then((data) => {
        this.metrics = data;
      })
      .catch((error) => {
        const errorMsg =
          (error && error.body && error.body.message) ||
          error.message ||
          "Erro ao carregar métricas.";
        this.showToast("Erro", errorMsg, "error");
      });
  }

  get hasPositiveAccounts() {
    return (
      this.metrics &&
      this.metrics.positiveBankAccounts &&
      this.metrics.positiveBankAccounts.length > 0
    );
  }

  get isGeneralTab() {
    return this.selectedAccountId === "ALL";
  }

  get geralTabItemClass() {
    return this.isGeneralTab
      ? "slds-tabs_default__item slds-is-active"
      : "slds-tabs_default__item";
  }

  get geralTabAriaSelected() {
    return this.isGeneralTab ? "true" : "false";
  }

  get accountHolderTabs() {
    const holders = (this.metrics && this.metrics.accountHolders) || [];
    return holders.map((holder) => ({
      ...holder,
      tabItemClass:
        holder.id === this.selectedAccountId
          ? "slds-tabs_default__item slds-is-active"
          : "slds-tabs_default__item",
      ariaSelected: holder.id === this.selectedAccountId ? "true" : "false"
    }));
  }

  handleTabClick(event) {
    event.preventDefault();
    const accountId = event.currentTarget.dataset.id;
    if (!accountId || accountId === this.selectedAccountId) {
      return;
    }
    this.selectedAccountId = accountId;
    this.loadMetrics();
  }

  handleAccountClick(event) {
    const recordId = event.currentTarget.dataset.id;
    if (recordId) {
      this[NavigationMixin.Navigate]({
        type: "standard__recordPage",
        attributes: {
          recordId: recordId,
          actionName: "view"
        }
      });
    }
  }

  handleRefresh() {
    this.isLoading = true;
    triggerSyncAllConnections()
      .then((message) => {
        return this.loadMetrics().then(() => {
          this.showToast(
            "Sucesso",
            message || "Atualização iniciada com sucesso.",
            "success"
          );
        });
      })
      .catch((error) => {
        const errorMsg =
          (error && error.body && error.body.message) ||
          error.message ||
          "Erro ao processar atualização.";
        this.showToast("Erro", errorMsg, "error");
      })
      .finally(() => {
        this.isLoading = false;
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

  @api
  refresh() {
    return this.loadMetrics();
  }
}
