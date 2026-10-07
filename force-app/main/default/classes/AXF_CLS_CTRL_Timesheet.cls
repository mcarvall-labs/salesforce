public with sharing class AXF_CLS_CTRL_Timesheet {
  public class DayDto {
    @AuraEnabled
    public Date workDate;
    @AuraEnabled
    public Boolean workingDay;
    @AuraEnabled
    public String in1;
    @AuraEnabled
    public String out1;
    @AuraEnabled
    public String in2;
    @AuraEnabled
    public String out2;
    @AuraEnabled
    public Decimal hours;
  }

  public class MonthDto {
    @AuraEnabled
    public Date competence;
    @AuraEnabled
    public String currencyCode;
    @AuraEnabled
    public Decimal hourlyRate;
    @AuraEnabled
    public Decimal dailyLimit;
    @AuraEnabled
    public Decimal monthlyLimit;
    @AuraEnabled
    public Decimal totalHours;
    @AuraEnabled
    public Integer filledDays;
    @AuraEnabled
    public Integer skippedDays;
    @AuraEnabled
    public List<DayDto> days = new List<DayDto>();
  }

  public class SaveDto {
    @AuraEnabled
    public Decimal dayHours;
    @AuraEnabled
    public Decimal monthHours;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public Boolean entryLocked;
  }

  @AuraEnabled
  public static MonthDto getMonth(Id contractId, Integer year, Integer month) {
    checkAccess(contractId, false);
    try {
      return toDto(new ALT_CLS_Timesheet().loadMonth(contractId, year, month));
    } catch (ALT_CLS_Timesheet.TimesheetException e) {
      throw fail(e.getMessage());
    } catch (DmlException e) {
      throw fail(e.getDmlMessage(0));
    }
  }

  // Saves one day; an empty day removes it. Times arrive as the lightning-input text (HH:mm:ss.SSS).
  @AuraEnabled
  public static SaveDto saveDay(
    Id contractId,
    Date workDate,
    String in1,
    String out1,
    String in2,
    String out2
  ) {
    checkAccess(contractId, true);
    if (workDate == null) {
      throw fail('Informe a data.');
    }
    try {
      ALT_CLS_Timesheet.Row row = new ALT_CLS_Timesheet.Row(
        workDate,
        parseTime(in1),
        parseTime(out1),
        parseTime(in2),
        parseTime(out2)
      );
      ALT_CLS_Timesheet.Result result = new ALT_CLS_Timesheet()
        .save(contractId, new List<ALT_CLS_Timesheet.Row>{ row });
      SaveDto dto = new SaveDto();
      dto.dayHours = ALT_CLS_Timesheet.hours(row);
      dto.monthHours = result.monthHours;
      dto.amount = result.amount;
      dto.entryLocked = result.entryLocked;
      return dto;
    } catch (ALT_CLS_Timesheet.TimesheetException e) {
      throw fail(e.getMessage());
    } catch (DmlException e) {
      throw fail(e.getDmlMessage(0));
    }
  }

  @AuraEnabled
  public static MonthDto fillWorkdays(
    Id contractId,
    Integer year,
    Integer month
  ) {
    checkAccess(contractId, true);
    try {
      return toDto(
        new ALT_CLS_Timesheet().fillWorkdays(contractId, year, month)
      );
    } catch (ALT_CLS_Timesheet.TimesheetException e) {
      throw fail(e.getMessage());
    } catch (DmlException e) {
      throw fail(e.getDmlMessage(0));
    }
  }

  private static void checkAccess(Id contractId, Boolean forWrite) {
    if (contractId == null) {
      throw fail('Informe o contrato.');
    }
    if (forWrite && !Schema.sObjectType.AXF_OBJ_Contract__c.isUpdateable()) {
      throw fail('Você não tem permissão para apontar horas.');
    }
    List<AXF_OBJ_Contract__c> visible = new List<AXF_OBJ_Contract__c>();
    try {
      visible = [
        SELECT Id
        FROM AXF_OBJ_Contract__c
        WHERE Id = :contractId
        WITH USER_MODE
      ];
    } catch (QueryException e) {
      // A user with no access to the object at all gets this instead of an empty list.
      visible.clear();
    }
    if (visible.isEmpty()) {
      throw fail('Contrato não encontrado.');
    }
  }

  private static AuraHandledException fail(String message) {
    AuraHandledException error = new AuraHandledException(message);
    error.setMessage(message);
    return error;
  }

  private static MonthDto toDto(ALT_CLS_Timesheet.MonthView view) {
    MonthDto dto = new MonthDto();
    dto.competence = view.competence;
    dto.currencyCode = view.currencyCode;
    dto.hourlyRate = view.hourlyRate;
    dto.dailyLimit = view.dailyLimit;
    dto.monthlyLimit = view.monthlyLimit;
    dto.totalHours = view.totalHours;
    dto.filledDays = view.filledDays;
    dto.skippedDays = view.skippedDays;
    for (ALT_CLS_Timesheet.DayView day : view.days) {
      DayDto item = new DayDto();
      item.workDate = day.workDate;
      item.workingDay = day.workingDay;
      item.in1 = formatTime(day.in1);
      item.out1 = formatTime(day.out1);
      item.in2 = formatTime(day.in2);
      item.out2 = formatTime(day.out2);
      item.hours = day.hours;
      dto.days.add(item);
    }
    return dto;
  }

  @TestVisible
  private static Time parseTime(String text) {
    if (String.isBlank(text)) {
      return null;
    }
    List<String> parts = text.trim().split(':');
    if (parts.size() < 2 || String.isBlank(parts[1])) {
      throw new ALT_CLS_Timesheet.TimesheetException(
        'Horário inválido: ' + text + '.'
      );
    }
    try {
      Integer hour = Integer.valueOf(parts[0]);
      Integer minute = Integer.valueOf(parts[1]);
      if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
        throw new ALT_CLS_Timesheet.TimesheetException(
          'Horário inválido: ' + text + '.'
        );
      }
      return Time.newInstance(hour, minute, 0, 0);
    } catch (TypeException e) {
      throw new ALT_CLS_Timesheet.TimesheetException(
        'Horário inválido: ' + text + '.'
      );
    }
  }

  @TestVisible
  private static String formatTime(Time value) {
    if (value == null) {
      return null;
    }
    return String.valueOf(value.hour()).leftPad(2, '0') +
      ':' +
      String.valueOf(value.minute()).leftPad(2, '0') +
      ':00.000';
  }
}
