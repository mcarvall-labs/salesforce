@IsTest
private class ALT_CLS_ManualSyncTest {
  private static final String BANK = AXF_CLS_PluggyTestFactory.BANK_PLUGGY_ID;
  private static final String CARD = AXF_CLS_PluggyTestFactory.CARD_PLUGGY_ID;

  @TestSetup
  static void setup() {
    User u = AXF_CLS_PluggyTestFactory.createTestUser();
    System.runAs(u) {
      AXF_CLS_PluggyTestFactory.createStandardData();
    }
  }

  private static ALT_CLS_ManualSync service() {
    return new ALT_CLS_ManualSync();
  }

  private static AXF_OBJ_BankAccount__c bankAccount() {
    return [
      SELECT Id
      FROM AXF_OBJ_BankAccount__c
      WHERE AXF_BA_EXI_PluggyAccountId__c = :BANK
    ];
  }

  private static AXF_OBJ_CreditCard__c creditCard() {
    return [
      SELECT Id
      FROM AXF_OBJ_CreditCard__c
      WHERE AXF_CC_EXI_PluggyCreditCardId__c = :CARD
    ];
  }

  // ------------------------------------------------------------ performSync

  @IsTest
  static void performSyncUpsertsAccountsCardsInvestmentsAndLoans() {
    Test.setMock(
      HttpCalloutMock.class,
      AXF_CLS_PluggyTestFactory.itemSyncMock()
    );
    ALT_CLS_ManualSync.SyncExecutionResult result;
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      result = service().performSync();
      Test.stopTest();
    }
    Assert.isTrue(result.isSuccess, result.message);
    Assert.areEqual(1, result.connectionsProcessed);
    Assert.areEqual(1, result.bankAccountsSynced);
    Assert.areEqual(1, result.creditCardsSynced);
    Assert.isTrue(result.errors.isEmpty(), String.valueOf(result.errors));
    Assert.isTrue(
      result.message.startsWith('Sincronização concluída com sucesso!'),
      result.message
    );
    Assert.areEqual(2, [SELECT COUNT() FROM AXF_OBJ_Investment__c]);
    Assert.areEqual(1, [SELECT COUNT() FROM AXF_OBJ_Loan__c]);
    Assert.areEqual(
      'UPDATED',
      [SELECT AXF_CON_TXT_SyncStatus__c FROM AXF_OBJ_PluggyConnection__c]
      .AXF_CON_TXT_SyncStatus__c
    );
    Assert.areEqual(
      1500.50,
      [
        SELECT AXF_BA_CUR_Balance__c
        FROM AXF_OBJ_BankAccount__c
        WHERE AXF_BA_EXI_PluggyAccountId__c = :BANK
      ]
      .AXF_BA_CUR_Balance__c
    );
  }

  @IsTest
  static void performSyncReportsAuthenticationFailure() {
    Test.setMock(
      HttpCalloutMock.class,
      new AXF_CLS_PluggyTestFactory.MockRouter()
        .route('/auth', 401, '{"message":"client keys are invalid"}')
    );
    ALT_CLS_ManualSync.SyncExecutionResult result;
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      result = service().performSync();
      Test.stopTest();
    }
    Assert.isFalse(result.isSuccess);
    Assert.isTrue(
      result.message.contains('client keys are invalid'),
      result.message
    );
  }

  @IsTest
  static void performSyncWithoutConnectionsFails() {
    Test.setMock(
      HttpCalloutMock.class,
      AXF_CLS_PluggyTestFactory.itemSyncMock()
    );
    ALT_CLS_ManualSync.SyncExecutionResult result;
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      delete [SELECT Id FROM AXF_OBJ_PluggyConnection__c];
      Test.startTest();
      result = service().performSync();
      Test.stopTest();
    }
    Assert.isFalse(result.isSuccess);
    Assert.isTrue(
      result.message.startsWith('Nenhuma conexão bancária'),
      result.message
    );
  }

  @IsTest
  static void performSyncCollectsConnectionAndSaveErrors() {
    AXF_OBJ_BankInstitution__c inst = [
      SELECT Id
      FROM AXF_OBJ_BankInstitution__c
      LIMIT 1
    ];
    Map<String, Object> badAccount = AXF_CLS_PluggyTestFactory.bankAccountJson(
      'acc-too-long',
      null,
      null
    );
    badAccount.put('number', '1234567890123456789012345678901234567890');
    Map<String, Object> badCard = AXF_CLS_PluggyTestFactory.creditCardJson(
      'card-too-long',
      null,
      null
    );
    ((Map<String, Object>) badCard.get('creditData'))
      .put('brand', 'B'.repeat(60));
    AXF_CLS_PluggyTestFactory.MockRouter mock = new AXF_CLS_PluggyTestFactory.MockRouter()
      .route('/auth', 200, AXF_CLS_PluggyTestFactory.authBody())
      .route('/items/item-http', 500, '{"message":"boom"}')
      .onThrow('/items/item-down')
      .route(
        '/items/',
        200,
        AXF_CLS_PluggyTestFactory.itemBody(
          'LOGIN_ERROR',
          new Map<String, Object>{ 'code' => 'INVALID_CREDENTIALS' }
        )
      )
      .route(
        '/accounts?itemId=' + AXF_CLS_PluggyTestFactory.ITEM_ID,
        200,
        AXF_CLS_PluggyTestFactory.accountsBody(
          new List<Object>{ badAccount, badCard }
        )
      )
      .onThrow('/accounts?itemId=')
      .onThrow('/investments')
      .onThrow('/loans');
    ALT_CLS_ManualSync.SyncExecutionResult result;
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      insert new List<AXF_OBJ_PluggyConnection__c>{
        new AXF_OBJ_PluggyConnection__c(
          Name = 'Conn HTTP',
          AXF_CON_LKP_BankInstitution__c = inst.Id,
          AXF_CON_EXI_PluggyItemId__c = 'item-http'
        ),
        new AXF_OBJ_PluggyConnection__c(
          Name = 'Conn Down',
          AXF_CON_LKP_BankInstitution__c = inst.Id,
          AXF_CON_EXI_PluggyItemId__c = 'item-down'
        ),
        new AXF_OBJ_PluggyConnection__c(
          Name = 'Conn Acc',
          AXF_CON_LKP_BankInstitution__c = inst.Id,
          AXF_CON_EXI_PluggyItemId__c = 'item-acc'
        )
      };
      Test.setMock(HttpCalloutMock.class, mock);
      Test.startTest();
      result = service().performSync();
      Test.stopTest();
    }
    Assert.isFalse(result.isSuccess, 'No account could be saved');
    Assert.areEqual(4, result.connectionsProcessed);
    Assert.areEqual(0, result.bankAccountsSynced);
    Assert.areEqual(0, result.creditCardsSynced);
    String allErrors = String.join(result.errors, '\n');
    Assert.isTrue(allErrors.contains('Falha HTTP 500'), allErrors);
    Assert.isTrue(
      allErrors.contains('Erro ao conectar (Conn Down)'),
      allErrors
    );
    Assert.isTrue(
      allErrors.contains('Erro ao buscar contas para Conn Acc'),
      allErrors
    );
    Assert.isTrue(allErrors.contains('INVALID_CREDENTIALS'), allErrors);
    Assert.isTrue(
      allErrors.contains('Erro ao salvar Conta Bancária'),
      allErrors
    );
    Assert.isTrue(
      allErrors.contains('Erro ao salvar Cartão de Crédito'),
      allErrors
    );
    Assert.isTrue(
      result.message.startsWith('A consulta de conexões foi executada'),
      result.message
    );
    AXF_OBJ_PluggyConnection__c down = [
      SELECT AXF_CON_TXT_SyncErrorMessage__c
      FROM AXF_OBJ_PluggyConnection__c
      WHERE Name = 'Conn Down'
    ];
    Assert.isTrue(
      down.AXF_CON_TXT_SyncErrorMessage__c.startsWith(
        'Erro de conexão (Conn Down)'
      )
    );
  }

  @IsTest
  static void performSyncReportsUnexpectedPersistenceFailure() {
    AXF_OBJ_BankInstitution__c inst = [
      SELECT Id
      FROM AXF_OBJ_BankInstitution__c
      LIMIT 1
    ];
    // Error message built from a long HTTP body exceeds the 255-char sync error field,
    // so the final connection update fails and hits the outer catch.
    AXF_CLS_PluggyTestFactory.MockRouter mock = new AXF_CLS_PluggyTestFactory.MockRouter()
      .route('/auth', 200, AXF_CLS_PluggyTestFactory.authBody())
      .route('/items/item-nodate', 200, '{"status":"UPDATED"}')
      .route('/items/', 502, 'x'.repeat(400));
    ALT_CLS_ManualSync.SyncExecutionResult result;
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      insert new AXF_OBJ_PluggyConnection__c(
        Name = 'Conn No Date',
        AXF_CON_LKP_BankInstitution__c = inst.Id,
        AXF_CON_EXI_PluggyItemId__c = 'item-nodate'
      );
      Test.setMock(HttpCalloutMock.class, mock);
      Test.startTest();
      result = service().performSync();
      Test.stopTest();
    }
    Assert.isFalse(result.isSuccess);
    Assert.isTrue(
      result.message.startsWith('Erro inesperado durante a sincronização'),
      result.message
    );
    Assert.isNull(
      [
        SELECT AXF_CON_TXT_SyncStatus__c
        FROM AXF_OBJ_PluggyConnection__c
        WHERE AXF_CON_EXI_PluggyItemId__c = 'item-nodate'
      ]
      .AXF_CON_TXT_SyncStatus__c,
      'Failed update leaves connections untouched'
    );
  }

  @IsTest
  static void triggerItemSyncReturnsConfirmation() {
    Assert.areEqual(
      'Sincronização iniciada com sucesso!',
      service().triggerItemSync()
    );
  }

  // ------------------------------------------------------------ syncRecord: Bank Account

  @IsTest
  static void syncBankAccountUpsertsTransactionsForPeriod() {
    AXF_CLS_PluggyTestFactory.MockRouter mock = new AXF_CLS_PluggyTestFactory.MockRouter()
      .route('/auth', 200, AXF_CLS_PluggyTestFactory.authBody())
      .route(
        '/v2/transactions',
        200,
        AXF_CLS_PluggyTestFactory.txBody(
          new List<Object>{
            AXF_CLS_PluggyTestFactory.txJson('tx-1', BANK, -10.0, null)
          },
          null
        )
      );
    Test.setMock(HttpCalloutMock.class, mock);
    Id baId = bankAccount().Id;
    ALT_CLS_ManualSync.SyncExecutionResult result;
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      result = service()
        .syncRecord(
          baId,
          'AXF_OBJ_BankAccount__c',
          Date.newInstance(2026, 8, 1),
          Date.newInstance(2026, 8, 31)
        );
      Test.stopTest();
    }
    Assert.isTrue(result.isSuccess, result.message);
    Assert.areEqual(1, result.transactionsSynced);
    Assert.isTrue(
      mock.endpoints[1].contains('dateFrom=2026-08-01&dateTo=2026-08-31'),
      mock.endpoints[1]
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AXF_OBJ_BankAccountTransaction__c
        WHERE AXF_BAT_LKP_BankAccount__c = :baId
      ]
    );
  }

  @IsTest
  static void syncBankAccountReportsPartialSaveErrorsWithDefaultWindow() {
    Map<String, Object> badTx = AXF_CLS_PluggyTestFactory.txJson(
      'tx-bad',
      BANK,
      -1.0,
      null
    );
    badTx.put('description', 'x'.repeat(300));
    AXF_CLS_PluggyTestFactory.MockRouter mock = new AXF_CLS_PluggyTestFactory.MockRouter()
      .route('/auth', 200, AXF_CLS_PluggyTestFactory.authBody())
      .route(
        '/v2/transactions',
        200,
        AXF_CLS_PluggyTestFactory.txBody(
          new List<Object>{
            AXF_CLS_PluggyTestFactory.txJson('tx-ok', BANK, -10.0, null),
            badTx
          },
          null
        )
      );
    Test.setMock(HttpCalloutMock.class, mock);
    Id baId = bankAccount().Id;
    ALT_CLS_ManualSync.SyncExecutionResult result;
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      result = service().syncRecord(baId, 'AXF_OBJ_BankAccount__c', null, null);
      Test.stopTest();
    }
    Date firstOfMonth = Date.today().toStartOfMonth();
    Assert.isTrue(
      result.isSuccess,
      'Partial success when at least one transaction saved'
    );
    Assert.areEqual(1, result.transactionsSynced);
    Assert.areEqual(1, result.errors.size());
    Assert.isTrue(result.message.contains('com 1 erro(s)'), result.message);
    Assert.isTrue(
      mock.endpoints[1]
        .contains('dateFrom=' + String.valueOf(firstOfMonth.addMonths(-1))),
      'Default window starts on the first day of the previous month: ' +
      mock.endpoints[1]
    );
  }

  @IsTest
  static void syncBankAccountWithoutConnectionOrAuthFails() {
    Test.setMock(
      HttpCalloutMock.class,
      new AXF_CLS_PluggyTestFactory.MockRouter().route('/auth', 500, 'down')
    );
    Id baId = bankAccount().Id;
    ALT_CLS_ManualSync.SyncExecutionResult noConn;
    ALT_CLS_ManualSync.SyncExecutionResult authFail;
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      AXF_OBJ_BankAccount__c orphan = AXF_CLS_PluggyTestFactory.createBankAccount(
        null,
        null,
        'acc-orphan'
      );
      Test.startTest();
      noConn = service()
        .syncRecord(orphan.Id, 'AXF_OBJ_BankAccount__c', null, null);
      authFail = service()
        .syncRecord(baId, 'AXF_OBJ_BankAccount__c', null, null);
      Test.stopTest();
    }
    Assert.isFalse(noConn.isSuccess);
    Assert.isTrue(
      noConn.message.contains('não possui uma Conexão Pluggy válida'),
      noConn.message
    );
    Assert.isFalse(authFail.isSuccess);
    Assert.isTrue(
      authFail.message.startsWith('Erro durante a sincronização'),
      authFail.message
    );
  }

  // ------------------------------------------------------------ syncRecord: Credit Card / Invoice

  @IsTest
  static void syncCreditCardUpsertsInvoicesAndTransactions() {
    AXF_CLS_PluggyTestFactory.MockRouter mock = new AXF_CLS_PluggyTestFactory.MockRouter()
      .route('/auth', 200, AXF_CLS_PluggyTestFactory.authBody())
      .route('/bills?accountId=', 200, AXF_CLS_PluggyTestFactory.billsBody())
      .route(
        '/v2/transactions',
        200,
        AXF_CLS_PluggyTestFactory.txBody(
          new List<Object>{
            AXF_CLS_PluggyTestFactory.txJson('tx-card', CARD, -30.0, 'bill-001')
          },
          null
        )
      );
    Test.setMock(HttpCalloutMock.class, mock);
    Id cardId = creditCard().Id;
    ALT_CLS_ManualSync.SyncExecutionResult result;
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      result = service()
        .syncRecord(cardId, 'AXF_OBJ_CreditCard__c', null, null);
      Test.stopTest();
    }
    Assert.isTrue(result.isSuccess, result.message);
    Assert.areEqual(2, result.invoicesSynced);
    Assert.areEqual(1, result.transactionsSynced);
    Assert.isTrue(
      result.message.startsWith('Sincronização concluída com sucesso!'),
      result.message
    );
    AXF_OBJ_CreditCardTransaction__c tx = [
      SELECT AXF_CCT_LKP_CreditCardInvoice__r.AXF_CCI_EXI_PluggyInvoiceId__c
      FROM AXF_OBJ_CreditCardTransaction__c
    ];
    Assert.areEqual(
      'bill-001',
      tx.AXF_CCT_LKP_CreditCardInvoice__r.AXF_CCI_EXI_PluggyInvoiceId__c,
      'Transaction linked to the synced bill'
    );
  }

  @IsTest
  static void syncFromInvoiceUsesParentCardAndReportsErrors() {
    Id cardId = creditCard().Id;
    AXF_OBJ_CreditCardInvoice__c invoice;
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      invoice = AXF_CLS_PluggyTestFactory.createInvoice(
        cardId,
        'bill-001',
        null
      );
    }
    AXF_CLS_PluggyTestFactory.MockRouter mock = new AXF_CLS_PluggyTestFactory.MockRouter()
      .route('/auth', 200, AXF_CLS_PluggyTestFactory.authBody())
      .route(
        '/bills?accountId=',
        200,
        // Pluggy id longer than the 255-char external id field: invoice save error
        JSON.serialize(
          new Map<String, Object>{
            'results' => new List<Object>{
              new Map<String, Object>{
                'id' => 'b'.repeat(300),
                'dueDate' => '2026-09-15T00:00:00.000Z'
              }
            }
          }
        )
      )
      .route(
        '/v2/transactions',
        200,
        AXF_CLS_PluggyTestFactory.txBody(
          new List<Object>{
            AXF_CLS_PluggyTestFactory.txJson(
              'tx-unknown-bill',
              CARD,
              -30.0,
              'bill-never-synced'
            )
          },
          null
        )
      );
    Test.setMock(HttpCalloutMock.class, mock);
    ALT_CLS_ManualSync.SyncExecutionResult result;
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      result = service()
        .syncRecord(
          invoice.Id,
          'AXF_OBJ_CreditCardInvoice__c',
          Date.newInstance(2026, 9, 1),
          Date.newInstance(2026, 9, 30)
        );
      Test.stopTest();
    }
    Assert.isFalse(result.isSuccess, 'Nothing saved');
    Assert.areEqual(0, result.transactionsSynced);
    Assert.areEqual(0, result.invoicesSynced);
    Assert.areEqual(2, result.errors.size());
    Assert.isTrue(
      result.errors[0].startsWith('Erro ao salvar fatura') &&
      result.errors[1].startsWith('Erro ao salvar transação'),
      String.valueOf(result.errors)
    );
    Assert.isTrue(result.message.contains('com 2 erro(s)'), result.message);
    Assert.isTrue(
      mock.endpoints[1].contains('accountId=' + CARD),
      'Bills fetched for the parent card'
    );
  }

  @IsTest
  static void syncCreditCardWithoutConnectionOrAuthFails() {
    Test.setMock(
      HttpCalloutMock.class,
      new AXF_CLS_PluggyTestFactory.MockRouter().route('/auth', 500, 'down')
    );
    Id cardId = creditCard().Id;
    ALT_CLS_ManualSync.SyncExecutionResult noConn;
    ALT_CLS_ManualSync.SyncExecutionResult authFail;
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      AXF_OBJ_CreditCard__c orphan = AXF_CLS_PluggyTestFactory.createCreditCard(
        null,
        'card-orphan',
        '0000'
      );
      Test.startTest();
      noConn = service()
        .syncRecord(orphan.Id, 'AXF_OBJ_CreditCard__c', null, null);
      authFail = service()
        .syncRecord(cardId, 'AXF_OBJ_CreditCard__c', null, null);
      Test.stopTest();
    }
    Assert.isFalse(noConn.isSuccess);
    Assert.isTrue(
      noConn.message.contains(
        'Cartão de Crédito não possui uma Conexão Pluggy válida'
      ),
      noConn.message
    );
    Assert.isFalse(authFail.isSuccess);
    Assert.isTrue(
      authFail.message.startsWith(
        'Erro durante a sincronização de faturas e transações'
      ),
      authFail.message
    );
  }

  @IsTest
  static void syncRecordForOtherObjectFallsBackToGeneralSync() {
    Id connId = [SELECT Id FROM AXF_OBJ_PluggyConnection__c LIMIT 1].Id;
    ALT_CLS_ManualSync.SyncExecutionResult result;
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      result = service()
        .syncRecord(connId, 'AXF_OBJ_PluggyConnection__c', null, null);
      Test.stopTest();
    }
    Assert.isTrue(result.isSuccess);
    Assert.areEqual(
      'Sincronização geral iniciada com sucesso!',
      result.message
    );
  }
}
