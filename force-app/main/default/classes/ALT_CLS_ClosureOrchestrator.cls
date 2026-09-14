/**
 * @description Orquestracao central do encerramento local de um titular (AXF-119, fatia de
 * AXF-9). Sequencia fixa e auditavel: EXPORT -> REVOKE_ACCESS -> STOP_COLLECTION -> PURGE ->
 * RETAIN_EVIDENCE -> CLOSED (terminal). Cada etapa e idempotente (checkpoint persistido em
 * AXF_OBJ_ClosureRun__c), observavel (correlacao, progresso, ultimo ponto, impacto, proxima
 * acao segura) e retomavel pelo mesmo escopo; etapa material nao se repete enquanto o resultado
 * anterior nao for reconciliado (RESULT_UNKNOWN) ou o bloqueio removido (BLOCKED).
 *
 * Limites desta fatia: a exportacao (historia irma) anexa sua evidencia via attachExportEvidence;
 * estados bloqueados/Pluggy externos e a invariante de restore sao historias irmas. Nunca executa
 * DELETE /items na Pluggy; nao concede Delete; ausencia de policy de retencao nao expurga.
 */
public with sharing class ALT_CLS_ClosureOrchestrator {
  public static final String CP_CLOSE = 'AXF_CanCloseInstallation';
  public static final List<String> STAGES = new List<String>{
    'EXPORT',
    'REVOKE_ACCESS',
    'STOP_COLLECTION',
    'PURGE',
    'RETAIN_EVIDENCE'
  };
  public static final String DOMAIN_TRANSACTION_DESCRIPTION = 'closure.transaction.description';
  public static final List<String> REVALIDATED_DOMAINS = new List<String>{
    'csv.raw',
    'documents',
    'backup'
  };
  private static final String PURGE_TRIGGER = 'CLOSURE';

  /** Test seam: stage name whose material effect must be reported as RESULT_UNKNOWN. */
  @TestVisible
  private static String simulateUnknownAt;
  /** Last stage failure (type + message) kept for diagnostics; never surfaced to the client. */
  @TestVisible
  private static String lastStageFailure;

  public class ClosureException extends Exception {
    public String code;
  }

  public class StageCheckpoint {
    @AuraEnabled
    public String stage;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Integer attempt;
    @AuraEnabled
    public String effectKey;
    @AuraEnabled
    public String completedAt;
    @AuraEnabled
    public String reason;
    @AuraEnabled
    public Map<String, Integer> impact = new Map<String, Integer>();
  }

  public class RunView {
    @AuraEnabled
    public Id runId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String lastCompletedStage;
    @AuraEnabled
    public Integer progressPercent;
    @AuraEnabled
    public String correlationId;
    @AuraEnabled
    public Integer attempt;
    @AuraEnabled
    public String blockReason;
    @AuraEnabled
    public String nextAction;
    @AuraEnabled
    public Datetime lastCompletedAt;
    @AuraEnabled
    public String externalRevocation;
    @AuraEnabled
    public Boolean legalHold;
    @AuraEnabled
    public String exportEvidenceRef;
    @AuraEnabled
    public Decimal version;
    @AuraEnabled
    public List<StageCheckpoint> checkpoints = new List<StageCheckpoint>();
    @AuraEnabled
    public Boolean closed;
    @AuraEnabled
    public Boolean canAdvance;
    @AuraEnabled
    public Boolean canReconcile;
  }

  private class StageOutcome {
    String status = 'DONE'; // DONE | BLOCKED | RESULT_UNKNOWN
    String reason;
    String nextAction;
    Map<String, Integer> impact = new Map<String, Integer>();
    Map<String, Object> evidence = new Map<String, Object>();
  }

  // ---------------------------------------------------------------- public API

  /** Starts (or returns) the single run of the scope; the same scope always resumes the same run. */
  public RunView request(Id accountId, Boolean legalHold) {
    Account holder = authorizedHolder(accountId);
    String scopeKey = String.valueOf(holder.Id);
    List<AXF_OBJ_ClosureRun__c> existing = [
      SELECT Id
      FROM AXF_OBJ_ClosureRun__c
      WHERE AXF_CLR_EXI_ScopeKey__c = :scopeKey
      WITH USER_MODE
      LIMIT 1
    ];
    if (!existing.isEmpty()) {
      return read(existing[0].Id);
    }
    AXF_OBJ_ClosureRun__c run = new AXF_OBJ_ClosureRun__c(
      AXF_CLR_LKP_Account__c = holder.Id,
      AXF_CLR_EXI_ScopeKey__c = scopeKey,
      AXF_CLR_PKL_Status__c = 'REQUESTED',
      AXF_CLR_PKL_Stage__c = 'NONE',
      AXF_CLR_TXT_CorrelationId__c = 'closure-' +
        EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 24),
      AXF_CLR_NUM_Attempt__c = 0,
      AXF_CLR_BOL_LegalHold__c = legalHold == true,
      AXF_CLR_PKL_ExternalRevocation__c = 'NOT_APPLICABLE',
      AXF_CLR_TXT_NextAction__c = 'RESUME',
      AXF_CLR_TAL_Checkpoints__c = '[]',
      AXF_CLR_NUM_Version__c = 1,
      OwnerId = holder.OwnerId
    );
    Database.insert(run, AccessLevel.USER_MODE);
    return read(run.Id);
  }

  /** The export story attaches its evidence here; unblocks the EXPORT stage. */
  public RunView attachExportEvidence(
    Id runId,
    String evidenceRef,
    Decimal expectedVersion
  ) {
    if (String.isBlank(evidenceRef)) {
      throw failure('INVALID_INPUT');
    }
    AXF_OBJ_ClosureRun__c run = load(runId, expectedVersion);
    if (run.AXF_CLR_PKL_Status__c == 'CLOSED') {
      throw failure('TERMINAL');
    }
    run.AXF_CLR_TXT_ExportEvidenceRef__c = evidenceRef.left(64);
    if (
      run.AXF_CLR_PKL_Status__c == 'BLOCKED' &&
      run.AXF_CLR_TXT_BlockReason__c == 'EXPORT_PENDING'
    ) {
      run.AXF_CLR_PKL_Status__c = 'REQUESTED';
      run.AXF_CLR_TXT_BlockReason__c = null;
      run.AXF_CLR_TXT_NextAction__c = 'RESUME';
    }
    run.AXF_CLR_NUM_Version__c = nz(run.AXF_CLR_NUM_Version__c) + 1;
    Database.update(run, AccessLevel.USER_MODE);
    return read(run.Id);
  }

  /** Operator reconciles a RESULT_UNKNOWN stage after verifying its effect; only then may it repeat. */
  public RunView reconcile(Id runId, Decimal expectedVersion) {
    AXF_OBJ_ClosureRun__c run = load(runId, expectedVersion);
    if (run.AXF_CLR_PKL_Status__c != 'RESULT_UNKNOWN') {
      throw failure('NOT_RECONCILABLE');
    }
    run.AXF_CLR_PKL_Status__c = 'REQUESTED';
    run.AXF_CLR_TXT_BlockReason__c = null;
    run.AXF_CLR_TXT_NextAction__c = 'RESUME';
    run.AXF_CLR_NUM_Version__c = nz(run.AXF_CLR_NUM_Version__c) + 1;
    Database.update(run, AccessLevel.USER_MODE);
    return read(run.Id);
  }

  /**
   * Executes the remaining stages in order, one checkpoint per stage, stopping at the first
   * BLOCKED or RESULT_UNKNOWN. Completed stages are never executed again.
   */
  public RunView advance(Id runId, Decimal expectedVersion) {
    AXF_OBJ_ClosureRun__c run = load(runId, expectedVersion);
    if (run.AXF_CLR_PKL_Status__c == 'CLOSED') {
      throw failure('TERMINAL');
    }
    if (run.AXF_CLR_PKL_Status__c == 'RESULT_UNKNOWN') {
      throw failure('RECONCILE_FIRST');
    }
    Account holder = authorizedHolder(run.AXF_CLR_LKP_Account__c);
    List<StageCheckpoint> checkpoints = parseCheckpoints(
      run.AXF_CLR_TAL_Checkpoints__c
    );
    Integer attempt = Integer.valueOf(nz(run.AXF_CLR_NUM_Attempt__c)) + 1;
    run.AXF_CLR_NUM_Attempt__c = attempt;
    run.AXF_CLR_PKL_Status__c = 'RUNNING';
    run.AXF_CLR_TXT_BlockReason__c = null;
    run.AXF_CLR_TXT_NextAction__c = null;

    Integer start = STAGES.indexOf(run.AXF_CLR_PKL_Stage__c) + 1;
    for (Integer i = start; i < STAGES.size(); i++) {
      String stage = STAGES[i];
      String effectKey = stage + ':' + attempt;
      Savepoint point = Database.setSavepoint();
      StageOutcome outcome;
      try {
        outcome = execute(stage, run, holder, checkpoints);
      } catch (Exception failure) {
        Database.rollback(point);
        lastStageFailure =
          failure.getTypeName() +
          ': ' +
          failure.getMessage() +
          ' @ ' +
          failure.getStackTraceString();
        outcome = new StageOutcome();
        outcome.status = 'BLOCKED';
        outcome.reason = 'STAGE_FAILED';
        outcome.nextAction = 'RESUME';
      }
      if (simulateUnknownAt == stage) {
        outcome.status = 'RESULT_UNKNOWN';
        outcome.reason = 'RESULT_UNKNOWN';
        outcome.nextAction = 'RECONCILE';
      }
      StageCheckpoint checkpoint = new StageCheckpoint();
      checkpoint.stage = stage;
      checkpoint.status = outcome.status;
      checkpoint.attempt = attempt;
      checkpoint.effectKey = effectKey;
      checkpoint.reason = outcome.reason;
      checkpoint.impact = outcome.impact;
      checkpoint.completedAt = String.valueOf(Datetime.now());
      checkpoints.add(checkpoint);
      run.AXF_CLR_TXT_LastEffectKey__c = effectKey;
      if (outcome.status != 'DONE') {
        run.AXF_CLR_PKL_Status__c = outcome.status;
        run.AXF_CLR_TXT_BlockReason__c = outcome.reason;
        run.AXF_CLR_TXT_NextAction__c = outcome.nextAction;
        break;
      }
      run.AXF_CLR_PKL_Stage__c = stage;
      run.AXF_CLR_DT_LastCompletedAt__c = Datetime.now();
      if (outcome.evidence.containsKey('policyVersion')) {
        run.AXF_CLR_TXT_PolicyVersion__c = String.valueOf(
            outcome.evidence.get('policyVersion')
          )
          .left(120);
      }
      if (outcome.evidence.containsKey('externalRevocation')) {
        run.AXF_CLR_PKL_ExternalRevocation__c = String.valueOf(
          outcome.evidence.get('externalRevocation')
        );
      }
      if (stage == 'RETAIN_EVIDENCE') {
        run.AXF_CLR_TAL_EvidenceSummary__c = evidenceSummary(run, checkpoints);
        run.AXF_CLR_PKL_Status__c = 'CLOSED';
        run.AXF_CLR_TXT_NextAction__c = 'NONE';
      }
    }
    run.AXF_CLR_TAL_Checkpoints__c = JSON.serialize(checkpoints);
    run.AXF_CLR_NUM_Version__c = nz(run.AXF_CLR_NUM_Version__c) + 1;
    Database.update(run, AccessLevel.USER_MODE);
    return read(run.Id);
  }

  public RunView read(Id runId) {
    if (runId == null) {
      throw failure('INVALID_INPUT');
    }
    List<AXF_OBJ_ClosureRun__c> rows = [
      SELECT
        Id,
        Name,
        AXF_CLR_LKP_Account__c,
        AXF_CLR_LKP_Account__r.Name,
        AXF_CLR_PKL_Status__c,
        AXF_CLR_PKL_Stage__c,
        AXF_CLR_TXT_CorrelationId__c,
        AXF_CLR_NUM_Attempt__c,
        AXF_CLR_TXT_BlockReason__c,
        AXF_CLR_TXT_NextAction__c,
        AXF_CLR_DT_LastCompletedAt__c,
        AXF_CLR_PKL_ExternalRevocation__c,
        AXF_CLR_BOL_LegalHold__c,
        AXF_CLR_TXT_ExportEvidenceRef__c,
        AXF_CLR_NUM_Version__c,
        AXF_CLR_TAL_Checkpoints__c
      FROM AXF_OBJ_ClosureRun__c
      WHERE Id = :runId
      WITH USER_MODE
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      throw failure('NOT_ACCESSIBLE');
    }
    AXF_OBJ_ClosureRun__c run = rows[0];
    RunView view = new RunView();
    view.runId = run.Id;
    view.name = run.Name;
    view.accountId = run.AXF_CLR_LKP_Account__c;
    view.accountName = run.AXF_CLR_LKP_Account__r?.Name;
    view.status = run.AXF_CLR_PKL_Status__c;
    view.lastCompletedStage = run.AXF_CLR_PKL_Stage__c;
    Integer done = STAGES.indexOf(run.AXF_CLR_PKL_Stage__c) + 1;
    view.progressPercent = (done * 100) / STAGES.size();
    view.correlationId = run.AXF_CLR_TXT_CorrelationId__c;
    view.attempt = Integer.valueOf(nz(run.AXF_CLR_NUM_Attempt__c));
    view.blockReason = run.AXF_CLR_TXT_BlockReason__c;
    view.nextAction = run.AXF_CLR_TXT_NextAction__c;
    view.lastCompletedAt = run.AXF_CLR_DT_LastCompletedAt__c;
    view.externalRevocation = run.AXF_CLR_PKL_ExternalRevocation__c;
    view.legalHold = run.AXF_CLR_BOL_LegalHold__c;
    view.exportEvidenceRef = run.AXF_CLR_TXT_ExportEvidenceRef__c;
    view.version = run.AXF_CLR_NUM_Version__c;
    view.checkpoints = parseCheckpoints(run.AXF_CLR_TAL_Checkpoints__c);
    view.closed = run.AXF_CLR_PKL_Status__c == 'CLOSED';
    view.canReconcile = run.AXF_CLR_PKL_Status__c == 'RESULT_UNKNOWN';
    view.canAdvance = !view.closed && !view.canReconcile;
    return view;
  }

  public List<RunView> listRuns() {
    List<RunView> result = new List<RunView>();
    for (AXF_OBJ_ClosureRun__c run : [
      SELECT Id
      FROM AXF_OBJ_ClosureRun__c
      WITH USER_MODE
      ORDER BY LastModifiedDate DESC
      LIMIT 50
    ]) {
      result.add(read(run.Id));
    }
    return result;
  }

  // ---------------------------------------------------------------- stages

  private StageOutcome execute(
    String stage,
    AXF_OBJ_ClosureRun__c run,
    Account holder,
    List<StageCheckpoint> checkpoints
  ) {
    if (stage == 'EXPORT') {
      return stageExport(run);
    }
    if (stage == 'REVOKE_ACCESS') {
      return stageRevokeAccess(holder);
    }
    if (stage == 'STOP_COLLECTION') {
      return stageStopCollection(holder);
    }
    if (stage == 'PURGE') {
      return stagePurge(run, holder);
    }
    return stageRetainEvidence(holder);
  }

  /** Export is delivered by the sibling story; without its evidence the run stays safely blocked. */
  private StageOutcome stageExport(AXF_OBJ_ClosureRun__c run) {
    StageOutcome outcome = new StageOutcome();
    if (String.isBlank(run.AXF_CLR_TXT_ExportEvidenceRef__c)) {
      outcome.status = 'BLOCKED';
      outcome.reason = 'EXPORT_PENDING';
      outcome.nextAction = 'ATTACH_EXPORT_EVIDENCE';
      return outcome;
    }
    outcome.impact.put('exportEvidence', 1);
    return outcome;
  }

  /** Withdraws local derived access: collaboration grants and company-responsible grants. */
  private StageOutcome stageRevokeAccess(Account holder) {
    StageOutcome outcome = new StageOutcome();
    Id accountId = holder.Id;
    // AXF-6 collaboration grants are revoked when that object is installed (resolved
    // dynamically so this slice does not depend on the AXF-6 merge order).
    Integer revokedGrants = 0;
    Schema.SObjectType grantType = Schema.getGlobalDescribe()
      .get('axf_obj_sharedexpensegrant__c');
    if (grantType != null && !grantType.getDescribe().isUpdateable()) {
      // Installed but not granted to this operator: refuse to skip derived access silently.
      outcome.status = 'BLOCKED';
      outcome.reason = 'GRANTS_NOT_ACCESSIBLE';
      outcome.nextAction = 'RESUME';
      return outcome;
    }
    if (grantType != null) {
      List<SObject> grants = Database.queryWithBinds(
        'SELECT Id, AXF_SEG_NUM_Version__c FROM AXF_OBJ_SharedExpenseGrant__c ' +
          'WHERE AXF_SEG_PKL_Status__c = \'ACTIVE\' ' +
          'AND AXF_SEG_LKP_FinancialTransaction__r.AXF_FTX_LKP_Account__c = :accountId',
        new Map<String, Object>{ 'accountId' => accountId },
        AccessLevel.USER_MODE
      );
      for (SObject grant : grants) {
        grant.put('AXF_SEG_PKL_Status__c', 'REVOKED');
        grant.put('AXF_SEG_DT_RevokedAt__c', Datetime.now());
        grant.put('AXF_SEG_LKP_RevokedBy__c', UserInfo.getUserId());
        grant.put(
          'AXF_SEG_NUM_Version__c',
          nz((Decimal) grant.get('AXF_SEG_NUM_Version__c')) + 1
        );
      }
      if (!grants.isEmpty()) {
        Database.update(grants, AccessLevel.USER_MODE);
      }
      revokedGrants = grants.size();
    }
    outcome.impact.put('collaborationGrantsRevoked', revokedGrants);

    // Company-responsible grants are owned by the AXF-83 service (privileged gateway);
    // listing and revocation go through it so its own authorization applies.
    Integer responsibles = 0;
    ALT_CLS_AxonCompanyResponsible responsibility = new ALT_CLS_AxonCompanyResponsible();
    for (
      ALT_CLS_AxonCompanyResponsible.ResponsibilityView access : responsibility.getResponsibilities(
        accountId
      )
    ) {
      if (access.status != 'GRANTED') {
        continue;
      }
      ALT_CLS_AxonCompanyResponsible.ResponsibilityView view = responsibility.revokeResponsibility(
        access.craId,
        access.version
      );
      if (view.outcome != 'REVOKED' && view.outcome != 'ALREADY') {
        outcome.status = 'BLOCKED';
        outcome.reason = 'REVOCATION_FAILED';
        outcome.nextAction = 'RESUME';
        return outcome;
      }
      responsibles++;
    }
    outcome.impact.put('companyResponsiblesRevoked', responsibles);
    return outcome;
  }

  /** Stops collection and publication for the scope; never calls the provider. */
  private StageOutcome stageStopCollection(Account holder) {
    StageOutcome outcome = new StageOutcome();
    Id accountId = holder.Id;
    AXF_CLS_PluggyCollectionControlService control = new AXF_CLS_PluggyCollectionControlService();
    Integer paused = 0;
    List<AXF_OBJ_PluggyConnection__c> connections = [
      SELECT Id, AXF_CON_PKL_CollectionState__c
      FROM AXF_OBJ_PluggyConnection__c
      WHERE AXF_CON_LKP_Account__c = :accountId
      WITH USER_MODE
    ];
    for (AXF_OBJ_PluggyConnection__c connection : connections) {
      if (connection.AXF_CON_PKL_CollectionState__c != 'PAUSED') {
        control.pauseConnection(connection.Id);
        paused++;
      }
    }
    outcome.impact.put('connectionsPaused', paused);
    outcome.evidence.put(
      'externalRevocation',
      connections.isEmpty() ? 'NOT_APPLICABLE' : 'NOT_CONFIRMED'
    );

    List<AXF_OBJ_BankAccount__c> banks = [
      SELECT Id
      FROM AXF_OBJ_BankAccount__c
      WHERE
        AXF_BA_LKP_Account__c = :accountId
        AND AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE'
      WITH USER_MODE
    ];
    for (AXF_OBJ_BankAccount__c bank : banks) {
      bank.AXF_BA_PKL_AvailabilityState__c = 'CUSTODY';
    }
    List<AXF_OBJ_CreditCard__c> cards = [
      SELECT Id
      FROM AXF_OBJ_CreditCard__c
      WHERE
        AXF_CC_LKP_Account__c = :accountId
        AND AXF_CC_PKL_AvailabilityState__c = 'AVAILABLE'
      WITH USER_MODE
    ];
    for (AXF_OBJ_CreditCard__c card : cards) {
      card.AXF_CC_PKL_AvailabilityState__c = 'CUSTODY';
    }
    if (!banks.isEmpty()) {
      Database.update(banks, AccessLevel.USER_MODE);
    }
    if (!cards.isEmpty()) {
      Database.update(cards, AccessLevel.USER_MODE);
    }
    outcome.impact.put('sourcesWithdrawn', banks.size() + cards.size());
    return outcome;
  }

  /**
   * Policy-governed purge (AXF-101): each domain is evaluated with the server clock and the
   * run's declared safety state; no policy or BLOCKED preserves content. Executes only the
   * pseudonymization of transaction descriptions in scope; the independently revalidated
   * domains (csv.raw, documents, backup) are evaluated and recorded, execution deferred to
   * the recovery gate (AXF-79).
   */
  private StageOutcome stagePurge(AXF_OBJ_ClosureRun__c run, Account holder) {
    StageOutcome outcome = new StageOutcome();
    Datetime now = Datetime.now();
    List<String> domains = new List<String>{ DOMAIN_TRANSACTION_DESCRIPTION };
    domains.addAll(REVALIDATED_DOMAINS);
    List<ALT_CLS_RetentionPolicy.Request> requests = new List<ALT_CLS_RetentionPolicy.Request>();
    for (String domain : domains) {
      ALT_CLS_RetentionPolicy.Request request = new ALT_CLS_RetentionPolicy.Request();
      request.domain = domain;
      request.purgeTrigger = PURGE_TRIGGER;
      // The closure request instant is the trigger; retention days count from it.
      request.triggerAt = run.CreatedDate == null ? now : run.CreatedDate;
      request.evaluatedAt = now;
      request.legalHold = run.AXF_CLR_BOL_LegalHold__c == true;
      request.activeDependencies = hasActiveDependencies(holder);
      request.openReview = hasOpenReview(holder);
      request.unresolvedOutcome = false;
      requests.add(request);
    }
    List<ALT_CLS_RetentionPolicy.Result> results = ALT_CLS_RetentionPolicy.evaluate(
      requests
    );
    List<String> versions = new List<String>();
    for (Integer i = 0; i < domains.size(); i++) {
      ALT_CLS_RetentionPolicy.Result result = results[i];
      String domain = domains[i];
      outcome.impact.put('policy.' + domain + '.' + result.status, 1);
      if (result.receipt != null) {
        versions.add(domain + '=' + result.receipt.policyVersion);
      }
      if (
        result.status == 'BLOCKED' &&
        (result.reasonCode == 'LEGAL_HOLD' ||
        result.reasonCode == 'ACTIVE_DEPENDENCIES' ||
        result.reasonCode == 'OPEN_REVIEW')
      ) {
        outcome.status = 'BLOCKED';
        outcome.reason = result.reasonCode;
        outcome.nextAction = result.reasonCode == 'LEGAL_HOLD'
          ? 'RELEASE_LEGAL_HOLD'
          : 'RESOLVE_DEPENDENCIES';
        return outcome;
      }
      if (result.status == 'KEEP') {
        // Policy applies but the window has not elapsed: content is preserved; execution
        // belongs to the retention schedule after the window, never anticipated here.
        outcome.impact.put('policy.' + domain + '.DUE_LATER', 1);
      } else if (
        result.eligible == true &&
        domain == DOMAIN_TRANSACTION_DESCRIPTION
      ) {
        outcome.impact.putAll(pseudonymizeDescriptions(holder));
      }
    }
    outcome.evidence.put('policyVersion', String.join(versions, ';'));
    return outcome;
  }

  private StageOutcome stageRetainEvidence(Account holder) {
    StageOutcome outcome = new StageOutcome();
    outcome.impact.put('evidenceRetained', 1);
    return outcome;
  }

  // ---------------------------------------------------------------- helpers

  private Boolean hasActiveDependencies(Account holder) {
    Id accountId = holder.Id;
    Integer active = [
      SELECT COUNT()
      FROM AXF_OBJ_Contract__c
      WHERE
        AXF_CTR_LKP_Account__c = :accountId
        AND AXF_CTR_PKL_Lifecycle__c = 'ACTIVE'
      WITH USER_MODE
    ];
    return active > 0;
  }

  private Boolean hasOpenReview(Account holder) {
    Id accountId = holder.Id;
    Integer open = [
      SELECT COUNT()
      FROM AXF_OBJ_ReviewItem__c
      WHERE
        AXF_RVI_LKP_Account__c = :accountId
        AND AXF_RVI_PKL_State__c = 'OPEN'
      WITH USER_MODE
    ];
    return open > 0;
  }

  /**
   * Replaces free-text descriptions in scope by an irreversible token; amounts and dates stay.
   * Facts already referenced by a realization allocation are immutable evidence
   * (ALT_CLS_RealizationGuard) and are retained untouched. Writes run in system mode as an
   * isolated, policy-governed effect authorized by the closure operator (CP + edit access on
   * the holder); no other field is touched.
   */
  private Map<String, Integer> pseudonymizeDescriptions(Account holder) {
    Id accountId = holder.Id;
    Map<String, Integer> impact = new Map<String, Integer>{
      'descriptionsPseudonymized' => 0,
      'descriptionsRetainedAsEvidence' => 0
    };
    Set<Id> referenced = new Set<Id>();
    for (AXF_OBJ_ReconciliationAllocation__c allocation : [
      SELECT
        AXF_RA_LKP_FinancialTransaction__c,
        AXF_RA_LKP_BankTransaction__c,
        AXF_RA_LKP_ManualTransaction__c
      FROM AXF_OBJ_ReconciliationAllocation__c
      WHERE
        AXF_RA_LKP_FinancialTransaction__r.AXF_FTX_LKP_Account__c = :accountId
        OR AXF_RA_LKP_BankTransaction__r.AXF_BAT_MDR_BankAccount__r.AXF_BA_LKP_Account__c = :accountId
      WITH SYSTEM_MODE
    ]) {
      referenced.add(allocation.AXF_RA_LKP_FinancialTransaction__c);
      referenced.add(allocation.AXF_RA_LKP_BankTransaction__c);
      referenced.add(allocation.AXF_RA_LKP_ManualTransaction__c);
    }
    List<SObject> changes = new List<SObject>();
    List<AXF_OBJ_FinancialTransaction__c> plans = [
      SELECT Id, AXF_FTX_TXT_Description__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE
        AXF_FTX_LKP_Account__c = :accountId
        AND AXF_FTX_TXT_Description__c != NULL
        AND (NOT AXF_FTX_TXT_Description__c LIKE 'pseudo:%')
      WITH USER_MODE
      LIMIT 2000
    ];
    for (AXF_OBJ_FinancialTransaction__c plan : plans) {
      if (referenced.contains(plan.Id)) {
        impact.put(
          'descriptionsRetainedAsEvidence',
          impact.get('descriptionsRetainedAsEvidence') + 1
        );
        continue;
      }
      plan.AXF_FTX_TXT_Description__c = token(
        plan.Id,
        plan.AXF_FTX_TXT_Description__c
      );
      changes.add(plan);
    }
    List<AXF_OBJ_BankAccountTransaction__c> facts = [
      SELECT Id, AXF_BAT_TXT_Description__c
      FROM AXF_OBJ_BankAccountTransaction__c
      WHERE
        AXF_BAT_MDR_BankAccount__r.AXF_BA_LKP_Account__c = :accountId
        AND AXF_BAT_TXT_Description__c != NULL
        AND (NOT AXF_BAT_TXT_Description__c LIKE 'pseudo:%')
      WITH SYSTEM_MODE
      LIMIT 2000
    ];
    for (AXF_OBJ_BankAccountTransaction__c fact : facts) {
      if (referenced.contains(fact.Id)) {
        impact.put(
          'descriptionsRetainedAsEvidence',
          impact.get('descriptionsRetainedAsEvidence') + 1
        );
        continue;
      }
      fact.AXF_BAT_TXT_Description__c = token(
        fact.Id,
        fact.AXF_BAT_TXT_Description__c
      );
      fact.AXF_BAT_TXT_NormalizedDescription__c = fact.AXF_BAT_TXT_Description__c;
      changes.add(fact);
    }
    if (!changes.isEmpty()) {
      Database.update(changes, AccessLevel.SYSTEM_MODE);
    }
    impact.put('descriptionsPseudonymized', changes.size());
    return impact;
  }

  private static String token(Id recordId, String value) {
    if (value != null && value.startsWith('pseudo:')) {
      return value;
    }
    return 'pseudo:' +
      EncodingUtil.convertToHex(
          Crypto.generateDigest('SHA-256', Blob.valueOf(recordId + '|' + value))
        )
        .left(24);
  }

  private Account authorizedHolder(Id accountId) {
    if (accountId == null) {
      throw failure('INVALID_INPUT');
    }
    if (!FeatureManagement.checkPermission(CP_CLOSE)) {
      throw failure('FORBIDDEN');
    }
    List<Account> holders = [
      SELECT Id, Name, OwnerId
      FROM Account
      WHERE Id = :accountId
      WITH USER_MODE
      LIMIT 1
    ];
    if (holders.isEmpty()) {
      throw failure('NOT_ACCESSIBLE');
    }
    List<UserRecordAccess> access = [
      SELECT RecordId, HasEditAccess
      FROM UserRecordAccess
      WHERE UserId = :UserInfo.getUserId() AND RecordId = :accountId
      LIMIT 1
    ];
    if (access.isEmpty() || access[0].HasEditAccess != true) {
      throw failure('NOT_ACCESSIBLE');
    }
    return holders[0];
  }

  private AXF_OBJ_ClosureRun__c load(Id runId, Decimal expectedVersion) {
    if (runId == null) {
      throw failure('INVALID_INPUT');
    }
    if (!FeatureManagement.checkPermission(CP_CLOSE)) {
      throw failure('FORBIDDEN');
    }
    List<AXF_OBJ_ClosureRun__c> rows = [
      SELECT
        Id,
        AXF_CLR_LKP_Account__c,
        AXF_CLR_PKL_Status__c,
        AXF_CLR_PKL_Stage__c,
        AXF_CLR_NUM_Attempt__c,
        AXF_CLR_TXT_BlockReason__c,
        AXF_CLR_TXT_NextAction__c,
        AXF_CLR_BOL_LegalHold__c,
        AXF_CLR_TXT_ExportEvidenceRef__c,
        AXF_CLR_PKL_ExternalRevocation__c,
        AXF_CLR_TXT_PolicyVersion__c,
        AXF_CLR_TXT_CorrelationId__c,
        AXF_CLR_NUM_Version__c,
        AXF_CLR_TAL_Checkpoints__c,
        CreatedDate
      FROM AXF_OBJ_ClosureRun__c
      WHERE Id = :runId
      WITH USER_MODE
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      throw failure('NOT_ACCESSIBLE');
    }
    if (
      expectedVersion != null &&
      expectedVersion != nz(rows[0].AXF_CLR_NUM_Version__c)
    ) {
      throw failure('CONFLICT');
    }
    return rows[0];
  }

  private static List<StageCheckpoint> parseCheckpoints(String raw) {
    if (String.isBlank(raw)) {
      return new List<StageCheckpoint>();
    }
    return (List<StageCheckpoint>) JSON.deserialize(
      raw,
      List<StageCheckpoint>.class
    );
  }

  private static String evidenceSummary(
    AXF_OBJ_ClosureRun__c run,
    List<StageCheckpoint> checkpoints
  ) {
    return JSON.serialize(
      new Map<String, Object>{
        'correlationId' => run.AXF_CLR_TXT_CorrelationId__c,
        'scopeKey' => String.valueOf(run.AXF_CLR_LKP_Account__c),
        'policyVersion' => run.AXF_CLR_TXT_PolicyVersion__c,
        'externalRevocation' => run.AXF_CLR_PKL_ExternalRevocation__c,
        'legalHold' => run.AXF_CLR_BOL_LegalHold__c,
        'closedAt' => String.valueOf(Datetime.now()),
        'stages' => checkpoints
      }
    );
  }

  private static Decimal nz(Decimal value) {
    return value == null ? 0 : value;
  }

  private static ClosureException failure(String code) {
    ClosureException result = new ClosureException(code);
    result.code = code;
    return result;
  }
}
