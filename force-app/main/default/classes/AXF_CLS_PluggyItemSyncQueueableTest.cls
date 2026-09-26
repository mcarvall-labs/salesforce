@IsTest
private class AXF_CLS_PluggyItemSyncQueueableTest {
  @TestSetup
  static void setup() {
    User u = AXF_CLS_PluggyTestFactory.createTestUser();
    System.runAs(u) {
      AXF_CLS_PluggyTestFactory.createHolder(
        'Joao Silva',
        AXF_CLS_PluggyTestFactory.CPF
      );
      AXF_OBJ_BankInstitution__c inst = AXF_CLS_PluggyTestFactory.createInstitution(
        'Banco do Brasil (001)',
        '001'
      );
      AXF_CLS_PluggyTestFactory.createConnection(
        inst.Id,
        AXF_CLS_PluggyTestFactory.ITEM_ID
      );
    }
  }

  @IsTest
  static void updatedItemSyncsAccountsInvestmentsAndLoans() {
    AXF_CLS_PluggyTestFactory.MockRouter mock = AXF_CLS_PluggyTestFactory.itemSyncMock();
    Test.setMock(HttpCalloutMock.class, mock);

    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      System.enqueueJob(new AXF_CLS_PluggyItemSyncQueueable());
      Test.stopTest();
    }

