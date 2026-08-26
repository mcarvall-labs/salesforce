@IsTest
private class ALT_CLS_AxfHouseholdBehaviorTest {
  @TestSetup
  static void users() {
    Id profileId = UserInfo.getProfileId();
    List<User> created = new List<User>{
      user(profileId, 'operator', 'operator@axon.test'),
      user(profileId, 'service', 'service@axon.test'),
      user(profileId, 'nextsvc', 'nextsvc@axon.test')
    };
    insert created;
    Map<String, Id> permissionIds = new Map<String, Id>();
    for (PermissionSet ps : [
      SELECT Id, Name
      FROM PermissionSet
      WHERE Name IN ('AXF_PS_HouseholdOperator', 'AXF_PS_SecurityProjector')
    ])
      permissionIds.put(ps.Name, ps.Id);
    insert new List<PermissionSetAssignment>{
      new PermissionSetAssignment(
        AssigneeId = created[0].Id,
        PermissionSetId = permissionIds.get('AXF_PS_HouseholdOperator')
      ),
      new PermissionSetAssignment(
        AssigneeId = created[1].Id,
        PermissionSetId = permissionIds.get('AXF_PS_SecurityProjector')
      ),
      new PermissionSetAssignment(
        AssigneeId = created[2].Id,
        PermissionSetId = permissionIds.get('AXF_PS_SecurityProjector')
      )
    };
  }
  private static User user(Id profileId, String alias, String federation) {
    return new User(
      Alias = alias.left(8),
      Email = federation,
      EmailEncodingKey = 'UTF-8',
      LastName = alias,
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = profileId,
      TimeZoneSidKey = 'America/Sao_Paulo',
      Username = alias +
        '-' +
        String.valueOf(DateTime.now().getTime()) +
        '@axon.test',
      FederationIdentifier = federation
    );
  }
  private static Map<String, User> actors() {
    Map<String, User> r = new Map<String, User>();
    for (User u : [
      SELECT Id, FederationIdentifier
      FROM User
      WHERE
        FederationIdentifier IN (
          'operator@axon.test',
          'service@axon.test',
          'nextsvc@axon.test'
        )
    ])
      r.put(u.FederationIdentifier, u);
    return r;
  }
  private static void seams(Map<String, User> a) {
    ALT_CLS_ServicePrincipalResolver.testPrincipalId = a.get(
        'service@axon.test'
      )
      .Id;
    ALT_CLS_HouseholdApplicationService.allowInTests = true;
    ALT_CLS_FinancialEntityAuthorization.allowCustomPermissionsInTests = true;
    AXF_CLS_CTRL_FinancialEntity.allowCustomPermissionsInTests = true;
    ALT_CLS_AuthorizationRevocationService.allowInTests = true;
    ALT_CLS_ServicePrincipalProvisioner.testPrincipals.put(
      'service@axon.test',
      a.get('service@axon.test').Id
    );
    ALT_CLS_ServicePrincipalProvisioner.testPrincipals.put(
      'nextsvc@axon.test',
      a.get('nextsvc@axon.test').Id
    );
  }
  private static AXF_CLS_CTRL_HouseholdBootstrap.InitializeRequest bootstrapRequest() {
    AXF_CLS_CTRL_HouseholdBootstrap.InitializeRequest r = new AXF_CLS_CTRL_HouseholdBootstrap.InitializeRequest();
    r.reportingCurrency = 'BRL';
    r.timeZone = 'America/Sao_Paulo';
    r.entityKey = 'fie-v1:00000000-0000-4000-8000-000000000001';
    r.kind = 'PERSON';
    r.legalName = 'Owner';
    r.displayName = 'Owner';
    r.idempotencyKey = '00000000-0000-4000-8000-000000000001';
    r.correlationId = '00000000-0000-4000-8000-000000000002';
    return r;
  }
  private static void seedAuthority(Id owner) {
    insert new AXF_OBJ_BootstrapAuthority__c(
      OwnerId = owner,
      AXF_BSA_EXI_AuthorityKey__c = 'HH_PRIMARY_V1',
      AXF_BSA_PKL_State__c = 'AVAILABLE',
      AXF_BSA_NUM_Version__c = 0
    );
  }

