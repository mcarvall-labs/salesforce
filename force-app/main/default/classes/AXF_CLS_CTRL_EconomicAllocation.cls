/**
 * @description Controller exclusivo do LWC aXF_LWC_economicAllocation (AXF-126). Erros
 * sanitizados como {code, reasons[]}; nunca stack trace, PII ou existencia de registros nao
 * autorizados.
 */
public with sharing class AXF_CLS_CTRL_EconomicAllocation {
  public class Context {
    @AuraEnabled
    public Boolean canAllocate;
    @AuraEnabled
    public String factKind;
    @AuraEnabled
    public List<AXF_CLS_AuthorizedContextService.ContextView> holders;
    @AuraEnabled
    public List<ALT_CLS_EconomicAllocationService.SetView> sets;
  }

  @AuraEnabled
  public static Context getContext(Id factId) {
    try {
      if (factId == null) {
        throw invalid();
      }
      Context result = new Context();
      result.canAllocate = FeatureManagement.checkPermission(
        ALT_CLS_EconomicAllocationService.CP_ALLOCATE
      );
      result.factKind = kindOf(factId);
      result.holders = AXF_CLS_AuthorizedContextService.listAuthorizedContexts();
      result.sets = new ALT_CLS_EconomicAllocationService()
        .listForFact(result.factKind, factId);
      return result;
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_EconomicAllocationService.SetView propose(
    String request
  ) {
    try {
      if (String.isBlank(request)) {
        throw invalid();
      }
      return new ALT_CLS_EconomicAllocationService()
        .propose(
          (ALT_CLS_EconomicAllocationService.ProposeInput) JSON.deserializeStrict(
            request,
            ALT_CLS_EconomicAllocationService.ProposeInput.class
          )
        );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_EconomicAllocationService.SetView confirm(
    Id setId,
    Decimal expectedVersion,
    String operationKey
  ) {
    try {
      return new ALT_CLS_EconomicAllocationService()
        .confirm(setId, expectedVersion, operationKey);
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_EconomicAllocationService.SetView discard(
    Id setId,
    Decimal expectedVersion
  ) {
    try {
      return new ALT_CLS_EconomicAllocationService()
        .discard(setId, expectedVersion);
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  private static String kindOf(Id factId) {
    Schema.SObjectType type = factId.getSObjectType();
    if (type == AXF_OBJ_BankAccountTransaction__c.SObjectType) {
      return 'BANK';
    }
    if (type == AXF_OBJ_CreditCardTransaction__c.SObjectType) {
      return 'CARD';
    }
    if (type == AXF_OBJ_FinancialTransaction__c.SObjectType) {
      return 'MANUAL';
    }
    throw invalid();
  }

  private static AuraHandledException invalid() {
    return sanitized('INVALID_INPUT', new List<String>());
  }

  private static AuraHandledException sanitized(
    String code,
    List<String> reasons
  ) {
    AuraHandledException result = new AuraHandledException(code);
    result.setMessage(
      JSON.serialize(
        new Map<String, Object>{ 'code' => code, 'reasons' => reasons }
      )
    );
    return result;
  }

  private static AuraHandledException safe(Exception failure) {
    if (failure instanceof AuraHandledException) {
      return (AuraHandledException) failure;
    }
    if (
      failure instanceof ALT_CLS_EconomicAllocationService.EconomicAllocationException
    ) {
      ALT_CLS_EconomicAllocationService.EconomicAllocationException typed = (ALT_CLS_EconomicAllocationService.EconomicAllocationException) failure;
      return sanitized(typed.code, typed.reasons);
    }
    if (
      failure instanceof JSONException ||
      failure instanceof System.StringException ||
      failure instanceof System.TypeException
    ) {
      return invalid();
    }
    if (
      failure instanceof System.QueryException &&
      failure.getMessage() != null &&
      failure.getMessage().contains('UNABLE_TO_LOCK_ROW')
    ) {
      // Lock contention is transient: tell the client a retry may succeed.
      return sanitized('LOCKED', new List<String>());
    }
    if (
      failure instanceof System.QueryException ||
      failure instanceof System.SecurityException ||
      failure instanceof System.NoAccessException
    ) {
      return sanitized('NOT_ACCESSIBLE', new List<String>());
    }
    if (failure instanceof DmlException) {
      DmlException dml = (DmlException) failure;
      if (dml.getDmlType(0) == StatusCode.DUPLICATE_VALUE) {
        return sanitized('ACTIVE_SET_EXISTS', new List<String>());
      }
      return sanitized('REJECTED', new List<String>());
    }
    System.debug(
      LoggingLevel.ERROR,
      'AXF-126 UNEXPECTED: ' +
        failure.getTypeName() +
        ' ' +
        failure.getMessage()
    );
    return sanitized('UNEXPECTED', new List<String>());
  }
}
