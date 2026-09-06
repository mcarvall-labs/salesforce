/**
 * @description Drives one Pluggy transaction sync: processes a single scope per execution
 * (which naturally bounds the callouts of a transaction) and re-chains for the rest, so a
 * connection with many accounts, or a scope with many pages, finishes across a chain of
 * short jobs. Recovery produces at most one canonical successor (AXF-12 AC5). A scope that
 * asks to continue goes to the back of the queue so every scope keeps making progress.
 */
public with sharing class AXF_CLS_PluggySyncQueueable implements Queueable, Database.AllowsCallouts {
  private final List<AXF_CLS_PluggySyncService.ClaimedScope> pending;

  public AXF_CLS_PluggySyncQueueable(
    List<AXF_CLS_PluggySyncService.ClaimedScope> scopes
  ) {
    this.pending = (scopes == null)
      ? new List<AXF_CLS_PluggySyncService.ClaimedScope>()
      : scopes;
  }

  public void execute(QueueableContext ctx) {
    if (pending.isEmpty()) {
      return;
    }
    AXF_CLS_PluggySyncService.ClaimedScope scope = pending.remove(0);
    AXF_CLS_PluggySyncService.ScopeOutcome outcome;
    try {
      outcome = new AXF_CLS_PluggySyncService().runScope(scope);
    } catch (Exception e) {
      // Unexpected failure mid-scope: the run keeps its RUNNING/RETRYABLE row and stale
      // heartbeat, so the next scheduled pass reclaims it. Carry on with the other scopes.
      outcome = null;
    }

    if (outcome != null && outcome.moreWork) {
      scope.startCursor = outcome.resumeCursor;
      scope.attempt = outcome.nextAttempt;
      pending.add(scope);
    }
    if (pending.isEmpty()) {
      return;
    }

    Integer delayMinutes = 0;
    if (outcome != null && outcome.retryAfterSeconds != null) {
      delayMinutes = Math.min(
        10,
        Math.max(1, (Integer) Math.ceil(outcome.retryAfterSeconds / 60.0))
      );
    }
    chain(new AXF_CLS_PluggySyncQueueable(pending), delayMinutes);
  }

  /** @description Isolated so a test can drive execute() without a forbidden test-context
   * chain. Delay + immediate fallback handle orgs that reject delayed chaining. */
  @TestVisible
  private void chain(AXF_CLS_PluggySyncQueueable next, Integer delayMinutes) {
    if (Test.isRunningTest()) {
      return;
    }
    try {
      if (delayMinutes > 0) {
        System.enqueueJob(next, delayMinutes);
      } else {
        System.enqueueJob(next);
      }
    } catch (Exception e) {
      System.enqueueJob(next);
    }
  }
}
