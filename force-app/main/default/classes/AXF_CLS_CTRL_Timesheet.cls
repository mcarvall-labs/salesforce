/**
 * @description Controller exclusivo do LWC aXF_LWC_timesheet (AXF-157). Fino: valida o JSON de
 * entrada (`deserializeStrict`), delega ao ALT_CLS_TimesheetService, converte o resultado nos DTOs
 * da tela e devolve erros sanitizados como {code}; nunca stack trace, mensagem interna ou
 * existência de registros fora do contexto autorizado.
 */
public with sharing class AXF_CLS_CTRL_Timesheet {
  public class Context {
    @AuraEnabled
    public Boolean canUse = false;
    @AuraEnabled
    public Boolean canRegister = false;
    @AuraEnabled
    public Boolean canSubmit = false;
  }

  public class ContractOption {
    @AuraEnabled
    public Id contractId;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Id holderId;
    @AuraEnabled
    public String holderLabel;
    @AuraEnabled
    public Decimal rate;
    @AuraEnabled
    public String currencyIsoCode;
  }

  public class EntryResult {
    @AuraEnabled
    public Id workRecordId;
    @AuraEnabled
    public Decimal hours;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Boolean created;
  }

  public class Entry {
    @AuraEnabled
    public Id workRecordId;
    @AuraEnabled
    public String recordNumber;
    @AuraEnabled
    public Date workDate;
    @AuraEnabled
    public Id contractId;
    @AuraEnabled
    public String contractLabel;
    @AuraEnabled
    public String times;
    @AuraEnabled
    public String note;
    @AuraEnabled
    public Decimal hours;
    @AuraEnabled
    public Decimal rate;
    @AuraEnabled
    public String currencyIsoCode;
    @AuraEnabled
    public Decimal totalAmount;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String billingStatus;
    @AuraEnabled
    public Decimal billedHours;
    @AuraEnabled
    public Boolean canSubmit;
    @AuraEnabled
    public Boolean canEdit;
  }

  public class EntryList {
    @AuraEnabled
    public Integer year;
    @AuraEnabled
    public Integer month;
    @AuraEnabled
    public Date fromDate;
    @AuraEnabled
    public Date toDate;
    @AuraEnabled
    public Boolean customPeriod;
    @AuraEnabled
    public Boolean truncated;
    @AuraEnabled
    public List<Entry> entries;
  }

  public class Destination {
    @AuraEnabled
    public String key;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Boolean wallet;
  }

  public class CurrencyTotal {
    @AuraEnabled
    public String currencyIsoCode;
    @AuraEnabled
    public Decimal approvedHours;
    @AuraEnabled
    public Decimal pendingHours;
    @AuraEnabled
    public Decimal approvedAmount;
    @AuraEnabled
    public Decimal pendingAmount;
  }

  public class ForecastLine {
    @AuraEnabled
    public Id contractId;
    @AuraEnabled
    public String contractLabel;
    @AuraEnabled
    public String currencyIsoCode;
    @AuraEnabled
    public Decimal approvedHours;
    @AuraEnabled
    public Decimal approvedAmount;
    @AuraEnabled
    public Decimal pendingHours;
    @AuraEnabled
    public Decimal pendingAmount;
  }

  public class ForecastGroup {
    @AuraEnabled
    public Destination destination;
    @AuraEnabled
    public List<ForecastLine> lines;
    @AuraEnabled
    public List<CurrencyTotal> totals;
  }

  public class Forecast {
    @AuraEnabled
    public Integer year;
    @AuraEnabled
    public Integer month;
    @AuraEnabled
    public List<Destination> destinations;
    @AuraEnabled
    public List<ForecastGroup> groups;
    @AuraEnabled
    public List<CurrencyTotal> totals;
  }

  @AuraEnabled(cacheable=true)
  public static Context getContext() {
    try {
      ALT_CLS_TimesheetService service = new ALT_CLS_TimesheetService();
      Context result = new Context();
      result.canUse = true;
      result.canRegister = service.canRegister();
      result.canSubmit = service.canSubmit();
      return result;
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static List<ContractOption> listContracts() {
    try {
      return (List<ContractOption>) convert(
        new ALT_CLS_TimesheetService().contracts(),
        List<ContractOption>.class
      );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static EntryResult saveEntry(String request) {
    try {
      return (EntryResult) convert(
        new ALT_CLS_TimesheetService()
          .register(
            (ALT_CLS_TimesheetService.EntryRequest) parse(
              request,
              ALT_CLS_TimesheetService.EntryRequest.class
            )
          ),
        EntryResult.class
      );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static EntryResult submitEntry(String request) {
    try {
      return (EntryResult) convert(
        new ALT_CLS_TimesheetService()
          .submit(
            (ALT_CLS_TimesheetService.SubmitRequest) parse(
              request,
              ALT_CLS_TimesheetService.SubmitRequest.class
            )
          ),
        EntryResult.class
      );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static EntryList listEntries(String request) {
    try {
      return (EntryList) convert(
        new ALT_CLS_TimesheetService()
          .entries(
            (ALT_CLS_TimesheetService.ListQuery) parse(
              request,
              ALT_CLS_TimesheetService.ListQuery.class
            )
          ),
        EntryList.class
      );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  @AuraEnabled
  public static Forecast getForecast(String request) {
    try {
      return (Forecast) convert(
        new ALT_CLS_TimesheetService()
          .forecast(
            (ALT_CLS_TimesheetService.ForecastQuery) parse(
              request,
              ALT_CLS_TimesheetService.ForecastQuery.class
            )
          ),
        Forecast.class
      );
    } catch (Exception failure) {
      throw safe(failure);
    }
  }

  /** Service views and screen DTOs share their shape field by field. */
  private static Object convert(Object view, Type shape) {
    return JSON.deserialize(JSON.serialize(view), shape);
  }

  private static Object parse(String request, Type shape) {
    if (String.isBlank(request)) {
      throw new ALT_CLS_TimesheetService.TimesheetException(
        ALT_CLS_TimesheetService.CODE_INVALID_INPUT
      );
    }
    try {
      return JSON.deserializeStrict(request, shape);
    } catch (Exception failure) {
      throw new ALT_CLS_TimesheetService.TimesheetException(
        ALT_CLS_TimesheetService.CODE_INVALID_INPUT
      );
    }
  }

  @TestVisible
  private static AuraHandledException safe(Exception failure) {
    String code;
    if (failure instanceof ALT_CLS_TimesheetService.TimesheetException) {
      code = failure.getMessage();
    } else if (
      failure instanceof QueryException ||
      failure instanceof System.SecurityException ||
      failure instanceof System.NoAccessException
    ) {
      code = ALT_CLS_TimesheetService.CODE_NOT_ACCESSIBLE;
    } else if (failure instanceof DmlException) {
      code = 'REJECTED';
    } else {
      code = 'UNEXPECTED';
    }
    AuraHandledException result = new AuraHandledException(code);
    result.setMessage(code);
    return result;
  }
}
