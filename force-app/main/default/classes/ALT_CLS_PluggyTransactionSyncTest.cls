@IsTest
private class ALT_CLS_PluggyTransactionSyncTest {
  private class PluggyMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      if (req.getEndpoint().endsWith('/auth')) {
        res.setBody('{"apiKey":"abc"}');
        return res;
      }
      System.assert(
        req.getEndpoint().contains('/v2/transactions?accountId=acc-1&dateFrom=')
      );
      if (req.getEndpoint().contains('&after=cursor-2')) {
        res.setBody(
          '{"results":[{"id":"tx-3","amount":10,"type":"CREDIT","date":"2026-09-12T00:00:00.000Z","description":"Pix recebido"}],"next":null}'
        );
      } else {
        res.setBody(
          '{"results":[' +
            '{"id":"tx-1","amount":-35.5,"type":"DEBIT","date":"2026-09-10T00:00:00.000Z","descriptionRaw":"COMPRA MERCADO","description":"Mercado","category":"Shopping"},' +
            '{"id":"tx-2","amount":100,"type":"DEBIT","date":"2026-09-11T00:00:00.000Z","description":"Saque"}' +
            '],"next":"cursor-2"}'
        );
      }
      return res;
    }
  }

  private class ErrorMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(req.getEndpoint().endsWith('/auth') ? 200 : 500);
      res.setBody('{"apiKey":"abc"}');
      return res;
    }
  }

  @TestSetup
  static void setup() {
    ALT_CLS_SyncTestUser.create(
      'axftx',
      new List<String>{
        'AXF_OBJ_BankAccount__c',
        'AXF_OBJ_BankAccountTransaction__c'
      }
    );
  }

  private static AXF_OBJ_BankAccount__c account(String pluggyId) {
    Account holder = new Account(Name = 'Holder');
    insert holder;
    AXF_OBJ_BankAccount__c account = new AXF_OBJ_BankAccount__c(
      Name = 'Conta',
      AXF_BA_MD_Holder__c = holder.Id,
      AXF_BA_PKL_Institution__c = '341',
      AXF_BA_PKL_Type__c = 'Checking',
      AXF_BA_EXI_PluggyAccountId__c = pluggyId
    );
    insert account;
    return account;
  }

  @IsTest
  static void syncFollowsPagesAndStoresSignedAmounts() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      AXF_OBJ_BankAccount__c account = account('acc-1');
      Test.setMock(HttpCalloutMock.class, new PluggyMock());
      Test.startTest();
      ALT_CLS_PluggyTransactionSync.Result r = new ALT_CLS_PluggyTransactionSync()
        .sync(account.Id);
      Test.stopTest();
      System.assertEquals(true, r.success, r.message);
      System.assertEquals(3, r.transactions);
      Map<String, AXF_OBJ_BankAccountTransaction__c> saved = new Map<String, AXF_OBJ_BankAccountTransaction__c>();
      for (AXF_OBJ_BankAccountTransaction__c t : [
        SELECT
          AXF_BAT_EXI_PluggyTransactionId__c,
          AXF_BAT_CUR_Amount__c,
          AXF_BAT_DAT_Date__c,
          AXF_BAT_TXT_Description__c,
          AXF_BAT_TXT_PluggyCategory__c
        FROM AXF_OBJ_BankAccountTransaction__c
      ]) {
        saved.put(t.AXF_BAT_EXI_PluggyTransactionId__c, t);
      }
      System.assertEquals(-35.5, saved.get('tx-1').AXF_BAT_CUR_Amount__c);
      System.assertEquals(
        'COMPRA MERCADO',
        saved.get('tx-1').AXF_BAT_TXT_Description__c
      );
      System.assertEquals(
        'Shopping',
        saved.get('tx-1').AXF_BAT_TXT_PluggyCategory__c
      );
      System.assertEquals(
        Date.newInstance(2026, 9, 10),
        saved.get('tx-1').AXF_BAT_DAT_Date__c
      );
      System.assertEquals(-100, saved.get('tx-2').AXF_BAT_CUR_Amount__c);
      System.assertEquals(10, saved.get('tx-3').AXF_BAT_CUR_Amount__c);
    }
  }

  @IsTest
  static void syncUpdatesExistingTransactionWithoutDuplicates() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      AXF_OBJ_BankAccount__c account = account('acc-1');
      insert new AXF_OBJ_BankAccountTransaction__c(
        AXF_BAT_MD_BankAccount__c = account.Id,
        AXF_BAT_DAT_Date__c = Date.newInstance(2026, 9, 9),
        AXF_BAT_CUR_Amount__c = 1,
        AXF_BAT_EXI_PluggyTransactionId__c = 'tx-1'
      );
      Test.setMock(HttpCalloutMock.class, new PluggyMock());
      Test.startTest();
      ALT_CLS_PluggyTransactionSync.Result r = new ALT_CLS_PluggyTransactionSync()
        .sync(account.Id);
      Test.stopTest();
      System.assertEquals(true, r.success, r.message);
      System.assertEquals(
        3,
        [SELECT COUNT() FROM AXF_OBJ_BankAccountTransaction__c]
      );
      System.assertEquals(
        -35.5,
        [
          SELECT AXF_BAT_CUR_Amount__c
          FROM AXF_OBJ_BankAccountTransaction__c
          WHERE AXF_BAT_EXI_PluggyTransactionId__c = 'tx-1'
        ]
        .AXF_BAT_CUR_Amount__c
      );
    }
  }

  @IsTest
  static void syncRejectsManualAccount() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      AXF_OBJ_BankAccount__c account = account(null);
      ALT_CLS_PluggyTransactionSync.Result r = new ALT_CLS_PluggyTransactionSync()
        .sync(account.Id);
      System.assertEquals(false, r.success);
    }
  }

  @IsTest
  static void syncReportsPluggyError() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      AXF_OBJ_BankAccount__c account = account('acc-1');
      Test.setMock(HttpCalloutMock.class, new ErrorMock());
      Test.startTest();
      ALT_CLS_PluggyTransactionSync.Result r = new ALT_CLS_PluggyTransactionSync()
        .sync(account.Id);
      Test.stopTest();
      System.assertEquals(false, r.success);
      System.assert(r.message.contains('HTTP 500'));
    }
  }
}
