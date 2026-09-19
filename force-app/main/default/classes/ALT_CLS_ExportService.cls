/**
 * @description AXF-118 authorized data export (the export slice of AXF-9). One holder scope is
 * exported to a private, short-lived artifact: authorization is verified when the request is
 * made and again on every download, and **every** refusal that finds a live artifact revokes it
 * by deleting the artifact before refusing — an elapsed window, a withdrawn capability, a lost
 * requester binding, a lost holder access, or an artifact that is missing or does not match its
 * evidence. File name, notification and log lines carry no PII: they use only the run's opaque
 * auto-number.
 *
 * Scope (AXF-118 expansion, ratified 19/09/2026): the holder's canonical financial facts
 * (AXF_OBJ_FinancialTransaction__c), bank facts (AXF_OBJ_BankAccountTransaction__c) and card
 * facts (AXF_OBJ_CreditCardTransaction__c), each exported with its own native columns side by
 * side — no lookup or unifying schema is invented between the three objects. Cell values are
 * neutralized against spreadsheet formulas by the single project neutralizer (AD-25), the same
 * one the CSV import uses.
 *
 * Below EXPORT_ROW_LIMIT (summed across the three sources) the request stays fully synchronous,
 * unchanged in spirit from the original AXF-118 cut. Above it, the run is handed to
 * {@link ALT_CLS_ExportRunBatch}, a resumable `Database.Batchable`: the run moves to RUNNING, a
 * chunk failure moves it to PARTIAL without losing the persisted cursor or duplicating rows
 * already written, and the next `request()` resumes it instead of restarting.
 *
 * The download window (15 minutes) is read from `AXF_CMT_RetentionPolicy__mdt` by
 * `DeveloperName = 'Export'` (`AXF_RPT_NUM_WindowMinutes__c`) rather than a hardcoded constant; a
 * missing or disabled policy record is a sanitized explicit failure, never a silently invented
 * default.
 *
 * The download is never a public link: a ContentDistribution has no caller identity, so it could
 * not revalidate authorization, which both acceptance criteria require.
 *
 * A refusal that must commit a revocation is returned as a DownloadView outcome rather than
 * thrown: an unhandled Apex exception rolls the whole transaction back, which would undo the
 * revocation it is supposed to record. Only failures that leave no side effect to preserve are
 * thrown.
 *
 * Two state-machine properties the review demanded and this class now holds: availability is only
 * reported for a run whose artifact still exists (a `REQUEST_AGAIN` that the next `request()`
 * silently ignored would be a dead end), and a copy the platform refused to remove keeps its
 * pointer — minting a new artifact over it would destroy the only reference an operator could act
 * on. Both `request()` and `download()` take the run lock, so two concurrent requests cannot each
 * write an artifact for the same run and orphan one of them.
 *
 * Isolated elevation, stated rather than implied: the class runs **without sharing** because the
 * state machine it owns cannot run any other way. The run follows the holder's owner (G2), so an
 * authorized requester who is not that owner holds only a read share, and the permission set
 * deliberately grants no more than that; a sharing-enforcing write would then be refused for
 * exactly the caller the service exists to serve. The refusal paths need the same reach: they must
 * revoke the artifact, and record it, after the caller lost object access entirely. Nothing is
 * decided by the elevation: every read that must respect the caller's access states `WITH USER_MODE`
 * — the holder lookup and the run reads on the gated paths — the fact queries that build the CSV
 * run in `USER_MODE`, the capability, requester binding, holder access and window are revalidated
 * before any effect, and the remaining unconditional operations are the control row and the
 * artifact this service itself wrote. The merged `ALT_CLS_SharedExpenseService` elevates for the
 * same class of reason.
 */
