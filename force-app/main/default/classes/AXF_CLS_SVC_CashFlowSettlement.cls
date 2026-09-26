/**
 * Shared business logic for settling a Cash Flow entry (marking an expense/revenue as paid or
 * received), used by more than one LWC controller (AXF_CLS_CTRL_OverdueExpensesAlert and
 * AXF_CLS_CTRL_OverdueRevenuesAlert), so the update logic lives in one place.
 */
public with sharing class AXF_CLS_SVC_CashFlowSettlement {

    public static void settleEntry(Id cashFlowId, Date paymentDate, String targetStatus) {
        if (cashFlowId == null) {
            throw new AuraHandledException('Invalid Cash Flow ID.');
        }

        AXF_OBJ_CashFlow__c cf = [
            SELECT Id, RecordType.DeveloperName, AXF_CF_DAT_DueDate__c
            FROM AXF_OBJ_CashFlow__c
            WHERE Id = :cashFlowId
            WITH USER_MODE
            LIMIT 1
        ];

        cf.AXF_CF_DAT_PaymentDate__c = paymentDate != null ? paymentDate : Date.today();
        cf.AXF_CF_PKL_Status__c = targetStatus;

        update cf;
    }
}