    AXF_OBJ_PluggyConnection__c conn = [
      SELECT
        AXF_CON_TXT_SyncStatus__c,
        AXF_CON_TXT_ExecutionStatus__c,
        AXF_CON_DT_LastSyncDatetime__c,
        AXF_CON_TXT_SyncErrorMessage__c
      FROM AXF_OBJ_PluggyConnection__c
    ];
    Assert.areEqual('UPDATED', conn.AXF_CON_TXT_SyncStatus__c);
    Assert.areEqual('SUCCESS', conn.AXF_CON_TXT_ExecutionStatus__c);
    Assert.areEqual(
      Datetime.newInstanceGmt(2026, 9, 20, 10, 0, 0),
      conn.AXF_CON_DT_LastSyncDatetime__c
    );
    Assert.isNull(conn.AXF_CON_TXT_SyncErrorMessage__c);

    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AXF_OBJ_BankAccount__c
        WHERE
          AXF_BA_EXI_PluggyAccountId__c = :AXF_CLS_PluggyTestFactory.BANK_PLUGGY_ID
      ]
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AXF_OBJ_CreditCard__c
        WHERE
          AXF_CC_EXI_PluggyCreditCardId__c = :AXF_CLS_PluggyTestFactory.CARD_PLUGGY_ID
      ]
    );
    Assert.areEqual(2, [SELECT COUNT() FROM AXF_OBJ_Investment__c]);
    Assert.areEqual(1, [SELECT COUNT() FROM AXF_OBJ_Loan__c]);
    Assert.areEqual(1, mock.callsTo('/auth'));
  }

  @IsTest
  static void relatedDataFailuresDoNotBlockConnectionUpdate() {
    Test.setMock(
      HttpCalloutMock.class,
      new AXF_CLS_PluggyTestFactory.MockRouter()
        .route('/auth', 200, AXF_CLS_PluggyTestFactory.authBody())
        .route(
          '/items/',
          200,
          AXF_CLS_PluggyTestFactory.itemBody('UPDATED', null)
        )
        .onThrow('/accounts?itemId=')
        .onThrow('/investments?itemId=')
        .onThrow('/loans?itemId=')
    );
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      System.enqueueJob(new AXF_CLS_PluggyItemSyncQueueable());
      Test.stopTest();
    }
    Assert.areEqual(
      'UPDATED',
      [SELECT AXF_CON_TXT_SyncStatus__c FROM AXF_OBJ_PluggyConnection__c]
      .AXF_CON_TXT_SyncStatus__c
    );
    Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_BankAccount__c]);
    Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_Investment__c]);
  }

  @IsTest
  static void mapsPluggyErrorsToFriendlyMessages() {
    Map<String, Object> errorsByItem = new Map<String, Object>{
      'item-cred' => new Map<String, Object>{
        'code' => 'INVALID_CREDENTIALS',
        'message' => 'x'
      },
      'item-mfa' => new Map<String, Object>{ 'code' => 'USER_INPUT_REQUIRED' },
      'item-site' => new Map<String, Object>{ 'code' => 'SITE_ERROR' },
      'item-unexp' => new Map<String, Object>{ 'code' => 'UNEXPECTED_ERROR' },
      'item-rawcred' => new Map<String, Object>{
        'code' => 'OTHER',
        'message' => 'Bank said: invalid credentials'
      },
      'item-raw' => new Map<String, Object>{
        'code' => 'OTHER',
        'message' => 'Some raw message'
      },
      'item-str' => 'Plain string error',
      'item-nomsg' => new Map<String, Object>{ 'code' => null }
    };
    AXF_OBJ_BankInstitution__c inst = [
      SELECT Id
      FROM AXF_OBJ_BankInstitution__c
      LIMIT 1
    ];
    AXF_CLS_PluggyTestFactory.MockRouter mock = new AXF_CLS_PluggyTestFactory.MockRouter()
      .route('/auth', 200, AXF_CLS_PluggyTestFactory.authBody());
    List<AXF_OBJ_PluggyConnection__c> conns = new List<AXF_OBJ_PluggyConnection__c>();
    for (String itemId : errorsByItem.keySet()) {
      conns.add(
        new AXF_OBJ_PluggyConnection__c(
          Name = itemId,
          AXF_CON_LKP_BankInstitution__c = inst.Id,
          AXF_CON_EXI_PluggyItemId__c = itemId
        )
      );
      mock.route(
        '/items/' + itemId,
        200,
        AXF_CLS_PluggyTestFactory.itemBody(
          'LOGIN_ERROR',
          errorsByItem.get(itemId)
        )
      );
    }
    conns.add(
      new AXF_OBJ_PluggyConnection__c(
        Name = 'item-http',
        AXF_CON_LKP_BankInstitution__c = inst.Id,
        AXF_CON_EXI_PluggyItemId__c = 'item-http'
      )
    );
    conns.add(
      new AXF_OBJ_PluggyConnection__c(
        Name = 'item-down',
        AXF_CON_LKP_BankInstitution__c = inst.Id,
        AXF_CON_EXI_PluggyItemId__c = 'item-down'
      )
    );
    mock.route('/items/item-http', 500, '{}');
    mock.onThrow('/items/item-down');
    mock.route(
      '/items/',
      200,
      AXF_CLS_PluggyTestFactory.itemBody('OUTDATED', null)
    );

    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      insert conns;
      Test.setMock(HttpCalloutMock.class, mock);
      Test.startTest();
      System.enqueueJob(new AXF_CLS_PluggyItemSyncQueueable());
      Test.stopTest();
    }

    Map<String, String> messages = new Map<String, String>();
    for (AXF_OBJ_PluggyConnection__c c : [
      SELECT
        AXF_CON_EXI_PluggyItemId__c,
        AXF_CON_TXT_SyncErrorMessage__c,
        AXF_CON_TXT_SyncStatus__c
      FROM AXF_OBJ_PluggyConnection__c
    ]) {
      messages.put(
        c.AXF_CON_EXI_PluggyItemId__c,
        c.AXF_CON_TXT_SyncErrorMessage__c
      );
    }
    Assert.isTrue(
      messages.get('item-cred').startsWith('Credenciais inválidas'),
      messages.get('item-cred')
    );
    Assert.isTrue(
      messages.get('item-mfa').startsWith('Autenticação necessária'),
      messages.get('item-mfa')
    );
    Assert.isTrue(
      messages.get('item-site').startsWith('Instabilidade na Instituição'),
      messages.get('item-site')
    );
    Assert.isTrue(
      messages.get('item-unexp').startsWith('Erro Inesperado'),
      messages.get('item-unexp')
    );
    Assert.isTrue(
      messages.get('item-rawcred').startsWith('Credenciais inválidas'),
      messages.get('item-rawcred')
    );
    Assert.areEqual('Some raw message', messages.get('item-raw'));
    Assert.areEqual('Plain string error', messages.get('item-str'));
    Assert.isNotNull(
      messages.get('item-nomsg'),
      'Unknown error node is stringified'
    );
    Assert.areEqual(
      'Falha HTTP 500 ao consultar /items.',
      messages.get('item-http')
    );
    Assert.isTrue(
      messages.get('item-down').startsWith('Erro de conexão'),
      messages.get('item-down')
    );
    Assert.isNull(
      messages.get(AXF_CLS_PluggyTestFactory.ITEM_ID),
      'OUTDATED item without error'
    );
    Assert.areEqual(
      0,
      mock.callsTo('/accounts'),
      'Related data only fetched for UPDATED items'
    );
  }

  @IsTest
  static void emptyConnectionListDoesNothing() {
    AXF_CLS_PluggyTestFactory.MockRouter mock = AXF_CLS_PluggyTestFactory.itemSyncMock();
    Test.setMock(HttpCalloutMock.class, mock);
    System.runAs(AXF_CLS_PluggyTestFactory.getTestUser()) {
      Test.startTest();
      new AXF_CLS_PluggyItemSyncQueueable(
          new List<AXF_OBJ_PluggyConnection__c>()
        )
        .execute(null);
      Test.stopTest();
    }
    Assert.areEqual(0, mock.endpoints.size());
  }
}
