/**
 * @description Controller exclusivo do LWC aXF_LWC_sourceLink (AXF-134). Erros sanitizados
 * como {code}; nunca stack trace, PII ou existencia de registros nao autorizados. Elegibilidade,
 * candidatos, sugestao e confirmacao vem do servico; a UI apenas apresenta e exige confirmacao.
 */
public with sharing class AXF_CLS_CTRL_SourceLink {
  public class Context {
    @AuraEnabled
    public Boolean canLink;
    @AuraEnabled
    public String policyVersion;
    @AuraEnabled
    public Integer pageSize;
    @AuraEnabled
    public List<ALT_CLS_AxonHolder.HolderView> holders;
  }

  @AuraEnabled(cacheable=true)
  public static Context getContext(String search) {
    try {
      Context result = new Context();
      result.canLink =
        FeatureManagement.checkPermission(ALT_CLS_SourceLinkService.CP_LINK) &&
        FeatureManagement.checkPermission('AXF_CanRealize');
      result.policyVersion = ALT_CLS_SourceLinkService.POLICY_VERSION;
      result.pageSize = ALT_CLS_SourceLinkService.DEFAULT_PAGE;
      result.holders = result.canLink
        ? new ALT_CLS_AxonHolder().listHolders(search)
        : new List<ALT_CLS_AxonHolder.HolderView>();
      return result;
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_SourceLinkService.SourcePage listSources(
    String request
  ) {
    try {
      return new ALT_CLS_SourceLinkService()
        .listSources(
          (ALT_CLS_SourceLinkService.SourceQuery) parse(
            request,
            ALT_CLS_SourceLinkService.SourceQuery.class
          )
        );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_SourceLinkService.CandidatePage listCandidates(
    String request
  ) {
    try {
      return new ALT_CLS_SourceLinkService()
        .listCandidates(
          (ALT_CLS_SourceLinkService.CandidateQuery) parse(
            request,
            ALT_CLS_SourceLinkService.CandidateQuery.class
          )
        );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_SourceLinkService.ConfirmResult confirm(
    String request
  ) {
    try {
      return new ALT_CLS_SourceLinkService()
        .confirm(
          (ALT_CLS_SourceLinkService.ConfirmInput) parse(
            request,
            ALT_CLS_SourceLinkService.ConfirmInput.class
          )
        );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  private static Object parse(String request, Type shape) {
    try {
      return JSON.deserializeStrict(request, shape);
    } catch (Exception failure) {
      throw new ALT_CLS_SourceLinkService.SourceLinkException('INVALID_INPUT');
    }
  }

  private static AuraHandledException safe(Exception failure) {
    String code;
    if (failure instanceof ALT_CLS_SourceLinkService.SourceLinkException) {
      code = failure.getMessage();
    } else if (
      failure instanceof QueryException ||
      failure instanceof System.SecurityException ||
      failure instanceof System.NoAccessException
    ) {
      code = 'NOT_ACCESSIBLE';
    } else {
      code = 'UNEXPECTED';
    }
    AuraHandledException result = new AuraHandledException(code);
    result.setMessage(code);
    return result;
  }
}
