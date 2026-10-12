@IsTest
private class AXF_CLS_CTRL_PluggyConnectionTest {
  private class PluggyMock implements HttpCalloutMock {
    private Integer itemStatus;

    PluggyMock(Integer itemStatus) {
      this.itemStatus = itemStatus;
    }

    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      String endpoint = req.getEndpoint();
      if (endpoint.endsWith('/auth')) {
        res.setStatusCode(200);
        res.setBody('{"apiKey":"abc"}');
      } else if (endpoint.contains('/accounts?')) {
        res.setStatusCode(200);
        res.setBody(
          '{"results":[' +
            '{"id":"acc-1","type":"BANK","subtype":"CHECKING_ACCOUNT","name":"Conta Corrente","number":"12345-6","balance":10,"currencyCode":"BRL","bankData":{"transferNumber":"0001/12345-6"}},' +
            '{"id":"card-1","type":"CREDIT","subtype":"CREDIT_CARD","name":"Cartão","number":"5555","creditData":{"brand":"VISA","level":"GOLD","creditLimit":5000,"availableCreditLimit":3000}}' +
            ']}'
        );
      } else {
        res.setStatusCode(itemStatus);
        res.setBody('{"id":"item-1"}');
      }
      return res;
    }
  }

  @TestSetup
  static void setup() {
    ALT_CLS_SyncTestUser.create(
      'axfcon',
      new List<String>{
        'AXF_OBJ_PluggyConnection__c',
        'AXF_OBJ_BankAccount__c',
        'AXF_OBJ_CreditCard__c'
      }
    );
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
  static void validItemImportsAccountsAndCards() {
    AXF_OBJ_PluggyConnection__c connection = connection();
    ALT_CLS_PluggyAccountSync.assignRecordType = false;
    Test.setMock(HttpCalloutMock.class, new PluggyMock(200));
    Test.startTest();
    AXF_CLS_CTRL_PluggyConnection.TestView view = AXF_CLS_CTRL_PluggyConnection.testAndSync(
      connection.Id
    );
    Test.stopTest();
    System.assertEquals(true, view.success, view.message);
    System.assertEquals(1, view.accounts);
    System.assertEquals(1, view.cards);
  }

  @IsTest
  static void invalidItemDoesNotImport() {
    AXF_OBJ_PluggyConnection__c connection = connection();
    Test.setMock(HttpCalloutMock.class, new PluggyMock(404));
    Test.startTest();
    AXF_CLS_CTRL_PluggyConnection.TestView view = AXF_CLS_CTRL_PluggyConnection.testAndSync(
      connection.Id
    );
    Test.stopTest();
    System.assertEquals(false, view.success);
    System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_BankAccount__c]);
  }

  @IsTest
  static void rejectsMissingConnection() {
    try {
      AXF_CLS_CTRL_PluggyConnection.testAndSync(null);
      System.assert(false, 'expected AuraHandledException');
    } catch (AuraHandledException e) {
      System.assertNotEquals(null, e.getMessage());
    }
  }
}
