/**
 * @description Covers AXF_CLS_TH_AccountCardNaming, AXF_CLS_TH_BankInstitution and the triggers
 * AXF_TRG_BankAccount, AXF_TRG_CreditCard and AXF_TRG_BankInstitution through DML.
 */
@IsTest
private class AXF_CLS_TH_AccountCardNamingTest {
  private static final String USER_KEY = 'naming';

  @TestSetup
  static void setup() {
    AXF_CLS_AccountCardTestFactory.createUser(USER_KEY, false);
    insert AXF_CLS_AccountCardTestFactory.newAccount('Maria Souza');
  }

  @IsTest
  static void institutionNameCombinesBankNameAndNumber() {
    System.runAs(AXF_CLS_AccountCardTestFactory.getUser(USER_KEY)) {
      AXF_OBJ_BankInstitution__c withPicklist = AXF_CLS_AccountCardTestFactory.newInstitution(
        'Bradesco',
        '237'
      );
      AXF_OBJ_BankInstitution__c withoutPicklist = new AXF_OBJ_BankInstitution__c(
        Name = 'Banco Custom',
        AXF_BI_EXI_Bank_Number__c = '999'
      );

      Test.startTest();
      insert new List<AXF_OBJ_BankInstitution__c>{
        withPicklist,
        withoutPicklist
      };
      withPicklist.AXF_BI_PKL_BankName__c = 'Nubank';
      withPicklist.AXF_BI_EXI_Bank_Number__c = '260';
      update withPicklist;
      Test.stopTest();

      Map<Id, AXF_OBJ_BankInstitution__c> saved = new Map<Id, AXF_OBJ_BankInstitution__c>(
        [SELECT Id, Name FROM AXF_OBJ_BankInstitution__c]
      );
      Assert.areEqual(
        'Nubank (260)',
        saved.get(withPicklist.Id).Name,
        'Update must reformat the name'
      );
      Assert.areEqual(
        'Banco Custom',
        saved.get(withoutPicklist.Id).Name,
        'Name must be kept when the bank name picklist is blank'
      );
    }
  }

  @IsTest
  static void institutionInsertFormatsName() {
    System.runAs(AXF_CLS_AccountCardTestFactory.getUser(USER_KEY)) {
      AXF_OBJ_BankInstitution__c inst = AXF_CLS_AccountCardTestFactory.newInstitution(
        'Itaú',
        '341'
      );
      inst.Name = 'placeholder';

      Test.startTest();
      insert inst;
      Test.stopTest();

      Assert.areEqual(
        'Itaú (341)',
        [SELECT Name FROM AXF_OBJ_BankInstitution__c WHERE Id = :inst.Id].Name
      );
    }
  }

  @IsTest
  static void bankAccountNamesAreStandardized() {
    Account holder = [SELECT Id FROM Account WHERE Name = 'Maria Souza'];
    System.runAs(AXF_CLS_AccountCardTestFactory.getUser(USER_KEY)) {
      AXF_OBJ_BankInstitution__c inst = AXF_CLS_AccountCardTestFactory.newInstitution(
        'Itaú',
        '341'
      );
      insert inst;

      AXF_OBJ_BankAccount__c full = AXF_CLS_AccountCardTestFactory.newBankAccount(
        'x',
        holder.Id,
        inst.Id,
        'BA-1'
      );
      AXF_OBJ_BankAccount__c holderOnly = AXF_CLS_AccountCardTestFactory.newBankAccount(
        'x',
        holder.Id,
        null,
        'BA-2'
      );
      AXF_OBJ_BankAccount__c institutionOnly = AXF_CLS_AccountCardTestFactory.newBankAccount(
        'x',
        null,
        inst.Id,
        'BA-3'
      );
      AXF_OBJ_BankAccount__c fallback = AXF_CLS_AccountCardTestFactory.newBankAccount(
        ' minha conta ',
        null,
        null,
        'BA-4'
      );
      AXF_OBJ_BankAccount__c defaulted = AXF_CLS_AccountCardTestFactory.newBankAccount(
        null,
        null,
        null,
        'BA-5'
      );
      List<AXF_OBJ_BankAccount__c> records = new List<AXF_OBJ_BankAccount__c>{
        full,
        holderOnly,
        institutionOnly,
        fallback,
        defaulted
      };

      Test.startTest();
      insert records;
      holderOnly.AXF_BA_LKP_BankInstitution__c = inst.Id;
      update holderOnly;
      Test.stopTest();

      Map<Id, AXF_OBJ_BankAccount__c> saved = new Map<Id, AXF_OBJ_BankAccount__c>(
        [SELECT Id, Name FROM AXF_OBJ_BankAccount__c]
      );
      Assert.areEqual('MARIA SOUZA - ITAU', saved.get(full.Id).Name);
      Assert.areEqual(
        'MARIA SOUZA - ITAU',
        saved.get(holderOnly.Id).Name,
        'Update must re-run naming'
      );
      Assert.areEqual('ITAU', saved.get(institutionOnly.Id).Name);
      Assert.areEqual('MINHA CONTA', saved.get(fallback.Id).Name);
      Assert.areEqual(
        System.Label.AXF_LBL_DefaultBankAccountName.toUpperCase(),
        saved.get(defaulted.Id).Name,
        'Default label must be used when nothing else is available'
      );
    }
  }

  @IsTest
  static void creditCardNamesAreStandardized() {
    Account holder = [SELECT Id FROM Account WHERE Name = 'Maria Souza'];
    System.runAs(AXF_CLS_AccountCardTestFactory.getUser(USER_KEY)) {
      AXF_OBJ_BankInstitution__c inst = AXF_CLS_AccountCardTestFactory.newInstitution(
        'Nubank',
        '260'
      );
      insert inst;

      AXF_OBJ_CreditCard__c full = AXF_CLS_AccountCardTestFactory.newCreditCard(
        'x',
        holder.Id,
        inst.Id,
        'CC-1',
        '1234'
      );
      AXF_OBJ_CreditCard__c holderOnly = AXF_CLS_AccountCardTestFactory.newCreditCard(
        'x',
        holder.Id,
        null,
        'CC-2',
        null
      );
      AXF_OBJ_CreditCard__c fallback = AXF_CLS_AccountCardTestFactory.newCreditCard(
        'Cartão Extra',
        null,
        null,
        'CC-3',
        null
      );
      AXF_OBJ_CreditCard__c defaulted = AXF_CLS_AccountCardTestFactory.newCreditCard(
        null,
        null,
        null,
        'CC-4',
        null
      );

      Test.startTest();
      insert new List<AXF_OBJ_CreditCard__c>{
        full,
        holderOnly,
        fallback,
        defaulted
      };
      fallback.AXF_CC_LKP_Account__c = holder.Id;
      update fallback;
      Test.stopTest();

      Map<Id, AXF_OBJ_CreditCard__c> saved = new Map<Id, AXF_OBJ_CreditCard__c>(
        [SELECT Id, Name FROM AXF_OBJ_CreditCard__c]
      );
      Assert.areEqual('MARIA SOUZA - NUBANK', saved.get(full.Id).Name);
      Assert.areEqual('MARIA SOUZA', saved.get(holderOnly.Id).Name);
      Assert.areEqual(
        'MARIA SOUZA',
        saved.get(fallback.Id).Name,
        'Update must re-run naming'
      );
      Assert.areEqual(
        System.Label.AXF_LBL_DefaultCreditCardName.toUpperCase(),
        saved.get(defaulted.Id).Name
      );
    }
  }
}
