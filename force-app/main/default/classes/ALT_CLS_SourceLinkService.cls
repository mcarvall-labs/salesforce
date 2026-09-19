/**
 * @description AXF-134: basic link flow from an imported bank/card fact to a planned financial
 * transaction. Selects eligible sources (BANK/CARD, POSTED, AVAILABLE parent, authorized holder,
 * no OPEN review), suggests persisted and virtual forecast candidates in a deterministic order
 * without any undocumented amount/date tolerance, and confirms the link through the AXF-25
 * realization contract (typed allocation, idempotent operation key, CONFLICT on divergence).
 * The source fact is never copied or altered; only its optimistic version is bumped by AXF-25.
 * AXF-139: every candidate carries independent observable evidence (ALT_CLS_MatchEvidence,
 * AXF-MATCHING@1.0.0), stays CONSULTATIVE, and is ordered by the policy's presentation order.
 * AXF-140: a candidate in another currency is shown with its original amount, available amount,
 * currency, indicative conversion and remaining residual as separate facts; it stays BLOCKED and
 * unlinkable because confirmation requires exact currency arithmetic, and confirmation of a pair
 * without material exchange-rate evidence is refused with MISSING_MATERIAL_FX. A linkable candidate
 * whose residual stays non-zero after the source's available amount is applied is PARTIAL (policy
 * §3). No tolerance, weight, default rate or conclusion policy is introduced: the residual is
 * reported as it is.
 * AXF-135: the caller declares the economic role of the link and the service never classifies it —
 * `AXF_CCT_TXT_BillReference__c` is only the statement a card line belongs to and never makes a link
 * an invoice payment. The declared role travels in the canonical payload (AXF-25), and a role this
 * slice cannot route (invoice payment, transfer, refund) is refused before any write, so an invoice
 * payment can never create a second consumption expense. The whole available amount of the source is
 * applied to the chosen obligation — an outflow to an expense, an inflow to a revenue, as the source
 * already carries — and what that obligation cannot absorb stays on the source as an explicit
 * multi-target need (AXF-30); the obligation is never increased to absorb it.
 */
