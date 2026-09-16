/** @description Dedicated realization UI boundary with sanitized application errors. */
public with sharing class AXF_CLS_CTRL_Realization {
  public class Applied {
    @AuraEnabled
    public Id allocationId;
    @AuraEnabled
    public Id targetId;
  }
  @AuraEnabled
  public static String read(Id targetId) {
    try {
      return JSON.serialize(new ALT_CLS_RealizationService().read(targetId));
    } catch (Exception failure) {
      throw safe(failure);
    }
  }
  @AuraEnabled
  public static Applied apply(String request) {
    try {
      Applied result = new Applied();
      result.allocationId = new ALT_CLS_RealizationService()
        .apply(
          (ALT_CLS_RealizationService.Input) JSON.deserializeStrict(
            request,
            ALT_CLS_RealizationService.Input.class
          )
        );
      result.targetId = [
        SELECT AXF_RA_LKP_FinancialTransaction__c
        FROM AXF_OBJ_ReconciliationAllocation__c
        WHERE Id = :result.allocationId
        WITH USER_MODE
      ]
      .AXF_RA_LKP_FinancialTransaction__c;
      return result;
    } catch (Exception failure) {
      throw safe(failure);
    }
  }
  @AuraEnabled
  public static Decimal sourceVersion(Id sourceId, String sourceKind) {
    try {
      return new ALT_CLS_RealizationService()
        .sourceVersion(sourceId, sourceKind);
    } catch (Exception failure) {
      throw safe(failure);
    }
  }
  @AuraEnabled
  public static Id reverse(
    Id allocationId,
    Decimal expectedVersion,
    String operationKey
  ) {
    try {
      return new ALT_CLS_RealizationService()
        .reverse(allocationId, expectedVersion, operationKey);
    } catch (Exception failure) {
      throw safe(failure);
    }
  }
  @AuraEnabled
  public static void retryFx(Id allocationId) {
    try {
      new ALT_CLS_RealizationService().retryFx(allocationId);
    } catch (Exception failure) {
      throw safe(failure);
    }
  }
  private static AuraHandledException safe(Exception failure) {
    String code = failure instanceof ALT_CLS_RealizationService.RealizationException
      ? failure.getMessage()
      : 'UNAVAILABLE';
    AuraHandledException result = new AuraHandledException(code);
    result.setMessage(code);
    return result;
  }
}
