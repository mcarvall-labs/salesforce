@IsTest
private class AXF_CLS_ContractValidationTest {
  private static Account holder(String name) {
    Account a = new Account(Name = name);
    insert a;
    return a;
  }

  private static AXF_OBJ_BankAccount__c bankAccount(Id holderId) {
    AXF_OBJ_BankAccount__c b = new AXF_OBJ_BankAccount__c(
      Name = 'Conta',
      AXF_BA_MD_Holder__c = holderId,
      AXF_BA_PKL_Institution__c = '341',
      AXF_BA_PKL_Type__c = 'Checking'
    );
    insert b;
    return b;
  }

  private static AXF_OBJ_CreditCard__c creditCard(Id holderId) {
    AXF_OBJ_CreditCard__c c = new AXF_OBJ_CreditCard__c(
      Name = 'Cartão',
      AXF_CC_MD_Holder__c = holderId,
      AXF_CC_PKL_Institution__c = '341'
    );
    insert c;
    return c;
  }

  private static AXF_OBJ_Contract__c contract(Id holderId, String recordType) {
    return new AXF_OBJ_Contract__c(
      Name = 'Contrato',
      AXF_CTR_MD_Holder__c = holderId,
      RecordTypeId = Schema.SObjectType.AXF_OBJ_Contract__c.getRecordTypeInfosByDeveloperName()
        .get(recordType)
        .getRecordTypeId(),
      AXF_CTR_PKL_Direction__c = 'Expense',
      AXF_CTR_PKL_Status__c = 'Active'
    );
  }

  private static void assertRejected(AXF_OBJ_Contract__c c, String expectedField) {
    Database.SaveResult result = Database.insert(c, false);
    System.assert(!result.isSuccess(), 'Expected the contract to be rejected');
    Database.Error err = result.getErrors()[0];
    System.assertEquals(
      StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION,
      err.getStatusCode()
    );
    System.assertEquals(
      expectedField,
      err.getFields()[0],
      'Error shown on the wrong field'
    );
  }

  @IsTest
  static void validContractOfEveryRecordTypeIsAccepted() {
    Account h = holder('Titular');
    List<AXF_OBJ_Contract__c> rows = new List<AXF_OBJ_Contract__c>();
    for (
      String rt : new List<String>{
        'AXF_Recurring',
        'AXF_Installment',
        'AXF_Consortium',
        'AXF_Financing',
        'AXF_ServiceProvision'
      }
    ) {
      rows.add(contract(h.Id, rt));
    }
    insert rows;
    for (AXF_OBJ_Contract__c c : rows) {
      System.assertNotEquals(null, c.Id);
    }
  }

  @IsTest
  static void ownBankAccountOrCardIsAccepted() {
    Account h = holder('Titular');
    AXF_OBJ_Contract__c a = contract(h.Id, 'AXF_Recurring');
    a.AXF_CTR_LKP_BankAccount__c = bankAccount(h.Id).Id;
    AXF_OBJ_Contract__c b = contract(h.Id, 'AXF_Installment');
    b.AXF_CTR_LKP_CreditCard__c = creditCard(h.Id).Id;
    insert new List<AXF_OBJ_Contract__c>{ a, b };
    System.assertNotEquals(null, a.Id);
    System.assertNotEquals(null, b.Id);
  }

  @IsTest
  static void bankAccountAndCardTogetherAreRejected() {
    Account h = holder('Titular');
    AXF_OBJ_Contract__c c = contract(h.Id, 'AXF_Recurring');
    c.AXF_CTR_LKP_BankAccount__c = bankAccount(h.Id).Id;
    c.AXF_CTR_LKP_CreditCard__c = creditCard(h.Id).Id;
    assertRejected(c, 'AXF_CTR_LKP_CreditCard__c');
  }

  @IsTest
  static void bankAccountOfAnotherHolderIsRejected() {
    Account h = holder('Titular');
    Account other = holder('Outro');
    AXF_OBJ_Contract__c c = contract(h.Id, 'AXF_Recurring');
    c.AXF_CTR_LKP_BankAccount__c = bankAccount(other.Id).Id;
    assertRejected(c, 'AXF_CTR_LKP_BankAccount__c');
  }

  @IsTest
  static void creditCardOfAnotherHolderIsRejected() {
    Account h = holder('Titular');
    Account other = holder('Outro');
    AXF_OBJ_Contract__c c = contract(h.Id, 'AXF_Installment');
    c.AXF_CTR_LKP_CreditCard__c = creditCard(other.Id).Id;
    assertRejected(c, 'AXF_CTR_LKP_CreditCard__c');
  }

  @IsTest
  static void dueDayOutsideOneToThirtyOneIsRejected() {
    Account h = holder('Titular');
    for (Integer day : new List<Integer>{ 0, 32 }) {
      AXF_OBJ_Contract__c c = contract(h.Id, 'AXF_Recurring');
      c.AXF_CTR_NUM_DueDay__c = day;
      assertRejected(c, 'AXF_CTR_NUM_DueDay__c');
    }
  }

  @IsTest
  static void dueDayBoundsAreAccepted() {
    Account h = holder('Titular');
    AXF_OBJ_Contract__c first = contract(h.Id, 'AXF_Recurring');
    first.AXF_CTR_NUM_DueDay__c = 1;
    AXF_OBJ_Contract__c last = contract(h.Id, 'AXF_Recurring');
    last.AXF_CTR_NUM_DueDay__c = 31;
    insert new List<AXF_OBJ_Contract__c>{ first, last };
    System.assertNotEquals(null, first.Id);
    System.assertNotEquals(null, last.Id);
  }

  @IsTest
  static void directionDefaultsFollowTheRecordType() {
    Schema.DescribeFieldResult f = AXF_OBJ_Contract__c.AXF_CTR_PKL_Direction__c.getDescribe();
    System.assertEquals(2, f.getPicklistValues().size());
    Account h = holder('Titular');
    AXF_OBJ_Contract__c c = contract(h.Id, 'AXF_ServiceProvision');
    c.AXF_CTR_PKL_Direction__c = 'Income';
    insert c;
    System.assertEquals(
      'Income',
      [SELECT AXF_CTR_PKL_Direction__c FROM AXF_OBJ_Contract__c WHERE Id = :c.Id]
      .AXF_CTR_PKL_Direction__c
    );
  }
}
