/**
 * @description Covers AXF_TRG_CashFlow, AXF_TRG_BankAccountTransaction and
 * AXF_TRG_CreditCardTransaction through DML, together with their handlers
 * AXF_CLS_TH_CashFlow and AXF_CLS_TH_Reconciliation.
 */
@IsTest
private class AXF_CLS_TH_CashFlowTest {
  @TestSetup
  static void setup() {
    User testUser = AXF_CLS_CashFlowTestFactory.createDomainUser();
    System.runAs(testUser) {
      Account holder = AXF_CLS_CashFlowTestFactory.createAccount(
        'Trigger Holder'
      );
      AXF_OBJ_BankAccount__c bank = AXF_CLS_CashFlowTestFactory.createBankAccount(
        holder.Id,
        'TRG_BANK',
        100
      );
      AXF_OBJ_CreditCard__c card = AXF_CLS_CashFlowTestFactory.createCreditCard(
        holder.Id,
        'TRG_CARD'
      );
      insert AXF_CLS_CashFlowTestFactory.buildBankTransaction(
        bank.Id,
        'TRG_BAT_1',
        -50,
        Date.today(),
        'Mercado'
      );
      insert AXF_CLS_CashFlowTestFactory.buildCardTransaction(
        card.Id,
        'TRG_CCT_1',
        80,
        Date.today(),
        'Farmacia'
      );
    }
  }

  private static Account holder() {
    return [SELECT Id FROM Account WHERE Name = 'Trigger Holder' LIMIT 1];
  }

  private static AXF_OBJ_BankAccountTransaction__c bankTransaction() {
    return [SELECT Id FROM AXF_OBJ_BankAccountTransaction__c LIMIT 1];
  }

  private static AXF_OBJ_CreditCardTransaction__c cardTransaction() {
    return [SELECT Id FROM AXF_OBJ_CreditCardTransaction__c LIMIT 1];
  }

  private static String saveError(SObject record, Boolean isInsert) {
    Database.SaveResult result = isInsert
      ? Database.insert(record, false)
      : Database.update(record, false);
    return result.isSuccess() ? null : result.getErrors()[0].getMessage();
  }

  @IsTest
  static void settledStatusesAreNormalizedOnInsertAndUpdate() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      Id accountId = holder().Id;
      Date due = Date.today().addDays(-10);
      AXF_OBJ_CashFlow__c paidOnTime = AXF_CLS_CashFlowTestFactory.buildCashFlow(
        true,
        accountId,
        'On time',
        10,
        Date.today().addDays(5),
        'PAGA'
      );
      AXF_OBJ_CashFlow__c paidLate = AXF_CLS_CashFlowTestFactory.buildCashFlow(
        true,
        accountId,
        'Late',
        10,
        due,
        'PAGA'
      );
      paidLate.AXF_CF_DAT_PaymentDate__c = Date.today();
      AXF_OBJ_CashFlow__c receivedLate = AXF_CLS_CashFlowTestFactory.buildCashFlow(
        false,
        accountId,
        'Rev late',
        10,
        due,
        'RECEBIDA_EM_ATRASO'
      );
      AXF_OBJ_CashFlow__c receivedOnTime = AXF_CLS_CashFlowTestFactory.buildCashFlow(
        false,
        accountId,
        'Rev ok',
        10,
        due,
        'RECEBIDA'
      );
      receivedOnTime.AXF_CF_DAT_PaymentDate__c = due;
      AXF_OBJ_CashFlow__c open = AXF_CLS_CashFlowTestFactory.buildCashFlow(
        true,
        accountId,
        'Open',
        10,
        due,
        'PENDENTE'
      );

      Test.startTest();
      insert new List<AXF_OBJ_CashFlow__c>{
        paidOnTime,
        paidLate,
        receivedLate,
        receivedOnTime,
        open
      };
      open.AXF_CF_PKL_Status__c = 'PAGA_EM_ATRASO';
      open.AXF_CF_DAT_PaymentDate__c = due;
      update open;
      Test.stopTest();

