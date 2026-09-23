/**
 * @description AXF-152: card invoice calendar (Fechamento G1 — calendário de cartão). Closing day
 * capped at the month end, business-day adjustments of CAL-1.0.0, due date, invoice window,
 * per-purchase classification by the rule of its own date and the BLOCKED fallback.
 */
@IsTest
// API 62: AXON_DEV enforces FLS on plain test DML under runAs from API 67 onwards.
private class ALT_CLS_CardInvoiceCalendarTest {
  /** Weekdays are business days except the given holidays. */
  private class FixedDays implements ALT_CLS_CardInvoiceCalendar.BusinessDays {
    Set<Date> holidays = new Set<Date>();
    public Boolean isBusinessDay(Date onDate) {
      return !ALT_CLS_CardInvoiceCalendar.isWeekend(onDate) &&
        !holidays.contains(onDate);
    }
  }

  private static AXF_OBJ_CardBillingCycleRule__c rule(
    Date effectiveFrom,
    Date effectiveTo,
    Integer closingDay,
    String adjustment,
    Integer dueOffset
  ) {
    return new AXF_OBJ_CardBillingCycleRule__c(
      AXF_CBR_PKL_State__c = 'ACTIVE',
      AXF_CBR_DAT_EffectiveFrom__c = effectiveFrom,
      AXF_CBR_DAT_EffectiveTo__c = effectiveTo,
      AXF_CBR_NUM_ClosingDay__c = closingDay,
      AXF_CBR_PKL_ClosingDayAdjustment__c = adjustment,
      AXF_CBR_NUM_DueDayOffset__c = dueOffset,
      AXF_CBR_PKL_DueDayAdjustment__c = adjustment,
      AXF_CBR_TXT_CalendarPolicyVersion__c = 'CAL-1.0.0',
      AXF_CBR_TXT_TimeZone__c = 'America/Sao_Paulo'
    );
  }

  private static ALT_CLS_CardInvoiceCalendar calendar(
    List<AXF_OBJ_CardBillingCycleRule__c> rules,
    FixedDays days
  ) {
    return new ALT_CLS_CardInvoiceCalendar(rules, days);
  }

  private static Date d(Integer y, Integer m, Integer dd) {
    return Date.newInstance(y, m, dd);
  }

  @IsTest
  static void closingDayIsCappedAtTheMonthEnd() {
    ALT_CLS_CardInvoiceCalendar none = calendar(
      new List<AXF_OBJ_CardBillingCycleRule__c>{
        rule(d(2026, 1, 1), null, 31, 'NONE', 7)
      },
      new FixedDays()
    );
    ALT_CLS_CardInvoiceCalendar.Invoice feb = none.invoice(2027, 2);
    Assert.areEqual('RESOLVED', feb.outcome);
    Assert.areEqual(d(2027, 2, 28), feb.closingDate, 'capped at 28/02');
    Assert.areEqual(d(2027, 2, 1), feb.windowStart, 'after 31/01');
    // 28/02/2027 is a Sunday: FOLLOWING would leave the month, so the previous business day.
    ALT_CLS_CardInvoiceCalendar following = calendar(
      new List<AXF_OBJ_CardBillingCycleRule__c>{
        rule(d(2026, 1, 1), null, 31, 'FOLLOWING', 7)
      },
      new FixedDays()
    );
    Assert.areEqual(d(2027, 2, 26), following.invoice(2027, 2).closingDate);
  }

  @IsTest
  static void followingStaysInTheMonthAndSkipsHolidays() {
    FixedDays days = new FixedDays();
    days.holidays.add(d(2026, 9, 7));
    ALT_CLS_CardInvoiceCalendar cal = calendar(
      new List<AXF_OBJ_CardBillingCycleRule__c>{
        rule(d(2026, 1, 1), null, 5, 'FOLLOWING', 7)
      },
      days
    );
    // 05/09/2026 is a Saturday and 07/09 a holiday: next business day is 08/09.
    Assert.areEqual(d(2026, 9, 8), cal.invoice(2026, 9).closingDate);
    // 31/10/2026 is a Saturday: FOLLOWING would reach November, so Friday 30/10.
    Assert.areEqual(d(2026, 10, 30), cal.adjust(d(2026, 10, 31), 'FOLLOWING'));
    Assert.areEqual(d(2026, 9, 4), cal.adjust(d(2026, 9, 5), 'PRECEDING'));
    Assert.areEqual(d(2026, 9, 5), cal.adjust(d(2026, 9, 5), 'NONE'));
  }

