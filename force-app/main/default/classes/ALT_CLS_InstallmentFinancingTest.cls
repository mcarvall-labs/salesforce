/**
 * @description Covers the rolling-window financing services ALT_CLS_PriceFinancing,
 * ALT_CLS_SacFinancing and ALT_CLS_Consortium, plus the AXF_TRG_InstallmentGroup trigger. Runs
 * as a user holding AXF_PS_User plus a test-only FLS permission set, since the services read and
 * write in USER_MODE fields that AXF_PS_User does not grant.
 */
@IsTest
private class ALT_CLS_InstallmentFinancingTest {
  private static final String USER_KEY = 'financing';

  @TestSetup
  static void setup() {
    User financeUser = AXF_CLS_AccountCardTestFactory.createUser(
      USER_KEY,
      true
    );
    System.runAs(financeUser) {
      Account holder = AXF_CLS_AccountCardTestFactory.newAccount(
        'Titular Financiamento'
      );
      insert holder;

      Date today = Date.today();
      AXF_OBJ_InstallmentGroup__c price = new AXF_OBJ_InstallmentGroup__c(
        AXF_IG_PKL_GroupType__c = 'FINANCING',
        AXF_IG_PKL_FinancingType__c = 'PRICE',
        AXF_IG_NUM_TotalInstallments__c = 12,
        AXF_IG_CUR_InstallmentAmount__c = 100,
        AXF_IG_CUR_TotalAmount__c = 1250,
        AXF_IG_DAT_FirstDueDate__c = today.addMonths(-1)
      );
      AXF_OBJ_InstallmentGroup__c priceEmpty = new AXF_OBJ_InstallmentGroup__c(
        AXF_IG_PKL_GroupType__c = 'FINANCING',
        AXF_IG_PKL_FinancingType__c = 'PRICE',
        AXF_IG_NUM_TotalInstallments__c = 3,
        AXF_IG_CUR_InstallmentAmount__c = 10,
        AXF_IG_CUR_TotalAmount__c = 30,
        AXF_IG_DAT_FirstDueDate__c = today
      );
      AXF_OBJ_InstallmentGroup__c consortium = new AXF_OBJ_InstallmentGroup__c(
        AXF_IG_PKL_GroupType__c = 'CONSORTIUM',
        AXF_IG_DAT_AdjustmentAnniversary__c = today.addMonths(11),
        AXF_IG_NUM_TotalInstallments__c = 20,
        AXF_IG_CUR_InstallmentAmount__c = 500,
        AXF_IG_DAT_FirstDueDate__c = today.addMonths(-2)
      );
      AXF_OBJ_InstallmentGroup__c sac = new AXF_OBJ_InstallmentGroup__c(
        AXF_IG_PKL_GroupType__c = 'FINANCING',
        AXF_IG_PKL_FinancingType__c = 'SAC',
        AXF_IG_PCT_MonthlyAdjustmentRate__c = 1,
        AXF_IG_NUM_TotalInstallments__c = 24,
        AXF_IG_CUR_InstallmentAmount__c = 1000,
        AXF_IG_DAT_FirstDueDate__c = today
      );
      insert new List<AXF_OBJ_InstallmentGroup__c>{
        price,
        priceEmpty,
        consortium,
        sac
      };

      List<AXF_OBJ_CashFlow__c> entries = new List<AXF_OBJ_CashFlow__c>();
      entries.addAll(
        buildEntries(
          price,
          holder.Id,
          'Carro',
          'FINANCIAMENTO',
          ALT_CLS_PriceFinancing.initialWindow(12)
        )
      );
      entries.addAll(
        buildEntries(
          consortium,
          holder.Id,
          'Consorcio',
          'CONSORCIO',
          ALT_CLS_Consortium.initialWindow(20)
        )
      );
      entries.addAll(
        buildEntries(
          sac,
          holder.Id,
          'Casa',
          'FINANCIAMENTO_SAC',
          ALT_CLS_SacFinancing.initialWindow(24)
        )
      );
      insert entries;
    }
  }

