/**
 * @description Queueable that updates the exchange rates (callouts are not allowed in
 * Schedulable.execute, so ALT_CLS_FxRateSchedule only enqueues this). A day without a bulletin
 * (holiday) or any failure leaves the previous rates in place and fails the job, which then shows
 * in Apex Jobs.
 */
public with sharing class ALT_CLS_FxRateJob implements Queueable, Database.AllowsCallouts {
  public void execute(QueueableContext context) {
    List<ALT_CLS_FxRate.Outcome> outcomes = new ALT_CLS_FxRate().updateAll();
    List<String> failures = new List<String>();
    for (ALT_CLS_FxRate.Outcome outcome : outcomes) {
      if (outcome.error != null) {
        failures.add(outcome.isoCode + ': ' + outcome.error);
      }
    }
    if (!failures.isEmpty()) {
      throw new ALT_CLS_FxRate.FxException(String.join(failures, ' | '));
    }
  }
}
