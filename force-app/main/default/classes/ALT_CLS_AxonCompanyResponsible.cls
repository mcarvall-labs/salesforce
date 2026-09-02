/**
 * @description Links a person (Person Account) to a company (Business Account) as
 * a business responsible — sócia (PARTNER) or administradora (MANAGER) — and, when
 * that person has an eligible linked Salesforce user, grants that user Read/Edit
 * on the Business Account through a native Account Team member (AXF-83).
 *
 * Contract: ARCHITECTURE-SPINE.md "Fechamento G2" (G2-3 "Responsável empresarial"
 * row) + "Fechamento G1" + refinamento de acesso/ownership 28/08/2026 +
 * SHARING-MATRIX.md. AD-5 / AD-6 / AD-19 / AD-21 / AD-27 / D-52.
 *
 * Model:
 * - Business relationship = `AccountContactRelation` (Contacts to Multiple
 *   Accounts) between the person's PersonContact and the Business Account,
 *   flagged `AXF_ACR_BOL_AxonManaged__c` with `AXF_ACR_PKL_AxonRole__c`.
 * - Durable grant record = `AXF_OBJ_CompanyResponsibleAccess__c` (CRA), one per
 *   (business, person) pair via `AXF_CRA_EXI_Key__c`.
 * - Access grant = native `AccountTeamMember` (role "Responsável Financeiro",
 *   AccountAccessLevel Edit). The team member auto-creates the AccountShare
 *   (RowCause "Team"). Children of the Business Account that do NOT follow the
 *   account owner are shared by Apex Managed Sharing under the CRA row cause —
 *   `shareChildren()` is the hook; there are no such child objects integrated
 *   yet, so it is a documented no-op.
 *
 * Boundaries:
 * - The business role is NOT a Salesforce Role and NOT System Administrator. It
 *   grants only the G2 record access; no extra Delete, ViewAll or ModifyAll.
 * - A person with no eligible linked user keeps the relationship (status
 *   RELATIONSHIP_ONLY); the grant completes later (AC3).
 * - Same name / same document never proves identity and never auto-grants.
 * - Removal here does the direct un-grant (team member + row cause); the
 *   convergent cross-surface revalidation (caches / exports / async) is AXF-8.
 * - Never deactivates a user, never deletes financial facts, never touches
 *   independent grants (PS/PSG, ownership, other teams) — AC7.
 *
 * Authority: every entry point requires the `AXF_CanConfigure` custom permission.
 * The CRA grant-state record and the sharing-plumbing DML (AccountTeamMember,
 * future child shares) run in SYSTEM_MODE as privileged, idempotent automation
 * separated from user-mode entry points (AD-27) — the CRA is internal workflow
 * state, not user data, and grants no access to the records it references. The
 * `AccountContactRelation` and CRA mutations are service-owned privileged
 * automation. Gestores receive read-only ACR access for presentation; the CRA
 * remains internal workflow state and is not exposed through object/FLS grants.
 *
 * User-facing strings are PT-BR literals for the MVP (D-86).
 *
 * AXF-83.
 */
