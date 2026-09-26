/**
 * Shared business logic for computing monthly cash flow balances, used by more than one
 * LWC controller (AXF_CLS_CTRL_MonthlyBalanceKpi and AXF_CLS_CTRL_InvestmentCapacityKPI),
 * so the calculation lives in one place instead of each controller's own copy.
 */
public with sharing class AXF_CLS_SVC_CashFlowBalance {

    public class MonthlyBalanceDTO {
        @AuraEnabled public Decimal plannedRevenues;
        @AuraEnabled public Decimal realizedRevenues;
        @AuraEnabled public Decimal plannedExpenses;
        @AuraEnabled public Decimal realizedExpenses;
        @AuraEnabled public Decimal plannedBalance;
        @AuraEnabled public Decimal realizedBalance;
    }

    public static MonthlyBalanceDTO calculateMonthlyBalance(String selectedAccountId) {
        Date startOfMonth = Date.today().toStartOfMonth();
        Date endOfMonth = startOfMonth.addMonths(1).addDays(-1);

        List<AXF_OBJ_CashFlow__c> monthEntries;
        if (String.isNotBlank(selectedAccountId) && selectedAccountId != 'ALL') {
            monthEntries = [
                SELECT Id, RecordType.DeveloperName, AXF_CF_CUR_Value__c, AXF_CF_PKL_Status__c
                FROM AXF_OBJ_CashFlow__c
                WHERE AXF_CF_DAT_DueDate__c >= :startOfMonth AND AXF_CF_DAT_DueDate__c <= :endOfMonth
                  AND AXF_CF_LKP_Account__c = :selectedAccountId
                WITH USER_MODE
            ];
        } else {
            monthEntries = [
                SELECT Id, RecordType.DeveloperName, AXF_CF_CUR_Value__c, AXF_CF_PKL_Status__c
                FROM AXF_OBJ_CashFlow__c
                WHERE AXF_CF_DAT_DueDate__c >= :startOfMonth AND AXF_CF_DAT_DueDate__c <= :endOfMonth
                WITH USER_MODE
            ];
        }

        MonthlyBalanceDTO dto = new MonthlyBalanceDTO();
        dto.plannedRevenues = 0;
        dto.realizedRevenues = 0;
        dto.plannedExpenses = 0;
        dto.realizedExpenses = 0;

        for (AXF_OBJ_CashFlow__c cf : monthEntries) {
            Decimal val = cf.AXF_CF_CUR_Value__c != null ? cf.AXF_CF_CUR_Value__c : 0;
            if (cf.RecordType.DeveloperName == 'AXF_CF_RT_Revenue') {
                dto.plannedRevenues += val;
                if (cf.AXF_CF_PKL_Status__c == 'RECEBIDA' || cf.AXF_CF_PKL_Status__c == 'RECEBIDA_EM_ATRASO') {
                    dto.realizedRevenues += val;
                }
            } else if (cf.RecordType.DeveloperName == 'AXF_CF_RT_Expense') {
                dto.plannedExpenses += val;
                if (cf.AXF_CF_PKL_Status__c == 'PAGA' || cf.AXF_CF_PKL_Status__c == 'PAGA_EM_ATRASO') {
                    dto.realizedExpenses += val;
                }
            }
        }

        dto.plannedBalance = dto.plannedRevenues - dto.plannedExpenses;
        dto.realizedBalance = dto.realizedRevenues - dto.realizedExpenses;

        return dto;
    }
}