  @IsTest
  static void bootstrapControllerSuccessReplayAndConflict() {
    Map<String, User> a = actors();
    seams(a);
    seedAuthority(a.get('service@axon.test').Id);
    System.runAs(a.get('operator@axon.test')) {
      AXF_CLS_CTRL_HouseholdBootstrap.InitializeRequest r = bootstrapRequest();
      AXF_CLS_CTRL_HouseholdBootstrap.Result first = AXF_CLS_CTRL_HouseholdBootstrap.initialize(
        r
      );
      System.assertEquals('READY_DATA', first.state);
      System.assertNotEquals(null, first.entityRef);
      System.assertEquals(
        first.entityRef,
        AXF_CLS_CTRL_HouseholdBootstrap.initialize(r).entityRef
      );
      r.displayName = 'Different';
      System.assertEquals(
        'FORBIDDEN',
        AXF_CLS_CTRL_HouseholdBootstrap.initialize(r).state
      );
      System.assertEquals(1, [SELECT COUNT() FROM AXF_OBJ_Household__c]);
      System.assertEquals(
        2,
        [SELECT COUNT() FROM AXF_OBJ_EntityAccessGrant__c]
      );
      System.assertEquals(1, [SELECT COUNT() FROM AXF_OBJ_CommandExecution__c]);
    }
  }
  @IsTest
  static void bootstrapDeniesInvalidRequest() {
    AXF_CLS_CTRL_HouseholdBootstrap.InitializeRequest r = bootstrapRequest();
    r.entityKey = 'bad';
    System.assertEquals(
      'FORBIDDEN',
      AXF_CLS_CTRL_HouseholdBootstrap.initialize(r).state
    );
    r = bootstrapRequest();
    r.idempotencyKey = 'not-a-uuid';
    System.assertEquals(
      'FORBIDDEN',
      AXF_CLS_CTRL_HouseholdBootstrap.initialize(r).state
    );
    r = bootstrapRequest();
    r.reportingCurrency = ' ';
    System.assertEquals(
      'FORBIDDEN',
      AXF_CLS_CTRL_HouseholdBootstrap.initialize(r).state
    );
    r = bootstrapRequest();
    r.timeZone = null;
    System.assertEquals(
      'FORBIDDEN',
      AXF_CLS_CTRL_HouseholdBootstrap.initialize(r).state
    );
  }

