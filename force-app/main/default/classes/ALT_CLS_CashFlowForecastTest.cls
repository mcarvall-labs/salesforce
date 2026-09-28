@IsTest
private class ALT_CLS_CashFlowForecastTest {
  @TestSetup
  static void setup() {
    User testUser = AXF_CLS_CashFlowTestFactory.createDomainUser();
    System.runAs(testUser) {
      AXF_CLS_CashFlowTestFactory.createAccount('Forecast Holder');
    }
  }

  private static Id holderId() {
    return [SELECT Id FROM Account WHERE Name = 'Forecast Holder' LIMIT 1].Id;
  }

  private static AXF_OBJ_InstallmentGroup__c insertGroup(
    String groupType,
    String financingType,
    Integer totalInstallments
  ) {
    AXF_OBJ_InstallmentGroup__c groupRecord = new AXF_OBJ_InstallmentGroup__c(
      AXF_IG_PKL_GroupType__c = groupType,
      AXF_IG_PKL_FinancingType__c = financingType,
      AXF_IG_NUM_TotalInstallments__c = totalInstallments,
      AXF_IG_CUR_InstallmentAmount__c = 100
    );
    insert groupRecord;
    return groupRecord;
  }

  private static AXF_OBJ_CashFlow__c insertEntry(
    Id groupId,
    String name,
    Date dueDate,
    Integer currentInstallment,
    Integer totalInstallments
  ) {
    AXF_OBJ_CashFlow__c entry = AXF_CLS_CashFlowTestFactory.buildCashFlow(
      true,
      holderId(),
      name,
      100,
      dueDate,
      'PENDENTE'
    );
    entry.AXF_CF_LKP_InstallmentGroup__c = groupId;
    entry.AXF_CF_NUM_CurrentInstallment__c = currentInstallment;
    entry.AXF_CF_NUM_TotalInstallments__c = totalInstallments;
    insert entry;
    return entry;
  }

  @IsTest
  static void extendsRecurringGroupBelowHorizon() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      AXF_OBJ_InstallmentGroup__c groupRecord = insertGroup(
        'RECURRING',
        null,
        null
      );
      AXF_OBJ_CashFlow__c latest = insertEntry(
        groupRecord.Id,
        'Aluguel',
        Date.today().addMonths(2),
        null,
        null
      );

      Test.startTest();
      new ALT_CLS_CashFlowForecast().extendActiveGroups();
      Test.stopTest();

      List<AXF_OBJ_CashFlow__c> entries = [
        SELECT AXF_CF_DAT_DueDate__c, Name
        FROM AXF_OBJ_CashFlow__c
        WHERE AXF_CF_LKP_InstallmentGroup__c = :groupRecord.Id
        ORDER BY AXF_CF_DAT_DueDate__c
      ];
      Assert.areEqual(
        2,
        entries.size(),
        'A new occurrence is appended one month after the latest one'
      );
      Assert.areEqual(
        latest.AXF_CF_DAT_DueDate__c.addMonths(1),
        entries[1].AXF_CF_DAT_DueDate__c
      );
      Assert.areEqual('Aluguel', entries[1].Name);
    }
  }

  @IsTest
  static void skipsRecurringGroupAlreadyAtHorizon() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      AXF_OBJ_InstallmentGroup__c groupRecord = insertGroup(
        'RECURRING',
        null,
        null
      );
      insertEntry(
        groupRecord.Id,
        'Assinatura',
        Date.today().addMonths(ALT_CLS_CashFlowForecast.FUTURE_HORIZON_MONTHS),
        null,
        null
      );

      Test.startTest();
      new ALT_CLS_CashFlowForecast().extendActiveGroups();
      Test.stopTest();

      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM AXF_OBJ_CashFlow__c
          WHERE AXF_CF_LKP_InstallmentGroup__c = :groupRecord.Id
        ],
        'A group already at the horizon is left untouched'
      );
    }
  }

  @IsTest
  static void extendsPriceFinancingWithinTotalAndSkipsOnceComplete() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      AXF_OBJ_InstallmentGroup__c openGroup = insertGroup(
        'FINANCING',
        'PRICE',
        10
      );
      insertEntry(
        openGroup.Id,
        'Financiamento (7/10)',
        Date.today().addMonths(1),
        7,
        10
      );

      AXF_OBJ_InstallmentGroup__c completedGroup = insertGroup(
        'FINANCING',
        'PRICE',
        3
      );
      insertEntry(
        completedGroup.Id,
        'Financiamento (3/3)',
        Date.today().addMonths(1),
        3,
        3
      );

      Test.startTest();
      new ALT_CLS_CashFlowForecast().extendActiveGroups();
      Test.stopTest();

      Assert.areEqual(
        2,
        [
          SELECT COUNT()
          FROM AXF_OBJ_CashFlow__c
          WHERE AXF_CF_LKP_InstallmentGroup__c = :openGroup.Id
        ],
        'Financing below its total gets the next installment'
      );
      AXF_OBJ_CashFlow__c eighth = [
        SELECT Name, AXF_CF_NUM_CurrentInstallment__c
        FROM AXF_OBJ_CashFlow__c
        WHERE
          AXF_CF_LKP_InstallmentGroup__c = :openGroup.Id
          AND AXF_CF_NUM_CurrentInstallment__c = 8
      ];
      Assert.areEqual('Financiamento (8/10)', eighth.Name);
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM AXF_OBJ_CashFlow__c
          WHERE AXF_CF_LKP_InstallmentGroup__c = :completedGroup.Id
        ],
        'A fully materialized financing group is never extended past its total'
      );
    }
  }

  @IsTest
  static void ignoresGroupTypesWithoutForecastMaintenance() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      AXF_OBJ_InstallmentGroup__c consortium = new AXF_OBJ_InstallmentGroup__c(
        AXF_IG_PKL_GroupType__c = 'CONSORTIUM',
        AXF_IG_NUM_TotalInstallments__c = 24,
        AXF_IG_CUR_InstallmentAmount__c = 100,
        AXF_IG_DAT_AdjustmentAnniversary__c = Date.today().addYears(1)
      );
      insert consortium;
      insertEntry(
        consortium.Id,
        'Consorcio (1/24)',
        Date.today().addMonths(1),
        1,
        24
      );

      Test.startTest();
      new ALT_CLS_CashFlowForecast().extendActiveGroups();
      Test.stopTest();

      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM AXF_OBJ_CashFlow__c
          WHERE AXF_CF_LKP_InstallmentGroup__c = :consortium.Id
        ],
        'Only RECURRING and PRICE financing groups are auto-extended'
      );
    }
  }
}
