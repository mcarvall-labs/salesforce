@IsTest
private class ALT_CLS_TimesheetTest {
  private static Account holder;

  private static AXF_OBJ_Contract__c service(String currencyCode) {
    if (holder == null) {
      holder = new Account(Name = 'Titular');
      insert holder;
    }
    AXF_OBJ_Contract__c c = new AXF_OBJ_Contract__c(
      Name = 'Serviço',
      AXF_CTR_MD_Holder__c = holder.Id,
      RecordTypeId = Schema.SObjectType.AXF_OBJ_Contract__c.getRecordTypeInfosByDeveloperName()
        .get('AXF_ServiceProvision')
        .getRecordTypeId(),
      CurrencyIsoCode = currencyCode,
      AXF_CTR_PKL_Direction__c = 'Income',
      AXF_CTR_PKL_Status__c = 'Active',
      AXF_CTR_CUR_HourlyRate__c = 50,
      AXF_CTR_PKL_ReceiptMonth__c = 'SameMonth',
      AXF_CTR_NUM_ReceiptDay__c = 30
    );
    insert c;
    return c;
  }

  private static ALT_CLS_Timesheet.Row day(
    Integer d,
    Integer inH,
    Integer outH
  ) {
    return new ALT_CLS_Timesheet.Row(
      Date.newInstance(2026, 9, d),
      Time.newInstance(inH, 0, 0, 0),
      Time.newInstance(outH, 0, 0, 0),
      null,
      null
    );
  }

  private static ALT_CLS_Timesheet.Row twoPeriods(Integer d) {
    return new ALT_CLS_Timesheet.Row(
      Date.newInstance(2026, 9, d),
      Time.newInstance(9, 0, 0, 0),
      Time.newInstance(12, 30, 0, 0),
      Time.newInstance(13, 30, 0, 0),
      Time.newInstance(18, 0, 0, 0)
    );
  }

  private static List<AXF_OBJ_Entry__c> monthEntries(Id contractId) {
    Date competence = Date.newInstance(2026, 9, 1);
    return [
      SELECT
        Id,
        AXF_ENT_CUR_Amount__c,
        AXF_ENT_DAT_DueDate__c,
        AXF_ENT_PKL_Status__c,
        AXF_ENT_PKL_Type__c,
        CurrencyIsoCode
      FROM AXF_OBJ_Entry__c
      WHERE
        AXF_ENT_LKP_Contract__c = :contractId
        AND AXF_ENT_DAT_Competence__c = :competence
    ];
  }

  private static Integer timeEntryCount(Id contractId) {
    return [
      SELECT COUNT()
      FROM AXF_OBJ_TimeEntry__c
      WHERE AXF_TME_MD_Contract__c = :contractId
    ];
  }

  private static String failure(
    AXF_OBJ_Contract__c c,
    List<ALT_CLS_Timesheet.Row> rows
  ) {
    try {
      new ALT_CLS_Timesheet().save(c.Id, rows);
    } catch (ALT_CLS_Timesheet.TimesheetException e) {
      return e.getMessage();
    }
    return null;
  }

  @IsTest
  static void hoursCoverOneAndTwoPeriods() {
    System.assertEquals(8, ALT_CLS_Timesheet.hours(day(1, 9, 17)));
    System.assertEquals(8, ALT_CLS_Timesheet.hours(twoPeriods(1)));
    System.assertEquals(
      0,
      ALT_CLS_Timesheet.hours(
        new ALT_CLS_Timesheet.Row(Date.today(), null, null, null, null)
      )
    );
  }

