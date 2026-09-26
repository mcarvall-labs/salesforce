/**
 * @description Covers the holder/bank account/credit card lookups: ALT_CLS_AccountLookup,
 * AXF_CLS_CTRL_AccountLookup, AXF_CLS_CTRL_BankAccountLookup, AXF_CLS_CTRL_CreditCardLookup and
 * ALT_CLS_FinancialAccountLookup.
 */
@IsTest
private class AXF_CLS_LookupControllersTest {
  private static final String USER_KEY = 'lookups';

  @TestSetup
  static void setup() {
    AXF_CLS_AccountCardTestFactory.createUser(USER_KEY, false);
    Account beta = AXF_CLS_AccountCardTestFactory.newAccount('Beta Holder');
    Account alpha = AXF_CLS_AccountCardTestFactory.newAccount('Alpha Holder');
    insert new List<Account>{ beta, alpha };
    AXF_OBJ_BankInstitution__c inst = AXF_CLS_AccountCardTestFactory.newInstitution(
      'Nubank',
      '260'
    );
    insert inst;
    insert new List<AXF_OBJ_BankAccount__c>{
      AXF_CLS_AccountCardTestFactory.newBankAccount(
        'x',
        alpha.Id,
        inst.Id,
        'BA-LK-1'
      ),
      AXF_CLS_AccountCardTestFactory.newBankAccount(
        'x',
        beta.Id,
        null,
        'BA-LK-2'
      )
    };
    insert new List<AXF_OBJ_CreditCard__c>{
      AXF_CLS_AccountCardTestFactory.newCreditCard(
        'x',
        alpha.Id,
        inst.Id,
        'CC-LK-1',
        '1234'
      ),
      AXF_CLS_AccountCardTestFactory.newCreditCard(
        'x',
        beta.Id,
        null,
        'CC-LK-2',
        '5678'
      )
    };
  }

  private static Id accountIdByName(String name) {
    return [SELECT Id FROM Account WHERE Name = :name].Id;
  }

  @IsTest
  static void accountLookupReturnsHoldersOrderedByName() {
    Id alphaId = accountIdByName('Alpha Holder');
    List<ALT_CLS_AccountLookup.OptionResult> serviceOptions;
    List<AXF_CLS_CTRL_AccountLookup.AccountOptionDTO> dtos;
    System.runAs(AXF_CLS_AccountCardTestFactory.getUser(USER_KEY)) {
      Test.startTest();
      serviceOptions = new ALT_CLS_AccountLookup().getAccountOptions();
      dtos = AXF_CLS_CTRL_AccountLookup.getAccountOptions();
      Test.stopTest();
    }

    Assert.areEqual(2, serviceOptions.size());
    Assert.areEqual('Alpha Holder', serviceOptions[0].displayLabel);
    Assert.areEqual(alphaId, serviceOptions[0].id);
    Assert.areEqual(2, dtos.size());
    Assert.areEqual('Alpha Holder', dtos[0].displayLabel);
    Assert.areEqual('Beta Holder', dtos[1].displayLabel);
    Assert.areEqual(alphaId, dtos[0].id);
  }

  @IsTest
  static void bankAccountLookupAppendsHolderName() {
    Id alphaId = accountIdByName('Alpha Holder');
    List<AXF_CLS_CTRL_BankAccountLookup.BankAccountOptionDTO> dtos;
    System.runAs(AXF_CLS_AccountCardTestFactory.getUser(USER_KEY)) {
      Test.startTest();
      dtos = AXF_CLS_CTRL_BankAccountLookup.getBankAccountOptions();
      Test.stopTest();
    }

    Assert.areEqual(2, dtos.size());
    Assert.areEqual(
      'ALPHA HOLDER - NUBANK (Alpha Holder)',
      dtos[0].displayLabel
    );
    Assert.areEqual(alphaId, dtos[0].accountId);
    Assert.areEqual('BETA HOLDER (Beta Holder)', dtos[1].displayLabel);
    Assert.isNotNull(dtos[1].id);
  }

  @IsTest
  static void creditCardLookupAppendsHolderName() {
    Id betaId = accountIdByName('Beta Holder');
    List<AXF_CLS_CTRL_CreditCardLookup.CreditCardOptionDTO> dtos;
    System.runAs(AXF_CLS_AccountCardTestFactory.getUser(USER_KEY)) {
      Test.startTest();
      dtos = AXF_CLS_CTRL_CreditCardLookup.getCreditCardOptions();
      Test.stopTest();
    }

    Assert.areEqual(2, dtos.size());
    Assert.areEqual(
      'ALPHA HOLDER - NUBANK (Alpha Holder)',
      dtos[0].displayLabel
    );
    Assert.areEqual('BETA HOLDER (Beta Holder)', dtos[1].displayLabel);
    Assert.areEqual(betaId, dtos[1].accountId);
    Assert.isNotNull(dtos[1].id);
  }

  @IsTest
  static void financialAccountLookupFiltersByHolder() {
    Id alphaId = accountIdByName('Alpha Holder');
    Id betaId = accountIdByName('Beta Holder');
    AXF_OBJ_BankAccount__c alphaBank = [
      SELECT Id
      FROM AXF_OBJ_BankAccount__c
      WHERE AXF_BA_LKP_Account__c = :alphaId
    ];
    AXF_OBJ_CreditCard__c betaCard = [
      SELECT Id
      FROM AXF_OBJ_CreditCard__c
      WHERE AXF_CC_LKP_Account__c = :betaId
    ];

    ALT_CLS_FinancialAccountLookup service = new ALT_CLS_FinancialAccountLookup();
    List<ALT_CLS_FinancialAccountLookup.OptionResult> alphaBanks;
    List<ALT_CLS_FinancialAccountLookup.OptionResult> betaCards;
    List<ALT_CLS_FinancialAccountLookup.OptionResult> noHolderBanks;
    List<ALT_CLS_FinancialAccountLookup.OptionResult> noHolderCards;
    System.runAs(AXF_CLS_AccountCardTestFactory.getUser(USER_KEY)) {
      Test.startTest();
      alphaBanks = service.getBankAccounts(alphaId);
      betaCards = service.getCreditCards(betaId);
      noHolderBanks = service.getBankAccounts(null);
      noHolderCards = service.getCreditCards(null);
      Test.stopTest();
    }

    Assert.areEqual(1, alphaBanks.size());
    Assert.areEqual(alphaBank.Id, alphaBanks[0].id);
    Assert.areEqual('ALPHA HOLDER - NUBANK', alphaBanks[0].displayLabel);
    Assert.areEqual(1, betaCards.size());
    Assert.areEqual(betaCard.Id, betaCards[0].id);
    Assert.areEqual('BETA HOLDER', betaCards[0].displayLabel);
    Assert.isTrue(noHolderBanks.isEmpty());
    Assert.isTrue(noHolderCards.isEmpty());
  }
}
