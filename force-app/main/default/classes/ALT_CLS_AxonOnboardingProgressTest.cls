/**
 * @description Tests for ALT_CLS_AxonOnboardingProgress (AXF-88).
 * Functional paths use the `canConfigureOverride` seam; effective-authority
 * paths use a real user (System Administrator + AXF_PSG_GestorFinanceiro, or a
 * user without it) so AC7 is proven against the real permission.
 */
@IsTest(isParallel=false)
private class ALT_CLS_AxonOnboardingProgressTest {
  private static void allow() {
    ALT_CLS_AxonOnboardingProgress.canConfigureOverride = true;
  }

  private static ALT_CLS_AxonOnboardingProgress svc() {
    return new ALT_CLS_AxonOnboardingProgress();
  }

  private static ALT_CLS_AxonOnboardingProgress.ConfirmInput confirm(
    String step,
    Integer version,
    String evidence
  ) {
    ALT_CLS_AxonOnboardingProgress.ConfirmInput c = new ALT_CLS_AxonOnboardingProgress.ConfirmInput();
    c.stepKey = step;
    c.expectedVersion = version;
    c.evidenceRef = evidence;
    return c;
  }

  private static User plainUser(Boolean withGestorPsg) {
    Profile admin = [
      SELECT Id
      FROM Profile
      WHERE Name = 'System Administrator'
      LIMIT 1
    ];
    User u = new User(
      ProfileId = admin.Id,
      LastName = 'Onb Tester',
      Email = 'axf88.cfg@example.com',
      Username = 'axf88.cfg.' +
        Crypto.getRandomInteger() +
        '@example.com.invalid',
      Alias = 'axf88c',
      TimeZoneSidKey = 'America/Sao_Paulo',
      LocaleSidKey = 'pt_BR',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'pt_BR'
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert u;
      if (withGestorPsg) {
        PermissionSetGroup psg = [
          SELECT Id, Status
          FROM PermissionSetGroup
          WHERE DeveloperName = 'AXF_PSG_GestorFinanceiro'
          LIMIT 1
        ];
        if (psg.Status != 'Updated') {
          Test.calculatePermissionSetGroup(psg.Id);
        }
        insert new PermissionSetAssignment(
          AssigneeId = u.Id,
          PermissionSetGroupId = psg.Id
        );
      }
    }
    return u;
  }

  @IsTest
  static void getStateForbiddenWithoutAuthority() {
    ALT_CLS_AxonOnboardingProgress.canConfigureOverride = false;
    Test.startTest();
    ALT_CLS_AxonOnboardingProgress.OnboardingState st = svc().getState();
    Test.stopTest();
    System.assert(st.forbidden, 'must be forbidden');
    System.assertEquals(0, st.steps.size(), 'no rows leak');
    System.assertEquals(
      0,
      [SELECT COUNT() FROM AXF_OBJ_OnboardingProgress__c],
      'no header created for an unauthorized caller'
    );
  }

  @IsTest
  static void getStateCreatesHeaderAndStepCatalog() {
    allow();
    Test.startTest();
    ALT_CLS_AxonOnboardingProgress.OnboardingState st = svc().getState();
    Test.stopTest();
    System.assertEquals(false, st.forbidden);
    System.assertEquals(7, st.steps.size(), 'all seven steps seeded');
    System.assertEquals('WELCOME_PREFS', st.currentStep);
    System.assertEquals(0, st.version);
    System.assertEquals(
      1,
      [SELECT COUNT() FROM AXF_OBJ_OnboardingProgress__c],
      'single header'
    );
    // calling again does not create a second header (deterministic scope key)
    ALT_CLS_AxonOnboardingProgress.OnboardingState again = svc().getState();
    System.assertEquals(1, [SELECT COUNT() FROM AXF_OBJ_OnboardingProgress__c]);
    System.assertEquals(st.progressId, again.progressId);
  }

