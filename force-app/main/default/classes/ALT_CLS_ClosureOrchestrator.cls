/**
 * @description Orquestracao central do encerramento local de um titular (AXF-119, fatia de
 * AXF-9). Sequencia fixa e auditavel: EXPORT -> REVOKE_ACCESS -> STOP_COLLECTION -> PURGE ->
 * RETAIN_EVIDENCE -> CLOSED (terminal). Cada etapa e idempotente (checkpoint persistido em
 * AXF_OBJ_ClosureRun__c), observavel (correlacao, progresso, ultimo ponto, impacto, proxima
 * acao segura) e retomavel pelo mesmo escopo; etapa material nao se repete enquanto o resultado
 * anterior nao for reconciliado (RESULT_UNKNOWN) ou o bloqueio removido (BLOCKED).
 *
 * Limites desta fatia: a exportacao anexa sua evidencia via attachExportEvidence e a invariante de
 * restore e historia irma. Nunca executa DELETE /items na Pluggy; nao concede Delete; ausencia de
 * policy de retencao nao expurga.
 *
 * Impedimentos (AXF-120): legal hold, arquivo sem copia recuperavel confirmada e backup
 * obrigatorio pendente sao avaliados antes de qualquer efeito destrutivo e expostos como BLOCKED
 * com motivo seguro e acao autorizada; a retencao nunca reativa acesso ao conteudo. A revogacao
 * externa e exibida separadamente: so a evidencia observada no provedor confirma, o operador
 * nunca a afirma, e a pendencia nao reativa coleta nem vira proxima acao do run.
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
  /** Rows pseudonymized per stage execution; more than this leaves the stage resumable. */
  private static final Integer PURGE_BATCH = 2000;
  /** Oldest checkpoints are folded into a summary entry beyond this count (field size). */
  private static final Integer CHECKPOINT_LIMIT = 40;
  private static final Set<String> DEPENDENT_CONTRACT_STATES = new Set<String>{
    'ACTIVE',
    'SUSPENDED'
  };
  /**
   * AXF-95 writes AXF_ARR_TXT_HotRemoval__c only when verification closes a run, so the value
   * tells whether the scope has a confirmed recoverable copy. Verified and kept hot by policy.
   */
  private static final String ARCHIVE_VERIFIED_RETAINED = 'BLOCKED:HOT_REMOVAL_NOT_AUTHORIZED';
  /** Verified copy whose removal the recovery/backup acceptance still holds open (AD-18). */
  private static final String ARCHIVE_RECOVERY_GATE_OPEN = 'BLOCKED:RECOVERY_GATE_OPEN';
  /** Guidance shown next to a closed run while the provider has not confirmed the revocation. */
  public static final String EXTERNAL_REVOKE_ACTION = 'REVOKE_IN_PLUGGY';
  private static Boolean writing = false;

  /** ClosureRun rows are written only by the orchestrator (trigger guard). */
  public static Boolean isWriting() {
    return writing;
  }

  /** Test seam: stage name whose material effect must be reported as RESULT_UNKNOWN. */
  @TestVisible
  private static String simulateUnknownAt;
  /** Test seam: stage name that must fail after its effects (exercises rollback + STAGE_FAILED). */
  @TestVisible
  private static String simulateFailureAt;
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
    public String externalRevocationAction;
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
    try {
      persist(run, true);
    } catch (DmlException race) {
      if (race.getDmlType(0) != StatusCode.DUPLICATE_VALUE) {
        throw race;
      }
      // A concurrent request won the scope key: continue with that run.
      return read(
        [
          SELECT Id
          FROM AXF_OBJ_ClosureRun__c
          WHERE AXF_CLR_EXI_ScopeKey__c = :scopeKey
          LIMIT 1
        ]
        .Id
      );
    }
    grantOperatorAccess(run.Id, holder.OwnerId);
    return read(run.Id);
  }

  /** Operator releases a legal hold they declared; the run becomes resumable again. */
  public RunView releaseLegalHold(Id runId, Decimal expectedVersion) {
    AXF_OBJ_ClosureRun__c run = load(runId, expectedVersion);
    if (run.AXF_CLR_PKL_Status__c == 'CLOSED') {
      throw failure('TERMINAL');
    }
    if (run.AXF_CLR_BOL_LegalHold__c != true) {
      return read(run.Id);
    }
    run.AXF_CLR_BOL_LegalHold__c = false;
    if (
      run.AXF_CLR_PKL_Status__c == 'BLOCKED' &&
      run.AXF_CLR_TXT_BlockReason__c == 'LEGAL_HOLD'
    ) {
      run.AXF_CLR_PKL_Status__c = 'REQUESTED';
      run.AXF_CLR_TXT_BlockReason__c = null;
      run.AXF_CLR_TXT_NextAction__c = 'RESUME';
    }
    List<StageCheckpoint> checkpoints = parseCheckpoints(
      run.AXF_CLR_TAL_Checkpoints__c
    );
    checkpoints.add(
      note(
        'LEGAL_HOLD',
        'RELEASED',
        Integer.valueOf(nz(run.AXF_CLR_NUM_Attempt__c))
      )
    );
    run.AXF_CLR_TAL_Checkpoints__c = serializeCheckpoints(checkpoints);
    run.AXF_CLR_NUM_Version__c = nz(run.AXF_CLR_NUM_Version__c) + 1;
    persist(run, false);
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
    persist(run, false);
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
    // The reconciliation decision is part of the audit trail (who/when, which effect).
    List<StageCheckpoint> checkpoints = parseCheckpoints(
      run.AXF_CLR_TAL_Checkpoints__c
    );
    StageCheckpoint reconciled = note(
      run.AXF_CLR_PKL_Stage__c == null ? 'NONE' : nextStageAfter(run),
      'RECONCILED',
      Integer.valueOf(nz(run.AXF_CLR_NUM_Attempt__c))
    );
    reconciled.effectKey = run.AXF_CLR_TXT_LastEffectKey__c;
    checkpoints.add(reconciled);
    run.AXF_CLR_TAL_Checkpoints__c = serializeCheckpoints(checkpoints);
    run.AXF_CLR_NUM_Version__c = nz(run.AXF_CLR_NUM_Version__c) + 1;
    persist(run, false);
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
    if (start >= STAGES.size()) {
      // Every stage is already complete (e.g. terminal state lost): close, never spin.
      run.AXF_CLR_PKL_Status__c = 'CLOSED';
      run.AXF_CLR_TXT_NextAction__c = 'NONE';
    }
    // One unit of work: either the checkpoints are persisted with the effects or nothing is.
    Savepoint whole = Database.setSavepoint();
    for (Integer i = start; i < STAGES.size(); i++) {
      String stage = STAGES[i];
      String effectKey = stage + ':' + attempt;
      Savepoint point = Database.setSavepoint();
      StageOutcome outcome;
      try {
        outcome = execute(stage, run, holder, checkpoints);
        if (simulateFailureAt == stage) {
          throw new ClosureException('simulated stage failure');
        }
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
        // The failure class is the persisted diagnostic; message/stack stay server-side.
        outcome.reason = 'STAGE_FAILED:' + failure.getTypeName().left(60);
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
      checkpoint.completedAt = isoNow();
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
    run.AXF_CLR_TAL_Checkpoints__c = serializeCheckpoints(checkpoints);
    run.AXF_CLR_NUM_Version__c = nz(run.AXF_CLR_NUM_Version__c) + 1;
    try {
      persist(run, false);
    } catch (Exception lost) {
      // Effects without their checkpoint would be unauditable: undo the whole attempt.
      Database.rollback(whole);
      throw lost;
    }
    return read(run.Id);
  }

  public RunView read(Id runId) {
    if (runId == null) {
      throw failure('INVALID_INPUT');
    }
    if (!FeatureManagement.checkPermission(CP_CLOSE)) {
      throw failure('FORBIDDEN');
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
    return toView(rows[0]);
  }

  private static RunView toView(AXF_OBJ_ClosureRun__c run) {
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
    String revocation = run.AXF_CLR_PKL_ExternalRevocation__c;
    view.externalRevocation = revocation;
    // Separately from the run's own next action: a pending external revocation is the
    // operator's own step at the provider, never a step of this closure. It is only offered
    // once the local closure is complete: a blocked run still has its own step to take, and
    // presenting "Axon closed" then would be a false statement about the installation.
    view.externalRevocationAction =
      run.AXF_CLR_PKL_Status__c == 'CLOSED' && revocation == 'NOT_CONFIRMED'
      ? EXTERNAL_REVOKE_ACTION
      : null;
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
    if (!FeatureManagement.checkPermission(CP_CLOSE)) {
      throw failure('FORBIDDEN');
    }
    List<RunView> result = new List<RunView>();
    for (AXF_OBJ_ClosureRun__c run : [
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
      WITH USER_MODE
      ORDER BY LastModifiedDate DESC
      LIMIT 50
    ]) {
      result.add(toView(run));
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
      // Grants are written only by the AXF-6 service (trigger guard); reach it through its
      // Callable entry point so this slice stays independent of the merge order.
      Set<Id> expenseIds = new Map<Id, AXF_OBJ_FinancialTransaction__c>(
          [
            SELECT Id
            FROM AXF_OBJ_FinancialTransaction__c
            WHERE AXF_FTX_LKP_Account__c = :accountId
            WITH USER_MODE
          ]
        )
        .keySet();
      Type serviceType = Type.forName('ALT_CLS_SharedExpenseService');
      if (serviceType == null) {
        outcome.status = 'BLOCKED';
        outcome.reason = 'GRANTS_NOT_ACCESSIBLE';
        outcome.nextAction = 'RESUME';
        return outcome;
      }
      Callable grantService = (Callable) serviceType.newInstance();
      revokedGrants = (Integer) grantService.call(
        'revokeForClosure',
        new Map<String, Object>{ 'financialTransactionIds' => expenseIds }
      );
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
      SELECT Id, AXF_CON_PKL_CollectionState__c, AXF_CON_PKL_ConsentState__c
      FROM AXF_OBJ_PluggyConnection__c
      WHERE AXF_CON_LKP_Account__c = :accountId
      WITH USER_MODE
    ];
    for (AXF_OBJ_PluggyConnection__c connection : connections) {
      if (connection.AXF_CON_PKL_CollectionState__c != 'PAUSED') {
        try {
          control.pauseConnection(connection.Id);
        } catch (Exception denied) {
          // Pausing needs AXF_CanConfigure; explain instead of a generic stage failure.
          outcome.status = 'BLOCKED';
          outcome.reason = 'COLLECTION_NOT_PAUSABLE';
          outcome.nextAction = 'RESUME';
          return outcome;
        }
        paused++;
      }
    }
    outcome.impact.put('connectionsPaused', paused);

    // Pausing is local and proves nothing about the provider. The consent state observed by the
    // AXF-11 consent surface is the only evidence of an external revocation: it stays pending
    // until every connection of the scope reports revoked, and an operator never asserts it.
    Boolean allRevoked = !connections.isEmpty();
    for (AXF_OBJ_PluggyConnection__c connection : connections) {
      if (connection.AXF_CON_PKL_ConsentState__c != 'REVOKED') {
        allRevoked = false;
      }
    }
    outcome.evidence.put(
      'externalRevocation',
      connections.isEmpty()
        ? 'NOT_APPLICABLE'
        : (allRevoked ? 'CONFIRMED' : 'NOT_CONFIRMED')
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
    // Nothing destructive runs while an impediment of the closure is in force.
    StageOutcome safeguard = deletionSafeguard(run, holder);
    if (safeguard != null) {
      return safeguard;
    }
    Datetime now = Datetime.now();
    List<String> domains = new List<String>{ DOMAIN_TRANSACTION_DESCRIPTION };
    domains.addAll(REVALIDATED_DOMAINS);
    List<ALT_CLS_RetentionPolicy.Request> requests = new List<ALT_CLS_RetentionPolicy.Request>();
    Boolean activeDependencies = hasActiveDependencies(holder);
    Boolean openReview = hasOpenReview(holder);
    for (String domain : domains) {
      ALT_CLS_RetentionPolicy.Request request = new ALT_CLS_RetentionPolicy.Request();
      request.domain = domain;
      request.purgeTrigger = PURGE_TRIGGER;
      // The closure request instant is the trigger; retention days count from it.
      request.triggerAt = run.CreatedDate == null ? now : run.CreatedDate;
      request.evaluatedAt = now;
      request.legalHold = run.AXF_CLR_BOL_LegalHold__c == true;
      request.activeDependencies = activeDependencies;
      request.openReview = openReview;
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
        Map<String, Integer> impact = pseudonymizeDescriptions(holder);
        outcome.impact.putAll(impact);
        if (impact.get('descriptionsRemaining') > 0) {
          // More rows than one execution handles: stay resumable, never report DONE early.
          outcome.status = 'BLOCKED';
          outcome.reason = 'PURGE_INCOMPLETE';
          outcome.nextAction = 'RESUME';
          return outcome;
        }
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

  /**
   * A deletion only happens when no impediment of the closure is in force (AXF-120). The legal
   * hold is declared on the run itself and outranks the policy evaluation, which only exists
   * where an administrator configured a policy for the domain. The other causes come from the
   * recoverable copy of the scope.
   */
  private StageOutcome deletionSafeguard(
    AXF_OBJ_ClosureRun__c run,
    Account holder
  ) {
    if (run.AXF_CLR_BOL_LegalHold__c == true) {
      return blockedStage('LEGAL_HOLD', 'RELEASE_LEGAL_HOLD');
    }
    return archiveSafeguard(holder);
  }

  /**
   * AXF-95 never removes the hot copy, so an archive whose verification never closed leaves the
   * scope with no confirmed recoverable copy and deleting content would destroy the only one. A
   * verified archive whose removal gate is still held open by the recovery/backup acceptance is
   * the pending mandatory backup (AD-18). `BLOCKED:HOT_REMOVAL_NOT_AUTHORIZED` is the opposite:
   * a verified copy the policy keeps hot, which does not impede a governed purge. With no archive
   * attempt there is no copy to confirm and the retention policy of each domain governs alone.
   *
   * Verification is per source family (BAT/CCT/FTX, the families the purge pseudonymizes): a
   * confirmed copy of one family says nothing about the content of another, so each family with
   * an archive attempt must own a confirmed copy before anything is erased.
   */
  private StageOutcome archiveSafeguard(Account holder) {
    Id accountId = holder.Id;
    Set<String> attemptedFamilies = new Set<String>();
    Set<String> verifiedFamilies = new Set<String>();
    Set<String> recoveryGateFamilies = new Set<String>();
    for (AXF_OBJ_ArchiveRun__c run : [
      SELECT AXF_ARR_PKL_SourceFamily__c, AXF_ARR_TXT_HotRemoval__c
      FROM AXF_OBJ_ArchiveRun__c
      WHERE AXF_ARR_LKP_Account__c = :accountId
      WITH USER_MODE
      ORDER BY AXF_ARR_DTM_LastCheckpointAt__c DESC
      LIMIT 200
    ]) {
      String family = run.AXF_ARR_PKL_SourceFamily__c;
      String gate = run.AXF_ARR_TXT_HotRemoval__c;
      attemptedFamilies.add(family);
      if (gate == ARCHIVE_VERIFIED_RETAINED) {
        verifiedFamilies.add(family);
      } else if (gate == ARCHIVE_RECOVERY_GATE_OPEN) {
        recoveryGateFamilies.add(family);
      }
      // Any other gate (as a null one) means verification never closed the run: scanning,
      // writing or failed. Such a family has no confirmed copy until another run confirms one.
    }
    if (!recoveryGateFamilies.isEmpty()) {
      return blockedStage('BACKUP_PENDING', 'AWAIT_BACKUP_CONFIRMATION');
    }
    for (String family : attemptedFamilies) {
      if (!verifiedFamilies.contains(family)) {
        return blockedStage('ARCHIVE_UNVERIFIED', 'VERIFY_ARCHIVE');
      }
    }
    return null;
  }

  private static StageOutcome blockedStage(String reason, String nextAction) {
    StageOutcome outcome = new StageOutcome();
    outcome.status = 'BLOCKED';
    outcome.reason = reason;
    outcome.nextAction = nextAction;
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
        AND AXF_CTR_PKL_Lifecycle__c IN :DEPENDENT_CONTRACT_STATES
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
      'descriptionsRetainedAsEvidence' => 0,
      'descriptionsRemaining' => 0
    };
    Set<Id> referenced = new Set<Id>();
    for (AXF_OBJ_ReconciliationAllocation__c allocation : [
      SELECT
        AXF_RA_LKP_FinancialTransaction__c,
        AXF_RA_LKP_BankTransaction__c,
        AXF_RA_LKP_CardTransaction__c,
        AXF_RA_LKP_ManualTransaction__c
      FROM AXF_OBJ_ReconciliationAllocation__c
      WHERE
        AXF_RA_LKP_FinancialTransaction__r.AXF_FTX_LKP_Account__c = :accountId
        OR AXF_RA_LKP_BankTransaction__r.AXF_BAT_MDR_BankAccount__r.AXF_BA_LKP_Account__c = :accountId
        OR AXF_RA_LKP_CardTransaction__r.AXF_CCT_MDR_CreditCard__r.AXF_CC_LKP_Account__c = :accountId
      WITH SYSTEM_MODE
    ]) {
      referenced.add(allocation.AXF_RA_LKP_FinancialTransaction__c);
      referenced.add(allocation.AXF_RA_LKP_BankTransaction__c);
      referenced.add(allocation.AXF_RA_LKP_CardTransaction__c);
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
      WITH SYSTEM_MODE
      LIMIT :PURGE_BATCH
    ];
    if (plans.size() == PURGE_BATCH) {
      impact.put(
        'descriptionsRemaining',
        impact.get('descriptionsRemaining') + 1
      );
    }
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
      LIMIT :PURGE_BATCH
    ];
    if (facts.size() == PURGE_BATCH) {
      impact.put(
        'descriptionsRemaining',
        impact.get('descriptionsRemaining') + 1
      );
    }
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
    List<AXF_OBJ_CreditCardTransaction__c> cardFacts = [
      SELECT Id, AXF_CCT_TXT_Description__c
      FROM AXF_OBJ_CreditCardTransaction__c
      WHERE
        AXF_CCT_MDR_CreditCard__r.AXF_CC_LKP_Account__c = :accountId
        AND AXF_CCT_TXT_Description__c != NULL
        AND (NOT AXF_CCT_TXT_Description__c LIKE 'pseudo:%')
      WITH SYSTEM_MODE
      LIMIT :PURGE_BATCH
    ];
    if (cardFacts.size() == PURGE_BATCH) {
      impact.put(
        'descriptionsRemaining',
        impact.get('descriptionsRemaining') + 1
      );
    }
    for (AXF_OBJ_CreditCardTransaction__c fact : cardFacts) {
      if (referenced.contains(fact.Id)) {
        impact.put(
          'descriptionsRetainedAsEvidence',
          impact.get('descriptionsRetainedAsEvidence') + 1
        );
        continue;
      }
      fact.AXF_CCT_TXT_Description__c = token(
        fact.Id,
        fact.AXF_CCT_TXT_Description__c
      );
      fact.AXF_CCT_TXT_NormalizedDescription__c = fact.AXF_CCT_TXT_Description__c;
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
        AXF_CLR_TXT_LastEffectKey__c,
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
    // Serialize concurrent operators on the same run before comparing versions.
    List<AXF_OBJ_ClosureRun__c> locked = [
      SELECT Id, AXF_CLR_NUM_Version__c
      FROM AXF_OBJ_ClosureRun__c
      WHERE Id = :runId
      FOR UPDATE
    ];
    if (expectedVersion == null) {
      throw failure('INVALID_INPUT');
    }
    if (expectedVersion != nz(locked[0].AXF_CLR_NUM_Version__c)) {
      throw failure('CONFLICT');
    }
    rows[0].AXF_CLR_NUM_Version__c = locked[0].AXF_CLR_NUM_Version__c;
    return rows[0];
  }

  private static List<StageCheckpoint> parseCheckpoints(String raw) {
    if (String.isBlank(raw)) {
      return new List<StageCheckpoint>();
    }
    try {
      return (List<StageCheckpoint>) JSON.deserialize(
        raw,
        List<StageCheckpoint>.class
      );
    } catch (Exception corrupt) {
      throw failure('CHECKPOINTS_CORRUPT');
    }
  }

  /** Keeps the trail within the field: the oldest entries collapse into one summary entry. */
  private static String serializeCheckpoints(
    List<StageCheckpoint> checkpoints
  ) {
    while (checkpoints.size() > CHECKPOINT_LIMIT) {
      StageCheckpoint folded = checkpoints.remove(0);
      StageCheckpoint next = checkpoints[0];
      if (next.stage != 'FOLDED') {
        StageCheckpoint summary = new StageCheckpoint();
        summary.stage = 'FOLDED';
        summary.status = 'FOLDED';
        summary.attempt = folded.attempt;
        summary.completedAt = folded.completedAt;
        summary.impact = new Map<String, Integer>{ 'entries' => 1 };
        checkpoints.add(0, summary);
      } else {
        next.impact.put('entries', next.impact.get('entries') + 1);
      }
    }
    return JSON.serialize(checkpoints);
  }

  private static StageCheckpoint note(
    String stage,
    String status,
    Integer attempt
  ) {
    StageCheckpoint checkpoint = new StageCheckpoint();
    checkpoint.stage = stage;
    checkpoint.status = status;
    checkpoint.attempt = attempt;
    checkpoint.completedAt = isoNow();
    return checkpoint;
  }

  private static String nextStageAfter(AXF_OBJ_ClosureRun__c run) {
    Integer next = STAGES.indexOf(run.AXF_CLR_PKL_Stage__c) + 1;
    return next < STAGES.size() ? STAGES[next] : 'RETAIN_EVIDENCE';
  }

  private static String isoNow() {
    return Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
  }

  /** All writes to the run go through here so the trigger guard can tell the orchestrator apart. */
  private static void persist(AXF_OBJ_ClosureRun__c run, Boolean isInsert) {
    writing = true;
    try {
      if (isInsert) {
        Database.insert(run, AccessLevel.USER_MODE);
      } else {
        Database.update(run, AccessLevel.USER_MODE);
      }
    } finally {
      writing = false;
    }
  }

  /** The run follows the holder's owner (G2); the requesting operator keeps access via a share row. */
  @SuppressWarnings('PMD.ApexCRUDViolation')
  private static void grantOperatorAccess(Id runId, Id ownerId) {
    Id me = UserInfo.getUserId();
    if (me == ownerId) {
      return;
    }
    Database.insert(
      new AXF_OBJ_ClosureRun__Share(
        ParentId = runId,
        UserOrGroupId = me,
        AccessLevel = 'Edit',
        RowCause = Schema.AXF_OBJ_ClosureRun__Share.RowCause.Manual
      ),
      false
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
        'closedAt' => isoNow(),
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
