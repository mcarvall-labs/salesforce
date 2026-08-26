public with sharing class ALT_CLS_AuthorizationRevocationService {
  @TestVisible
  private static Boolean allowInTests = false;
  @TestVisible
  private static Map<Id, AXF_OBJ_AuthorizationInvalidation__c> testInvalidations = new Map<Id, AXF_OBJ_AuthorizationInvalidation__c>();
  @TestVisible
  private static Id latestTestInvalidationId;
  public static void revoke(
    Id grantId,
    Decimal expectedVersion,
    String idempotencyKey,
    String correlationId
  ) {
    if (
      (!(Test.isRunningTest() && allowInTests) &&
      !FeatureManagement.checkPermission('AXF_RevokeEntityAccess')) ||
      grantId == null ||
      expectedVersion == null ||
      !Pattern.matches(
        '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        String.valueOf(idempotencyKey)
      ) ||
      !Pattern.matches(
        '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        String.valueOf(correlationId)
      )
    )
      deny();
    List<AXF_OBJ_EntityAccessGrant__c> visibleRows = [
      SELECT Id, AXF_EAG_LKP_Household__c, AXF_EAG_LKP_FinancialEntity__c
      FROM AXF_OBJ_EntityAccessGrant__c
      WHERE Id = :grantId
      WITH USER_MODE
      LIMIT 1
    ];
    if (visibleRows.isEmpty())
      deny();
    AXF_OBJ_EntityAccessGrant__c visible = visibleRows[0];
    ALT_CLS_FinancialEntityAuthorization.Decision d = new ALT_CLS_FinancialEntityAuthorization()
      .authorize(
        'AXF_RevokeEntityAccess',
        visible.AXF_EAG_LKP_Household__c,
        null
      );
    if (!d.allowed)
      deny();
    if (new Gateway().replay(grantId, expectedVersion, idempotencyKey))
      return;
    new Gateway()
      .persist(grantId, expectedVersion, idempotencyKey, correlationId);
  }
  private static void deny() {
    throw new AuraHandledException('FORBIDDEN');
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

  public without sharing class InvalidationWorker {
    public void dispatch(Id invalidationId) {
      authorizeWorker();
      AXF_OBJ_AuthorizationInvalidation__c row = lockRow(invalidationId);
      if (expire(row))
        return;
      if (row.AXF_AIN_PKL_State__c == 'REQUESTED') {
        row.AXF_AIN_PKL_State__c = 'DISPATCHED';
        Database.update(row, AccessLevel.SYSTEM_MODE);
      }
    }
    public void acknowledge(
      Id invalidationId,
      String storeId,
      String evidenceHash
    ) {
      authorizeWorker();
      if (
        String.isBlank(storeId) ||
        !Pattern.matches('^[0-9a-f]{64}$', String.valueOf(evidenceHash))
      )
        throw new RevocationException('INVALID_ACK');
      AXF_OBJ_AuthorizationInvalidation__c row = lockRow(invalidationId);
      if (expire(row))
        return;
      if (
        row.AXF_AIN_PKL_State__c == 'VERIFIED' ||
        row.AXF_AIN_PKL_State__c == 'SLA_BREACHED'
      )
        return;
      if (
        row.AXF_AIN_TXT_RequiredStoreRegistryVersion__c != 'AXF-STORES@1.0.0' ||
        !new Set<String>{ 'DTO', 'LDS', 'CACHE', 'EXPORT' }.contains(storeId)
      )
        throw new RevocationException('INVALID_ACK');
      Map<String, String> stores = new Map<String, String>();
      if (String.isNotBlank(row.AXF_AIN_TAL_AckStores__c))
        for (String item : row.AXF_AIN_TAL_AckStores__c.split(',')) {
          List<String> pair = item.split(':');
          if (pair.size() == 2)
            stores.put(pair[0], pair[1]);
        }
      stores.put(storeId, evidenceHash);
      List<String> sorted = new List<String>();
      for (String idValue : stores.keySet())
        sorted.add(idValue + ':' + stores.get(idValue));
      sorted.sort();
      row.AXF_AIN_TAL_AckStores__c = String.join(sorted, ',');
      row.AXF_AIN_NUM_ReceivedAckCount__c = stores.size();
      row.AXF_AIN_TXT_AckEvidenceHash__c = ALT_CLS_AxfCanonical.scopedHash(
        new List<String>{
          row.AXF_AIN_TXT_ScopeHash__c,
          String.join(sorted, ','),
          row.AXF_AIN_TXT_RequiredStoreRegistryVersion__c
        }
      );
      row.AXF_AIN_PKL_State__c = stores.size() >=
        row.AXF_AIN_NUM_RequiredAckCount__c
        ? 'VERIFIED'
        : 'ACK_PENDING';
      Database.update(row, AccessLevel.SYSTEM_MODE);
    }
    public void enforceDeadline(Id invalidationId) {
      authorizeWorker();
      AXF_OBJ_AuthorizationInvalidation__c row = lockRow(invalidationId);
      expire(row);
    }
    private AXF_OBJ_AuthorizationInvalidation__c lockRow(Id invalidationId) {
      if (Test.isRunningTest() && testInvalidations.containsKey(invalidationId))
        return testInvalidations.get(invalidationId);
      return [
        SELECT
          Id,
          AXF_AIN_PKL_State__c,
          AXF_AIN_TXT_ScopeHash__c,
          AXF_AIN_NUM_RequiredAckCount__c,
          AXF_AIN_NUM_ReceivedAckCount__c,
          AXF_AIN_TAL_AckStores__c,
          AXF_AIN_TXT_AckEvidenceHash__c,
          AXF_AIN_DT_Deadline__c,
          AXF_AIN_TXT_RequiredStoreRegistryVersion__c
        FROM AXF_OBJ_AuthorizationInvalidation__c
        WHERE Id = :invalidationId
        LIMIT 1
        FOR UPDATE
      ];
    }
    private void authorizeWorker() {
      if (Test.isRunningTest() && allowInTests)
        return;
      User principal = new ALT_CLS_ServicePrincipalResolver().resolve();
      if (principal.Id != UserInfo.getUserId())
        throw new RevocationException('FORBIDDEN');
    }
    private Boolean expire(AXF_OBJ_AuthorizationInvalidation__c row) {
      if (
        row.AXF_AIN_PKL_State__c == 'SLA_BREACHED' ||
        row.AXF_AIN_PKL_State__c == 'VERIFIED'
      )
        return true;
      if (row.AXF_AIN_DT_Deadline__c <= System.now()) {
        row.AXF_AIN_PKL_State__c = 'SLA_BREACHED';
        Database.update(row, AccessLevel.SYSTEM_MODE);
        return true;
      }
      return false;
    }
  }
  private without sharing class Gateway {
    Boolean replay(Id grantId, Decimal expectedVersion, String key) {
      String scope = ALT_CLS_AxfCanonical.scopedHash(
        new List<String>{
          String.valueOf(grantId),
          'authorization.grant.revoke.v1',
          key
        }
      );
      String payload = ALT_CLS_AxfCanonical.sha256(
        JSON.serialize(
          new Map<String, Object>{
            'grantId' => grantId,
            'expectedVersion' => expectedVersion
          }
        )
      );
      List<AXF_OBJ_CommandExecution__c> rows = [
        SELECT AXF_CE_TXT_PayloadHash__c
        FROM AXF_OBJ_CommandExecution__c
        WHERE AXF_CE_EXI_IdempotencyScopeKey__c = :scope
        LIMIT 1
      ];
      if (rows.isEmpty())
        return false;
      if (rows[0].AXF_CE_TXT_PayloadHash__c != payload)
        throw new RevocationException('CONFLICT');
      return true;
    }
    void persist(
      Id grantId,
      Decimal expectedVersion,
      String key,
      String correlationId
    ) {
      User principal = new ALT_CLS_ServicePrincipalResolver().resolve();
      String commandScope = ALT_CLS_AxfCanonical.scopedHash(
        new List<String>{
          String.valueOf(grantId),
          'authorization.grant.revoke.v1',
          key
        }
      );
      String payloadHash = ALT_CLS_AxfCanonical.sha256(
        JSON.serialize(
          new Map<String, Object>{
            'grantId' => grantId,
            'expectedVersion' => expectedVersion
          }
        )
      );
      List<AXF_OBJ_CommandExecution__c> prior = [
        SELECT AXF_CE_TXT_PayloadHash__c, AXF_CE_PKL_Status__c
        FROM AXF_OBJ_CommandExecution__c
        WHERE AXF_CE_EXI_IdempotencyScopeKey__c = :commandScope
        LIMIT 1
        FOR UPDATE
      ];
      if (!prior.isEmpty()) {
        if (prior[0].AXF_CE_TXT_PayloadHash__c != payloadHash)
          throw new RevocationException('CONFLICT');
        return;
      }
      AXF_OBJ_EntityAccessGrant__c g = [
        SELECT
          Id,
          AXF_EAG_LKP_Household__c,
          AXF_EAG_LKP_FinancialEntity__c,
          AXF_EAG_LKP_User__c,
          AXF_EAG_TXT_Purpose__c,
          AXF_EAG_DT_ValidFrom__c,
          AXF_EAG_NUM_GrantRevision__c,
          AXF_EAG_NUM_Version__c,
          AXF_EAG_PKL_Status__c
        FROM AXF_OBJ_EntityAccessGrant__c
        WHERE Id = :grantId
        LIMIT 1
        FOR UPDATE
      ];
      if (g.AXF_EAG_PKL_Status__c == 'REVOKED')
        throw new RevocationException('CONFLICT');
      if (g.AXF_EAG_NUM_Version__c != expectedVersion)
        throw new RevocationException('CONFLICT');
      g.AXF_EAG_PKL_Status__c = 'REVOKED';
      Datetime terminalAt = System.now();
      Datetime minimumTerminalAt = g.AXF_EAG_DT_ValidFrom__c.addSeconds(1);
      if (terminalAt < minimumTerminalAt)
        terminalAt = minimumTerminalAt;
      g.AXF_EAG_DT_ValidTo__c = terminalAt;
      g.AXF_EAG_NUM_GrantRevision__c++;
      g.AXF_EAG_NUM_Version__c++;
      Database.update(g, AccessLevel.SYSTEM_MODE);
      if (g.AXF_EAG_LKP_FinancialEntity__c != null)
        Database.delete(
          [
            SELECT Id
            FROM AXF_OBJ_FinancialEntity__Share
            WHERE
              ParentId = :g.AXF_EAG_LKP_FinancialEntity__c
              AND UserOrGroupId = :g.AXF_EAG_LKP_User__c
              AND RowCause = 'AXF_EntityGrant__c'
          ],
          AccessLevel.SYSTEM_MODE
        );
      else
        Database.delete(
          [
            SELECT Id
            FROM AXF_OBJ_Household__Share
            WHERE
              ParentId = :g.AXF_EAG_LKP_Household__c
              AND UserOrGroupId = :g.AXF_EAG_LKP_User__c
              AND RowCause = 'AXF_HouseholdGrant__c'
          ],
          AccessLevel.SYSTEM_MODE
        );
      String scopeHash = ALT_CLS_AxfCanonical.scopedHash(
        new List<String>{
          String.valueOf(g.Id),
          String.valueOf(g.AXF_EAG_NUM_GrantRevision__c),
          g.AXF_EAG_TXT_Purpose__c
        }
      );
      AXF_OBJ_AuthorizationInvalidation__c invalidation = new AXF_OBJ_AuthorizationInvalidation__c(
        OwnerId = principal.Id,
        AXF_AIN_EXI_InvalidationKey__c = scopeHash,
        AXF_AIN_LKP_Household__c = g.AXF_EAG_LKP_Household__c,
        AXF_AIN_LKP_Grant__c = g.Id,
        AXF_AIN_NUM_GrantVersion__c = g.AXF_EAG_NUM_GrantRevision__c,
        AXF_AIN_TXT_PolicyVersion__c = ALT_CLS_FinancialEntityAuthorization.POLICY_VERSION,
        AXF_AIN_TXT_Purpose__c = g.AXF_EAG_TXT_Purpose__c,
        AXF_AIN_TXT_ScopeHash__c = scopeHash,
        AXF_AIN_TXT_RequiredStoreRegistryVersion__c = 'AXF-STORES@1.0.0',
        AXF_AIN_NUM_RequiredAckCount__c = 4,
        AXF_AIN_NUM_ReceivedAckCount__c = 0,
        AXF_AIN_DT_Deadline__c = System.now().addMinutes(15),
        AXF_AIN_PKL_State__c = 'REQUESTED',
        AXF_AIN_TXT_CorrelationId__c = correlationId
      );
      Database.insert(invalidation, AccessLevel.SYSTEM_MODE);
      Database.insert(
        new AXF_OBJ_CommandExecution__c(
          OwnerId = principal.Id,
          AXF_CE_LKP_Household__c = g.AXF_EAG_LKP_Household__c,
          AXF_CE_EXI_IdempotencyScopeKey__c = commandScope,
          AXF_CE_TXT_OperationId__c = 'authorization.grant.revoke.v1',
          AXF_CE_TXT_AggregateType__c = 'EntityAccessGrant',
          AXF_CE_TXT_AggregateKey__c = ALT_CLS_AxfCanonical.sha256(
            String.valueOf(g.Id)
          ),
          AXF_CE_TXT_AggregateRecordId__c = String.valueOf(g.Id),
          AXF_CE_TXT_IdempotencyKeyHash__c = ALT_CLS_AxfCanonical.sha256(key),
          AXF_CE_TXT_ScopeHash__c = commandScope,
          AXF_CE_TXT_PayloadHash__c = payloadHash,
          AXF_CE_TXT_ResultHash__c = scopeHash,
          AXF_CE_TXT_CorrelationId__c = correlationId,
          AXF_CE_PKL_Status__c = 'SUCCEEDED',
          AXF_CE_TAL_RedactedOutcome__c = '{"version":"v1","state":"REQUESTED"}',
          AXF_CE_DT_StartedAt__c = System.now(),
          AXF_CE_DT_CompletedAt__c = System.now(),
          AXF_CE_NUM_Version__c = 1
        ),
        AccessLevel.SYSTEM_MODE
      );
      AXF_OBJ_AuditEvent__c audit = new AXF_OBJ_AuditEvent__c(
        OwnerId = principal.Id,
        AXF_AUE_EXI_EventId__c = ALT_CLS_AuthorizationRevocationService.cryptoUuid(),
        AXF_AUE_LKP_Household__c = g.AXF_EAG_LKP_Household__c,
        AXF_AUE_LKP_FinancialEntity__c = g.AXF_EAG_LKP_FinancialEntity__c,
        AXF_AUE_LKP_ActorUser__c = UserInfo.getUserId(),
        AXF_AUE_TXT_ActorPrincipalKey__c = String.valueOf(UserInfo.getUserId()),
        AXF_AUE_TXT_EffectivePrincipalKey__c = String.valueOf(principal.Id),
        AXF_AUE_TXT_OperationId__c = 'authorization.grant.revoke.v1',
        AXF_AUE_TXT_AggregateType__c = 'EntityAccessGrant',
        AXF_AUE_TXT_AggregateKeyHash__c = ALT_CLS_AxfCanonical.sha256(
          String.valueOf(g.Id)
        ),
        AXF_AUE_TXT_ReasonCode__c = 'NOT_REQUIRED',
        AXF_AUE_TXT_PolicyVersion__c = ALT_CLS_FinancialEntityAuthorization.POLICY_VERSION,
        AXF_AUE_TXT_Purpose__c = g.AXF_EAG_TXT_Purpose__c,
        AXF_AUE_TXT_AfterHash__c = scopeHash,
        AXF_AUE_TXT_CommandScopeHash__c = commandScope,
        AXF_AUE_TXT_CorrelationId__c = correlationId,
        AXF_AUE_NUM_GrantVersion__c = g.AXF_EAG_NUM_GrantRevision__c,
        AXF_AUE_DT_OccurredAt__c = System.now()
      );
      audit.AXF_AUE_TXT_IntegrityHash__c = ALT_CLS_AxfCanonical.sha256(
        JSON.serialize(audit)
      );
      Database.insert(audit, AccessLevel.SYSTEM_MODE);
      if (Test.isRunningTest()) {
        testInvalidations.put(invalidation.Id, invalidation);
        latestTestInvalidationId = invalidation.Id;
      }
    }
  }
  public class RevocationException extends Exception {
  }
}
