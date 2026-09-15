/**
 * @description AXF-118 authorized data export (the export slice of AXF-9). One holder scope is
 * exported to a private, short-lived artifact: authorization is verified when the request is
 * made and again on every download, and an expired or no-longer-authorized download is revoked
 * by deleting the artifact. File name, notification and log lines carry no PII: they use only
 * the run's opaque auto-number.
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
 */
public with sharing class ALT_CLS_ExportService {
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
   * same artifact come back. Once the window elapsed, or after a revocation, a fresh artifact
   * replaces the dead one on the same run.
   */
  public RunView request(Id accountId) {
    Account holder = authorizedHolder(accountId);
    String key = scopeKey(accountId, UserInfo.getUserId());
    Id existing = findByScopeKey(key);
    AXF_OBJ_ExportRun__c run;
    if (existing == null) {
      Savepoint point = Database.setSavepoint();
      try {
        // Reloaded after the insert: the auto-number, which names the file, is only readable
        // from a query, and the artifact must never be named from an unpopulated field.
        run = prepare(loadRun(insertRun(holder, key).Id), holder);
      } catch (DmlException race) {
        Database.rollback(point);
        if (race.getDmlType(0) != StatusCode.DUPLICATE_VALUE) {
          throw race;
        }
        Id winner = findByScopeKey(key);
        if (winner == null) {
          throw race;
        }
        // A concurrent request won the scope key: its own transaction owns the artifact.
        return toView(loadRun(winner));
      } catch (Exception failure) {
        Database.rollback(point);
        throw failure;
      }
      grantRequesterAccess(run.Id, holder.OwnerId);
      notifyRequester(run);
      log('PREPARED', run.Name);
      return toView(run);
    }
    run = loadRun(existing);
    if (run.AXF_EPR_PKL_Status__c == STATUS_REVOKED) {
      return toView(prepare(run, holder));
    }
    if (isElapsed(run)) {
      revoke(run, REASON_EXPIRED);
      // revoke() cleared the artifact fields in place, so prepare() writes a fresh one.
      return toView(prepare(run, holder));
    }
    return toView(run);
  }

  /** Observes the run; never mints and never revokes. canDownload reports real availability. */
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
   */
  public DownloadView download(Id runId) {
    if (runId == null) {
      throw failure('INVALID_INPUT');
    }
    requireCapability();
    AXF_OBJ_ExportRun__c run = lockAndLoad(runId);
    if (run.AXF_EPR_LKP_Requester__c != UserInfo.getUserId()) {
      // The artifact is bound to its exact requester; another operator is not the requester.
      throw failure('FORBIDDEN');
    }
    if (!hasHolderReadAccess(run.AXF_EPR_LKP_Account__c)) {
      revoke(run, REASON_ACCESS_REVOKED);
      return refused(run.AXF_EPR_TXT_Reason__c);
    }
    if (run.AXF_EPR_PKL_Status__c == STATUS_REVOKED) {
      return refused('REVOKED');
    }
    if (
      run.AXF_EPR_PKL_Status__c != STATUS_PREPARED &&
      run.AXF_EPR_PKL_Status__c != STATUS_DOWNLOADED
    ) {
      return refused('NOT_PREPARED');
    }
    if (isElapsed(run)) {
      revoke(run, REASON_EXPIRED);
      return refused(run.AXF_EPR_TXT_Reason__c);
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

  // ---------------------------------------------------------------- preparation

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
   * Private artifact. The document gets NO ContentDocumentLink on purpose: the platform rejects
   * the least-exposure visibility (SharedUsers) for a record link, leaving only org-wide
   * visibility, and the ratified evidence pattern forbids a navigable link to a sensitive
   * artifact ("nunca cria ContentDocumentLink navegavel", SCHEMA-DICTIONARY.md). With no link
   * the only read path is this service, which revalidates authorization on every download;
   * revocation then deletes the document itself.
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
    Id documentId = run.AXF_EPR_TXT_ContentDocument__c;
    if (documentId == null) {
      revoke(run, REASON_MISSING);
      return null;
    }
    List<ContentVersion> versions = [
      SELECT VersionData
      FROM ContentVersion
      WHERE ContentDocumentId = :documentId AND IsLatest = TRUE
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
   * Kills the artifact of a run: the document is deleted, so the only copy this application
   * controls stops existing and no link survives. A download already delivered cannot be
   * recalled, which AD-21 declares as an accepted limit rather than a promise.
   */
  private void revoke(AXF_OBJ_ExportRun__c run, String reason) {
    Savepoint point = Database.setSavepoint();
    try {
      if (run.AXF_EPR_TXT_ContentDocument__c != null) {
        // No business user is granted Delete on Files: the service removes its own artifact,
        // the same isolated policy-governed effect the closure orchestrator performs.
        removeArtifact(run.AXF_EPR_TXT_ContentDocument__c);
      }
      run.AXF_EPR_TXT_ContentDocument__c = null;
      run.AXF_EPR_TXT_FileName__c = null;
      run.AXF_EPR_TXT_ContentHash__c = null;
      run.AXF_EPR_DT_ExpiresAt__c = null;
      run.AXF_EPR_PKL_Status__c = STATUS_REVOKED;
      run.AXF_EPR_TXT_Reason__c = reason;
      checkpoint(run);
    } catch (Exception failure) {
      Database.rollback(point);
      throw failure;
    }
    log('REVOKED_' + reason, run.Name);
  }

  /**
   * Deletes the artifact. A document that an administrator or a Files policy already removed
   * satisfies the goal state, so that one error is accepted; any other failure refuses the
   * revocation rather than recording REVOKED while the artifact lives on.
   */
  private static void removeArtifact(Id documentId) {
    Database.DeleteResult removed = Database.delete(
      new ContentDocument(Id = documentId),
      false
    );
    if (removed.isSuccess()) {
      return;
    }
    for (Database.Error problem : removed.getErrors()) {
      if (problem.getStatusCode() != StatusCode.ENTITY_IS_DELETED) {
        throw failure('ARTIFACT_NOT_REMOVED');
      }
    }
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
    if (!FeatureManagement.checkPermission(CP_EXPORT)) {
      throw failure('FORBIDDEN');
    }
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
   * Effective access to the scope, read from the platform. Re-evaluated on the download, so a
   * withdrawn share revokes the artifact instead of leaving it reachable.
   */
  private Boolean hasHolderReadAccess(Id accountId) {
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
    Database.insert(run, AccessLevel.USER_MODE);
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

  private AXF_OBJ_ExportRun__c loadRun(Id runId) {
    List<AXF_OBJ_ExportRun__c> rows = [
      SELECT
        Id,
        Name,
        AXF_EPR_LKP_Account__c,
        AXF_EPR_LKP_Requester__c,
        AXF_EPR_TXT_ContentDocument__c,
        AXF_EPR_PKL_Status__c,
        AXF_EPR_DT_ExpiresAt__c,
        AXF_EPR_TXT_FileName__c,
        AXF_EPR_TXT_ContentHash__c,
        AXF_EPR_TXT_Reason__c,
        AXF_EPR_NUM_Version__c
      FROM AXF_OBJ_ExportRun__c
      WHERE Id = :runId
      WITH USER_MODE
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      throw failure('NOT_ACCESSIBLE');
    }
    return rows[0];
  }

  /** Sharing is what makes the run visible; the lock serializes concurrent downloads (NFR-18). */
  private AXF_OBJ_ExportRun__c lockAndLoad(Id runId) {
    AXF_OBJ_ExportRun__c run = loadRun(runId);
    List<AXF_OBJ_ExportRun__c> locked = [
      SELECT Id, AXF_EPR_NUM_Version__c
      FROM AXF_OBJ_ExportRun__c
      WHERE Id = :runId
      FOR UPDATE
    ];
    run.AXF_EPR_NUM_Version__c = locked[0].AXF_EPR_NUM_Version__c;
    return run;
  }

  private static void checkpoint(AXF_OBJ_ExportRun__c run) {
    run.AXF_EPR_NUM_Version__c = run.AXF_EPR_NUM_Version__c == null
      ? 1
      : run.AXF_EPR_NUM_Version__c + 1;
    Database.update(run, AccessLevel.USER_MODE);
  }

  /** The run follows the holder's owner (G2); the requester keeps access via an explicit share. */
  @SuppressWarnings('PMD.ApexCRUDViolation')
  private static void grantRequesterAccess(Id runId, Id ownerId) {
    Id me = UserInfo.getUserId();
    if (me == ownerId) {
      return;
    }
    Database.insert(
      new AXF_OBJ_ExportRun__Share(
        ParentId = runId,
        UserOrGroupId = me,
        AccessLevel = 'Edit',
        RowCause = Schema.AXF_OBJ_ExportRun__Share.RowCause.Manual
      ),
      false
    );
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
    view.evidenceRef = run.AXF_EPR_TXT_ContentDocument__c == null
      ? null
      : String.valueOf(run.AXF_EPR_TXT_ContentDocument__c);
    view.version = run.AXF_EPR_NUM_Version__c;
    Boolean live =
      run.AXF_EPR_LKP_Requester__c == UserInfo.getUserId() &&
      (run.AXF_EPR_PKL_Status__c == STATUS_PREPARED ||
      run.AXF_EPR_PKL_Status__c == STATUS_DOWNLOADED) &&
      !isElapsed(run);
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
