/** @description AXF-101 retention contract tests. Fixture days are not deployed policies. */
@IsTest
private class ALT_CLS_RetentionPolicyTest {
  @IsTest
  static void pendingReceiptReplaysAtOriginalExpiry() {
    ALT_CLS_RetentionPolicy.policyFixtures = new List<AXF_CMT_RetentionPolicy__mdt>{
      policy()
    };
    ALT_CLS_RetentionPolicy.Request r = request();
    Datetime dueAt = r.evaluatedAt;
    r.evaluatedAt = r.triggerAt;
    ALT_CLS_RetentionPolicy.Result initial = run(r);
    r.originalReceipt = initial.receipt;
    r.replay = true;
    Test.startTest();
    r.evaluatedAt = dueAt.addSeconds(-1);
    ALT_CLS_RetentionPolicy.Result pending = run(r);
    Assert.areEqual('KEEP', pending.status, 'Replay remains pending');
    Assert.isFalse(pending.eligible, 'Cannot expire early');
    Assert.areEqual('RETENTION_PENDING', pending.reasonCode, 'Pending reason');
    Assert.areEqual(dueAt, pending.dueAt, 'Original due time retained');
    r.evaluatedAt = dueAt;
    ALT_CLS_RetentionPolicy.Result expired = run(r);
    Assert.isTrue(expired.eligible, 'Eligible exactly at original expiry');
    Assert.areEqual('ELIGIBLE', expired.status, 'Expired status');
    Assert.areEqual(dueAt, expired.dueAt, 'Expiry is unchanged');
    Assert.areEqual(
      JSON.serialize(initial.receipt),
      JSON.serialize(expired.receipt),
      'Receipt preserved'
    );
    Test.stopTest();
  }
  @IsTest
  static void mixedBatchPreservesResultAssociations() {
    ALT_CLS_RetentionPolicy.policyFixtures = new List<AXF_CMT_RetentionPolicy__mdt>{
      policy()
    };
    ALT_CLS_RetentionPolicy.Request eligible = request();
    ALT_CLS_RetentionPolicy.Request pending = request();
    pending.triggerAt = pending.triggerAt.addSeconds(60);
    ALT_CLS_RetentionPolicy.Request hold = request();
    hold.legalHold = true;
    ALT_CLS_RetentionPolicy.Request missing = request();
    missing.domain = 'missing';
    List<ALT_CLS_RetentionPolicy.Request> batch = new List<ALT_CLS_RetentionPolicy.Request>{
      eligible,
      pending,
      hold,
      missing,
      null
    };
    Test.startTest();
    List<ALT_CLS_RetentionPolicy.Result> results = ALT_CLS_RetentionPolicy.evaluate(
      batch
    );
    Test.stopTest();
    Assert.areEqual(5, results.size(), 'One result per input including null');
    List<String> statuses = new List<String>{
      'ELIGIBLE',
      'KEEP',
      'BLOCKED',
      'BLOCKED',
      'BLOCKED'
    };
    List<String> reasons = new List<String>{
      'RETENTION_ELAPSED',
      'RETENTION_PENDING',
      'LEGAL_HOLD',
      'POLICY_MISSING',
      'INVALID_REQUEST'
    };
    for (Integer i = 0; i < results.size(); i++) {
      ALT_CLS_RetentionPolicy.Result actual = results[i];
      Assert.areEqual(statuses[i], actual.status, 'Position ' + i + ' status');
      Assert.areEqual(
        i == 0,
        actual.eligible,
        'Position ' + i + ' eligibility'
      );
      Assert.areEqual(
        reasons[i],
        actual.reasonCode,
        'Position ' + i + ' reason'
      );
      if (i < 2) {
        Assert.areEqual(
          batch[i].triggerAt.addSeconds(172800),
          actual.dueAt,
          'Due belongs to request'
        );
        Assert.areEqual(
          batch[i].triggerAt,
          actual.receipt.triggerAt,
          'Receipt timestamp belongs to request'
        );
        Assert.areEqual(
          batch[i].domain,
          actual.receipt.domain,
          'Receipt domain belongs to request'
        );
        Assert.areEqual(
          batch[i].purgeTrigger,
          actual.receipt.purgeTrigger,
          'Receipt trigger belongs to request'
        );
        Assert.areEqual(
          'ReviewPolicy',
          actual.receipt.policyIdentity,
          'Receipt policy'
        );
        Assert.areEqual('1', actual.receipt.policyVersion, 'Receipt version');
        Assert.isNotNull(
          actual.receipt.fingerprint,
          'Receipt fingerprints configuration'
        );
      } else {
        Assert.isNull(actual.dueAt, 'Blocked due is null');
        Assert.isNull(actual.receipt, 'Blocked receipt is null');
      }
    }
  }
  @IsTest
  static void timestampOverflowBlocks() {
    ALT_CLS_RetentionPolicy.policyFixtures = new List<AXF_CMT_RetentionPolicy__mdt>{
      policy()
    };
    ALT_CLS_RetentionPolicy.Request r = request();
    r.triggerAt = Datetime.newInstanceGmt(9999, 12, 31, 12, 0, 0);
    r.evaluatedAt = r.triggerAt;
    Test.startTest();
    reason(r, 'TIME_OVERFLOW');
    Test.stopTest();
  }
  @IsTest
  static void replayRejectsNewDomainAndTriggerTimestamp() {
    AXF_CMT_RetentionPolicy__mdt p = policy();
    p.AXF_RPT_TXT_Domain__c = 'generic';
    ALT_CLS_RetentionPolicy.policyFixtures = new List<AXF_CMT_RetentionPolicy__mdt>{
      p
    };
    ALT_CLS_RetentionPolicy.Request r = request();
    r.domain = 'generic';
    r.originalReceipt = run(r).receipt;
    r.replay = true;
    Test.startTest();
    r.triggerAt = r.triggerAt.addSeconds(-1);
    reason(r, 'RECEIPT_MISMATCH');
    r.triggerAt = r.originalReceipt.triggerAt;
    r.domain = 'other';
    p.AXF_RPT_TXT_Domain__c = 'other';
    reason(r, 'RECEIPT_MISMATCH');
    r.domain = 'generic';
    p.AXF_RPT_TXT_Domain__c = 'generic';
    r.purgeTrigger = 'OTHER';
    p.AXF_RPT_TXT_PurgeTrigger__c = 'OTHER';
    reason(r, 'RECEIPT_MISMATCH');
    Test.stopTest();
  }
  @IsTest
  static void explicitTriggerMustMatchPolicy() {
    AXF_CMT_RetentionPolicy__mdt p = policy();
    p.AXF_RPT_TXT_Domain__c = 'other';
    ALT_CLS_RetentionPolicy.policyFixtures = new List<AXF_CMT_RetentionPolicy__mdt>{
      p
    };
    ALT_CLS_RetentionPolicy.Request r = request();
    r.domain = 'other';
    r.purgeTrigger = 'OTHER';
    Test.startTest();
    reason(r, 'TRIGGER_MISMATCH');
    p.AXF_RPT_TXT_PurgeTrigger__c = null;
    reason(r, 'POLICY_INVALID');
    Test.stopTest();
  }
  private static AXF_CMT_RetentionPolicy__mdt policy() {
    return new AXF_CMT_RetentionPolicy__mdt(
      DeveloperName = 'ReviewPolicy',
      AXF_RPT_TXT_Domain__c = 'review.prior',
      AXF_RPT_TXT_PurgeTrigger__c = 'REVIEW_FINALIZED',
      AXF_RPT_NUM_RetentionDays__c = 2,
      AXF_RPT_BOL_Enabled__c = true,
      AXF_RPT_TXT_Version__c = '1'
    );
  }
  private static ALT_CLS_RetentionPolicy.Request request() {
    ALT_CLS_RetentionPolicy.Request r = new ALT_CLS_RetentionPolicy.Request();
    r.domain = 'review.prior';
    r.purgeTrigger = 'REVIEW_FINALIZED';
    r.triggerAt = Datetime.newInstanceGmt(2026, 1, 1, 12, 0, 0);
    r.evaluatedAt = r.triggerAt.addSeconds(172800);
    r.legalHold = false;
    r.activeDependencies = false;
    r.openReview = false;
    r.unresolvedOutcome = false;
    r.reviewState = 'RESOLVED';
    return r;
  }
  private static ALT_CLS_RetentionPolicy.Result run(
    ALT_CLS_RetentionPolicy.Request r
  ) {
    return ALT_CLS_RetentionPolicy.evaluate(
      new List<ALT_CLS_RetentionPolicy.Request>{ r }
    )[0];
  }
  private static void reason(ALT_CLS_RetentionPolicy.Request r, String code) {
    ALT_CLS_RetentionPolicy.Result actual = run(r);
    Assert.areEqual(code, actual.reasonCode, 'Stable reason');
    Assert.isFalse(actual.eligible, 'Must keep data');
    Assert.isNull(actual.dueAt, 'Blocked has no due time');
    Assert.areEqual('BLOCKED', actual.status, 'Blocked status');
    Assert.isNull(actual.receipt, 'Blocked has no receipt');
  }
  @IsTest
  static void expiryBoundariesAndDeterminism() {
    ALT_CLS_RetentionPolicy.policyFixtures = new List<AXF_CMT_RetentionPolicy__mdt>{
      policy()
    };
    ALT_CLS_RetentionPolicy.Request r = request();
    Test.startTest();
    r.evaluatedAt = r.evaluatedAt.addSeconds(-1);
    Assert.areEqual('KEEP', run(r).status, 'Before deadline');
    r.evaluatedAt = r.evaluatedAt.addSeconds(1);
    ALT_CLS_RetentionPolicy.Result first = run(r);
    Assert.isTrue(first.eligible, 'At deadline');
    Assert.areEqual(r.evaluatedAt, first.dueAt, 'UTC due date');
    Assert.areEqual(
      JSON.serialize(first),
      JSON.serialize(run(r)),
      'Deterministic results'
    );
    r.evaluatedAt = r.evaluatedAt.addSeconds(1);
    Assert.isTrue(run(r).eligible, 'After deadline');
    Test.stopTest();
  }
  @IsTest
  static void unavailablePoliciesAndIsolation() {
    ALT_CLS_RetentionPolicy.Request r = request();
    Test.startTest();
    ALT_CLS_RetentionPolicy.policyFixtures = new List<AXF_CMT_RetentionPolicy__mdt>();
    reason(r, 'POLICY_MISSING');
    AXF_CMT_RetentionPolicy__mdt p = policy();
    ALT_CLS_RetentionPolicy.policyFixtures.add(p);
    p.AXF_RPT_BOL_Enabled__c = false;
    reason(r, 'POLICY_DISABLED');
    p.AXF_RPT_BOL_Enabled__c = true;
    ALT_CLS_RetentionPolicy.policyFixtures.add(policy());
    reason(r, 'POLICY_AMBIGUOUS');
    p.AXF_RPT_BOL_Enabled__c = false;
    reason(r, 'POLICY_AMBIGUOUS');
    r.domain = 'other';
    reason(r, 'POLICY_MISSING');
    Test.stopTest();
  }
  @IsTest
  static void invalidPolicyWindows() {
    AXF_CMT_RetentionPolicy__mdt p = policy();
    ALT_CLS_RetentionPolicy.policyFixtures = new List<AXF_CMT_RetentionPolicy__mdt>{
      p
    };
    Test.startTest();
    for (
      Decimal days : new List<Decimal>{ null, 0, -1, 1.5, 999999999999999999L }
    ) {
      p.AXF_RPT_NUM_RetentionDays__c = days;
      reason(request(), 'POLICY_INVALID');
    }
    p.AXF_RPT_NUM_RetentionDays__c = 2;
    p.AXF_RPT_TXT_Version__c = null;
    reason(request(), 'POLICY_INVALID');
    Test.stopTest();
  }
  @IsTest
  static void vetoesAndUnknownSafety() {
    ALT_CLS_RetentionPolicy.policyFixtures = new List<AXF_CMT_RetentionPolicy__mdt>{
      policy()
    };
    Test.startTest();
    ALT_CLS_RetentionPolicy.Request r = request();
    r.legalHold = true;
    reason(r, 'LEGAL_HOLD');
    r = request();
    r.activeDependencies = true;
    reason(r, 'ACTIVE_DEPENDENCIES');
    r = request();
    r.openReview = true;
    reason(r, 'OPEN_REVIEW');
    r = request();
    r.unresolvedOutcome = true;
    reason(r, 'UNRESOLVED_OUTCOME');
    for (
      String field : new List<String>{
        'legalHold',
        'activeDependencies',
        'openReview',
        'unresolvedOutcome'
      }
    ) {
      Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(
        JSON.serialize(request())
      );
      raw.put(field, null);
      reason(
        (ALT_CLS_RetentionPolicy.Request) JSON.deserialize(
          JSON.serialize(raw),
          ALT_CLS_RetentionPolicy.Request.class
        ),
        'UNKNOWN_SAFETY_STATE'
      );
    }
    Test.stopTest();
  }
  @IsTest
  static void invalidRequestAndReviewState() {
    ALT_CLS_RetentionPolicy.policyFixtures = new List<AXF_CMT_RetentionPolicy__mdt>{
      policy()
    };
    Test.startTest();
    reason(null, 'INVALID_REQUEST');
    for (
      String field : new List<String>{
        'domain',
        'purgeTrigger',
        'triggerAt',
        'evaluatedAt',
        'replay'
      }
    ) {
      Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(
        JSON.serialize(request())
      );
      raw.put(field, null);
      reason(
        (ALT_CLS_RetentionPolicy.Request) JSON.deserialize(
          JSON.serialize(raw),
          ALT_CLS_RetentionPolicy.Request.class
        ),
        'INVALID_REQUEST'
      );
    }
    ALT_CLS_RetentionPolicy.Request r = request();
    r.triggerAt = r.evaluatedAt.addSeconds(1);
    reason(r, 'INVALID_REQUEST');
    r = request();
    r.reviewState = 'OPEN';
    reason(r, 'OPEN_REVIEW');
    r.reviewState = null;
    reason(r, 'INVALID_REVIEW_STATE');
    r.reviewState = 'DISMISSED';
    Assert.isTrue(run(r).eligible, 'Dismissal starts explicit window');
    r.purgeTrigger = 'OTHER';
    reason(r, 'INVALID_REVIEW_STATE');
    Test.stopTest();
  }
  @IsTest
  static void replayPinsAllReceiptFields() {
    ALT_CLS_RetentionPolicy.policyFixtures = new List<AXF_CMT_RetentionPolicy__mdt>{
      policy()
    };
    ALT_CLS_RetentionPolicy.Request r = request();
    ALT_CLS_RetentionPolicy.Receipt receipt = run(r).receipt;
    Test.startTest();
    r.replay = true;
    reason(r, 'RECEIPT_REQUIRED');
    r.originalReceipt = receipt;
    Assert.isTrue(run(r).eligible, 'Unchanged receipt accepted');
    for (
      String field : new List<String>{
        'policyIdentity',
        'policyVersion',
        'fingerprint',
        'domain',
        'purgeTrigger',
        'triggerAt'
      }
    ) {
      Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(
        JSON.serialize(receipt)
      );
      raw.put(field, null);
      r.originalReceipt = (ALT_CLS_RetentionPolicy.Receipt) JSON.deserialize(
        JSON.serialize(raw),
        ALT_CLS_RetentionPolicy.Receipt.class
      );
      reason(r, 'RECEIPT_MISMATCH');
    }
    r.originalReceipt = receipt;
    r.legalHold = true;
    reason(r, 'LEGAL_HOLD');
    Test.stopTest();
  }
  @IsTest
  static void replayRejectsChangedOrMissingPolicy() {
    AXF_CMT_RetentionPolicy__mdt p = policy();
    ALT_CLS_RetentionPolicy.policyFixtures = new List<AXF_CMT_RetentionPolicy__mdt>{
      p
    };
    ALT_CLS_RetentionPolicy.Request r = request();
    r.originalReceipt = run(r).receipt;
    r.replay = true;
    Test.startTest();
    p.AXF_RPT_NUM_RetentionDays__c = 1;
    reason(r, 'RECEIPT_MISMATCH');
    p.AXF_RPT_NUM_RetentionDays__c = 2;
    p.DeveloperName = 'Replacement';
    reason(r, 'RECEIPT_MISMATCH');
    p.DeveloperName = 'ReviewPolicy';
    p.AXF_RPT_TXT_Version__c = '2';
    reason(r, 'RECEIPT_MISMATCH');
    ALT_CLS_RetentionPolicy.policyFixtures.clear();
    reason(r, 'POLICY_MISSING');
    Test.stopTest();
  }
  @IsTest
  static void bulkHasNoDmlOrQueries() {
    ALT_CLS_RetentionPolicy.policyFixtures = new List<AXF_CMT_RetentionPolicy__mdt>{
      policy()
    };
    List<ALT_CLS_RetentionPolicy.Request> batch = new List<ALT_CLS_RetentionPolicy.Request>();
    for (Integer i = 0; i < 251; i++) {
      batch.add(request());
    }
    Test.startTest();
    List<ALT_CLS_RetentionPolicy.Result> results = ALT_CLS_RetentionPolicy.evaluate(
      batch
    );
    Assert.areEqual(0, Limits.getDmlStatements(), 'No business mutations');
    Assert.areEqual(0, Limits.getQueries(), 'No record queries');
    Test.stopTest();
    Assert.areEqual(251, results.size(), 'All requests returned');
    for (ALT_CLS_RetentionPolicy.Result r : results) {
      Assert.isTrue(r.eligible, 'Each result evaluated');
    }
  }
  @IsTest
  static void metadataLoaderMatchesConfigurationSnapshot() {
    ALT_CLS_RetentionPolicy.policyFixtures = AXF_CMT_RetentionPolicy__mdt.getAll()
      .values();
    String expected = JSON.serialize(run(request()));
    ALT_CLS_RetentionPolicy.policyFixtures = null;
    Test.startTest();
    Assert.areEqual(
      expected,
      JSON.serialize(run(request())),
      'Loader reflects the same metadata snapshot regardless of administrator configuration'
    );
    Test.stopTest();
  }
  @IsTest
  static void emptyBatch() {
    Test.startTest();
    Assert.areEqual(
      0,
      ALT_CLS_RetentionPolicy.evaluate(
          new List<ALT_CLS_RetentionPolicy.Request>()
        )
        .size(),
      'Empty batch'
    );
    Test.stopTest();
  }
  @IsTest
  static void nullBatch() {
    Test.startTest();
    Assert.areEqual(
      0,
      ALT_CLS_RetentionPolicy.evaluate(null).size(),
      'Null batch'
    );
    Test.stopTest();
  }
}
