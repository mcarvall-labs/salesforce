/**
 * @description Actions on transactions that have no Entry (Lançamento) to match (E6-7, E6-8).
 * Ignore: the transaction gets the Ignored reconciliation status and leaves the queue (for example
 * a transfer between the holder's own accounts). Create Entry: the transaction becomes an Entry
 * that is born Realized and reconciled: type by the sign of the amount, payment and due date from
 * the transaction date, realized amount in BRL, no category (the user classifies it later), no
 * invoice (a card purchase is paid by the invoice Entry, so it does not affect cash). Both act on
 * transactions that are Pending (or without status) and not linked to an Entry, in batches with one
 * outcome per transaction. Runs with the caller's sharing and CRUD/FLS; only the duplicate-link
 * check ignores sharing.
 */
public with sharing class ALT_CLS_ReconciliationActions {
  public class Outcome {
    public Id transactionId;
    public Id entryId;
    public Boolean success = false;
    public String message;
  }

  private without sharing class LinkLookup {
    Set<Id> linked(Set<Id> bankIds, Set<Id> cardIds) {
      Set<Id> linked = new Set<Id>();
      for (AXF_OBJ_Entry__c entry : [
        SELECT
          AXF_ENT_LKP_BankAccountTransaction__c,
          AXF_ENT_LKP_CreditCardTransaction__c
        FROM AXF_OBJ_Entry__c
        WHERE
          AXF_ENT_LKP_BankAccountTransaction__c IN :bankIds
          OR AXF_ENT_LKP_CreditCardTransaction__c IN :cardIds
      ]) {
        if (entry.AXF_ENT_LKP_BankAccountTransaction__c != null) {
          linked.add(entry.AXF_ENT_LKP_BankAccountTransaction__c);
        }
        if (entry.AXF_ENT_LKP_CreditCardTransaction__c != null) {
          linked.add(entry.AXF_ENT_LKP_CreditCardTransaction__c);
        }
      }
      return linked;
    }
  }

  // The transactions of one call, locked, with the reason each one cannot be acted on.
  private class Batch {
    List<Outcome> outcomes = new List<Outcome>();
    Map<Id, Outcome> byTransaction = new Map<Id, Outcome>();
    Map<Id, AXF_OBJ_BankAccountTransaction__c> banks;
    Map<Id, AXF_OBJ_CreditCardTransaction__c> cards;
    Set<Id> linked;
    // Transactions that passed every check, in request order.
    List<Id> eligible = new List<Id>();
  }

  private static final String PENDING = 'Pending';
  private static final String IGNORED = 'Ignored';
  private static final String RECONCILED = 'Reconciled';

  public List<Outcome> ignore(List<Id> bankIds, List<Id> cardIds) {
    Batch batch = open(bankIds, cardIds);
    List<AXF_OBJ_BankAccountTransaction__c> bankUpdates = new List<AXF_OBJ_BankAccountTransaction__c>();
    List<AXF_OBJ_CreditCardTransaction__c> cardUpdates = new List<AXF_OBJ_CreditCardTransaction__c>();
    for (Id id : batch.eligible) {
      if (batch.banks.containsKey(id)) {
        bankUpdates.add(
          new AXF_OBJ_BankAccountTransaction__c(
            Id = id,
            AXF_BAT_PKL_ReconciliationStatus__c = IGNORED
          )
        );
      } else {
        cardUpdates.add(
          new AXF_OBJ_CreditCardTransaction__c(
            Id = id,
            AXF_CCT_PKL_ReconciliationStatus__c = IGNORED
          )
        );
      }
    }
    List<Database.SaveResult> bankResults = Database.update(
      bankUpdates,
      false,
      AccessLevel.USER_MODE
    );
    for (Integer i = 0; i < bankResults.size(); i++) {
      record(batch, bankUpdates[i].Id, bankResults[i]);
    }
    List<Database.SaveResult> cardResults = Database.update(
      cardUpdates,
      false,
      AccessLevel.USER_MODE
    );
    for (Integer i = 0; i < cardResults.size(); i++) {
      record(batch, cardUpdates[i].Id, cardResults[i]);
    }
    return batch.outcomes;
  }

  public List<Outcome> createEntries(List<Id> bankIds, List<Id> cardIds) {
    Batch batch = open(bankIds, cardIds);
    Map<Id, AXF_OBJ_Entry__c> entries = new Map<Id, AXF_OBJ_Entry__c>();
    for (Id id : batch.eligible) {
      if (batch.banks.containsKey(id)) {
        entries.put(id, fromBank(batch.banks.get(id)));
      } else {
        entries.put(id, fromCard(batch.cards.get(id)));
      }
    }
    // Entries and the Reconciled mark of their transactions go in together; a transaction that
    // fails to save rolls the attempt back and it is retried without that one.
    Set<Id> excluded = new Set<Id>();
    for (Integer attempt = 0; attempt <= entries.size(); attempt++) {
      List<Id> ids = new List<Id>();
      for (Id id : batch.eligible) {
        if (!excluded.contains(id)) {
          ids.add(id);
        }
      }
      if (ids.isEmpty()) {
        break;
      }
      Savepoint point = Database.setSavepoint();
      Set<Id> failed = insertAndMark(ids, entries, batch);
      if (failed.isEmpty()) {
        break;
      }
      Database.rollback(point);
      excluded.addAll(failed);
      for (Id id : failed) {
        batch.byTransaction.get(id).success = false;
        batch.byTransaction.get(id).entryId = null;
      }
    }
    return batch.outcomes;
  }

  private Set<Id> insertAndMark(
    List<Id> ids,
    Map<Id, AXF_OBJ_Entry__c> entries,
    Batch batch
  ) {
    Set<Id> failed = new Set<Id>();
    List<AXF_OBJ_Entry__c> toInsert = new List<AXF_OBJ_Entry__c>();
    for (Id id : ids) {
      toInsert.add(entries.get(id).clone(false, true, false, false));
    }
    List<Database.SaveResult> inserted = Database.insert(
      toInsert,
      false,
      AccessLevel.USER_MODE
    );
    List<AXF_OBJ_BankAccountTransaction__c> bankUpdates = new List<AXF_OBJ_BankAccountTransaction__c>();
    List<AXF_OBJ_CreditCardTransaction__c> cardUpdates = new List<AXF_OBJ_CreditCardTransaction__c>();
    for (Integer i = 0; i < inserted.size(); i++) {
      Id id = ids[i];
      Outcome outcome = batch.byTransaction.get(id);
      if (!inserted[i].isSuccess()) {
        outcome.message = inserted[i].getErrors()[0].getMessage();
        failed.add(id);
      } else {
        outcome.entryId = inserted[i].getId();
        outcome.success = true;
        if (batch.banks.containsKey(id)) {
          bankUpdates.add(
            new AXF_OBJ_BankAccountTransaction__c(
              Id = id,
              AXF_BAT_PKL_ReconciliationStatus__c = RECONCILED
            )
          );
        } else {
          cardUpdates.add(
            new AXF_OBJ_CreditCardTransaction__c(
              Id = id,
              AXF_CCT_PKL_ReconciliationStatus__c = RECONCILED
            )
          );
        }
      }
    }
    List<Database.SaveResult> bankResults = Database.update(
      bankUpdates,
      false,
      AccessLevel.USER_MODE
    );
    for (Integer i = 0; i < bankResults.size(); i++) {
      if (!bankResults[i].isSuccess()) {
        failed.add(bankUpdates[i].Id);
        batch.byTransaction.get(bankUpdates[i].Id).message = bankResults[i]
            .getErrors()[0]
          .getMessage();
      }
    }
    List<Database.SaveResult> cardResults = Database.update(
      cardUpdates,
      false,
      AccessLevel.USER_MODE
    );
    for (Integer i = 0; i < cardResults.size(); i++) {
      if (!cardResults[i].isSuccess()) {
        failed.add(cardUpdates[i].Id);
        batch.byTransaction.get(cardUpdates[i].Id).message = cardResults[i]
            .getErrors()[0]
          .getMessage();
      }
    }
    return failed;
  }

  private void record(Batch batch, Id id, Database.SaveResult result) {
    Outcome outcome = batch.byTransaction.get(id);
    if (result.isSuccess()) {
      outcome.success = true;
    } else {
      outcome.message = result.getErrors()[0].getMessage();
    }
  }

  // Locks the transactions and marks each request as eligible or with the reason it is not.
  private Batch open(List<Id> bankIds, List<Id> cardIds) {
    Batch batch = new Batch();
    List<Id> requested = new List<Id>();
    Set<Id> bankSet = new Set<Id>();
    Set<Id> cardSet = new Set<Id>();
    for (Id id : bankIds == null ? new List<Id>() : bankIds) {
      requested.add(id);
      bankSet.add(id);
    }
    for (Id id : cardIds == null ? new List<Id>() : cardIds) {
      requested.add(id);
      cardSet.add(id);
    }
    bankSet.remove(null);
    cardSet.remove(null);
    batch.banks = lockBank(bankSet);
    batch.cards = lockCard(cardSet);
    batch.linked = new LinkLookup().linked(bankSet, cardSet);
    for (Id id : requested) {
      Outcome outcome = new Outcome();
      outcome.transactionId = id;
      batch.outcomes.add(outcome);
      if (id == null || batch.byTransaction.containsKey(id)) {
        outcome.message = 'Informe cada transação uma única vez.';
        continue;
      }
      batch.byTransaction.put(id, outcome);
      outcome.message = reason(batch, id);
      if (outcome.message == null) {
        batch.eligible.add(id);
      }
    }
    return batch;
  }

  private String reason(Batch batch, Id id) {
    String status;
    Date day;
    Decimal amount;
    if (batch.banks.containsKey(id)) {
      AXF_OBJ_BankAccountTransaction__c bank = batch.banks.get(id);
      status = bank.AXF_BAT_PKL_ReconciliationStatus__c;
      day = bank.AXF_BAT_DAT_Date__c;
      amount = bank.AXF_BAT_CUR_Amount__c;
    } else if (batch.cards.containsKey(id)) {
      AXF_OBJ_CreditCardTransaction__c card = batch.cards.get(id);
      status = card.AXF_CCT_PKL_ReconciliationStatus__c;
      day = card.AXF_CCT_DAT_Date__c;
      amount = card.AXF_CCT_CUR_Amount__c;
      if (
        card.AXF_CCT_CUR_AmountBRL__c == null &&
        card.AXF_CCT_TXT_CurrencyCode__c != null &&
        card.AXF_CCT_TXT_CurrencyCode__c != 'BRL'
      ) {
        return 'A transação do cartão em moeda estrangeira não tem valor em BRL.';
      }
    } else {
      return 'Transação não encontrada ou sem acesso.';
    }
    if (status != null && status != PENDING) {
      return 'A transação já foi conciliada ou ignorada.';
    }
    if (batch.linked.contains(id)) {
      return 'A transação já está ligada a um lançamento.';
    }
    if (day == null || amount == null) {
      return 'A transação não tem data ou valor.';
    }
    return null;
  }

  private AXF_OBJ_Entry__c fromBank(AXF_OBJ_BankAccountTransaction__c bank) {
    AXF_OBJ_Entry__c entry = newEntry(
      bank.AXF_BAT_TXT_Description__c,
      bank.AXF_BAT_MD_BankAccount__r.AXF_BA_MD_Holder__c,
      bank.AXF_BAT_CUR_Amount__c,
      bank.CurrencyIsoCode,
      bank.AXF_BAT_DAT_Date__c,
      bank.AXF_BAT_CUR_Amount__c.abs()
    );
    entry.AXF_ENT_LKP_BankAccount__c = bank.AXF_BAT_MD_BankAccount__c;
    entry.AXF_ENT_LKP_BankAccountTransaction__c = bank.Id;
    return entry;
  }

  private AXF_OBJ_Entry__c fromCard(AXF_OBJ_CreditCardTransaction__c card) {
    Decimal brl = card.AXF_CCT_CUR_AmountBRL__c == null
      ? card.AXF_CCT_CUR_Amount__c
      : card.AXF_CCT_CUR_AmountBRL__c;
    AXF_OBJ_Entry__c entry = newEntry(
      card.AXF_CCT_TXT_Description__c,
      card.AXF_CCT_MD_CreditCard__r.AXF_CC_MD_Holder__c,
      card.AXF_CCT_CUR_Amount__c,
      String.isBlank(card.AXF_CCT_TXT_CurrencyCode__c)
        ? card.CurrencyIsoCode
        : card.AXF_CCT_TXT_CurrencyCode__c,
      card.AXF_CCT_DAT_Date__c,
      brl.abs()
    );
    entry.AXF_ENT_LKP_CreditCard__c = card.AXF_CCT_MD_CreditCard__c;
    entry.AXF_ENT_LKP_CreditCardTransaction__c = card.Id;
    return entry;
  }

  private AXF_OBJ_Entry__c newEntry(
    String description,
    Id holderId,
    Decimal signedAmount,
    String currencyCode,
    Date day,
    Decimal realizedBRL
  ) {
    return new AXF_OBJ_Entry__c(
      Name = String.isBlank(description)
        ? 'Lançamento da transação'
        : description.abbreviate(80),
      AXF_ENT_MD_Holder__c = holderId,
      AXF_ENT_PKL_Type__c = signedAmount < 0 ? 'Expense' : 'Income',
      AXF_ENT_PKL_Status__c = 'Realized',
      CurrencyIsoCode = currencyCode,
      AXF_ENT_CUR_Amount__c = signedAmount.abs(),
      AXF_ENT_DAT_DueDate__c = day,
      AXF_ENT_DAT_PaymentDate__c = day,
      AXF_ENT_NUM_RealizedAmountBRL__c = realizedBRL
    );
  }

  private Map<Id, AXF_OBJ_BankAccountTransaction__c> lockBank(Set<Id> ids) {
    return new Map<Id, AXF_OBJ_BankAccountTransaction__c>(
      [
        SELECT
          AXF_BAT_DAT_Date__c,
          AXF_BAT_CUR_Amount__c,
          AXF_BAT_TXT_Description__c,
          CurrencyIsoCode,
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
          AXF_CCT_TXT_Description__c,
          CurrencyIsoCode,
          AXF_CCT_MD_CreditCard__c,
          AXF_CCT_MD_CreditCard__r.AXF_CC_MD_Holder__c,
          AXF_CCT_PKL_ReconciliationStatus__c
        FROM AXF_OBJ_CreditCardTransaction__c
        WHERE Id IN :ids
        WITH USER_MODE
        FOR UPDATE
      ]
    );
  }
}
