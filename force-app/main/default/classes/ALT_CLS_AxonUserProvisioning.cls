/**
 * @description "Adicionar pessoa e dar acesso ao Axon" (AXF-82). Cria ou vincula
 * um User a um Person Account e aplica o nível de acesso Axon, decompondo a
 * operação na cadeia idempotente encadeada do G3-4:
 *
 *   CREATE_OR_LINK_PERSON -> CREATE_OR_LINK_USER -> ASSIGN_ROLE -> ASSIGN_PSG
 *   -> SET_OWNER_SYNC -> ACTIVATE -> DONE
 *
 * Contrato: ARCHITECTURE-SPINE.md "Fechamento G3" (G3-3 licença, G3-4 Mixed DML,
 * G3-5 idioma) + "Fechamento G1/G2"; disposição de ownership 28/08/2026. AXF-82.
 *
 * - Setup DML (User, PermissionSetAssignment, UserRole) e non-setup DML
 *   (Account/Person Account, o próprio objeto AXF_OBJ_AccessProvisioning__c)
 *   NUNCA no mesmo contexto: cada execução de Queueable faz um só tipo. As
 *   etapas de setup gravam o checkpoint numa fase COMMIT separada (só toca o
 *   objeto custom).
 * - Idempotente: chave `AXF_APV_EXI_RequestKey__c` por pessoa+escopo. Retomar
 *   nunca cria 2º User / 2ª Person Account.
 * - Autoridade: o chamador precisa de `AXF_CanConfigure`. Ser System
 *   Administrator não basta (sem auto-elevação — G3-1).
 * - Nível de acesso aplicado por `ALT_CLS_AxonAccessProvisioning` (AXF-7):
 *   ALL_DATA -> Gestor Financeiro, OWN_DATA -> Participante.
 * - Ativação e senha usam o fluxo nativo do Salesforce; o Axon nunca gera,
 *   guarda ou envia senha.
 * - Execução no contexto do configurador (System Administrator) por ora; a
 *   migração para o usuário de serviço `AXF_PS_Provisioning` (G3-6) é AXF-77/91.
 */