  @IsTest
  static void savingDaysCreatesOneMonthlyEntryWithTheReceiptRule() {
    AXF_OBJ_Contract__c c = service('EUR');
    ALT_CLS_Timesheet.Result result = new ALT_CLS_Timesheet()
      .save(
        c.Id,
        new List<ALT_CLS_Timesheet.Row>{ day(1, 9, 17), twoPeriods(2) }
      );
    System.assertEquals(16, result.monthHours);
    System.assertEquals(800, result.amount);
    List<AXF_OBJ_Entry__c> entries = monthEntries(c.Id);
    System.assertEquals(1, entries.size());
    System.assertEquals(800, entries[0].AXF_ENT_CUR_Amount__c);
    System.assertEquals('Income', entries[0].AXF_ENT_PKL_Type__c);
    System.assertEquals('Pending', entries[0].AXF_ENT_PKL_Status__c);
    System.assertEquals('EUR', entries[0].CurrencyIsoCode);
    System.assertEquals(
      Date.newInstance(2026, 9, 30),
      entries[0].AXF_ENT_DAT_DueDate__c
    );
    System.assertEquals(2, timeEntryCount(c.Id));
  }

  @IsTest
  static void receiptInTheNextMonthClampsTheDay() {
    AXF_OBJ_Contract__c c = service('BRL');
    c.AXF_CTR_PKL_ReceiptMonth__c = 'NextMonth';
    c.AXF_CTR_NUM_ReceiptDay__c = 15;
    update c;
    new ALT_CLS_Timesheet()
      .save(c.Id, new List<ALT_CLS_Timesheet.Row>{ day(1, 9, 17) });
    System.assertEquals(
      Date.newInstance(2026, 10, 15),
      monthEntries(c.Id)[0].AXF_ENT_DAT_DueDate__c
    );
    c.AXF_CTR_NUM_ReceiptDay__c = 31;
    update c;
    new ALT_CLS_Timesheet()
      .save(c.Id, new List<ALT_CLS_Timesheet.Row>{ day(1, 9, 17) });
    System.assertEquals(
      Date.newInstance(2026, 10, 31),
      monthEntries(c.Id)[0].AXF_ENT_DAT_DueDate__c
    );
  }

  @IsTest
  static void savingTheSameDayAgainReplacesItAndKeepsASingleEntry() {
    AXF_OBJ_Contract__c c = service('BRL');
    new ALT_CLS_Timesheet()
      .save(c.Id, new List<ALT_CLS_Timesheet.Row>{ day(1, 9, 17) });
    ALT_CLS_Timesheet.Result result = new ALT_CLS_Timesheet()
      .save(c.Id, new List<ALT_CLS_Timesheet.Row>{ day(1, 9, 13) });
    System.assertEquals(4, result.monthHours);
    System.assertEquals(1, timeEntryCount(c.Id));
    List<AXF_OBJ_Entry__c> entries = monthEntries(c.Id);
    System.assertEquals(1, entries.size());
    System.assertEquals(200, entries[0].AXF_ENT_CUR_Amount__c);
  }

  @IsTest
  static void clearingEveryDayDropsThePendingEntry() {
    AXF_OBJ_Contract__c c = service('BRL');
    new ALT_CLS_Timesheet()
      .save(c.Id, new List<ALT_CLS_Timesheet.Row>{ day(1, 9, 17) });
    ALT_CLS_Timesheet.Result result = new ALT_CLS_Timesheet()
      .save(
        c.Id,
        new List<ALT_CLS_Timesheet.Row>{
          new ALT_CLS_Timesheet.Row(
            Date.newInstance(2026, 9, 1),
            null,
            null,
            null,
            null
          )
        }
      );
    System.assertEquals(0, result.monthHours);
    System.assertEquals(null, result.entryId);
    System.assertEquals(0, monthEntries(c.Id).size());
    System.assertEquals(0, timeEntryCount(c.Id));
  }

  @IsTest
  static void aRealizedEntryIsNeverChanged() {
    AXF_OBJ_Contract__c c = service('BRL');
    new ALT_CLS_Timesheet()
      .save(c.Id, new List<ALT_CLS_Timesheet.Row>{ day(1, 9, 17) });
    AXF_OBJ_Entry__c entry = monthEntries(c.Id)[0];
    entry.AXF_ENT_PKL_Status__c = 'Realized';
    entry.AXF_ENT_DAT_PaymentDate__c = Date.newInstance(2026, 9, 30);
    update entry;
    ALT_CLS_Timesheet.Result result = new ALT_CLS_Timesheet()
      .save(c.Id, new List<ALT_CLS_Timesheet.Row>{ day(2, 9, 17) });
    System.assertEquals(entry.Id, result.entryId);
    System.assertEquals(1, monthEntries(c.Id).size());
    System.assertEquals(400, monthEntries(c.Id)[0].AXF_ENT_CUR_Amount__c);
  }

