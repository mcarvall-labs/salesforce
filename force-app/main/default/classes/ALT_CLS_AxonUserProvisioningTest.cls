/**
 * @description Tests for ALT_CLS_AxonUserProvisioning (AXF-82). Exercita a cadeia
 * G3-4 completa via `driveSync` (bypassa Queueable), com o configurador real
 * (System Administrator + AXF_PSG_GestorFinanceiro para `AXF_CanConfigure`).
 */
@IsTest(isParallel=false)
private class ALT_CLS_AxonUserProvisioningTest {
  private static void licenseFree(Boolean value) {
    ALT_CLS_AxonUserProvisioning.licenseAvailableOverride = value;
  }

  private static User configurator() {
    Profile admin = [
      SELECT Id
      FROM Profile
      WHERE Name = 'System Administrator'
      LIMIT 1
    ];
    PermissionSetGroup psg = [
      SELECT Id, Status
      FROM PermissionSetGroup
      WHERE DeveloperName = 'AXF_PSG_GestorFinanceiro'
      LIMIT 1
    ];
    if (psg.Status != 'Updated') {
      Test.calculatePermissionSetGroup(psg.Id);
    }
    Id psgId = psg.Id;
    User u = new User(
      ProfileId = admin.Id,
      LastName = 'Configurador AXF82',
      Email = 'axf82.cfg@example.com',
      Username = 'axf82.cfg.' +
        Crypto.getRandomInteger() +
        '@example.com.invalid',
      Alias = 'axf82c',
      TimeZoneSidKey = 'America/Sao_Paulo',
      LocaleSidKey = 'pt_BR',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'pt_BR'
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert u;
      insert new PermissionSetAssignment(
        AssigneeId = u.Id,
        PermissionSetGroupId = psgId
      );
    }
    return u;
  }

  private static Id personAccount(String lastName) {
    Id rt = Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
      .getRecordTypeInfosByDeveloperName()
      .get('AXF_Person')
      .getRecordTypeId();
    Account a = new Account(LastName = lastName, RecordTypeId = rt);
    insert a;
    return a.Id;
  }

  private static ALT_CLS_AxonUserProvisioning.StartInput createInput(
    Id personId,
    String scope
  ) {
    ALT_CLS_AxonUserProvisioning.StartInput si = new ALT_CLS_AxonUserProvisioning.StartInput();
    si.personId = personId;
    si.mode = 'CREATE';
    si.scope = scope;
    si.name = 'Maria Testadora';
    si.email = 'maria.testadora@example.com';
    return si;
  }

  @IsTest
  static void startIsForbiddenWithoutAuthority() {
    ALT_CLS_AxonUserProvisioning.canConfigureOverride = false;
    Id personId;
    User cfg = configurator();
    System.runAs(cfg) {
      personId = personAccount('Silva');
    }
    ALT_CLS_AxonUserProvisioning svc = new ALT_CLS_AxonUserProvisioning();
    ALT_CLS_AxonUserProvisioning.Result r = svc.start(
      createInput(personId, 'OWN_DATA')
    );
    System.assertEquals('FORBIDDEN', r.outcome);
  }

  @IsTest
  static void rejectsNonPersonAccount() {
    User cfg = configurator();
    System.runAs(cfg) {
      Account biz = new Account(Name = 'Empresa X');
      insert biz;

      ALT_CLS_AxonUserProvisioning.Result r = new ALT_CLS_AxonUserProvisioning()
        .start(createInput(biz.Id, 'OWN_DATA'));
      System.assertEquals('INVALID', r.outcome, r.message);
    }
  }

  @IsTest
  static void createChainGrantsParticipantAndTransfersOwnership() {
    User cfg = configurator();
    licenseFree(true);
    Test.startTest();
    System.runAs(cfg) {
      Id personId = personAccount('Souza');
      ALT_CLS_AxonUserProvisioning svc = new ALT_CLS_AxonUserProvisioning();
      ALT_CLS_AxonUserProvisioning.Result r = svc.start(
        createInput(personId, 'OWN_DATA')
      );
      System.assertEquals('STARTED', r.outcome, r.message);

      ALT_CLS_AxonUserProvisioning.driveSync(r.provisioningId);

      AXF_OBJ_AccessProvisioning__c apv = ALT_CLS_AxonUserProvisioning.readApv(
        r.provisioningId
      );
      System.assertEquals(
        'DONE',
        apv.AXF_APV_PKL_CurrentStep__c,
        apv.AXF_APV_TXT_Message__c
      );
      System.assertEquals('SUCCEEDED', apv.AXF_APV_PKL_Status__c);
      System.assertNotEquals(null, apv.AXF_APV_LKP_User__c, 'user linked');
      System.assertEquals(true, apv.AXF_APV_CHK_OwnerSynced__c);

      User created = [
        SELECT IsActive, Profile.Name, LanguageLocaleKey
        FROM User
        WHERE Id = :apv.AXF_APV_LKP_User__c
      ];
      System.assertEquals(true, created.IsActive);
      System.assertEquals('Minimum Access - Salesforce', created.Profile.Name);
      System.assertEquals('pt_BR', created.LanguageLocaleKey);

      Account person = [
        SELECT OwnerId
        FROM Account
        WHERE Id = :personId
      ];
      System.assertEquals(
        apv.AXF_APV_LKP_User__c,
        person.OwnerId,
        'owner transferred'
      );

      Map<Id, String> lvl = new ALT_CLS_AxonAccessProvisioning()
        .currentLevels(new Set<Id>{ apv.AXF_APV_LKP_User__c });
      System.assertEquals('Participante', lvl.get(apv.AXF_APV_LKP_User__c));
    }
    Test.stopTest();
  }

