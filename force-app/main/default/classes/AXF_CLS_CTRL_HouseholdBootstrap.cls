public with sharing class AXF_CLS_CTRL_HouseholdBootstrap {
  @AuraEnabled
  public static Result initialize(InitializeRequest request) {
    try {
      ALT_CLS_HouseholdApplicationService.InitializeRequest serviceRequest = new ALT_CLS_HouseholdApplicationService.InitializeRequest();
      serviceRequest.reportingCurrency = request.reportingCurrency;
      serviceRequest.timeZone = request.timeZone;
      serviceRequest.entityKey = request.entityKey;
      serviceRequest.kind = request.kind;
      serviceRequest.legalName = request.legalName;
      serviceRequest.displayName = request.displayName;
      serviceRequest.idempotencyKey = request.idempotencyKey;
      serviceRequest.correlationId = request.correlationId;
      ALT_CLS_HouseholdBootstrapGateway.Result serviceResult = new ALT_CLS_HouseholdApplicationService()
        .initialize(serviceRequest);
      Result result = new Result();
      result.state = 'READY_DATA';
      result.entityRef = serviceResult.entityRef;
      return result;
    } catch (Exception ignored) {
      Result result = new Result();
      result.state = 'FORBIDDEN';
      return result;
    }
  }
  public class InitializeRequest {
    @AuraEnabled
    public String reportingCurrency;
    @AuraEnabled
    public String timeZone;
    @AuraEnabled
    public String entityKey;
    @AuraEnabled
    public String kind;
    @AuraEnabled
    public String legalName;
    @AuraEnabled
    public String displayName;
    @AuraEnabled
    public String idempotencyKey;
    @AuraEnabled
    public String correlationId;
  }
  public class Result {
    @AuraEnabled
    public String state;
    @AuraEnabled
    public String entityRef;
  }
}