      Map<Id, AXF_OBJ_CashFlow__c> saved = new Map<Id, AXF_OBJ_CashFlow__c>(
        [
          SELECT Id, AXF_CF_PKL_Status__c, AXF_CF_DAT_PaymentDate__c
          FROM AXF_OBJ_CashFlow__c
        ]
      );
      Assert.areEqual('PAGA', saved.get(paidOnTime.Id).AXF_CF_PKL_Status__c);
      Assert.areEqual(
        Date.today(),
        saved.get(paidOnTime.Id).AXF_CF_DAT_PaymentDate__c,
        'Payment date defaults to today'
      );
      Assert.areEqual(
        'PAGA_EM_ATRASO',
        saved.get(paidLate.Id).AXF_CF_PKL_Status__c
      );
      Assert.areEqual(
        'RECEBIDA_EM_ATRASO',
        saved.get(receivedLate.Id).AXF_CF_PKL_Status__c
      );
      Assert.areEqual(
        'RECEBIDA',
        saved.get(receivedOnTime.Id).AXF_CF_PKL_Status__c
      );
      Assert.areEqual(
        'PAGA',
        saved.get(open.Id).AXF_CF_PKL_Status__c,
        'Paid on the due date is not late'
      );
    }
  }

  @IsTest
  static void installmentGroupCountersFollowInsertUpdateAndDelete() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      Id accountId = holder().Id;
      AXF_OBJ_InstallmentGroup__c groupA = new AXF_OBJ_InstallmentGroup__c(
        AXF_IG_PKL_GroupType__c = 'INSTALLMENT'
      );
      AXF_OBJ_InstallmentGroup__c groupB = new AXF_OBJ_InstallmentGroup__c(
        AXF_IG_PKL_GroupType__c = 'INSTALLMENT'
      );
      insert new List<AXF_OBJ_InstallmentGroup__c>{ groupA, groupB };

      List<AXF_OBJ_CashFlow__c> entries = new List<AXF_OBJ_CashFlow__c>{
        AXF_CLS_CashFlowTestFactory.buildCashFlow(
          true,
          accountId,
          'P1',
          100,
          Date.today(),
          'PAGA'
        ),
        AXF_CLS_CashFlowTestFactory.buildCashFlow(
          true,
          accountId,
          'P2',
          200,
          Date.today().addDays(-40),
          'VENCIDA'
        ),
        AXF_CLS_CashFlowTestFactory.buildCashFlow(
          true,
          accountId,
          'P3',
          300,
          Date.today().addDays(30),
          'PENDENTE'
        )
      };
      entries[2].AXF_CF_CUR_Value__c = 300;
      for (AXF_OBJ_CashFlow__c entry : entries) {
        entry.AXF_CF_LKP_InstallmentGroup__c = groupA.Id;
      }

      Test.startTest();
      insert entries;
      AXF_OBJ_InstallmentGroup__c afterInsert = [
        SELECT
          AXF_IG_NUM_PaidInstallmentsCount__c,
          AXF_IG_NUM_PendingInstallmentsCount__c,
          AXF_IG_NUM_OverdueInstallmentsCount__c,
          AXF_IG_CUR_TotalPaidAmount__c,
          AXF_IG_CUR_TotalRemainingAmount__c
        FROM AXF_OBJ_InstallmentGroup__c
        WHERE Id = :groupA.Id
      ];
      Assert.areEqual(1, afterInsert.AXF_IG_NUM_PaidInstallmentsCount__c);
      Assert.areEqual(1, afterInsert.AXF_IG_NUM_OverdueInstallmentsCount__c);
      Assert.areEqual(1, afterInsert.AXF_IG_NUM_PendingInstallmentsCount__c);
      Assert.areEqual(100, afterInsert.AXF_IG_CUR_TotalPaidAmount__c);
      Assert.areEqual(500, afterInsert.AXF_IG_CUR_TotalRemainingAmount__c);

      entries[2].AXF_CF_LKP_InstallmentGroup__c = groupB.Id;
      update entries[2];
      delete entries[1];
      Test.stopTest();

      Map<Id, AXF_OBJ_InstallmentGroup__c> groups = new Map<Id, AXF_OBJ_InstallmentGroup__c>(
        [
          SELECT
            Id,
            AXF_IG_NUM_PaidInstallmentsCount__c,
            AXF_IG_NUM_PendingInstallmentsCount__c,
            AXF_IG_NUM_OverdueInstallmentsCount__c,
            AXF_IG_CUR_TotalRemainingAmount__c
          FROM AXF_OBJ_InstallmentGroup__c
        ]
      );
      Assert.areEqual(
        0,
        groups.get(groupA.Id).AXF_IG_NUM_PendingInstallmentsCount__c,
        'Moved entry leaves old group'
      );
      Assert.areEqual(
        0,
        groups.get(groupA.Id).AXF_IG_NUM_OverdueInstallmentsCount__c,
        'Deleted entry is removed'
      );
      Assert.areEqual(
        0,
        groups.get(groupA.Id).AXF_IG_CUR_TotalRemainingAmount__c
      );
      Assert.areEqual(
        1,
        groups.get(groupB.Id).AXF_IG_NUM_PendingInstallmentsCount__c
      );
      Assert.areEqual(
        300,
        groups.get(groupB.Id).AXF_IG_CUR_TotalRemainingAmount__c
      );
    }
  }

  @IsTest
  static void cashFlowReconciliationInvariantsAreEnforced() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      Id accountId = holder().Id;
      AXF_OBJ_CashFlow__c reconciledWithoutLink = AXF_CLS_CashFlowTestFactory.buildCashFlow(
        true,
        accountId,
        'R',
        50,
        Date.today(),
        'PENDENTE'
      );
      reconciledWithoutLink.AXF_CF_PKL_ReconciliationStatus__c = 'RECONCILED';
      AXF_OBJ_CashFlow__c linkedButOpen = AXF_CLS_CashFlowTestFactory.buildCashFlow(
        true,
        accountId,
        'U',
        50,
        Date.today(),
        'PENDENTE'
      );
      linkedButOpen.AXF_CF_LKP_BankAccountTransaction__c = bankTransaction().Id;
      linkedButOpen.AXF_CF_PKL_ReconciliationStatus__c = 'UNRECONCILED';
      AXF_OBJ_CashFlow__c bankNotReciprocal = AXF_CLS_CashFlowTestFactory.buildCashFlow(
        true,
        accountId,
        'B',
        50,
        Date.today(),
        'PENDENTE'
      );
      bankNotReciprocal.AXF_CF_LKP_BankAccountTransaction__c = bankTransaction()
        .Id;
      bankNotReciprocal.AXF_CF_PKL_ReconciliationStatus__c = 'RECONCILED';
      AXF_OBJ_CashFlow__c cardNotReciprocal = AXF_CLS_CashFlowTestFactory.buildCashFlow(
        true,
        accountId,
        'C',
        50,
        Date.today(),
        'PENDENTE'
      );
      cardNotReciprocal.AXF_CF_LKP_CreditCardTransaction__c = cardTransaction()
        .Id;
      cardNotReciprocal.AXF_CF_PKL_ReconciliationStatus__c = 'RECONCILED';

      Test.startTest();
      String invariant = saveError(reconciledWithoutLink, true);
      String openLinked = saveError(linkedButOpen, true);
      String bankError = saveError(bankNotReciprocal, true);
      String cardError = saveError(cardNotReciprocal, true);
      Test.stopTest();

      Assert.isTrue(invariant.contains('exatamente uma'), invariant);
      Assert.isTrue(openLinked.contains('exatamente uma'), openLinked);
      Assert.isTrue(bankError.contains('recíprocos'), bankError);
      Assert.isTrue(cardError.contains('recíprocos'), cardError);
    }
  }

  @IsTest
  static void reciprocalLinksAreAcceptedAndDeletesAreBlocked() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      Id accountId = holder().Id;
      AXF_OBJ_CashFlow__c bankFlow = AXF_CLS_CashFlowTestFactory.buildCashFlow(
        true,
        accountId,
        'Bank flow',
        50,
        Date.today(),
        'PENDENTE'
      );
      AXF_OBJ_CashFlow__c cardFlow = AXF_CLS_CashFlowTestFactory.buildCashFlow(
        true,
        accountId,
        'Card flow',
        80,
        Date.today(),
        'PENDENTE'
      );
      insert new List<AXF_OBJ_CashFlow__c>{ bankFlow, cardFlow };

      AXF_OBJ_BankAccountTransaction__c bank = bankTransaction();
      AXF_OBJ_CreditCardTransaction__c card = cardTransaction();

      Test.startTest();
      // Direct transaction-side links without a reciprocal Cash Flow are rejected.
      bank.AXF_BAT_LKP_CashFlow__c = bankFlow.Id;
      bank.AXF_BAT_PKL_ReconciliationStatus__c = 'RECONCILED';
      String bankDirect = saveError(bank, false);
      card.AXF_CCT_LKP_CashFlow__c = cardFlow.Id;
      card.AXF_CCT_PKL_ReconciliationStatus__c = 'RECONCILED';
      String cardDirect = saveError(card, false);

      // Transaction side written by the service operation, then the Cash Flow side validates.
      ALT_CLS_CashFlowSettlement.serviceOperation = true;
      update bank;
      update card;
      ALT_CLS_CashFlowSettlement.serviceOperation = false;
      bankFlow.AXF_CF_LKP_BankAccountTransaction__c = bank.Id;
      bankFlow.AXF_CF_PKL_ReconciliationStatus__c = 'RECONCILED';
      cardFlow.AXF_CF_LKP_CreditCardTransaction__c = card.Id;
      cardFlow.AXF_CF_PKL_ReconciliationStatus__c = 'RECONCILED';
      update new List<AXF_OBJ_CashFlow__c>{ bankFlow, cardFlow };

      // Re-saving the transaction now finds a reciprocal Cash Flow.
      bank.AXF_BAT_TXT_Description__c = 'Mercado editado';
      update bank;

      List<Database.DeleteResult> deletes = Database.delete(
        new List<SObject>{ bankFlow, bank, card },
        false
      );
      Test.stopTest();

      Assert.isTrue(bankDirect.contains('recíprocos'), bankDirect);
      Assert.isTrue(cardDirect.contains('recíprocos'), cardDirect);
      Assert.areEqual(
        'RECONCILED',
        [
          SELECT AXF_CF_PKL_ReconciliationStatus__c
          FROM AXF_OBJ_CashFlow__c
          WHERE Id = :cardFlow.Id
        ]
        .AXF_CF_PKL_ReconciliationStatus__c
      );
      for (Database.DeleteResult result : deletes) {
        Assert.isFalse(
          result.isSuccess(),
          'Reconciled records cannot be deleted'
        );
        Assert.isTrue(
          result.getErrors()[0].getMessage().contains('Desfaça a conciliação')
        );
      }
    }
  }

  @IsTest
  static void transactionStatusMustMatchLink() {
    System.runAs(AXF_CLS_CashFlowTestFactory.getDomainUser()) {
      AXF_OBJ_BankAccount__c bankAccount = [
        SELECT Id
        FROM AXF_OBJ_BankAccount__c
        LIMIT 1
      ];
      AXF_OBJ_CreditCard__c creditCard = [
        SELECT Id
        FROM AXF_OBJ_CreditCard__c
        LIMIT 1
      ];
      AXF_OBJ_BankAccountTransaction__c bank = AXF_CLS_CashFlowTestFactory.buildBankTransaction(
        bankAccount.Id,
        'TRG_BAT_2',
        10,
        Date.today(),
        'x'
      );
      bank.AXF_BAT_PKL_ReconciliationStatus__c = 'RECONCILED';
      AXF_OBJ_CreditCardTransaction__c card = AXF_CLS_CashFlowTestFactory.buildCardTransaction(
        creditCard.Id,
        'TRG_CCT_2',
        10,
        Date.today(),
        'y'
      );
      card.AXF_CCT_PKL_ReconciliationStatus__c = 'RECONCILED';
      AXF_OBJ_BankAccountTransaction__c freeBank = AXF_CLS_CashFlowTestFactory.buildBankTransaction(
        bankAccount.Id,
        'TRG_BAT_3',
        10,
        Date.today(),
        'z'
      );

      Test.startTest();
      String bankError = saveError(bank, true);
      String cardError = saveError(card, true);
      insert freeBank;
      delete freeBank;
      Test.stopTest();

      Assert.isTrue(bankError.contains('atualizados juntos'), bankError);
      Assert.isTrue(cardError.contains('atualizados juntos'), cardError);
      Assert.areEqual(
        0,
        [
          SELECT COUNT()
          FROM AXF_OBJ_BankAccountTransaction__c
          WHERE Id = :freeBank.Id
        ]
      );
    }
  }
}
