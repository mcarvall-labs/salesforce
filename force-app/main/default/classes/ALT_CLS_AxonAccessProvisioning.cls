/**
 * @description Applies an Axon access level (Financial Manager / Participant) to an existing
 * Salesforce user by assigning the matching UserRole and Permission Set Group.
 *
 * Contract: ARCHITECTURE-SPINE.md "Fechamento G3" + "Fechamento G2"; SHARING-MATRIX.md.
 * - Requires the caller to hold the AXF_CanConfigure custom permission (no self-elevation).
 * - Grants: consultar/cadastrar/editar via the PSG. Never Delete, ViewAll or ModifyAll.
 * - Idempotent: re-applying the same level is a no-op; switching levels removes only the
 *   previous Axon PSG assignment and preserves independent grants.
 * - Setup-only DML (User, PermissionSetAssignment). No non-setup DML => no Mixed DML in
 *   this story; chained-async provisioning (D-65) belongs to AXF-82 (user creation).
 * - User-facing strings are PT-BR literals for the MVP (D-86: PT-BR only); moving to Custom
 *   Labels + Translation Workbench is a dedicated i18n task once that infra exists.
 * - AXF-7.
 */
public with sharing class ALT_CLS_AxonAccessProvisioning {
  public enum Tier {
    GESTOR,
    PARTICIPANTE
  }

  public enum Outcome {
    SUCCEEDED,
    ALREADY_APPLIED,
    PENDING,
    FAILED,
    FORBIDDEN
  }

  public class Result {
    public Id userId;
    public String level;
    public Outcome outcome;
    public String message;
  }

  // ---- PT-BR messages (MVP; see class header) ----
  @TestVisible
  private static final String MSG_FORBIDDEN = 'Voce nao tem autorizacao para configurar niveis de acesso.';
  @TestVisible
  private static final String MSG_INVALID_LEVEL = 'Selecione um nivel de acesso valido.';
  @TestVisible
  private static final String MSG_USER_NOT_FOUND = 'O usuario selecionado nao foi encontrado.';
  @TestVisible
  private static final String MSG_USER_INACTIVE = 'Usuarios inativos nao podem receber um nivel de acesso. Reative o usuario primeiro.';
  @TestVisible
  private static final String MSG_LICENSE_INCOMPATIBLE = 'A licenca do usuario nao e compativel com o nivel de acesso do Axon.';
  @TestVisible
  private static final String MSG_GROUP_UNAVAILABLE = 'O grupo de conjuntos de permissoes do Axon nao esta disponivel nesta org.';
  @TestVisible
  private static final String MSG_GROUP_RECALCULATING = 'O grupo de conjuntos de permissoes do Axon ainda esta sendo recalculado. Tente novamente em instantes.';
  @TestVisible
  private static final String MSG_APPLIED = 'Nivel de acesso aplicado.';
  @TestVisible
  private static final String MSG_ALREADY_APPLIED = 'O usuario ja tem esse nivel de acesso. Nada foi alterado.';
  @TestVisible
  private static final String MSG_FAILED = 'Nao foi possivel aplicar o nivel de acesso. Nada foi alterado.';

  @TestVisible
  private static final String LEVEL_GESTOR = 'Gestor Financeiro';
  @TestVisible
  private static final String LEVEL_PARTICIPANTE = 'Participante';
  @TestVisible
  private static final String LEVEL_NONE = 'Sem acesso ao Axon';

  @TestVisible
  private static final Map<Tier, String> PSG_BY_LEVEL = new Map<Tier, String>{
    Tier.GESTOR => 'AXF_PSG_GestorFinanceiro',
    Tier.PARTICIPANTE => 'AXF_PSG_Participante'
  };

  @TestVisible
  private static final Map<Tier, String> ROLE_BY_LEVEL = new Map<Tier, String>{
    Tier.GESTOR => 'Axon_Gestor_Financeiro',
    Tier.PARTICIPANTE => 'Axon_Participante'
  };

  private static final Set<String> ALL_AXON_PSG_NAMES = new Set<String>(
    PSG_BY_LEVEL.values()
  );

  // User license names that cannot carry Axon custom permission sets.
  private static final Set<String> INCOMPATIBLE_LICENSES = new Set<String>{
    'Guest User License',
    'Chatter Free',
    'Chatter External'
  };

  /**
   * @description Test seam: when non-null, overrides the AXF_CanConfigure check so tests can
   * exercise the authorized and forbidden paths without granting the custom permission.
   */
  @TestVisible
  private static Boolean canConfigureOverride;

  private Boolean callerCanConfigure() {
    if (canConfigureOverride != null) {
      return canConfigureOverride;
    }
    return FeatureManagement.checkPermission('AXF_CanConfigure');
  }

  /**
   * @description Parses a client-supplied level string into the enum, or null when invalid.
   */
  public static Tier parseLevel(String raw) {
    if (String.isBlank(raw)) {
      return null;
    }
    String normalized = raw.trim().toUpperCase();
    for (Tier t : Tier.values()) {
      if (t.name() == normalized) {
        return t;
      }
    }
    return null;
  }

  /**
   * @description Applies the given access level to the given user. Never throws for expected
   * conditions; returns a Result describing pending / failed / forbidden outcomes.
   */
  public Result applyAccessLevel(Id userId, Tier level) {
    Result r = new Result();
    r.userId = userId;
    r.level = level == null ? null : level.name();

    if (!callerCanConfigure()) {
      return fail(r, Outcome.FORBIDDEN, MSG_FORBIDDEN);
    }
    if (level == null) {
      return fail(r, Outcome.FAILED, MSG_INVALID_LEVEL);
    }
    if (userId == null || userId.getSobjectType() != User.SObjectType) {
      return fail(r, Outcome.FAILED, MSG_USER_NOT_FOUND);
    }

    List<User> users = [
      SELECT Id, IsActive, UserRoleId, Profile.UserLicense.Name
      FROM User
      WHERE Id = :userId
      WITH USER_MODE
      LIMIT 1
    ];
    if (users.isEmpty()) {
      return fail(r, Outcome.FAILED, MSG_USER_NOT_FOUND);
    }
    User target = users[0];
    if (!target.IsActive) {
      return fail(r, Outcome.FAILED, MSG_USER_INACTIVE);
    }
    String licenseName = target.Profile != null &&
      target.Profile.UserLicense != null
      ? target.Profile.UserLicense.Name
      : null;
    if (licenseName != null && INCOMPATIBLE_LICENSES.contains(licenseName)) {
      return fail(r, Outcome.FAILED, MSG_LICENSE_INCOMPATIBLE);
    }

    UserRole role = findRole(ROLE_BY_LEVEL.get(level));
    PermissionSetGroup targetPsg = findGroup(PSG_BY_LEVEL.get(level));
    if (role == null || targetPsg == null) {
      return fail(r, Outcome.FAILED, MSG_GROUP_UNAVAILABLE);
    }
    if (targetPsg.Status != 'Updated') {
      return fail(r, Outcome.PENDING, MSG_GROUP_RECALCULATING);
    }

    Map<Id, PermissionSetAssignment> axonPsgAssignments = currentAxonPsgAssignments(
      userId
    );
    Boolean roleAlready = target.UserRoleId == role.Id;
    Boolean psgAlready = axonPsgAssignments.containsKey(targetPsg.Id);
    Boolean hasOtherAxonPsg = false;
    for (Id psgId : axonPsgAssignments.keySet()) {
      if (psgId != targetPsg.Id) {
        hasOtherAxonPsg = true;
      }
    }

    if (roleAlready && psgAlready && !hasOtherAxonPsg) {
      return ok(r, Outcome.ALREADY_APPLIED, MSG_ALREADY_APPLIED);
    }

    try {
      applyPrivileged(target, role.Id, targetPsg.Id, axonPsgAssignments);
    } catch (System.DmlException e) {
      // Duplicate assignment created by a concurrent apply of the same level: treat as done.
      if (isDuplicateValue(e)) {
        return ok(r, Outcome.ALREADY_APPLIED, MSG_ALREADY_APPLIED);
      }
      return fail(r, Outcome.FAILED, MSG_FAILED);
    } catch (Exception e) {
      return fail(r, Outcome.FAILED, MSG_FAILED);
    }

    return ok(r, Outcome.SUCCEEDED, MSG_APPLIED);
  }

  /**
   * @description Reports the current Axon access level of each user (Financial Manager /
   * Participant / none), derived from the Axon PSG assignments only.
   */
  public Map<Id, String> currentLevels(Set<Id> userIds) {
    Map<Id, String> levelByUser = new Map<Id, String>();
    if (userIds == null || userIds.isEmpty()) {
      return levelByUser;
    }
    Map<String, Tier> levelByPsgName = new Map<String, Tier>();
    for (Tier lvl : PSG_BY_LEVEL.keySet()) {
      levelByPsgName.put(PSG_BY_LEVEL.get(lvl), lvl);
    }
    // Reading Permission Set Group assignments is a privileged, display/decision-only
    // concern (the caller authority is already checked upstream). USER_MODE here fails
    // for a Gestor on the "Minimum Access" base profile, which has no read on the setup
    // objects — see AXF-7 id 10229. SYSTEM_MODE keeps the read working without widening
    // any user-facing access.
    Set<String> axonPsgNames = ALL_AXON_PSG_NAMES;
    for (PermissionSetAssignment psa : [
      SELECT AssigneeId, PermissionSetGroup.DeveloperName
      FROM PermissionSetAssignment
      WHERE
        AssigneeId IN :userIds
        AND PermissionSetGroupId != NULL
        AND PermissionSetGroup.DeveloperName IN :axonPsgNames
      WITH SYSTEM_MODE
    ]) {
      Tier lvl = levelByPsgName.get(psa.PermissionSetGroup.DeveloperName);
      if (lvl != null) {
        levelByUser.put(
          psa.AssigneeId,
          lvl == Tier.GESTOR ? LEVEL_GESTOR : LEVEL_PARTICIPANTE
        );
      }
    }
    for (Id uid : userIds) {
      if (!levelByUser.containsKey(uid)) {
        levelByUser.put(uid, LEVEL_NONE);
      }
    }
    return levelByUser;
  }

  // ---- privileged, isolated section (setup DML) ----

  private void applyPrivileged(
    User target,
    Id roleId,
    Id targetPsgId,
    Map<Id, PermissionSetAssignment> axonPsgAssignments
  ) {
    if (target.UserRoleId != roleId) {
      update new User(Id = target.Id, UserRoleId = roleId);
    }

    List<PermissionSetAssignment> toDelete = new List<PermissionSetAssignment>();
    for (PermissionSetAssignment psa : axonPsgAssignments.values()) {
      if (psa.PermissionSetGroupId != targetPsgId) {
        toDelete.add(psa);
      }
    }
    if (!toDelete.isEmpty()) {
      delete toDelete;
    }

    if (!axonPsgAssignments.containsKey(targetPsgId)) {
      insert new PermissionSetAssignment(
        AssigneeId = target.Id,
        PermissionSetGroupId = targetPsgId
      );
    }
  }

  // ---- helpers ----

  private Map<Id, PermissionSetAssignment> currentAxonPsgAssignments(
    Id userId
  ) {
    Map<Id, PermissionSetAssignment> byPsg = new Map<Id, PermissionSetAssignment>();
    // Privileged read of the current PSG assignment state, used for idempotency and the
    // level switch. SYSTEM_MODE for the same reason as currentLevels(): the base profile
    // has no read on setup objects. Assignment mutation stays in applyPrivileged().
    Set<String> axonPsgNames = ALL_AXON_PSG_NAMES;
    for (PermissionSetAssignment psa : [
      SELECT Id, PermissionSetGroupId, PermissionSetGroup.DeveloperName
      FROM PermissionSetAssignment
      WHERE
        AssigneeId = :userId
        AND PermissionSetGroupId != NULL
        AND PermissionSetGroup.DeveloperName IN :axonPsgNames
      WITH SYSTEM_MODE
    ]) {
      byPsg.put(psa.PermissionSetGroupId, psa);
    }
    return byPsg;
  }

  private UserRole findRole(String developerName) {
    List<UserRole> roles = [
      SELECT Id
      FROM UserRole
      WHERE DeveloperName = :developerName
      LIMIT 1
    ];
    return roles.isEmpty() ? null : roles[0];
  }

  private PermissionSetGroup findGroup(String developerName) {
    List<PermissionSetGroup> groups = [
      SELECT Id, Status
      FROM PermissionSetGroup
      WHERE DeveloperName = :developerName
      LIMIT 1
    ];
    return groups.isEmpty() ? null : groups[0];
  }

  private Boolean isDuplicateValue(System.DmlException e) {
    for (Integer i = 0; i < e.getNumDml(); i++) {
      if (e.getDmlType(i) == System.StatusCode.DUPLICATE_VALUE) {
        return true;
      }
    }
    return false;
  }

  private Result fail(Result r, Outcome outcome, String message) {
    r.outcome = outcome;
    r.message = message;
    return r;
  }

  private Result ok(Result r, Outcome outcome, String message) {
    r.outcome = outcome;
    r.message = message;
    return r;
  }
}
