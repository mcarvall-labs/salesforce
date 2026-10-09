@IsTest
private class AXF_CLS_CTRL_InvoiceTransactionsTest {
  @TestSetup
  static void setup() {
    ALT_CLS_SyncTestUser.create(
      'axfit',
      new List<String>{
        'AXF_OBJ_Entry__c',
        'AXF_OBJ_CreditCard__c',
        'AXF_OBJ_CreditCardInvoice__c',
        'AXF_OBJ_CreditCardTransaction__c'
      }
    );
  }

  private static AXF_OBJ_CreditCardInvoice__c invoice;
  private static AXF_OBJ_Entry__c entry;

  private static void base() {
    Account holder = new Account(Name = 'Titular');
    insert holder;
    AXF_OBJ_CreditCard__c card = new AXF_OBJ_CreditCard__c(
      Name = 'Cartão Teste',
      AXF_CC_MD_Holder__c = holder.Id,
      AXF_CC_PKL_Institution__c = '341'
    );
    insert card;
    invoice = new AXF_OBJ_CreditCardInvoice__c(
      AXF_CCI_MD_CreditCard__c = card.Id,
      AXF_CCI_TXT_Period__c = '2026-10',
      AXF_CCI_DAT_ClosingDate__c = Date.newInstance(2026, 10, 1),
      AXF_CCI_DAT_DueDate__c = Date.newInstance(2026, 10, 10),
      AXF_CCI_CUR_TotalAmount__c = 300,
      AXF_CCI_PKL_Status__c = 'Open'
    );
    insert invoice;
    insert new List<AXF_OBJ_CreditCardTransaction__c>{
      new AXF_OBJ_CreditCardTransaction__c(
        AXF_CCT_MD_CreditCard__c = card.Id,
        AXF_CCT_LKP_Invoice__c = invoice.Id,
        AXF_CCT_DAT_Date__c = Date.newInstance(2026, 9, 12),
        AXF_CCT_TXT_Description__c = 'Notebook',
        AXF_CCT_CUR_Amount__c = -200,
        AXF_CCT_CUR_AmountBRL__c = -200,
        AXF_CCT_TXT_CurrencyCode__c = 'BRL',
        AXF_CCT_TXT_Installment__c = '3/10'
      ),
      new AXF_OBJ_CreditCardTransaction__c(
        AXF_CCT_MD_CreditCard__c = card.Id,
        AXF_CCT_LKP_Invoice__c = invoice.Id,
        AXF_CCT_DAT_Date__c = Date.newInstance(2026, 9, 15),
        AXF_CCT_TXT_Description__c = 'Streaming US$ 20',
        AXF_CCT_CUR_Amount__c = -20,
        AXF_CCT_CUR_AmountBRL__c = -100,
        AXF_CCT_TXT_CurrencyCode__c = 'USD'
      )
    };
    entry = new AXF_OBJ_Entry__c(
      Name = 'Fatura Cartão Teste 2026-10',
      AXF_ENT_MD_Holder__c = holder.Id,
      AXF_ENT_CUR_Amount__c = 300,
      AXF_ENT_DAT_DueDate__c = Date.newInstance(2026, 10, 10),
      AXF_ENT_PKL_Type__c = 'Expense',
      AXF_ENT_PKL_Status__c = 'Pending',
      AXF_ENT_LKP_CreditCard__c = card.Id,
      AXF_ENT_LKP_Invoice__c = invoice.Id
    );
    insert entry;
  }

  @IsTest
  static void invoiceEntryShowsTheInvoiceAndItsTransactions() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      AXF_CLS_CTRL_InvoiceTransactions.InvoiceView view = AXF_CLS_CTRL_InvoiceTransactions.getInvoice(
        entry.Id
      );
      System.assertEquals(invoice.Id, view.id);
      System.assertEquals('Cartão Teste', view.cardName);
      System.assertEquals('2026-10', view.period);
      System.assertEquals(Date.newInstance(2026, 10, 1), view.closingDate);
      System.assertEquals(Date.newInstance(2026, 10, 10), view.dueDate);
      System.assertEquals(300, view.totalAmount);
      System.assertEquals('Open', view.status);
      System.assertEquals(2, view.lines.size());
      Map<String, AXF_CLS_CTRL_InvoiceTransactions.LineView> byText = new Map<String, AXF_CLS_CTRL_InvoiceTransactions.LineView>();
      for (AXF_CLS_CTRL_InvoiceTransactions.LineView line : view.lines) {
        byText.put(line.description, line);
        System.assertNotEquals(null, line.id);
      }
      System.assertEquals('3/10', byText.get('Notebook').installment);
      System.assertEquals(-20, byText.get('Streaming US$ 20').amount);
      System.assertEquals(-100, byText.get('Streaming US$ 20').amountBRL);
      System.assertEquals(
        'USD',
        byText.get('Streaming US$ 20').originalCurrency
      );
    }
  }

  @IsTest
  static void invoiceIdWorksAndEntryWithoutInvoiceReturnsNothing() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      System.assertEquals(
        invoice.Id,
        AXF_CLS_CTRL_InvoiceTransactions.getInvoice(invoice.Id).id
      );
      AXF_OBJ_Entry__c plain = entry.clone(false, true);
      plain.AXF_ENT_LKP_Invoice__c = null;
      plain.AXF_ENT_LKP_CreditCard__c = null;
      insert plain;
      System.assertEquals(
        null,
        AXF_CLS_CTRL_InvoiceTransactions.getInvoice(plain.Id)
      );
    }
  }

  @IsTest
  static void invalidRecordsAreRejected() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
      for (Id id : new List<Id>{ null, UserInfo.getUserId() }) {
        try {
          AXF_CLS_CTRL_InvoiceTransactions.getInvoice(id);
          System.assert(false, 'expected AuraHandledException');
        } catch (AuraHandledException e) {
          System.assertNotEquals(null, e.getMessage());
        }
      }
    }
  }

  @IsTest
  static void userWithoutAccessIsDenied() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      base();
    }
    User restricted = new User(
      Alias = 'axfnoit',
      Email = 'axfnoit@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'NoAccessInvoice',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
      .Id,
      TimeZoneSidKey = 'America/Sao_Paulo',
      Username = 'axfnoit' + System.currentTimeMillis() + '@example.com'
    );
    insert restricted;
    Id invoiceId = invoice.Id;
    System.runAs(restricted) {
      try {
        AXF_CLS_CTRL_InvoiceTransactions.getInvoice(invoiceId);
        System.assert(false, 'expected AuraHandledException');
      } catch (AuraHandledException e) {
        System.assertNotEquals(null, e.getMessage());
      }
    }
  }
}
