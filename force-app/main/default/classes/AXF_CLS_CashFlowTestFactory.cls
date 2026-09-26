/**
 * @description Test data factory for the Cash Flow domain (home dashboard, settlement,
 * reconciliation and KPI tests). Creates a Standard User with AXF_PS_User plus a test-only
 * permission set that grants field-level security on every permissionable custom field of the
 * Cash Flow domain objects, so USER_MODE queries/DML can be exercised deterministically.
 */
@IsTest
public class AXF_CLS_CashFlowTestFactory {
  public static final String TEST_USER_LAST_NAME = 'AxfCashFlowTestUser';
  private static final String TEST_PERMISSION_SET = 'AXF_TEST_CashFlowDomainFls';
  private static final List<Schema.SObjectType> DOMAIN_OBJECTS = new List<Schema.SObjectType>{
    AXF_OBJ_CashFlow__c.SObjectType,
    AXF_OBJ_InstallmentGroup__c.SObjectType,
    AXF_OBJ_BankAccountTransaction__c.SObjectType,
    AXF_OBJ_CreditCardTransaction__c.SObjectType,
    AXF_OBJ_BankAccount__c.SObjectType,
    AXF_OBJ_CreditCard__c.SObjectType,
    AXF_OBJ_Category__c.SObjectType
  };

  /**
   * @description Creates the domain test user (setup objects only). Call from @TestSetup
   * before any non-setup DML, and insert business data inside System.runAs(user).
   */
  public static User createDomainUser() {
    PermissionSet fls = new PermissionSet(
      Name = TEST_PERMISSION_SET,
      Label = TEST_PERMISSION_SET
    );
    insert fls;

    List<FieldPermissions> fieldPermissions = new List<FieldPermissions>();
    for (Schema.SObjectType objectType : DOMAIN_OBJECTS) {
      String objectName = objectType.getDescribe().getName();
      for (
        Schema.SObjectField field : objectType.getDescribe()
          .fields.getMap()
          .values()
      ) {
        Schema.DescribeFieldResult describe = field.getDescribe();
        if (!describe.isCustom() || !describe.isPermissionable()) {
          continue;
        }
        fieldPermissions.add(
          new FieldPermissions(
            ParentId = fls.Id,
            SobjectType = objectName,
            Field = objectName + '.' + describe.getName(),
            PermissionsRead = true,
            PermissionsEdit = !describe.isCalculated() &&
              !describe.isAutoNumber()
          )
        );
      }
    }
    insert fieldPermissions;

    Profile standardProfile = [
      SELECT Id
      FROM Profile
      WHERE Name IN ('Standard User', 'Usuário Padrão')
      LIMIT 1
    ];
    String unique = String.valueOf(Crypto.getRandomInteger()).remove('-');
    User testUser = new User(
      ProfileId = standardProfile.Id,
      LastName = TEST_USER_LAST_NAME,
      Email = 'axf.cashflow.test@example.com',
      Username = 'axf.cashflow.' + unique + '@example.com.axftest',
      Alias = 'axfcf',
      TimeZoneSidKey = 'America/Sao_Paulo',
      LocaleSidKey = 'pt_BR',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    insert testUser;

    PermissionSet userPermissionSet = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'AXF_PS_User'
      LIMIT 1
    ];
    insert new List<PermissionSetAssignment>{
      new PermissionSetAssignment(
        AssigneeId = testUser.Id,
        PermissionSetId = userPermissionSet.Id
      ),
      new PermissionSetAssignment(
        AssigneeId = testUser.Id,
        PermissionSetId = fls.Id
      )
    };
    return testUser;
  }

