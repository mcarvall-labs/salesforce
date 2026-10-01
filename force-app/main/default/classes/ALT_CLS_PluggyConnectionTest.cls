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
    PermissionSet ps = new PermissionSet(
      Label = 'Connection Test',
      Name = 'AXF_Connection_Test'
    );
    insert ps;
    insert new ObjectPermissions(
      ParentId = ps.Id,
      SobjectType = 'AXF_OBJ_PluggyConnection__c',
      PermissionsCreate = true,
      PermissionsRead = true,
      PermissionsEdit = true,
      PermissionsDelete = true
    );
    List<FieldPermissions> fields = new List<FieldPermissions>();
    for (
      String field : new List<String>{
        'AXF_CON_EXI_PluggyItemId__c',
        'AXF_CON_PKL_Status__c'
      }
    ) {
      fields.add(
        new FieldPermissions(
          ParentId = ps.Id,
          SobjectType = 'AXF_OBJ_PluggyConnection__c',
          Field = 'AXF_OBJ_PluggyConnection__c.' + field,
          PermissionsRead = true,
          PermissionsEdit = true
        )
      );
    }
    insert fields;
    User u = new User(
      Alias = 'axfcon',
      Email = 'axfcon@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Connection',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
      .Id,
      TimeZoneSidKey = 'America/Sao_Paulo',
      Username = 'axfcon' + System.currentTimeMillis() + '@example.com'
    );
    insert u;
    insert new PermissionSetAssignment(
      AssigneeId = u.Id,
      PermissionSetId = ps.Id
    );
  }

  private static User connectionUser() {
    return [SELECT Id FROM User WHERE Alias = 'axfcon' LIMIT 1];
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
      System.assertEquals('Holder - 341', saved.Name);
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
