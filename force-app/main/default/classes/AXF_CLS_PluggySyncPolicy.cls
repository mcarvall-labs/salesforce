/**
 * @description Typed reader for AXF_PluggySyncPolicy__mdt (AXF-12 AC8). Every parameter that
 * bounds the sync — page size, checkpoint cadence, backoff, attempt ceiling, single-run
 * guard, schedule — comes from the approved "Default" record, never from a literal in the
 * engine. Missing record => the sync refuses to run (no invented budget).
 */
public inherited sharing class AXF_CLS_PluggySyncPolicy {
  @TestVisible
  private static AXF_PluggySyncPolicy__mdt overrideRecord;

  /** @description Test hook: force the "no approved policy" path even though the org ships a
   * Default record. */
  @TestVisible
  private static Boolean forceMissing = false;

  public final Integer pageSize;
  public final Integer checkpointEveryPages;
  public final Integer backoffSeconds;
  public final Integer maxAttempts;
  public final Integer maxActiveRunsPerScope;
  public final Integer dailyScheduleHour;
  public final Integer inactivityMinutesToTerminal;
  public final String scheduleTimeZone;

  private AXF_CLS_PluggySyncPolicy(AXF_PluggySyncPolicy__mdt r) {
    this.pageSize = intOf(r.AXF_PSP_NUM_PageSize__c);
    this.checkpointEveryPages = intOf(r.AXF_PSP_NUM_CheckpointEveryPages__c);
    this.backoffSeconds = intOf(r.AXF_PSP_NUM_BackoffSeconds__c);
    this.maxAttempts = intOf(r.AXF_PSP_NUM_MaxAttempts__c);
    this.maxActiveRunsPerScope = intOf(r.AXF_PSP_NUM_MaxActiveRunsPerScope__c);
    this.dailyScheduleHour = intOf(r.AXF_PSP_NUM_DailyScheduleHour__c);
    this.inactivityMinutesToTerminal = intOf(
      r.AXF_PSP_NUM_InactivityMinutesToTerminal__c
    );
    this.scheduleTimeZone = r.AXF_PSP_TXT_ScheduleTimeZone__c;
  }

  /**
   * @description The approved policy. Throws AXF_CLS_PluggyConfigException when the record is
   * absent or has an unusable value, so a run never proceeds on a guessed limit.
   */
  public static AXF_CLS_PluggySyncPolicy current() {
    AXF_PluggySyncPolicy__mdt r = forceMissing
      ? null
      : (overrideRecord != null
          ? overrideRecord
          : AXF_PluggySyncPolicy__mdt.getInstance('Default'));
    if (r == null) {
      throw new AXF_CLS_PluggyConfigException(
        'Politica de sincronizacao Pluggy nao configurada (AXF_PluggySyncPolicy__mdt.Default). ' +
        'Peca ao Gestor Financeiro para publicar os parametros aprovados antes de sincronizar.'
      );
    }
    AXF_CLS_PluggySyncPolicy p = new AXF_CLS_PluggySyncPolicy(r);
    if (
      p.pageSize == null ||
      p.pageSize <= 0 ||
      p.checkpointEveryPages == null ||
      p.checkpointEveryPages <= 0 ||
      p.backoffSeconds == null ||
      p.backoffSeconds < 0 ||
      p.maxAttempts == null ||
      p.maxAttempts <= 0 ||
      p.maxActiveRunsPerScope == null ||
      p.maxActiveRunsPerScope <= 0 ||
      p.inactivityMinutesToTerminal == null ||
      p.inactivityMinutesToTerminal <= 0
    ) {
      throw new AXF_CLS_PluggyConfigException(
        'Politica de sincronizacao Pluggy com valores invalidos. Revise AXF_PluggySyncPolicy__mdt.Default.'
      );
    }
    return p;
  }

  private static Integer intOf(Decimal d) {
    return d == null ? null : Integer.valueOf(d);
  }
}
