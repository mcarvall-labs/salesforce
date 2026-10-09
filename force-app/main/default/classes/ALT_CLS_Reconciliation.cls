/**
 * @description Reconciles an Entry (Lançamento) with one bank account transaction or one credit
 * card transaction (1 Entry : 1 transaction), and undoes it. Compatibility (E6-2): an Entry with a
 * card only reconciles with a card transaction, an Entry without a card only with a bank account
 * transaction; the Entry of an invoice (E6-3) is the exception: it carries the card but is paid
 * from the bank account, so it reconciles with a bank account transaction. Reconciling turns the
 * Entry into Realized with the transaction date and the realized amount in BRL, and the
 * transaction into Reconciled; undoing clears the link, the payment date and the realized amount,
 * returns the Entry to Pending and the transaction to Pending, and clears the bank account
 * of an Entry without card. Batches are partial: each pair succeeds or fails on its own, with the
 * reason in its result. Runs with the caller's sharing and CRUD/FLS; only the duplicate-link check
 * ignores sharing, because a transaction linked to an Entry the caller cannot see is still linked.
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

  // Everything a batch changes: Entry rows plus the transactions they point to, by Entry.
  private class Changes {
    List<AXF_OBJ_Entry__c> entries = new List<AXF_OBJ_Entry__c>();
    Map<Id, AXF_OBJ_BankAccountTransaction__c> banks = new Map<Id, AXF_OBJ_BankAccountTransaction__c>();
    Map<Id, AXF_OBJ_CreditCardTransaction__c> cards = new Map<Id, AXF_OBJ_CreditCardTransaction__c>();
    Map<Id, Id> entryByTransaction = new Map<Id, Id>();
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
      outcomes.add(outcome);
      if (pair == null) {
        outcome.message = 'Par inválido.';
        continue;
      }
      outcome.entryId = pair.entryId;
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
    Set<Id> linked = new ALT_CLS_ReconciliationLinks().linked(bankIds, cardIds);
    Changes changes = new Changes();
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
      AXF_OBJ_Entry__c change = new AXF_OBJ_Entry__c(
        Id = entry.Id,
        AXF_ENT_PKL_Status__c = ENTRY_REALIZED
      );
      if (pair.bankTransactionId != null) {
        AXF_OBJ_BankAccountTransaction__c bank = bankTransactions.get(
          pair.bankTransactionId
        );
        change.AXF_ENT_LKP_BankAccountTransaction__c = bank.Id;
        change.AXF_ENT_DAT_PaymentDate__c = bank.AXF_BAT_DAT_Date__c;
        change.AXF_ENT_NUM_RealizedAmountBRL__c = bank.AXF_BAT_CUR_Amount__c.abs();
        if (
          entry.AXF_ENT_LKP_BankAccount__c == null &&
          entry.AXF_ENT_LKP_CreditCard__c == null
        ) {
          change.AXF_ENT_LKP_BankAccount__c = bank.AXF_BAT_MD_BankAccount__c;
        }
        changes.banks.put(
          bank.Id,
          new AXF_OBJ_BankAccountTransaction__c(
            Id = bank.Id,
            AXF_BAT_PKL_ReconciliationStatus__c = TX_RECONCILED
          )
        );
        changes.entryByTransaction.put(bank.Id, entry.Id);
      } else {
        AXF_OBJ_CreditCardTransaction__c card = cardTransactions.get(
          pair.cardTransactionId
        );
        change.AXF_ENT_LKP_CreditCardTransaction__c = card.Id;
        change.AXF_ENT_DAT_PaymentDate__c = card.AXF_CCT_DAT_Date__c;
        change.AXF_ENT_NUM_RealizedAmountBRL__c = (card.AXF_CCT_CUR_AmountBRL__c ==
            null
            ? card.AXF_CCT_CUR_Amount__c
            : card.AXF_CCT_CUR_AmountBRL__c)
          .abs();
        changes.cards.put(
          card.Id,
          new AXF_OBJ_CreditCardTransaction__c(
            Id = card.Id,
            AXF_CCT_PKL_ReconciliationStatus__c = TX_RECONCILED
          )
        );
        changes.entryByTransaction.put(card.Id, entry.Id);
      }
      changes.entries.add(change);
    }
    save(changes, byEntry);
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
    Map<Id, AXF_OBJ_Entry__c> entries = lockEntries(byEntry.keySet());
    Set<Id> bankIds = new Set<Id>();
    Set<Id> cardIds = new Set<Id>();
    for (AXF_OBJ_Entry__c entry : entries.values()) {
      if (entry.AXF_ENT_LKP_BankAccountTransaction__c != null) {
        bankIds.add(entry.AXF_ENT_LKP_BankAccountTransaction__c);
      }
      if (entry.AXF_ENT_LKP_CreditCardTransaction__c != null) {
        cardIds.add(entry.AXF_ENT_LKP_CreditCardTransaction__c);
      }
    }
    Map<Id, AXF_OBJ_BankAccountTransaction__c> bankTransactions = lockBank(
      bankIds
    );
    Map<Id, AXF_OBJ_CreditCardTransaction__c> cardTransactions = lockCard(
      cardIds
    );
    Changes changes = new Changes();
    for (Id entryId : byEntry.keySet()) {
      Outcome outcome = byEntry.get(entryId);
      AXF_OBJ_Entry__c entry = entries.get(entryId);
      if (entry == null) {
        outcome.message = 'Lançamento não encontrado ou sem acesso.';
      } else if (
        entry.AXF_ENT_PKL_Status__c != ENTRY_REALIZED ||
        (entry.AXF_ENT_LKP_BankAccountTransaction__c == null &&
        entry.AXF_ENT_LKP_CreditCardTransaction__c == null)
      ) {
        outcome.message = 'O lançamento não está conciliado.';
      } else {
        changes.entries.add(
          new AXF_OBJ_Entry__c(
            Id = entry.Id,
            AXF_ENT_PKL_Status__c = ENTRY_PENDING,
            AXF_ENT_DAT_PaymentDate__c = null,
            AXF_ENT_NUM_RealizedAmountBRL__c = null,
            AXF_ENT_LKP_BankAccountTransaction__c = null,
            AXF_ENT_LKP_CreditCardTransaction__c = null,
            AXF_ENT_LKP_BankAccount__c = filledAccount(entry, bankTransactions)
          )
        );
        // Only a transaction that is Reconciled goes back to Pending: an Ignored one stays.
        Id bankId = entry.AXF_ENT_LKP_BankAccountTransaction__c;
        if (
          bankTransactions.containsKey(bankId) &&
          bankTransactions.get(bankId).AXF_BAT_PKL_ReconciliationStatus__c ==
          TX_RECONCILED
        ) {
          changes.banks.put(
            bankId,
            new AXF_OBJ_BankAccountTransaction__c(
              Id = bankId,
              AXF_BAT_PKL_ReconciliationStatus__c = TX_PENDING
            )
          );
          changes.entryByTransaction.put(bankId, entry.Id);
        }
        Id cardId = entry.AXF_ENT_LKP_CreditCardTransaction__c;
        if (
          cardTransactions.containsKey(cardId) &&
          cardTransactions.get(cardId).AXF_CCT_PKL_ReconciliationStatus__c ==
          TX_RECONCILED
        ) {
          changes.cards.put(
            cardId,
            new AXF_OBJ_CreditCardTransaction__c(
              Id = cardId,
              AXF_CCT_PKL_ReconciliationStatus__c = TX_PENDING
            )
          );
          changes.entryByTransaction.put(cardId, entry.Id);
        }
      }
    }
    save(changes, byEntry);
    return outcomes;
  }

  // The account of the reconciled transaction goes back to empty on an Entry without card. An
  // account typed by the user before reconciling is the same account (reconcile only accepts a
  // transaction of the Entry's account), so the two cannot be told apart and both are cleared.
  private Id filledAccount(
    AXF_OBJ_Entry__c entry,
    Map<Id, AXF_OBJ_BankAccountTransaction__c> bankTransactions
  ) {
    AXF_OBJ_BankAccountTransaction__c bank = bankTransactions.get(
      entry.AXF_ENT_LKP_BankAccountTransaction__c
    );
    Boolean filledByReconcile =
      bank != null &&
      entry.AXF_ENT_LKP_CreditCard__c == null &&
      entry.AXF_ENT_LKP_BankAccount__c == bank.AXF_BAT_MD_BankAccount__c;
    return filledByReconcile ? null : entry.AXF_ENT_LKP_BankAccount__c;
  }

  // Entry rows and their transactions go in together: when a transaction fails to save, the
  // whole attempt is rolled back and retried without that Entry, so the two sides never disagree.
  private void save(Changes changes, Map<Id, Outcome> byEntry) {
    Set<Id> excluded = new Set<Id>();
    for (Integer attempt = 0; attempt <= changes.entries.size(); attempt++) {
      if (changes.entries.size() == excluded.size()) {
        return;
      }
      Savepoint point = Database.setSavepoint();
      Set<Id> failed = apply(changes, excluded, byEntry);
      if (failed.isEmpty()) {
        for (AXF_OBJ_Entry__c entry : changes.entries) {
          if (!excluded.contains(entry.Id)) {
            byEntry.get(entry.Id).success = true;
          }
        }
        return;
      }
      Database.rollback(point);
      excluded.addAll(failed);
    }
  }

  // One save attempt for the Entries not in `excluded`; returns the Entries that failed, with the
  // reason already in their outcome.
  private Set<Id> apply(
    Changes changes,
    Set<Id> excluded,
    Map<Id, Outcome> byEntry
  ) {
    Set<Id> failed = new Set<Id>();
    List<AXF_OBJ_Entry__c> entries = new List<AXF_OBJ_Entry__c>();
    for (AXF_OBJ_Entry__c entry : changes.entries) {
      if (!excluded.contains(entry.Id)) {
        entries.add(entry);
      }
    }
    List<Database.SaveResult> entryResults = Database.update(
      entries,
      false,
      AccessLevel.USER_MODE
    );
    for (Integer i = 0; i < entryResults.size(); i++) {
      if (!entryResults[i].isSuccess()) {
        fail(failed, byEntry, entries[i].Id, entryResults[i]);
      }
    }
    List<AXF_OBJ_BankAccountTransaction__c> banks = new List<AXF_OBJ_BankAccountTransaction__c>();
    for (AXF_OBJ_BankAccountTransaction__c bank : changes.banks.values()) {
      Id entryId = changes.entryByTransaction.get(bank.Id);
      if (!excluded.contains(entryId) && !failed.contains(entryId)) {
        banks.add(bank);
      }
    }
    List<Database.SaveResult> bankResults = Database.update(
      banks,
      false,
      AccessLevel.USER_MODE
    );
    for (Integer i = 0; i < bankResults.size(); i++) {
      if (!bankResults[i].isSuccess()) {
        fail(
          failed,
          byEntry,
          changes.entryByTransaction.get(banks[i].Id),
          bankResults[i]
        );
      }
    }
    List<AXF_OBJ_CreditCardTransaction__c> cards = new List<AXF_OBJ_CreditCardTransaction__c>();
    for (AXF_OBJ_CreditCardTransaction__c card : changes.cards.values()) {
      Id entryId = changes.entryByTransaction.get(card.Id);
      if (!excluded.contains(entryId) && !failed.contains(entryId)) {
        cards.add(card);
      }
    }
    List<Database.SaveResult> cardResults = Database.update(
      cards,
      false,
      AccessLevel.USER_MODE
    );
    for (Integer i = 0; i < cardResults.size(); i++) {
      if (!cardResults[i].isSuccess()) {
        fail(
          failed,
          byEntry,
          changes.entryByTransaction.get(cards[i].Id),
          cardResults[i]
        );
      }
    }
    return failed;
  }

  private void fail(
    Set<Id> failed,
    Map<Id, Outcome> byEntry,
    Id entryId,
    Database.SaveResult result
  ) {
    failed.add(entryId);
    byEntry.get(entryId).message = result.getErrors()[0].getMessage();
  }

  // Amount of the transaction of the pair with its sign (debit negative); null when not found.
  private Decimal signedAmount(
    Pair pair,
    Map<Id, AXF_OBJ_BankAccountTransaction__c> bankTransactions,
    Map<Id, AXF_OBJ_CreditCardTransaction__c> cardTransactions
  ) {
    if (pair.bankTransactionId != null) {
      AXF_OBJ_BankAccountTransaction__c bank = bankTransactions.get(
        pair.bankTransactionId
      );
      return bank == null ? null : bank.AXF_BAT_CUR_Amount__c;
    }
    AXF_OBJ_CreditCardTransaction__c card = cardTransactions.get(
      pair.cardTransactionId
    );
    return card == null ? null : card.AXF_CCT_CUR_Amount__c;
  }

  // Expense with an outflow (debit) and income with an inflow (credit), nothing else.
  private Boolean sameDirection(AXF_OBJ_Entry__c entry, Decimal signed) {
    return entry.AXF_ENT_PKL_Type__c == 'Expense' ? signed < 0 : signed > 0;
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
    Decimal signed = signedAmount(pair, bankTransactions, cardTransactions);
    if (signed != null && !sameDirection(entry, signed)) {
      return 'Despesa só concilia com saída (débito) e receita só com entrada (crédito).';
    }
    Boolean byCard =
      entry.AXF_ENT_LKP_CreditCard__c != null &&
      entry.AXF_ENT_LKP_Invoice__c == null;
    if (pair.bankTransactionId != null) {
      return checkBank(
        entry,
        byCard,
        bankTransactions.get(pair.bankTransactionId),
        linked
      );
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
    if (card.AXF_CCT_DAT_Date__c == null) {
      return 'A transação do cartão não tem data.';
    }
    if (card.AXF_CCT_CUR_Amount__c == null) {
      return 'A transação do cartão não tem valor.';
    }
    if (
      card.AXF_CCT_CUR_AmountBRL__c == null &&
      card.AXF_CCT_TXT_CurrencyCode__c != null &&
      card.AXF_CCT_TXT_CurrencyCode__c != 'BRL'
    ) {
      return 'A transação do cartão em moeda estrangeira não tem valor em BRL.';
    }
    return null;
  }

  private String checkBank(
    AXF_OBJ_Entry__c entry,
    Boolean byCard,
    AXF_OBJ_BankAccountTransaction__c bank,
    Set<Id> linked
  ) {
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
      (bank.AXF_BAT_MD_BankAccount__r == null ||
      bank.AXF_BAT_MD_BankAccount__r.AXF_BA_MD_Holder__c !=
      entry.AXF_ENT_MD_Holder__c)
    ) {
      return 'A conta da transação pertence a outro titular ou não está acessível.';
    }
    if (bank.AXF_BAT_DAT_Date__c == null) {
      return 'A transação da conta não tem data.';
    }
    if (bank.AXF_BAT_CUR_Amount__c == null) {
      return 'A transação da conta não tem valor.';
    }
    return null;
  }

  private Map<Id, AXF_OBJ_Entry__c> lockEntries(Set<Id> ids) {
    return new Map<Id, AXF_OBJ_Entry__c>(
      [
        SELECT
          AXF_ENT_PKL_Status__c,
          AXF_ENT_PKL_Type__c,
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
          AXF_CCT_TXT_CurrencyCode__c,
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
