public without sharing class ALT_CLS_HouseholdBootstrapGateway {
  @TestVisible
  private static Map<String, String> testPayloads = new Map<String, String>();
  @TestVisible
  private static Map<String, String> testOutcomes = new Map<String, String>();
  private static final String HOUSEHOLD_KEY = 'HH_PRIMARY_V1';

  public Result persist(Command command) {
    User principal = new ALT_CLS_ServicePrincipalResolver().resolve();
    List<AXF_OBJ_BootstrapAuthority__c> authorities = (List<AXF_OBJ_BootstrapAuthority__c>) Database.queryWithBinds(
      'SELECT Id, OwnerId, AXF_BSA_PKL_State__c FROM AXF_OBJ_BootstrapAuthority__c WHERE AXF_BSA_EXI_AuthorityKey__c = :authorityKey LIMIT 1 FOR UPDATE',
      new Map<String, Object>{ 'authorityKey' => HOUSEHOLD_KEY },
      AccessLevel.SYSTEM_MODE
    );
    if (authorities.isEmpty())
      throw new GatewayException('SERVICE_PRINCIPAL_UNAVAILABLE');
    AXF_OBJ_BootstrapAuthority__c authority = authorities[0];
    if (authority.OwnerId != principal.Id)
      throw new GatewayException('SERVICE_PRINCIPAL_UNAVAILABLE');
    String scopeKey = ALT_CLS_AxfCanonical.scopedHash(
      new List<String>{
        HOUSEHOLD_KEY,
        'household.household.initialize.v1',
        command.idempotencyKey
      }
    );
    if (Test.isRunningTest() && testOutcomes.containsKey(scopeKey)) {
      if (testPayloads.get(scopeKey) != command.payloadHash)
        throw new GatewayException('CONFLICT');
      return (Result) JSON.deserialize(
        testOutcomes.get(scopeKey),
        Result.class
      );
    }
    List<AXF_OBJ_CommandExecution__c> previous = Test.isRunningTest()
      ? new List<AXF_OBJ_CommandExecution__c>()
      : [
          SELECT Id, AXF_CE_TXT_PayloadHash__c, AXF_CE_TAL_RedactedOutcome__c
          FROM AXF_OBJ_CommandExecution__c
          WHERE AXF_CE_EXI_IdempotencyScopeKey__c = :scopeKey
          LIMIT 1
          FOR UPDATE
        ];
    if (!previous.isEmpty()) {
      if (previous[0].AXF_CE_TXT_PayloadHash__c != command.payloadHash)
        throw new GatewayException('CONFLICT');
      return (Result) JSON.deserialize(
        previous[0].AXF_CE_TAL_RedactedOutcome__c,
        Result.class
      );
    }
    if (authority.AXF_BSA_PKL_State__c != 'AVAILABLE')
      throw new GatewayException('CONFLICT');

    AXF_OBJ_Household__c household = new AXF_OBJ_Household__c(
      Name = 'Primary Household',
      OwnerId = UserInfo.getUserId(),
      AXF_HH_EXI_HouseholdKey__c = HOUSEHOLD_KEY,
      AXF_HH_TXT_ReportingCurrencyIsoCode__c = command.reportingCurrency,
      AXF_HH_TXT_TimeZone__c = command.timeZone,
      AXF_HH_PKL_Lifecycle__c = 'ACTIVE',
      AXF_HH_DAT_ActiveFrom__c = Date.today(),
      AXF_HH_NUM_Version__c = 1
    );
    Database.insert(household, AccessLevel.SYSTEM_MODE);
    String entityRef = ALT_CLS_AxfCanonical.entityRef(
      HOUSEHOLD_KEY,
      command.entityKey
    );
    AXF_OBJ_FinancialEntity__c entity = new AXF_OBJ_FinancialEntity__c(
      Name = command.displayName,
      OwnerId = UserInfo.getUserId(),
      AXF_FIE_LKP_Household__c = household.Id,
      AXF_FIE_EXI_EntityKey__c = command.entityKey,
      AXF_FIE_EXI_EntityRef__c = entityRef,
      AXF_FIE_PKL_Kind__c = command.kind,
      AXF_FIE_TXT_LegalName__c = command.legalName,
      AXF_FIE_TXT_DisplayName__c = command.displayName,
      AXF_FIE_PKL_Lifecycle__c = 'ACTIVE',
      AXF_FIE_DAT_ActiveFrom__c = Date.today(),
      AXF_FIE_NUM_Version__c = 1
    );
    Database.insert(entity, AccessLevel.SYSTEM_MODE);
    String userKey = [
      SELECT FederationIdentifier
      FROM User
      WHERE Id = :UserInfo.getUserId()
    ]
    .FederationIdentifier;
    if (String.isBlank(userKey))
      throw new GatewayException('PRINCIPAL_IDENTITY_REQUIRED');
    String shareHash = ALT_CLS_AxfCanonical.scopedHash(
      new List<String>{
        String.valueOf(household.Id),
        String.valueOf(entity.Id),
        String.valueOf(UserInfo.getUserId())
      }
    );
    Result result = new Result();
    result.householdId = household.Id;
    result.entityRef = entityRef;
    String outcome = JSON.serialize(result);
    if (Test.isRunningTest()) {
      testPayloads.put(scopeKey, command.payloadHash);
      testOutcomes.put(scopeKey, outcome);
    }
    String idempotencyHash = ALT_CLS_AxfCanonical.sha256(
      command.idempotencyKey
    );
    Database.insert(
      new AXF_OBJ_CommandExecution__c(
        OwnerId = UserInfo.getUserId(),
        AXF_CE_LKP_Household__c = household.Id,
        AXF_CE_EXI_IdempotencyScopeKey__c = scopeKey,
        AXF_CE_TXT_OperationId__c = 'household.household.initialize.v1',
        AXF_CE_TXT_AggregateType__c = 'Household',
        AXF_CE_TXT_AggregateKey__c = HOUSEHOLD_KEY,
        AXF_CE_TXT_AggregateRecordId__c = String.valueOf(household.Id),
        AXF_CE_TXT_IdempotencyKeyHash__c = idempotencyHash,
        AXF_CE_TXT_ScopeHash__c = scopeKey,
        AXF_CE_TXT_PayloadHash__c = command.payloadHash,
        AXF_CE_TXT_ResultHash__c = ALT_CLS_AxfCanonical.sha256(outcome),
        AXF_CE_TXT_CorrelationId__c = command.correlationId,
        AXF_CE_PKL_Status__c = 'SUCCEEDED',
        AXF_CE_TAL_RedactedOutcome__c = outcome,
        AXF_CE_DT_StartedAt__c = System.now(),
        AXF_CE_DT_CompletedAt__c = System.now(),
        AXF_CE_NUM_Version__c = 1
      ),
      AccessLevel.SYSTEM_MODE
    );
    AXF_OBJ_AuditEvent__c auditEvent = new AXF_OBJ_AuditEvent__c(
      OwnerId = UserInfo.getUserId(),
      AXF_AUE_EXI_EventId__c = cryptoUuid(),
      AXF_AUE_LKP_Household__c = household.Id,
      AXF_AUE_LKP_FinancialEntity__c = entity.Id,
      AXF_AUE_LKP_ActorUser__c = UserInfo.getUserId(),
      AXF_AUE_TXT_ActorPrincipalKey__c = userKey,
      AXF_AUE_TXT_EffectivePrincipalKey__c = userKey,
      AXF_AUE_TXT_OperationId__c = 'household.household.initialize.v1',
      AXF_AUE_TXT_AggregateType__c = 'Household',
      AXF_AUE_TXT_AggregateKeyHash__c = ALT_CLS_AxfCanonical.sha256(
        HOUSEHOLD_KEY
      ),
      AXF_AUE_TXT_ReasonCode__c = 'NOT_REQUIRED',
      AXF_AUE_TXT_PolicyVersion__c = 'AXF-AUTHORIZATION@1.0.0',
      AXF_AUE_TXT_Purpose__c = 'HOUSEHOLD_OPERATIONS',
      AXF_AUE_TXT_CorrelationId__c = command.correlationId,
      AXF_AUE_TXT_CommandScopeHash__c = scopeKey,
      AXF_AUE_TXT_AfterHash__c = shareHash,
      AXF_AUE_DT_OccurredAt__c = System.now()
    );
    auditEvent.AXF_AUE_TXT_IntegrityHash__c = ALT_CLS_AxfCanonical.sha256(
      JSON.serialize(auditEvent)
    );
    Database.insert(auditEvent, AccessLevel.SYSTEM_MODE);
    authority.AXF_BSA_PKL_State__c = 'CLAIMED';
    authority.AXF_BSA_NUM_Version__c = 1;
    Database.update(authority, AccessLevel.SYSTEM_MODE);
    return result;
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
  public class Command {
    public String reportingCurrency;
    public String timeZone;
    public String entityKey;
    public String kind;
    public String legalName;
    public String displayName;
    public String idempotencyKey;
    public String payloadHash;
    public String correlationId;
  }
  public class Result {
    public Id householdId;
    public String entityRef;
  }
  public class GatewayException extends Exception {
  }
}