  @IsTest
  static void confirmStepAdvancesCurrentStepAndBumpsVersion() {
    allow();
    ALT_CLS_AxonOnboardingProgress.OnboardingState st0 = svc().getState();
    Test.startTest();
    ALT_CLS_AxonOnboardingProgress.OnboardingState st1 = svc()
      .confirmStep(confirm('WELCOME_PREFS', st0.version, 'BRL'));
    Test.stopTest();
    System.assertEquals('CONFIRMED', st1.outcome);
    System.assertEquals(1, st1.version, 'version bumped');
    System.assertEquals(
      'PLUGGY_CREDENTIALS',
      st1.currentStep,
      'next unsettled step'
    );
    for (ALT_CLS_AxonOnboardingProgress.StepView v : st1.steps) {
      if (v.stepKey == 'WELCOME_PREFS') {
        System.assertEquals('CONFIRMED', v.status);
        System.assertEquals(1, v.attempt);
        System.assertNotEquals(null, v.confirmedAt);
      }
    }
  }

  @IsTest
  static void confirmStepWithStaleVersionConflicts() {
    allow();
    ALT_CLS_AxonOnboardingProgress.OnboardingState st0 = svc().getState();
    svc().confirmStep(confirm('WELCOME_PREFS', st0.version, 'x'));
    Test.startTest();
    // second session still thinks version is 0
    ALT_CLS_AxonOnboardingProgress.OnboardingState conflict = svc()
      .confirmStep(confirm('PLUGGY_CREDENTIALS', 0, 'y'));
    Test.stopTest();
    System.assertEquals('CONFLICT', conflict.outcome);
    // nothing was overwritten
    AXF_OBJ_OnboardingStep__c cred = [
      SELECT AXF_OST_PKL_Status__c
      FROM AXF_OBJ_OnboardingStep__c
      WHERE AXF_OST_PKL_StepKey__c = 'PLUGGY_CREDENTIALS'
      LIMIT 1
    ];
    System.assertEquals('NOT_STARTED', cred.AXF_OST_PKL_Status__c);
  }

  @IsTest
  static void confirmWithNullExpectedVersionIsRejected() {
    allow();
    svc().getState();
    Test.startTest();
    ALT_CLS_AxonOnboardingProgress.OnboardingState st = svc()
      .confirmStep(confirm('WELCOME_PREFS', null, 'x'));
    Test.stopTest();
    System.assertEquals(
      'CONFLICT',
      st.outcome,
      'no blind write without a read'
    );
  }

  @IsTest
  static void confirmRejectsSecretLikeEvidence() {
    allow();
    ALT_CLS_AxonOnboardingProgress.OnboardingState st0 = svc().getState();
    Test.startTest();
    ALT_CLS_AxonOnboardingProgress.OnboardingState wordHit = svc()
      .confirmStep(
        confirm('PLUGGY_CREDENTIALS', st0.version, 'client_secret=abc')
      );
    ALT_CLS_AxonOnboardingProgress.OnboardingState blobHit = svc()
      .confirmStep(
        confirm(
          'PLUGGY_CREDENTIALS',
          st0.version,
          'aXQK83jfKD93jfHf83hfJDKf83jfPQ0zzTdd12'
        )
      );
    Test.stopTest();
    System.assertEquals('INVALID', wordHit.outcome);
    System.assertEquals('INVALID', blobHit.outcome);
    System.assertEquals(
      'NOT_STARTED',
      [
        SELECT AXF_OST_PKL_Status__c
        FROM AXF_OBJ_OnboardingStep__c
        WHERE AXF_OST_PKL_StepKey__c = 'PLUGGY_CREDENTIALS'
        LIMIT 1
      ]
      .AXF_OST_PKL_Status__c
    );
  }

  @IsTest
  static void confirmAcceptsASalesforceIdAsEvidence() {
    allow();
    ALT_CLS_AxonOnboardingProgress.OnboardingState st0 = svc().getState();
    Test.startTest();
    ALT_CLS_AxonOnboardingProgress.OnboardingState ok = svc()
      .confirmStep(confirm('WELCOME_PREFS', st0.version, UserInfo.getUserId()));
    Test.stopTest();
    System.assertEquals('CONFIRMED', ok.outcome);
  }

