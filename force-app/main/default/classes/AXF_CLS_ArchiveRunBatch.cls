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
    return ALT_CLS_ArchiveRunService.locator(
      ALT_CLS_ArchiveRunService.read(runId)
    );
  }

  public void execute(Database.BatchableContext context, List<SObject> scope) {
    if (failed) {
      return;
    }
    try {
      ALT_CLS_ArchiveRunService.archiveChunk(runId, scope);
    } catch (Exception failure) {
      failed = true;
      ALT_CLS_ArchiveRunService.fail(
        runId,
        'CHUNK_FAILED:' + failure.getTypeName()
      );
    }
  }

  public void finish(Database.BatchableContext context) {
    if (failed) {
      return;
    }
    try {
      ALT_CLS_ArchiveRunService.verify(runId);
    } catch (Exception failure) {
      ALT_CLS_ArchiveRunService.fail(
        runId,
        'VERIFY_FAILED:' + failure.getTypeName()
      );
    }
  }
}
