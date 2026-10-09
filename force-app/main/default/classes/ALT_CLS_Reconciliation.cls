/**
 * @description Reconciles an Entry (Lançamento) with one bank account transaction or one credit
 * card transaction (1 Entry : 1 transaction), and undoes it. Compatibility (E6-2): an Entry with a
 * card only reconciles with a card transaction, an Entry without a card only with a bank account
 * transaction; the Entry of an invoice (E6-3) is the exception: it carries the card but is paid
 * from the bank account, so it reconciles with a bank account transaction. Reconciling turns the
 * Entry into Realized with the transaction date and the realized amount in BRL, and the
 * transaction into Reconciled; undoing reverts all of it. Batches are partial: each pair succeeds
 * or fails on its own, with the reason in its result. Runs with the caller's sharing and CRUD/FLS.
 */
public with sharing class ALT_CLS_Reconciliation {
  public class Pair {
    public Id entryId;
    public Id bankTransactionId;
    public Id cardTransactionId;

    public Pair(Id entryId, Id bankTransactionId, Id cardTransactionId) {
      this.entryId = entryId;
      this.bankTransactionId = bankTransactionId;
      this.cardTransactionId = cardTransactionId;
    }
  }

  public class Outcome {
    public Id entryId;
    public Boolean success = false;
    public String message;
  }

  private static final String ENTRY_PENDING = 'Pending';
  private static final String ENTRY_REALIZED = 'Realized';
  private static final String TX_PENDING = 'Pending';
  private static final String TX_RECONCILED = 'Reconciled';

  public List<Outcome> reconcile(List<Pair> pairs) {
    List<Outcome> outcomes = new List<Outcome>();
    Map<Id, Outcome> byEntry = new Map<Id, Outcome>();
    List<Pair> candidates = new List<Pair>();
    Set<Id> seenEntries = new Set<Id>();
    Set<Id> seenTransactions = new Set<Id>();
    for (Pair pair : pairs == null ? new List<Pair>() : pairs) {
      Outcome outcome = new Outcome();
      outcome.entryId = pair.entryId;
      outcomes.add(outcome);
      Id transactionId = pair.bankTransactionId == null
        ? pair.cardTransactionId
        : pair.bankTransactionId;
      if (
        pair.entryId == null ||
        (pair.bankTransactionId == null) == (pair.cardTransactionId == null)
      ) {
        outcome.message = 'Informe o lançamento e exatamente uma transação.';
      } else if (
        !seenEntries.add(pair.entryId) || !seenTransactions.add(transactionId)
      ) {
        outcome.message = 'Lançamento ou transação repetidos no mesmo lote.';
      } else {
        candidates.add(pair);
        byEntry.put(pair.entryId, outcome);
      }
    }
    if (candidates.isEmpty()) {
      return outcomes;
    }
    Map<Id, AXF_OBJ_Entry__c> entries = lockEntries(byEntry.keySet());
    Set<Id> bankIds = new Set<Id>();
    Set<Id> cardIds = new Set<Id>();
    for (Pair pair : candidates) {
      if (pair.bankTransactionId != null) {
        bankIds.add(pair.bankTransactionId);
      } else {
        cardIds.add(pair.cardTransactionId);
      }
    }
    Map<Id, AXF_OBJ_BankAccountTransaction__c> bankTransactions = lockBank(
      bankIds
    );
    Map<Id, AXF_OBJ_CreditCardTransaction__c> cardTransactions = lockCard(
      cardIds
    );
    Set<Id> linked = alreadyLinked(bankIds, cardIds);
    List<AXF_OBJ_Entry__c> entryUpdates = new List<AXF_OBJ_Entry__c>();
    List<SObject> transactionUpdates = new List<SObject>();
    Map<Id, Id> entryByTransaction = new Map<Id, Id>();
    for (Pair pair : candidates) {
      Outcome outcome = byEntry.get(pair.entryId);
      AXF_OBJ_Entry__c entry = entries.get(pair.entryId);
      String problem = check(
        pair,
        entry,
        bankTransactions,
        cardTransactions,
        linked
      );
      if (problem != null) {
        outcome.message = problem;
        continue;
      }
      AXF_OBJ_Entry__c changes = new AXF_OBJ_Entry__c(
        Id = entry.Id,
        AXF_ENT_PKL_Status__c = ENTRY_REALIZED
      );
      AXF_OBJ_BankAccountTransaction__c bank = bankTransactions.get(
        pair.bankTransactionId
      );
      AXF_OBJ_CreditCardTransaction__c card = cardTransactions.get(
        pair.cardTransactionId
      );
      if (bank != null) {
        changes.AXF_ENT_LKP_BankAccountTransaction__c = bank.Id;
        changes.AXF_ENT_DAT_PaymentDate__c = bank.AXF_BAT_DAT_Date__c;
        changes.AXF_ENT_NUM_RealizedAmountBRL__c = amountOf(
          bank.AXF_BAT_CUR_Amount__c
        );
        if (
          entry.AXF_ENT_LKP_BankAccount__c == null &&
          entry.AXF_ENT_LKP_CreditCard__c == null
        ) {
          changes.AXF_ENT_LKP_BankAccount__c = bank.AXF_BAT_MD_BankAccount__c;
        }
        transactionUpdates.add(
          new AXF_OBJ_BankAccountTransaction__c(
            Id = bank.Id,
            AXF_BAT_PKL_ReconciliationStatus__c = TX_RECONCILED
          )
        );
        entryByTransaction.put(bank.Id, entry.Id);
      } else {
        changes.AXF_ENT_LKP_CreditCardTransaction__c = card.Id;
        changes.AXF_ENT_DAT_PaymentDate__c = card.AXF_CCT_DAT_Date__c;
        changes.AXF_ENT_NUM_RealizedAmountBRL__c = amountOf(
          card.AXF_CCT_CUR_AmountBRL__c == null
            ? card.AXF_CCT_CUR_Amount__c
            : card.AXF_CCT_CUR_AmountBRL__c
        );
        if (entry.AXF_ENT_LKP_CreditCard__c == null) {
          changes.AXF_ENT_LKP_CreditCard__c = card.AXF_CCT_MD_CreditCard__c;
        }
        transactionUpdates.add(
          new AXF_OBJ_CreditCardTransaction__c(
            Id = card.Id,
            AXF_CCT_PKL_ReconciliationStatus__c = TX_RECONCILED
          )
        );
        entryByTransaction.put(card.Id, entry.Id);
      }
      entryUpdates.add(changes);
    }
    save(entryUpdates, transactionUpdates, byEntry, entryByTransaction);
    return outcomes;
  }

  public List<Outcome> unreconcile(List<Id> entryIds) {
    List<Outcome> outcomes = new List<Outcome>();
    Map<Id, Outcome> byEntry = new Map<Id, Outcome>();
    for (Id entryId : entryIds == null ? new List<Id>() : entryIds) {
      Outcome outcome = new Outcome();
      outcome.entryId = entryId;
      outcomes.add(outcome);
      if (entryId == null || byEntry.containsKey(entryId)) {
        outcome.message = 'Informe cada lançamento uma única vez.';
      } else {
        byEntry.put(entryId, outcome);
      }
    }
    if (byEntry.isEmpty()) {
      return outcomes;
    }
    List<AXF_OBJ_Entry__c> entryUpdates = new List<AXF_OBJ_Entry__c>();
    List<SObject> transactionUpdates = new List<SObject>();
    Map<Id, Id> entryByTransaction = new Map<Id, Id>();
    for (AXF_OBJ_Entry__c entry : lockEntries(byEntry.keySet()).values()) {
      Outcome outcome = byEntry.get(entry.Id);
      if (
        entry.AXF_ENT_LKP_BankAccountTransaction__c == null &&
        entry.AXF_ENT_LKP_CreditCardTransaction__c == null
      ) {
        outcome.message = 'O lançamento não está conciliado.';
        continue;
      }
      entryUpdates.add(
        new AXF_OBJ_Entry__c(
          Id = entry.Id,
          AXF_ENT_PKL_Status__c = ENTRY_PENDING,
          AXF_ENT_DAT_PaymentDate__c = null,
          AXF_ENT_NUM_RealizedAmountBRL__c = null,
          AXF_ENT_LKP_BankAccountTransaction__c = null,
          AXF_ENT_LKP_CreditCardTransaction__c = null
        )
      );
      if (entry.AXF_ENT_LKP_BankAccountTransaction__c != null) {
        transactionUpdates.add(
          new AXF_OBJ_BankAccountTransaction__c(
            Id = entry.AXF_ENT_LKP_BankAccountTransaction__c,
            AXF_BAT_PKL_ReconciliationStatus__c = TX_PENDING
          )
        );
        entryByTransaction.put(
          entry.AXF_ENT_LKP_BankAccountTransaction__c,
          entry.Id
        );
      } else {
        transactionUpdates.add(
          new AXF_OBJ_CreditCardTransaction__c(
            Id = entry.AXF_ENT_LKP_CreditCardTransaction__c,
            AXF_CCT_PKL_ReconciliationStatus__c = TX_PENDING
          )
        );
        entryByTransaction.put(
          entry.AXF_ENT_LKP_CreditCardTransaction__c,
          entry.Id
        );
      }
    }
    for (Outcome outcome : byEntry.values()) {
      if (outcome.message == null && !hasEntry(entryUpdates, outcome.entryId)) {
        outcome.message = 'Lançamento não encontrado ou sem acesso.';
      }
    }
    save(entryUpdates, transactionUpdates, byEntry, entryByTransaction);
    return outcomes;
  }

  private Decimal amountOf(Decimal value) {
    return value == null ? 0 : value.abs();
  }

  private Boolean hasEntry(List<AXF_OBJ_Entry__c> updates, Id entryId) {
    for (AXF_OBJ_Entry__c change : updates) {
      if (change.Id == entryId) {
        return true;
      }
    }
    return false;
  }

  // Entry rows first, then the transactions of the entries that saved; an entry whose
  // transaction fails to save is rolled back so the two sides never disagree.
  private void save(
    List<AXF_OBJ_Entry__c> entryUpdates,
    List<SObject> transactionUpdates,
    Map<Id, Outcome> byEntry,
    Map<Id, Id> entryByTransaction
  ) {
    if (entryUpdates.isEmpty()) {
      return;
    }
    Savepoint point = Database.setSavepoint();
    Set<Id> savedEntries = new Set<Id>();
    List<Database.SaveResult> entryResults = Database.update(
      entryUpdates,
      false,
      AccessLevel.USER_MODE
    );
    for (Integer i = 0; i < entryResults.size(); i++) {
      Id entryId = entryUpdates[i].Id;
      if (entryResults[i].isSuccess()) {
        savedEntries.add(entryId);
      } else {
        byEntry.get(entryId).message = entryResults[i].getErrors()[0]
          .getMessage();
      }
    }
    List<SObject> toSave = new List<SObject>();
    for (SObject record : transactionUpdates) {
      if (savedEntries.contains(entryByTransaction.get(record.Id))) {
        toSave.add(record);
      }
    }
    List<Database.SaveResult> transactionResults = Database.update(
      toSave,
      false,
      AccessLevel.USER_MODE
    );
    Boolean failed = false;
    for (Integer i = 0; i < transactionResults.size(); i++) {
      if (!transactionResults[i].isSuccess()) {
        failed = true;
        savedEntries.remove(entryByTransaction.get(toSave[i].Id));
        byEntry.get(entryByTransaction.get(toSave[i].Id))
          .message = transactionResults[i].getErrors()[0].getMessage();
      }
    }
    if (failed) {
      // A partially saved batch is undone and redone without the failed entries.
      Database.rollback(point);
      resave(
        entryUpdates,
        transactionUpdates,
        savedEntries,
        entryByTransaction
      );
    }
    for (Id entryId : savedEntries) {
      byEntry.get(entryId).success = true;
    }
  }

  private void resave(
    List<AXF_OBJ_Entry__c> entryUpdates,
    List<SObject> transactionUpdates,
    Set<Id> keep,
    Map<Id, Id> entryByTransaction
  ) {
    List<AXF_OBJ_Entry__c> entries = new List<AXF_OBJ_Entry__c>();
    for (AXF_OBJ_Entry__c change : entryUpdates) {
      if (keep.contains(change.Id)) {
        entries.add(change);
      }
    }
    List<SObject> transactions = new List<SObject>();
    for (SObject record : transactionUpdates) {
      if (keep.contains(entryByTransaction.get(record.Id))) {
        transactions.add(record);
      }
    }
    update as user entries;
    update as user transactions;
  }

  private String check(
    Pair pair,
    AXF_OBJ_Entry__c entry,
    Map<Id, AXF_OBJ_BankAccountTransaction__c> bankTransactions,
    Map<Id, AXF_OBJ_CreditCardTransaction__c> cardTransactions,
    Set<Id> linked
  ) {
    if (entry == null) {
      return 'Lançamento não encontrado ou sem acesso.';
    }
    if (
      entry.AXF_ENT_PKL_Status__c != ENTRY_PENDING ||
      entry.AXF_ENT_LKP_BankAccountTransaction__c != null ||
      entry.AXF_ENT_LKP_CreditCardTransaction__c != null
    ) {
      return 'O lançamento já está realizado ou conciliado.';
    }
    Boolean byCard =
      entry.AXF_ENT_LKP_CreditCard__c != null &&
      entry.AXF_ENT_LKP_Invoice__c == null;
    if (pair.bankTransactionId != null) {
      AXF_OBJ_BankAccountTransaction__c bank = bankTransactions.get(
        pair.bankTransactionId
      );
      if (bank == null) {
        return 'Transação da conta não encontrada ou sem acesso.';
      }
      if (byCard) {
        return 'Lançamento de cartão só concilia com transação do cartão.';
      }
      if (
        bank.AXF_BAT_PKL_ReconciliationStatus__c != null &&
        bank.AXF_BAT_PKL_ReconciliationStatus__c != TX_PENDING
      ) {
        return 'A transação da conta já foi conciliada ou ignorada.';
      }
      if (linked.contains(bank.Id)) {
        return 'A transação da conta já está ligada a outro lançamento.';
      }
      if (
        entry.AXF_ENT_LKP_BankAccount__c != null &&
        entry.AXF_ENT_LKP_BankAccount__c != bank.AXF_BAT_MD_BankAccount__c
      ) {
        return 'A transação é de outra conta bancária.';
      }
      if (
        entry.AXF_ENT_LKP_BankAccount__c == null &&
        bank.AXF_BAT_MD_BankAccount__r.AXF_BA_MD_Holder__c !=
        entry.AXF_ENT_MD_Holder__c
      ) {
        return 'A conta da transação pertence a outro titular.';
      }
      return null;
    }
    AXF_OBJ_CreditCardTransaction__c card = cardTransactions.get(
      pair.cardTransactionId
    );
    if (card == null) {
      return 'Transação do cartão não encontrada ou sem acesso.';
    }
    if (!byCard) {
      return entry.AXF_ENT_LKP_CreditCard__c == null
        ? 'Lançamento sem cartão só concilia com transação da conta.'
        : 'O lançamento da fatura concilia com o pagamento na conta.';
    }
    if (
      card.AXF_CCT_PKL_ReconciliationStatus__c != null &&
      card.AXF_CCT_PKL_ReconciliationStatus__c != TX_PENDING
    ) {
      return 'A transação do cartão já foi conciliada ou ignorada.';
    }
    if (linked.contains(card.Id)) {
      return 'A transação do cartão já está ligada a outro lançamento.';
    }
    if (entry.AXF_ENT_LKP_CreditCard__c != card.AXF_CCT_MD_CreditCard__c) {
      return 'A transação é de outro cartão.';
    }
    return null;
  }

  // Transactions some Entry already points to, locked by the Entry rows that hold the lookups.
  private Set<Id> alreadyLinked(Set<Id> bankIds, Set<Id> cardIds) {
    Set<Id> linked = new Set<Id>();
    for (AXF_OBJ_Entry__c entry : [
      SELECT
        AXF_ENT_LKP_BankAccountTransaction__c,
        AXF_ENT_LKP_CreditCardTransaction__c
      FROM AXF_OBJ_Entry__c
      WHERE
        AXF_ENT_LKP_BankAccountTransaction__c IN :bankIds
        OR AXF_ENT_LKP_CreditCardTransaction__c IN :cardIds
      WITH USER_MODE
    ]) {
      linked.add(entry.AXF_ENT_LKP_BankAccountTransaction__c);
      linked.add(entry.AXF_ENT_LKP_CreditCardTransaction__c);
    }
    return linked;
  }

  private Map<Id, AXF_OBJ_Entry__c> lockEntries(Set<Id> ids) {
    return new Map<Id, AXF_OBJ_Entry__c>(
      [
        SELECT
          AXF_ENT_PKL_Status__c,
          AXF_ENT_MD_Holder__c,
          AXF_ENT_LKP_BankAccount__c,
          AXF_ENT_LKP_CreditCard__c,
          AXF_ENT_LKP_Invoice__c,
          AXF_ENT_LKP_BankAccountTransaction__c,
          AXF_ENT_LKP_CreditCardTransaction__c
        FROM AXF_OBJ_Entry__c
        WHERE Id IN :ids
        WITH USER_MODE
        FOR UPDATE
      ]
    );
  }

  private Map<Id, AXF_OBJ_BankAccountTransaction__c> lockBank(Set<Id> ids) {
    return new Map<Id, AXF_OBJ_BankAccountTransaction__c>(
      [
        SELECT
          AXF_BAT_DAT_Date__c,
          AXF_BAT_CUR_Amount__c,
          AXF_BAT_MD_BankAccount__c,
          AXF_BAT_MD_BankAccount__r.AXF_BA_MD_Holder__c,
          AXF_BAT_PKL_ReconciliationStatus__c
        FROM AXF_OBJ_BankAccountTransaction__c
        WHERE Id IN :ids
        WITH USER_MODE
        FOR UPDATE
      ]
    );
  }

  private Map<Id, AXF_OBJ_CreditCardTransaction__c> lockCard(Set<Id> ids) {
    return new Map<Id, AXF_OBJ_CreditCardTransaction__c>(
      [
        SELECT
          AXF_CCT_DAT_Date__c,
          AXF_CCT_CUR_Amount__c,
          AXF_CCT_CUR_AmountBRL__c,
          AXF_CCT_MD_CreditCard__c,
          AXF_CCT_PKL_ReconciliationStatus__c
        FROM AXF_OBJ_CreditCardTransaction__c
        WHERE Id IN :ids
        WITH USER_MODE
        FOR UPDATE
      ]
    );
  }
}
