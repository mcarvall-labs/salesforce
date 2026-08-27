@IsTest
private class ALT_CLS_AxfHouseholdBehaviorTest {
  @TestSetup
  static void setupUsers() {
    Profile administratorProfile = [
      SELECT Id, PermissionsModifyAllData, UserLicenseId
      FROM Profile
      WHERE Id = :UserInfo.getProfileId()
    ];
    System.assert(
      administratorProfile.PermissionsModifyAllData,
      'The MVP access administrator fixture requires Modify All Data.'
    );
    Id limitedProfileId = [
      SELECT Id
      FROM Profile
      WHERE
        PermissionsModifyAllData = FALSE
        AND UserLicenseId = :administratorProfile.UserLicenseId
      LIMIT 1
    ]
    .Id;
    List<User> u = new List<User>{
      makeUser(administratorProfile.Id, 'owner', 'owner@axon.test'),
      makeUser(
        administratorProfile.Id,
        'privtarget',
        'privileged-target@axon.test'
      ),
      makeUser(limitedProfileId, 'target', 'target@axon.test'),
      makeUser(limitedProfileId, 'service', 'service@axon.test'),
      makeUser(limitedProfileId, 'nextsvc', 'next-service@axon.test'),
      makeUser(limitedProfileId, 'inactive', 'inactive@axon.test'),
      makeUser(administratorProfile.Id, 'nofedid', null)
    };
    u[2].LanguageLocaleKey = 'pt_BR';
    u[2].LocaleSidKey = 'pt_BR';
    u[5].IsActive = false;
    insert u;
    Map<String, Id> permissionIds = new Map<String, Id>();
    for (PermissionSet permissionSet : [
      SELECT Id, Name
      FROM PermissionSet
      WHERE Name IN ('AXF_PS_HouseholdOperator', 'AXF_PS_SecurityProjector')
    ])
      permissionIds.put(permissionSet.Name, permissionSet.Id);
    insert new List<PermissionSetAssignment>{
      new PermissionSetAssignment(
        AssigneeId = u[0].Id,
        PermissionSetId = permissionIds.get('AXF_PS_HouseholdOperator')
      ),
      new PermissionSetAssignment(
        AssigneeId = u[2].Id,
        PermissionSetId = permissionIds.get('AXF_PS_HouseholdOperator')
      ),
      new PermissionSetAssignment(
        AssigneeId = u[3].Id,
        PermissionSetId = permissionIds.get('AXF_PS_SecurityProjector')
      ),
      new PermissionSetAssignment(
        AssigneeId = u[4].Id,
        PermissionSetId = permissionIds.get('AXF_PS_SecurityProjector')
      )
    };
  }
  @IsTest
  static void onboardingOwnershipReplayConflict() {
    Map<String, User> u = users();
    seams(u);
    authority(u.get('service@axon.test').Id);
    System.runAs(u.get('owner@axon.test')) {
      AXF_CLS_CTRL_HouseholdBootstrap.InitializeRequest r = bootstrap();
      AXF_CLS_CTRL_HouseholdBootstrap.Result a = AXF_CLS_CTRL_HouseholdBootstrap.initialize(
          r
        ),
        b = AXF_CLS_CTRL_HouseholdBootstrap.initialize(r);
      System.assertEquals('READY_DATA', a.state);
      System.assertEquals(a.entityRef, b.entityRef);
      System.assertEquals(
        UserInfo.getUserId(),
        [SELECT OwnerId FROM AXF_OBJ_Household__c LIMIT 1].OwnerId
      );
      System.assertEquals(
        UserInfo.getUserId(),
        [SELECT OwnerId FROM AXF_OBJ_FinancialEntity__c LIMIT 1].OwnerId
      );
      System.assertEquals(
        UserInfo.getUserId(),
        [SELECT OwnerId FROM AXF_OBJ_CommandExecution__c LIMIT 1].OwnerId
      );
      System.assertEquals(
        UserInfo.getUserId(),
        [SELECT OwnerId FROM AXF_OBJ_AuditEvent__c LIMIT 1].OwnerId
      );
      r.displayName = 'Different';
      System.assertEquals(
        'FORBIDDEN',
        AXF_CLS_CTRL_HouseholdBootstrap.initialize(r).state
      );
    }
  }
  @IsTest
  static void assignRemoveReplayAndDelegationBoundary() {
    Map<String, User> u = users();
    Assert.areEqual(
      'en_US',
      u.get('owner@axon.test').LanguageLocaleKey,
      'Access owner must exercise English language behavior.'
    );
    Assert.areEqual(
      'en_US',
      u.get('owner@axon.test').LocaleSidKey,
      'Access owner must use the English locale.'
    );
    Assert.areEqual(
      'pt_BR',
      u.get('target@axon.test').LanguageLocaleKey,
      'Access target must exercise Brazilian Portuguese language behavior.'
    );
    Assert.areEqual(
      'pt_BR',
      u.get('target@axon.test').LocaleSidKey,
      'Access target must use the Brazilian Portuguese locale.'
    );
    seams(u);
    authority(u.get('service@axon.test').Id);
    Id hh;
    Id fie;
    System.runAs(u.get('owner@axon.test')) {
      AXF_CLS_CTRL_HouseholdBootstrap.initialize(bootstrap());
      AXF_OBJ_FinancialEntity__c e = [
        SELECT Id, AXF_FIE_LKP_Household__c
        FROM AXF_OBJ_FinancialEntity__c
        LIMIT 1
      ];
      hh = e.AXF_FIE_LKP_Household__c;
      fie = e.Id;
      ALT_CLS_EntityAccessService.Request r = access(
        hh,
        fie,
        u.get('target@axon.test').Id,
        'VIEWER'
      );
      User limitedTarget = [
        SELECT UserType, Profile.PermissionsModifyAllData
        FROM User
        WHERE Id = :r.targetUserId
      ];
      System.assertEquals('Standard', limitedTarget.UserType);
      System.assertEquals(
        false,
        limitedTarget.Profile.PermissionsModifyAllData
      );
      System.assertEquals(
        'VIEWER',
        AXF_CLS_CTRL_FinancialEntity.assignAccess(r).role
      );
      ALT_CLS_EntityAccessService.Request privilegedTarget = access(
        hh,
        fie,
        u.get('privileged-target@axon.test').Id,
        'VIEWER'
      );
      privilegedTarget.expectedVersion = 2;
      privilegedTarget.idempotencyKey = '00000000-0000-4000-8000-000000000012';
      try {
        new ALT_CLS_EntityAccessService().assign(privilegedTarget);
        System.assert(
          false,
          'A user with Modify All Data cannot be a collaborator target.'
        );
      } catch (ALT_CLS_EntityAccessService.AccessException expected) {
        System.assertEquals('FORBIDDEN', expected.getMessage());
      }
      System.assertEquals(
        'VIEWER',
        AXF_CLS_CTRL_FinancialEntity.assignAccess(r).role
      );
      r.role = 'EDITOR';
      try {
        new ALT_CLS_EntityAccessService().assign(r);
        System.assert(false);
      } catch (ALT_CLS_EntityAccessService.AccessException expected) {
        System.assertEquals('CONFLICT', expected.getMessage());
      }
      try {
        AXF_CLS_CTRL_FinancialEntity.assignAccess(r);
        System.assert(false);
      } catch (AuraHandledException x) {
        System.assertNotEquals(null, x);
      }
      r.role = null;
      r.expectedVersion = 2;
      r.idempotencyKey = '00000000-0000-4000-8000-000000000020';
      AXF_CLS_CTRL_FinancialEntity.removeAccess(r);
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM AXF_OBJ_FinancialEntity__Share
          WHERE
            ParentId = :fie
            AND UserOrGroupId = :r.targetUserId
            AND RowCause = 'AXF_EntityGrant__c'
        ]
      );
    }
    System.runAs(u.get('target@axon.test')) {
      ALT_CLS_EntityAccessService.Request deniedAccess = access(
        hh,
        fie,
        u.get('service@axon.test').Id,
        'VIEWER'
      );
      try {
        new ALT_CLS_EntityAccessService().assign(deniedAccess);
        System.assert(false);
      } catch (ALT_CLS_EntityAccessService.AccessException expected) {
        System.assertEquals('FORBIDDEN', expected.getMessage());
      }
      try {
        AXF_CLS_CTRL_FinancialEntity.assignAccess(deniedAccess);
        System.assert(false);
      } catch (AuraHandledException expected) {
        System.assertNotEquals(null, expected);
      }
    }
  }
  @IsTest
  static void servicePrincipalProvisionAndRotationOnlyTransfersTechnicalRoots() {
    Map<String, User> u = users();
    seams(u);
    ALT_CLS_ServicePrincipalProvisioner.testPrincipals.clear();
    ALT_CLS_ServicePrincipalProvisioner.testReplayOutcomes.clear();
    ALT_CLS_ServicePrincipalProvisioner.testReplayPayloads.clear();
    ALT_CLS_ServicePrincipalProvisioner.testRotationOutcomes.clear();
    ALT_CLS_ServicePrincipalProvisioner.testPrincipals.put(
      'service@axon.test',
      u.get('service@axon.test').Id
    );
    ALT_CLS_ServicePrincipalProvisioner.testPrincipals.put(
      'next-service@axon.test',
      u.get('next-service@axon.test').Id
    );
    System.runAs(u.get('owner@axon.test')) {
      ALT_CLS_ServicePrincipalProvisioner provisioner = new ALT_CLS_ServicePrincipalProvisioner();
      try {
        provisioner.provision('service@axon.test', null);
        System.assert(false, 'Provisioning requires a release identifier.');
      } catch (ALT_CLS_ServicePrincipalProvisioner.ProvisioningException e) {
        System.assertEquals('INVALID_INPUT', e.getMessage());
      }
      try {
        provisioner.rotate(
          'service@axon.test',
          'service@axon.test',
          'invalid-rotation'
        );
        System.assert(false, 'Rotation requires distinct principals.');
      } catch (ALT_CLS_ServicePrincipalProvisioner.ProvisioningException e) {
        System.assertEquals('INVALID_INPUT', e.getMessage());
      }
      ALT_CLS_ServicePrincipalProvisioner.ProvisionResult provisioned = provisioner.provision(
        'service@axon.test',
        'release-axf-76'
      );
      System.assertEquals(u.get('service@axon.test').Id, provisioned.ownerId);
      System.assertEquals(
        provisioned.authorityId,
        provisioner.provision('service@axon.test', 'release-axf-76')
          .authorityId,
        'Equivalent provisioning must replay.'
      );
      try {
        provisioner.provision('next-service@axon.test', 'release-axf-76');
        System.assert(false, 'A divergent provisioning replay must conflict.');
      } catch (ALT_CLS_ServicePrincipalProvisioner.ProvisioningException e) {
        System.assertEquals('CONFLICT', e.getMessage());
      }
      try {
        provisioner.provision('next-service@axon.test', 'drift-release');
        System.assert(false, 'A different owner must be reported as drift.');
      } catch (ALT_CLS_ServicePrincipalProvisioner.ProvisioningException e) {
        System.assertEquals('PROVISIONING_DRIFT', e.getMessage());
      }

      AXF_CLS_CTRL_HouseholdBootstrap.initialize(bootstrap());
      Id householdOwner = [SELECT OwnerId FROM AXF_OBJ_Household__c LIMIT 1]
      .OwnerId;
      Id entityOwner = [SELECT OwnerId FROM AXF_OBJ_FinancialEntity__c LIMIT 1]
      .OwnerId;

      ALT_CLS_ServicePrincipalProvisioner.RotationResult rotated = provisioner.rotate(
        'service@axon.test',
        'next-service@axon.test',
        'rotation-axf-76'
      );
      System.assertEquals(true, rotated.verified);
      System.assertEquals(
        u.get('service@axon.test').Id,
        rotated.previousOwnerId
      );
      System.assertEquals(
        u.get('next-service@axon.test').Id,
        rotated.currentOwnerId
      );
      System.assertEquals(
        rotated.currentOwnerId,
        [SELECT OwnerId FROM AXF_OBJ_BootstrapAuthority__c LIMIT 1].OwnerId
      );
      System.assertEquals(
        householdOwner,
        [SELECT OwnerId FROM AXF_OBJ_Household__c LIMIT 1].OwnerId,
        'Rotation must preserve functional Household ownership.'
      );
      System.assertEquals(
        entityOwner,
        [SELECT OwnerId FROM AXF_OBJ_FinancialEntity__c LIMIT 1].OwnerId,
        'Rotation must preserve functional Financial Entity ownership.'
      );
      System.assertEquals(
        rotated.currentOwnerId,
        provisioner.rotate(
            'service@axon.test',
            'next-service@axon.test',
            'rotation-axf-76'
          )
          .currentOwnerId,
        'Equivalent rotation must replay.'
      );
    }
  }
  @IsTest
  static void authorizedCrudReplayConflictAndDeniedMutation() {
    Map<String, User> u = users();
    seams(u);
    authority(u.get('service@axon.test').Id);
    Id householdId;
    Id entityId;
    String entityRef;
    AXF_CLS_CTRL_FinancialEntity.MutationRequest updateRequest;
    System.runAs(u.get('owner@axon.test')) {
      AXF_CLS_CTRL_HouseholdBootstrap.initialize(bootstrap());
      householdId = [SELECT Id FROM AXF_OBJ_Household__c LIMIT 1].Id;
      AXF_CLS_CTRL_FinancialEntity.MutationRequest createRequest = new AXF_CLS_CTRL_FinancialEntity.MutationRequest();
      createRequest.householdId = householdId;
      createRequest.entityKey = 'fie-v1:00000000-0000-4000-8000-000000000030';
      createRequest.kind = 'ORGANIZATION';
      createRequest.legalName = 'Acme Legal';
      createRequest.displayName = 'Acme';
      createRequest.idempotencyKey = '00000000-0000-4000-8000-000000000031';
      createRequest.correlationId = '00000000-0000-4000-8000-000000000032';
      ALT_CLS_FinancialEntityGateway.Result created = AXF_CLS_CTRL_FinancialEntity.createEntity(
        createRequest
      );
      entityRef = created.entityRef;
      entityId = [
        SELECT Id
        FROM AXF_OBJ_FinancialEntity__c
        WHERE AXF_FIE_EXI_EntityRef__c = :entityRef
      ]
      .Id;
      System.assertEquals(
        entityRef,
        AXF_CLS_CTRL_FinancialEntity.createEntity(createRequest).entityRef
      );
      AXF_CLS_CTRL_FinancialEntity.ResponseEnvelope listed = AXF_CLS_CTRL_FinancialEntity.listEntities();
      System.assertEquals('READY_DATA', listed.state);
      System.assertEquals(2, listed.entities.size());
      AXF_CLS_CTRL_FinancialEntity.ResponseEnvelope detail = AXF_CLS_CTRL_FinancialEntity.readEntity(
        entityRef
      );
      System.assertEquals('READY_DATA', detail.state);
      System.assertEquals(
        'Acme Legal',
        ((AXF_CLS_CTRL_FinancialEntity.FinancialEntityDetail) detail.detail)
          .legalName
      );
      updateRequest = new AXF_CLS_CTRL_FinancialEntity.MutationRequest();
      updateRequest.entityRef = entityRef;
      updateRequest.displayName = 'Acme Updated';
      updateRequest.legalName = 'Acme Legal Updated';
      updateRequest.lifecycle = 'ACTIVE';
      updateRequest.expectedVersion = 1;
      updateRequest.idempotencyKey = '00000000-0000-4000-8000-000000000033';
      updateRequest.correlationId = '00000000-0000-4000-8000-000000000034';
      new ALT_CLS_EntityAccessService()
        .assign(
          access(householdId, entityId, u.get('target@axon.test').Id, 'VIEWER')
        );
    }
    System.runAs(u.get('target@axon.test')) {
      try {
        AXF_CLS_CTRL_FinancialEntity.updateEntity(updateRequest);
        Assert.fail('VIEWER must not update an entity.');
      } catch (AuraHandledException expected) {
        Assert.isNotNull(
          expected,
          'VIEWER denial must remain non-enumerating.'
        );
      }
    }
    System.runAs(u.get('owner@axon.test')) {
      ALT_CLS_EntityAccessService.Request editor = access(
        householdId,
        entityId,
        u.get('target@axon.test').Id,
        'EDITOR'
      );
      editor.expectedVersion = 2;
      editor.idempotencyKey = '00000000-0000-4000-8000-000000000039';
      new ALT_CLS_EntityAccessService().assign(editor);
    }
    System.runAs(u.get('target@axon.test')) {
      ALT_CLS_FinancialEntityGateway.Result updated = AXF_CLS_CTRL_FinancialEntity.updateEntity(
        updateRequest
      );
      Assert.areEqual(2, updated.version, 'EDITOR must update successfully.');
      Assert.areEqual(
        2,
        AXF_CLS_CTRL_FinancialEntity.updateEntity(updateRequest).version,
        'Equivalent EDITOR update must replay.'
      );
      updateRequest.idempotencyKey = '00000000-0000-4000-8000-000000000035';
      try {
        AXF_CLS_CTRL_FinancialEntity.updateEntity(updateRequest);
        Assert.fail('A stale EDITOR update must conflict.');
      } catch (AuraHandledException expected) {
        Assert.isNotNull(
          expected,
          'Conflict must use a stable endpoint error.'
        );
      }
      AXF_CLS_CTRL_FinancialEntity.MutationRequest denied = new AXF_CLS_CTRL_FinancialEntity.MutationRequest();
      denied.householdId = householdId;
      denied.entityKey = 'fie-v1:00000000-0000-4000-8000-000000000036';
      denied.kind = 'PERSON';
      denied.legalName = 'Denied';
      denied.displayName = 'Denied';
      denied.idempotencyKey = '00000000-0000-4000-8000-000000000037';
      denied.correlationId = '00000000-0000-4000-8000-000000000038';
      System.assertEquals(
        false,
        new ALT_CLS_FinancialEntityAuthorization()
          .authorize('AXF_CreateFinancialEntity', householdId, null)
          .allowed
      );
      try {
        AXF_CLS_CTRL_FinancialEntity.createEntity(denied);
        System.assert(false);
      } catch (AuraHandledException expected) {
        System.assertNotEquals(null, expected);
      }
      System.assertEquals(
        'READY_DATA',
        AXF_CLS_CTRL_FinancialEntity.readEntity(entityRef).state
      );
    }
  }
  @IsTest
  static void deniedUserCannotEnumerate() {
    Map<String, User> u = users();
    seams(u);
    authority(u.get('service@axon.test').Id);
    System.runAs(u.get('owner@axon.test')) {
      AXF_CLS_CTRL_HouseholdBootstrap.initialize(bootstrap());
    }
    System.runAs(u.get('target@axon.test')) {
      System.assertEquals(
        'READY_EMPTY',
        AXF_CLS_CTRL_FinancialEntity.listEntities().state
      );
      System.assertEquals(
        'FORBIDDEN',
        AXF_CLS_CTRL_FinancialEntity.readEntity(
            EncodingUtil.convertToHex(
              Crypto.generateDigest('SHA-256', Blob.valueOf('missing'))
            )
          )
          .state
      );
    }
  }

  @IsTest
  static void viewerHasReadWithoutEditOrCreateAndEditorHasEdit() {
    Map<String, User> u = users();
    seams(u);
    authority(u.get('service@axon.test').Id);
    Id householdId;
    Id entityId;
    System.runAs(u.get('owner@axon.test')) {
      AXF_CLS_CTRL_HouseholdBootstrap.initialize(bootstrap());
      AXF_OBJ_FinancialEntity__c entity = [
        SELECT Id, AXF_FIE_LKP_Household__c
        FROM AXF_OBJ_FinancialEntity__c
        LIMIT 1
      ];
      householdId = entity.AXF_FIE_LKP_Household__c;
      entityId = entity.Id;
      Test.startTest();
      new ALT_CLS_EntityAccessService()
        .assign(
          access(householdId, entityId, u.get('target@axon.test').Id, 'VIEWER')
        );
      Test.stopTest();
      Id targetId = u.get('target@axon.test').Id;
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM AXF_OBJ_FinancialEntity__Share
          WHERE
            ParentId = :entityId
            AND UserOrGroupId = :targetId
            AND RowCause = 'AXF_EntityGrant__c'
            AND AccessLevel = 'Read'
        ],
        'VIEWER must receive exactly one Read entity share.'
      );
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM AXF_OBJ_Household__Share
          WHERE
            ParentId = :householdId
            AND UserOrGroupId = :targetId
            AND RowCause = 'AXF_HouseholdGrant__c'
            AND AccessLevel = 'Read'
        ],
        'VIEWER must receive exactly one Read household share.'
      );
    }
    System.runAs(u.get('target@axon.test')) {
      ALT_CLS_FinancialEntityAuthorization authorization = new ALT_CLS_FinancialEntityAuthorization();
      Assert.isTrue(
        authorization.authorize(
            'AXF_ReadFinancialEntity',
            householdId,
            entityId
          )
          .allowed,
        'VIEWER must be able to read the entity.'
      );
      Assert.isFalse(
        authorization.authorize(
            'AXF_UpdateFinancialEntity',
            householdId,
            entityId
          )
          .allowed,
        'VIEWER must not be able to update the entity.'
      );
      Assert.isFalse(
        authorization.authorize('AXF_CreateFinancialEntity', householdId, null)
          .allowed,
        'VIEWER must not be able to create an entity.'
      );
    }
    System.runAs(u.get('owner@axon.test')) {
      ALT_CLS_EntityAccessService.Request editor = access(
        householdId,
        entityId,
        u.get('target@axon.test').Id,
        'EDITOR'
      );
      editor.expectedVersion = 2;
      editor.idempotencyKey = '00000000-0000-4000-8000-000000000041';
      new ALT_CLS_EntityAccessService().assign(editor);
    }
    System.runAs(u.get('target@axon.test')) {
      Assert.isTrue(
        new ALT_CLS_FinancialEntityAuthorization()
          .authorize('AXF_UpdateFinancialEntity', householdId, entityId)
          .allowed,
        'EDITOR must be able to update the entity.'
      );
    }
  }

  @IsTest
  static void removalPreservesHouseholdShareAndReportsResidualManualAccess() {
    Map<String, User> u = users();
    seams(u);
    authority(u.get('service@axon.test').Id);
    System.runAs(u.get('owner@axon.test')) {
      AXF_CLS_CTRL_HouseholdBootstrap.initialize(bootstrap());
      AXF_OBJ_FinancialEntity__c first = [
        SELECT
          Id,
          Name,
          AXF_FIE_LKP_Household__c,
          AXF_FIE_EXI_EntityKey__c,
          AXF_FIE_EXI_EntityRef__c,
          AXF_FIE_PKL_Kind__c,
          AXF_FIE_TXT_LegalName__c,
          AXF_FIE_TXT_DisplayName__c,
          AXF_FIE_PKL_Lifecycle__c,
          AXF_FIE_DAT_ActiveFrom__c,
          AXF_FIE_NUM_Version__c
        FROM AXF_OBJ_FinancialEntity__c
        LIMIT 1
      ];
      AXF_OBJ_FinancialEntity__c second = first.clone(
        false,
        true,
        false,
        false
      );
      second.AXF_FIE_EXI_EntityKey__c = 'fie-v1:00000000-0000-4000-8000-000000000042';
      second.AXF_FIE_EXI_EntityRef__c = ALT_CLS_AxfCanonical.entityRef(
        'HH_PRIMARY_V1',
        second.AXF_FIE_EXI_EntityKey__c
      );
      insert second;
      Id targetId = u.get('target@axon.test').Id;
      new ALT_CLS_EntityAccessService()
        .assign(
          access(first.AXF_FIE_LKP_Household__c, first.Id, targetId, 'VIEWER')
        );
      ALT_CLS_EntityAccessService.Request secondGrant = access(
        first.AXF_FIE_LKP_Household__c,
        second.Id,
        targetId,
        'VIEWER'
      );
      secondGrant.expectedVersion = 2;
      secondGrant.idempotencyKey = '00000000-0000-4000-8000-000000000043';
      new ALT_CLS_EntityAccessService().assign(secondGrant);
      insert new AXF_OBJ_FinancialEntity__Share(
        ParentId = first.Id,
        UserOrGroupId = targetId,
        AccessLevel = 'Read',
        RowCause = Schema.AXF_OBJ_FinancialEntity__Share.RowCause.Manual
      );
      ALT_CLS_EntityAccessService.Request removal = access(
        first.AXF_FIE_LKP_Household__c,
        first.Id,
        targetId,
        null
      );
      removal.expectedVersion = 3;
      removal.idempotencyKey = '00000000-0000-4000-8000-000000000044';
      ALT_CLS_EntityAccessService.Result result = new ALT_CLS_EntityAccessService()
        .remove(removal);
      Assert.isTrue(
        result.hasRemainingAccess,
        'A residual Manual share must be reported.'
      );
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM AXF_OBJ_Household__Share
          WHERE
            ParentId = :first.AXF_FIE_LKP_Household__c
            AND UserOrGroupId = :targetId
            AND RowCause = 'AXF_HouseholdGrant__c'
        ],
        'Another entity grant must preserve the household share.'
      );
    }
  }

  @IsTest
  static void accessRejectsNonCanonicalUuidAndAuditsFederationIdentity() {
    Map<String, User> u = users();
    seams(u);
    authority(u.get('service@axon.test').Id);
    System.runAs(u.get('owner@axon.test')) {
      AXF_CLS_CTRL_HouseholdBootstrap.initialize(bootstrap());
      AXF_OBJ_FinancialEntity__c entity = [
        SELECT Id, AXF_FIE_LKP_Household__c
        FROM AXF_OBJ_FinancialEntity__c
        LIMIT 1
      ];
      ALT_CLS_EntityAccessService.Request invalid = access(
        entity.AXF_FIE_LKP_Household__c,
        entity.Id,
        u.get('target@axon.test').Id,
        'VIEWER'
      );
      invalid.idempotencyKey = 'NOT-A-UUID';
      try {
        new ALT_CLS_EntityAccessService().assign(invalid);
        Assert.fail('A non-canonical UUID must be rejected.');
      } catch (ALT_CLS_EntityAccessService.AccessException expected) {
        Assert.areEqual(
          'FORBIDDEN',
          expected.getMessage(),
          'Invalid UUIDs fail closed.'
        );
      }
      ALT_CLS_EntityAccessService.Request valid = access(
        entity.AXF_FIE_LKP_Household__c,
        entity.Id,
        u.get('target@axon.test').Id,
        'VIEWER'
      );
      new ALT_CLS_EntityAccessService().assign(valid);
      AXF_OBJ_AuditEvent__c audit = (AXF_OBJ_AuditEvent__c) Database.queryWithBinds(
        'SELECT AXF_AUE_TXT_ActorPrincipalKey__c, ' +
          'AXF_AUE_TXT_EffectivePrincipalKey__c, AXF_AUE_EXI_EventId__c ' +
          'FROM AXF_OBJ_AuditEvent__c ' +
          'WHERE AXF_AUE_TXT_OperationId__c = :operationId ' +
          'ORDER BY CreatedDate DESC LIMIT 1',
        new Map<String, Object>{
          'operationId' => 'authorization.entity-access.assign.v1'
        },
        AccessLevel.SYSTEM_MODE
      )[0];
      Assert.areEqual(
        'owner@axon.test',
        audit.AXF_AUE_TXT_ActorPrincipalKey__c,
        'Audit actor principal must use the acting federation identifier.'
      );
      Assert.areEqual(
        'owner@axon.test',
        audit.AXF_AUE_TXT_EffectivePrincipalKey__c,
        'Audit effective principal must equal the acting user for this operation.'
      );
      Assert.isTrue(
        Pattern.matches(
          '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          audit.AXF_AUE_EXI_EventId__c
        ),
        'Audit event ID must be a canonical UUID v4.'
      );
    }
  }

  @IsTest
  static void removalAllowsInactiveAndPrivilegedTargets() {
    Map<String, User> u = users();
    seams(u);
    authority(u.get('service@axon.test').Id);
    System.runAs(u.get('owner@axon.test')) {
      AXF_CLS_CTRL_HouseholdBootstrap.initialize(bootstrap());
      AXF_OBJ_FinancialEntity__c entity = [
        SELECT Id, AXF_FIE_LKP_Household__c
        FROM AXF_OBJ_FinancialEntity__c
        LIMIT 1
      ];
      List<Id> targets = new List<Id>{
        u.get('inactive@axon.test').Id,
        u.get('privileged-target@axon.test').Id
      };
      insert new AXF_OBJ_FinancialEntity__Share(
        ParentId = entity.Id,
        UserOrGroupId = targets[1],
        AccessLevel = 'Read',
        RowCause = Schema.AXF_OBJ_FinancialEntity__Share.RowCause.AXF_EntityGrant__c
      );
      Decimal expectedVersion = 1;
      Integer sequence = 50;
      for (Id targetId : targets) {
        ALT_CLS_EntityAccessService.Request removal = access(
          entity.AXF_FIE_LKP_Household__c,
          entity.Id,
          targetId,
          null
        );
        removal.expectedVersion = expectedVersion++;
        removal.idempotencyKey =
          '00000000-0000-4000-8000-0000000000' + String.valueOf(sequence++);
        new ALT_CLS_EntityAccessService().remove(removal);
      }
      Assert.areEqual(
        0,
        [
          SELECT COUNT()
          FROM AXF_OBJ_FinancialEntity__Share
          WHERE
            ParentId = :entity.Id
            AND UserOrGroupId IN :targets
            AND RowCause = 'AXF_EntityGrant__c'
        ],
        'Cleanup must work even when a former target is inactive or privileged.'
      );
    }
  }

  @IsTest
  static void detailExposesManagementOnlyToQualifiedOwner() {
    Map<String, User> u = users();
    seams(u);
    authority(u.get('service@axon.test').Id);
    String entityRef;
    Id householdId;
    Id entityId;
    System.runAs(u.get('owner@axon.test')) {
      AXF_CLS_CTRL_HouseholdBootstrap.initialize(bootstrap());
      AXF_OBJ_FinancialEntity__c entity = [
        SELECT Id, AXF_FIE_LKP_Household__c, AXF_FIE_EXI_EntityRef__c
        FROM AXF_OBJ_FinancialEntity__c
        LIMIT 1
      ];
      entityRef = entity.AXF_FIE_EXI_EntityRef__c;
      householdId = entity.AXF_FIE_LKP_Household__c;
      entityId = entity.Id;
      Assert.isTrue(
        AXF_CLS_CTRL_FinancialEntity.readEntity(entityRef)
          .detail.canManageAccess,
        'Owner with custom permission and Modify All Data can manage access.'
      );
      new ALT_CLS_EntityAccessService()
        .assign(
          access(householdId, entityId, u.get('target@axon.test').Id, 'VIEWER')
        );
    }
    System.runAs(u.get('target@axon.test')) {
      Assert.isFalse(
        AXF_CLS_CTRL_FinancialEntity.readEntity(entityRef)
          .detail.canManageAccess,
        'A collaborator cannot manage access.'
      );
    }
  }

  @IsTest
  static void accessFailsClosedWithoutActingFederationIdentifier() {
    Map<String, User> u = users();
    seams(u);
    User actor = [SELECT Id FROM User WHERE LastName = 'nofedid' LIMIT 1];
    System.runAs(actor) {
      AXF_OBJ_Household__c household = new AXF_OBJ_Household__c(
        Name = 'No identity household',
        AXF_HH_EXI_HouseholdKey__c = 'HH_NO_IDENTITY_V1',
        AXF_HH_TXT_ReportingCurrencyIsoCode__c = 'BRL',
        AXF_HH_TXT_TimeZone__c = 'America/Sao_Paulo',
        AXF_HH_DAT_ActiveFrom__c = Date.today(),
        AXF_HH_PKL_Lifecycle__c = 'ACTIVE',
        AXF_HH_NUM_Version__c = 1
      );
      insert household;
      String entityKey = 'fie-v1:00000000-0000-4000-8000-000000000060';
      AXF_OBJ_FinancialEntity__c entity = new AXF_OBJ_FinancialEntity__c(
        AXF_FIE_LKP_Household__c = household.Id,
        AXF_FIE_EXI_EntityKey__c = entityKey,
        AXF_FIE_EXI_EntityRef__c = ALT_CLS_AxfCanonical.entityRef(
          String.valueOf(household.Id),
          entityKey
        ),
        AXF_FIE_PKL_Kind__c = 'PERSON',
        AXF_FIE_TXT_LegalName__c = 'No identity',
        AXF_FIE_TXT_DisplayName__c = 'No identity',
        AXF_FIE_DAT_ActiveFrom__c = Date.today(),
        AXF_FIE_PKL_Lifecycle__c = 'ACTIVE',
        AXF_FIE_NUM_Version__c = 1
      );
      insert entity;
      try {
        new ALT_CLS_EntityAccessService()
          .assign(
            access(
              household.Id,
              entity.Id,
              u.get('target@axon.test').Id,
              'VIEWER'
            )
          );
        Assert.fail('An actor without FederationIdentifier must fail closed.');
      } catch (ALT_CLS_EntityAccessService.AccessException expected) {
        Assert.areEqual(
          'FORBIDDEN',
          expected.getMessage(),
          'Missing identity must be rejected before mutation.'
        );
      }
      Assert.areEqual(
        0,
        [
          SELECT COUNT()
          FROM AXF_OBJ_FinancialEntity__Share
          WHERE ParentId = :entity.Id AND RowCause = 'AXF_EntityGrant__c'
        ],
        'Identity failure must not create a share.'
      );
    }
  }
  private static ALT_CLS_EntityAccessService.Request access(
    Id h,
    Id e,
    Id target,
    String role
  ) {
    ALT_CLS_EntityAccessService.Request r = new ALT_CLS_EntityAccessService.Request();
    r.householdId = h;
    r.entityId = e;
    r.targetUserId = target;
    r.role = role;
    r.expectedVersion = 1;
    r.idempotencyKey = '00000000-0000-4000-8000-000000000010';
    r.correlationId = '00000000-0000-4000-8000-000000000011';
    return r;
  }
  private static void seams(Map<String, User> u) {
    ALT_CLS_ServicePrincipalResolver.testPrincipalId = u.get(
        'service@axon.test'
      )
      .Id;
    ALT_CLS_HouseholdApplicationService.allowInTests = true;
    ALT_CLS_FinancialEntityAuthorization.allowCustomPermissionsInTests = true;
    AXF_CLS_CTRL_FinancialEntity.allowCustomPermissionsInTests = true;
    ALT_CLS_EntityAccessService.allowInTests = true;
  }
  private static void authority(Id o) {
    insert new AXF_OBJ_BootstrapAuthority__c(
      OwnerId = o,
      AXF_BSA_EXI_AuthorityKey__c = 'HH_PRIMARY_V1',
      AXF_BSA_PKL_State__c = 'AVAILABLE',
      AXF_BSA_NUM_Version__c = 0
    );
  }
  private static AXF_CLS_CTRL_HouseholdBootstrap.InitializeRequest bootstrap() {
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
  private static User makeUser(Id p, String a, String f) {
    return new User(
      Alias = a.left(8),
      Email = String.isBlank(f) ? a + '@axon.test' : f,
      EmailEncodingKey = 'UTF-8',
      LastName = a,
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = p,
      TimeZoneSidKey = 'America/Sao_Paulo',
      Username = a + '-' + DateTime.now().getTime() + '@axon.test',
      FederationIdentifier = f
    );
  }
  private static Map<String, User> users() {
    Map<String, User> r = new Map<String, User>();
    for (User u : [
      SELECT Id, FederationIdentifier, LanguageLocaleKey, LocaleSidKey
      FROM User
      WHERE
        FederationIdentifier IN (
          'owner@axon.test',
          'privileged-target@axon.test',
          'target@axon.test',
          'service@axon.test',
          'next-service@axon.test',
          'inactive@axon.test'
        )
    ])
      r.put(u.FederationIdentifier, u);
    return r;
  }
}