  @IsTest
  static void windowRunsFromThePreviousClosingToThisOne() {
    ALT_CLS_CardInvoiceCalendar cal = calendar(
      new List<AXF_OBJ_CardBillingCycleRule__c>{
        rule(d(2026, 1, 1), null, 5, 'NONE', 7)
      },
      new FixedDays()
    );
    ALT_CLS_CardInvoiceCalendar.Invoice sep = cal.invoice(2026, 9);
    Assert.areEqual(d(2026, 8, 6), sep.windowStart, 'C(ago)=05/08');
    Assert.areEqual(d(2026, 9, 5), sep.windowEnd, 'C(set)=05/09');
    Assert.areEqual(d(2026, 9, 12), sep.dueDate, 'closing + 7 days');
    Assert.areEqual(d(2026, 9, 1), cal.invoiceMonthOf(d(2026, 8, 6)));
    Assert.areEqual(d(2026, 9, 1), cal.invoiceMonthOf(d(2026, 9, 5)));
    Assert.areEqual(d(2026, 8, 1), cal.invoiceMonthOf(d(2026, 8, 5)));
    Assert.areEqual(d(2026, 10, 1), cal.invoiceMonthOf(d(2026, 9, 6)));
  }

  @IsTest
  static void dueDateIsAdjustedToABusinessDay() {
    ALT_CLS_CardInvoiceCalendar cal = calendar(
      new List<AXF_OBJ_CardBillingCycleRule__c>{
        rule(d(2026, 1, 1), null, 4, 'FOLLOWING', 8)
      },
      new FixedDays()
    );
    // Closing Friday 04/09/2026 + 8 = Saturday 12/09 → Monday 14/09.
    ALT_CLS_CardInvoiceCalendar.Invoice sep = cal.invoice(2026, 9);
    Assert.areEqual(d(2026, 9, 4), sep.closingDate);
    Assert.areEqual(d(2026, 9, 14), sep.dueDate);
  }

  @IsTest
  static void eachPurchaseFollowsTheRuleOfItsOwnDate() {
    ALT_CLS_CardInvoiceCalendar cal = calendar(
      new List<AXF_OBJ_CardBillingCycleRule__c>{
        rule(d(2026, 1, 1), d(2026, 8, 20), 5, 'NONE', 7),
        rule(d(2026, 8, 20), null, 20, 'NONE', 10)
      },
      new FixedDays()
    );
    Assert.areEqual(2, cal.ruleCount());
    // 10/08 under the old rule (closing 5) belongs to September.
    Assert.areEqual(d(2026, 9, 1), cal.invoiceMonthOf(d(2026, 8, 10)));
    // 25/08 under the new rule (closing 20) also belongs to September.
    Assert.areEqual(d(2026, 9, 1), cal.invoiceMonthOf(d(2026, 8, 25)));
    // 03/08 under the old rule belongs to August.
    Assert.areEqual(d(2026, 8, 1), cal.invoiceMonthOf(d(2026, 8, 3)));
    ALT_CLS_CardInvoiceCalendar.Invoice sep = cal.invoice(2026, 9);
    Assert.areEqual(d(2026, 9, 20), sep.closingDate);
    Assert.areEqual(d(2026, 8, 20), cal.latestEnd());
    Assert.isTrue(cal.overlapsFrom(d(2026, 9, 1)));
  }