  @IsTest
  static void createReadUpdateReplayConflictAndRevoke() {
    Map<String, User> a = actors();
    seams(a);
    seedAuthority(a.get('service@axon.test').Id);
    System.runAs(a.get('operator@axon.test')) {
      AXF_CLS_CTRL_HouseholdBootstrap.initialize(bootstrapRequest());
      Id hh = [SELECT Id FROM AXF_OBJ_Household__c LIMIT 1].Id;
      ALT_CLS_FinancialEntityAuthorization.allowCustomPermissionsInTests = false;
      AXF_CLS_CTRL_FinancialEntity.allowCustomPermissionsInTests = false;
      System.assertNotEquals(
        'FORBIDDEN',
        AXF_CLS_CTRL_FinancialEntity.listEntities().state,
        'Assigned custom permissions must work without the test bypass.'
      );
      ALT_CLS_FinancialEntityAuthorization.allowCustomPermissionsInTests = true;
      AXF_CLS_CTRL_FinancialEntity.allowCustomPermissionsInTests = true;
      AXF_CLS_CTRL_FinancialEntity.MutationRequest c = new AXF_CLS_CTRL_FinancialEntity.MutationRequest();
      c.householdId = hh;
      c.entityKey = 'fie-v1:00000000-0000-4000-8000-000000000003';
      c.kind = 'ORGANIZATION';
      c.legalName = 'Acme';
      c.displayName = 'Acme';
      c.idempotencyKey = '00000000-0000-4000-8000-000000000003';
      c.correlationId = '00000000-0000-4000-8000-000000000004';
      ALT_CLS_FinancialEntityGateway.Result created = AXF_CLS_CTRL_FinancialEntity.createEntity(
        c
      );
      System.assertEquals(
        created.entityRef,
        AXF_CLS_CTRL_FinancialEntity.createEntity(c).entityRef
      );
      AXF_CLS_CTRL_FinancialEntity.ResponseEnvelope detailResponse = AXF_CLS_CTRL_FinancialEntity.readEntity(
        created.entityRef
      );
      System.assertEquals('READY_DATA', detailResponse.state);
      System.assertEquals(
        'Acme',
        ((AXF_CLS_CTRL_FinancialEntity.FinancialEntityDetail) detailResponse.detail)
          .legalName
      );
      AXF_OBJ_EntityAccessGrant__c policyGrant = [
        SELECT Id, AXF_EAG_TXT_FieldPolicyVersion__c
        FROM AXF_OBJ_EntityAccessGrant__c
        WHERE
          AXF_EAG_LKP_FinancialEntity__r.AXF_FIE_EXI_EntityRef__c = :created.entityRef
        LIMIT 1
      ];
      policyGrant.AXF_EAG_TXT_FieldPolicyVersion__c = 'AXF-SERVICE-PRINCIPAL@1.0.0';
      Database.update(policyGrant, AccessLevel.SYSTEM_MODE);
      String policyDeniedDetail = JSON.serialize(
        AXF_CLS_CTRL_FinancialEntity.readEntity(created.entityRef)
      );
      System.assertEquals(false, policyDeniedDetail.contains('legalName'));
      policyGrant.AXF_EAG_TXT_FieldPolicyVersion__c = ALT_CLS_FinancialEntityAuthorization.POLICY_VERSION;
      Database.update(policyGrant, AccessLevel.SYSTEM_MODE);
      AXF_CLS_CTRL_FinancialEntity.ResponseEnvelope listResponse = AXF_CLS_CTRL_FinancialEntity.listEntities();
      System.assertEquals(2, listResponse.entities.size());
      String serializedList = JSON.serialize(listResponse);
      System.assertEquals(false, serializedList.contains('legalName'));
      System.assertEquals(false, serializedList.contains('Acme Legal'));
      AXF_CLS_CTRL_FinancialEntity.MutationRequest u = new AXF_CLS_CTRL_FinancialEntity.MutationRequest();
      u.entityRef = created.entityRef;
      u.displayName = 'Acme 2';
      u.legalName = 'Acme Legal';
      u.lifecycle = 'ACTIVE';
      u.expectedVersion = 1;
      u.idempotencyKey = '00000000-0000-4000-8000-000000000005';
      u.correlationId = '00000000-0000-4000-8000-000000000006';
      ALT_CLS_FinancialEntityGateway.Result updated = AXF_CLS_CTRL_FinancialEntity.updateEntity(
        u
      );
      System.assertEquals(2, updated.version);
      System.assertEquals(
        2,
        AXF_CLS_CTRL_FinancialEntity.updateEntity(u).version
      );
      u.idempotencyKey = '00000000-0000-4000-8000-000000000007';
      try {
        AXF_CLS_CTRL_FinancialEntity.updateEntity(u);
        System.assert(false);
      } catch (Exception e) {
        System.assert(e.getMessage().contains('CONFLICT'));
      }
      Test.startTest();
      AXF_OBJ_EntityAccessGrant__c grant = [
        SELECT Id, AXF_EAG_NUM_Version__c
        FROM AXF_OBJ_EntityAccessGrant__c
        WHERE
          AXF_EAG_LKP_FinancialEntity__r.AXF_FIE_EXI_EntityRef__c = :created.entityRef
        LIMIT 1
      ];
      Id missingGrantId = Id.valueOf(
        String.valueOf(grant.Id).substring(0, 3) + '000000000000'
      );
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM AXF_OBJ_EntityAccessGrant__c
          WHERE Id = :missingGrantId
        ],
        'The missing-grant fixture must not resolve to an existing row.'
      );
      try {
        AXF_CLS_CTRL_FinancialEntity.revokeGrant(
          missingGrantId,
          1,
          '00000000-0000-4000-8000-000000000018',
          '00000000-0000-4000-8000-000000000019'
        );
        System.assert(false, 'A missing grant must be sanitized.');
      } catch (AuraHandledException expected) {
        System.assertNotEquals(null, expected);
      }
      try {
        AXF_CLS_CTRL_FinancialEntity.revokeGrant(
          grant.Id,
          999,
          '00000000-0000-4000-8000-000000000008',
          '00000000-0000-4000-8000-000000000009'
        );
        System.assert(false, 'A stale grant version must conflict.');
      } catch (ALT_CLS_AuthorizationRevocationService.RevocationException expected) {
        System.assertEquals('CONFLICT', expected.getMessage());
      }
      AXF_CLS_CTRL_FinancialEntity.revokeGrant(
        grant.Id,
        grant.AXF_EAG_NUM_Version__c,
        '00000000-0000-4000-8000-000000000008',
        '00000000-0000-4000-8000-000000000009'
      );
      AXF_OBJ_EntityAccessGrant__c revokedGrant = [
        SELECT
          AXF_EAG_PKL_Status__c,
          AXF_EAG_NUM_Version__c,
          AXF_EAG_DT_ValidFrom__c,
          AXF_EAG_DT_ValidTo__c
        FROM AXF_OBJ_EntityAccessGrant__c
        WHERE Id = :grant.Id
      ];
      System.assertEquals('REVOKED', revokedGrant.AXF_EAG_PKL_Status__c);
      System.assertEquals(
        grant.AXF_EAG_NUM_Version__c + 1,
        revokedGrant.AXF_EAG_NUM_Version__c
      );
      System.assert(
        revokedGrant.AXF_EAG_DT_ValidTo__c >
        revokedGrant.AXF_EAG_DT_ValidFrom__c,
        'The terminal interval must remain physically valid.'
      );
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM AXF_OBJ_FinancialEntity__Share
          WHERE
            Parent.AXF_FIE_EXI_EntityRef__c = :created.entityRef
            AND RowCause = 'AXF_EntityGrant__c'
        ]
      );
      System.assertEquals(
        'FORBIDDEN',
        AXF_CLS_CTRL_FinancialEntity.readEntity(created.entityRef).state
      );
      for (
        AXF_CLS_CTRL_FinancialEntity.FinancialEntitySummary item : AXF_CLS_CTRL_FinancialEntity.listEntities()
          .entities
      )
        System.assertNotEquals(created.entityRef, item.entityRef);
      AXF_OBJ_AuthorizationInvalidation__c inv = ALT_CLS_AuthorizationRevocationService.testInvalidations.get(
        ALT_CLS_AuthorizationRevocationService.latestTestInvalidationId
      );
      System.assertEquals('REQUESTED', inv.AXF_AIN_PKL_State__c);
      ALT_CLS_AuthorizationRevocationService.InvalidationWorker w = new ALT_CLS_AuthorizationRevocationService.InvalidationWorker();
      w.dispatch(inv.Id);
      try {
        w.acknowledge(inv.Id, 'DTO', 'invalid');
        System.assert(false, 'Unverifiable ACK evidence must be rejected.');
      } catch (ALT_CLS_AuthorizationRevocationService.RevocationException expected) {
        System.assertEquals('INVALID_ACK', expected.getMessage());
      }
      try {
        w.acknowledge(inv.Id, 'UNKNOWN', ALT_CLS_AxfCanonical.sha256('ack'));
        System.assert(
          false,
          'Stores outside AXF-STORES@1.0.0 must be rejected.'
        );
      } catch (ALT_CLS_AuthorizationRevocationService.RevocationException expected) {
        System.assertEquals('INVALID_ACK', expected.getMessage());
      }
      String hash = ALT_CLS_AxfCanonical.sha256('ack');
      for (String store : new List<String>{ 'DTO', 'LDS', 'CACHE', 'EXPORT' })
        w.acknowledge(inv.Id, store, hash);
      System.assertEquals(
        'VERIFIED',
        ALT_CLS_AuthorizationRevocationService.testInvalidations.get(inv.Id)
          .AXF_AIN_PKL_State__c
      );
      System.assert(
        ALT_CLS_AuthorizationRevocationService.testInvalidations.get(inv.Id)
          .AXF_AIN_TAL_AckStores__c.contains('DTO:' + hash)
      );
      System.assertNotEquals(
        null,
        ALT_CLS_AuthorizationRevocationService.testInvalidations.get(inv.Id)
          .AXF_AIN_TXT_AckEvidenceHash__c
      );
      w.acknowledge(inv.Id, 'DTO', hash);
      AXF_OBJ_EntityAccessGrant__c householdGrant = [
        SELECT Id, AXF_EAG_TXT_OperationSet__c
        FROM AXF_OBJ_EntityAccessGrant__c
        WHERE
          AXF_EAG_LKP_Household__c = :hh
          AND AXF_EAG_PKL_ScopeType__c = 'HOUSEHOLD'
          AND AXF_EAG_PKL_Status__c = 'ACTIVE'
        LIMIT 1
      ];
      householdGrant.AXF_EAG_TXT_OperationSet__c = 'AXF_CreateFinancialEntity';
      Database.update(householdGrant, AccessLevel.SYSTEM_MODE);
      try {
        AXF_CLS_CTRL_FinancialEntity.revokeGrant(
          grant.Id,
          grant.AXF_EAG_NUM_Version__c,
          '00000000-0000-4000-8000-000000000008',
          '00000000-0000-4000-8000-000000000009'
        );
        System.assert(false, 'Replay must not bypass current authorization.');
      } catch (AuraHandledException expected) {
        System.assertNotEquals(null, expected);
      }
      inv.AXF_AIN_PKL_State__c = 'ACK_PENDING';
      inv.AXF_AIN_DT_Deadline__c = System.now().addSeconds(-1);
      w.dispatch(inv.Id);
      System.assertEquals(
        'SLA_BREACHED',
        ALT_CLS_AuthorizationRevocationService.testInvalidations.get(inv.Id)
          .AXF_AIN_PKL_State__c
      );
      inv.AXF_AIN_PKL_State__c = 'ACK_PENDING';
      w.acknowledge(inv.Id, 'DTO', hash);
      System.assertEquals(
        'SLA_BREACHED',
        ALT_CLS_AuthorizationRevocationService.testInvalidations.get(inv.Id)
          .AXF_AIN_PKL_State__c
      );
      Test.stopTest();
    }

  }

  @IsTest
  static void provisionReplayDriftAndRotate() {
    Map<String, User> a = actors();
    seams(a);
    ALT_CLS_ServicePrincipalProvisioner p = new ALT_CLS_ServicePrincipalProvisioner();
    ALT_CLS_ServicePrincipalProvisioner.ProvisionResult first = p.provision(
      'service@axon.test',
      'release-1'
    );
    System.assertEquals(
      first.authorityId,
      p.provision('service@axon.test', 'release-1').authorityId
    );
    try {
      p.provision('nextsvc@axon.test', 'release-1');
      System.assert(false, 'A divergent replay payload must conflict.');
    } catch (ALT_CLS_ServicePrincipalProvisioner.ProvisioningException e) {
      System.assertEquals('CONFLICT', e.getMessage());
    }
    ALT_CLS_ServicePrincipalProvisioner.RotationResult rotation = p.rotate(
      'service@axon.test',
      'nextsvc@axon.test',
      'release-2'
    );
    System.assert(rotation.verified);
    System.assertEquals(a.get('nextsvc@axon.test').Id, rotation.currentOwnerId);
    ALT_CLS_ServicePrincipalProvisioner.RotationResult replayed = p.rotate(
      'service@axon.test',
      'nextsvc@axon.test',
      'release-2'
    );
    System.assertEquals(rotation.transferredCount, replayed.transferredCount);
    try {
      p.provision('service@axon.test', 'release-3');
      System.assert(false);
    } catch (ALT_CLS_ServicePrincipalProvisioner.ProvisioningException e) {
      System.assertEquals('PROVISIONING_DRIFT', e.getMessage());
    }
  }
  @IsTest
  static void resolverFailClosedWithoutPolicy() {
    ALT_CLS_ServicePrincipalResolver.testPrincipalId = null;
    try {
      new ALT_CLS_ServicePrincipalResolver().resolve();
      System.assert(false);
    } catch (ALT_CLS_ServicePrincipalResolver.ServicePrincipalException e) {
      System.assertEquals('SERVICE_PRINCIPAL_UNAVAILABLE', e.getMessage());
    }
  }
  @IsTest
  static void provisioningReplaySerializationContract() {
    ALT_CLS_ServicePrincipalProvisioner.ProvisionResult expected = new ALT_CLS_ServicePrincipalProvisioner.ProvisionResult();
    expected.authorityId = UserInfo.getUserId();
    expected.ownerId = UserInfo.getUserId();
    expected.state = 'AVAILABLE';
    ALT_CLS_ServicePrincipalProvisioner.ProvisionResult replayed = ALT_CLS_ServicePrincipalProvisioner.deserializeProvisionResult(
      JSON.serialize(expected)
    );
    System.assertEquals(expected.authorityId, replayed.authorityId);
    System.assertEquals(expected.ownerId, replayed.ownerId);
    System.assertEquals('AVAILABLE', replayed.state);
  }
  @IsTest
  static void revocationRejectsMalformedRequestBeforeElevation() {
    ALT_CLS_AuthorizationRevocationService.allowInTests = true;
    try {
      AXF_CLS_CTRL_FinancialEntity.revokeGrant(null, null, null, null);
      System.assert(false, 'Malformed requests must fail before gateway DML.');
    } catch (AuraHandledException expected) {
      System.assertNotEquals(null, expected);
    }
  }
}
