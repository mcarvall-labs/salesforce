/**
 * @description Covers AXF_TH_CreditCardInvoice (period normalization and external id building).
 * The handler has no trigger in this baseline, so it is exercised directly.
 */
@IsTest
private class AXF_TH_CreditCardInvoiceTest {
  private static final String USER_KEY = 'invoice';

  @TestSetup
  static void setup() {
    AXF_CLS_AccountCardTestFactory.createUser(USER_KEY, false);
    Account holder = AXF_CLS_AccountCardTestFactory.newAccount(
      'Titular Fatura'
    );
    insert holder;
    insert new List<AXF_OBJ_CreditCard__c>{
      AXF_CLS_AccountCardTestFactory.newCreditCard(
        'Com final',
        holder.Id,
        null,
        'CC-INV-1',
        '4321'
      ),
      AXF_CLS_AccountCardTestFactory.newCreditCard(
        'Sem final',
        holder.Id,
        null,
        'CC-INV-2',
        null
      )
    };
  }

  private static AXF_OBJ_CreditCardInvoice__c invoice(
    Id cardId,
    String period
  ) {
    return new AXF_OBJ_CreditCardInvoice__c(
      Name = 'original',
      AXF_CCI_MD_CreditCard__c = cardId,
      AXF_CCI_TXT_Period__c = period
    );
  }

  @IsTest
  static void beforeInsertNormalizesPeriodsAndBuildsExternalId() {
    Id cardWithDigits = [
      SELECT Id
      FROM AXF_OBJ_CreditCard__c
      WHERE AXF_CC_EXI_PluggyCreditCardId__c = 'CC-INV-1'
    ]
    .Id;
    Id cardWithoutDigits = [
      SELECT Id
      FROM AXF_OBJ_CreditCard__c
      WHERE AXF_CC_EXI_PluggyCreditCardId__c = 'CC-INV-2'
    ]
    .Id;

    AXF_OBJ_CreditCardInvoice__c slashShortMonth = invoice(
      cardWithDigits,
      ' 6/2027 '
    );
    AXF_OBJ_CreditCardInvoice__c isoShortMonth = invoice(
      cardWithDigits,
      '2027-7'
    );
    AXF_OBJ_CreditCardInvoice__c freeText = invoice(
      cardWithDigits,
      'Junho 2027'
    );
    AXF_OBJ_CreditCardInvoice__c invalidSlash = invoice(
      cardWithDigits,
      '123/27'
    );
    AXF_OBJ_CreditCardInvoice__c blankPeriod = invoice(cardWithDigits, null);
    AXF_OBJ_CreditCardInvoice__c noDigits = invoice(
      cardWithoutDigits,
      '08/2027'
    );
    AXF_OBJ_CreditCardInvoice__c noCard = invoice(null, '09/2027');

    List<AXF_OBJ_CreditCardInvoice__c> invoices = new List<AXF_OBJ_CreditCardInvoice__c>{
      slashShortMonth,
      isoShortMonth,
      freeText,
      invalidSlash,
      blankPeriod,
      noDigits,
      noCard
    };

    System.runAs(AXF_CLS_AccountCardTestFactory.getUser(USER_KEY)) {
      Test.startTest();
      AXF_TH_CreditCardInvoice.handleBeforeInsert(invoices);
      Test.stopTest();
    }

    Assert.areEqual('2027-06', slashShortMonth.Name);
    Assert.areEqual('4321_2027-06', slashShortMonth.AXF_CCI_EXT_ExternalId__c);
    Assert.areEqual('2027-07', isoShortMonth.Name);
    Assert.areEqual('4321_2027-07', isoShortMonth.AXF_CCI_EXT_ExternalId__c);
    Assert.areEqual(
      'Junho 2027',
      freeText.Name,
      'Unrecognized periods are kept as-is'
    );
    Assert.areEqual('4321_Junho 2027', freeText.AXF_CCI_EXT_ExternalId__c);
    Assert.areEqual('123/27', invalidSlash.Name);
    Assert.areEqual(
      'original',
      blankPeriod.Name,
      'Name must not change without a period'
    );
    Assert.isNull(blankPeriod.AXF_CCI_EXT_ExternalId__c);
    Assert.areEqual('2027-08', noDigits.Name);
    Assert.isNull(
      noDigits.AXF_CCI_EXT_ExternalId__c,
      'No external id without last four digits'
    );
    Assert.areEqual('2027-09', noCard.Name);
    Assert.isNull(noCard.AXF_CCI_EXT_ExternalId__c);
  }

  @IsTest
  static void beforeUpdateUsesInMemoryCardRelationship() {
    AXF_OBJ_CreditCard__c card = [
      SELECT Id, AXF_CC_TXT_LastFourDigits__c
      FROM AXF_OBJ_CreditCard__c
      WHERE AXF_CC_EXI_PluggyCreditCardId__c = 'CC-INV-2'
    ];
    card.AXF_CC_TXT_LastFourDigits__c = '9999';

    AXF_OBJ_CreditCardInvoice__c inv = invoice(card.Id, '2027-12');
    inv.AXF_CCI_MD_CreditCard__r = card;

    System.runAs(AXF_CLS_AccountCardTestFactory.getUser(USER_KEY)) {
      Test.startTest();
      AXF_TH_CreditCardInvoice.handleBeforeUpdate(
        new List<AXF_OBJ_CreditCardInvoice__c>{ inv },
        new Map<Id, AXF_OBJ_CreditCardInvoice__c>()
      );
      Test.stopTest();
    }

    Assert.areEqual('2027-12', inv.Name);
    Assert.areEqual(
      '9999_2027-12',
      inv.AXF_CCI_EXT_ExternalId__c,
      'In-memory card digits take precedence'
    );
  }
}
