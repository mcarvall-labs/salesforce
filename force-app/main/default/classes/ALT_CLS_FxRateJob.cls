/**
 * @description Queueable that updates the exchange rates (callouts are not allowed in
 * Schedulable.execute, so ALT_CLS_FxRateSchedule only enqueues this). A holiday falls back to the
 * last closing bulletin; a failure on a currency (no bulletin in the lookback window, service down,
 * write refused, missing parameter) leaves that currency's previous rate in place and fails the
 * job after all currencies were tried, so it shows in Apex Jobs. Currencies are independent: some
 * can be updated while another fails.
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