  @IsTest
  static void withoutARuleTheInvoiceIsBlockedOnTheCivilMonth() {
    ALT_CLS_CardInvoiceCalendar empty = calendar(
      new List<AXF_OBJ_CardBillingCycleRule__c>(),
      new FixedDays()
    );
    ALT_CLS_CardInvoiceCalendar.Invoice sep = empty.invoice(2026, 9);
    Assert.areEqual('BLOCKED', sep.outcome);
    Assert.areEqual('NO_RULE', sep.reason);
    Assert.areEqual(d(2026, 9, 1), sep.windowStart);
    Assert.areEqual(d(2026, 9, 30), sep.windowEnd);
    Assert.isNull(sep.closingDate, 'no cut-off date is invented');
    Assert.isNull(sep.dueDate);
    Assert.isNull(empty.invoiceMonthOf(d(2026, 9, 10)));
    Assert.isFalse(empty.hasRules());
    Assert.isNull(empty.latestEnd());
    Assert.isFalse(empty.overlapsFrom(d(2026, 9, 1)));

    AXF_OBJ_CardBillingCycleRule__c unversioned = rule(
      d(2026, 1, 1),
      null,
      5,
      'NONE',
      7
    );
    unversioned.AXF_CBR_TXT_CalendarPolicyVersion__c = null;
    AXF_OBJ_CardBillingCycleRule__c draft = rule(
      d(2025, 1, 1),
      null,
      5,
      'NONE',
      7
    );
    draft.AXF_CBR_PKL_State__c = 'DRAFT';
    ALT_CLS_CardInvoiceCalendar blocked = calendar(
      new List<AXF_OBJ_CardBillingCycleRule__c>{ unversioned, draft },
      new FixedDays()
    );
    Assert.areEqual(1, blocked.ruleCount(), 'a draft never applies');
    Assert.areEqual('BLOCKED', blocked.invoice(2026, 9).outcome);
    Assert.isNull(blocked.ruleOn(d(2026, 9, 10)), 'no calendar policy');
    Assert.areEqual('BLOCKED', blocked.invoice(2025, 6).outcome);
  }

  @IsTest
  static void dueOffsetDoesNotDependOnTheMonthItIsSavedIn() {
    Assert.areEqual(7, ALT_CLS_CardInvoiceCalendar.dueOffset(5, 12));
    Assert.areEqual(1, ALT_CLS_CardInvoiceCalendar.dueOffset(29, 30));
    // Due day not after the closing: next month over a conventional 30-day month.
    Assert.areEqual(10, ALT_CLS_CardInvoiceCalendar.dueOffset(25, 5));
    Assert.areEqual(30, ALT_CLS_CardInvoiceCalendar.dueOffset(10, 10));
    Assert.areEqual(30, ALT_CLS_CardInvoiceCalendar.dueOffset(31, 31));
  }

  @IsTest
  static void aFirstRuleStartsItsInvoiceAtItsOwnValidity() {
    ALT_CLS_CardInvoiceCalendar cal = calendar(
      new List<AXF_OBJ_CardBillingCycleRule__c>{
        rule(d(2026, 8, 20), null, 5, 'NONE', 7)
      },
      new FixedDays()
    );
    ALT_CLS_CardInvoiceCalendar.Invoice sep = cal.invoice(2026, 9);
    // C(ago)=05/08 would open the window on 06/08, before the rule exists.
    Assert.areEqual(d(2026, 8, 20), sep.windowStart);
    Assert.areEqual(d(2026, 9, 5), sep.windowEnd);
    Assert.isNull(cal.invoiceMonthOf(d(2026, 8, 10)), 'no rule: civil month');
    Assert.areEqual('BLOCKED', cal.invoice(2026, 8).outcome);
    Assert.areEqual(
      d(2026, 9, 1),
      cal.invoiceOn(d(2026, 8, 25)).windowEnd.toStartOfMonth()
    );
    Assert.isNull(cal.invoiceOn(d(2026, 8, 1)));
  }

  @IsTest
  static void orgCalendarClosesWeekendsAndReadsTheDefaultHours() {
    ALT_CLS_CardInvoiceCalendar.OrgBusinessDays org = new ALT_CLS_CardInvoiceCalendar.OrgBusinessDays();
    Assert.isFalse(org.isBusinessDay(d(2026, 9, 5)), 'Saturday');
    Assert.isFalse(org.isBusinessDay(d(2026, 9, 6)), 'Sunday');
    Boolean monday = org.isBusinessDay(d(2026, 9, 14));
    Assert.areEqual(monday, org.isBusinessDay(d(2026, 9, 14)), 'cached');
    Assert.isTrue(ALT_CLS_CardInvoiceCalendar.isWeekend(d(1899, 12, 31)));
    // 00:00 of 14/09/2026 in Sao Paulo (UTC-3) is 03:00 UTC, whatever the running user's zone.
    Assert.areEqual(
      Datetime.newInstanceGmt(2026, 9, 14, 3, 0, 0),
      ALT_CLS_CardInvoiceCalendar.midnightIn(
        d(2026, 9, 14),
        'America/Sao_Paulo'
      )
    );
    Assert.isFalse(ALT_CLS_CardInvoiceCalendar.isWeekend(d(1899, 12, 29)));
  }

