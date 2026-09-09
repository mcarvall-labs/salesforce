/**
 * @description AXF-12 — the sync engine claims per-account scopes, paginates by cursor,
 * publishes exactly one fact per identity idempotently, checkpoints, honours 429/backoff and
 * consent, verifies every DML result, and exposes health. Fictitious data only — no real
 * counterparties reach a fixture.
 */
@IsTest
private class AXF_CLS_PluggySyncServiceTest {
  @TestSetup
  static void seed() {
    AXF_CLS_PluggyTestData.grantIntegrationAccess();
    AXF_CLS_PluggyTestData.config(false, 'A', 'TESTED_OK');
    AXF_OBJ_PluggyConnection__c conn = AXF_CLS_PluggyTestData.connection(
      'ITEMSYNC1'
    );
    AXF_CLS_PluggyTestData.bankAccount(conn.Id, 'ACC-BANK-1', true);
    AXF_CLS_PluggyTestData.creditCard(conn.Id, 'ACC-CARD-1', true);
    AXF_CLS_PluggyTestData.bankAccount(conn.Id, 'ACC-CUSTODY', false);
  }

  static Id connId() {
    return [SELECT Id FROM AXF_OBJ_PluggyConnection__c LIMIT 1].Id;
  }

  static AXF_CLS_PluggySyncService svc() {
    AXF_CLS_PluggySyncService.canConfigureOverride = true;
    AXF_CLS_PluggySyncPolicy.overrideRecord = AXF_CLS_PluggyTestData.syncPolicy(
      100,
      10,
      3
    );
    return new AXF_CLS_PluggySyncService();
  }

  static AXF_CLS_PluggySyncService.ClaimedScope scopeOf(
    List<AXF_CLS_PluggySyncService.ClaimedScope> scopes,
    String kind
  ) {
    for (AXF_CLS_PluggySyncService.ClaimedScope s : scopes) {
      if (s.kind == kind) {
        return s;
      }
    }
    return null;
  }

  static Map<String, Object> row(String id, String amount, String type) {
    return new Map<String, Object>{
      'id' => id,
      'amount' => amount,
      'type' => type
    };
  }

  static AXF_OBJ_IntegrationRun__c runFor(String runKey) {
    return [
      SELECT
        AXF_INR_PKL_State__c,
        AXF_INR_TXT_Cursor__c,
        AXF_INR_NUM_Attempt__c,
        AXF_INR_NUM_RecordsWritten__c,
        AXF_INR_DT_CompleteThrough__c,
        AXF_INR_DT_LastSuccessAt__c,
        AXF_INR_TXT_ActiveToken__c
      FROM AXF_OBJ_IntegrationRun__c
      WHERE AXF_INR_EXI_RunKey__c = :runKey
      LIMIT 1
    ];
  }

  // ------------------------------------------------------------------ claim

  @IsTest
  static void claimsOneScopePerAvailableAccountAndSkipsCustody() {
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());
    Test.startTest();
    List<AXF_CLS_PluggySyncService.ClaimedScope> scopes = svc()
      .claimScopes(connId());
    Test.stopTest();

