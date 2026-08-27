public with sharing class AXF_CLS_CTRL_FinancialEntity {
  @TestVisible
  private static Boolean allowCustomPermissionsInTests = false;
  private static final String UUID = '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$';
  @AuraEnabled(cacheable=true)
  public static ResponseEnvelope listEntities() {
    ResponseEnvelope response = new ResponseEnvelope('READY_EMPTY');
    try {
      requireReadAccess();
      for (
        AXF_OBJ_FinancialEntity__c record : new ALT_CLS_FinancialEntitySelector()
          .selectAccessible()
      ) {
        ALT_CLS_FinancialEntityAuthorization.Decision decision = new ALT_CLS_FinancialEntityAuthorization()
          .authorize(
            'AXF_ReadFinancialEntity',
            record.AXF_FIE_LKP_Household__c,
            record.Id
          );
        if (decision.allowed)
          response.entities.add(toSummary(record, decision.allowedActions));
      }
      if (!response.entities.isEmpty())
        response.state = 'READY_DATA';
      return response;
    } catch (AuraHandledException denied) {
      return new ResponseEnvelope('FORBIDDEN');
    } catch (QueryException denied) {
      return new ResponseEnvelope('FORBIDDEN');
    } catch (Exception operationalFailure) {
      return new ResponseEnvelope('ERROR_TERMINAL');
    }
  }

  @AuraEnabled(cacheable=true)
  public static ResponseEnvelope readEntity(String entityRef) {
    if (
      String.isBlank(entityRef) || !Pattern.matches('^[0-9a-f]{64}$', entityRef)
    )
      return new ResponseEnvelope('FORBIDDEN');
    try {
      requireReadAccess();
      AXF_OBJ_FinancialEntity__c record = new ALT_CLS_FinancialEntitySelector()
        .selectAccessibleByRef(entityRef);
      if (record == null)
        return new ResponseEnvelope('FORBIDDEN');
      ResponseEnvelope response = new ResponseEnvelope('READY_DATA');
      ALT_CLS_FinancialEntityAuthorization.Decision decision = new ALT_CLS_FinancialEntityAuthorization()
        .authorize(
          'AXF_ReadFinancialEntity',
          record.AXF_FIE_LKP_Household__c,
          record.Id
        );
      if (!decision.allowed)
        return new ResponseEnvelope('FORBIDDEN');
      Boolean includeLegalName = decision.allowedFields.contains('legalName');
      if (includeLegalName) {
        if (
          !Schema.sObjectType.AXF_OBJ_FinancialEntity__c.fields.AXF_FIE_TXT_LegalName__c.isAccessible()
        )
          return new ResponseEnvelope('FORBIDDEN');
        record = new ALT_CLS_FinancialEntitySelector()
          .selectAccessibleDetailByRef(entityRef);
      }
      response.detail = toDetail(
        record,
        includeLegalName,
        decision.allowedActions
      );
      return response;
    } catch (AuraHandledException denied) {
      return new ResponseEnvelope('FORBIDDEN');
    } catch (QueryException denied) {
      return new ResponseEnvelope('FORBIDDEN');
    } catch (Exception operationalFailure) {
      return new ResponseEnvelope('ERROR_TERMINAL');
    }
  }

  @AuraEnabled
  public static ALT_CLS_FinancialEntityGateway.Result createEntity(
    MutationRequest request
  ) {
    if (
      request == null ||
      request.householdId == null ||
      !allowPermission('AXF_CreateFinancialEntity')
    )
      deny();
    ALT_CLS_FinancialEntityAuthorization.Decision decision = new ALT_CLS_FinancialEntityAuthorization()
      .authorize('AXF_CreateFinancialEntity', request.householdId, null);
    if (
      !decision.allowed ||
      !Schema.sObjectType.AXF_OBJ_FinancialEntity__c.isCreateable() ||
      !mutationFieldsAllowed(true)
    )
      deny();
    validate(request, true, true);
    ALT_CLS_FinancialEntityGateway.Command command = command(request);
    command.payloadHash = ALT_CLS_AxfCanonical.sha256(JSON.serialize(request));
    return persistMutation(command, true);
  }

  @AuraEnabled
  public static ALT_CLS_FinancialEntityGateway.Result updateEntity(
    MutationRequest request
  ) {
    if (
      request == null ||
      String.isBlank(request.entityRef) ||
      !allowPermission('AXF_UpdateFinancialEntity')
    )
      deny();
    AXF_OBJ_FinancialEntity__c target = new ALT_CLS_FinancialEntitySelector()
      .selectAccessibleByRef(request.entityRef);
    if (
      target == null ||
      (request.householdId != null &&
      target.AXF_FIE_LKP_Household__c != request.householdId)
    )
      deny();
    request.householdId = target.AXF_FIE_LKP_Household__c;
    ALT_CLS_FinancialEntityAuthorization.Decision decision = new ALT_CLS_FinancialEntityAuthorization()
      .authorize('AXF_UpdateFinancialEntity', request.householdId, target.Id);
    Boolean mayEditLegalName = decision.allowedFields.contains('legalName');
    if (
      !decision.allowed ||
      !Schema.sObjectType.AXF_OBJ_FinancialEntity__c.isUpdateable() ||
      !mutationFieldsAllowed(false, mayEditLegalName)
    )
      deny();
    validate(request, false, mayEditLegalName);
    ALT_CLS_FinancialEntityGateway.Command command = command(request);
    command.updateLegalName = mayEditLegalName;
    command.payloadHash = ALT_CLS_AxfCanonical.sha256(JSON.serialize(request));
    return persistMutation(command, false);
  }

  private static ALT_CLS_FinancialEntityGateway.Result persistMutation(
    ALT_CLS_FinancialEntityGateway.Command command,
    Boolean creating
  ) {
    Savepoint checkpoint = Database.setSavepoint();
    try {
      ALT_CLS_FinancialEntityGateway gateway = new ALT_CLS_FinancialEntityGateway();
      return creating
        ? gateway.createEntity(command)
        : gateway.updateEntity(command);
    } catch (ALT_CLS_FinancialEntityGateway.GatewayException failure) {
      Database.rollback(checkpoint);
      if (failure.getMessage() == 'CONFLICT')
        throw new AuraHandledException('CONFLICT');
      deny();
      return null;
    } catch (Exception failure) {
      Database.rollback(checkpoint);
      throw new AuraHandledException('ERROR_TERMINAL');
    }
  }

  private static void validate(
    MutationRequest r,
    Boolean creating,
    Boolean requireLegalName
  ) {
    if (
      !Pattern.matches(UUID, String.valueOf(r.idempotencyKey)) ||
      !Pattern.matches(UUID, String.valueOf(r.correlationId)) ||
      String.isBlank(r.displayName) ||
      (requireLegalName && String.isBlank(r.legalName))
    )
      deny();
    if (
      r.displayName.length() > 255 ||
      (requireLegalName && r.legalName.length() > 255)
    )
      deny();
    if (
      creating &&
      (!Pattern.matches(
        '^fie-v1:' + UUID.substring(1),
        String.valueOf(r.entityKey)
      ) || !new Set<String>{ 'PERSON', 'ORGANIZATION' }.contains(r.kind))
    )
      deny();
    if (
      !creating &&
      (r.expectedVersion == null ||
      !new Set<String>{ 'ACTIVE', 'SUSPENDED', 'CLOSED' }
        .contains(r.lifecycle) ||
      (r.lifecycle == 'CLOSED' &&
      r.activeTo == null))
    )
      deny();
  }
  private static ALT_CLS_FinancialEntityGateway.Command command(
    MutationRequest r
  ) {
    ALT_CLS_FinancialEntityGateway.Command c = new ALT_CLS_FinancialEntityGateway.Command();
    c.householdId = r.householdId;
    c.entityKey = r.entityKey;
    c.entityRef = r.entityRef;
    c.kind = r.kind;
    c.legalName = r.legalName;
    c.displayName = r.displayName;
    c.lifecycle = r.lifecycle;
    c.activeTo = r.activeTo;
    c.expectedVersion = r.expectedVersion;
    c.idempotencyKey = r.idempotencyKey;
    c.correlationId = r.correlationId;
    return c;
  }
  private static void deny() {
    throw new AuraHandledException('FORBIDDEN');
  }
  private static void requireReadAccess() {
    if (
      !allowPermission('AXF_ReadFinancialEntity') ||
      !Schema.sObjectType.AXF_OBJ_FinancialEntity__c.isAccessible() ||
      !Schema.sObjectType.AXF_OBJ_FinancialEntity__c.fields.AXF_FIE_EXI_EntityRef__c.isAccessible() ||
      !Schema.sObjectType.AXF_OBJ_FinancialEntity__c.fields.AXF_FIE_TXT_DisplayName__c.isAccessible() ||
      !Schema.sObjectType.AXF_OBJ_FinancialEntity__c.fields.AXF_FIE_PKL_Kind__c.isAccessible() ||
      !Schema.sObjectType.AXF_OBJ_FinancialEntity__c.fields.AXF_FIE_PKL_Lifecycle__c.isAccessible() ||
      !Schema.sObjectType.AXF_OBJ_FinancialEntity__c.fields.AXF_FIE_NUM_Version__c.isAccessible()
    )
      deny();
  }
  private static Boolean mutationFieldsAllowed(Boolean creating) {
    return mutationFieldsAllowed(creating, true);
  }
  private static Boolean mutationFieldsAllowed(
    Boolean creating,
    Boolean includeLegalName
  ) {
    Boolean common = creating
      ? Schema.sObjectType.AXF_OBJ_FinancialEntity__c.fields.AXF_FIE_TXT_DisplayName__c.isCreateable() &&
        Schema.sObjectType.AXF_OBJ_FinancialEntity__c.fields.AXF_FIE_TXT_LegalName__c.isCreateable()
      : Schema.sObjectType.AXF_OBJ_FinancialEntity__c.fields.AXF_FIE_TXT_DisplayName__c.isUpdateable() &&
        (!includeLegalName ||
        Schema.sObjectType.AXF_OBJ_FinancialEntity__c.fields.AXF_FIE_TXT_LegalName__c.isUpdateable()) &&
        Schema.sObjectType.AXF_OBJ_FinancialEntity__c.fields.AXF_FIE_PKL_Lifecycle__c.isUpdateable() &&
        Schema.sObjectType.AXF_OBJ_FinancialEntity__c.fields.AXF_FIE_DAT_ActiveTo__c.isUpdateable();
    if (!creating)
      return common;
    return common &&
      Schema.sObjectType.AXF_OBJ_FinancialEntity__c.fields.AXF_FIE_LKP_Household__c.isCreateable() &&
      Schema.sObjectType.AXF_OBJ_FinancialEntity__c.fields.AXF_FIE_EXI_EntityKey__c.isCreateable() &&
      Schema.sObjectType.AXF_OBJ_FinancialEntity__c.fields.AXF_FIE_PKL_Kind__c.isCreateable();
  }
  private static Boolean allowPermission(String permissionName) {
    return (Test.isRunningTest() && allowCustomPermissionsInTests) ||
      FeatureManagement.checkPermission(permissionName);
  }

  private static FinancialEntitySummary toSummary(
    AXF_OBJ_FinancialEntity__c record,
    Set<String> allowedActions
  ) {
    FinancialEntitySummary dto = new FinancialEntitySummary();
    dto.entityRef = record.AXF_FIE_EXI_EntityRef__c;
    dto.entityId = record.Id;
    dto.householdVersion = record.AXF_FIE_LKP_Household__r.AXF_HH_NUM_Version__c;
    dto.canManageAccess = ALT_CLS_EntityAccessService.canManageAccess(
      record.AXF_FIE_LKP_Household__r.OwnerId
    );
    dto.displayName = record.AXF_FIE_TXT_DisplayName__c;
    dto.kind = record.AXF_FIE_PKL_Kind__c;
    dto.reportingCurrencyIsoCode = record.AXF_FIE_LKP_Household__r.AXF_HH_TXT_ReportingCurrencyIsoCode__c;
    dto.lifecycle = record.AXF_FIE_PKL_Lifecycle__c;
    dto.version = record.AXF_FIE_NUM_Version__c;
    dto.activeTo = record.AXF_FIE_DAT_ActiveTo__c;
    dto.allowedActions = new List<String>(allowedActions);
    return dto;
  }
  @AuraEnabled
  public static ALT_CLS_EntityAccessService.Result assignAccess(
    ALT_CLS_EntityAccessService.Request request
  ) {
    try {
      return new ALT_CLS_EntityAccessService().assign(request);
    } catch (ALT_CLS_EntityAccessService.AccessException denied) {
      if (denied.getMessage() == 'CONFLICT')
        throw new AuraHandledException('CONFLICT');
      deny();
      return null;
    }
  }
  @AuraEnabled
  public static ALT_CLS_EntityAccessService.Result removeAccess(
    ALT_CLS_EntityAccessService.Request request
  ) {
    try {
      return new ALT_CLS_EntityAccessService().remove(request);
    } catch (ALT_CLS_EntityAccessService.AccessException denied) {
      if (denied.getMessage() == 'CONFLICT')
        throw new AuraHandledException('CONFLICT');
      deny();
      return null;
    }
  }
  private static FinancialEntitySummary toDetail(
    AXF_OBJ_FinancialEntity__c record,
    Boolean includeLegalName,
    Set<String> allowedActions
  ) {
    FinancialEntitySummary summary = toSummary(record, allowedActions);
    if (!includeLegalName)
      return summary;
    FinancialEntityDetail dto = new FinancialEntityDetail();
    dto.entityRef = summary.entityRef;
    dto.entityId = summary.entityId;
    dto.householdVersion = summary.householdVersion;
    dto.canManageAccess = summary.canManageAccess;
    dto.displayName = summary.displayName;
    dto.kind = summary.kind;
    dto.reportingCurrencyIsoCode = summary.reportingCurrencyIsoCode;
    dto.lifecycle = summary.lifecycle;
    dto.version = summary.version;
    dto.activeTo = summary.activeTo;
    dto.allowedActions = summary.allowedActions;
    dto.legalName = record.AXF_FIE_TXT_LegalName__c;
    return dto;
  }

  public class ResponseEnvelope {
    @AuraEnabled
    public String version = 'v1';
    @AuraEnabled
    public String state;
    @AuraEnabled
    public List<FinancialEntitySummary> entities = new List<FinancialEntitySummary>();
    @AuraEnabled
    public FinancialEntitySummary detail;
    public ResponseEnvelope(String state) {
      this.state = state;
    }
  }
  public virtual class FinancialEntitySummary {
    @AuraEnabled
    public String entityRef;
    @AuraEnabled
    public Id entityId;
    @AuraEnabled
    public Decimal householdVersion;
    @AuraEnabled
    public Boolean canManageAccess;
    @AuraEnabled
    public String displayName;
    @AuraEnabled
    public String kind;
    @AuraEnabled
    public String reportingCurrencyIsoCode;
    @AuraEnabled
    public String lifecycle;
    @AuraEnabled
    public Decimal version;
    @AuraEnabled
    public Date activeTo;
    @AuraEnabled
    public List<String> allowedActions;
  }
  public class FinancialEntityDetail extends FinancialEntitySummary {
    @AuraEnabled
    public String legalName;
  }
  public class MutationRequest {
    @AuraEnabled
    public Id householdId;
    @AuraEnabled
    public String entityKey;
    @AuraEnabled
    public String entityRef;
    @AuraEnabled
    public String kind;
    @AuraEnabled
    public String legalName;
    @AuraEnabled
    public String displayName;
    @AuraEnabled
    public String lifecycle;
    @AuraEnabled
    public Date activeTo;
    @AuraEnabled
    public Decimal expectedVersion;
    @AuraEnabled
    public String idempotencyKey;
    @AuraEnabled
    public String correlationId;
  }
}
