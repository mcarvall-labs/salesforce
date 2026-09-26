@IsTest
private class AXF_CLS_PluggyAccountSync_ServiceTest {
  @TestSetup
  static void setup() {
    User u = AXF_CLS_PluggyTestFactory.createTestUser();
    System.runAs(u) {
      Account holder = AXF_CLS_PluggyTestFactory.createHolder(
        'Joao Silva',
        AXF_CLS_PluggyTestFactory.CPF
      );
      AXF_OBJ_BankInstitution__c bb = AXF_CLS_PluggyTestFactory.createInstitution(
        'Banco do Brasil (001)',
        '001'
      );
      AXF_CLS_PluggyTestFactory.createInstitution('Itaú Unibanco', '341');
      AXF_OBJ_PluggyConnection__c conn = AXF_CLS_PluggyTestFactory.createConnection(
        bb.Id,
        AXF_CLS_PluggyTestFactory.ITEM_ID
      );
      // Existing bank account linking the connection to the holder (credit card account fallback)
      AXF_CLS_PluggyTestFactory.createBankAccount(
        conn.Id,
        holder.Id,
        'acc-existing'
      );
    }
  }

  private static AXF_OBJ_PluggyConnection__c getConnection() {
    return [
      SELECT Id, AXF_CON_LKP_BankInstitution__c
      FROM AXF_OBJ_PluggyConnection__c
      LIMIT 1
    ];
  }

  @IsTest
  static void fetchAndUpsertMapsBankAccountsAndCreditCards() {
    List<Object> results = new List<Object>{
      // CPF exact match, agencyNumber present, bank number 001
      AXF_CLS_PluggyTestFactory.bankAccountJson(
        'acc-1',
        AXF_CLS_PluggyTestFactory.CPF,
        new Map<String, Object>{
          'transferNumber' => '001/1234/12345-6',
          'agencyNumber' => '1234'
        }
      ),
      // CPF digits-only fallback, agency parsed from 3-part transfer number, bank 341
      AXF_CLS_PluggyTestFactory.bankAccountJson(
        'acc-2',
        '123 456 789 09',
        new Map<String, Object>{ 'transferNumber' => ' 341 / 5555 / 99999-1' }
      ),
      // 2-part transfer number with zero-padded bank number resolved via Integer normalization
      AXF_CLS_PluggyTestFactory.bankAccountJson(
        'acc-3',
        null,
        new Map<String, Object>{ 'transferNumber' => '0001/7777' }
      ),
      // Unknown bank number: institution falls back to the connection's institution
      AXF_CLS_PluggyTestFactory.bankAccountJson(
        'acc-4',
        null,
        new Map<String, Object>{ 'transferNumber' => '999' }
      ),
      // Credit card without taxNumber: holder from connection fallback, bank by '341'
      AXF_CLS_PluggyTestFactory.creditCardJson('card-1', null, '341'),
      // Credit card with CPF digits-only and zero-padded bank
      AXF_CLS_PluggyTestFactory.creditCardJson(
        'card-2',
        '123456789-09',
        '0001'
      ),
      // Ignored account type
      new Map<String, Object>{ 'id' => 'inv-x', 'type' => 'INVESTMENT' }
    };
    Test.setMock(
      HttpCalloutMock.class,
      new AXF_CLS_PluggyTestFactory.MockRouter()
        .route(
          '/accounts?itemId=',
          200,
          AXF_CLS_PluggyTestFactory.accountsBody(results)
        )
    );
    AXF_OBJ_PluggyConnection__c conn = getConnection();

    AXF_CLS_PluggyAccountSync_Service.AccountSyncResult result;
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      result = AXF_CLS_PluggyAccountSync_Service.fetchAccountsForConnection(
        conn.Id,
        AXF_CLS_PluggyTestFactory.ITEM_ID,
        'key'
      );
      AXF_CLS_PluggyAccountSync_Service.upsertAccounts(result);
      Test.stopTest();
    }

    Assert.areEqual(
      4,
      result.bankAccounts.size(),
      'Four BANK accounts expected'
    );
    Assert.areEqual(
      2,
      result.creditCards.size(),
      'Two CREDIT_CARD accounts expected'
    );

    Account holder = [SELECT Id FROM Account WHERE Name = 'Joao Silva'];
    AXF_OBJ_BankInstitution__c bb = [
      SELECT Id
      FROM AXF_OBJ_BankInstitution__c
      WHERE AXF_BI_EXI_Bank_Number__c = '001'
    ];
    AXF_OBJ_BankInstitution__c itau = [
      SELECT Id
      FROM AXF_OBJ_BankInstitution__c
      WHERE AXF_BI_EXI_Bank_Number__c = '341'
    ];

