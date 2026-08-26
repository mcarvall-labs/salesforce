public with sharing class ALT_CLS_HouseholdApplicationService {
  @TestVisible
  private static Boolean allowInTests = false;
  public ALT_CLS_HouseholdBootstrapGateway.Result initialize(
    InitializeRequest request
  ) {
    if (
      !(Test.isRunningTest() && allowInTests) &&
      !FeatureManagement.checkPermission('AXF_InitializeHousehold')
    )
      deny();
    if (
      request == null ||
      String.isBlank(request.reportingCurrency) ||
      String.isBlank(request.timeZone) ||
      !Pattern.matches(
        '^[A-Za-z]{3}$',
        String.valueOf(request.reportingCurrency)
      ) ||
      !Pattern.matches(
        '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        String.valueOf(request.idempotencyKey)
      ) ||
      !Pattern.matches(
        '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        String.valueOf(request.correlationId)
      ) ||
      !Pattern.matches(
        '^fie-v1:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        request.entityKey
      ) ||
      !new Set<String>{ 'PERSON', 'ORGANIZATION' }.contains(request.kind) ||
      String.isBlank(request.legalName) ||
      String.isBlank(request.displayName) ||
      request.reportingCurrency.length() > 255 ||
      request.timeZone.length() > 255 ||
      request.entityKey.length() > 255 ||
      request.legalName.length() > 255 ||
      request.displayName.length() > 255 ||
      request.idempotencyKey.length() > 255 ||
      request.correlationId.length() > 255
    )
      deny();
    if (
      !(Test.isRunningTest() && allowInTests) &&
      (!Schema.sObjectType.AXF_OBJ_Household__c.isCreateable() ||
      !Schema.sObjectType.AXF_OBJ_FinancialEntity__c.isCreateable())
    )
      deny();
    String payload = JSON.serialize(
      new Map<String, Object>{
        'initialEntity' => new Map<String, Object>{
          'displayName' => request.displayName,
          'entityKey' => request.entityKey,
          'kind' => request.kind,
          'legalName' => request.legalName
        },
        'reportingCurrency' => request.reportingCurrency.toUpperCase(),
        'timeZone' => request.timeZone
      }
    );
    ALT_CLS_HouseholdBootstrapGateway.Command command = new ALT_CLS_HouseholdBootstrapGateway.Command();
    command.reportingCurrency = request.reportingCurrency.toUpperCase();
    command.timeZone = request.timeZone;
    command.entityKey = request.entityKey;
    command.kind = request.kind;
    command.legalName = request.legalName;
    command.displayName = request.displayName;
    command.idempotencyKey = request.idempotencyKey;
    command.correlationId = request.correlationId;
    command.payloadHash = ALT_CLS_AxfCanonical.sha256(payload);
    return new ALT_CLS_HouseholdBootstrapGateway().persist(command);
  }
  private static void deny() {
    throw new ApplicationException('FORBIDDEN');
  }
  public class InitializeRequest {
    public String reportingCurrency;
    public String timeZone;
    public String entityKey;
    public String kind;
    public String legalName;
    public String displayName;
    public String idempotencyKey;
    public String correlationId;
  }
  public class ApplicationException extends Exception {
  }
}
