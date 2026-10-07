@IsTest
private class AXF_CLS_CTRL_TimesheetTest {
  private static AXF_OBJ_Contract__c service() {
    Account holder = new Account(Name = 'Titular');
    insert holder;
    AXF_OBJ_Contract__c c = new AXF_OBJ_Contract__c(
      Name = 'Serviço',
      AXF_CTR_MD_Holder__c = holder.Id,
      RecordTypeId = Schema.SObjectType.AXF_OBJ_Contract__c.getRecordTypeInfosByDeveloperName()
        .get('AXF_ServiceProvision')
        .getRecordTypeId(),
      AXF_CTR_PKL_Direction__c = 'Income',
      AXF_CTR_PKL_Status__c = 'Active',
      AXF_CTR_CUR_HourlyRate__c = 50,
      AXF_CTR_PKL_ReceiptMonth__c = 'SameMonth',
      AXF_CTR_NUM_ReceiptDay__c = 30,
      AXF_CTR_NUM_DailyLimit__c = 8,
      AXF_CTR_NUM_MonthlyLimit__c = 100,
      AXF_CTR_TIM_DefaultIn1__c = Time.newInstance(9, 0, 0, 0),
      AXF_CTR_TIM_DefaultOut1__c = Time.newInstance(13, 0, 0, 0),
      AXF_CTR_TIM_DefaultIn2__c = Time.newInstance(14, 0, 0, 0),
      AXF_CTR_TIM_DefaultOut2__c = Time.newInstance(18, 0, 0, 0)
    );
    insert c;
    return c;
  }

  @IsTest
  static void saveDayStoresTheDayAndReturnsTheTotals() {
    AXF_OBJ_Contract__c c = service();
    AXF_CLS_CTRL_Timesheet.SaveDto saved = AXF_CLS_CTRL_Timesheet.saveDay(
      c.Id,
      Date.newInstance(2026, 9, 1),
      '09:00:00.000',
      '13:00:00.000',
      '14:00:00.000',
      '18:00:00.000'
    );
    System.assertEquals(8, saved.dayHours);
    System.assertEquals(8, saved.monthHours);
    System.assertEquals(400, saved.amount);
    AXF_CLS_CTRL_Timesheet.MonthDto month = AXF_CLS_CTRL_Timesheet.getMonth(
      c.Id,
      2026,
      9
    );
    System.assertEquals(30, month.days.size());
    System.assertEquals(8, month.totalHours);
    System.assertEquals(8, month.dailyLimit);
    System.assertEquals(100, month.monthlyLimit);
    System.assertEquals('09:00:00.000', month.days[0].in1);
    System.assertEquals('18:00:00.000', month.days[0].out2);
    System.assertEquals(null, month.days[1].in1);
    // Sunday 06/09 is not a working day, Monday 07/09 is (no calendar chosen on the contract).
    System.assertEquals(false, month.days[5].workingDay);
    System.assertEquals(true, month.days[6].workingDay);
  }