  @IsTest
  static void allDataScopeGrantsGestor() {
    User cfg = configurator();
    licenseFree(true);
    Test.startTest();
    System.runAs(cfg) {
      Id personId = personAccount('Dias');
      ALT_CLS_AxonUserProvisioning.Result r = new ALT_CLS_AxonUserProvisioning()
        .start(createInput(personId, 'ALL_DATA'));
      ALT_CLS_AxonUserProvisioning.driveSync(r.provisioningId);

      AXF_OBJ_AccessProvisioning__c apv = ALT_CLS_AxonUserProvisioning.readApv(
        r.provisioningId
      );
      System.assertEquals(
        'DONE',
        apv.AXF_APV_PKL_CurrentStep__c,
        apv.AXF_APV_TXT_Message__c
      );
      Map<Id, String> lvl = new ALT_CLS_AxonAccessProvisioning()
        .currentLevels(new Set<Id>{ apv.AXF_APV_LKP_User__c });
      System.assertEquals(
        'Gestor Financeiro',
        lvl.get(apv.AXF_APV_LKP_User__c)
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void repeatSamePersonScopeDoesNotDuplicate() {
    User cfg = configurator();
    licenseFree(true);
    Test.startTest();
    System.runAs(cfg) {
      Id personId = personAccount('Alves');
      ALT_CLS_AxonUserProvisioning svc = new ALT_CLS_AxonUserProvisioning();
      ALT_CLS_AxonUserProvisioning.Result first = svc.start(
        createInput(personId, 'OWN_DATA')
      );
      ALT_CLS_AxonUserProvisioning.driveSync(first.provisioningId);

      ALT_CLS_AxonUserProvisioning.Result again = svc.start(
        createInput(personId, 'OWN_DATA')
      );
      System.assertEquals('ALREADY_DONE', again.outcome);
      System.assertEquals(
        first.provisioningId,
        again.provisioningId,
        'same request record'
      );
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM AXF_OBJ_AccessProvisioning__c
          WHERE AXF_APV_LKP_Person__c = :personId
        ],
        'no 2nd request'
      );
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM User
          WHERE Username LIKE :('axf82.' + first.provisioningId + '@%')
        ],
        'no 2nd user for this request'
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void createIsBlockedWhenNoSalesforceLicense() {
    User cfg = configurator();
    licenseFree(false);
    System.runAs(cfg) {
      Id personId = personAccount('Prado');
      ALT_CLS_AxonUserProvisioning.Result r = new ALT_CLS_AxonUserProvisioning()
        .start(createInput(personId, 'OWN_DATA'));
      System.assertEquals('BLOCKED_LICENSE', r.outcome, r.message);
      System.assertEquals(
        0,
        [SELECT COUNT() FROM AXF_OBJ_AccessProvisioning__c],
        'nothing created'
      );
    }
  }

  @IsTest
  static void linkInactiveUserIsRejected() {
    User cfg = configurator();
    User target;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
      target = new User(
        ProfileId = p.Id,
        LastName = 'Inativo',
        Email = 'axf82.inativo@example.com',
        Username = 'axf82.inativo.' +
          Crypto.getRandomInteger() +
          '@example.com.invalid',
        Alias = 'axf82i',
        IsActive = false,
        TimeZoneSidKey = 'America/Sao_Paulo',
        LocaleSidKey = 'pt_BR',
        EmailEncodingKey = 'UTF-8',
        LanguageLocaleKey = 'pt_BR'
      );
      insert target;
    }
    System.runAs(cfg) {
      Id personId = personAccount('Faria');
      ALT_CLS_AxonUserProvisioning.StartInput si = new ALT_CLS_AxonUserProvisioning.StartInput();
      si.personId = personId;
      si.mode = 'LINK';
      si.scope = 'OWN_DATA';
      si.existingUserId = target.Id;

      ALT_CLS_AxonUserProvisioning.Result r = new ALT_CLS_AxonUserProvisioning()
        .start(si);
      System.assertEquals('INVALID', r.outcome);
      System.assert(r.message.contains('inativo'), r.message);
    }
  }

  @IsTest
  static void getStatusReportsNotFoundForUnknown() {
    User cfg = configurator();
    System.runAs(cfg) {
      ALT_CLS_AxonUserProvisioning.Result r = new ALT_CLS_AxonUserProvisioning()
        .getStatus('a0T000000000000AAA');
      System.assertEquals('NOT_FOUND', r.outcome);
    }
  }

  @IsTest
  static void linkExistingUserRunsChainAndSyncsOwner() {
    User cfg = configurator();
    User target;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Profile admin = [
        SELECT Id
        FROM Profile
        WHERE Name = 'System Administrator'
        LIMIT 1
      ];
      target = new User(
        ProfileId = admin.Id,
        LastName = 'Alvo Vinculo',
        Email = 'axf82.alvo@example.com',
        Username = 'axf82.alvo.' +
          Crypto.getRandomInteger() +
          '@example.com.invalid',
        Alias = 'axf82a',
        TimeZoneSidKey = 'America/Sao_Paulo',
        LocaleSidKey = 'pt_BR',
        EmailEncodingKey = 'UTF-8',
        LanguageLocaleKey = 'pt_BR'
      );
      insert target;
    }

    Test.startTest();
    System.runAs(cfg) {
      Id personId = personAccount('Nunes');
      ALT_CLS_AxonUserProvisioning.StartInput si = new ALT_CLS_AxonUserProvisioning.StartInput();
      si.personId = personId;
      si.mode = 'LINK';
      si.scope = 'ALL_DATA';
      si.existingUserId = target.Id;

      ALT_CLS_AxonUserProvisioning svc = new ALT_CLS_AxonUserProvisioning();
      ALT_CLS_AxonUserProvisioning.Result r = svc.start(si);
      System.assertEquals('STARTED', r.outcome, r.message);
      ALT_CLS_AxonUserProvisioning.driveSync(r.provisioningId);

      AXF_OBJ_AccessProvisioning__c apv = ALT_CLS_AxonUserProvisioning.readApv(
        r.provisioningId
      );
      System.assertEquals(
        'DONE',
        apv.AXF_APV_PKL_CurrentStep__c,
        apv.AXF_APV_TXT_Message__c
      );
      System.assertEquals(target.Id, apv.AXF_APV_LKP_User__c);

      Account person = [SELECT OwnerId FROM Account WHERE Id = :personId];
      System.assertEquals(
        target.Id,
        person.OwnerId,
        'owner transferred to linked user'
      );

      ALT_CLS_AxonUserProvisioning.Result status = svc.getStatus(
        r.provisioningId
      );
      System.assertEquals('ALREADY_DONE', status.outcome);
      System.assertEquals(target.Id, status.linkedUserId);
    }
    Test.stopTest();
  }