  @IsTest
  static void readsTheActiveRulesOfEachCardOnce() {
    // The rules are read in user mode: the running user gets the read access the branch grants
    // through its permission sets (not applied to test users by a check-only deploy).
    User self = new User(Id = UserInfo.getUserId());
    System.runAs(self) {
      PermissionSet ruleRead = new PermissionSet(
        Name = 'AXF152_TestCalendarRuleRead',
        Label = 'AXF152 test calendar rule read'
      );
      insert ruleRead;
      insert new ObjectPermissions(
        ParentId = ruleRead.Id,
        SobjectType = 'AXF_OBJ_CardBillingCycleRule__c',
        PermissionsRead = true
      );
      List<FieldPermissions> fields = new List<FieldPermissions>();
      for (
        String field : new List<String>{
          'AXF_CBR_DAT_EffectiveTo__c',
          'AXF_CBR_NUM_ClosingDay__c',
          'AXF_CBR_NUM_DueDayOffset__c',
          'AXF_CBR_PKL_ClosingDayAdjustment__c',
          'AXF_CBR_PKL_DueDayAdjustment__c',
          'AXF_CBR_TXT_CalendarPolicyVersion__c'
        }
      ) {
        fields.add(
          new FieldPermissions(
            ParentId = ruleRead.Id,
            SobjectType = 'AXF_OBJ_CardBillingCycleRule__c',
            Field = 'AXF_OBJ_CardBillingCycleRule__c.' + field,
            PermissionsRead = true
          )
        );
      }
      insert fields;
      insert new PermissionSetAssignment(
        AssigneeId = self.Id,
        PermissionSetId = ruleRead.Id
      );
    }
    System.runAs(self) {
      readRules();
    }
  }

  private static void readRules() {
    Account owner = new Account(
      Name = 'Holder 152 calendar',
      RecordTypeId = Account.SObjectType.getDescribe()
        .getRecordTypeInfosByDeveloperName()
        .get('AXF_Business')
        .getRecordTypeId()
    );
    insert owner;
    AXF_OBJ_CreditCard__c card = new AXF_OBJ_CreditCard__c(
      AXF_CC_LKP_Account__c = owner.Id,
      AXF_CC_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_CC_TXT_CurrencyIsoCode__c = 'BRL'
    );
    AXF_OBJ_CreditCard__c bare = new AXF_OBJ_CreditCard__c(
      AXF_CC_LKP_Account__c = owner.Id,
      AXF_CC_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_CC_TXT_CurrencyIsoCode__c = 'BRL'
    );
    insert new List<AXF_OBJ_CreditCard__c>{ card, bare };
    AXF_OBJ_CardBillingCycleRule__c active = rule(
      d(2026, 1, 1),
      null,
      5,
      'NONE',
      7
    );
    active.AXF_CBR_LKP_CreditCard__c = card.Id;
    AXF_OBJ_CardBillingCycleRule__c draft = rule(
      d(2025, 1, 1),
      d(2026, 1, 1),
      9,
      'NONE',
      7
    );
    draft.AXF_CBR_LKP_CreditCard__c = card.Id;
    draft.AXF_CBR_PKL_State__c = 'DRAFT';
    insert new List<AXF_OBJ_CardBillingCycleRule__c>{ active, draft };
    Test.startTest();
    Map<Id, ALT_CLS_CardInvoiceCalendar> calendars = ALT_CLS_CardInvoiceCalendar.forCards(
      new Set<Id>{ card.Id, bare.Id },
      new FixedDays()
    );
    Test.stopTest();
    Assert.areEqual(1, calendars.get(card.Id).ruleCount());
    Assert.areEqual(
      active.Id,
      calendars.get(card.Id).ruleOn(d(2026, 9, 1)).ruleId
    );
    Assert.isFalse(calendars.get(bare.Id).hasRules());
    Assert.isTrue(
      ALT_CLS_CardInvoiceCalendar.forCards(new Set<Id>(), null).isEmpty()
    );
  }
}
