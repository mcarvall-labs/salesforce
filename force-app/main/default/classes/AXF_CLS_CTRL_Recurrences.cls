/**
 * @description Controller exclusivo do LWC aXF_LWC_recurrences (AXF-155). Fino: valida o JSON de
 * entrada (`deserializeStrict`), delega ao ALT_CLS_RecurrenceService, converte o resultado em DTOs
 * da tela e devolve erros sanitizados como {code}; nunca stack trace, mensagem interna ou
 * existência de registros fora do contexto autorizado.
 */
public with sharing class AXF_CLS_CTRL_Recurrences {
  public class Context {
    @AuraEnabled
    public Boolean canUse = false;
    /** Criar, editar valor e encerrar (Gestor); sem ela a tela é somente leitura. */
    @AuraEnabled
    public Boolean canManage = false;
    @AuraEnabled
    public List<Holder> holders = new List<Holder>();
  }

  public class Holder {
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String label;
  }

  public class Source {
    @AuraEnabled
    public Id bankAccountId;
    @AuraEnabled
    public Id creditCardId;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String kind;
    @AuraEnabled
    public String currencyIsoCode;
  }

  public class Recurrence {
    @AuraEnabled
    public Id scheduleId;
    @AuraEnabled
    public Id holderId;
    @AuraEnabled
    public String holderLabel;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public String direction;
    @AuraEnabled
    public String currencyIsoCode;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public Integer periodDays;
    @AuraEnabled
    public Integer periodMonths;
    @AuraEnabled
    public Date firstDueDate;
    @AuraEnabled
    public Id bankAccountId;
    @AuraEnabled
    public Id creditCardId;
    @AuraEnabled
    public String sourceKind;
    @AuraEnabled
    public String sourceLabel;
    @AuraEnabled
    public Date nextDueDate;
    @AuraEnabled
    public Date lastDueDate;
    @AuraEnabled
    public String state;
    @AuraEnabled
    public Date terminationDate;
    @AuraEnabled
    public Long version;
  }

  public class Occurrence {
    @AuraEnabled
    public Id transactionId;
    @AuraEnabled
    public Integer sequence;
    @AuraEnabled
    public Date dueDate;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public String status;
  }

  public class Detail {
    @AuraEnabled
    public Recurrence recurrence;
    @AuraEnabled
    public List<Occurrence> occurrences = new List<Occurrence>();
    @AuraEnabled
    public Boolean truncated = false;
    @AuraEnabled
    public Boolean unverified = false;
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
  }

  @AuraEnabled(cacheable=true)
  public static Context getContext() {
    try {
      ALT_CLS_RecurrenceService service = new ALT_CLS_RecurrenceService();
      Context result = new Context();
      result.canUse = true;
      result.canManage = service.canManage();
      for (ALT_CLS_RecurrenceService.HolderOption option : service.holders()) {
        Holder holder = new Holder();
        holder.accountId = option.accountId;
        holder.label = option.label;
        result.holders.add(holder);
      }
      return result;
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static List<Source> getSources(String request) {
    try {
      List<Source> result = new List<Source>();
      for (
        ALT_CLS_RecurrenceService.SourceOption option : new ALT_CLS_RecurrenceService()
          .sources(
            (ALT_CLS_RecurrenceService.SourceQuery) parse(
              request,
              ALT_CLS_RecurrenceService.SourceQuery.class
            )
          )
      ) {
        Source source = new Source();
        source.bankAccountId = option.bankAccountId;
        source.creditCardId = option.creditCardId;
        source.label = option.label;
        source.kind = option.kind;
        source.currencyIsoCode = option.currencyIsoCode;
        result.add(source);
      }
      return result;
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static List<Recurrence> listRecurrences() {
    try {
      List<Recurrence> result = new List<Recurrence>();
      for (
        ALT_CLS_RecurrenceService.RecurrenceView view : new ALT_CLS_RecurrenceService()
          .listRecurrences()
      ) {
        result.add(toRecurrence(view));
      }
      return result;
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static Detail getDetail(String request) {
    try {
      ALT_CLS_RecurrenceService.DetailView view = new ALT_CLS_RecurrenceService()
        .detail(
          (ALT_CLS_RecurrenceService.DetailQuery) parse(
            request,
            ALT_CLS_RecurrenceService.DetailQuery.class
          )
        );
      Detail result = new Detail();
      result.recurrence = toRecurrence(view.recurrence);
      result.truncated = view.truncated;
      result.unverified = view.unverified;
      for (ALT_CLS_RecurrenceService.OccurrenceView item : view.occurrences) {
        Occurrence occurrence = new Occurrence();
        occurrence.transactionId = item.transactionId;
        occurrence.sequence = item.sequence;
        occurrence.dueDate = item.dueDate;
        occurrence.amount = item.amount;
        occurrence.status = item.status;
        result.occurrences.add(occurrence);
      }
      return result;
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static Result createRecurrence(String request) {
    try {
      return toResult(
        new ALT_CLS_RecurrenceService()
          .create(
            (ALT_CLS_RecurrenceService.CreateRequest) parse(
              request,
              ALT_CLS_RecurrenceService.CreateRequest.class
            )
          )
      );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static Result editAmount(String request) {
    try {
      return toResult(
        new ALT_CLS_RecurrenceService()
          .editAmount(
            (ALT_CLS_RecurrenceService.EditRequest) parse(
              request,
              ALT_CLS_RecurrenceService.EditRequest.class
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
        new ALT_CLS_RecurrenceService()
          .terminate(
            (ALT_CLS_RecurrenceService.TerminateRequest) parse(
              request,
              ALT_CLS_RecurrenceService.TerminateRequest.class
            )
          )
      );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  private static Recurrence toRecurrence(
    ALT_CLS_RecurrenceService.RecurrenceView view
  ) {
    Recurrence result = new Recurrence();
    result.scheduleId = view.scheduleId;
    result.holderId = view.holderId;
    result.holderLabel = view.holderLabel;
    result.description = view.description;
    result.direction = view.direction;
    result.currencyIsoCode = view.currencyIsoCode;
    result.amount = view.amount;
    result.periodDays = view.periodDays;
    result.periodMonths = view.periodMonths;
    result.firstDueDate = view.firstDueDate;
    result.bankAccountId = view.bankAccountId;
    result.creditCardId = view.creditCardId;
    result.sourceKind = view.sourceKind;
    result.sourceLabel = view.sourceLabel;
    result.nextDueDate = view.nextDueDate;
    result.lastDueDate = view.lastDueDate;
    result.state = view.state;
    result.terminationDate = view.terminationDate;
    result.version = view.version;
    return result;
  }

  private static Result toResult(
    ALT_CLS_RecurrenceService.CommandResult command
  ) {
    Result result = new Result();
    result.scheduleId = command.scheduleId;
    result.replay = command.replay;
    result.changedCount = command.changedCount;
    result.protectedCount = command.protectedCount;
    return result;
  }

  private static Object parse(String request, Type shape) {
    if (String.isBlank(request)) {
      throw new ALT_CLS_RecurrenceService.RecurrenceException(
        ALT_CLS_RecurrenceService.CODE_INVALID
      );
    }
    try {
      return JSON.deserializeStrict(request, shape);
    } catch (Exception failure) {
      throw new ALT_CLS_RecurrenceService.RecurrenceException(
        ALT_CLS_RecurrenceService.CODE_INVALID
      );
    }
  }

  @TestVisible
  private static AuraHandledException safe(Exception failure) {
    String code;
    if (failure instanceof ALT_CLS_RecurrenceService.RecurrenceException) {
      code = failure.getMessage();
    } else if (
      failure instanceof QueryException ||
      failure instanceof System.SecurityException ||
      failure instanceof System.NoAccessException
    ) {
      code = ALT_CLS_RecurrenceService.CODE_NOT_ACCESSIBLE;
    } else if (failure instanceof DmlException) {
      code = ALT_CLS_RecurrenceService.CODE_REJECTED;
    } else {
      code = 'UNEXPECTED';
    }
    AuraHandledException result = new AuraHandledException(code);
    result.setMessage(code);
    return result;
  }
}
