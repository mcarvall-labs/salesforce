/**
 * @description Controller exclusivo do LWC aXF_LWC_financings (AXF-156). Fino: valida o JSON de
 * entrada (`deserializeStrict`), delega ao ALT_CLS_FinancingService, converte o resultado em DTOs
 * da tela e devolve erros sanitizados como {code}; nunca stack trace, mensagem interna ou
 * existência de registros fora do contexto autorizado.
 */
public with sharing class AXF_CLS_CTRL_Financings {
  public class Context {
    @AuraEnabled
    public Boolean canUse = false;
    /** Editar valor, encerrar e quitar (Gestor); sem ela a tela é somente leitura. */
    @AuraEnabled
    public Boolean canManage = false;
  }

  public class Financing {
    @AuraEnabled
    public Id scheduleId;
    @AuraEnabled
    public String legacyKey;
    @AuraEnabled
    public Boolean legacy;
    @AuraEnabled
    public Id holderId;
    @AuraEnabled
    public String holderLabel;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public String method;
    @AuraEnabled
    public String direction;
    @AuraEnabled
    public String currencyIsoCode;
    @AuraEnabled
    public Decimal principal;
    @AuraEnabled
    public Integer totalInstallments;
    @AuraEnabled
    public Integer paidCount;
    @AuraEnabled
    public Date nextDueDate;
    @AuraEnabled
    public Decimal nextAmount;
    @AuraEnabled
    public Decimal outstandingBalance;
    @AuraEnabled
    public String state;
    @AuraEnabled
    public Date terminationDate;
    @AuraEnabled
    public Date lastDueDate;
    @AuraEnabled
    public Long version;
    @AuraEnabled
    public Id settlementTransactionId;
    @AuraEnabled
    public Boolean canEdit;
    @AuraEnabled
    public Boolean canChange;
    @AuraEnabled
    public Boolean unverified;
  }

  public class Installment {
    @AuraEnabled
    public Id transactionId;
    @AuraEnabled
    public Integer sequence;
    @AuraEnabled
    public Date dueDate;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public Decimal principalPortion;
    @AuraEnabled
    public Decimal interestPortion;
    @AuraEnabled
    public Decimal closingBalance;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Boolean projected;
  }

  public class Detail {
    @AuraEnabled
    public Financing financing;
    @AuraEnabled
    public List<Installment> installments = new List<Installment>();
    @AuraEnabled
    public Boolean truncated = false;
    @AuraEnabled
    public Boolean unverified = false;
  }

  public class Preview {
    @AuraEnabled
    public Id scheduleId;
    @AuraEnabled
    public Decimal suggestedAmount;
    @AuraEnabled
    public Date minDate;
    @AuraEnabled
    public Date maxDate;
    @AuraEnabled
    public Date settlementDate;
    @AuraEnabled
    public String currencyIsoCode;
    @AuraEnabled
    public Long version;
  }

  public class Result {
    @AuraEnabled
    public Id scheduleId;
    @AuraEnabled
    public Boolean replay = false;
    @AuraEnabled
    public Integer changedCount = 0;
    @AuraEnabled
    public Integer protectedCount = 0;
    @AuraEnabled
    public Id settlementTransactionId;
  }

  @AuraEnabled(cacheable=true)
  public static Context getContext() {
    try {
      Context result = new Context();
      result.canUse = true;
      result.canManage = new ALT_CLS_FinancingService().canManage();
      return result;
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static List<Financing> listFinancings() {
    try {
      return (List<Financing>) convert(
        new ALT_CLS_FinancingService().listFinancings(),
        List<Financing>.class
      );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static Detail getDetail(String request) {
    try {
      return (Detail) convert(
        new ALT_CLS_FinancingService()
          .detail(
            (ALT_CLS_FinancingService.DetailQuery) parse(
              request,
              ALT_CLS_FinancingService.DetailQuery.class
            )
          ),
        Detail.class
      );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static Preview previewSettlement(String request) {
    try {
      return (Preview) convert(
        new ALT_CLS_FinancingService()
          .settlementPreview(
            (ALT_CLS_FinancingService.SettlementQuery) parse(
              request,
              ALT_CLS_FinancingService.SettlementQuery.class
            )
          ),
        Preview.class
      );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static Result editAmount(String request) {
    try {
      return toResult(
        new ALT_CLS_FinancingService()
          .editAmount(
            (ALT_CLS_FinancingService.EditRequest) parse(
              request,
              ALT_CLS_FinancingService.EditRequest.class
            )
          )
      );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static Result terminate(String request) {
    try {
      return toResult(
        new ALT_CLS_FinancingService()
          .terminate(
            (ALT_CLS_FinancingService.TerminateRequest) parse(
              request,
              ALT_CLS_FinancingService.TerminateRequest.class
            )
          )
      );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static Result settle(String request) {
    try {
      return toResult(
        new ALT_CLS_FinancingService()
          .settle(
            (ALT_CLS_FinancingService.SettleRequest) parse(
              request,
              ALT_CLS_FinancingService.SettleRequest.class
            )
          )
      );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  private static Result toResult(
    ALT_CLS_FinancingService.CommandResult command
  ) {
    return (Result) convert(command, Result.class);
  }

  /** Views and screen DTOs share field names: the conversion is a typed copy. */
  private static Object convert(Object view, Type shape) {
    return JSON.deserialize(JSON.serialize(view), shape);
  }

  private static Object parse(String request, Type shape) {
    if (String.isBlank(request)) {
      throw new ALT_CLS_FinancingService.FinancingException(
        ALT_CLS_FinancingService.CODE_INVALID
      );
    }
    try {
      return JSON.deserializeStrict(request, shape);
    } catch (Exception failure) {
      throw new ALT_CLS_FinancingService.FinancingException(
        ALT_CLS_FinancingService.CODE_INVALID
      );
    }
  }

  @TestVisible
  private static AuraHandledException safe(Exception failure) {
    String code;
    if (failure instanceof ALT_CLS_FinancingService.FinancingException) {
      code = failure.getMessage();
    } else if (
      failure instanceof QueryException ||
      failure instanceof System.SecurityException ||
      failure instanceof System.NoAccessException
    ) {
      code = ALT_CLS_FinancingService.CODE_NOT_ACCESSIBLE;
    } else if (failure instanceof DmlException) {
      code = ALT_CLS_FinancingService.CODE_REJECTED;
    } else {
      code = 'UNEXPECTED';
    }
    AuraHandledException result = new AuraHandledException(code);
    result.setMessage(code);
    return result;
  }
}
