/**
 * @description Shared test helper for the legacy Pluggy integration tests: test user with
 * AXF_PS_User, record builders and a multi-route HttpCalloutMock returning Pluggy-shaped JSON.
 */
@IsTest
public class AXF_CLS_PluggyTestFactory {
  public static final String TEST_USER_LAST_NAME = 'AXFPluggyTester';
  public static final String API_KEY = 'test-api-key';
  public static final String ITEM_ID = 'item-001';
  public static final String BANK_PLUGGY_ID = 'acc-bank-001';
  public static final String CARD_PLUGGY_ID = 'acc-card-001';
  public static final String CPF = '123.456.789-09';
  public static final String BANK_NUMBER = '001';

  // ---------------------------------------------------------------- users

  public static User createTestUser() {
    Profile p = [
      SELECT Id
      FROM Profile
      WHERE Name IN ('Standard User', 'Usuário Padrão', 'Usuario Padrao')
      LIMIT 1
    ];
    String unique =
      String.valueOf(Crypto.getRandomInteger()).replace('-', '') +
      System.now().getTime();
    User u = new User(
      LastName = TEST_USER_LAST_NAME,
      FirstName = 'Pluggy',
      Alias = 'plgtst',
      Email = 'axf.pluggy.tester@example.com',
      Username = 'axf.pluggy.' + unique + '@example.com.axon',
      ProfileId = p.Id,
      TimeZoneSidKey = 'America/Sao_Paulo',
      LocaleSidKey = 'pt_BR',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    insert u;
    PermissionSet ps = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'AXF_PS_User'
      LIMIT 1
    ];
    insert new List<PermissionSetAssignment>{
      new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id),
      new PermissionSetAssignment(
        AssigneeId = u.Id,
        PermissionSetId = createSyncStampFlsPermissionSet().Id
      )
    };
    return u;
  }

  /**
   * @description Test-only permission set mirroring the LastTransactionSync FLS that AXF_PS_User
   * declares in source. Keeps the tests independent of permission-set drift in the target org
   * (API 67 classes enforce FLS on their static SOQL under System.runAs).
   */
  private static PermissionSet createSyncStampFlsPermissionSet() {
    PermissionSet ps = new PermissionSet(
      Name = 'AXF_Test_PluggySyncStampFls',
      Label = 'AXF Test Pluggy Sync Stamp FLS'
    );
    insert ps;
    insert new List<FieldPermissions>{
      new FieldPermissions(
        ParentId = ps.Id,
        SobjectType = 'AXF_OBJ_BankAccount__c',
        Field = 'AXF_OBJ_BankAccount__c.AXF_BA_DT_LastTransactionSync__c',
        PermissionsRead = true,
        PermissionsEdit = true
      ),
      new FieldPermissions(
        ParentId = ps.Id,
        SobjectType = 'AXF_OBJ_CreditCard__c',
        Field = 'AXF_OBJ_CreditCard__c.AXF_CC_DT_LastTransactionSync__c',
        PermissionsRead = true,
        PermissionsEdit = true
      )
    };
    return ps;
  }

  public static User getTestUser() {
    return [
      SELECT Id
      FROM User
      WHERE LastName = :TEST_USER_LAST_NAME AND IsActive = TRUE
      LIMIT 1
    ];
  }

  // ---------------------------------------------------------------- records

  public static Account createHolder(String name, String cpf) {
    Account acc = new Account(Name = name, AXF_ACC_EXI_CPF__c = cpf);
    insert acc;
    return acc;
  }

  public static AXF_OBJ_BankInstitution__c createInstitution(
    String name,
    String bankNumber
  ) {
    AXF_OBJ_BankInstitution__c inst = new AXF_OBJ_BankInstitution__c(
      Name = name,
      AXF_BI_EXI_Bank_Number__c = bankNumber
    );
    insert inst;
    return inst;
  }

  public static AXF_OBJ_PluggyConnection__c createConnection(
    Id institutionId,
    String itemId
  ) {
    AXF_OBJ_PluggyConnection__c conn = new AXF_OBJ_PluggyConnection__c(
      Name = 'Conn ' + itemId,
      AXF_CON_LKP_BankInstitution__c = institutionId,
      AXF_CON_EXI_PluggyItemId__c = itemId
    );
    insert conn;
    return conn;
  }

  public static AXF_OBJ_BankAccount__c createBankAccount(
    Id connectionId,
    Id holderId,
    String pluggyId
  ) {
    AXF_OBJ_BankAccount__c ba = new AXF_OBJ_BankAccount__c(
      Name = 'Bank ' + pluggyId,
      AXF_BA_LKP_PluggyConnection__c = connectionId,
      AXF_BA_LKP_Account__c = holderId,
      AXF_BA_EXI_PluggyAccountId__c = pluggyId
    );
    insert ba;
    return ba;
  }

  public static AXF_OBJ_CreditCard__c createCreditCard(
    Id connectionId,
    String pluggyId,
    String lastFour
  ) {
    AXF_OBJ_CreditCard__c card = new AXF_OBJ_CreditCard__c(
      Name = 'Card ' + pluggyId,
      AXF_CC_LKP_PluggyConnection__c = connectionId,
      AXF_CC_EXI_PluggyCreditCardId__c = pluggyId,
      AXF_CC_TXT_LastFourDigits__c = lastFour
    );
    insert card;
    return card;
  }

  public static AXF_OBJ_CreditCardInvoice__c createInvoice(
    Id cardId,
    String pluggyInvoiceId,
    String externalId
  ) {
    AXF_OBJ_CreditCardInvoice__c inv = new AXF_OBJ_CreditCardInvoice__c(
      Name = 'Invoice ' + pluggyInvoiceId,
      AXF_CCI_MD_CreditCard__c = cardId,
      AXF_CCI_EXI_PluggyInvoiceId__c = pluggyInvoiceId,
      AXF_CCI_EXT_ExternalId__c = externalId
    );
    insert inv;
    return inv;
  }

  /**
   * @description Standard data set: holder with CPF, institution 001, connection ITEM_ID,
   * a bank account BANK_PLUGGY_ID and a credit card CARD_PLUGGY_ID (last four 1234).
   */
  public static void createStandardData() {
    Account holder = createHolder('Joao Silva', CPF);
    AXF_OBJ_BankInstitution__c inst = createInstitution(
      'Banco do Brasil (001)',
      BANK_NUMBER
    );
    AXF_OBJ_PluggyConnection__c conn = createConnection(inst.Id, ITEM_ID);
    createBankAccount(conn.Id, holder.Id, BANK_PLUGGY_ID);
    createCreditCard(conn.Id, CARD_PLUGGY_ID, '1234');
  }

  // ---------------------------------------------------------------- JSON payloads

  public static String authBody() {
    return JSON.serialize(new Map<String, Object>{ 'apiKey' => API_KEY });
  }

  public static String itemBody(String status, Object error) {
    return JSON.serialize(
      new Map<String, Object>{
        'id' => ITEM_ID,
        'status' => status,
        'executionStatus' => 'SUCCESS',
        'lastUpdatedAt' => '2026-09-20T10:00:00.000Z',
        'error' => error
      }
    );
  }

  public static Map<String, Object> bankAccountJson(
    String id,
    String taxNumber,
    Map<String, Object> bankData
  ) {
    return new Map<String, Object>{
      'id' => id,
      'type' => 'BANK',
      'subtype' => 'CHECKING_ACCOUNT',
      'number' => '12345-6',
      'balance' => 1500.50,
      'currency' => 'BRL',
      'taxNumber' => taxNumber,
      'updatedAt' => '2026-09-20T10:00:00.000Z',
      'bankData' => bankData
    };
  }

  public static Map<String, Object> creditCardJson(
    String id,
    String taxNumber,
    String transferNumber
  ) {
    return new Map<String, Object>{
      'id' => id,
      'type' => 'CREDIT',
      'subtype' => 'CREDIT_CARD',
      'name' => 'Ourocard Visa',
      'number' => '**** **** **** 1234',
      'taxNumber' => taxNumber,
      'updatedAt' => '2026-09-20T10:00:00.000Z',
      'bankData' => transferNumber == null
        ? null
        : new Map<String, Object>{ 'transferNumber' => transferNumber },
      'creditData' => new Map<String, Object>{
        'availableCreditLimit' => 4000.25,
        'creditLimit' => 10000.00,
        'brand' => 'VISA',
        'level' => 'GOLD',
        'balanceCloseDate' => '2026-09-05T00:00:00.000Z',
        'balanceDueDate' => '2026-09-15T00:00:00.000Z'
      }
    };
  }

  public static String accountsBody(List<Object> results) {
    return JSON.serialize(
      new Map<String, Object>{ 'total' => results.size(), 'results' => results }
    );
  }

  /** @description Default /accounts payload: one bank account and one credit card for the standard data. */
  public static String defaultAccountsBody() {
    return accountsBody(
      new List<Object>{
        bankAccountJson(
          BANK_PLUGGY_ID,
          CPF,
          new Map<String, Object>{
            'transferNumber' => '001/1234/12345-6',
            'agencyNumber' => '1234'
          }
        ),
        creditCardJson(CARD_PLUGGY_ID, null, '001')
      }
    );
  }

  public static String investmentsBody() {
    return JSON.serialize(
      new Map<String, Object>{
        'results' => new List<Object>{
          new Map<String, Object>{
            'id' => 'inv-001',
            'type' => 'FIXED_INCOME',
            'currencyCode' => 'BRL',
            'balance' => 2500.75,
            'name' => 'CDB Banco do Brasil'
          },
          new Map<String, Object>{
            'id' => 'inv-002',
            'type' => 'MUTUAL_FUND',
            'currencyCode' => 'BRL',
            'balance' => null
          }
        }
      }
    );
  }

  public static String loansBody() {
    return JSON.serialize(
      new Map<String, Object>{
        'results' => new List<Object>{
          new Map<String, Object>{
            'id' => 'loan-001',
            'type' => 'LOAN',
            'contractedAmount' => 10000.00,
            'outstandingBalance' => 6500.50,
            'interestRate' => 1.99,
            'totalInstallments' => 48.0,
            'paidInstallments' => 12.0
          }
        }
      }
    );
  }

  public static String billsBody() {
    return JSON.serialize(
      new Map<String, Object>{
        'results' => new List<Object>{
          new Map<String, Object>{
            'id' => 'bill-001',
            'dueDate' => '2026-09-15T00:00:00.000Z',
            'billClosingDate' => '2026-09-08T00:00:00.000Z',
            'totalAmount' => 850.40
          },
          new Map<String, Object>{
            'id' => 'bill-002',
            'dueDate' => '2026-10-15T00:00:00.000Z',
            'billClosingDate' => null,
            'totalAmount' => null
          }
        }
      }
    );
  }

  public static Map<String, Object> txJson(
    String id,
    String accountId,
    Decimal amount,
    String billId
  ) {
    Map<String, Object> tx = new Map<String, Object>{
      'id' => id,
      'accountId' => accountId,
      'amount' => amount,
      'description' => 'Compra ' + id,
      'date' => '2026-09-15T12:00:00.000Z',
      'categoryId' => '01000000'
    };
    if (billId != null) {
      tx.put(
        'creditCardMetadata',
        new Map<String, Object>{ 'billId' => billId }
      );
    }
    return tx;
  }

  public static String txBody(List<Object> results, String nextCursor) {
    return JSON.serialize(
      new Map<String, Object>{ 'results' => results, 'next' => nextCursor }
    );
  }

  public static String balanceBody(Decimal balance) {
    return JSON.serialize(
      new Map<String, Object>{
        'id' => BANK_PLUGGY_ID,
        'balance' => balance,
        'currency' => 'BRL',
        'updatedAt' => '2026-09-20T10:00:00.000Z'
      }
    );
  }

  /** @description Mock with successful /auth, /items (UPDATED), /accounts, /investments and /loans routes. */
  public static MockRouter itemSyncMock() {
    return new MockRouter()
      .route('/auth', 200, authBody())
      .route('/items/', 200, itemBody('UPDATED', null))
      .route('/accounts?itemId=', 200, defaultAccountsBody())
      .route('/investments?itemId=', 200, investmentsBody())
      .route('/loans?itemId=', 200, loansBody());
  }

  // ---------------------------------------------------------------- HTTP mock

  public class Route {
    public String fragment;
    public Integer status;
    public String body;
    public Map<String, String> headers = new Map<String, String>();
    public Boolean throwError = false;
    // Remaining uses before the route is skipped; null means unlimited.
    public Integer remaining;
  }

  /**
   * @description Multi-route HttpCalloutMock. The first route whose fragment is contained in the
   * request endpoint wins, so register more specific fragments first. Unmatched requests get 404.
   */
  public class MockRouter implements HttpCalloutMock {
    public List<Route> routes = new List<Route>();
    public List<String> endpoints = new List<String>();

    public MockRouter route(String fragment, Integer status, String body) {
      Route r = new Route();
      r.fragment = fragment;
      r.status = status;
      r.body = body;
      routes.add(r);
      return this;
    }

    public MockRouter onWithHeader(
      String fragment,
      Integer status,
      String body,
      String header,
      String value
    ) {
      route(fragment, status, body);
      routes[routes.size() - 1].headers.put(header, value);
      return this;
    }

    /** @description Route answered only once; later matching requests fall through to the next routes. */
    public MockRouter routeOnce(String fragment, Integer status, String body) {
      route(fragment, status, body);
      routes[routes.size() - 1].remaining = 1;
      return this;
    }

    public MockRouter onThrow(String fragment) {
      route(fragment, 0, null);
      routes[routes.size() - 1].throwError = true;
      return this;
    }

    public Integer callsTo(String fragment) {
      Integer n = 0;
      for (String e : endpoints) {
        if (e.contains(fragment)) {
          n++;
        }
      }
      return n;
    }

    public HttpResponse respond(HttpRequest req) {
      String endpoint = req.getEndpoint();
      endpoints.add(endpoint);
      HttpResponse res = new HttpResponse();
      for (Route r : routes) {
        if (endpoint.contains(r.fragment) && r.remaining != 0) {
          if (r.remaining != null) {
            r.remaining--;
          }
          if (r.throwError) {
            throw new CalloutException('Simulated connection failure');
          }
          res.setStatusCode(r.status);
          res.setBody(r.body == null ? '' : r.body);
          for (String h : r.headers.keySet()) {
            res.setHeader(h, r.headers.get(h));
          }
          return res;
        }
      }
      res.setStatusCode(404);
      res.setBody('{"message":"not found"}');
      return res;
    }
  }
}
