/**
 * @description Working days of a contract, from the holiday calendar chosen on it (picklist
 * "Calendário de feriados": Brazil or Portugal). Each choice maps to a native Business Hours
 * record (Brasil, Portugal; Monday to Friday, with the national holidays of 2026 to 2028), and the
 * native engine tells whether a day is a working day. A contract without calendar counts Monday
 * to Friday only.
 */
public with sharing class ALT_CLS_ContractCalendar {
  public static final String BRAZIL = 'Brazil';
  public static final String PORTUGAL = 'Portugal';

  public class CalendarException extends Exception {
  }

  private static final Map<String, String> BUSINESS_HOURS_NAMES = new Map<String, String>{
    BRAZIL => 'Brasil',
    PORTUGAL => 'Portugal'
  };

  private final Map<String, Id> idsByCalendar = new Map<String, Id>();

  public Boolean isWorkingDay(String calendar, Date day) {
    if (day == null) {
      return false;
    }
    if (String.isBlank(calendar)) {
      return !isWeekend(day);
    }
    // Noon GMT falls inside the 08:00 to 18:00 working day of both time zones.
    Datetime noon = Datetime.newInstanceGmt(
      day.year(),
      day.month(),
      day.day(),
      12,
      0,
      0
    );
    return BusinessHours.isWithin(businessHoursId(calendar), noon);
  }

  public List<Date> workingDays(String calendar, Date fromDay, Date toDay) {
    List<Date> days = new List<Date>();
    if (fromDay == null || toDay == null) {
      return days;
    }
    for (Date day = fromDay; day <= toDay; day = day.addDays(1)) {
      if (isWorkingDay(calendar, day)) {
        days.add(day);
      }
    }
    return days;
  }

  public Integer countWorkingDays(String calendar, Date fromDay, Date toDay) {
    return workingDays(calendar, fromDay, toDay).size();
  }

  private static Boolean isWeekend(Date day) {
    // 2000-01-01 was a Saturday: 0 = Saturday, 1 = Sunday.
    Integer weekday = Math.mod(
      Date.newInstance(2000, 1, 1).daysBetween(day),
      7
    );
    weekday = weekday < 0 ? weekday + 7 : weekday;
    return weekday == 0 || weekday == 1;
  }

  private Id businessHoursId(String calendar) {
    if (idsByCalendar.containsKey(calendar)) {
      return idsByCalendar.get(calendar);
    }
    String name = BUSINESS_HOURS_NAMES.get(calendar);
    if (name == null) {
      throw new CalendarException(
        'Calendário de feriados desconhecido: ' + calendar + '.'
      );
    }
    List<BusinessHours> found = [
      SELECT Id
      FROM BusinessHours
      WHERE Name = :name AND IsActive = TRUE
      ORDER BY CreatedDate
      LIMIT 1
    ];
    if (found.isEmpty()) {
      throw new CalendarException(
        'O horário comercial "' + name + '" não existe nesta org.'
      );
    }
    idsByCalendar.put(calendar, found[0].Id);
    return found[0].Id;
  }
}
