/**
 * @description AXF-95 — run-key integrity across archivists. Checkpoints are OWD Private and
 * their key is unique, so a second Gestor must learn that a run exists (without reading it)
 * instead of colliding on the key, and a run whose batch is still executing must not be
 * restarted. Returns booleans only.
 */
public without sharing class ALT_CLS_ArchiveRunIntegrity {
  private static final Set<String> ACTIVE = new Set<String>{
    'Holding',
    'Queued',
    'Preparing',
    'Processing'
  };

  /** A sibling run (other key: previous policy/window) of the same family and holder still executing. */
  public static Boolean anotherRunActive(
    String family,
    Id accountId,
    String runKey
  ) {
    for (AXF_OBJ_ArchiveRun__c run : [
      SELECT AXF_ARR_TXT_JobId__c
      FROM AXF_OBJ_ArchiveRun__c
      WHERE
        AXF_ARR_PKL_SourceFamily__c = :family
        AND AXF_ARR_LKP_Account__c = :accountId
        AND AXF_ARR_EXI_RunKey__c != :runKey
        AND AXF_ARR_PKL_Phase__c IN ('SCANNING', 'WRITING', 'VERIFYING')
      WITH SYSTEM_MODE
      LIMIT 20
    ]) {
      if (isJobActive(run.AXF_ARR_TXT_JobId__c)) {
        return true;
      }
    }
    return false;
  }

  public static Boolean exists(String runKey) {
    return ![
        SELECT Id
        FROM AXF_OBJ_ArchiveRun__c
        WHERE AXF_ARR_EXI_RunKey__c = :runKey
        WITH SYSTEM_MODE
        LIMIT 1
      ]
      .isEmpty();
  }

  @TestVisible
  private static Boolean jobActiveOverride;

  public static Boolean isJobActive(String jobId) {
    if (jobActiveOverride != null) {
      return jobActiveOverride;
    }
    if (String.isBlank(jobId)) {
      return false;
    }
    for (AsyncApexJob job : [
      SELECT Status
      FROM AsyncApexJob
      WHERE Id = :jobId
      LIMIT 1
    ]) {
      return ACTIVE.contains(job.Status);
    }
    return false;
  }
}
