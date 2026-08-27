public with sharing class ALT_CLS_EntityAccessService {
  @TestVisible
  private static Boolean allowInTests = false;
  private static final String ASSIGN = 'authorization.entity-access.assign.v1';
  private static final String REMOVE = 'authorization.entity-access.remove.v1';
  private static final String UUID = '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$';

  public Result assign(Request request) {
    return atomicChange(request, false);
  }
  public Result remove(Request request) {
    return atomicChange(request, true);
  }

  private Result atomicChange(Request request, Boolean removing) {
    Savepoint checkpoint = Database.setSavepoint();
    try {
      return change(request, removing);
    } catch (Exception failure) {
      Database.rollback(checkpoint);
      throw new AccessException(
        failure instanceof AccessException && failure.getMessage() == 'CONFLICT'
          ? 'CONFLICT'
          : 'FORBIDDEN'
      );
    }
  }

  private Result change(Request request, Boolean removing) {
    validate(request, removing);
    String actor = [
      SELECT FederationIdentifier
      FROM User
      WHERE Id = :UserInfo.getUserId()
    ]
    .FederationIdentifier;
    if (String.isBlank(actor))
      fail('FORBIDDEN');
    List<AXF_OBJ_Household__c> households = [
      SELECT Id, OwnerId, AXF_HH_NUM_Version__c
      FROM AXF_OBJ_Household__c
      WHERE Id = :request.householdId
      LIMIT 1
      FOR UPDATE
    ];
    if (households.isEmpty())
      fail('FORBIDDEN');
    AXF_OBJ_Household__c household = households[0];
    if (household.OwnerId != UserInfo.getUserId())
      fail('FORBIDDEN');
    List<AXF_OBJ_FinancialEntity__c> entities = [
      SELECT Id
      FROM AXF_OBJ_FinancialEntity__c
      WHERE Id = :request.entityId AND AXF_FIE_LKP_Household__c = :household.Id
      LIMIT 1
      FOR UPDATE
    ];
    if (entities.isEmpty())
      fail('FORBIDDEN');
    AXF_OBJ_FinancialEntity__c entity = entities[0];
    List<User> targets = [
      SELECT Id, IsActive, UserType, Profile.PermissionsModifyAllData
      FROM User
      WHERE Id = :request.targetUserId
      LIMIT 1
    ];
    if (
      targets.isEmpty() ||
      (!removing &&
      (!targets[0].IsActive ||
      targets[0].UserType != 'Standard' ||
      targets[0].Profile.PermissionsModifyAllData ||
      request.targetUserId == UserInfo.getUserId()))
    )
      fail('FORBIDDEN');
    String operationId = removing ? REMOVE : ASSIGN;
    String payloadHash = ALT_CLS_AxfCanonical.sha256(JSON.serialize(request));
    String scope = ALT_CLS_AxfCanonical.scopedHash(
      new List<String>{
        String.valueOf(household.Id),
        String.valueOf(entity.Id),
        String.valueOf(request.targetUserId),
        operationId,
        request.idempotencyKey
      }
    );
    List<AXF_OBJ_CommandExecution__c> previous = [
      SELECT AXF_CE_TXT_PayloadHash__c, AXF_CE_TAL_RedactedOutcome__c
      FROM AXF_OBJ_CommandExecution__c
      WHERE AXF_CE_EXI_IdempotencyScopeKey__c = :scope
      LIMIT 1
      FOR UPDATE
    ];
    if (!previous.isEmpty()) {
      if (previous[0].AXF_CE_TXT_PayloadHash__c != payloadHash)
        fail('CONFLICT');
      return (Result) JSON.deserialize(
        previous[0].AXF_CE_TAL_RedactedOutcome__c,
        Result.class
      );
    }
    if (household.AXF_HH_NUM_Version__c != request.expectedVersion)
      fail('CONFLICT');
    List<AXF_OBJ_FinancialEntity__Share> entityShares = [
      SELECT Id, AccessLevel
      FROM AXF_OBJ_FinancialEntity__Share
      WHERE
        ParentId = :entity.Id
        AND UserOrGroupId = :request.targetUserId
        AND RowCause = 'AXF_EntityGrant__c'
      FOR UPDATE
    ];
    if (removing) {
      if (!entityShares.isEmpty())
        Database.delete(entityShares, AccessLevel.SYSTEM_MODE);
    } else {
      String access = request.role == 'EDITOR' ? 'Edit' : 'Read';
      if (entityShares.isEmpty())
        Database.insert(
          new AXF_OBJ_FinancialEntity__Share(
            ParentId = entity.Id,
            UserOrGroupId = request.targetUserId,
            AccessLevel = access,
            RowCause = Schema.AXF_OBJ_FinancialEntity__Share.RowCause.AXF_EntityGrant__c
          ),
          AccessLevel.SYSTEM_MODE
        );
      else if (entityShares[0].AccessLevel != access) {
        entityShares[0].AccessLevel = access;
        Database.update(entityShares[0], AccessLevel.SYSTEM_MODE);
      }
      ensureHouseholdShare(household.Id, request.targetUserId);
    }
    if (removing)
      removeUnusedHouseholdShare(household.Id, request.targetUserId);
    household.AXF_HH_NUM_Version__c++;
    Database.update(household, AccessLevel.SYSTEM_MODE);
    Result result = new Result();
    result.entityId = entity.Id;
    result.targetUserId = request.targetUserId;
    result.role = removing ? null : request.role;
    result.householdVersion = household.AXF_HH_NUM_Version__c;
    List<UserRecordAccess> accessRows = [
      SELECT RecordId, HasReadAccess, HasEditAccess
      FROM UserRecordAccess
      WHERE UserId = :request.targetUserId AND RecordId = :entity.Id
    ];
    result.hasRemainingAccess =
      !accessRows.isEmpty() && accessRows[0].HasReadAccess;
    String outcome = JSON.serialize(result);
    Database.insert(
      new AXF_OBJ_CommandExecution__c(
        OwnerId = UserInfo.getUserId(),
        AXF_CE_LKP_Household__c = household.Id,
        AXF_CE_EXI_IdempotencyScopeKey__c = scope,
        AXF_CE_TXT_OperationId__c = operationId,
        AXF_CE_TXT_AggregateType__c = 'FinancialEntity',
        AXF_CE_TXT_AggregateKey__c = String.valueOf(entity.Id),
        AXF_CE_TXT_AggregateRecordId__c = String.valueOf(entity.Id),
        AXF_CE_TXT_IdempotencyKeyHash__c = ALT_CLS_AxfCanonical.sha256(
          request.idempotencyKey
        ),
        AXF_CE_TXT_ScopeHash__c = scope,
        AXF_CE_TXT_PayloadHash__c = payloadHash,
        AXF_CE_TXT_ResultHash__c = ALT_CLS_AxfCanonical.sha256(outcome),
        AXF_CE_TXT_CorrelationId__c = request.correlationId,
        AXF_CE_PKL_Status__c = 'SUCCEEDED',
        AXF_CE_TAL_RedactedOutcome__c = outcome,
        AXF_CE_DT_StartedAt__c = System.now(),
        AXF_CE_DT_CompletedAt__c = System.now(),
        AXF_CE_NUM_Version__c = 1
      ),
      AccessLevel.SYSTEM_MODE
    );
    AXF_OBJ_AuditEvent__c audit = new AXF_OBJ_AuditEvent__c(
      OwnerId = UserInfo.getUserId(),
      AXF_AUE_EXI_EventId__c = uuid(),
      AXF_AUE_LKP_Household__c = household.Id,
      AXF_AUE_LKP_FinancialEntity__c = entity.Id,
      AXF_AUE_LKP_ActorUser__c = UserInfo.getUserId(),
      AXF_AUE_TXT_ActorPrincipalKey__c = actor,
      AXF_AUE_TXT_EffectivePrincipalKey__c = actor,
      AXF_AUE_TXT_OperationId__c = operationId,
      AXF_AUE_TXT_AggregateType__c = 'FinancialEntity',
      AXF_AUE_TXT_AggregateKeyHash__c = ALT_CLS_AxfCanonical.sha256(
        String.valueOf(entity.Id)
      ),
      AXF_AUE_TXT_ReasonCode__c = 'NOT_REQUIRED',
      AXF_AUE_TXT_CommandScopeHash__c = scope,
      AXF_AUE_TXT_CorrelationId__c = request.correlationId,
      AXF_AUE_TXT_AfterHash__c = ALT_CLS_AxfCanonical.sha256(outcome),
      AXF_AUE_DT_OccurredAt__c = System.now()
    );
    audit.AXF_AUE_TXT_IntegrityHash__c = ALT_CLS_AxfCanonical.sha256(
      JSON.serialize(audit)
    );
    Database.insert(audit, AccessLevel.SYSTEM_MODE);
    return result;
  }
  private static void ensureHouseholdShare(Id householdId, Id userId) {
    if (
      [
        SELECT COUNT()
        FROM AXF_OBJ_Household__Share
        WHERE
          ParentId = :householdId
          AND UserOrGroupId = :userId
          AND RowCause = 'AXF_HouseholdGrant__c'
      ] == 0
    )
      Database.insert(
        new AXF_OBJ_Household__Share(
          ParentId = householdId,
          UserOrGroupId = userId,
          AccessLevel = 'Read',
          RowCause = Schema.AXF_OBJ_Household__Share.RowCause.AXF_HouseholdGrant__c
        ),
        AccessLevel.SYSTEM_MODE
      );
  }
  private static void removeUnusedHouseholdShare(Id householdId, Id userId) {
    List<AXF_OBJ_FinancialEntity__Share> remaining = [
      SELECT Id
      FROM AXF_OBJ_FinancialEntity__Share
      WHERE
        Parent.AXF_FIE_LKP_Household__c = :householdId
        AND UserOrGroupId = :userId
        AND RowCause = 'AXF_EntityGrant__c'
      LIMIT 1
    ];
    if (remaining.isEmpty()) {
      List<AXF_OBJ_Household__Share> rows = [
        SELECT Id
        FROM AXF_OBJ_Household__Share
        WHERE
          ParentId = :householdId
          AND UserOrGroupId = :userId
          AND RowCause = 'AXF_HouseholdGrant__c'
      ];
      if (!rows.isEmpty())
        Database.delete(rows, AccessLevel.SYSTEM_MODE);
    }
  }
  private static void validate(Request r, Boolean removing) {
    if (
      r == null ||
      r.householdId == null ||
      r.entityId == null ||
      r.targetUserId == null ||
      r.expectedVersion == null ||
      !Pattern.matches(UUID, String.valueOf(r.idempotencyKey)) ||
      !Pattern.matches(UUID, String.valueOf(r.correlationId)) ||
      (!removing && !new Set<String>{ 'VIEWER', 'EDITOR' }.contains(r.role)) ||
      !isSystemAdministrator() ||
      (!(Test.isRunningTest() && allowInTests) &&
      !FeatureManagement.checkPermission('AXF_AssignEntityAccess'))
    )
      fail('FORBIDDEN');
  }
  public static Boolean canManageAccess(Id householdOwnerId) {
    return householdOwnerId == UserInfo.getUserId() &&
      FeatureManagement.checkPermission('AXF_AssignEntityAccess') &&
      isSystemAdministrator();
  }
  private static Boolean isSystemAdministrator() {
    return [
      SELECT Profile.PermissionsModifyAllData
      FROM User
      WHERE Id = :UserInfo.getUserId()
    ]
    .Profile.PermissionsModifyAllData;
  }
  private static void fail(String code) {
    throw new AccessException(code);
  }
  private static String uuid() {
    String h = EncodingUtil.convertToHex(Crypto.generateAesKey(128))
      .toLowerCase();
    return h.substring(0, 8) +
      '-' +
      h.substring(8, 12) +
      '-4' +
      h.substring(13, 16) +
      '-a' +
      h.substring(17, 20) +
      '-' +
      h.substring(20, 32);
  }
  public class Request {
    @AuraEnabled
    public Id householdId;
    @AuraEnabled
    public Id entityId;
    @AuraEnabled
    public Id targetUserId;
    @AuraEnabled
    public String role;
    @AuraEnabled
    public Decimal expectedVersion;
    @AuraEnabled
    public String idempotencyKey;
    @AuraEnabled
    public String correlationId;
  }
  public class Result {
    @AuraEnabled
    public Id entityId;
    @AuraEnabled
    public Id targetUserId;
    @AuraEnabled
    public String role;
    @AuraEnabled
    public Decimal householdVersion;
    @AuraEnabled
    public Boolean hasRemainingAccess;
  }
  public class AccessException extends Exception {
  }
}
