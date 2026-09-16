/**
 * @description AXF-95 — idempotent, resumable archiving of one holder's facts (BAT/CCT/FTX)
 * that fall before the hot window. A run is identified by (family, holder, policy version,
 * hot-window start); its checkpoint (AXF_OBJ_ArchiveRun__c) records the watermark, counts,
 * per-currency amounts and a chained hash. Rows are upserted into the Big Object by their
 * deterministic ArchiveKey, so a restart from the watermark never duplicates. The hot copy is
 * never removed here: after verification the run ends as HOT_RETAINED with the removal gate
 * reported as BLOCKED (recovery/backup acceptance and explicit authorization are separate).
 */
public with sharing class ALT_CLS_ArchiveRunService {
  public static final String CP_ARCHIVE = 'AXF_CanArchiveTransactions';
  public static final Set<String> FAMILIES = new Set<String>{
    'BAT',
    'CCT',
    'FTX'
  };
  /** Rows re-read in finish(): its own transaction, well under the 50k SOQL row limit. */
  public static final Integer VERIFY_LIMIT = 10000;
  @TestVisible
  private static Integer verifyLimit = VERIFY_LIMIT;
  private static final Set<String> AXON_RECORD_TYPES = new Set<String>{
    ALT_CLS_AxonHolder.RT_PERSON,
    ALT_CLS_AxonHolder.RT_BUSINESS
  };

  @TestVisible
  private static Boolean writing = false;
  public static Boolean isWriting() {
    return writing;
  }

  /** Test seam: batches only run at Test.stopTest(); tests may drive them synchronously. */
  @TestVisible
  private static Boolean enqueueBatches = true;

  public class ArchiveRunException extends Exception {
    public String code;
  }

  public class RunView {
    @AuraEnabled
    public Id runId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String family;
    @AuraEnabled
    public String phase;
    @AuraEnabled
    public String policyVersion;
    @AuraEnabled
    public Date hotWindowStart;
    @AuraEnabled
    public Date watermark;
    @AuraEnabled
    public Integer scanned;
    @AuraEnabled
    public Integer archived;
    @AuraEnabled
    public Integer verified;
    @AuraEnabled
    public String amountsByCurrency;
    @AuraEnabled
    public String hotRemoval;
    @AuraEnabled
    public String reason;
    @AuraEnabled
    public Datetime lastCheckpointAt;
    @AuraEnabled
    public Boolean resumed = false;
  }

  /** Per-currency totals of what a run archived (count, credit, debit). */
  public class CurrencyTotal {
    public Integer count = 0;
    public Decimal credit = 0;
    public Decimal debit = 0;
  }

  // ------------------------------------------------------------------ entry points

  /** Starts (or resumes) the run of one family for one holder and enqueues its batch. */
  public RunView start(Id accountId, String family) {
    if (
      accountId == null ||
      String.isBlank(family) ||
      !FAMILIES.contains(family)
    ) {
      throw failure('INVALID_INPUT');
    }
    if (!FeatureManagement.checkPermission(CP_ARCHIVE)) {
      throw failure('FORBIDDEN');
    }
    ALT_CLS_ArchivePolicy.Resolved policy;
    try {
      policy = ALT_CLS_ArchivePolicy.resolve();
    } catch (ALT_CLS_ArchivePolicy.PolicyException blocked) {
      throw failure(blocked.code);
    }
    requireFullAccess(accountId);
    String runKey = runKey(family, accountId, policy);
    AXF_OBJ_ArchiveRun__c run = existing(runKey);
    if (run == null && ALT_CLS_ArchiveRunIntegrity.exists(runKey)) {
      // Another archivist owns the checkpoint (OWD Private): resuming it needs that user or a share.
      throw failure('RUN_OWNED_BY_OTHER');
    }
    if (
      (run != null &&
      ALT_CLS_ArchiveRunIntegrity.isJobActive(run.AXF_ARR_TXT_JobId__c)) ||
      ALT_CLS_ArchiveRunIntegrity.anotherRunActive(family, accountId, runKey)
    ) {
      // Same checkpoint still executing, or a sibling run (e.g. previous month's window).
      throw failure('RUN_IN_PROGRESS');
    }
    Boolean resumed = run != null;
    Savepoint point = Database.setSavepoint();
    try {
      writing = true;
      if (run == null) {
        run = new AXF_OBJ_ArchiveRun__c(
          AXF_ARR_EXI_RunKey__c = runKey,
          AXF_ARR_PKL_SourceFamily__c = family,
          AXF_ARR_LKP_Account__c = accountId,
          AXF_ARR_PKL_Phase__c = 'SCANNING',
          AXF_ARR_TXT_PolicyVersion__c = policy.version,
          AXF_ARR_DAT_HotWindowStart__c = policy.hotWindowStart,
          AXF_ARR_NUM_ScannedCount__c = 0,
          AXF_ARR_NUM_ArchivedCount__c = 0,
          AXF_ARR_NUM_VerifiedCount__c = 0,
          AXF_ARR_LTX_AmountsByCurrency__c = '{}',
          AXF_ARR_NUM_Version__c = 0
        );
        Database.insert(run, AccessLevel.USER_MODE);
      } else {
        if (
          run.AXF_ARR_PKL_Phase__c == 'HOT_RETAINED' ||
          run.AXF_ARR_PKL_Phase__c == 'COMPLETED' ||
          String.valueOf(run.AXF_ARR_TXT_Reason__c)
            .startsWith('PARITY_MISMATCH')
        ) {
          // Re-scan the whole window (a parity failure may sit before the watermark): upserts
          // by ArchiveKey make this safe.
          run.AXF_ARR_DAT_Watermark__c = null;
          run.AXF_ARR_NUM_ScannedCount__c = 0;
          run.AXF_ARR_NUM_ArchivedCount__c = 0;
          run.AXF_ARR_NUM_VerifiedCount__c = 0;
          run.AXF_ARR_LTX_AmountsByCurrency__c = '{}';
          run.AXF_ARR_TXT_ContentHash__c = null;
        }
        run.AXF_ARR_PKL_Phase__c = 'SCANNING';
        run.AXF_ARR_TXT_Reason__c = null;
        run.AXF_ARR_NUM_Version__c = nz(run.AXF_ARR_NUM_Version__c) + 1;
        Database.update(run, AccessLevel.USER_MODE);
      }
    } catch (DmlException dml) {
      Database.rollback(point);
      if (dml.getDmlType(0) == StatusCode.DUPLICATE_VALUE) {
        throw failure('RUN_IN_PROGRESS');
      }
      throw dml;
    } finally {
      writing = false;
    }
    if (enqueueBatches) {
      Id jobId;
      try {
        jobId = Database.executeBatch(
          new AXF_CLS_ArchiveRunBatch(run.Id),
          policy.batchSize
        );
      } catch (AsyncException unavailable) {
        fail(read(run.Id), 'ENQUEUE_FAILED');
        throw failure('ASYNC_UNAVAILABLE');
      }
      run = read(run.Id);
      run.AXF_ARR_TXT_JobId__c = jobId;
      checkpoint(run);
    }
    RunView view = toView(read(run.Id));
    view.resumed = resumed;
    return view;
  }

  public List<RunView> listRuns(Id accountId) {
    if (accountId == null) {
      throw failure('INVALID_INPUT');
    }
    if (
      !FeatureManagement.checkPermission(CP_ARCHIVE) &&
      !FeatureManagement.checkPermission(ALT_CLS_ArchiveReadService.CP_READ)
    ) {
      throw failure('FORBIDDEN');
    }
    List<RunView> result = new List<RunView>();
    for (AXF_OBJ_ArchiveRun__c run : [
      SELECT
        Id,
        Name,
        AXF_ARR_PKL_SourceFamily__c,
        AXF_ARR_PKL_Phase__c,
        AXF_ARR_TXT_PolicyVersion__c,
        AXF_ARR_DAT_HotWindowStart__c,
        AXF_ARR_DAT_Watermark__c,
        AXF_ARR_NUM_ScannedCount__c,
        AXF_ARR_NUM_ArchivedCount__c,
        AXF_ARR_NUM_VerifiedCount__c,
        AXF_ARR_LTX_AmountsByCurrency__c,
        AXF_ARR_TXT_HotRemoval__c,
        AXF_ARR_TXT_Reason__c,
        AXF_ARR_DTM_LastCheckpointAt__c
      FROM AXF_OBJ_ArchiveRun__c
      WHERE AXF_ARR_LKP_Account__c = :accountId
      WITH USER_MODE
      ORDER BY LastModifiedDate DESC
      LIMIT 50
    ]) {
      result.add(toView(run));
    }
    return result;
  }

  // ------------------------------------------------------------------ batch collaborators

  /** Hot rows of one run in checkpoint order: date, then deterministic key. */
  public static Database.QueryLocator locator(AXF_OBJ_ArchiveRun__c run) {
    String family = run.AXF_ARR_PKL_SourceFamily__c;
    Id accountId = run.AXF_ARR_LKP_Account__c;
    Date limitDate = run.AXF_ARR_DAT_HotWindowStart__c;
    Date watermark = run.AXF_ARR_DAT_Watermark__c;
    if (family == 'BAT') {
      return Database.getQueryLocatorWithBinds(
        'SELECT Id, AXF_BAT_EXI_SourceKey__c, AXF_BAT_DAT_Date__c, AXF_BAT_NUM_Magnitude__c, ' +
          'AXF_BAT_PKL_Direction__c, AXF_BAT_TXT_CurrencyIsoCode__c, AXF_BAT_PKL_Status__c, ' +
          'AXF_BAT_TXT_Description__c, AXF_BAT_MDR_BankAccount__c, ' +
          'AXF_BAT_MDR_BankAccount__r.AXF_BA_LKP_Account__c, ' +
          'AXF_BAT_MDR_BankAccount__r.AXF_BA_LKP_BankInstitution__c, ' +
          'AXF_BAT_MDR_BankAccount__r.AXF_BA_TXT_InstitutionName__c ' +
          'FROM AXF_OBJ_BankAccountTransaction__c ' +
          'WHERE AXF_BAT_MDR_BankAccount__r.AXF_BA_LKP_Account__c = :accountId ' +
          'AND AXF_BAT_DAT_Date__c < :limitDate ' +
          (watermark == null ? '' : 'AND AXF_BAT_DAT_Date__c >= :watermark ') +
          'ORDER BY AXF_BAT_DAT_Date__c, AXF_BAT_EXI_SourceKey__c',
        new Map<String, Object>{
          'accountId' => accountId,
          'limitDate' => limitDate,
          'watermark' => watermark
        },
        AccessLevel.USER_MODE
      );
    }
    if (family == 'CCT') {
      return Database.getQueryLocatorWithBinds(
        'SELECT Id, AXF_CCT_EXI_SourceKey__c, AXF_CCT_DAT_Date__c, AXF_CCT_NUM_Magnitude__c, ' +
          'AXF_CCT_PKL_Direction__c, AXF_CCT_TXT_CurrencyIsoCode__c, AXF_CCT_PKL_Status__c, ' +
          'AXF_CCT_TXT_Description__c, AXF_CCT_MDR_CreditCard__c, ' +
          'AXF_CCT_MDR_CreditCard__r.AXF_CC_LKP_Account__c, ' +
          'AXF_CCT_MDR_CreditCard__r.AXF_CC_LKP_BankInstitution__c, ' +
          'AXF_CCT_MDR_CreditCard__r.AXF_CC_TXT_InstitutionName__c ' +
          'FROM AXF_OBJ_CreditCardTransaction__c ' +
          'WHERE AXF_CCT_MDR_CreditCard__r.AXF_CC_LKP_Account__c = :accountId ' +
          'AND AXF_CCT_DAT_Date__c < :limitDate ' +
          (watermark == null ? '' : 'AND AXF_CCT_DAT_Date__c >= :watermark ') +
          'ORDER BY AXF_CCT_DAT_Date__c, AXF_CCT_EXI_SourceKey__c',
        new Map<String, Object>{
          'accountId' => accountId,
          'limitDate' => limitDate,
          'watermark' => watermark
        },
        AccessLevel.USER_MODE
      );
    }
    return Database.getQueryLocatorWithBinds(
      'SELECT Id, AXF_FTX_EXI_ClientRequestId__c, AXF_FTX_DAT_PurchaseDate__c, ' +
        'AXF_FTX_NUM_Magnitude__c, AXF_FTX_PKL_Direction__c, AXF_FTX_TXT_CurrencyIsoCode__c, ' +
        'AXF_FTX_PKL_Status__c, AXF_FTX_LKP_Account__c ' +
        'FROM AXF_OBJ_FinancialTransaction__c ' +
        'WHERE AXF_FTX_LKP_Account__c = :accountId ' +
        'AND AXF_FTX_DAT_PurchaseDate__c < :limitDate ' +
        (watermark == null
          ? ''
          : 'AND AXF_FTX_DAT_PurchaseDate__c >= :watermark ') +
        'ORDER BY AXF_FTX_DAT_PurchaseDate__c, AXF_FTX_EXI_ClientRequestId__c',
      new Map<String, Object>{
        'accountId' => accountId,
        'limitDate' => limitDate,
        'watermark' => watermark
      },
      AccessLevel.USER_MODE
    );
  }

  /** Archives one chunk and moves the checkpoint only after the rows are written. */
  public static void archiveChunk(Id runId, List<SObject> hot) {
    AXF_OBJ_ArchiveRun__c run = read(runId);
    if (run.AXF_ARR_PKL_Phase__c == 'FAILED') {
      return;
    }
    List<AXF_OBJ_TransactionArchive__b> rows = new List<AXF_OBJ_TransactionArchive__b>();
    Map<String, CurrencyTotal> totals = totals(run);
    List<String> keys = new List<String>();
    Date lastDate = run.AXF_ARR_DAT_Watermark__c;
    // Resume re-reads the whole watermark day: the upsert by ArchiveKey makes that harmless and
    // the counters below are progress only — verify() recomputes the authoritative numbers.
    for (SObject source : hot) {
      AXF_OBJ_TransactionArchive__b row = toArchiveRow(
        run.AXF_ARR_PKL_SourceFamily__c,
        source,
        run
      );
      Date day = ALT_CLS_ArchiveStore.bookingDay(row.AXF_ARC_DT_BookingDate__c);
      rows.add(row);
      keys.add(row.AXF_ARC_TXT_ArchiveKey__c);
      CurrencyTotal total = totals.get(row.AXF_ARC_TXT_CurrencyIsoCode__c);
      if (total == null) {
        total = new CurrencyTotal();
        totals.put(row.AXF_ARC_TXT_CurrencyIsoCode__c, total);
      }
      total.count++;
      if (row.AXF_ARC_TXT_Direction__c == 'CREDIT') {
        total.credit += nz(row.AXF_ARC_NUM_Magnitude__c);
      } else {
        total.debit += nz(row.AXF_ARC_NUM_Magnitude__c);
      }
      lastDate = day;
    }
    try {
      ALT_CLS_ArchiveStore.instance().write(rows);
    } catch (Exception writeFailure) {
      // The batch records the reason once and stops; the checkpoint is not moved.
      throw failure('ARCHIVE_WRITE_FAILED:' + writeFailure.getTypeName());
    }
    // Checkpoint after the write: an interruption between the two replays this chunk, and the
    // upsert-by-key makes the replay harmless.
    run.AXF_ARR_PKL_Phase__c = 'WRITING';
    run.AXF_ARR_NUM_ScannedCount__c =
      nz(run.AXF_ARR_NUM_ScannedCount__c) + hot.size();
    run.AXF_ARR_NUM_ArchivedCount__c =
      nz(run.AXF_ARR_NUM_ArchivedCount__c) + rows.size();
    run.AXF_ARR_DAT_Watermark__c = lastDate;
    run.AXF_ARR_LTX_AmountsByCurrency__c = JSON.serialize(totals);
    run.AXF_ARR_DTM_LastCheckpointAt__c = Datetime.now();
    checkpoint(run);
  }

  /** Re-reads the archive (bounded) and closes the run without touching the hot copy. */
  public static void verify(Id runId) {
    AXF_OBJ_ArchiveRun__c run = read(runId);
    if (run.AXF_ARR_PKL_Phase__c == 'FAILED') {
      return;
    }
    run.AXF_ARR_PKL_Phase__c = 'VERIFYING';
    checkpoint(run);
    String accountKey = String.valueOf(run.AXF_ARR_LKP_Account__c);
    Date toDate = run.AXF_ARR_DAT_HotWindowStart__c.addDays(-1);
    Date fromDate = Date.newInstance(1700, 1, 1);
    Integer verified = 0;
    Integer read = 0;
    Date cursorDate;
    String cursorKey;
    Boolean sampled = false;
    Map<String, CurrencyTotal> archiveTotals = new Map<String, CurrencyTotal>();
    List<String> verifiedKeys = new List<String>();
    Integer pageSize = Math.min(ALT_CLS_ArchiveStore.MAX_PAGE, verifyLimit);
    while (true) {
      List<AXF_OBJ_TransactionArchive__b> page = ALT_CLS_ArchiveReadService.page(
        accountKey,
        fromDate,
        toDate,
        cursorDate,
        cursorKey,
        pageSize
      );
      for (AXF_OBJ_TransactionArchive__b row : page) {
        read++;
        if (
          row.AXF_ARC_TXT_RunKey__c == run.AXF_ARR_EXI_RunKey__c &&
          row.AXF_ARC_TXT_SourceFamily__c == run.AXF_ARR_PKL_SourceFamily__c &&
          row.AXF_ARC_TXT_ContentHash__c == contentHash(row)
        ) {
          verified++;
          accumulate(archiveTotals, row);
          verifiedKeys.add(row.AXF_ARC_TXT_ArchiveKey__c);
        }
      }
      if (page.size() < pageSize) {
        break;
      }
      if (read >= verifyLimit) {
        sampled = true;
        break;
      }
      AXF_OBJ_TransactionArchive__b last = page[page.size() - 1];
      cursorDate = ALT_CLS_ArchiveStore.bookingDay(
        last.AXF_ARC_DT_BookingDate__c
      );
      cursorKey = last.AXF_ARC_TXT_ArchiveKey__c;
    }
    run.AXF_ARR_NUM_VerifiedCount__c = verified;
    if (!sampled) {
      // Parity: what the archive holds for this run equals what the hot copy holds in scope
      // (count and amounts per currency), independently recounted on both sides.
      Map<String, CurrencyTotal> hotTotals = hotTotals(run);
      String mismatch = mismatch(hotTotals, archiveTotals);
      if (mismatch != null) {
        fail(run, 'PARITY_MISMATCH:' + mismatch);
        return;
      }
      // Authoritative numbers replace the progress counters (resume/replay may have inflated them).
      Integer hotCount = 0;
      for (CurrencyTotal total : hotTotals.values()) {
        hotCount += total.count;
      }
      run.AXF_ARR_NUM_ScannedCount__c = hotCount;
      run.AXF_ARR_NUM_ArchivedCount__c = verified;
      run.AXF_ARR_LTX_AmountsByCurrency__c = JSON.serialize(archiveTotals);
    }
    // Reproducible run hash: the sorted set of verified archive keys, independent of chunking.
    verifiedKeys.sort();
    run.AXF_ARR_TXT_ContentHash__c = ALT_CLS_ArchiveStore.sha256(
      String.join(verifiedKeys, '|')
    );
    ALT_CLS_ArchivePolicy.Resolved policy;
    try {
      policy = ALT_CLS_ArchivePolicy.resolve();
    } catch (ALT_CLS_ArchivePolicy.PolicyException blocked) {
      fail(run, blocked.code);
      return;
    }
    run.AXF_ARR_PKL_Phase__c = 'HOT_RETAINED';
    run.AXF_ARR_TXT_Reason__c = sampled ? 'VERIFY_SAMPLED:' + read : null;
    // The verified redundant hot copy is only removed under the recovery/cutover gate; an
    // unverified (sampled) archive never qualifies.
    run.AXF_ARR_TXT_HotRemoval__c = sampled
      ? 'BLOCKED:VERIFY_SAMPLED'
      : (policy.allowHotRemoval
          ? 'BLOCKED:RECOVERY_GATE_OPEN'
          : 'BLOCKED:HOT_REMOVAL_NOT_AUTHORIZED');
    run.AXF_ARR_DTM_LastCheckpointAt__c = Datetime.now();
    checkpoint(run);
  }

  public static void fail(Id runId, String reason) {
    fail(read(runId), reason);
  }

  // ------------------------------------------------------------------ mapping

  /** Deterministic archive identity: family and source identity, never the record id. */
  public static String archiveKey(String family, String sourceKey) {
    return ALT_CLS_ArchiveStore.sha256(family + '|' + sourceKey);
  }

  public static AXF_OBJ_TransactionArchive__b toArchiveRow(
    String family,
    SObject source,
    AXF_OBJ_ArchiveRun__c run
  ) {
    AXF_OBJ_TransactionArchive__b row = new AXF_OBJ_TransactionArchive__b();
    String sourceKey;
    Date day;
    Id sourceId;
    Id institutionKey;
    String institutionLabel;
    if (family == 'BAT') {
      AXF_OBJ_BankAccountTransaction__c fact = (AXF_OBJ_BankAccountTransaction__c) source;
      sourceKey = fact.AXF_BAT_EXI_SourceKey__c;
      day = fact.AXF_BAT_DAT_Date__c;
      sourceId = fact.AXF_BAT_MDR_BankAccount__c;
      institutionKey = fact.AXF_BAT_MDR_BankAccount__r
        ?.AXF_BA_LKP_BankInstitution__c;
      institutionLabel = fact.AXF_BAT_MDR_BankAccount__r
        ?.AXF_BA_TXT_InstitutionName__c;
      row.AXF_ARC_NUM_Magnitude__c = fact.AXF_BAT_NUM_Magnitude__c;
      row.AXF_ARC_TXT_Direction__c = fact.AXF_BAT_PKL_Direction__c;
      row.AXF_ARC_TXT_CurrencyIsoCode__c = fact.AXF_BAT_TXT_CurrencyIsoCode__c;
      row.AXF_ARC_TXT_Status__c = fact.AXF_BAT_PKL_Status__c;
      row.AXF_ARC_TXT_Description__c = fact.AXF_BAT_TXT_Description__c;
    } else if (family == 'CCT') {
      AXF_OBJ_CreditCardTransaction__c fact = (AXF_OBJ_CreditCardTransaction__c) source;
      sourceKey = fact.AXF_CCT_EXI_SourceKey__c;
      day = fact.AXF_CCT_DAT_Date__c;
      sourceId = fact.AXF_CCT_MDR_CreditCard__c;
      institutionKey = fact.AXF_CCT_MDR_CreditCard__r
        ?.AXF_CC_LKP_BankInstitution__c;
      institutionLabel = fact.AXF_CCT_MDR_CreditCard__r
        ?.AXF_CC_TXT_InstitutionName__c;
      row.AXF_ARC_NUM_Magnitude__c = fact.AXF_CCT_NUM_Magnitude__c;
      row.AXF_ARC_TXT_Direction__c = fact.AXF_CCT_PKL_Direction__c;
      row.AXF_ARC_TXT_CurrencyIsoCode__c = fact.AXF_CCT_TXT_CurrencyIsoCode__c;
      row.AXF_ARC_TXT_Status__c = fact.AXF_CCT_PKL_Status__c;
      row.AXF_ARC_TXT_Description__c = fact.AXF_CCT_TXT_Description__c;
    } else {
      AXF_OBJ_FinancialTransaction__c fact = (AXF_OBJ_FinancialTransaction__c) source;
      sourceKey = String.isBlank(fact.AXF_FTX_EXI_ClientRequestId__c)
        ? String.valueOf(fact.Id)
        : fact.AXF_FTX_EXI_ClientRequestId__c;
      day = fact.AXF_FTX_DAT_PurchaseDate__c;
      sourceId = fact.AXF_FTX_LKP_Account__c;
      row.AXF_ARC_NUM_Magnitude__c = fact.AXF_FTX_NUM_Magnitude__c;
      row.AXF_ARC_TXT_Direction__c = fact.AXF_FTX_PKL_Direction__c;
      row.AXF_ARC_TXT_CurrencyIsoCode__c = fact.AXF_FTX_TXT_CurrencyIsoCode__c;
      row.AXF_ARC_TXT_Status__c = fact.AXF_FTX_PKL_Status__c;
    }
    if (String.isBlank(sourceKey)) {
      sourceKey = String.valueOf(source.Id);
    }
    row.AXF_ARC_TXT_AccountKey__c = String.valueOf(run.AXF_ARR_LKP_Account__c);
    row.AXF_ARC_DT_BookingDate__c = ALT_CLS_ArchiveStore.bookingKey(day);
    row.AXF_ARC_TXT_ArchiveKey__c = archiveKey(family, sourceKey);
    row.AXF_ARC_TXT_SourceFamily__c = family;
    row.AXF_ARC_TXT_SourceKey__c = sourceKey.left(255);
    row.AXF_ARC_TXT_SourceRecordId__c = String.valueOf(source.Id);
    row.AXF_ARC_TXT_SourceId__c = sourceId == null
      ? null
      : String.valueOf(sourceId);
    row.AXF_ARC_TXT_InstitutionKey__c = institutionKey == null
      ? null
      : String.valueOf(institutionKey);
    row.AXF_ARC_TXT_InstitutionLabel__c = institutionLabel == null
      ? null
      : institutionLabel.left(120);
    row.AXF_ARC_TXT_Description__c = row.AXF_ARC_TXT_Description__c == null
      ? null
      : row.AXF_ARC_TXT_Description__c.left(255);
    row.AXF_ARC_TXT_PolicyVersion__c = run.AXF_ARR_TXT_PolicyVersion__c;
    row.AXF_ARC_TXT_RunKey__c = run.AXF_ARR_EXI_RunKey__c;
    row.AXF_ARC_TXT_ContentHash__c = contentHash(row);
    row.AXF_ARC_DT_ArchivedAt__c = Datetime.now();
    row.AXF_ARC_LTX_Snapshot__c = snapshot(source);
    return row;
  }

  /** The fact's own fields only (no parent objects); truncation is explicit, never silent. */
  public static String snapshot(SObject source) {
    Map<String, Object> own = new Map<String, Object>();
    for (String field : source.getPopulatedFieldsAsMap().keySet()) {
      if (!field.endsWith('__r')) {
        own.put(field, source.get(field));
      }
    }
    String json = JSON.serialize(own);
    return json.length() <= 32000
      ? json
      : json.left(32000 - 16) + '"...TRUNCATED"}';
  }

  /**
   * Scale- and timezone-independent: the hot field (scale 2) and the archive field (scale 8)
   * must hash identically, and the day is rendered in UTC regardless of the running user.
   */
  public static String contentHash(AXF_OBJ_TransactionArchive__b row) {
    return ALT_CLS_ArchiveStore.sha256(
      String.join(
        new List<String>{
          row.AXF_ARC_TXT_SourceFamily__c,
          row.AXF_ARC_TXT_SourceKey__c,
          row.AXF_ARC_DT_BookingDate__c == null
            ? ''
            : row.AXF_ARC_DT_BookingDate__c.formatGmt('yyyy-MM-dd'),
          row.AXF_ARC_NUM_Magnitude__c == null
            ? ''
            : row.AXF_ARC_NUM_Magnitude__c.setScale(8).toPlainString(),
          row.AXF_ARC_TXT_Direction__c,
          row.AXF_ARC_TXT_CurrencyIsoCode__c,
          row.AXF_ARC_TXT_Status__c
        },
        '|'
      )
    );
  }

  public static String runKey(
    String family,
    Id accountId,
    ALT_CLS_ArchivePolicy.Resolved policy
  ) {
    return ALT_CLS_ArchiveStore.sha256(
      family +
        '|' +
        accountId +
        '|' +
        policy.version +
        '|' +
        String.valueOf(policy.hotWindowStart)
    );
  }

  // ------------------------------------------------------------------ parity

  private static void accumulate(
    Map<String, CurrencyTotal> totals,
    AXF_OBJ_TransactionArchive__b row
  ) {
    CurrencyTotal total = totals.get(row.AXF_ARC_TXT_CurrencyIsoCode__c);
    if (total == null) {
      total = new CurrencyTotal();
      totals.put(row.AXF_ARC_TXT_CurrencyIsoCode__c, total);
    }
    total.count++;
    if (row.AXF_ARC_TXT_Direction__c == 'CREDIT') {
      total.credit += nz(row.AXF_ARC_NUM_Magnitude__c);
    } else {
      total.debit += nz(row.AXF_ARC_NUM_Magnitude__c);
    }
  }

  /** Independent recount of the hot copy in the run's scope (aggregate query, USER_MODE). */
  public static Map<String, CurrencyTotal> hotTotals(
    AXF_OBJ_ArchiveRun__c run
  ) {
    String family = run.AXF_ARR_PKL_SourceFamily__c;
    String prefix = family == 'BAT'
      ? 'AXF_BAT_'
      : (family == 'CCT' ? 'AXF_CCT_' : 'AXF_FTX_');
    String objectName = family == 'BAT'
      ? 'AXF_OBJ_BankAccountTransaction__c'
      : (family == 'CCT'
          ? 'AXF_OBJ_CreditCardTransaction__c'
          : 'AXF_OBJ_FinancialTransaction__c');
    String dateField = family == 'FTX'
      ? 'AXF_FTX_DAT_PurchaseDate__c'
      : prefix + 'DAT_Date__c';
    String scopeField = family == 'BAT'
      ? 'AXF_BAT_MDR_BankAccount__r.AXF_BA_LKP_Account__c'
      : (family == 'CCT'
          ? 'AXF_CCT_MDR_CreditCard__r.AXF_CC_LKP_Account__c'
          : 'AXF_FTX_LKP_Account__c');
    Map<String, CurrencyTotal> result = new Map<String, CurrencyTotal>();
    Id accountId = run.AXF_ARR_LKP_Account__c;
    Date limitDate = run.AXF_ARR_DAT_HotWindowStart__c;
    for (
      SObject aggregate : Database.queryWithBinds(
        'SELECT ' +
          prefix +
          'TXT_CurrencyIsoCode__c ccy, ' +
          prefix +
          'PKL_Direction__c dir, COUNT(Id) n, SUM(' +
          prefix +
          'NUM_Magnitude__c) total FROM ' +
          objectName +
          ' WHERE ' +
          scopeField +
          ' = :accountId AND ' +
          dateField +
          ' < :limitDate GROUP BY ' +
          prefix +
          'TXT_CurrencyIsoCode__c, ' +
          prefix +
          'PKL_Direction__c',
        new Map<String, Object>{
          'accountId' => accountId,
          'limitDate' => limitDate
        },
        AccessLevel.USER_MODE
      )
    ) {
      AggregateResult row = (AggregateResult) aggregate;
      String currencyIso = (String) row.get('ccy');
      CurrencyTotal total = result.get(currencyIso);
      if (total == null) {
        total = new CurrencyTotal();
        result.put(currencyIso, total);
      }
      total.count += (Integer) row.get('n');
      if ((String) row.get('dir') == 'CREDIT') {
        total.credit += nz((Decimal) row.get('total'));
      } else {
        total.debit += nz((Decimal) row.get('total'));
      }
    }
    return result;
  }

  /** First differing currency as "CCY:count/credit/debit vs count/credit/debit", or null. */
  public static String mismatch(
    Map<String, CurrencyTotal> hot,
    Map<String, CurrencyTotal> archive
  ) {
    Set<String> currencies = new Set<String>(hot.keySet());
    currencies.addAll(archive.keySet());
    List<String> ordered = new List<String>(currencies);
    ordered.sort();
    for (String currencyIso : ordered) {
      CurrencyTotal h = hot.containsKey(currencyIso)
        ? hot.get(currencyIso)
        : new CurrencyTotal();
      CurrencyTotal a = archive.containsKey(currencyIso)
        ? archive.get(currencyIso)
        : new CurrencyTotal();
      if (
        h.count != a.count ||
        h.credit.setScale(8) != a.credit.setScale(8) ||
        h.debit.setScale(8) != a.debit.setScale(8)
      ) {
        return currencyIso +
          ':' +
          h.count +
          '/' +
          h.credit +
          '/' +
          h.debit +
          ' vs ' +
          a.count +
          '/' +
          a.credit +
          '/' +
          a.debit;
      }
    }
    return null;
  }

  // ------------------------------------------------------------------ helpers

  private static void requireFullAccess(Id accountId) {
    List<Account> rows = [
      SELECT Id
      FROM Account
      WHERE Id = :accountId AND RecordType.DeveloperName IN :AXON_RECORD_TYPES
      WITH USER_MODE
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      throw failure('NOT_ACCESSIBLE');
    }
    Id me = UserInfo.getUserId();
    for (UserRecordAccess access : [
      SELECT RecordId, HasAllAccess
      FROM UserRecordAccess
      WHERE UserId = :me AND RecordId = :accountId
    ]) {
      if (access.HasAllAccess != true) {
        // Archiving moves a holder's whole history; partial sharing is not enough.
        throw failure('FORBIDDEN');
      }
    }
  }

  private static AXF_OBJ_ArchiveRun__c existing(String runKey) {
    List<AXF_OBJ_ArchiveRun__c> rows = [
      SELECT
        Id,
        AXF_ARR_EXI_RunKey__c,
        AXF_ARR_PKL_SourceFamily__c,
        AXF_ARR_LKP_Account__c,
        AXF_ARR_PKL_Phase__c,
        AXF_ARR_TXT_PolicyVersion__c,
        AXF_ARR_DAT_HotWindowStart__c,
        AXF_ARR_DAT_Watermark__c,
        AXF_ARR_NUM_ScannedCount__c,
        AXF_ARR_NUM_ArchivedCount__c,
        AXF_ARR_NUM_VerifiedCount__c,
        AXF_ARR_LTX_AmountsByCurrency__c,
        AXF_ARR_TXT_ContentHash__c,
        AXF_ARR_TXT_HotRemoval__c,
        AXF_ARR_TXT_Reason__c,
        AXF_ARR_TXT_JobId__c,
        AXF_ARR_NUM_Version__c
      FROM AXF_OBJ_ArchiveRun__c
      WHERE AXF_ARR_EXI_RunKey__c = :runKey
      WITH USER_MODE
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0];
  }

  public static AXF_OBJ_ArchiveRun__c read(Id runId) {
    List<AXF_OBJ_ArchiveRun__c> rows = [
      SELECT
        Id,
        Name,
        AXF_ARR_EXI_RunKey__c,
        AXF_ARR_PKL_SourceFamily__c,
        AXF_ARR_LKP_Account__c,
        AXF_ARR_PKL_Phase__c,
        AXF_ARR_TXT_PolicyVersion__c,
        AXF_ARR_DAT_HotWindowStart__c,
        AXF_ARR_DAT_Watermark__c,
        AXF_ARR_NUM_ScannedCount__c,
        AXF_ARR_NUM_ArchivedCount__c,
        AXF_ARR_NUM_VerifiedCount__c,
        AXF_ARR_LTX_AmountsByCurrency__c,
        AXF_ARR_TXT_ContentHash__c,
        AXF_ARR_TXT_HotRemoval__c,
        AXF_ARR_TXT_Reason__c,
        AXF_ARR_DTM_LastCheckpointAt__c,
        AXF_ARR_TXT_JobId__c,
        AXF_ARR_NUM_Version__c
      FROM AXF_OBJ_ArchiveRun__c
      WHERE Id = :runId
      WITH USER_MODE
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      throw failure('RUN_NOT_ACCESSIBLE');
    }
    return rows[0];
  }

  private static void fail(AXF_OBJ_ArchiveRun__c run, String reason) {
    run.AXF_ARR_PKL_Phase__c = 'FAILED';
    run.AXF_ARR_TXT_Reason__c = reason.left(255);
    run.AXF_ARR_TXT_HotRemoval__c = null;
    run.AXF_ARR_DTM_LastCheckpointAt__c = Datetime.now();
    checkpoint(run);
  }

  private static void checkpoint(AXF_OBJ_ArchiveRun__c run) {
    run.AXF_ARR_NUM_Version__c = nz(run.AXF_ARR_NUM_Version__c) + 1;
    try {
      writing = true;
      Database.update(run, AccessLevel.USER_MODE);
    } finally {
      writing = false;
    }
  }

  private static Map<String, CurrencyTotal> totals(AXF_OBJ_ArchiveRun__c run) {
    if (String.isBlank(run.AXF_ARR_LTX_AmountsByCurrency__c)) {
      return new Map<String, CurrencyTotal>();
    }
    return (Map<String, CurrencyTotal>) JSON.deserialize(
      run.AXF_ARR_LTX_AmountsByCurrency__c,
      Map<String, CurrencyTotal>.class
    );
  }

  private static RunView toView(AXF_OBJ_ArchiveRun__c run) {
    RunView view = new RunView();
    view.runId = run.Id;
    view.name = run.Name;
    view.family = run.AXF_ARR_PKL_SourceFamily__c;
    view.phase = run.AXF_ARR_PKL_Phase__c;
    view.policyVersion = run.AXF_ARR_TXT_PolicyVersion__c;
    view.hotWindowStart = run.AXF_ARR_DAT_HotWindowStart__c;
    view.watermark = run.AXF_ARR_DAT_Watermark__c;
    view.scanned = nz(run.AXF_ARR_NUM_ScannedCount__c).intValue();
    view.archived = nz(run.AXF_ARR_NUM_ArchivedCount__c).intValue();
    view.verified = nz(run.AXF_ARR_NUM_VerifiedCount__c).intValue();
    view.amountsByCurrency = run.AXF_ARR_LTX_AmountsByCurrency__c;
    view.hotRemoval = run.AXF_ARR_TXT_HotRemoval__c;
    view.reason = run.AXF_ARR_TXT_Reason__c;
    view.lastCheckpointAt = run.AXF_ARR_DTM_LastCheckpointAt__c;
    return view;
  }

  private static Decimal nz(Decimal value) {
    return value == null ? 0 : value;
  }

  private static ArchiveRunException failure(String code) {
    ArchiveRunException result = new ArchiveRunException(code);
    result.code = code;
    return result;
  }
}
