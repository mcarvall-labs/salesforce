/**
 * @description Tests for the small Pluggy sync services: Balance, Bill, Category, Investment and Loan.
 */
@IsTest
private class AXF_CLS_PluggySyncServicesTest {
  @TestSetup
  static void setup() {
    User u = AXF_CLS_PluggyTestFactory.createTestUser();
    System.runAs(u) {
      AXF_CLS_PluggyTestFactory.createStandardData();
    }
  }

  private static AXF_OBJ_PluggyConnection__c getConnection() {
    return [SELECT Id FROM AXF_OBJ_PluggyConnection__c LIMIT 1];
  }

  // ------------------------------------------------------------ Balance

  @IsTest
  static void fetchBalanceParsesAccountPayload() {
    AXF_CLS_PluggyTestFactory.MockRouter mock = new AXF_CLS_PluggyTestFactory.MockRouter()
      .route('/accounts/', 200, AXF_CLS_PluggyTestFactory.balanceBody(987.65));
    Test.setMock(HttpCalloutMock.class, mock);
    AXF_CLS_PluggyBalanceSync_Service.BalanceResult result;
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      result = AXF_CLS_PluggyBalanceSync_Service.fetchBalance(
        AXF_CLS_PluggyTestFactory.BANK_PLUGGY_ID,
        'key'
      );
      Test.stopTest();
    }
    Assert.areEqual(987.65, result.balance);
    Assert.areEqual('BRL', result.currencyCode);
    Assert.areEqual(
      Datetime.newInstanceGmt(2026, 9, 20, 10, 0, 0),
      result.lastSync
    );
    Assert.isTrue(
      mock.endpoints[0]
        .endsWith('/accounts/' + AXF_CLS_PluggyTestFactory.BANK_PLUGGY_ID)
    );
  }

  @IsTest
  static void fetchBalanceHandlesNullFieldsAndHttpError() {
    AXF_CLS_PluggyTestFactory.MockRouter mock = new AXF_CLS_PluggyTestFactory.MockRouter()
      .route(
        '/accounts/ok',
        200,
        '{"id":"ok","balance":null,"currency":"BRL","updatedAt":null}'
      )
      .route('/accounts/', 404, '{"message":"not found"}');
    Test.setMock(HttpCalloutMock.class, mock);
    AXF_CLS_PluggyBalanceSync_Service.BalanceResult result;
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      result = AXF_CLS_PluggyBalanceSync_Service.fetchBalance('ok', 'key');
      try {
        AXF_CLS_PluggyBalanceSync_Service.fetchBalance('missing', 'key');
        Assert.fail('Expected BalanceSyncException');
      } catch (AXF_CLS_PluggyBalanceSync_Service.BalanceSyncException e) {
        Assert.isTrue(e.getMessage().contains('HTTP 404'), e.getMessage());
      }
      Test.stopTest();
    }
    Assert.isNull(result.balance);
    Assert.isNull(result.lastSync);
  }

  // ------------------------------------------------------------ Bills

  @IsTest
  static void fetchAndUpsertBillsForCreditCard() {
    AXF_CLS_PluggyTestFactory.MockRouter mock = new AXF_CLS_PluggyTestFactory.MockRouter()
      .route('/bills?accountId=', 200, AXF_CLS_PluggyTestFactory.billsBody());
    Test.setMock(HttpCalloutMock.class, mock);
    AXF_OBJ_CreditCard__c card = [SELECT Id FROM AXF_OBJ_CreditCard__c LIMIT 1];
    List<AXF_OBJ_CreditCardInvoice__c> invoices;
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      invoices = AXF_CLS_PluggyBillSync_Service.fetchBillsForCreditCard(
        card.Id,
        AXF_CLS_PluggyTestFactory.CARD_PLUGGY_ID,
        'key'
      );
      AXF_CLS_PluggyBillSync_Service.upsertBills(invoices);
      Test.stopTest();
    }
    Assert.areEqual(2, invoices.size());
    Map<String, AXF_OBJ_CreditCardInvoice__c> byId = new Map<String, AXF_OBJ_CreditCardInvoice__c>();
    for (AXF_OBJ_CreditCardInvoice__c inv : [
      SELECT
        Name,
        AXF_CCI_EXI_PluggyInvoiceId__c,
        AXF_CCI_DAT_DueDate__c,
        AXF_CCI_DAT_ClosingDate__c,
        AXF_CCI_CUR_TotalAmount__c,
        AXF_CCI_TXT_Period__c,
        AXF_CCI_MD_CreditCard__c
      FROM AXF_OBJ_CreditCardInvoice__c
    ]) {
      byId.put(inv.AXF_CCI_EXI_PluggyInvoiceId__c, inv);
    }
    AXF_OBJ_CreditCardInvoice__c first = byId.get('bill-001');
    Assert.areEqual(card.Id, first.AXF_CCI_MD_CreditCard__c);
    Assert.areEqual(
      Date.newInstance(2026, 9, 15),
      first.AXF_CCI_DAT_DueDate__c
    );
    Assert.areEqual(
      Date.newInstance(2026, 9, 8),
      first.AXF_CCI_DAT_ClosingDate__c
    );
    Assert.areEqual(850.40, first.AXF_CCI_CUR_TotalAmount__c);
    Assert.areEqual('09/2026', first.AXF_CCI_TXT_Period__c);
    AXF_OBJ_CreditCardInvoice__c second = byId.get('bill-002');
    Assert.areEqual(
      Date.newInstance(2026, 10, 5),
      second.AXF_CCI_DAT_ClosingDate__c,
      'Closing = due - 10 days'
    );
    Assert.areEqual('10/2026', second.AXF_CCI_TXT_Period__c);
    Assert.isNull(second.AXF_CCI_CUR_TotalAmount__c);
  }

  @IsTest
  static void billsBlankIdErrorAndMissingResults() {
    AXF_CLS_PluggyTestFactory.MockRouter mock = new AXF_CLS_PluggyTestFactory.MockRouter()
      .route('accountId=empty', 200, '{"total":0}')
      .route('/bills', 500, '{}');
    Test.setMock(HttpCalloutMock.class, mock);
    AXF_OBJ_CreditCard__c card = [SELECT Id FROM AXF_OBJ_CreditCard__c LIMIT 1];
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      Assert.isTrue(
        AXF_CLS_PluggyBillSync_Service.fetchBillsForCreditCard(
            card.Id,
            null,
            'key'
          )
          .isEmpty()
      );
      Assert.isTrue(
        AXF_CLS_PluggyBillSync_Service.fetchBillsForCreditCard(
            card.Id,
            'err',
            'key'
          )
          .isEmpty()
      );
      Assert.isTrue(
        AXF_CLS_PluggyBillSync_Service.fetchBillsForCreditCard(
            card.Id,
            'empty',
            'key'
          )
          .isEmpty()
      );
      AXF_CLS_PluggyBillSync_Service.upsertBills(
        new List<AXF_OBJ_CreditCardInvoice__c>()
      );
      Test.stopTest();
    }
    Assert.areEqual(2, mock.endpoints.size());
    Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_CreditCardInvoice__c]);
  }

  // ------------------------------------------------------------ Categories

  @IsTest
  static void syncCategoriesBuildsHierarchyFromArrayPayload() {
    String body = JSON.serialize(
      new List<Object>{
        new Map<String, Object>{
          'id' => '01000000',
          'descriptionTranslated' => 'Renda',
          'parentId' => null
        },
        new Map<String, Object>{
          'id' => '01010000',
          'descriptionTranslated' => 'Salário',
          'parentId' => '01000000'
        },
        new Map<String, Object>{
          'id' => '09999999',
          'descriptionTranslated' => 'Órfã',
          'parentId' => 'missing'
        }
      }
    );
    Test.setMock(
      HttpCalloutMock.class,
      new AXF_CLS_PluggyTestFactory.MockRouter()
        .route('/auth', 200, AXF_CLS_PluggyTestFactory.authBody())
        .route('/categories', 200, body)
    );
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      AXF_CLS_PluggyCategorySync_Service.syncCategories();
      Test.stopTest();
    }
    AXF_OBJ_Category__c root = [
      SELECT Id, Name
      FROM AXF_OBJ_Category__c
      WHERE AXF_CAT_EXI_PluggyCategoryId__c = '01000000'
    ];
    AXF_OBJ_Category__c child = [
      SELECT Name, AXF_CAT_LKP_Parent__c
      FROM AXF_OBJ_Category__c
      WHERE AXF_CAT_EXI_PluggyCategoryId__c = '01010000'
    ];
    AXF_OBJ_Category__c orphan = [
      SELECT AXF_CAT_LKP_Parent__c
      FROM AXF_OBJ_Category__c
      WHERE AXF_CAT_EXI_PluggyCategoryId__c = '09999999'
    ];
    Assert.areEqual('Renda', root.Name);
    Assert.areEqual('Salário', child.Name);
    Assert.areEqual(
      root.Id,
      child.AXF_CAT_LKP_Parent__c,
      'Child linked to its parent'
    );
    Assert.isNull(orphan.AXF_CAT_LKP_Parent__c);
  }

  @IsTest
  static void syncCategoriesSupportsResultsWrapperAndHttpError() {
    String body = JSON.serialize(
      new Map<String, Object>{
        'results' => new List<Object>{
          new Map<String, Object>{
            'id' => '02000000',
            'descriptionTranslated' => 'Moradia'
          }
        }
      }
    );
    AXF_CLS_PluggyTestFactory.MockRouter mock = new AXF_CLS_PluggyTestFactory.MockRouter()
      .route('/auth', 200, AXF_CLS_PluggyTestFactory.authBody())
      .route('/categories', 500, '{}');
    Test.setMock(HttpCalloutMock.class, mock);
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      // HTTP error and empty payload perform no DML, so the successful call can run last.
      AXF_CLS_PluggyCategorySync_Service.syncCategories();
      mock.routes[1].status = 200;
      mock.routes[1].body = '{"total":0}';
      AXF_CLS_PluggyCategorySync_Service.syncCategories();
      mock.routes[1].body = body;
      AXF_CLS_PluggyCategorySync_Service.syncCategories();
      Test.stopTest();
    }
    Assert.areEqual(1, [SELECT COUNT() FROM AXF_OBJ_Category__c]);
    Assert.areEqual('Moradia', [SELECT Name FROM AXF_OBJ_Category__c].Name);
  }

  // ------------------------------------------------------------ Investments

  @IsTest
  static void fetchAndUpsertInvestments() {
    Test.setMock(
      HttpCalloutMock.class,
      new AXF_CLS_PluggyTestFactory.MockRouter()
        .route(
          '/investments?itemId=',
          200,
          AXF_CLS_PluggyTestFactory.investmentsBody()
        )
    );
    AXF_OBJ_PluggyConnection__c conn = getConnection();
    List<AXF_OBJ_Investment__c> investments;
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      investments = AXF_CLS_PluggyInvSync_Service.fetchInvestmentsForConnection(
        conn.Id,
        AXF_CLS_PluggyTestFactory.ITEM_ID,
        'key'
      );
      AXF_CLS_PluggyInvSync_Service.upsertInvestments(investments);
      Test.stopTest();
    }
    Assert.areEqual(2, investments.size());
    AXF_OBJ_Investment__c cdb = [
      SELECT
        Name,
        AXF_INV_PKL_Type__c,
        AXF_INV_PKL_Currency__c,
        AXF_INV_CUR_Balance__c,
        AXF_INV_LKP_PluggyConnection__c
      FROM AXF_OBJ_Investment__c
      WHERE AXF_INV_EXI_PluggyInvestmentId__c = 'inv-001'
    ];
    Assert.areEqual('CDB Banco do Brasil', cdb.Name);
    Assert.areEqual('FIXED_INCOME', cdb.AXF_INV_PKL_Type__c);
    Assert.areEqual(2500.75, cdb.AXF_INV_CUR_Balance__c);
    Assert.areEqual(conn.Id, cdb.AXF_INV_LKP_PluggyConnection__c);
    Assert.areEqual(
      'inv-002',
      [
        SELECT Name
        FROM AXF_OBJ_Investment__c
        WHERE AXF_INV_EXI_PluggyInvestmentId__c = 'inv-002'
      ]
      .Name,
      'Name falls back to id'
    );
  }

  @IsTest
  static void investmentsBlankErrorAndEmptyPayload() {
    AXF_CLS_PluggyTestFactory.MockRouter mock = new AXF_CLS_PluggyTestFactory.MockRouter()
      .route('itemId=empty', 200, '{}')
      .route('/investments', 503, '{}');
    Test.setMock(HttpCalloutMock.class, mock);
    AXF_OBJ_PluggyConnection__c conn = getConnection();
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      Assert.isTrue(
        AXF_CLS_PluggyInvSync_Service.fetchInvestmentsForConnection(
            conn.Id,
            ' ',
            'key'
          )
          .isEmpty()
      );
      Assert.isTrue(
        AXF_CLS_PluggyInvSync_Service.fetchInvestmentsForConnection(
            conn.Id,
            'err',
            'key'
          )
          .isEmpty()
      );
      Assert.isTrue(
        AXF_CLS_PluggyInvSync_Service.fetchInvestmentsForConnection(
            conn.Id,
            'empty',
            'key'
          )
          .isEmpty()
      );
      AXF_CLS_PluggyInvSync_Service.upsertInvestments(
        new List<AXF_OBJ_Investment__c>()
      );
      Test.stopTest();
    }
    Assert.areEqual(2, mock.endpoints.size());
  }

  // ------------------------------------------------------------ Loans

  @IsTest
  static void fetchAndUpsertLoans() {
    Test.setMock(
      HttpCalloutMock.class,
      new AXF_CLS_PluggyTestFactory.MockRouter()
        .route('/loans?itemId=', 200, AXF_CLS_PluggyTestFactory.loansBody())
    );
    AXF_OBJ_PluggyConnection__c conn = getConnection();
    List<AXF_OBJ_Loan__c> loans;
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      loans = AXF_CLS_PluggyLoanSync_Service.fetchLoansForConnection(
        conn.Id,
        AXF_CLS_PluggyTestFactory.ITEM_ID,
        'key'
      );
      AXF_CLS_PluggyLoanSync_Service.upsertLoans(loans);
      Test.stopTest();
    }
    Assert.areEqual(1, loans.size());
    AXF_OBJ_Loan__c loan = [
      SELECT
        Name,
        AXF_LOA_PKL_Type__c,
        AXF_LOA_CUR_ContractedAmount__c,
        AXF_LOA_CUR_OutstandingBalance__c,
        AXF_LOA_NUM_InterestRate__c,
        AXF_LOA_NUM_TotalInstallments__c,
        AXF_LOA_NUM_PaidInstallments__c
      FROM AXF_OBJ_Loan__c
    ];
    Assert.areEqual('loan-001', loan.Name);
    Assert.areEqual('LOAN', loan.AXF_LOA_PKL_Type__c);
    Assert.areEqual(10000.00, loan.AXF_LOA_CUR_ContractedAmount__c);
    Assert.areEqual(6500.50, loan.AXF_LOA_CUR_OutstandingBalance__c);
    Assert.areEqual(48, loan.AXF_LOA_NUM_TotalInstallments__c);
    Assert.areEqual(12, loan.AXF_LOA_NUM_PaidInstallments__c);
  }

  @IsTest
  static void loansBlankErrorAndEmptyPayload() {
    AXF_CLS_PluggyTestFactory.MockRouter mock = new AXF_CLS_PluggyTestFactory.MockRouter()
      .route('itemId=empty', 200, '{}')
      .route('/loans', 500, '{}');
    Test.setMock(HttpCalloutMock.class, mock);
    AXF_OBJ_PluggyConnection__c conn = getConnection();
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      Assert.isTrue(
        AXF_CLS_PluggyLoanSync_Service.fetchLoansForConnection(
            conn.Id,
            null,
            'key'
          )
          .isEmpty()
      );
      Assert.isTrue(
        AXF_CLS_PluggyLoanSync_Service.fetchLoansForConnection(
            conn.Id,
            'err',
            'key'
          )
          .isEmpty()
      );
      Assert.isTrue(
        AXF_CLS_PluggyLoanSync_Service.fetchLoansForConnection(
            conn.Id,
            'empty',
            'key'
          )
          .isEmpty()
      );
      AXF_CLS_PluggyLoanSync_Service.upsertLoans(new List<AXF_OBJ_Loan__c>());
      Test.stopTest();
    }
    Assert.areEqual(2, mock.endpoints.size());
  }
}
