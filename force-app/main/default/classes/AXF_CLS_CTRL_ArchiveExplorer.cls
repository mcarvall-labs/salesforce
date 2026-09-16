/**
 * @description Controller exclusivo do LWC aXF_LWC_archiveExplorer (AXF-95). Erros sanitizados
 * como {code}; nunca stack trace, PII ou existencia de registros nao autorizados. A UI nao
 * recalcula nada: janela quente, paginacao e fases vem dos servicos.
 */
public with sharing class AXF_CLS_CTRL_ArchiveExplorer {
  public class Context {
    @AuraEnabled
    public Boolean canRead;
    @AuraEnabled
    public Boolean canArchive;
    @AuraEnabled
    public Date hotWindowStart;
    @AuraEnabled
    public String policyVersion;
    @AuraEnabled
    public List<ALT_CLS_AxonHolder.HolderView> holders;
  }

  @AuraEnabled(cacheable=true)
  public static Context getContext(String search) {
    try {
      Context result = new Context();
      result.canRead = FeatureManagement.checkPermission(
        ALT_CLS_ArchiveReadService.CP_READ
      );
      result.canArchive = FeatureManagement.checkPermission(
        ALT_CLS_ArchiveRunService.CP_ARCHIVE
      );
      try {
        ALT_CLS_ArchivePolicy.Resolved policy = ALT_CLS_ArchivePolicy.resolve();
        result.hotWindowStart = policy.hotWindowStart;
        result.policyVersion = policy.version;
      } catch (ALT_CLS_ArchivePolicy.PolicyException blocked) {
        result.policyVersion = blocked.code;
      }
      result.holders = result.canRead || result.canArchive
        ? new ALT_CLS_AxonHolder().listHolders(search)
        : new List<ALT_CLS_AxonHolder.HolderView>();
      return result;
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_ArchiveReadService.ReadResult read(String request) {
    try {
      ALT_CLS_ArchiveReadService.ReadInput input;
      try {
        input = (ALT_CLS_ArchiveReadService.ReadInput) JSON.deserializeStrict(
          request,
          ALT_CLS_ArchiveReadService.ReadInput.class
        );
      } catch (Exception malformed) {
        throw sanitized('INVALID_INPUT');
      }
      return new ALT_CLS_ArchiveReadService().read(input);
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_ArchiveRunService.RunView startArchive(
    Id accountId,
    String family
  ) {
    try {
      return new ALT_CLS_ArchiveRunService().start(accountId, family);
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static List<ALT_CLS_ArchiveRunService.RunView> listRuns(Id accountId) {
    try {
      return new ALT_CLS_ArchiveRunService().listRuns(accountId);
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  private static AuraHandledException safe(Exception failure) {
    if (failure instanceof AuraHandledException) {
      return (AuraHandledException) failure;
    }
    String code = 'UNEXPECTED';
    if (failure instanceof ALT_CLS_ArchiveReadService.ArchiveReadException) {
      code = ((ALT_CLS_ArchiveReadService.ArchiveReadException) failure).code;
    } else if (
      failure instanceof ALT_CLS_ArchiveRunService.ArchiveRunException
    ) {
      code = ((ALT_CLS_ArchiveRunService.ArchiveRunException) failure).code;
    } else if (failure instanceof ALT_CLS_ArchivePolicy.PolicyException) {
      code = ((ALT_CLS_ArchivePolicy.PolicyException) failure).code;
    } else if (
      failure instanceof System.QueryException ||
      failure instanceof System.SecurityException ||
      failure instanceof System.NoAccessException
    ) {
      code = 'NOT_ACCESSIBLE';
    } else if (failure instanceof System.AsyncException) {
      code = 'ASYNC_UNAVAILABLE';
    }
    System.debug(LoggingLevel.ERROR, 'Archive explorer failure: ' + failure);
    return sanitized(code);
  }

  private static AuraHandledException sanitized(String code) {
    AuraHandledException result = new AuraHandledException(code);
    result.setMessage(code);
    return result;
  }
}
