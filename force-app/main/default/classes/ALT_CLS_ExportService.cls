/**
 * @description AXF-118 authorized data export (the export slice of AXF-9). One holder scope is
 * exported to a private, short-lived artifact: authorization is verified when the request is
 * made and again on every download, and **every** refusal that finds a live artifact revokes it
 * by deleting the artifact before refusing — an elapsed window, a withdrawn capability, a lost
 * requester binding, a lost holder access, or an artifact that is missing or does not match its
 * evidence. File name, notification and log lines carry no PII: they use only the run's opaque
 * auto-number.
 *
 * Scope boundary: the holder's canonical financial facts (AXF_OBJ_FinancialTransaction__c),
 * bounded by EXPORT_ROW_LIMIT. Cell values are neutralized against spreadsheet formulas by the
 * single project neutralizer (AD-25), the same one the CSV import uses.
 *
 * No ratified document fixes the physical export/download mechanism, the export scope, the
 * artifact retention or the download window (AXF-9:107 forbids inventing schema or deadlines).
 * The choices taken here are declared as assumptions in docs/implementation/AXF-118.md. The
 * download is never a public link: a ContentDistribution has no caller identity, so it could
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
  /**
   * Short-lived download window. ASSUMPTION: no ratified source fixes a value for the export
   * artifact, and the G7-3 retention table has no export domain, so this is declared rather
   * than derived.
   */
  public static final Integer DOWNLOAD_WINDOW_MINUTES = 15;
  /** Rows in one artifact. Above it the request blocks instead of discarding rows silently. */
  public static final Integer EXPORT_ROW_LIMIT = 5000;
  private static final String STATUS_REQUESTED = 'REQUESTED';
  private static final String STATUS_PREPARED = 'PREPARED';
  private static final String STATUS_DOWNLOADED = 'DOWNLOADED';
  private static final String STATUS_REVOKED = 'REVOKED';
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
  /** Reproducible order, so the same scope always hashes to the same artifact. */
  private static final String FACT_QUERY =
    'SELECT AXF_FTX_DAT_PurchaseDate__c, AXF_FTX_PKL_Direction__c, AXF_FTX_NUM_Magnitude__c, ' +
    'AXF_FTX_TXT_CurrencyIsoCode__c, AXF_FTX_PKL_Status__c, AXF_FTX_TXT_Description__c ' +
    'FROM AXF_OBJ_FinancialTransaction__c ' +
    'WHERE AXF_FTX_LKP_Account__c = :accountId ' +
    'ORDER BY AXF_FTX_DAT_PurchaseDate__c, Id';
  /** Control-row fields, named once so both access modes of loadRun select the same ones. */
  private static final String RUN_FIELDS =
    'Id, Name, AXF_EPR_LKP_Account__c, AXF_EPR_LKP_Requester__c, ' +
    'AXF_EPR_TXT_ContentDocument__c, AXF_EPR_PKL_Status__c, AXF_EPR_DT_ExpiresAt__c, ' +
    'AXF_EPR_TXT_FileName__c, AXF_EPR_TXT_ContentHash__c, AXF_EPR_TXT_Reason__c, ' +
    'AXF_EPR_NUM_Version__c';

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
      notifyRequester(run);
      log('PREPARED', run.Name);
      return toView(run);
    }
    // Locked exactly like download(), and for the same reason: two concurrent requests must not
    // each write an artifact for this run, because the loser's ContentVersion would be left with
    // no reference at all. The re-read under the lock is what the caller's version is compared
    // against (NFR-18): an unstated or stale expectation is refused before anything is written.
    run = lockAndLoad(existing, expectedVersion);
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
   * for every export after the first.
   *
   * The savepoint sits **after** the revocation the caller already performed, so a refusal that
   * has to undo a partial preparation (the row limit, a failed upload) cannot roll the revocation
   * back with it: an expired or revoked artifact stays revoked even when its replacement cannot be
   * built, which is what AC-2 asks for.
   */
  private RunView mint(AXF_OBJ_ExportRun__c run, Account holder) {
    Savepoint point = Database.setSavepoint();
    try {
      RunView view = toView(prepare(run, holder));
      notifyRequester(run);
      log('PREPARED', run.Name);
      return view;
    } catch (Exception refusal) {
      Database.rollback(point);
      throw refusal;
    }
  }

  /** Writes the artifact and its control row as one unit: neither survives without the other. */
  private AXF_OBJ_ExportRun__c prepare(
    AXF_OBJ_ExportRun__c run,
    Account holder
  ) {
    Id accountId = holder.Id;
    Integer rows = [
      SELECT COUNT()
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE AXF_FTX_LKP_Account__c = :accountId
      WITH USER_MODE
    ];
    if (rows > EXPORT_ROW_LIMIT) {
      // Refusing beats truncating invisibly (NFR-19); the run stays resumable, nothing is lost.
      throw failure('EXPORT_TOO_LARGE');
    }
    List<AXF_OBJ_FinancialTransaction__c> facts = Database.queryWithBinds(
      FACT_QUERY,
      new Map<String, Object>{ 'accountId' => accountId },
      AccessLevel.USER_MODE
    );
    String csv = csv(facts);
    Savepoint point = Database.setSavepoint();
    try {
      String fileName = FILE_NAME_PREFIX + run.Name + FILE_NAME_SUFFIX;
      run.AXF_EPR_TXT_FileName__c = fileName;
      run.AXF_EPR_TXT_ContentHash__c = sha256(csv);
      run.AXF_EPR_TXT_ContentDocument__c = store(fileName, csv);
      run.AXF_EPR_DT_ExpiresAt__c = Datetime.now()
        .addMinutes(DOWNLOAD_WINDOW_MINUTES);
      run.AXF_EPR_PKL_Status__c = STATUS_PREPARED;
      run.AXF_EPR_TXT_Reason__c = null;
      checkpoint(run);
    } catch (Exception failure) {
      Database.rollback(point);
      throw failure;
    }
    return run;
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

  // ---------------------------------------------------------------- csv

  /** Header plus one always-quoted line per fact, in a deterministic order. */
  private static String csv(List<AXF_OBJ_FinancialTransaction__c> facts) {
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
