@IsTest
private class ALT_CLS_ContractCalendarTest {
  // The calendars come from the deployed settings; a dry-run validation has none yet.
  private static Boolean calendarsExist() {
    return [
        SELECT COUNT()
        FROM BusinessHours
        WHERE Name IN ('Brasil', 'Portugal')
      ] == 2;
  }

  @IsTest
  static void withoutACalendarOnlyWeekendsAreOff() {
    ALT_CLS_ContractCalendar cal = new ALT_CLS_ContractCalendar();
    System.assertEquals(
      true,
      cal.isWorkingDay(null, Date.newInstance(2026, 9, 7))
    );
    System.assertEquals(
      false,
      cal.isWorkingDay(null, Date.newInstance(2026, 9, 5))
    );
    System.assertEquals(
      false,
      cal.isWorkingDay(null, Date.newInstance(2026, 9, 6))
    );
    System.assertEquals(false, cal.isWorkingDay(null, null));
    // September 2026 has 22 Monday-to-Friday days.
    System.assertEquals(
      22,
      cal.countWorkingDays(
        null,
        Date.newInstance(2026, 9, 1),
        Date.newInstance(2026, 9, 30)
      )
    );
  }

  @IsTest
  static void anUnknownCalendarIsRejected() {
    try {
      new ALT_CLS_ContractCalendar()
        .isWorkingDay('Mars', Date.newInstance(2026, 9, 7));
      System.assert(false, 'Expected an error');
    } catch (ALT_CLS_ContractCalendar.CalendarException e) {
      System.assert(e.getMessage().contains('desconhecido'));
    }
  }

  @IsTest
  static void independenceDayIsAHolidayInBrazilAndAWorkingDayInPortugal() {
    if (!calendarsExist()) {
      return;
    }
    ALT_CLS_ContractCalendar cal = new ALT_CLS_ContractCalendar();
    Date sept7 = Date.newInstance(2026, 9, 7);
    System.assertEquals(
      false,
      cal.isWorkingDay(ALT_CLS_ContractCalendar.BRAZIL, sept7)
    );
    System.assertEquals(
      true,
      cal.isWorkingDay(ALT_CLS_ContractCalendar.PORTUGAL, sept7)
    );
  }

  @IsTest
  static void holidaysOfTheThreeYearsAreLoaded() {
    if (!calendarsExist()) {
      return;
    }
    ALT_CLS_ContractCalendar cal = new ALT_CLS_ContractCalendar();
    List<Date> brazilHolidays = new List<Date>{
      Date.newInstance(2026, 2, 16), // Carnaval
      Date.newInstance(2026, 4, 3), // Sexta-feira Santa
      Date.newInstance(2027, 11, 15),
      Date.newInstance(2028, 6, 15), // Corpus Christi
      Date.newInstance(2028, 12, 25)
    };
    for (Date d : brazilHolidays) {
      System.assertEquals(
        false,
        cal.isWorkingDay(ALT_CLS_ContractCalendar.BRAZIL, d),
        String.valueOf(d)
      );
    }
    System.assertEquals(
      false,
      cal.isWorkingDay(
        ALT_CLS_ContractCalendar.PORTUGAL,
        Date.newInstance(2026, 4, 3)
      )
    );
    System.assertEquals(
      false,
      cal.isWorkingDay(
        ALT_CLS_ContractCalendar.PORTUGAL,
        Date.newInstance(2027, 12, 8)
      )
    );
    System.assertEquals(
      false,
      cal.isWorkingDay(
        ALT_CLS_ContractCalendar.PORTUGAL,
        Date.newInstance(2028, 10, 5)
      )
    );
    // Carnaval is a Brazilian holiday only.
    System.assertEquals(
      true,
      cal.isWorkingDay(
        ALT_CLS_ContractCalendar.PORTUGAL,
        Date.newInstance(2026, 2, 16)
      )
    );
  }

  @IsTest
  static void weekendsAreNeverWorkingDaysInTheCalendars() {
    if (!calendarsExist()) {
      return;
    }
    ALT_CLS_ContractCalendar cal = new ALT_CLS_ContractCalendar();
    System.assertEquals(
      false,
      cal.isWorkingDay(
        ALT_CLS_ContractCalendar.BRAZIL,
        Date.newInstance(2026, 9, 5)
      )
    );
    System.assertEquals(
      false,
      cal.isWorkingDay(
        ALT_CLS_ContractCalendar.PORTUGAL,
        Date.newInstance(2026, 9, 6)
      )
    );
    // September 2026: 22 weekdays; Brazil loses 07/09, Portugal loses none.
    System.assertEquals(
      21,
      cal.countWorkingDays(
        ALT_CLS_ContractCalendar.BRAZIL,
        Date.newInstance(2026, 9, 1),
        Date.newInstance(2026, 9, 30)
      )
    );
    System.assertEquals(
      22,
      cal.countWorkingDays(
        ALT_CLS_ContractCalendar.PORTUGAL,
        Date.newInstance(2026, 9, 1),
        Date.newInstance(2026, 9, 30)
      )
    );
  }
}
