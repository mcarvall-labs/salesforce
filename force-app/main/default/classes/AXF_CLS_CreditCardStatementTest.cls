/**
 * @description Covers the credit card statement stack: ALT_CLS_CreditCardStatement,
 * AXF_CLS_CTRL_CreditCardStatement and the legacy AXF_CLS_CreditCardStatementController.
 */
@IsTest
private class AXF_CLS_CreditCardStatementTest {
  private static final String USER_KEY = 'ccstmt';

  @TestSetup
  static void setup() {
    AXF_CLS_AccountCardTestFactory.createUser(USER_KEY, false);
    Account holder = AXF_CLS_AccountCardTestFactory.newAccount(
      'Titular Cartao'
    );
    insert holder;
    AXF_OBJ_CreditCard__c card = AXF_CLS_AccountCardTestFactory.newCreditCard(
      'Cartao',
      holder.Id,
      null,
      'CC-STMT-1',
      '1111'
    );
    insert card;
    AXF_OBJ_Category__c food = AXF_CLS_AccountCardTestFactory.newCategory(
      'Restaurantes',
      'AXF_CAT_RT_Expense',
      null
    );
    insert food;

    Date today = Date.today();
    AXF_OBJ_CreditCardInvoice__c current = new AXF_OBJ_CreditCardInvoice__c(
      Name = 'Atual',
      AXF_CCI_MD_CreditCard__c = card.Id,
      AXF_CCI_TXT_Period__c = '2027-05',
      AXF_CCI_DAT_DueDate__c = today.addDays(10),
      AXF_CCI_CUR_TotalAmount__c = 200
    );
    AXF_OBJ_CreditCardInvoice__c previous = new AXF_OBJ_CreditCardInvoice__c(
      Name = 'Anterior',
      AXF_CCI_MD_CreditCard__c = card.Id,
      AXF_CCI_TXT_Period__c = '2027-04',
      AXF_CCI_DAT_DueDate__c = today.addDays(-20)
    );
    insert new List<AXF_OBJ_CreditCardInvoice__c>{ current, previous };

    insert new List<AXF_OBJ_CreditCardTransaction__c>{
      new AXF_OBJ_CreditCardTransaction__c(
        Name = 'T1',
        AXF_CCT_LKP_CreditCard__c = card.Id,
        AXF_CCT_LKP_CreditCardInvoice__c = current.Id,
        AXF_CCT_EXI_PluggyTransactionId__c = 'CCT-1',
        AXF_CCT_DAT_Date__c = AXF_CLS_AccountCardTestFactory.middayOf(
          today.addDays(-9)
        ),
        AXF_CCT_TXT_Description__c = 'Restaurante Bom',
        AXF_CCT_CUR_Amount__c = 300,
        AXF_CCT_LKP_Category__c = food.Id
      ),
      new AXF_OBJ_CreditCardTransaction__c(
        Name = 'T2',
        AXF_CCT_LKP_CreditCard__c = card.Id,
        AXF_CCT_LKP_CreditCardInvoice__c = current.Id,
        AXF_CCT_EXI_PluggyTransactionId__c = 'CCT-2',
        AXF_CCT_DAT_Date__c = AXF_CLS_AccountCardTestFactory.middayOf(
          today.addDays(-8)
        ),
        AXF_CCT_TXT_Description__c = 'Estorno',
        AXF_CCT_CUR_Amount__c = -100
      ),
      new AXF_OBJ_CreditCardTransaction__c(
        Name = 'T3',
        AXF_CCT_LKP_CreditCard__c = card.Id,
        AXF_CCT_LKP_CreditCardInvoice__c = current.Id,
        AXF_CCT_EXI_PluggyTransactionId__c = 'CCT-3',
        AXF_CCT_DAT_Date__c = AXF_CLS_AccountCardTestFactory.middayOf(
          today.addDays(-7)
        ),
        AXF_CCT_TXT_Description__c = 'Tarifa sem valor'
      ),
      new AXF_OBJ_CreditCardTransaction__c(
        Name = 'T4',
        AXF_CCT_LKP_CreditCard__c = card.Id,
        AXF_CCT_LKP_CreditCardInvoice__c = previous.Id,
        AXF_CCT_EXI_PluggyTransactionId__c = 'CCT-4',
        AXF_CCT_DAT_Date__c = AXF_CLS_AccountCardTestFactory.middayOf(
          today.addDays(-40)
        ),
        AXF_CCT_TXT_Description__c = 'Outra fatura',
        AXF_CCT_CUR_Amount__c = 50
      )
    };
  }

  private static Id cardId() {
    return [
      SELECT Id
      FROM AXF_OBJ_CreditCard__c
      WHERE AXF_CC_EXI_PluggyCreditCardId__c = 'CC-STMT-1'
    ]
    .Id;
  }

  private static Id currentInvoiceId() {
    return [
      SELECT Id
      FROM AXF_OBJ_CreditCardInvoice__c
      WHERE AXF_CCI_TXT_Period__c = '2027-05'
    ]
    .Id;
  }

