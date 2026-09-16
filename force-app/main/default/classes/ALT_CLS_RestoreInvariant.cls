/**
 * @description AXF-121 non-resurrection invariant on restore (the restore slice of AXF-9). The
 * closure writes, together with its terminal state, a non-reactivation mark: minimal proof of the
 * lifecycle, digested over the very fields that compose it and carrying no private content at all.
 * A later restore or rollback consults this guard before reactivating any scope. Where a closure
 * lifecycle is known, reactivation is refused, and refusal is the safe answer whenever the proof
 * is missing, was altered, or the closure is still running (AD-24).
 *
 * Scope boundary: the backup vendor and mechanism are `Deferred` (G9-3, tracked in AXF-79), so the
 * real end-to-end restore stays a production gate. This class delivers the invariant and the
 * integration point that restore must respect. It never runs a restore and never reactivates
 * anything. The mark lives inside the same database: a restore that also rolls back the closure
 * evidence is outside the reach of this local build and remains tracked in AXF-79.
 *
 * Basis: FR-49; AD-13 (native evidence), AD-18 (proven recovery), AD-20 (closure lifecycle),
 * AD-21 (authorization), AD-24 (unknown result is not retryable), AD-29 (binding contracts).
 */
public with sharing class ALT_CLS_RestoreInvariant {
  /**
   * Result of asking the invariant whether a restored scope may be reactivated. Refusal is the
   * default: only a scope with no closure lifecycle at all allows reactivation.
   */
  public class Assessment {
    public Id holderId;
    public Boolean reactivationAllowed = false;
    public String verdict = 'NOT_REACTIVATED';
    /** Why the verdict was reached; safe to surface, carries no private content. */
    public String reason;
    /** Minimal, content-free proof of the lifecycle; null when there is nothing to prove. */
    public String lifecycleProof;
  }

  /**
   * Every key a proof may carry. The list is closed on purpose: evidence with nowhere to hold
   * private content cannot reconstruct it, and a proof carrying anything else is refused.
   */
  private static final List<String> MARK_KEYS = new List<String>{
    'schemaVersion',
    'scopeKey',
    'correlationId',
    'policyVersion',
    'closedAt',
    'fingerprint'
  };
  private static final String MARK_SCHEMA = 'axf-non-reactivation@1.0.0';
  private static final String CLOSED = 'CLOSED';
  private static final String REASON_NEVER_CLOSED = 'NEVER_CLOSED';
  private static final String REASON_IN_PROGRESS = 'CLOSURE_IN_PROGRESS';
  private static final String REASON_MARK_MISSING = 'MARK_MISSING';
  private static final String REASON_MARK_MISMATCH = 'MARK_MISMATCH';
  private static final String REASON_CLOSED_SCOPE = 'CLOSED_SCOPE';

  /**
   * Builds the non-reactivation mark of a scope that is reaching its terminal state. It is written
   * once, with `CLOSED`, and the closure's terminal rule freezes it from then on.
   * @param scopeKey Holder scope key of the closure.
   * @param correlationId Lifecycle correlation of the closure.
   * @param policyVersion Policy receipts of the purge stage, when a policy applied.
   * @param closedAt Instant the closure reached its terminal state.
   * @return Serialized mark holding only the allowlisted, content-free keys.
   */
  public static String mark(
    String scopeKey,
    String correlationId,
    String policyVersion,
    Datetime closedAt
  ) {
    Map<String, Object> proof = new Map<String, Object>{
      'schemaVersion' => MARK_SCHEMA,
      'scopeKey' => scopeKey,
      'correlationId' => correlationId,
      'policyVersion' => policyVersion,
      'closedAt' => closedAt == null
        ? null
        : closedAt.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
    };
    proof.put('fingerprint', fingerprint(proof));
    return JSON.serialize(proof);
  }

  /**
   * Answers, for each restored scope, whether a restore may reactivate it. The caller is the
   * restore or rollback reconciliation, and it must honour a refusal: this guard never reactivates
   * anything by itself.
   * @param holders Holder scopes the restore found in the backup, in the order to be answered.
   * @return One assessment per holder, in the same order.
   */
  public List<Assessment> assess(List<Id> holders) {
    if (holders == null) {
      throw failure('INVALID_INPUT');
    }
    if (
      !FeatureManagement.checkPermission(ALT_CLS_ClosureOrchestrator.CP_CLOSE)
    ) {
      throw failure('FORBIDDEN');
    }
    Set<String> scopeKeys = new Set<String>();
    for (Id holder : holders) {
      if (holder == null) {
        throw failure('INVALID_INPUT');
      }
      scopeKeys.add(String.valueOf(holder));
    }
    Map<String, AXF_OBJ_ClosureRun__c> runs = new Map<String, AXF_OBJ_ClosureRun__c>();
    if (!scopeKeys.isEmpty()) {
      // The invariant is a protection duty, not a record-visibility question: reading the lifecycle
      // in system mode is deliberate, so that a caller who cannot see a closure is never answered
      // "allowed" — an authorization gap must not turn into a resurrection. The entry point
      // requires the closure capability, only content-free fields are read, and the caller only
      // ever learns about scopes it already named.
      for (AXF_OBJ_ClosureRun__c run : [
        SELECT
          Id,
          AXF_CLR_EXI_ScopeKey__c,
          AXF_CLR_PKL_Status__c,
          AXF_CLR_TXT_CorrelationId__c,
          AXF_CLR_TXT_PolicyVersion__c,
          AXF_CLR_TAL_NonReactivationMark__c
        FROM AXF_OBJ_ClosureRun__c
        WHERE AXF_CLR_EXI_ScopeKey__c IN :scopeKeys
        WITH SYSTEM_MODE
      ]) {
        runs.put(run.AXF_CLR_EXI_ScopeKey__c, run);
      }
    }
    List<Assessment> results = new List<Assessment>();
    for (Id holder : holders) {
      String scopeKey = String.valueOf(holder);
      Assessment result = assessOne(scopeKey, runs.get(scopeKey));
      result.holderId = holder;
      results.add(result);
    }
    return results;
  }

  /**
   * The decision itself. A scope with no closure lifecycle was never closed through it and is none
   * of this invariant's business. Every other case refuses reactivation, including the ones where
   * the proof cannot be trusted — a closure still running, a mark that never got written (any
   * closure that reached `CLOSED` before AXF-121 shipped), and a mark that does not belong to this
   * scope or was altered.
   */
  @TestVisible
  private static Assessment assessOne(
    String scopeKey,
    AXF_OBJ_ClosureRun__c run
  ) {
    Assessment result = new Assessment();
    if (run == null) {
      result.reactivationAllowed = true;
      result.verdict = 'REACTIVATION_ALLOWED';
      result.reason = REASON_NEVER_CLOSED;
      return result;
    }
    if (run.AXF_CLR_PKL_Status__c != CLOSED) {
      result.reason = REASON_IN_PROGRESS;
      return result;
    }
    Map<String, Object> proof = parseProof(
      run.AXF_CLR_TAL_NonReactivationMark__c
    );
    if (proof == null) {
      result.reason = REASON_MARK_MISSING;
      return result;
    }
    if (!isIntact(proof, scopeKey)) {
      result.reason = REASON_MARK_MISMATCH;
      return result;
    }
    result.reason = REASON_CLOSED_SCOPE;
    result.lifecycleProof = run.AXF_CLR_TAL_NonReactivationMark__c;
    return result;
  }

  private static Map<String, Object> parseProof(String mark) {
    if (String.isBlank(mark)) {
      return null;
    }
    try {
      Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
        mark
      );
      return parsed;
    } catch (Exception corrupt) {
      return null;
    }
  }

  /**
   * A proof is trusted only when it carries nothing outside the allowlist, describes this scope and
   * still matches its own digest. Anything else is a tampered or spliced mark: refuse.
   */
  private static Boolean isIntact(Map<String, Object> proof, String scopeKey) {
    for (String key : proof.keySet()) {
      if (!MARK_KEYS.contains(key)) {
        return false;
      }
    }
    if (!MARK_SCHEMA.equals(proof.get('schemaVersion'))) {
      return false;
    }
    if (!scopeKey.equals(proof.get('scopeKey'))) {
      return false;
    }
    Object stored = proof.get('fingerprint');
    if (!(stored instanceof String)) {
      return false;
    }
    return ((String) stored).equals(fingerprint(proof));
  }

  private static String fingerprint(Map<String, Object> proof) {
    return EncodingUtil.convertToHex(
      Crypto.generateDigest('SHA-256', Blob.valueOf(canonical(proof)))
    );
  }

  /**
   * Canonical form of a proof: allowlisted keys in fixed order, so the digest is reproducible. The
   * fingerprint itself is excluded — it is the digest of everything else.
   */
  private static String canonical(Map<String, Object> proof) {
    List<String> parts = new List<String>();
    for (String key : MARK_KEYS) {
      if (key == 'fingerprint') {
        continue;
      }
      parts.add(JSON.serialize(key) + ':' + JSON.serialize(proof.get(key)));
    }
    return '{' + String.join(parts, ',') + '}';
  }

  /** The closure lifecycle's own error contract; a safety gate fails loudly, never silently. */
  private static ALT_CLS_ClosureOrchestrator.ClosureException failure(
    String code
  ) {
    ALT_CLS_ClosureOrchestrator.ClosureException result = new ALT_CLS_ClosureOrchestrator.ClosureException(
      code
    );
    result.code = code;
    return result;
  }
}
