@IsTest
private class AXF_CLS_CTRL_PluggySyncTest {
  private static List<String> transactionUrls = new List<String>();

  private class PluggyMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      String url = req.getEndpoint();
      if (url.endsWith('/auth')) {
        res.setBody('{"apiKey":"abc"}');
      } else if (url.contains('/bills?')) {
        res.setBody(
          '{"total":1,"totalPages":1,"page":1,"results":[{"id":"bill-1","dueDate":"2026-09-27T00:00:00.000Z","totalAmount":100}]}'
        );
      } else {
        transactionUrls.add(url);
        res.setBody(
          '{"results":[{"id":"tx-1","amount":-35.5,"type":"DEBIT","date":"2026-09-10T00:00:00.000Z","description":"Mercado","creditCardMetadata":{"billId":"bill-1"}}],"next":null}'
        );
      }
      return res;
    }
  }

  @TestSetup
  static void setup() {
    ALT_CLS_SyncTestUser.create(
      'axfps',
      new List<String>{
        'AXF_OBJ_BankAccount__c',
        'AXF_OBJ_BankAccountTransaction__c',
        'AXF_OBJ_CreditCard__c',
        'AXF_OBJ_CreditCardInvoice__c',
        'AXF_OBJ_CreditCardTransaction__c',
        'AXF_OBJ_Entry__c'
      }
    );
  }

  private static Account holder() {
    Account holder = new Account(Name = 'Holder');
    insert holder;
    return holder;
  }

  @IsTest
  static void syncsBankAccountPeriodWithinWindow() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      AXF_OBJ_BankAccount__c account = new AXF_OBJ_BankAccount__c(
        Name = 'Conta',
        AXF_BA_MD_Holder__c = holder().Id,
        AXF_BA_PKL_Institution__c = '341',
        AXF_BA_PKL_Type__c = 'Checking',
        AXF_BA_EXI_PluggyAccountId__c = 'acc-1'
      );
      insert account;
      Test.setMock(HttpCalloutMock.class, new PluggyMock());
      Test.startTest();
      AXF_CLS_CTRL_PluggySync.SyncView view = AXF_CLS_CTRL_PluggySync.syncPeriod(
        account.Id,
        Date.newInstance(2026, 9, 1),
        Date.newInstance(2026, 9, 30)
      );
      Test.stopTest();
      System.assertEquals(true, view.success, view.message);
      System.assertEquals(1, view.transactions);
      System.assertEquals(1, transactionUrls.size());
      System.assert(transactionUrls[0].contains('&dateFrom=2026-09-01'));
      System.assert(transactionUrls[0].endsWith('&dateTo=2026-09-30'));
    }
  }

  @IsTest
  static void syncsCardPeriodAndInvoices() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      AXF_OBJ_CreditCard__c card = new AXF_OBJ_CreditCard__c(
        Name = 'Cartão',
        AXF_CC_MD_Holder__c = holder().Id,
        AXF_CC_PKL_Institution__c = '341',
        AXF_CC_EXI_PluggyCardId__c = 'card-1'
      );
      insert card;
      Test.setMock(HttpCalloutMock.class, new PluggyMock());
      Test.startTest();
      AXF_CLS_CTRL_PluggySync.SyncView view = AXF_CLS_CTRL_PluggySync.syncPeriod(
        card.Id,
        Date.newInstance(2026, 8, 1),
        Date.newInstance(2026, 9, 30)
      );
      Test.stopTest();
      System.assertEquals(true, view.success, view.message);
      System.assert(transactionUrls[0].contains('&dateFrom=2026-08-01'));
      System.assert(transactionUrls[0].endsWith('&dateTo=2026-09-30'));
      System.assertEquals(
        1,
        [SELECT COUNT() FROM AXF_OBJ_CreditCardInvoice__c]
      );
    }
  }

  @IsTest
  static void manualAccountWithoutPluggyIdReportsFailure() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      AXF_OBJ_BankAccount__c account = new AXF_OBJ_BankAccount__c(
        Name = 'Manual',
        AXF_BA_MD_Holder__c = holder().Id,
        AXF_BA_PKL_Institution__c = '341',
        AXF_BA_PKL_Type__c = 'Checking'
      );
      insert account;
      AXF_CLS_CTRL_PluggySync.SyncView view = AXF_CLS_CTRL_PluggySync.syncPeriod(
        account.Id,
        Date.newInstance(2026, 9, 1),
        Date.newInstance(2026, 9, 30)
      );
      System.assertEquals(false, view.success);
      System.assert(view.message.contains('sem Id do Pluggy'));
    }
  }

  @IsTest
  static void rejectsInvalidInput() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Id holderId = holder().Id;
      for (
        List<Object> args : new List<List<Object>>{
          new List<Object>{ null, Date.today(), Date.today() },
          new List<Object>{ holderId, Date.today(), Date.today() },
          new List<Object>{ holderId, Date.today(), Date.today().addDays(-1) }
        }
      ) {
        try {
          AXF_CLS_CTRL_PluggySync.syncPeriod(
            (Id) args[0],
            (Date) args[1],
            (Date) args[2]
          );
          System.assert(false, 'expected AuraHandledException');
        } catch (AuraHandledException e) {
          System.assert(true);
        }
      }
    }
  }
}