  @IsTest
  static void reopenStepMarksLaterConfirmedStepsStale() {
    allow();
    ALT_CLS_AxonOnboardingProgress.OnboardingState s = svc().getState();
    s = svc().confirmStep(confirm('WELCOME_PREFS', s.version, 'a'));
    s = svc().confirmStep(confirm('PLUGGY_CREDENTIALS', s.version, 'b'));
    s = svc().confirmStep(confirm('PLUGGY_DISCOVERY', s.version, 'c'));
    Test.startTest();
    ALT_CLS_AxonOnboardingProgress.OnboardingState reopened = svc()
      .reopenStep('PLUGGY_CREDENTIALS', s.version);
    Test.stopTest();
    System.assertEquals('REOPENED', reopened.outcome);
    System.assert(reopened.staleDetected, 'stale flagged');
    Map<String, String> byKey = new Map<String, String>();
    for (ALT_CLS_AxonOnboardingProgress.StepView v : reopened.steps) {
      byKey.put(v.stepKey, v.status);
    }
    System.assertEquals(
      'CONFIRMED',
      byKey.get('WELCOME_PREFS'),
      'earlier kept'
    );
    System.assertEquals('NOT_STARTED', byKey.get('PLUGGY_CREDENTIALS'));
    System.assertEquals(
      'STALE',
      byKey.get('PLUGGY_DISCOVERY'),
      'later invalidated'
    );
    System.assertEquals(
      'PLUGGY_CREDENTIALS',
      reopened.currentStep,
      'next action points at the reopened step'
    );
  }

  @IsTest
  static void markResultUnknownBlocksConfirmUntilReconcile() {
    allow();
    ALT_CLS_AxonOnboardingProgress.OnboardingState s = svc().getState();
    s = svc().markResultUnknown('PLUGGY_DISCOVERY', s.version, 'corr-123');
    System.assertEquals('UNKNOWN_PARKED', s.outcome);
    Test.startTest();
    ALT_CLS_AxonOnboardingProgress.OnboardingState blocked = svc()
      .confirmStep(confirm('PLUGGY_DISCOVERY', s.version, 'd'));
    Test.stopTest();
    System.assertEquals('BLOCKED_UNKNOWN', blocked.outcome, 'no blind retry');
    for (ALT_CLS_AxonOnboardingProgress.StepView v : blocked.steps) {
      if (v.stepKey == 'PLUGGY_DISCOVERY') {
        System.assertEquals('RESULT_UNKNOWN', v.status);
        System.assertEquals('corr-123', v.correlationId);
      }
    }
  }

  @IsTest
  static void reconcileResolvesResultUnknown() {
    allow();
    ALT_CLS_AxonOnboardingProgress.OnboardingState s = svc().getState();
    s = svc().markResultUnknown('PLUGGY_DISCOVERY', s.version, 'corr-9');
    Test.startTest();
    ALT_CLS_AxonOnboardingProgress.OnboardingState done = svc()
      .reconcileStep('PLUGGY_DISCOVERY', s.version, true, 'item-42');
    Test.stopTest();
    System.assertEquals('RECONCILED', done.outcome);
    System.assertNotEquals(
      null,
      done.lastReconciledAt,
      'reconciliation stamped on the header'
    );
    for (ALT_CLS_AxonOnboardingProgress.StepView v : done.steps) {
      if (v.stepKey == 'PLUGGY_DISCOVERY') {
        System.assertEquals('CONFIRMED', v.status);
        System.assertEquals('item-42', v.evidenceRef);
        System.assertEquals(null, v.correlationId);
      }
    }
  }

  @IsTest
  static void reconcileCanAlsoFailAStep() {
    allow();
    ALT_CLS_AxonOnboardingProgress.OnboardingState s = svc().getState();
    s = svc().markResultUnknown('PLUGGY_CREDENTIALS', s.version, 'c');
    Test.startTest();
    ALT_CLS_AxonOnboardingProgress.OnboardingState f = svc()
      .reconcileStep('PLUGGY_CREDENTIALS', s.version, false, null);
    Test.stopTest();
    for (ALT_CLS_AxonOnboardingProgress.StepView v : f.steps) {
      if (v.stepKey == 'PLUGGY_CREDENTIALS') {
        System.assertEquals('FAILED', v.status);
      }
    }
  }

