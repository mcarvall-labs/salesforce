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
 * contractual (fixed/calculated), PROBABLE when it is an ESTIMATED occurrence; a standalone
 * FinancialTransaction is CONFIRMED by status, PROBABLE when planned, UNCERTAIN when planned and
 * flagged estimated.
 *
 * Visibility rules (AXF-21): obligations beyond the selected horizon stay visible in the
 * explanation (never hidden by a short horizon); overdue occurrences are reported separately and
 * never dropped; absence, error or a stale projection never becomes zero — the result derives
 * DEGRADED or BLOCKED on the server with explicit reasons. Results are display-only
 * (INFORMATIVE at best) and never authorize a material action.
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
    @AuraEnabled
    public String reason; // NOT_AUTHORIZED | NOT_A_HOLDER | COVERAGE_UNVERIFIED
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
    Boolean materialFailure = false;
    Integer scheduleCap = scheduleLimit + 1;
    List<AXF_OBJ_FinancialSchedule__c> schedules = [
      SELECT Id, Name, AXF_FSC_TXT_CurrencyIsoCode__c, AXF_FSC_PKL_Direction__c
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
      // The projection flags every unconfirmed line as "estimated"; the tier needs the
      // definition method: an ESTIMATED method (reference value) is PROBABLE, a contractual
      // amount (fixed/calculated) is a confirmed commitment.
      Set<Id> definitionIds = new Set<Id>();
      for (ALT_CLS_ScheduleProjection.OccurrenceLine line : projection.lines) {
        if (line.definitionId != null) {
          definitionIds.add(line.definitionId);
        }
      }
      Set<Id> estimatedDefinitions = new Set<Id>();
      if (!definitionIds.isEmpty()) {
        for (AXF_OBJ_ScheduleDefinition__c definition : [
          SELECT Id
          FROM AXF_OBJ_ScheduleDefinition__c
          WHERE
            Id IN :definitionIds
            AND AXF_SDF_PKL_Method__c = :ALT_CLS_ScheduleProjection.METHOD_ESTIMATED
          WITH USER_MODE
        ]) {
          estimatedDefinitions.add(definition.Id);
        }
      }
      for (ALT_CLS_ScheduleProjection.OccurrenceLine line : projection.lines) {
        Contribution c = new Contribution();
        c.currencyIso = schedule.AXF_FSC_TXT_CurrencyIsoCode__c;
        c.direction = schedule.AXF_FSC_PKL_Direction__c;
        c.tier = line.confirmed == true ||
          !estimatedDefinitions.contains(line.definitionId)
          ? TIER_CONFIRMED
          : TIER_PROBABLE;
        c.dueDate = line.effectiveDueDate == null
          ? line.nominalDueDate
          : line.effectiveDueDate;
        c.amount = nz(line.amount);
        contributions.add(c);
      }
    }
    Date planFloor = result.asOf.addYears(-1);
    Date horizon24 = ALT_CLS_ScheduleCalendar.monthEndShifted(
      result.asOf,
      MAX_HORIZON - 1
    );
    Integer planCap = MAX_PLANS + 1;
    Integer plans = 0;
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
        AND AXF_FTX_DAT_PurchaseDate__c >= :planFloor
      WITH USER_MODE
      ORDER BY AXF_FTX_DAT_PurchaseDate__c
      LIMIT :planCap
    ]) {
      plans++;
      if (plans > MAX_PLANS) {
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
      c.amount = nz(plan.AXF_FTX_NUM_Magnitude__c);
      contributions.add(c);
    }
    if (plans > 0) {
      SourceView view = new SourceView();
      view.kind = 'PLAN';
      view.label = 'FinancialTransaction';
      view.outcome = ALT_CLS_ScheduleProjection.OUTCOME_OK;
      view.occurrenceCount = plans;
      result.sources.add(view);
    }

    // ---- buckets
    Map<String, PeriodView> periods = new Map<String, PeriodView>();
    Map<String, OverdueView> overdue = new Map<String, OverdueView>();
    Map<String, Map<Integer, HorizonTotal>> byCurrency = new Map<String, Map<Integer, HorizonTotal>>();
    Set<String> currencies = new Set<String>();
    for (Contribution c : contributions) {
      if (String.isBlank(c.currencyIso) || c.dueDate == null) {
        addReason(result, 'INCOMPLETE_CONTRIBUTION');
        continue;
      }
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

  private static void exclude(Result result, Id accountId, String reason) {
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