public without sharing class ALT_CLS_ExportService {
  public static final String CP_EXPORT = 'AXF_CanExportData';
  /** DeveloperName of the AXF_CMT_RetentionPolicy__mdt record this domain reads (AXF-118). */
  private static final String RETENTION_POLICY_NAME = 'Export';
  /** Rows in one artifact, summed across the three sources. Above it, the run batches (AXF-118). */
  public static final Integer EXPORT_ROW_LIMIT = 5000;
  /**
   * Test-only override of the effective row limit (AXF-118). Apex test execution only supports a
   * single Database.executeBatch chunk (max scope 2000) for a Batchable driven by a custom
   * Iterable, so a test that must cross the real 5000-row EXPORT_ROW_LIMIT cannot also stay
   * inside one chunk. Tests that exercise the batch path instead cross this override with a
   * fixture small enough to fit in one chunk; production always enforces EXPORT_ROW_LIMIT.
   */
  @TestVisible
  private static Integer exportRowLimitOverride;
  /** Batch Apex scope size for the resumable path; small enough to keep each chunk's content
   * rewrite (read-modify-write of the whole artifact so far) comfortably inside one execute(). */
  public static final Integer BATCH_CHUNK_SIZE = 2000;
  /**
   * Test-only override of the scope passed to Database.executeBatch (AXF-118). Apex test
   * execution only supports a single chunk for a Batchable driven by a custom Iterable — a
   * second chunk means a second, disallowed executeBatch. Production always uses
   * BATCH_CHUNK_SIZE; a test that must cross EXPORT_ROW_LIMIT sets this to its own fixture size
   * so the whole run fits in one chunk.
   */
  @TestVisible
  private static Integer batchScopeOverride;
  private static final String STATUS_REQUESTED = 'REQUESTED';
  private static final String STATUS_PREPARED = 'PREPARED';
  private static final String STATUS_DOWNLOADED = 'DOWNLOADED';
  private static final String STATUS_REVOKED = 'REVOKED';
  /** Resumable batch is actively processing this run (AXF-118). */
  private static final String STATUS_RUNNING = 'RUNNING';
  /** A batch chunk failed: the cursor and any content already persisted survive; resumable. */
  private static final String STATUS_PARTIAL = 'PARTIAL';
  private static final String REASON_EXPIRED = 'EXPIRED';
  private static final String REASON_ACCESS_REVOKED = 'ACCESS_REVOKED';
  private static final String REASON_MISSING = 'ARTIFACT_MISSING';
  private static final String REASON_MISMATCH = 'ARTIFACT_MISMATCH';
  /** Recorded when the artifact survived a removal attempt: REVOKED, but the copy is still there. */
  private static final String REASON_NOT_REMOVED = 'ARTIFACT_NOT_REMOVED';
  private static final String MIME_TYPE = 'text/csv';
  private static final String FILE_NAME_PREFIX = 'axon-export-';
  private static final String FILE_NAME_SUFFIX = '.csv';
  private static final String CSV_HEADER = 'date,direction,amount,currency,status,description';
  private static final String BAT_HEADER = 'date,direction,amount,currency,status,description,bankAccount';
  private static final String CCT_HEADER = 'date,direction,amount,currency,status,description,creditCard,merchant';
  /** Source tags used by the resumable cursor and the multi-section file layout (AXF-118). */
  @TestVisible
  private static final String SOURCE_FTX = 'FTX';
  @TestVisible
  private static final String SOURCE_BAT = 'BAT';
  @TestVisible
  private static final String SOURCE_CCT = 'CCT';
  /**
   * Reproducible order within the sync path, so the same scope always hashes to the same
   * artifact while it stays below the row limit. The resumable batch path orders each source by
   * Id (keyset pagination) rather than by date+Id, so the same scope can hash differently
   * depending on whether it crossed EXPORT_ROW_LIMIT — that cross-path guarantee does not hold
   * today; fixing the batch path to match this ordering is out of scope for this change.
   */
  private static final String FACT_QUERY =
    'SELECT AXF_FTX_DAT_PurchaseDate__c, AXF_FTX_PKL_Direction__c, AXF_FTX_NUM_Magnitude__c, ' +
    'AXF_FTX_TXT_CurrencyIsoCode__c, AXF_FTX_PKL_Status__c, AXF_FTX_TXT_Description__c ' +
    'FROM AXF_OBJ_FinancialTransaction__c ' +
    'WHERE AXF_FTX_LKP_Account__c = :accountId ' +
    'ORDER BY AXF_FTX_DAT_PurchaseDate__c, Id';
  private static final String BAT_QUERY =
    'SELECT AXF_BAT_DAT_Date__c, AXF_BAT_PKL_Direction__c, AXF_BAT_NUM_Magnitude__c, ' +
    'AXF_BAT_TXT_CurrencyIsoCode__c, AXF_BAT_PKL_Status__c, AXF_BAT_TXT_Description__c, ' +
    'AXF_BAT_MDR_BankAccount__r.AXF_BA_TXT_NumberMasked__c ' +
    'FROM AXF_OBJ_BankAccountTransaction__c ' +
    'WHERE AXF_BAT_MDR_BankAccount__r.AXF_BA_LKP_Account__c = :accountId ' +
    'ORDER BY AXF_BAT_DAT_Date__c, Id';
  private static final String CCT_QUERY =
    'SELECT AXF_CCT_DAT_Date__c, AXF_CCT_PKL_Direction__c, AXF_CCT_NUM_Magnitude__c, ' +
    'AXF_CCT_TXT_CurrencyIsoCode__c, AXF_CCT_PKL_Status__c, AXF_CCT_TXT_Description__c, ' +
    'AXF_CCT_MDR_CreditCard__r.AXF_CC_TXT_LastFourMasked__c, AXF_CCT_TXT_MerchantName__c ' +
    'FROM AXF_OBJ_CreditCardTransaction__c ' +
    'WHERE AXF_CCT_MDR_CreditCard__r.AXF_CC_LKP_Account__c = :accountId ' +
    'ORDER BY AXF_CCT_DAT_Date__c, Id';
  /** Control-row fields, named once so both access modes of loadRun select the same ones. */
  private static final String RUN_FIELDS =
    'Id, Name, AXF_EPR_LKP_Account__c, AXF_EPR_LKP_Requester__c, ' +
    'AXF_EPR_TXT_ContentDocument__c, AXF_EPR_PKL_Status__c, AXF_EPR_DT_ExpiresAt__c, ' +
    'AXF_EPR_TXT_FileName__c, AXF_EPR_TXT_ContentHash__c, AXF_EPR_TXT_Reason__c, ' +
    'AXF_EPR_NUM_Version__c, AXF_EPR_TXT_Cursor__c, AXF_EPR_DT_Watermark__c, ' +
    'AXF_EPR_DT_CompleteThrough__c, AXF_EPR_NUM_Attempt__c';

  public class ExportException extends Exception {
    public String code;
  }

  public class RunView {
    @AuraEnabled
    public Id runId;
    /** Opaque auto-number, the only reference used in names, notifications and logs. */
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String fileName;
    @AuraEnabled
    public String contentHash;
    @AuraEnabled
    public Datetime expiresAt;
    @AuraEnabled
    public String reason;
    /** Readable artifact reference for the closure sibling (AXF-119); null once revoked. */
    @AuraEnabled
    public String evidenceRef;
    @AuraEnabled
    public Decimal version;
    @AuraEnabled
    public Boolean canDownload;
    @AuraEnabled
    public String nextAction;
  }

  public class DownloadView {
    /** READY, or the safe reason the download was refused and the artifact revoked. */
    @AuraEnabled
    public String outcome;
    @AuraEnabled
    public String fileName;
    @AuraEnabled
    public String mimeType;
    @AuraEnabled
    public String contentHash;
    @AuraEnabled
    public String bodyBase64;
    @AuraEnabled
    public Boolean ready = false;
  }

  // ---------------------------------------------------------------- public API

  /**
   * Authorizes the caller for the holder scope and prepares (or replays) the export artifact of
   * that exact requester. Within the download window this is idempotent: the same run and the
   * same artifact come back. Once the window elapsed, after a revocation, or once the artifact
   * itself is gone, a fresh artifact replaces the dead one on the same run — unless a copy the
   * platform refused to remove is still pointed at, in which case the run keeps that pointer
   * instead of losing it.
   *
   * Above EXPORT_ROW_LIMIT (AXF-118): the run moves to RUNNING and a resumable batch is enqueued.
   * A `request()` observed while RUNNING simply reports the current status (no mutation, no
   * second batch enqueued). A `request()` observed while PARTIAL (a chunk failed) resumes the
   * batch from the persisted cursor instead of restarting the export.
   *
   * NFR-18 optimistic precondition, following the merged ALT_CLS_ClosureOrchestrator.load: the
   * caller states the version it last observed for this scope, and a stale expectation is
   * refused with CONFLICT instead of acting on a state the caller never saw. `null` is only
   * valid while no run exists, which is the first request and the only one that mints a run; a
   * version stated for a scope that has no run is an impossible expectation, not a first request.
   */
  public RunView request(Id accountId, Decimal expectedVersion) {
    Account holder = authorizedHolder(accountId);
    String key = scopeKey(accountId, UserInfo.getUserId());
    Id existing = findByScopeKey(key);
    AXF_OBJ_ExportRun__c run;
    if (existing == null) {
      if (expectedVersion != null) {
        throw failure('CONFLICT');
      }
      Savepoint point = Database.setSavepoint();
      try {
        // Reloaded after the insert: the auto-number, which names the file, is only readable
        // from a query, and the artifact must never be named from an unpopulated field. The
        // reload is privileged because the run follows the holder's owner: a requester who is
        // not that owner only receives the share granted further below.
        run = prepare(loadRunPrivileged(insertRun(holder, key).Id), holder);
      } catch (DmlException race) {
        Database.rollback(point);
        List<Schema.SObjectField> duplicated = null;
        if (race.getDmlType(0) == StatusCode.DUPLICATE_VALUE) {
          duplicated = race.getDmlFields(0);
        }
        if (
          duplicated != null &&
          !duplicated.isEmpty() &&
          !namesScopeKey(duplicated)
        ) {
          // The platform named the fields it rejected: a duplicate that is not the scope key (the
          // artifact title, for instance) is a real failure, not the concurrent request this
          // branch answers, and must not be reported as a lost race.
          throw race;
        }
        if (race.getDmlType(0) != StatusCode.DUPLICATE_VALUE) {
          throw race;
        }
        // A concurrent request won the scope key. Its own transaction owns the artifact; this
        // one reports the winner. The winner is re-read in system mode because the caller may
        // not be able to see a row it has no access to yet, and a lost race answers with a safe
        // code instead of leaking the platform DmlException.
        Id winner = findByScopeKey(key);
        if (winner == null) {
          winner = findByScopeKeySystemMode(key);
        }
        if (winner == null) {
          throw failure('CONFLICT');
        }
        return toView(loadRunPrivileged(winner));
      } catch (Exception failure) {
        Database.rollback(point);
        throw failure;
      }
      grantRequesterAccess(run.Id, holder.OwnerId);
      if (run.AXF_EPR_PKL_Status__c == STATUS_PREPARED) {
        notifyRequester(run);
        log('PREPARED', run.Name);
      } else {
        log('RUNNING', run.Name);
      }
      return toView(run);
    }
    // Locked exactly like download(), and for the same reason: two concurrent requests must not
    // each write an artifact for this run, because the loser's ContentVersion would be left with
    // no reference at all. The re-read under the lock is what the caller's version is compared
    // against (NFR-18): an unstated or stale expectation is refused before anything is written.
    run = lockAndLoad(existing, expectedVersion);
    if (run.AXF_EPR_PKL_Status__c == STATUS_RUNNING) {
      // A batch is already active for this run: report status, never enqueue a second one.
      return toView(run);
    }
    if (run.AXF_EPR_PKL_Status__c == STATUS_PARTIAL) {
      // A chunk failed: resume from the persisted cursor instead of restarting the export.
      return toView(resumeBatch(run));
    }
    if (run.AXF_EPR_PKL_Status__c == STATUS_REVOKED) {
      if (run.AXF_EPR_TXT_ContentDocument__c != null) {
        // A revoked run that still holds a document is the recorded removal failure: retry the
        // removal before minting a new artifact, so the old copy does not survive unrecorded.
        revoke(run, run.AXF_EPR_TXT_Reason__c);
        if (run.AXF_EPR_TXT_ContentDocument__c != null) {
          // The copy survived again. Minting over it would overwrite the only reference an
          // operator could still act on, so the run stays REVOKED with its pointer and the next
          // request retries the removal instead of losing the copy.
          return toView(run);
        }
      }
      return mint(run, holder);
    }
    if (isElapsed(run)) {
      revoke(run, REASON_EXPIRED);
      // revoke() cleared the artifact fields in place, so mint() writes a fresh one.
      return mint(run, holder);
    }
    if (!artifactAvailable(run.AXF_EPR_TXT_ContentDocument__c)) {
      // A prepared run whose artifact is gone can never be served: the platform copy was removed
      // or the pointer is unusable. revoke() records why and clears the dead reference, so the
      // REQUEST_AGAIN this run reports is actually actionable.
      revoke(run, REASON_MISSING);
      return mint(run, holder);
    }
    return toView(run);
  }

  /**
   * Observes the run; never mints and never revokes. Availability is computed from the same gates
   * download() applies — the requester binding, the state, the window and the holder access
   * re-read from the platform — so `canDownload`/`nextAction` never advertise a download that
   * would be refused, and never advertise one for a scope whose authorization was withdrawn.
   */
  public RunView read(Id runId) {
    if (runId == null) {
      throw failure('INVALID_INPUT');
    }
    requireCapability();
    return toView(loadRun(runId));
  }

  /**
   * Second authorization gate. Revalidates the capability, the exact requester binding and the
   * holder access, then the window; an expired or no-longer-authorized download is revoked by
   * deleting the artifact, so the copy this application controls does not survive the refusal.
   *
   * Every refusal that finds a live artifact revokes it before refusing, and is returned as a
   * DownloadView outcome rather than thrown: AC-2 requires the unauthorized access to be revoked,
   * and an unhandled exception would roll the revocation back. The row is read and locked in
   * system mode because it is application-owned state — the caller may hold only a read share on
   * it and, once the capability was withdrawn, no object access at all — so the authorization
   * decisions below are explicit and never delegated to the query's access mode.
   *
   * NFR-18: expectedVersion is the version the caller observed (RunView.version). A stale or
   * unstated expectation is refused before anything is touched, because that caller is
   * authorized and only its view is old.
   *
   * A run that is RUNNING or PARTIAL (AXF-118 resumable batch) has no artifact yet: it falls
   * through to the same NOT_PREPARED refusal a REQUESTED run already produced before this
   * expansion, so no new gate had to be added here.
   */
  public DownloadView download(Id runId, Decimal expectedVersion) {
    if (runId == null) {
      throw failure('INVALID_INPUT');
    }
    AXF_OBJ_ExportRun__c run = lockAndLoad(runId, expectedVersion);
    if (!hasCapability()) {
      return refuseForbidden(run);
    }
    if (run.AXF_EPR_LKP_Requester__c != UserInfo.getUserId()) {
      // The artifact is bound to its exact requester; a null binding (the requester was deleted)
      // or another operator is not that requester.
      return refuseForbidden(run);
    }
    if (!hasHolderReadAccess(run.AXF_EPR_LKP_Account__c)) {
      return refused(revoke(run, REASON_ACCESS_REVOKED));
    }
    if (run.AXF_EPR_PKL_Status__c == STATUS_REVOKED) {
      if (run.AXF_EPR_TXT_ContentDocument__c != null) {
        // A revoked run that still holds a document is the recorded removal failure: retry the
        // removal, so a copy that survived one attempt does not survive indefinitely.
        return refused(revoke(run, run.AXF_EPR_TXT_Reason__c));
      }
      return refused('REVOKED');
    }
    if (
      run.AXF_EPR_PKL_Status__c != STATUS_PREPARED &&
      run.AXF_EPR_PKL_Status__c != STATUS_DOWNLOADED
    ) {
      return refused('NOT_PREPARED');
    }
    if (isElapsed(run)) {
      return refused(revoke(run, REASON_EXPIRED));
    }
    Blob data = body(run);
    if (data == null) {
      // body() revoked the artifact and recorded why on the run.
      return refused(run.AXF_EPR_TXT_Reason__c);
    }
    DownloadView view = new DownloadView();
    view.outcome = 'READY';
    view.ready = true;
    view.fileName = run.AXF_EPR_TXT_FileName__c;
    view.mimeType = MIME_TYPE;
    view.contentHash = run.AXF_EPR_TXT_ContentHash__c;
    view.bodyBase64 = EncodingUtil.base64Encode(data);
    if (run.AXF_EPR_PKL_Status__c != STATUS_DOWNLOADED) {
      run.AXF_EPR_PKL_Status__c = STATUS_DOWNLOADED;
      checkpoint(run);
    }
    log('DOWNLOADED', run.Name);
    return view;
  }

  /**
   * A refusal over the requester's own artifact: a withdrawn capability or a lost requester
   * binding is an unauthorized download access, so the artifact is revoked before the refusal is
   * reported back with a safe code.
   */
  private DownloadView refuseForbidden(AXF_OBJ_ExportRun__c run) {
    revoke(run, REASON_ACCESS_REVOKED);
    return refused('FORBIDDEN');
  }

  // ---------------------------------------------------------------- preparation

  /**
   * Prepares the replacement artifact of an existing run and announces it exactly like the first
   * preparation does: a second artifact nobody is told about would break the ready notice (D-80)
   * for every export after the first. Above the row limit, `prepare()` moves the run to RUNNING
   * instead, and no notice is sent until the batch's `finish()` actually prepares it.
   *
   * The savepoint sits **after** the revocation the caller already performed, so a refusal that
   * has to undo a partial preparation (a failed upload) cannot roll the revocation back with it:
   * an expired or revoked artifact stays revoked even when its replacement cannot be built, which
   * is what AC-2 asks for.
   */
  private RunView mint(AXF_OBJ_ExportRun__c run, Account holder) {
    Savepoint point = Database.setSavepoint();
    try {
      run = prepare(run, holder);
    } catch (Exception refusal) {
      Database.rollback(point);
      throw refusal;
    }
    // Outside the rollback scope, same as request()'s equivalent branch: once prepare() (or the
    // resumable batch it may have enqueued) has committed, a notify/log failure must never trigger
    // a rollback that reverts committed state an already-launched async job depends on.
    RunView view = toView(run);
    if (run.AXF_EPR_PKL_Status__c == STATUS_PREPARED) {
      notifyRequester(run);
      log('PREPARED', run.Name);
    } else {
      log('RUNNING', run.Name);
    }
    return view;
  }

  /**
   * Writes the artifact and its control row as one unit below the row limit; at or above it,
   * moves the run to RUNNING and hands it to the resumable batch (AXF-118) instead of throwing
   * EXPORT_TOO_LARGE — the block that used to stop the request here is now a batch continuation.
   */
  private AXF_OBJ_ExportRun__c prepare(
    AXF_OBJ_ExportRun__c run,
    Account holder
  ) {
    Id accountId = holder.Id;
    Integer rows = countAllSources(accountId);
    if (rows > exportRowLimit()) {
      // Fail fast on a misconfigured retention policy before the batch is enqueued: the same
      // validation batchFinish() applies at the end, checked here too so a bad policy is not
      // discovered only after every source has already been fully drained across many chunks.
      downloadWindowMinutes();
      return startResumableBatch(run);
    }
    List<AXF_OBJ_FinancialTransaction__c> ftx = Database.queryWithBinds(
      FACT_QUERY,
      new Map<String, Object>{ 'accountId' => accountId },
      AccessLevel.USER_MODE
    );
    List<AXF_OBJ_BankAccountTransaction__c> bat = Database.queryWithBinds(
      BAT_QUERY,
      new Map<String, Object>{ 'accountId' => accountId },
      AccessLevel.USER_MODE
    );
    List<AXF_OBJ_CreditCardTransaction__c> cct = Database.queryWithBinds(
      CCT_QUERY,
      new Map<String, Object>{ 'accountId' => accountId },
      AccessLevel.USER_MODE
    );
    String csv = assembleCsv(ftx, bat, cct);
    Savepoint point = Database.setSavepoint();
    try {
      String fileName = FILE_NAME_PREFIX + run.Name + FILE_NAME_SUFFIX;
      run.AXF_EPR_TXT_FileName__c = fileName;
      run.AXF_EPR_TXT_ContentHash__c = sha256(csv);
      run.AXF_EPR_TXT_ContentDocument__c = store(fileName, csv);
      run.AXF_EPR_DT_ExpiresAt__c = Datetime.now()
        .addMinutes(downloadWindowMinutes());
      run.AXF_EPR_PKL_Status__c = STATUS_PREPARED;
      run.AXF_EPR_TXT_Reason__c = null;
      run.AXF_EPR_TXT_Cursor__c = null;
      run.AXF_EPR_DT_CompleteThrough__c = Datetime.now();
      checkpoint(run);
    } catch (Exception failure) {
      Database.rollback(point);
      throw failure;
    }
    return run;
  }

  /** Total rows across the three sources (AXF-118), the sync/batch threshold decision. */
  private static Integer countAllSources(Id accountId) {
    Integer ftxCount = [
      SELECT COUNT()
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE AXF_FTX_LKP_Account__c = :accountId
      WITH USER_MODE
    ];
    Integer batCount = [
      SELECT COUNT()
      FROM AXF_OBJ_BankAccountTransaction__c
      WHERE AXF_BAT_MDR_BankAccount__r.AXF_BA_LKP_Account__c = :accountId
      WITH USER_MODE
    ];
    Integer cctCount = [
      SELECT COUNT()
      FROM AXF_OBJ_CreditCardTransaction__c
      WHERE AXF_CCT_MDR_CreditCard__r.AXF_CC_LKP_Account__c = :accountId
      WITH USER_MODE
    ];
    return ftxCount + batCount + cctCount;
  }

  /**
   * Private artifact. The service creates NO ContentDocumentLink: the platform rejects the
   * least-exposure visibility (SharedUsers) for a record link, leaving only org-wide visibility,
   * and the ratified evidence pattern forbids a navigable link to a sensitive artifact ("nunca
   * cria ContentDocumentLink navegavel", SCHEMA-DICTIONARY.md). Revocation then deletes the
   * document itself.
   *
   * What that guarantees, exactly: every read **through this service** revalidates authorization
   * and the stored content hash before it serves anything, and the service opens no other path to
   * the document. What it does NOT guarantee: that direct platform access is prevented. When the
   * ContentVersion is written, the platform creates its own ContentDocumentLink (ShareType I) for
   * the creating user, and Files ownership lets that user open the file without passing through
   * this service. That residual is declared rather than defeated — the ratified FX resolution
   * requires the caveat to be acknowledged and administered separately
   * (review-fx-current-fit.md:66), so the service never claims to close it.
   *
   * The artifact is application-owned, so its DML runs in system mode after the caller was
   * authorized above: the project grants no Files CRUD to business users (the CSV evidence path
   * writes its ContentVersion the same way), and granting it just to upload would widen Files
   * access far beyond this story.
   */
  private static Id store(String fileName, String csv) {
    ContentVersion version = new ContentVersion(
      Title = fileName,
      PathOnClient = fileName,
      Description = 'Authorized export artifact (AXF-118).',
      VersionData = Blob.valueOf(csv)
    );
    Database.insert(version, AccessLevel.SYSTEM_MODE);
    return [
      SELECT ContentDocumentId
      FROM ContentVersion
      WHERE Id = :version.Id
      WITH SYSTEM_MODE
      LIMIT 1
    ]
    .ContentDocumentId;
  }

  /**
   * Reads the artifact this service wrote, under system mode because the caller was already
   * authorized above and the artifact is application-owned. The stored hash is rechecked: an
   * artifact that does not match its evidence is refused instead of served. Returns null after
   * revoking, so the caller reports the recorded reason without throwing (which would undo it).
   */
  private Blob body(AXF_OBJ_ExportRun__c run) {
    Id artifact = documentId(run);
    if (artifact == null) {
      // No addressable reference: either the run never had one or the stored pointer is not a
      // document id. revoke() clears it, so no dead reference is left claiming a copy exists.
      revoke(run, REASON_MISSING);
      return null;
    }
    List<ContentVersion> versions = [
      SELECT VersionData
      FROM ContentVersion
      WHERE ContentDocumentId = :artifact AND IsLatest = TRUE
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (versions.isEmpty() || versions[0].VersionData == null) {
      revoke(run, REASON_MISSING);
      return null;
    }
    Blob data = versions[0].VersionData;
    if (sha256(data.toString()) != run.AXF_EPR_TXT_ContentHash__c) {
      revoke(run, REASON_MISMATCH);
      return null;
    }
    return data;
  }

  // ---------------------------------------------------------------- revocation

  /**
   * Test seam for the one branch a healthy org cannot produce: an artifact the platform refuses
   * to remove. It exists so the state that branch must leave behind can be proved.
   */
  @TestVisible
  private static Boolean artifactRemovalFails = false;

  /**
   * Kills the artifact of a run: the document is deleted, so the only copy this application
   * controls stops existing and no link survives. A download already delivered cannot be
   * recalled, which AD-21 declares as an accepted limit rather than a promise.
   *
   * Never throws and never rolls back. A removal that fails must still leave a REVOKED state
   * behind — that is the only evidence the artifact no longer counts — so the failure is recorded
   * as the run's reason and reported as the outcome, and the document pointer is kept so a later
   * attempt can still remove the copy that survived. The recorded reason follows **this** attempt:
   * a retry that finally deleted the copy stops reporting a survivor.
   *
   * @return the reason recorded on the run, which the caller reports as the download outcome.
   */
  private String revoke(AXF_OBJ_ExportRun__c run, String reason) {
    String recorded = reason;
    if (run.AXF_EPR_TXT_ContentDocument__c != null) {
      Id artifact = documentId(run);
      if (artifact != null && !removeArtifact(artifact)) {
        // The copy survived **this** attempt, which is the fact an operator must be able to see,
        // so the pointer is kept for a later attempt.
        recorded = REASON_NOT_REMOVED;
      } else {
        // Removed, or a pointer no query could address: either way nothing here still points at a
        // copy. A retry that finally removed it must also stop claiming one survived.
        run.AXF_EPR_TXT_ContentDocument__c = null;
        if (REASON_NOT_REMOVED.equals(recorded)) {
          recorded = STATUS_REVOKED;
        }
      }
    }
    run.AXF_EPR_TXT_FileName__c = null;
    run.AXF_EPR_TXT_ContentHash__c = null;
    run.AXF_EPR_DT_ExpiresAt__c = null;
    run.AXF_EPR_PKL_Status__c = STATUS_REVOKED;
    run.AXF_EPR_TXT_Reason__c = recorded;
    checkpoint(run);
    log('REVOKED_' + recorded, run.Name);
    return recorded;
  }

  /**
   * Deletes the artifact. No business user is granted Delete on Files: the service removes its
   * own artifact, the same isolated policy-governed effect the closure orchestrator performs. The
   * removal is system mode for the same reason as the reads: the artifact is application-owned, and
   * a refusal has to remove it even for a caller whose own access to it is gone. A document that an
   * administrator or a Files policy already removed satisfies the goal state, so that one error
   * counts as removed; any other failure is reported to the caller, which records it instead of
   * claiming the artifact is gone.
   */
  private static Boolean removeArtifact(Id documentId) {
    if (artifactRemovalFails) {
      return false;
    }
    List<Database.DeleteResult> removed = Database.delete(
      new List<ContentDocument>{ new ContentDocument(Id = documentId) },
      false,
      AccessLevel.SYSTEM_MODE
    );
    if (removed[0].isSuccess()) {
      return true;
    }
    if (removed[0].getErrors().isEmpty()) {
      // A failure the platform did not explain is not evidence that the copy is gone: fail closed
      // rather than clear the only reference to an artifact that may still exist.
      return false;
    }
    for (Database.Error problem : removed[0].getErrors()) {
      if (problem.getStatusCode() != StatusCode.ENTITY_IS_DELETED) {
        return false;
      }
    }
    return true;
  }

  /**
   * The artifact pointer as an id. The field is Text because the Metadata API rejects a lookup to
   * ContentDocument, so a stored value that is not a document id is possible in principle; it is
   * answered as "no addressable artifact" instead of letting a platform cast error escape the
   * sanitized refusal path.
   */
  private static Id documentId(AXF_OBJ_ExportRun__c run) {
    return documentId(run.AXF_EPR_TXT_ContentDocument__c);
  }

  private static Id documentId(String stored) {
    if (String.isBlank(stored)) {
      return null;
    }
    try {
      return Id.valueOf(stored);
    } catch (Exception malformed) {
      return null;
    }
  }

  /**
   * Whether the artifact the run points at still exists. `read()` and `request()` use it so
   * availability is never advertised for a run whose download would refuse with
   * ARTIFACT_MISSING, and so the REQUEST_AGAIN they report is actionable.
   */
  private static Boolean artifactAvailable(String storedDocumentId) {
    Id artifact = documentId(storedDocumentId);
    if (artifact == null) {
      return false;
    }
    return ![
        SELECT Id
        FROM ContentVersion
        WHERE ContentDocumentId = :artifact AND IsLatest = TRUE
        WITH SYSTEM_MODE
        LIMIT 1
      ]
      .isEmpty();
  }

  // ---------------------------------------------------------------- csv (sync path)

  /**
   * Assembles the full export file out of the three independent sources (AXF-118): each keeps its
   * own native columns and its own header, one section per source that actually has rows for the
   * scope, in a fixed FTX/BAT/CCT order. A source with zero rows contributes no section at all.
   * Every section — even the only one present — carries its `# SOURCE` marker, matching the shape
   * the resumable batch path always produces (AXF-118 review fix): the same data must not produce
   * a differently-shaped CSV depending on which path prepared it. When every source is empty, the
   * header alone is returned, exactly as the original single-source csv() always did.
   */
  @TestVisible
  private static String assembleCsv(
    List<AXF_OBJ_FinancialTransaction__c> ftx,
    List<AXF_OBJ_BankAccountTransaction__c> bat,
    List<AXF_OBJ_CreditCardTransaction__c> cct
  ) {
    List<String> tagged = new List<String>();
    if (!ftx.isEmpty()) {
      tagged.add('# ' + SOURCE_FTX + '\n' + ftxSection(ftx));
    }
    if (!bat.isEmpty()) {
      tagged.add('# ' + SOURCE_BAT + '\n' + batSection(bat));
    }
    if (!cct.isEmpty()) {
      tagged.add('# ' + SOURCE_CCT + '\n' + cctSection(cct));
    }
    if (tagged.isEmpty()) {
      return CSV_HEADER;
    }
    return String.join(tagged, '\n\n');
  }

  private static String ftxSection(
    List<AXF_OBJ_FinancialTransaction__c> facts
  ) {
    List<String> lines = new List<String>{ CSV_HEADER };
    for (AXF_OBJ_FinancialTransaction__c fact : facts) {
      lines.add(
        String.join(
          new List<String>{
            cell(String.valueOf(fact.AXF_FTX_DAT_PurchaseDate__c)),
            cell(fact.AXF_FTX_PKL_Direction__c),
            cell(
              fact.AXF_FTX_NUM_Magnitude__c == null
                ? null
                : fact.AXF_FTX_NUM_Magnitude__c.toPlainString()
            ),
            cell(fact.AXF_FTX_TXT_CurrencyIsoCode__c),
            cell(fact.AXF_FTX_PKL_Status__c),
            cell(fact.AXF_FTX_TXT_Description__c)
          },
          ','
        )
      );
    }
    return String.join(lines, '\n');
  }

  private static String batSection(
    List<AXF_OBJ_BankAccountTransaction__c> facts
  ) {
    List<String> lines = new List<String>{ BAT_HEADER };
    for (AXF_OBJ_BankAccountTransaction__c fact : facts) {
      lines.add(
        String.join(
          new List<String>{
            cell(String.valueOf(fact.AXF_BAT_DAT_Date__c)),
            cell(fact.AXF_BAT_PKL_Direction__c),
            cell(
              fact.AXF_BAT_NUM_Magnitude__c == null
                ? null
                : fact.AXF_BAT_NUM_Magnitude__c.toPlainString()
            ),
            cell(fact.AXF_BAT_TXT_CurrencyIsoCode__c),
            cell(fact.AXF_BAT_PKL_Status__c),
            cell(fact.AXF_BAT_TXT_Description__c),
            cell(fact.AXF_BAT_MDR_BankAccount__r?.AXF_BA_TXT_NumberMasked__c)
          },
          ','
        )
      );
    }
    return String.join(lines, '\n');
  }

  private static String cctSection(
    List<AXF_OBJ_CreditCardTransaction__c> facts
  ) {
    List<String> lines = new List<String>{ CCT_HEADER };
    for (AXF_OBJ_CreditCardTransaction__c fact : facts) {
      lines.add(
        String.join(
          new List<String>{
            cell(String.valueOf(fact.AXF_CCT_DAT_Date__c)),
            cell(fact.AXF_CCT_PKL_Direction__c),
            cell(
              fact.AXF_CCT_NUM_Magnitude__c == null
                ? null
                : fact.AXF_CCT_NUM_Magnitude__c.toPlainString()
            ),
            cell(fact.AXF_CCT_TXT_CurrencyIsoCode__c),
            cell(fact.AXF_CCT_PKL_Status__c),
            cell(fact.AXF_CCT_TXT_Description__c),
            cell(fact.AXF_CCT_MDR_CreditCard__r?.AXF_CC_TXT_LastFourMasked__c),
            cell(fact.AXF_CCT_TXT_MerchantName__c)
          },
          ','
        )
      );
    }
    return String.join(lines, '\n');
  }

  /**
   * Quoted unconditionally, with the leading formula prefix neutralized by the single shared
   * policy AD-25 requires so import and export cannot disagree on active content.
   */
  private static String cell(String value) {
    String safe = ALT_CLS_CsvFormatParser.neutralizeFormula(value);
    if (safe == null) {
      return '""';
    }
    return '"' + safe.replace('"', '""') + '"';
  }

  // ---------------------------------------------------------------- resumable batch (AXF-118)

  /**
   * Moves a fresh run to RUNNING and hands it to the resumable batch. The cursor starts empty
   * (nothing processed yet); Attempt starts at 1.
   */
  private AXF_OBJ_ExportRun__c startResumableBatch(AXF_OBJ_ExportRun__c run) {
    Savepoint point = Database.setSavepoint();
    try {
      run.AXF_EPR_PKL_Status__c = STATUS_RUNNING;
      run.AXF_EPR_TXT_Reason__c = null;
      run.AXF_EPR_TXT_Cursor__c = null;
      run.AXF_EPR_DT_Watermark__c = Datetime.now();
      run.AXF_EPR_DT_CompleteThrough__c = null;
      run.AXF_EPR_NUM_Attempt__c = 1;
      checkpoint(run);
    } catch (Exception failure) {
      Database.rollback(point);
      throw failure;
    }
    Database.executeBatch(new ALT_CLS_ExportRunBatch(run.Id), batchScope());
    return run;
  }

  /**
   * Resumes a PARTIAL run: the persisted cursor is left untouched (the new batch job re-reads it
   * from the run at its own start()), only the state and attempt counter move.
   */
  private AXF_OBJ_ExportRun__c resumeBatch(AXF_OBJ_ExportRun__c run) {
    Savepoint point = Database.setSavepoint();
    try {
      run.AXF_EPR_PKL_Status__c = STATUS_RUNNING;
      run.AXF_EPR_TXT_Reason__c = null;
      run.AXF_EPR_NUM_Attempt__c = (run.AXF_EPR_NUM_Attempt__c == null
        ? 1
        : run.AXF_EPR_NUM_Attempt__c + 1);
      checkpoint(run);
    } catch (Exception failure) {
      Database.rollback(point);
      throw failure;
    }
    Database.executeBatch(new ALT_CLS_ExportRunBatch(run.Id), batchScope());
    log('RUNNING', run.Name);
    return run;
  }

  /** BATCH_CHUNK_SIZE in production; a test-set override while running under Test.isRunningTest(). */
  private static Integer batchScope() {
    return (Test.isRunningTest() && batchScopeOverride != null)
      ? batchScopeOverride
      : BATCH_CHUNK_SIZE;
  }

  /** EXPORT_ROW_LIMIT in production; a test-set override while running under Test.isRunningTest(). */
  private static Integer exportRowLimit() {
    return (Test.isRunningTest() && exportRowLimitOverride != null)
      ? exportRowLimitOverride
      : EXPORT_ROW_LIMIT;
  }

  /**
   * Batch-facing entry points below. Called only by {@link ALT_CLS_ExportRunBatch}, which runs in
   * its own transaction per chunk; every one of them is self-contained (loads what it needs,
   * commits or rolls back its own effect) so the batch class stays a thin driver.
   */

  /** Minimal run projection the batch needs, read in system mode (application-owned state). */
  public static AXF_OBJ_ExportRun__c batchLoadRun(Id runId) {
    List<AXF_OBJ_ExportRun__c> rows = Database.queryWithBinds(
      'SELECT ' +
        RUN_FIELDS +
        ' FROM AXF_OBJ_ExportRun__c WHERE Id = :runId LIMIT 1',
      new Map<String, Object>{ 'runId' => runId },
      AccessLevel.SYSTEM_MODE
    );
    if (rows.isEmpty()) {
      throw failure('NOT_ACCESSIBLE');
    }
    return rows[0];
  }

  /** Resume point for the batch's source iterator: the account and the persisted cursor. */
  public class BatchCursor {
    public Id accountId;
    public Map<String, String> lastIdBySource;
  }

  public static BatchCursor batchCursor(Id runId) {
    AXF_OBJ_ExportRun__c run = batchLoadRun(runId);
    BatchCursor result = new BatchCursor();
    result.accountId = run.AXF_EPR_LKP_Account__c;
    result.lastIdBySource = parseCursor(run.AXF_EPR_TXT_Cursor__c);
    return result;
  }

  /** One page of a source, ordered and filtered strictly after `afterId` (keyset pagination). */
  public static List<AXF_OBJ_FinancialTransaction__c> queryFtxPage(
    Id accountId,
    Id afterId,
    Integer pageSize
  ) {
    String clause = afterId == null ? '' : ' AND Id > :afterId';
    return Database.queryWithBinds(
      'SELECT AXF_FTX_DAT_PurchaseDate__c, AXF_FTX_PKL_Direction__c, AXF_FTX_NUM_Magnitude__c, ' +
        'AXF_FTX_TXT_CurrencyIsoCode__c, AXF_FTX_PKL_Status__c, AXF_FTX_TXT_Description__c ' +
        'FROM AXF_OBJ_FinancialTransaction__c ' +
        'WHERE AXF_FTX_LKP_Account__c = :accountId' +
        clause +
        ' ORDER BY Id LIMIT :pageSize',
      new Map<String, Object>{
        'accountId' => accountId,
        'afterId' => afterId,
        'pageSize' => pageSize
      },
      AccessLevel.USER_MODE
    );
  }

  public static List<AXF_OBJ_BankAccountTransaction__c> queryBatPage(
    Id accountId,
    Id afterId,
    Integer pageSize
  ) {
    String clause = afterId == null ? '' : ' AND Id > :afterId';
    return Database.queryWithBinds(
      'SELECT AXF_BAT_DAT_Date__c, AXF_BAT_PKL_Direction__c, AXF_BAT_NUM_Magnitude__c, ' +
        'AXF_BAT_TXT_CurrencyIsoCode__c, AXF_BAT_PKL_Status__c, AXF_BAT_TXT_Description__c, ' +
        'AXF_BAT_MDR_BankAccount__r.AXF_BA_TXT_NumberMasked__c ' +
        'FROM AXF_OBJ_BankAccountTransaction__c ' +
        'WHERE AXF_BAT_MDR_BankAccount__r.AXF_BA_LKP_Account__c = :accountId' +
        clause +
        ' ORDER BY Id LIMIT :pageSize',
      new Map<String, Object>{
        'accountId' => accountId,
        'afterId' => afterId,
        'pageSize' => pageSize
      },
      AccessLevel.USER_MODE
    );
  }

  public static List<AXF_OBJ_CreditCardTransaction__c> queryCctPage(
    Id accountId,
    Id afterId,
    Integer pageSize
  ) {
    String clause = afterId == null ? '' : ' AND Id > :afterId';
    return Database.queryWithBinds(
      'SELECT AXF_CCT_DAT_Date__c, AXF_CCT_PKL_Direction__c, AXF_CCT_NUM_Magnitude__c, ' +
        'AXF_CCT_TXT_CurrencyIsoCode__c, AXF_CCT_PKL_Status__c, AXF_CCT_TXT_Description__c, ' +
        'AXF_CCT_MDR_CreditCard__r.AXF_CC_TXT_LastFourMasked__c, AXF_CCT_TXT_MerchantName__c ' +
        'FROM AXF_OBJ_CreditCardTransaction__c ' +
        'WHERE AXF_CCT_MDR_CreditCard__r.AXF_CC_LKP_Account__c = :accountId' +
        clause +
        ' ORDER BY Id LIMIT :pageSize',
      new Map<String, Object>{
        'accountId' => accountId,
        'afterId' => afterId,
        'pageSize' => pageSize
      },
      AccessLevel.USER_MODE
    );
  }

  /** `SOURCE:lastId` pairs, semicolon-separated; a source absent from the map was never reached. */
  @TestVisible
  private static Map<String, String> parseCursor(String raw) {
    Map<String, String> result = new Map<String, String>();
    if (String.isBlank(raw)) {
      return result;
    }
    for (String part : raw.split(';')) {
      List<String> kv = part.split(':', 2);
      if (kv.size() == 2 && String.isNotBlank(kv[0])) {
        result.put(kv[0], kv[1]);
      }
    }
    return result;
  }

  @TestVisible
  private static String serializeCursor(Map<String, String> lastIdBySource) {
    List<String> parts = new List<String>();
    for (
      String source : new List<String>{ SOURCE_FTX, SOURCE_BAT, SOURCE_CCT }
    ) {
      if (lastIdBySource.containsKey(source)) {
        parts.add(source + ':' + lastIdBySource.get(source));
      }
    }
    return parts.isEmpty() ? null : String.join(parts, ';');
  }

  /**
   * Persists one chunk: the artifact content already written so far is read back, the new rows
   * (grouped by source, a chunk may straddle two adjacent sources since the iterator's page size
   * need not align with the batch scope size) are appended — with a section header only the first
   * time a source appears, tracked by the cursor map itself — and the whole thing is written as a
   * new ContentVersion together with the advanced cursor, in one savepoint-guarded unit: either
   * both persist, or neither does, so a mid-chunk failure can never lose the cursor or duplicate a
   * row already durably written.
   */
  /**
   * Test seam: forces exactly the next chunk to fail, so a test can prove the cursor and any
   * content already checkpointed by a prior chunk survive the failure untouched, and that a
   * resumed run neither loses nor duplicates rows.
   */
  @TestVisible
  private static Boolean forceNextChunkFailure = false;

  public static void batchAppendChunk(Id runId, List<SObject> scope) {
    if (forceNextChunkFailure) {
      forceNextChunkFailure = false;
      throw new ExportException('FORCED_TEST_FAILURE');
    }
    AXF_OBJ_ExportRun__c run = batchLoadRun(runId);
    Map<String, String> cursor = parseCursor(run.AXF_EPR_TXT_Cursor__c);
    List<AXF_OBJ_FinancialTransaction__c> ftx = new List<AXF_OBJ_FinancialTransaction__c>();
    List<AXF_OBJ_BankAccountTransaction__c> bat = new List<AXF_OBJ_BankAccountTransaction__c>();
    List<AXF_OBJ_CreditCardTransaction__c> cct = new List<AXF_OBJ_CreditCardTransaction__c>();
    for (SObject record : scope) {
      if (record instanceof AXF_OBJ_FinancialTransaction__c) {
        ftx.add((AXF_OBJ_FinancialTransaction__c) record);
      } else if (record instanceof AXF_OBJ_BankAccountTransaction__c) {
        bat.add((AXF_OBJ_BankAccountTransaction__c) record);
      } else if (record instanceof AXF_OBJ_CreditCardTransaction__c) {
        cct.add((AXF_OBJ_CreditCardTransaction__c) record);
      }
    }
    String addition = '';
    if (!ftx.isEmpty()) {
      addition += chunkSection(SOURCE_FTX, ftxSection(ftx), cursor);
      cursor.put(SOURCE_FTX, String.valueOf(ftx[ftx.size() - 1].Id));
    }
    if (!bat.isEmpty()) {
      addition += chunkSection(SOURCE_BAT, batSection(bat), cursor);
      cursor.put(SOURCE_BAT, String.valueOf(bat[bat.size() - 1].Id));
    }
    if (!cct.isEmpty()) {
      addition += chunkSection(SOURCE_CCT, cctSection(cct), cursor);
      cursor.put(SOURCE_CCT, String.valueOf(cct[cct.size() - 1].Id));
    }
    if (String.isBlank(addition)) {
      return;
    }
    Savepoint point = Database.setSavepoint();
    try {
      String existingContent = run.AXF_EPR_TXT_ContentDocument__c == null
        ? ''
        : currentContent(run.AXF_EPR_TXT_ContentDocument__c);
      String newContent = existingContent.length() == 0
        ? addition.replaceFirst('^\n+', '')
        : existingContent + addition;
      if (run.AXF_EPR_TXT_ContentDocument__c == null) {
        String fileName = FILE_NAME_PREFIX + run.Name + FILE_NAME_SUFFIX;
        run.AXF_EPR_TXT_FileName__c = fileName;
        run.AXF_EPR_TXT_ContentDocument__c = store(fileName, newContent);
      } else {
        appendVersion(run.AXF_EPR_TXT_FileName__c, documentId(run), newContent);
      }
      run.AXF_EPR_TXT_Cursor__c = serializeCursor(cursor);
      run.AXF_EPR_DT_Watermark__c = Datetime.now();
      run.AXF_EPR_DT_CompleteThrough__c = Datetime.now();
      checkpoint(run);
    } catch (Exception failure) {
      Database.rollback(point);
      throw failure;
    }
  }

  /**
   * A section's marker and column header, only the first time its source appears (tracked by
   * whether the cursor map already has an entry for it); every later chunk of the same source
   * appends only its rows, on a new line after whatever was written last.
   */
  private static String chunkSection(
    String source,
    String sectionCsv,
    Map<String, String> cursor
  ) {
    String rows = rowsOnly(sectionCsv);
    if (cursor.containsKey(source)) {
      return '\n' + rows;
    }
    return '\n\n# ' + source + '\n' + sectionHeaderLine(source) + '\n' + rows;
  }

  /** Strips the header line a section() builder always includes; the batch owns header timing. */
  private static String rowsOnly(String sectionCsv) {
    Integer firstBreak = sectionCsv.indexOf('\n');
    return firstBreak < 0 ? '' : sectionCsv.substring(firstBreak + 1);
  }

  /**
   * The batch always writes the section's own header immediately after its `# SOURCE` marker, so
   * `chunkSection` needs it back; rebuilt here rather than threading it through every call site.
   */
  private static String sectionHeaderLine(String source) {
    if (source == SOURCE_FTX) {
      return CSV_HEADER;
    }
    if (source == SOURCE_BAT) {
      return BAT_HEADER;
    }
    return CCT_HEADER;
  }

  private static String currentContent(String storedDocumentId) {
    Id artifact = documentId(storedDocumentId);
    if (artifact == null) {
      return '';
    }
    List<ContentVersion> versions = [
      SELECT VersionData
      FROM ContentVersion
      WHERE ContentDocumentId = :artifact AND IsLatest = TRUE
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (versions.isEmpty() || versions[0].VersionData == null) {
      return '';
    }
    return versions[0].VersionData.toString();
  }

  private static void appendVersion(
    String fileName,
    Id documentId,
    String content
  ) {
    ContentVersion version = new ContentVersion(
      ContentDocumentId = documentId,
      Title = fileName,
      PathOnClient = fileName,
      VersionData = Blob.valueOf(content)
    );
    Database.insert(version, AccessLevel.SYSTEM_MODE);
  }

  /** Called from the batch's finish(): the run completed every source without a chunk failure. */
  public static void batchFinish(Id runId) {
    AXF_OBJ_ExportRun__c run = batchLoadRun(runId);
    Savepoint point = Database.setSavepoint();
    try {
      String content = currentContent(run.AXF_EPR_TXT_ContentDocument__c);
      if (String.isBlank(content)) {
        // Every source was empty: the batch was launched (rows counted above the limit) but a
        // concurrent deletion could still leave nothing to persist; fall back to the same empty
        // header the sync path would have produced, so the artifact is never left undefined.
        content = CSV_HEADER;
        String fileName = FILE_NAME_PREFIX + run.Name + FILE_NAME_SUFFIX;
        run.AXF_EPR_TXT_FileName__c = fileName;
        run.AXF_EPR_TXT_ContentDocument__c = store(fileName, content);
      }
      run.AXF_EPR_TXT_ContentHash__c = sha256(content);
      run.AXF_EPR_DT_ExpiresAt__c = Datetime.now()
        .addMinutes(downloadWindowMinutes());
      run.AXF_EPR_PKL_Status__c = STATUS_PREPARED;
      run.AXF_EPR_TXT_Reason__c = null;
      run.AXF_EPR_DT_CompleteThrough__c = Datetime.now();
      checkpoint(run);
    } catch (Exception failure) {
      Database.rollback(point);
      throw failure;
    }
    // Outside the savepoint's try/catch on purpose: PREPARED is already durably committed above.
    // A notify/log failure here must never propagate to ALT_CLS_ExportRunBatch.finish()'s catch,
    // which would call batchFail() and revert this already-complete, hashed run back to PARTIAL.
    try {
      notifyRequester(run);
      log('PREPARED', run.Name);
    } catch (Exception postCommitFailure) {
      System.debug(
        LoggingLevel.ERROR,
        'AXF-118 export run ' +
          run.Name +
          ' committed PREPARED but notify/log failed: ' +
          postCommitFailure.getMessage()
      );
    }
  }

  /**
   * Called from the batch's execute()/finish() catch blocks: never throws. The cursor and any
   * content already checkpointed by a prior chunk are untouched — only the status and reason move
   * — so a later `request()` resumes exactly where the last successful chunk left off.
   */
  public static void batchFail(Id runId, String reasonCode) {
    try {
      AXF_OBJ_ExportRun__c run = batchLoadRun(runId);
      run.AXF_EPR_PKL_Status__c = STATUS_PARTIAL;
      run.AXF_EPR_TXT_Reason__c = reasonCode;
      checkpoint(run);
      log('PARTIAL_' + reasonCode, run.Name);
    } catch (Exception ignored) {
      System.debug(
        LoggingLevel.ERROR,
        'AXF-118 export run ' +
          runId +
          ' could not record failure: ' +
          reasonCode
      );
    }
  }

  // ---------------------------------------------------------------- retention policy (AXF-118)

  /**
   * Short-lived download window, read from AXF_CMT_RetentionPolicy__mdt('Export') instead of a
   * hardcoded constant. A missing, disabled or incompletely configured record is a sanitized
   * explicit failure: never a silently invented default.
   */
  private static Integer downloadWindowMinutes() {
    List<AXF_CMT_RetentionPolicy__mdt> policies = [
      SELECT AXF_RPT_BOL_Enabled__c, AXF_RPT_NUM_WindowMinutes__c
      FROM AXF_CMT_RetentionPolicy__mdt
      WHERE DeveloperName = :RETENTION_POLICY_NAME
      LIMIT 1
    ];
    if (
      policies.isEmpty() ||
      policies[0].AXF_RPT_BOL_Enabled__c != true ||
      policies[0].AXF_RPT_NUM_WindowMinutes__c == null ||
      policies[0].AXF_RPT_NUM_WindowMinutes__c <= 0
    ) {
      // A configured-but-nonpositive window would silently produce an immediate/past expiry
      // instead of the explicit-failure guarantee this domain promises: treated the same as a
      // missing or disabled record, never a silently invented default.
      throw failure('EXPORT_POLICY_MISSING');
    }
    return policies[0].AXF_RPT_NUM_WindowMinutes__c.intValue();
  }

  // ---------------------------------------------------------------- authorization

  private void requireCapability() {
    if (!hasCapability()) {
      throw failure('FORBIDDEN');
    }
  }

  private static Boolean hasCapability() {
    return FeatureManagement.checkPermission(CP_EXPORT);
  }

  /** First gate: capability, holder visibility and read access to the exact scope. */
  private Account authorizedHolder(Id accountId) {
    if (accountId == null) {
      throw failure('INVALID_INPUT');
    }
    requireCapability();
    List<Account> holders = [
      SELECT Id, OwnerId
      FROM Account
      WHERE Id = :accountId
      WITH USER_MODE
      LIMIT 1
    ];
    if (holders.isEmpty() || !hasHolderReadAccess(accountId)) {
      throw failure('NOT_ACCESSIBLE');
    }
    return holders[0];
  }

  /**
   * Effective access to the scope, read from the platform. Re-evaluated on the download and in
   * the availability `read()` reports, so a withdrawn share revokes the artifact instead of
   * leaving it reachable, and is never advertised as downloadable.
   */
  private static Boolean hasHolderReadAccess(Id accountId) {
    List<UserRecordAccess> access = [
      SELECT RecordId, HasReadAccess
      FROM UserRecordAccess
      WHERE UserId = :UserInfo.getUserId() AND RecordId = :accountId
      LIMIT 1
    ];
    return !access.isEmpty() && access[0].HasReadAccess == true;
  }

  @TestVisible
  private static String scopeKey(Id accountId, Id requesterId) {
    return sha256(
      String.valueOf(accountId) + '|' + String.valueOf(requesterId)
    );
  }

  /**
   * Whether the platform named the scope key among the fields it rejected. Compared by describe
   * name rather than by token identity, so the answer does not depend on how the platform hands
   * the tokens back.
   */
  private static Boolean namesScopeKey(List<Schema.SObjectField> fields) {
    for (Schema.SObjectField field : fields) {
      if (field.getDescribe().getName() == 'AXF_EPR_EXI_ScopeKey__c') {
        return true;
      }
    }
    return false;
  }

  // ---------------------------------------------------------------- persistence

  private AXF_OBJ_ExportRun__c insertRun(Account holder, String key) {
    AXF_OBJ_ExportRun__c run = new AXF_OBJ_ExportRun__c(
      AXF_EPR_LKP_Account__c = holder.Id,
      AXF_EPR_LKP_Requester__c = UserInfo.getUserId(),
      AXF_EPR_EXI_ScopeKey__c = key,
      AXF_EPR_PKL_Status__c = STATUS_REQUESTED,
      AXF_EPR_NUM_Version__c = 1,
      OwnerId = holder.OwnerId
    );
    // System mode: the control row is application-owned state whose fields are read-only to
    // users, and the owner follows the holder (G2) rather than the caller. The caller was
    // authorized for the scope immediately above.
    Database.insert(run, AccessLevel.SYSTEM_MODE);
    return run;
  }

  /** Id only: the caller reloads the run so every field it reads is explicitly queried. */
  private Id findByScopeKey(String key) {
    List<AXF_OBJ_ExportRun__c> rows = [
      SELECT Id
      FROM AXF_OBJ_ExportRun__c
      WHERE AXF_EPR_EXI_ScopeKey__c = :key
      WITH USER_MODE
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0].Id;
  }

  /**
   * Same lookup under system mode, for the one case where the row cannot be visible yet: the
   * winner of a scope-key race grants the requester its share only after its own insert.
   */
  private Id findByScopeKeySystemMode(String key) {
    List<AXF_OBJ_ExportRun__c> rows = Database.queryWithBinds(
      'SELECT Id FROM AXF_OBJ_ExportRun__c WHERE AXF_EPR_EXI_ScopeKey__c = :key LIMIT 1',
      new Map<String, Object>{ 'key' => key },
      AccessLevel.SYSTEM_MODE
    );
    return rows.isEmpty() ? null : rows[0].Id;
  }

  /** The run must be visible to the caller: ownership, or the share granted to the requester. */
  private AXF_OBJ_ExportRun__c loadRun(Id runId) {
    return loadRun(runId, AccessLevel.USER_MODE);
  }

  /**
   * Reads the control row in system mode. Used where the row is application-owned state the
   * caller may not be able to see: immediately after its own insert, as the winner of a race, and
   * on the refusal paths of download(), which must reach the run to revoke the artifact even
   * after the capability was withdrawn. Every caller of this decides authorization with explicit
   * checks; none of them delegates it to the query's access mode.
   */
  private AXF_OBJ_ExportRun__c loadRunPrivileged(Id runId) {
    return loadRun(runId, AccessLevel.SYSTEM_MODE);
  }

  private AXF_OBJ_ExportRun__c loadRun(Id runId, AccessLevel mode) {
    List<AXF_OBJ_ExportRun__c> rows = Database.queryWithBinds(
      'SELECT ' +
        RUN_FIELDS +
        ' FROM AXF_OBJ_ExportRun__c WHERE Id = :runId LIMIT 1',
      new Map<String, Object>{ 'runId' => runId },
      mode
    );
    if (rows.isEmpty()) {
      throw failure('NOT_ACCESSIBLE');
    }
    return rows[0];
  }

  /**
   * Locks and reloads the run for a state transition: the lock serializes concurrent downloads
   * (NFR-18), and the re-read is what the caller's expectedVersion is compared against, so a
   * stale expectation is refused instead of overwriting a state the caller never saw.
   */
  private AXF_OBJ_ExportRun__c lockAndLoad(Id runId, Decimal expectedVersion) {
    AXF_OBJ_ExportRun__c run = loadRunPrivileged(runId);
    List<AXF_OBJ_ExportRun__c> locked = [
      SELECT Id, AXF_EPR_NUM_Version__c
      FROM AXF_OBJ_ExportRun__c
      WHERE Id = :runId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    if (locked.isEmpty()) {
      // The row vanished between the read and the lock: refuse with a safe code instead of
      // letting the platform ListException escape.
      throw failure('NOT_ACCESSIBLE');
    }
    if (expectedVersion == null) {
      throw failure('INVALID_INPUT');
    }
    if (expectedVersion != locked[0].AXF_EPR_NUM_Version__c) {
      throw failure('CONFLICT');
    }
    run.AXF_EPR_NUM_Version__c = locked[0].AXF_EPR_NUM_Version__c;
    return run;
  }

  private static void checkpoint(AXF_OBJ_ExportRun__c run) {
    run.AXF_EPR_NUM_Version__c = run.AXF_EPR_NUM_Version__c == null
      ? 1
      : run.AXF_EPR_NUM_Version__c + 1;
    // System mode for the same reason as the insert: the state machine is Apex's, and the fields
    // it advances are read-only to users.
    Database.update(run, AccessLevel.SYSTEM_MODE);
  }

  /**
   * The run follows the holder's owner (G2), so a requester who is not that owner keeps access
   * only through this explicit share. Read level: the state machine belongs to Apex and the
   * fields it writes are read-only to users, so an edit share would grant nothing but the
   * ability to change fields the service owns.
   */
  @SuppressWarnings('PMD.ApexCRUDViolation')
  private static void grantRequesterAccess(Id runId, Id ownerId) {
    Id me = UserInfo.getUserId();
    if (me == ownerId) {
      return;
    }
    Database.SaveResult granted = Database.insert(
      new AXF_OBJ_ExportRun__Share(
        ParentId = runId,
        UserOrGroupId = me,
        AccessLevel = 'Read',
        RowCause = Schema.AXF_OBJ_ExportRun__Share.RowCause.Manual
      ),
      false,
      AccessLevel.SYSTEM_MODE
    );
    if (!granted.isSuccess()) {
      // Without the share the requester cannot read the run it just asked for, so the artifact
      // would be unreachable: refuse with a safe code instead of returning an unusable run.
      throw failure('SHARE_FAILED');
    }
  }

  private static Boolean isElapsed(AXF_OBJ_ExportRun__c run) {
    return run.AXF_EPR_DT_ExpiresAt__c == null ||
      Datetime.now() >= run.AXF_EPR_DT_ExpiresAt__c;
  }

  // ---------------------------------------------------------------- notification and logs

  /**
   * In-app notification text. Built from the opaque run number only: no holder name, no
   * document, no e-mail, no file content. The test class reads this exact builder, so the text
   * that is sent is the text that is checked.
   */
  @TestVisible
  private static Map<String, String> notificationText(String runName) {
    return new Map<String, String>{
      'title' => 'Axon: exportacao autorizada pronta',
      'body' => 'Sua exportacao ' +
      runName +
      ' esta pronta para download.'
    };
  }

  /**
   * Observation of the notice path. The type lookup and the send are both swallowed by design, so
   * without these two the only thing a test can see is the text builder — a wrong DeveloperName
   * would pass green. They are set only after the platform accepted the send, following the merged
   * ALT_CLS_SharedExpenseService seam.
   */
  @TestVisible
  private static Boolean notificationSent = false;
  /** Notification type the last attempt resolved; null when it never resolved one. */
  @TestVisible
  private static Id lastNotificationTypeId;

  private static void notifyRequester(AXF_OBJ_ExportRun__c run) {
    try {
      List<CustomNotificationType> types = [
        SELECT Id
        FROM CustomNotificationType
        WHERE DeveloperName = 'AXF_ExportReady'
        LIMIT 1
      ];
      if (types.isEmpty()) {
        return;
      }
      Map<String, String> text = notificationText(run.Name);
      Messaging.CustomNotification notification = new Messaging.CustomNotification();
      notification.setTitle(text.get('title'));
      notification.setBody(text.get('body'));
      notification.setNotificationTypeId(types[0].Id);
      notification.setTargetId(run.Id);
      notification.send(
        new Set<String>{ String.valueOf(run.AXF_EPR_LKP_Requester__c) }
      );
      lastNotificationTypeId = types[0].Id;
      notificationSent = true;
    } catch (Exception undelivered) {
      // The artifact already exists; a lost notification never undoes it.
      log('NOTIFY_FAILED', run.Name);
    }
  }

  /**
   * The single log line builder, and the only argument any debug call site receives. It carries
   * a fixed code and the opaque run number, never a description, identifier or record value.
   */
  @TestVisible
  private static String logLine(String code, String runName) {
    return 'AXF-118 ' + code + ' ' + (String.isBlank(runName) ? '-' : runName);
  }

  private static void log(String code, String runName) {
    System.debug(LoggingLevel.INFO, logLine(code, runName));
  }

  // ---------------------------------------------------------------- mapping

  private static DownloadView refused(String outcome) {
    DownloadView view = new DownloadView();
    view.outcome = String.isBlank(outcome) ? 'REVOKED' : outcome;
    return view;
  }

  private static RunView toView(AXF_OBJ_ExportRun__c run) {
    RunView view = new RunView();
    view.runId = run.Id;
    view.name = run.Name;
    view.accountId = run.AXF_EPR_LKP_Account__c;
    view.status = run.AXF_EPR_PKL_Status__c;
    view.fileName = run.AXF_EPR_TXT_FileName__c;
    view.contentHash = run.AXF_EPR_TXT_ContentHash__c;
    view.expiresAt = run.AXF_EPR_DT_ExpiresAt__c;
    view.reason = run.AXF_EPR_TXT_Reason__c;
    view.evidenceRef = run.AXF_EPR_TXT_ContentDocument__c == null ||
      run.AXF_EPR_PKL_Status__c == STATUS_REVOKED
      ? null
      : String.valueOf(run.AXF_EPR_TXT_ContentDocument__c);
    view.version = run.AXF_EPR_NUM_Version__c;
    if (
      run.AXF_EPR_PKL_Status__c == STATUS_RUNNING ||
      run.AXF_EPR_PKL_Status__c == STATUS_PARTIAL
    ) {
      // A resumable batch is in flight or paused on a recoverable failure: never advertise a
      // download, and never REQUEST_AGAIN (which would restart instead of letting it resume).
      view.canDownload = false;
      view.nextAction = 'PROCESSING';
      return view;
    }
    // Availability is only reported as real when every gate download() applies still passes: the
    // requester binding, the state, the window, the holder access revalidated against the platform,
    // and the artifact itself still being there. Otherwise read() would advertise DOWNLOAD for a
    // scope whose authorization was withdrawn or for a run whose download would revoke instead of
    // serving, and the REQUEST_AGAIN it reports would not be actionable by request().
    Boolean live =
      run.AXF_EPR_LKP_Requester__c == UserInfo.getUserId() &&
      (run.AXF_EPR_PKL_Status__c == STATUS_PREPARED ||
      run.AXF_EPR_PKL_Status__c == STATUS_DOWNLOADED) &&
      !isElapsed(run) &&
      hasHolderReadAccess(run.AXF_EPR_LKP_Account__c) &&
      artifactAvailable(run.AXF_EPR_TXT_ContentDocument__c);
    view.canDownload = live;
    view.nextAction = live ? 'DOWNLOAD' : 'REQUEST_AGAIN';
    return view;
  }

  private static String sha256(String value) {
    return EncodingUtil.convertToHex(
      Crypto.generateDigest('SHA-256', Blob.valueOf(value))
    );
  }

  private static ExportException failure(String code) {
    ExportException result = new ExportException(code);
    result.code = code;
    return result;
  }
}
