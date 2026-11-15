/**
 * @description Bank/card transactions that can pay one Pending Entry (AXF-327, popup Pagar/Receber
 * of the home). Same rules as ALT_CLS_ReconciliationSuggestions (E6-2 payment rules, transaction
 * within 7 days of the due date, amount within 5 %, Pending/unset and not yet linked), but listing every candidate of one Entry instead of one pair per Entry.
 * Closest in date first, then in amount; the first is the best match. Nothing is saved here.
 * Runs with the caller's sharing and CRUD/FLS; an Entry the user cannot read yields no candidates.
 */
public with sharing class ALT_CLS_EntryCandidates {
  public class Candidate {
    @AuraEnabled
    public Id id;
    // account or card
    @AuraEnabled
    public String source;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public Date transactionDate;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public String currencyCode;
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public Integer daysApart;
    @AuraEnabled
    public Decimal amountGap;
    // BEST, VALUE (amount differs) or DATE (same amount, other day)
    @AuraEnabled
    public String tag;
  }

  public static final String TAG_BEST = 'BEST';
  public static final String TAG_VALUE = 'VALUE';
  public static final String TAG_DATE = 'DATE';
  private static final Integer MAX_ROWS = 200;
  private static final Decimal CENT = 0.005;
  private static final String BRL = 'BRL';

  private final ALT_CLS_ReconciliationSuggestions rules = new ALT_CLS_ReconciliationSuggestions();

  public List<Candidate> candidates(Id entryId) {
    List<Candidate> result = new List<Candidate>();
    if (entryId == null) {
      return result;
    }
    List<AXF_OBJ_Entry__c> found = [
      SELECT
        CurrencyIsoCode,
        AXF_ENT_PKL_Type__c,
        AXF_ENT_CUR_Amount__c,
        AXF_ENT_DAT_DueDate__c,
        AXF_ENT_MD_Holder__c,
        AXF_ENT_LKP_BankAccount__c,
        AXF_ENT_LKP_CreditCard__c,
        AXF_ENT_LKP_Invoice__c
      FROM AXF_OBJ_Entry__c
      WHERE
        Id = :entryId
        AND AXF_ENT_PKL_Status__c = 'Pending'
        AND AXF_ENT_LKP_BankAccountTransaction__c = NULL
        AND AXF_ENT_LKP_CreditCardTransaction__c = NULL
        AND AXF_ENT_DAT_DueDate__c != NULL
        AND AXF_ENT_CUR_Amount__c != NULL
      WITH USER_MODE
    ];
    if (found.isEmpty()) {
      return result;
    }
    AXF_OBJ_Entry__c entry = found[0];
    Date earliest = entry.AXF_ENT_DAT_DueDate__c.addDays(
      -ALT_CLS_ReconciliationSuggestions.WINDOW_DAYS
    );
    Date latest = entry.AXF_ENT_DAT_DueDate__c.addDays(
      ALT_CLS_ReconciliationSuggestions.WINDOW_DAYS
    );
    Boolean byCard =
      entry.AXF_ENT_LKP_CreditCard__c != null &&
      entry.AXF_ENT_LKP_Invoice__c == null;
    List<AXF_OBJ_CreditCardTransaction__c> cards = new List<AXF_OBJ_CreditCardTransaction__c>();
    List<AXF_OBJ_BankAccountTransaction__c> banks = new List<AXF_OBJ_BankAccountTransaction__c>();
    if (byCard) {
      cards = cardTransactions(entry, earliest, latest);
    } else {
      banks = bankTransactions(entry, earliest, latest);
    }
    Set<String> codes = new Set<String>{ entry.CurrencyIsoCode };
    for (AXF_OBJ_CreditCardTransaction__c card : cards) {
      codes.add(rules.cardCurrency(card));
    }
    for (AXF_OBJ_BankAccountTransaction__c bank : banks) {
      codes.add(bank.CurrencyIsoCode);
    }
    Map<String, Decimal> rates = rules.ratesFor(codes);
    for (AXF_OBJ_CreditCardTransaction__c card : cards) {
      Candidate candidate = candidate(
        entry,
        card.AXF_CCT_DAT_Date__c,
        card.AXF_CCT_CUR_Amount__c,
        card.AXF_CCT_CUR_AmountBRL__c,
        rules.cardCurrency(card),
        true,
        rates
      );
      if (candidate != null) {
        candidate.id = card.Id;
        candidate.source = 'card';
        candidate.description = card.AXF_CCT_TXT_Description__c;
        candidate.accountName = card.AXF_CCT_MD_CreditCard__r?.Name;
        result.add(candidate);
      }
    }
    for (AXF_OBJ_BankAccountTransaction__c bank : banks) {
      Candidate candidate = candidate(
        entry,
        bank.AXF_BAT_DAT_Date__c,
        bank.AXF_BAT_CUR_Amount__c,
        null,
        bank.CurrencyIsoCode,
        false,
        rates
      );
      if (candidate != null) {
        candidate.id = bank.Id;
        candidate.source = 'account';
        candidate.description = bank.AXF_BAT_TXT_Description__c;
        candidate.accountName = bank.AXF_BAT_MD_BankAccount__r?.Name;
        result.add(candidate);
      }
    }
    result.sort(new CandidateComparator());
    for (Integer index = 0; index < result.size(); index++) {
      result[index].tag = index == 0
        ? TAG_BEST
        : (result[index].amountGap > 0 ? TAG_VALUE : TAG_DATE);
    }
    return result;
  }

  private List<AXF_OBJ_BankAccountTransaction__c> bankTransactions(
    AXF_OBJ_Entry__c entry,
    Date earliest,
    Date latest
  ) {
    Id holderId = entry.AXF_ENT_MD_Holder__c;
    Id accountId = entry.AXF_ENT_LKP_BankAccount__c;
    if (accountId != null) {
      return [
        SELECT
          CurrencyIsoCode,
          AXF_BAT_CUR_Amount__c,
          AXF_BAT_DAT_Date__c,
          AXF_BAT_TXT_Description__c,
          AXF_BAT_MD_BankAccount__r.Name
        FROM AXF_OBJ_BankAccountTransaction__c
        WHERE
          AXF_BAT_MD_BankAccount__c = :accountId
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
    }
    return [
      SELECT
        CurrencyIsoCode,
        AXF_BAT_CUR_Amount__c,
        AXF_BAT_DAT_Date__c,
        AXF_BAT_TXT_Description__c,
        AXF_BAT_MD_BankAccount__r.Name
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
  }

  private List<AXF_OBJ_CreditCardTransaction__c> cardTransactions(
    AXF_OBJ_Entry__c entry,
    Date earliest,
    Date latest
  ) {
    Id cardId = entry.AXF_ENT_LKP_CreditCard__c;
    return [
      SELECT
        CurrencyIsoCode,
        AXF_CCT_CUR_Amount__c,
        AXF_CCT_CUR_AmountBRL__c,
        AXF_CCT_TXT_CurrencyCode__c,
        AXF_CCT_DAT_Date__c,
        AXF_CCT_TXT_Description__c,
        AXF_CCT_MD_CreditCard__r.Name
      FROM AXF_OBJ_CreditCardTransaction__c
      WHERE
        AXF_CCT_MD_CreditCard__c = :cardId
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
  }

  // Null when the transaction does not fit the Entry (same checks as the batch suggestions).
  private Candidate candidate(
    AXF_OBJ_Entry__c entry,
    Date day,
    Decimal amount,
    Decimal amountBRL,
    String currencyCode,
    Boolean isCard,
    Map<String, Decimal> rates
  ) {
    if (day == null || amount == null) {
      return null;
    }
    Integer apart = Math.abs(entry.AXF_ENT_DAT_DueDate__c.daysBetween(day));
    if (apart > ALT_CLS_ReconciliationSuggestions.WINDOW_DAYS) {
      return null;
    }
    if (
      (entry.AXF_ENT_PKL_Type__c == 'Expense' && amount >= 0) ||
      (entry.AXF_ENT_PKL_Type__c != 'Expense' &&
      amount <= 0)
    ) {
      return null;
    }
    if (isCard && amountBRL == null && currencyCode != BRL) {
      return null;
    }
    // Unlike the batch suggestions, the user picks here, so the 5 % tolerance also applies to the
    // same currency; across currencies both sides are compared in BRL. The Entry is the reference.
    Decimal gap;
    Decimal reference;
    if (entry.CurrencyIsoCode == currencyCode) {
      gap = (entry.AXF_ENT_CUR_Amount__c.abs() - amount.abs()).abs();
      reference = entry.AXF_ENT_CUR_Amount__c.abs();
    } else {
      Decimal transactionBRL = amountBRL != null
        ? amountBRL.abs()
        : rules.toBRL(amount.abs(), currencyCode, rates);
      Decimal entryBRL = rules.toBRL(
        entry.AXF_ENT_CUR_Amount__c.abs(),
        entry.CurrencyIsoCode,
        rates
      );
      if (transactionBRL == null || entryBRL == null) {
        return null;
      }
      gap = (entryBRL - transactionBRL).abs();
      reference = entryBRL;
    }
    if (
      reference == 0 ||
      gap / reference > ALT_CLS_ReconciliationSuggestions.TOLERANCE
    ) {
      return null;
    }
    if (gap < CENT) {
      gap = 0;
    }
    Candidate candidate = new Candidate();
    candidate.transactionDate = day;
    candidate.amount = amount;
    candidate.currencyCode = currencyCode;
    candidate.daysApart = apart;
    candidate.amountGap = gap;
    return candidate;
  }

  private class CandidateComparator implements System.Comparator<Candidate> {
    public Integer compare(Candidate first, Candidate second) {
      if (first.daysApart != second.daysApart) {
        return first.daysApart < second.daysApart ? -1 : 1;
      }
      if (first.amountGap != second.amountGap) {
        return first.amountGap < second.amountGap ? -1 : 1;
      }
      return 0;
    }
  }
}
