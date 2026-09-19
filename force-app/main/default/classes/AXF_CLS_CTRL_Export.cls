/**
 * @description Controller exclusivo do LWC aXF_LWC_export (AXF-118). Expoe getContext/request/
 * read/download de ALT_CLS_ExportService como @AuraEnabled; nenhuma regra de negocio e
 * reimplementada aqui e nenhuma revalidacao de capacidade, vinculo do solicitante ou acesso ao
 * titular e contornada — o servico revalida tudo isso em toda chamada, exatamente como antes desta
 * superficie existir. Erros sanitizados como {code}; nunca stack trace, PII ou existencia de
 * registros nao autorizados (mesmo padrao de AXF_CLS_CTRL_InternalTransfer, AXF-32).
 */
public with sharing class AXF_CLS_CTRL_Export {
  public class Context {
    @AuraEnabled
    public Boolean canExport;
  }

  @AuraEnabled(cacheable=true)
  public static Context getContext() {
    try {
      Context result = new Context();
      result.canExport = FeatureManagement.checkPermission(
        ALT_CLS_ExportService.CP_EXPORT
      );
      return result;
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  /** @description Solicita (ou retoma) o export do escopo; o servico decide sync vs. lote. */
  @AuraEnabled
  public static ALT_CLS_ExportService.RunView request(
    Id accountId,
    Decimal expectedVersion
  ) {
    try {
      return new ALT_CLS_ExportService().request(accountId, expectedVersion);
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  /** @description Observa o run; nunca prepara nem revoga (somente download() faz isso). */
  @AuraEnabled
  public static ALT_CLS_ExportService.RunView read(Id runId) {
    try {
      return new ALT_CLS_ExportService().read(runId);
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static ALT_CLS_ExportService.DownloadView download(
    Id runId,
    Decimal expectedVersion
  ) {
    try {
      return new ALT_CLS_ExportService().download(runId, expectedVersion);
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  private static AuraHandledException safe(Exception failure) {
    String code;
    if (failure instanceof ALT_CLS_ExportService.ExportException) {
      code = ((ALT_CLS_ExportService.ExportException) failure).code;
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
