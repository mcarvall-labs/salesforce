@IsTest
private class ALT_CLS_PluggyConnectionTest {
  private class PluggyMock implements HttpCalloutMock {
    private Integer itemStatus;

    PluggyMock(Integer itemStatus) {
      this.itemStatus = itemStatus;
    }

    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      if (req.getEndpoint().endsWith('/auth')) {
        res.setStatusCode(200);
        res.setBody('{"apiKey":"abc"}');
      } else {
        System.assertEquals('abc', req.getHeader('X-API-KEY'));
        res.setStatusCode(itemStatus);
        res.setBody('{"id":"item-1"}');
      }
      return res;
    }
  }

  @TestSetup
  static void setup() {
    ALT_CLS_ConnectionTestUser.create('axfcon');
  }

  private static User connectionUser() {
    return ALT_CLS_ConnectionTestUser.find('axfcon');
  }

  private static Id holder() {
    Account a = new Account(Name = 'Holder');
    insert a;
    return a.Id;
  }

  @IsTest
  static void createRejectsMissingData() {
    ALT_CLS_PluggyConnection.Result r = new ALT_CLS_PluggyConnection()
      .create(null, '341', 'item-1');
    System.assertEquals(false, r.success);
  }

  @IsTest
  static void createInsertsConnectionForValidItem() {
    System.runAs(connectionUser()) {
      Id holderId = holder();
      Test.setMock(HttpCalloutMock.class, new PluggyMock(200));
      Test.startTest();
      ALT_CLS_PluggyConnection.Result r = new ALT_CLS_PluggyConnection()
        .create(holderId, '341', ' item-1 ');
      Test.stopTest();
      System.assertEquals(true, r.success, r.message);
      AXF_OBJ_PluggyConnection__c saved = [
        SELECT Name, AXF_CON_EXI_PluggyItemId__c, AXF_CON_PKL_Status__c
        FROM AXF_OBJ_PluggyConnection__c
        WHERE Id = :r.connectionId
      ];
      System.assertEquals('item-1', saved.AXF_CON_EXI_PluggyItemId__c);
      System.assertEquals('Active', saved.AXF_CON_PKL_Status__c);
      System.assertEquals('Holder - Itaú Unibanco (341)', saved.Name);
      System.assertEquals(1, new ALT_CLS_PluggyConnection().countConnections());
    }
  }

  @IsTest
  static void createReportsUnknownItem() {
    System.runAs(connectionUser()) {
      Id holderId = holder();
      Test.setMock(HttpCalloutMock.class, new PluggyMock(404));
      Test.startTest();
      ALT_CLS_PluggyConnection.Result r = new ALT_CLS_PluggyConnection()
        .create(holderId, '341', 'missing');
      Test.stopTest();
      System.assertEquals(false, r.success);
      System.assert(r.message.contains('não encontrado'));
      System.assertEquals(0, new ALT_CLS_PluggyConnection().countConnections());
    }
  }

  @IsTest
  static void createReportsPluggyError() {
    System.runAs(connectionUser()) {
      Id holderId = holder();
      Test.setMock(HttpCalloutMock.class, new PluggyMock(500));
      Test.startTest();
      ALT_CLS_PluggyConnection.Result r = new ALT_CLS_PluggyConnection()
        .create(holderId, '341', 'item-1');
      Test.stopTest();
      System.assertEquals(false, r.success);
      System.assert(r.message.contains('500'));
    }
  }

  @IsTest
  static void createReportsDuplicateItem() {
    System.runAs(connectionUser()) {
      Id holderId = holder();
      Test.setMock(HttpCalloutMock.class, new PluggyMock(200));
      insert new AXF_OBJ_PluggyConnection__c(
        AXF_CON_MD_Holder__c = holderId,
        AXF_CON_PKL_Institution__c = '341',
        AXF_CON_EXI_PluggyItemId__c = 'item-1'
      );
      Test.startTest();
      ALT_CLS_PluggyConnection.Result r = new ALT_CLS_PluggyConnection()
        .create(holderId, '341', 'item-1');
      Test.stopTest();
      System.assertEquals(false, r.success);
      System.assert(r.message.contains('já está cadastrado'));
    }
  }
}
