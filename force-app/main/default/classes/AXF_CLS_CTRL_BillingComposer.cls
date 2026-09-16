/**
 * @description Controller exclusivo do LWC aXF_LWC_billingComposer (AXF-65). Orquestra o
 * servico de rascunho de cobranca e devolve erros sanitizados (codigo + incompatibilidades
 * por linha, sem stack trace, PII ou existencia de registros nao autorizados).
 */
public with sharing class AXF_CLS_CTRL_BillingComposer {
  public class ContractOption {
    @AuraEnabled
    public Id contractId;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Id counterpartyId;
    @AuraEnabled
    public String counterpartyName;
    @AuraEnabled
    public String currencyIso;
  }

  @AuraEnabled(cacheable=true)
  public static List<AXF_CLS_AuthorizedContextService.ContextView> getAuthorizedEntities() {
    try {
      return AXF_CLS_AuthorizedContextService.listAuthorizedContexts();
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<ContractOption> getContracts(Id accountId) {
    try {
      if (accountId == null) {
        throw invalid();
      }
      List<ContractOption> result = new List<ContractOption>();
      for (AXF_OBJ_Contract__c contract : [
        SELECT
          Id,
          Name,
          AXF_CTR_TXT_Title__c,
          AXF_CTR_TXT_CurrencyIsoCode__c,
          AXF_CTR_LKP_Counterparty__c,
          AXF_CTR_LKP_Counterparty__r.AXF_CPTY_TXT_DisplayName__c
        FROM AXF_OBJ_Contract__c
        WHERE
          AXF_CTR_LKP_Account__c = :accountId
          AND AXF_CTR_PKL_Lifecycle__c NOT IN :ALT_CLS_BillingDraftService.NON_BILLABLE_CONTRACTS
        WITH USER_MODE
        ORDER BY Name
        LIMIT 200
      ]) {
        ContractOption option = new ContractOption();
        option.contractId = contract.Id;
        option.label = String.isBlank(contract.AXF_CTR_TXT_Title__c)
          ? contract.Name
          : contract.Name + ' - ' + contract.AXF_CTR_TXT_Title__c;
        option.counterpartyId = contract.AXF_CTR_LKP_Counterparty__c;
        option.counterpartyName = contract.AXF_CTR_LKP_Counterparty__r
          ?.AXF_CPTY_TXT_DisplayName__c;
        option.currencyIso = contract.AXF_CTR_TXT_CurrencyIsoCode__c;
        result.add(option);
      }
      return result;
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static List<ALT_CLS_BillingDraftService.Candidate> getCandidates(
    Id contractId,
    Date periodStart,
    Date periodEnd,
    String currencyIso
  ) {
    try {
      if (contractId == null) {
        throw invalid();
      }
      return new ALT_CLS_BillingDraftService()
        .listCandidates(contractId, periodStart, periodEnd, currencyIso);
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static List<ALT_CLS_BillingDraftService.WorkRecordView> getApprovedWork(
    Id contractId
  ) {
    try {
      if (contractId == null) {
        throw invalid();
      }
      return new ALT_CLS_BillingDraftService().listApprovedWork(contractId);
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_BillingDraftService.DraftView compose(String request) {
    try {
      if (String.isBlank(request)) {
        throw invalid();
      }
      ALT_CLS_BillingDraftService service = new ALT_CLS_BillingDraftService();
      Id documentId = service.compose(
        (ALT_CLS_BillingDraftService.ComposeInput) JSON.deserializeStrict(
          request,
          ALT_CLS_BillingDraftService.ComposeInput.class
        )
      );
      return service.read(documentId);
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_BillingDraftService.DraftView read(Id documentId) {
    try {
      if (documentId == null) {
        throw invalid();
      }
      return new ALT_CLS_BillingDraftService().read(documentId);
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  private static AuraHandledException invalid() {
    AuraHandledException result = new AuraHandledException('INVALID_INPUT');
    result.setMessage(
      JSON.serialize(
        new Map<String, Object>{
          'code' => 'INVALID_INPUT',
          'issues' => new List<Object>()
        }
      )
    );
    return result;
  }

  /** Converte falhas em mensagem sanitizada: JSON {code, issues[]} para o LWC traduzir. */
  private static AuraHandledException safe(Exception failure) {
    if (failure instanceof AuraHandledException) {
      return (AuraHandledException) failure;
    }
    String code = 'UNEXPECTED';
    List<ALT_CLS_BillingDraftService.LineIssue> issues = new List<ALT_CLS_BillingDraftService.LineIssue>();
    if (failure instanceof ALT_CLS_BillingDraftService.BillingDraftException) {
      ALT_CLS_BillingDraftService.BillingDraftException typed = (ALT_CLS_BillingDraftService.BillingDraftException) failure;
      code = typed.code;
      issues = typed.issues;
    } else if (
      failure instanceof JSONException ||
      failure instanceof System.StringException ||
      failure instanceof System.TypeException
    ) {
      code = 'INVALID_INPUT';
    } else if (
      failure instanceof System.QueryException ||
      failure instanceof System.SecurityException ||
      failure instanceof System.NoAccessException
    ) {
      code = 'NOT_ACCESSIBLE';
    } else if (failure instanceof DmlException) {
      code = 'REJECTED';
    }
    AuraHandledException result = new AuraHandledException(code);
    result.setMessage(
      JSON.serialize(
        new Map<String, Object>{ 'code' => code, 'issues' => issues }
      )
    );
    return result;
  }
}
