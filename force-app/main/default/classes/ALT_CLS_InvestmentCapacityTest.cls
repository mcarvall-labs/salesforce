/**
 * @description Covers ALT_CLS_InvestmentCapacity, AXF_CLS_SVC_CashFlowBalance and the KPI
 * controllers AXF_CLS_CTRL_InvestmentCapacityKPI and AXF_CLS_CTRL_MonthlyBalanceKPI.
 */
@IsTest
private class ALT_CLS_InvestmentCapacityTest {
  @TestSetup
  static void setup() {
    User testUser = AXF_CLS_CashFlowTestFactory.createDomainUser();
    System.runAs(testUser) {
      Account primary = AXF_CLS_CashFlowTestFactory.createAccount(
        'Maria da Silva Souza'
      );
      Account secondary = AXF_CLS_CashFlowTestFactory.createAccount('Joao');
      AXF_CLS_CashFlowTestFactory.createBankAccount(
        primary.Id,
        'IC_BANK_1',
        1000
      );
      AXF_CLS_CashFlowTestFactory.createBankAccount(
        primary.Id,
        'IC_BANK_2',
        500
      );
      AXF_CLS_CashFlowTestFactory.createBankAccount(
        primary.Id,
        'IC_BANK_ZERO',
        0
      );
      AXF_CLS_CashFlowTestFactory.createBankAccount(
        secondary.Id,
        'IC_BANK_3',
        -200
      );

      Date today = Date.today();
      insert new List<AXF_OBJ_CashFlow__c>{
        AXF_CLS_CashFlowTestFactory.buildCashFlow(
          false,
          primary.Id,
          'Salario',
          3000,
          today,
          'RECEBIDA'
        ),
        AXF_CLS_CashFlowTestFactory.buildCashFlow(
          false,
          primary.Id,
          'Bonus',
          1000,
          today,
          'PENDENTE'
        ),
        AXF_CLS_CashFlowTestFactory.buildCashFlow(
          true,
          primary.Id,
          'Aluguel',
          800,
          today,
          'PAGA'
        ),
        AXF_CLS_CashFlowTestFactory.buildCashFlow(
          true,
          primary.Id,
          'Mercado',
          200,
          today,
          'PENDENTE'
        ),
        AXF_CLS_CashFlowTestFactory.buildCashFlow(
          false,
          secondary.Id,
          'Freela',
          100,
          today,
          'PENDENTE'
        ),
        AXF_CLS_CashFlowTestFactory.buildCashFlow(
          true,
          primary.Id,
          'Outro mes',
          999,
          today.toStartOfMonth().addMonths(1),
          'PENDENTE'
        )
      };
    }
  }

  private static Id primaryId() {
    return [SELECT Id FROM Account WHERE Name = 'Maria da Silva Souza'].Id;
  }

  @IsTest
  static void monthlyBalanceKpiAggregatesAllHolders() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      Test.startTest();
      AXF_CLS_CTRL_MonthlyBalanceKPI.MonthlyBalanceDTO dto = AXF_CLS_CTRL_MonthlyBalanceKPI.getMonthlyBalanceMetrics();
      Test.stopTest();