public with sharing class ALT_CLS_SourceLinkService {
  public static final String POLICY_VERSION = 'AXF-SOURCE-LINK@1.0.0';
  public static final String CP_LINK = 'AXF_CanLinkSource';
  public static final String KIND_BANK = 'BANK';
  public static final String KIND_CARD = 'CARD';
  /**
   * AXF-135: economic roles of a link. The role is always declared by the caller and never derived
   * from a description, a provider category or the statement association of a card line. Only
   * `APPLICATION` — the fact settles the obligation of the target, or becomes the realized entry
   * itself — has a supported capability in this slice.
   */
  public static final String ROLE_APPLICATION = 'APPLICATION';
  public static final String ROLE_INVOICE_PAYMENT = 'INVOICE_PAYMENT';
  public static final String ROLE_TRANSFER = 'TRANSFER';
  public static final String ROLE_REFUND = 'REFUND';
  public static final Integer DEFAULT_PAGE = 25;
  public static final Integer MAX_PAGE = 50;
  /** Rows scanned per candidate scan window before in-memory exclusion of realized/cancelled targets. */
  public static final Integer MAX_SCAN = 200;
  public static final Integer MAX_SCHEDULES = 12;
  public static final Integer MAX_VIRTUAL = 60;
  /** Highest page a caller may ask for; beyond it the scan itself is the limit. */
  public static final Integer MAX_PAGE_NUMBER = 1000;
  /** Allocation rows read per verification; reaching it means the net cannot be trusted. */
  public static final Integer MAX_ALLOCATION_ROWS = 2000;
  private static final Set<String> KINDS = new Set<String>{
    KIND_BANK,
    KIND_CARD
  };
  private static final Set<String> DIRECTIONS = new Set<String>{
    'DEBIT',
    'CREDIT'
  };
  private static final Set<String> ECONOMIC_ROLES = new Set<String>{
    ROLE_APPLICATION,
    ROLE_INVOICE_PAYMENT,
    ROLE_TRANSFER,
    ROLE_REFUND
  };
  /** Roles with a supported capability here; every other declared role is refused without a write. */
  private static final Set<String> ROUTABLE_ROLES = new Set<String>{
    ROLE_APPLICATION
  };
  private static final Set<String> SOURCES = new Set<String>{
    'PLUGGY',
    'CSV',
    'MANUAL'
  };
  @TestVisible
  private static Date todayOverride;

  public class SourceLinkException extends Exception {
  }

  public class SourceView {
    @AuraEnabled
    public Id sourceId;
    @AuraEnabled
    public String sourceKind;
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public Id fundingId;
    @AuraEnabled
    public String fundingLabel;
    @AuraEnabled
    public String origin;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public Decimal residual;
    @AuraEnabled
    public String currencyIso;
    @AuraEnabled
    public String direction;
    @AuraEnabled
    public Date factDate;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public String category;
    /** Provider key: used server-side for the EXTERNAL_IDENTITY feature, never sent to the client. */
    public transient String sourceKey;
    @AuraEnabled
    public Decimal version;
    @AuraEnabled
    public Boolean eligible = false;
    @AuraEnabled
    public List<String> reasons = new List<String>();
  }

  public class CandidateView {
    @AuraEnabled
    public Id targetId;
    @AuraEnabled
    public Id scheduleId;
    @AuraEnabled
    public Integer sequence;
    @AuraEnabled
    public Boolean persisted = false;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public Decimal residual;
    @AuraEnabled
    public String currencyIso;
    @AuraEnabled
    public String direction;
    @AuraEnabled
    public Date dueDate;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public String category;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Decimal version;
    @AuraEnabled
    public Boolean linkable = false;
    @AuraEnabled
    public List<String> reasons = new List<String>();
    /** AXF-139: consultative state, independent evidence, explicit tie / low-evidence flags. */
    @AuraEnabled
    public String state = ALT_CLS_MatchEvidence.STATE_CONSULTATIVE;
    @AuraEnabled
    public List<ALT_CLS_MatchEvidence.EvidenceView> evidence = new List<ALT_CLS_MatchEvidence.EvidenceView>();
    /**
     * AXF-140: residual left on this candidate once the source's available amount is applied to it.
     * `residual` above is the candidate's own available amount; this is what remains after the
     * allocation. Filled for every same-currency candidate, persisted and virtual alike, so a null
     * has one meaning only: the currencies differ and the remainder is unknown, never zero. Reported
     * as computed — no approved tolerance may turn a non-zero residual into zero.
     */
    @AuraEnabled
    public Decimal residualAfter;
    /**
     * AXF-135: available amount left on the source once this candidate's obligation is settled.
     * Distinct from `residualAfter`, which is what the obligation still needs: when the source is
     * larger than the obligation this stays non-zero and is the amount this flow does not split —
     * the multi-target need (AXF-30). The obligation is never grown to absorb it.
     */
    @AuraEnabled
    public Decimal sourceResidualAfter;
    /** AXF-140: indicative conversion evidence, present only when the currencies differ. */
    @AuraEnabled
    public ConversionView conversion;
    @AuraEnabled
    public Boolean tied = false;
    @AuraEnabled
    public Boolean lowEvidence = false;
    public Id fundingId;
    public Id holderId;
    public transient String signature;
  }

  /**
   * AXF-140: the conversion evidence of a candidate whose currency differs from the source's.
   * Display-only and derived from the approved indicative layer (AXF-92): no rate is ever invented,
   * the original amount and currency are never altered, and a quote that is stale, superseded by a
   * non-positive rate or absent leaves the converted amount empty instead of zero.
   */
  public class ConversionView {
    /** AXF-92 vocabulary: ESTIMATED | STALE | UNAVAILABLE (no usable rate at all). */
    @AuraEnabled
    public String state;
    @AuraEnabled
    public Decimal originalAmount;
    @AuraEnabled
    public String originalIso;
    /** Currency the candidate is compared against: the source fact's own currency. */
    @AuraEnabled
    public String reportingIso;
    @AuraEnabled
    public Decimal rate;
    @AuraEnabled
    public String provider;
    @AuraEnabled
    public Datetime effectiveAt;
    @AuraEnabled
    public Decimal convertedAmount;
  }

  public class SourceQuery {
    public Id accountId;
    public String sourceKind;
    public String term;
    public Integer pageNumber;
    public Integer pageSize;
  }

  public class CandidateQuery {
    public Id sourceId;
    public String sourceKind;
    public String term;
    public Integer pageNumber;
    public Integer pageSize;
  }

  public class SourcePage {
    @AuraEnabled
    public String policyVersion = POLICY_VERSION;
    @AuraEnabled
    public Integer pageNumber;
    @AuraEnabled
    public Integer pageSize;
    @AuraEnabled
    public Boolean hasMore = false;
    @AuraEnabled
    public Integer scannedCount = 0;
    @AuraEnabled
    public Integer excludedCount = 0;
    /** True when a kind had more rows than MAX_SCAN inside the window; narrow the search. */
    @AuraEnabled
    public Boolean scanTruncated = false;
    @AuraEnabled
    public Integer maxScan = MAX_SCAN;
    @AuraEnabled
    public List<SourceView> items = new List<SourceView>();
  }

  public class CandidatePage {
    @AuraEnabled
    public String policyVersion = POLICY_VERSION;
    @AuraEnabled
    public String matchingPolicy = ALT_CLS_MatchEvidence.MATCHING_POLICY;
    /**
     * Policy §3: the page itself stays the consultative baseline — it only offers candidates for
     * inspection and comparison and concludes nothing; the per-candidate state carries PARTIAL or
     * BLOCKED for each row.
     */
    @AuraEnabled
    public String state = ALT_CLS_MatchEvidence.STATE_CONSULTATIVE;
    @AuraEnabled
    public Datetime evidenceCutoff;
    @AuraEnabled
    public Integer tieCount = 0;
    @AuraEnabled
    public Integer lowEvidenceCount = 0;
    @AuraEnabled
    public SourceView source;
    @AuraEnabled
    public Decimal suggestedAmount;
    @AuraEnabled
    public Date suggestedDate;
    @AuraEnabled
    public Integer pageNumber;
    @AuraEnabled
    public Integer pageSize;
    @AuraEnabled
    public Boolean hasMore = false;
    @AuraEnabled
    public Boolean scanTruncated = false;
    @AuraEnabled
    public Integer maxScan = MAX_SCAN;
    @AuraEnabled
    public Integer excludedCount = 0;
    @AuraEnabled
    public Integer virtualCount = 0;
    @AuraEnabled
    public List<CandidateView> items = new List<CandidateView>();
  }

  public class ConfirmInput {
    public Id sourceId;
    public String sourceKind;
    public Decimal sourceVersion;
    public Id targetId;
    public Decimal targetVersion;
    public Decimal amount;
    public Date recognitionDate;
    /** Explicit review acknowledgement, required whenever amount/date differ from the suggestion. */
    public Boolean changesReviewed;
    /**
     * AXF-135: economic role declared by the caller — required, and never defaulted, inferred or
     * classified by the service. It is preserved in the canonical payload of the realization.
     */
    public String economicRole;
    public String operationKey;
  }

  public class ConfirmResult {
    @AuraEnabled
    public String policyVersion = POLICY_VERSION;
    @AuraEnabled
    public Id allocationId;
    @AuraEnabled
    public Id targetId;
    @AuraEnabled
    public Boolean replayed = false;
    @AuraEnabled
    public Boolean createdActualOnly = false;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public String currencyIso;
  }

  /** @description Capability plus the AXF-25 realization capability; neither grants record access. */
  public static void requireAccess() {
    if (
      !FeatureManagement.checkPermission(CP_LINK) ||
      !FeatureManagement.checkPermission('AXF_CanRealize')
    ) {
      throw new SourceLinkException('UNAVAILABLE');
    }
  }

  private static void check(Boolean valid, String code) {
    if (!valid) {
      throw new SourceLinkException(code);
    }
  }

  private static Date today() {
    return todayOverride == null ? Date.today() : todayOverride;
  }

  private static Integer pageSize(Integer requested) {
    return requested == null ||
      requested < 1
      ? DEFAULT_PAGE
      : Math.min(requested, MAX_PAGE);
  }

  private static Integer pageNumber(Integer requested) {
    check(requested == null || requested <= MAX_PAGE_NUMBER, 'INVALID');
    return requested == null || requested < 1 ? 1 : requested;
  }

  /** Authorized holders are resolved once per request; the context service is the authority. */
  private Set<Id> authorizedCache;
  private Set<Id> authorizedAccounts() {
    if (authorizedCache == null) {
      authorizedCache = new Set<Id>();
      for (
        AXF_CLS_AuthorizedContextService.ContextView context : AXF_CLS_AuthorizedContextService.listAuthorizedContexts()
      ) {
        authorizedCache.add(context.accountId);
      }
    }
    return authorizedCache;
  }

  // ---------------------------------------------------------------- sources

  /** @description Lists eligible facts of one authorized holder; ineligible rows are counted, never shown. */
  public SourcePage listSources(SourceQuery query) {
    requireAccess();
    check(query != null && query.accountId != null, 'INVALID');
    check(
      query.sourceKind == null || KINDS.contains(query.sourceKind),
      'INVALID_SOURCE'
    );
    SourcePage result = new SourcePage();
    result.pageNumber = pageNumber(query.pageNumber);
    result.pageSize = pageSize(query.pageSize);
    // Holder existence is disclosed only through the authorized context list.
    check(authorizedAccounts().contains(query.accountId), 'UNAVAILABLE');
    List<SourceView> views = new List<SourceView>();
    if (query.sourceKind == null || query.sourceKind == KIND_BANK) {
      views.addAll(truncate(bankSources(query.accountId, query.term), result));
    }
    if (query.sourceKind == null || query.sourceKind == KIND_CARD) {
      views.addAll(truncate(cardSources(query.accountId, query.term), result));
    }
    evaluate(views);
    List<SourceView> eligible = new List<SourceView>();
    for (SourceView view : views) {
      result.scannedCount++;
      if (view.eligible) {
        eligible.add(view);
      } else {
        result.excludedCount++;
      }
    }
    // Deterministic: date, amount, kind, id; independent of query interleaving.
    List<SourceKey> keys = new List<SourceKey>();
    for (SourceView view : eligible) {
      keys.add(new SourceKey(view));
    }
    keys.sort();
    Integer skip = (result.pageNumber - 1) * result.pageSize;
    for (Integer i = skip; i < keys.size() && i < skip + result.pageSize; i++) {
      result.items.add(keys[i].view);
    }
    result.hasMore = keys.size() > skip + result.pageSize;
    return result;
  }

  /** Each kind is read with a sentinel row; more than MAX_SCAN is reported, never hidden. */
  private static List<SourceView> truncate(
    List<SourceView> views,
    SourcePage page
  ) {
    if (views.size() > MAX_SCAN) {
      page.scanTruncated = true;
      views.remove(views.size() - 1);
    }
    return views;
  }

  private class SourceKey implements Comparable {
    public SourceView view;
    public SourceKey(SourceView view) {
      this.view = view;
    }
    public Integer compareTo(Object other) {
      SourceView b = ((SourceKey) other).view;
      if (view.factDate != b.factDate) {
        return view.factDate > b.factDate ? -1 : 1;
      }
      if (view.amount != b.amount) {
        return view.amount < b.amount ? -1 : 1;
      }
      if (view.sourceKind != b.sourceKind) {
        return view.sourceKind < b.sourceKind ? -1 : 1;
      }
      return String.valueOf(view.sourceId)
        .compareTo(String.valueOf(b.sourceId));
    }
  }

  private static String pattern(String term) {
    // Bound values treat escaped wildcards literally; the search never reaches the SOQL text.
    return ('%' +
    term.trim().replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_') +
    '%');
  }

  private List<SourceView> bankSources(Id accountId, String term) {
    Date floor = today().addYears(-1);
    String soql =
      'SELECT Id, AXF_BAT_MDR_BankAccount__c, AXF_BAT_NUM_Magnitude__c, AXF_BAT_TXT_CurrencyIsoCode__c,' +
      ' AXF_BAT_PKL_Direction__c, AXF_BAT_DAT_Date__c, AXF_BAT_TXT_Description__c, AXF_BAT_PKL_Source__c,' +
      ' AXF_BAT_TXT_ProviderCategory__c, AXF_BAT_EXI_SourceKey__c,' +
      ' AXF_BAT_PKL_Status__c, AXF_BAT_NUM_Version__c, AXF_BAT_MDR_BankAccount__r.AXF_BA_LKP_Account__c,' +
      ' AXF_BAT_MDR_BankAccount__r.AXF_BA_PKL_AvailabilityState__c, AXF_BAT_MDR_BankAccount__r.AXF_BA_TXT_InstitutionName__c,' +
      ' AXF_BAT_MDR_BankAccount__r.AXF_BA_TXT_NumberMasked__c' +
      ' FROM AXF_OBJ_BankAccountTransaction__c' +
      ' WHERE AXF_BAT_MDR_BankAccount__r.AXF_BA_LKP_Account__c = :accountId' +
      ' AND AXF_BAT_PKL_Status__c = \'POSTED\' AND AXF_BAT_DAT_Date__c >= :floor' +
      (String.isBlank(term)
        ? ''
        : ' AND AXF_BAT_TXT_Description__c LIKE :pattern') +
      ' ORDER BY AXF_BAT_DAT_Date__c DESC, AXF_BAT_NUM_Magnitude__c ASC, Id ASC LIMIT :scan';
    List<SourceView> result = new List<SourceView>();
    for (
      SObject row : Database.queryWithBinds(
        soql,
        new Map<String, Object>{
          'accountId' => accountId,
          'floor' => floor,
          'pattern' => String.isBlank(term) ? null : pattern(term),
          'scan' => MAX_SCAN + 1
        },
        AccessLevel.USER_MODE
      )
    ) {
      result.add(view((AXF_OBJ_BankAccountTransaction__c) row));
    }
    return result;
  }

  private List<SourceView> cardSources(Id accountId, String term) {
    Date floor = today().addYears(-1);
    String soql =
      'SELECT Id, AXF_CCT_MDR_CreditCard__c, AXF_CCT_NUM_Magnitude__c, AXF_CCT_TXT_CurrencyIsoCode__c,' +
      ' AXF_CCT_PKL_Direction__c, AXF_CCT_DAT_Date__c, AXF_CCT_TXT_Description__c, AXF_CCT_PKL_Source__c,' +
      ' AXF_CCT_TXT_ProviderCategory__c, AXF_CCT_EXI_SourceKey__c,' +
      ' AXF_CCT_PKL_Status__c, AXF_CCT_NUM_Version__c, AXF_CCT_MDR_CreditCard__r.AXF_CC_LKP_Account__c,' +
      ' AXF_CCT_MDR_CreditCard__r.AXF_CC_PKL_AvailabilityState__c, AXF_CCT_MDR_CreditCard__r.AXF_CC_TXT_InstitutionName__c,' +
      ' AXF_CCT_MDR_CreditCard__r.AXF_CC_TXT_LastFourMasked__c' +
      ' FROM AXF_OBJ_CreditCardTransaction__c' +
      ' WHERE AXF_CCT_MDR_CreditCard__r.AXF_CC_LKP_Account__c = :accountId' +
      ' AND AXF_CCT_PKL_Status__c = \'POSTED\' AND AXF_CCT_DAT_Date__c >= :floor' +
      (String.isBlank(term)
        ? ''
        : ' AND AXF_CCT_TXT_Description__c LIKE :pattern') +
      ' ORDER BY AXF_CCT_DAT_Date__c DESC, AXF_CCT_NUM_Magnitude__c ASC, Id ASC LIMIT :scan';
    List<SourceView> result = new List<SourceView>();
    for (
      SObject row : Database.queryWithBinds(
        soql,
        new Map<String, Object>{
          'accountId' => accountId,
          'floor' => floor,
          'pattern' => String.isBlank(term) ? null : pattern(term),
          'scan' => MAX_SCAN + 1
        },
        AccessLevel.USER_MODE
      )
    ) {
      result.add(view((AXF_OBJ_CreditCardTransaction__c) row));
    }
    return result;
  }

  private static SourceView view(AXF_OBJ_BankAccountTransaction__c row) {
    SourceView v = new SourceView();
    v.sourceId = row.Id;
    v.sourceKind = KIND_BANK;
    v.fundingId = row.AXF_BAT_MDR_BankAccount__c;
    v.accountId = row.AXF_BAT_MDR_BankAccount__r?.AXF_BA_LKP_Account__c;
    v.fundingLabel = label(
      row.AXF_BAT_MDR_BankAccount__r?.AXF_BA_TXT_InstitutionName__c,
      row.AXF_BAT_MDR_BankAccount__r?.AXF_BA_TXT_NumberMasked__c
    );
    v.origin = row.AXF_BAT_PKL_Source__c;
    v.amount = row.AXF_BAT_NUM_Magnitude__c;
    v.currencyIso = row.AXF_BAT_TXT_CurrencyIsoCode__c;
    v.direction = row.AXF_BAT_PKL_Direction__c;
    v.factDate = row.AXF_BAT_DAT_Date__c;
    v.description = row.AXF_BAT_TXT_Description__c;
    v.category = row.AXF_BAT_TXT_ProviderCategory__c;
    v.sourceKey = row.AXF_BAT_EXI_SourceKey__c;
    v.version = row.AXF_BAT_NUM_Version__c == null
      ? 0
      : row.AXF_BAT_NUM_Version__c;
    if (row.AXF_BAT_PKL_Status__c != 'POSTED') {
      v.reasons.add('NOT_POSTED');
    }
    if (
      row.AXF_BAT_MDR_BankAccount__r?.AXF_BA_PKL_AvailabilityState__c !=
      'AVAILABLE'
    ) {
      v.reasons.add('FUNDING_NOT_AVAILABLE');
    }
    return v;
  }

  private static SourceView view(AXF_OBJ_CreditCardTransaction__c row) {
    SourceView v = new SourceView();
    v.sourceId = row.Id;
    v.sourceKind = KIND_CARD;
    v.fundingId = row.AXF_CCT_MDR_CreditCard__c;
    v.accountId = row.AXF_CCT_MDR_CreditCard__r?.AXF_CC_LKP_Account__c;
    v.fundingLabel = label(
      row.AXF_CCT_MDR_CreditCard__r?.AXF_CC_TXT_InstitutionName__c,
      row.AXF_CCT_MDR_CreditCard__r?.AXF_CC_TXT_LastFourMasked__c
    );
    v.origin = row.AXF_CCT_PKL_Source__c;
    v.amount = row.AXF_CCT_NUM_Magnitude__c;
    v.currencyIso = row.AXF_CCT_TXT_CurrencyIsoCode__c;
    v.direction = row.AXF_CCT_PKL_Direction__c;
    v.factDate = row.AXF_CCT_DAT_Date__c;
    v.description = row.AXF_CCT_TXT_Description__c;
    v.category = row.AXF_CCT_TXT_ProviderCategory__c;
    v.sourceKey = row.AXF_CCT_EXI_SourceKey__c;
    v.version = row.AXF_CCT_NUM_Version__c == null
      ? 0
      : row.AXF_CCT_NUM_Version__c;
    if (row.AXF_CCT_PKL_Status__c != 'POSTED') {
      v.reasons.add('NOT_POSTED');
    }
    if (
      row.AXF_CCT_MDR_CreditCard__r?.AXF_CC_PKL_AvailabilityState__c !=
      'AVAILABLE'
    ) {
      v.reasons.add('FUNDING_NOT_AVAILABLE');
    }
    return v;
  }

  private static String label(String institution, String masked) {
    String result = String.isBlank(institution) ? '' : institution.trim();
    if (!String.isBlank(masked)) {
      result += (result == '' ? '' : ' ') + masked.trim();
    }
    return result;
  }

  /** Completes eligibility: holder authorization, fact data, open reviews and residual capacity. */
  private void evaluate(List<SourceView> views) {
    if (views.isEmpty()) {
      return;
    }
    Set<Id> authorized = authorizedAccounts();
    Set<Id> ids = new Set<Id>();
    for (SourceView v : views) {
      ids.add(v.sourceId);
    }
    Set<Id> reviewed = new Conservation().openReviews(ids);
    Map<Id, Decimal> nets = new Map<Id, Decimal>();
    Set<Id> unverified = new Set<Id>();
    netBySource(ids, nets, unverified);
    for (SourceView v : views) {
      if (v.accountId == null || !authorized.contains(v.accountId)) {
        v.reasons.add('NOT_AUTHORIZED');
      }
      if (
        v.origin == null ||
        !SOURCES.contains(v.origin) ||
        v.amount == null ||
        v.amount <= 0 ||
        v.factDate == null ||
        v.currencyIso == null ||
        !Pattern.matches('[A-Z]{3}', v.currencyIso) ||
        !DIRECTIONS.contains(v.direction)
      ) {
        v.reasons.add('INVALID_SOURCE_DATA');
      }
      if (reviewed.contains(v.sourceId)) {
        v.reasons.add('REVIEW_OPEN');
      }
      if (unverified.contains(v.sourceId)) {
        v.reasons.add('ALLOCATIONS_UNVERIFIED');
        v.residual = null;
      } else if (v.amount != null) {
        Decimal net = nets.containsKey(v.sourceId) ? nets.get(v.sourceId) : 0;
        v.residual = v.amount - net;
        if (v.residual <= 0) {
          v.reasons.add('SOURCE_EXHAUSTED');
        }
      }
      v.eligible = v.reasons.isEmpty();
    }
  }

  /** User-visible net per source; a source whose allocation count differs from the private count is unverified. */
  private void netBySource(
    Set<Id> ids,
    Map<Id, Decimal> nets,
    Set<Id> unverified
  ) {
    Map<Id, Integer> visibleCounts = new Map<Id, Integer>();
    List<AXF_OBJ_ReconciliationAllocation__c> visibleRows = [
      SELECT
        AXF_RA_LKP_BankTransaction__c,
        AXF_RA_LKP_CardTransaction__c,
        AXF_RA_PKL_Kind__c,
        AXF_RA_NUM_Magnitude__c
      FROM AXF_OBJ_ReconciliationAllocation__c
      WHERE
        AXF_RA_LKP_BankTransaction__c IN :ids
        OR AXF_RA_LKP_CardTransaction__c IN :ids
      WITH USER_MODE
      LIMIT :MAX_ALLOCATION_ROWS
    ];
    Map<Id, Integer> privateCounts = new Conservation().countBySource(ids);
    if (visibleRows.size() >= MAX_ALLOCATION_ROWS || privateCounts == null) {
      // A truncated read can coincide by accident: everything scanned is unverified.
      unverified.addAll(ids);
      return;
    }
    for (AXF_OBJ_ReconciliationAllocation__c row : visibleRows) {
      Id key = row.AXF_RA_LKP_BankTransaction__c != null
        ? row.AXF_RA_LKP_BankTransaction__c
        : row.AXF_RA_LKP_CardTransaction__c;
      Decimal sign = row.AXF_RA_PKL_Kind__c == 'REVERSAL' ? -1 : 1;
      nets.put(
        key,
        (nets.containsKey(key) ? nets.get(key) : 0) +
        sign * row.AXF_RA_NUM_Magnitude__c
      );
      visibleCounts.put(
        key,
        (visibleCounts.containsKey(key) ? visibleCounts.get(key) : 0) + 1
      );
    }
    for (Id id : ids) {
      Integer visible = visibleCounts.containsKey(id)
        ? visibleCounts.get(id)
        : 0;
      Integer total = privateCounts.containsKey(id) ? privateCounts.get(id) : 0;
      if (visible != total) {
        unverified.add(id);
      }
    }
  }

  /** @description Reads and evaluates one fact; unauthorized or missing facts are indistinguishable. */
  public SourceView readSource(Id sourceId, String sourceKind) {
    requireAccess();
    check(sourceId != null && KINDS.contains(sourceKind), 'INVALID_SOURCE');
    List<SourceView> views = new List<SourceView>();
    if (sourceKind == KIND_BANK) {
      for (AXF_OBJ_BankAccountTransaction__c row : [
        SELECT
          Id,
          AXF_BAT_MDR_BankAccount__c,
          AXF_BAT_NUM_Magnitude__c,
          AXF_BAT_TXT_CurrencyIsoCode__c,
          AXF_BAT_PKL_Direction__c,
          AXF_BAT_DAT_Date__c,
          AXF_BAT_TXT_Description__c,
          AXF_BAT_PKL_Source__c,
          AXF_BAT_TXT_ProviderCategory__c,
          AXF_BAT_EXI_SourceKey__c,
          AXF_BAT_PKL_Status__c,
          AXF_BAT_NUM_Version__c,
          AXF_BAT_MDR_BankAccount__r.AXF_BA_LKP_Account__c,
          AXF_BAT_MDR_BankAccount__r.AXF_BA_PKL_AvailabilityState__c,
          AXF_BAT_MDR_BankAccount__r.AXF_BA_TXT_InstitutionName__c,
          AXF_BAT_MDR_BankAccount__r.AXF_BA_TXT_NumberMasked__c
        FROM AXF_OBJ_BankAccountTransaction__c
        WHERE Id = :sourceId
        WITH USER_MODE
      ]) {
        views.add(view(row));
      }
    } else {
      for (AXF_OBJ_CreditCardTransaction__c row : [
        SELECT
          Id,
          AXF_CCT_MDR_CreditCard__c,
          AXF_CCT_NUM_Magnitude__c,
          AXF_CCT_TXT_CurrencyIsoCode__c,
          AXF_CCT_PKL_Direction__c,
          AXF_CCT_DAT_Date__c,
          AXF_CCT_TXT_Description__c,
          AXF_CCT_PKL_Source__c,
          AXF_CCT_TXT_ProviderCategory__c,
          AXF_CCT_EXI_SourceKey__c,
          AXF_CCT_PKL_Status__c,
          AXF_CCT_NUM_Version__c,
          AXF_CCT_MDR_CreditCard__r.AXF_CC_LKP_Account__c,
          AXF_CCT_MDR_CreditCard__r.AXF_CC_PKL_AvailabilityState__c,
          AXF_CCT_MDR_CreditCard__r.AXF_CC_TXT_InstitutionName__c,
          AXF_CCT_MDR_CreditCard__r.AXF_CC_TXT_LastFourMasked__c
        FROM AXF_OBJ_CreditCardTransaction__c
        WHERE Id = :sourceId
        WITH USER_MODE
      ]) {
        views.add(view(row));
      }
    }
    check(views.size() == 1, 'UNAVAILABLE');
    evaluate(views);
    check(!views[0].reasons.contains('NOT_AUTHORIZED'), 'UNAVAILABLE');
    return views[0];
  }

  // ------------------------------------------------------------- candidates

  /** @description Persisted forecasts (linkable) and virtual projection lines (materialization pending, AXF-136). */
  public CandidatePage listCandidates(CandidateQuery query) {
    requireAccess();
    check(query != null, 'INVALID');
    CandidatePage result = new CandidatePage();
    result.pageNumber = pageNumber(query.pageNumber);
    result.pageSize = pageSize(query.pageSize);
    result.source = readSource(query.sourceId, query.sourceKind);
    result.suggestedDate = result.source.factDate;
    List<CandidateView> all = new List<CandidateView>();
    if (result.source.eligible) {
      all.addAll(persistedCandidates(result.source, query.term, result));
      all.addAll(virtualCandidates(result.source, query.term, result));
    }
    result.evidenceCutoff = System.now();
    List<ALT_CLS_MatchEvidence.OrderKey> keys = new List<ALT_CLS_MatchEvidence.OrderKey>();
    Map<String, Integer> signatures = new Map<String, Integer>();
    for (CandidateView c : all) {
      c.evidence = ALT_CLS_MatchEvidence.evaluate(side(result.source), side(c));
      c.lowEvidence = ALT_CLS_MatchEvidence.lowEvidence(c.evidence);
      c.signature = ALT_CLS_MatchEvidence.signature(c.evidence);
      signatures.put(
        c.signature,
        (signatures.containsKey(c.signature)
          ? signatures.get(c.signature)
          : 0) + 1
      );
      keys.add(
        new ALT_CLS_MatchEvidence.OrderKey(
          c.evidence,
          c.persisted ? 0 : 1,
          c.persisted
            ? String.valueOf(c.targetId)
            : String.valueOf(c.scheduleId) +
              '#' +
              String.valueOf(c.sequence == null ? 0 : c.sequence)
                .leftPad(6, '0'),
          c
        )
      );
    }
    for (CandidateView c : all) {
      // A tie is explicit: identical evidence (relations and exact deltas) on every
      // feature never selects a winner.
      c.tied = signatures.get(c.signature) > 1;
      if (c.tied) {
        result.tieCount++;
      }
      if (c.lowEvidence) {
        result.lowEvidenceCount++;
      }
    }
    keys.sort();
    Integer skip = (result.pageNumber - 1) * result.pageSize;
    for (Integer i = skip; i < keys.size() && i < skip + result.pageSize; i++) {
      result.items.add((CandidateView) keys[i].payload);
    }
    result.hasMore = keys.size() > skip + result.pageSize;
    resolveConversions(result.source, result.items);
    result.suggestedAmount = result.source.eligible
      ? result.source.residual
      : null;
    return result;
  }

  /**
   * AXF-140: resolves the indicative conversion evidence of the candidates shown on the page. One
   * read per request for every currency involved, never one per row; the original amount and its
   * currency are never altered and no rate is invented.
   */
  private void resolveConversions(
    SourceView source,
    List<CandidateView> items
  ) {
    Set<String> isos = new Set<String>();
    for (CandidateView c : items) {
      if (c.currencyIso != null && c.currencyIso != source.currencyIso) {
        isos.add(c.currencyIso);
      }
    }
    if (isos.isEmpty()) {
      return;
    }
    Map<String, AXF_OBJ_ExchangeRate__c> quotes = indicativeQuotes(
      source.currencyIso,
      isos,
      quoteSide(source.direction)
    );
    for (CandidateView c : items) {
      if (c.currencyIso == null || c.currencyIso == source.currencyIso) {
        continue;
      }
      c.conversion = convert(
        quotes.get(c.currencyIso),
        c.currencyIso,
        source.currencyIso,
        c.amount
      );
      if (
        c.conversion.state !=
        ALT_CLS_IndicativeEquivalenceService.STATE_ESTIMATED
      ) {
        // Without a usable quote the pair has no material FX evidence: confirmation is blocked.
        c.reasons.add('MISSING_MATERIAL_FX');
      }
    }
  }

  /** Material FX evidence for one pair, or null when the pair has none: a fresh usable quote. */
  private static ConversionView materialRate(
    String originalIso,
    String reportingIso,
    String side
  ) {
    Map<String, AXF_OBJ_ExchangeRate__c> quotes = indicativeQuotes(
      reportingIso,
      new Set<String>{ originalIso },
      side
    );
    ConversionView view = convert(
      quotes.get(originalIso),
      originalIso,
      reportingIso,
      null
    );
    return view.state == ALT_CLS_IndicativeEquivalenceService.STATE_ESTIMATED
      ? view
      : null;
  }

  /**
   * AXF-140: the rate side of the approved FX layer, derived exactly as ALT_CLS_RealizationService
   * derives it for the same purpose (recognize()): an outflow is converted at the SELL quote and an
   * inflow at the BUY quote, from the direction the source fact already carries. No side is invented
   * here and none is defaulted; the direction is validated before this is reached.
   */
  private static String quoteSide(String direction) {
    return direction == 'DEBIT' ? 'SELL' : 'BUY';
  }

  /**
   * Fresh usable quote → ESTIMATED; only an older one → STALE; no usable rate at all → UNAVAILABLE
   * (never zero). A newest quote whose rate is not positive leaves the pair unusable: no older,
   * superseded quote and no invented parity stands in for it.
   */
  private static ConversionView convert(
    AXF_OBJ_ExchangeRate__c quote,
    String originalIso,
    String reportingIso,
    Decimal amount
  ) {
    ConversionView view = new ConversionView();
    view.originalIso = originalIso;
    // The original amount is a fact of the candidate: it travels whatever the quote state is.
    view.originalAmount = amount;
    view.reportingIso = reportingIso;
    if (
      quote == null ||
      quote.AXF_EXR_NUM_Rate__c == null ||
      quote.AXF_EXR_NUM_Rate__c <= 0
    ) {
      view.state = ALT_CLS_IndicativeEquivalenceService.STATE_UNAVAILABLE;
      return view;
    }
    view.rate = quote.AXF_EXR_NUM_Rate__c;
    view.provider = quote.AXF_EXR_TXT_Provider__c;
    view.effectiveAt = quote.AXF_EXR_DT_EffectiveDateTime__c;
    if (
      quote.AXF_EXR_DT_EffectiveDateTime__c <
      System.now()
        .addDays(-ALT_CLS_IndicativeEquivalenceService.QUOTE_MAX_AGE_DAYS)
    ) {
      view.state = ALT_CLS_IndicativeEquivalenceService.STATE_STALE;
      return view;
    }
    view.state = ALT_CLS_IndicativeEquivalenceService.STATE_ESTIMATED;
    view.convertedAmount = amount == null
      ? null
      : (amount * view.rate)
          .setScale(
            ALT_CLS_IndicativeEquivalenceService.DISPLAY_SCALE,
            System.RoundingMode.HALF_UP
          );
    return view;
  }

  /**
   * Newest indicative quote per base currency for one reporting currency, in a single read: the
   * approved provider, the approved rate side (AXF-59/24) and a deterministic order. The newest row
   * of the pair decides, even when its rate is not usable — an older, superseded quote is never
   * substituted for it, and a tie on the effective instant is broken by record identity.
   */
  private static Map<String, AXF_OBJ_ExchangeRate__c> indicativeQuotes(
    String reportingIso,
    Set<String> originalIsos,
    String side
  ) {
    // The reference quote is read exactly as the approved indicative layer does (AXF-92): under
    // sharing, not under field-level security, because the quote is shared reference data and its
    // fields are not granted to every capability holder.
    String provider = ALT_CLS_IndicativeEquivalenceService.PROVIDER_BCB_PTAX;
    Datetime oldest = System.now()
      .addDays(-ALT_CLS_IndicativeEquivalenceService.QUOTE_MAX_AGE_DAYS * 2);
    Map<String, AXF_OBJ_ExchangeRate__c> result = new Map<String, AXF_OBJ_ExchangeRate__c>();
    for (AXF_OBJ_ExchangeRate__c row : [
      SELECT
        AXF_EXR_TXT_BaseCurrency__c,
        AXF_EXR_NUM_Rate__c,
        AXF_EXR_TXT_Provider__c,
        AXF_EXR_DT_EffectiveDateTime__c
      FROM AXF_OBJ_ExchangeRate__c
      WHERE
        AXF_EXR_TXT_BaseCurrency__c IN :originalIsos
        AND AXF_EXR_TXT_QuoteCurrency__c = :reportingIso
        AND AXF_EXR_TXT_Provider__c = :provider
        AND AXF_EXR_PKL_Side__c = :side
        AND AXF_EXR_DT_EffectiveDateTime__c >= :oldest
      ORDER BY AXF_EXR_DT_EffectiveDateTime__c DESC, Id ASC
    ]) {
      // Newest first, record identity as the deterministic tie-break: the first row of each base
      // currency is its latest quote.
      if (!result.containsKey(row.AXF_EXR_TXT_BaseCurrency__c)) {
        result.put(row.AXF_EXR_TXT_BaseCurrency__c, row);
      }
    }
    return result;
  }

  /**
   * AXF-140 (AC-3): withholding is an authorization fact, never the presence of a value. The fact is
   * read through the authorized-holder gate, so its external identity is a displayed fact — the
   * policy's first presentation criterion; a side whose holder is not authorized carries it
   * withheld. The raw provider key still never travels as a field (`SourceView.sourceKey` is
   * transient): the identity travels only as the evidence fact, and only when nothing is withheld.
   */
  private ALT_CLS_MatchEvidence.Side side(SourceView source) {
    ALT_CLS_MatchEvidence.Side result = new ALT_CLS_MatchEvidence.Side();
    // The fact's own identity: origin + provider key. Forecasts carry no external identity in v1.
    result.externalIdentity = source.sourceKey == null
      ? null
      : source.origin + ':' + source.sourceKey;
    result.externalIdentityRedacted = !authorizedAccounts()
      .contains(source.accountId);
    result.sourceIdentity = source.fundingId;
    result.holderId = source.accountId;
    result.currencyIso = source.currencyIso;
    result.amount = source.amount;
    result.residual = source.residual;
    result.onDate = source.factDate;
    result.description = source.description;
    result.category = source.category;
    return result;
  }

  /** The same authorization fact on the candidate side: absent identity stays UNKNOWN there too. */
  private ALT_CLS_MatchEvidence.Side side(CandidateView candidate) {
    ALT_CLS_MatchEvidence.Side result = new ALT_CLS_MatchEvidence.Side();
    result.externalIdentityRedacted = !authorizedAccounts()
      .contains(candidate.holderId);
    result.sourceIdentity = candidate.fundingId;
    result.holderId = candidate.holderId;
    result.currencyIso = candidate.currencyIso;
    result.amount = candidate.amount;
    result.residual = candidate.residual;
    result.onDate = candidate.dueDate;
    result.description = candidate.description;
    result.category = candidate.category;
    return result;
  }

  private static String fundingField(String kind) {
    return kind == KIND_BANK
      ? 'AXF_FTX_LKP_BankAccount__c'
      : 'AXF_FTX_LKP_CreditCard__c';
  }

  private static String otherFundingField(String kind) {
    return kind == KIND_BANK
      ? 'AXF_FTX_LKP_CreditCard__c'
      : 'AXF_FTX_LKP_BankAccount__c';
  }

  /** One candidate scan window; the sentinel row past MAX_SCAN is dropped and reported, never hidden. */
  private static List<AXF_OBJ_FinancialTransaction__c> scan(
    String soql,
    Map<String, Object> binds,
    CandidatePage page
  ) {
    List<AXF_OBJ_FinancialTransaction__c> rows = (List<AXF_OBJ_FinancialTransaction__c>) Database.queryWithBinds(
      soql,
      binds,
      AccessLevel.USER_MODE
    );
    if (rows.size() > MAX_SCAN) {
      page.scanTruncated = true;
      rows.remove(rows.size() - 1);
    }
    return rows;
  }

  private List<CandidateView> persistedCandidates(
    SourceView source,
    String term,
    CandidatePage page
  ) {
    String base =
      'SELECT Id, AXF_FTX_NUM_Magnitude__c, AXF_FTX_TXT_CurrencyIsoCode__c, AXF_FTX_PKL_Direction__c,' +
      ' AXF_FTX_DAT_DueDate__c, AXF_FTX_DAT_PurchaseDate__c, AXF_FTX_TXT_Description__c, AXF_FTX_TXT_UserCategory__c,' +
      ' AXF_FTX_PKL_Status__c, AXF_FTX_NUM_Version__c, AXF_FTX_PKL_ScheduleState__c, AXF_FTX_LKP_Schedule__c,' +
      ' AXF_FTX_NUM_Sequence__c, AXF_FTX_LKP_BankAccount__c, AXF_FTX_LKP_CreditCard__c, AXF_FTX_LKP_Account__c' +
      ' FROM AXF_OBJ_FinancialTransaction__c' +
      ' WHERE AXF_FTX_LKP_Account__c = :accountId AND AXF_FTX_PKL_PlanKind__c = \'PLANNED\'' +
      ' AND AXF_FTX_PKL_Direction__c = :direction' +
      ' AND (AXF_FTX_PKL_ScheduleState__c = NULL OR AXF_FTX_PKL_ScheduleState__c != \'CANCELLED\')' +
      ' AND (' +
      fundingField(source.sourceKind) +
      ' = NULL OR ' +
      fundingField(source.sourceKind) +
      ' = :fundingId) AND ' +
      otherFundingField(source.sourceKind) +
      ' = NULL' +
      (String.isBlank(term)
        ? ''
        : ' AND AXF_FTX_TXT_Description__c LIKE :pattern');
    String tail =
      ' ORDER BY AXF_FTX_DAT_DueDate__c ASC NULLS LAST, AXF_FTX_DAT_PurchaseDate__c ASC, AXF_FTX_NUM_Magnitude__c ASC, Id ASC' +
      ' LIMIT :scan';
    Map<String, Object> binds = new Map<String, Object>{
      'accountId' => source.accountId,
      'direction' => source.direction,
      'fundingId' => source.fundingId,
      'pattern' => String.isBlank(term) ? null : pattern(term),
      'scan' => MAX_SCAN + 1
    };
    // AXF-140: a candidate in another currency is BLOCKED and never selectable, so it must not
    // consume the window that decides which linkable forecasts are seen at all. The two groups are
    // scanned with a window of their own — same currency first, everything else second — and both
    // go through the same in-memory exclusion below; a truncation in either one is reported.
    Map<String, Object> linkableBinds = new Map<String, Object>(binds);
    linkableBinds.put('iso', source.currencyIso);
    List<AXF_OBJ_FinancialTransaction__c> rows = scan(
      base + ' AND AXF_FTX_TXT_CurrencyIsoCode__c = :iso' + tail,
      linkableBinds,
      page
    );
    Map<String, Object> blockedBinds = new Map<String, Object>(binds);
    blockedBinds.put('iso', source.currencyIso);
    rows.addAll(
      scan(
        base +
          ' AND (AXF_FTX_TXT_CurrencyIsoCode__c = NULL OR AXF_FTX_TXT_CurrencyIsoCode__c != :iso)' +
          tail,
        blockedBinds,
        page
      )
    );
    Map<Id, Decimal> nets = new Map<Id, Decimal>();
    Set<Id> unverified = new Set<Id>();
    netByTarget(
      new Map<Id, AXF_OBJ_FinancialTransaction__c>(rows).keySet(),
      nets,
      unverified
    );
    List<CandidateView> result = new List<CandidateView>();
    for (AXF_OBJ_FinancialTransaction__c row : rows) {
      if (unverified.contains(row.Id)) {
        page.excludedCount++;
        continue;
      }
      Decimal net = nets.containsKey(row.Id) ? nets.get(row.Id) : 0;
      Decimal residual = row.AXF_FTX_NUM_Magnitude__c == null
        ? 0
        : row.AXF_FTX_NUM_Magnitude__c - net;
      if (residual <= 0) {
        page.excludedCount++;
        continue;
      }
      CandidateView c = new CandidateView();
      c.targetId = row.Id;
      c.scheduleId = row.AXF_FTX_LKP_Schedule__c;
      c.sequence = row.AXF_FTX_NUM_Sequence__c == null
        ? null
        : row.AXF_FTX_NUM_Sequence__c.intValue();
      c.persisted = true;
      c.amount = row.AXF_FTX_NUM_Magnitude__c;
      c.residual = residual;
      c.currencyIso = row.AXF_FTX_TXT_CurrencyIsoCode__c;
      c.direction = row.AXF_FTX_PKL_Direction__c;
      c.dueDate = row.AXF_FTX_DAT_DueDate__c == null
        ? row.AXF_FTX_DAT_PurchaseDate__c
        : row.AXF_FTX_DAT_DueDate__c;
      c.description = row.AXF_FTX_TXT_Description__c;
      c.category = row.AXF_FTX_TXT_UserCategory__c;
      c.status = row.AXF_FTX_PKL_Status__c;
      c.version = row.AXF_FTX_NUM_Version__c == null
        ? 0
        : row.AXF_FTX_NUM_Version__c;
      if (c.currencyIso != source.currencyIso) {
        // AXF-140: a candidate in another currency is shown with its own original, available and
        // currency, but completion requires exact currency arithmetic (policy §3) and material FX
        // evidence (policy §2): it stays BLOCKED and is never selectable, so no draft is offered
        // for an allocation that cannot be confirmed. The residual is left unknown, never zero.
        c.state = ALT_CLS_MatchEvidence.STATE_BLOCKED;
        c.reasons.add('CURRENCY_MISMATCH');
      } else {
        // Policy §3: a non-zero remainder stays explicit — no approved tolerance exists to zero it —
        // and it leaves the candidate PARTIAL, where the user may still add or edit draft
        // allocations. A candidate the source extinguishes exactly stays CONSULTATIVE.
        c.residualAfter = residual - Math.min(source.residual, residual);
        // AXF-135: the same amount seen from the source: what this obligation cannot absorb is a
        // multi-target need and is never met by increasing the obligation.
        c.sourceResidualAfter =
          source.residual - Math.min(source.residual, residual);
        c.linkable = true;
        if (c.residualAfter > 0) {
          c.state = ALT_CLS_MatchEvidence.STATE_PARTIAL;
        }
      }
      c.fundingId = (Id) row.get(fundingField(source.sourceKind));
      c.holderId = row.AXF_FTX_LKP_Account__c; // observed, not copied from the source
      result.add(c);
    }
    return result;
  }

  private void netByTarget(
    Set<Id> ids,
    Map<Id, Decimal> nets,
    Set<Id> unverified
  ) {
    if (ids.isEmpty()) {
      return;
    }
    Map<Id, Integer> visibleCounts = new Map<Id, Integer>();
    List<AXF_OBJ_ReconciliationAllocation__c> visibleRows = [
      SELECT
        AXF_RA_LKP_FinancialTransaction__c,
        AXF_RA_PKL_Kind__c,
        AXF_RA_NUM_Magnitude__c
      FROM AXF_OBJ_ReconciliationAllocation__c
      WHERE AXF_RA_LKP_FinancialTransaction__c IN :ids
      WITH USER_MODE
      LIMIT :MAX_ALLOCATION_ROWS
    ];
    Map<Id, Integer> privateCounts = new Conservation().countByTarget(ids);
    if (visibleRows.size() >= MAX_ALLOCATION_ROWS || privateCounts == null) {
      unverified.addAll(ids);
      return;
    }
    for (AXF_OBJ_ReconciliationAllocation__c row : visibleRows) {
      Id key = row.AXF_RA_LKP_FinancialTransaction__c;
      Decimal sign = row.AXF_RA_PKL_Kind__c == 'REVERSAL' ? -1 : 1;
      nets.put(
        key,
        (nets.containsKey(key) ? nets.get(key) : 0) +
        sign * row.AXF_RA_NUM_Magnitude__c
      );
      visibleCounts.put(
        key,
        (visibleCounts.containsKey(key) ? visibleCounts.get(key) : 0) + 1
      );
    }
    for (Id id : ids) {
      Integer visible = visibleCounts.containsKey(id)
        ? visibleCounts.get(id)
        : 0;
      Integer total = privateCounts.containsKey(id) ? privateCounts.get(id) : 0;
      if (visible != total) {
        unverified.add(id);
      }
    }
  }

  private List<CandidateView> virtualCandidates(
    SourceView source,
    String term,
    CandidatePage page
  ) {
    List<CandidateView> result = new List<CandidateView>();
    if (!String.isBlank(term)) {
      // Virtual lines carry no description; a manual search targets persisted forecasts only.
      return result;
    }
    Integer scheduleCap = MAX_SCHEDULES + 1;
    List<AXF_OBJ_FinancialSchedule__c> schedules = [
      SELECT Id, Name, AXF_FSC_LKP_Account__c
      FROM AXF_OBJ_FinancialSchedule__c
      WHERE
        AXF_FSC_LKP_Account__c = :source.accountId
        AND AXF_FSC_PKL_State__c = 'ACTIVE'
        AND AXF_FSC_TXT_CurrencyIsoCode__c = :source.currencyIso
        AND AXF_FSC_PKL_Direction__c = :source.direction
      WITH USER_MODE
      ORDER BY Id
      LIMIT :scheduleCap
    ];
    if (schedules.size() > MAX_SCHEDULES) {
      page.scanTruncated = true;
      schedules.remove(schedules.size() - 1);
    }
    for (AXF_OBJ_FinancialSchedule__c schedule : schedules) {
      ALT_CLS_ScheduleProjection.ProjectionInput request = new ALT_CLS_ScheduleProjection.ProjectionInput();
      request.scheduleId = schedule.Id;
      request.asOfDate = today();
      ALT_CLS_ScheduleProjection.ProjectionResult projection = ALT_CLS_FinancialScheduleService.readProjection(
        request
      );
      if (projection.outcome != ALT_CLS_ScheduleProjection.OUTCOME_OK) {
        continue;
      }
      for (ALT_CLS_ScheduleProjection.OccurrenceLine line : projection.lines) {
        if (line.persisted == true) {
          continue;
        }
        if (result.size() >= MAX_VIRTUAL) {
          page.scanTruncated = true;
          break;
        }
        CandidateView c = new CandidateView();
        c.scheduleId = schedule.Id;
        c.sequence = line.sequence;
        c.persisted = false;
        c.amount = line.amount;
        c.residual = line.amount;
        // AXF-140: the same remainder fact as a persisted candidate, so the cell never renders
        // nothing for a projected line and null keeps its single meaning — another currency, where
        // the remainder is unknown and never zero.
        c.residualAfter = line.amount == null
          ? null
          : line.amount - Math.min(source.residual, line.amount);
        // AXF-135: the source side of the same remainder, so a projected occurrence states what is
        // left for another target too (unknown, never zero, when the currencies differ).
        c.sourceResidualAfter = line.amount == null
          ? null
          : source.residual - Math.min(source.residual, line.amount);
        c.currencyIso = source.currencyIso;
        c.direction = source.direction;
        c.dueDate = line.effectiveDueDate == null
          ? line.nominalDueDate
          : line.effectiveDueDate;
        c.description = schedule.Name;
        c.status = line.estimated == true ? 'ESTIMATED' : 'PLANNED';
        // Not linkable before materialization, so it stays CONSULTATIVE: PARTIAL (policy §5) allows
        // editing draft allocations, and no draft can be constructed for a projected occurrence.
        c.linkable = false;
        c.holderId = schedule.AXF_FSC_LKP_Account__c;
        c.reasons.add('MATERIALIZATION_REQUIRED');
        result.add(c);
        page.virtualCount++;
      }
    }
    return result;
  }

  // ---------------------------------------------------------------- confirm

  /** @description Re-validates eligibility, then realizes through AXF-25; replay returns the prior result. */
  public ConfirmResult confirm(ConfirmInput input) {
    requireAccess();
    check(
      input != null &&
        !String.isBlank(input.operationKey) &&
        input.operationKey.length() <= 80 &&
        input.sourceId != null &&
        KINDS.contains(input.sourceKind),
      'INVALID'
    );
    ConfirmResult result = new ConfirmResult();
    // Visibility and holder authorization first; a hidden fact never reaches the key lookup.
    SourceView source = readSource(input.sourceId, input.sourceKind);
    String operation = AXF_CLS_IdentityFraming.key(
      new List<Object>{ 'AXF25', input.operationKey }
    );
    List<AXF_OBJ_ReconciliationAllocation__c> previous = [
      SELECT Id, AXF_RA_LKP_BankTransaction__c, AXF_RA_LKP_CardTransaction__c
      FROM AXF_OBJ_ReconciliationAllocation__c
      WHERE AXF_RA_EXI_AllocationKey__c = :operation
      WITH USER_MODE
      LIMIT 1
    ];
    if (!previous.isEmpty()) {
      // AXF-135: an operation that was already applied is resolved before the role is judged, so a
      // retry that declares no role — a cached client — reproduces the recorded result instead of
      // being refused on a field it never sent. Replay skips eligibility (the link may have
      // exhausted the source); AXF-25 still compares the payload hash and answers CONFLICT on any
      // divergence whenever the retry does declare a role.
      result.replayed = true;
      result.createdActualOnly = input.targetId == null;
      if (String.isNotBlank(input.economicRole)) {
        result.allocationId = realize(input, source);
      } else {
        result.allocationId = previous[0].Id;
      }
      finish(result);
      if (String.isBlank(input.economicRole)) {
        // The role of the recorded operation is not part of this retry, so it cannot take part in
        // the comparison: the retry is checked against what the recorded allocation holds.
        Id recordedSource = previous[0].AXF_RA_LKP_BankTransaction__c != null
          ? previous[0].AXF_RA_LKP_BankTransaction__c
          : previous[0].AXF_RA_LKP_CardTransaction__c;
        check(
          input.sourceId == recordedSource &&
            input.amount == result.amount &&
            (input.targetId == null ||
            input.targetId == result.targetId),
          'CONFLICT'
        );
      }
      return result;
    }
    // AXF-135: the role is declared, never defaulted. A role this slice cannot route is refused
    // here, before any read of a candidate and before any write, so no invoice payment, transfer or
    // refund can ever become an allocation or a second consumption expense.
    check(
      input.economicRole != null && ECONOMIC_ROLES.contains(input.economicRole),
      'INVALID_ECONOMIC_ROLE'
    );
    check(
      ROUTABLE_ROLES.contains(input.economicRole),
      'UNSUPPORTED_ECONOMIC_ROLE'
    );
    if (!source.eligible) {
      throw new SourceLinkException(source.reasons[0]);
    }
    check(
      input.sourceVersion != null && input.sourceVersion == source.version,
      'CONFLICT'
    );
    check(
      input.amount != null &&
        input.amount > 0 &&
        input.amount == input.amount.setScale(2) &&
        input.recognitionDate != null,
      'INVALID'
    );
    Decimal suggested = source.residual;
    if (input.targetId != null) {
      CandidateView target = candidate(source, input.targetId);
      check(target != null, 'INVALID_TARGET');
      check(
        input.targetVersion != null && input.targetVersion == target.version,
        'CONFLICT'
      );
      check(
        !new Conservation().linked(input.targetId, input.sourceId),
        'ALREADY_LINKED'
      );
      suggested = Math.min(suggested, target.residual);
    }
    // Any deviation from the visible suggestion demands an explicit review acknowledgement.
    check(
      (input.amount == suggested && input.recognitionDate == source.factDate) ||
      input.changesReviewed == true,
      'REVIEW_REQUIRED'
    );
    check(
      input.amount <= source.residual &&
      (input.targetId == null ||
      input.amount <= suggested),
      'UNAVAILABLE_AMOUNT'
    );
    result.createdActualOnly = input.targetId == null;
    result.allocationId = realize(input, source);
    finish(result);
    return result;
  }

  private CandidateView candidate(SourceView source, Id targetId) {
    List<AXF_OBJ_FinancialTransaction__c> rows = [
      SELECT
        Id,
        AXF_FTX_LKP_Account__c,
        AXF_FTX_NUM_Magnitude__c,
        AXF_FTX_TXT_CurrencyIsoCode__c,
        AXF_FTX_PKL_Direction__c,
        AXF_FTX_PKL_PlanKind__c,
        AXF_FTX_PKL_ScheduleState__c,
        AXF_FTX_NUM_Version__c,
        AXF_FTX_LKP_BankAccount__c,
        AXF_FTX_LKP_CreditCard__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE Id = :targetId
      WITH USER_MODE
    ];
    check(rows.size() == 1, 'UNAVAILABLE');
    AXF_OBJ_FinancialTransaction__c row = rows[0];
    check(row.AXF_FTX_LKP_Account__c == source.accountId, 'UNAVAILABLE');
    check(row.AXF_FTX_PKL_PlanKind__c == 'PLANNED', 'INVALID_TARGET');
    check(row.AXF_FTX_PKL_ScheduleState__c != 'CANCELLED', 'TARGET_CANCELLED');
    if (row.AXF_FTX_TXT_CurrencyIsoCode__c != source.currencyIso) {
      // AXF-140: material FX evidence is checked first, so a pair with no usable quote is refused
      // with the missing rate the user has to correct instead of a bare currency mismatch.
      check(
        materialRate(
          row.AXF_FTX_TXT_CurrencyIsoCode__c,
          source.currencyIso,
          quoteSide(source.direction)
        ) != null,
        'MISSING_MATERIAL_FX'
      );
    }
    check(
      row.AXF_FTX_TXT_CurrencyIsoCode__c == source.currencyIso,
      'CURRENCY_MISMATCH'
    );
    check(row.AXF_FTX_PKL_Direction__c == source.direction, 'INVALID_TARGET');
    Id expected = (Id) row.get(fundingField(source.sourceKind));
    Id other = (Id) row.get(otherFundingField(source.sourceKind));
    check(
      other == null && (expected == null || expected == source.fundingId),
      'FUNDING_MISMATCH'
    );
    Map<Id, Decimal> nets = new Map<Id, Decimal>();
    Set<Id> unverified = new Set<Id>();
    netByTarget(new Set<Id>{ row.Id }, nets, unverified);
    check(!unverified.contains(row.Id), 'ALLOCATIONS_UNVERIFIED');
    CandidateView c = new CandidateView();
    c.targetId = row.Id;
    c.amount = row.AXF_FTX_NUM_Magnitude__c;
    c.residual =
      row.AXF_FTX_NUM_Magnitude__c -
      (nets.containsKey(row.Id) ? nets.get(row.Id) : 0);
    check(c.residual > 0, 'TARGET_REALIZED');
    c.version = row.AXF_FTX_NUM_Version__c == null
      ? 0
      : row.AXF_FTX_NUM_Version__c;
    return c;
  }

  private Id realize(ConfirmInput input, SourceView source) {
    ALT_CLS_RealizationService.Input request = new ALT_CLS_RealizationService.Input();
    request.targetId = input.targetId;
    request.sourceId = input.sourceId;
    request.sourceKind = input.sourceKind;
    request.amount = input.amount;
    request.recognitionDate = input.recognitionDate;
    request.targetVersion = input.targetVersion;
    request.sourceVersion = input.sourceVersion;
    request.operationKey = input.operationKey;
    // AXF-135: the declared role travels into the canonical payload of the realization.
    request.economicRole = input.economicRole;
    if (input.targetId == null) {
      // ACTUAL_ONLY: the plan is born from the fact itself (holder, currency, direction).
      request.accountId = source.accountId;
      request.currencyIso = source.currencyIso;
      request.direction = source.direction;
    }
    try {
      return new ALT_CLS_RealizationService().apply(request);
    } catch (ALT_CLS_RealizationService.RealizationException failure) {
      throw new SourceLinkException(failure.getMessage());
    }
  }

  private void finish(ConfirmResult result) {
    List<AXF_OBJ_ReconciliationAllocation__c> rows = [
      SELECT
        AXF_RA_LKP_FinancialTransaction__c,
        AXF_RA_NUM_Magnitude__c,
        AXF_RA_TXT_CurrencyIsoCode__c
      FROM AXF_OBJ_ReconciliationAllocation__c
      WHERE Id = :result.allocationId
      WITH USER_MODE
    ];
    check(rows.size() == 1, 'UNAVAILABLE');
    result.targetId = rows[0].AXF_RA_LKP_FinancialTransaction__c;
    result.amount = rows[0].AXF_RA_NUM_Magnitude__c;
    result.currencyIso = rows[0].AXF_RA_TXT_CurrencyIsoCode__c;
  }

  /** @description Private verification only: counts and booleans leave this boundary, never amounts or rows. */
  private without sharing class Conservation {
    @SuppressWarnings('PMD.ApexCRUDViolation')
    public Map<Id, Integer> countBySource(Set<Id> ids) {
      requireAccess();
      Map<Id, Integer> result = new Map<Id, Integer>();
      List<AXF_OBJ_ReconciliationAllocation__c> rows = [
        SELECT AXF_RA_LKP_BankTransaction__c, AXF_RA_LKP_CardTransaction__c
        FROM AXF_OBJ_ReconciliationAllocation__c
        WHERE
          AXF_RA_LKP_BankTransaction__c IN :ids
          OR AXF_RA_LKP_CardTransaction__c IN :ids
        LIMIT :MAX_ALLOCATION_ROWS
      ];
      if (rows.size() >= MAX_ALLOCATION_ROWS) {
        return null; // truncated: the caller treats every id as unverified
      }
      for (AXF_OBJ_ReconciliationAllocation__c row : rows) {
        Id key = row.AXF_RA_LKP_BankTransaction__c != null
          ? row.AXF_RA_LKP_BankTransaction__c
          : row.AXF_RA_LKP_CardTransaction__c;
        result.put(key, (result.containsKey(key) ? result.get(key) : 0) + 1);
      }
      return result;
    }
    @SuppressWarnings('PMD.ApexCRUDViolation')
    public Map<Id, Integer> countByTarget(Set<Id> ids) {
      requireAccess();
      Map<Id, Integer> result = new Map<Id, Integer>();
      List<AXF_OBJ_ReconciliationAllocation__c> rows = [
        SELECT AXF_RA_LKP_FinancialTransaction__c
        FROM AXF_OBJ_ReconciliationAllocation__c
        WHERE AXF_RA_LKP_FinancialTransaction__c IN :ids
        LIMIT :MAX_ALLOCATION_ROWS
      ];
      if (rows.size() >= MAX_ALLOCATION_ROWS) {
        return null;
      }
      for (AXF_OBJ_ReconciliationAllocation__c row : rows) {
        Id key = row.AXF_RA_LKP_FinancialTransaction__c;
        result.put(key, (result.containsKey(key) ? result.get(key) : 0) + 1);
      }
      return result;
    }
    /** An OPEN review of any type (SOURCE_CHANGE, SOURCE_DELETE, ...) blocks the fact regardless of queue visibility. */
    @SuppressWarnings('PMD.ApexCRUDViolation')
    public Set<Id> openReviews(Set<Id> ids) {
      requireAccess();
      Set<Id> result = new Set<Id>();
      for (AXF_OBJ_ReviewItem__c row : [
        SELECT
          AXF_RVI_LKP_BankAccountTransaction__c,
          AXF_RVI_LKP_CreditCardTransaction__c
        FROM AXF_OBJ_ReviewItem__c
        WHERE
          AXF_RVI_PKL_State__c = 'OPEN'
          AND (AXF_RVI_LKP_BankAccountTransaction__c IN :ids
          OR AXF_RVI_LKP_CreditCardTransaction__c IN :ids)
        LIMIT 2000
      ]) {
        if (row.AXF_RVI_LKP_BankAccountTransaction__c != null) {
          result.add(row.AXF_RVI_LKP_BankAccountTransaction__c);
        }
        if (row.AXF_RVI_LKP_CreditCardTransaction__c != null) {
          result.add(row.AXF_RVI_LKP_CreditCardTransaction__c);
        }
      }
      return result;
    }
    @SuppressWarnings('PMD.ApexCRUDViolation')
    public Boolean linked(Id targetId, Id sourceId) {
      requireAccess();
      Decimal net = 0;
      for (AXF_OBJ_ReconciliationAllocation__c row : [
        SELECT AXF_RA_PKL_Kind__c, AXF_RA_NUM_Magnitude__c
        FROM AXF_OBJ_ReconciliationAllocation__c
        WHERE
          AXF_RA_LKP_FinancialTransaction__c = :targetId
          AND (AXF_RA_LKP_BankTransaction__c = :sourceId
          OR AXF_RA_LKP_CardTransaction__c = :sourceId)
        LIMIT 2000
      ]) {
        net +=
          (row.AXF_RA_PKL_Kind__c == 'REVERSAL' ? -1 : 1) *
          row.AXF_RA_NUM_Magnitude__c;
      }
      return net > 0;
    }
  }
}