  @IsTest
  static void serviceReturnsInvoicesByDueDateDesc() {
    Id card = cardId();
    List<AXF_OBJ_CreditCardInvoice__c> invoices;
    List<AXF_OBJ_CreditCardInvoice__c> none;
    System.runAs(AXF_CLS_AccountCardTestFactory.getUser(USER_KEY)) {
      Test.startTest();
      invoices = new ALT_CLS_CreditCardStatement().getInvoices(card);
      none = new ALT_CLS_CreditCardStatement().getInvoices(null);
      Test.stopTest();
    }

    Assert.areEqual(2, invoices.size());
    Assert.areEqual(
      '2027-05',
      invoices[0].AXF_CCI_TXT_Period__c,
      'Latest due date must come first'
    );
    Assert.areEqual(200, invoices[0].AXF_CCI_CUR_TotalAmount__c);
    Assert.isTrue(none.isEmpty());
  }

  @IsTest
  static void serviceComputesTotalsAndFilters() {
    Id invoiceId = currentInvoiceId();
    ALT_CLS_CreditCardStatement service = new ALT_CLS_CreditCardStatement();
    ALT_CLS_CreditCardStatement.StatementResult all;
    ALT_CLS_CreditCardStatement.StatementResult filtered;
    ALT_CLS_CreditCardStatement.StatementResult empty;
    System.runAs(AXF_CLS_AccountCardTestFactory.getUser(USER_KEY)) {
      Test.startTest();
      all = service.getStatement(invoiceId, null, null, null);
      filtered = service.getStatement(invoiceId, ' restaurante ', 0, 500);
      empty = service.getStatement(null, 'x', 1, 2);
      Test.stopTest();
    }

    Assert.areEqual(
      3,
      all.transactions.size(),
      'Only transactions of the selected invoice'
    );
    Assert.areEqual('Restaurantes', all.transactions[0].categoryName);
    Assert.isFalse(all.transactions[0].isCredit, 'Purchases are debits');
    Assert.isTrue(all.transactions[1].isCredit, 'Refunds are credits');
    Assert.areEqual(
      0,
      all.transactions[2].amount,
      'Null amount must be treated as zero'
    );
    Assert.isNull(all.transactions[2].categoryName);
    Assert.areEqual(-100, all.totalCredits);
    Assert.areEqual(300, all.totalDebits);
    Assert.areEqual(200, all.netBalance);
    Assert.areEqual(1, filtered.transactions.size());
    Assert.areEqual('Restaurante Bom', filtered.transactions[0].description);
    Assert.isTrue(empty.transactions.isEmpty());
  }

  @IsTest
  static void lwcControllerDelegatesToService() {
    Id card = cardId();
    Id invoiceId = currentInvoiceId();
    List<AXF_OBJ_CreditCardInvoice__c> invoices;
    AXF_CLS_CTRL_CreditCardStatement.StatementResult result;
    System.runAs(AXF_CLS_AccountCardTestFactory.getUser(USER_KEY)) {
      Test.startTest();
      invoices = AXF_CLS_CTRL_CreditCardStatement.getInvoices(card);
      result = AXF_CLS_CTRL_CreditCardStatement.getStatement(
        invoiceId,
        null,
        -1000,
        null
      );
      Test.stopTest();
    }

    Assert.areEqual(2, invoices.size());
    Assert.areEqual(
      2,
      result.transactions.size(),
      'Null amounts are excluded by the minimum value filter'
    );
    AXF_CLS_CTRL_CreditCardStatement.TransactionRow refund = result.transactions[1];
    Assert.areEqual('Estorno', refund.description);
    Assert.areEqual(-100, refund.amount);
    Assert.isTrue(refund.isCredit);
    Assert.isNotNull(refund.id);
    Assert.isNotNull(refund.transactionDate);
    Assert.isNull(refund.categoryName);
    Assert.areEqual(-100, result.totalCredits);
    Assert.areEqual(300, result.totalDebits);
    Assert.areEqual(200, result.netBalance);
  }

  @IsTest
  static void legacyControllerReturnsInvoicesAndStatement() {
    Id card = cardId();
    Id invoiceId = currentInvoiceId();
    List<AXF_OBJ_CreditCardInvoice__c> invoices;
    List<AXF_OBJ_CreditCardInvoice__c> noInvoices;
    AXF_CLS_CreditCardStatementController.StatementResult all;
    AXF_CLS_CreditCardStatementController.StatementResult filtered;
    AXF_CLS_CreditCardStatementController.StatementResult empty;
    System.runAs(AXF_CLS_AccountCardTestFactory.getUser(USER_KEY)) {
      Test.startTest();
      invoices = AXF_CLS_CreditCardStatementController.getInvoices(card);
      noInvoices = AXF_CLS_CreditCardStatementController.getInvoices(null);
      all = AXF_CLS_CreditCardStatementController.getStatement(
        invoiceId,
        null,
        null,
        null
      );
      filtered = AXF_CLS_CreditCardStatementController.getStatement(
        invoiceId,
        'Estorno',
        -200,
        0
      );
      empty = AXF_CLS_CreditCardStatementController.getStatement(
        null,
        null,
        null,
        null
      );
      Test.stopTest();
    }

    Assert.areEqual(2, invoices.size());
    Assert.isTrue(noInvoices.isEmpty());
    Assert.areEqual(3, all.transactions.size());
    Assert.areEqual('Restaurantes', all.transactions[0].categoryName);
    Assert.areEqual(200, all.netBalance);
    Assert.areEqual(1, filtered.transactions.size());
    Assert.isTrue(filtered.transactions[0].isCredit);
    Assert.areEqual(-100, filtered.totalCredits);
    Assert.isTrue(empty.transactions.isEmpty());
  }
}
