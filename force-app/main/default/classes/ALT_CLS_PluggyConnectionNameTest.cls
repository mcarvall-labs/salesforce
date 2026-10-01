@IsTest
private class ALT_CLS_PluggyConnectionNameTest {
  @TestSetup
  static void setup() {
    ALT_CLS_ConnectionTestUser.create('axfname');
  }

  private static AXF_OBJ_PluggyConnection__c connection(
    Id holderId,
    String code,
    String item
  ) {
    return new AXF_OBJ_PluggyConnection__c(
      AXF_CON_MD_Holder__c = holderId,
      AXF_CON_PKL_Institution__c = code,
      AXF_CON_EXI_PluggyItemId__c = item
    );
  }

  private static String nameOf(Id connectionId) {
    return [
      SELECT Name
      FROM AXF_OBJ_PluggyConnection__c
      WHERE Id = :connectionId
    ]
    .Name;
  }

  @IsTest
  static void insertSetsNameWithBankAndCode() {
    System.runAs(ALT_CLS_ConnectionTestUser.find('axfname')) {
      Account holder = new Account(Name = 'Michel Lopes');
      insert holder;
      AXF_OBJ_PluggyConnection__c c6 = connection(holder.Id, '336', 'a');
      AXF_OBJ_PluggyConnection__c cef = connection(holder.Id, '104', 'b');
      insert new List<AXF_OBJ_PluggyConnection__c>{ c6, cef };
      System.assertEquals('Michel Lopes - C6 Bank (336)', nameOf(c6.Id));
      System.assertEquals('Michel Lopes - CEF (104)', nameOf(cef.Id));
    }
  }

  @IsTest
  static void personAccountHolderNameIsUsed() {
    System.runAs(ALT_CLS_ConnectionTestUser.find('axfname')) {
      Id recordTypeId = [
        SELECT Id
        FROM RecordType
        WHERE SobjectType = 'Account' AND IsPersonType = TRUE
        LIMIT 1
      ]
      .Id;
      Account holder = new Account(
        RecordTypeId = recordTypeId,
        FirstName = 'Michel',
        LastName = 'Lopes'
      );
      insert holder;
      AXF_OBJ_PluggyConnection__c c = connection(holder.Id, '336', 'a');
      insert c;
      System.assertEquals('Michel Lopes - C6 Bank (336)', nameOf(c.Id));
    }
  }

  @IsTest
  static void nameIsTruncatedToTheFieldLength() {
    System.runAs(ALT_CLS_ConnectionTestUser.find('axfname')) {
      Account holder = new Account(Name = 'A'.repeat(100));
      insert holder;
      AXF_OBJ_PluggyConnection__c c = connection(holder.Id, '336', 'a');
      insert c;
      System.assertEquals(80, nameOf(c.Id).length());
    }
  }
}