  @IsTest
  static void rejectsInvalidModeAndScope() {
    User cfg = configurator();
    System.runAs(cfg) {
      Id personId = personAccount('Garbage');
      ALT_CLS_AxonUserProvisioning.StartInput si = new ALT_CLS_AxonUserProvisioning.StartInput();
      si.personId = personId;
      si.mode = 'NOPE';
      si.scope = 'NOPE';
      System.assertEquals(
        'INVALID',
        new ALT_CLS_AxonUserProvisioning().start(si).outcome
      );
    }
  }

  @IsTest
  static void chainQueueablePhasesAreCallable() {
    User cfg = configurator();
    licenseFree(true);
    System.runAs(cfg) {
      Id personId = personAccount('Chain');
      ALT_CLS_AxonUserProvisioning.Result r = new ALT_CLS_AxonUserProvisioning()
        .start(createInput(personId, 'OWN_DATA'));
      // exercise the Queueable branches directly (chaining does not run in tests)
      new ALT_CLS_AxonUserProvisioning.Chain(
          'STEP',
          r.provisioningId,
          null,
          null,
          null
        )
        .execute(null);
      new ALT_CLS_AxonUserProvisioning.Chain(
          'COMMIT',
          r.provisioningId,
          'CREATE_OR_LINK_USER',
          null,
          'ok'
        )
        .execute(null);
      System.assertNotEquals(
        null,
        ALT_CLS_AxonUserProvisioning.readApv(r.provisioningId)
      );
    }
  }

