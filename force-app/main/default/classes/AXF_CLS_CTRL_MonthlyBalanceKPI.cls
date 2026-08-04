/**
 * @description Dedicated controller for the aXF_LWC_monthlyBalanceKpi LWC. Thin entry point that
 * delegates to ALT_CLS_InvestmentCapacity for the monthly balance calculation, per
 * PROJECT_RULES.md §3.
 */
public with sharing class AXF_CLS_CTRL_MonthlyBalanceKPI {
  public class MonthlyBalanceDTO {
    @AuraEnabled
    public Decimal plannedRevenues;
    @AuraEnabled
    public Decimal realizedRevenues;
    @AuraEnabled
    public Decimal plannedExpenses;
    @AuraEnabled
    public Decimal realizedExpenses;
    @AuraEnabled
    public Decimal plannedBalance;
    @AuraEnabled
    public Decimal realizedBalance;
  }

  @AuraEnabled(cacheable=true)
  public static MonthlyBalanceDTO getMonthlyBalanceMetrics() {
    ALT_CLS_InvestmentCapacity businessService = new ALT_CLS_InvestmentCapacity();
    ALT_CLS_InvestmentCapacity.MonthlyBalanceResult businessResult = businessService.getMonthlyBalanceMetrics(
      null
    );

    MonthlyBalanceDTO dto = new MonthlyBalanceDTO();
    dto.plannedRevenues = businessResult.plannedRevenues;
    dto.realizedRevenues = businessResult.realizedRevenues;
    dto.plannedExpenses = businessResult.plannedExpenses;
    dto.realizedExpenses = businessResult.realizedExpenses;
    dto.plannedBalance = businessResult.plannedBalance;
    dto.realizedBalance = businessResult.realizedBalance;
    return dto;
  }
}