  private static List<AXF_OBJ_CashFlow__c> buildEntries(
    AXF_OBJ_InstallmentGroup__c groupRecord,
    Id accountId,
    String baseName,
    String paymentMode,
    Integer count
  ) {
    Id expenseRt = Schema.SObjectType.AXF_OBJ_CashFlow__c.getRecordTypeInfosByDeveloperName()
      .get('AXF_CF_RT_Expense')
      .getRecordTypeId();
    Integer total = Integer.valueOf(
      groupRecord.AXF_IG_NUM_TotalInstallments__c
    );
    List<AXF_OBJ_CashFlow__c> entries = new List<AXF_OBJ_CashFlow__c>();
    for (Integer sequence = 1; sequence <= count; sequence++) {
      entries.add(
        new AXF_OBJ_CashFlow__c(
          RecordTypeId = expenseRt,
          Name = baseName + ' (' + sequence + '/' + total + ')',
          AXF_CF_CUR_Value__c = groupRecord.AXF_IG_CUR_InstallmentAmount__c,
          AXF_CF_DAT_PurchaseDate__c = groupRecord.AXF_IG_DAT_FirstDueDate__c,
          AXF_CF_DAT_DueDate__c = groupRecord.AXF_IG_DAT_FirstDueDate__c.addMonths(
            sequence - 1
          ),
          AXF_CF_PKL_Status__c = 'PENDENTE',
          AXF_CF_PKL_PaymentMode__c = paymentMode,
          AXF_CF_PKL_PaymentMethod__c = 'BOLETO',
          AXF_CF_CHK_IsEstimated__c = true,
          AXF_CF_NUM_CurrentInstallment__c = sequence,
          AXF_CF_NUM_TotalInstallments__c = total,
          AXF_CF_LKP_Account__c = accountId,
          AXF_CF_LKP_InstallmentGroup__c = groupRecord.Id
        )
      );
    }
    return entries;
  }

  private static AXF_OBJ_InstallmentGroup__c groupOf(
    String groupType,
    String financingType
  ) {
    return [
      SELECT
        Id,
        AXF_IG_CUR_InstallmentAmount__c,
        AXF_IG_PCT_MonthlyAdjustmentRate__c,
        AXF_IG_NUM_TotalInstallments__c
      FROM AXF_OBJ_InstallmentGroup__c
      WHERE
        AXF_IG_PKL_GroupType__c = :groupType
        AND AXF_IG_PKL_FinancingType__c = :financingType
      ORDER BY AXF_IG_NUM_TotalInstallments__c DESC
      LIMIT 1
    ];
  }

  private static Map<Integer, AXF_OBJ_CashFlow__c> entriesBySequence(
    Id groupId
  ) {
    Map<Integer, AXF_OBJ_CashFlow__c> result = new Map<Integer, AXF_OBJ_CashFlow__c>();
    for (AXF_OBJ_CashFlow__c entry : [
      SELECT
        Id,
        Name,
        AXF_CF_CUR_Value__c,
        AXF_CF_DAT_DueDate__c,
        AXF_CF_PKL_Status__c,
        AXF_CF_CHK_IsEstimated__c,
        AXF_CF_NUM_CurrentInstallment__c,
        AXF_CF_NUM_TotalInstallments__c
      FROM AXF_OBJ_CashFlow__c
      WHERE AXF_CF_LKP_InstallmentGroup__c = :groupId
    ]) {
      result.put(
        Integer.valueOf(entry.AXF_CF_NUM_CurrentInstallment__c),
        entry
      );
    }
    return result;
  }

  @IsTest
  static void initialWindowsAreCappedByTotal() {
    Assert.areEqual(7, ALT_CLS_PriceFinancing.initialWindow(12));
    Assert.areEqual(3, ALT_CLS_PriceFinancing.initialWindow(3));
    Assert.areEqual(6, ALT_CLS_Consortium.initialWindow(20));
    Assert.areEqual(2, ALT_CLS_Consortium.initialWindow(2));
    Assert.areEqual(6, ALT_CLS_SacFinancing.initialWindow(24));
    Assert.areEqual(4, ALT_CLS_SacFinancing.initialWindow(4));
  }