  @IsTest
  static void optionalStepsCanBeSkippedAndCompletionIgnoresThem() {
    allow();
    ALT_CLS_AxonOnboardingProgress.OnboardingState s = svc().getState();
    s = svc().confirmStep(confirm('WELCOME_PREFS', s.version, 'a'));
    s = svc().confirmStep(confirm('PLUGGY_CREDENTIALS', s.version, 'b'));
    s = svc().confirmStep(confirm('PLUGGY_DISCOVERY', s.version, 'c'));
    s = svc().confirmStep(confirm('ACCOUNT_HOLDERS', s.version, 'd'));
    s = svc().skipStep('PEOPLE_ACCESS', s.version);
    s = svc().skipStep('MANUAL_SOURCES', s.version);
    s = svc().confirmStep(confirm('CURRENCY_PREF', s.version, 'e'));
    System.assertEquals('REVIEW', s.currentStep);
    Test.startTest();
    ALT_CLS_AxonOnboardingProgress.OnboardingState done = svc()
      .complete(s.version, false);
    Test.stopTest();
    System.assertEquals('COMPLETED', done.outcome);
    System.assertEquals('COMPLETED', done.status);
    System.assertEquals('DONE', done.currentStep);
  }

  @IsTest
  static void completeIsRejectedWithRequiredStepsPendingUnlessAcknowledged() {
    allow();
    ALT_CLS_AxonOnboardingProgress.OnboardingState s = svc().getState();
    s = svc().confirmStep(confirm('WELCOME_PREFS', s.version, 'a'));
    Test.startTest();
    ALT_CLS_AxonOnboardingProgress.OnboardingState rej = svc()
      .complete(s.version, false);
    System.assertEquals('INVALID', rej.outcome);
    ALT_CLS_AxonOnboardingProgress.OnboardingState ack = svc()
      .complete(s.version, true);
    Test.stopTest();
    System.assertEquals('COMPLETED', ack.outcome);
  }

  @IsTest
  static void repeatConfirmSameStepIsIdempotentOnRowCount() {
    allow();
    ALT_CLS_AxonOnboardingProgress.OnboardingState s = svc().getState();
    s = svc().confirmStep(confirm('WELCOME_PREFS', s.version, 'a'));
    s = svc().confirmStep(confirm('WELCOME_PREFS', s.version, 'a2'));
    Test.startTest();
    s = svc().confirmStep(confirm('WELCOME_PREFS', s.version, 'a3'));
    Test.stopTest();
    System.assertEquals(
      7,
      [SELECT COUNT() FROM AXF_OBJ_OnboardingStep__c],
      'still one row per step'
    );
    for (ALT_CLS_AxonOnboardingProgress.StepView v : s.steps) {
      if (v.stepKey == 'WELCOME_PREFS') {
        System.assertEquals(3, v.attempt, 'attempt counter grew');
        System.assertEquals('a3', v.evidenceRef);
      }
    }
  }

  @IsTest
  static void unknownStepKeyIsInvalid() {
    allow();
    svc().getState();
    Test.startTest();
    ALT_CLS_AxonOnboardingProgress.OnboardingState st = svc()
      .confirmStep(confirm('NOPE', 0, 'x'));
    Test.stopTest();
    System.assertEquals('INVALID', st.outcome);
  }

  @IsTest
  static void realConfiguratorCanLoadStateAndPlainUserCannot() {
    User gestor = plainUser(true);
    User outsider = plainUser(false);

    Test.startTest();
    System.runAs(gestor) {
      ALT_CLS_AxonOnboardingProgress.OnboardingState ok = new ALT_CLS_AxonOnboardingProgress()
        .getState();
      System.assertEquals(false, ok.forbidden, 'gestor has AXF_CanConfigure');
      System.assertEquals(7, ok.steps.size());
    }
    System.runAs(outsider) {
      ALT_CLS_AxonOnboardingProgress.OnboardingState no = new ALT_CLS_AxonOnboardingProgress()
        .getState();
      System.assert(no.forbidden, 'no authority => forbidden');
      System.assertEquals(0, no.steps.size(), 'history/resume reveal nothing');
    }
    Test.stopTest();
  }

  @IsTest
  static void secretHitHelperMatchesWordsAndBlobsbutNotShortValues() {
    System.assertEquals(
      null,
      ALT_CLS_AxonOnboardingProgress.firstSecretHit('BRL')
    );
    System.assertEquals(
      null,
      ALT_CLS_AxonOnboardingProgress.firstSecretHit(null)
    );
    System.assertNotEquals(
      null,
      ALT_CLS_AxonOnboardingProgress.firstSecretHit('my api-key here')
    );
    System.assertNotEquals(
      null,
      ALT_CLS_AxonOnboardingProgress.firstSecretHit(
        'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcd'
      )
    );
  }
}
