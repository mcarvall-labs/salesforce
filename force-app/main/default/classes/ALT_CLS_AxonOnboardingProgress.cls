/**
 * @description Durable, server-side authority for onboarding progress (AXF-88).
 *
 * Contract: ARCHITECTURE-SPINE.md "Fechamento G5" (G5-1, G5-4, G5-6) + G3-4
 * (retomar qualquer etapa isoladamente) + AD-14/AD-17/AD-24.
 *
 * What this story owns:
 * - Persist which onboarding steps were *confirmed on the server* and what the
 *   next action is. Navigating, marking locally or clicking is never proof of a
 *   write (AC2) — only confirmStep() with a minimal evidence reference is.
 * - Resume: getState() revalidates authority and returns the effective per-step
 *   state; it never trusts client-held progress.
 * - Optimistic concurrency: every mutation carries the expected header Version;
 *   a mismatch (concurrent session or out-of-wizard change) is CONFLICT, never a
 *   silent overwrite (AC6).
 * - RESULT_UNKNOWN: a step whose submit outcome is unknown is parked and blocks
 *   any further confirm until reconcileStep() resolves it — never a blind retry
 *   (AC3, G5-4).
 * - Back-edit: reopenStep() flips one step back and marks later confirmed
 *   non-optional steps STALE; it triggers no side effect in other capabilities
 *   and never repeats an import / user creation / access grant (AC4).
 * - Secrets: evidence and notes are rejected when they look like a secret; this
 *   object never stores a Client Secret, token, password or financial data
 *   (AC5).
 * - Authorization: getState() and every mutation require AXF_CanConfigure. With
 *   authority removed, getState() returns forbidden and no rows — history/resume
 *   reveal nothing, and the progress record grants no access to the records it
 *   references (AC7).
 *
 * Not in scope: the wizard UI itself (AXF-90), the consumer capabilities
 * (AXF-11/84/85/82/87) and their own idempotency/identity. This story does not
 * re-implement their services.
 *
 * User-facing strings are PT-BR literals for the MVP (D-86); the DTO is built so
 * AXF-90 can localise on the client.
 *
 * AXF-88.
 */