  @IsTest
  static void theDailyLimitBlocksTheSave() {
    AXF_OBJ_Contract__c c = service('EUR');
    c.AXF_CTR_NUM_DailyLimit__c = 8;
    update c;
    System.assertEquals(
      null,
      failure(c, new List<ALT_CLS_Timesheet.Row>{ day(1, 9, 17) })
    );
    String message = failure(
      c,
      new List<ALT_CLS_Timesheet.Row>{ day(2, 8, 18) }
    );
    System.assert(message.contains('limite diário'), message);
    System.assertEquals(1, timeEntryCount(c.Id));
  }

  @IsTest
  static void theMonthlyLimitCountsTheOtherDaysOfTheMonth() {
    AXF_OBJ_Contract__c c = service('BRL');
    c.AXF_CTR_NUM_MonthlyLimit__c = 12;
    update c;
    System.assertEquals(
      null,
      failure(c, new List<ALT_CLS_Timesheet.Row>{ day(1, 9, 17) })
    );
    String message = failure(
      c,
      new List<ALT_CLS_Timesheet.Row>{ day(2, 9, 17) }
    );
    System.assert(message.contains('limite mensal'), message);
    // Editing the saved day itself does not count it twice.
    System.assertEquals(
      null,
      failure(c, new List<ALT_CLS_Timesheet.Row>{ day(1, 9, 12) })
    );
  }

  @IsTest
  static void invalidInputIsRejected() {
    AXF_OBJ_Contract__c c = service('BRL');
    System.assert(
      failure(c, new List<ALT_CLS_Timesheet.Row>()).contains('ao menos um dia')
    );
    System.assert(
      failure(
          c,
          new List<ALT_CLS_Timesheet.Row>{ day(1, 9, 17), day(1, 9, 12) }
        )
        .contains('dois apontamentos')
    );
    ALT_CLS_Timesheet.Row october = new ALT_CLS_Timesheet.Row(
      Date.newInstance(2026, 10, 1),
      Time.newInstance(9, 0, 0, 0),
      Time.newInstance(17, 0, 0, 0),
      null,
      null
    );
    System.assert(
      failure(c, new List<ALT_CLS_Timesheet.Row>{ day(1, 9, 17), october })
        .contains('mesmo mês')
    );
    // A period with the out time before the in time is stopped before anything is saved.
    System.assertNotEquals(
      null,
      failure(c, new List<ALT_CLS_Timesheet.Row>{ day(3, 17, 9) })
    );
    System.assertEquals(0, timeEntryCount(c.Id));
  }

  @IsTest
  static void onlyActiveServiceContractsAreAccepted() {
    AXF_OBJ_Contract__c closed = service('BRL');
    closed.AXF_CTR_PKL_Status__c = 'Closed';
    update closed;
    System.assert(
      failure(closed, new List<ALT_CLS_Timesheet.Row>{ day(1, 9, 17) })
        .contains('não está ativo')
    );
    AXF_OBJ_Contract__c recurring = new AXF_OBJ_Contract__c(
      Name = 'Assinatura',
      AXF_CTR_MD_Holder__c = holder.Id,
      RecordTypeId = Schema.SObjectType.AXF_OBJ_Contract__c.getRecordTypeInfosByDeveloperName()
        .get('AXF_Recurring')
        .getRecordTypeId(),
      AXF_CTR_PKL_Direction__c = 'Expense',
      AXF_CTR_PKL_Status__c = 'Active'
    );
    insert recurring;
    System.assert(
      failure(recurring, new List<ALT_CLS_Timesheet.Row>{ day(1, 9, 17) })
        .contains('prestação de serviço')
    );
  }

