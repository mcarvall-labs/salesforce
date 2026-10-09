/**
 * @description Suggests Entry (Lançamento) x transaction pairs to reconcile (E6-5); nothing is
 * saved or reconciled here, the user confirms each pair (or the batch) afterwards. A pair is
 * suggested when the Entry is Pending and due inside the requested range, the transaction is Pending or without status (and not linked), the payment
 * rules of ALT_CLS_Reconciliation allow it (E6-2: card Entry x card transaction, Entry without
 * card x bank transaction, invoice Entry x bank transaction), the Account/Card matches (any
 * account of the holder when the Entry has none, which is also the invoice case), the transaction
 * date is within 7 days of the due date and the amounts match: equal in the same currency, or
 * within 5 % when compared in BRL across currencies. Each Entry and each transaction appears in at
 * most one suggestion, the closest in date and then in amount first. Runs with the caller's
 * sharing and CRUD/FLS.
 */
public with sharing class ALT_CLS_ReconciliationSuggestions {
  public class Suggestion {
    public Id entryId;
    public Id bankTransactionId;
    public Id cardTransactionId;
    public Integer daysApart;
    public Boolean crossCurrency = false;
  }

  public static final Integer WINDOW_DAYS = 7;
  public static final Decimal TOLERANCE = 0.05;
  private static final String BRL = 'BRL';
  private static final Decimal CENT = 0.005;
  private static final Integer MAX_ROWS = 2000;

  // Units of each currency per 1 BRL (CurrencyType.ConversionRate, corporate currency BRL).
  @TestVisible
  private static Map<String, Decimal> rateOverride;

  private class Candidate {
    Suggestion suggestion;
    Decimal amountGap;
  }

  public List<Suggestion> suggest(Id holderId, Date fromDate, Date toDate) {
    if (
      holderId == null ||
      fromDate == null ||
      toDate == null ||
      fromDate > toDate
    ) {
      return new List<Suggestion>();
    }
    Date earliest = fromDate.addDays(-WINDOW_DAYS);
    Date latest = toDate.addDays(WINDOW_DAYS);
    List<AXF_OBJ_Entry__c> entries = [
      SELECT
        CurrencyIsoCode,
        AXF_ENT_PKL_Type__c,
        AXF_ENT_CUR_Amount__c,
        AXF_ENT_DAT_DueDate__c,
        AXF_ENT_LKP_BankAccount__c,
        AXF_ENT_LKP_CreditCard__c,
        AXF_ENT_LKP_Invoice__c
      FROM AXF_OBJ_Entry__c
      WHERE
        AXF_ENT_MD_Holder__c = :holderId
        AND AXF_ENT_PKL_Status__c = 'Pending'
        AND AXF_ENT_LKP_BankAccountTransaction__c = NULL
        AND AXF_ENT_LKP_CreditCardTransaction__c = NULL
        AND AXF_ENT_DAT_DueDate__c >= :fromDate
        AND AXF_ENT_DAT_DueDate__c <= :toDate
        AND AXF_ENT_CUR_Amount__c != NULL
      WITH USER_MODE
      ORDER BY AXF_ENT_DAT_DueDate__c, Id
      LIMIT :MAX_ROWS
    ];
    List<AXF_OBJ_BankAccountTransaction__c> banks = [
      SELECT
        CurrencyIsoCode,
        AXF_BAT_CUR_Amount__c,
        AXF_BAT_DAT_Date__c,
        AXF_BAT_MD_BankAccount__c
      FROM AXF_OBJ_BankAccountTransaction__c
      WHERE
        AXF_BAT_MD_BankAccount__r.AXF_BA_MD_Holder__c = :holderId
        AND (AXF_BAT_PKL_ReconciliationStatus__c = NULL
        OR AXF_BAT_PKL_ReconciliationStatus__c = 'Pending')
        AND AXF_BAT_DAT_Date__c >= :earliest
        AND AXF_BAT_DAT_Date__c <= :latest
        AND Id NOT IN (
          SELECT AXF_ENT_LKP_BankAccountTransaction__c
          FROM AXF_OBJ_Entry__c
          WHERE AXF_ENT_LKP_BankAccountTransaction__c != NULL
        )
      WITH USER_MODE
      ORDER BY AXF_BAT_DAT_Date__c, Id
      LIMIT :MAX_ROWS
    ];
    List<AXF_OBJ_CreditCardTransaction__c> cards = [
      SELECT
        CurrencyIsoCode,
        AXF_CCT_CUR_Amount__c,
        AXF_CCT_CUR_AmountBRL__c,
        AXF_CCT_TXT_CurrencyCode__c,
        AXF_CCT_DAT_Date__c,
        AXF_CCT_MD_CreditCard__c
      FROM AXF_OBJ_CreditCardTransaction__c
      WHERE
        AXF_CCT_MD_CreditCard__r.AXF_CC_MD_Holder__c = :holderId
        AND (AXF_CCT_PKL_ReconciliationStatus__c = NULL
        OR AXF_CCT_PKL_ReconciliationStatus__c = 'Pending')
        AND AXF_CCT_DAT_Date__c >= :earliest
        AND AXF_CCT_DAT_Date__c <= :latest
        AND Id NOT IN (
          SELECT AXF_ENT_LKP_CreditCardTransaction__c
          FROM AXF_OBJ_Entry__c
          WHERE AXF_ENT_LKP_CreditCardTransaction__c != NULL
        )
      WITH USER_MODE
      ORDER BY AXF_CCT_DAT_Date__c, Id
      LIMIT :MAX_ROWS
    ];
    Map<String, Decimal> rates = rates(entries, banks, cards);
    Map<Id, Candidate> bestByEntry = new Map<Id, Candidate>();
    List<Candidate> all = new List<Candidate>();
    for (AXF_OBJ_Entry__c entry : entries) {
      Boolean byCard =
        entry.AXF_ENT_LKP_CreditCard__c != null &&
        entry.AXF_ENT_LKP_Invoice__c == null;
      if (byCard) {
        for (AXF_OBJ_CreditCardTransaction__c card : cards) {
          if (
            entry.AXF_ENT_LKP_CreditCard__c == card.AXF_CCT_MD_CreditCard__c
          ) {
            add(
              all,
              entry,
              null,
              card,
              card.AXF_CCT_DAT_Date__c,
              card.AXF_CCT_CUR_Amount__c,
              card.AXF_CCT_CUR_AmountBRL__c,
              cardCurrency(card),
              rates
            );
          }
        }
      } else {
        for (AXF_OBJ_BankAccountTransaction__c bank : banks) {
          if (
            entry.AXF_ENT_LKP_BankAccount__c == null ||
            entry.AXF_ENT_LKP_BankAccount__c == bank.AXF_BAT_MD_BankAccount__c
          ) {
            add(
              all,
              entry,
              bank,
              null,
              bank.AXF_BAT_DAT_Date__c,
              bank.AXF_BAT_CUR_Amount__c,
              null,
              bank.CurrencyIsoCode,
              rates
            );
          }
        }
      }
    }
    return pick(all);
  }

  private void add(
    List<Candidate> all,
    AXF_OBJ_Entry__c entry,
    AXF_OBJ_BankAccountTransaction__c bank,
    AXF_OBJ_CreditCardTransaction__c card,
    Date day,
    Decimal amount,
    Decimal amountBRL,
    String currencyCode,
    Map<String, Decimal> rates
  ) {
    Integer apart = Math.abs(entry.AXF_ENT_DAT_DueDate__c.daysBetween(day));
    if (apart > WINDOW_DAYS || amount == null) {
      return;
    }
    // Expense only with an outflow (debit), income only with an inflow (credit).
    if (
      (entry.AXF_ENT_PKL_Type__c == 'Expense' && amount >= 0) ||
      (entry.AXF_ENT_PKL_Type__c != 'Expense' &&
      amount <= 0)
    ) {
      return;
    }
    Boolean same = entry.CurrencyIsoCode == currencyCode;
    Decimal gap;
    if (same) {
      gap = (entry.AXF_ENT_CUR_Amount__c.abs() - amount.abs()).abs();
      if (gap >= CENT) {
        return;
      }
    } else {
      Decimal transactionBRL = amountBRL != null
        ? amountBRL.abs()
        : toBRL(amount.abs(), currencyCode, rates);
      Decimal entryBRL = toBRL(
        entry.AXF_ENT_CUR_Amount__c.abs(),
        entry.CurrencyIsoCode,
        rates
      );
      if (transactionBRL == null || entryBRL == null || transactionBRL == 0) {
        return;
      }
      gap = (entryBRL - transactionBRL).abs();
      if (gap / transactionBRL > TOLERANCE) {
        return;
      }
    }
    Candidate candidate = new Candidate();
    candidate.suggestion = new Suggestion();
    candidate.suggestion.entryId = entry.Id;
    candidate.suggestion.bankTransactionId = bank == null ? null : bank.Id;
    candidate.suggestion.cardTransactionId = card == null ? null : card.Id;
    candidate.suggestion.daysApart = apart;
    candidate.suggestion.crossCurrency = !same;
    candidate.amountGap = gap;
    all.add(candidate);
  }

  // Closest in date first, then in amount; an Entry and a transaction each appear once.
  private List<Suggestion> pick(List<Candidate> all) {
    List<Candidate> ordered = new List<Candidate>();
    for (Integer days = 0; days <= WINDOW_DAYS; days++) {
      List<Candidate> bucket = new List<Candidate>();
      for (Candidate candidate : all) {
        if (candidate.suggestion.daysApart == days) {
          bucket.add(candidate);
        }
      }
      bucket.sort(new GapComparator());
      ordered.addAll(bucket);
    }
    Set<Id> usedEntries = new Set<Id>();
    Set<Id> usedTransactions = new Set<Id>();
    List<Suggestion> result = new List<Suggestion>();
    for (Candidate candidate : ordered) {
      Suggestion suggestion = candidate.suggestion;
      Id transactionId = suggestion.bankTransactionId == null
        ? suggestion.cardTransactionId
        : suggestion.bankTransactionId;
      if (
        !usedEntries.contains(suggestion.entryId) &&
        !usedTransactions.contains(transactionId)
      ) {
        usedEntries.add(suggestion.entryId);
        usedTransactions.add(transactionId);
        result.add(suggestion);
      }
    }
    return result;
  }

  private class GapComparator implements System.Comparator<Candidate> {
    public Integer compare(Candidate first, Candidate second) {
      return first.amountGap < second.amountGap
        ? -1
        : (first.amountGap > second.amountGap ? 1 : 0);
    }
  }

  private String cardCurrency(AXF_OBJ_CreditCardTransaction__c card) {
    return String.isBlank(card.AXF_CCT_TXT_CurrencyCode__c)
      ? card.CurrencyIsoCode
      : card.AXF_CCT_TXT_CurrencyCode__c;
  }

  private Decimal toBRL(
    Decimal amount,
    String currencyCode,
    Map<String, Decimal> rates
  ) {
    if (currencyCode == BRL) {
      return amount;
    }
    Decimal rate = rates.get(currencyCode);
    return rate == null || rate == 0 ? null : amount / rate;
  }

  private Map<String, Decimal> rates(
    List<AXF_OBJ_Entry__c> entries,
    List<AXF_OBJ_BankAccountTransaction__c> banks,
    List<AXF_OBJ_CreditCardTransaction__c> cards
  ) {
    if (rateOverride != null) {
      return rateOverride;
    }
    Set<String> foreign = new Set<String>();
    for (AXF_OBJ_Entry__c entry : entries) {
      foreign.add(entry.CurrencyIsoCode);
    }
    for (AXF_OBJ_BankAccountTransaction__c bank : banks) {
      foreign.add(bank.CurrencyIsoCode);
    }
    for (AXF_OBJ_CreditCardTransaction__c card : cards) {
      foreign.add(cardCurrency(card));
    }
    foreign.remove(BRL);
    foreign.remove(null);
    Map<String, Decimal> rates = new Map<String, Decimal>();
    if (!foreign.isEmpty()) {
      for (CurrencyType type : [
        SELECT IsoCode, ConversionRate
        FROM CurrencyType
        WHERE IsoCode IN :foreign AND IsActive = TRUE
      ]) {
        rates.put(type.IsoCode, type.ConversionRate);
      }
    }
    return rates;
  }
}
