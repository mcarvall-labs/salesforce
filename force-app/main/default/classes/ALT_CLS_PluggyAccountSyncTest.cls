@IsTest
private class ALT_CLS_PluggyAccountSyncTest {
  private class PluggyMock implements HttpCalloutMock {
    private Integer accountsStatus;

    PluggyMock(Integer accountsStatus) {
      this.accountsStatus = accountsStatus;
    }

    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      if (req.getEndpoint().endsWith('/auth')) {
        res.setStatusCode(200);
        res.setBody('{"apiKey":"abc"}');
        return res;
      }
      System.assert(req.getEndpoint().contains('/accounts?itemId=item-1'));
      res.setStatusCode(accountsStatus);
      res.setBody(
        '{"results":[' +
          '{"id":"acc-1","type":"BANK","subtype":"CHECKING_ACCOUNT","name":"Conta Corrente","number":"12345-6","balance":1500.75,"currencyCode":"BRL","bankData":{"transferNumber":"0001/12345-6"}},' +
          '{"id":"acc-2","type":"BANK","subtype":"SAVINGS_ACCOUNT","name":"Poupança","number":"777","balance":10},' +
          '{"id":"card-1","type":"CREDIT","subtype":"CREDIT_CARD","name":"Cartão Gold","number":"5555","creditData":{"brand":"VISA","level":"GOLD","creditLimit":5000,"availableCreditLimit":3200.5,"balanceCloseDate":"2026-09-25T00:00:00.000Z","balanceDueDate":"2026-10-05T00:00:00.000Z"}}' +
          ']}'
      );
      return res;
    }
  }

  @TestSetup
  static void setup() {
    ALT_CLS_SyncTestUser.create(
      'axfsync',
      new List<String>{
        'AXF_OBJ_PluggyConnection__c',
        'AXF_OBJ_BankAccount__c',
        'AXF_OBJ_CreditCard__c'
      }
    );
  }

  private static User syncUser() {
    return [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
  }

  private static AXF_OBJ_PluggyConnection__c connection() {
    Account holder = new Account(Name = 'Holder');
    insert holder;
    AXF_OBJ_PluggyConnection__c connection = new AXF_OBJ_PluggyConnection__c(
      AXF_CON_MD_Holder__c = holder.Id,
      AXF_CON_PKL_Institution__c = '341',
      AXF_CON_EXI_PluggyItemId__c = 'item-1',
      AXF_CON_PKL_Status__c = 'Active'
    );
    insert connection;
    return connection;
  }

  @IsTest
  static void syncCreatesAccountsAndCards() {
    System.runAs(syncUser()) {
      AXF_OBJ_PluggyConnection__c connection = connection();
      ALT_CLS_PluggyAccountSync.assignRecordType = false;
      Test.setMock(HttpCalloutMock.class, new PluggyMock(200));
      Test.startTest();
      ALT_CLS_PluggyAccountSync.Result first = new ALT_CLS_PluggyAccountSync()
        .sync(connection.Id);
      Test.stopTest();
      System.assertEquals(true, first.success, first.message);
      System.assertEquals(2, first.accounts);
      System.assertEquals(1, first.cards);
      AXF_OBJ_BankAccount__c checking = [
        SELECT
          AXF_BA_MD_Holder__c,
          AXF_BA_LKP_Connection__c,
          AXF_BA_PKL_Institution__c,
          AXF_BA_PKL_Type__c,
          AXF_BA_TXT_Branch__c,
          AXF_BA_TXT_Number__c,
          AXF_BA_CUR_Balance__c
        FROM AXF_OBJ_BankAccount__c
        WHERE AXF_BA_EXI_PluggyAccountId__c = 'acc-1'
      ];
      System.assertEquals(
        connection.AXF_CON_MD_Holder__c,
        checking.AXF_BA_MD_Holder__c
      );
      System.assertEquals(connection.Id, checking.AXF_BA_LKP_Connection__c);
      System.assertEquals('341', checking.AXF_BA_PKL_Institution__c);
      System.assertEquals('Checking', checking.AXF_BA_PKL_Type__c);
      System.assertEquals('0001', checking.AXF_BA_TXT_Branch__c);
      System.assertEquals('12345-6', checking.AXF_BA_TXT_Number__c);
      System.assertEquals(1500.75, checking.AXF_BA_CUR_Balance__c);
      System.assertEquals(
        'Savings',
        [
          SELECT AXF_BA_PKL_Type__c
          FROM AXF_OBJ_BankAccount__c
          WHERE AXF_BA_EXI_PluggyAccountId__c = 'acc-2'
        ]
        .AXF_BA_PKL_Type__c
      );
      System.assertEquals(2, [SELECT COUNT() FROM AXF_OBJ_BankAccount__c]);
      AXF_OBJ_CreditCard__c card = [
        SELECT
          Name,
          AXF_CC_TXT_Brand__c,
          AXF_CC_TXT_Level__c,
          AXF_CC_TXT_LastDigits__c,
          AXF_CC_CUR_Limit__c,
          AXF_CC_CUR_AvailableLimit__c,
          AXF_CC_NUM_ClosingDay__c,
          AXF_CC_NUM_DueDay__c
        FROM AXF_OBJ_CreditCard__c
      ];
      System.assertEquals('VISA', card.AXF_CC_TXT_Brand__c);
      System.assert(
        card.Name.endsWith(' - VISA (5555)') && !card.Name.startsWith('341'),
        card.Name
      );
      System.assertEquals('GOLD', card.AXF_CC_TXT_Level__c);
      System.assertEquals('5555', card.AXF_CC_TXT_LastDigits__c);
      System.assertEquals(5000, card.AXF_CC_CUR_Limit__c);
      System.assertEquals(3200.5, card.AXF_CC_CUR_AvailableLimit__c);
      System.assertEquals(25, card.AXF_CC_NUM_ClosingDay__c);
      System.assertEquals(5, card.AXF_CC_NUM_DueDay__c);
      System.assertNotEquals(
        null,
        [
          SELECT AXF_CON_DT_LastSyncDatetime__c
          FROM AXF_OBJ_PluggyConnection__c
          WHERE Id = :connection.Id
        ]
        .AXF_CON_DT_LastSyncDatetime__c
      );
    }
  }

  @IsTest
  static void syncReportsPluggyError() {
    System.runAs(syncUser()) {
      AXF_OBJ_PluggyConnection__c connection = connection();
      ALT_CLS_PluggyAccountSync.assignRecordType = false;
      Test.setMock(HttpCalloutMock.class, new PluggyMock(500));
      Test.startTest();
      ALT_CLS_PluggyAccountSync.Result r = new ALT_CLS_PluggyAccountSync()
        .sync(connection.Id);
      Test.stopTest();
      System.assertEquals(false, r.success);
      System.assert(r.message.contains('HTTP 500'));
      System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_BankAccount__c]);
    }
  }

  @IsTest
  static void syncRejectsUnknownConnection() {
    System.runAs(syncUser()) {
      Account holder = new Account(Name = 'Other');
      insert holder;
      AXF_OBJ_PluggyConnection__c connection = new AXF_OBJ_PluggyConnection__c(
        AXF_CON_MD_Holder__c = holder.Id,
        AXF_CON_PKL_Institution__c = '341',
        AXF_CON_EXI_PluggyItemId__c = 'gone'
      );
      insert connection;
      Id missing = connection.Id;
      delete connection;
      ALT_CLS_PluggyAccountSync.Result r = new ALT_CLS_PluggyAccountSync()
        .sync(missing);
      System.assertEquals(false, r.success);
      System.assertEquals('Conexão não encontrada.', r.message);
    }
  }

  @IsTest
  static void pluggyRecordTypesExist() {
    System.assertNotEquals(
      null,
      ALT_CLS_PluggyAccountSync.recordTypeId(
        Schema.SObjectType.AXF_OBJ_BankAccount__c
      )
    );
    System.assertNotEquals(
      null,
      ALT_CLS_PluggyAccountSync.recordTypeId(
        Schema.SObjectType.AXF_OBJ_CreditCard__c
      )
    );
  }

  @IsTest
  static void syncUpdatesExistingRecordsWithoutDuplicates() {
    System.runAs(syncUser()) {
      AXF_OBJ_PluggyConnection__c connection = connection();
      insert new AXF_OBJ_BankAccount__c(
        Name = 'Old name',
        AXF_BA_MD_Holder__c = connection.AXF_CON_MD_Holder__c,
        AXF_BA_PKL_Institution__c = '341',
        AXF_BA_PKL_Type__c = 'Checking',
        AXF_BA_EXI_PluggyAccountId__c = 'acc-1'
      );
      ALT_CLS_PluggyAccountSync.assignRecordType = false;
      Test.setMock(HttpCalloutMock.class, new PluggyMock(200));
      Test.startTest();
      ALT_CLS_PluggyAccountSync.Result r = new ALT_CLS_PluggyAccountSync()
        .sync(connection.Id);
      Test.stopTest();
      System.assertEquals(true, r.success, r.message);
      System.assertEquals(2, [SELECT COUNT() FROM AXF_OBJ_BankAccount__c]);
      System.assertEquals(
        'Conta Corrente',
        [
          SELECT Name
          FROM AXF_OBJ_BankAccount__c
          WHERE AXF_BA_EXI_PluggyAccountId__c = 'acc-1'
        ]
        .Name
      );
    }
  }
}
