/**
 * @description Monthly job that keeps recurring and PRICE-financing Cash Flow series
 * projected ALT_CLS_CashFlowForecast.FUTURE_HORIZON_MONTHS ahead of today.
 */
public with sharing class AXF_CLS_CashFlowForecastScheduler implements Schedulable {
  private static final String MONTHLY_CRON_EXPRESSION = '0 0 3 1 * ?';
  private static final String JOB_NAME = 'AXF Cash Flow Forecast - Monthly';

  public void execute(SchedulableContext context) {
    new ALT_CLS_CashFlowForecast().extendActiveGroups();
  }

  public static String scheduleMonthly() {
    return System.schedule(
      JOB_NAME,
      MONTHLY_CRON_EXPRESSION,
      new AXF_CLS_CashFlowForecastScheduler()
    );
  }
}
