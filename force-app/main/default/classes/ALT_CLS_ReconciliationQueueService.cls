/**
 * @description AXF-154: cross-account reconciliation queue. Lists the Pluggy facts (bank and card
 * transactions with Source PLUGGY) of the available accounts and cards of the authorized holders,
 * with combinable filters and the derived reconciliation status of the current-account (AXF-151)
 * and credit-card (AXF-152) screens, pending lines first. Suggestions and the one-click
 * confirmation are delegated unchanged to ALT_CLS_BankStatementService / ALT_CLS_CardStatementService:
 * no new engine or window, nothing written besides the allocations those services create.
 */
public with sharing class ALT_CLS_ReconciliationQueueService {
  public static final String MATCHING_POLICY = ALT_CLS_MatchingWindow.POLICY;
  public static final String KIND_BANK = 'BANK';
  public static final String KIND_CARD = 'CARD';
  public static final String SOURCE_PLUGGY = 'PLUGGY';
  public static final String LINE_FACT = ALT_CLS_BankStatementService.LINE_FACT;
  public static final String STATUS_RECONCILED = ALT_CLS_BankStatementService.STATUS_RECONCILED;
  public static final String STATUS_PARTIAL = ALT_CLS_BankStatementService.STATUS_PARTIAL;
  public static final String STATUS_UNRECONCILED = ALT_CLS_BankStatementService.STATUS_UNRECONCILED;
  public static final String STATUS_UNVERIFIED = ALT_CLS_BankStatementService.STATUS_UNVERIFIED;
  /** Status filter value: UNRECONCILED or PARTIAL. The default: the queue exists to close them. */
  public static final String STATUS_PENDING = 'PENDING';
  /** Status filter value: every status. */
  public static final String STATUS_ALL = 'ALL';
  public static final Integer MAX_SOURCES = 200;
  /** Facts read per kind (bank, card); a larger result is flagged, never cut silently. */
  public static final Integer MAX_FACTS = 500;
  public static final Integer MAX_PERIOD_DAYS = 366;
  /** Fact ids per allocation read: a capped read only leaves its own chunk unverified. */
  public static final Integer NET_CHUNK = 200;
  /** Same margin as AXF-152: a purchase near the window may belong to a neighbouring invoice. */
  private static final Integer CLASSIFY_MARGIN_DAYS = 35;
  private static final Set<String> KINDS = new Set<String>{
    KIND_BANK,
    KIND_CARD
  };
  private static final Set<String> STATUSES = new Set<String>{
    STATUS_ALL,
    STATUS_PENDING,
    STATUS_RECONCILED,
    STATUS_PARTIAL,
    STATUS_UNRECONCILED,
    STATUS_UNVERIFIED
  };

  @TestVisible
  private static Date todayOverride;
  @TestVisible
  private static ALT_CLS_CardInvoiceCalendar.BusinessDays businessDaysOverride;
  @TestVisible
  private static Integer allocationCapOverride;

  public class ReconciliationQueueException extends Exception {
  }

  /** An account or card the queue can be filtered by. */
  public class SourceView {
    @AuraEnabled
    public String kind;
    @AuraEnabled
    public Id fundingId;
    @AuraEnabled
    public Id holderId;
    @AuraEnabled
    public String holderLabel;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String currencyIso;
  }

  public class SourceList {
    @AuraEnabled
    public Boolean truncated = false;
    @AuraEnabled
    public List<SourceView> items = new List<SourceView>();
  }

  public class QueueQuery {
    /** BANK | CARD | null (both). */
    public String kind;
    /** One bank account or card; its kind must agree with {@code kind}. */
    public Id fundingId;
    /** Invoice reference month: only with a card selected. */
    public Integer invoiceYear;
    public Integer invoiceMonth;
    public Date fromDate;
    public Date toDate;
    public Decimal minAmount;
    public Decimal maxAmount;
    public String term;
    /** PENDING (default when null) | ALL | RECONCILED | PARTIAL | UNRECONCILED | UNVERIFIED. */
    public String status;
  }

  public class QueueLine {
    @AuraEnabled
    public String kind;
    @AuraEnabled
    public String lineKind = LINE_FACT;
    @AuraEnabled
    public Id fundingId;
    @AuraEnabled
    public String fundingName;
    @AuraEnabled
    public String holderLabel;
    @AuraEnabled
    public Id recordId;
    @AuraEnabled
    public Date lineDate;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public String direction;
    @AuraEnabled
    public String currencyIso;
    @AuraEnabled
    public Decimal allocated;
    @AuraEnabled
    public Decimal residual;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Decimal version;
    @AuraEnabled
    public Boolean canSuggest = false;
  }

  public class QueueView {
    @AuraEnabled
    public String matchingPolicy = MATCHING_POLICY;
    /** False without the link capability: the queue is read-only and offers no action. */
    @AuraEnabled
    public Boolean canReconcile = false;
    /** Dates the lines were read in (the invoice window narrowed by a custom period, if any). */
    @AuraEnabled
    public Date fromDate;
    @AuraEnabled
    public Date toDate;
    @AuraEnabled
    public Boolean customPeriod = false;
    /** The status filter applied (PENDING when none was given). */
    @AuraEnabled
    public String status;
    /** Purchases window of the invoice (only with the invoice filter). */
    @AuraEnabled
    public Date invoiceFromDate;
    @AuraEnabled
    public Date invoiceToDate;
    @AuraEnabled
    public Integer invoiceYear;
    @AuraEnabled
    public Integer invoiceMonth;
    /** RESOLVED (invoice window) | BLOCKED (civil month, no calendar) | null (no invoice filter). */
    @AuraEnabled
    public String invoiceOutcome;
    @AuraEnabled
    public Date closingDate;
    @AuraEnabled
    public Date dueDate;
    /** True when a read hit its cap: lines and counters are partial. */
    @AuraEnabled
    public Boolean truncated = false;
    @AuraEnabled
    public Integer countReconciled = 0;
    @AuraEnabled
    public Integer countPartial = 0;
    @AuraEnabled
    public Integer countUnreconciled = 0;
    @AuraEnabled
    public Integer countUnverified = 0;
    /** UNRECONCILED and PARTIAL lines, shown first. */
    @AuraEnabled
    public List<QueueLine> pending = new List<QueueLine>();
    @AuraEnabled
    public List<QueueLine> unverified = new List<QueueLine>();
    @AuraEnabled
    public List<QueueLine> reconciled = new List<QueueLine>();
  }

  public class SuggestionQuery {
    public Id fundingId;
    public Id recordId;
  }

  public class ConfirmInput {
    public Id fundingId;
    public Id sourceId;
    public Decimal sourceVersion;
    public Id targetId;
    public Decimal targetVersion;
    public String operationKey;
  }

  // ------------------------------------------------------------------ access

  /** Reconciling relies on the link capability (AXF-134) and AXF-25, as on the 151/152 screens. */
  public static void requireAccess() {
    try {
      ALT_CLS_SourceLinkService.requireAccess();
    } catch (ALT_CLS_SourceLinkService.SourceLinkException denied) {
      throw new ReconciliationQueueException('UNAVAILABLE');
    }
  }

  private Boolean reconcileCache;
  public Boolean canReconcile() {
    if (reconcileCache == null) {
      try {
        requireAccess();
        reconcileCache = true;
      } catch (ReconciliationQueueException denied) {
        reconcileCache = false;
      }
    }
    return reconcileCache;
  }

  private static void check(Boolean valid, String code) {
    if (!valid) {
      throw new ReconciliationQueueException(code);
    }
  }

  private static Date today() {
    return todayOverride == null ? Date.today() : todayOverride;
  }

  private Map<Id, String> authorizedCache;
  private Map<Id, String> authorizedHolders() {
    if (authorizedCache == null) {
      authorizedCache = new Map<Id, String>();
      for (
        AXF_CLS_AuthorizedContextService.ContextView context : AXF_CLS_AuthorizedContextService.listAuthorizedContexts()
      ) {
        authorizedCache.put(context.accountId, context.label);
      }
    }
    return authorizedCache;
  }

  // ----------------------------------------------------------------- sources

  /** @description Available bank accounts and cards of every authorized holder (filter options). */
  public SourceList listSources() {
    SourceList result = new SourceList();
    Set<Id> holders = authorizedHolders().keySet();
    if (holders.isEmpty()) {
      return result;
    }
    Integer cap = MAX_SOURCES + 1;
    // A kind the user cannot read at all is simply absent; field access is enforced by USER_MODE.
    List<AXF_OBJ_BankAccount__c> banks = !readable(
        AXF_OBJ_BankAccount__c.SObjectType,
        AXF_OBJ_BankAccountTransaction__c.SObjectType
      )
      ? new List<AXF_OBJ_BankAccount__c>()
      : [
          SELECT
            Id,
            AXF_BA_LKP_Account__c,
            AXF_BA_TXT_InstitutionName__c,
            AXF_BA_LKP_BankInstitution__r.Name,
            AXF_BA_TXT_NumberMasked__c,
            AXF_BA_TXT_Type__c,
            AXF_BA_TXT_CurrencyIsoCode__c
          FROM AXF_OBJ_BankAccount__c
          WHERE
            AXF_BA_LKP_Account__c IN :holders
            AND AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE'
          WITH USER_MODE
          ORDER BY AXF_BA_LKP_Account__c, AXF_BA_TXT_InstitutionName__c, Id
          LIMIT :cap
        ];
    if (banks.size() > MAX_SOURCES) {
      result.truncated = true;
      banks.remove(banks.size() - 1);
    }
    for (AXF_OBJ_BankAccount__c row : banks) {
      result.items.add(bankView(row));
    }
    List<AXF_OBJ_CreditCard__c> cards = !readable(
        AXF_OBJ_CreditCard__c.SObjectType,
        AXF_OBJ_CreditCardTransaction__c.SObjectType
      )
      ? new List<AXF_OBJ_CreditCard__c>()
      : [
          SELECT
            Id,
            AXF_CC_LKP_Account__c,
            AXF_CC_TXT_InstitutionName__c,
            AXF_CC_LKP_BankInstitution__r.Name,
            AXF_CC_TXT_LastFourMasked__c,
            AXF_CC_TXT_Brand__c,
            AXF_CC_TXT_CurrencyIsoCode__c
          FROM AXF_OBJ_CreditCard__c
          WHERE
            AXF_CC_LKP_Account__c IN :holders
            AND AXF_CC_PKL_AvailabilityState__c = 'AVAILABLE'
          WITH USER_MODE
          ORDER BY AXF_CC_LKP_Account__c, AXF_CC_TXT_InstitutionName__c, Id
          LIMIT :cap
        ];
    if (cards.size() > MAX_SOURCES) {
      result.truncated = true;
      cards.remove(cards.size() - 1);
    }
    for (AXF_OBJ_CreditCard__c row : cards) {
      result.items.add(cardView(row));
    }
    return result;
  }

  private static Boolean readable(
    Schema.SObjectType funding,
    Schema.SObjectType facts
  ) {
    return funding.getDescribe().isAccessible() &&
      facts.getDescribe().isAccessible();
  }

  private SourceView bankView(AXF_OBJ_BankAccount__c row) {
    SourceView v = new SourceView();
    v.kind = KIND_BANK;
    v.fundingId = row.Id;
    v.holderId = row.AXF_BA_LKP_Account__c;
    v.holderLabel = authorizedHolders().get(row.AXF_BA_LKP_Account__c);
    Boolean wallet = ALT_CLS_BankStatementService.TYPE_WALLET.equalsIgnoreCase(
      row.AXF_BA_TXT_Type__c
    );
    String institution = wallet
      ? null
      : (row.AXF_BA_LKP_BankInstitution__r == null
          ? row.AXF_BA_TXT_InstitutionName__c
          : row.AXF_BA_LKP_BankInstitution__r.Name);
    v.name = String.join(
      nonBlank(new List<String>{ institution, row.AXF_BA_TXT_NumberMasked__c }),
      ' '
    );
    v.currencyIso = row.AXF_BA_TXT_CurrencyIsoCode__c;
    return v;
  }

  private SourceView cardView(AXF_OBJ_CreditCard__c row) {
    SourceView v = new SourceView();
    v.kind = KIND_CARD;
    v.fundingId = row.Id;
    v.holderId = row.AXF_CC_LKP_Account__c;
    v.holderLabel = authorizedHolders().get(row.AXF_CC_LKP_Account__c);
    String institution = row.AXF_CC_LKP_BankInstitution__r == null
      ? row.AXF_CC_TXT_InstitutionName__c
      : row.AXF_CC_LKP_BankInstitution__r.Name;
    v.name = String.join(
      nonBlank(
        new List<String>{
          institution,
          row.AXF_CC_TXT_Brand__c,
          row.AXF_CC_TXT_LastFourMasked__c
        }
      ),
      ' '
    );
    v.currencyIso = row.AXF_CC_TXT_CurrencyIsoCode__c;
    return v;
  }

  private static List<String> nonBlank(List<String> values) {
    List<String> result = new List<String>();
    for (String value : values) {
      if (String.isNotBlank(value)) {
        result.add(value);
      }
    }
    return result;
  }

  /** One account or card of an authorized holder; anything else is indistinguishable from missing. */
  private SourceView readFunding(Id fundingId) {
    Schema.SObjectType type = fundingId.getSObjectType();
    if (type == AXF_OBJ_BankAccount__c.SObjectType) {
      List<AXF_OBJ_BankAccount__c> rows = [
        SELECT
          Id,
          AXF_BA_LKP_Account__c,
          AXF_BA_TXT_InstitutionName__c,
          AXF_BA_LKP_BankInstitution__r.Name,
          AXF_BA_TXT_NumberMasked__c,
          AXF_BA_TXT_Type__c,
          AXF_BA_TXT_CurrencyIsoCode__c,
          AXF_BA_PKL_AvailabilityState__c
        FROM AXF_OBJ_BankAccount__c
        WHERE Id = :fundingId
        WITH USER_MODE
        LIMIT 1
      ];
      check(
        rows.size() == 1 &&
          authorizedHolders().containsKey(rows[0].AXF_BA_LKP_Account__c) &&
          rows[0].AXF_BA_PKL_AvailabilityState__c == 'AVAILABLE',
        'NOT_ACCESSIBLE'
      );
      return bankView(rows[0]);
    }
    check(type == AXF_OBJ_CreditCard__c.SObjectType, 'INVALID_INPUT');
    List<AXF_OBJ_CreditCard__c> rows = [
      SELECT
        Id,
        AXF_CC_LKP_Account__c,
        AXF_CC_TXT_InstitutionName__c,
        AXF_CC_LKP_BankInstitution__r.Name,
        AXF_CC_TXT_LastFourMasked__c,
        AXF_CC_TXT_Brand__c,
        AXF_CC_TXT_CurrencyIsoCode__c,
        AXF_CC_PKL_AvailabilityState__c
      FROM AXF_OBJ_CreditCard__c
      WHERE Id = :fundingId
      WITH USER_MODE
      LIMIT 1
    ];
    check(
      rows.size() == 1 &&
        authorizedHolders().containsKey(rows[0].AXF_CC_LKP_Account__c) &&
        rows[0].AXF_CC_PKL_AvailabilityState__c == 'AVAILABLE',
      'NOT_ACCESSIBLE'
    );
    return cardView(rows[0]);
  }

  // ------------------------------------------------------------------- queue

  /** Invoice classification of one card (same rule as the AXF-152 invoice scope). */
  private class InvoiceScope {
    public Boolean blocked = false;
    public Integer year;
    public Integer month;
    public Date windowStart;
    public Date windowEnd;
    public ALT_CLS_CardInvoiceCalendar calendar;

    public Boolean contains(Date onDate) {
      if (onDate == null) {
        return false;
      }
      Boolean inWindow = onDate >= windowStart && onDate <= windowEnd;
      Date invoiceMonth = calendar.invoiceMonthOf(onDate);
      if (blocked) {
        // Civil month without a calendar: a dated purchase with a rule belongs to its own invoice.
        return inWindow && invoiceMonth == null;
      }
      if (invoiceMonth == null) {
        return inWindow;
      }
      return invoiceMonth.year() == year && invoiceMonth.month() == month;
    }
  }

  /** @description The Pluggy facts of the authorized context matching every filter given. */
  public QueueView queue(QueueQuery query) {
    check(query != null, 'INVALID_INPUT');
    validate(query);
    String status = query.status == null ? STATUS_PENDING : query.status;
    QueueView result = new QueueView();
    result.canReconcile = canReconcile();
    result.status = status;

    Map<Id, SourceView> fundings = new Map<Id, SourceView>();
    if (query.fundingId != null) {
      SourceView selected = readFunding(query.fundingId);
      check(query.kind == null || query.kind == selected.kind, 'INVALID_INPUT');
      fundings.put(selected.fundingId, selected);
    } else {
      SourceList all = listSources();
      result.truncated = all.truncated;
      for (SourceView v : all.items) {
        if (query.kind == null || query.kind == v.kind) {
          fundings.put(v.fundingId, v);
        }
      }
    }

    Boolean withInvoice = query.invoiceYear != null;
    InvoiceScope scope;
    Date readFrom;
    Date readTo;
    if (withInvoice) {
      SourceView card = fundings.values()[0];
      check(card.kind == KIND_CARD, 'INVALID_INPUT');
      scope = invoiceScope(card.fundingId, query, result);
      Integer margin = scope.blocked || scope.calendar.ruleCount() <= 1
        ? 0
        : CLASSIFY_MARGIN_DAYS;
      readFrom = scope.windowStart.addDays(-margin);
      readTo = scope.windowEnd.addDays(margin);
      result.invoiceFromDate = scope.windowStart;
      result.invoiceToDate = scope.windowEnd;
      result.fromDate = scope.windowStart;
      result.toDate = scope.windowEnd;
      if (query.fromDate != null) {
        // The period only narrows the lines inside the invoice; the response says so.
        result.customPeriod = true;
        readFrom = max(readFrom, query.fromDate);
        readTo = min(readTo, query.toDate);
        result.fromDate = max(scope.windowStart, query.fromDate);
        result.toDate = min(scope.windowEnd, query.toDate);
      }
    } else {
      period(query, result);
      readFrom = result.fromDate;
      readTo = result.toDate;
    }

    Set<Id> banks = new Set<Id>();
    Set<Id> cards = new Set<Id>();
    for (SourceView v : fundings.values()) {
      if (v.kind == KIND_BANK) {
        banks.add(v.fundingId);
      } else {
        cards.add(v.fundingId);
      }
    }
    // Pending view: facts never allocated and facts with allocations are read apart, so the
    // backlog is never pushed out of the capped read by reconciled rows.
    List<String> reads = status == STATUS_PENDING &&
      AXF_OBJ_ReconciliationAllocation__c.SObjectType.getDescribe()
        .isAccessible()
      ? new List<String>{ JOIN_UNALLOCATED, JOIN_ALLOCATED }
      : new List<String>{ JOIN_NONE };
    List<QueueLine> lines = new List<QueueLine>();
    if (readFrom <= readTo) {
      for (String allocationRead : reads) {
        lines.addAll(
          bankLines(
            banks,
            fundings,
            query,
            readFrom,
            readTo,
            allocationRead,
            result
          )
        );
        for (
          QueueLine line : cardLines(
            cards,
            fundings,
            query,
            readFrom,
            readTo,
            allocationRead,
            result
          )
        ) {
          if (scope == null || scope.contains(line.lineDate)) {
            lines.add(line);
          }
        }
      }
    }
    applyStatuses(lines);
    groupLines(lines, status, result);
    return result;
  }

  private static void validate(QueueQuery query) {
    check(
      (query.kind == null || KINDS.contains(query.kind)) &&
        (query.status == null || STATUSES.contains(query.status)) &&
        (query.minAmount == null ||
        query.minAmount >= 0) &&
        (query.maxAmount == null ||
        query.maxAmount >= 0) &&
        (query.minAmount == null ||
        query.maxAmount == null ||
        query.minAmount <= query.maxAmount) &&
        (query.term == null ||
        query.term.length() <= 100),
      'INVALID_INPUT'
    );
    if (query.fromDate != null || query.toDate != null) {
      check(
        query.fromDate != null &&
          query.toDate != null &&
          query.fromDate <= query.toDate &&
          query.fromDate.daysBetween(query.toDate) < MAX_PERIOD_DAYS,
        'INVALID_INPUT'
      );
    }
    if (query.invoiceYear != null || query.invoiceMonth != null) {
      // An invoice exists only for one card: the reference month without a card is refused.
      check(
        query.invoiceYear != null &&
          query.invoiceMonth != null &&
          query.invoiceYear >= 1900 &&
          query.invoiceYear <= 9999 &&
          query.invoiceMonth >= 1 &&
          query.invoiceMonth <= 12 &&
          query.fundingId != null &&
          query.fundingId.getSObjectType() == AXF_OBJ_CreditCard__c.SObjectType,
        'INVALID_INPUT'
      );
    }
  }

  /** Custom period (bounded) or, by default, the last 366 days up to today. */
  private static void period(QueueQuery query, QueueView result) {
    if (query.fromDate != null) {
      result.customPeriod = true;
      result.fromDate = query.fromDate;
      result.toDate = query.toDate;
      return;
    }
    result.toDate = today();
    result.fromDate = result.toDate.addDays(-(MAX_PERIOD_DAYS - 1));
  }

  private static final String JOIN_NONE = 'NONE';
  private static final String JOIN_UNALLOCATED = 'UNALLOCATED';
  private static final String JOIN_ALLOCATED = 'ALLOCATED';

  /** Restricts the facts to those without any allocation, with some, or neither. */
  private static String allocationJoin(String allocationRead, String lookup) {
    if (allocationRead == JOIN_NONE) {
      return '';
    }
    return ' AND Id ' +
      (allocationRead == JOIN_UNALLOCATED ? 'NOT IN' : 'IN') +
      ' (SELECT ' +
      lookup +
      ' FROM AXF_OBJ_ReconciliationAllocation__c WHERE ' +
      lookup +
      ' != NULL)';
  }

  private static InvoiceScope invoiceScope(
    Id creditCardId,
    QueueQuery query,
    QueueView result
  ) {
    ALT_CLS_CardInvoiceCalendar calendar = ALT_CLS_CardInvoiceCalendar.forCards(
        new Set<Id>{ creditCardId },
        businessDaysOverride
      )
      .get(creditCardId);
    ALT_CLS_CardInvoiceCalendar.Invoice invoice = calendar.invoice(
      query.invoiceYear,
      query.invoiceMonth
    );
    InvoiceScope scope = new InvoiceScope();
    scope.calendar = calendar;
    scope.year = query.invoiceYear;
    scope.month = query.invoiceMonth;
    scope.blocked =
      invoice.outcome == ALT_CLS_CardInvoiceCalendar.OUTCOME_BLOCKED;
    scope.windowStart = invoice.windowStart;
    scope.windowEnd = invoice.windowEnd;
    result.invoiceYear = query.invoiceYear;
    result.invoiceMonth = query.invoiceMonth;
    result.invoiceOutcome = invoice.outcome;
    result.closingDate = invoice.closingDate;
    result.dueDate = invoice.dueDate;
    return scope;
  }

  private static Date max(Date a, Date b) {
    return a > b ? a : b;
  }

  private static Date min(Date a, Date b) {
    return a < b ? a : b;
  }

  private static String pattern(String term) {
    // Bound values treat escaped wildcards literally; the search never reaches the SOQL text.
    return ('%' +
    term.trim().replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_') +
    '%');
  }

  private static String filters(String prefix, QueueQuery query) {
    return (query.minAmount == null
        ? ''
        : ' AND ' + prefix + '_NUM_Magnitude__c >= :minAmount') +
      (query.maxAmount == null
        ? ''
        : ' AND ' + prefix + '_NUM_Magnitude__c <= :maxAmount') +
      (String.isBlank(query.term)
        ? ''
        : ' AND ' + prefix + '_TXT_Description__c LIKE :pattern');
  }

  private static Map<String, Object> binds(
    Set<Id> fundingIds,
    QueueQuery query,
    Date readFrom,
    Date readTo
  ) {
    return new Map<String, Object>{
      'fundingIds' => fundingIds,
      'source' => SOURCE_PLUGGY,
      'fromDate' => readFrom,
      'toDate' => readTo,
      'minAmount' => query.minAmount,
      'maxAmount' => query.maxAmount,
      'pattern' => String.isBlank(query.term) ? null : pattern(query.term),
      'cap' => MAX_FACTS + 1
    };
  }

  private List<QueueLine> bankLines(
    Set<Id> bankIds,
    Map<Id, SourceView> fundings,
    QueueQuery query,
    Date readFrom,
    Date readTo,
    String allocationRead,
    QueueView result
  ) {
    List<QueueLine> lines = new List<QueueLine>();
    if (bankIds.isEmpty()) {
      return lines;
    }
    String soql =
      'SELECT Id, AXF_BAT_MDR_BankAccount__c, AXF_BAT_NUM_Magnitude__c, AXF_BAT_TXT_CurrencyIsoCode__c,' +
      ' AXF_BAT_PKL_Direction__c, AXF_BAT_DAT_Date__c, AXF_BAT_TXT_Description__c, AXF_BAT_NUM_Version__c' +
      ' FROM AXF_OBJ_BankAccountTransaction__c' +
      ' WHERE AXF_BAT_MDR_BankAccount__c IN :fundingIds' +
      ' AND AXF_BAT_PKL_Source__c = :source' +
      ' AND AXF_BAT_PKL_Status__c = \'POSTED\'' +
      ' AND AXF_BAT_DAT_Date__c >= :fromDate AND AXF_BAT_DAT_Date__c <= :toDate' +
      filters('AXF_BAT', query) +
      allocationJoin(allocationRead, 'AXF_RA_LKP_BankTransaction__c') +
      ' ORDER BY AXF_BAT_DAT_Date__c DESC, Id ASC LIMIT :cap';
    List<AXF_OBJ_BankAccountTransaction__c> rows = (List<AXF_OBJ_BankAccountTransaction__c>) Database.queryWithBinds(
      soql,
      binds(bankIds, query, readFrom, readTo),
      AccessLevel.USER_MODE
    );
    if (rows.size() > MAX_FACTS) {
      result.truncated = true;
      rows.remove(rows.size() - 1);
    }
    for (AXF_OBJ_BankAccountTransaction__c row : rows) {
      SourceView funding = fundings.get(row.AXF_BAT_MDR_BankAccount__c);
      QueueLine line = new QueueLine();
      line.kind = KIND_BANK;
      line.fundingId = funding.fundingId;
      line.fundingName = funding.name;
      line.holderLabel = funding.holderLabel;
      line.recordId = row.Id;
      line.lineDate = row.AXF_BAT_DAT_Date__c;
      line.description = row.AXF_BAT_TXT_Description__c;
      line.amount = row.AXF_BAT_NUM_Magnitude__c;
      line.direction = row.AXF_BAT_PKL_Direction__c;
      line.currencyIso = row.AXF_BAT_TXT_CurrencyIsoCode__c;
      line.version = row.AXF_BAT_NUM_Version__c == null
        ? 0
        : row.AXF_BAT_NUM_Version__c;
      lines.add(line);
    }
    return lines;
  }

  private List<QueueLine> cardLines(
    Set<Id> cardIds,
    Map<Id, SourceView> fundings,
    QueueQuery query,
    Date readFrom,
    Date readTo,
    String allocationRead,
    QueueView result
  ) {
    List<QueueLine> lines = new List<QueueLine>();
    if (cardIds.isEmpty()) {
      return lines;
    }
    String soql =
      'SELECT Id, AXF_CCT_MDR_CreditCard__c, AXF_CCT_NUM_Magnitude__c, AXF_CCT_TXT_CurrencyIsoCode__c,' +
      ' AXF_CCT_PKL_Direction__c, AXF_CCT_DAT_Date__c, AXF_CCT_TXT_Description__c, AXF_CCT_NUM_Version__c' +
      ' FROM AXF_OBJ_CreditCardTransaction__c' +
      ' WHERE AXF_CCT_MDR_CreditCard__c IN :fundingIds' +
      ' AND AXF_CCT_PKL_Source__c = :source' +
      ' AND AXF_CCT_PKL_Status__c = \'POSTED\'' +
      ' AND AXF_CCT_DAT_Date__c >= :fromDate AND AXF_CCT_DAT_Date__c <= :toDate' +
      filters('AXF_CCT', query) +
      allocationJoin(allocationRead, 'AXF_RA_LKP_CardTransaction__c') +
      ' ORDER BY AXF_CCT_DAT_Date__c DESC, Id ASC LIMIT :cap';
    List<AXF_OBJ_CreditCardTransaction__c> rows = (List<AXF_OBJ_CreditCardTransaction__c>) Database.queryWithBinds(
      soql,
      binds(cardIds, query, readFrom, readTo),
      AccessLevel.USER_MODE
    );
    if (rows.size() > MAX_FACTS) {
      result.truncated = true;
      rows.remove(rows.size() - 1);
    }
    for (AXF_OBJ_CreditCardTransaction__c row : rows) {
      SourceView funding = fundings.get(row.AXF_CCT_MDR_CreditCard__c);
      QueueLine line = new QueueLine();
      line.kind = KIND_CARD;
      line.fundingId = funding.fundingId;
      line.fundingName = funding.name;
      line.holderLabel = funding.holderLabel;
      line.recordId = row.Id;
      line.lineDate = row.AXF_CCT_DAT_Date__c;
      line.description = row.AXF_CCT_TXT_Description__c;
      line.amount = row.AXF_CCT_NUM_Magnitude__c;
      line.direction = row.AXF_CCT_PKL_Direction__c;
      line.currencyIso = row.AXF_CCT_TXT_CurrencyIsoCode__c;
      line.version = row.AXF_CCT_NUM_Version__c == null
        ? 0
        : row.AXF_CCT_NUM_Version__c;
      lines.add(line);
    }
    return lines;
  }

  // ------------------------------------------------------------------ status

  /** Derived status exactly as on the 151/152 screens (net APPLICATION minus REVERSAL). */
  private void applyStatuses(List<QueueLine> lines) {
    Map<String, Set<Id>> idsByLookup = new Map<String, Set<Id>>{
      'AXF_RA_LKP_BankTransaction__c' => new Set<Id>(),
      'AXF_RA_LKP_CardTransaction__c' => new Set<Id>()
    };
    for (QueueLine line : lines) {
      idsByLookup.get(
          line.kind == KIND_BANK
            ? 'AXF_RA_LKP_BankTransaction__c'
            : 'AXF_RA_LKP_CardTransaction__c'
        )
        .add(line.recordId);
    }
    Set<Id> unverified = new Set<Id>();
    Map<Id, Decimal> nets = nets(idsByLookup, unverified);
    for (QueueLine line : lines) {
      if (unverified.contains(line.recordId) || line.amount == null) {
        line.status = STATUS_UNVERIFIED;
        continue;
      }
      line.allocated = nets.containsKey(line.recordId)
        ? nets.get(line.recordId)
        : 0;
      line.residual = line.amount - line.allocated;
      if (line.residual <= 0) {
        line.status = STATUS_RECONCILED;
      } else if (line.allocated > 0) {
        line.status = STATUS_PARTIAL;
      } else {
        line.status = STATUS_UNRECONCILED;
      }
      line.canSuggest = line.residual > 0 && canReconcile();
    }
  }

  /**
   * Net allocation per fact. With the link capability the link contract's verified net is used;
   * without it the net of the allocations the user can see, and a truncated or refused read leaves
   * the rows unverified instead of guessing (same rule as the 151/152 services).
   */
  private Map<Id, Decimal> nets(
    Map<String, Set<Id>> idsByLookup,
    Set<Id> unverified
  ) {
    Map<Id, Decimal> result = new Map<Id, Decimal>();
    for (String lookup : idsByLookup.keySet()) {
      for (Set<Id> chunk : chunks(idsByLookup.get(lookup))) {
        if (canReconcile()) {
          result.putAll(
            new ALT_CLS_SourceLinkService().netOfSources(chunk, unverified)
          );
        } else {
          visibleNets(lookup, chunk, result, unverified);
        }
      }
    }
    return result;
  }

  private static List<Set<Id>> chunks(Set<Id> ids) {
    List<Set<Id>> result = new List<Set<Id>>();
    Set<Id> current = new Set<Id>();
    for (Id factId : ids) {
      if (current.size() == NET_CHUNK) {
        result.add(current);
        current = new Set<Id>();
      }
      current.add(factId);
    }
    if (!current.isEmpty()) {
      result.add(current);
    }
    return result;
  }

  /** Net of the allocations the user can see, for one kind of fact and one chunk of ids. */
  private static void visibleNets(
    String lookup,
    Set<Id> ids,
    Map<Id, Decimal> result,
    Set<Id> unverified
  ) {
    Integer cap = allocationCapOverride == null
      ? ALT_CLS_SourceLinkService.MAX_ALLOCATION_ROWS
      : allocationCapOverride;
    List<AXF_OBJ_ReconciliationAllocation__c> rows;
    try {
      rows = (List<AXF_OBJ_ReconciliationAllocation__c>) Database.queryWithBinds(
        'SELECT ' +
          lookup +
          ', AXF_RA_PKL_Kind__c, AXF_RA_NUM_Magnitude__c' +
          ' FROM AXF_OBJ_ReconciliationAllocation__c WHERE ' +
          lookup +
          ' IN :ids LIMIT :cap',
        new Map<String, Object>{ 'ids' => ids, 'cap' => cap },
        AccessLevel.USER_MODE
      );
    } catch (Exception refused) {
      unverified.addAll(ids);
      return;
    }
    if (rows.size() >= cap) {
      unverified.addAll(ids);
      return;
    }
    for (AXF_OBJ_ReconciliationAllocation__c row : rows) {
      Id key = (Id) row.get(lookup);
      if (row.AXF_RA_NUM_Magnitude__c == null) {
        // An allocation without magnitude cannot be netted: never guess.
        unverified.add(key);
        continue;
      }
      Decimal sign = row.AXF_RA_PKL_Kind__c == 'REVERSAL' ? -1 : 1;
      result.put(
        key,
        (result.containsKey(key) ? result.get(key) : 0) +
        sign * row.AXF_RA_NUM_Magnitude__c
      );
    }
  }

  /** Counters over every line; the status filter only selects the lines listed. */
  private static void groupLines(
    List<QueueLine> lines,
    String status,
    QueueView result
  ) {
    List<LineKey> keys = new List<LineKey>();
    for (QueueLine line : lines) {
      keys.add(new LineKey(line));
    }
    keys.sort();
    for (LineKey key : keys) {
      QueueLine line = key.line;
      if (line.status == STATUS_RECONCILED) {
        result.countReconciled++;
      } else if (line.status == STATUS_PARTIAL) {
        result.countPartial++;
      } else if (line.status == STATUS_UNRECONCILED) {
        result.countUnreconciled++;
      } else {
        result.countUnverified++;
      }
      Boolean pending =
        line.status == STATUS_PARTIAL ||
        line.status == STATUS_UNRECONCILED;
      if (
        status != STATUS_ALL &&
        status != line.status &&
        !(status == STATUS_PENDING && pending)
      ) {
        continue;
      }
      if (pending) {
        result.pending.add(line);
      } else if (line.status == STATUS_RECONCILED) {
        result.reconciled.add(line);
      } else {
        result.unverified.add(line);
      }
    }
  }

  private class LineKey implements Comparable {
    public QueueLine line;
    public LineKey(QueueLine line) {
      this.line = line;
    }
    public Integer compareTo(Object other) {
      QueueLine b = ((LineKey) other).line;
      if (line.lineDate != b.lineDate) {
        if (line.lineDate == null) {
          return 1;
        }
        if (b.lineDate == null) {
          return -1;
        }
        return line.lineDate > b.lineDate ? -1 : 1;
      }
      return String.valueOf(line.recordId)
        .compareTo(String.valueOf(b.recordId));
    }
  }

  // ------------------------------------------------------- delegated engine

  /** @description Suggestions of one Pluggy fact from the AXF-151/152 engine, unchanged. */
  public ALT_CLS_BankStatementService.SuggestionPage suggest(
    SuggestionQuery query
  ) {
    requireAccess();
    check(
      query != null && query.fundingId != null && query.recordId != null,
      'INVALID_INPUT'
    );
    Schema.SObjectType type = query.fundingId.getSObjectType();
    try {
      if (type == AXF_OBJ_BankAccount__c.SObjectType) {
        ALT_CLS_BankStatementService.SuggestionQuery bank = new ALT_CLS_BankStatementService.SuggestionQuery();
        bank.bankAccountId = query.fundingId;
        bank.lineKind = LINE_FACT;
        bank.recordId = query.recordId;
        return new ALT_CLS_BankStatementService().suggest(bank);
      }
      if (type == AXF_OBJ_CreditCard__c.SObjectType) {
        ALT_CLS_CardStatementService.SuggestionQuery card = new ALT_CLS_CardStatementService.SuggestionQuery();
        card.creditCardId = query.fundingId;
        card.lineKind = LINE_FACT;
        card.recordId = query.recordId;
        return new ALT_CLS_CardStatementService().suggest(card);
      }
    } catch (ALT_CLS_BankStatementService.BankStatementException failure) {
      throw new ReconciliationQueueException(failure.getMessage());
    } catch (ALT_CLS_CardStatementService.CardStatementException failure) {
      throw new ReconciliationQueueException(failure.getMessage());
    }
    throw new ReconciliationQueueException('INVALID_INPUT');
  }

  /** @description One-click confirmation through the AXF-151/152 engine, unchanged. */
  public ALT_CLS_BankStatementService.ConfirmResult confirm(
    ConfirmInput input
  ) {
    requireAccess();
    check(input != null && input.fundingId != null, 'INVALID_INPUT');
    Schema.SObjectType type = input.fundingId.getSObjectType();
    try {
      if (type == AXF_OBJ_BankAccount__c.SObjectType) {
        ALT_CLS_BankStatementService.ConfirmInput bank = new ALT_CLS_BankStatementService.ConfirmInput();
        bank.bankAccountId = input.fundingId;
        bank.sourceId = input.sourceId;
        bank.sourceVersion = input.sourceVersion;
        bank.targetId = input.targetId;
        bank.targetVersion = input.targetVersion;
        bank.operationKey = input.operationKey;
        return new ALT_CLS_BankStatementService().confirm(bank);
      }
      if (type == AXF_OBJ_CreditCard__c.SObjectType) {
        ALT_CLS_CardStatementService.ConfirmInput card = new ALT_CLS_CardStatementService.ConfirmInput();
        card.creditCardId = input.fundingId;
        card.sourceId = input.sourceId;
        card.sourceVersion = input.sourceVersion;
        card.targetId = input.targetId;
        card.targetVersion = input.targetVersion;
        card.operationKey = input.operationKey;
        return new ALT_CLS_CardStatementService().confirm(card);
      }
    } catch (ALT_CLS_BankStatementService.BankStatementException failure) {
      throw new ReconciliationQueueException(failure.getMessage());
    } catch (ALT_CLS_CardStatementService.CardStatementException failure) {
      throw new ReconciliationQueueException(failure.getMessage());
    }
    throw new ReconciliationQueueException('INVALID_INPUT');
  }
}