  @IsTest
  static void priceWindowRollsForwardAndAdjustsLastInstallment() {
    AXF_OBJ_InstallmentGroup__c price = groupOf('FINANCING', 'PRICE');
    AXF_OBJ_InstallmentGroup__c priceEmpty = [
      SELECT Id
      FROM AXF_OBJ_InstallmentGroup__c
      WHERE
        AXF_IG_PKL_FinancingType__c = 'PRICE'
        AND AXF_IG_NUM_TotalInstallments__c = 3
    ];
    Map<Integer, AXF_OBJ_CashFlow__c> afterFirstRoll;
    System.runAs(AXF_CLS_AccountCardTestFactory.getUser(USER_KEY)) {
      Test.startTest();
      ALT_CLS_PriceFinancing.maintain(price.Id, 3);
      afterFirstRoll = entriesBySequence(price.Id);
      ALT_CLS_PriceFinancing.maintain(price.Id, 6);
      ALT_CLS_PriceFinancing.maintain(priceEmpty.Id, 1);
      Test.stopTest();
    }

    Assert.areEqual(
      9,
      afterFirstRoll.size(),
      'Window must extend to settled + 6'
    );
    AXF_OBJ_CashFlow__c ninth = afterFirstRoll.get(9);
    Assert.areEqual('Carro (9/12)', ninth.Name);
    Assert.areEqual(100, ninth.AXF_CF_CUR_Value__c);
    Assert.areEqual(
      Date.today().addMonths(-1).addMonths(8),
      ninth.AXF_CF_DAT_DueDate__c
    );
    Assert.areEqual('PENDENTE', ninth.AXF_CF_PKL_Status__c);

    Map<Integer, AXF_OBJ_CashFlow__c> finalEntries = entriesBySequence(
      price.Id
    );
    Assert.areEqual(
      12,
      finalEntries.size(),
      'Window is capped by the total installments'
    );
    Assert.areEqual(
      150,
      finalEntries.get(12).AXF_CF_CUR_Value__c,
      'Last installment absorbs the residual'
    );
    Assert.areEqual(
      0,
      entriesBySequence(priceEmpty.Id).size(),
      'Groups without entries are left untouched'
    );
  }

  @IsTest
  static void consortiumConfirmedAdjustmentRevaluesFutureEntries() {
    AXF_OBJ_InstallmentGroup__c consortium = [
      SELECT Id
      FROM AXF_OBJ_InstallmentGroup__c
      WHERE AXF_IG_PKL_GroupType__c = 'CONSORTIUM'
    ];
    System.runAs(AXF_CLS_AccountCardTestFactory.getUser(USER_KEY)) {
      Test.startTest();
      ALT_CLS_Consortium.maintain(consortium.Id, 2, 550, true);
      ALT_CLS_Consortium.maintain(consortium.Id, 3, null, false);
      Test.stopTest();
    }

    Assert.areEqual(
      550,
      [
        SELECT AXF_IG_CUR_InstallmentAmount__c
        FROM AXF_OBJ_InstallmentGroup__c
        WHERE Id = :consortium.Id
      ]
      .AXF_IG_CUR_InstallmentAmount__c,
      'Confirmed adjustment updates the group installment value'
    );
    Map<Integer, AXF_OBJ_CashFlow__c> entries = entriesBySequence(
      consortium.Id
    );
    Assert.areEqual(9, entries.size(), 'Window must extend to settled + 6');
    Assert.areEqual(
      500,
      entries.get(2).AXF_CF_CUR_Value__c,
      'Settled entries keep their value'
    );
    Assert.areEqual(
      550,
      entries.get(3).AXF_CF_CUR_Value__c,
      'Future entries take the confirmed value'
    );
    Assert.areEqual(550, entries.get(8).AXF_CF_CUR_Value__c);
    Assert.areEqual(
      550,
      entries.get(9).AXF_CF_CUR_Value__c,
      'New entries use the adjusted group value'
    );
    Assert.areEqual('Consorcio (9/20)', entries.get(9).Name);
    Assert.isTrue(entries.get(9).AXF_CF_CHK_IsEstimated__c);
  }

  @IsTest
  static void sacInsertTriggerEstimatesAndExtendsWindow() {
    AXF_OBJ_InstallmentGroup__c sac = groupOf('FINANCING', 'SAC');
    Map<Integer, AXF_OBJ_CashFlow__c> entries = entriesBySequence(sac.Id);

    Assert.areEqual(
      7,
      entries.size(),
      'Insert trigger must extend the window to anchor + 6'
    );
    Assert.areEqual(1000, entries.get(1).AXF_CF_CUR_Value__c);
    Assert.areEqual(1010, entries.get(2).AXF_CF_CUR_Value__c);
    Assert.areEqual(
      1061.52,
      entries.get(7).AXF_CF_CUR_Value__c,
      'Value compounds the monthly rate'
    );
  }