  @IsTest
  static void anEmptyDayRemovesTheEntry() {
    AXF_OBJ_Contract__c c = service();
    Date day = Date.newInstance(2026, 9, 1);
    AXF_CLS_CTRL_Timesheet.saveDay(c.Id, day, '09:00', '13:00', null, null);
    AXF_CLS_CTRL_Timesheet.SaveDto cleared = AXF_CLS_CTRL_Timesheet.saveDay(
      c.Id,
      day,
      null,
      null,
      null,
      null
    );
    System.assertEquals(0, cleared.monthHours);
    System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_TimeEntry__c]);
  }

  @IsTest
  static void fillWorkdaysFillsEmptyWorkingDaysWithTheDefaultSchedule() {
    AXF_OBJ_Contract__c c = service();
    c.AXF_CTR_NUM_MonthlyLimit__c = null;
    update c;
    AXF_CLS_CTRL_Timesheet.saveDay(
      c.Id,
      Date.newInstance(2026, 9, 1),
      '09:00',
      '10:00',
      null,
      null
    );
    AXF_CLS_CTRL_Timesheet.MonthDto month = AXF_CLS_CTRL_Timesheet.fillWorkdays(
      c.Id,
      2026,
      9
    );
    System.assertEquals(
      1,
      month.days[0].hours,
      'The day already filled is kept'
    );
    System.assertEquals(8, month.days[1].hours);
    System.assertEquals(null, month.days[5].in1, 'Sunday stays empty');
    // 1 + 21 working days x 8 h
    System.assertEquals(1 + 21 * 8, month.totalHours);
  }

  @IsTest
  static void aMonthlyLimitStopsTheFill() {
    AXF_OBJ_Contract__c c = service();
    String message;
    try {
      AXF_CLS_CTRL_Timesheet.fillWorkdays(c.Id, 2026, 9);
    } catch (AuraHandledException e) {
      message = e.getMessage();
    }
    System.assert(message.contains('limite mensal'), message);
    System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_TimeEntry__c]);
  }

  @IsTest
  static void fillWorkdaysNeedsTheDefaultSchedule() {
    AXF_OBJ_Contract__c c = service();
    c.AXF_CTR_TIM_DefaultIn1__c = null;
    update c;
    String message;
    try {
      AXF_CLS_CTRL_Timesheet.fillWorkdays(c.Id, 2026, 9);
    } catch (AuraHandledException e) {
      message = e.getMessage();
    }
    System.assert(message.contains('horário padrão'), message);
  }

  @IsTest
  static void errorsReachTheScreenWithTheirMessage() {
    AXF_OBJ_Contract__c c = service();
    List<String> messages = new List<String>();
    for (Integer i = 0; i < 5; i++) {
      try {
        if (i == 0) {
          AXF_CLS_CTRL_Timesheet.getMonth(null, 2026, 9);
        } else if (i == 1) {
          AXF_CLS_CTRL_Timesheet.getMonth(c.Id, 2026, 13);
        } else if (i == 2) {
          AXF_CLS_CTRL_Timesheet.saveDay(
            c.Id,
            Date.newInstance(2026, 9, 1),
            '09:00',
            '18:00',
            null,
            null
          );
        } else if (i == 3) {
          AXF_CLS_CTRL_Timesheet.saveDay(
            c.Id,
            Date.newInstance(2026, 9, 1),
            '25:00',
            '17:00',
            null,
            null
          );
        } else {
          AXF_CLS_CTRL_Timesheet.saveDay(
            c.Id,
            Date.newInstance(2026, 9, 1),
            'abc',
            '17:00',
            null,
            null
          );
        }
        messages.add(null);
      } catch (AuraHandledException e) {
        messages.add(e.getMessage());
      }
    }
    System.assert(messages[0].contains('contrato'), messages[0]);
    System.assert(messages[1].contains('Mês inválido'), messages[1]);
    System.assert(messages[2].contains('limite diário'), messages[2]);
    System.assert(messages[3].contains('Horário inválido'), messages[3]);
    System.assert(messages[4].contains('Horário inválido'), messages[4]);
  }

  @IsTest
  static void timeConversionRoundTrips() {
    System.assertEquals(null, AXF_CLS_CTRL_Timesheet.parseTime(' '));
    System.assertEquals(
      Time.newInstance(9, 5, 0, 0),
      AXF_CLS_CTRL_Timesheet.parseTime('09:05:00.000')
    );
    System.assertEquals(
      '09:05:00.000',
      AXF_CLS_CTRL_Timesheet.formatTime(Time.newInstance(9, 5, 0, 0))
    );
    System.assertEquals(null, AXF_CLS_CTRL_Timesheet.formatTime(null));
  }

  @IsTest
  static void aBrazilCalendarMakesIndependenceDayANonWorkingDay() {
    AXF_OBJ_Contract__c c = service();
    // Only meaningful once the Business Hours of AXF-221 are deployed.
    if ([SELECT COUNT() FROM BusinessHours WHERE Name = 'Brasil'] == 0) {
      return;
    }
    c.AXF_CTR_PKL_HolidayCalendar__c = 'Brazil';
    update c;
    AXF_CLS_CTRL_Timesheet.MonthDto month = AXF_CLS_CTRL_Timesheet.getMonth(
      c.Id,
      2026,
      9
    );
    System.assertEquals(false, month.days[6].workingDay);
  }
}
