/**
 * @description Right-column previews of the Axon dashboard (E7-11, E7-14): the transactions still to
 * reconcile (count and the 3 most recent, flagged when a suggestion exists) and the accounts and
 * cards of the holder with balance and available limit. Sharing applies. "All holders" (null)
 * covers every holder the user can see.
 */
public with sharing class ALT_CLS_DashboardPreview {
  public class PendingItem {
    @AuraEnabled
    public Id id;
    // account or card
    @AuraEnabled
    public String source;
    @AuraEnabled
    public Date transactionDate;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public Boolean suggested = false;
  }

  public class Pending {
    @AuraEnabled
    public Integer total = 0;
    @AuraEnabled
    public Integer suggestions = 0;
    @AuraEnabled
    public Boolean truncated = false;
    @AuraEnabled
    public List<PendingItem> items = new List<PendingItem>();
  }

  public class Source {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    // account or card
    @AuraEnabled
    public String kind;
    // Balance of an account; available limit of a card.
    @AuraEnabled
    public Decimal value;
    @AuraEnabled
    public Decimal limitTotal;
    @AuraEnabled
    public String holderName;
  }

  public class Sources {
    @AuraEnabled
    public List<Source> accounts = new List<Source>();
    @AuraEnabled
    public List<Source> cards = new List<Source>();
  }

  private static final Integer PREVIEW_ITEMS = 3;
  private static final Integer MAX_ROWS = 2000;
  private static final Integer MAX_HOLDERS = 10;
  private static final Integer MAX_SOURCES = 50;

  public Pending pending(Id holderId, Date month) {
    Date first = (month == null ? Date.today() : month).toStartOfMonth();
    Date last = first.addMonths(1).addDays(-1);
    Pending result = new Pending();
    List<PendingItem> open = new List<PendingItem>();
    Set<Id> bankIds = new Set<Id>();
    Set<Id> cardIds = new Set<Id>();
    Map<String, Object> binds = new Map<String, Object>{
      'holderId' => holderId,
      'first' => first,
      'last' => last,
      'pendingStatus' => 'Pending',
      'maxRows' => MAX_ROWS
    };
    for (
      SObject row : Database.queryWithBinds(
        'SELECT AXF_BAT_DAT_Date__c, AXF_BAT_TXT_Description__c, ' +
          'convertCurrency(AXF_BAT_CUR_Amount__c) FROM AXF_OBJ_BankAccountTransaction__c ' +
          'WHERE (AXF_BAT_PKL_ReconciliationStatus__c = NULL OR ' +
          'AXF_BAT_PKL_ReconciliationStatus__c = :pendingStatus) ' +
          'AND AXF_BAT_DAT_Date__c >= :first AND AXF_BAT_DAT_Date__c <= :last' +
          (holderId == null
            ? ''
            : ' AND AXF_BAT_MD_BankAccount__r.AXF_BA_MD_Holder__c = :holderId') +
          ' ORDER BY AXF_BAT_DAT_Date__c DESC, Id LIMIT :maxRows',
        binds,
        AccessLevel.USER_MODE
      )
    ) {
      AXF_OBJ_BankAccountTransaction__c bank = (AXF_OBJ_BankAccountTransaction__c) row;
      bankIds.add(bank.Id);
      open.add(
        item(
          bank.Id,
          'account',
          bank.AXF_BAT_DAT_Date__c,
          bank.AXF_BAT_TXT_Description__c,
          bank.AXF_BAT_CUR_Amount__c
        )
      );
    }
    for (
      SObject row : Database.queryWithBinds(
        'SELECT AXF_CCT_DAT_Date__c, AXF_CCT_TXT_Description__c, ' +
          'convertCurrency(AXF_CCT_CUR_Amount__c) FROM AXF_OBJ_CreditCardTransaction__c ' +
          'WHERE (AXF_CCT_PKL_ReconciliationStatus__c = NULL OR ' +
          'AXF_CCT_PKL_ReconciliationStatus__c = :pendingStatus) ' +
          'AND AXF_CCT_DAT_Date__c >= :first AND AXF_CCT_DAT_Date__c <= :last' +
          (holderId == null
            ? ''
            : ' AND AXF_CCT_MD_CreditCard__r.AXF_CC_MD_Holder__c = :holderId') +
          ' ORDER BY AXF_CCT_DAT_Date__c DESC, Id LIMIT :maxRows',
        binds,
        AccessLevel.USER_MODE
      )
    ) {
      AXF_OBJ_CreditCardTransaction__c card = (AXF_OBJ_CreditCardTransaction__c) row;
      cardIds.add(card.Id);
      open.add(
        item(
          card.Id,
          'card',
          card.AXF_CCT_DAT_Date__c,
          card.AXF_CCT_TXT_Description__c,
          card.AXF_CCT_CUR_Amount__c
        )
      );
    }
    result.truncated = bankIds.size() >= MAX_ROWS || cardIds.size() >= MAX_ROWS;
    // A transaction linked to an Entry the user cannot see is still not "to reconcile".
    Set<Id> linked = new ALT_CLS_ReconciliationLinks().linked(bankIds, cardIds);
    List<PendingItem> still = new List<PendingItem>();
    for (PendingItem line : open) {
      if (!linked.contains(line.id)) {
        still.add(line);
      }
    }
    still.sort(new ByDateDescending());
    result.total = still.size();
    Set<Id> suggested = suggestedTransactions(holderId, first, last);
    for (PendingItem line : still) {
      line.suggested = suggested.contains(line.id);
      result.suggestions += line.suggested ? 1 : 0;
    }
    for (Integer i = 0; i < Math.min(PREVIEW_ITEMS, still.size()); i++) {
      result.items.add(still[i]);
    }
    return result;
  }

  public Sources sources(Id holderId) {
    Sources result = new Sources();
    Map<String, Object> binds = new Map<String, Object>{
      'holderId' => holderId,
      'maxSources' => MAX_SOURCES
    };
    String holderClause = holderId == null ? '' : ' WHERE {0} = :holderId';
    for (
      SObject row : Database.queryWithBinds(
        'SELECT Name, AXF_BA_MD_Holder__r.Name, convertCurrency(AXF_BA_CUR_Balance__c) ' +
          'FROM AXF_OBJ_BankAccount__c' +
          holderClause.replace('{0}', 'AXF_BA_MD_Holder__c') +
          ' ORDER BY Name LIMIT :maxSources',
        binds,
        AccessLevel.USER_MODE
      )
    ) {
      AXF_OBJ_BankAccount__c account = (AXF_OBJ_BankAccount__c) row;
      Source line = new Source();
      line.id = account.Id;
      line.name = account.Name;
      line.kind = 'account';
      line.value = account.AXF_BA_CUR_Balance__c;
      line.holderName = account.AXF_BA_MD_Holder__r?.Name;
      result.accounts.add(line);
    }
    for (
      SObject row : Database.queryWithBinds(
        'SELECT Name, AXF_CC_MD_Holder__r.Name, convertCurrency(AXF_CC_CUR_AvailableLimit__c), ' +
          'convertCurrency(AXF_CC_CUR_Limit__c) FROM AXF_OBJ_CreditCard__c' +
          holderClause.replace('{0}', 'AXF_CC_MD_Holder__c') +
          ' ORDER BY Name LIMIT :maxSources',
        binds,
        AccessLevel.USER_MODE
      )
    ) {
      AXF_OBJ_CreditCard__c card = (AXF_OBJ_CreditCard__c) row;
      Source line = new Source();
      line.id = card.Id;
      line.name = card.Name;
      line.kind = 'card';
      line.value = card.AXF_CC_CUR_AvailableLimit__c;
      line.limitTotal = card.AXF_CC_CUR_Limit__c;
      line.holderName = card.AXF_CC_MD_Holder__r?.Name;
      result.cards.add(line);
    }
    return result;
  }

  private static PendingItem item(
    Id id,
    String source,
    Date transactionDate,
    String description,
    Decimal amount
  ) {
    PendingItem line = new PendingItem();
    line.id = id;
    line.source = source;
    line.transactionDate = transactionDate;
    line.description = description;
    line.amount = amount;
    return line;
  }

  // Transactions that have a suggested Entry. Suggestions are per holder, so "all holders" asks
  // for the first holders the user can see.
  private Set<Id> suggestedTransactions(Id holderId, Date first, Date last) {
    List<Id> holderIds = new List<Id>();
    if (holderId != null) {
      holderIds.add(holderId);
    } else {
      for (Account holder : [
        SELECT Id
        FROM Account
        WHERE RecordType.DeveloperName IN ('AXF_Person', 'AXF_Business')
        WITH USER_MODE
        ORDER BY Name
        LIMIT :MAX_HOLDERS
      ]) {
        holderIds.add(holder.Id);
      }
    }
    Set<Id> ids = new Set<Id>();
    for (Id id : holderIds) {
      for (
        ALT_CLS_ReconciliationSuggestions.Suggestion suggestion : new ALT_CLS_ReconciliationSuggestions()
          .suggest(id, first, last)
      ) {
        ids.add(
          suggestion.bankTransactionId != null
            ? suggestion.bankTransactionId
            : suggestion.cardTransactionId
        );
      }
    }
    return ids;
  }

  private class ByDateDescending implements System.Comparator<PendingItem> {
    public Integer compare(PendingItem first, PendingItem second) {
      if (first.transactionDate == second.transactionDate) {
        return 0;
      }
      return first.transactionDate > second.transactionDate ? -1 : 1;
    }
  }
}