  public static User getDomainUser() {
    return [
      SELECT Id
      FROM User
      WHERE LastName = :TEST_USER_LAST_NAME
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
  }

  public static Id cashFlowRecordTypeId(Boolean expense) {
    return Schema.SObjectType.AXF_OBJ_CashFlow__c.getRecordTypeInfosByDeveloperName()
      .get(expense ? 'AXF_CF_RT_Expense' : 'AXF_CF_RT_Revenue')
      .getRecordTypeId();
  }

  public static Account createAccount(String name) {
    Account record = new Account(Name = name);
    Schema.RecordTypeInfo businessType = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get('AXF_Business');
    if (businessType != null) {
      record.RecordTypeId = businessType.getRecordTypeId();
    }
    insert record;
    return record;
  }

  public static AXF_OBJ_Category__c createCategory(
    String name,
    Boolean expense
  ) {
    AXF_OBJ_Category__c record = new AXF_OBJ_Category__c(
      Name = name,
      RecordTypeId = Schema.SObjectType.AXF_OBJ_Category__c.getRecordTypeInfosByDeveloperName()
        .get(expense ? 'AXF_CAT_RT_Expense' : 'AXF_CAT_RT_Revenue')
        .getRecordTypeId()
    );
    insert record;
    return record;
  }

  public static AXF_OBJ_BankAccount__c createBankAccount(
    Id accountId,
    String externalId,
    Decimal balance
  ) {
    AXF_OBJ_BankAccount__c record = new AXF_OBJ_BankAccount__c(
      Name = 'Conta ' + externalId,
      AXF_BA_LKP_Account__c = accountId,
      AXF_BA_EXI_PluggyAccountId__c = externalId,
      AXF_BA_CUR_Balance__c = balance
    );
    insert record;
    return record;
  }

  public static AXF_OBJ_CreditCard__c createCreditCard(
    Id accountId,
    String externalId
  ) {
    AXF_OBJ_CreditCard__c record = new AXF_OBJ_CreditCard__c(
      Name = 'Cartao ' + externalId,
      AXF_CC_LKP_Account__c = accountId,
      AXF_CC_EXI_PluggyCreditCardId__c = externalId
    );
    insert record;
    return record;
  }

  public static AXF_OBJ_CashFlow__c buildCashFlow(
    Boolean expense,
    Id accountId,
    String name,
    Decimal value,
    Date dueDate,
    String status
  ) {
    return new AXF_OBJ_CashFlow__c(
      RecordTypeId = cashFlowRecordTypeId(expense),
      Name = name,
      AXF_CF_LKP_Account__c = accountId,
      AXF_CF_CUR_Value__c = value,
      AXF_CF_DAT_DueDate__c = dueDate,
      AXF_CF_DAT_PurchaseDate__c = dueDate,
      AXF_CF_PKL_Status__c = status,
      AXF_CF_PKL_PaymentMode__c = 'A_VISTA',
      AXF_CF_PKL_PaymentMethod__c = 'BOLETO'
    );
  }

  public static AXF_OBJ_BankAccountTransaction__c buildBankTransaction(
    Id bankAccountId,
    String externalId,
    Decimal amount,
    Date transactionDate,
    String description
  ) {
    return new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_LKP_BankAccount__c = bankAccountId,
      AXF_BAT_EXI_PluggyTransactionId__c = externalId,
      AXF_BAT_CUR_Amount__c = amount,
      AXF_BAT_DAT_Date__c = Datetime.newInstance(
        transactionDate,
        Time.newInstance(12, 0, 0, 0)
      ),
      AXF_BAT_TXT_Description__c = description
    );
  }

  public static AXF_OBJ_CreditCardTransaction__c buildCardTransaction(
    Id creditCardId,
    String externalId,
    Decimal amount,
    Date transactionDate,
    String description
  ) {
    return new AXF_OBJ_CreditCardTransaction__c(
      AXF_CCT_LKP_CreditCard__c = creditCardId,
      AXF_CCT_EXI_PluggyTransactionId__c = externalId,
      AXF_CCT_CUR_Amount__c = amount,
      AXF_CCT_DAT_Date__c = Datetime.newInstance(
        transactionDate,
        Time.newInstance(12, 0, 0, 0)
      ),
      AXF_CCT_TXT_Description__c = description
    );
  }
}
