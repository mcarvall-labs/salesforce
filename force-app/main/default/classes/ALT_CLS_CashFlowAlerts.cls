/**
 * @description Business service layer for overdue Cash Flow alerts (expenses and revenues) and
 * the settlement of a single overdue entry. Consumed by AXF_CLS_CTRL_OverdueExpensesAlert and
 * AXF_CLS_CTRL_OverdueRevenuesAlert. Contains no @AuraEnabled members and no LWC-specific
 * concepts, per PROJECT_RULES.md §3.
 */
public inherited sharing class ALT_CLS_CashFlowAlerts {
  public List<AXF_OBJ_CashFlow__c> getOverdueExpenses() {
    Date firstDayOfThisMonth = Date.today().toStartOfMonth();
    return [
      SELECT
        Id,
        Name,
        AXF_CF_CUR_Value__c,
        AXF_CF_DAT_DueDate__c,
        AXF_CF_PKL_Status__c,
        AXF_CF_LKP_Category__r.Name,
        AXF_CF_NUM_CurrentInstallment__c,
        AXF_CF_NUM_TotalInstallments__c
      FROM AXF_OBJ_CashFlow__c
      WHERE
        RecordType.DeveloperName = 'AXF_CF_RT_Expense'
        AND AXF_CF_DAT_DueDate__c < :firstDayOfThisMonth
        AND AXF_CF_PKL_Status__c IN ('PENDENTE', 'VENCIDA')
      WITH USER_MODE
      ORDER BY AXF_CF_DAT_DueDate__c ASC
    ];
  }

  public List<AXF_OBJ_CashFlow__c> getOverdueRevenues() {
    Date firstDayOfThisMonth = Date.today().toStartOfMonth();
    return [
      SELECT
        Id,
        Name,
        AXF_CF_CUR_Value__c,
        AXF_CF_DAT_DueDate__c,
        AXF_CF_PKL_Status__c,
        AXF_CF_LKP_Category__r.Name,
        AXF_CF_NUM_CurrentInstallment__c,
        AXF_CF_NUM_TotalInstallments__c
      FROM AXF_OBJ_CashFlow__c
      WHERE
        RecordType.DeveloperName = 'AXF_CF_RT_Revenue'
        AND AXF_CF_DAT_DueDate__c < :firstDayOfThisMonth
        AND AXF_CF_PKL_Status__c IN ('PENDENTE', 'VENCIDA')
      WITH USER_MODE
      ORDER BY AXF_CF_DAT_DueDate__c ASC
    ];
  }

  public void settleEntry(
    Id cashFlowId,
    Date paymentDate,
    String targetStatus
  ) {
    if (cashFlowId == null) {
      throw new IllegalArgumentException('Cash Flow ID is required.');
    }

    AXF_OBJ_CashFlow__c cf = [
      SELECT Id, RecordType.DeveloperName, AXF_CF_DAT_DueDate__c
      FROM AXF_OBJ_CashFlow__c
      WHERE Id = :cashFlowId
      WITH USER_MODE
      LIMIT 1
    ];

    cf.AXF_CF_DAT_PaymentDate__c = paymentDate != null
      ? paymentDate
      : Date.today();
    cf.AXF_CF_PKL_Status__c = targetStatus;

    update cf;
  }
}
