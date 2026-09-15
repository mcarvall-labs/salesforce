/**
 * @description AXF-137 — horizon/scenario comparison engine (S1 of AXF-21) under
 * AXF-FORECASTING@1.0.0. For an authorized scope of people/companies it composes, for the eight
 * horizons (3..24 months) and the three scenarios, the full remaining commitment: persisted and
 * virtual schedule occurrences from the AXF-103 projection engine (never recomputed here) plus
 * standalone planned/confirmed FinancialTransactions, each counted exactly once and kept in its
 * original currency. Scenario inclusion is integral and non-probabilistic: conservative =
 * confirmed, intermediate adds probable, optimistic adds uncertain. Nothing is weighted.
 *
 * Tier derivation (v1, ratified with this slice; the sibling policy-application story owns an
 * explicit scenario state): a schedule occurrence is CONFIRMED when realized or when its amount is
 * contractual (fixed/calculated), PROBABLE when it is an ESTIMATED occurrence — AXF-138 removes
 * the ESTIMATED case, because the applied policy approves no method for it (§3 row 5), so every
 * schedule occurrence that contributes is a contractual amount and is CONFIRMED; a standalone
 * FinancialTransaction is CONFIRMED by status, PROBABLE when planned, UNCERTAIN when planned and
 * flagged estimated.
 *
 * Visibility rules (AXF-21): obligations beyond the selected horizon stay visible in the
 * explanation (never hidden by a short horizon); overdue occurrences are reported separately and
 * never dropped; absence, error or a stale projection never becomes zero — the result derives
 * DEGRADED or BLOCKED on the server with explicit reasons. Results are display-only
 * (INFORMATIVE at best) and never authorize a material action.
 *
 * AXF-138 applies `AXF-FORECASTING@1.0.0` to that result. Every contribution is placed in one
 * category class of §3 and carries the evidence authority of §2; the class, the authority and the
 * method v1.0.0 permits for it are reported per class (`categories`), the fallbacks actually
 * applied are named (`fallbacks`), the cutoff is `asOf`, the FX references are the preserved
 * original `currencies` (no conversion is applied, so no rate is consumed) and the taxonomy and
 * policy identity travel with the result. §2 rank 3 (approved WorkRecords and billing schedules)
 * is not an evidence source of this engine, so no contribution carries it.
 *
 * A class v1.0.0 gives no method to — §3 row 5, the variable, seasonal, discretionary and
 * exceptional classes — is never estimated: no average, weight, tier or probability is asserted
 * for such a contribution, and it is not summed. The class is read from the applied policy's own
 * category → method table over the method that produced the amounts — an amount taken from a
 * reference value instead of the approved formula is the reachable case, since no approved policy
 * version names a method for it — and never from the recorded formula version, which the schedule
 * service stamps for every method alike. Such an occurrence is reported with reason
 * `NO_APPROVED_METHOD`, the fallback of its row and an exclusion of its holder, so an incomplete
 * total stays distinguishable from a complete one, and no authority is asserted for evidence
 * whose class was not established. Omitting an obligation could increase the capacity shown, so
 * that omission only stays display-only (`INFORMATIVE_DISPLAY`) when it cannot: an inflow;
 * anything else is `BLOCKED_MATERIAL_OMISSION`.
 */
