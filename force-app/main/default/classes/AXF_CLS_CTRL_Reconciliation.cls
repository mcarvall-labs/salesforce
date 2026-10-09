public with sharing class AXF_CLS_CTRL_Reconciliation {
  public class HolderView {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
  }

  public class SourceView {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    // account or card
    @AuraEnabled
    public String kind;
  }

  public class EntryView {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Date dueDate;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public String currencyCode;
    // Expense or Income
    @AuraEnabled
    public String type;
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public Id cardId;
    @AuraEnabled
    public Id invoiceId;
  }

  public class TransactionView {
    @AuraEnabled
    public Id id;
    // account or card
    @AuraEnabled
    public String source;
    @AuraEnabled
    public Date transactionDate;
    @AuraEnabled
    public String description;
    // Signed: debit negative.
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public String currencyCode;
    @AuraEnabled
    public Decimal amountBRL;
    @AuraEnabled
    public Id sourceId;
  }

  public class SuggestionView {
    @AuraEnabled
    public Id entryId;
    @AuraEnabled
    public Id bankTransactionId;
    @AuraEnabled
    public Id cardTransactionId;
    @AuraEnabled
    public Integer daysApart;
    @AuraEnabled
    public Boolean crossCurrency;
  }

  public class ScreenData {
    @AuraEnabled
    public List<SourceView> sources = new List<SourceView>();
    @AuraEnabled
    public List<EntryView> entries = new List<EntryView>();
    @AuraEnabled
    public List<TransactionView> transactions = new List<TransactionView>();
    @AuraEnabled
    public List<SuggestionView> suggestions = new List<SuggestionView>();
    @AuraEnabled
    public Id lastReconciledEntryId;
  }

  // What the Entry record page shows: the transaction the Entry is reconciled with.
  public class EntryReconciliationView {
    @AuraEnabled
    public Boolean reconciled = false;
    // account or card
    @AuraEnabled
    public String source;
    @AuraEnabled
    public Id transactionId;
    @AuraEnabled
    public Date transactionDate;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public String currencyCode;
    @AuraEnabled
    public Decimal amountBRL;
    @AuraEnabled
    public Decimal realizedAmountBRL;
    @AuraEnabled
    public Date paymentDate;
  }

  public class PairInput {
    @AuraEnabled
    public Id entryId;
    @AuraEnabled
    public Id bankTransactionId;
    @AuraEnabled
    public Id cardTransactionId;
  }

  public class OutcomeView {
    @AuraEnabled
    public Id entryId;
    @AuraEnabled
    public Id transactionId;
    @AuraEnabled
    public Boolean success;
    @AuraEnabled
    public String message;
  }

  private static final Integer MAX_ROWS = 500;
  private static final Integer WINDOW_DAYS = 7;
  private static final String DENIED = 'Sem acesso para concluir esta ação.';
  private static final String FAILED = 'Não foi possível concluir agora; tente novamente.';

  @AuraEnabled
  public static List<HolderView> getHolders() {
    Set<Id> ids = new Set<Id>();
    try {
      for (AXF_OBJ_BankAccount__c account : [
        SELECT AXF_BA_MD_Holder__c
        FROM AXF_OBJ_BankAccount__c
        WITH USER_MODE
        LIMIT :MAX_ROWS
      ]) {
        if (account.AXF_BA_MD_Holder__c != null) {
          ids.add(account.AXF_BA_MD_Holder__c);
        }
      }
      for (AXF_OBJ_CreditCard__c card : [
        SELECT AXF_CC_MD_Holder__c
        FROM AXF_OBJ_CreditCard__c
        WITH USER_MODE
        LIMIT :MAX_ROWS
      ]) {
        if (card.AXF_CC_MD_Holder__c != null) {
          ids.add(card.AXF_CC_MD_Holder__c);
        }
      }
    } catch (QueryException e) {
      throw new AuraHandledException(DENIED);
    } catch (DmlException e) {
      throw new AuraHandledException(FAILED);
    }
    List<HolderView> holders = new List<HolderView>();
    for (Account holder : [
      SELECT Name
      FROM Account
      WHERE Id IN :ids
      WITH USER_MODE
      ORDER BY Name
    ]) {
      HolderView view = new HolderView();
      view.id = holder.Id;
      view.name = holder.Name;
      holders.add(view);
    }
    return holders;
  }

  // Everything the screen needs for one holder and one month (YYYY-MM): pending Entries due in the
  // month, open transactions within 7 days of it, the suggested pairs and the account/card filter.
  @AuraEnabled
  public static ScreenData getData(Id holderId, String month) {
    if (holderId == null) {
      throw new AuraHandledException('Informe o titular.');
    }
    Date first = firstDay(month);
    Date last = first.addMonths(1).addDays(-1);
    Date earliest = first.addDays(-WINDOW_DAYS);
    Date latest = last.addDays(WINDOW_DAYS);
    ScreenData data = new ScreenData();
    try {
      addSources(data, holderId);
      addEntries(data, holderId, first, last);
      addBankTransactions(data, holderId, earliest, latest);
      addCardTransactions(data, holderId, earliest, latest);
      for (
        ALT_CLS_ReconciliationSuggestions.Suggestion suggestion : new ALT_CLS_ReconciliationSuggestions()
          .suggest(holderId, first, last)
      ) {
        SuggestionView view = new SuggestionView();
        view.entryId = suggestion.entryId;
        view.bankTransactionId = suggestion.bankTransactionId;
        view.cardTransactionId = suggestion.cardTransactionId;
        view.daysApart = suggestion.daysApart;
        view.crossCurrency = suggestion.crossCurrency;
        data.suggestions.add(view);
      }
      data.lastReconciledEntryId = lastReconciled(holderId);
    } catch (QueryException e) {
      throw new AuraHandledException(DENIED);
    } catch (DmlException e) {
      throw new AuraHandledException(FAILED);
    }
    return data;
  }

  @AuraEnabled
  public static List<OutcomeView> reconcile(List<PairInput> pairs) {
    List<ALT_CLS_Reconciliation.Pair> converted = new List<ALT_CLS_Reconciliation.Pair>();
    for (PairInput pair : pairs == null ? new List<PairInput>() : pairs) {
      converted.add(
        pair == null
          ? null
          : new ALT_CLS_Reconciliation.Pair(
              pair.entryId,
              pair.bankTransactionId,
              pair.cardTransactionId
            )
      );
    }
    List<OutcomeView> views = new List<OutcomeView>();
    try {
      for (
        ALT_CLS_Reconciliation.Outcome outcome : new ALT_CLS_Reconciliation()
          .reconcile(converted)
      ) {
        views.add(
          view(outcome.entryId, null, outcome.success, outcome.message)
        );
      }
    } catch (QueryException e) {
      throw new AuraHandledException(DENIED);
    } catch (DmlException e) {
      throw new AuraHandledException(FAILED);
    }
    return views;
  }

  @AuraEnabled
  public static List<OutcomeView> unreconcile(List<Id> entryIds) {
    List<OutcomeView> views = new List<OutcomeView>();
    try {
      for (
        ALT_CLS_Reconciliation.Outcome outcome : new ALT_CLS_Reconciliation()
          .unreconcile(entryIds)
      ) {
        views.add(
          view(outcome.entryId, null, outcome.success, outcome.message)
        );
      }
    } catch (QueryException e) {
      throw new AuraHandledException(DENIED);
    } catch (DmlException e) {
      throw new AuraHandledException(FAILED);
    }
    return views;
  }

  @AuraEnabled
  public static List<OutcomeView> ignoreTransactions(
    List<Id> bankIds,
    List<Id> cardIds
  ) {
    List<OutcomeView> views = new List<OutcomeView>();
    try {
      for (
        ALT_CLS_ReconciliationActions.Outcome outcome : new ALT_CLS_ReconciliationActions()
          .ignore(bankIds, cardIds)
      ) {
        views.add(
          view(
            outcome.entryId,
            outcome.transactionId,
            outcome.success,
            outcome.message
          )
        );
      }
    } catch (QueryException e) {
      throw new AuraHandledException(DENIED);
    } catch (DmlException e) {
      throw new AuraHandledException(FAILED);
    }
    return views;
  }

  @AuraEnabled
  public static List<OutcomeView> createEntries(
    List<Id> bankIds,
    List<Id> cardIds
  ) {
    List<OutcomeView> views = new List<OutcomeView>();
    try {
      for (
        ALT_CLS_ReconciliationActions.Outcome outcome : new ALT_CLS_ReconciliationActions()
          .createEntries(bankIds, cardIds)
      ) {
        views.add(
          view(
            outcome.entryId,
            outcome.transactionId,
            outcome.success,
            outcome.message
          )
        );
      }
    } catch (QueryException e) {
      throw new AuraHandledException(DENIED);
    } catch (DmlException e) {
      throw new AuraHandledException(FAILED);
    }
    return views;
  }

  @AuraEnabled
  public static EntryReconciliationView getEntryReconciliation(Id entryId) {
    if (entryId == null) {
      throw new AuraHandledException('Informe o lançamento.');
    }
    EntryReconciliationView view = new EntryReconciliationView();
    try {
      List<AXF_OBJ_Entry__c> entries = [
        SELECT
          AXF_ENT_NUM_RealizedAmountBRL__c,
          AXF_ENT_DAT_PaymentDate__c,
          AXF_ENT_LKP_BankAccountTransaction__c,
          AXF_ENT_LKP_BankAccountTransaction__r.AXF_BAT_DAT_Date__c,
          AXF_ENT_LKP_BankAccountTransaction__r.AXF_BAT_TXT_Description__c,
          AXF_ENT_LKP_BankAccountTransaction__r.AXF_BAT_CUR_Amount__c,
          AXF_ENT_LKP_BankAccountTransaction__r.CurrencyIsoCode,
          AXF_ENT_LKP_CreditCardTransaction__c,
          AXF_ENT_LKP_CreditCardTransaction__r.AXF_CCT_DAT_Date__c,
          AXF_ENT_LKP_CreditCardTransaction__r.AXF_CCT_TXT_Description__c,
          AXF_ENT_LKP_CreditCardTransaction__r.AXF_CCT_CUR_Amount__c,
          AXF_ENT_LKP_CreditCardTransaction__r.AXF_CCT_CUR_AmountBRL__c,
          AXF_ENT_LKP_CreditCardTransaction__r.AXF_CCT_TXT_CurrencyCode__c,
          AXF_ENT_LKP_CreditCardTransaction__r.CurrencyIsoCode
        FROM AXF_OBJ_Entry__c
        WHERE Id = :entryId
        WITH USER_MODE
      ];
      if (entries.isEmpty()) {
        throw new AuraHandledException('Lançamento não encontrado.');
      }
      AXF_OBJ_Entry__c entry = entries[0];
      view.realizedAmountBRL = entry.AXF_ENT_NUM_RealizedAmountBRL__c;
      view.paymentDate = entry.AXF_ENT_DAT_PaymentDate__c;
      if (entry.AXF_ENT_LKP_BankAccountTransaction__c != null) {
        AXF_OBJ_BankAccountTransaction__c bank = entry.AXF_ENT_LKP_BankAccountTransaction__r;
        view.reconciled = true;
        view.source = 'account';
        view.transactionId = bank.Id;
        view.transactionDate = bank.AXF_BAT_DAT_Date__c;
        view.description = bank.AXF_BAT_TXT_Description__c;
        view.amount = bank.AXF_BAT_CUR_Amount__c;
        view.currencyCode = bank.CurrencyIsoCode;
      } else if (entry.AXF_ENT_LKP_CreditCardTransaction__c != null) {
        AXF_OBJ_CreditCardTransaction__c card = entry.AXF_ENT_LKP_CreditCardTransaction__r;
        view.reconciled = true;
        view.source = 'card';
        view.transactionId = card.Id;
        view.transactionDate = card.AXF_CCT_DAT_Date__c;
        view.description = card.AXF_CCT_TXT_Description__c;
        view.amount = card.AXF_CCT_CUR_Amount__c;
        view.amountBRL = card.AXF_CCT_CUR_AmountBRL__c;
        view.currencyCode = String.isBlank(card.AXF_CCT_TXT_CurrencyCode__c)
          ? card.CurrencyIsoCode
          : card.AXF_CCT_TXT_CurrencyCode__c;
      }
    } catch (QueryException e) {
      throw new AuraHandledException(DENIED);
    }
    return view;
  }

  private static OutcomeView view(
    Id entryId,
    Id transactionId,
    Boolean success,
    String message
  ) {
    OutcomeView view = new OutcomeView();
    view.entryId = entryId;
    view.transactionId = transactionId;
    view.success = success;
    view.message = message;
    return view;
  }

  private static Date firstDay(String month) {
    if (
      String.isBlank(month) ||
      month.length() != 7 ||
      !month.substring(0, 4).isNumeric() ||
      !month.substring(5).isNumeric()
    ) {
      throw new AuraHandledException('Informe o mês no formato AAAA-MM.');
    }
    Integer monthNumber = Integer.valueOf(month.substring(5));
    if (monthNumber < 1 || monthNumber > 12) {
      throw new AuraHandledException('Informe o mês no formato AAAA-MM.');
    }
    return Date.newInstance(
      Integer.valueOf(month.substring(0, 4)),
      monthNumber,
      1
    );
  }

  private static void addSources(ScreenData data, Id holderId) {
    for (AXF_OBJ_BankAccount__c account : [
      SELECT Name
      FROM AXF_OBJ_BankAccount__c
      WHERE AXF_BA_MD_Holder__c = :holderId
      WITH USER_MODE
      ORDER BY Name
      LIMIT :MAX_ROWS
    ]) {
      data.sources.add(source(account.Id, account.Name, 'account'));
    }
    for (AXF_OBJ_CreditCard__c card : [
      SELECT Name
      FROM AXF_OBJ_CreditCard__c
      WHERE AXF_CC_MD_Holder__c = :holderId
      WITH USER_MODE
      ORDER BY Name
      LIMIT :MAX_ROWS
    ]) {
      data.sources.add(source(card.Id, card.Name, 'card'));
    }
  }

  private static SourceView source(Id id, String name, String kind) {
    SourceView view = new SourceView();
    view.id = id;
    view.name = name;
    view.kind = kind;
    return view;
  }

  private static void addEntries(
    ScreenData data,
    Id holderId,
    Date first,
    Date last
  ) {
    for (AXF_OBJ_Entry__c entry : [
      SELECT
        Name,
        AXF_ENT_DAT_DueDate__c,
        AXF_ENT_CUR_Amount__c,
        CurrencyIsoCode,
        AXF_ENT_PKL_Type__c,
        AXF_ENT_LKP_BankAccount__c,
        AXF_ENT_LKP_CreditCard__c,
        AXF_ENT_LKP_Invoice__c
      FROM AXF_OBJ_Entry__c
      WHERE
        AXF_ENT_MD_Holder__c = :holderId
        AND AXF_ENT_PKL_Status__c = 'Pending'
        AND AXF_ENT_LKP_BankAccountTransaction__c = NULL
        AND AXF_ENT_LKP_CreditCardTransaction__c = NULL
        AND AXF_ENT_DAT_DueDate__c >= :first
        AND AXF_ENT_DAT_DueDate__c <= :last
      WITH USER_MODE
      ORDER BY AXF_ENT_DAT_DueDate__c, Name
      LIMIT :MAX_ROWS
    ]) {
      EntryView view = new EntryView();
      view.id = entry.Id;
      view.name = entry.Name;
      view.dueDate = entry.AXF_ENT_DAT_DueDate__c;
      view.amount = entry.AXF_ENT_CUR_Amount__c;
      view.currencyCode = entry.CurrencyIsoCode;
      view.type = entry.AXF_ENT_PKL_Type__c;
      view.accountId = entry.AXF_ENT_LKP_BankAccount__c;
      view.cardId = entry.AXF_ENT_LKP_CreditCard__c;
      view.invoiceId = entry.AXF_ENT_LKP_Invoice__c;
      data.entries.add(view);
    }
  }

  private static void addBankTransactions(
    ScreenData data,
    Id holderId,
    Date earliest,
    Date latest
  ) {
    Set<Id> linked = new ALT_CLS_ReconciliationLinks()
      .linkedBank(holderId, earliest, latest);
    for (AXF_OBJ_BankAccountTransaction__c bank : [
      SELECT
        AXF_BAT_DAT_Date__c,
        AXF_BAT_TXT_Description__c,
        AXF_BAT_CUR_Amount__c,
        CurrencyIsoCode,
        AXF_BAT_MD_BankAccount__c
      FROM AXF_OBJ_BankAccountTransaction__c
      WHERE
        AXF_BAT_MD_BankAccount__r.AXF_BA_MD_Holder__c = :holderId
        AND (AXF_BAT_PKL_ReconciliationStatus__c = NULL
        OR AXF_BAT_PKL_ReconciliationStatus__c = 'Pending')
        AND AXF_BAT_DAT_Date__c >= :earliest
        AND AXF_BAT_DAT_Date__c <= :latest
        AND Id NOT IN :linked
      WITH USER_MODE
      ORDER BY AXF_BAT_DAT_Date__c, Id
      LIMIT :MAX_ROWS
    ]) {
      TransactionView view = new TransactionView();
      view.id = bank.Id;
      view.source = 'account';
      view.transactionDate = bank.AXF_BAT_DAT_Date__c;
      view.description = bank.AXF_BAT_TXT_Description__c;
      view.amount = bank.AXF_BAT_CUR_Amount__c;
      view.currencyCode = bank.CurrencyIsoCode;
      view.sourceId = bank.AXF_BAT_MD_BankAccount__c;
      data.transactions.add(view);
    }
  }

  private static void addCardTransactions(
    ScreenData data,
    Id holderId,
    Date earliest,
    Date latest
  ) {
    Set<Id> linked = new ALT_CLS_ReconciliationLinks()
      .linkedCard(holderId, earliest, latest);
    for (AXF_OBJ_CreditCardTransaction__c card : [
      SELECT
        AXF_CCT_DAT_Date__c,
        AXF_CCT_TXT_Description__c,
        AXF_CCT_CUR_Amount__c,
        AXF_CCT_CUR_AmountBRL__c,
        AXF_CCT_TXT_CurrencyCode__c,
        CurrencyIsoCode,
        AXF_CCT_MD_CreditCard__c
      FROM AXF_OBJ_CreditCardTransaction__c
      WHERE
        AXF_CCT_MD_CreditCard__r.AXF_CC_MD_Holder__c = :holderId
        AND (AXF_CCT_PKL_ReconciliationStatus__c = NULL
        OR AXF_CCT_PKL_ReconciliationStatus__c = 'Pending')
        AND AXF_CCT_DAT_Date__c >= :earliest
        AND AXF_CCT_DAT_Date__c <= :latest
        AND Id NOT IN :linked
      WITH USER_MODE
      ORDER BY AXF_CCT_DAT_Date__c, Id
      LIMIT :MAX_ROWS
    ]) {
      TransactionView view = new TransactionView();
      view.id = card.Id;
      view.source = 'card';
      view.transactionDate = card.AXF_CCT_DAT_Date__c;
      view.description = card.AXF_CCT_TXT_Description__c;
      view.amount = card.AXF_CCT_CUR_Amount__c;
      view.currencyCode = String.isBlank(card.AXF_CCT_TXT_CurrencyCode__c)
        ? card.CurrencyIsoCode
        : card.AXF_CCT_TXT_CurrencyCode__c;
      view.amountBRL = card.AXF_CCT_CUR_AmountBRL__c;
      view.sourceId = card.AXF_CCT_MD_CreditCard__c;
      data.transactions.add(view);
    }
  }

  // The Entry reconciled most recently (the one "Desconciliar último" undoes).
  private static Id lastReconciled(Id holderId) {
    List<AXF_OBJ_Entry__c> entries = [
      SELECT Id
      FROM AXF_OBJ_Entry__c
      WHERE
        AXF_ENT_MD_Holder__c = :holderId
        AND AXF_ENT_PKL_Status__c = 'Realized'
        AND (AXF_ENT_LKP_BankAccountTransaction__c != NULL
        OR AXF_ENT_LKP_CreditCardTransaction__c != NULL)
      WITH USER_MODE
      ORDER BY LastModifiedDate DESC
      LIMIT 1
    ];
    return entries.isEmpty() ? null : entries[0].Id;
  }
}