    Map<String, AXF_OBJ_BankAccount__c> accounts = new Map<String, AXF_OBJ_BankAccount__c>();
    for (AXF_OBJ_BankAccount__c ba : [
      SELECT
        Name,
        AXF_BA_EXI_PluggyAccountId__c,
        AXF_BA_LKP_Account__c,
        AXF_BA_LKP_BankInstitution__c,
        AXF_BA_TXT_AgencyNumber__c,
        AXF_BA_CUR_Balance__c,
        AXF_BA_PKL_Type__c,
        AXF_BA_DAT_LastSync__c
      FROM AXF_OBJ_BankAccount__c
    ]) {
      accounts.put(ba.AXF_BA_EXI_PluggyAccountId__c, ba);
    }
    AXF_OBJ_BankAccount__c acc1 = accounts.get('acc-1');
    Assert.areEqual(
      holder.Id,
      acc1.AXF_BA_LKP_Account__c,
      'Holder matched by CPF'
    );
    Assert.areEqual(
      bb.Id,
      acc1.AXF_BA_LKP_BankInstitution__c,
      'Institution matched by bank number'
    );
    Assert.areEqual('1234', acc1.AXF_BA_TXT_AgencyNumber__c);
    Assert.areEqual(1500.50, acc1.AXF_BA_CUR_Balance__c);
    Assert.areEqual('CHECKING_ACCOUNT', acc1.AXF_BA_PKL_Type__c);
    Assert.isNotNull(acc1.AXF_BA_DAT_LastSync__c);
    Assert.areEqual(
      'JOAO SILVA - BANCO DO BRASIL',
      acc1.Name,
      'Standardized name without bank code'
    );

    AXF_OBJ_BankAccount__c acc2 = accounts.get('acc-2');
    Assert.areEqual(
      holder.Id,
      acc2.AXF_BA_LKP_Account__c,
      'Holder matched by CPF digits'
    );
    Assert.areEqual(itau.Id, acc2.AXF_BA_LKP_BankInstitution__c);
    Assert.areEqual('5555', acc2.AXF_BA_TXT_AgencyNumber__c);
    Assert.areEqual(
      'JOAO SILVA - ITAU UNIBANCO',
      acc2.Name,
      'Diacritics removed from institution name'
    );

    AXF_OBJ_BankAccount__c acc3 = accounts.get('acc-3');
    Assert.areEqual(
      bb.Id,
      acc3.AXF_BA_LKP_BankInstitution__c,
      '0001 normalized to bank 1'
    );
    Assert.areEqual('0001', acc3.AXF_BA_TXT_AgencyNumber__c);
    Assert.isNull(acc3.AXF_BA_LKP_Account__c);
    Assert.areEqual('BANCO DO BRASIL', acc3.Name);

    Assert.areEqual(
      bb.Id,
      accounts.get('acc-4').AXF_BA_LKP_BankInstitution__c,
      'Connection institution fallback'
    );

    Map<String, AXF_OBJ_CreditCard__c> cards = new Map<String, AXF_OBJ_CreditCard__c>();
    for (AXF_OBJ_CreditCard__c c : [
      SELECT
        Name,
        AXF_CC_EXI_PluggyCreditCardId__c,
        AXF_CC_LKP_Account__c,
        AXF_CC_LKP_BankInstitution__c,
        AXF_CC_TXT_LastFourDigits__c,
        AXF_CC_CUR_CreditLimit__c,
        AXF_CC_CUR_AvailableLimit__c,
        AXF_CC_TXT_Brand__c,
        AXF_CC_NUM_ClosingDay__c,
        AXF_CC_NUM_DueDay__c
      FROM AXF_OBJ_CreditCard__c
    ]) {
      cards.put(c.AXF_CC_EXI_PluggyCreditCardId__c, c);
    }
    AXF_OBJ_CreditCard__c card1 = cards.get('card-1');
    Assert.areEqual(
      holder.Id,
      card1.AXF_CC_LKP_Account__c,
      'Holder from connection fallback'
    );
    Assert.areEqual(itau.Id, card1.AXF_CC_LKP_BankInstitution__c);
    Assert.areEqual('1234', card1.AXF_CC_TXT_LastFourDigits__c);
    Assert.areEqual(10000.00, card1.AXF_CC_CUR_CreditLimit__c);
    Assert.areEqual(4000.25, card1.AXF_CC_CUR_AvailableLimit__c);
    Assert.areEqual('VISA', card1.AXF_CC_TXT_Brand__c);
    Assert.areEqual(5, card1.AXF_CC_NUM_ClosingDay__c);
    Assert.areEqual(15, card1.AXF_CC_NUM_DueDay__c);
    Assert.areEqual('JOAO SILVA - ITAU UNIBANCO', card1.Name);

