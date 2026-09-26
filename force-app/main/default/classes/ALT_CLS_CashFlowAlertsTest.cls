/**
 * @description Covers ALT_CLS_CashFlowAlerts, its controllers AXF_CLS_CTRL_OverdueExpensesAlert
 * and AXF_CLS_CTRL_OverdueRevenuesAlert, and the shared AXF_CLS_SVC_CashFlowSettlement service.
 */
@IsTest
private class ALT_CLS_CashFlowAlertsTest {
  @TestSetup
  static void setup() {
    User testUser = AXF_CLS_CashFlowTestFactory.createDomainUser();
    System.runAs(testUser) {
      Account holder = AXF_CLS_CashFlowTestFactory.createAccount(
        'Alerts Holder'
      );
      Date lastMonth = Date.today().toStartOfMonth().addDays(-3);
      Date twoMonthsAgo = Date.today().toStartOfMonth().addMonths(-2);
      insert new List<AXF_OBJ_CashFlow__c>{
        AXF_CLS_CashFlowTestFactory.buildCashFlow(
          true,
          holder.Id,
          'Old expense',
          100,
          twoMonthsAgo,
          'VENCIDA'
        ),
        AXF_CLS_CashFlowTestFactory.buildCashFlow(
          true,
          holder.Id,
          'Late expense',
          50,
          lastMonth,
          'PENDENTE'
        ),
        AXF_CLS_CashFlowTestFactory.buildCashFlow(
          true,
          holder.Id,
          'Current expense',
          70,
          Date.today(),
          'PENDENTE'
        ),
        AXF_CLS_CashFlowTestFactory.buildCashFlow(
          true,
          holder.Id,
          'Paid expense',
          70,
          lastMonth,
          'PAGA'
        ),
        AXF_CLS_CashFlowTestFactory.buildCashFlow(
          false,
          holder.Id,
          'Late revenue',
          900,
          lastMonth,
          'VENCIDA'
        ),
        AXF_CLS_CashFlowTestFactory.buildCashFlow(
          false,
          holder.Id,
          'Current revenue',
          900,
          Date.today(),
          'PENDENTE'
        )
      };
    }
  }

  private static Id entryId(String name) {
    return [SELECT Id FROM AXF_OBJ_CashFlow__c WHERE Name = :name].Id;
  }

  @IsTest
  static void listsOnlyOpenEntriesFromPreviousMonths() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      Test.startTest();
      List<AXF_OBJ_CashFlow__c> expenses = AXF_CLS_CTRL_OverdueExpensesAlert.getOverdueExpenses();
      List<AXF_OBJ_CashFlow__c> revenues = AXF_CLS_CTRL_OverdueRevenuesAlert.getOverdueRevenues();
      Test.stopTest();

