/**
 * @description Tests for ALT_CLS_AxonCompanyResponsible (AXF-83). Functional
 * paths use the `canConfigureOverride` seam; the effective-access path grants a
 * real user and proves visibility with System.runAs.
 */
@IsTest(isParallel=false)
private class ALT_CLS_AxonCompanyResponsibleTest {
  /**
   * Selects an active role only as a test seam for native AccountTeamMember DML.
   * It does not assert that the approved production role is configured; the
   * production default remains exactly `Responsável Financeiro` and fail-closed.
   */
  private static void allow() {
    ALT_CLS_AxonCompanyResponsible.canConfigureOverride = true;
    for (
      Schema.PicklistEntry entry : AccountTeamMember.TeamMemberRole.getDescribe()
        .getPicklistValues()
    ) {
      if (entry.isActive()) {
        ALT_CLS_AxonCompanyResponsible.teamRole = entry.getValue();
        break;
      }
    }
  }

  private static ALT_CLS_AxonCompanyResponsible svc() {
    return new ALT_CLS_AxonCompanyResponsible();
  }

  private static Id rt(String dev) {
    return Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
      .getRecordTypeInfosByDeveloperName()
      .get(dev)
      .getRecordTypeId();
  }

  private static Account business(String name) {
    Account a = new Account(Name = name, RecordTypeId = rt('AXF_Business'));
    insert a;
    return a;
  }

  private static Account person(String lastName) {
    Account a = new Account(
      LastName = lastName,
      RecordTypeId = rt('AXF_Person')
    );
    insert a;
    return [SELECT Id, Name, PersonContactId FROM Account WHERE Id = :a.Id];
  }

  private static ALT_CLS_AxonCompanyResponsible.ConfirmInput input(
    Id businessId,
    Id personId,
    String role,
    Integer version
  ) {
    ALT_CLS_AxonCompanyResponsible.ConfirmInput c = new ALT_CLS_AxonCompanyResponsible.ConfirmInput();
    c.businessId = businessId;
    c.personId = personId;
    c.role = role;
    c.expectedVersion = version;
    return c;
  }

