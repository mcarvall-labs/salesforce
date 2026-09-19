/**
 * @description AXF-118 — resumable Batch Apex for an authorized export run whose total row count
 * (FinancialTransaction + BankAccountTransaction + CreditCardTransaction) is above
 * `ALT_CLS_ExportService.EXPORT_ROW_LIMIT`. Replaces the old EXPORT_TOO_LARGE block: the run moves
 * to RUNNING when this job is enqueued, each chunk's rows are appended to the artifact and the
 * cursor is advanced together in one unit (`ALT_CLS_ExportService.batchAppendChunk`), and a chunk
 * failure moves the run to PARTIAL without losing the cursor or duplicating rows already written —
 * a later `request()` resumes it. `finish()` finalizes the artifact (hash, expiry, PREPARED) once
 * every source has been fully drained.
 *
 * The three fact sources are read strictly in FTX -> BAT -> CCT order via a custom
 * `Iterable<SObject>` (Database.QueryLocator only supports one object type): each source is paged
 * by keyset (`Id > lastId ORDER BY Id`), never by SOQL OFFSET, which is capped at 2000 rows and
 * cannot page an export of arbitrary size.
 *
 * Two known limitations, not addressed by this class: (1) `batchAppendChunk` rewrites the full
 * artifact as a new ContentVersion on every chunk and never deletes superseded intermediate
 * versions once the run reaches PREPARED. (2) A RUNNING run whose batch job dies without reaching
 * `execute()`'s catch or `finish()` has no recovery path — `AXF_EPR_DT_Watermark__c` is written
 * but never read back to detect a stalled run, and `request()` on a RUNNING run only reports
 * status, never re-enqueues.
 */
public without sharing class ALT_CLS_ExportRunBatch implements Database.Batchable<SObject>, Database.Stateful {
  private final Id runId;
  private Boolean failed = false;

  public ALT_CLS_ExportRunBatch(Id runId) {
    this.runId = runId;
  }

  public Iterable<SObject> start(Database.BatchableContext context) {
    return new SourceIterable(runId);
  }

  public void execute(Database.BatchableContext context, List<SObject> scope) {
    if (failed) {
      return;
    }
    try {
      ALT_CLS_ExportService.batchAppendChunk(runId, scope);
    } catch (Exception chunkFailure) {
      failed = true;
      ALT_CLS_ExportService.batchFail(
        runId,
        reason('CHUNK_FAILED', chunkFailure)
      );
      if (context != null) {
        // No further chunk is useful once the checkpoint stopped moving.
        System.abortJob(context.getJobId());
      }
    }
  }

  public void finish(Database.BatchableContext context) {
    if (failed) {
      return;
    }
    try {
      ALT_CLS_ExportService.batchFinish(runId);
    } catch (Exception finishFailure) {
      ALT_CLS_ExportService.batchFail(
        runId,
        reason('FINISH_FAILED', finishFailure)
      );
    }
  }

  /** AXF_EPR_TXT_Reason__c is Text(80); a reason longer than that is truncated to fit. */
  private static final Integer REASON_FIELD_LENGTH = 80;

  /**
   * Typed service codes are kept verbatim; platform failures contribute their type and message,
   * truncated to fit the field. The message is the only persisted trace of why a run went
   * PARTIAL — without it, different root causes of the same exception type are indistinguishable
   * in the stored reason.
   */
  private static String reason(String prefix, Exception failure) {
    String base = prefix + ':' + failure.getTypeName();
    String message = failure.getMessage();
    String full = String.isBlank(message) ? base : base + ':' + message;
    return full.length() > REASON_FIELD_LENGTH
      ? full.substring(0, REASON_FIELD_LENGTH)
      : full;
  }

  // ---------------------------------------------------------------- three-source iterator

  /** Wraps the resumable iterator so `start()` can return it as an `Iterable<SObject>`. */
  private class SourceIterable implements Iterable<SObject> {
    private final Id runId;
    SourceIterable(Id runId) {
      this.runId = runId;
    }
    public Iterator<SObject> iterator() {
      return new SourceIterator(runId);
    }
  }

  /**
   * Drains FinancialTransaction, then BankAccountTransaction, then CreditCardTransaction, each by
   * keyset pagination resumed from the run's persisted cursor. One instance is held by the batch
   * framework for the whole job, so its state (current source, buffer) survives across the many
   * execute() scopes a single job builds.
   */
  private class SourceIterator implements Iterator<SObject> {
    // Apex forbids static members on inner types, so these are instance-final instead.
    private final Integer pageSize = 400;
    private final List<String> sources = new List<String>{
      'FTX',
      'BAT',
      'CCT'
    };
    private final Id runId;
    private Id accountId;
    private Map<String, String> lastIdBySource;
    private Integer sourceIndex = 0;
    private List<SObject> buffer = new List<SObject>();
    private Integer bufferPos = 0;
    private Boolean initialized = false;

    SourceIterator(Id runId) {
      this.runId = runId;
    }

    private void init() {
      if (initialized) {
        return;
      }
      ALT_CLS_ExportService.BatchCursor cursor = ALT_CLS_ExportService.batchCursor(
        runId
      );
      accountId = cursor.accountId;
      lastIdBySource = cursor.lastIdBySource;
      initialized = true;
    }

    public Boolean hasNext() {
      init();
      if (bufferPos < buffer.size()) {
        return true;
      }
      refill();
      return bufferPos < buffer.size();
    }

    public SObject next() {
      init();
      if (bufferPos >= buffer.size()) {
        refill();
      }
      SObject record = buffer[bufferPos];
      bufferPos++;
      return record;
    }

    /**
     * Refills the buffer from the current source; advances past any source that is exhausted.
     * `lastIdBySource` is also advanced in memory to the last row of the page just read: this
     * iterator instance is reused by the platform across many next()/hasNext() calls (and the
     * page it just returned is not yet checkpointed to the run), so without this a source whose
     * page was fully drained would be re-queried from the same afterId and hand back the exact
     * same rows again — hasNext() would then never truthfully report exhaustion.
     */
    private void refill() {
      buffer = new List<SObject>();
      bufferPos = 0;
      while (sourceIndex < sources.size()) {
        String source = sources[sourceIndex];
        Id afterId = idFrom(lastIdBySource.get(source));
        List<SObject> page = queryPage(source, afterId);
        if (!page.isEmpty()) {
          buffer = page;
          lastIdBySource.put(source, String.valueOf(page[page.size() - 1].Id));
          return;
        }
        sourceIndex++;
      }
    }

    private List<SObject> queryPage(String source, Id afterId) {
      if (source == 'FTX') {
        return ALT_CLS_ExportService.queryFtxPage(accountId, afterId, pageSize);
      }
      if (source == 'BAT') {
        return ALT_CLS_ExportService.queryBatPage(accountId, afterId, pageSize);
      }
      return ALT_CLS_ExportService.queryCctPage(accountId, afterId, pageSize);
    }

    private Id idFrom(String value) {
      return String.isBlank(value) ? null : Id.valueOf(value);
    }
  }
}
