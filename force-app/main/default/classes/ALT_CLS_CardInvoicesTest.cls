@IsTest
private class ALT_CLS_CardInvoicesTest {
  @TestSetup
  static void setup() {
    ALT_CLS_SyncTestUser.create(
      'axfci',
      new List<String>{
        'AXF_OBJ_CreditCard__c',
        'AXF_OBJ_CreditCardInvoice__c',
        'AXF_OBJ_CreditCardTransaction__c'
      }
    );
  }

  private static AXF_OBJ_CreditCard__c card() {
    Account holder = new Account(Name = 'Holder');
    insert holder;
    AXF_OBJ_CreditCard__c card = new AXF_OBJ_CreditCard__c(
      Name = 'Cartão',
      AXF_CC_MD_Holder__c = holder.Id,
      AXF_CC_PKL_Institution__c = '341'
    );
    insert card;
    return card;
  }

  private static AXF_OBJ_CreditCardInvoice__c invoice(
    Id cardId,
    String period,
    Date due
  ) {
    return new AXF_OBJ_CreditCardInvoice__c(
      AXF_CCI_MD_CreditCard__c = cardId,
      AXF_CCI_TXT_Period__c = period,
      AXF_CCI_DAT_DueDate__c = due,
      AXF_CCI_CUR_TotalAmount__c = 100,
      AXF_CCI_PKL_Status__c = 'Open'
    );
  }

  @IsTest
  static void invoicesComeNewestDueDateFirst() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      AXF_OBJ_CreditCard__c card = card();
      insert new List<AXF_OBJ_CreditCardInvoice__c>{
        invoice(card.Id, '2026-09', Date.newInstance(2026, 9, 5)),
        invoice(card.Id, '2026-10', Date.newInstance(2026, 10, 5))
      };
      List<AXF_CLS_CTRL_CardInvoices.InvoiceView> views = AXF_CLS_CTRL_CardInvoices.getInvoices(
        card.Id
      );
      System.assertEquals(2, views.size());
      System.assertEquals('2026-10', views[0].period);
      System.assertEquals(100, views[0].totalAmount);
      System.assertEquals('Open', views[0].status);
    }
  }

  @IsTest
  static void linesBelongToTheInvoice() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      AXF_OBJ_CreditCard__c card = card();
      AXF_OBJ_CreditCardInvoice__c invoice = invoice(
        card.Id,
        '2026-10',
        Date.newInstance(2026, 10, 5)
      );
      insert invoice;
      insert new List<AXF_OBJ_CreditCardTransaction__c>{
        new AXF_OBJ_CreditCardTransaction__c(
          AXF_CCT_MD_CreditCard__c = card.Id,
          AXF_CCT_LKP_Invoice__c = invoice.Id,
          AXF_CCT_DAT_Date__c = Date.newInstance(2026, 9, 10),
          AXF_CCT_TXT_Description__c = 'Loja',
          AXF_CCT_CUR_Amount__c = -50,
          AXF_CCT_CUR_AmountBRL__c = -260,
          AXF_CCT_TXT_CurrencyCode__c = 'USD',
          AXF_CCT_TXT_Installment__c = '1/3'
        ),
        new AXF_OBJ_CreditCardTransaction__c(
          AXF_CCT_MD_CreditCard__c = card.Id,
          AXF_CCT_DAT_Date__c = Date.newInstance(2026, 9, 11),
          AXF_CCT_CUR_Amount__c = -5
        )
      };
      List<AXF_CLS_CTRL_CardInvoices.LineView> lines = AXF_CLS_CTRL_CardInvoices.getLines(
        invoice.Id
      );
      System.assertEquals(1, lines.size());
      System.assertEquals('Loja', lines[0].description);
      System.assertEquals(-260, lines[0].amountBRL);
      System.assertEquals('USD', lines[0].originalCurrency);
      System.assertEquals('1/3', lines[0].installment);
    }
  }

  @IsTest
  static void controllerRejectsMissingIds() {
    for (Integer i = 0; i < 2; i++) {
      try {
        if (i == 0) {
          AXF_CLS_CTRL_CardInvoices.getInvoices(null);
        } else {
          AXF_CLS_CTRL_CardInvoices.getLines(null);
        }
        System.assert(false, 'Expected AuraHandledException');
      } catch (AuraHandledException e) {
        System.assertNotEquals(null, e.getMessage());
      }
    }
  }

  @IsTest
  static void userWithoutAccessCannotReadInvoicesOrLines() {
    User restricted = new User(
      Alias = 'axfnoacc',
      Email = 'axfnoacc@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'NoAccess',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
      .Id,
      TimeZoneSidKey = 'America/Sao_Paulo',
      Username = 'axfnoacc' + System.currentTimeMillis() + '@example.com'
    );
    insert restricted;
    Integer denied = 0;
    System.runAs(restricted) {
      for (Integer i = 0; i < 2; i++) {
        try {
          if (i == 0) {
            new ALT_CLS_CardInvoices().invoices(UserInfo.getUserId());
          } else {
            new ALT_CLS_CardInvoices().lines(UserInfo.getUserId());
          }
        } catch (QueryException e) {
          denied++;
        }
      }
    }
    System.assertEquals(2, denied);
  }
}
