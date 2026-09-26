/**
 * @description Test data factory for the accounts/cards/statements/categories/financing tests.
 * Creates a Standard User with AXF_PS_User and, optionally, a test-only permission set granting
 * field-level security on every permissionable custom field of the financial objects (AXF_PS_User
 * does not grant FLS on several fields read in USER_MODE by the financing services).
 */
@IsTest
public class AXF_CLS_AccountCardTestFactory {
  private static final String LAST_NAME_PREFIX = 'AxfAcctCardTest_';
  private static final List<Schema.SObjectType> FINANCIAL_OBJECTS = new List<Schema.SObjectType>{
    AXF_OBJ_CashFlow__c.SObjectType,
    AXF_OBJ_InstallmentGroup__c.SObjectType,
    AXF_OBJ_BankAccountTransaction__c.SObjectType,
    AXF_OBJ_CreditCardTransaction__c.SObjectType,
    AXF_OBJ_CreditCardInvoice__c.SObjectType,
    AXF_OBJ_BankAccount__c.SObjectType,
    AXF_OBJ_CreditCard__c.SObjectType,
    AXF_OBJ_BankInstitution__c.SObjectType,
    AXF_OBJ_Category__c.SObjectType
  };

  /**
   * @description Creates a test user (setup DML only, run as the current user to avoid mixed
   * DML). Business data must be inserted afterwards.
   */
  public static User createUser(String key, Boolean grantFullFieldAccess) {
    User testUser;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Profile standardProfile = [
        SELECT Id
        FROM Profile
        WHERE Name IN ('Standard User', 'Usuário Padrão')
        LIMIT 1
      ];
      String unique = String.valueOf(Crypto.getRandomInteger()).remove('-');
      testUser = new User(
        ProfileId = standardProfile.Id,
        LastName = LAST_NAME_PREFIX + key,
        Email = 'axf.acctcard.' + key + '@example.com',
        Username = 'axf.acctcard.' +
          key +
          '.' +
          unique +
          '@example.com.axftest',
        Alias = ('ac' + key).left(8),
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
      List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>{
        new PermissionSetAssignment(
          AssigneeId = testUser.Id,
          PermissionSetId = userPermissionSet.Id
        )
      };
      if (grantFullFieldAccess) {
        assignments.add(
          new PermissionSetAssignment(
            AssigneeId = testUser.Id,
            PermissionSetId = createFullFlsPermissionSet(key)
          )
        );
      }
      insert assignments;
    }
    return testUser;
  }

  public static User getUser(String key) {
    String lastName = LAST_NAME_PREFIX + key;
    return [
      SELECT Id
      FROM User
      WHERE LastName = :lastName
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
  }

  private static Id createFullFlsPermissionSet(String key) {
    String name = ('AXF_TEST_AcctCardFls_' + key).left(80);
    PermissionSet fls = new PermissionSet(Name = name, Label = name);
    insert fls;

    List<FieldPermissions> fieldPermissions = new List<FieldPermissions>();
    for (Schema.SObjectType objectType : FINANCIAL_OBJECTS) {
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
    return fls.Id;
  }

  public static Account newAccount(String name) {
    Account acc = new Account(Name = name);
    Schema.RecordTypeInfo businessRt = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get('AXF_Business');
    if (businessRt != null) {
      acc.RecordTypeId = businessRt.getRecordTypeId();
    }
    return acc;
  }

  public static AXF_OBJ_BankInstitution__c newInstitution(
    String bankName,
    String bankNumber
  ) {
    return new AXF_OBJ_BankInstitution__c(
      Name = bankName,
      AXF_BI_PKL_BankName__c = bankName,
      AXF_BI_EXI_Bank_Number__c = bankNumber
    );
  }

  public static AXF_OBJ_BankAccount__c newBankAccount(
    String name,
    Id accountId,
    Id institutionId,
    String pluggyId
  ) {
    return new AXF_OBJ_BankAccount__c(
      Name = name,
      AXF_BA_LKP_Account__c = accountId,
      AXF_BA_LKP_BankInstitution__c = institutionId,
      AXF_BA_EXI_PluggyAccountId__c = pluggyId
    );
  }

  public static AXF_OBJ_CreditCard__c newCreditCard(
    String name,
    Id accountId,
    Id institutionId,
    String pluggyId,
    String lastFourDigits
  ) {
    return new AXF_OBJ_CreditCard__c(
      Name = name,
      AXF_CC_LKP_Account__c = accountId,
      AXF_CC_LKP_BankInstitution__c = institutionId,
      AXF_CC_EXI_PluggyCreditCardId__c = pluggyId,
      AXF_CC_TXT_LastFourDigits__c = lastFourDigits
    );
  }

  public static AXF_OBJ_Category__c newCategory(
    String name,
    String recordTypeDeveloperName,
    Id parentId
  ) {
    return new AXF_OBJ_Category__c(
      Name = name,
      RecordTypeId = Schema.SObjectType.AXF_OBJ_Category__c.getRecordTypeInfosByDeveloperName()
        .get(recordTypeDeveloperName)
        .getRecordTypeId(),
      AXF_CAT_LKP_Parent__c = parentId
    );
  }

  public static Datetime middayOf(Date day) {
    return Datetime.newInstance(day, Time.newInstance(12, 0, 0, 0));
  }
}