public with sharing class ALT_CLS_ForecastComparisonService {
  public static final String POLICY_VERSION = 'AXF-FORECASTING@1.0.0';
  public static final String ENGINE_VERSION = 'forecast-horizon@1.0.0';
  public static final String CP_COMPARE = 'AXF_CanCompareForecast';
  public static final List<Integer> HORIZONS = new List<Integer>{
    3,
    6,
    9,
    12,
    15,
    18,
    21,
    24
  };
  public static final Integer MAX_HORIZON = 24;
  public static final String SCENARIO_CONSERVATIVE = 'CONSERVATIVE';
  public static final String SCENARIO_INTERMEDIATE = 'INTERMEDIATE';
  public static final String SCENARIO_OPTIMISTIC = 'OPTIMISTIC';
  public static final String TIER_CONFIRMED = 'CONFIRMED';
  public static final String TIER_PROBABLE = 'PROBABLE';
  public static final String TIER_UNCERTAIN = 'UNCERTAIN';
  public static final String CONFIDENCE_INFORMATIVE = 'INFORMATIVE';
  public static final String CONFIDENCE_DEGRADED = 'DEGRADED';
  public static final String CONFIDENCE_BLOCKED = 'BLOCKED';
  // ---- AXF-138 — the applied clauses of AXF-FORECASTING@1.0.0 ----
  /** §2 evidence precedence, ranked. Rank 6 (statistical estimation) is named by no approved
   * version, so no contribution assembled here may carry it. */
  public static final Integer AUTHORITY_CONFIRMED_FACT = 1;
  public static final Integer AUTHORITY_CONTRACT_INSTALLMENT = 2;
  public static final Integer AUTHORITY_APPROVED_RECURRENCE = 4;
  public static final Integer AUTHORITY_SCENARIO_ITEM = 5;
  /** §3 category taxonomy, as the applied policy version names it. */
  public static final String CATEGORY_TAXONOMY = POLICY_VERSION + '#3';
  public static final String CATEGORY_CONTRACTUAL_INSTALLMENT = 'CONTRACTUAL_INSTALLMENT';
  public static final String CATEGORY_FIXED_RECURRENCE = 'FIXED_RECURRENCE';
  public static final String CATEGORY_EXPLICIT_SCENARIO_ITEM = 'EXPLICIT_SCENARIO_ITEM';
  /** §3 row 5 — variable, seasonal, discretionary and exceptional classes: no method in v1.0.0. */
  public static final String CATEGORY_UNPREDICTABLE_STATISTICAL = 'VARIABLE_SEASONAL_DISCRETIONARY_EXCEPTIONAL';
  public static final String METHOD_AUTHORITATIVE_SCHEDULE = 'authoritative-schedule@1.0.0';
  public static final String METHOD_APPROVED_RECURRENCE_SCHEDULE = 'approved-recurrence-schedule@1.0.0';
  public static final String METHOD_INTEGRAL_SCENARIO_INCLUSION = 'integral-scenario-inclusion@1.0.0';
  /** §3 fallback column, as actually applied. */
  public static final String FALLBACK_INFORMATIVE_DISPLAY = 'INFORMATIVE_DISPLAY';
  public static final String FALLBACK_BLOCKED_MATERIAL_OMISSION = 'BLOCKED_MATERIAL_OMISSION';
  public static final String REASON_NO_APPROVED_METHOD = 'NO_APPROVED_METHOD';
  /** §3 row 1 — methods whose amount the approved amortization formula produced. */
  private static final Set<String> INSTALLMENT_METHODS = new Set<String>{
    'INSTALLMENT',
    'PRICE',
    'SAC'
  };
  /** §3 row 3 — the approved recurrence schedule: the approved formula produces its amounts and
   * the declaration is used as declared, so no recurrence is invented. `ESTIMATED` is not a
   * method of this table — its amount comes from a reference value, not from an approved
   * formula — and falls in §3 row 5 instead. */
  private static final Set<String> RECURRENCE_METHODS = new Set<String>{
    'RECURRING'
  };
  /** Projections cost several queries each; beyond this the scope is refused, not truncated. */
  public static final Integer MAX_SCHEDULES = 12;
  public static final Integer MAX_PLANS = 2000;
  public static final Integer MAX_SCOPE = 200;
  private static final Set<String> AXON_RECORD_TYPES = new Set<String>{
    ALT_CLS_AxonHolder.RT_PERSON,
    ALT_CLS_AxonHolder.RT_BUSINESS
  };

  /** Test seam: evaluation instant. */
  @TestVisible
  private static Date todayOverride;
  @TestVisible
  private static Integer scheduleLimit = MAX_SCHEDULES;
  @TestVisible
  private static Integer planLimit = MAX_PLANS;

  public class ForecastException extends Exception {
    public String code;
  }

  public class Input {
    public List<Id> accountIds;
    public Integer horizonMonths;
    public String scenario;
    public Date asOf;
  }

  public class HolderScope {
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public String state; // AUTHORIZED | UNKNOWN
  }

  public class Exclusion {
    @AuraEnabled
    public Id accountId;
    /** NOT_AUTHORIZED | NOT_A_HOLDER | COVERAGE_UNVERIFIED | NO_APPROVED_METHOD */
    @AuraEnabled
    public String reason;
  }

  public class SourceView {
    @AuraEnabled
    public String kind; // SCHEDULE | PLAN
    @AuraEnabled
    public Id sourceId;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String currencyIso;
    @AuraEnabled
    public String outcome;
    @AuraEnabled
    public Integer occurrenceCount = 0;
    @AuraEnabled
    public Boolean coverageComplete = true;
    @AuraEnabled
    public Boolean unbounded = false;
    @AuraEnabled
    public Long projectionRevision;
    /** §2 — occurrences whose persisted row restates this schedule's evidence and is therefore
     * not read again by the standalone scenario query: counted once, never twice. */
    @AuraEnabled
    public Integer resolvedOverlapCount = 0;
  }

  /** One §3 category class as applied to this result, with the §2 authority behind it (AXF-138). */
  public class CategoryView {
    @AuraEnabled
    public String category;
    @AuraEnabled
    public Integer authority;
    /** The method v1.0.0 permits for the class; null when it permits none. */
    @AuraEnabled
    public String method;
    /** Contributions actually added under the class; an occurrence the policy gives no method to
     * is not a contribution and is not counted here. */
    @AuraEnabled
    public Integer contributionCount = 0;
  }

  /** One calendar month of one currency, split by tier and direction. */
  public class PeriodView {
    @AuraEnabled
    public String periodKey; // yyyy-MM
    @AuraEnabled
    public String currencyIso;
    @AuraEnabled
    public Decimal confirmedIn = 0;
    @AuraEnabled
    public Decimal confirmedOut = 0;
    @AuraEnabled
    public Decimal probableIn = 0;
    @AuraEnabled
    public Decimal probableOut = 0;
    @AuraEnabled
    public Decimal uncertainIn = 0;
    @AuraEnabled
    public Decimal uncertainOut = 0;
    @AuraEnabled
    public Integer count = 0;
  }

  /** Cumulative tiers of one horizon and currency; scenarios are sums of tiers. */
  public class HorizonTotal {
    @AuraEnabled
    public Integer horizonMonths;
    @AuraEnabled
    public String currencyIso;
    @AuraEnabled
    public Decimal confirmedIn = 0;
    @AuraEnabled
    public Decimal confirmedOut = 0;
    @AuraEnabled
    public Decimal probableIn = 0;
    @AuraEnabled
    public Decimal probableOut = 0;
    @AuraEnabled
    public Decimal uncertainIn = 0;
    @AuraEnabled
    public Decimal uncertainOut = 0;
    @AuraEnabled
    public Decimal conservativeNet = 0;
    @AuraEnabled
    public Decimal intermediateNet = 0;
    @AuraEnabled
    public Decimal optimisticNet = 0;
    /** Obligations dated after this horizon (up to and beyond 24 months): never hidden. */
    @AuraEnabled
    public Decimal beyondOut = 0;
    @AuraEnabled
    public Decimal beyondIn = 0;
    @AuraEnabled
    public Integer beyondCount = 0;
  }

  public class OverdueView {
    @AuraEnabled
    public String currencyIso;
    @AuraEnabled
    public Decimal amountOut = 0;
    @AuraEnabled
    public Decimal amountIn = 0;
    @AuraEnabled
    public Integer count = 0;
  }

  public class Result {
    @AuraEnabled
    public String policyVersion = POLICY_VERSION;
    @AuraEnabled
    public String categoryTaxonomy = CATEGORY_TAXONOMY;
    @AuraEnabled
    public String engineVersion = ENGINE_VERSION;
    @AuraEnabled
    public Date asOf;
    @AuraEnabled
    public Datetime computedAt;
    @AuraEnabled
    public Integer horizonMonths;
    @AuraEnabled
    public Date horizonEnd;
    @AuraEnabled
    public String scenario;
    @AuraEnabled
    public String confidence;
    @AuraEnabled
    public List<String> reasons = new List<String>();
    @AuraEnabled
    public List<String> allowedActions = new List<String>();
    @AuraEnabled
    public List<HolderScope> holders = new List<HolderScope>();
    @AuraEnabled
    public List<Exclusion> exclusions = new List<Exclusion>();
    /** §3 category classes applied to this result, with their §2 evidence authority (AXF-138). */
    @AuraEnabled
    public List<CategoryView> categories = new List<CategoryView>();
    /** §3 fallbacks actually applied; empty means none was needed. */
    @AuraEnabled
    public List<String> fallbacks = new List<String>();
    @AuraEnabled
    public List<SourceView> sources = new List<SourceView>();
    @AuraEnabled
    public List<String> currencies = new List<String>();
    @AuraEnabled
    public List<PeriodView> periods = new List<PeriodView>();
    @AuraEnabled
    public List<HorizonTotal> horizons = new List<HorizonTotal>();
    @AuraEnabled
    public List<OverdueView> overdue = new List<OverdueView>();
    @AuraEnabled
    public Boolean unboundedCommitment = false;
  }

  /** One contribution, counted exactly once. */
  private class Contribution {
    String currencyIso;
    String direction;
    String tier;
    Date dueDate;
    Decimal amount;
    /** The §3 class row this contribution is counted on, once it is actually added. */
    CategoryView category;
  }

  private class PendingLine {
    AXF_OBJ_FinancialSchedule__c schedule;
    ALT_CLS_ScheduleProjection.OccurrenceLine line;
  }

  // ------------------------------------------------------------------ entry point

  public Result compare(Input input) {
    if (!FeatureManagement.checkPermission(CP_COMPARE)) {
      throw failure('FORBIDDEN');
    }
    Set<Id> requested = new Set<Id>();
    if (input != null && input.accountIds != null) {
      for (Id accountId : input.accountIds) {
        if (accountId != null) {
          requested.add(accountId);
        }
      }
    }
    if (
      requested.isEmpty() ||
      requested.size() > MAX_SCOPE ||
      input.horizonMonths == null ||
      !HORIZONS.contains(input.horizonMonths) ||
      String.isBlank(input.scenario) ||
      !new Set<String>{
          SCENARIO_CONSERVATIVE,
          SCENARIO_INTERMEDIATE,
          SCENARIO_OPTIMISTIC
        }
        .contains(input.scenario)
    ) {
      throw failure('INVALID_INPUT');
    }
    try {
      return compareScope(input, requested);
    } catch (ForecastException typed) {
      throw typed;
    } catch (Exception unexpected) {
      System.debug(
        LoggingLevel.ERROR,
        'Forecast comparison failed: ' + unexpected
      );
      throw failure('UNAVAILABLE');
    }
  }

  private Result compareScope(Input input, Set<Id> requested) {
    Result result = new Result();
    Date today = todayOverride == null ? Date.today() : todayOverride;
    result.asOf = input.asOf == null ? today : input.asOf;
    result.computedAt = Datetime.now();
    result.horizonMonths = input.horizonMonths;
    result.scenario = input.scenario;
    result.horizonEnd = ALT_CLS_ScheduleCalendar.monthEndShifted(
      result.asOf,
      input.horizonMonths - 1
    );
    if (result.asOf != today) {
      addReason(result, 'AS_OF_NOT_TODAY');
    }

    // ---- holders: visible Axon record types, full control decides coverage
    Map<Id, Account> visible = new Map<Id, Account>();
    Set<Id> notHolders = new Set<Id>();
    for (Account holder : [
      SELECT Id, Name, RecordTypeId, RecordType.DeveloperName
      FROM Account
      WHERE Id IN :requested
      WITH USER_MODE
    ]) {
      if (
        holder.RecordTypeId != null &&
        AXON_RECORD_TYPES.contains(holder.RecordType.DeveloperName)
      ) {
        visible.put(holder.Id, holder);
      } else {
        notHolders.add(holder.Id);
      }
    }
    for (Id accountId : requested) {
      if (!visible.containsKey(accountId)) {
        exclude(
          result,
          accountId,
          notHolders.contains(accountId) ? 'NOT_A_HOLDER' : 'NOT_AUTHORIZED'
        );
      }
    }
    Set<Id> fullScope = new Set<Id>();
    if (!visible.isEmpty()) {
      Id me = UserInfo.getUserId();
      Set<Id> visibleIds = visible.keySet();
      for (UserRecordAccess access : [
        SELECT RecordId, HasAllAccess
        FROM UserRecordAccess
        WHERE UserId = :me AND RecordId IN :visibleIds
      ]) {
        if (access.HasAllAccess == true) {
          fullScope.add(access.RecordId);
        }
      }
    }
    for (Id holderId : visible.keySet()) {
      HolderScope scope = new HolderScope();
      scope.accountId = holderId;
      scope.accountName = visible.get(holderId).Name;
      scope.state = fullScope.contains(holderId) ? 'AUTHORIZED' : 'UNKNOWN';
      result.holders.add(scope);
      if (!fullScope.contains(holderId)) {
        // Partial sharing cannot prove every schedule/plan is visible: withheld, not summed.
        exclude(result, holderId, 'COVERAGE_UNVERIFIED');
        addReason(result, 'COVERAGE_UNVERIFIED');
      }
    }
    if (fullScope.isEmpty()) {
      return blocked(result, 'NO_AUTHORIZED_SCOPE');
    }

    // ---- contributions
    List<Contribution> contributions = new List<Contribution>();
    List<PendingLine> pendingLines = new List<PendingLine>();
    Set<Id> definitionIds = new Set<Id>();
    Map<String, CategoryView> categories = new Map<String, CategoryView>();
    Boolean materialFailure = false;
    Integer scheduleCap = scheduleLimit + 1;
    List<AXF_OBJ_FinancialSchedule__c> schedules = [
      SELECT
        Id,
        Name,
        AXF_FSC_LKP_Account__c,
        AXF_FSC_TXT_CurrencyIsoCode__c,
        AXF_FSC_PKL_Direction__c
      FROM AXF_OBJ_FinancialSchedule__c
      WHERE
        AXF_FSC_LKP_Account__c IN :fullScope
        AND AXF_FSC_PKL_State__c = 'ACTIVE'
      WITH USER_MODE
      ORDER BY Name
      LIMIT :scheduleCap
    ];
    if (schedules.size() > scheduleLimit) {
      return blocked(result, 'VOLUME_EXCEEDED');
    }
    for (AXF_OBJ_FinancialSchedule__c schedule : schedules) {
      SourceView view = new SourceView();
      view.kind = 'SCHEDULE';
      view.sourceId = schedule.Id;
      view.label = schedule.Name;
      view.currencyIso = schedule.AXF_FSC_TXT_CurrencyIsoCode__c;
      ALT_CLS_ScheduleProjection.ProjectionInput request = new ALT_CLS_ScheduleProjection.ProjectionInput();
      request.scheduleId = schedule.Id;
      request.asOfDate = result.asOf;
      ALT_CLS_ScheduleProjection.ProjectionResult projection = ALT_CLS_FinancialScheduleService.readProjection(
        request
      );
      view.outcome = projection.outcome;
      view.projectionRevision = projection.capturedProjectionRevision;
      result.sources.add(view);
      if (projection.outcome != ALT_CLS_ScheduleProjection.OUTCOME_OK) {
        // A stale, ambiguous or invalid commitment is material: it could conceal an obligation.
        addReason(result, 'SCHEDULE_' + projection.outcome);
        materialFailure = true;
        continue;
      }
      view.occurrenceCount = projection.lines.size();
      view.coverageComplete = projection.coverageComplete == true;
      view.unbounded = projection.unbounded == true;
      if (!view.coverageComplete) {
        // Indefinite recurrence or evaluation ceiling: the commitment continues past what
        // was evaluated, so the result says so instead of presenting a complete total.
        result.unboundedCommitment = true;
        addReason(result, 'COMMITMENT_UNBOUNDED');
      }
      for (ALT_CLS_ScheduleProjection.OccurrenceLine line : projection.lines) {
        if (line.persisted == true) {
          // §2: this occurrence already has its persisted row; it is counted here and is not
          // read again by the standalone scenario query, so no evidence is duplicated.
          view.resolvedOverlapCount++;
        }
        PendingLine pending = new PendingLine();
        pending.schedule = schedule;
        pending.line = line;
        pendingLines.add(pending);
        if (line.definitionId != null) {
          definitionIds.add(line.definitionId);
        }
      }
    }
    // §3 needs the method that produced the amounts: that is the evidence of the class, and the
    // recorded formula version is not — the schedule service stamps it for every method alike.
    // One query for every schedule.
    Map<Id, AXF_OBJ_ScheduleDefinition__c> definitions = new Map<Id, AXF_OBJ_ScheduleDefinition__c>();
    if (!definitionIds.isEmpty()) {
      definitions = new Map<Id, AXF_OBJ_ScheduleDefinition__c>(
        [
          SELECT Id, AXF_SDF_PKL_Method__c
          FROM AXF_OBJ_ScheduleDefinition__c
          WHERE Id IN :definitionIds
          WITH USER_MODE
        ]
      );
    }
    for (PendingLine pending : pendingLines) {
      CategoryView classified = classifyOccurrence(
        definitions.get(pending.line.definitionId)
      );
      CategoryView counted = categoryRow(categories, classified);
      if (classified.method == null) {
        // §3 row 5: v1.0.0 approves no method, so no amount, tier or probability is asserted and
        // nothing is summed. The omission is recorded against its holder instead of vanishing:
        // an incomplete total stays distinguishable from a complete one. Omitting an obligation
        // could increase the capacity shown, so only an inflow omission is provably safe and
        // stays display-only.
        addReason(result, REASON_NO_APPROVED_METHOD);
        exclude(
          result,
          pending.schedule.AXF_FSC_LKP_Account__c,
          REASON_NO_APPROVED_METHOD
        );
        Boolean omissionIsSafe =
          pending.schedule.AXF_FSC_PKL_Direction__c == 'CREDIT';
        addFallback(
          result,
          omissionIsSafe
            ? FALLBACK_INFORMATIVE_DISPLAY
            : FALLBACK_BLOCKED_MATERIAL_OMISSION
        );
        materialFailure = materialFailure || !omissionIsSafe;
        continue;
      }
      Contribution c = new Contribution();
      c.category = counted;
      c.currencyIso = pending.schedule.AXF_FSC_TXT_CurrencyIsoCode__c;
      c.direction = pending.schedule.AXF_FSC_PKL_Direction__c;
      // Only occurrences whose class v1.0.0 gives a method reach here, and that method's amount is
      // a commitment rather than a reference value: the tier is confirmed.
      c.tier = TIER_CONFIRMED;
      c.dueDate = pending.line.effectiveDueDate == null
        ? pending.line.nominalDueDate
        : pending.line.effectiveDueDate;
      c.amount = pending.line.amount;
      contributions.add(c);
    }
    // Floor on the effective due date: an old purchase with a recent or future due date
    // stays in; only obligations due more than a year before asOf are outside the window.
    Date planFloor = result.asOf.addYears(-1);
    Integer planCap = planLimit + 1;
    Integer plans = 0;
    Integer planContributions = 0;
    for (AXF_OBJ_FinancialTransaction__c plan : [
      SELECT
        Id,
        AXF_FTX_PKL_Status__c,
        AXF_FTX_PKL_Direction__c,
        AXF_FTX_TXT_CurrencyIsoCode__c,
        AXF_FTX_NUM_Magnitude__c,
        AXF_FTX_DAT_DueDate__c,
        AXF_FTX_DAT_PurchaseDate__c,
        AXF_FTX_CHK_IsEstimated__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE
        AXF_FTX_LKP_Account__c IN :fullScope
        AND AXF_FTX_LKP_Schedule__c = NULL
        AND AXF_FTX_PKL_ScheduleState__c != 'CANCELLED'
        AND (AXF_FTX_DAT_DueDate__c >= :planFloor
        OR (AXF_FTX_DAT_DueDate__c = NULL
        AND AXF_FTX_DAT_PurchaseDate__c >= :planFloor))
      WITH USER_MODE
      ORDER BY AXF_FTX_DAT_PurchaseDate__c
      LIMIT :planCap
    ]) {
      plans++;
      if (plans > planLimit) {
        return blocked(result, 'VOLUME_EXCEEDED');
      }
      Date due = plan.AXF_FTX_DAT_DueDate__c == null
        ? plan.AXF_FTX_DAT_PurchaseDate__c
        : plan.AXF_FTX_DAT_DueDate__c;
      Boolean confirmed = plan.AXF_FTX_PKL_Status__c == 'CONFIRMED';
      if (confirmed && due < result.asOf) {
        continue; // realized history, not a forecast
      }
      Contribution c = new Contribution();
      c.currencyIso = plan.AXF_FTX_TXT_CurrencyIsoCode__c;
      c.direction = plan.AXF_FTX_PKL_Direction__c;
      c.tier = confirmed
        ? TIER_CONFIRMED
        : (plan.AXF_FTX_CHK_IsEstimated__c == true
            ? TIER_UNCERTAIN
            : TIER_PROBABLE);
      c.dueDate = due;
      c.amount = plan.AXF_FTX_NUM_Magnitude__c;
      contributions.add(c);
      // §3 row 4: an explicit amount, period, currency and state are integral scenario
      // inclusion. §2 ranks a confirmed fact above the scenario item it restates.
      CategoryView classified = new CategoryView();
      classified.category = CATEGORY_EXPLICIT_SCENARIO_ITEM;
      classified.authority = confirmed
        ? AUTHORITY_CONFIRMED_FACT
        : AUTHORITY_SCENARIO_ITEM;
      classified.method = METHOD_INTEGRAL_SCENARIO_INCLUSION;
      c.category = categoryRow(categories, classified);
      planContributions++;
    }
    if (plans > 0) {
      SourceView view = new SourceView();
      view.kind = 'PLAN';
      view.label = 'FinancialTransaction';
      view.outcome = ALT_CLS_ScheduleProjection.OUTCOME_OK;
      // Only rows that contribute; realized history is not a forecast input.
      view.occurrenceCount = planContributions;
      result.sources.add(view);
    }

    // ---- buckets
    Map<String, PeriodView> periods = new Map<String, PeriodView>();
    Map<String, OverdueView> overdue = new Map<String, OverdueView>();
    Map<String, Map<Integer, HorizonTotal>> byCurrency = new Map<String, Map<Integer, HorizonTotal>>();
    Set<String> currencies = new Set<String>();
    for (Contribution c : contributions) {
      if (
        String.isBlank(c.currencyIso) ||
        c.dueDate == null ||
        c.amount == null ||
        (c.direction != 'CREDIT' &&
        c.direction != 'DEBIT')
      ) {
        // A missing amount or direction is never zero: it degrades the result instead.
        addReason(result, 'INCOMPLETE_CONTRIBUTION');
        continue;
      }
      // The class counts the contributions actually added — an occurrence dropped above, or
      // dropped here, never inflates it.
      c.category.contributionCount++;
      currencies.add(c.currencyIso);
      if (c.dueDate < result.asOf) {
        OverdueView late = overdue.get(c.currencyIso);
        if (late == null) {
          late = new OverdueView();
          late.currencyIso = c.currencyIso;
          overdue.put(c.currencyIso, late);
        }
        late.count++;
        if (c.direction == 'CREDIT') {
          late.amountIn += c.amount;
        } else {
          late.amountOut += c.amount;
        }
        continue;
      }
      if (!byCurrency.containsKey(c.currencyIso)) {
        Map<Integer, HorizonTotal> totals = new Map<Integer, HorizonTotal>();
        for (Integer months : HORIZONS) {
          HorizonTotal total = new HorizonTotal();
          total.horizonMonths = months;
          total.currencyIso = c.currencyIso;
          totals.put(months, total);
        }
        byCurrency.put(c.currencyIso, totals);
      }
      Boolean inflow = c.direction == 'CREDIT';
      for (Integer months : HORIZONS) {
        HorizonTotal total = byCurrency.get(c.currencyIso).get(months);
        Date endOf = ALT_CLS_ScheduleCalendar.monthEndShifted(
          result.asOf,
          months - 1
        );
        if (c.dueDate <= endOf) {
          addTier(total, c.tier, inflow, c.amount);
        } else {
          total.beyondCount++;
          if (inflow) {
            total.beyondIn += c.amount;
          } else {
            total.beyondOut += c.amount;
          }
        }
      }
      if (c.dueDate <= result.horizonEnd) {
        String key = periodKey(c.dueDate) + '|' + c.currencyIso;
        PeriodView period = periods.get(key);
        if (period == null) {
          period = new PeriodView();
          period.periodKey = periodKey(c.dueDate);
          period.currencyIso = c.currencyIso;
          periods.put(key, period);
        }
        period.count++;
        addTier(period, c.tier, inflow, c.amount);
      }
    }
    List<String> currencyList = new List<String>(currencies);
    currencyList.sort();
    result.currencies = currencyList;
    if (currencyList.size() > 1) {
      addReason(result, 'MULTI_CURRENCY');
    }
    for (String currencyIso : currencyList) {
      if (!byCurrency.containsKey(currencyIso)) {
        continue;
      }
      for (Integer months : HORIZONS) {
        HorizonTotal total = byCurrency.get(currencyIso).get(months);
        total.conservativeNet = total.confirmedIn - total.confirmedOut;
        total.intermediateNet =
          total.conservativeNet +
          total.probableIn -
          total.probableOut;
        total.optimisticNet =
          total.intermediateNet +
          total.uncertainIn -
          total.uncertainOut;
        result.horizons.add(total);
      }
    }
    // Every calendar month of the selected horizon is listed per currency, zero rows
    // included, so a gap reads as "nothing due" instead of "nothing known".
    for (String currencyIso : byCurrency.keySet()) {
      Date month = result.asOf.toStartOfMonth();
      while (month <= result.horizonEnd) {
        String key = periodKey(month) + '|' + currencyIso;
        if (!periods.containsKey(key)) {
          PeriodView period = new PeriodView();
          period.periodKey = periodKey(month);
          period.currencyIso = currencyIso;
          periods.put(key, period);
        }
        month = month.addMonths(1);
      }
    }
    List<String> periodKeys = new List<String>(periods.keySet());
    periodKeys.sort();
    for (String key : periodKeys) {
      result.periods.add(periods.get(key));
    }
    List<String> overdueKeys = new List<String>(overdue.keySet());
    overdueKeys.sort();
    for (String key : overdueKeys) {
      result.overdue.add(overdue.get(key));
      addReason(result, 'OVERDUE_OBLIGATIONS');
    }
    Boolean beyond = false;
    for (HorizonTotal total : result.horizons) {
      if (total.horizonMonths == input.horizonMonths && total.beyondCount > 0) {
        beyond = true;
      }
    }
    if (beyond) {
      addReason(result, 'OBLIGATIONS_BEYOND_HORIZON');
    }
    if (contributions.isEmpty()) {
      addReason(result, 'NO_CONTRIBUTIONS');
    }
    // The applied §3 taxonomy travels with the result, deterministically ordered.
    List<String> categoryKeys = new List<String>(categories.keySet());
    categoryKeys.sort();
    for (String key : categoryKeys) {
      result.categories.add(categories.get(key));
    }

    // ---- confidence: display-only at best; never authorizes a material action
    if (materialFailure) {
      result.confidence = CONFIDENCE_BLOCKED;
    } else if (
      result.reasons.contains('COVERAGE_UNVERIFIED') ||
      result.reasons.contains('COMMITMENT_UNBOUNDED') ||
      result.reasons.contains('INCOMPLETE_CONTRIBUTION') ||
      result.reasons.contains('OVERDUE_OBLIGATIONS')
    ) {
      result.confidence = CONFIDENCE_DEGRADED;
    } else {
      result.confidence = CONFIDENCE_INFORMATIVE;
    }
    if (result.confidence != CONFIDENCE_BLOCKED) {
      result.allowedActions.add('REVIEW_SCHEDULES');
    }
    return result;
  }

  // ------------------------------------------------------------------ helpers

  /**
   * §3: the class of a scheduled occurrence, the §2 authority behind it and the method v1.0.0
   * permits for it. The class comes from the applied policy's own category → method table, read
   * over the method that produced the occurrence's amounts; the recorded formula version is not
   * consulted, because it is stamped for every method alike. An occurrence whose class the policy
   * does not name, and one whose definition cannot be read, carry neither a class the policy
   * approves nor an authority: nothing is asserted for them, and the caller records the omission.
   */
  private static CategoryView classifyOccurrence(
    AXF_OBJ_ScheduleDefinition__c definition
  ) {
    CategoryView view = new CategoryView();
    String definitionMethod = definition == null
      ? null
      : definition.AXF_SDF_PKL_Method__c;
    if (INSTALLMENT_METHODS.contains(definitionMethod)) {
      // §3 row 1 — contractual/installment: the authoritative schedule is the permitted method.
      view.category = CATEGORY_CONTRACTUAL_INSTALLMENT;
      view.authority = AUTHORITY_CONTRACT_INSTALLMENT;
      view.method = METHOD_AUTHORITATIVE_SCHEDULE;
    } else if (RECURRENCE_METHODS.contains(definitionMethod)) {
      // §3 row 3 — fixed recurrence: the approved recurrence schedule is the permitted method,
      // and its amount is the declared one, so no recurrence is invented for it.
      view.category = CATEGORY_FIXED_RECURRENCE;
      view.authority = AUTHORITY_APPROVED_RECURRENCE;
      view.method = METHOD_APPROVED_RECURRENCE_SCHEDULE;
    } else {
      // §3 row 5 — the variable, seasonal, discretionary and exceptional classes, and any class
      // the policy does not name: v1.0.0 approves no method, and no authority was established,
      // so none is claimed.
      view.category = CATEGORY_UNPREDICTABLE_STATISTICAL;
    }
    return view;
  }

  /** One row per distinct class/authority/method applied. Its count is incremented where a
   * contribution is actually added, so an occurrence the policy drops never inflates it. */
  private static CategoryView categoryRow(
    Map<String, CategoryView> categories,
    CategoryView classified
  ) {
    String key =
      classified.category +
      '|' +
      String.valueOf(classified.authority) +
      '|' +
      classified.method;
    CategoryView view = categories.get(key);
    if (view == null) {
      view = new CategoryView();
      view.category = classified.category;
      view.authority = classified.authority;
      view.method = classified.method;
      categories.put(key, view);
    }
    return view;
  }

  private static void addFallback(Result result, String fallback) {
    if (!result.fallbacks.contains(fallback)) {
      result.fallbacks.add(fallback);
    }
  }

  private static void addTier(
    Object bucket,
    String tier,
    Boolean inflow,
    Decimal amount
  ) {
    if (bucket instanceof PeriodView) {
      PeriodView p = (PeriodView) bucket;
      if (tier == TIER_CONFIRMED) {
        if (inflow) {
          p.confirmedIn += amount;
        } else {
          p.confirmedOut += amount;
        }
      } else if (tier == TIER_PROBABLE) {
        if (inflow) {
          p.probableIn += amount;
        } else {
          p.probableOut += amount;
        }
      } else {
        if (inflow) {
          p.uncertainIn += amount;
        } else {
          p.uncertainOut += amount;
        }
      }
      return;
    }
    HorizonTotal h = (HorizonTotal) bucket;
    if (tier == TIER_CONFIRMED) {
      if (inflow) {
        h.confirmedIn += amount;
      } else {
        h.confirmedOut += amount;
      }
    } else if (tier == TIER_PROBABLE) {
      if (inflow) {
        h.probableIn += amount;
      } else {
        h.probableOut += amount;
      }
    } else {
      if (inflow) {
        h.uncertainIn += amount;
      } else {
        h.uncertainOut += amount;
      }
    }
  }

  public static String periodKey(Date day) {
    return String.valueOf(day.year()) +
      '-' +
      (day.month() < 10 ? '0' : '') +
      String.valueOf(day.month());
  }

  private static Result blocked(Result result, String reason) {
    addReason(result, reason);
    result.confidence = CONFIDENCE_BLOCKED;
    result.allowedActions.clear();
    return result;
  }

  /** One exclusion per holder and reason: an omission is recorded, never inferred from a total. */
  private static void exclude(Result result, Id accountId, String reason) {
    for (Exclusion existing : result.exclusions) {
      if (existing.accountId == accountId && existing.reason == reason) {
        return;
      }
    }
    Exclusion exclusion = new Exclusion();
    exclusion.accountId = accountId;
    exclusion.reason = reason;
    result.exclusions.add(exclusion);
  }

  private static void addReason(Result result, String reason) {
    if (!result.reasons.contains(reason)) {
      result.reasons.add(reason);
    }
  }

  private static Decimal nz(Decimal value) {
    return value == null ? 0 : value;
  }

  private static ForecastException failure(String code) {
    ForecastException result = new ForecastException(code);
    result.code = code;
    return result;
  }
}