public with sharing class ALT_CLS_AxonUserProvisioning {
  public enum LinkMode {
    CREATE,
    LINK
  }
  public enum AccessScope {
    OWN_DATA,
    ALL_DATA
  }
  public enum Outcome {
    STARTED,
    RESUMED,
    FORBIDDEN,
    INVALID,
    BLOCKED_LICENSE,
    CONFLICT,
    ALREADY_DONE,
    NOT_FOUND
  }

  private static final List<String> STEP_ORDER = new List<String>{
    'CREATE_OR_LINK_PERSON',
    'CREATE_OR_LINK_USER',
    'ASSIGN_ROLE',
    'ASSIGN_PSG',
    'SET_OWNER_SYNC',
    'ACTIVATE',
    'DONE'
  };
  // Steps whose work is setup DML — their checkpoint is written in a COMMIT phase.
  private static final Set<String> SETUP_STEPS = new Set<String>{
    'CREATE_OR_LINK_USER',
    'ASSIGN_ROLE',
    'ASSIGN_PSG',
    'ACTIVATE'
  };

  private static final String MIN_PROFILE = 'Minimum Access - Salesforce';
  private static final String RT_PERSON = 'AXF_Person';

  @TestVisible
  private static final String MSG_FORBIDDEN = 'Voce nao tem autorizacao para adicionar pessoas ou conceder acesso ao Axon.';
  @TestVisible
  private static final String MSG_NOT_PERSON = 'Selecione uma pessoa (Person Account) ja cadastrada.';
  @TestVisible
  private static final String MSG_NEED_EMAIL = 'Informe um e-mail para criar o usuario.';
  @TestVisible
  private static final String MSG_NEED_USER = 'Selecione o usuario existente a vincular.';
  @TestVisible
  private static final String MSG_USER_INACTIVE = 'O usuario selecionado esta inativo. Reative-o pelo fluxo padrao antes de vincular.';
  @TestVisible
  private static final String MSG_USER_LINKED = 'Esse usuario ja esta vinculado a outra pessoa. Nomes ou e-mails iguais nao autorizam reassociacao.';
  @TestVisible
  private static final String MSG_NO_LICENSE = 'Nao ha licenca Salesforce disponivel para criar o usuario. Libere uma licenca e retome.';
  @TestVisible
  private static final String MSG_STARTED = 'Provisionamento iniciado.';
  @TestVisible
  private static final String MSG_RESUMED = 'Provisionamento retomado da etapa pendente.';
  @TestVisible
  private static final String MSG_DONE = 'Acesso concluido.';

  @TestVisible
  private static Boolean canConfigureOverride;

  private Boolean callerCanConfigure() {
    if (canConfigureOverride != null) {
      return canConfigureOverride;
    }
    return FeatureManagement.checkPermission('AXF_CanConfigure');
  }

  // ---- input / output ----

  public class StartInput {
    @AuraEnabled
    public Id personId;
    @AuraEnabled
    public String mode; // CREATE | LINK
    @AuraEnabled
    public String scope; // OWN_DATA | ALL_DATA
    @AuraEnabled
    public String name; // display name shown for review
    @AuraEnabled
    public String email; // CREATE
    @AuraEnabled
    public Id existingUserId; // LINK
  }

  public class Result {
    @AuraEnabled
    public Id provisioningId;
    @AuraEnabled
    public String outcome;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String currentStep;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Id linkedUserId;
  }

  // ---- public API ----

  public Result start(StartInput input) {
    Result r = new Result();
    if (!callerCanConfigure()) {
      return fail(r, Outcome.FORBIDDEN, MSG_FORBIDDEN);
    }
    if (input == null || input.personId == null) {
      return fail(r, Outcome.INVALID, MSG_NOT_PERSON);
    }

    LinkMode mode = parseEnum(input.mode, LinkMode.values());
    AccessScope scope = parseEnum(input.scope, AccessScope.values());
    if (mode == null || scope == null) {
      return fail(r, Outcome.INVALID, MSG_NOT_PERSON);
    }

    Account person = readPerson(input.personId);
    if (person == null) {
      return fail(r, Outcome.INVALID, MSG_NOT_PERSON);
    }

    if (mode == LinkMode.CREATE && String.isBlank(input.email)) {
      return fail(r, Outcome.INVALID, MSG_NEED_EMAIL);
    }
    if (mode == LinkMode.LINK) {
      Result linkCheck = validateExistingUser(input.existingUserId, r);
      if (linkCheck != null) {
        return linkCheck;
      }
    }
    if (mode == LinkMode.CREATE && !hasSalesforceLicense()) {
      return fail(r, Outcome.BLOCKED_LICENSE, MSG_NO_LICENSE);
    }

    String requestKey = buildRequestKey(input.personId, scope);
    AXF_OBJ_AccessProvisioning__c existing = findByKey(requestKey);
    if (existing != null) {
      return resumeRecord(existing, r);
    }

    AXF_OBJ_AccessProvisioning__c apv = new AXF_OBJ_AccessProvisioning__c(
      AXF_APV_LKP_Person__c = input.personId,
      AXF_APV_LKP_User__c = mode == LinkMode.LINK ? input.existingUserId : null,
      AXF_APV_PKL_Mode__c = mode.name(),
      AXF_APV_PKL_Scope__c = scope.name(),
      AXF_APV_PKL_CurrentStep__c = 'CREATE_OR_LINK_PERSON',
      AXF_APV_PKL_Status__c = 'PENDING',
      AXF_APV_EXI_RequestKey__c = requestKey,
      AXF_APV_TXT_TargetEmail__c = input.email,
      AXF_APV_TXT_TargetName__c = input.name,
      AXF_APV_TXT_Message__c = MSG_STARTED,
      AXF_APV_TAL_StepLog__c = '[]'
    );
    Database.insert(apv, AccessLevel.USER_MODE);

    enqueueStep(apv.Id);

    r.provisioningId = apv.Id;
    r.outcome = Outcome.STARTED.name();
    r.status = 'PENDING';
    r.currentStep = 'CREATE_OR_LINK_PERSON';
    r.message = MSG_STARTED;
    return r;
  }

  public Result resume(Id provisioningId) {
    Result r = new Result();
    if (!callerCanConfigure()) {
      return fail(r, Outcome.FORBIDDEN, MSG_FORBIDDEN);
    }
    AXF_OBJ_AccessProvisioning__c apv = readApv(provisioningId);
    if (apv == null) {
      return fail(r, Outcome.NOT_FOUND, MSG_NOT_PERSON);
    }
    return resumeRecord(apv, r);
  }

  public Result getStatus(Id provisioningId) {
    Result r = new Result();
    AXF_OBJ_AccessProvisioning__c apv = readApv(provisioningId);
    if (apv == null) {
      return fail(r, Outcome.NOT_FOUND, MSG_NOT_PERSON);
    }
    r.provisioningId = apv.Id;
    r.status = apv.AXF_APV_PKL_Status__c;
    r.currentStep = apv.AXF_APV_PKL_CurrentStep__c;
    r.message = apv.AXF_APV_TXT_Message__c;
    r.linkedUserId = apv.AXF_APV_LKP_User__c;
    r.outcome = apv.AXF_APV_PKL_CurrentStep__c == 'DONE'
      ? Outcome.ALREADY_DONE.name()
      : null;
    return r;
  }

  // ---- resume helper ----

  private Result resumeRecord(AXF_OBJ_AccessProvisioning__c apv, Result r) {
    r.provisioningId = apv.Id;
    r.linkedUserId = apv.AXF_APV_LKP_User__c;
    r.status = apv.AXF_APV_PKL_Status__c;
    r.currentStep = apv.AXF_APV_PKL_CurrentStep__c;
    if (apv.AXF_APV_PKL_CurrentStep__c == 'DONE') {
      r.outcome = Outcome.ALREADY_DONE.name();
      r.message = MSG_DONE;
      return r;
    }
    if (apv.AXF_APV_PKL_Status__c == 'FAILED_TERMINAL') {
      r.outcome = Outcome.CONFLICT.name();
      r.message = apv.AXF_APV_TXT_Message__c;
      return r;
    }
    enqueueStep(apv.Id);
    r.outcome = Outcome.RESUMED.name();
    r.message = MSG_RESUMED;
    return r;
  }

  // ---- chained Queueable ----

  private static void enqueueStep(Id apvId) {
    if (Test.isRunningTest()) {
      return; // tests drive steps synchronously via driveSync()
    }
    System.enqueueJob(new Chain('STEP', apvId, null, null, null));
  }

  public class Chain implements Queueable {
    private String phase; // STEP | COMMIT
    private Id apvId;
    private String nextStep;
    private String failStatus;
    private String message;

    public Chain(
      String phase,
      Id apvId,
      String nextStep,
      String failStatus,
      String message
    ) {
      this.phase = phase;
      this.apvId = apvId;
      this.nextStep = nextStep;
      this.failStatus = failStatus;
      this.message = message;
    }

    public void execute(QueueableContext ctx) {
      if (phase == 'COMMIT') {
        commitCheckpoint(apvId, nextStep, failStatus, message);
        Boolean canChain =
          Limits.getQueueableJobs() < Limits.getLimitQueueableJobs();
        if (failStatus == null && nextStep != 'DONE' && canChain) {
          System.enqueueJob(new Chain('STEP', apvId, null, null, null));
        }
        return;
      }
      runStep(apvId);
    }
  }

  public class StepResult {
    public String message;
    public Id producedUserId;
    public StepResult(String message) {
      this.message = message;
    }
    public StepResult(String message, Id producedUserId) {
      this.message = message;
      this.producedUserId = producedUserId;
    }
  }

  /**
   * @description Runs exactly one step (one DML kind). Setup steps enqueue a
   * COMMIT to persist the checkpoint; non-setup steps persist inline.
   */
  @TestVisible
  private static void runStep(Id apvId) {
    AXF_OBJ_AccessProvisioning__c apv = readApv(apvId);
    if (apv == null || apv.AXF_APV_PKL_CurrentStep__c == 'DONE') {
      return;
    }
    String step = apv.AXF_APV_PKL_CurrentStep__c;
    String nextStep = STEP_ORDER[STEP_ORDER.indexOf(step) + 1];
    StepResult sr;
    try {
      sr = execStep(apv, step);
    } catch (StepException se) {
      commitCheckpoint(
        apvId,
        step,
        se.retryable ? 'FAILED_RETRYABLE' : 'FAILED_TERMINAL',
        se.getMessage(),
        null
      );
      return;
    } catch (Exception e) {
      commitCheckpoint(apvId, step, 'FAILED_RETRYABLE', sanitize(e), null);
      return;
    }

    if (SETUP_STEPS.contains(step) && !Test.isRunningTest()) {
      System.enqueueJob(new Chain('COMMIT', apvId, nextStep, null, sr.message));
      // producedUserId is carried into COMMIT by re-deriving it there via
      // username lookup (resume-safe); no cross-transaction static.
    } else {
      commitCheckpoint(apvId, nextStep, null, sr.message, sr.producedUserId);
    }
  }

  private static void commitCheckpoint(
    Id apvId,
    String nextStep,
    String failStatus,
    String message
  ) {
    commitCheckpoint(apvId, nextStep, failStatus, message, null);
  }

  private static void commitCheckpoint(
    Id apvId,
    String nextStep,
    String failStatus,
    String message,
    Id producedUserId
  ) {
    AXF_OBJ_AccessProvisioning__c apv = readApv(apvId);
    if (apv == null) {
      return;
    }
    apv.AXF_APV_PKL_CurrentStep__c = failStatus == null
      ? nextStep
      : apv.AXF_APV_PKL_CurrentStep__c;
    apv.AXF_APV_PKL_Status__c = failStatus != null
      ? failStatus
      : (nextStep == 'DONE' ? 'SUCCEEDED' : 'RUNNING');
    apv.AXF_APV_TXT_Message__c = message == null
      ? apv.AXF_APV_TXT_Message__c
      : message.abbreviate(255);
    if (producedUserId != null && apv.AXF_APV_LKP_User__c == null) {
      apv.AXF_APV_LKP_User__c = producedUserId;
    }
    apv.AXF_APV_TAL_StepLog__c = appendLog(
      apv.AXF_APV_TAL_StepLog__c,
      apv.AXF_APV_PKL_CurrentStep__c,
      apv.AXF_APV_PKL_Status__c,
      message
    );
    Database.update(apv, AccessLevel.SYSTEM_MODE);
  }

  // ---- step implementations ----

  private static StepResult execStep(
    AXF_OBJ_AccessProvisioning__c apv,
    String step
  ) {
    switch on step {
      when 'CREATE_OR_LINK_PERSON' {
        if (readPersonStatic(apv.AXF_APV_LKP_Person__c) == null) {
          throw new StepException(MSG_NOT_PERSON, false);
        }
        return new StepResult('Pessoa confirmada.');
      }
      when 'CREATE_OR_LINK_USER' {
        return stepCreateOrLinkUser(apv);
      }
      when 'ASSIGN_ROLE' {
        return new StepResult(stepApplyLevel(apv));
      }
      when 'ASSIGN_PSG' {
        return new StepResult(stepVerifyLevel(apv));
      }
      when 'SET_OWNER_SYNC' {
        return new StepResult(stepOwnerSync(apv));
      }
      when 'ACTIVATE' {
        return new StepResult(stepActivate(apv));
      }
      when else {
        return new StepResult(null);
      }
    }
  }

  private static StepResult stepCreateOrLinkUser(
    AXF_OBJ_AccessProvisioning__c apv
  ) {
    if (apv.AXF_APV_PKL_Mode__c == 'LINK') {
      if (apv.AXF_APV_LKP_User__c == null) {
        throw new StepException(MSG_NEED_USER, false);
      }
      return new StepResult(
        'Usuario existente vinculado.',
        apv.AXF_APV_LKP_User__c
      );
    }
    // CREATE
    if (!hasSalesforceLicense()) {
      throw new StepException(MSG_NO_LICENSE, true);
    }
    Id profileId = [SELECT Id FROM Profile WHERE Name = :MIN_PROFILE LIMIT 1]
    .Id;
    String last = apv.AXF_APV_TXT_TargetName__c;
    String first;
    if (String.isNotBlank(last) && last.contains(' ')) {
      first = last.substringBeforeLast(' ');
      last = last.substringAfterLast(' ');
    }
    String alias = (String.isBlank(last) ? 'axf' : last)
      .deleteWhitespace()
      .toLowerCase();
    alias =
      (alias.length() > 5 ? alias.substring(0, 5) : alias) +
      String.valueOf(Crypto.getRandomInteger()).right(3);
    User u = new User(
      ProfileId = profileId,
      LastName = String.isBlank(last) ? 'Axon' : last,
      FirstName = first,
      Email = apv.AXF_APV_TXT_TargetEmail__c,
      Username = buildUsername(apv.AXF_APV_TXT_TargetEmail__c, apv.Id),
      Alias = alias.abbreviate(8),
      TimeZoneSidKey = UserInfo.getTimeZone().getID(),
      LocaleSidKey = 'pt_BR',
      LanguageLocaleKey = 'pt_BR',
      EmailEncodingKey = 'UTF-8',
      IsActive = true
    );
    Database.insert(u, AccessLevel.SYSTEM_MODE);
    // The APV lookup is set in the COMMIT phase (non-setup) via producedUserId,
    // or re-derived from the deterministic username on resume.
    return new StepResult('Usuario criado.', u.Id);
  }

  private static String stepApplyLevel(AXF_OBJ_AccessProvisioning__c apv) {
    Id userId = resolveUserId(apv);
    ALT_CLS_AxonAccessProvisioning.Tier tier = apv.AXF_APV_PKL_Scope__c ==
      'ALL_DATA'
      ? ALT_CLS_AxonAccessProvisioning.Tier.GESTOR
      : ALT_CLS_AxonAccessProvisioning.Tier.PARTICIPANTE;
    // The AXF-7 service does its own AXF_CanConfigure check; this chain runs as
    // the configurator who holds it (start() already validated the caller).
    ALT_CLS_AxonAccessProvisioning svc = new ALT_CLS_AxonAccessProvisioning();
    ALT_CLS_AxonAccessProvisioning.Result res = svc.applyAccessLevel(
      userId,
      tier
    );
    if (
      res.outcome != ALT_CLS_AxonAccessProvisioning.Outcome.SUCCEEDED &&
      res.outcome != ALT_CLS_AxonAccessProvisioning.Outcome.ALREADY_APPLIED
    ) {
      Boolean retry =
        res.outcome == ALT_CLS_AxonAccessProvisioning.Outcome.PENDING;
      throw new StepException(res.message, retry);
    }
    return 'Papel e PSG aplicados (' + tier.name() + ').';
  }

  private static String stepVerifyLevel(AXF_OBJ_AccessProvisioning__c apv) {
    Id userId = resolveUserId(apv);
    Map<Id, String> levels = new ALT_CLS_AxonAccessProvisioning()
      .currentLevels(new Set<Id>{ userId });
    if (levels.get(userId) == 'Sem acesso ao Axon') {
      throw new StepException(
        'O nivel de acesso ainda nao esta efetivo. Retome.',
        true
      );
    }
    return 'Nivel confirmado: ' + levels.get(userId) + '.';
  }

  private static String stepOwnerSync(AXF_OBJ_AccessProvisioning__c apv) {
    Id userId = resolveUserId(apv);
    // Disposição 28/08: Person Account com vínculo validado passa a pertencer ao User.
    Database.update(
      new Account(Id = apv.AXF_APV_LKP_Person__c, OwnerId = userId),
      AccessLevel.SYSTEM_MODE
    );
    apv.AXF_APV_CHK_OwnerSynced__c = true;
    apv.AXF_APV_LKP_User__c = userId;
    Database.update(apv, AccessLevel.SYSTEM_MODE);
    return 'Person Account transferido para o usuario.';
  }

  private static String stepActivate(AXF_OBJ_AccessProvisioning__c apv) {
    if (apv.AXF_APV_PKL_Mode__c == 'LINK') {
      return 'Vinculo concluido (usuario existente nao e reativado aqui).';
    }
    // CREATE: user was inserted active; activation e-mail / senha sao nativos.
    return 'Usuario ativo; definicao de senha pelo fluxo padrao do Salesforce.';
  }

  // ---- helpers ----

  private static Id resolveUserId(AXF_OBJ_AccessProvisioning__c apv) {
    if (apv.AXF_APV_LKP_User__c != null) {
      return apv.AXF_APV_LKP_User__c;
    }
    // CREATE + resume: the user was created with a deterministic username.
    String prefix = 'axf82.' + apv.Id + '@%';
    List<User> u = [SELECT Id FROM User WHERE Username LIKE :prefix LIMIT 1];
    if (u.isEmpty()) {
      throw new StepException(
        'Usuario nao encontrado para esta requisicao.',
        false
      );
    }
    return u[0].Id;
  }

  private Result validateExistingUser(Id userId, Result r) {
    if (userId == null) {
      return fail(r, Outcome.INVALID, MSG_NEED_USER);
    }
    List<User> users = [
      SELECT Id, IsActive
      FROM User
      WHERE Id = :userId
      WITH USER_MODE
      LIMIT 1
    ];
    if (users.isEmpty()) {
      return fail(r, Outcome.INVALID, MSG_NEED_USER);
    }
    if (!users[0].IsActive) {
      return fail(r, Outcome.INVALID, MSG_USER_INACTIVE);
    }
    Integer linked = [
      SELECT COUNT()
      FROM AXF_OBJ_AccessProvisioning__c
      WHERE AXF_APV_LKP_User__c = :userId AND AXF_APV_CHK_OwnerSynced__c = TRUE
    ];
    if (linked > 0) {
      return fail(r, Outcome.CONFLICT, MSG_USER_LINKED);
    }
    return null;
  }

  @TestVisible
  private static Boolean licenseAvailableOverride;

  private static Boolean hasSalesforceLicense() {
    if (licenseAvailableOverride != null) {
      return licenseAvailableOverride;
    }
    for (UserLicense ul : [
      SELECT UsedLicenses, TotalLicenses
      FROM UserLicense
      WHERE Name = 'Salesforce' AND Status = 'Active'
    ]) {
      if (ul.UsedLicenses < ul.TotalLicenses) {
        return true;
      }
    }
    return false;
  }

  private static String buildUsername(String email, Id apvId) {
    return 'axf82.' + apvId + '@' + orgUsernameSuffix();
  }

  private static String orgUsernameSuffix() {
    String orgId = UserInfo.getOrganizationId().toLowerCase();
    return 'axon.' + orgId + '.invalid';
  }

  @TestVisible
  private static String buildRequestKey(Id personId, AccessScope scope) {
    Blob b = Crypto.generateDigest(
      'SHA-256',
      Blob.valueOf('axf82:v1:' + personId + ':' + scope.name())
    );
    return EncodingUtil.convertToHex(b);
  }

  private Account readPerson(Id personId) {
    return readPersonStatic(personId);
  }

  private static Account readPersonStatic(Id personId) {
    if (personId == null || personId.getSobjectType() != Account.SObjectType) {
      return null;
    }
    List<Account> a = [
      SELECT Id, OwnerId, IsPersonAccount, RecordType.DeveloperName
      FROM Account
      WHERE Id = :personId AND RecordType.DeveloperName = :RT_PERSON
      WITH USER_MODE
      LIMIT 1
    ];
    return a.isEmpty() ? null : a[0];
  }

  private AXF_OBJ_AccessProvisioning__c findByKey(String requestKey) {
    List<AXF_OBJ_AccessProvisioning__c> rows = [
      SELECT
        Id,
        AXF_APV_LKP_Person__c,
        AXF_APV_LKP_User__c,
        AXF_APV_PKL_Mode__c,
        AXF_APV_PKL_Scope__c,
        AXF_APV_PKL_CurrentStep__c,
        AXF_APV_PKL_Status__c,
        AXF_APV_TXT_Message__c,
        AXF_APV_TXT_TargetEmail__c,
        AXF_APV_TXT_TargetName__c,
        AXF_APV_CHK_OwnerSynced__c,
        AXF_APV_TAL_StepLog__c
      FROM AXF_OBJ_AccessProvisioning__c
      WHERE AXF_APV_EXI_RequestKey__c = :requestKey
      WITH USER_MODE
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0];
  }

  @TestVisible
  private static AXF_OBJ_AccessProvisioning__c readApv(Id apvId) {
    if (apvId == null) {
      return null;
    }
    List<AXF_OBJ_AccessProvisioning__c> rows = [
      SELECT
        Id,
        AXF_APV_LKP_Person__c,
        AXF_APV_LKP_User__c,
        AXF_APV_PKL_Mode__c,
        AXF_APV_PKL_Scope__c,
        AXF_APV_PKL_CurrentStep__c,
        AXF_APV_PKL_Status__c,
        AXF_APV_TXT_Message__c,
        AXF_APV_TXT_TargetEmail__c,
        AXF_APV_TXT_TargetName__c,
        AXF_APV_CHK_OwnerSynced__c,
        AXF_APV_TAL_StepLog__c
      FROM AXF_OBJ_AccessProvisioning__c
      WHERE Id = :apvId
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0];
  }

  private static String appendLog(
    String current,
    String step,
    String status,
    String message
  ) {
    List<Object> log;
    try {
      log = (List<Object>) JSON.deserializeUntyped(
        String.isBlank(current) ? '[]' : current
      );
    } catch (Exception e) {
      log = new List<Object>();
    }
    log.add(
      new Map<String, Object>{
        'at' => Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''),
        'step' => step,
        'status' => status,
        'message' => message
      }
    );
    String out = JSON.serialize(log);
    return out.length() > 32000 ? out.substring(out.length() - 32000) : out;
  }

  private static String sanitize(Exception e) {
    return e.getTypeName() + ': ' + e.getMessage().abbreviate(200);
  }

  private static LinkMode parseEnum(String raw, List<LinkMode> values) {
    if (String.isBlank(raw)) {
      return null;
    }
    String n = raw.trim().toUpperCase();
    for (LinkMode m : values) {
      if (m.name() == n) {
        return m;
      }
    }
    return null;
  }

  private static AccessScope parseEnum(String raw, List<AccessScope> values) {
    if (String.isBlank(raw)) {
      return null;
    }
    String n = raw.trim().toUpperCase();
    for (AccessScope s : values) {
      if (s.name() == n) {
        return s;
      }
    }
    return null;
  }

  private static Result fail(Result r, Outcome outcome, String message) {
    r.outcome = outcome.name();
    r.message = message;
    return r;
  }

  public class StepException extends Exception {
    public Boolean retryable = true;
    public StepException(String message, Boolean retryable) {
      this(message);
      this.retryable = retryable;
    }
  }

  // ---- test seam: run the whole chain synchronously (bypasses Queueable) ----

  @TestVisible
  private static void driveSync(Id apvId) {
    for (Integer guard = 0; guard < 10; guard++) {
      AXF_OBJ_AccessProvisioning__c apv = readApv(apvId);
      if (
        apv == null ||
        apv.AXF_APV_PKL_CurrentStep__c == 'DONE' ||
        apv.AXF_APV_PKL_Status__c == 'FAILED_TERMINAL' ||
        apv.AXF_APV_PKL_Status__c == 'FAILED_RETRYABLE'
      ) {
        return;
      }
      System.runAs(new User(Id = UserInfo.getUserId())) {
        runStep(apvId);
      }
    }
  }
}