public with sharing class ALT_CLS_AxonCompanyResponsible {
  public enum RespRole {
    PARTNER,
    MANAGER
  }

  public enum Outcome {
    GRANTED,
    RELATIONSHIP_ONLY,
    UPDATED,
    ALREADY,
    REVOKED,
    FORBIDDEN,
    INVALID,
    CONFLICT,
    FAILED,
    NOT_FOUND
  }

  @TestVisible
  private static String teamRole = 'Responsável Financeiro';

  private static final String RT_PERSON = 'AXF_Person';
  private static final String RT_BUSINESS = 'AXF_Business';

  @TestVisible
  private static final String MSG_FORBIDDEN = 'Você não tem autorização para vincular responsáveis por empresa.';
  @TestVisible
  private static final String MSG_NOT_BUSINESS = 'Selecione uma empresa (Business Account) válida.';
  @TestVisible
  private static final String MSG_NOT_PERSON = 'Selecione uma pessoa (Person Account) válida.';
  @TestVisible
  private static final String MSG_SAME_ACCOUNT = 'A empresa e a pessoa responsável não podem ser o mesmo registro.';
  @TestVisible
  private static final String MSG_ROLE = 'Selecione um papel de negócio válido (sócia ou administradora).';
  @TestVisible
  private static final String MSG_CONFLICT = 'Esta responsabilidade mudou em outra sessão. Recarregue antes de continuar.';
  @TestVisible
  private static final String MSG_NOT_FOUND = 'A responsabilidade não foi encontrada ou você não tem acesso a ela.';
  @TestVisible
  private static final String MSG_TEAM_ROLE = 'O papel de equipe Responsável Financeiro não está configurado. Tente novamente após corrigir a configuração.';
  @TestVisible
  private static final String MSG_INDEPENDENT_ACR = 'Já existe um vínculo independente entre esta pessoa e empresa. O Axon não pode assumir esse registro.';
  @TestVisible
  private static final String MSG_INDEPENDENT_TEAM = 'Este usuário já possui um membro de equipe independente nesta empresa. O Axon não pode assumir esse acesso.';
  @TestVisible
  private static final String MSG_MANAGED_EFFECT = 'O acesso gerenciado pelo Axon não pôde ser verificado. Nenhum acesso independente foi alterado.';

  @TestVisible
  private static Boolean canConfigureOverride;
  @TestVisible
  private static Boolean simulateConcurrentInsert;
  private Boolean relationshipChanged;
  private Boolean teamGrantChanged;

  @TestVisible
  private static Boolean callerCanConfigure() {
    if (canConfigureOverride != null) {
      return canConfigureOverride;
    }
    return FeatureManagement.checkPermission('AXF_CanConfigure');
  }

  // ================= DTOs =================
  public class ConfirmInput {
    @AuraEnabled
    public Id businessId;
    @AuraEnabled
    public Id personId;
    @AuraEnabled
    public String role; // PARTNER | MANAGER
    @AuraEnabled
    public Integer expectedVersion; // required when the CRA already exists
  }

  public class ResponsibilityView {
    @AuraEnabled
    public Id craId;
    @AuraEnabled
    public Id businessId;
    @AuraEnabled
    public String businessName;
    @AuraEnabled
    public Id personId;
    @AuraEnabled
    public String personName;
    @AuraEnabled
    public String role;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Id grantedUserId;
    @AuraEnabled
    public Integer version;
    @AuraEnabled
    public Datetime grantedAt;
    @AuraEnabled
    public Datetime revokedAt;
    // Sanitized: only ever one of the MSG_* constants, never provider/PII text.
    @AuraEnabled
    public String lastError;
    @AuraEnabled
    public String outcome;
    @AuraEnabled
    public String message;
  }

  // ================= public API =================
  public ResponsibilityView confirmResponsibility(ConfirmInput input) {
    relationshipChanged = false;
    teamGrantChanged = false;
    if (!callerCanConfigure()) {
      return err(Outcome.FORBIDDEN, MSG_FORBIDDEN);
    }
    if (input == null || input.businessId == null || input.personId == null) {
      return err(Outcome.INVALID, MSG_NOT_BUSINESS);
    }
    if (input.businessId == input.personId) {
      return err(Outcome.INVALID, MSG_SAME_ACCOUNT);
    }
    RespRole role = parseRole(input.role);
    if (role == null) {
      return err(Outcome.INVALID, MSG_ROLE);
    }

    Map<Id, Account> byId = new Map<Id, Account>(
      [
        SELECT
          Id,
          Name,
          IsPersonAccount,
          PersonContactId,
          OwnerId,
          RecordType.DeveloperName
        FROM Account
        WHERE Id IN (:input.businessId, :input.personId)
        WITH USER_MODE
      ]
    );
    Account business = byId.get(input.businessId);
    Account person = byId.get(input.personId);
    if (business == null || business.RecordType.DeveloperName != RT_BUSINESS) {
      return err(Outcome.INVALID, MSG_NOT_BUSINESS);
    }
    if (person == null || person.RecordType.DeveloperName != RT_PERSON) {
      return err(Outcome.INVALID, MSG_NOT_PERSON);
    }

    String key = key(input.businessId, input.personId);
    List<AXF_OBJ_CompanyResponsibleAccess__c> found = [
      SELECT
        Id,
        AXF_CRA_LKP_Business__c,
        AXF_CRA_LKP_Person__c,
        AXF_CRA_LKP_GrantedUser__c,
        AXF_CRA_PKL_Role__c,
        AXF_CRA_PKL_Status__c,
        AXF_CRA_NUM_Version__c,
        AXF_CRA_DT_GrantedAt__c,
        AXF_CRA_DT_RevokedAt__c,
        AXF_CRA_TXT_ManagedTeamMemberId__c,
        AXF_CRA_TXT_LastError__c
      FROM AXF_OBJ_CompanyResponsibleAccess__c
      WHERE AXF_CRA_EXI_Key__c = :key
      WITH SYSTEM_MODE
      LIMIT 1
      FOR UPDATE
    ];

    AXF_OBJ_CompanyResponsibleAccess__c cra;
    Boolean isNew = found.isEmpty();
    Boolean sameRole = false;
    String priorStatus;
    if (isNew) {
      cra = new AXF_OBJ_CompanyResponsibleAccess__c(
        AXF_CRA_EXI_Key__c = key,
        AXF_CRA_LKP_Business__c = input.businessId,
        AXF_CRA_LKP_Person__c = input.personId,
        AXF_CRA_PKL_Role__c = role.name(),
        AXF_CRA_PKL_Status__c = 'RELATIONSHIP_ONLY',
        AXF_CRA_NUM_Version__c = 0
      );
      if (simulateConcurrentInsert == true) {
        simulateConcurrentInsert = false;
        Database.insert(
          cra.clone(false, true, false, false),
          AccessLevel.SYSTEM_MODE
        );
      }
      try {
        Database.insert(cra, AccessLevel.SYSTEM_MODE);
      } catch (DmlException ex) {
        if (ex.getDmlStatusCode(0) != 'DUPLICATE_VALUE') {
          throw ex;
        }
        List<AXF_OBJ_CompanyResponsibleAccess__c> raced = findCraForUpdate(key);
        if (raced.isEmpty()) {
          return err(Outcome.CONFLICT, MSG_CONFLICT);
        }
        cra = raced[0];
        isNew = false;
        sameRole = cra.AXF_CRA_PKL_Role__c == role.name();
        priorStatus = cra.AXF_CRA_PKL_Status__c;
        if (!sameRole) {
          ResponsibilityView conflict = toView(cra, business, person);
          conflict.outcome = Outcome.CONFLICT.name();
          conflict.message = MSG_CONFLICT;
          return conflict;
        }
        if (!canAdvanceVersion(cra.AXF_CRA_NUM_Version__c)) {
          return err(Outcome.CONFLICT, MSG_CONFLICT);
        }
      }
    } else {
      cra = found[0];
      if (
        input.expectedVersion == null ||
        input.expectedVersion != asInt(cra.AXF_CRA_NUM_Version__c)
      ) {
        ResponsibilityView c = toView(cra, business, person);
        c.outcome = Outcome.CONFLICT.name();
        c.message = MSG_CONFLICT;
        return c;
      }
      sameRole = cra.AXF_CRA_PKL_Role__c == role.name();
      priorStatus = cra.AXF_CRA_PKL_Status__c;
      if (!canAdvanceVersion(cra.AXF_CRA_NUM_Version__c)) {
        return err(Outcome.CONFLICT, MSG_CONFLICT);
      }
      cra.AXF_CRA_PKL_Role__c = role.name();
    }

    String relationshipError = upsertRelationship(
      person.PersonContactId,
      input.businessId,
      role
    );
    if (relationshipError != null) {
      return fail(cra, relationshipError, business, person);
    }

    // eligible linked user? = a completed AXF-82 provisioning for this person
    Id eligibleUserId = eligibleUser(input.personId);
    Outcome oc;
    if (eligibleUserId != null) {
      Savepoint grantSavepoint = Database.setSavepoint();
      String grantError = grantTeamAccess(
        cra,
        input.businessId,
        eligibleUserId
      );
      if (grantError != null) {
        Database.rollback(grantSavepoint);
        return fail(reload(cra.Id), grantError, business, person);
      }
      shareChildren(cra.Id, input.businessId, eligibleUserId);
      cra.AXF_CRA_LKP_GrantedUser__c = eligibleUserId;
      cra.AXF_CRA_PKL_Status__c = 'GRANTED';
      if (priorStatus != 'GRANTED') {
        cra.AXF_CRA_DT_GrantedAt__c = Datetime.now();
      }
      cra.AXF_CRA_DT_RevokedAt__c = null;
      cra.AXF_CRA_TXT_LastError__c = null;
      oc = isNew
        ? Outcome.GRANTED
        : (sameRole && priorStatus == 'GRANTED'
            ? Outcome.ALREADY
            : Outcome.UPDATED);
    } else {
      if (cra.AXF_CRA_TXT_ManagedTeamMemberId__c != null) {
        Savepoint downgradeSavepoint = Database.setSavepoint();
        if (!revokeTeamAccess(cra)) {
          Database.rollback(downgradeSavepoint);
          return fail(cra, MSG_MANAGED_EFFECT, business, person);
        }
        unshareChildren(cra.Id, cra.AXF_CRA_LKP_GrantedUser__c);
        cra.AXF_CRA_TXT_ManagedTeamMemberId__c = null;
        cra.AXF_CRA_LKP_GrantedUser__c = null;
      }
      cra.AXF_CRA_PKL_Status__c = 'RELATIONSHIP_ONLY';
      cra.AXF_CRA_TXT_LastError__c = null;
      oc = isNew
        ? Outcome.RELATIONSHIP_ONLY
        : (sameRole &&
            priorStatus == 'RELATIONSHIP_ONLY' &&
            !relationshipChanged
            ? Outcome.ALREADY
            : Outcome.UPDATED);
    }
    if (oc == Outcome.ALREADY && (relationshipChanged || teamGrantChanged)) {
      oc = Outcome.UPDATED;
    }
    if (oc == Outcome.ALREADY) {
      ResponsibilityView stable = toView(cra, business, person);
      stable.outcome = Outcome.ALREADY.name();
      return stable;
    }
    cra.AXF_CRA_NUM_Version__c = nextVersion(cra.AXF_CRA_NUM_Version__c);
    new PrivilegedGateway().updateCra(cra);

    ResponsibilityView v = toView(reload(cra.Id), business, person);
    v.outcome = oc.name();
    return v;
  }

  public List<ResponsibilityView> getResponsibilities(Id businessId) {
    if (!callerCanConfigure() || businessId == null) {
      return new List<ResponsibilityView>();
    }
    Map<Id, Account> accs = new Map<Id, Account>(
      [SELECT Id, Name FROM Account WHERE Id = :businessId WITH USER_MODE]
    );
    Account business = accs.get(businessId);
    if (business == null) {
      return new List<ResponsibilityView>();
    }
    List<ResponsibilityView> out = new List<ResponsibilityView>();
    List<AXF_OBJ_CompanyResponsibleAccess__c> rows = new PrivilegedGateway()
      .listByBusiness(businessId);
    Set<Id> personIds = new Set<Id>();
    Set<Id> grantedUserIds = new Set<Id>();
    for (AXF_OBJ_CompanyResponsibleAccess__c row : rows) {
      personIds.add(row.AXF_CRA_LKP_Person__c);
      if (row.AXF_CRA_LKP_GrantedUser__c != null) {
        grantedUserIds.add(row.AXF_CRA_LKP_GrantedUser__c);
      }
    }
    Map<Id, Account> visiblePeople = new Map<Id, Account>();
    if (!personIds.isEmpty()) {
      visiblePeople = new Map<Id, Account>(
        [SELECT Id, Name FROM Account WHERE Id IN :personIds WITH USER_MODE]
      );
    }
    Set<Id> visibleUserIds = new Map<Id, User>(
        [SELECT Id FROM User WHERE Id IN :grantedUserIds WITH USER_MODE]
      )
      .keySet();
    for (AXF_OBJ_CompanyResponsibleAccess__c cra : rows) {
      ResponsibilityView v = new ResponsibilityView();
      v.craId = cra.Id;
      v.businessId = businessId;
      v.businessName = business.Name;
      if (visiblePeople.containsKey(cra.AXF_CRA_LKP_Person__c)) {
        v.personId = cra.AXF_CRA_LKP_Person__c;
        v.personName = visiblePeople.get(cra.AXF_CRA_LKP_Person__c).Name;
      }
      v.role = cra.AXF_CRA_PKL_Role__c;
      v.status = cra.AXF_CRA_PKL_Status__c;
      v.grantedUserId = visibleUserIds.contains(cra.AXF_CRA_LKP_GrantedUser__c)
        ? cra.AXF_CRA_LKP_GrantedUser__c
        : null;
      v.version = asInt(cra.AXF_CRA_NUM_Version__c);
      v.grantedAt = cra.AXF_CRA_DT_GrantedAt__c;
      v.revokedAt = cra.AXF_CRA_DT_RevokedAt__c;
      v.lastError = cra.AXF_CRA_TXT_LastError__c;
      out.add(v);
    }
    return out;
  }

  /**
   * Direct removal of the grant produced by this responsibility. Preserves every
   * independent grant and never deactivates the user (AC7). The convergent
   * cross-surface revalidation (caches, exports, async) is AXF-8.
   */
  public ResponsibilityView revokeResponsibility(
    Id craId,
    Integer expectedVersion
  ) {
    if (!callerCanConfigure()) {
      return err(Outcome.FORBIDDEN, MSG_FORBIDDEN);
    }
    List<AXF_OBJ_CompanyResponsibleAccess__c> found = new PrivilegedGateway()
      .findByIdForUpdate(craId);
    if (found.isEmpty()) {
      return err(Outcome.NOT_FOUND, MSG_NOT_FOUND);
    }
    AXF_OBJ_CompanyResponsibleAccess__c cra = found[0];
    if (
      [
        SELECT COUNT()
        FROM Account
        WHERE Id = :cra.AXF_CRA_LKP_Business__c
        WITH USER_MODE
      ] == 0
    ) {
      return err(Outcome.NOT_FOUND, MSG_NOT_FOUND);
    }
    if (
      expectedVersion == null ||
      expectedVersion != asInt(cra.AXF_CRA_NUM_Version__c)
    ) {
      return err(Outcome.CONFLICT, MSG_CONFLICT);
    }
    if (!canAdvanceVersion(cra.AXF_CRA_NUM_Version__c)) {
      return err(Outcome.CONFLICT, MSG_CONFLICT);
    }

    if (cra.AXF_CRA_TXT_ManagedTeamMemberId__c != null) {
      if (!revokeTeamAccess(cra)) {
        return fail(reload(cra.Id), MSG_MANAGED_EFFECT, null, null);
      }
      unshareChildren(cra.Id, cra.AXF_CRA_LKP_GrantedUser__c);
      cra.AXF_CRA_TXT_ManagedTeamMemberId__c = null;
      cra.AXF_CRA_LKP_GrantedUser__c = null;
    }
    if (
      !deactivateRelationship(
        cra.AXF_CRA_LKP_Person__c,
        cra.AXF_CRA_LKP_Business__c
      )
    ) {
      return fail(cra, MSG_MANAGED_EFFECT, null, null);
    }

    cra.AXF_CRA_PKL_Status__c = 'REVOKED';
    cra.AXF_CRA_DT_RevokedAt__c = Datetime.now();
    cra.AXF_CRA_LKP_GrantedUser__c = null;
    cra.AXF_CRA_TXT_ManagedTeamMemberId__c = null;
    cra.AXF_CRA_TXT_LastError__c = null;
    cra.AXF_CRA_NUM_Version__c = nextVersion(cra.AXF_CRA_NUM_Version__c);
    new PrivilegedGateway().updateCra(cra);

    ResponsibilityView v = toView(reload(cra.Id), null, null);
    v.outcome = Outcome.REVOKED.name();
    return v;
  }

  // ============ business relationship (SYSTEM_MODE — privileged) ============
  // The AccountContactRelation is created / maintained by the privileged grant
  // automation (AD-27). The Gestor still gets object + FLS on the two custom
  // fields via the PS so AXF-90's UI can bind it directly.
  private String upsertRelationship(
    Id personContactId,
    Id businessId,
    RespRole role
  ) {
    if (personContactId == null) {
      return MSG_NOT_PERSON;
    }
    List<AccountContactRelation> existing = [
      SELECT Id, IsActive, AXF_ACR_PKL_AxonRole__c, AXF_ACR_BOL_AxonManaged__c
      FROM AccountContactRelation
      WHERE ContactId = :personContactId AND AccountId = :businessId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (existing.isEmpty()) {
      try {
        Database.insert(
          new AccountContactRelation(
            ContactId = personContactId,
            AccountId = businessId,
            IsActive = true,
            AXF_ACR_BOL_AxonManaged__c = true,
            AXF_ACR_PKL_AxonRole__c = role.name()
          ),
          AccessLevel.SYSTEM_MODE
        );
        relationshipChanged = true;
        return null;
      } catch (DmlException ex) {
        if (ex.getDmlStatusCode(0) != 'DUPLICATE_VALUE') {
          return MSG_MANAGED_EFFECT;
        }
        existing = [
          SELECT
            Id,
            IsActive,
            AXF_ACR_PKL_AxonRole__c,
            AXF_ACR_BOL_AxonManaged__c
          FROM AccountContactRelation
          WHERE ContactId = :personContactId AND AccountId = :businessId
          WITH SYSTEM_MODE
          LIMIT 1
        ];
        if (existing.isEmpty()) {
          return MSG_MANAGED_EFFECT;
        }
      }
    }
    if (!existing[0].AXF_ACR_BOL_AxonManaged__c) {
      return MSG_INDEPENDENT_ACR;
    }
    AccountContactRelation acr = existing[0];
    relationshipChanged =
      !acr.IsActive || acr.AXF_ACR_PKL_AxonRole__c != role.name();
    if (relationshipChanged) {
      acr.IsActive = true;
      acr.AXF_ACR_PKL_AxonRole__c = role.name();
      try {
        Database.update(acr, AccessLevel.SYSTEM_MODE);
      } catch (DmlException ignored) {
        return MSG_MANAGED_EFFECT;
      }
    }
    return null;
  }

  private Boolean deactivateRelationship(Id personId, Id businessId) {
    return new PrivilegedGateway()
      .deactivateManagedRelationship(personId, businessId);
  }

  // ================= grant (SYSTEM_MODE — privileged automation) =================
  @TestVisible
  private String grantTeamAccess(
    AXF_OBJ_CompanyResponsibleAccess__c cra,
    Id businessId,
    Id userId
  ) {
    String role = validTeamRole();
    if (role == null) {
      return MSG_TEAM_ROLE;
    }
    String opportunityAccess = minimumChildAccess(
      AccountTeamMember.OpportunityAccessLevel
    );
    String caseAccess = minimumChildAccess(AccountTeamMember.CaseAccessLevel);
    String contactAccess = minimumChildAccess(
      AccountTeamMember.ContactAccessLevel
    );
    if (cra.AXF_CRA_TXT_ManagedTeamMemberId__c != null) {
      List<AccountTeamMember> managed = [
        SELECT
          Id,
          AccountId,
          UserId,
          TeamMemberRole,
          AccountAccessLevel,
          OpportunityAccessLevel,
          CaseAccessLevel,
          ContactAccessLevel
        FROM AccountTeamMember
        WHERE Id = :cra.AXF_CRA_TXT_ManagedTeamMemberId__c
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      if (managed.isEmpty()) {
        List<AccountTeamMember> conflicting = [
          SELECT Id
          FROM AccountTeamMember
          WHERE
            AccountId = :businessId
            AND UserId = :cra.AXF_CRA_LKP_GrantedUser__c
          WITH SYSTEM_MODE
          LIMIT 1
        ];
        if (!conflicting.isEmpty()) {
          return MSG_MANAGED_EFFECT;
        }
        cra.AXF_CRA_TXT_ManagedTeamMemberId__c = null;
        teamGrantChanged = true;
      } else if (
        managed.size() == 1 &&
        managed[0].AccountId == businessId &&
        managed[0].UserId == cra.AXF_CRA_LKP_GrantedUser__c
      ) {
        if (managed[0].UserId == userId) {
          if (
            managed[0].TeamMemberRole != role ||
            managed[0].AccountAccessLevel != 'Edit' ||
            managed[0].OpportunityAccessLevel != opportunityAccess ||
            managed[0].CaseAccessLevel != caseAccess ||
            managed[0].ContactAccessLevel != contactAccess
          ) {
            managed[0].TeamMemberRole = role;
            managed[0].AccountAccessLevel = 'Edit';
            managed[0].OpportunityAccessLevel = opportunityAccess;
            managed[0].CaseAccessLevel = caseAccess;
            managed[0].ContactAccessLevel = contactAccess;
            try {
              Database.update(managed[0], AccessLevel.SYSTEM_MODE);
            } catch (DmlException ignored) {
              return MSG_MANAGED_EFFECT;
            }
            teamGrantChanged = true;
          }
          return null;
        }
        if (!revokeTeamAccess(cra)) {
          return MSG_MANAGED_EFFECT;
        }
        cra.AXF_CRA_TXT_ManagedTeamMemberId__c = null;
        teamGrantChanged = true;
      } else {
        return MSG_MANAGED_EFFECT;
      }
    }
    List<AccountTeamMember> existing = [
      SELECT Id, TeamMemberRole, AccountAccessLevel
      FROM AccountTeamMember
      WHERE AccountId = :businessId AND UserId = :userId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (!existing.isEmpty()) {
      return MSG_INDEPENDENT_TEAM;
    }
    AccountTeamMember member = new AccountTeamMember(
      AccountId = businessId,
      UserId = userId,
      TeamMemberRole = role,
      AccountAccessLevel = 'Edit',
      OpportunityAccessLevel = opportunityAccess,
      CaseAccessLevel = caseAccess,
      ContactAccessLevel = contactAccess
    );
    try {
      Database.insert(member, AccessLevel.SYSTEM_MODE);
    } catch (DmlException ex) {
      if (ex.getDmlStatusCode(0) == 'DUPLICATE_VALUE') {
        return MSG_INDEPENDENT_TEAM;
      }
      return MSG_MANAGED_EFFECT;
    }
    cra.AXF_CRA_TXT_ManagedTeamMemberId__c = member.Id;
    teamGrantChanged = true;
    return null;
  }

  /**
   * The configured team role, but only if it is an active picklist value in this
   * org (Setup → Account Teams → Team Roles). Otherwise null — the Edit access
   * grant is what enforces sharing; the role is reporting metadata.
   */
  @TestVisible
  private static String validTeamRole() {
    if (String.isBlank(teamRole)) {
      return null;
    }
    for (
      Schema.PicklistEntry e : AccountTeamMember.TeamMemberRole.getDescribe()
        .getPicklistValues()
    ) {
      if (e.isActive() && e.getValue() == teamRole) {
        return teamRole;
      }
    }
    return null;
  }

  private static String minimumChildAccess(Schema.SObjectField fieldToken) {
    String fallback;
    for (
      Schema.PicklistEntry entry : fieldToken.getDescribe().getPicklistValues()
    ) {
      if (!entry.isActive()) {
        continue;
      }
      if (entry.getValue() == 'None') {
        return 'None';
      }
      if (fallback == null || entry.getValue() == 'Read') {
        fallback = entry.getValue();
      }
    }
    return fallback;
  }

  @TestVisible
  private Boolean revokeTeamAccess(AXF_OBJ_CompanyResponsibleAccess__c cra) {
    return new PrivilegedGateway().revokeManagedTeamAccess(cra);
  }

  /**
   * Hook for Apex Managed Sharing of Business Account children that do NOT follow
   * the account owner (BankAccount / CreditCard / FinancialTransaction linked to
   * the business), under the CRA row cause. No such object is integrated yet, so
   * this is a deliberate no-op; the row cause name is the anchor. AXF-83 / G2-3.
   */
  @SuppressWarnings('PMD.EmptyStatementBlock')
  private void shareChildren(Id craId, Id businessId, Id userId) {
    // intentionally empty until a business-owned child root exists
  }

  @SuppressWarnings('PMD.EmptyStatementBlock')
  private void unshareChildren(Id craId, Id userId) {
    // intentionally empty — mirror of shareChildren
  }

  // ================= helpers =================
  /**
   * The Salesforce user eligible for the grant = the one linked to this Person
   * Account by a completed AXF-82 provisioning (`AXF_OBJ_AccessProvisioning__c`
   * at step DONE with a user), still active and Standard. No completed
   * provisioning => the responsibility stays RELATIONSHIP_ONLY (AC3). Same name /
   * email never stands in for this link.
   */
  @TestVisible
  private static Id eligibleUser(Id personId) {
    List<AXF_OBJ_AccessProvisioning__c> apvs = [
      SELECT AXF_APV_LKP_User__c
      FROM AXF_OBJ_AccessProvisioning__c
      WHERE
        AXF_APV_LKP_Person__c = :personId
        AND AXF_APV_PKL_CurrentStep__c = 'DONE'
        AND AXF_APV_LKP_User__c != NULL
      WITH SYSTEM_MODE
    ];
    if (apvs.isEmpty()) {
      return null;
    }
    Set<Id> candidateIds = new Set<Id>();
    for (AXF_OBJ_AccessProvisioning__c apv : apvs) {
      candidateIds.add(apv.AXF_APV_LKP_User__c);
    }
    List<User> eligible = [
      SELECT Id
      FROM User
      WHERE Id IN :candidateIds AND IsActive = TRUE AND UserType = 'Standard'
      WITH SYSTEM_MODE
    ];
    return eligible.size() == 1 ? eligible[0].Id : null;
  }

  private static AXF_OBJ_CompanyResponsibleAccess__c reload(Id craId) {
    return new PrivilegedGateway().reload(craId);
  }

  private static List<AXF_OBJ_CompanyResponsibleAccess__c> findCraForUpdate(
    String key
  ) {
    return new PrivilegedGateway().findByKeyForUpdate(key);
  }

  /** Narrow privileged persistence boundary for service-owned CRA/ACR state. */
  private without sharing class PrivilegedGateway {
    private List<AXF_OBJ_CompanyResponsibleAccess__c> findByKeyForUpdate(
      String key
    ) {
      return [
        SELECT
          Id,
          AXF_CRA_LKP_Business__c,
          AXF_CRA_LKP_Person__c,
          AXF_CRA_LKP_GrantedUser__c,
          AXF_CRA_PKL_Role__c,
          AXF_CRA_PKL_Status__c,
          AXF_CRA_NUM_Version__c,
          AXF_CRA_DT_GrantedAt__c,
          AXF_CRA_DT_RevokedAt__c,
          AXF_CRA_TXT_ManagedTeamMemberId__c,
          AXF_CRA_TXT_LastError__c
        FROM AXF_OBJ_CompanyResponsibleAccess__c
        WHERE AXF_CRA_EXI_Key__c = :key
        WITH SYSTEM_MODE
        LIMIT 1
        FOR UPDATE
      ];
    }

    private List<AXF_OBJ_CompanyResponsibleAccess__c> findByIdForUpdate(
      Id craId
    ) {
      return [
        SELECT
          Id,
          AXF_CRA_LKP_Business__c,
          AXF_CRA_LKP_Person__c,
          AXF_CRA_LKP_GrantedUser__c,
          AXF_CRA_PKL_Role__c,
          AXF_CRA_PKL_Status__c,
          AXF_CRA_NUM_Version__c,
          AXF_CRA_TXT_ManagedTeamMemberId__c
        FROM AXF_OBJ_CompanyResponsibleAccess__c
        WHERE Id = :craId
        WITH SYSTEM_MODE
        LIMIT 1
        FOR UPDATE
      ];
    }

    private AXF_OBJ_CompanyResponsibleAccess__c reload(Id craId) {
      return [
        SELECT
          Id,
          AXF_CRA_LKP_Business__c,
          AXF_CRA_LKP_Person__c,
          AXF_CRA_LKP_GrantedUser__c,
          AXF_CRA_PKL_Role__c,
          AXF_CRA_PKL_Status__c,
          AXF_CRA_NUM_Version__c,
          AXF_CRA_DT_GrantedAt__c,
          AXF_CRA_DT_RevokedAt__c,
          AXF_CRA_TXT_ManagedTeamMemberId__c,
          AXF_CRA_TXT_LastError__c
        FROM AXF_OBJ_CompanyResponsibleAccess__c
        WHERE Id = :craId
        WITH SYSTEM_MODE
        LIMIT 1
      ];
    }

    private void updateCra(AXF_OBJ_CompanyResponsibleAccess__c cra) {
      Database.update(cra, AccessLevel.SYSTEM_MODE);
    }

    private List<AXF_OBJ_CompanyResponsibleAccess__c> listByBusiness(
      Id businessId
    ) {
      return [
        SELECT
          Id,
          AXF_CRA_LKP_Business__c,
          AXF_CRA_LKP_Person__c,
          AXF_CRA_LKP_GrantedUser__c,
          AXF_CRA_PKL_Role__c,
          AXF_CRA_PKL_Status__c,
          AXF_CRA_NUM_Version__c,
          AXF_CRA_DT_GrantedAt__c,
          AXF_CRA_DT_RevokedAt__c,
          AXF_CRA_TXT_LastError__c
        FROM AXF_OBJ_CompanyResponsibleAccess__c
        WHERE AXF_CRA_LKP_Business__c = :businessId
        WITH SYSTEM_MODE
        ORDER BY CreatedDate
      ];
    }

    private Boolean deactivateManagedRelationship(Id personId, Id businessId) {
      List<Account> people = [
        SELECT PersonContactId
        FROM Account
        WHERE Id = :personId
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      if (people.isEmpty() || people[0].PersonContactId == null) {
        return false;
      }
      List<AccountContactRelation> existing = [
        SELECT Id, IsActive
        FROM AccountContactRelation
        WHERE
          ContactId = :people[0].PersonContactId
          AND AccountId = :businessId
          AND AXF_ACR_BOL_AxonManaged__c = TRUE
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      if (existing.size() != 1) {
        return false;
      }
      if (existing[0].IsActive) {
        existing[0].IsActive = false;
        try {
          Database.update(existing[0], AccessLevel.SYSTEM_MODE);
        } catch (DmlException ignored) {
          return false;
        }
      }
      AccountContactRelation verified = [
        SELECT IsActive
        FROM AccountContactRelation
        WHERE Id = :existing[0].Id
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      return !verified.IsActive;
    }

    private Boolean revokeManagedTeamAccess(
      AXF_OBJ_CompanyResponsibleAccess__c cra
    ) {
      Id memberId;
      try {
        memberId = (Id) cra.AXF_CRA_TXT_ManagedTeamMemberId__c;
      } catch (Exception ignored) {
        return false;
      }
      List<AccountTeamMember> existing = [
        SELECT Id, AccountId, UserId, TeamMemberRole
        FROM AccountTeamMember
        WHERE Id = :memberId
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      if (
        existing.size() != 1 ||
        existing[0].AccountId != cra.AXF_CRA_LKP_Business__c ||
        existing[0].UserId != cra.AXF_CRA_LKP_GrantedUser__c
      ) {
        return false;
      }
      try {
        Database.delete(existing[0], AccessLevel.SYSTEM_MODE);
      } catch (DmlException ignored) {
        return false;
      }
      return true;
    }

    private Boolean hasActiveManagedEdit(
      AXF_OBJ_CompanyResponsibleAccess__c cra
    ) {
      if (String.isBlank(cra.AXF_CRA_TXT_ManagedTeamMemberId__c)) {
        return false;
      }
      List<AccountTeamMember> managed = [
        SELECT
          AccountAccessLevel,
          OpportunityAccessLevel,
          CaseAccessLevel,
          ContactAccessLevel
        FROM AccountTeamMember
        WHERE
          Id = :cra.AXF_CRA_TXT_ManagedTeamMemberId__c
          AND AccountId = :cra.AXF_CRA_LKP_Business__c
          AND UserId = :cra.AXF_CRA_LKP_GrantedUser__c
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      return managed.size() == 1 &&
        managed[0].AccountAccessLevel == 'Edit' &&
        managed[0].OpportunityAccessLevel ==
        minimumChildAccess(AccountTeamMember.OpportunityAccessLevel) &&
        managed[0].CaseAccessLevel ==
        minimumChildAccess(AccountTeamMember.CaseAccessLevel) &&
        managed[0].ContactAccessLevel ==
        minimumChildAccess(AccountTeamMember.ContactAccessLevel);
    }
  }

  private static ResponsibilityView toView(
    AXF_OBJ_CompanyResponsibleAccess__c cra,
    Account business,
    Account person
  ) {
    ResponsibilityView v = new ResponsibilityView();
    v.craId = cra.Id;
    v.businessId = cra.AXF_CRA_LKP_Business__c;
    v.businessName = business != null ? business.Name : null;
    v.personId = person != null ? cra.AXF_CRA_LKP_Person__c : null;
    v.personName = person != null ? person.Name : null;
    v.role = cra.AXF_CRA_PKL_Role__c;
    v.status = cra.AXF_CRA_PKL_Status__c;
    v.grantedUserId = visibleUserId(cra.AXF_CRA_LKP_GrantedUser__c);
    v.version = asInt(cra.AXF_CRA_NUM_Version__c);
    v.grantedAt = cra.AXF_CRA_DT_GrantedAt__c;
    v.revokedAt = cra.AXF_CRA_DT_RevokedAt__c;
    v.lastError = cra.AXF_CRA_TXT_LastError__c;
    return v;
  }

  private static ResponsibilityView err(Outcome oc, String message) {
    ResponsibilityView v = new ResponsibilityView();
    v.outcome = oc.name();
    v.message = message;
    return v;
  }

  private static Id visibleUserId(Id userId) {
    if (userId == null) {
      return null;
    }
    List<User> visible = [
      SELECT Id
      FROM User
      WHERE Id = :userId
      WITH USER_MODE
      LIMIT 1
    ];
    return visible.isEmpty() ? null : visible[0].Id;
  }

  private static ResponsibilityView fail(
    AXF_OBJ_CompanyResponsibleAccess__c cra,
    String message,
    Account business,
    Account person
  ) {
    cra.AXF_CRA_PKL_Status__c = new PrivilegedGateway()
        .hasActiveManagedEdit(cra)
      ? 'GRANTED'
      : 'FAILED';
    cra.AXF_CRA_TXT_LastError__c = message;
    if (canAdvanceVersion(cra.AXF_CRA_NUM_Version__c)) {
      cra.AXF_CRA_NUM_Version__c = nextVersion(cra.AXF_CRA_NUM_Version__c);
    }
    new PrivilegedGateway().updateCra(cra);
    ResponsibilityView v = toView(reload(cra.Id), business, person);
    v.outcome = Outcome.FAILED.name();
    v.message = message;
    return v;
  }

  private static RespRole parseRole(String raw) {
    if (String.isBlank(raw)) {
      return null;
    }
    String n = raw.trim().toUpperCase();
    for (RespRole r : RespRole.values()) {
      if (r.name() == n) {
        return r;
      }
    }
    return null;
  }

  private static String key(Id businessId, Id personId) {
    return String.valueOf(businessId).left(18) +
      ':' +
      String.valueOf(personId).left(18);
  }

  private static Integer asInt(Decimal d) {
    return d == null ? 0 : d.intValue();
  }

  private static Boolean canAdvanceVersion(Decimal version) {
    return asInt(version) < 999999999;
  }

  private static Integer nextVersion(Decimal version) {
    return asInt(version) + 1;
  }
}