    System.assertEquals(
      2,
      scopes.size(),
      'one bank + one card, custody excluded'
    );
    System.assertEquals(
      2,
      [
        SELECT COUNT()
        FROM AXF_OBJ_IntegrationRun__c
        WHERE AXF_INR_PKL_State__c = 'RUNNING'
      ]
    );
  }

  @IsTest
  static void claimReusesAnActiveRunInsteadOfFanningOut() {
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());
    Test.startTest();
    svc().claimScopes(connId());
    // second claim, same window: the RUNNING scopes are still fresh -> reused, not re-claimed
    List<AXF_CLS_PluggySyncService.ClaimedScope> again = svc()
      .claimScopes(connId());
    Test.stopTest();

    System.assertEquals(0, again.size(), 'AC1 — no fan-out over an active run');
  }

  @IsTest
  static void claimDeniedWithoutAuthority() {
    AXF_CLS_PluggySyncService.canConfigureOverride = false;
    AXF_CLS_PluggySyncPolicy.overrideRecord = AXF_CLS_PluggyTestData.syncPolicy(
      100,
      10,
      3
    );
    Test.setMock(HttpCalloutMock.class, new AXF_CLS_PluggyHttpCalloutMock());
    try {
      new AXF_CLS_PluggySyncService().claimScopes(connId());
      System.assert(false, 'expected authority failure');
    } catch (AXF_CLS_PluggyDiscoveryException e) {
      System.assert(e.getMessage().containsIgnoreCase('autorizacao'));
    }
  }

  @IsTest
  static void missingPolicyRefusesToRun() {
    AXF_CLS_PluggySyncService.canConfigureOverride = true;
    AXF_CLS_PluggySyncPolicy.overrideRecord = null;
    AXF_CLS_PluggySyncPolicy.forceMissing = true;
    try {
      new AXF_CLS_PluggySyncService().claimScopes(connId());
      System.assert(false, 'expected config failure');
    } catch (AXF_CLS_PluggyConfigException e) {
      System.assert(e.getMessage().containsIgnoreCase('politica'));
    }
  }

  // ------------------------------------------------------------------ run

  @IsTest
  static void bankScopePublishesOneFactPerIdentity() {
    AXF_CLS_PluggyHttpCalloutMock mock = new AXF_CLS_PluggyHttpCalloutMock();
    mock.txPages = new List<String>{
      AXF_CLS_PluggyTestData.txPage(
        new List<Map<String, Object>>{
          row('t-0001', '-25.90', 'DEBIT'),
          row('t-0002', '1000.00', 'CREDIT')
        },
        null
      )
    };
    Test.setMock(HttpCalloutMock.class, mock);

    List<AXF_CLS_PluggySyncService.ClaimedScope> scopes = svc()
      .claimScopes(connId());
    AXF_CLS_PluggySyncService.ClaimedScope bank = scopeOf(scopes, 'BANK');

    Test.startTest();
    AXF_CLS_PluggySyncService.ScopeOutcome out = svc().runScope(bank);
    Test.stopTest();

    System.assertEquals('SUCCEEDED', out.state, out.message);
    System.assertEquals(2, out.recordsWritten);
    System.assertEquals(0, out.recordsFailed);
    System.assertEquals(false, out.moreWork);

    Map<String, AXF_OBJ_BankAccountTransaction__c> byKey = new Map<String, AXF_OBJ_BankAccountTransaction__c>();
    for (AXF_OBJ_BankAccountTransaction__c t : [
      SELECT
        AXF_BAT_EXI_SourceKey__c,
        AXF_BAT_NUM_Magnitude__c,
        AXF_BAT_PKL_Direction__c,
        AXF_BAT_PKL_Source__c,
        AXF_BAT_PKL_Status__c,
        AXF_BAT_TXT_CurrencyIsoCode__c,
        AXF_BAT_TXT_Description__c,
        AXF_BAT_TXT_NormalizedDescription__c
      FROM AXF_OBJ_BankAccountTransaction__c
    ]) {
      byKey.put(t.AXF_BAT_EXI_SourceKey__c, t);
    }
    System.assertEquals(2, byKey.size());
    AXF_OBJ_BankAccountTransaction__c debit = byKey.get('t-0001');
    System.assertEquals(25.90, debit.AXF_BAT_NUM_Magnitude__c, 'abs(amount)');
    System.assertEquals('DEBIT', debit.AXF_BAT_PKL_Direction__c);
    System.assertEquals('PLUGGY', debit.AXF_BAT_PKL_Source__c);
    System.assertEquals('POSTED', debit.AXF_BAT_PKL_Status__c);
    System.assertEquals('BRL', debit.AXF_BAT_TXT_CurrencyIsoCode__c);
    System.assert(
      String.isNotBlank(debit.AXF_BAT_TXT_NormalizedDescription__c),
      'AC3 normalized description'
    );

    AXF_OBJ_IntegrationRun__c run = runFor(bank.runKey);
    System.assertNotEquals(null, run.AXF_INR_DT_CompleteThrough__c, 'AC6');
    System.assertNotEquals(null, run.AXF_INR_DT_LastSuccessAt__c, 'AC6');
    System.assertEquals(null, run.AXF_INR_TXT_ActiveToken__c, 'token released');
  }

  @IsTest
  static void cardScopeMapsBillReferenceFromMetadata() {
    AXF_CLS_PluggyHttpCalloutMock mock = new AXF_CLS_PluggyHttpCalloutMock();
    Map<String, Object> r = row('c-0001', '-120.00', 'DEBIT');
    r.put('billId', 'BILL-2026-09');
    mock.txPages = new List<String>{
      AXF_CLS_PluggyTestData.txPage(new List<Map<String, Object>>{ r }, null)
    };
    Test.setMock(HttpCalloutMock.class, mock);

    List<AXF_CLS_PluggySyncService.ClaimedScope> scopes = svc()
      .claimScopes(connId());
    AXF_CLS_PluggySyncService.ClaimedScope card = scopeOf(scopes, 'CARD');

    Test.startTest();
    AXF_CLS_PluggySyncService.ScopeOutcome out = svc().runScope(card);
    Test.stopTest();

    System.assertEquals('SUCCEEDED', out.state, out.message);
    AXF_OBJ_CreditCardTransaction__c t = [
      SELECT
        AXF_CCT_TXT_BillReference__c,
        AXF_CCT_TXT_BillForecastPeriod__c,
        AXF_CCT_NUM_Magnitude__c
      FROM AXF_OBJ_CreditCardTransaction__c
      LIMIT 1
    ];
    System.assertEquals('BILL-2026-09', t.AXF_CCT_TXT_BillReference__c);
    System.assertEquals('2026-09', t.AXF_CCT_TXT_BillForecastPeriod__c);
    System.assertEquals(120.00, t.AXF_CCT_NUM_Magnitude__c);
  }

  @IsTest
  static void replayReusesTheSameFact() {
    // A fact with the same provider identity already exists (an earlier sync / reconnection).
    AXF_OBJ_BankAccount__c ba = [
      SELECT Id
      FROM AXF_OBJ_BankAccount__c
      WHERE AXF_BA_EXI_PluggyAccountId__c = 'ACC-BANK-1'
    ];
    insert new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_MDR_BankAccount__c = ba.Id,
      AXF_BAT_EXI_SourceKey__c = 'dup-1',
      AXF_BAT_PKL_Source__c = 'PLUGGY',
      AXF_BAT_DAT_Date__c = Date.newInstance(2026, 9, 4),
      AXF_BAT_NUM_Magnitude__c = 10.00,
      AXF_BAT_PKL_Direction__c = 'DEBIT',
      AXF_BAT_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BAT_NUM_Version__c = 0
    );

    AXF_CLS_PluggyHttpCalloutMock mock = new AXF_CLS_PluggyHttpCalloutMock();
    mock.txPages = new List<String>{
      AXF_CLS_PluggyTestData.txPage(
        new List<Map<String, Object>>{ row('dup-1', '-10.00', 'DEBIT') },
        null
      )
    };
    Test.setMock(HttpCalloutMock.class, mock);
    AXF_CLS_PluggySyncService.ClaimedScope bank = scopeOf(
      svc().claimScopes(connId()),
      'BANK'
    );

    Test.startTest();
    AXF_CLS_PluggySyncService.ScopeOutcome out = svc().runScope(bank);
    Test.stopTest();

    System.assertEquals('SUCCEEDED', out.state, out.message);
    System.assertEquals(
      1,
      [SELECT COUNT() FROM AXF_OBJ_BankAccountTransaction__c],
      'AC4 — one fact per identity, never duplicated'
    );
  }

  static AXF_CLS_PluggyHttpCalloutMock twoPageMock() {
    AXF_CLS_PluggyHttpCalloutMock mock = new AXF_CLS_PluggyHttpCalloutMock();
    mock.txPages = new List<String>{
      AXF_CLS_PluggyTestData.txPage(
        new List<Map<String, Object>>{ row('p0', '-1.00', 'DEBIT') },
        '1'
      ),
      AXF_CLS_PluggyTestData.txPage(
        new List<Map<String, Object>>{ row('p1', '-2.00', 'DEBIT') },
        null
      )
    };
    return mock;
  }

  @IsTest
  static void sourceDeltaCreatesReviewAndCountsOnlyNewFacts() {
    AXF_OBJ_BankAccount__c bankAccount = [
      SELECT Id
      FROM AXF_OBJ_BankAccount__c
      WHERE AXF_BA_EXI_PluggyAccountId__c = 'ACC-BANK-1'
    ];
    AXF_OBJ_BankAccountTransaction__c original = new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_MDR_BankAccount__c = bankAccount.Id,
      AXF_BAT_EXI_SourceKey__c = 'changed',
      AXF_BAT_PKL_Source__c = 'PLUGGY',
      AXF_BAT_NUM_Magnitude__c = 10,
      AXF_BAT_DAT_Date__c = Date.newInstance(2026, 9, 4),
      AXF_BAT_PKL_Direction__c = 'DEBIT',
      AXF_BAT_PKL_Status__c = 'POSTED',
      AXF_BAT_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BAT_TXT_Description__c = 'COMPRA EXEMPLO LTDA',
      AXF_BAT_TXT_NormalizedDescription__c = 'preserved normalization'
    );
    insert original;
    AXF_CLS_PluggyHttpCalloutMock mock = new AXF_CLS_PluggyHttpCalloutMock();
    mock.txPages = new List<String>{
      AXF_CLS_PluggyTestData.txPage(
        new List<Map<String, Object>>{
          row('changed', '-12', 'DEBIT'),
          row('new-fact', '-3', 'DEBIT')
        },
        null
      )
    };
    Test.setMock(HttpCalloutMock.class, mock);
    AXF_CLS_PluggySyncService.ClaimedScope bankScope = scopeOf(
      svc().claimScopes(connId()),
      'BANK'
    );
    Test.startTest();
    AXF_CLS_PluggySyncService.ScopeOutcome outcome = svc().runScope(bankScope);
    Test.stopTest();
    Assert.areEqual(
      'SUCCEEDED',
      outcome.state,
      'Accepted evidence permits completion.'
    );
    Assert.areEqual(1, outcome.recordsWritten, 'Only the new fact is written.');
    Assert.areEqual(
      0,
      outcome.recordsFailed,
      'Both accepted rows are accounted for.'
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AXF_OBJ_ReviewItem__c
        WHERE
          AXF_RVI_NUM_PriorAmount__c = 10
          AND AXF_RVI_NUM_ProposedAmount__c = 12
      ],
      'Typed delta evidence is persisted.'
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AXF_OBJ_BankAccountTransaction__c
        WHERE
          Id = :original.Id
          AND AXF_BAT_NUM_Magnitude__c = 10
          AND AXF_BAT_TXT_NormalizedDescription__c = 'preserved normalization'
      ],
      'Published source remains unchanged.'
    );
  }

  @IsTest
  static void invalidProviderFactRetainsTheCheckpoint() {
    AXF_CLS_PluggyHttpCalloutMock mock = new AXF_CLS_PluggyHttpCalloutMock();
    Map<String, Object> invalid = row('invalid', '-12', 'DEBIT');
    invalid.put('date', 'not-a-date');
    mock.txPages = new List<String>{
      AXF_CLS_PluggyTestData.txPage(
        new List<Map<String, Object>>{ invalid },
        null
      )
    };
    Test.setMock(HttpCalloutMock.class, mock);
    AXF_CLS_PluggySyncService.ClaimedScope bankScope = scopeOf(
      svc().claimScopes(connId()),
      'BANK'
    );
    Test.startTest();
    AXF_CLS_PluggySyncService.ScopeOutcome outcome = svc().runScope(bankScope);
    Test.stopTest();
    Assert.areEqual(
      'FAILED_RETRYABLE',
      outcome.state,
      'Invalid evidence cannot mark an interval complete.'
    );
    Assert.areEqual(1, outcome.recordsFailed, 'Rejected row is counted.');
    Assert.isNull(
      runFor(bankScope.runKey).AXF_INR_DT_CompleteThrough__c,
      'Incomplete interval does not advance completeness.'
    );
    Assert.areEqual(
      bankScope.startCursor,
      runFor(bankScope.runKey).AXF_INR_TXT_Cursor__c,
      'Retry starts from the original checkpoint.'
    );
  }

  @IsTest
  static void checkpointPausesAtTheCadence() {
    AXF_CLS_PluggySyncService.canConfigureOverride = true;
    AXF_CLS_PluggySyncPolicy.overrideRecord = AXF_CLS_PluggyTestData.syncPolicy(
      100,
      1, // checkpoint every single page
      3
    );
    Test.setMock(HttpCalloutMock.class, twoPageMock());
    AXF_CLS_PluggySyncService.ClaimedScope bank = scopeOf(
      new AXF_CLS_PluggySyncService().claimScopes(connId()),
      'BANK'
    );

    Test.startTest();
    AXF_CLS_PluggySyncService.ScopeOutcome first = new AXF_CLS_PluggySyncService()
      .runScope(bank);
    Test.stopTest();

    System.assertEquals('RUNNING', first.state, 'paused at checkpoint');
    System.assertEquals(true, first.moreWork);
    System.assertEquals('1', first.resumeCursor);
    System.assertEquals(
      '1',
      runFor(bank.runKey).AXF_INR_TXT_Cursor__c,
      'checkpoint persisted before the risky unit (AC2)'
    );
  }

  @IsTest
  static void resumeContinuesFromTheCheckpointCursor() {
    AXF_CLS_PluggySyncService.canConfigureOverride = true;
    AXF_CLS_PluggySyncPolicy.overrideRecord = AXF_CLS_PluggyTestData.syncPolicy(
      100,
      10,
      3
    );
    String runKey = AXF_CLS_PluggySyncService.runKeyFor(connId(), 'ACC-BANK-1');
    insert new AXF_OBJ_IntegrationRun__c(
      AXF_INR_EXI_RunKey__c = runKey,
      AXF_INR_LKP_Connection__c = connId(),
      AXF_INR_PKL_Product__c = 'TRANSACTIONS',
      AXF_INR_PKL_State__c = 'FAILED_RETRYABLE',
      AXF_INR_TXT_Cursor__c = '1',
      AXF_INR_NUM_Attempt__c = 1,
      AXF_INR_NUM_Version__c = 2
    );
    Test.setMock(HttpCalloutMock.class, twoPageMock());
    AXF_CLS_PluggySyncService.ClaimedScope bank = scopeOf(
      new AXF_CLS_PluggySyncService().claimScopes(connId()),
      'BANK'
    );
    System.assertEquals('1', bank.startCursor, 'claim resumes from the cursor');

    Test.startTest();
    AXF_CLS_PluggySyncService.ScopeOutcome out = new AXF_CLS_PluggySyncService()
      .runScope(bank);
    Test.stopTest();

    System.assertEquals('SUCCEEDED', out.state, out.message);
    System.assertEquals(
      1,
      [SELECT COUNT() FROM AXF_OBJ_BankAccountTransaction__c],
      'only page 1 (the resumed page) is fetched'
    );
    System.assertEquals(
      'p1',
      [SELECT AXF_BAT_EXI_SourceKey__c FROM AXF_OBJ_BankAccountTransaction__c]
      .AXF_BAT_EXI_SourceKey__c
    );
  }

  @IsTest
  static void rateLimitLeavesRetryableWithBackoff() {
    AXF_CLS_PluggyHttpCalloutMock mock = new AXF_CLS_PluggyHttpCalloutMock();
    mock.txStatus = 429;
    mock.txRetryAfterSeconds = 120;
    Test.setMock(HttpCalloutMock.class, mock);

    AXF_CLS_PluggySyncService.ClaimedScope bank = scopeOf(
      svc().claimScopes(connId()),
      'BANK'
    );

    Test.startTest();
    AXF_CLS_PluggySyncService.ScopeOutcome out = svc().runScope(bank);
    Test.stopTest();

    System.assertEquals('FAILED_RETRYABLE', out.state);
    System.assertEquals(120, out.retryAfterSeconds, 'Retry-After honoured');
    System.assertEquals(true, out.moreWork);
    System.assertEquals(1, runFor(bank.runKey).AXF_INR_NUM_Attempt__c);
  }

  @IsTest
  static void forbiddenIsTerminal() {
    AXF_CLS_PluggyHttpCalloutMock mock = new AXF_CLS_PluggyHttpCalloutMock();
    mock.txStatus = 403;
    Test.setMock(HttpCalloutMock.class, mock);

    AXF_CLS_PluggySyncService.ClaimedScope bank = scopeOf(
      svc().claimScopes(connId()),
      'BANK'
    );

    Test.startTest();
    AXF_CLS_PluggySyncService.ScopeOutcome out = svc().runScope(bank);
    Test.stopTest();

    System.assertEquals('FAILED_TERMINAL', out.state);
    System.assertEquals(false, out.moreWork);
  }

  @IsTest
  static void consentLostDuringSyncIsTerminalAndNotMarkedCurrent() {
    AXF_CLS_PluggyHttpCalloutMock mock = new AXF_CLS_PluggyHttpCalloutMock();
    mock.txPages = new List<String>{
      AXF_CLS_PluggyTestData.txPage(
        new List<Map<String, Object>>{ row('x-1', '-5.00', 'DEBIT') },
        null
      )
    };
    mock.itemBodyStatus = 'LOGIN_ERROR'; // consent refresh -> REVOKED
    Test.setMock(HttpCalloutMock.class, mock);

    AXF_CLS_PluggySyncService.ClaimedScope bank = scopeOf(
      svc().claimScopes(connId()),
      'BANK'
    );

    Test.startTest();
    AXF_CLS_PluggySyncService.ScopeOutcome out = svc().runScope(bank);
    Test.stopTest();

    System.assertEquals('FAILED_TERMINAL', out.state, out.message);
    System.assertEquals(
      null,
      runFor(bank.runKey).AXF_INR_DT_CompleteThrough__c,
      'AC5 — incomplete interval is never marked current'
    );
  }

  @IsTest
  static void healthReportsStateAndNextAction() {
    AXF_CLS_PluggyHttpCalloutMock mock = new AXF_CLS_PluggyHttpCalloutMock();
    mock.txPages = new List<String>{
      AXF_CLS_PluggyTestData.txPage(
        new List<Map<String, Object>>{ row('h-1', '-9.00', 'DEBIT') },
        null
      )
    };
    Test.setMock(HttpCalloutMock.class, mock);
    AXF_CLS_PluggySyncService.ClaimedScope bank = scopeOf(
      svc().claimScopes(connId()),
      'BANK'
    );

    Test.startTest();
    svc().runScope(bank);
    List<AXF_CLS_PluggySyncService.HealthRow> rows = svc().health(connId());
    Test.stopTest();

    Boolean sawSucceeded = false;
    for (AXF_CLS_PluggySyncService.HealthRow h : rows) {
      if (h.state == 'SUCCEEDED') {
        sawSucceeded = true;
        System.assertEquals('Nenhuma acao necessaria.', h.nextAction);
        System.assertNotEquals(null, h.completeThrough);
      }
    }
    System.assert(sawSucceeded, 'health surfaces the succeeded scope');
  }

  @IsTest
  static void unknownTransportResultIsRetryableNotSuccess() {
    AXF_CLS_PluggyHttpCalloutMock mock = new AXF_CLS_PluggyHttpCalloutMock();
    mock.throwOnTransactions = true;
    Test.setMock(HttpCalloutMock.class, mock);

    AXF_CLS_PluggySyncService.ClaimedScope bank = scopeOf(
      svc().claimScopes(connId()),
      'BANK'
    );

    Test.startTest();
    AXF_CLS_PluggySyncService.ScopeOutcome out = svc().runScope(bank);
    Test.stopTest();

    System.assertEquals('FAILED_RETRYABLE', out.state);
    System.assert(out.state != 'SUCCEEDED');
  }
}
