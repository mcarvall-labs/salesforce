/**
 * @description Sync engine for Pluggy financial facts (AXF-12). Turns the transactions of a
 * connection's holder-confirmed accounts and cards into exactly one immutable
 * AXF_OBJ_BankAccountTransaction__c / AXF_OBJ_CreditCardTransaction__c per AXF-13 identity,
 * idempotently, with a resumable checkpoint per (connection, product, account) scope.
 *
 * Contract honoured (AXF-12):
 *  - daily schedule and on-demand refresh run the SAME processing; concurrency reuses the
 *    active run for a scope instead of fanning out (AC1);
 *  - checkpoint (cursor) is persisted before the risky unit; pagination follows the
 *    provider cursor and Retry-After/backoff; consent/collection is revalidated before any
 *    effect; an account without a confirmed holder is never collected (AC2);
 *  - one fact per approved identity, with the original amount, currency and date; the
 *    provider payment counterparties (CPF/CNPJ) are never persisted (AC3, security);
 *  - replay / reconnection reuse the prior fact by proven identity; upsert on the source
 *    key, never dedup by similarity (AC4);
 *  - every DML result is checked; an incomplete interval is never marked current; recovery
 *    resumes from the checkpoint (AC5);
 *  - health exposes state, attempts, complete-through, last success, sanitized cause (AC6);
 *  - server-side sharing/CRUD/FLS on every path, jobs included (AC7);
 *  - every bound (page size, checkpoint cadence, backoff, attempts) comes from the approved
 *    AXF_PluggySyncPolicy__mdt — nothing invented (AC8).
 *
 * Ordering inside runScope: all reads, then all callouts, then consent refresh + all DML —
 * a callout is never issued after uncommitted DML.
 */
