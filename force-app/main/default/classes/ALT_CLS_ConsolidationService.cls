/**
 * @description AXF-122 — consolidated totals over an authorized scope (S1 of AXF-4).
 *
 * The caller names the people/companies (Accounts) to consolidate. The server keeps only the
 * holders it can actually read (effective sharing + CRUD/FLS, `USER_MODE`), sums only the
 * settled facts (BAT/CCT, status POSTED) of the sources it can read, and keeps every
 * contribution attributed to its person/company, in its original currency, with its effective
 * date range and the source it came from. Nothing is reallocated here (siblings AXF-124/125).
 * AXF-123 adds the cross-currency comparison: a reporting currency converts the other currencies
 * through the canonical indicative policy, and withholds the comparable indicator when a pair has
 * no usable quote — see `applyComparison`.
 *
 * Access contract (AXF-4 AC2/AC3, AD-19/AD-21/AD-22):
 * - A requested holder that is not visible is reported as `NOT_AUTHORIZED` — the same answer
 *   whether it does not exist or is private; nothing about it is loaded.
 * - A visible holder the user does not fully control (`UserRecordAccess.HasAllAccess` false —
 *   reached through team, manual or role sharing) is `UNKNOWN` with coverage `UNVERIFIED`: the
 *   server cannot prove the visible sources are all of them, so its contributions are withheld
 *   and the result becomes `DEGRADED`. A total is never presented with silently omitted data and
 *   private amounts cannot be inferred by difference.
 * - Missing field access on the fact fields the sum depends on makes the whole result `BLOCKED`.
 * - A visible Account that is not an Axon person/company is `NOT_A_HOLDER`.
 * - When AXF-5 economic allocations are installed and a confirmed set exists for a fact, the
 *   fact contributes through its shares (attribution `ALLOCATION`, stored share magnitude when
 *   present); shares attributed outside the effective scope are counted as
 *   `ALLOCATED_OUTSIDE_SCOPE` (strangers) or `ALLOCATED_TO_UNVERIFIED_HOLDER` (requested holders
 *   whose coverage is unverified) without naming anyone. Invalid, incomplete or ambiguous
 *   allocations degrade the result instead of being summed.
 * - AXF-128 internal counter-entries: a confirmed allocation derives one counter-entry between
 *   the fact's holder and each allocated person/company. They are neutralized atomically — the
 *   fact then contributes once, through its economic attribution — only when the calculation
 *   receives *every* participant as an authorized holder; that is the consolidated view. While
 *   any participant is missing from the authorized scope nothing is netted: the fact contributes
 *   once at its material location, on its holder (`HOLDER`), and each authorized participant
 *   other than the holder still contributes its own parcel, redacted, so an individual view never
 *   loses its contribution to an attribution it cannot see. A pending counter-entry leaves the
 *   result `DEGRADED` with the existing exclusion reasons — the pair is not netted, so no total
 *   is presented as if it had been.
 * - Unbounded scopes are refused: at most `MAX_SCOPE` holders and `MAX_FACTS` facts per kind;
 *   beyond that the result is `BLOCKED` with `VOLUME_EXCEEDED` rather than partially summed.
 * - AXF-123 currency comparison: totals are only comparable inside one currency, so a requested
 *   reporting currency converts every other currency through the **canonical indicative policy**
 *   (AXF-92 / G8: same provider, same validity window, same displayed rounding, no snapshot). The
 *   original magnitudes and ISO codes are never written, converted in place or dropped, and the
 *   inflow/outflow are converted on the sides the contract fixes for them (BUY for an asset inflow,
 *   SELL for a liability/expense outflow). A pair without a usable fresh quote produces **no number
 *   at all** and withholds the comparable indicator with `MISSING_MATERIAL_FX` — parity is never
 *   assumed, and no total disappears because every original stays in the result.
 * - Any unexpected platform failure surfaces as `UNAVAILABLE`, never as a raw exception.
 *
 * Known limitation (deferred): joint holders (`AXF_OBJ_AccountHolder__c`) are not split here;
 * a source contributes to its primary holder unless a confirmed allocation says otherwise.
 */
