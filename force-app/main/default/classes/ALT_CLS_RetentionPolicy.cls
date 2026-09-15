/**
 * @description AXF-101 deterministic retention eligibility, without record access or DML.
 * Trusted consumers supply state, enforce authorization, and persist/reload receipts
 * server-side. A receipt is configuration evidence, never an authorization token.
 */
public with sharing class ALT_CLS_RetentionPolicy {
  /**
   * @description Trusted consumer inputs, never direct client-supplied safety claims.
   * evaluatedAt must come from a trusted server clock. Domain and purgeTrigger are
   * matched exactly, without case normalization or fallback. For review.prior,
   * triggerAt must be the persisted ResolvedAt of RESOLVED/DISMISSED review evidence,
   * never its creation time. Consumers reload current safety state for every call.
   */
  public class Request {
    public String domain;
    public String purgeTrigger;
    public Datetime triggerAt;
    public Datetime evaluatedAt;
    public Boolean legalHold;
    public Boolean activeDependencies;
    public Boolean openReview;
    public Boolean unresolvedOutcome;
    public String reviewState;
    public Boolean replay = false;
    public Receipt originalReceipt;
  }

  /**
   * @description Policy evidence to persist and reload server-side for replay.
   * Set replay=true and supply the original receipt when reevaluating a captured
   * decision. This structure grants no purge authority or consumer authorization.
   */
  public class Receipt {
    public String policyIdentity;
    public String policyVersion;
    public String fingerprint;
    public String domain;
    public String purgeTrigger;
    public Datetime triggerAt;
  }

  /** @description Ordered eligibility result; BLOCKED has null dueAt and receipt. */
  public class Result {
    public Boolean eligible = false;
    public String status = 'BLOCKED';
    public String reasonCode;
    public Datetime dueAt;
    public Receipt receipt;
  }

  @TestVisible
  private static List<AXF_CMT_RetentionPolicy__mdt> policyFixtures;

  /**
   * @description Loads metadata once per batch; request order determines result order.
   * No business records are read or changed. Consumers enforce access, supply trusted
   * inputs, and persist/reload receipts; eligibility is never permission to purge.
   * @param requests Trusted domain requests, including a server-derived evaluatedAt.
   * @return One result per request, or an empty list for a null/empty batch.
   */
  public static List<Result> evaluate(List<Request> requests) {
    List<Result> results = new List<Result>();
    if (requests == null || requests.isEmpty()) {
      return results;
    }
    List<AXF_CMT_RetentionPolicy__mdt> policies = policyFixtures != null
      ? policyFixtures
      : AXF_CMT_RetentionPolicy__mdt.getAll().values();
    Map<String, List<AXF_CMT_RetentionPolicy__mdt>> byDomain = new Map<String, List<AXF_CMT_RetentionPolicy__mdt>>();
    for (AXF_CMT_RetentionPolicy__mdt policy : policies) {
      if (policy == null || String.isBlank(policy.AXF_RPT_TXT_Domain__c)) {
        continue;
      }
      String key = policy.AXF_RPT_TXT_Domain__c;
      if (!byDomain.containsKey(key)) {
        byDomain.put(key, new List<AXF_CMT_RetentionPolicy__mdt>());
      }
      byDomain.get(key).add(policy);
    }
    for (Request request : requests) {
      results.add(evaluateOne(request, byDomain));
    }
    return results;
  }

  private static Result blocked(String reason) {
    Result result = new Result();
    result.reasonCode = reason;
    return result;
  }

  private static String safetyReason(Request request) {
    if (
      request == null ||
      String.isBlank(request.domain) ||
      String.isBlank(request.purgeTrigger) ||
      request.triggerAt == null ||
      request.evaluatedAt == null ||
      request.triggerAt > request.evaluatedAt ||
      request.replay == null
    ) {
      return 'INVALID_REQUEST';
    }
    if (
      request.legalHold == null ||
      request.activeDependencies == null ||
      request.openReview == null ||
      request.unresolvedOutcome == null
    ) {
      return 'UNKNOWN_SAFETY_STATE';
    }
    if (request.legalHold) {
      return 'LEGAL_HOLD';
    }
    if (request.activeDependencies) {
      return 'ACTIVE_DEPENDENCIES';
    }
    if (request.openReview) {
      return 'OPEN_REVIEW';
    }
    if (request.unresolvedOutcome) {
      return 'UNRESOLVED_OUTCOME';
    }
    if (request.domain.equals('review.prior')) {
      if (request.reviewState == 'OPEN') {
        return 'OPEN_REVIEW';
      }
      if (
        (request.reviewState != 'RESOLVED' &&
        request.reviewState != 'DISMISSED') ||
        !request.purgeTrigger.equals('REVIEW_FINALIZED')
      ) {
        return 'INVALID_REVIEW_STATE';
      }
    }
    return null;
  }

  private static Result evaluateOne(
    Request request,
    Map<String, List<AXF_CMT_RetentionPolicy__mdt>> byDomain
  ) {
    String reason = safetyReason(request);
    if (reason != null) {
      return blocked(reason);
    }
    List<AXF_CMT_RetentionPolicy__mdt> matches = byDomain.get(request.domain);
    if (matches == null) {
      return blocked('POLICY_MISSING');
    }
    if (matches.size() != 1) {
      return blocked('POLICY_AMBIGUOUS');
    }
    AXF_CMT_RetentionPolicy__mdt policy = matches[0];
    if (policy.AXF_RPT_BOL_Enabled__c != true) {
      return blocked('POLICY_DISABLED');
    }
    Decimal days = policy.AXF_RPT_NUM_RetentionDays__c;
    if (
      String.isBlank(policy.DeveloperName) ||
      String.isBlank(policy.AXF_RPT_TXT_Version__c) ||
      String.isBlank(policy.AXF_RPT_TXT_PurgeTrigger__c) ||
      days == null ||
      days <= 0 ||
      days != days.setScale(0) ||
      days > 3652058
    ) {
      return blocked('POLICY_INVALID');
    }
    if (
      !request.domain.equals(policy.AXF_RPT_TXT_Domain__c) ||
      !request.purgeTrigger.equals(policy.AXF_RPT_TXT_PurgeTrigger__c)
    ) {
      return blocked('TRIGGER_MISMATCH');
    }
    Receipt receipt = new Receipt();
    receipt.policyIdentity =
      (policy.NamespacePrefix == null ? '' : policy.NamespacePrefix + '.') +
      policy.DeveloperName;
    receipt.policyVersion = policy.AXF_RPT_TXT_Version__c;
    receipt.domain = request.domain;
    receipt.purgeTrigger = request.purgeTrigger;
    receipt.triggerAt = request.triggerAt;
    receipt.fingerprint = EncodingUtil.convertToHex(
      Crypto.generateDigest(
        'SHA-256',
        Blob.valueOf(
          JSON.serialize(
            new List<String>{
              receipt.policyIdentity,
              receipt.policyVersion,
              policy.AXF_RPT_TXT_Domain__c,
              policy.AXF_RPT_TXT_PurgeTrigger__c,
              String.valueOf(days.setScale(0)),
              String.valueOf(policy.AXF_RPT_BOL_Enabled__c)
            }
          )
        )
      )
    );
    if (request.replay && request.originalReceipt == null) {
      return blocked('RECEIPT_REQUIRED');
    }
    if (
      request.originalReceipt != null &&
      !sameReceipt(request.originalReceipt, receipt)
    ) {
      return blocked('RECEIPT_MISMATCH');
    }
    Result result = new Result();
    // Epoch arithmetic avoids daylight-saving shifts; each day is exactly 24 hours.
    Long dueMillis = request.triggerAt.getTime() + days.longValue() * 86400000L;
    if (
      dueMillis > Datetime.newInstanceGmt(9999, 12, 31, 23, 59, 59).getTime()
    ) {
      return blocked('TIME_OVERFLOW');
    }
    result.dueAt = Datetime.newInstance(dueMillis);
    result.receipt = receipt;
    result.eligible = request.evaluatedAt >= result.dueAt;
    result.status = result.eligible ? 'ELIGIBLE' : 'KEEP';
    result.reasonCode = result.eligible
      ? 'RETENTION_ELAPSED'
      : 'RETENTION_PENDING';
    return result;
  }

  private static Boolean sameReceipt(Receipt original, Receipt current) {
    return current.policyIdentity.equals(original.policyIdentity) &&
      current.policyVersion.equals(original.policyVersion) &&
      current.fingerprint.equals(original.fingerprint) &&
      current.domain.equals(original.domain) &&
      current.purgeTrigger.equals(original.purgeTrigger) &&
      current.triggerAt == original.triggerAt;
  }
}