public with sharing class AXF_CLS_PluggySyncService {
  public static final String PRODUCT = 'TRANSACTIONS';
  private static final String SOURCE = 'PLUGGY';
  private static final Integer CALLOUT_SAFETY_MARGIN = 2;
  /** @description Re-scan the last few days each incremental pass so a PENDING row that
   * later changes or a late-arriving transaction is picked up (upsert stays idempotent). */
  private static final Integer INCREMENTAL_OVERLAP_DAYS = 3;

  @TestVisible
  private AXF_CLS_PluggyHttpClient clientForTests;
  @TestVisible
  private AXF_CLS_PluggyConsentService consentServiceForTests;
  @TestVisible
  private static Boolean canConfigureOverride;

  // ---------------------------------------------------------------------------
  // Public shapes
  // ---------------------------------------------------------------------------

  /** @description One durable sync scope: the transactions of a single Pluggy account. */
  public class ClaimedScope {
    public Id connectionId;
    public String runKey;
    public String pluggyAccountId;
    public String kind; // BANK | CARD
    public Id targetId; // AXF_OBJ_BankAccount__c / AXF_OBJ_CreditCard__c
    public String currencyIso;
    public String dateFrom; // YYYY-MM-DD, incremental window start; null = full history
    public String startCursor; // provider cursor to resume from; null = from the start
    public Integer attempt;
    public String token;
  }

  public class ScopeOutcome {
    @AuraEnabled
    public String runKey;
    @AuraEnabled
    public String pluggyAccountId;
    @AuraEnabled
    public String state;
    @AuraEnabled
    public Integer recordsWritten = 0;
    @AuraEnabled
    public Integer recordsFailed = 0;
    @AuraEnabled
    public Boolean moreWork = false;
    @AuraEnabled
    public Integer retryAfterSeconds;
    @AuraEnabled
    public String message;
    // carried to the next execution when moreWork
    public String resumeCursor;
    public Integer nextAttempt;
  }

  public class HealthRow {
    @AuraEnabled
    public String pluggyAccountId;
    @AuraEnabled
    public String kind;
    @AuraEnabled
    public String state;
    @AuraEnabled
    public Integer attempts;
    @AuraEnabled
    public Datetime completeThrough;
    @AuraEnabled
    public Datetime lastSuccessAt;
    @AuraEnabled
    public Integer recordsWritten;
    @AuraEnabled
    public String cause;
    @AuraEnabled
    public String nextAction;
  }

  // ---------------------------------------------------------------------------
  // Claim — DML only, no callout. Serialises daily vs on-demand for a scope.
  // ---------------------------------------------------------------------------

  /**
   * @description Marks the AXF_OBJ_IntegrationRun__c RUNNING (with a fresh worker token) for
   * every eligible scope of a connection and returns the scopes a worker should process now.
   * A scope already RUNNING with a fresh heartbeat is reused, not re-claimed (AC1); a stale
   * RUNNING heartbeat (older than the policy inactivity window) is reclaimed. Collection/consent is
   * asserted up front (AC2). No callout here — safe to call before enqueuing a Queueable.
   */
  public List<ClaimedScope> claimScopes(Id connectionId) {
    requireAuthority();
    AXF_CLS_PluggySyncPolicy policy = AXF_CLS_PluggySyncPolicy.current();

    AXF_OBJ_PluggyConnection__c conn = [
      SELECT Id, AXF_CON_PKL_ConsentState__c, AXF_CON_PKL_CollectionState__c
      FROM AXF_OBJ_PluggyConnection__c
      WHERE Id = :connectionId
      WITH USER_MODE
      LIMIT 1
    ];
    new AXF_CLS_PluggyCollectionControlService()
      .assertCollectionAllowed(conn.Id);

    Map<String, ClaimedScope> wanted = new Map<String, ClaimedScope>();
    for (AXF_OBJ_BankAccount__c b : [
      SELECT Id, AXF_BA_EXI_PluggyAccountId__c, AXF_BA_TXT_CurrencyIsoCode__c
      FROM AXF_OBJ_BankAccount__c
      WHERE
        AXF_BA_LKP_Connection__c = :connectionId
        AND AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE'
        AND AXF_BA_EXI_PluggyAccountId__c != NULL
      WITH USER_MODE
    ]) {
      addWanted(
        wanted,
        connectionId,
        'BANK',
        b.Id,
        b.AXF_BA_EXI_PluggyAccountId__c,
        b.AXF_BA_TXT_CurrencyIsoCode__c
      );
    }
    for (AXF_OBJ_CreditCard__c c : [
      SELECT Id, AXF_CC_EXI_PluggyAccountId__c, AXF_CC_TXT_CurrencyIsoCode__c
      FROM AXF_OBJ_CreditCard__c
      WHERE
        AXF_CC_LKP_Connection__c = :connectionId
        AND AXF_CC_PKL_AvailabilityState__c = 'AVAILABLE'
        AND AXF_CC_EXI_PluggyAccountId__c != NULL
      WITH USER_MODE
    ]) {
      addWanted(
        wanted,
        connectionId,
        'CARD',
        c.Id,
        c.AXF_CC_EXI_PluggyAccountId__c,
        c.AXF_CC_TXT_CurrencyIsoCode__c
      );
    }
    if (wanted.isEmpty()) {
      return new List<ClaimedScope>();
    }

    Map<String, AXF_OBJ_IntegrationRun__c> runByKey = new Map<String, AXF_OBJ_IntegrationRun__c>();
    for (AXF_OBJ_IntegrationRun__c r : [
      SELECT
        Id,
        AXF_INR_EXI_RunKey__c,
        AXF_INR_PKL_State__c,
        AXF_INR_TXT_Cursor__c,
        AXF_INR_DT_Watermark__c,
        AXF_INR_DT_CompleteThrough__c,
        AXF_INR_NUM_Attempt__c,
        AXF_INR_NUM_Version__c
      FROM AXF_OBJ_IntegrationRun__c
      WHERE AXF_INR_EXI_RunKey__c IN :wanted.keySet()
      WITH USER_MODE
    ]) {
      runByKey.put(r.AXF_INR_EXI_RunKey__c, r);
    }

    Datetime staleBefore = Datetime.now()
      .addMinutes(-policy.inactivityMinutesToTerminal);
    List<AXF_OBJ_IntegrationRun__c> toPersist = new List<AXF_OBJ_IntegrationRun__c>();
    List<ClaimedScope> claimed = new List<ClaimedScope>();

    for (String runKey : wanted.keySet()) {
      ClaimedScope scope = wanted.get(runKey);
      AXF_OBJ_IntegrationRun__c run = runByKey.get(runKey);

      Boolean activeElsewhere =
        run != null &&
        run.AXF_INR_PKL_State__c == 'RUNNING' &&
        run.AXF_INR_DT_Watermark__c != null &&
        run.AXF_INR_DT_Watermark__c > staleBefore;
      if (activeElsewhere) {
        continue; // AC1 — reuse the active run, do not fan out
      }
      if (run != null && run.AXF_INR_PKL_State__c == 'FAILED_TERMINAL') {
        continue; // needs a human decision (reauthorize / policy) before retrying
      }

      Boolean resuming =
        run != null &&
        run.AXF_INR_PKL_State__c == 'FAILED_RETRYABLE' &&
        String.isNotBlank(run.AXF_INR_TXT_Cursor__c);

      scope.token = AXF_CLS_PluggyHttpClient.newCorrelationId();
      scope.attempt = (run == null ||
        run.AXF_INR_NUM_Attempt__c == null)
        ? 0
        : Integer.valueOf(run.AXF_INR_NUM_Attempt__c);
      scope.startCursor = resuming ? run.AXF_INR_TXT_Cursor__c : null;
      scope.dateFrom = (!resuming &&
        run != null &&
        run.AXF_INR_DT_CompleteThrough__c != null)
        ? isoDate(
            run.AXF_INR_DT_CompleteThrough__c.dateGmt()
              .addDays(-INCREMENTAL_OVERLAP_DAYS)
          )
        : null;

      AXF_OBJ_IntegrationRun__c persistRun = (run != null)
        ? run
        : new AXF_OBJ_IntegrationRun__c(
            AXF_INR_EXI_RunKey__c = runKey,
            AXF_INR_LKP_Connection__c = connectionId,
            AXF_INR_PKL_Product__c = PRODUCT,
            AXF_INR_NUM_Version__c = 0,
            AXF_INR_NUM_Attempt__c = 0
          );
      persistRun.AXF_INR_PKL_State__c = 'RUNNING';
      persistRun.AXF_INR_TXT_ActiveToken__c = scope.token;
      persistRun.AXF_INR_DT_Watermark__c = Datetime.now();
      persistRun.AXF_INR_NUM_Version__c =
        (persistRun.AXF_INR_NUM_Version__c == null
          ? 0
          : persistRun.AXF_INR_NUM_Version__c) + 1;
      toPersist.add(persistRun);
      claimed.add(scope);
    }

    if (!toPersist.isEmpty()) {
      upsert as user toPersist AXF_INR_EXI_RunKey__c;
    }
    return claimed;
  }

  private void addWanted(
    Map<String, ClaimedScope> wanted,
    Id connectionId,
    String kind,
    Id targetId,
    String pluggyAccountId,
    String currencyIso
  ) {
    String runKey = runKeyFor(connectionId, pluggyAccountId);
    ClaimedScope s = new ClaimedScope();
    s.connectionId = connectionId;
    s.runKey = runKey;
    s.kind = kind;
    s.targetId = targetId;
    s.pluggyAccountId = pluggyAccountId;
    s.currencyIso = String.isBlank(currencyIso) ? 'BRL' : currencyIso;
    wanted.put(runKey, s);
  }

  public static String runKeyFor(Id connectionId, String pluggyAccountId) {
    return AXF_CLS_IdentityFraming.key(
      new List<Object>{ 'inr-v1', connectionId, PRODUCT, pluggyAccountId }
    );
  }

  // ---------------------------------------------------------------------------
  // Run one scope — reads, then callouts, then consent refresh + DML.
  // ---------------------------------------------------------------------------

  public ScopeOutcome runScope(ClaimedScope s) {
    AXF_CLS_PluggySyncPolicy policy = AXF_CLS_PluggySyncPolicy.current();
    ScopeOutcome out = new ScopeOutcome();
    out.runKey = s.runKey;
    out.pluggyAccountId = s.pluggyAccountId;

    // ---- reads ----
    List<AXF_OBJ_IntegrationRun__c> runs = [
      SELECT
        Id,
        AXF_INR_TXT_ActiveToken__c,
        AXF_INR_PKL_State__c,
        AXF_INR_NUM_RecordsWritten__c,
        AXF_INR_NUM_Version__c,
        AXF_INR_DT_CompleteThrough__c
      FROM AXF_OBJ_IntegrationRun__c
      WHERE AXF_INR_EXI_RunKey__c = :s.runKey
      WITH USER_MODE
      LIMIT 1
    ];
    if (runs.isEmpty()) {
      out.state = 'RESULT_UNKNOWN';
      out.message = 'Execucao nao encontrada para este escopo.';
      return out;
    }
    AXF_OBJ_IntegrationRun__c run = runs[0];
    if (run.AXF_INR_TXT_ActiveToken__c != s.token) {
      // Another worker owns this scope now — stand down without side effects (AC1).
      out.state = run.AXF_INR_PKL_State__c;
      out.message = 'Escopo assumido por outra execucao.';
      return out;
    }

    // ---- callouts: paginate up to the checkpoint cadence ----
    List<Map<String, Object>> raw = new List<Map<String, Object>>();
    String cursor = s.startCursor;
    Boolean more = true;
    Integer pages = 0;
    String stop = null; // RATE_LIMIT | GOVERNOR | FORBIDDEN | HTTP_ERROR | UNKNOWN
    Integer retryAfter = null;
    Integer statusSeen = null;
    AXF_CLS_PluggyHttpClient http = client();

    while (more && pages < policy.checkpointEveryPages) {
      if (
        Limits.getLimitCallouts() - Limits.getCallouts() <=
        CALLOUT_SAFETY_MARGIN
      ) {
        stop = 'GOVERNOR';
        break;
      }
      AXF_CLS_PluggyHttpClient.PluggyResponse res;
      try {
        res = http.getJson(buildPath(s, cursor, policy.pageSize));
      } catch (AXF_CLS_PluggyIntegrationException unknownResult) {
        stop = 'UNKNOWN';
        break;
      }
      statusSeen = res.statusCode;
      if (res.statusCode == 429 || res.statusCode == 503) {
        stop = 'RATE_LIMIT';
        retryAfter = res.retryAfterSeconds;
        break;
      }
      if (res.statusCode == 401 || res.statusCode == 403) {
        stop = 'FORBIDDEN';
        break;
      }
      if (!res.isSuccess || res.body == null) {
        stop = 'HTTP_ERROR';
        break;
      }
      Object results = res.body.get('results');
      if (results instanceof List<Object>) {
        for (Object o : (List<Object>) results) {
          if (o instanceof Map<String, Object>) {
            raw.add((Map<String, Object>) o);
          }
        }
      }
      cursor = strOf(res.body.get('next'));
      more = String.isNotBlank(cursor);
      pages++;
    }
    Boolean paginationComplete = !more && stop == null;
    Boolean healthyPause = more && stop == null; // hit checkpoint cadence

    // ---- consent revalidation before any effect (AC2) ----
    AXF_CLS_PluggyConsentService.ConsentSnapshot snap = consentService()
      .refresh(s.connectionId);

    // ---- DML: publish facts, then finalize the run ----
    Map<String, Object> dml = upsertFacts(s, raw);
    out.recordsWritten = (Integer) dml.get('written');
    out.recordsFailed = (Integer) dml.get('failed');
    Date maxDate = (Date) dml.get('maxDate');

    Integer priorWritten = run.AXF_INR_NUM_RecordsWritten__c == null
      ? 0
      : Integer.valueOf(run.AXF_INR_NUM_RecordsWritten__c);

    String state;
    String message;
    Integer attempt = s.attempt;
    String saveCursor = null;
    Datetime completeThrough = run.AXF_INR_DT_CompleteThrough__c;
    Datetime lastSuccessAt = null;

    if (snap.consentState != 'ACTIVE') {
      state = 'FAILED_TERMINAL';
      message = 'Consentimento deixou de estar ativo durante a sincronizacao. Reautorize no provedor.';
    } else if (stop == 'FORBIDDEN') {
      state = 'FAILED_TERMINAL';
      message = 'A aplicacao nao tem autorizacao para ler as transacoes desta conta. Reautorize.';
    } else if (out.recordsFailed > 0) {
      attempt += 1;
      state = attempt >= policy.maxAttempts
        ? 'FAILED_TERMINAL'
        : 'FAILED_RETRYABLE';
      saveCursor = s.startCursor;
      message =
        out.recordsFailed +
        ' registro(s) nao gravaram. ' +
        (state == 'FAILED_TERMINAL'
          ? 'Limite de tentativas atingido.'
          : 'Nova tentativa a partir do checkpoint.');
    } else if (
      stop == 'RATE_LIMIT' ||
      stop == 'UNKNOWN' ||
      stop == 'HTTP_ERROR'
    ) {
      attempt += 1;
      state = attempt >= policy.maxAttempts
        ? 'FAILED_TERMINAL'
        : 'FAILED_RETRYABLE';
      saveCursor = cursor;
      out.retryAfterSeconds = (stop == 'RATE_LIMIT')
        ? (retryAfter != null ? retryAfter : policy.backoffSeconds)
        : policy.backoffSeconds;
      message = (stop == 'RATE_LIMIT')
        ? 'Provedor limitou a taxa de chamadas. Retomada agendada.'
        : AXF_CLS_PluggyHttpClient.sanitizedError(
            'GET /v2/transactions',
            statusSeen,
            s.token
          );
      if (state == 'FAILED_TERMINAL') {
        message += ' Limite de tentativas atingido.';
      }
    } else if (healthyPause || stop == 'GOVERNOR') {
      state = 'RUNNING';
      saveCursor = cursor;
      message =
        'Checkpoint: ' +
        pages +
        ' pagina(s) processada(s). Retomando o restante.';
    } else {
      // paginationComplete
      state = 'SUCCEEDED';
      Datetime seen = (maxDate != null)
        ? Datetime.newInstanceGmt(maxDate, Time.newInstance(23, 59, 59, 0))
        : Datetime.now();
      completeThrough = (completeThrough == null ||
        seen > completeThrough)
        ? seen
        : completeThrough;
      lastSuccessAt = Datetime.now();
      attempt = 0;
      message = out.recordsWritten == 0
        ? 'Sincronizado. Nenhum lancamento novo.'
        : out.recordsWritten + ' lancamento(s) publicado(s) ou atualizado(s).';
    }

    run.AXF_INR_PKL_State__c = state;
    run.AXF_INR_TXT_Cursor__c = saveCursor;
    run.AXF_INR_NUM_Attempt__c = attempt;
    run.AXF_INR_NUM_RecordsWritten__c = priorWritten + out.recordsWritten;
    run.AXF_INR_TXT_Message__c = clip(message, 255);
    run.AXF_INR_TXT_CorrelationId__c = s.token;
    run.AXF_INR_DT_Watermark__c = Datetime.now();
    run.AXF_INR_DT_CompleteThrough__c = completeThrough;
    if (lastSuccessAt != null) {
      run.AXF_INR_DT_LastSuccessAt__c = lastSuccessAt;
    }
    run.AXF_INR_NUM_Version__c =
      (run.AXF_INR_NUM_Version__c == null ? 0 : run.AXF_INR_NUM_Version__c) + 1;
    run.AXF_INR_TXT_ActiveToken__c = (state == 'RUNNING') ? s.token : null;
    update as user run;

    out.state = state;
    out.message = message;
    out.resumeCursor = saveCursor;
    out.nextAttempt = attempt;
    out.moreWork =
      state == 'RUNNING' ||
      (state == 'FAILED_RETRYABLE' &&
      attempt < policy.maxAttempts);
    return out;
  }

  private String buildPath(ClaimedScope s, String cursor, Integer pageSize) {
    String p =
      '/v2/transactions?accountId=' +
      EncodingUtil.urlEncode(s.pluggyAccountId, 'UTF-8') +
      '&pageSize=' +
      pageSize;
    if (String.isNotBlank(s.dateFrom)) {
      p += '&dateFrom=' + s.dateFrom;
    }
    if (String.isNotBlank(cursor)) {
      p += '&after=' + EncodingUtil.urlEncode(cursor, 'UTF-8');
    }
    return p;
  }

  // ---------------------------------------------------------------------------
  // Mapping — Pluggy /v2/transactions object -> one immutable fact (AXF-13).
  // ---------------------------------------------------------------------------

  private Map<String, Object> upsertFacts(
    ClaimedScope s,
    List<Map<String, Object>> raw
  ) {
    Map<String, SObject> bankByKey = new Map<String, SObject>();
    Map<String, SObject> cardByKey = new Map<String, SObject>();
    Date maxDate = null;
    Datetime now = Datetime.now();

    for (Map<String, Object> t : raw) {
      String providerId = strOf(t.get('id'));
      if (String.isBlank(providerId)) {
        continue;
      }
      // Only route rows that belong to the account we asked for.
      String rowAccount = strOf(t.get('accountId'));
      if (String.isNotBlank(rowAccount) && rowAccount != s.pluggyAccountId) {
        continue;
      }
      String key = AXF_CLS_PluggyFactIdentity.fromProviderId(providerId)
        .pluggyId;
      Date bookedOn = factDate(t);
      if (bookedOn != null && (maxDate == null || bookedOn > maxDate)) {
        maxDate = bookedOn;
      }
      Decimal amount = decimalOf(t.get('amount'));
      Decimal magnitude = (amount == null) ? 0 : Math.abs(amount).setScale(2);
      String direction = directionOf(t.get('type'), amount);
      String rawDesc = firstNonBlank(
        strOf(t.get('descriptionRaw')),
        strOf(t.get('description'))
      );
      String status = ('PENDING' == strOf(t.get('status')))
        ? 'PENDING'
        : 'POSTED';
      String ccy = firstNonBlank(strOf(t.get('currencyCode')), s.currencyIso);

      if (s.kind == 'BANK') {
        bankByKey.put(
          key,
          new AXF_OBJ_BankAccountTransaction__c(
            AXF_BAT_MDR_BankAccount__c = s.targetId,
            AXF_BAT_EXI_SourceKey__c = key,
            AXF_BAT_PKL_Source__c = SOURCE,
            AXF_BAT_DAT_Date__c = bookedOn,
            AXF_BAT_NUM_Magnitude__c = magnitude,
            AXF_BAT_PKL_Direction__c = direction,
            AXF_BAT_PKL_Status__c = status,
            AXF_BAT_TXT_CurrencyIsoCode__c = ccy,
            AXF_BAT_TXT_Description__c = clip(rawDesc, 255),
            AXF_BAT_TXT_NormalizedDescription__c = clip(
              AXF_CLS_TextNormalization.normalize(rawDesc),
              255
            ),
            AXF_BAT_TXT_ParserVersion__c = AXF_CLS_TextNormalization.POLICY_VERSION,
            AXF_BAT_TXT_CorrelationId__c = s.token,
            AXF_BAT_TXT_EvidenceRef__c = s.token,
            AXF_BAT_DTM_ImportedAt__c = now,
            AXF_BAT_NUM_Version__c = 0
          )
        );
      } else {
        Map<String, Object> ccMeta = (t.get(
            'creditCardMetadata'
          ) instanceof Map<String, Object>)
          ? (Map<String, Object>) t.get('creditCardMetadata')
          : null;
        String billId = ccMeta == null ? null : strOf(ccMeta.get('billId'));
        String billPeriod = ccMeta == null
          ? null
          : forecastPeriod(ccMeta.get('billForecastDate'));
        cardByKey.put(
          key,
          new AXF_OBJ_CreditCardTransaction__c(
            AXF_CCT_MDR_CreditCard__c = s.targetId,
            AXF_CCT_EXI_SourceKey__c = key,
            AXF_CCT_PKL_Source__c = SOURCE,
            AXF_CCT_DAT_Date__c = bookedOn,
            AXF_CCT_NUM_Magnitude__c = magnitude,
            AXF_CCT_PKL_Direction__c = direction,
            AXF_CCT_PKL_Status__c = status,
            AXF_CCT_TXT_CurrencyIsoCode__c = ccy,
            AXF_CCT_TXT_Description__c = clip(rawDesc, 255),
            AXF_CCT_TXT_NormalizedDescription__c = clip(
              AXF_CLS_TextNormalization.normalize(rawDesc),
              255
            ),
            AXF_CCT_TXT_BillReference__c = clip(billId, 80),
            AXF_CCT_TXT_BillForecastPeriod__c = billPeriod,
            AXF_CCT_TXT_CorrelationId__c = s.token,
            AXF_CCT_TXT_EvidenceRef__c = s.token,
            AXF_CCT_DTM_ImportedAt__c = now,
            AXF_CCT_NUM_Version__c = 0
          )
        );
      }
    }

    Integer written = 0;
    Integer failed = 0;
    if (!bankByKey.isEmpty()) {
      Map<String, Object> r = applyUpsert(
        bankByKey.values(),
        AXF_OBJ_BankAccountTransaction__c.AXF_BAT_EXI_SourceKey__c
      );
      written += (Integer) r.get('ok');
      failed += (Integer) r.get('bad');
    }
    if (!cardByKey.isEmpty()) {
      Map<String, Object> r = applyUpsert(
        cardByKey.values(),
        AXF_OBJ_CreditCardTransaction__c.AXF_CCT_EXI_SourceKey__c
      );
      written += (Integer) r.get('ok');
      failed += (Integer) r.get('bad');
    }
    return new Map<String, Object>{
      'written' => written,
      'failed' => failed,
      'maxDate' => maxDate
    };
  }

  /** @description Partial-success upsert with per-row result inspection (AC5). */
  private Map<String, Object> applyUpsert(
    List<SObject> records,
    Schema.SObjectField externalIdField
  ) {
    Integer ok = 0;
    Integer bad = 0;
    List<Database.UpsertResult> results = Database.upsert(
      records,
      externalIdField,
      false,
      AccessLevel.USER_MODE
    );
    for (Database.UpsertResult r : results) {
      if (r.isSuccess()) {
        ok++;
      } else {
        bad++;
      }
    }
    return new Map<String, Object>{ 'ok' => ok, 'bad' => bad };
  }

  // ---------------------------------------------------------------------------
  // Health (AC6)
  // ---------------------------------------------------------------------------

  public List<HealthRow> health(Id connectionId) {
    requireAuthority();
    Map<String, String> kindByKey = new Map<String, String>();
    Map<String, String> accByKey = new Map<String, String>();
    for (AXF_OBJ_BankAccount__c b : [
      SELECT AXF_BA_EXI_PluggyAccountId__c
      FROM AXF_OBJ_BankAccount__c
      WHERE
        AXF_BA_LKP_Connection__c = :connectionId
        AND AXF_BA_EXI_PluggyAccountId__c != NULL
      WITH USER_MODE
    ]) {
      String k = runKeyFor(connectionId, b.AXF_BA_EXI_PluggyAccountId__c);
      kindByKey.put(k, 'BANK');
      accByKey.put(k, b.AXF_BA_EXI_PluggyAccountId__c);
    }
    for (AXF_OBJ_CreditCard__c c : [
      SELECT AXF_CC_EXI_PluggyAccountId__c
      FROM AXF_OBJ_CreditCard__c
      WHERE
        AXF_CC_LKP_Connection__c = :connectionId
        AND AXF_CC_EXI_PluggyAccountId__c != NULL
      WITH USER_MODE
    ]) {
      String k = runKeyFor(connectionId, c.AXF_CC_EXI_PluggyAccountId__c);
      kindByKey.put(k, 'CARD');
      accByKey.put(k, c.AXF_CC_EXI_PluggyAccountId__c);
    }

    // One row per scope — accounts that have never synced still show, as "waiting".
    Map<String, HealthRow> byKey = new Map<String, HealthRow>();
    for (String k : kindByKey.keySet()) {
      HealthRow h = new HealthRow();
      h.pluggyAccountId = accByKey.get(k);
      h.kind = kindByKey.get(k);
      h.state = null;
      h.attempts = 0;
      h.recordsWritten = 0;
      h.nextAction = nextAction(null);
      byKey.put(k, h);
    }
    if (byKey.isEmpty()) {
      return new List<HealthRow>();
    }
    for (AXF_OBJ_IntegrationRun__c r : [
      SELECT
        AXF_INR_EXI_RunKey__c,
        AXF_INR_PKL_State__c,
        AXF_INR_NUM_Attempt__c,
        AXF_INR_NUM_RecordsWritten__c,
        AXF_INR_DT_CompleteThrough__c,
        AXF_INR_DT_LastSuccessAt__c,
        AXF_INR_TXT_Message__c
      FROM AXF_OBJ_IntegrationRun__c
      WHERE AXF_INR_EXI_RunKey__c IN :kindByKey.keySet()
      WITH USER_MODE
    ]) {
      HealthRow h = byKey.get(r.AXF_INR_EXI_RunKey__c);
      if (h == null) {
        continue;
      }
      h.state = r.AXF_INR_PKL_State__c;
      h.attempts = (Integer) r.AXF_INR_NUM_Attempt__c;
      h.completeThrough = r.AXF_INR_DT_CompleteThrough__c;
      h.lastSuccessAt = r.AXF_INR_DT_LastSuccessAt__c;
      h.recordsWritten = (Integer) r.AXF_INR_NUM_RecordsWritten__c;
      h.cause = r.AXF_INR_TXT_Message__c;
      h.nextAction = nextAction(r.AXF_INR_PKL_State__c);
    }
    return byKey.values();
  }

  private static String nextAction(String state) {
    switch on state {
      when 'SUCCEEDED' {
        return 'Nenhuma acao necessaria.';
      }
      when 'RUNNING' {
        return 'Sincronizacao em andamento.';
      }
      when 'FAILED_RETRYABLE' {
        return 'Retomada automatica agendada.';
      }
      when 'FAILED_TERMINAL' {
        return 'Reautorize a conexao no provedor ou revise a politica; depois acione "Sincronizar agora".';
      }
      when else {
        return 'Aguardando primeira sincronizacao.';
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Small helpers
  // ---------------------------------------------------------------------------

  private AXF_CLS_PluggyHttpClient client() {
    return clientForTests != null
      ? clientForTests
      : new AXF_CLS_PluggyHttpClient();
  }

  private AXF_CLS_PluggyConsentService consentService() {
    return consentServiceForTests != null
      ? consentServiceForTests
      : new AXF_CLS_PluggyConsentService();
  }

  private Boolean callerCanConfigure() {
    if (canConfigureOverride != null) {
      return canConfigureOverride;
    }
    return FeatureManagement.checkPermission('AXF_CanConfigure');
  }

  private void requireAuthority() {
    if (!callerCanConfigure()) {
      throw new AXF_CLS_PluggyDiscoveryException(
        'Voce nao tem autorizacao para sincronizar fontes Pluggy.'
      );
    }
  }

  private static Date factDate(Map<String, Object> t) {
    Datetime dt = parseIso(strOf(t.get('date')));
    return dt == null ? null : dt.dateGmt();
  }

  private static String directionOf(Object typeValue, Decimal amount) {
    String type = strOf(typeValue);
    if (type == 'CREDIT' || type == 'DEBIT') {
      return type;
    }
    return (amount != null && amount < 0) ? 'DEBIT' : 'CREDIT';
  }

  private static String forecastPeriod(Object billForecastDate) {
    Datetime dt = parseIso(strOf(billForecastDate));
    if (dt == null) {
      return null;
    }
    Date d = dt.dateGmt();
    return d.year() + '-' + String.valueOf(d.month()).leftPad(2, '0');
  }

  private static Datetime parseIso(String iso) {
    if (String.isBlank(iso)) {
      return null;
    }
    try {
      return (Datetime) JSON.deserialize('"' + iso + '"', Datetime.class);
    } catch (Exception e) {
      return null;
    }
  }

  private static String isoDate(Date d) {
    return d.year() +
      '-' +
      String.valueOf(d.month()).leftPad(2, '0') +
      '-' +
      String.valueOf(d.day()).leftPad(2, '0');
  }

  private static String strOf(Object o) {
    return o == null ? null : String.valueOf(o);
  }

  private static String firstNonBlank(String a, String b) {
    return String.isNotBlank(a) ? a : b;
  }

  private static Decimal decimalOf(Object o) {
    if (o == null) {
      return null;
    }
    try {
      return Decimal.valueOf(String.valueOf(o));
    } catch (Exception e) {
      return null;
    }
  }

  private static String clip(String s, Integer max) {
    if (s == null) {
      return null;
    }
    return s.length() > max ? s.substring(0, max) : s;
  }
}
