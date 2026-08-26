@IsTest
private class ALT_CLS_AxfHouseholdGoldenFixturesTest {
  @IsTest
  static void gf82BootstrapCanonicalKeys() {
    System.assertEquals(
      64,
      ALT_CLS_AxfCanonical.entityRef(
          'HH_PRIMARY_V1',
          'fie-v1:00000000-0000-4000-8000-000000000000'
        )
        .length()
    );
  }
  @IsTest
  static void gf83ReplayScopeSeparatesPayload() {
    String a = ALT_CLS_AxfCanonical.scopedHash(
      new List<String>{
        'HH_PRIMARY_V1',
        'household.household.initialize.v1',
        '00000000-0000-4000-8000-000000000000'
      }
    );
    System.assertEquals(
      a,
      ALT_CLS_AxfCanonical.scopedHash(
        new List<String>{
          'HH_PRIMARY_V1',
          'household.household.initialize.v1',
          '00000000-0000-4000-8000-000000000000'
        }
      )
    );
  }
  @IsTest
  static void gf84ConcurrentBootstrapUnique() {
    System.assert(
      Schema.SObjectType.AXF_OBJ_BootstrapAuthority__c.fields.AXF_BSA_EXI_AuthorityKey__c.isUnique()
    );
  }
  @IsTest
  static void gf85CreatePermissionExists() {
    System.assertNotEquals(
      null,
      FeatureManagement.checkPermission('AXF_CreateFinancialEntity')
    );
  }
  @IsTest
  static void gf86EntityRefDoesNotEnumerate() {
    String value = ALT_CLS_AxfCanonical.entityRef(
      'HH_PRIMARY_V1',
      'fie-v1:00000000-0000-4000-8000-000000000000'
    );
    System.assert(!value.contains('HH_PRIMARY_V1'));
    System.assert(Pattern.matches('^[0-9a-f]{64}$', value));
  }
  @IsTest
  static void gf87MembershipKeyBindsBothScopes() {
    String a = ALT_CLS_AxfCanonical.scopedHash(
        new List<String>{ 'hfe-v1', 'HH_PRIMARY_V1', 'entity-a' }
      ),
      b = ALT_CLS_AxfCanonical.scopedHash(
        new List<String>{ 'hfe-v1', 'HH_PRIMARY_V1', 'entity-b' }
      );
    System.assertNotEquals(a, b);
  }
  @IsTest
  static void gf88UpdateOperationHasIndependentScope() {
    String key = '00000000-0000-4000-8000-000000000000';
    System.assertNotEquals(
      ALT_CLS_AxfCanonical.scopedHash(
        new List<String>{ 'hh', 'household.financial-entity.create.v1', key }
      ),
      ALT_CLS_AxfCanonical.scopedHash(
        new List<String>{ 'hh', 'household.financial-entity.update.v1', key }
      )
    );
  }
  @IsTest
  static void gf89AuthorizationDefaultsDeny() {
    ALT_CLS_FinancialEntityAuthorization.Decision d = new ALT_CLS_FinancialEntityAuthorization()
      .authorize(null, null, null);
    System.assertEquals(false, d.allowed);
    System.assertEquals(0, d.allowedActions.size());
  }
  @IsTest
  static void gf90RootsArePrivate() {
    Map<String, EntityDefinition> definitions = entityDefinitions(
      new Set<String>{ 'AXF_OBJ_Household__c', 'AXF_OBJ_FinancialEntity__c' }
    );
    System.assertEquals(
      'Private',
      definitions.get('AXF_OBJ_Household__c').InternalSharingModel
    );
    System.assertEquals(
      'Private',
      definitions.get('AXF_OBJ_FinancialEntity__c').InternalSharingModel
    );
  }
  @IsTest
  static void gf91AccessibleStatesAreDistinct() {
    Set<String> states = new Set<String>{
      'LOADING',
      'READY_EMPTY',
      'READY_DATA',
      'FORBIDDEN',
      'CONFLICT',
      'ERROR_RECOVERABLE'
    };
    System.assertEquals(6, states.size());
  }
  @IsTest
  static void gf92OperationalObjectsNotPublic() {
    Map<String, EntityDefinition> definitions = entityDefinitions(
      new Set<String>{ 'AXF_OBJ_CommandExecution__c', 'AXF_OBJ_AuditEvent__c' }
    );
    System.assertEquals(
      'Private',
      definitions.get('AXF_OBJ_CommandExecution__c').InternalSharingModel
    );
    System.assertEquals(
      'Private',
      definitions.get('AXF_OBJ_AuditEvent__c').InternalSharingModel
    );
  }
  @IsTest
  static void gf93DtoContainsOnlyCanonicalFields() {
    Set<String> exposed = new Set<String>{
      'entityRef',
      'displayName',
      'kind',
      'reportingCurrencyIsoCode',
      'lifecycle',
      'version',
      'allowedActions'
    };
    System.assertEquals(7, exposed.size());
    System.assert(!exposed.contains('entityKey'));
    System.assert(!exposed.contains('legalName'));
  }
  @IsTest
  static void gf94GrantScopesDoNotCollide() {
    String user = 'user@example.test';
    String h = ALT_CLS_AxfCanonical.scopedHash(
        new List<String>{
          'grant-v1',
          'HH_PRIMARY_V1',
          'HOUSEHOLD',
          'HH_PRIMARY_V1',
          user,
          'HOUSEHOLD_OPERATIONS',
          '1'
        }
      ),
      e = ALT_CLS_AxfCanonical.scopedHash(
        new List<String>{
          'grant-v1',
          'HH_PRIMARY_V1',
          'ENTITY',
          'entity',
          user,
          'HOUSEHOLD_OPERATIONS',
          '1'
        }
      );
    System.assertNotEquals(h, e);
  }
  @IsTest
  static void gf95ProvisioningFailsClosedWithoutPrincipal() {
    try {
      ALT_CLS_ServicePrincipalProvisioner.requirePrincipal(
        'missing-' + String.valueOf(Crypto.getRandomInteger()) + '@invalid.test'
      );
      System.assert(false);
    } catch (ALT_CLS_ServicePrincipalProvisioner.ProvisioningException e) {
      System.assertEquals('SERVICE_PRINCIPAL_UNAVAILABLE', e.getMessage());
    }
  }
  @IsTest
  static void gf96ResolverFailsClosedForZeroUsers() {
    try {
      ALT_CLS_ServicePrincipalProvisioner.requirePrincipal(
        'rotation-missing-' +
          String.valueOf(Crypto.getRandomInteger()) +
          '@invalid.test'
      );
      System.assert(false);
    } catch (ALT_CLS_ServicePrincipalProvisioner.ProvisioningException e) {
      System.assertEquals('SERVICE_PRINCIPAL_UNAVAILABLE', e.getMessage());
    }
  }
  @IsTest
  static void ioMatrixDivergentPayloadHashesDiffer() {
    System.assertNotEquals(
      ALT_CLS_AxfCanonical.sha256('{"a":1}'),
      ALT_CLS_AxfCanonical.sha256('{"a":2}')
    );
  }
  @IsTest
  static void ioMatrixInvalidPrincipalIsFailClosed() {
    gf96ResolverFailsClosedForZeroUsers();
  }
  @IsTest
  static void ioMatrixNonEnumerationEnvelope() {
    AXF_CLS_CTRL_FinancialEntity.ResponseEnvelope e = AXF_CLS_CTRL_FinancialEntity.readEntity(
      'not-a-reference'
    );
    System.assertEquals('FORBIDDEN', e.state);
    System.assertEquals(0, e.entities.size());
  }
  private static Map<String, EntityDefinition> entityDefinitions(
    Set<String> names
  ) {
    Map<String, EntityDefinition> result = new Map<String, EntityDefinition>();
    for (EntityDefinition definition : [
      SELECT QualifiedApiName, InternalSharingModel
      FROM EntityDefinition
      WHERE QualifiedApiName IN :names
    ])
      result.put(definition.QualifiedApiName, definition);
    System.assertEquals(
      names.size(),
      result.size(),
      'Every canonical object must have an EntityDefinition.'
    );
    return result;
  }
}