public with sharing class ALT_CLS_ConsolidationService {
  public static final String POLICY_VERSION = 'consolidation-scope@1.0.0';
  public static final String CONFIDENCE_FULL = 'FULL';
  public static final String CONFIDENCE_DEGRADED = 'DEGRADED';
  public static final String CONFIDENCE_BLOCKED = 'BLOCKED';
  private static final String CP_CONSOLIDATE = 'AXF_CanConsolidate';
  private static final Set<String> AXON_RECORD_TYPES = new Set<String>{
    'AXF_Person',
    'AXF_Business'
  };
  private static final String EAS_OBJECT = 'AXF_OBJ_EconomicAllocationSet__c';
  private static final String EA_OBJECT = 'AXF_OBJ_EconomicAllocation__c';
  /** UserRecordAccess accepts at most 200 record ids per query. */
  public static final Integer MAX_SCOPE = 200;
  /** Facts per kind beyond which a scope is refused instead of partially summed. */
  public static final Integer MAX_FACTS = 10000;
  @TestVisible
  private static Integer factCap = MAX_FACTS;
  private static final Date EARLIEST = Date.newInstance(1700, 1, 1);
  private static final Date LATEST = Date.newInstance(4000, 12, 31);

  /** Test seam: replaces the AXF-5 allocation lookup (fact id -> shares). */
  @TestVisible
  private static Map<Id, List<AllocationShare>> allocationOverride;

  public class ConsolidationException extends Exception {
    public String code;
  }

  public class ScopeInput {
    public List<Id> accountIds;
    public Date fromDate;
    public Date toDate;
    /** AXF-123: currency the totals are compared in; blank leaves every total in its own currency. */
    public String reportingIso;
  }

  public class AllocationShare {
    public Id accountId;
    public Decimal percent;
    /** Stored share magnitude (AXF-126 conserves the fact); null falls back to percent. */
    public Decimal magnitude;
    public AllocationShare(Id accountId, Decimal percent) {
      this.accountId = accountId;
      this.percent = percent;
    }
    public AllocationShare(Id accountId, Decimal percent, Decimal magnitude) {
      this(accountId, percent);
      this.magnitude = magnitude;
    }
  }

  public class HolderScope {
    public Id accountId;
    public String accountName;
    public String state; // AUTHORIZED | UNKNOWN
    public String coverage; // FULL | UNVERIFIED
  }

  public class Exclusion {
    public Id accountId; // only echoed for ids the caller supplied
    public String reason; // NOT_AUTHORIZED | NOT_A_HOLDER | ALLOCATED_OUTSIDE_SCOPE | ALLOCATED_TO_UNVERIFIED_HOLDER
    public Integer count = 1;
  }

  public class Contribution {
    public Id accountId;
    public String accountName;
    public String attribution; // HOLDER | ALLOCATION | MIXED
    public String sourceKind; // BANK | CARD
    public Id sourceId;
    public String sourceLabel;
    public String currencyIso;
    public Decimal inflow = 0;
    public Decimal outflow = 0;
    public Decimal net = 0;
    public Integer factCount = 0;
    public Integer pendingCount = 0;
    public Date effectiveFrom;
    public Date effectiveTo;
  }

  public class Total {
    public String currencyIso;
    public Decimal inflow = 0;
    public Decimal outflow = 0;
    public Decimal net = 0;
    public Integer factCount = 0;
    public Integer holderCount = 0;
    /**
     * AXF-123: the same total in the requested reporting currency. Null state means no comparison
     * was requested; `ESTIMATED` carries the numbers, `STALE`/`UNAVAILABLE` carry none of them.
     */
    public String conversionState;
    public Decimal rateInflow; // BUY quote applied to the inflow (empty side: null)
    public Decimal rateOutflow; // SELL quote applied to the outflow (empty side: null)
    public String rateProvider;
    public Datetime rateEffectiveAt;
    public Decimal reportingInflow;
    public Decimal reportingOutflow;
    public Decimal reportingNet;
  }

  public class Result {
    public String policyVersion = POLICY_VERSION;
    public Datetime asOf;
    public Date fromDate;
    public Date toDate;
    public String confidence;
    public List<String> reasons = new List<String>();
    public List<HolderScope> holders = new List<HolderScope>();
    public List<Exclusion> exclusions = new List<Exclusion>();
    public List<Contribution> contributions = new List<Contribution>();
    public List<Total> totals = new List<Total>();
    /** AXF-123: currency the comparison was requested in (null when none was requested). */
    public String reportingIso;
    /** AXF-123: the one comparable indicator, or null when a currency has no usable quote. */
    public Total comparableTotal;
  }

  private class Fact {
    Id id;
    String kind;
    Id sourceId;
    Id holderId;
    String currencyIso;
    Decimal magnitude;
    String direction;
    String status;
    Date effectiveDate;
  }

  private class Source {
    Id id;
    String kind;
    Id holderId;
    String label;
  }

  /** One canonical exchange-rate row of the indicative policy; a null rate means unusable. */
  private class Quote {
    Decimal rate;
    String provider;
    Datetime effectiveAt;
  }

  public Result consolidate(ScopeInput input) {
    Set<Id> requested = new Set<Id>();
    if (input != null && input.accountIds != null) {
      for (Id accountId : input.accountIds) {
        if (accountId != null) {
          requested.add(accountId);
        }
      }
    }
    if (requested.isEmpty() || requested.size() > MAX_SCOPE) {
      throw failure('INVALID_INPUT');
    }
    if (
      input.fromDate != null &&
      input.toDate != null &&
      input.fromDate > input.toDate
    ) {
      throw failure('INVALID_INPUT');
    }
    if (!FeatureManagement.checkPermission(CP_CONSOLIDATE)) {
      throw failure('FORBIDDEN');
    }
    try {
      return consolidateScope(input, requested);
    } catch (ConsolidationException typed) {
      throw typed;
    } catch (Exception unexpected) {
      // Platform failures (query/security/null) never leak details to the caller.
      System.debug(LoggingLevel.ERROR, 'Consolidation failed: ' + unexpected);
      throw failure('UNAVAILABLE');
    }
  }

  private Result consolidateScope(ScopeInput input, Set<Id> requested) {
    Result result = new Result();
    result.asOf = Datetime.now();
    result.fromDate = input.fromDate;
    result.toDate = input.toDate;

    List<String> fieldGaps = missingFieldAccess();
    if (!fieldGaps.isEmpty()) {
      result.confidence = CONFIDENCE_BLOCKED;
      result.reasons.addAll(fieldGaps);
      return result;
    }

    Map<Id, Account> visible = new Map<Id, Account>();
    Set<Id> notHolders = new Set<Id>();
    for (Account holder : [
      SELECT Id, Name, RecordTypeId, RecordType.DeveloperName
      FROM Account
      WHERE Id IN :requested
      WITH USER_MODE
    ]) {
      // A record without an Axon record type is readable but is not a person/company here.
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
        Exclusion exclusion = new Exclusion();
        exclusion.accountId = accountId;
        exclusion.reason = notHolders.contains(accountId)
          ? 'NOT_A_HOLDER'
          : 'NOT_AUTHORIZED';
        result.exclusions.add(exclusion);
      }
    }

    // Coverage: only a holder the user fully controls (owner or equivalent full access) is known
    // to expose every source; a holder reached through partial sharing cannot prove that the
    // visible sources are all of them, so its contribution is withheld instead of summed.
    Set<Id> fullScope = new Set<Id>();
    Set<Id> visibleIds = visible.keySet();
    Id me = UserInfo.getUserId();
    if (!visibleIds.isEmpty()) {
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
      Boolean full = fullScope.contains(holderId);
      scope.coverage = full ? 'FULL' : 'UNVERIFIED';
      scope.state = full ? 'AUTHORIZED' : 'UNKNOWN';
      result.holders.add(scope);
      if (!full) {
        addReason(result, 'COVERAGE_UNVERIFIED');
      }
    }
    Map<Id, Source> sources = loadSources(fullScope);

    List<Fact> facts = loadFacts(
      sources,
      fullScope,
      input.fromDate,
      input.toDate
    );
    if (facts.size() > factCap) {
      // A partial sum would be presented as a total; refuse instead.
      result.holders.clear();
      result.confidence = CONFIDENCE_BLOCKED;
      result.reasons.clear();
      addReason(result, 'VOLUME_EXCEEDED');
      return result;
    }
    Map<Id, List<AllocationShare>> allocations = loadAllocations(facts, result);
    Map<String, Contribution> byKey = new Map<String, Contribution>();
    Integer outsideScope = 0;
    Integer unverifiedScope = 0;
    for (Fact fact : facts) {
      Source source = sources.get(fact.sourceId);
      List<AllocationShare> shares = allocations.get(fact.id);
      if (
        shares == null ||
        shares.isEmpty() ||
        fact.status != 'POSTED' ||
        !sharesAreUsable(shares, fact, result)
      ) {
        // Pending facts are counted once, on the holder, never split; unusable shares fall
        // back to the holder with the reason already recorded.
        accumulate(
          byKey,
          visible,
          source,
          fact,
          fact.holderId,
          'HOLDER',
          fact.magnitude,
          result
        );
        continue;
      }
      // Internal counter-entries (AXF-128). Each confirmed parcel derives a counter-entry
      // between the fact's holder and the allocated person/company; the pair reconciles the two
      // individual views and is neutralized only once the calculation holds *all* participants
      // as authorized holders. The decision is taken for the allocation as a whole, so a fact
      // is never netted by halves.
      Boolean neutralized = true;
      for (AllocationShare share : shares) {
        if (!fullScope.contains(share.accountId)) {
          neutralized = false;
          break;
        }
      }
      if (!neutralized) {
        // Not the consolidated view: nothing is netted. The fact keeps its contribution where
        // it materially is, so the holder's individual view does not lose it, and no private
        // participant is named for the parcels that stay outside.
        accumulate(
          byKey,
          visible,
          source,
          fact,
          fact.holderId,
          'HOLDER',
          fact.magnitude,
          result
        );
      }
      for (AllocationShare share : shares) {
        if (!fullScope.contains(share.accountId)) {
          if (visible.containsKey(share.accountId)) {
            unverifiedScope++;
          } else {
            outsideScope++;
          }
          continue;
        }
        if (!neutralized && share.accountId == fact.holderId) {
          // The holder's own parcel is already inside the material contribution it kept;
          // counting it again would inflate the very view it belongs to.
          continue;
        }
        Decimal magnitude = share.magnitude != null
          ? share.magnitude
          : (fact.magnitude *
              share.percent /
              100)
              .setScale(2, RoundingMode.HALF_EVEN);
        accumulate(
          byKey,
          visible,
          source,
          fact,
          share.accountId,
          'ALLOCATION',
          magnitude,
          result
        );
      }
    }
    if (outsideScope > 0) {
      Exclusion exclusion = new Exclusion();
      exclusion.reason = 'ALLOCATED_OUTSIDE_SCOPE';
      exclusion.count = outsideScope;
      result.exclusions.add(exclusion);
      addReason(result, 'ALLOCATED_OUTSIDE_SCOPE');
    }
    if (unverifiedScope > 0) {
      Exclusion exclusion = new Exclusion();
      exclusion.reason = 'ALLOCATED_TO_UNVERIFIED_HOLDER';
      exclusion.count = unverifiedScope;
      result.exclusions.add(exclusion);
      addReason(result, 'ALLOCATED_TO_UNVERIFIED_HOLDER');
    }
    List<String> keys = new List<String>(byKey.keySet());
    keys.sort();
    Map<String, Total> totals = new Map<String, Total>();
    Map<String, Set<Id>> holdersByCurrency = new Map<String, Set<Id>>();
    for (String key : keys) {
      Contribution contribution = byKey.get(key);
      result.contributions.add(contribution);
      Total total = totals.get(contribution.currencyIso);
      if (total == null) {
        total = new Total();
        total.currencyIso = contribution.currencyIso;
        totals.put(contribution.currencyIso, total);
        holdersByCurrency.put(contribution.currencyIso, new Set<Id>());
      }
      total.inflow += contribution.inflow;
      total.outflow += contribution.outflow;
      total.net += contribution.net;
      total.factCount += contribution.factCount;
      holdersByCurrency.get(contribution.currencyIso)
        .add(contribution.accountId);
    }
    List<String> currencies = new List<String>(totals.keySet());
    currencies.sort();
    for (String currencyIso : currencies) {
      Total total = totals.get(currencyIso);
      total.holderCount = holdersByCurrency.get(currencyIso).size();
      result.totals.add(total);
    }
    if (fullScope.isEmpty()) {
      result.confidence = CONFIDENCE_BLOCKED;
      addReason(result, 'NO_AUTHORIZED_SCOPE');
    } else {
      applyComparison(result, totals, holdersByCurrency, input.reportingIso);
      result.confidence = result.reasons.isEmpty()
        ? CONFIDENCE_FULL
        : CONFIDENCE_DEGRADED;
    }
    return result;
  }

  // ------------------------------------------------------- comparison (AXF-123)

  /**
   * Adds the reporting-currency comparison. A consolidated total is only comparable inside one
   * currency, so every other currency is converted through the canonical indicative policy
   * (AXF-92 / G8): the ratified provider, its validity window and its displayed rounding, read in
   * one query and never frozen into a snapshot. The original totals are left exactly as they are —
   * no magnitude, ISO code or stored row is written, and a currency that cannot be converted keeps
   * its original total in the result. The inflow is converted on the BUY quote and the outflow on
   * the SELL quote, the sides the contract fixes for an asset inflow and for a liability/expense
   * (AXF-24), and a side that is zero needs no quote at all.
   *
   * A currency whose needed quote is missing, non-positive or older than the window yields **no
   * number** (`STALE`/`UNAVAILABLE`), and the comparable indicator is then withheld entirely with
   * `MISSING_MATERIAL_FX`: assuming parity, or summing only the currencies that happened to have a
   * quote, would present a total that is not the consolidated position.
   */
  private static void applyComparison(
    Result result,
    Map<String, Total> totals,
    Map<String, Set<Id>> holdersByCurrency,
    String reportingIso
  ) {
    if (String.isBlank(reportingIso)) {
      return;
    }
    String reporting = reportingIso.trim().toUpperCase();
    result.reportingIso = reporting;
    Set<String> foreign = new Set<String>();
    for (String iso : totals.keySet()) {
      if (iso != null && !iso.equalsIgnoreCase(reporting)) {
        foreign.add(iso);
      }
    }
    Map<String, Quote> quotes = foreign.isEmpty()
      ? new Map<String, Quote>()
      : latestQuotes(foreign, reporting);
    Total comparable = new Total();
    comparable.currencyIso = reporting;
    Set<Id> comparableHolders = new Set<Id>();
    Boolean complete = true;
    List<String> currencies = new List<String>(totals.keySet());
    currencies.sort();
    for (String iso : currencies) {
      Total total = totals.get(iso);
      if (iso != null && iso.equalsIgnoreCase(reporting)) {
        comparable.inflow += total.inflow;
        comparable.outflow += total.outflow;
        comparable.factCount += total.factCount;
        comparableHolders.addAll(holdersByCurrency.get(iso));
        continue;
      }
      convert(total, quotes.get(iso + '|BUY'), quotes.get(iso + '|SELL'));
      if (total.conversionState != ALT_CLS_IndicativeEquivalenceService.STATE_ESTIMATED) {
        complete = false;
        continue;
      }
      comparable.inflow += total.reportingInflow;
      comparable.outflow += total.reportingOutflow;
      comparable.factCount += total.factCount;
      comparableHolders.addAll(holdersByCurrency.get(iso));
    }
    if (!complete) {
      // No comparable indicator: the original totals stay, the comparison never guesses a rate.
      addReason(result, 'MISSING_MATERIAL_FX');
      return;
    }
    comparable.net = comparable.inflow - comparable.outflow;
    comparable.holderCount = comparableHolders.size();
    result.comparableTotal = comparable;
  }

  /** Converts one currency total in place; leaves every reporting amount null when it cannot. */
  private static void convert(Total total, Quote buy, Quote sell) {
    // Only a side that contributes can fail: a zero side needs no quote and blocks nothing.
    Boolean inflowNeeded = total.inflow != 0;
    Boolean outflowNeeded = total.outflow != 0;
    if (inflowNeeded && !usable(buy)) {
      total.conversionState = stateOf(buy);
      return;
    }
    if (outflowNeeded && !usable(sell)) {
      total.conversionState = stateOf(sell);
      return;
    }
    Decimal inflow = inflowNeeded ? scaled(total.inflow * buy.rate) : 0;
    Decimal outflow = outflowNeeded ? scaled(total.outflow * sell.rate) : 0;
    total.reportingInflow = inflow;
    total.reportingOutflow = outflow;
    total.reportingNet = inflow - outflow;
    if (inflowNeeded) {
      total.rateInflow = buy.rate;
    }
    if (outflowNeeded) {
      total.rateOutflow = sell.rate;
    }
    Quote applied = inflowNeeded ? buy : (outflowNeeded ? sell : null);
    if (applied != null) {
      total.rateProvider = applied.provider;
      total.rateEffectiveAt = applied.effectiveAt;
    }
    total.conversionState = ALT_CLS_IndicativeEquivalenceService.STATE_ESTIMATED;
  }

  /**
   * Newest quote per base currency and side, in one read: the ratified provider and a deterministic
   * order. The newest row of a pair decides even when its rate is unusable — an older, superseded
   * quote is never substituted for it (AXF-140) — and a non-positive rate leaves the pair unusable.
   * Read under sharing and not under field-level security, exactly like the indicative layer it
   * mirrors: the quote is shared reference data (AXF-92; same posture as AXF-140).
   */
  private static Map<String, Quote> latestQuotes(
    Set<String> baseIsos,
    String quoteIso
  ) {
    Datetime oldest = System.now()
      .addDays(-ALT_CLS_IndicativeEquivalenceService.QUOTE_MAX_AGE_DAYS * 2);
    Map<String, Quote> result = new Map<String, Quote>();
    for (AXF_OBJ_ExchangeRate__c row : [
      SELECT
        AXF_EXR_TXT_BaseCurrency__c,
        AXF_EXR_PKL_Side__c,
        AXF_EXR_NUM_Rate__c,
        AXF_EXR_TXT_Provider__c,
        AXF_EXR_DT_EffectiveDateTime__c
      FROM AXF_OBJ_ExchangeRate__c
      WHERE
        AXF_EXR_TXT_BaseCurrency__c IN :baseIsos
        AND AXF_EXR_TXT_QuoteCurrency__c = :quoteIso
        AND AXF_EXR_TXT_Provider__c = :ALT_CLS_IndicativeEquivalenceService.PROVIDER_BCB_PTAX
        AND AXF_EXR_DT_EffectiveDateTime__c >= :oldest
      ORDER BY AXF_EXR_DT_EffectiveDateTime__c DESC, Id ASC
    ]) {
      String key =
        row.AXF_EXR_TXT_BaseCurrency__c +
        '|' +
        row.AXF_EXR_PKL_Side__c;
      if (result.containsKey(key)) {
        continue;
      }
      Quote quote = new Quote();
      quote.rate = row.AXF_EXR_NUM_Rate__c != null &&
        row.AXF_EXR_NUM_Rate__c > 0
        ? row.AXF_EXR_NUM_Rate__c
        : null;
      quote.provider = row.AXF_EXR_TXT_Provider__c;
      quote.effectiveAt = row.AXF_EXR_DT_EffectiveDateTime__c;
      result.put(key, quote);
    }
    return result;
  }

  private static Boolean usable(Quote quote) {
    return quote != null &&
      quote.rate != null &&
      quote.effectiveAt != null &&
      quote.effectiveAt >=
      System.now()
        .addDays(-ALT_CLS_IndicativeEquivalenceService.QUOTE_MAX_AGE_DAYS);
  }

  private static String stateOf(Quote quote) {
    // Present but outside the validity window -> stale; absent or non-positive -> unavailable.
    // Neither one is ever converted, and neither one falls back to an older quote.
    return quote == null || quote.rate == null
      ? ALT_CLS_IndicativeEquivalenceService.STATE_UNAVAILABLE
      : ALT_CLS_IndicativeEquivalenceService.STATE_STALE;
  }

  private static Decimal scaled(Decimal amount) {
    return amount.setScale(
      ALT_CLS_IndicativeEquivalenceService.DISPLAY_SCALE,
      System.RoundingMode.HALF_UP
    );
  }

  // ---------------------------------------------------------------- loaders

  private static Map<Id, Source> loadSources(Set<Id> holderIds) {
    Map<Id, Source> result = new Map<Id, Source>();
    if (holderIds.isEmpty()) {
      return result;
    }
    for (AXF_OBJ_BankAccount__c bank : [
      SELECT
        Id,
        AXF_BA_LKP_Account__c,
        AXF_BA_TXT_InstitutionName__c,
        AXF_BA_TXT_NumberMasked__c
      FROM AXF_OBJ_BankAccount__c
      WHERE AXF_BA_LKP_Account__c IN :holderIds
      WITH USER_MODE
    ]) {
      Source source = new Source();
      source.id = bank.Id;
      source.kind = 'BANK';
      source.holderId = bank.AXF_BA_LKP_Account__c;
      source.label = label(
        bank.AXF_BA_TXT_InstitutionName__c,
        bank.AXF_BA_TXT_NumberMasked__c
      );
      result.put(source.id, source);
    }
    for (AXF_OBJ_CreditCard__c card : [
      SELECT
        Id,
        AXF_CC_LKP_Account__c,
        AXF_CC_TXT_InstitutionName__c,
        AXF_CC_TXT_LastFourMasked__c
      FROM AXF_OBJ_CreditCard__c
      WHERE AXF_CC_LKP_Account__c IN :holderIds
      WITH USER_MODE
    ]) {
      Source source = new Source();
      source.id = card.Id;
      source.kind = 'CARD';
      source.holderId = card.AXF_CC_LKP_Account__c;
      source.label = label(
        card.AXF_CC_TXT_InstitutionName__c,
        card.AXF_CC_TXT_LastFourMasked__c
      );
      result.put(source.id, source);
    }
    return result;
  }

  private static List<Fact> loadFacts(
    Map<Id, Source> sources,
    Set<Id> fullScope,
    Date fromDate,
    Date toDate
  ) {
    List<Fact> result = new List<Fact>();
    Set<Id> bankIds = new Set<Id>();
    Set<Id> cardIds = new Set<Id>();
    for (Source source : sources.values()) {
      if (!fullScope.contains(source.holderId)) {
        continue;
      }
      if (source.kind == 'BANK') {
        bankIds.add(source.id);
      } else {
        cardIds.add(source.id);
      }
    }
    // The platform Date range itself; nothing dated inside it is silently excluded.
    Date lower = fromDate == null ? EARLIEST : fromDate;
    Date upper = toDate == null ? LATEST : toDate;
    Integer cap = factCap + 1;
    if (!bankIds.isEmpty()) {
      for (AXF_OBJ_BankAccountTransaction__c row : [
        SELECT
          Id,
          AXF_BAT_MDR_BankAccount__c,
          AXF_BAT_TXT_CurrencyIsoCode__c,
          AXF_BAT_NUM_Magnitude__c,
          AXF_BAT_PKL_Direction__c,
          AXF_BAT_PKL_Status__c,
          AXF_BAT_DAT_Date__c
        FROM AXF_OBJ_BankAccountTransaction__c
        WHERE
          AXF_BAT_MDR_BankAccount__c IN :bankIds
          AND AXF_BAT_DAT_Date__c >= :lower
          AND AXF_BAT_DAT_Date__c <= :upper
        WITH USER_MODE
        ORDER BY AXF_BAT_DAT_Date__c
        LIMIT :cap
      ]) {
        Fact fact = new Fact();
        fact.id = row.Id;
        fact.kind = 'BANK';
        fact.sourceId = row.AXF_BAT_MDR_BankAccount__c;
        fact.holderId = sources.get(fact.sourceId).holderId;
        fact.currencyIso = row.AXF_BAT_TXT_CurrencyIsoCode__c;
        fact.magnitude = row.AXF_BAT_NUM_Magnitude__c;
        fact.direction = row.AXF_BAT_PKL_Direction__c;
        fact.status = row.AXF_BAT_PKL_Status__c;
        fact.effectiveDate = row.AXF_BAT_DAT_Date__c;
        result.add(fact);
      }
    }
    if (!cardIds.isEmpty()) {
      for (AXF_OBJ_CreditCardTransaction__c row : [
        SELECT
          Id,
          AXF_CCT_MDR_CreditCard__c,
          AXF_CCT_TXT_CurrencyIsoCode__c,
          AXF_CCT_NUM_Magnitude__c,
          AXF_CCT_PKL_Direction__c,
          AXF_CCT_PKL_Status__c,
          AXF_CCT_DAT_Date__c
        FROM AXF_OBJ_CreditCardTransaction__c
        WHERE
          AXF_CCT_MDR_CreditCard__c IN :cardIds
          AND AXF_CCT_DAT_Date__c >= :lower
          AND AXF_CCT_DAT_Date__c <= :upper
        WITH USER_MODE
        ORDER BY AXF_CCT_DAT_Date__c
        LIMIT :cap
      ]) {
        Fact fact = new Fact();
        fact.id = row.Id;
        fact.kind = 'CARD';
        fact.sourceId = row.AXF_CCT_MDR_CreditCard__c;
        fact.holderId = sources.get(fact.sourceId).holderId;
        fact.currencyIso = row.AXF_CCT_TXT_CurrencyIsoCode__c;
        fact.magnitude = row.AXF_CCT_NUM_Magnitude__c;
        fact.direction = row.AXF_CCT_PKL_Direction__c;
        fact.status = row.AXF_CCT_PKL_Status__c;
        fact.effectiveDate = row.AXF_CCT_DAT_Date__c;
        result.add(fact);
      }
    }
    return result;
  }

  /**
   * Confirmed AXF-5 allocation shares per fact, when the allocation objects are installed.
   * Read dynamically so this class deploys before AXF-126 lands; the sum itself is never
   * redefined here (AD-19: the confirmed set is the only attribution authority).
   */
  private static Map<Id, List<AllocationShare>> loadAllocations(
    List<Fact> facts,
    Result summary
  ) {
    if (allocationOverride != null) {
      return allocationOverride;
    }
    Map<Id, List<AllocationShare>> result = new Map<Id, List<AllocationShare>>();
    if (facts.isEmpty()) {
      return result;
    }
    List<Schema.DescribeSObjectResult> describes;
    try {
      describes = Schema.describeSObjects(
        new List<String>{ EAS_OBJECT, EA_OBJECT }
      );
    } catch (Exception notInstalled) {
      // AXF-126 not deployed on this org: every fact is attributed to its holder.
      return result;
    }
    if (!describes[0].isAccessible() || !describes[1].isAccessible()) {
      // The attribution authority exists but this user cannot read it: holder sums may be
      // misattributed, so the result is degraded rather than silently summed by holder.
      addReason(summary, 'ALLOCATION_UNREADABLE');
      return result;
    }
    Set<Id> bankFacts = new Set<Id>();
    Set<Id> cardFacts = new Set<Id>();
    for (Fact fact : facts) {
      if (fact.kind == 'BANK') {
        bankFacts.add(fact.id);
      } else {
        cardFacts.add(fact.id);
      }
    }
    Map<Id, Id> factBySet = new Map<Id, Id>();
    Set<Id> ambiguous = new Set<Id>();
    try {
      Set<Id> seenFacts = new Set<Id>();
      for (
        SObject setRow : Database.queryWithBinds(
          'SELECT Id, AXF_EAS_LKP_BankTransaction__c, AXF_EAS_LKP_CardTransaction__c ' +
            'FROM ' +
            EAS_OBJECT +
            ' WHERE AXF_EAS_PKL_State__c = \'CONFIRMED\' AND (AXF_EAS_LKP_BankTransaction__c IN :bankFacts' +
            ' OR AXF_EAS_LKP_CardTransaction__c IN :cardFacts)',
          new Map<String, Object>{
            'bankFacts' => bankFacts,
            'cardFacts' => cardFacts
          },
          AccessLevel.USER_MODE
        )
      ) {
        Id factId = (Id) setRow.get('AXF_EAS_LKP_BankTransaction__c');
        if (factId == null) {
          factId = (Id) setRow.get('AXF_EAS_LKP_CardTransaction__c');
        }
        if (factId == null) {
          continue;
        }
        if (!seenFacts.add(factId)) {
          // Two confirmed sets for one fact: no single attribution authority.
          ambiguous.add(factId);
        }
        factBySet.put(setRow.Id, factId);
      }
      if (factBySet.isEmpty()) {
        return result;
      }
      Set<Id> setIds = factBySet.keySet();
      for (
        SObject share : Database.queryWithBinds(
          'SELECT AXF_EA_MDR_AllocationSet__c, AXF_EA_LKP_Account__c, AXF_EA_NUM_Percent__c, ' +
            'AXF_EA_NUM_Magnitude__c FROM ' +
            EA_OBJECT +
            ' WHERE AXF_EA_MDR_AllocationSet__c IN :setIds',
          new Map<String, Object>{ 'setIds' => setIds },
          AccessLevel.USER_MODE
        )
      ) {
        Id factId = factBySet.get(
          (Id) share.get('AXF_EA_MDR_AllocationSet__c')
        );
        if (!result.containsKey(factId)) {
          result.put(factId, new List<AllocationShare>());
        }
        result.get(factId)
          .add(
            new AllocationShare(
              (Id) share.get('AXF_EA_LKP_Account__c'),
              (Decimal) share.get('AXF_EA_NUM_Percent__c'),
              (Decimal) share.get('AXF_EA_NUM_Magnitude__c')
            )
          );
      }
    } catch (System.QueryException fieldAccess) {
      // Object readable but a queried field is not (or naming drift): degrade, do not throw.
      addReason(summary, 'ALLOCATION_UNREADABLE');
      return new Map<Id, List<AllocationShare>>();
    }
    if (!ambiguous.isEmpty()) {
      addReason(summary, 'ALLOCATION_AMBIGUOUS');
      for (Id factId : ambiguous) {
        result.remove(factId);
      }
    }
    return result;
  }

  /** Shares must be well-formed and complete before a fact is split; otherwise the holder keeps it. */
  private static Boolean sharesAreUsable(
    List<AllocationShare> shares,
    Fact fact,
    Result summary
  ) {
    Decimal totalPercent = 0;
    Decimal totalMagnitude = 0;
    Boolean storedMagnitudes = true;
    for (AllocationShare share : shares) {
      if (
        share.accountId == null ||
        share.percent == null ||
        share.percent < 0 ||
        share.percent > 100
      ) {
        addReason(summary, 'ALLOCATION_INVALID');
        return false;
      }
      totalPercent += share.percent;
      if (share.magnitude == null) {
        storedMagnitudes = false;
      } else {
        totalMagnitude += share.magnitude;
      }
    }
    if (totalPercent.setScale(6) != 100) {
      addReason(summary, 'ALLOCATION_INCOMPLETE');
      return false;
    }
    if (storedMagnitudes && totalMagnitude != fact.magnitude) {
      addReason(summary, 'ALLOCATION_INCOMPLETE');
      return false;
    }
    return true;
  }

  // ---------------------------------------------------------------- helpers

  private static void accumulate(
    Map<String, Contribution> byKey,
    Map<Id, Account> visible,
    Source source,
    Fact fact,
    Id accountId,
    String attribution,
    Decimal magnitude,
    Result summary
  ) {
    String key = String.join(
      new List<String>{
        String.valueOf(accountId),
        fact.currencyIso,
        String.valueOf(source.id)
      },
      '|'
    );
    Contribution contribution = byKey.get(key);
    if (contribution == null) {
      contribution = new Contribution();
      contribution.accountId = accountId;
      contribution.accountName = visible.get(accountId).Name;
      contribution.attribution = attribution;
      contribution.sourceKind = source.kind;
      contribution.sourceId = source.id;
      contribution.sourceLabel = source.label;
      contribution.currencyIso = fact.currencyIso;
      byKey.put(key, contribution);
    } else if (contribution.attribution != attribution) {
      contribution.attribution = 'MIXED';
    }
    if (fact.status == 'PENDING') {
      contribution.pendingCount++;
      return;
    }
    if (fact.status != 'POSTED') {
      // Unknown or missing status is neither settled nor pending: report, never sum.
      addReason(summary, 'UNKNOWN_STATUS');
      return;
    }
    if (fact.direction == 'CREDIT') {
      contribution.inflow += magnitude;
    } else if (fact.direction == 'DEBIT') {
      contribution.outflow += magnitude;
    } else {
      addReason(summary, 'UNKNOWN_DIRECTION');
      return;
    }
    contribution.net = contribution.inflow - contribution.outflow;
    contribution.factCount++;
    if (
      contribution.effectiveFrom == null ||
      fact.effectiveDate < contribution.effectiveFrom
    ) {
      contribution.effectiveFrom = fact.effectiveDate;
    }
    if (
      contribution.effectiveTo == null ||
      fact.effectiveDate > contribution.effectiveTo
    ) {
      contribution.effectiveTo = fact.effectiveDate;
    }
  }

  private static List<String> missingFieldAccess() {
    List<String> gaps = new List<String>();
    Map<Schema.SObjectType, List<Schema.SObjectField>> required = new Map<Schema.SObjectType, List<Schema.SObjectField>>{
      AXF_OBJ_BankAccountTransaction__c.SObjectType => new List<Schema.SObjectField>{
        AXF_OBJ_BankAccountTransaction__c.AXF_BAT_NUM_Magnitude__c,
        AXF_OBJ_BankAccountTransaction__c.AXF_BAT_PKL_Direction__c,
        AXF_OBJ_BankAccountTransaction__c.AXF_BAT_PKL_Status__c,
        AXF_OBJ_BankAccountTransaction__c.AXF_BAT_TXT_CurrencyIsoCode__c,
        AXF_OBJ_BankAccountTransaction__c.AXF_BAT_DAT_Date__c
      },
      AXF_OBJ_CreditCardTransaction__c.SObjectType => new List<Schema.SObjectField>{
        AXF_OBJ_CreditCardTransaction__c.AXF_CCT_NUM_Magnitude__c,
        AXF_OBJ_CreditCardTransaction__c.AXF_CCT_PKL_Direction__c,
        AXF_OBJ_CreditCardTransaction__c.AXF_CCT_PKL_Status__c,
        AXF_OBJ_CreditCardTransaction__c.AXF_CCT_TXT_CurrencyIsoCode__c,
        AXF_OBJ_CreditCardTransaction__c.AXF_CCT_DAT_Date__c
      },
      AXF_OBJ_BankAccount__c.SObjectType => new List<Schema.SObjectField>{
        AXF_OBJ_BankAccount__c.AXF_BA_LKP_Account__c,
        AXF_OBJ_BankAccount__c.AXF_BA_TXT_InstitutionName__c,
        AXF_OBJ_BankAccount__c.AXF_BA_TXT_NumberMasked__c
      },
      AXF_OBJ_CreditCard__c.SObjectType => new List<Schema.SObjectField>{
        AXF_OBJ_CreditCard__c.AXF_CC_LKP_Account__c,
        AXF_OBJ_CreditCard__c.AXF_CC_TXT_InstitutionName__c,
        AXF_OBJ_CreditCard__c.AXF_CC_TXT_LastFourMasked__c
      },
      Account.SObjectType => new List<Schema.SObjectField>{
        Account.Name,
        Account.RecordTypeId
      }
    };
    for (Schema.SObjectType type : required.keySet()) {
      if (!type.getDescribe().isAccessible()) {
        gaps.add('FIELD_ACCESS:' + type.getDescribe().getName());
        continue;
      }
      for (Schema.SObjectField field : required.get(type)) {
        if (!field.getDescribe().isAccessible()) {
          gaps.add('FIELD_ACCESS:' + field.getDescribe().getName());
        }
      }
    }
    return gaps;
  }

  private static String label(String institution, String masked) {
    if (String.isBlank(institution)) {
      return String.isBlank(masked) ? '' : masked;
    }
    return String.isBlank(masked) ? institution : institution + ' ' + masked;
  }

  private static void addReason(Result result, String reason) {
    if (!result.reasons.contains(reason)) {
      result.reasons.add(reason);
    }
  }

  private static ConsolidationException failure(String code) {
    ConsolidationException result = new ConsolidationException(code);
    result.code = code;
    return result;
  }
}