  @IsTest
  static void sacActualPaymentsDeriveRateAndReanchorEstimates() {
    AXF_OBJ_InstallmentGroup__c sac = groupOf('FINANCING', 'SAC');
    Map<Integer, AXF_OBJ_CashFlow__c> entries = entriesBySequence(sac.Id);
    AXF_OBJ_CashFlow__c first = entries.get(1);
    AXF_OBJ_CashFlow__c second = entries.get(2);
    first.AXF_CF_CHK_IsEstimated__c = false;
    first.AXF_CF_CUR_PaidValue__c = 1000;
    first.AXF_CF_PKL_Status__c = 'PAGA';
    second.AXF_CF_CHK_IsEstimated__c = false;
    second.AXF_CF_CUR_PaidValue__c = 1020;
    second.AXF_CF_PKL_Status__c = 'PAGA';

    System.runAs(AXF_CLS_AccountCardTestFactory.getUser(USER_KEY)) {
      Test.startTest();
      update new List<AXF_OBJ_CashFlow__c>{ first, second };
      Test.stopTest();
    }

    Assert.areEqual(
      2,
      [
        SELECT AXF_IG_PCT_MonthlyAdjustmentRate__c
        FROM AXF_OBJ_InstallmentGroup__c
        WHERE Id = :sac.Id
      ]
      .AXF_IG_PCT_MonthlyAdjustmentRate__c,
      'Rate must be derived from the actual payments'
    );
    Map<Integer, AXF_OBJ_CashFlow__c> updated = entriesBySequence(sac.Id);
    Assert.areEqual(
      8,
      updated.size(),
      'Window must extend to the new anchor + 6'
    );
    Assert.areEqual(
      1040.40,
      updated.get(3).AXF_CF_CUR_Value__c,
      'Estimates re-anchor on the last actual'
    );
    Assert.areEqual(1148.69, updated.get(8).AXF_CF_CUR_Value__c);
  }

  @IsTest
  static void sacRateChangeTriggerReestimatesOpenEntries() {
    AXF_OBJ_InstallmentGroup__c sac = groupOf('FINANCING', 'SAC');
    AXF_OBJ_InstallmentGroup__c price = groupOf('FINANCING', 'PRICE');

    System.runAs(AXF_CLS_AccountCardTestFactory.getUser(USER_KEY)) {
      Test.startTest();
      update new List<AXF_OBJ_InstallmentGroup__c>{
        new AXF_OBJ_InstallmentGroup__c(
          Id = sac.Id,
          AXF_IG_PCT_MonthlyAdjustmentRate__c = 2
        ),
        new AXF_OBJ_InstallmentGroup__c(
          Id = price.Id,
          AXF_IG_CUR_InstallmentAmount__c = 101
        )
      };
      Test.stopTest();
    }

    Map<Integer, AXF_OBJ_CashFlow__c> entries = entriesBySequence(sac.Id);
    Assert.areEqual(1000, entries.get(1).AXF_CF_CUR_Value__c);
    Assert.areEqual(
      1020,
      entries.get(2).AXF_CF_CUR_Value__c,
      'Rate change must re-estimate open entries'
    );
    Assert.areEqual(1126.16, entries.get(7).AXF_CF_CUR_Value__c);
    Assert.areEqual(
      100,
      entriesBySequence(price.Id).get(1).AXF_CF_CUR_Value__c,
      'Non-SAC groups are ignored'
    );
  }

  @IsTest
  static void sacGuardsAndEstimateValidation() {
    String nullBaseError;
    String negativeResultError;
    System.runAs(AXF_CLS_AccountCardTestFactory.getUser(USER_KEY)) {
      Test.startTest();
      ALT_CLS_SacFinancing.afterCashFlowChange(null);
      ALT_CLS_SacFinancing.afterCashFlowChange(new Set<Id>());
      ALT_CLS_SacFinancing.processing = true;
      ALT_CLS_SacFinancing.afterGroupRateChange(
        new List<AXF_OBJ_InstallmentGroup__c>(),
        new Map<Id, AXF_OBJ_InstallmentGroup__c>()
      );
      ALT_CLS_SacFinancing.processing = false;
      try {
        ALT_CLS_SacFinancing.estimate(null, 1, 1);
      } catch (IllegalArgumentException e) {
        nullBaseError = e.getMessage();
      }
      try {
        ALT_CLS_SacFinancing.estimate(100, -100, 1);
      } catch (IllegalArgumentException e) {
        negativeResultError = e.getMessage();
      }
      Test.stopTest();
    }

    Assert.areEqual('SAC base value must be positive.', nullBaseError);
    Assert.areEqual(
      'SAC installment estimates must remain positive.',
      negativeResultError
    );
    Assert.areEqual(110.25, ALT_CLS_SacFinancing.estimate(100, 5, 2));
  }
}
