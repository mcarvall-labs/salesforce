/**
 * @description Dedicated controller for the aXF_LWC_overdueRevenuesAlert LWC. Thin entry point
 * that delegates to ALT_CLS_CashFlowAlerts for the actual query/settlement logic, per
 * PROJECT_RULES.md §3.
 */
public with sharing class AXF_CLS_CTRL_OverdueRevenuesAlert {

    @AuraEnabled(cacheable=true)
    public static List<AXF_OBJ_CashFlow__c> getOverdueRevenues() {
        ALT_CLS_CashFlowAlerts businessService = new ALT_CLS_CashFlowAlerts();
        return businessService.getOverdueRevenues();
    }

    @AuraEnabled
    public static void settleEntry(Id cashFlowId, Date paymentDate, String targetStatus) {
        if (cashFlowId == null) {
            throw new AuraHandledException('Invalid Cash Flow ID.');
        }
        try {
            ALT_CLS_CashFlowAlerts businessService = new ALT_CLS_CashFlowAlerts();
            businessService.settleEntry(cashFlowId, paymentDate, targetStatus);
        } catch (Exception e) {
            throw new AuraHandledException('Erro ao liquidar lançamento: ' + e.getMessage());
        }
    }
}
