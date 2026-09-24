/**
 * @description AXF-152: invoice calendar of a credit card (Fechamento G1 — calendário de cartão,
 * 07/09/2026), derived from the effective-dated AXF-35 rules (AXF_OBJ_CardBillingCycleRule__c).
 *
 * For a reference month M the closing date C(M) is the rule's closing day capped at the last day
 * of M and adjusted by the closing-day adjustment: NONE keeps it; FOLLOWING moves to the next
 * business day without leaving the month, otherwise to the previous one; PRECEDING moves to the
 * previous business day. The due date is C(M) plus the due-day offset in calendar days, adjusted
 * the same way by the due-day adjustment. Business days follow the calendar policy CAL-1.0.0:
 * weekends are never business days and the org's default business hours (with its holidays)
 * decide the rest. Invoice M holds the purchases dated in (C(M-1), C(M)], each purchase being
 * classified by the rule in force on its own date. Without a rule nothing is invented: the
 * invoice is BLOCKED and falls back to the civil month.
 */
public with sharing class ALT_CLS_CardInvoiceCalendar {
  public static final String CALENDAR_POLICY = 'CAL-1.0.0';
  public static final String OUTCOME_RESOLVED = 'RESOLVED';
  public static final String OUTCOME_BLOCKED = 'BLOCKED';
  public static final String REASON_NO_RULE = 'NO_RULE';
  public static final String ADJUST_NONE = 'NONE';
  public static final String ADJUST_FOLLOWING = 'FOLLOWING';
  public static final String ADJUST_PRECEDING = 'PRECEDING';
  public static final Integer MAX_RULES = 2000;
  /** A business-day search never moves further than a month. */
  private static final Integer MAX_SHIFT = 31;
  /** A known Sunday: the weekday of any date is its distance to it, modulo 7. */
  private static final Date SUNDAY = Date.newInstance(1900, 1, 7);

  /** Business-day source; the org calendar in production, a fixed one in tests. */
  public interface BusinessDays {
    Boolean isBusinessDay(Date onDate);
  }

  /** CAL-1.0.0: weekends are closed; the org's default business hours decide every other day. */
  public class OrgBusinessDays implements BusinessDays {
    private Boolean loaded = false;
    private Id hoursId;
    private String zone;
    private Map<Date, Boolean> cache = new Map<Date, Boolean>();

    public Boolean isBusinessDay(Date onDate) {
      if (isWeekend(onDate)) {
        return false;
      }
      if (!cache.containsKey(onDate)) {
        Id hours = defaultHours();
        Boolean open = true;
        if (hours != null) {
          // A day is open when the business hours start somewhere inside it (holidays included).
          // The probe is the midnight of that day in the business hours' own time zone, and the
          // answer is read back as a local date of that zone, never of the running user.
          Datetime next = BusinessHours.nextStartDate(
            hours,
            midnightIn(onDate, zone)
          );
          open =
            next != null &&
            Date.valueOf(next.format('yyyy-MM-dd', zone)) == onDate;
        }
        cache.put(onDate, open);
      }
      return cache.get(onDate);
    }

    private Id defaultHours() {
      if (!loaded) {
        loaded = true;
        // Shared org reference data (like the exchange-rate layer): read under sharing only.
        List<BusinessHours> rows = [
          SELECT Id, TimeZoneSidKey
          FROM BusinessHours
          WHERE IsDefault = TRUE AND IsActive = TRUE
          LIMIT 1
        ];
        hoursId = rows.isEmpty() ? null : rows[0].Id;
        zone = rows.isEmpty() ? null : rows[0].TimeZoneSidKey;
        if (String.isBlank(zone)) {
          zone = UserInfo.getTimeZone().getID();
        }
      }
      return hoursId;
    }
  }

  /** @description The instant of 00:00 of a calendar date in the given time zone. */
  public static Datetime midnightIn(Date onDate, String zone) {
    Datetime utcMidnight = Datetime.newInstanceGmt(
      onDate,
      Time.newInstance(0, 0, 0, 0)
    );
    Integer offset = TimeZone.getTimeZone(zone).getOffset(utcMidnight);
    return utcMidnight.addSeconds(-offset / 1000);
  }

  public static Boolean isWeekend(Date onDate) {
    Integer weekday = Math.mod(SUNDAY.daysBetween(onDate), 7);
    if (weekday < 0) {
      weekday += 7;
    }
    return weekday == 0 || weekday == 6;
  }

  /** One ACTIVE rule, reduced to the parameters the calendar needs. */
  public class Rule {
    public Id ruleId;
    public Date effectiveFrom;
    public Date effectiveTo;
    public Integer closingDay;
    public String closingAdjustment;
    public Integer dueDayOffset;
    public String dueAdjustment;
    public String calendarPolicyVersion;

    /** Half-open validity [from, to), as the AXF-35 service derives it. */
    public Boolean covers(Date onDate) {
      return onDate != null &&
        effectiveFrom != null &&
        onDate >= effectiveFrom &&
        (effectiveTo == null ||
        onDate < effectiveTo);
    }
  }

  /** The invoice of one reference month: its window, closing and due dates, or BLOCKED. */
  public class Invoice {
    public Integer year;
    public Integer month;
    public String outcome;
    public String reason;
    public Id ruleId;
    /** First and last day (inclusive) of the purchases the invoice holds. */
    public Date windowStart;
    public Date windowEnd;
    public Date closingDate;
    public Date dueDate;
  }

  private final List<Rule> rules = new List<Rule>();
  private final BusinessDays days;
  private final Map<String, Date> closings = new Map<String, Date>();

  /** @description Calendar over the ACTIVE rules given (any other state is ignored). */
  public ALT_CLS_CardInvoiceCalendar(
    List<AXF_OBJ_CardBillingCycleRule__c> rows,
    BusinessDays days
  ) {
    this.days = days == null ? new OrgBusinessDays() : days;
    // Newest validity first: the first rule covering a date is the one in force on it.
    List<AXF_OBJ_CardBillingCycleRule__c> given = rows == null
      ? new List<AXF_OBJ_CardBillingCycleRule__c>()
      : rows;
    for (AXF_OBJ_CardBillingCycleRule__c row : given) {
      if (
        row.AXF_CBR_PKL_State__c !=
        ALT_CLS_CardBillingCycleService.STATE_ACTIVE ||
        row.AXF_CBR_DAT_EffectiveFrom__c == null ||
        row.AXF_CBR_NUM_ClosingDay__c == null
      ) {
        continue;
      }
      Rule rule = new Rule();
      rule.ruleId = row.Id;
      rule.effectiveFrom = row.AXF_CBR_DAT_EffectiveFrom__c;
      rule.effectiveTo = row.AXF_CBR_DAT_EffectiveTo__c;
      rule.closingDay = row.AXF_CBR_NUM_ClosingDay__c.intValue();
      rule.closingAdjustment = row.AXF_CBR_PKL_ClosingDayAdjustment__c;
      rule.dueDayOffset = row.AXF_CBR_NUM_DueDayOffset__c == null
        ? 0
        : row.AXF_CBR_NUM_DueDayOffset__c.intValue();
      rule.dueAdjustment = row.AXF_CBR_PKL_DueDayAdjustment__c;
      rule.calendarPolicyVersion = row.AXF_CBR_TXT_CalendarPolicyVersion__c;
      insertByValidity(rule);
    }
  }

  private void insertByValidity(Rule rule) {
    Integer at = 0;
    while (at < rules.size() && rules[at].effectiveFrom >= rule.effectiveFrom) {
      at++;
    }
    if (at == rules.size()) {
      rules.add(rule);
    } else {
      rules.add(at, rule);
    }
  }

  /**
   * @description ACTIVE rules of each card, read once for all of them; the caller has already
   * resolved the cards through the authorized context.
   */
  public static Map<Id, ALT_CLS_CardInvoiceCalendar> forCards(
    Set<Id> creditCardIds,
    BusinessDays days
  ) {
    BusinessDays shared = days == null ? new OrgBusinessDays() : days;
    Map<Id, List<AXF_OBJ_CardBillingCycleRule__c>> byCard = new Map<Id, List<AXF_OBJ_CardBillingCycleRule__c>>();
    for (Id cardId : creditCardIds) {
      byCard.put(cardId, new List<AXF_OBJ_CardBillingCycleRule__c>());
    }
    if (!creditCardIds.isEmpty()) {
      String soql =
        'SELECT Id, AXF_CBR_LKP_CreditCard__c, AXF_CBR_PKL_State__c, AXF_CBR_DAT_EffectiveFrom__c,' +
        ' AXF_CBR_DAT_EffectiveTo__c, AXF_CBR_NUM_ClosingDay__c, AXF_CBR_PKL_ClosingDayAdjustment__c,' +
        ' AXF_CBR_NUM_DueDayOffset__c, AXF_CBR_PKL_DueDayAdjustment__c, AXF_CBR_TXT_CalendarPolicyVersion__c' +
        ' FROM AXF_OBJ_CardBillingCycleRule__c' +
        ' WHERE AXF_CBR_LKP_CreditCard__c IN :cardIds AND AXF_CBR_PKL_State__c = :state' +
        ' ORDER BY AXF_CBR_DAT_EffectiveFrom__c ASC, Id ASC LIMIT :cap';
      for (
        SObject found : Database.queryWithBinds(
          soql,
          new Map<String, Object>{
            'cardIds' => new Set<Id>(creditCardIds),
            'state' => ALT_CLS_CardBillingCycleService.STATE_ACTIVE,
            'cap' => MAX_RULES
          },
          AccessLevel.USER_MODE
        )
      ) {
        AXF_OBJ_CardBillingCycleRule__c row = (AXF_OBJ_CardBillingCycleRule__c) found;
        byCard.get(row.AXF_CBR_LKP_CreditCard__c).add(row);
      }
    }
    Map<Id, ALT_CLS_CardInvoiceCalendar> result = new Map<Id, ALT_CLS_CardInvoiceCalendar>();
    for (Id cardId : byCard.keySet()) {
      result.put(
        cardId,
        new ALT_CLS_CardInvoiceCalendar(byCard.get(cardId), shared)
      );
    }
    return result;
  }

  // ------------------------------------------------------------------- rules

  /**
   * @description The rule in force on a date — the newest validity covering it, as the AXF-35
   * derivation — or null when there is none or it carries no calendar policy (BLOCKED).
   */
  public Rule ruleOn(Date onDate) {
    for (Rule rule : rules) {
      if (rule.covers(onDate)) {
        return String.isBlank(rule.calendarPolicyVersion) ? null : rule;
      }
    }
    return null;
  }

  public Boolean hasRules() {
    return !rules.isEmpty();
  }

  public Integer ruleCount() {
    return rules.size();
  }

  /** @description Latest end of a closed validity, or null when none has ended. */
  public Date latestEnd() {
    Date result;
    for (Rule rule : rules) {
      if (
        rule.effectiveTo != null &&
        (result == null ||
        rule.effectiveTo > result)
      ) {
        result = rule.effectiveTo;
      }
    }
    return result;
  }

  /** @description True when an ACTIVE validity reaches [onDate, ∞). */
  public Boolean overlapsFrom(Date onDate) {
    for (Rule rule : rules) {
      if (rule.effectiveTo == null || rule.effectiveTo > onDate) {
        return true;
      }
    }
    return false;
  }

  /** The rule of month M: the one in force on its own (unadjusted) closing day of M. */
  private Rule ruleForMonth(Integer year, Integer month) {
    Integer last = Date.daysInMonth(year, month);
    for (Rule rule : rules) {
      Date nominal = Date.newInstance(
        year,
        month,
        Math.min(rule.closingDay, last)
      );
      if (rule.covers(nominal)) {
        return String.isBlank(rule.calendarPolicyVersion) ? null : rule;
      }
    }
    return null;
  }

  // ------------------------------------------------------------------- dates

  /** @description C(M) under one rule: closing day capped at the month end, then adjusted. */
  public Date closingDate(Rule rule, Integer year, Integer month) {
    String key =
      rule.ruleId +
      '|' +
      rule.closingDay +
      '|' +
      rule.closingAdjustment +
      '|' +
      year +
      '|' +
      month;
    if (!closings.containsKey(key)) {
      Date nominal = Date.newInstance(
        year,
        month,
        Math.min(rule.closingDay, Date.daysInMonth(year, month))
      );
      closings.put(key, adjust(nominal, rule.closingAdjustment));
    }
    return closings.get(key);
  }

  /** @description Due date: closing date plus the offset in calendar days, then adjusted. */
  public Date dueDate(Rule rule, Date closing) {
    return adjust(
      closing.addDays(rule.dueDayOffset == null ? 0 : rule.dueDayOffset),
      rule.dueAdjustment
    );
  }

  /** @description Business-day adjustment of CAL-1.0.0 (FOLLOWING never leaves the month). */
  public Date adjust(Date nominal, String adjustment) {
    if (adjustment == ADJUST_FOLLOWING) {
      Date candidate = nominal;
      for (
        Integer i = 0;
        i <= MAX_SHIFT &&
        candidate.month() == nominal.month();
        i++
      ) {
        if (days.isBusinessDay(candidate)) {
          return candidate;
        }
        candidate = candidate.addDays(1);
      }
      return preceding(nominal);
    }
    if (adjustment == ADJUST_PRECEDING) {
      return preceding(nominal);
    }
    return nominal;
  }

  private Date preceding(Date nominal) {
    Date candidate = nominal;
    for (Integer i = 0; i <= MAX_SHIFT; i++) {
      if (days.isBusinessDay(candidate)) {
        return candidate;
      }
      candidate = candidate.addDays(-1);
    }
    return nominal;
  }

  // ---------------------------------------------------------------- invoices

  /** @description Invoice of reference month M, or BLOCKED on the civil month without a rule. */
  public Invoice invoice(Integer year, Integer month) {
    Invoice result = new Invoice();
    result.year = year;
    result.month = month;
    Rule rule = ruleForMonth(year, month);
    if (rule == null) {
      result.outcome = OUTCOME_BLOCKED;
      result.reason = REASON_NO_RULE;
      result.windowStart = Date.newInstance(year, month, 1);
      result.windowEnd = result.windowStart.addMonths(1).addDays(-1);
      return result;
    }
    Date previousMonth = Date.newInstance(year, month, 1).addMonths(-1);
    Rule previousRule = ruleForMonth(
      previousMonth.year(),
      previousMonth.month()
    );
    Date previousClosing = closingDate(
      previousRule == null ? rule : previousRule,
      previousMonth.year(),
      previousMonth.month()
    );
    Date windowStart = previousClosing.addDays(1);
    if (previousRule == null && rule.effectiveFrom > windowStart) {
      // No rule before this one: a date before its validity has no invoice and stays in the
      // (BLOCKED) civil month, so every date belongs to exactly one scope.
      windowStart = rule.effectiveFrom;
    }
    result.outcome = OUTCOME_RESOLVED;
    result.ruleId = rule.ruleId;
    result.closingDate = closingDate(rule, year, month);
    result.dueDate = dueDate(rule, result.closingDate);
    result.windowStart = windowStart;
    result.windowEnd = result.closingDate;
    return result;
  }

  /**
   * @description First day of the reference month whose invoice holds a purchase on this date,
   * classified by the rule in force on the date itself; null when no rule covers the date.
   */
  public Date invoiceMonthOf(Date onDate) {
    Rule rule = ruleOn(onDate);
    if (rule == null) {
      return null;
    }
    Date base = onDate.toStartOfMonth();
    for (Integer shift = -1; shift <= 2; shift++) {
      Date month = base.addMonths(shift);
      Date before = month.addMonths(-1);
      if (
        onDate > closingDate(rule, before.year(), before.month()) &&
        onDate <= closingDate(rule, month.year(), month.month())
      ) {
        return month;
      }
    }
    return null;
  }

  /**
   * @description Due-day offset (calendar days) from the closing day to the due day, independent
   * of the month it is saved in. Convention: a due day after the closing day falls in the same
   * month (due - closing); otherwise in the next one, counted over a conventional 30-day month
   * (due + 30 - closing). The derived due date is then the real closing date plus this offset.
   */
  public static Integer dueOffset(Integer closingDay, Integer dueDay) {
    return dueDay > closingDay ? dueDay - closingDay : dueDay + 30 - closingDay;
  }

  /**
   * @description The invoice whose purchases include this date (the "current" invoice on
   * today), or null when no rule covers it.
   */
  public Invoice invoiceOn(Date onDate) {
    Date month = invoiceMonthOf(onDate);
    return month == null ? null : invoice(month.year(), month.month());
  }
}