      Assert.areEqual(2, expenses.size());
      Assert.areEqual('Old expense', expenses[0].Name, 'Ordered by due date');
      Assert.areEqual('Late expense', expenses[1].Name);
      Assert.areEqual(1, revenues.size());
      Assert.areEqual('Late revenue', revenues[0].Name);
    }
  }

  @IsTest
  static void settlesOverdueEntriesThroughControllers() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      Id expenseId = entryId('Late expense');
      Id revenueId = entryId('Late revenue');

      Test.startTest();
      AXF_CLS_CTRL_OverdueExpensesAlert.settleEntry(expenseId, null, 'PAGA');
      AXF_CLS_CTRL_OverdueRevenuesAlert.settleEntry(
        revenueId,
        Date.today().toStartOfMonth().addDays(-3),
        'RECEBIDA'
      );
      Test.stopTest();

      AXF_OBJ_CashFlow__c expense = [
        SELECT AXF_CF_PKL_Status__c, AXF_CF_DAT_PaymentDate__c
        FROM AXF_OBJ_CashFlow__c
        WHERE Id = :expenseId
      ];
      Assert.areEqual(
        'PAGA_EM_ATRASO',
        expense.AXF_CF_PKL_Status__c,
        'Settled today after the due date'
      );
      Assert.areEqual(Date.today(), expense.AXF_CF_DAT_PaymentDate__c);
      Assert.areEqual(
        'RECEBIDA',
        [
          SELECT AXF_CF_PKL_Status__c
          FROM AXF_OBJ_CashFlow__c
          WHERE Id = :revenueId
        ]
        .AXF_CF_PKL_Status__c
      );
      Assert.areEqual(
        1,
        AXF_CLS_CTRL_OverdueExpensesAlert.getOverdueExpenses().size()
      );
    }
  }

  @IsTest
  static void controllersReportInvalidRequests() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      Id expenseId = entryId('Late expense');
      Id revenueId = entryId('Late revenue');
      List<String> messages = new List<String>();

      Test.startTest();
      try {
        AXF_CLS_CTRL_OverdueExpensesAlert.settleEntry(null, null, 'PAGA');
      } catch (AuraHandledException e) {
        messages.add(e.getMessage());
      }
      try {
        AXF_CLS_CTRL_OverdueRevenuesAlert.settleEntry(null, null, 'RECEBIDA');
      } catch (AuraHandledException e) {
        messages.add(e.getMessage());
      }
      try {
        // Unknown values are rejected by the restricted status picklist.
        AXF_CLS_CTRL_OverdueExpensesAlert.settleEntry(
          expenseId,
          Date.today(),
          'INVALIDO'
        );
      } catch (AuraHandledException e) {
        messages.add(e.getMessage());
      }
      try {
        AXF_CLS_CTRL_OverdueRevenuesAlert.settleEntry(
          revenueId,
          Date.today(),
          'INVALIDO'
        );
      } catch (AuraHandledException e) {
        messages.add(e.getMessage());
      }
      String serviceMessage;
      try {
        new ALT_CLS_CashFlowAlerts().settleEntry(null, null, 'PAGA');
      } catch (IllegalArgumentException e) {
        serviceMessage = e.getMessage();
      }
      Test.stopTest();

      Assert.areEqual(4, messages.size());
      // AuraHandledException built without setMessage() exposes a generic message in tests,
      // so only the rejection itself is asserted for the controller paths.
      for (String message : messages) {
        Assert.isNotNull(message);
      }
      Assert.areEqual('Cash Flow ID is required.', serviceMessage);
      Assert.areEqual(
        'PENDENTE',
        [
          SELECT AXF_CF_PKL_Status__c
          FROM AXF_OBJ_CashFlow__c
          WHERE Id = :expenseId
        ]
        .AXF_CF_PKL_Status__c
      );
    }
  }

  @IsTest
  static void sharedSettlementServiceUpdatesEntry() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      Id expenseId = entryId('Old expense');
      Id revenueId = entryId('Current revenue');
      String nullIdMessage;

      Test.startTest();
      AXF_CLS_SVC_CashFlowSettlement.settleEntry(
        expenseId,
        Date.today().toStartOfMonth().addMonths(-2),
        'PAGA'
      );
      AXF_CLS_SVC_CashFlowSettlement.settleEntry(revenueId, null, 'RECEBIDA');
      try {
        AXF_CLS_SVC_CashFlowSettlement.settleEntry(null, null, 'PAGA');
      } catch (AuraHandledException e) {
        nullIdMessage = e.getMessage();
      }
      Test.stopTest();

      Assert.areEqual(
        'PAGA',
        [
          SELECT AXF_CF_PKL_Status__c
          FROM AXF_OBJ_CashFlow__c
          WHERE Id = :expenseId
        ]
        .AXF_CF_PKL_Status__c
      );
      AXF_OBJ_CashFlow__c revenue = [
        SELECT AXF_CF_PKL_Status__c, AXF_CF_DAT_PaymentDate__c
        FROM AXF_OBJ_CashFlow__c
        WHERE Id = :revenueId
      ];
      Assert.areEqual('RECEBIDA', revenue.AXF_CF_PKL_Status__c);
      Assert.areEqual(Date.today(), revenue.AXF_CF_DAT_PaymentDate__c);
      Assert.isNotNull(nullIdMessage);
    }
  }
}
