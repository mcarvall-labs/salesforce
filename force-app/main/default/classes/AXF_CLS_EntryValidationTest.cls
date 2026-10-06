@IsTest
private class AXF_CLS_EntryValidationTest {
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

  private static AXF_OBJ_Entry__c entry(Id holderId) {
    return new AXF_OBJ_Entry__c(
      Name = 'Lançamento',
      AXF_ENT_MD_Holder__c = holderId,
      AXF_ENT_CUR_Amount__c = 100,
      AXF_ENT_DAT_DueDate__c = Date.today(),
      AXF_ENT_PKL_Type__c = 'Expense',
      AXF_ENT_PKL_Status__c = 'Pending'
    );
  }

  private static void assertRejected(AXF_OBJ_Entry__c e, String expectedField) {
    Database.SaveResult result = Database.insert(e, false);
    System.assert(!result.isSuccess(), 'Expected the entry to be rejected');
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
  static void validEntryWithoutPaymentSourceIsAccepted() {
    // Cash expenses have neither bank account nor card.
    Account h = holder('Titular');
    AXF_OBJ_Entry__c e = entry(h.Id);
    e.AXF_ENT_PKL_Status__c = 'Realized';
    e.AXF_ENT_DAT_PaymentDate__c = Date.today();
    insert e;
    System.assertNotEquals(null, e.Id);
  }

  @IsTest
  static void validEntryWithOwnBankAccountOrCardIsAccepted() {
    Account h = holder('Titular');
    AXF_OBJ_Entry__c a = entry(h.Id);
    a.AXF_ENT_LKP_BankAccount__c = bankAccount(h.Id).Id;
    AXF_OBJ_Entry__c c = entry(h.Id);
    c.AXF_ENT_LKP_CreditCard__c = creditCard(h.Id).Id;
    insert new List<AXF_OBJ_Entry__c>{ a, c };
    System.assertNotEquals(null, a.Id);
    System.assertNotEquals(null, c.Id);
  }

  @IsTest
  static void amountMustBeGreaterThanZero() {
    Account h = holder('Titular');
    for (Decimal invalid : new List<Decimal>{ 0, -1 }) {
      AXF_OBJ_Entry__c e = entry(h.Id);
      e.AXF_ENT_CUR_Amount__c = invalid;
      assertRejected(e, 'AXF_ENT_CUR_Amount__c');
    }
  }

  @IsTest
  static void paymentDateIsRequiredWhenRealized() {
    AXF_OBJ_Entry__c e = entry(holder('Titular').Id);
    e.AXF_ENT_PKL_Status__c = 'Realized';
    assertRejected(e, 'AXF_ENT_DAT_PaymentDate__c');
  }

  @IsTest
  static void paymentDateIsRejectedWhenNotRealized() {
    AXF_OBJ_Entry__c e = entry(holder('Titular').Id);
    e.AXF_ENT_DAT_PaymentDate__c = Date.today();
    assertRejected(e, 'AXF_ENT_DAT_PaymentDate__c');
  }

  @IsTest
  static void bankAccountAndCardTogetherAreRejected() {
    Account h = holder('Titular');
    AXF_OBJ_Entry__c e = entry(h.Id);
    e.AXF_ENT_LKP_BankAccount__c = bankAccount(h.Id).Id;
    e.AXF_ENT_LKP_CreditCard__c = creditCard(h.Id).Id;
    assertRejected(e, 'AXF_ENT_LKP_CreditCard__c');
  }

  @IsTest
  static void bankAccountFromAnotherHolderIsRejected() {
    Account h = holder('Titular');
    AXF_OBJ_Entry__c e = entry(h.Id);
    e.AXF_ENT_LKP_BankAccount__c = bankAccount(holder('Outro').Id).Id;
    assertRejected(e, 'AXF_ENT_LKP_BankAccount__c');
  }

  @IsTest
  static void creditCardFromAnotherHolderIsRejected() {
    Account h = holder('Titular');
    AXF_OBJ_Entry__c e = entry(h.Id);
    e.AXF_ENT_LKP_CreditCard__c = creditCard(holder('Outro').Id).Id;
    assertRejected(e, 'AXF_ENT_LKP_CreditCard__c');
  }
}