      Assert.areEqual(4100, dto.plannedRevenues);
      Assert.areEqual(3000, dto.realizedRevenues);
      Assert.areEqual(1000, dto.plannedExpenses);
      Assert.areEqual(800, dto.realizedExpenses);
      Assert.areEqual(3100, dto.plannedBalance);
      Assert.areEqual(2200, dto.realizedBalance);
    }
  }

  @IsTest
  static void sharedBalanceServiceFiltersByHolder() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      Test.startTest();
      AXF_CLS_SVC_CashFlowBalance.MonthlyBalanceDTO all = AXF_CLS_SVC_CashFlowBalance.calculateMonthlyBalance(
        'ALL'
      );
      AXF_CLS_SVC_CashFlowBalance.MonthlyBalanceDTO primary = AXF_CLS_SVC_CashFlowBalance.calculateMonthlyBalance(
        primaryId()
      );
      ALT_CLS_InvestmentCapacity.MonthlyBalanceResult business = new ALT_CLS_InvestmentCapacity()
        .getMonthlyBalanceMetrics(primaryId());
      Test.stopTest();

      Assert.areEqual(3100, all.plannedBalance);
      Assert.areEqual(2200, all.realizedBalance);
      Assert.areEqual(4000, primary.plannedRevenues);
      Assert.areEqual(3000, primary.plannedBalance);
      Assert.areEqual(800, primary.realizedExpenses);
      Assert.areEqual(3000, business.plannedBalance);
      Assert.areEqual(2200, business.realizedBalance);
    }
  }

  @IsTest
  static void investmentCapacityForAllHolders() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      Test.startTest();
      AXF_CLS_CTRL_InvestmentCapacityKPI.InvestmentCapacityDTO dto = AXF_CLS_CTRL_InvestmentCapacityKPI.getInvestmentCapacityMetrics(
        'ALL'
      );
      Test.stopTest();

      Assert.areEqual(1300, dto.bankAccountsBalance);
      Assert.areEqual(3100, dto.monthProjectedSurplus);
      Assert.areEqual(4400, dto.totalInvestmentCapacity);
      Assert.areEqual(
        3,
        dto.positiveBankAccounts.size(),
        'Zero-balance accounts are hidden'
      );
      Assert.areEqual(2, dto.accountHolders.size());
      Set<String> holderNames = new Set<String>();
      for (
        AXF_CLS_CTRL_InvestmentCapacityKPI.AccountHolderDTO holder : dto.accountHolders
      ) {
        holderNames.add(holder.name);
        Assert.isNotNull(holder.id);
      }
      Assert.isTrue(
        holderNames.contains('Maria Souza'),
        'Display name keeps first and last names'
      );
      Assert.isTrue(holderNames.contains('Joao'));
    }
  }

  @IsTest
  static void investmentCapacityForSelectedHolder() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      Test.startTest();
      AXF_CLS_CTRL_InvestmentCapacityKPI.InvestmentCapacityDTO dto = AXF_CLS_CTRL_InvestmentCapacityKPI.getInvestmentCapacityMetrics(
        primaryId()
      );
      Test.stopTest();

      Assert.areEqual(1500, dto.bankAccountsBalance);
      Assert.areEqual(3000, dto.monthProjectedSurplus);
      Assert.areEqual(4500, dto.totalInvestmentCapacity);
      Assert.areEqual(2, dto.positiveBankAccounts.size());
      Decimal listed = 0;
      for (
        AXF_CLS_CTRL_InvestmentCapacityKPI.BankAccountDTO account : dto.positiveBankAccounts
      ) {
        listed += account.balance;
        Assert.isNotNull(account.name);
      }
      Assert.areEqual(1500, listed);
    }
  }

  @IsTest
  static void investmentCapacityWithoutBankAccounts() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      Account empty = AXF_CLS_CashFlowTestFactory.createAccount('Sem Contas');

      Test.startTest();
      ALT_CLS_InvestmentCapacity.InvestmentCapacityResult result = new ALT_CLS_InvestmentCapacity()
        .getInvestmentCapacityMetrics(empty.Id);
      Test.stopTest();

      Assert.areEqual(0, result.bankAccountsBalance);
      Assert.areEqual(0, result.totalInvestmentCapacity);
      Assert.isTrue(result.positiveBankAccounts.isEmpty());
    }
  }

  @IsTest
  static void triggersFullConnectionSync() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      Test.startTest();
      String message = AXF_CLS_CTRL_InvestmentCapacityKPI.triggerSyncAllConnections();
      Integer queued = Limits.getQueueableJobs();
      Test.stopTest();

      Assert.areEqual('Sincronização iniciada com sucesso.', message);
      Assert.areEqual(1, queued, 'One sync job is enqueued');
    }
  }
}