public with sharing class ALT_CLS_AxonOnboardingProgress {
  // ---- step catalogue (canonical order) ----
  public enum StepKey {
    WELCOME_PREFS,
    PLUGGY_CREDENTIALS,
    PLUGGY_DISCOVERY,
    ACCOUNT_HOLDERS,
    PEOPLE_ACCESS,
    MANUAL_SOURCES,
    CURRENCY_PREF
  }

  @TestVisible
  private static final List<StepKey> STEP_ORDER = new List<StepKey>{
    StepKey.WELCOME_PREFS,
    StepKey.PLUGGY_CREDENTIALS,
    StepKey.PLUGGY_DISCOVERY,
    StepKey.ACCOUNT_HOLDERS,
    StepKey.PEOPLE_ACCESS,
    StepKey.MANUAL_SOURCES,
    StepKey.CURRENCY_PREF
  };

  @TestVisible
  private static final Set<StepKey> OPTIONAL_STEPS = new Set<StepKey>{
    StepKey.PEOPLE_ACCESS,
    StepKey.MANUAL_SOURCES
  };

  private static final Map<String, StepKey> NAME_TO_STEP = buildNameMap();

  private static Map<String, StepKey> buildNameMap() {
    Map<String, StepKey> m = new Map<String, StepKey>();
    for (StepKey k : StepKey.values()) {
      m.put(k.name(), k);
    }
    return m;
  }

  public enum Outcome {
    LOADED,
    CONFIRMED,
    REOPENED,
    SKIPPED,
    UNKNOWN_PARKED,
    RECONCILED,
    COMPLETED,
    CONFLICT,
    FORBIDDEN,
    INVALID,
    BLOCKED_UNKNOWN
  }

  // ---- PT-BR messages (MVP) ----
  @TestVisible
  private static final String MSG_FORBIDDEN = 'Você não tem autorização para configurar o Axon.';
  @TestVisible
  private static final String MSG_CONFLICT = 'A configuração mudou em outra sessão. Recarregue para ver o estado atual antes de continuar.';
  @TestVisible
  private static final String MSG_UNKNOWN_BLOCKED = 'Esta etapa está aguardando reconciliação porque o resultado do envio anterior é desconhecido. Reconcilie antes de confirmar de novo.';
  @TestVisible
  private static final String MSG_SECRET_LIKE = 'A referência de evidência não pode conter segredo, token, senha ou chave de API.';
  @TestVisible
  private static final String MSG_UNKNOWN_STEP = 'Etapa desconhecida.';
  @TestVisible
  private static final String MSG_PENDING_ON_COMPLETE = 'Ainda há etapas obrigatórias pendentes. Conclua-as ou reconheça as pendências para finalizar.';
  @TestVisible
  private static final String MSG_STALE_DETECTED = 'Estado obsoleto detectado: uma etapa anterior foi reaberta; revise as etapas marcadas como desatualizadas.';

  private static final Pattern SECRET_WORDS = Pattern.compile(
    '(?i)(secret|token|senha|password|api[_\\- ]?key|bearer|client[_\\- ]?secret|authorization)'
  );
  // long unbroken hex / base64-ish blob => very likely a credential
  private static final Pattern SECRET_BLOB = Pattern.compile(
    '[A-Za-z0-9+/=_\\-]{32,}'
  );

  @TestVisible
  private static Boolean canConfigureOverride;

  @TestVisible
  private static Boolean callerCanConfigure() {
    if (canConfigureOverride != null) {
      return canConfigureOverride;
    }
    return FeatureManagement.checkPermission('AXF_CanConfigure');
  }

  // ================= DTOs =================
  public class StepView {
    @AuraEnabled
    public String stepKey;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Boolean optional;
    @AuraEnabled
    public String evidenceRef;
    @AuraEnabled
    public Integer attempt;
    @AuraEnabled
    public Datetime confirmedAt;
    @AuraEnabled
    public String note;
    @AuraEnabled
    public String correlationId;
  }

  public class OnboardingState {
    @AuraEnabled
    public Boolean forbidden = false;
    @AuraEnabled
    public Id progressId;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String currentStep;
    @AuraEnabled
    public Integer version;
    @AuraEnabled
    public Boolean staleDetected = false;
    @AuraEnabled
    public String notice;
    @AuraEnabled
    public Datetime lastReconciledAt;
    @AuraEnabled
    public Datetime completedAt;
    @AuraEnabled
    public String outcome;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public List<StepView> steps = new List<StepView>();
  }

  public class ConfirmInput {
    @AuraEnabled
    public String stepKey;
    @AuraEnabled
    public Integer expectedVersion;
    @AuraEnabled
    public String evidenceRef;
    @AuraEnabled
    public String note;
  }

  // ================= public API =================
  public OnboardingState getState() {
    if (!callerCanConfigure()) {
      return forbidden();
    }
    Header h = loadOrCreate();
    return toState(h, Outcome.LOADED, null);
  }

  public OnboardingState confirmStep(ConfirmInput input) {
    return mutate(
      input == null ? null : input.stepKey,
      input == null ? null : input.expectedVersion,
      MutationKind.CONFIRM,
      input == null ? null : input.evidenceRef,
      input == null ? null : input.note,
      null
    );
  }

  public OnboardingState skipStep(String stepKey, Integer expectedVersion) {
    return mutate(
      stepKey,
      expectedVersion,
      MutationKind.SKIP,
      null,
      null,
      null
    );
  }

  public OnboardingState reopenStep(String stepKey, Integer expectedVersion) {
    return mutate(
      stepKey,
      expectedVersion,
      MutationKind.REOPEN,
      null,
      null,
      null
    );
  }

  public OnboardingState markResultUnknown(
    String stepKey,
    Integer expectedVersion,
    String correlationId
  ) {
    return mutate(
      stepKey,
      expectedVersion,
      MutationKind.PARK_UNKNOWN,
      null,
      null,
      correlationId
    );
  }

  /**
   * Resolve a RESULT_UNKNOWN step. The caller has already reconciled the real
   * effect (by external id / effective record) and passes the verified outcome.
   */
  public OnboardingState reconcileStep(
    String stepKey,
    Integer expectedVersion,
    Boolean confirmed,
    String evidenceRef
  ) {
    return mutate(
      stepKey,
      expectedVersion,
      confirmed == true
        ? MutationKind.RECONCILE_OK
        : MutationKind.RECONCILE_FAIL,
      evidenceRef,
      null,
      null
    );
  }

  public OnboardingState complete(
    Integer expectedVersion,
    Boolean acknowledgePending
  ) {
    if (!callerCanConfigure()) {
      return forbidden();
    }
    Header h = loadOrCreate();
    if (!versionMatches(h, expectedVersion)) {
      return toState(h, Outcome.CONFLICT, MSG_CONFLICT);
    }
    Boolean pending = false;
    for (AXF_OBJ_OnboardingStep__c s : h.steps.values()) {
      StepKey k = parseStep(s.AXF_OST_PKL_StepKey__c);
      Boolean done =
        s.AXF_OST_PKL_Status__c == 'CONFIRMED' ||
        s.AXF_OST_PKL_Status__c == 'SKIPPED';
      if (!done && !OPTIONAL_STEPS.contains(k)) {
        pending = true;
      }
    }
    if (pending && acknowledgePending != true) {
      return toState(h, Outcome.INVALID, MSG_PENDING_ON_COMPLETE);
    }
    h.record.AXF_ONB_PKL_Status__c = 'COMPLETED';
    h.record.AXF_ONB_PKL_CurrentStep__c = 'DONE';
    h.record.AXF_ONB_DTM_CompletedAt__c = Datetime.now();
    h.record.AXF_ONB_NUM_Version__c = h.version() + 1;
    h.record.AXF_ONB_LKP_RunningUser__c = UserInfo.getUserId();
    Database.update(h.record, AccessLevel.SYSTEM_MODE);
    return toState(reload(h.record.Id), Outcome.COMPLETED, null);
  }

  // ================= internals =================
  private enum MutationKind {
    CONFIRM,
    SKIP,
    REOPEN,
    PARK_UNKNOWN,
    RECONCILE_OK,
    RECONCILE_FAIL
  }

  private OnboardingState mutate(
    String rawStep,
    Integer expectedVersion,
    MutationKind kind,
    String evidenceRef,
    String note,
    String correlationId
  ) {
    if (!callerCanConfigure()) {
      return forbidden();
    }
    StepKey step;
    try {
      step = parseStep(rawStep);
    } catch (Exception e) {
      OnboardingState bad = new OnboardingState();
      bad.outcome = Outcome.INVALID.name();
      bad.message = MSG_UNKNOWN_STEP;
      return bad;
    }

    if (kind == MutationKind.CONFIRM || kind == MutationKind.RECONCILE_OK) {
      String secretHit = firstSecretHit(evidenceRef);
      if (secretHit == null) {
        secretHit = firstSecretHit(note);
      }
      if (secretHit != null) {
        OnboardingState bad = new OnboardingState();
        bad.outcome = Outcome.INVALID.name();
        bad.message = MSG_SECRET_LIKE;
        return bad;
      }
    }

    Header h = loadOrCreate();
    if (!versionMatches(h, expectedVersion)) {
      return toState(h, Outcome.CONFLICT, MSG_CONFLICT);
    }

    AXF_OBJ_OnboardingStep__c row = h.steps.get(step);
    Boolean parkedUnknown = row.AXF_OST_PKL_Status__c == 'RESULT_UNKNOWN';
    if (
      parkedUnknown &&
      (kind == MutationKind.CONFIRM ||
      kind == MutationKind.SKIP)
    ) {
      return toState(h, Outcome.BLOCKED_UNKNOWN, MSG_UNKNOWN_BLOCKED);
    }

    Outcome result;
    List<SObject> toUpdate = new List<SObject>();

    if (kind == MutationKind.CONFIRM || kind == MutationKind.RECONCILE_OK) {
      row.AXF_OST_PKL_Status__c = 'CONFIRMED';
      row.AXF_OST_DTM_ConfirmedAt__c = Datetime.now();
      row.AXF_OST_LKP_ConfirmedBy__c = UserInfo.getUserId();
      row.AXF_OST_NUM_Attempt__c = safeInt(row.AXF_OST_NUM_Attempt__c) + 1;
      if (String.isNotBlank(evidenceRef)) {
        row.AXF_OST_TXT_EvidenceRef__c = evidenceRef.abbreviate(255);
      }
      if (String.isNotBlank(note)) {
        row.AXF_OST_TXT_Note__c = note.abbreviate(255);
      }
      if (kind == MutationKind.RECONCILE_OK) {
        row.AXF_OST_TXT_CorrelationId__c = null;
      }
      result = kind == MutationKind.RECONCILE_OK
        ? Outcome.RECONCILED
        : Outcome.CONFIRMED;
    } else if (kind == MutationKind.SKIP) {
      row.AXF_OST_PKL_Status__c = 'SKIPPED';
      row.AXF_OST_DTM_ConfirmedAt__c = Datetime.now();
      row.AXF_OST_LKP_ConfirmedBy__c = UserInfo.getUserId();
      row.AXF_OST_NUM_Attempt__c = safeInt(row.AXF_OST_NUM_Attempt__c) + 1;
      result = Outcome.SKIPPED;
    } else if (kind == MutationKind.REOPEN) {
      row.AXF_OST_PKL_Status__c = 'NOT_STARTED';
      row.AXF_OST_DTM_ConfirmedAt__c = null;
      row.AXF_OST_TXT_EvidenceRef__c = null;
      row.AXF_OST_TXT_CorrelationId__c = null;
      // later confirmed, non-optional steps become STALE (AC4)
      Integer fromIdx = STEP_ORDER.indexOf(step);
      for (Integer i = fromIdx + 1; i < STEP_ORDER.size(); i++) {
        StepKey later = STEP_ORDER[i];
        AXF_OBJ_OnboardingStep__c ls = h.steps.get(later);
        if (
          ls.AXF_OST_PKL_Status__c == 'CONFIRMED' &&
          !OPTIONAL_STEPS.contains(later)
        ) {
          ls.AXF_OST_PKL_Status__c = 'STALE';
          toUpdate.add(ls);
        }
      }
      result = Outcome.REOPENED;
    } else if (kind == MutationKind.PARK_UNKNOWN) {
      row.AXF_OST_PKL_Status__c = 'RESULT_UNKNOWN';
      row.AXF_OST_TXT_CorrelationId__c = String.isBlank(correlationId)
        ? null
        : correlationId.abbreviate(64);
      result = Outcome.UNKNOWN_PARKED;
    } else {
      // RECONCILE_FAIL
      row.AXF_OST_PKL_Status__c = 'FAILED';
      row.AXF_OST_TXT_CorrelationId__c = null;
      result = Outcome.RECONCILED;
    }

    toUpdate.add(row);

    h.record.AXF_ONB_NUM_Version__c = h.version() + 1;
    h.record.AXF_ONB_LKP_RunningUser__c = UserInfo.getUserId();
    h.record.AXF_ONB_PKL_CurrentStep__c = deriveCurrentStep(h);
    if (
      kind == MutationKind.RECONCILE_OK ||
      kind == MutationKind.RECONCILE_FAIL
    ) {
      h.record.AXF_ONB_DTM_LastReconciledAt__c = Datetime.now();
    }
    h.record.AXF_ONB_TXT_Notice__c = anyStale(h) ? MSG_STALE_DETECTED : null;

    Database.update(toUpdate, AccessLevel.SYSTEM_MODE);
    Database.update(h.record, AccessLevel.SYSTEM_MODE);

    return toState(reload(h.record.Id), result, null);
  }

  // ---- header + steps holder ----
  private class Header {
    AXF_OBJ_OnboardingProgress__c record;
    Map<StepKey, AXF_OBJ_OnboardingStep__c> steps = new Map<StepKey, AXF_OBJ_OnboardingStep__c>();
    Integer version() {
      return safeInt(record.AXF_ONB_NUM_Version__c);
    }
  }

  @TestVisible
  private static String scopeKey() {
    // single family per install (G3/AXF-77): one onboarding per org.
    return UserInfo.getOrganizationId();
  }

  // Internal workflow-state object: reads and writes run in SYSTEM_MODE. The
  // authority is the explicit AXF_CanConfigure check on every entry point (AC2,
  // AC7); this record grants no access to the records it references, and it must
  // be visible to *every* authorised configurator regardless of who created it
  // (concurrent sessions — AC6), which record-level sharing on a Private object
  // would not guarantee. The PS still carries object/FLS grants for AXF-90's UI.
  private static final String HEADER_FIELDS =
    'Id, AXF_ONB_EXI_ScopeKey__c, AXF_ONB_PKL_Status__c, ' +
    'AXF_ONB_PKL_CurrentStep__c, AXF_ONB_NUM_Version__c, AXF_ONB_TXT_Notice__c, ' +
    'AXF_ONB_DTM_LastReconciledAt__c, AXF_ONB_DTM_CompletedAt__c, ' +
    '(SELECT Id, AXF_OST_PKL_StepKey__c, AXF_OST_PKL_Status__c, ' +
    'AXF_OST_CHK_Optional__c, AXF_OST_TXT_EvidenceRef__c, AXF_OST_NUM_Attempt__c, ' +
    'AXF_OST_DTM_ConfirmedAt__c, AXF_OST_TXT_Note__c, AXF_OST_TXT_CorrelationId__c ' +
    'FROM Steps__r)';

  private Header loadOrCreate() {
    String key = scopeKey();
    List<AXF_OBJ_OnboardingProgress__c> found = Database.query(
      'SELECT ' +
        HEADER_FIELDS +
        ' FROM AXF_OBJ_OnboardingProgress__c' +
        ' WHERE AXF_ONB_EXI_ScopeKey__c = :key LIMIT 1',
      AccessLevel.SYSTEM_MODE
    );
    if (!found.isEmpty()) {
      return hydrate(found[0]);
    }
    return create(key);
  }

  private Header create(String key) {
    AXF_OBJ_OnboardingProgress__c rec = new AXF_OBJ_OnboardingProgress__c(
      AXF_ONB_EXI_ScopeKey__c = key,
      AXF_ONB_PKL_Status__c = 'IN_PROGRESS',
      AXF_ONB_PKL_CurrentStep__c = STEP_ORDER[0].name(),
      AXF_ONB_NUM_Version__c = 0,
      AXF_ONB_LKP_RunningUser__c = UserInfo.getUserId()
    );
    Database.insert(rec, AccessLevel.SYSTEM_MODE);

    List<AXF_OBJ_OnboardingStep__c> rows = new List<AXF_OBJ_OnboardingStep__c>();
    for (StepKey k : STEP_ORDER) {
      rows.add(
        new AXF_OBJ_OnboardingStep__c(
          AXF_OST_MDR_Progress__c = rec.Id,
          AXF_OST_PKL_StepKey__c = k.name(),
          AXF_OST_PKL_Status__c = 'NOT_STARTED',
          AXF_OST_CHK_Optional__c = OPTIONAL_STEPS.contains(k),
          AXF_OST_EXI_StepUid__c = key + ':' + k.name(),
          AXF_OST_NUM_Attempt__c = 0
        )
      );
    }
    Database.insert(rows, AccessLevel.SYSTEM_MODE);
    return reload(rec.Id);
  }

  private Header reload(Id progressId) {
    List<AXF_OBJ_OnboardingProgress__c> rows = Database.query(
      'SELECT ' +
        HEADER_FIELDS +
        ' FROM AXF_OBJ_OnboardingProgress__c WHERE Id = :progressId LIMIT 1',
      AccessLevel.SYSTEM_MODE
    );
    return hydrate(rows[0]);
  }

  private Header hydrate(AXF_OBJ_OnboardingProgress__c rec) {
    Header h = new Header();
    h.record = rec;
    for (AXF_OBJ_OnboardingStep__c s : rec.Steps__r) {
      h.steps.put(parseStep(s.AXF_OST_PKL_StepKey__c), s);
    }
    // tolerate a step catalogue that grew after this record was created
    for (StepKey k : STEP_ORDER) {
      if (!h.steps.containsKey(k)) {
        AXF_OBJ_OnboardingStep__c s = new AXF_OBJ_OnboardingStep__c(
          AXF_OST_MDR_Progress__c = rec.Id,
          AXF_OST_PKL_StepKey__c = k.name(),
          AXF_OST_PKL_Status__c = 'NOT_STARTED',
          AXF_OST_CHK_Optional__c = OPTIONAL_STEPS.contains(k),
          AXF_OST_EXI_StepUid__c = rec.AXF_ONB_EXI_ScopeKey__c + ':' + k.name(),
          AXF_OST_NUM_Attempt__c = 0
        );
        Database.insert(s, AccessLevel.SYSTEM_MODE);
        h.steps.put(k, s);
      }
    }
    return h;
  }

  private String deriveCurrentStep(Header h) {
    for (StepKey k : STEP_ORDER) {
      String st = h.steps.get(k).AXF_OST_PKL_Status__c;
      Boolean settled = st == 'CONFIRMED' || st == 'SKIPPED';
      if (!settled) {
        return k.name();
      }
    }
    return 'REVIEW';
  }

  private Boolean anyStale(Header h) {
    for (AXF_OBJ_OnboardingStep__c s : h.steps.values()) {
      if (s.AXF_OST_PKL_Status__c == 'STALE') {
        return true;
      }
    }
    return false;
  }

  private Boolean versionMatches(Header h, Integer expected) {
    // null expected => caller did not read first; be strict (AC6)
    return expected != null && expected == h.version();
  }

  private OnboardingState forbidden() {
    OnboardingState s = new OnboardingState();
    s.forbidden = true;
    s.outcome = Outcome.FORBIDDEN.name();
    s.message = MSG_FORBIDDEN;
    return s;
  }

  private OnboardingState toState(Header h, Outcome outcome, String message) {
    OnboardingState s = new OnboardingState();
    s.progressId = h.record.Id;
    s.status = h.record.AXF_ONB_PKL_Status__c;
    s.currentStep = h.record.AXF_ONB_PKL_CurrentStep__c;
    s.version = h.version();
    s.staleDetected = anyStale(h);
    s.notice = h.record.AXF_ONB_TXT_Notice__c;
    s.lastReconciledAt = h.record.AXF_ONB_DTM_LastReconciledAt__c;
    s.completedAt = h.record.AXF_ONB_DTM_CompletedAt__c;
    s.outcome = outcome.name();
    s.message = message;
    for (StepKey k : STEP_ORDER) {
      AXF_OBJ_OnboardingStep__c row = h.steps.get(k);
      StepView v = new StepView();
      v.stepKey = k.name();
      v.status = row.AXF_OST_PKL_Status__c;
      v.optional = row.AXF_OST_CHK_Optional__c == true;
      v.evidenceRef = row.AXF_OST_TXT_EvidenceRef__c;
      v.attempt = safeInt(row.AXF_OST_NUM_Attempt__c);
      v.confirmedAt = row.AXF_OST_DTM_ConfirmedAt__c;
      v.note = row.AXF_OST_TXT_Note__c;
      v.correlationId = row.AXF_OST_TXT_CorrelationId__c;
      s.steps.add(v);
    }
    return s;
  }

  @TestVisible
  private static String firstSecretHit(String value) {
    if (String.isBlank(value)) {
      return null;
    }
    if (SECRET_WORDS.matcher(value).find()) {
      return 'word';
    }
    Matcher m = SECRET_BLOB.matcher(value.trim());
    if (m.matches()) {
      // whole value is one long opaque blob and not a plain 18-char Salesforce Id
      if (value.trim().length() != 15 && value.trim().length() != 18) {
        return 'blob';
      }
    }
    return null;
  }

  private static StepKey parseStep(String raw) {
    StepKey k = raw == null ? null : NAME_TO_STEP.get(raw.trim());
    if (k == null) {
      throw new IllegalArgumentException(MSG_UNKNOWN_STEP);
    }
    return k;
  }

  private static Integer safeInt(Decimal d) {
    return d == null ? 0 : d.intValue();
  }
}
