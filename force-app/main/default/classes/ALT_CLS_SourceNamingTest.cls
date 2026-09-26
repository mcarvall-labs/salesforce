/**
 * @description Standardized bank account / credit card names (production parity): holder and
 * institution in upper case, codes and diacritics removed, bulk insert and rename on update.
 */
@IsTest
private class ALT_CLS_SourceNamingTest {
  private static Account holder(String name) {
    Account result = new Account(
      Name = name,
      RecordTypeId = Account.SObjectType.getDescribe()
        .getRecordTypeInfosByDeveloperName()
        .get('AXF_Business')
        .getRecordTypeId()
    );
    insert result;
    return result;
  }

  @IsTest
  static void namesBankAccountsInBulkFromHolderAndInstitution() {
    Account owner = holder('Michel Lopes');
    AXF_OBJ_BankInstitution__c institution = new AXF_OBJ_BankInstitution__c(
      Name = 'Itaú Unibanco (341)',
      AXF_BI_EXI_Bank_Number__c = '341'
    );
    insert institution;
    List<AXF_OBJ_BankAccount__c> accounts = new List<AXF_OBJ_BankAccount__c>();
    for (Integer i = 0; i < 200; i++) {
      accounts.add(
        new AXF_OBJ_BankAccount__c(
          AXF_BA_LKP_Account__c = owner.Id,
          AXF_BA_LKP_BankInstitution__c = institution.Id,
          AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
          AXF_BA_EXI_ManualKey__c = 'naming-' + i
        )
      );
    }
    Test.startTest();
    insert accounts;
    Test.stopTest();
    for (AXF_OBJ_BankAccount__c row : [
      SELECT Name
      FROM AXF_OBJ_BankAccount__c
      WHERE Id IN :accounts
    ]) {
      Assert.areEqual('MICHEL LOPES - ITAU UNIBANCO', row.Name);
    }
  }

  @IsTest
  static void renamesCreditCardWhenInstitutionTextChanges() {
    Account owner = holder('Gisele Lopes');
    AXF_OBJ_CreditCard__c card = new AXF_OBJ_CreditCard__c(
      AXF_CC_LKP_Account__c = owner.Id,
      AXF_CC_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_CC_EXI_ManualKey__c = 'naming-card'
    );
    insert card;
    Assert.areEqual(
      'GISELE LOPES',
      [SELECT Name FROM AXF_OBJ_CreditCard__c WHERE Id = :card.Id].Name
    );
    card.AXF_CC_TXT_InstitutionName__c = 'Nubank';
    Test.startTest();
    update card;
    Test.stopTest();
    Assert.areEqual(
      'GISELE LOPES - NUBANK',
      [SELECT Name FROM AXF_OBJ_CreditCard__c WHERE Id = :card.Id].Name
    );
  }

  @IsTest
  static void fallsBackWhenHolderAndInstitutionAreMissing() {
    Assert.areEqual(
      'SICOOB',
      ALT_CLS_SourceNaming.standardizedName(null, ' Sicoob (756) ', 'x')
    );
    Assert.areEqual(
      'LEGACY NAME',
      ALT_CLS_SourceNaming.standardizedName(' ', null, 'legacy name')
    );
    Assert.isNull(ALT_CLS_SourceNaming.standardizedName(null, null, null));
  }
}
