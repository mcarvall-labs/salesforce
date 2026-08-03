import { LightningElement, track, wire, api } from 'lwc';
import getMonthlyBalanceMetrics from '@salesforce/apex/AXF_CLS_CTRL_MonthlyBalanceKPI.getMonthlyBalanceMetrics';
import { refreshApex } from '@salesforce/apex';

export default class AXF_LWC_monthlyBalanceKpi extends LightningElement {
    @track metrics = {
        plannedRevenues: 0,
        realizedRevenues: 0,
        plannedExpenses: 0,
        realizedExpenses: 0,
        plannedBalance: 0,
        realizedBalance: 0
    };

    wiredMetricsResult;

    @wire(getMonthlyBalanceMetrics)
    wiredMetrics(result) {
        this.wiredMetricsResult = result;
        if (result.data) {
            this.metrics = result.data;
        }
    }

    get currentMonthLabel() {
        const monthNames = [
            'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
            'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'
        ];
        const now = new Date();
        return `${monthNames[now.getMonth()]} / ${now.getFullYear()}`;
    }

    get plannedBalanceBoxClass() {
        const isPositive = (this.metrics.plannedBalance || 0) >= 0;
        return isPositive 
            ? 'slds-box slds-p-around_small kpi-box-positive' 
            : 'slds-box slds-p-around_small kpi-box-negative';
    }

    get realizedBalanceBoxClass() {
        const isPositive = (this.metrics.realizedBalance || 0) >= 0;
        return isPositive 
            ? 'slds-box slds-p-around_small kpi-box-positive' 
            : 'slds-box slds-p-around_small kpi-box-negative';
    }

    @api
    refresh() {
        return refreshApex(this.wiredMetricsResult);
    }
}
