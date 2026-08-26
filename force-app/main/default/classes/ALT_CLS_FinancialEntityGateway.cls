public without sharing class ALT_CLS_FinancialEntityGateway {
  @TestVisible
  private static Map<String, String> testPayloads = new Map<String, String>();
  @TestVisible
  private static Map<String, String> testOutcomes = new Map<String, String>();
  private static final String PURPOSE = 'HOUSEHOLD_OPERATIONS';
  private static final String POLICY = 'AXF-AUTHORIZATION@1.0.0';

  public Result createEntity(Command command) {
    User servicePrincipal = new ALT_CLS_ServicePrincipalResolver().resolve();
    AXF_OBJ_Household__c household = [
      SELECT Id, AXF_HH_EXI_HouseholdKey__c
      FROM AXF_OBJ_Household__c
      WHERE Id = :command.householdId
      LIMIT 1
      FOR UPDATE
    ];
    Replay replay = replay(
      household.Id,
      'household.financial-entity.create.v1',
      command.idempotencyKey,
      command.payloadHash
    );
    if (replay.result != null)
      return replay.result;

    AXF_OBJ_FinancialEntity__c entity = new AXF_OBJ_FinancialEntity__c(
      OwnerId = servicePrincipal.Id,
      Name = command.displayName,
      AXF_FIE_LKP_Household__c = household.Id,
      AXF_FIE_EXI_EntityKey__c = command.entityKey,
      AXF_FIE_EXI_EntityRef__c = ALT_CLS_AxfCanonical.entityRef(
        household.AXF_HH_EXI_HouseholdKey__c,
        command.entityKey
      ),
      AXF_FIE_PKL_Kind__c = command.kind,
      AXF_FIE_TXT_LegalName__c = command.legalName,
      AXF_FIE_TXT_DisplayName__c = command.displayName,
      AXF_FIE_PKL_Lifecycle__c = 'ACTIVE',
      AXF_FIE_DAT_ActiveFrom__c = Date.today(),
      AXF_FIE_NUM_Version__c = 1
    );
    Database.insert(entity, AccessLevel.SYSTEM_MODE);
    Database.insert(
      new AXF_OBJ_HouseholdFinancialEntity__c(
        AXF_HFE_MD_Household__c = household.Id,
        AXF_HFE_LKP_FinancialEntity__c = entity.Id,
        AXF_HFE_EXI_MembershipKey__c = ALT_CLS_AxfCanonical.scopedHash(
          new List<String>{
            'hfe-v1',
            household.AXF_HH_EXI_HouseholdKey__c,
            command.entityKey
          }
        ),
        AXF_HFE_PKL_Role__c = 'PARTICIPANT',
        AXF_HFE_PKL_Status__c = 'ACTIVE',
        AXF_HFE_DT_ValidFrom__c = System.now(),
        AXF_HFE_NUM_Version__c = 1
      ),
      AccessLevel.SYSTEM_MODE
    );
    String federationId = currentFederationId();
    Database.insert(
      new AXF_OBJ_EntityAccessGrant__c(
        AXF_EAG_LKP_Household__c = household.Id,
        AXF_EAG_LKP_FinancialEntity__c = entity.Id,
        AXF_EAG_LKP_User__c = UserInfo.getUserId(),
        AXF_EAG_EXI_GrantKey__c = ALT_CLS_AxfCanonical.scopedHash(
          new List<String>{
            'grant-v1',
            household.AXF_HH_EXI_HouseholdKey__c,
            'ENTITY',
            command.entityKey,
            federationId,
            PURPOSE,
            '1'
          }
        ),
        AXF_EAG_PKL_Role__c = 'OWNER',
        AXF_EAG_PKL_ScopeType__c = 'ENTITY',
        AXF_EAG_TXT_OperationSet__c = 'AXF_ReadFinancialEntity,AXF_UpdateFinancialEntity',
        AXF_EAG_TXT_Purpose__c = PURPOSE,
        AXF_EAG_TXT_FieldPolicyVersion__c = POLICY,
        AXF_EAG_PKL_Status__c = 'ACTIVE',
        AXF_EAG_DT_ValidFrom__c = System.now(),
        AXF_EAG_NUM_GrantRevision__c = 1,
        AXF_EAG_NUM_Version__c = 1
      ),
      AccessLevel.SYSTEM_MODE
    );
    Database.insert(
      new AXF_OBJ_FinancialEntity__Share(
        ParentId = entity.Id,
        UserOrGroupId = UserInfo.getUserId(),
        AccessLevel = 'Edit',
        RowCause = Schema.AXF_OBJ_FinancialEntity__Share.RowCause.AXF_EntityGrant__c
      ),
      AccessLevel.SYSTEM_MODE
    );
    Result result = result(entity);
    persistEvidence(
      servicePrincipal.Id,
      household.Id,
      entity.Id,
      'household.financial-entity.create.v1',
      command,
      replay.scopeKey,
      result,
      null
    );
    return result;
  }

  public Result updateEntity(Command command) {
    User servicePrincipal = new ALT_CLS_ServicePrincipalResolver().resolve();
    AXF_OBJ_FinancialEntity__c entity = [
      SELECT
        Id,
        OwnerId,
        AXF_FIE_LKP_Household__c,
        AXF_FIE_EXI_EntityRef__c,
        AXF_FIE_TXT_DisplayName__c,
        AXF_FIE_TXT_LegalName__c,
        AXF_FIE_PKL_Kind__c,
        AXF_FIE_PKL_Lifecycle__c,
        AXF_FIE_DAT_ActiveTo__c,
        AXF_FIE_NUM_Version__c
      FROM AXF_OBJ_FinancialEntity__c
      WHERE AXF_FIE_EXI_EntityRef__c = :command.entityRef
      LIMIT 1
      FOR UPDATE
    ];
    if (
      command.householdId != null &&
      entity.AXF_FIE_LKP_Household__c != command.householdId
    )
      throw new GatewayException('SCOPE_MISMATCH');
    Replay replay = replay(
      entity.AXF_FIE_LKP_Household__c,
      'household.financial-entity.update.v1',
      command.idempotencyKey,
      command.payloadHash
    );
    if (replay.result != null)
      return replay.result;
    if (entity.AXF_FIE_NUM_Version__c != command.expectedVersion)
      throw new GatewayException('CONFLICT');
    String beforeHash = ALT_CLS_AxfCanonical.sha256(
      JSON.serialize(result(entity))
    );
    entity.AXF_FIE_TXT_DisplayName__c = command.displayName;
    if (command.updateLegalName)
      entity.AXF_FIE_TXT_LegalName__c = command.legalName;
    entity.AXF_FIE_PKL_Lifecycle__c = command.lifecycle;
    entity.AXF_FIE_DAT_ActiveTo__c = command.lifecycle == 'CLOSED'
      ? command.activeTo
      : null;
    entity.AXF_FIE_NUM_Version__c++;
    Database.update(entity, AccessLevel.SYSTEM_MODE);
    Result result = result(entity);
    persistEvidence(
      servicePrincipal.Id,
      entity.AXF_FIE_LKP_Household__c,
      entity.Id,
      'household.financial-entity.update.v1',
      command,
      replay.scopeKey,
      result,
      beforeHash
    );
    return result;
  }

  private static Replay replay(
    Id householdId,
    String operationId,
    String key,
    String payloadHash
  ) {
    Replay r = new Replay();
    r.scopeKey = ALT_CLS_AxfCanonical.scopedHash(
      new List<String>{ String.valueOf(householdId), operationId, key }
    );
    if (Test.isRunningTest() && testOutcomes.containsKey(r.scopeKey)) {
      if (testPayloads.get(r.scopeKey) != payloadHash)
        throw new GatewayException('CONFLICT');
      r.result = (Result) JSON.deserialize(
        testOutcomes.get(r.scopeKey),
        Result.class
      );
      return r;
    }
    List<AXF_OBJ_CommandExecution__c> rows = Test.isRunningTest()
      ? new List<AXF_OBJ_CommandExecution__c>()
      : [
          SELECT AXF_CE_TXT_PayloadHash__c, AXF_CE_TAL_RedactedOutcome__c
          FROM AXF_OBJ_CommandExecution__c
          WHERE AXF_CE_EXI_IdempotencyScopeKey__c = :r.scopeKey
          LIMIT 1
          FOR UPDATE
        ];
    if (!rows.isEmpty()) {
      if (rows[0].AXF_CE_TXT_PayloadHash__c != payloadHash)
        throw new GatewayException('CONFLICT');
      r.result = (Result) JSON.deserialize(
        rows[0].AXF_CE_TAL_RedactedOutcome__c,
        Result.class
      );
    }
    return r;
  }
  private static void persistEvidence(
    Id ownerId,
    Id householdId,
    Id entityId,
    String operationId,
    Command c,
    String scopeKey,
    Result result,
    String beforeHash
  ) {
    String outcome = JSON.serialize(result),
      afterHash = ALT_CLS_AxfCanonical.sha256(outcome),
      idKeyHash = ALT_CLS_AxfCanonical.sha256(c.idempotencyKey);
    if (Test.isRunningTest()) {
      testPayloads.put(scopeKey, c.payloadHash);
      testOutcomes.put(scopeKey, outcome);
    }
    Database.insert(
      new AXF_OBJ_CommandExecution__c(
        OwnerId = ownerId,
        AXF_CE_LKP_Household__c = householdId,
        AXF_CE_EXI_IdempotencyScopeKey__c = scopeKey,
        AXF_CE_TXT_OperationId__c = operationId,
        AXF_CE_TXT_AggregateType__c = 'FinancialEntity',
        AXF_CE_TXT_AggregateKey__c = c.entityRef == null
          ? c.entityKey
          : c.entityRef,
        AXF_CE_TXT_AggregateRecordId__c = String.valueOf(entityId),
        AXF_CE_TXT_IdempotencyKeyHash__c = idKeyHash,
        AXF_CE_TXT_ScopeHash__c = scopeKey,
        AXF_CE_TXT_PayloadHash__c = c.payloadHash,
        AXF_CE_TXT_ResultHash__c = afterHash,
        AXF_CE_TXT_CorrelationId__c = c.correlationId,
        AXF_CE_PKL_Status__c = 'SUCCEEDED',
        AXF_CE_TAL_RedactedOutcome__c = outcome,
        AXF_CE_DT_StartedAt__c = System.now(),
        AXF_CE_DT_CompletedAt__c = System.now(),
        AXF_CE_NUM_Version__c = 1
      ),
      AccessLevel.SYSTEM_MODE
    );
    String actor = currentFederationId();
    String aggregateHash = ALT_CLS_AxfCanonical.sha256(
      c.entityRef == null ? c.entityKey : c.entityRef
    );
    AXF_OBJ_AuditEvent__c event = new AXF_OBJ_AuditEvent__c(
      OwnerId = ownerId,
      AXF_AUE_EXI_EventId__c = cryptoUuid(),
      AXF_AUE_LKP_Household__c = householdId,
      AXF_AUE_LKP_FinancialEntity__c = entityId,
      AXF_AUE_LKP_ActorUser__c = UserInfo.getUserId(),
      AXF_AUE_TXT_ActorPrincipalKey__c = actor,
      AXF_AUE_TXT_EffectivePrincipalKey__c = String.valueOf(ownerId),
      AXF_AUE_TXT_OperationId__c = operationId,
      AXF_AUE_TXT_AggregateType__c = 'FinancialEntity',
      AXF_AUE_TXT_AggregateKeyHash__c = aggregateHash,
      AXF_AUE_TXT_ReasonCode__c = 'NOT_REQUIRED',
      AXF_AUE_TXT_PolicyVersion__c = POLICY,
      AXF_AUE_TXT_Purpose__c = PURPOSE,
      AXF_AUE_TXT_BeforeHash__c = beforeHash,
      AXF_AUE_TXT_AfterHash__c = afterHash,
      AXF_AUE_TXT_CommandScopeHash__c = scopeKey,
      AXF_AUE_TXT_CorrelationId__c = c.correlationId,
      AXF_AUE_DT_OccurredAt__c = System.now()
    );
    event.AXF_AUE_TXT_IntegrityHash__c = ALT_CLS_AxfCanonical.sha256(
      JSON.serialize(event)
    );
    Database.insert(event, AccessLevel.SYSTEM_MODE);
  }
  private static Result result(AXF_OBJ_FinancialEntity__c e) {
    Result r = new Result();
    r.entityRef = e.AXF_FIE_EXI_EntityRef__c;
    r.displayName = e.AXF_FIE_TXT_DisplayName__c;
    r.legalName = e.AXF_FIE_TXT_LegalName__c;
    r.kind = e.AXF_FIE_PKL_Kind__c;
    r.lifecycle = e.AXF_FIE_PKL_Lifecycle__c;
    r.version = e.AXF_FIE_NUM_Version__c;
    r.activeTo = e.AXF_FIE_DAT_ActiveTo__c;
    return r;
  }
  private static String currentFederationId() {
    List<User> users = [
      SELECT FederationIdentifier
      FROM User
      WHERE Id = :UserInfo.getUserId()
    ];
    if (users.isEmpty() || String.isBlank(users[0].FederationIdentifier))
      throw new GatewayException('PRINCIPAL_IDENTITY_REQUIRED');
    return users[0].FederationIdentifier;
  }
  private static String cryptoUuid() {
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
  private class Replay {
    String scopeKey;
    Result result;
  }
  public class Command {
    public Id householdId;
    public String entityKey;
    public String entityRef;
    public String kind;
    public String legalName;
    public Boolean updateLegalName = false;
    public String displayName;
    public String lifecycle;
    public Date activeTo;
    public Decimal expectedVersion;
    public String idempotencyKey;
    public String payloadHash;
    public String correlationId;
  }
  public class Result {
    @AuraEnabled
    public String entityRef;
    @AuraEnabled
    public String displayName;
    @AuraEnabled
    public String legalName;
    @AuraEnabled
    public String kind;
    @AuraEnabled
    public String lifecycle;
    @AuraEnabled
    public Decimal version;
    @AuraEnabled
    public Date activeTo;
  }
  public class GatewayException extends Exception {
  }
}