  @IsTest
  static void createdParticipantHasScopedEffectiveAccess() {
    User cfg = configurator();
    licenseFree(true);
    Id foreignAccId;
    Id ownPersonId;
    Id linkedUserId;

    Test.startTest();
    System.runAs(cfg) {
      foreignAccId = personAccount('Estranho'); // stays owned by the configurator
      ownPersonId = personAccount('DonoNovo');
      ALT_CLS_AxonUserProvisioning.Result r = new ALT_CLS_AxonUserProvisioning()
        .start(createInput(ownPersonId, 'OWN_DATA'));
      ALT_CLS_AxonUserProvisioning.driveSync(r.provisioningId);
      linkedUserId = ALT_CLS_AxonUserProvisioning.readApv(r.provisioningId)
        .AXF_APV_LKP_User__c;
    }
    Test.stopTest();

    System.assertNotEquals(null, linkedUserId, 'user created');
    User participant = [SELECT Id FROM User WHERE Id = :linkedUserId];
    System.runAs(participant) {
      System.assertEquals(
        false,
        FeatureManagement.checkPermission('AXF_CanConfigure'),
        'Participante nao recebe autoridade de configuracao'
      );
      List<Account> mine = [
        SELECT Id
        FROM Account
        WHERE Id = :ownPersonId
        WITH USER_MODE
      ];
      System.assertEquals(
        1,
        mine.size(),
        've o proprio Person Account (owner sincronizado)'
      );

      List<Account> foreign = [
        SELECT Id
        FROM Account
        WHERE Id = :foreignAccId
        WITH USER_MODE
      ];
      System.assertEquals(
        0,
        foreign.size(),
        'nao ve titular de outro dono (OWD Private)'
      );
    }
  }

  @IsTest
  static void createdGestorHasConfigAuthority() {
    User cfg = configurator();
    licenseFree(true);
    Id ownPersonId;
    Id linkedUserId;

    Test.startTest();
    System.runAs(cfg) {
      ownPersonId = personAccount('GestorDono');
      ALT_CLS_AxonUserProvisioning.Result r = new ALT_CLS_AxonUserProvisioning()
        .start(createInput(ownPersonId, 'ALL_DATA'));
      ALT_CLS_AxonUserProvisioning.driveSync(r.provisioningId);
      linkedUserId = ALT_CLS_AxonUserProvisioning.readApv(r.provisioningId)
        .AXF_APV_LKP_User__c;
    }
    Test.stopTest();

    User gestor = [SELECT Id FROM User WHERE Id = :linkedUserId];
    System.runAs(gestor) {
      System.assertEquals(
        true,
        FeatureManagement.checkPermission('AXF_CanConfigure'),
        'Gestor criado carrega AXF_CanConfigure pelo PSG'
      );
      System.assertEquals(
        1,
        [SELECT COUNT() FROM Account WHERE Id = :ownPersonId],
        've o proprio titular'
      );
    }
  }

  // ---- AXF-107: continuacao encadeada, recuperacao e retomada idempotente ----

  private static String randomRequestKey() {
    return 'axf107:' +
      Crypto.getRandomInteger() +
      ':' +
      String.valueOf(Datetime.now().getTime());
  }

  /**
   * @description Persists a request directly at a given checkpoint, reproducing the
   * state a stalled operation (or a COMMIT that never ran) leaves behind.
   */
  private static Id seedRequest(
    Id personId,
    String mode,
    String scope,
    String step,
    String status,
    Id userId,
    String requestKey
  ) {
    AXF_OBJ_AccessProvisioning__c apv = new AXF_OBJ_AccessProvisioning__c(
      AXF_APV_LKP_Person__c = personId,
      AXF_APV_LKP_User__c = userId,
      AXF_APV_PKL_Mode__c = mode,
      AXF_APV_PKL_Scope__c = scope,
      AXF_APV_PKL_CurrentStep__c = step,
      AXF_APV_PKL_Status__c = status,
      AXF_APV_EXI_RequestKey__c = String.isBlank(requestKey)
        ? randomRequestKey()
        : requestKey,
      AXF_APV_TXT_TargetName__c = 'Maria Testadora',
      AXF_APV_TXT_TargetEmail__c = 'maria.testadora@example.com',
      AXF_APV_TAL_StepLog__c = '[]'
    );
    insert apv;
    return apv.Id;
  }

  private static Id seedRequest(
    Id personId,
    String mode,
    String scope,
    String step,
    String status,
    Id userId
  ) {
    return seedRequest(personId, mode, scope, step, status, userId, null);
  }

  private static User newActiveUser(String alias) {
    Profile admin = [
      SELECT Id
      FROM Profile
      WHERE Name = 'System Administrator'
      LIMIT 1
    ];
    User u = new User(
      ProfileId = admin.Id,
      LastName = 'Alvo AXF107',
      Email = 'axf107.' + alias + '@example.com',
      Username = 'axf107.' +
        alias +
        '.' +
        Crypto.getRandomInteger() +
        '@example.com.invalid',
      Alias = alias,
      TimeZoneSidKey = 'America/Sao_Paulo',
      LocaleSidKey = 'pt_BR',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'pt_BR'
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert u;
    }
    return u;
  }

  private static Integer createdUsersFor(Id apvId) {
    return [
      SELECT COUNT()
      FROM User
      WHERE Username LIKE :('axf82.' + apvId + '@%')
    ];
  }

