/**
 * @description AXF-95 — bounded Batch Apex that archives one run chunk by chunk. Each chunk is
 * written to the Big Object before the checkpoint moves; a failure marks the run FAILED with a
 * safe reason and stops, and a later start() resumes from the watermark. finish() verifies the
 * archive against the hot copy and closes the run as HOT_RETAINED (no hot removal here).
 */
public with sharing class AXF_CLS_ArchiveRunBatch implements Database.Batchable<SObject>, Database.Stateful {
  private final Id runId;
  private Boolean failed = false;

  public AXF_CLS_ArchiveRunBatch(Id runId) {
    this.runId = runId;
  }

  public Database.QueryLocator start(Database.BatchableContext context) {
    try {
      return ALT_CLS_ArchiveRunService.locator(
        ALT_CLS_ArchiveRunService.read(runId)
      );
    } catch (Exception failure) {
      failed = true;
      record(reason('START_FAILED', failure));
      throw failure;
    }
  }

  public void execute(Database.BatchableContext context, List<SObject> scope) {
    if (failed) {
      return;
    }
    try {
      ALT_CLS_ArchiveRunService.archiveChunk(runId, scope);
    } catch (Exception failure) {
      failed = true;
      record(reason('CHUNK_FAILED', failure));
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
      ALT_CLS_ArchiveRunService.verify(runId);
    } catch (Exception failure) {
      record(reason('VERIFY_FAILED', failure));
    }
  }

  /** Recording the failure must never itself throw (row lock, trigger, visibility). */
  private void record(String reason) {
    try {
      ALT_CLS_ArchiveRunService.fail(runId, reason);
    } catch (Exception ignored) {
      System.debug(
        LoggingLevel.ERROR,
        'Archive run ' + runId + ' could not record: ' + reason
      );
    }
  }

  /** Typed service codes are kept verbatim; platform failures contribute only their type. */
  private static String reason(String prefix, Exception failure) {
    if (failure instanceof ALT_CLS_ArchiveRunService.ArchiveRunException) {
      return prefix +
        ':' +
        ((ALT_CLS_ArchiveRunService.ArchiveRunException) failure).code;
    }
    return prefix + ':' + failure.getTypeName();
  }
}