  @IsTest
  static void aContractWithoutRateOrReceiptRuleRollsBackTheDays() {
    AXF_OBJ_Contract__c c = service('BRL');
    c.AXF_CTR_CUR_HourlyRate__c = null;
    update c;
    System.assert(
      failure(c, new List<ALT_CLS_Timesheet.Row>{ day(1, 9, 17) })
        .contains('valor por hora')
    );
    System.assertEquals(0, timeEntryCount(c.Id));
    c.AXF_CTR_CUR_HourlyRate__c = 50;
    c.AXF_CTR_NUM_ReceiptDay__c = null;
    update c;
    System.assert(
      failure(c, new List<ALT_CLS_Timesheet.Row>{ day(1, 9, 17) })
        .contains('dia limite de recebimento')
    );
    System.assertEquals(0, timeEntryCount(c.Id));
  }

  @IsTest
  static void theTimeEntryObjectCalculatesHoursAndCompetence() {
    AXF_OBJ_Contract__c c = service('BRL');
    AXF_OBJ_TimeEntry__c entry = new AXF_OBJ_TimeEntry__c(
      AXF_TME_MD_Contract__c = c.Id,
      AXF_TME_DAT_Date__c = Date.newInstance(2026, 9, 17),
      AXF_TME_TIM_In1__c = Time.newInstance(9, 0, 0, 0),
      AXF_TME_TIM_Out1__c = Time.newInstance(12, 30, 0, 0),
      AXF_TME_TIM_In2__c = Time.newInstance(13, 30, 0, 0),
      AXF_TME_TIM_Out2__c = Time.newInstance(18, 0, 0, 0)
    );
    insert entry;
    entry = [
      SELECT AXF_TME_FOR_Hours__c, AXF_TME_FOR_Competence__c
      FROM AXF_OBJ_TimeEntry__c
      WHERE Id = :entry.Id
    ];
    System.assertEquals(8, entry.AXF_TME_FOR_Hours__c);
    System.assertEquals(
      Date.newInstance(2026, 9, 1),
      entry.AXF_TME_FOR_Competence__c
    );
  }

  @IsTest
  static void theValidationRulesOfTheTimeEntryReject() {
    AXF_OBJ_Contract__c c = service('BRL');
    AXF_OBJ_TimeEntry__c overlap = new AXF_OBJ_TimeEntry__c(
      AXF_TME_MD_Contract__c = c.Id,
      AXF_TME_DAT_Date__c = Date.newInstance(2026, 9, 17),
      AXF_TME_TIM_In1__c = Time.newInstance(9, 0, 0, 0),
      AXF_TME_TIM_Out1__c = Time.newInstance(13, 0, 0, 0),
      AXF_TME_TIM_In2__c = Time.newInstance(12, 0, 0, 0),
      AXF_TME_TIM_Out2__c = Time.newInstance(18, 0, 0, 0)
    );
    AXF_OBJ_TimeEntry__c incomplete = new AXF_OBJ_TimeEntry__c(
      AXF_TME_MD_Contract__c = c.Id,
      AXF_TME_DAT_Date__c = Date.newInstance(2026, 9, 18),
      AXF_TME_TIM_In1__c = Time.newInstance(9, 0, 0, 0)
    );
    AXF_OBJ_TimeEntry__c backwards = new AXF_OBJ_TimeEntry__c(
      AXF_TME_MD_Contract__c = c.Id,
      AXF_TME_DAT_Date__c = Date.newInstance(2026, 9, 19),
      AXF_TME_TIM_In2__c = Time.newInstance(15, 0, 0, 0),
      AXF_TME_TIM_Out2__c = Time.newInstance(10, 0, 0, 0)
    );
    for (
      Database.SaveResult r : Database.insert(
        new List<AXF_OBJ_TimeEntry__c>{ overlap, incomplete, backwards },
        false
      )
    ) {
      System.assert(!r.isSuccess());
      System.assertEquals(
        StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION,
        r.getErrors()[0].getStatusCode()
      );
    }
  }
}