  /** Creates an active Standard user + a completed AXF-82 provisioning linking it
   *  to `personId`, and assigns the Gestor PSG so it can read Accounts. */
  private static User linkUser(Id personId, String tag) {
    Profile min = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Minimum Access - Salesforce'
      LIMIT 1
    ];
    User u = new User(
      ProfileId = min.Id,
      LastName = 'Resp ' + tag,
      Email = 'axf83.' + tag + '@example.com',
      Username = 'axf83.' +
        tag +
        '.' +
        Crypto.getRandomInteger() +
        '@example.com.invalid',
      Alias = ('a83' + tag).left(8),
      TimeZoneSidKey = 'America/Sao_Paulo',
      LocaleSidKey = 'pt_BR',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'pt_BR'
    );
    PermissionSetGroup psg = [
      SELECT Id, Status
      FROM PermissionSetGroup
      WHERE DeveloperName = 'AXF_PSG_Participante'
      LIMIT 1
    ];
    if (psg.Status != 'Updated') {
      Test.calculatePermissionSetGroup(psg.Id);
    }
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert u;
      insert new PermissionSetAssignment(
        AssigneeId = u.Id,
        PermissionSetGroupId = psg.Id
      );
    }
    Database.insert(
      new AXF_OBJ_AccessProvisioning__c(
        AXF_APV_EXI_RequestKey__c = 'axf83:test:' +
          tag +
          Crypto.getRandomInteger(),
        AXF_APV_LKP_Person__c = personId,
        AXF_APV_LKP_User__c = u.Id,
        AXF_APV_PKL_Mode__c = 'LINK',
        AXF_APV_PKL_Scope__c = 'OWN_DATA',
        AXF_APV_PKL_CurrentStep__c = 'DONE',
        AXF_APV_PKL_Status__c = 'SUCCEEDED'
      ),
      AccessLevel.SYSTEM_MODE
    );
    return u;
  }

  @IsTest
  static void confirmForbiddenWithoutAuthority() {
    ALT_CLS_AxonCompanyResponsible.canConfigureOverride = false;
    Account b = business('Empresa X');
    Account p = person('Silva');
    Test.startTest();
    ALT_CLS_AxonCompanyResponsible.ResponsibilityView v = svc()
      .confirmResponsibility(input(b.Id, p.Id, 'PARTNER', null));
    Test.stopTest();
    System.assertEquals('FORBIDDEN', v.outcome);
    System.assertEquals(
      0,
      [SELECT COUNT() FROM AXF_OBJ_CompanyResponsibleAccess__c]
    );
  }

  @IsTest
  static void rejectsWrongRecordTypesAndSameAccount() {
    allow();
    Account b = business('Empresa Y');
    Account p = person('Souza');
    Test.startTest();
    System.assertEquals(
      'INVALID',
      svc().confirmResponsibility(input(p.Id, b.Id, 'PARTNER', null)).outcome,
      'person as business => invalid'
    );
    System.assertEquals(
      'INVALID',
      svc().confirmResponsibility(input(b.Id, b.Id, 'PARTNER', null)).outcome,
      'same account => invalid'
    );
    System.assertEquals(
      'INVALID',
      svc().confirmResponsibility(input(b.Id, p.Id, 'CHEFE', null)).outcome,
      'bad role => invalid'
    );
    Test.stopTest();
  }

  @IsTest
  static void personWithoutUserStaysRelationshipOnly() {
    allow();
    Account b = business('Padaria do Bairro');
    Account p = person('Pereira');
    Test.startTest();
    ALT_CLS_AxonCompanyResponsible.ResponsibilityView v = svc()
      .confirmResponsibility(input(b.Id, p.Id, 'MANAGER', null));
    Test.stopTest();
    System.assertEquals('RELATIONSHIP_ONLY', v.outcome);
    System.assertEquals('RELATIONSHIP_ONLY', v.status);
    System.assertEquals(null, v.grantedUserId);
    Id accId = b.Id;
    List<AccountContactRelation> acrs = Database.queryWithBinds(
      'SELECT Id, IsActive, AXF_ACR_BOL_AxonManaged__c, AXF_ACR_PKL_AxonRole__c ' +
      'FROM AccountContactRelation WHERE AccountId = :accId',
      new Map<String, Object>{ 'accId' => accId },
      AccessLevel.SYSTEM_MODE
    );
    System.assertEquals(1, acrs.size(), 'business relationship persisted');
    System.assertEquals(true, acrs[0].AXF_ACR_BOL_AxonManaged__c);
    System.assertEquals('MANAGER', acrs[0].AXF_ACR_PKL_AxonRole__c);
    System.assertEquals(true, acrs[0].IsActive);
    System.assertEquals(
      0,
      [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :b.Id],
      'no team grant without an eligible user'
    );
  }

  @IsTest
  static void personWithEligibleUserGetsTeamGrantAndCanSee() {
    allow();
    Account b = business('Mercado Central');
    Account p = person('Almeida');
    User u = linkUser(p.Id, 'a');

    Test.startTest();
    ALT_CLS_AxonCompanyResponsible.ResponsibilityView v = svc()
      .confirmResponsibility(input(b.Id, p.Id, 'PARTNER', null));
    Test.stopTest();

    System.assertEquals('GRANTED', v.outcome);
    System.assertEquals('GRANTED', v.status);
    System.assertEquals(u.Id, v.grantedUserId);
    System.assertNotEquals(null, v.grantedAt);

    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM AccountTeamMember
        WHERE
          AccountId = :b.Id
          AND UserId = :u.Id
          AND AccountAccessLevel = 'Edit'
      ]
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM AccountShare
        WHERE
          AccountId = :b.Id
          AND UserOrGroupId = :u.Id
          AND AccountAccessLevel = 'Edit'
      ],
      'team member auto-creates the account share'
    );

    System.runAs(u) {
      List<Account> seen = [
        SELECT Id
        FROM Account
        WHERE Id = :b.Id
        WITH USER_MODE
      ];
      System.assertEquals(1, seen.size(), 'responsible user sees the company');
    }
  }

  @IsTest
  static void twoResponsiblesBothGrantedThirdWithoutLinkDenied() {
    allow();
    Account b = business('Loja XPTO');
    Account p1 = person('Um');
    Account p2 = person('Dois');
    Account p3 = person('Tres');
    User u1 = linkUser(p1.Id, 'x');
    User u2 = linkUser(p2.Id, 'y');
    User u3 = linkUser(p3.Id, 'z'); // linked user but NOT made responsible

    Test.startTest();
    svc().confirmResponsibility(input(b.Id, p1.Id, 'PARTNER', null));
    svc().confirmResponsibility(input(b.Id, p2.Id, 'MANAGER', null));
    Test.stopTest();

    System.assertEquals(
      2,
      [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :b.Id]
    );
    System.runAs(u1) {
      System.assertEquals(
        1,
        [SELECT COUNT() FROM Account WHERE Id = :b.Id WITH USER_MODE]
      );
    }
    System.runAs(u3) {
      System.assertEquals(
        0,
        [SELECT COUNT() FROM Account WHERE Id = :b.Id WITH USER_MODE],
        'a linked user who is not a responsible cannot see the company'
      );
    }
  }

  @IsTest
  static void repeatConfirmIsIdempotentAndBumpsVersion() {
    allow();
    Account b = business('Bar do Zé');
    Account p = person('Rocha');
    linkUser(p.Id, 'r');

    ALT_CLS_AxonCompanyResponsible.ResponsibilityView v1 = svc()
      .confirmResponsibility(input(b.Id, p.Id, 'PARTNER', null));
    Test.startTest();
    ALT_CLS_AxonCompanyResponsible.ResponsibilityView v2 = svc()
      .confirmResponsibility(input(b.Id, p.Id, 'MANAGER', v1.version));
    Test.stopTest();

    System.assertEquals('UPDATED', v2.outcome);
    System.assertEquals('MANAGER', v2.role, 'role updated in place');
    System.assert(v2.version > v1.version, 'version bumped');
    System.assertEquals(
      1,
      [SELECT COUNT() FROM AXF_OBJ_CompanyResponsibleAccess__c],
      'no duplicate grant record'
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM AccountContactRelation WHERE AccountId = :b.Id],
      'no duplicate relationship'
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :b.Id],
      'no duplicate team member'
    );
  }

  @IsTest
  static void staleVersionConflicts() {
    allow();
    Account b = business('Farmácia Nova');
    Account p = person('Dias');
    svc().confirmResponsibility(input(b.Id, p.Id, 'PARTNER', null));
    Test.startTest();
    ALT_CLS_AxonCompanyResponsible.ResponsibilityView c = svc()
      .confirmResponsibility(input(b.Id, p.Id, 'MANAGER', 0));
    Test.stopTest();
    System.assertEquals('CONFLICT', c.outcome);
    System.assertEquals(
      'PARTNER',
      [
        SELECT AXF_CRA_PKL_Role__c
        FROM AXF_OBJ_CompanyResponsibleAccess__c
        LIMIT 1
      ]
      .AXF_CRA_PKL_Role__c,
      'nothing overwritten'
    );
  }

  @IsTest
  static void revokeRemovesTeamGrantKeepsRecord() {
    allow();
    Account b = business('Auto Peças');
    Account p = person('Nunes');
    User u = linkUser(p.Id, 'n');
    ALT_CLS_AxonCompanyResponsible.ResponsibilityView g = svc()
      .confirmResponsibility(input(b.Id, p.Id, 'PARTNER', null));

    Test.startTest();
    ALT_CLS_AxonCompanyResponsible.ResponsibilityView r = svc()
      .revokeResponsibility(g.craId, g.version);
    Test.stopTest();

    System.assertEquals('REVOKED', r.outcome);
    System.assertEquals('REVOKED', r.status);
    System.assertNotEquals(
      null,
      r.revokedAt,
      'AXF-8 admin view: the revoke instant is surfaced'
    );
    System.assertEquals(
      null,
      r.lastError,
      'a verified revoke clears any prior error'
    );
    System.assertEquals(
      0,
      [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :b.Id],
      'team grant removed'
    );
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM AccountShare
        WHERE AccountId = :b.Id AND UserOrGroupId = :u.Id
      ]
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM AXF_OBJ_CompanyResponsibleAccess__c],
      'grant record kept for history'
    );
    System.runAs(u) {
      System.assertEquals(
        0,
        [SELECT COUNT() FROM Account WHERE Id = :b.Id WITH USER_MODE],
        'company no longer visible'
      );
    }
  }

  @IsTest
  static void revokeUnknownIsNotFoundAndStaleConflicts() {
    allow();
    Account b = business('Café Central');
    Account p = person('Lopes');
    ALT_CLS_AxonCompanyResponsible.ResponsibilityView g = svc()
      .confirmResponsibility(input(b.Id, p.Id, 'PARTNER', null));
    Test.startTest();
    System.assertEquals(
      'NOT_FOUND',
      svc().revokeResponsibility(null, 0).outcome
    );
    System.assertEquals(
      'CONFLICT',
      svc().revokeResponsibility(g.craId, 999).outcome
    );
    Test.stopTest();
  }

  @IsTest
  static void getResponsibilitiesListsForCompany() {
    allow();
    Account b = business('Construtora');
    Account p1 = person('Alfa');
    Account p2 = person('Beta');
    svc().confirmResponsibility(input(b.Id, p1.Id, 'PARTNER', null));
    svc().confirmResponsibility(input(b.Id, p2.Id, 'MANAGER', null));
    Test.startTest();
    List<ALT_CLS_AxonCompanyResponsible.ResponsibilityView> rows = svc()
      .getResponsibilities(b.Id);
    Test.stopTest();
    System.assertEquals(2, rows.size());
    Set<String> roles = new Set<String>();
    for (ALT_CLS_AxonCompanyResponsible.ResponsibilityView v : rows) {
      roles.add(v.role);
      System.assertNotEquals(null, v.personName);
      System.assertNotEquals(
        null,
        v.status,
        'AXF-8 admin view needs the effective status per row'
      );
    }
    System.assert(roles.contains('PARTNER') && roles.contains('MANAGER'));
  }

  @IsTest
  static void listSurfacesFailedReasonAndRevokedInstant() {
    allow();
    Account b = business('Consolidada');
    Account pFail = person('Falha Lista');
    linkUser(pFail.Id, 'fl');
    ALT_CLS_AxonCompanyResponsible.teamRole = 'Papel Inexistente Lista';
    svc().confirmResponsibility(input(b.Id, pFail.Id, 'PARTNER', null));
    ALT_CLS_AxonCompanyResponsible.teamRole = 'Responsável Financeiro';

    Account pRevoked = person('Revogada Lista');
    User u2 = linkUser(pRevoked.Id, 'rl');
    ALT_CLS_AxonCompanyResponsible.ResponsibilityView g = svc()
      .confirmResponsibility(input(b.Id, pRevoked.Id, 'MANAGER', null));
    svc().revokeResponsibility(g.craId, g.version);

    Test.startTest();
    List<ALT_CLS_AxonCompanyResponsible.ResponsibilityView> rows = svc()
      .getResponsibilities(b.Id);
    Test.stopTest();

    Boolean sawFailedReason = false;
    Boolean sawRevokedInstant = false;
    for (ALT_CLS_AxonCompanyResponsible.ResponsibilityView v : rows) {
      if (v.status == 'FAILED') {
        sawFailedReason = String.isNotBlank(v.lastError);
      }
      if (v.status == 'REVOKED') {
        sawRevokedInstant = v.revokedAt != null;
      }
    }
    System.assert(sawFailedReason, 'FAILED row carries the sanitized reason');
    System.assert(sawRevokedInstant, 'REVOKED row carries the revoke instant');
  }

  @IsTest
  static void validTeamRoleReturnsNullWhenNotConfigured() {
    ALT_CLS_AxonCompanyResponsible.teamRole = 'Papel Que Nao Existe 123';
    System.assertEquals(null, ALT_CLS_AxonCompanyResponsible.validTeamRole());
    ALT_CLS_AxonCompanyResponsible.teamRole = null;
    System.assertEquals(null, ALT_CLS_AxonCompanyResponsible.validTeamRole());
  }

  @IsTest
  static void missingTeamRoleFailsClosedAndCanRetry() {
    allow();
    Account b = business('Empresa Sem Papel');
    Account p = person('Papel');
    linkUser(p.Id, 'role');
    ALT_CLS_AxonCompanyResponsible.teamRole = 'Papel Inexistente AXF83';

    ALT_CLS_AxonCompanyResponsible.ResponsibilityView failed = svc()
      .confirmResponsibility(input(b.Id, p.Id, 'PARTNER', null));

    System.assertEquals('FAILED', failed.outcome);
    System.assertEquals('FAILED', failed.status);
    System.assertEquals(
      0,
      [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :b.Id]
    );
    System.assertNotEquals(null, failed.message);
  }

  @IsTest
  static void independentRelationshipIsPreserved() {
    allow();
    Account b = business('Empresa Relação Independente');
    Account p = person('Independente');
    AccountContactRelation independent = new AccountContactRelation(
      AccountId = b.Id,
      ContactId = p.PersonContactId,
      IsActive = true
    );
    insert independent;
    Datetime originalModified = [
      SELECT LastModifiedDate
      FROM AccountContactRelation
      WHERE Id = :independent.Id
    ]
    .LastModifiedDate;

    ALT_CLS_AxonCompanyResponsible.ResponsibilityView result = svc()
      .confirmResponsibility(input(b.Id, p.Id, 'MANAGER', null));

    System.assertEquals('FAILED', result.outcome);
    AccountContactRelation preserved = [
      SELECT Id, IsActive, LastModifiedDate
      FROM AccountContactRelation
      WHERE AccountId = :b.Id AND ContactId = :p.PersonContactId
    ];
    System.assertEquals(independent.Id, preserved.Id);
    System.assertEquals(true, preserved.IsActive);
    System.assertEquals(originalModified, preserved.LastModifiedDate);
  }

  @IsTest
  static void independentTeamMemberIsPreserved() {
    allow();
    Account b = business('Empresa Equipe Independente');
    Account p = person('Equipe');
    User u = linkUser(p.Id, 'team');
    insert new AccountTeamMember(
      AccountId = b.Id,
      UserId = u.Id,
      TeamMemberRole = ALT_CLS_AxonCompanyResponsible.validTeamRole(),
      AccountAccessLevel = 'Read',
      OpportunityAccessLevel = 'None',
      CaseAccessLevel = 'None'
    );

    ALT_CLS_AxonCompanyResponsible.ResponsibilityView result = svc()
      .confirmResponsibility(input(b.Id, p.Id, 'PARTNER', null));

    System.assertEquals('FAILED', result.outcome);
    AccountTeamMember preserved = [
      SELECT AccountAccessLevel
      FROM AccountTeamMember
      WHERE AccountId = :b.Id AND UserId = :u.Id
    ];
    System.assertEquals('Read', preserved.AccountAccessLevel);
  }

  @IsTest
  static void revokeThenReactivateOwnEffect() {
    allow();
    Account b = business('Empresa Reativada');
    Account p = person('Reativar');
    User u = linkUser(p.Id, 'reactivate');
    ALT_CLS_AxonCompanyResponsible.ResponsibilityView granted = svc()
      .confirmResponsibility(input(b.Id, p.Id, 'PARTNER', null));
    ALT_CLS_AxonCompanyResponsible.ResponsibilityView revoked = svc()
      .revokeResponsibility(granted.craId, granted.version);

    ALT_CLS_AxonCompanyResponsible.ResponsibilityView reactivated = svc()
      .confirmResponsibility(input(b.Id, p.Id, 'PARTNER', revoked.version));

    System.assertEquals('UPDATED', reactivated.outcome);
    System.assertEquals('GRANTED', reactivated.status);
    System.assertEquals(u.Id, reactivated.grantedUserId);
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM AccountTeamMember
        WHERE AccountId = :b.Id AND UserId = :u.Id
      ]
    );
  }

  @IsTest
  static void concurrentInitialCreateReloadsWithoutDuplicateEffects() {
    allow();
    Account b = business('Empresa Corrida');
    Account p = person('Concorrente');
    ALT_CLS_AxonCompanyResponsible.simulateConcurrentInsert = true;

    ALT_CLS_AxonCompanyResponsible.ResponsibilityView result = svc()
      .confirmResponsibility(input(b.Id, p.Id, 'PARTNER', null));

    System.assertEquals('UPDATED', result.outcome);
    System.assertEquals('RELATIONSHIP_ONLY', result.status);
    System.assertEquals(
      1,
      [SELECT COUNT() FROM AXF_OBJ_CompanyResponsibleAccess__c]
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM AccountContactRelation WHERE AccountId = :b.Id]
    );
    System.assertEquals(
      0,
      [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :b.Id]
    );
  }

  @IsTest
  static void revokeRemovesFinancialAccessWhenManagedRelationshipIsMissing() {
    allow();
    Account b = business('Empresa ACR Ausente');
    Account p = person('Sem ACR');
    User u = linkUser(p.Id, 'missingacr');
    ALT_CLS_AxonCompanyResponsible.ResponsibilityView granted = svc()
      .confirmResponsibility(input(b.Id, p.Id, 'PARTNER', null));
    delete [
      SELECT Id
      FROM AccountContactRelation
      WHERE AccountId = :b.Id AND ContactId = :p.PersonContactId
    ];

    ALT_CLS_AxonCompanyResponsible.ResponsibilityView result = svc()
      .revokeResponsibility(granted.craId, granted.version);

    System.assertEquals('FAILED', result.outcome);
    System.assertEquals(
      'FAILED',
      result.status,
      'the missing relationship remains an auditable failure'
    );
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM AccountTeamMember
        WHERE AccountId = :b.Id AND UserId = :u.Id
      ],
      'fail-safe revocation must not restore financial access'
    );
  }

  @IsTest
  static void revokeResolvesPersonContactOutsideCallerVisibility() {
    allow();
    Account b = business('Empresa Revogação Privilegiada');
    Account p = person('Invisível');
    User responsible = linkUser(p.Id, 'privileged');
    ALT_CLS_AxonCompanyResponsible.ResponsibilityView granted = svc()
      .confirmResponsibility(input(b.Id, p.Id, 'PARTNER', null));

    ALT_CLS_AxonCompanyResponsible.ResponsibilityView revoked;
    System.runAs(responsible) {
      System.assertEquals(
        0,
        [SELECT COUNT() FROM Account WHERE Id = :p.Id WITH USER_MODE],
        'fixture proves the caller cannot see the Person Account'
      );
      revoked = svc().revokeResponsibility(granted.craId, granted.version);
    }

    System.assertEquals('REVOKED', revoked.outcome);
    AccountContactRelation acr = [
      SELECT IsActive
      FROM AccountContactRelation
      WHERE AccountId = :b.Id AND ContactId = :p.PersonContactId
    ];
    System.assertEquals(false, acr.IsActive);
  }

  @IsTest
  static void revokeCannotCrossCompanyBoundary() {
    allow();
    Account ownBusiness = business('Empresa Permitida');
    Account ownPerson = person('Permitido');
    User caller = linkUser(ownPerson.Id, 'boundary');
    svc()
      .confirmResponsibility(
        input(ownBusiness.Id, ownPerson.Id, 'PARTNER', null)
      );

    Account hiddenBusiness = business('Empresa Oculta');
    Account hiddenPerson = person('Oculto');
    User hiddenUser = linkUser(hiddenPerson.Id, 'hidden');
    ALT_CLS_AxonCompanyResponsible.ResponsibilityView hidden = svc()
      .confirmResponsibility(
        input(hiddenBusiness.Id, hiddenPerson.Id, 'MANAGER', null)
      );

    ALT_CLS_AxonCompanyResponsible.ResponsibilityView result;
    System.runAs(caller) {
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM Account
          WHERE Id = :hiddenBusiness.Id
          WITH USER_MODE
        ]
      );
      result = svc().revokeResponsibility(hidden.craId, hidden.version);
    }
    System.assertEquals('NOT_FOUND', result.outcome);
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM AccountTeamMember
        WHERE AccountId = :hiddenBusiness.Id AND UserId = :hiddenUser.Id
      ]
    );
  }

  @IsTest
  static void listRedactsUnreadablePersonName() {
    allow();
    Account b = business('Empresa Lista Restrita');
    Account p = person('Nome Sigiloso');
    User caller = linkUser(p.Id, 'redact');
    svc().confirmResponsibility(input(b.Id, p.Id, 'PARTNER', null));

    List<ALT_CLS_AxonCompanyResponsible.ResponsibilityView> rows;
    System.runAs(caller) {
      System.assertEquals(
        0,
        [SELECT COUNT() FROM Account WHERE Id = :p.Id WITH USER_MODE]
      );
      rows = svc().getResponsibilities(b.Id);
    }
    System.assertEquals(1, rows.size());
    System.assertEquals(null, rows[0].personId);
    System.assertEquals(null, rows[0].personName);
  }

  @IsTest
  static void lostProvisioningDowngradesAndRemovesOwnedGrant() {
    allow();
    Account b = business('Empresa Elegibilidade Perdida');
    Account p = person('Sem Provisionamento');
    User oldUser = linkUser(p.Id, 'lost');
    ALT_CLS_AxonCompanyResponsible.ResponsibilityView granted = svc()
      .confirmResponsibility(input(b.Id, p.Id, 'PARTNER', null));
    delete [
      SELECT Id
      FROM AXF_OBJ_AccessProvisioning__c
      WHERE AXF_APV_LKP_Person__c = :p.Id
    ];

    ALT_CLS_AxonCompanyResponsible.ResponsibilityView result = svc()
      .confirmResponsibility(input(b.Id, p.Id, 'PARTNER', granted.version));
    System.assertEquals('UPDATED', result.outcome);
    System.assertEquals('RELATIONSHIP_ONLY', result.status);
    System.assertEquals(null, result.grantedUserId);
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM AccountTeamMember
        WHERE AccountId = :b.Id AND UserId = :oldUser.Id
      ]
    );
  }

  @IsTest
  static void eligibleUserChangeMigratesOnlyOwnedGrant() {
    allow();
    Account b = business('Empresa Migração');
    Account p = person('Usuário Novo');
    User oldUser = linkUser(p.Id, 'old');
    ALT_CLS_AxonCompanyResponsible.ResponsibilityView granted = svc()
      .confirmResponsibility(input(b.Id, p.Id, 'MANAGER', null));
    delete [
      SELECT Id
      FROM AXF_OBJ_AccessProvisioning__c
      WHERE AXF_APV_LKP_Person__c = :p.Id
    ];
    User newUser = linkUser(p.Id, 'new');

    ALT_CLS_AxonCompanyResponsible.ResponsibilityView result = svc()
      .confirmResponsibility(input(b.Id, p.Id, 'MANAGER', granted.version));
    System.assertEquals('UPDATED', result.outcome);
    System.assertEquals(newUser.Id, result.grantedUserId);
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM AccountTeamMember
        WHERE AccountId = :b.Id AND UserId = :oldUser.Id
      ]
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM AccountTeamMember
        WHERE AccountId = :b.Id AND UserId = :newUser.Id
      ]
    );
  }

  @IsTest
  static void revokeDeletesOwnedMemberDespiteAdministrativeDrift() {
    allow();
    Account b = business('Empresa Drift');
    Account p = person('Drift');
    linkUser(p.Id, 'drift');
    ALT_CLS_AxonCompanyResponsible.ResponsibilityView granted = svc()
      .confirmResponsibility(input(b.Id, p.Id, 'PARTNER', null));
    AccountTeamMember member = [
      SELECT Id, AccountAccessLevel
      FROM AccountTeamMember
      WHERE AccountId = :b.Id
    ];
    member.AccountAccessLevel = 'Read';
    update member;

    ALT_CLS_AxonCompanyResponsible.ResponsibilityView result = svc()
      .revokeResponsibility(granted.craId, granted.version);
    System.assertEquals('REVOKED', result.outcome);
    System.assertEquals(
      0,
      [SELECT COUNT() FROM AccountTeamMember WHERE Id = :member.Id]
    );
  }

  @IsTest
  static void acrRepairIsVersionedUpdate() {
    allow();
    Account b = business('Empresa Reparo ACR');
    Account p = person('Reparo');
    ALT_CLS_AxonCompanyResponsible.ResponsibilityView initial = svc()
      .confirmResponsibility(input(b.Id, p.Id, 'PARTNER', null));
    AccountContactRelation acr = [
      SELECT Id, IsActive
      FROM AccountContactRelation
      WHERE AccountId = :b.Id
    ];
    acr.IsActive = false;
    update acr;

    ALT_CLS_AxonCompanyResponsible.ResponsibilityView repaired = svc()
      .confirmResponsibility(input(b.Id, p.Id, 'PARTNER', initial.version));
    System.assertEquals('UPDATED', repaired.outcome);
    System.assert(repaired.version > initial.version);
  }

  @IsTest
  static void ambiguousActiveProvisioningFailsClosed() {
    allow();
    Account p = person('Provisionamento Ambíguo');
    linkUser(p.Id, 'amb1');
    linkUser(p.Id, 'amb2');
    System.assertEquals(
      null,
      ALT_CLS_AxonCompanyResponsible.eligibleUser(p.Id),
      'two distinct active Standard users are ambiguous'
    );
    Account b = business('Empresa Ambígua');
    ALT_CLS_AxonCompanyResponsible.ResponsibilityView result = svc()
      .confirmResponsibility(input(b.Id, p.Id, 'PARTNER', null));
    System.assertEquals('RELATIONSHIP_ONLY', result.status);
    System.assertEquals(
      0,
      [SELECT COUNT() FROM AccountTeamMember WHERE AccountId = :b.Id]
    );
  }

  @IsTest
  static void staleManagedMemberRecoversWithoutAdoptingIndependentGrant() {
    allow();
    Account b = business('Empresa Stale');
    Account p = person('Stale');
    User u = linkUser(p.Id, 'stale');
    ALT_CLS_AxonCompanyResponsible.ResponsibilityView granted = svc()
      .confirmResponsibility(input(b.Id, p.Id, 'PARTNER', null));
    AccountTeamMember original = [
      SELECT Id
      FROM AccountTeamMember
      WHERE AccountId = :b.Id
    ];
    delete original;

    ALT_CLS_AxonCompanyResponsible.ResponsibilityView repaired = svc()
      .confirmResponsibility(input(b.Id, p.Id, 'PARTNER', granted.version));
    System.assertEquals('UPDATED', repaired.outcome);
    AccountTeamMember replacement = [
      SELECT Id, OpportunityAccessLevel, CaseAccessLevel, ContactAccessLevel
      FROM AccountTeamMember
      WHERE AccountId = :b.Id AND UserId = :u.Id
    ];
    System.assertNotEquals(original.Id, replacement.Id);

    delete replacement;
    insert new AccountTeamMember(
      AccountId = b.Id,
      UserId = u.Id,
      TeamMemberRole = ALT_CLS_AxonCompanyResponsible.validTeamRole(),
      AccountAccessLevel = 'Read',
      OpportunityAccessLevel = 'None',
      CaseAccessLevel = 'None'
    );
    ALT_CLS_AxonCompanyResponsible.ResponsibilityView refused = svc()
      .confirmResponsibility(input(b.Id, p.Id, 'PARTNER', repaired.version));
    System.assertEquals('FAILED', refused.outcome);
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM AccountTeamMember
        WHERE AccountId = :b.Id AND UserId = :u.Id
      ]
    );
  }

  @IsTest
  static void versionOverflowFailsBeforeEffects() {
    allow();
    Account b = business('Empresa Versão Máxima');
    Account p = person('Versão');
    ALT_CLS_AxonCompanyResponsible.ResponsibilityView initial = svc()
      .confirmResponsibility(input(b.Id, p.Id, 'PARTNER', null));
    AXF_OBJ_CompanyResponsibleAccess__c cra = [
      SELECT Id, AXF_CRA_NUM_Version__c
      FROM AXF_OBJ_CompanyResponsibleAccess__c
      WHERE Id = :initial.craId
    ];
    cra.AXF_CRA_NUM_Version__c = 999999999;
    update cra;
    ALT_CLS_AxonCompanyResponsible.ResponsibilityView result = svc()
      .confirmResponsibility(input(b.Id, p.Id, 'MANAGER', 999999999));
    System.assertEquals('CONFLICT', result.outcome);
    System.assertEquals(
      'PARTNER',
      [
        SELECT AXF_CRA_PKL_Role__c
        FROM AXF_OBJ_CompanyResponsibleAccess__c
        WHERE Id = :cra.Id
      ]
      .AXF_CRA_PKL_Role__c
    );
  }

  @IsTest
  static void gestorMetadataIsReadOnlyForAcrAndEnablesController() {
    PermissionSet ps = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'AXF_PS_GestorFinanceiro'
      LIMIT 1
    ];
    System.assertEquals(
      2,
      [
        SELECT COUNT()
        FROM FieldPermissions
        WHERE
          ParentId = :ps.Id
          AND SObjectType = 'AccountContactRelation'
          AND PermissionsRead = TRUE
          AND PermissionsEdit = FALSE
      ],
      'both intentional ACR fields are readable but not editable'
    );
    Id controllerId = [
      SELECT Id
      FROM ApexClass
      WHERE Name = 'AXF_CLS_CTRL_CompanyResponsible'
    ]
    .Id;
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM SetupEntityAccess
        WHERE ParentId = :ps.Id AND SetupEntityId = :controllerId
      ]
    );
  }

  @IsTest
  static void productionRoleNameRemainsExact() {
    System.assertEquals(
      'Responsável Financeiro',
      ALT_CLS_AxonCompanyResponsible.teamRole
    );
    System.assertEquals(
      'Responsável Financeiro',
      ALT_CLS_AxonCompanyResponsible.validTeamRole(),
      'AXON_DEV must configure the exact active production Account Team role'
    );
  }
}