  @IsTest
  static void firstNonSetupStepSchedulesExactlyOneSuccessor() {
    User cfg = configurator();
    Test.startTest();
    System.runAs(cfg) {
      Id personId = personAccount('Continuacao');
      Id apvId = seedRequest(
        personId,
        'CREATE',
        'OWN_DATA',
        'CREATE_OR_LINK_PERSON',
        'PENDING',
        null
      );

      ALT_CLS_AxonUserProvisioning.scheduledPhases.clear();
      ALT_CLS_AxonUserProvisioning.runStep(apvId);

      AXF_OBJ_AccessProvisioning__c apv = ALT_CLS_AxonUserProvisioning.readApv(
        apvId
      );
      System.assertEquals(
        'CREATE_OR_LINK_USER',
        apv.AXF_APV_PKL_CurrentStep__c,
        apv.AXF_APV_TXT_Message__c
      );
      System.assertEquals('RUNNING', apv.AXF_APV_PKL_Status__c);
      System.assertEquals('Pessoa confirmada.', apv.AXF_APV_TXT_Message__c);
      // The defect: this step persisted RUNNING and scheduled nothing, which is the
      // exact state of the reported screenshot.
      System.assertEquals(
        1,
        ALT_CLS_AxonUserProvisioning.scheduledPhases.size(),
        'exactly one successor'
      );
      System.assertEquals(
        'STEP',
        ALT_CLS_AxonUserProvisioning.scheduledPhases[0]
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void ownerSyncStepSchedulesActivateSuccessor() {
    User cfg = configurator();
    User target = newActiveUser('axf107b');
    Test.startTest();
    System.runAs(cfg) {
      Id personId = personAccount('DonoSync');
      Id apvId = seedRequest(
        personId,
        'LINK',
        'OWN_DATA',
        'SET_OWNER_SYNC',
        'RUNNING',
        target.Id
      );

      ALT_CLS_AxonUserProvisioning.scheduledPhases.clear();
      ALT_CLS_AxonUserProvisioning.runStep(apvId);

      AXF_OBJ_AccessProvisioning__c apv = ALT_CLS_AxonUserProvisioning.readApv(
        apvId
      );
      System.assertEquals(
        'ACTIVATE',
        apv.AXF_APV_PKL_CurrentStep__c,
        apv.AXF_APV_TXT_Message__c
      );
      System.assertEquals('RUNNING', apv.AXF_APV_PKL_Status__c);
      System.assertEquals(true, apv.AXF_APV_CHK_OwnerSynced__c);
      System.assertEquals(target.Id, apv.AXF_APV_LKP_User__c);
      // The second gap of AXF-107: SET_OWNER_SYNC also persisted RUNNING and stopped.
      System.assertEquals(
        1,
        ALT_CLS_AxonUserProvisioning.scheduledPhases.size(),
        'exactly one successor'
      );
      System.assertEquals(
        'STEP',
        ALT_CLS_AxonUserProvisioning.scheduledPhases[0]
      );

      // the successor really carries the chain to DONE
      ALT_CLS_AxonUserProvisioning.driveSync(apvId);
      apv = ALT_CLS_AxonUserProvisioning.readApv(apvId);
      System.assertEquals(
        'DONE',
        apv.AXF_APV_PKL_CurrentStep__c,
        apv.AXF_APV_TXT_Message__c
      );
      System.assertEquals('SUCCEEDED', apv.AXF_APV_PKL_Status__c);
      System.assertEquals(
        target.Id,
        [SELECT OwnerId FROM Account WHERE Id = :personId].OwnerId
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void setupStepSchedulesSingleCommitThatContinues() {
    User cfg = configurator();
    licenseFree(true);
    Test.startTest();
    System.runAs(cfg) {
      Id personId = personAccount('Commit');
      Id apvId = seedRequest(
        personId,
        'CREATE',
        'OWN_DATA',
        'CREATE_OR_LINK_USER',
        'RUNNING',
        null
      );

      ALT_CLS_AxonUserProvisioning.scheduledPhases.clear();
      ALT_CLS_AxonUserProvisioning.runStep(apvId);

      // setup DML already happened; the checkpoint waits for the COMMIT transaction
      AXF_OBJ_AccessProvisioning__c apv = ALT_CLS_AxonUserProvisioning.readApv(
        apvId
      );
      System.assertEquals(
        'CREATE_OR_LINK_USER',
        apv.AXF_APV_PKL_CurrentStep__c,
        'checkpoint waits for COMMIT'
      );
      System.assertEquals(
        1,
        ALT_CLS_AxonUserProvisioning.scheduledPhases.size(),
        'exactly one COMMIT'
      );
      System.assertEquals(
        'COMMIT:ASSIGN_ROLE',
        ALT_CLS_AxonUserProvisioning.scheduledPhases[0]
      );

      // running only that COMMIT persists the checkpoint and schedules one successor
      ALT_CLS_AxonUserProvisioning.driveSyncFor(1);
      apv = ALT_CLS_AxonUserProvisioning.readApv(apvId);
      System.assertEquals('ASSIGN_ROLE', apv.AXF_APV_PKL_CurrentStep__c);
      System.assertEquals('RUNNING', apv.AXF_APV_PKL_Status__c);
      System.assertEquals(
        1,
        ALT_CLS_AxonUserProvisioning.scheduledPhases.size(),
        'COMMIT schedules exactly one STEP'
      );
      System.assertEquals(
        'STEP',
        ALT_CLS_AxonUserProvisioning.scheduledPhases[0]
      );

      ALT_CLS_AxonUserProvisioning.driveSync(apvId);
      apv = ALT_CLS_AxonUserProvisioning.readApv(apvId);
      System.assertEquals(
        'DONE',
        apv.AXF_APV_PKL_CurrentStep__c,
        apv.AXF_APV_TXT_Message__c
      );
      System.assertEquals('SUCCEEDED', apv.AXF_APV_PKL_Status__c);
    }
    Test.stopTest();
  }

  @IsTest
  static void commitWithoutCapacityPersistsRecoverableState() {
    User cfg = configurator();
    User target = newActiveUser('axf107c');
    Test.startTest();
    System.runAs(cfg) {
      Id personId = personAccount('SemCapacidade');
      Id apvId = seedRequest(
        personId,
        'LINK',
        'OWN_DATA',
        'CREATE_OR_LINK_USER',
        'RUNNING',
        target.Id
      );

      ALT_CLS_AxonUserProvisioning.scheduledPhases.clear();
      ALT_CLS_AxonUserProvisioning.runStep(apvId);
      System.assertEquals(
        'COMMIT:ASSIGN_ROLE',
        ALT_CLS_AxonUserProvisioning.scheduledPhases[0]
      );

      // the COMMIT transaction finds no Queueable capacity left
      ALT_CLS_AxonUserProvisioning.queueableCapacityOverride = false;
      ALT_CLS_AxonUserProvisioning.driveSyncFor(1);

      AXF_OBJ_AccessProvisioning__c apv = ALT_CLS_AxonUserProvisioning.readApv(
        apvId
      );
      System.assertEquals(
        'FAILED_RETRYABLE',
        apv.AXF_APV_PKL_Status__c,
        'never a silent RUNNING'
      );
      System.assertEquals(
        'ASSIGN_ROLE',
        apv.AXF_APV_PKL_CurrentStep__c,
        'the completed step advanced'
      );
      System.assertEquals(
        ALT_CLS_AxonUserProvisioning.MSG_NO_CAPACITY,
        apv.AXF_APV_TXT_Message__c
      );
      System.assertEquals(
        0,
        ALT_CLS_AxonUserProvisioning.scheduledPhases.size(),
        'nothing else was scheduled'
      );

      // recovery: with capacity back, resume schedules the single successor
      ALT_CLS_AxonUserProvisioning.queueableCapacityOverride = true;
      ALT_CLS_AxonUserProvisioning.Result resumed = new ALT_CLS_AxonUserProvisioning()
        .resume(apvId);
      System.assertEquals('RESUMED', resumed.outcome, resumed.message);
      ALT_CLS_AxonUserProvisioning.driveSync(apvId);
      apv = ALT_CLS_AxonUserProvisioning.readApv(apvId);
      System.assertEquals(
        'DONE',
        apv.AXF_APV_PKL_CurrentStep__c,
        apv.AXF_APV_TXT_Message__c
      );
      System.assertEquals('SUCCEEDED', apv.AXF_APV_PKL_Status__c);
      System.assertEquals(target.Id, apv.AXF_APV_LKP_User__c);
    }
    Test.stopTest();
  }

  @IsTest
  static void nonSetupStepWithoutCapacityPersistsRecoverableState() {
    User cfg = configurator();
    User target = newActiveUser('axf107d');
    Test.startTest();
    System.runAs(cfg) {
      Id personId = personAccount('SemCapacidade2');
      Id apvId = seedRequest(
        personId,
        'LINK',
        'OWN_DATA',
        'CREATE_OR_LINK_PERSON',
        'PENDING',
        target.Id
      );

      ALT_CLS_AxonUserProvisioning.queueableCapacityOverride = false;
      ALT_CLS_AxonUserProvisioning.scheduledPhases.clear();
      ALT_CLS_AxonUserProvisioning.runStep(apvId);

      AXF_OBJ_AccessProvisioning__c apv = ALT_CLS_AxonUserProvisioning.readApv(
        apvId
      );
      System.assertEquals(
        'CREATE_OR_LINK_USER',
        apv.AXF_APV_PKL_CurrentStep__c
      );
      System.assertEquals(
        'FAILED_RETRYABLE',
        apv.AXF_APV_PKL_Status__c,
        'no silent RUNNING'
      );
      System.assertEquals(
        0,
        ALT_CLS_AxonUserProvisioning.scheduledPhases.size()
      );

      ALT_CLS_AxonUserProvisioning.queueableCapacityOverride = true;
      ALT_CLS_AxonUserProvisioning.Result resumed = new ALT_CLS_AxonUserProvisioning()
        .resume(apvId);
      System.assertEquals('RESUMED', resumed.outcome, resumed.message);
      ALT_CLS_AxonUserProvisioning.driveSync(apvId);
      apv = ALT_CLS_AxonUserProvisioning.readApv(apvId);
      System.assertEquals(
        'DONE',
        apv.AXF_APV_PKL_CurrentStep__c,
        apv.AXF_APV_TXT_Message__c
      );
      System.assertEquals('SUCCEEDED', apv.AXF_APV_PKL_Status__c);
    }
    Test.stopTest();
  }

  @IsTest
  static void stalledRequestResumesFromCheckpointWithoutDuplicatingUser() {
    User cfg = configurator();
    licenseFree(true);
    Test.startTest();
    System.runAs(cfg) {
      Id personId = personAccount('Travada');
      // The state the defect persisted: CREATE_OR_LINK_USER / RUNNING with no job.
      Id apvId = seedRequest(
        personId,
        'CREATE',
        'OWN_DATA',
        'CREATE_OR_LINK_USER',
        'RUNNING',
        null,
        ALT_CLS_AxonUserProvisioning.buildRequestKey(
          personId,
          ALT_CLS_AxonUserProvisioning.AccessScope.OWN_DATA
        )
      );

      ALT_CLS_AxonUserProvisioning svc = new ALT_CLS_AxonUserProvisioning();
      ALT_CLS_AxonUserProvisioning.scheduledPhases.clear();
      ALT_CLS_AxonUserProvisioning.Result resumed = svc.start(
        createInput(personId, 'OWN_DATA')
      );

      System.assertEquals('RESUMED', resumed.outcome, resumed.message);
      System.assertEquals(
        apvId,
        resumed.provisioningId,
        'same request, no 2nd one'
      );
      System.assertEquals(
        1,
        ALT_CLS_AxonUserProvisioning.scheduledPhases.size(),
        'resume schedules exactly one STEP'
      );
      System.assertEquals(
        'STEP',
        ALT_CLS_AxonUserProvisioning.scheduledPhases[0]
      );

      ALT_CLS_AxonUserProvisioning.driveSync(apvId);

      AXF_OBJ_AccessProvisioning__c apv = ALT_CLS_AxonUserProvisioning.readApv(
        apvId
      );
      System.assertEquals(
        'DONE',
        apv.AXF_APV_PKL_CurrentStep__c,
        apv.AXF_APV_TXT_Message__c
      );
      System.assertEquals('SUCCEEDED', apv.AXF_APV_PKL_Status__c);
      System.assertNotEquals(null, apv.AXF_APV_LKP_User__c);
      System.assertEquals(
        1,
        createdUsersFor(apvId),
        'exactly one user for this request'
      );
      System.assertEquals(
        apv.AXF_APV_LKP_User__c,
        [SELECT OwnerId FROM Account WHERE Id = :personId].OwnerId,
        'ownership synced on resume'
      );

      // a repeated confirmation of a finished request changes nothing
      ALT_CLS_AxonUserProvisioning.Result again = svc.start(
        createInput(personId, 'OWN_DATA')
      );
      System.assertEquals('ALREADY_DONE', again.outcome);
      ALT_CLS_AxonUserProvisioning.driveSync(apvId);
      System.assertEquals(1, createdUsersFor(apvId), 'no duplicate user');
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM AXF_OBJ_AccessProvisioning__c
          WHERE AXF_APV_LKP_Person__c = :personId
        ],
        'no 2nd request'
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void stalledSetupStepResumesAndReusesTheCreatedUser() {
    User cfg = configurator();
    licenseFree(true);
    Test.startTest();
    System.runAs(cfg) {
      Id personId = personAccount('UsuarioUnico');
      Id apvId = seedRequest(
        personId,
        'CREATE',
        'OWN_DATA',
        'CREATE_OR_LINK_USER',
        'RUNNING',
        null
      );

      // the user is created, but the COMMIT that would persist the checkpoint cannot
      // be scheduled: the request stays at CREATE_OR_LINK_USER, still resumable
      ALT_CLS_AxonUserProvisioning.queueableCapacityOverride = false;
      ALT_CLS_AxonUserProvisioning.scheduledPhases.clear();
      ALT_CLS_AxonUserProvisioning.runStep(apvId);
      System.assertEquals(
        0,
        ALT_CLS_AxonUserProvisioning.scheduledPhases.size()
      );
      System.assertEquals(1, createdUsersFor(apvId), 'user created');

      // recovery re-runs the same step: it must reuse that user, never create a 2nd
      ALT_CLS_AxonUserProvisioning.queueableCapacityOverride = true;
      ALT_CLS_AxonUserProvisioning.Result resumed = new ALT_CLS_AxonUserProvisioning()
        .resume(apvId);
      System.assertEquals('RESUMED', resumed.outcome, resumed.message);
      ALT_CLS_AxonUserProvisioning.driveSync(apvId);

      System.assertEquals(
        1,
        createdUsersFor(apvId),
        'no duplicate user on resume'
      );
      AXF_OBJ_AccessProvisioning__c apv = ALT_CLS_AxonUserProvisioning.readApv(
        apvId
      );
      System.assertEquals(
        'DONE',
        apv.AXF_APV_PKL_CurrentStep__c,
        apv.AXF_APV_TXT_Message__c
      );
      System.assertEquals('SUCCEEDED', apv.AXF_APV_PKL_Status__c);
      System.assertEquals(
        [
          SELECT Id
          FROM User
          WHERE Username LIKE :('axf82.' + apvId + '@%')
          LIMIT 1
        ]
        .Id,
        apv.AXF_APV_LKP_User__c,
        'the reused user is the linked one'
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void startWithoutCapacityReportsRecoverableStatus() {
    User cfg = configurator();
    licenseFree(true);
    Test.startTest();
    System.runAs(cfg) {
      Id personId = personAccount('InicioSemCapacidade');
      ALT_CLS_AxonUserProvisioning.queueableCapacityOverride = false;
      ALT_CLS_AxonUserProvisioning svc = new ALT_CLS_AxonUserProvisioning();
      ALT_CLS_AxonUserProvisioning.Result r = svc.start(
        createInput(personId, 'OWN_DATA')
      );

      System.assertEquals('STARTED', r.outcome, r.message);
      System.assertEquals(
        'FAILED_RETRYABLE',
        r.status,
        'recovery instead of an endless spinner'
      );
      System.assertEquals(
        ALT_CLS_AxonUserProvisioning.MSG_NO_CAPACITY,
        r.message
      );
      System.assertEquals(
        'FAILED_RETRYABLE',
        ALT_CLS_AxonUserProvisioning.readApv(r.provisioningId)
          .AXF_APV_PKL_Status__c
      );

      // recovery from the configuration entry point
      ALT_CLS_AxonUserProvisioning.queueableCapacityOverride = true;
      ALT_CLS_AxonUserProvisioning.Result resumed = svc.start(
        createInput(personId, 'OWN_DATA')
      );
      System.assertEquals('RESUMED', resumed.outcome, resumed.message);
      ALT_CLS_AxonUserProvisioning.driveSync(resumed.provisioningId);
      AXF_OBJ_AccessProvisioning__c apv = ALT_CLS_AxonUserProvisioning.readApv(
        resumed.provisioningId
      );
      System.assertEquals(
        'DONE',
        apv.AXF_APV_PKL_CurrentStep__c,
        apv.AXF_APV_TXT_Message__c
      );
      System.assertEquals('SUCCEEDED', apv.AXF_APV_PKL_Status__c);
    }
    Test.stopTest();
  }

  @IsTest
  static void fullChainSchedulesExactlyOneSuccessorPerStep() {
    User cfg = configurator();
    licenseFree(true);
    Test.startTest();
    System.runAs(cfg) {
      Id personId = personAccount('CadeiaCompleta');
      ALT_CLS_AxonUserProvisioning.Result r = new ALT_CLS_AxonUserProvisioning()
        .start(createInput(personId, 'OWN_DATA'));

      System.assertEquals(
        1,
        ALT_CLS_AxonUserProvisioning.scheduledPhases.size(),
        'start schedules exactly one STEP'
      );
      System.assertEquals(
        'STEP',
        ALT_CLS_AxonUserProvisioning.scheduledPhases[0]
      );

      Set<String> planned = new Set<String>();
      Integer transactions = 0;
      while (
        !ALT_CLS_AxonUserProvisioning.scheduledPhases.isEmpty() &&
        transactions < 40
      ) {
        planned.add(ALT_CLS_AxonUserProvisioning.scheduledPhases[0]);
        ALT_CLS_AxonUserProvisioning.driveSyncFor(1);
        transactions++;
      }

      // 6 steps = 6 STEP transactions; the 4 setup steps (USER, ROLE, PSG,
      // ACTIVATE) add exactly one COMMIT each, so the chain settles in 10.
      System.assertEquals(
        10,
        transactions,
        'one successor per successful nonterminal step'
      );
      System.assertEquals(
        new Set<String>{
          'STEP',
          'COMMIT:ASSIGN_ROLE',
          'COMMIT:ASSIGN_PSG',
          'COMMIT:SET_OWNER_SYNC',
          'COMMIT:DONE'
        },
        planned
      );

      AXF_OBJ_AccessProvisioning__c apv = ALT_CLS_AxonUserProvisioning.readApv(
        r.provisioningId
      );
      System.assertEquals(
        'DONE',
        apv.AXF_APV_PKL_CurrentStep__c,
        apv.AXF_APV_TXT_Message__c
      );
      System.assertEquals('SUCCEEDED', apv.AXF_APV_PKL_Status__c);
    }
    Test.stopTest();
  }
}
