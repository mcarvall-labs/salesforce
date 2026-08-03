/**
 * @description Dedicated controller for the aXF_LWC_investmentCapacityKpi LWC. Thin entry point
 * that delegates to ALT_CLS_InvestmentCapacity for the actual calculation/sync logic, per
 * PROJECT_RULES.md §3. Refactored (US-094) — all other methods that used to live here were
 * extracted to their own dedicated controllers: getAccountOptions -> AXF_CLS_CTRL_AccountLookup,
 * getCategoryOptions -> AXF_CLS_CTRL_CategoryLookup, createCashFlowSeries ->
 * AXF_CLS_CTRL_QuickFlowActions, getOverdueExpenses/settleEntry -> AXF_CLS_CTRL_OverdueExpensesAlert,
 * getOverdueRevenues/settleEntry -> AXF_CLS_CTRL_OverdueRevenuesAlert, getMonthlyBalanceMetrics ->
 * AXF_CLS_CTRL_MonthlyBalanceKPI.
 */
public with sharing class AXF_CLS_CTRL_InvestmentCapacityKPI {

    public class BankAccountDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public Decimal balance;
    }

    public class AccountHolderDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
    }

    public class InvestmentCapacityDTO {
        @AuraEnabled public Decimal bankAccountsBalance;
        @AuraEnabled public Decimal monthProjectedSurplus;
        @AuraEnabled public Decimal totalInvestmentCapacity;
        @AuraEnabled public List<BankAccountDTO> positiveBankAccounts;
        @AuraEnabled public List<AccountHolderDTO> accountHolders;
    }

    @AuraEnabled(cacheable=true)
    public static InvestmentCapacityDTO getInvestmentCapacityMetrics(String selectedAccountId) {
        ALT_CLS_InvestmentCapacity businessService = new ALT_CLS_InvestmentCapacity();
        ALT_CLS_InvestmentCapacity.InvestmentCapacityResult businessResult = businessService.getInvestmentCapacityMetrics(selectedAccountId);

        InvestmentCapacityDTO dto = new InvestmentCapacityDTO();
        dto.bankAccountsBalance = businessResult.bankAccountsBalance;
        dto.monthProjectedSurplus = businessResult.monthProjectedSurplus;
        dto.totalInvestmentCapacity = businessResult.totalInvestmentCapacity;

        dto.positiveBankAccounts = new List<BankAccountDTO>();
        for (ALT_CLS_InvestmentCapacity.BankAccountBalanceResult bar : businessResult.positiveBankAccounts) {
            BankAccountDTO bDto = new BankAccountDTO();
            bDto.id = bar.id;
            bDto.name = bar.accName;
            bDto.balance = bar.balance;
            dto.positiveBankAccounts.add(bDto);
        }

        dto.accountHolders = new List<AccountHolderDTO>();
        for (ALT_CLS_InvestmentCapacity.AccountHolderResult ahr : businessResult.accountHolders) {
            AccountHolderDTO hDto = new AccountHolderDTO();
            hDto.id = ahr.id;
            hDto.name = ahr.holderName;
            dto.accountHolders.add(hDto);
        }

        return dto;
    }

    @AuraEnabled
    public static String triggerSyncAllConnections() {
        try {
            ALT_CLS_InvestmentCapacity businessService = new ALT_CLS_InvestmentCapacity();
            return businessService.triggerSyncAllConnections();
        } catch (Exception e) {
            throw new AuraHandledException('Erro ao disparar sincronização: ' + e.getMessage());
        }
    }
}