    AXF_OBJ_CreditCard__c card2 = cards.get('card-2');
    Assert.areEqual(
      holder.Id,
      card2.AXF_CC_LKP_Account__c,
      'Holder matched by CPF digits'
    );
    Assert.areEqual(
      bb.Id,
      card2.AXF_CC_LKP_BankInstitution__c,
      '0001 normalized to bank 1'
    );
  }

  @IsTest
  static void upsertCreditCardsFillsMissingLookupsFromConnection() {
    AXF_OBJ_PluggyConnection__c conn = getConnection();
    AXF_CLS_PluggyAccountSync_Service.AccountSyncResult result = new AXF_CLS_PluggyAccountSync_Service.AccountSyncResult();
    result.creditCards.add(
      new AXF_OBJ_CreditCard__c(
        Name = 'raw card',
        AXF_CC_EXI_PluggyCreditCardId__c = 'card-manual',
        AXF_CC_LKP_PluggyConnection__c = conn.Id
      )
    );
    result.bankAccounts.add(
      new AXF_OBJ_BankAccount__c(
        Name = 'lower name',
        AXF_BA_EXI_PluggyAccountId__c = 'acc-manual'
      )
    );

    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      AXF_CLS_PluggyAccountSync_Service.upsertAccounts(result);
      Test.stopTest();
    }

    AXF_OBJ_CreditCard__c card = [
      SELECT Name, AXF_CC_LKP_Account__c, AXF_CC_LKP_BankInstitution__c
      FROM AXF_OBJ_CreditCard__c
      WHERE AXF_CC_EXI_PluggyCreditCardId__c = 'card-manual'
    ];
    Assert.isNotNull(
      card.AXF_CC_LKP_Account__c,
      'Account filled from connection map'
    );
    Assert.areEqual(
      conn.AXF_CON_LKP_BankInstitution__c,
      card.AXF_CC_LKP_BankInstitution__c
    );
    Assert.areEqual('JOAO SILVA - BANCO DO BRASIL', card.Name);
    Assert.areEqual(
      'LOWER NAME',
      [
        SELECT Name
        FROM AXF_OBJ_BankAccount__c
        WHERE AXF_BA_EXI_PluggyAccountId__c = 'acc-manual'
      ]
      .Name
    );
  }

  @IsTest
  static void blankItemAndHttpErrorReturnEmptyResult() {
    AXF_CLS_PluggyTestFactory.MockRouter mock = new AXF_CLS_PluggyTestFactory.MockRouter()
      .route('/accounts?itemId=', 500, '{"message":"error"}');
    Test.setMock(HttpCalloutMock.class, mock);
    AXF_OBJ_PluggyConnection__c conn = getConnection();
    AXF_CLS_PluggyAccountSync_Service.AccountSyncResult blankResult;
    AXF_CLS_PluggyAccountSync_Service.AccountSyncResult errorResult;
    AXF_CLS_PluggyAccountSync_Service.AccountSyncResult noResults;

    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      blankResult = AXF_CLS_PluggyAccountSync_Service.fetchAccountsForConnection(
        conn.Id,
        '',
        'key'
      );
      errorResult = AXF_CLS_PluggyAccountSync_Service.fetchAccountsForConnection(
        conn.Id,
        'item-x',
        'key'
      );
      mock.routes.clear();
      mock.route('/accounts?itemId=', 200, '{"total":0}');
      noResults = AXF_CLS_PluggyAccountSync_Service.fetchAccountsForConnection(
        conn.Id,
        'item-x',
        'key'
      );
      Test.stopTest();
    }

    Assert.isTrue(
      blankResult.bankAccounts.isEmpty() && blankResult.creditCards.isEmpty()
    );
    Assert.isTrue(
      errorResult.bankAccounts.isEmpty() && errorResult.creditCards.isEmpty()
    );
    Assert.isTrue(
      noResults.bankAccounts.isEmpty() && noResults.creditCards.isEmpty()
    );
    Assert.areEqual(
      2,
      mock.endpoints.size(),
      'Blank item id must not trigger a callout'
    );
  }

  @IsTest
  static void buildStandardizedNameCoversAllFallbacks() {
    Assert.areEqual(
      'ANA - BANCO INTER',
      AXF_CLS_PluggyAccountSync_Service.buildStandardizedName(
        ' Ana ',
        'Banco Inter (077)',
        null,
        'Default'
      )
    );
    Assert.areEqual(
      'ANA',
      AXF_CLS_PluggyAccountSync_Service.buildStandardizedName(
        'Ana',
        null,
        'fb',
        'Default'
      )
    );
    Assert.areEqual(
      'SAO PAULO BANK',
      AXF_CLS_PluggyAccountSync_Service.buildStandardizedName(
        null,
        'São Paulo Bank',
        'fb',
        'Default'
      )
    );
    Assert.areEqual(
      'FALLBACK',
      AXF_CLS_PluggyAccountSync_Service.buildStandardizedName(
        null,
        null,
        ' fallback ',
        'Default'
      )
    );
    Assert.areEqual(
      'DEFAULT',
      AXF_CLS_PluggyAccountSync_Service.buildStandardizedName(
        null,
        '  ',
        null,
        'Default'
      )
    );
    Assert.isNull(
      AXF_CLS_PluggyAccountSync_Service.buildStandardizedName(
        null,
        null,
        null,
        null
      )
    );
  }
}
