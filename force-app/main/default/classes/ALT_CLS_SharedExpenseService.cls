/**
 * @description Colaboracao em despesa com escopo limitado (AXF-6). O titular (com acesso de
 * edicao ao FinancialTransaction e AXF_CanShareExpense) concede VIEW/EDIT a um usuario; o
 * colaborador nunca recebe share do registro: le um DTO redigido (G2-4) e altera somente os
 * campos permitidos (descricao, categoria) ou confirma a realizacao via AXF-25.
 *
 * Elevacao isolada e justificada: esta classe roda sem sharing apenas para (1) localizar a
 * concessao ativa do usuario corrente, (2) ler os campos redigidos do lancamento concedido e
 * (3) gravar os campos permitidos. Toda operacao revalida concessao ativa, Custom Permission,
 * FLS dos campos e versao antes de qualquer efeito; revogacao fecha o acesso imediatamente e
 * preserva direitos independentes (AXF-8). Sem Delete; sem fallback cliente.
 */
public without sharing class ALT_CLS_SharedExpenseService {
  public static final String PERMISSION_VIEW = 'VIEW';
  public static final String PERMISSION_EDIT = 'EDIT';
  public static final String STATUS_ACTIVE = 'ACTIVE';
  public static final String STATUS_REVOKED = 'REVOKED';
  public static final String CP_SHARE = 'AXF_CanShareExpense';
  public static final String CP_COLLABORATE = 'AXF_CanCollaborateExpense';
  public static final String NOTIFICATION_TYPE = 'AXF_SharedExpenseChange';
  public static final String STATUS_PLANNED = 'PLANNED';
  private static final Integer REQUEST_KEY_MAX = 64;
  private static final Integer GRANT_PAGE = 200;

  @TestVisible
  private static Boolean notificationsSent = false;
  /** Recipient of the last notification attempted (test observation). */
  @TestVisible
  private static Id lastNotifiedOwnerId;
  private static Boolean writing = false;

  /** Grant rows are only written by this service (trigger guard). */
  public static Boolean isWriting() {
    return writing;
  }

  public class SharedExpenseException extends Exception {
    public String code;
  }

  public class GrantInput {
    @AuraEnabled
    public Id financialTransactionId;
    @AuraEnabled
    public Id collaboratorId;
    @AuraEnabled
    public String permission;
    @AuraEnabled
    public String clientRequestId;
  }

  public class UpdateInput {
    @AuraEnabled
    public Id financialTransactionId;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public String userCategory;
    @AuraEnabled
    public Decimal expectedVersion;
    @AuraEnabled
    public String clientRequestId;
  }

  public class RealizeInput {
    @AuraEnabled
    public Id financialTransactionId;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public Date recognitionDate;
    @AuraEnabled
    public Decimal expectedVersion;
    @AuraEnabled
    public String clientRequestId;
  }

  public class GrantView {
    @AuraEnabled
    public Id grantId;
    @AuraEnabled
    public Id collaboratorId;
    @AuraEnabled
    public String collaboratorName;
    @AuraEnabled
    public String permission;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Decimal version;
  }

  /** Redacted view: never exposes source account, balances, identifiers or other allocations. */
  public class SharedView {
    @AuraEnabled
    public Id financialTransactionId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public String userCategory;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public String currencyIso;
    @AuraEnabled
    public Date dueDate;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Decimal version;
    @AuraEnabled
    public String permission;
    @AuraEnabled
    public Boolean canEdit;
    @AuraEnabled
    public Boolean canRealize;
  }

  // ---------------------------------------------------------------- owner side

  /** Owner grants (or reactivates) limited collaboration; idempotent by (expense, collaborator). */
  public GrantView share(GrantInput input) {
    if (
      input == null ||
      input.financialTransactionId == null ||
      input.collaboratorId == null ||
      String.isBlank(input.clientRequestId)
    ) {
      throw failure('INVALID_INPUT');
    }
    String permission = String.isBlank(input.permission)
      ? PERMISSION_VIEW
      : input.permission.toUpperCase();
    if (permission != PERMISSION_VIEW && permission != PERMISSION_EDIT) {
      throw failure('INVALID_INPUT');
    }
    AXF_OBJ_FinancialTransaction__c expense = ownerExpense(
      input.financialTransactionId
    );
    requireRequestKey(input.clientRequestId);
    if (
      expense.OwnerId == input.collaboratorId ||
      input.collaboratorId == UserInfo.getUserId()
    ) {
      throw failure('INVALID_INPUT');
    }
    if (expense.AXF_FTX_PKL_Status__c != STATUS_PLANNED) {
      throw failure('INVALID_STATE');
    }
    List<User> collaborators = [
      SELECT Id, Name
      FROM User
      WHERE Id = :input.collaboratorId AND IsActive = TRUE
      WITH USER_MODE
      LIMIT 1
    ];
    if (collaborators.isEmpty()) {
      throw failure('COLLABORATOR_NOT_FOUND');
    }
    if (
      !eligibleCollaboratorIds(new Set<Id>{ input.collaboratorId })
        .contains(input.collaboratorId)
    ) {
      throw failure('COLLABORATOR_NOT_ELIGIBLE');
    }
    String key = grantKey(expense.Id, input.collaboratorId);
    // Privileged by design: the owner was authorized above; the grant follows the expense owner.
    List<AXF_OBJ_SharedExpenseGrant__c> existing = [
      SELECT
        Id,
        AXF_SEG_PKL_Permission__c,
        AXF_SEG_PKL_Status__c,
        AXF_SEG_NUM_Version__c,
        AXF_SEG_TXT_LastRequestId__c
      FROM AXF_OBJ_SharedExpenseGrant__c
      WHERE AXF_SEG_EXI_GrantKey__c = :key
      LIMIT 1
      FOR UPDATE
    ];
    AXF_OBJ_SharedExpenseGrant__c grant;
    writing = true;
    try {
      if (existing.isEmpty()) {
        grant = new AXF_OBJ_SharedExpenseGrant__c(
          AXF_SEG_LKP_FinancialTransaction__c = expense.Id,
          AXF_SEG_LKP_Collaborator__c = input.collaboratorId,
          AXF_SEG_PKL_Permission__c = permission,
          AXF_SEG_PKL_Status__c = STATUS_ACTIVE,
          AXF_SEG_EXI_GrantKey__c = key,
          AXF_SEG_TXT_LastRequestId__c = input.clientRequestId,
          AXF_SEG_NUM_Version__c = 1,
          OwnerId = expense.OwnerId
        );
        try {
          Database.insert(grant, AccessLevel.SYSTEM_MODE);
        } catch (DmlException race) {
          if (race.getDmlType(0) != StatusCode.DUPLICATE_VALUE) {
            throw race;
          }
          // A concurrent share won the unique key: answer with that grant.
          grant = [
            SELECT Id
            FROM AXF_OBJ_SharedExpenseGrant__c
            WHERE AXF_SEG_EXI_GrantKey__c = :key
            LIMIT 1
          ];
        }
      } else {
        grant = existing[0];
        if (grant.AXF_SEG_TXT_LastRequestId__c != input.clientRequestId) {
          grant.AXF_SEG_PKL_Permission__c = permission;
          grant.AXF_SEG_PKL_Status__c = STATUS_ACTIVE;
          grant.AXF_SEG_DT_RevokedAt__c = null;
          grant.AXF_SEG_LKP_RevokedBy__c = null;
          grant.AXF_SEG_TXT_LastRequestId__c = input.clientRequestId;
          grant.AXF_SEG_NUM_Version__c = nz(grant.AXF_SEG_NUM_Version__c) + 1;
          Database.update(grant, AccessLevel.SYSTEM_MODE);
        }
      }
    } finally {
      writing = false;
    }
    return toGrantView(
      [
        SELECT
          Id,
          AXF_SEG_LKP_Collaborator__c,
          AXF_SEG_LKP_Collaborator__r.Name,
          AXF_SEG_PKL_Permission__c,
          AXF_SEG_PKL_Status__c,
          AXF_SEG_NUM_Version__c
        FROM AXF_OBJ_SharedExpenseGrant__c
        WHERE Id = :grant.Id
      ]
    );
  }

  /** Owner revokes; the collaborator's independent rights (own records, PS) are untouched. */
  public GrantView revoke(Id grantId, Decimal expectedVersion) {
    if (grantId == null) {
      throw failure('INVALID_INPUT');
    }
    List<AXF_OBJ_SharedExpenseGrant__c> grants = [
      SELECT
        Id,
        AXF_SEG_LKP_FinancialTransaction__c,
        AXF_SEG_LKP_Collaborator__c,
        AXF_SEG_LKP_Collaborator__r.Name,
        AXF_SEG_PKL_Permission__c,
        AXF_SEG_PKL_Status__c,
        AXF_SEG_NUM_Version__c
      FROM AXF_OBJ_SharedExpenseGrant__c
      WHERE Id = :grantId
      LIMIT 1
      FOR UPDATE
    ];
    if (grants.isEmpty()) {
      throw failure('NOT_ACCESSIBLE');
    }
    AXF_OBJ_SharedExpenseGrant__c grant = grants[0];
    // Authorization comes from the expense (owner/editor with the capability), not the grant row.
    ownerExpense(grant.AXF_SEG_LKP_FinancialTransaction__c);
    if (grant.AXF_SEG_PKL_Status__c == STATUS_REVOKED) {
      return toGrantView(grant);
    }
    if (
      expectedVersion != null &&
      expectedVersion != nz(grant.AXF_SEG_NUM_Version__c)
    ) {
      throw failure('CONFLICT');
    }
    grant.AXF_SEG_PKL_Status__c = STATUS_REVOKED;
    grant.AXF_SEG_DT_RevokedAt__c = Datetime.now();
    grant.AXF_SEG_LKP_RevokedBy__c = UserInfo.getUserId();
    grant.AXF_SEG_NUM_Version__c = nz(grant.AXF_SEG_NUM_Version__c) + 1;
    writing = true;
    try {
      Database.update(grant, AccessLevel.SYSTEM_MODE);
    } finally {
      writing = false;
    }
    return toGrantView(grant);
  }

  /** Owner lists the grants of one expense. */
  public List<GrantView> listGrants(Id financialTransactionId) {
    ownerExpense(financialTransactionId);
    List<GrantView> result = new List<GrantView>();
    for (AXF_OBJ_SharedExpenseGrant__c grant : [
      SELECT
        Id,
        AXF_SEG_LKP_Collaborator__c,
        AXF_SEG_LKP_Collaborator__r.Name,
        AXF_SEG_PKL_Permission__c,
        AXF_SEG_PKL_Status__c,
        AXF_SEG_NUM_Version__c
      FROM AXF_OBJ_SharedExpenseGrant__c
      WHERE AXF_SEG_LKP_FinancialTransaction__c = :financialTransactionId
      ORDER BY AXF_SEG_PKL_Status__c, AXF_SEG_LKP_Collaborator__r.Name
    ]) {
      result.add(toGrantView(grant));
    }
    return result;
  }

  // ---------------------------------------------------------------- collaborator side

  /** Collaborator lists the expenses shared with them (redacted). */
  public List<SharedView> listShared() {
    requireCollaborator();
    Map<Id, AXF_OBJ_SharedExpenseGrant__c> grants = activeGrantsForMe(null);
    List<SharedView> result = new List<SharedView>();
    if (grants.isEmpty()) {
      return result;
    }
    Set<Id> frozen = frozenExpenseIds(grants.keySet());
    for (
      AXF_OBJ_FinancialTransaction__c expense : redactedExpenses(
        grants.keySet()
      )
    ) {
      result.add(
        toSharedView(
          expense,
          grants.get(expense.Id),
          frozen.contains(expense.Id)
        )
      );
    }
    return result;
  }

  /** Collaborator reads one shared expense; direct URL/replay revalidate the grant. */
  public SharedView readShared(Id financialTransactionId) {
    requireCollaborator();
    AXF_OBJ_SharedExpenseGrant__c grant = activeGrant(financialTransactionId);
    List<AXF_OBJ_FinancialTransaction__c> rows = redactedExpenses(
      new Set<Id>{ financialTransactionId }
    );
    if (rows.isEmpty()) {
      throw failure('NOT_ACCESSIBLE');
    }
    return toSharedView(
      rows[0],
      grant,
      !frozenExpenseIds(new Set<Id>{ financialTransactionId }).isEmpty()
    );
  }

  /** Collaborator with EDIT changes only description/category; atomic, versioned, idempotent. */
  public SharedView updateShared(UpdateInput input) {
    if (
      input == null ||
      input.financialTransactionId == null ||
      String.isBlank(input.clientRequestId)
    ) {
      throw failure('INVALID_INPUT');
    }
    requireCollaborator();
    requireRequestKey(input.clientRequestId);
    if (input.expectedVersion == null) {
      throw failure('INVALID_INPUT');
    }
    AXF_OBJ_SharedExpenseGrant__c grant = activeGrant(
      input.financialTransactionId
    );
    if (grant.AXF_SEG_PKL_Permission__c != PERMISSION_EDIT) {
      throw failure('FORBIDDEN');
    }
    if (grant.AXF_SEG_TXT_LastEditRequestId__c == input.clientRequestId) {
      return readShared(input.financialTransactionId);
    }
    Schema.DescribeFieldResult description = AXF_OBJ_FinancialTransaction__c.AXF_FTX_TXT_Description__c.getDescribe();
    Schema.DescribeFieldResult category = AXF_OBJ_FinancialTransaction__c.AXF_FTX_TXT_UserCategory__c.getDescribe();
    if (!description.isUpdateable() || !category.isUpdateable()) {
      throw failure('FORBIDDEN');
    }
    // Row lock so the version check and the write are one unit against concurrent editors.
    List<AXF_OBJ_FinancialTransaction__c> locked = [
      SELECT Id
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE Id = :input.financialTransactionId
      FOR UPDATE
    ];
    List<AXF_OBJ_FinancialTransaction__c> rows = redactedExpenses(
      new Set<Id>{ input.financialTransactionId }
    );
    if (rows.isEmpty()) {
      throw failure('NOT_ACCESSIBLE');
    }
    AXF_OBJ_FinancialTransaction__c expense = rows[0];
    if (
      expense.AXF_FTX_PKL_Status__c != STATUS_PLANNED ||
      !frozenExpenseIds(new Set<Id>{ expense.Id }).isEmpty()
    ) {
      // Realized (allocation-referenced) evidence is immutable (AXF-25); explain, never REJECTED.
      throw failure('INVALID_STATE');
    }
    if (input.expectedVersion != nz(expense.AXF_FTX_NUM_Version__c)) {
      throw failure('CONFLICT');
    }
    // Partial payload keeps the untouched field; identical content is a no-op.
    String newDescription = input.description == null
      ? expense.AXF_FTX_TXT_Description__c
      : clip(input.description, 255);
    String newCategory = input.userCategory == null
      ? expense.AXF_FTX_TXT_UserCategory__c
      : clip(input.userCategory, 80);
    if (
      newDescription == expense.AXF_FTX_TXT_Description__c &&
      newCategory == expense.AXF_FTX_TXT_UserCategory__c
    ) {
      return toSharedView(expense, grant, false);
    }
    Savepoint point = Database.setSavepoint();
    writing = true;
    try {
      // Allowed fields only; the record is re-read privileged so no other field can travel.
      AXF_OBJ_FinancialTransaction__c change = new AXF_OBJ_FinancialTransaction__c(
        Id = expense.Id,
        AXF_FTX_TXT_Description__c = newDescription,
        AXF_FTX_TXT_UserCategory__c = newCategory,
        AXF_FTX_NUM_Version__c = nz(expense.AXF_FTX_NUM_Version__c) + 1
      );
      Database.update(change, AccessLevel.SYSTEM_MODE);
      grant.AXF_SEG_TXT_LastEditRequestId__c = input.clientRequestId;
      Database.update(grant, AccessLevel.SYSTEM_MODE);
    } catch (Exception failure) {
      Database.rollback(point);
      throw failure;
    } finally {
      writing = false;
    }
    // Best effort, after the write: a notification problem never undoes the edit.
    notifyOwner(expense, 'Campos permitidos alterados por colaborador.');
    return readShared(input.financialTransactionId);
  }

  /**
   * Collaborator with EDIT confirms realization through AXF-25. The realization service keeps
   * its own authorization (AXF_CanRealize + record access); this method never widens it.
   */
  public Id confirmRealization(RealizeInput input) {
    if (
      input == null ||
      input.financialTransactionId == null ||
      String.isBlank(input.clientRequestId) ||
      input.amount == null
    ) {
      throw failure('INVALID_INPUT');
    }
    requireCollaborator();
    requireRequestKey(input.clientRequestId);
    AXF_OBJ_SharedExpenseGrant__c grant = activeGrant(
      input.financialTransactionId
    );
    if (grant.AXF_SEG_PKL_Permission__c != PERMISSION_EDIT) {
      throw failure('FORBIDDEN');
    }
    ALT_CLS_RealizationService.Input request = new ALT_CLS_RealizationService.Input();
    request.targetId = input.financialTransactionId;
    request.sourceKind = 'CASH';
    request.amount = input.amount;
    request.recognitionDate = input.recognitionDate == null
      ? Date.today()
      : input.recognitionDate;
    request.targetVersion = input.expectedVersion;
    request.operationKey = input.clientRequestId;
    Id allocationId;
    try {
      allocationId = new ALT_CLS_RealizationService().apply(request);
    } catch (ALT_CLS_RealizationService.RealizationException denied) {
      // Without record access AXF-25 answers NOT_AUTHORIZED/UNAVAILABLE; both mean denied here.
      throw failure(
        denied.getMessage() == 'NOT_AUTHORIZED' ||
          denied.getMessage() == 'UNAVAILABLE'
          ? 'REALIZATION_DENIED'
          : denied.getMessage()
      );
    }
    // The allocation is committed; the notification is best effort.
    List<AXF_OBJ_FinancialTransaction__c> rows = redactedExpenses(
      new Set<Id>{ input.financialTransactionId }
    );
    if (!rows.isEmpty()) {
      notifyOwner(rows[0], 'Realizacao confirmada por colaborador.');
    }
    return allocationId;
  }

  // ---------------------------------------------------------------- guards

  private AXF_OBJ_FinancialTransaction__c ownerExpense(
    Id financialTransactionId
  ) {
    if (financialTransactionId == null) {
      throw failure('INVALID_INPUT');
    }
    if (!FeatureManagement.checkPermission(CP_SHARE)) {
      throw failure('FORBIDDEN');
    }
    List<AXF_OBJ_FinancialTransaction__c> rows = [
      SELECT Id, OwnerId, AXF_FTX_PKL_Status__c
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE Id = :financialTransactionId
      WITH USER_MODE
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      throw failure('NOT_ACCESSIBLE');
    }
    List<UserRecordAccess> access = [
      SELECT RecordId, HasEditAccess
      FROM UserRecordAccess
      WHERE
        UserId = :UserInfo.getUserId()
        AND RecordId = :financialTransactionId
      LIMIT 1
    ];
    if (access.isEmpty() || access[0].HasEditAccess != true) {
      throw failure('NOT_ACCESSIBLE');
    }
    return rows[0];
  }

  private void requireCollaborator() {
    if (!FeatureManagement.checkPermission(CP_COLLABORATE)) {
      throw failure('FORBIDDEN');
    }
  }

  private static void requireRequestKey(String clientRequestId) {
    if (
      String.isBlank(clientRequestId) ||
      clientRequestId.length() > REQUEST_KEY_MAX
    ) {
      throw failure('INVALID_INPUT');
    }
  }

  /**
   * Users who can collaborate: assigned the Participante permission set directly or through
   * its group. The same rule feeds the picker, so what is offered is what is accepted.
   */
  public static Set<Id> eligibleCollaboratorIds(Set<Id> candidateIds) {
    Set<Id> result = new Set<Id>();
    if (candidateIds == null || candidateIds.isEmpty()) {
      return result;
    }
    for (PermissionSetAssignment assignment : [
      SELECT AssigneeId
      FROM PermissionSetAssignment
      WHERE
        AssigneeId IN :candidateIds
        AND Assignee.IsActive = TRUE
        AND (PermissionSet.Name = 'AXF_PS_Participante'
        OR PermissionSetGroup.DeveloperName = 'AXF_PSG_Participante')
    ]) {
      result.add(assignment.AssigneeId);
    }
    return result;
  }

  private Map<Id, AXF_OBJ_SharedExpenseGrant__c> activeGrantsForMe(
    Id financialTransactionId
  ) {
    Id me = UserInfo.getUserId();
    Map<Id, AXF_OBJ_SharedExpenseGrant__c> result = new Map<Id, AXF_OBJ_SharedExpenseGrant__c>();
    List<AXF_OBJ_SharedExpenseGrant__c> grants = financialTransactionId == null
      ? [
          SELECT
            Id,
            AXF_SEG_LKP_FinancialTransaction__c,
            AXF_SEG_PKL_Permission__c,
            AXF_SEG_TXT_LastRequestId__c,
            AXF_SEG_TXT_LastEditRequestId__c,
            AXF_SEG_NUM_Version__c
          FROM AXF_OBJ_SharedExpenseGrant__c
          WHERE
            AXF_SEG_LKP_Collaborator__c = :me
            AND AXF_SEG_PKL_Status__c = :STATUS_ACTIVE
          ORDER BY CreatedDate DESC
          LIMIT :GRANT_PAGE
        ]
      : [
          SELECT
            Id,
            AXF_SEG_LKP_FinancialTransaction__c,
            AXF_SEG_PKL_Permission__c,
            AXF_SEG_TXT_LastRequestId__c,
            AXF_SEG_TXT_LastEditRequestId__c,
            AXF_SEG_NUM_Version__c
          FROM AXF_OBJ_SharedExpenseGrant__c
          WHERE
            AXF_SEG_LKP_Collaborator__c = :me
            AND AXF_SEG_PKL_Status__c = :STATUS_ACTIVE
            AND AXF_SEG_LKP_FinancialTransaction__c = :financialTransactionId
          LIMIT 1
        ];
    for (AXF_OBJ_SharedExpenseGrant__c grant : grants) {
      result.put(grant.AXF_SEG_LKP_FinancialTransaction__c, grant);
    }
    return result;
  }

  private AXF_OBJ_SharedExpenseGrant__c activeGrant(Id financialTransactionId) {
    if (financialTransactionId == null) {
      throw failure('INVALID_INPUT');
    }
    AXF_OBJ_SharedExpenseGrant__c grant = activeGrantsForMe(
        financialTransactionId
      )
      .get(financialTransactionId);
    if (grant == null) {
      // Same answer whether the expense exists, was never shared or was revoked.
      throw failure('NOT_ACCESSIBLE');
    }
    return grant;
  }

  /** Privileged read restricted to the redacted field set. */
  private List<AXF_OBJ_FinancialTransaction__c> redactedExpenses(Set<Id> ids) {
    return [
      SELECT
        Id,
        Name,
        AXF_FTX_TXT_Description__c,
        AXF_FTX_TXT_UserCategory__c,
        AXF_FTX_NUM_Magnitude__c,
        AXF_FTX_TXT_CurrencyIsoCode__c,
        AXF_FTX_DAT_DueDate__c,
        AXF_FTX_PKL_Status__c,
        AXF_FTX_NUM_Version__c,
        OwnerId
      FROM AXF_OBJ_FinancialTransaction__c
      WHERE Id IN :ids
      ORDER BY AXF_FTX_DAT_DueDate__c, Name
    ];
  }

  private void notifyOwner(
    AXF_OBJ_FinancialTransaction__c expense,
    String body
  ) {
    List<CustomNotificationType> types = [
      SELECT Id
      FROM CustomNotificationType
      WHERE DeveloperName = :NOTIFICATION_TYPE
      LIMIT 1
    ];
    if (types.isEmpty() || expense.OwnerId == null) {
      return;
    }
    Messaging.CustomNotification notification = new Messaging.CustomNotification();
    notification.setTitle('Despesa compartilhada: ' + expense.Name);
    notification.setBody(body);
    notification.setNotificationTypeId(types[0].Id);
    notification.setTargetId(expense.Id);
    try {
      notification.send(new Set<String>{ String.valueOf(expense.OwnerId) });
      notificationsSent = true;
      lastNotifiedOwnerId = expense.OwnerId;
    } catch (Exception undelivered) {
      // The financial effect already happened; a lost notification is logged, never fatal.
      System.debug(
        LoggingLevel.WARN,
        'AXF-6 owner notification not delivered: ' + undelivered.getTypeName()
      );
    }
  }

  private static GrantView toGrantView(AXF_OBJ_SharedExpenseGrant__c grant) {
    GrantView view = new GrantView();
    view.grantId = grant.Id;
    view.collaboratorId = grant.AXF_SEG_LKP_Collaborator__c;
    view.collaboratorName = grant.AXF_SEG_LKP_Collaborator__r?.Name;
    view.permission = grant.AXF_SEG_PKL_Permission__c;
    view.status = grant.AXF_SEG_PKL_Status__c;
    view.version = grant.AXF_SEG_NUM_Version__c;
    return view;
  }

  /** Expenses already referenced by a realization allocation: original evidence, immutable. */
  private static Set<Id> frozenExpenseIds(Set<Id> expenseIds) {
    Set<Id> result = new Set<Id>();
    for (AXF_OBJ_ReconciliationAllocation__c allocation : [
      SELECT AXF_RA_LKP_FinancialTransaction__c
      FROM AXF_OBJ_ReconciliationAllocation__c
      WHERE AXF_RA_LKP_FinancialTransaction__c IN :expenseIds
    ]) {
      result.add(allocation.AXF_RA_LKP_FinancialTransaction__c);
    }
    return result;
  }

  private static SharedView toSharedView(
    AXF_OBJ_FinancialTransaction__c expense,
    AXF_OBJ_SharedExpenseGrant__c grant,
    Boolean frozen
  ) {
    SharedView view = new SharedView();
    view.financialTransactionId = expense.Id;
    view.name = expense.Name;
    view.description = expense.AXF_FTX_TXT_Description__c;
    view.userCategory = expense.AXF_FTX_TXT_UserCategory__c;
    view.amount = expense.AXF_FTX_NUM_Magnitude__c;
    view.currencyIso = expense.AXF_FTX_TXT_CurrencyIsoCode__c;
    view.dueDate = expense.AXF_FTX_DAT_DueDate__c;
    view.status = expense.AXF_FTX_PKL_Status__c;
    view.version = nz(expense.AXF_FTX_NUM_Version__c);
    view.permission = grant.AXF_SEG_PKL_Permission__c;
    view.canEdit =
      grant.AXF_SEG_PKL_Permission__c == PERMISSION_EDIT &&
      expense.AXF_FTX_PKL_Status__c == STATUS_PLANNED &&
      frozen != true;
    // AXF-25 keeps its own record-access rule; only offer what can actually succeed.
    view.canRealize =
      view.canEdit &&
      FeatureManagement.checkPermission('AXF_CanRealize') &&
      hasRecordAccess(expense.Id);
    return view;
  }

  private static Boolean hasRecordAccess(Id recordId) {
    for (UserRecordAccess access : [
      SELECT RecordId, HasReadAccess
      FROM UserRecordAccess
      WHERE UserId = :UserInfo.getUserId() AND RecordId = :recordId
      LIMIT 1
    ]) {
      return access.HasReadAccess == true;
    }
    return false;
  }

  private static String grantKey(Id expenseId, Id userId) {
    return String.valueOf(expenseId) + ':' + String.valueOf(userId);
  }

  private static String clip(String value, Integer max) {
    return value == null ? null : value.left(max);
  }

  private static Decimal nz(Decimal value) {
    return value == null ? 0 : value;
  }

  private static SharedExpenseException failure(String code) {
    SharedExpenseException result = new SharedExpenseException(code);
    result.code = code;
    return result;
  }
}
