/**
 * @description AXF-152: credit-card capability ("Cartão de crédito"). Lists the available cards of
 * the authorized holders with their limits and the closing/due days of the rule in force today,
 * lets a configurator define the closing of a card without a calendar (AXF-35 draft + activate in
 * one command), builds the invoice of a reference month from the calendar derived per purchase
 * date (ALT_CLS_CardInvoiceCalendar) with a derived reconciliation status, suggests candidates
 * inside the AXF-MATCHING@1.1.0 window and confirms one of them through the AXF-134 link contract
 * — the same contract as the current-account screen (AXF-151), with the card as the source kind.
 * Reconciliation state is never written and no invoice record is persisted.
 */
public with sharing class ALT_CLS_CardStatementService {
  public static final String MATCHING_POLICY = ALT_CLS_MatchingWindow.POLICY;
  public static final String CALENDAR_POLICY = ALT_CLS_CardInvoiceCalendar.CALENDAR_POLICY;
  public static final String CP_CONFIGURE = 'AXF_CanConfigure';
  public static final String LINE_FACT = ALT_CLS_BankStatementService.LINE_FACT;
  public static final String LINE_ENTRY = ALT_CLS_BankStatementService.LINE_ENTRY;
  public static final String STATUS_RECONCILED = ALT_CLS_BankStatementService.STATUS_RECONCILED;
  public static final String STATUS_PARTIAL = ALT_CLS_BankStatementService.STATUS_PARTIAL;
  public static final String STATUS_UNRECONCILED = ALT_CLS_BankStatementService.STATUS_UNRECONCILED;
  public static final String STATUS_UNVERIFIED = ALT_CLS_BankStatementService.STATUS_UNVERIFIED;
  public static final Integer DAY_WINDOW = ALT_CLS_MatchingWindow.DAY_WINDOW;
  public static final Integer MAX_CARDS = 200;
  public static final Integer MAX_FACTS = 500;
  public static final Integer MAX_ENTRIES = 200;
  public static final Integer MAX_PERIOD_DAYS = 366;
  public static final Integer MAX_SUGGESTION_PAGES = 4;
  /**
   * With more than one rule a purchase near the window may belong to a neighbouring invoice by the
   * rule of its own date; the read reaches this far past the window so it can be classified.
   */
  private static final Integer CLASSIFY_MARGIN_DAYS = 35;
  private static final Set<String> PLAN_KINDS = new Set<String>{
    'PLANNED',
    'ACTUAL_ONLY'
  };

  @TestVisible
  private static Boolean canConfigureOverride;
  @TestVisible
  private static Date todayOverride;
  @TestVisible
  private static ALT_CLS_CardInvoiceCalendar.BusinessDays businessDaysOverride;

  public class CardStatementException extends Exception {
  }

  public class CardView {
    @AuraEnabled
    public Id creditCardId;
    @AuraEnabled
    public Id holderId;
    @AuraEnabled
    public String holderLabel;
    @AuraEnabled
    public String institutionName;
    @AuraEnabled
    public String lastFour;
    @AuraEnabled
    public String brand;
    /** Null for a card without reported limits (a manual card): shown as "—", never zero. */
    @AuraEnabled
    public Decimal creditLimit;
    @AuraEnabled
    public Decimal availableLimit;
    @AuraEnabled
    public String currencyIso;
    @AuraEnabled
    public Boolean hasConnection = false;
    /** True when an ACTIVE rule with a calendar policy is in force today. */
    @AuraEnabled
    public Boolean hasCalendar = false;
    @AuraEnabled
    public Integer closingDay;
    @AuraEnabled
    public Integer dueDay;
    @AuraEnabled
    public Boolean canDefineClosing = false;
  }

  public class InvoiceQuery {
    public Id creditCardId;
    public Integer year;
    public Integer month;
    public Date fromDate;
    public Date toDate;
    public Decimal minAmount;
    public Decimal maxAmount;
    public String term;
  }

  public class InvoiceView {
    @AuraEnabled
    public String matchingPolicy = MATCHING_POLICY;
    @AuraEnabled
    public String calendarPolicy = CALENDAR_POLICY;
    @AuraEnabled
    public CardView card;
    @AuraEnabled
    public Integer year;
    @AuraEnabled
    public Integer month;
    @AuraEnabled
    public Boolean customPeriod = false;
    /** RESOLVED (invoice window) | BLOCKED (civil month, no calendar). */
    @AuraEnabled
    public String outcome;
    @AuraEnabled
    public String blockedReason;
    @AuraEnabled
    public Date fromDate;
    @AuraEnabled
    public Date toDate;
    @AuraEnabled
    public Date closingDate;
    @AuraEnabled
    public Date dueDate;
    /** Net of the card facts of the invoice (debits minus credits), before the filters. */
    @AuraEnabled
    public Decimal total = 0;
    /** Net of the manual entries still unallocated in the invoice, before the filters. */
    @AuraEnabled
    public Decimal plannedTotal = 0;
    @AuraEnabled
    public String currencyIso;
    /** True when lines in another currency exist: they are listed but left out of the totals. */
    @AuraEnabled
    public Boolean mixedCurrency = false;
    @AuraEnabled
    public Boolean canReconcile = false;
    /** True when the read hit its cap: the lines and the totals are partial. */
    @AuraEnabled
    public Boolean truncated = false;
    @AuraEnabled
    public List<ALT_CLS_BankStatementService.LineView> lines = new List<ALT_CLS_BankStatementService.LineView>();
  }

  public class SuggestionQuery {
    public Id creditCardId;
    public String lineKind;
    public Id recordId;
  }

  public class ConfirmInput {
    public Id creditCardId;
    public Id sourceId;
    public Decimal sourceVersion;
    public Id targetId;
    public Decimal targetVersion;
    public String operationKey;
  }

  public class ClosingInput {
    public Id creditCardId;
    public Integer closingDay;
    public Integer dueDay;
  }

  // ------------------------------------------------------------------ access

  public static Boolean canConfigure() {
    return canConfigureOverride == null
      ? FeatureManagement.checkPermission(CP_CONFIGURE)
      : canConfigureOverride;
  }

  /** Reconciling relies on the link capability (AXF-134) and AXF-25. */
  public static void requireAccess() {
    try {
      ALT_CLS_SourceLinkService.requireAccess();
    } catch (ALT_CLS_SourceLinkService.SourceLinkException denied) {
      throw new CardStatementException('UNAVAILABLE');
    }
  }

  private Boolean reconcileCache;
  public Boolean canReconcile() {
    if (reconcileCache == null) {
      try {
        requireAccess();
        reconcileCache = true;
      } catch (CardStatementException denied) {
        reconcileCache = false;
      }
    }
    return reconcileCache;
  }

  private static void check(Boolean valid, String code) {
    if (!valid) {
      throw new CardStatementException(code);
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

  private static ALT_CLS_CardInvoiceCalendar calendarOf(Id creditCardId) {
    return ALT_CLS_CardInvoiceCalendar.forCards(
        new Set<Id>{ creditCardId },
        businessDaysOverride
      )
      .get(creditCardId);
  }

  // ------------------------------------------------------------------- cards

  /** @description Available cards of every authorized holder, with limits and calendar days. */
  public List<CardView> listCards() {
    Set<Id> holders = authorizedHolders().keySet();
    List<CardView> result = new List<CardView>();
    if (holders.isEmpty()) {
      return result;
    }
    List<AXF_OBJ_CreditCard__c> rows = [
      SELECT
        Id,
        AXF_CC_LKP_Account__c,
        AXF_CC_TXT_InstitutionName__c,
        AXF_CC_LKP_BankInstitution__r.Name,
        AXF_CC_TXT_LastFourMasked__c,
        AXF_CC_TXT_Brand__c,
        AXF_CC_CUR_CreditLimit__c,
        AXF_CC_CUR_AvailableLimit__c,
        AXF_CC_TXT_CurrencyIsoCode__c
      FROM AXF_OBJ_CreditCard__c
      WHERE
        AXF_CC_LKP_Account__c IN :holders
        AND AXF_CC_PKL_AvailabilityState__c = 'AVAILABLE'
      WITH USER_MODE
      ORDER BY AXF_CC_LKP_Account__c, AXF_CC_TXT_InstitutionName__c, Id
      LIMIT :MAX_CARDS
    ];
    Map<Id, ALT_CLS_CardInvoiceCalendar> calendars = ALT_CLS_CardInvoiceCalendar.forCards(
      new Map<Id, AXF_OBJ_CreditCard__c>(rows).keySet(),
      businessDaysOverride
    );
    connected(new Map<Id, AXF_OBJ_CreditCard__c>(rows).keySet());
    for (AXF_OBJ_CreditCard__c row : rows) {
      result.add(view(row, calendars.get(row.Id)));
    }
    return result;
  }

  private CardView view(
    AXF_OBJ_CreditCard__c row,
    ALT_CLS_CardInvoiceCalendar calendar
  ) {
    CardView v = new CardView();
    v.creditCardId = row.Id;
    v.holderId = row.AXF_CC_LKP_Account__c;
    v.holderLabel = authorizedHolders().get(row.AXF_CC_LKP_Account__c);
    v.institutionName = row.AXF_CC_LKP_BankInstitution__r == null
      ? row.AXF_CC_TXT_InstitutionName__c
      : row.AXF_CC_LKP_BankInstitution__r.Name;
    v.lastFour = row.AXF_CC_TXT_LastFourMasked__c;
    v.brand = row.AXF_CC_TXT_Brand__c;
    v.creditLimit = row.AXF_CC_CUR_CreditLimit__c;
    v.availableLimit = row.AXF_CC_CUR_AvailableLimit__c;
    v.currencyIso = row.AXF_CC_TXT_CurrencyIsoCode__c;
    v.hasConnection = connected(new Set<Id>{ row.Id }).contains(row.Id);
    ALT_CLS_CardInvoiceCalendar.Rule rule = calendar == null
      ? null
      : calendar.ruleOn(today());
    v.hasCalendar = rule != null;
    if (rule != null) {
      v.closingDay = rule.closingDay;
      // The due day shown is the one of the due date derived for the current invoice.
      ALT_CLS_CardInvoiceCalendar.Invoice current = calendar.invoiceOn(today());
      v.dueDay = current == null ||
        current.dueDate == null
        ? null
        : current.dueDate.day();
    }
    // Editing or superseding a rule is out of scope: the action is offered only when no ACTIVE
    // rule is in force or ahead (a future or unversioned one would make the save a CONFLICT).
    v.canDefineClosing =
      canConfigure() && (calendar == null || !calendar.overlapsFrom(today()));
    return v;
  }

  private Set<Id> connectedCache = new Set<Id>();
  private Set<Id> connectionRead = new Set<Id>();

  /**
   * Cards (already read in user mode through the authorized context) that have a Pluggy
   * connection. Only this flag leaves the read, never the connection itself: a reader without
   * access to the connection object must still see the card.
   */
  private Set<Id> connected(Set<Id> creditCardIds) {
    Set<Id> missing = new Set<Id>(creditCardIds);
    missing.removeAll(connectionRead);
    if (!missing.isEmpty()) {
      for (AXF_OBJ_CreditCard__c row : [
        SELECT Id
        FROM AXF_OBJ_CreditCard__c
        WHERE Id IN :missing AND AXF_CC_LKP_Connection__c != NULL
        WITH SYSTEM_MODE
      ]) {
        connectedCache.add(row.Id);
      }
      connectionRead.addAll(missing);
    }
    return connectedCache;
  }

  /** One card of an authorized holder; anything else is indistinguishable from missing. */
  private AXF_OBJ_CreditCard__c readCard(Id creditCardId) {
    check(
      creditCardId != null &&
        creditCardId.getSObjectType() == AXF_OBJ_CreditCard__c.SObjectType,
      'INVALID_INPUT'
    );
    List<AXF_OBJ_CreditCard__c> rows = [
      SELECT
        Id,
        AXF_CC_LKP_Account__c,
        AXF_CC_TXT_InstitutionName__c,
        AXF_CC_LKP_BankInstitution__r.Name,
        AXF_CC_TXT_LastFourMasked__c,
        AXF_CC_TXT_Brand__c,
        AXF_CC_CUR_CreditLimit__c,
        AXF_CC_CUR_AvailableLimit__c,
        AXF_CC_TXT_CurrencyIsoCode__c,
        AXF_CC_PKL_AvailabilityState__c
      FROM AXF_OBJ_CreditCard__c
      WHERE Id = :creditCardId
      WITH USER_MODE
      LIMIT 1
    ];
    check(
      rows.size() == 1 &&
        authorizedHolders().containsKey(rows[0].AXF_CC_LKP_Account__c) &&
        rows[0].AXF_CC_PKL_AvailabilityState__c == 'AVAILABLE',
      'NOT_ACCESSIBLE'
    );
    return rows[0];
  }

  // ----------------------------------------------------------------- closing

  /**
   * @description Defines the closing of a card that has no rule in force: an AXF-35 draft created
   * and activated in one command (atomic), valid from the oldest purchase of the card (or the first
   * day of the current month), open-ended, in the user's time zone, FOLLOWING on both days and the
   * CAL-1.0.0 policy. The due-day offset is the calendar days from the closing to the due day.
   */
  public CardView defineClosing(ClosingInput input) {
    check(input != null, 'INVALID_INPUT');
    check(canConfigure(), 'NOT_ALLOWED');
    AXF_OBJ_CreditCard__c card = readCard(input.creditCardId);
    check(
      input.closingDay != null &&
        input.closingDay >= 1 &&
        input.closingDay <= 31 &&
        input.dueDay != null &&
        input.dueDay >= 1 &&
        input.dueDay <= 31,
      'INVALID_INPUT'
    );
    // Rules are written only through the AXF-35 draft/activate flow (system mode): users hold
    // read-only access to the object, and AXF_CanConfigure is the only gate of this command.
    ALT_CLS_CardInvoiceCalendar calendar = calendarOf(card.Id);
    check(!calendar.overlapsFrom(today()), 'CONFLICT');
    // A closed rule of the past keeps its history: the new one starts exactly where it ended,
    // since AXF-35 forbids gaps between rules; otherwise at the oldest posted purchase.
    Date effectiveFrom = calendar.latestEnd();
    if (effectiveFrom == null) {
      effectiveFrom = oldestPurchase(card.Id);
    }
    if (effectiveFrom == null) {
      effectiveFrom = today().toStartOfMonth();
    }
    check(!calendar.overlapsFrom(effectiveFrom), 'CONFLICT');

    ALT_CLS_CardBillingCycleService.RuleInputDTO rule = new ALT_CLS_CardBillingCycleService.RuleInputDTO();
    rule.creditCardId = card.Id;
    rule.effectiveFrom = effectiveFrom;
    rule.effectiveTo = null;
    rule.timeZone = UserInfo.getTimeZone().getID();
    rule.closingDay = input.closingDay;
    rule.closingDayAdjustment = ALT_CLS_CardInvoiceCalendar.ADJUST_FOLLOWING;
    rule.dueDayOffset = ALT_CLS_CardInvoiceCalendar.dueOffset(
      input.closingDay,
      input.dueDay
    );
    rule.dueDayAdjustment = ALT_CLS_CardInvoiceCalendar.ADJUST_FOLLOWING;
    rule.calendarPolicyVersion = CALENDAR_POLICY;

    Savepoint before = Database.setSavepoint();
    try {
      ALT_CLS_CardBillingCycleService cycles = new ALT_CLS_CardBillingCycleService();
      ALT_CLS_CardBillingCycleService.ResultDTO draft = cycles.createDraft(
        rule
      );
      if (draft == null || draft.success != true || draft.ruleId == null) {
        Database.rollback(before);
        throw new CardStatementException('REJECTED');
      }
      ALT_CLS_CardBillingCycleService.ActivationInputDTO activation = new ALT_CLS_CardBillingCycleService.ActivationInputDTO();
      activation.ruleId = draft.ruleId;
      activation.expectedVersion = draft.version;
      ALT_CLS_CardBillingCycleService.ResultDTO active = cycles.activate(
        activation
      );
      if (active.success != true) {
        Database.rollback(before);
        throw new CardStatementException('REJECTED');
      }
    } catch (AXF_CLS_CardBillingCycleException refused) {
      Database.rollback(before);
      // Overlap, gap or a concurrent version: another rule got there first.
      throw new CardStatementException('CONFLICT');
    } catch (DmlException refused) {
      Database.rollback(before);
      throw new CardStatementException('REJECTED');
    }
    return view(readCard(card.Id), calendarOf(card.Id));
  }

  private static Date oldestPurchase(Id creditCardId) {
    List<AXF_OBJ_CreditCardTransaction__c> rows = [
      SELECT AXF_CCT_DAT_Date__c
      FROM AXF_OBJ_CreditCardTransaction__c
      WHERE
        AXF_CCT_MDR_CreditCard__c = :creditCardId
        AND AXF_CCT_PKL_Status__c = 'POSTED'
        AND AXF_CCT_DAT_Date__c != NULL
      WITH USER_MODE
      ORDER BY AXF_CCT_DAT_Date__c ASC
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0].AXF_CCT_DAT_Date__c;
  }

  // ----------------------------------------------------------------- invoice

  /** Which dates a line needs to belong to the requested invoice or period. */
  private class Scope {
    public Boolean blocked = false;
    public Integer year;
    public Integer month;
    public Date windowStart;
    public Date windowEnd;
    public Date readFrom;
    public Date readTo;
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

  /**
   * @description Invoice of one card for a reference month. The date filter only narrows the
   * lines inside that invoice; the invoice window, closing and due dates stay the invoice's.
   */
  public InvoiceView invoice(InvoiceQuery query) {
    check(query != null, 'INVALID_INPUT');
    AXF_OBJ_CreditCard__c card = readCard(query.creditCardId);
    check(
      (query.minAmount == null ||
        query.minAmount >= 0) &&
        (query.maxAmount == null ||
        query.maxAmount >= 0) &&
        (query.minAmount == null ||
        query.maxAmount == null ||
        query.minAmount <= query.maxAmount) &&
        (query.term == null ||
        query.term.length() <= 100) &&
        (query.fromDate == null ||
        query.toDate == null ||
        query.fromDate <= query.toDate),
      'INVALID_INPUT'
    );
    ALT_CLS_CardInvoiceCalendar calendar = calendarOf(card.Id);
    InvoiceView result = new InvoiceView();
    result.canReconcile = canReconcile();
    result.card = view(card, calendar);
    result.currencyIso = card.AXF_CC_TXT_CurrencyIsoCode__c;
    Scope scope = scope(query, result, calendar);

    List<ALT_CLS_BankStatementService.LineView> lines = new List<ALT_CLS_BankStatementService.LineView>();
    for (
      ALT_CLS_BankStatementService.LineView line : factLines(
        card,
        scope,
        result
      )
    ) {
      result.total += total(line, result);
      if (matches(line, query)) {
        lines.add(line);
      }
    }
    for (
      ALT_CLS_BankStatementService.LineView line : entryLines(
        card,
        scope,
        result
      )
    ) {
      result.plannedTotal += total(line, result);
      if (matches(line, query)) {
        lines.add(line);
      }
    }
    List<LineKey> keys = new List<LineKey>();
    for (ALT_CLS_BankStatementService.LineView line : lines) {
      keys.add(new LineKey(line));
    }
    keys.sort();
    for (LineKey key : keys) {
      result.lines.add(key.line);
    }
    return result;
  }

  /** The invoice of the reference month (the current one by default), bounded and validated. */
  private Scope scope(
    InvoiceQuery query,
    InvoiceView result,
    ALT_CLS_CardInvoiceCalendar calendar
  ) {
    Scope scope = new Scope();
    scope.calendar = calendar;
    Integer year = query.year == null ? today().year() : query.year;
    Integer month = query.month == null ? today().month() : query.month;
    check(
      year >= 1900 && year <= 9999 && month >= 1 && month <= 12,
      'INVALID_INPUT'
    );
    ALT_CLS_CardInvoiceCalendar.Invoice invoice = calendar.invoice(year, month);
    scope.year = year;
    scope.month = month;
    scope.blocked =
      invoice.outcome == ALT_CLS_CardInvoiceCalendar.OUTCOME_BLOCKED;
    scope.windowStart = invoice.windowStart;
    scope.windowEnd = invoice.windowEnd;
    Integer margin = scope.blocked || calendar.ruleCount() <= 1
      ? 0
      : CLASSIFY_MARGIN_DAYS;
    scope.readFrom = invoice.windowStart.addDays(-margin);
    scope.readTo = invoice.windowEnd.addDays(margin);
    result.year = year;
    result.month = month;
    result.outcome = invoice.outcome;
    result.blockedReason = invoice.reason;
    result.fromDate = invoice.windowStart;
    result.toDate = invoice.windowEnd;
    result.closingDate = invoice.closingDate;
    result.dueDate = invoice.dueDate;
    return scope;
  }

  /** Signed amount (a refund lowers the invoice) counted only in the card's currency. */
  private static Decimal total(
    ALT_CLS_BankStatementService.LineView line,
    InvoiceView result
  ) {
    if (line.amount == null) {
      return 0;
    }
    if (line.currencyIso != result.currencyIso) {
      result.mixedCurrency = true;
      return 0;
    }
    return line.direction == 'CREDIT' ? -line.amount : line.amount;
  }

  /** Date (inside the invoice), amount and description filters, all applied together. */
  private static Boolean matches(
    ALT_CLS_BankStatementService.LineView line,
    InvoiceQuery query
  ) {
    if (
      (query.fromDate != null &&
      (line.lineDate == null ||
      line.lineDate < query.fromDate)) ||
      (query.toDate != null &&
      (line.lineDate == null ||
      line.lineDate > query.toDate))
    ) {
      return false;
    }
    if (
      (query.minAmount != null || query.maxAmount != null) &&
      line.amount == null
    ) {
      return false;
    }
    if (query.minAmount != null && line.amount < query.minAmount) {
      return false;
    }
    if (query.maxAmount != null && line.amount > query.maxAmount) {
      return false;
    }
    if (String.isNotBlank(query.term)) {
      return line.description != null &&
        line.description.containsIgnoreCase(query.term.trim());
    }
    return true;
  }

  private List<ALT_CLS_BankStatementService.LineView> factLines(
    AXF_OBJ_CreditCard__c card,
    Scope scope,
    InvoiceView result
  ) {
    Id creditCardId = card.Id;
    Date readFrom = scope.readFrom;
    Date readTo = scope.readTo;
    Integer cap = MAX_FACTS + 1;
    List<AXF_OBJ_CreditCardTransaction__c> rows = [
      SELECT
        Id,
        AXF_CCT_NUM_Magnitude__c,
        AXF_CCT_TXT_CurrencyIsoCode__c,
        AXF_CCT_PKL_Direction__c,
        AXF_CCT_DAT_Date__c,
        AXF_CCT_TXT_Description__c,
        AXF_CCT_PKL_Source__c,
        AXF_CCT_NUM_Version__c
      FROM AXF_OBJ_CreditCardTransaction__c
      WHERE
        AXF_CCT_MDR_CreditCard__c = :creditCardId
        AND AXF_CCT_PKL_Status__c = 'POSTED'
        AND AXF_CCT_DAT_Date__c >= :readFrom
        AND AXF_CCT_DAT_Date__c <= :readTo
      WITH USER_MODE
      ORDER BY AXF_CCT_DAT_Date__c DESC, Id ASC
      LIMIT :cap
    ];
    if (rows.size() > MAX_FACTS) {
      result.truncated = true;
      rows.remove(rows.size() - 1);
    }
    List<AXF_OBJ_CreditCardTransaction__c> inScope = new List<AXF_OBJ_CreditCardTransaction__c>();
    for (AXF_OBJ_CreditCardTransaction__c row : rows) {
      if (scope.contains(row.AXF_CCT_DAT_Date__c)) {
        inScope.add(row);
      }
    }
    Set<Id> unverified = new Set<Id>();
    Map<Id, Decimal> nets = nets(
      true,
      new Map<Id, AXF_OBJ_CreditCardTransaction__c>(inScope).keySet(),
      unverified
    );
    List<ALT_CLS_BankStatementService.LineView> lines = new List<ALT_CLS_BankStatementService.LineView>();
    for (AXF_OBJ_CreditCardTransaction__c row : inScope) {
      ALT_CLS_BankStatementService.LineView line = new ALT_CLS_BankStatementService.LineView();
      line.lineKind = LINE_FACT;
      line.recordId = row.Id;
      line.lineDate = row.AXF_CCT_DAT_Date__c;
      line.description = row.AXF_CCT_TXT_Description__c;
      line.amount = row.AXF_CCT_NUM_Magnitude__c;
      line.direction = row.AXF_CCT_PKL_Direction__c;
      line.currencyIso = row.AXF_CCT_TXT_CurrencyIsoCode__c;
      line.origin = row.AXF_CCT_PKL_Source__c;
      line.version = row.AXF_CCT_NUM_Version__c == null
        ? 0
        : row.AXF_CCT_NUM_Version__c;
      applyStatus(line, nets, unverified);
      line.canSuggest = line.canSuggest && canReconcile();
      lines.add(line);
    }
    return lines;
  }

  /**
   * Manual entries (planned or actual-only) posted against this card whose net allocation is zero.
   * An allocated entry is shown only through the card fact that carries it (as in AXF-151).
   */
  private List<ALT_CLS_BankStatementService.LineView> entryLines(
    AXF_OBJ_CreditCard__c card,
    Scope scope,
    InvoiceView result
  ) {
    Id creditCardId = card.Id;
    Id holderId = card.AXF_CC_LKP_Account__c;
    Date readFrom = scope.readFrom;
    Date readTo = scope.readTo;
    Integer cap = MAX_ENTRIES + 1;
    List<AXF_OBJ_FinancialTransaction__c> rows = [
      SELECT
        Id,
        AXF_FTX_NUM_Magnitude__c,
        AXF_FTX_TXT_CurrencyIsoCode__c,
        AXF_FTX_PKL_Direction__c,
        AXF_FTX_DAT_DueDate__c,
        AXF_FTX_DAT_PurchaseDate__c,
        AXF_FTX_TXT_Description__c,
        AXF_FTX_PKL_PlanKind__c,
        AXF_FTX_NUM_Version__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE
        AXF_FTX_LKP_CreditCard__c = :creditCardId
        AND AXF_FTX_LKP_Account__c = :holderId
        AND AXF_FTX_PKL_PlanKind__c IN :PLAN_KINDS
        AND (AXF_FTX_PKL_ScheduleState__c = NULL
        OR AXF_FTX_PKL_ScheduleState__c != 'CANCELLED')
        AND ((AXF_FTX_DAT_PurchaseDate__c >= :readFrom
        AND AXF_FTX_DAT_PurchaseDate__c <= :readTo)
        OR (AXF_FTX_DAT_PurchaseDate__c = NULL
        AND AXF_FTX_DAT_DueDate__c >= :readFrom
        AND AXF_FTX_DAT_DueDate__c <= :readTo))
      WITH USER_MODE
      ORDER BY
        AXF_FTX_DAT_PurchaseDate__c DESC NULLS LAST,
        AXF_FTX_DAT_DueDate__c DESC,
        Id ASC
      LIMIT :cap
    ];
    if (rows.size() > MAX_ENTRIES) {
      result.truncated = true;
      rows.remove(rows.size() - 1);
    }
    List<AXF_OBJ_FinancialTransaction__c> inScope = new List<AXF_OBJ_FinancialTransaction__c>();
    for (AXF_OBJ_FinancialTransaction__c row : rows) {
      if (scope.contains(entryDate(row))) {
        inScope.add(row);
      }
    }
    Set<Id> unverified = new Set<Id>();
    Map<Id, Decimal> nets = nets(
      false,
      new Map<Id, AXF_OBJ_FinancialTransaction__c>(inScope).keySet(),
      unverified
    );
    List<ALT_CLS_BankStatementService.LineView> lines = new List<ALT_CLS_BankStatementService.LineView>();
    for (AXF_OBJ_FinancialTransaction__c row : inScope) {
      Decimal net = nets.containsKey(row.Id) ? nets.get(row.Id) : 0;
      if (unverified.contains(row.Id) || net != 0) {
        continue;
      }
      ALT_CLS_BankStatementService.LineView line = new ALT_CLS_BankStatementService.LineView();
      line.lineKind = LINE_ENTRY;
      line.recordId = row.Id;
      line.lineDate = entryDate(row);
      line.description = row.AXF_FTX_TXT_Description__c;
      line.amount = row.AXF_FTX_NUM_Magnitude__c;
      line.direction = row.AXF_FTX_PKL_Direction__c;
      line.currencyIso = row.AXF_FTX_TXT_CurrencyIsoCode__c;
      line.origin = row.AXF_FTX_PKL_PlanKind__c;
      line.version = row.AXF_FTX_NUM_Version__c == null
        ? 0
        : row.AXF_FTX_NUM_Version__c;
      line.allocated = 0;
      line.residual = line.amount;
      line.status = STATUS_UNRECONCILED;
      // Only a planned entry can be the target of a link (AXF-134).
      line.canSuggest =
        canReconcile() &&
        row.AXF_FTX_PKL_PlanKind__c == 'PLANNED' &&
        line.amount != null &&
        line.amount > 0;
      lines.add(line);
    }
    return lines;
  }

  /**
   * Net allocation (APPLICATION minus REVERSAL) per card fact or entry. With the link capability
   * the link contract's verified net is used; without it the net of the allocations the user can
   * see, and a truncated or refused read leaves the rows unverified instead of guessing.
   */
  private Map<Id, Decimal> nets(
    Boolean sourceSide,
    Set<Id> ids,
    Set<Id> unverified
  ) {
    if (ids.isEmpty()) {
      return new Map<Id, Decimal>();
    }
    if (canReconcile()) {
      ALT_CLS_SourceLinkService link = new ALT_CLS_SourceLinkService();
      return sourceSide
        ? link.netOfSources(ids, unverified)
        : link.netOfTargets(ids, unverified);
    }
    Map<Id, Decimal> result = new Map<Id, Decimal>();
    Integer cap = ALT_CLS_SourceLinkService.MAX_ALLOCATION_ROWS;
    List<AXF_OBJ_ReconciliationAllocation__c> rows;
    try {
      rows = sourceSide
        ? [
            SELECT
              AXF_RA_LKP_CardTransaction__c,
              AXF_RA_LKP_FinancialTransaction__c,
              AXF_RA_PKL_Kind__c,
              AXF_RA_NUM_Magnitude__c
            FROM AXF_OBJ_ReconciliationAllocation__c
            WHERE AXF_RA_LKP_CardTransaction__c IN :ids
            WITH USER_MODE
            LIMIT :cap
          ]
        : [
            SELECT
              AXF_RA_LKP_CardTransaction__c,
              AXF_RA_LKP_FinancialTransaction__c,
              AXF_RA_PKL_Kind__c,
              AXF_RA_NUM_Magnitude__c
            FROM AXF_OBJ_ReconciliationAllocation__c
            WHERE AXF_RA_LKP_FinancialTransaction__c IN :ids
            WITH USER_MODE
            LIMIT :cap
          ];
    } catch (Exception refused) {
      unverified.addAll(ids);
      return result;
    }
    if (rows.size() >= cap) {
      unverified.addAll(ids);
      return result;
    }
    for (AXF_OBJ_ReconciliationAllocation__c row : rows) {
      Id key = sourceSide
        ? row.AXF_RA_LKP_CardTransaction__c
        : row.AXF_RA_LKP_FinancialTransaction__c;
      Decimal sign = row.AXF_RA_PKL_Kind__c == 'REVERSAL' ? -1 : 1;
      result.put(
        key,
        (result.containsKey(key) ? result.get(key) : 0) +
        sign * row.AXF_RA_NUM_Magnitude__c
      );
    }
    return result;
  }

  private static void applyStatus(
    ALT_CLS_BankStatementService.LineView line,
    Map<Id, Decimal> nets,
    Set<Id> unverified
  ) {
    if (unverified.contains(line.recordId) || line.amount == null) {
      line.status = STATUS_UNVERIFIED;
      return;
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
    line.canSuggest = line.residual > 0;
  }

  private class LineKey implements Comparable {
    public ALT_CLS_BankStatementService.LineView line;
    public LineKey(ALT_CLS_BankStatementService.LineView line) {
      this.line = line;
    }
    public Integer compareTo(Object other) {
      ALT_CLS_BankStatementService.LineView b = ((LineKey) other).line;
      if (line.lineDate != b.lineDate) {
        if (line.lineDate == null) {
          return 1;
        }
        if (b.lineDate == null) {
          return -1;
        }
        return line.lineDate > b.lineDate ? -1 : 1;
      }
      if (line.lineKind != b.lineKind) {
        return line.lineKind == LINE_FACT ? -1 : 1;
      }
      return String.valueOf(line.recordId)
        .compareTo(String.valueOf(b.recordId));
    }
  }

  // ------------------------------------------------------------- suggestions

  /** @description Candidates of one line inside the AXF-MATCHING@1.1.0 window; never a score. */
  public ALT_CLS_BankStatementService.SuggestionPage suggest(
    SuggestionQuery query
  ) {
    requireAccess();
    check(
      query != null &&
        query.recordId != null &&
        (query.lineKind == LINE_FACT ||
        query.lineKind == LINE_ENTRY),
      'INVALID_INPUT'
    );
    AXF_OBJ_CreditCard__c card = readCard(query.creditCardId);
    ALT_CLS_BankStatementService.SuggestionPage page = new ALT_CLS_BankStatementService.SuggestionPage();
    List<ALT_CLS_BankStatementService.SuggestionView> items = query.lineKind ==
      LINE_FACT
      ? factSuggestions(card, query.recordId, page)
      : entrySuggestions(card, query.recordId, page);
    List<ALT_CLS_MatchingWindow.Ranked> ranked = new List<ALT_CLS_MatchingWindow.Ranked>();
    for (ALT_CLS_BankStatementService.SuggestionView item : items) {
      ranked.add(
        new ALT_CLS_MatchingWindow.Ranked(
          item.amountDelta,
          item.dayDelta,
          item.candidateId,
          item
        )
      );
    }
    // Ties stay explicit: the same distance on both axes never selects a winner.
    for (
      ALT_CLS_MatchingWindow.Ranked entry : ALT_CLS_MatchingWindow.order(ranked)
    ) {
      ALT_CLS_BankStatementService.SuggestionView item = (ALT_CLS_BankStatementService.SuggestionView) entry.item;
      item.tied = entry.tied;
      page.items.add(item);
    }
    return page;
  }

  /** The card fact of this card, read and evaluated by the link contract. */
  private ALT_CLS_SourceLinkService.SourceView readFact(
    AXF_OBJ_CreditCard__c card,
    Id factId
  ) {
    check(
      factId != null &&
        factId.getSObjectType() == AXF_OBJ_CreditCardTransaction__c.SObjectType,
      'INVALID_INPUT'
    );
    ALT_CLS_SourceLinkService.SourceView source;
    try {
      source = new ALT_CLS_SourceLinkService()
        .readSource(factId, ALT_CLS_SourceLinkService.KIND_CARD);
    } catch (ALT_CLS_SourceLinkService.SourceLinkException hidden) {
      throw new CardStatementException('NOT_ACCESSIBLE');
    }
    check(source.fundingId == card.Id, 'NOT_ACCESSIBLE');
    return source;
  }

  private List<ALT_CLS_BankStatementService.SuggestionView> factSuggestions(
    AXF_OBJ_CreditCard__c card,
    Id factId,
    ALT_CLS_BankStatementService.SuggestionPage page
  ) {
    ALT_CLS_SourceLinkService.SourceView source = readFact(card, factId);
    List<ALT_CLS_BankStatementService.SuggestionView> result = new List<ALT_CLS_BankStatementService.SuggestionView>();
    if (!source.eligible) {
      return result;
    }
    ALT_CLS_SourceLinkService service = new ALT_CLS_SourceLinkService();
    List<ALT_CLS_SourceLinkService.CandidateView> linkable = new List<ALT_CLS_SourceLinkService.CandidateView>();
    Boolean complete = false;
    for (Integer pageNo = 1; pageNo <= MAX_SUGGESTION_PAGES; pageNo++) {
      ALT_CLS_SourceLinkService.CandidateQuery request = new ALT_CLS_SourceLinkService.CandidateQuery();
      request.sourceId = source.sourceId;
      request.sourceKind = ALT_CLS_SourceLinkService.KIND_CARD;
      request.pageNumber = pageNo;
      request.pageSize = ALT_CLS_SourceLinkService.MAX_PAGE;
      ALT_CLS_SourceLinkService.CandidatePage candidates = service.listCandidates(
        request
      );
      page.truncated = page.truncated || candidates.scanTruncated;
      for (ALT_CLS_SourceLinkService.CandidateView c : candidates.items) {
        // A projection is never linkable; the presentation order may interleave it.
        if (
          c.persisted == true &&
          c.linkable == true &&
          c.currencyIso == source.currencyIso &&
          c.direction == source.direction
        ) {
          linkable.add(c);
        }
      }
      if (!candidates.hasMore) {
        complete = true;
        break;
      }
    }
    page.truncated = page.truncated || !complete;
    // A card purchase is placed by its purchase date (the due date is the invoice's).
    Map<Id, Date> dates = cardDates(linkable);
    for (ALT_CLS_SourceLinkService.CandidateView c : linkable) {
      Date onDate = dates.containsKey(c.targetId)
        ? dates.get(c.targetId)
        : c.dueDate;
      if (
        !ALT_CLS_MatchingWindow.inWindow(
          source.amount,
          source.factDate,
          c.amount,
          onDate
        )
      ) {
        continue;
      }
      ALT_CLS_BankStatementService.SuggestionView s = new ALT_CLS_BankStatementService.SuggestionView();
      s.sourceId = source.sourceId;
      s.sourceVersion = source.version;
      s.targetId = c.targetId;
      s.targetVersion = c.version;
      s.candidateId = c.targetId;
      s.candidateDate = onDate;
      s.candidateAmount = c.amount;
      s.description = c.description;
      s.currencyIso = c.currencyIso;
      s.amountDelta = (c.amount - source.amount).abs();
      s.dayDelta = Math.abs(source.factDate.daysBetween(onDate));
      s.allocationAmount = Math.min(source.residual, c.residual);
      result.add(s);
    }
    return result;
  }

  /** Card-entry date of each candidate, read once for the page (purchase date first). */
  private static Map<Id, Date> cardDates(
    List<ALT_CLS_SourceLinkService.CandidateView> candidates
  ) {
    Set<Id> ids = new Set<Id>();
    for (ALT_CLS_SourceLinkService.CandidateView c : candidates) {
      ids.add(c.targetId);
    }
    Map<Id, Date> result = new Map<Id, Date>();
    if (ids.isEmpty()) {
      return result;
    }
    for (AXF_OBJ_FinancialTransaction__c row : [
      SELECT Id, AXF_FTX_DAT_DueDate__c, AXF_FTX_DAT_PurchaseDate__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE Id IN :ids
      WITH USER_MODE
    ]) {
      result.put(row.Id, entryDate(row));
    }
    return result;
  }

  private AXF_OBJ_FinancialTransaction__c readEntry(
    AXF_OBJ_CreditCard__c card,
    Id entryId
  ) {
    check(
      entryId != null &&
        entryId.getSObjectType() == AXF_OBJ_FinancialTransaction__c.SObjectType,
      'INVALID_INPUT'
    );
    List<AXF_OBJ_FinancialTransaction__c> rows = [
      SELECT
        Id,
        AXF_FTX_LKP_Account__c,
        AXF_FTX_LKP_BankAccount__c,
        AXF_FTX_LKP_CreditCard__c,
        AXF_FTX_NUM_Magnitude__c,
        AXF_FTX_TXT_CurrencyIsoCode__c,
        AXF_FTX_PKL_Direction__c,
        AXF_FTX_DAT_DueDate__c,
        AXF_FTX_DAT_PurchaseDate__c,
        AXF_FTX_PKL_PlanKind__c,
        AXF_FTX_PKL_ScheduleState__c,
        AXF_FTX_NUM_Version__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE Id = :entryId
      WITH USER_MODE
      LIMIT 1
    ];
    check(
      rows.size() == 1 &&
        rows[0].AXF_FTX_LKP_Account__c == card.AXF_CC_LKP_Account__c,
      'NOT_ACCESSIBLE'
    );
    return rows[0];
  }

  /**
   * A card entry is dated by its purchase (which places it in an invoice); its due date is the
   * invoice's and only stands in when no purchase date exists.
   */
  private static Date entryDate(AXF_OBJ_FinancialTransaction__c row) {
    return row.AXF_FTX_DAT_PurchaseDate__c == null
      ? row.AXF_FTX_DAT_DueDate__c
      : row.AXF_FTX_DAT_PurchaseDate__c;
  }

  /** Available amount of a target entry, or null when its allocations cannot be verified. */
  private static Decimal entryResidual(AXF_OBJ_FinancialTransaction__c row) {
    Set<Id> unverified = new Set<Id>();
    Map<Id, Decimal> nets = new ALT_CLS_SourceLinkService()
      .netOfTargets(new Set<Id>{ row.Id }, unverified);
    if (unverified.contains(row.Id) || row.AXF_FTX_NUM_Magnitude__c == null) {
      return null;
    }
    return row.AXF_FTX_NUM_Magnitude__c -
      (nets.containsKey(row.Id) ? nets.get(row.Id) : 0);
  }

  private List<ALT_CLS_BankStatementService.SuggestionView> entrySuggestions(
    AXF_OBJ_CreditCard__c card,
    Id entryId,
    ALT_CLS_BankStatementService.SuggestionPage page
  ) {
    AXF_OBJ_FinancialTransaction__c entry = readEntry(card, entryId);
    check(entry.AXF_FTX_LKP_CreditCard__c == card.Id, 'NOT_ACCESSIBLE');
    List<ALT_CLS_BankStatementService.SuggestionView> result = new List<ALT_CLS_BankStatementService.SuggestionView>();
    Date onDate = entryDate(entry);
    Decimal available = entryResidual(entry);
    if (
      entry.AXF_FTX_PKL_PlanKind__c != 'PLANNED' ||
      entry.AXF_FTX_PKL_ScheduleState__c == 'CANCELLED' ||
      entry.AXF_FTX_LKP_BankAccount__c != null ||
      onDate == null ||
      available == null ||
      available <= 0
    ) {
      return result;
    }
    // Facts of THIS card inside the 7-day window only, bounded; never the holder's feed.
    Decimal base = entry.AXF_FTX_NUM_Magnitude__c;
    Date fromDate = onDate.addDays(-DAY_WINDOW);
    Date toDate = onDate.addDays(DAY_WINDOW);
    Decimal minAmount = ALT_CLS_MatchingWindow.minAmount(base);
    Decimal maxAmount = ALT_CLS_MatchingWindow.maxAmount(base);
    String iso = entry.AXF_FTX_TXT_CurrencyIsoCode__c;
    String direction = entry.AXF_FTX_PKL_Direction__c;
    Id creditCardId = card.Id;
    Integer cap = MAX_FACTS + 1;
    List<AXF_OBJ_CreditCardTransaction__c> rows = [
      SELECT
        Id,
        AXF_CCT_NUM_Magnitude__c,
        AXF_CCT_TXT_CurrencyIsoCode__c,
        AXF_CCT_PKL_Direction__c,
        AXF_CCT_DAT_Date__c,
        AXF_CCT_TXT_Description__c,
        AXF_CCT_NUM_Version__c
      FROM AXF_OBJ_CreditCardTransaction__c
      WHERE
        AXF_CCT_MDR_CreditCard__c = :creditCardId
        AND AXF_CCT_PKL_Status__c = 'POSTED'
        AND AXF_CCT_TXT_CurrencyIsoCode__c = :iso
        AND AXF_CCT_PKL_Direction__c = :direction
        AND AXF_CCT_DAT_Date__c >= :fromDate
        AND AXF_CCT_DAT_Date__c <= :toDate
        AND AXF_CCT_NUM_Magnitude__c >= :minAmount
        AND AXF_CCT_NUM_Magnitude__c <= :maxAmount
      WITH USER_MODE
      ORDER BY AXF_CCT_DAT_Date__c DESC, Id ASC
      LIMIT :cap
    ];
    if (rows.size() > MAX_FACTS) {
      page.truncated = true;
      rows.remove(rows.size() - 1);
    }
    Set<Id> unverified = new Set<Id>();
    Map<Id, Decimal> nets = new ALT_CLS_SourceLinkService()
      .netOfSources(
        new Map<Id, AXF_OBJ_CreditCardTransaction__c>(rows).keySet(),
        unverified
      );
    for (AXF_OBJ_CreditCardTransaction__c row : rows) {
      Decimal residual =
        row.AXF_CCT_NUM_Magnitude__c -
        (nets.containsKey(row.Id) ? nets.get(row.Id) : 0);
      // Only a fact that is verified and not exhausted can be linked by one click.
      if (
        unverified.contains(row.Id) ||
        residual <= 0 ||
        !ALT_CLS_MatchingWindow.inWindow(
          base,
          onDate,
          row.AXF_CCT_NUM_Magnitude__c,
          row.AXF_CCT_DAT_Date__c
        )
      ) {
        continue;
      }
      ALT_CLS_BankStatementService.SuggestionView s = new ALT_CLS_BankStatementService.SuggestionView();
      s.sourceId = row.Id;
      s.sourceVersion = row.AXF_CCT_NUM_Version__c == null
        ? 0
        : row.AXF_CCT_NUM_Version__c;
      s.targetId = entry.Id;
      s.targetVersion = entry.AXF_FTX_NUM_Version__c == null
        ? 0
        : entry.AXF_FTX_NUM_Version__c;
      s.candidateId = row.Id;
      s.candidateDate = row.AXF_CCT_DAT_Date__c;
      s.candidateAmount = row.AXF_CCT_NUM_Magnitude__c;
      s.description = row.AXF_CCT_TXT_Description__c;
      s.currencyIso = row.AXF_CCT_TXT_CurrencyIsoCode__c;
      s.amountDelta = (row.AXF_CCT_NUM_Magnitude__c - base).abs();
      s.dayDelta = Math.abs(onDate.daysBetween(row.AXF_CCT_DAT_Date__c));
      s.allocationAmount = Math.min(residual, available);
      result.add(s);
    }
    return result;
  }

  // ----------------------------------------------------------------- confirm

  /**
   * @description One-click confirmation of a displayed suggestion: an explicit human command. The
   * pair is re-checked against the window, then linked through the AXF-134 contract with
   * min(source residual, target available), the displayed versions and a fresh operation key.
   */
  public ALT_CLS_BankStatementService.ConfirmResult confirm(
    ConfirmInput input
  ) {
    requireAccess();
    check(
      input != null &&
        input.sourceId != null &&
        input.targetId != null &&
        input.sourceVersion != null &&
        input.targetVersion != null &&
        String.isNotBlank(input.operationKey) &&
        input.operationKey.length() <= 80,
      'INVALID_INPUT'
    );
    AXF_OBJ_CreditCard__c card = readCard(input.creditCardId);
    ALT_CLS_SourceLinkService.SourceView source = readFact(
      card,
      input.sourceId
    );
    AXF_OBJ_FinancialTransaction__c target = readEntry(card, input.targetId);
    Date targetDate = entryDate(target);
    // Either side may have been the line the suggestion was built for.
    check(
      target.AXF_FTX_TXT_CurrencyIsoCode__c == source.currencyIso &&
        target.AXF_FTX_PKL_Direction__c == source.direction &&
        (ALT_CLS_MatchingWindow.inWindow(
          source.amount,
          source.factDate,
          target.AXF_FTX_NUM_Magnitude__c,
          targetDate
        ) ||
        ALT_CLS_MatchingWindow.inWindow(
          target.AXF_FTX_NUM_Magnitude__c,
          targetDate,
          source.amount,
          source.factDate
        )),
      'OUT_OF_WINDOW'
    );
    Decimal available = entryResidual(target);
    check(available != null, 'ALLOCATIONS_UNVERIFIED');
    check(available > 0, 'TARGET_REALIZED');
    if (!source.eligible) {
      throw new CardStatementException(source.reasons[0]);
    }
    ALT_CLS_SourceLinkService.ConfirmInput request = new ALT_CLS_SourceLinkService.ConfirmInput();
    request.sourceId = source.sourceId;
    request.sourceKind = ALT_CLS_SourceLinkService.KIND_CARD;
    request.sourceVersion = input.sourceVersion;
    request.targetId = target.Id;
    request.targetVersion = input.targetVersion;
    request.amount = Math.min(source.residual, available);
    request.recognitionDate = source.factDate;
    request.changesReviewed = false;
    request.economicRole = ALT_CLS_SourceLinkService.ROLE_APPLICATION;
    request.operationKey = input.operationKey;
    ALT_CLS_SourceLinkService.ConfirmResult linked;
    try {
      linked = new ALT_CLS_SourceLinkService().confirm(request);
    } catch (ALT_CLS_SourceLinkService.SourceLinkException failure) {
      throw new CardStatementException(failure.getMessage());
    }
    ALT_CLS_BankStatementService.ConfirmResult result = new ALT_CLS_BankStatementService.ConfirmResult();
    result.allocationId = linked.allocationId;
    result.replayed = linked.replayed;
    result.amount = linked.amount;
    result.currencyIso = linked.currencyIso;
    return result;
  }
}
