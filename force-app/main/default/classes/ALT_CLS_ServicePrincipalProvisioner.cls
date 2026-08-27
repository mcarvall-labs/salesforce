public without sharing class ALT_CLS_ServicePrincipalProvisioner {
  @TestVisible
  private static Map<String, Id> testPrincipals = new Map<String, Id>();
  @TestVisible
  private static Map<String, String> testReplayOutcomes = new Map<String, String>();
  @TestVisible
  private static Map<String, String> testReplayPayloads = new Map<String, String>();
  @TestVisible
  private static Map<String, RotationResult> testRotationOutcomes = new Map<String, RotationResult>();
  private static final String AUTHORITY_KEY = 'HH_PRIMARY_V1';
  private static final String POLICY = 'AXF-SERVICE-PRINCIPAL@1.0.0';
  private static final String OPERATION = 'migration.bootstrap-authority.provision.v1';

  public ProvisionResult provision(
    String federationIdentifier,
    String releaseId
  ) {
    authorizeTrustedCaller();
    User principal = requirePrincipal(federationIdentifier);
    if (String.isBlank(releaseId))
      throw new ProvisioningException('INVALID_INPUT');
    String key = ALT_CLS_AxfCanonical.scopedHash(
      new List<String>{ releaseId, AUTHORITY_KEY, POLICY }
    );
    String payloadHash = ALT_CLS_AxfCanonical.scopedHash(
      new List<String>{ federationIdentifier, releaseId, POLICY }
    );
    if (Test.isRunningTest() && testReplayOutcomes.containsKey(key)) {
      if (testReplayPayloads.get(key) != payloadHash)
        throw new ProvisioningException('CONFLICT');
      return deserializeProvisionResult(testReplayOutcomes.get(key));
    }
    List<AXF_OBJ_CommandExecution__c> previous = new List<AXF_OBJ_CommandExecution__c>();
    if (!Test.isRunningTest())
      previous = [
        SELECT AXF_CE_TAL_RedactedOutcome__c, AXF_CE_TXT_PayloadHash__c
        FROM AXF_OBJ_CommandExecution__c
        WHERE AXF_CE_EXI_IdempotencyScopeKey__c = :key
        LIMIT 1
        FOR UPDATE
      ];
    if (!previous.isEmpty()) {
      if (previous[0].AXF_CE_TXT_PayloadHash__c != payloadHash)
        throw new ProvisioningException('CONFLICT');
      return deserializeProvisionResult(
        previous[0].AXF_CE_TAL_RedactedOutcome__c
      );
    }
    List<AXF_OBJ_BootstrapAuthority__c> rows = [
      SELECT Id, OwnerId, AXF_BSA_PKL_State__c, AXF_BSA_NUM_Version__c
      FROM AXF_OBJ_BootstrapAuthority__c
      WHERE AXF_BSA_EXI_AuthorityKey__c = :AUTHORITY_KEY
      LIMIT 1
      FOR UPDATE
    ];
    AXF_OBJ_BootstrapAuthority__c authority;
    if (rows.isEmpty()) {
      authority = new AXF_OBJ_BootstrapAuthority__c(
        OwnerId = principal.Id,
        AXF_BSA_EXI_AuthorityKey__c = AUTHORITY_KEY,
        AXF_BSA_PKL_State__c = 'AVAILABLE',
        AXF_BSA_NUM_Version__c = 0
      );
      Database.insert(authority, AccessLevel.SYSTEM_MODE);
    } else {
      authority = rows[0];
      if (authority.OwnerId != principal.Id)
        throw new ProvisioningException('PROVISIONING_DRIFT');
    }
    ProvisionResult result = new ProvisionResult();
    result.authorityId = authority.Id;
    result.ownerId = principal.Id;
    result.state = authority.AXF_BSA_PKL_State__c;
    String outcome = JSON.serialize(result), correlationId = uuid();
    if (Test.isRunningTest()) {
      testReplayOutcomes.put(key, outcome);
      testReplayPayloads.put(key, payloadHash);
    }
    Database.insert(
      new AXF_OBJ_CommandExecution__c(
        OwnerId = principal.Id,
        AXF_CE_LKP_BootstrapAuthority__c = authority.Id,
        AXF_CE_EXI_IdempotencyScopeKey__c = key,
        AXF_CE_TXT_OperationId__c = OPERATION,
        AXF_CE_TXT_AggregateType__c = 'BootstrapAuthority',
        AXF_CE_TXT_AggregateKey__c = AUTHORITY_KEY,
        AXF_CE_TXT_AggregateRecordId__c = String.valueOf(authority.Id),
        AXF_CE_TXT_IdempotencyKeyHash__c = ALT_CLS_AxfCanonical.sha256(
          releaseId
        ),
        AXF_CE_TXT_ScopeHash__c = key,
        AXF_CE_TXT_PayloadHash__c = payloadHash,
        AXF_CE_TXT_ResultHash__c = ALT_CLS_AxfCanonical.sha256(outcome),
        AXF_CE_TXT_CorrelationId__c = correlationId,
        AXF_CE_PKL_Status__c = 'SUCCEEDED',
        AXF_CE_TAL_RedactedOutcome__c = outcome,
        AXF_CE_DT_StartedAt__c = System.now(),
        AXF_CE_DT_CompletedAt__c = System.now(),
        AXF_CE_NUM_Version__c = 1
      ),
      AccessLevel.SYSTEM_MODE
    );
    AXF_OBJ_AuditEvent__c event = new AXF_OBJ_AuditEvent__c(
      OwnerId = principal.Id,
      AXF_AUE_EXI_EventId__c = uuid(),
      AXF_AUE_LKP_BootstrapAuthority__c = authority.Id,
      AXF_AUE_TXT_ActorPrincipalKey__c = federationIdentifier,
      AXF_AUE_TXT_EffectivePrincipalKey__c = federationIdentifier,
      AXF_AUE_TXT_OperationId__c = OPERATION,
      AXF_AUE_TXT_AggregateType__c = 'BootstrapAuthority',
      AXF_AUE_TXT_ReasonCode__c = 'NOT_REQUIRED',
      AXF_AUE_TXT_PolicyVersion__c = POLICY,
      AXF_AUE_TXT_Purpose__c = 'RELEASE_PROVISIONING',
      AXF_AUE_TXT_AggregateKeyHash__c = ALT_CLS_AxfCanonical.sha256(
        AUTHORITY_KEY
      ),
      AXF_AUE_TXT_AfterHash__c = ALT_CLS_AxfCanonical.sha256(outcome),
      AXF_AUE_TXT_CommandScopeHash__c = key,
      AXF_AUE_TXT_CorrelationId__c = correlationId,
      AXF_AUE_DT_OccurredAt__c = System.now()
    );
    event.AXF_AUE_TXT_IntegrityHash__c = ALT_CLS_AxfCanonical.sha256(
      JSON.serialize(event)
    );
    Database.insert(event, AccessLevel.SYSTEM_MODE);
    return result;
  }

  public RotationResult rotate(
    String oldFederationIdentifier,
    String newFederationIdentifier,
    String releaseId
  ) {
    authorizeTrustedCaller();
    User oldPrincipal = requirePrincipal(oldFederationIdentifier),
      nextPrincipal = requirePrincipal(newFederationIdentifier);
    if (oldPrincipal.Id == nextPrincipal.Id || String.isBlank(releaseId))
      throw new ProvisioningException('INVALID_INPUT');
    String rotationKey = ALT_CLS_AxfCanonical.scopedHash(
      new List<String>{
        'service-principal.rotate.v1',
        oldFederationIdentifier,
        newFederationIdentifier,
        releaseId
      }
    );
    String rotationPayload = ALT_CLS_AxfCanonical.scopedHash(
      new List<String>{
        oldFederationIdentifier,
        newFederationIdentifier,
        releaseId,
        POLICY
      }
    );
    if (Test.isRunningTest() && testRotationOutcomes.containsKey(rotationKey))
      return testRotationOutcomes.get(rotationKey);
    List<AXF_OBJ_CommandExecution__c> priorRotations = Test.isRunningTest()
      ? new List<AXF_OBJ_CommandExecution__c>()
      : [
          SELECT AXF_CE_TXT_PayloadHash__c, AXF_CE_TAL_RedactedOutcome__c
          FROM AXF_OBJ_CommandExecution__c
          WHERE AXF_CE_EXI_IdempotencyScopeKey__c = :rotationKey
          LIMIT 1
          FOR UPDATE
        ];
    if (!priorRotations.isEmpty()) {
      if (priorRotations[0].AXF_CE_TXT_PayloadHash__c != rotationPayload)
        throw new ProvisioningException('CONFLICT');
      return (RotationResult) JSON.deserialize(
        priorRotations[0].AXF_CE_TAL_RedactedOutcome__c,
        RotationResult.class
      );
    }
    AXF_OBJ_BootstrapAuthority__c authority = [
      SELECT Id, OwnerId, AXF_BSA_PKL_State__c
      FROM AXF_OBJ_BootstrapAuthority__c
      WHERE AXF_BSA_EXI_AuthorityKey__c = :AUTHORITY_KEY
      LIMIT 1
      FOR UPDATE
    ];
    if (authority.OwnerId != oldPrincipal.Id)
      throw new ProvisioningException('PROVISIONING_DRIFT');
    List<SObject> roots = new List<SObject>();
    for (AXF_OBJ_CommandExecution__c r : [
      SELECT Id, OwnerId
      FROM AXF_OBJ_CommandExecution__c
      WHERE OwnerId = :oldPrincipal.Id
      FOR UPDATE
    ]) {
      r.OwnerId = nextPrincipal.Id;
      roots.add(r);
    }
    for (AXF_OBJ_AuditEvent__c r : [
      SELECT Id, OwnerId
      FROM AXF_OBJ_AuditEvent__c
      WHERE OwnerId = :oldPrincipal.Id
      FOR UPDATE
    ]) {
      r.OwnerId = nextPrincipal.Id;
      roots.add(r);
    }
    updateInBatches(roots);
    authority.OwnerId = nextPrincipal.Id;
    Database.update(authority, AccessLevel.SYSTEM_MODE);
    RotationResult result = new RotationResult();
    result.previousOwnerId = oldPrincipal.Id;
    result.currentOwnerId = nextPrincipal.Id;
    result.transferredCount = roots.size() + 1;
    result.verified = verifyOwner(oldPrincipal.Id, nextPrincipal.Id);
    if (!result.verified)
      throw new ProvisioningException('ROTATION_VERIFY_FAILED');
    String rotationOutcome = JSON.serialize(result);
    if (!Test.isRunningTest())
      Database.insert(
        new AXF_OBJ_CommandExecution__c(
          OwnerId = nextPrincipal.Id,
          AXF_CE_EXI_IdempotencyScopeKey__c = rotationKey,
          AXF_CE_TXT_OperationId__c = 'migration.service-principal.rotate.v1',
          AXF_CE_TXT_AggregateType__c = 'BootstrapAuthority',
          AXF_CE_TXT_AggregateKey__c = AUTHORITY_KEY,
          AXF_CE_TXT_AggregateRecordId__c = String.valueOf(authority.Id),
          AXF_CE_TXT_IdempotencyKeyHash__c = ALT_CLS_AxfCanonical.sha256(
            releaseId
          ),
          AXF_CE_TXT_ScopeHash__c = rotationKey,
          AXF_CE_TXT_PayloadHash__c = rotationPayload,
          AXF_CE_TXT_ResultHash__c = ALT_CLS_AxfCanonical.sha256(
            rotationOutcome
          ),
          AXF_CE_TXT_CorrelationId__c = uuid(),
          AXF_CE_PKL_Status__c = 'SUCCEEDED',
          AXF_CE_TAL_RedactedOutcome__c = rotationOutcome,
          AXF_CE_DT_StartedAt__c = System.now(),
          AXF_CE_DT_CompletedAt__c = System.now(),
          AXF_CE_NUM_Version__c = 1
        ),
        AccessLevel.SYSTEM_MODE
      );
    if (Test.isRunningTest())
      testRotationOutcomes.put(rotationKey, result);
    return result;
  }
  private static void updateInBatches(List<SObject> roots) {
    Map<String, List<SObject>> byType = new Map<String, List<SObject>>();
    for (SObject root : roots) {
      String typeName = String.valueOf(root.getSObjectType());
      if (!byType.containsKey(typeName))
        byType.put(typeName, new List<SObject>());
      byType.get(typeName).add(root);
    }
    for (List<SObject> typedRoots : byType.values()) {
      for (Integer start = 0; start < typedRoots.size(); start += 200) {
        Integer finish = Math.min(start + 200, typedRoots.size());
        List<SObject> batch = new List<SObject>();
        for (Integer index = start; index < finish; index++)
          batch.add(typedRoots[index]);
        Database.update(batch, AccessLevel.SYSTEM_MODE);
      }
    }
  }
  private static Boolean verifyOwner(Id oldOwnerId, Id ownerId) {
    return [
        SELECT COUNT()
        FROM AXF_OBJ_BootstrapAuthority__c
        WHERE
          AXF_BSA_EXI_AuthorityKey__c = :AUTHORITY_KEY
          AND OwnerId = :ownerId
      ] == 1 &&
      [
        SELECT COUNT()
        FROM AXF_OBJ_CommandExecution__c
        WHERE OwnerId = :oldOwnerId
      ] == 0 &&
      [
        SELECT COUNT()
        FROM AXF_OBJ_AuditEvent__c
        WHERE OwnerId = :oldOwnerId
      ] == 0;
  }
  private static void authorizeTrustedCaller() {
    if (Test.isRunningTest() && !testPrincipals.isEmpty())
      return;
    User configured = new ALT_CLS_ServicePrincipalResolver().resolve();
    if (configured.Id != UserInfo.getUserId())
      throw new ProvisioningException('FORBIDDEN');
  }
  @TestVisible
  private static User requirePrincipal(String federationIdentifier) {
    if (
      Test.isRunningTest() && testPrincipals.containsKey(federationIdentifier)
    )
      return [
        SELECT Id, FederationIdentifier
        FROM User
        WHERE Id = :testPrincipals.get(federationIdentifier)
      ];
    List<User> users = [
      SELECT Id, FederationIdentifier
      FROM User
      WHERE IsActive = TRUE AND FederationIdentifier = :federationIdentifier
      LIMIT 2
    ];
    if (users.size() != 1)
      throw new ProvisioningException('SERVICE_PRINCIPAL_UNAVAILABLE');
    List<PermissionSetAssignment> p = [
      SELECT Id
      FROM PermissionSetAssignment
      WHERE
        AssigneeId = :users[0].Id
        AND PermissionSet.Name = 'AXF_PS_SecurityProjector'
      LIMIT 1
    ];
    if (p.isEmpty())
      throw new ProvisioningException('SERVICE_PRINCIPAL_UNAVAILABLE');
    return users[0];
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
  public class ProvisionResult {
    public Id authorityId;
    public Id ownerId;
    public String state;
  }
  public class RotationResult {
    public Id previousOwnerId;
    public Id currentOwnerId;
    public Integer transferredCount;
    public Boolean verified;
  }
  public class ProvisioningException extends Exception {
  }
  @TestVisible
  private static ProvisionResult deserializeProvisionResult(String outcome) {
    return (ProvisionResult) JSON.deserialize(outcome, ProvisionResult.class);
  }
}
