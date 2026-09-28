/**
 * @description Test data for the wizard source steps over the legacy PROD model
 * (AXF_CLS_CTRL_SourceDiscovery, AXF_CLS_CTRL_SourceHolderConfirmation,
 * AXF_CLS_CTRL_ManualFinancialSource). Users get AXF_PS_User; the configurer also gets a
 * test-only permission set granting the AXF_CanConfigure custom permission.
 */
@IsTest
public class AXF_CLS_SourceSetupTestFactory {
  public static final String CONFIGURER = 'AXFSrcConfigurer';
  public static final String READER = 'AXFSrcReader';
  public static final String BANK_NUMBER = '9901';

  /** @description Creates the configurer and the reader (setup DML, isolated). */
  public static void createUsers() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Profile p = [
        SELECT Id
        FROM Profile
        WHERE Name IN ('Standard User', 'Usuário Padrão')
        LIMIT 1
      ];
      User configurer = newUser(p.Id, CONFIGURER);
      User reader = newUser(p.Id, READER);
      insert new List<User>{ configurer, reader };

      Id userPs = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = 'AXF_PS_User'
        LIMIT 1
      ]
      .Id;
      PermissionSet cfg = new PermissionSet(
        Name = 'AXF_TEST_SrcCanConfigure',
        Label = 'AXF TEST Src CanConfigure'
      );
      insert cfg;
      insert new SetupEntityAccess(
        ParentId = cfg.Id,
        SetupEntityId = [
          SELECT Id
          FROM CustomPermission
          WHERE DeveloperName = 'AXF_CanConfigure'
          LIMIT 1
        ]
        .Id
      );
      insert new List<PermissionSetAssignment>{
        new PermissionSetAssignment(
          AssigneeId = configurer.Id,
          PermissionSetId = userPs
        ),
        new PermissionSetAssignment(
          AssigneeId = configurer.Id,
          PermissionSetId = cfg.Id
        ),
        new PermissionSetAssignment(
          AssigneeId = reader.Id,
          PermissionSetId = userPs
        )
      };
    }
  }

  public static User user(String lastName) {
    return [
      SELECT Id
      FROM User
      WHERE LastName = :lastName AND Email = 'axf.source.setup@example.com'
      LIMIT 1
    ];
  }

  public static Account holder(Id ownerId, String name) {
    Account a = new Account(
      Name = name,
      OwnerId = ownerId,
      RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
        .get('AXF_Business')
        .getRecordTypeId()
    );
    insert a;
    return a;
  }

  public static AXF_OBJ_BankInstitution__c institution(
    Id ownerId,
    String name,
    String bankNumber
  ) {
    AXF_OBJ_BankInstitution__c bi = new AXF_OBJ_BankInstitution__c(
      Name = name,
      OwnerId = ownerId,
      AXF_BI_EXI_Bank_Number__c = bankNumber
    );
    insert bi;
    return bi;
  }

  public static AXF_OBJ_PluggyConnection__c connection(
    Id bankId,
    String itemId,
    String syncStatus
  ) {
    AXF_OBJ_PluggyConnection__c c = new AXF_OBJ_PluggyConnection__c(
      Name = 'Conn ' + itemId,
      AXF_CON_EXI_PluggyItemId__c = itemId,
      AXF_CON_LKP_BankInstitution__c = bankId,
      AXF_CON_TXT_SyncStatus__c = syncStatus
    );
    insert c;
    return c;
  }

  public static AXF_OBJ_BankAccount__c bankAccount(
    Id ownerId,
    Id connectionId,
    Id bankId,
    Id holderId,
    String externalId
  ) {
    AXF_OBJ_BankAccount__c ba = new AXF_OBJ_BankAccount__c(
      OwnerId = ownerId,
      AXF_BA_EXI_PluggyAccountId__c = externalId,
      AXF_BA_LKP_PluggyConnection__c = connectionId,
      AXF_BA_LKP_BankInstitution__c = bankId,
      AXF_BA_LKP_Account__c = holderId,
      AXF_BA_PKL_Currency__c = 'BRL',
      AXF_BA_TXT_AccountNumber__c = '12345-6'
    );
    insert ba;
    return ba;
  }

  public static AXF_OBJ_CreditCard__c creditCard(
    Id ownerId,
    Id connectionId,
    Id bankId,
    Id holderId,
    String externalId
  ) {
    AXF_OBJ_CreditCard__c cc = new AXF_OBJ_CreditCard__c(
      OwnerId = ownerId,
      AXF_CC_EXI_PluggyCreditCardId__c = externalId,
      AXF_CC_LKP_PluggyConnection__c = connectionId,
      AXF_CC_LKP_BankInstitution__c = bankId,
      AXF_CC_LKP_Account__c = holderId,
      AXF_CC_TXT_LastFourDigits__c = '4321'
    );
    insert cc;
    return cc;
  }

  private static User newUser(Id profileId, String lastName) {
    String unique =
      lastName + String.valueOf(Math.abs(Crypto.getRandomInteger()));
    return new User(
      Alias = lastName.left(8),
      Email = 'axf.source.setup@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = lastName,
      LanguageLocaleKey = 'pt_BR',
      LocaleSidKey = 'pt_BR',
      ProfileId = profileId,
      TimeZoneSidKey = 'America/Sao_Paulo',
      Username = unique.toLowerCase() + '@axf-source-setup.test'
    );
  }

  /**
   * @description Pluggy API double for the legacy item sync: auth, item, accounts (one
   * bank account + one credit card), and empty investments/loans.
   */
  public class PluggyMock implements HttpCalloutMock {
    public String itemStatus = 'UPDATED';
    public String bankAccountId = 'src-bank-001';
    public String cardId = 'src-card-001';

    public HttpResponse respond(HttpRequest req) {
      String endpoint = req.getEndpoint();
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      res.setHeader('Content-Type', 'application/json');
      if (endpoint.contains('/auth')) {
        res.setBody('{"apiKey":"test-api-key"}');
      } else if (endpoint.contains('/items/')) {
        res.setBody(
          JSON.serialize(
            new Map<String, Object>{
              'status' => itemStatus,
              'executionStatus' => 'SUCCESS',
              'lastUpdatedAt' => '2026-09-26T10:00:00.000Z'
            }
          )
        );
      } else if (endpoint.contains('/accounts')) {
        res.setBody(
          JSON.serialize(
            new Map<String, Object>{
              'results' => new List<Object>{
                new Map<String, Object>{
                  'id' => bankAccountId,
                  'type' => 'BANK',
                  'subtype' => 'CHECKING_ACCOUNT',
                  'name' => 'Conta Corrente',
                  'number' => '0001/12345-6',
                  'balance' => 150.25,
                  'currency' => 'BRL',
                  'updatedAt' => '2026-09-26T10:00:00.000Z'
                },
                new Map<String, Object>{
                  'id' => cardId,
                  'type' => 'CREDIT',
                  'subtype' => 'CREDIT_CARD',
                  'name' => 'Cartão',
                  'number' => '5555666677778888',
                  'balance' => 10.5,
                  'currency' => 'BRL',
                  'updatedAt' => '2026-09-26T10:00:00.000Z',
                  'creditData' => new Map<String, Object>{
                    'brand' => 'VISA',
                    'level' => 'GOLD',
                    'creditLimit' => 5000.5,
                    'availableCreditLimit' => 4000.5
                  }
                }
              }
            }
          )
        );
      } else {
        res.setBody('{"results":[],"total":0,"totalPages":1,"page":1}');
      }
      return res;
    }
  }

  /**
   * @description Simulates Pluggy rejecting the configured Client ID/Secret
   * (HTTP 401 on /auth), the only case that should ever blame the credential.
   */
  public class PluggyAuthFailureMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(401);
      res.setHeader('Content-Type', 'application/json');
      res.setBody('{"message":"client keys are invalid"}');
      return res;
    }
  }
}
