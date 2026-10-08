/**
 * @description Saves the daily time entries of a service contract and keeps ONE Pending income
 * entry (AXF_OBJ_Entry__c) per contract and competence (month): amount = sum of the month's hours
 * (planned ones included) x hourly rate, in the contract currency, due date from the contract's
 * receipt rule. One time entry per contract and day: saving a day again replaces it; a day with
 * no times is removed. The daily and monthly hour limits of the contract block the save. A
 * Realized entry is never changed, and a month that ends with no hours drops its Pending entry.
 * All the rows of one call must belong to the same month.
 */
public with sharing class ALT_CLS_Timesheet {
  public static final String RT_SERVICE = 'AXF_ServiceProvision';
  public static final String NEXT_MONTH = 'NextMonth';
  // The hours of a service are always income, whatever the Direction picked on the contract.
  public static final String ENTRY_INCOME = 'Income';
  private static final Integer MS_PER_HOUR = 3600000;

  public class TimesheetException extends Exception {
  }

  public class Row {
    public Date workDate;
    public Time in1;
    public Time out1;
    public Time in2;
    public Time out2;

    public Row(Date workDate, Time in1, Time out1, Time in2, Time out2) {
      this.workDate = workDate;
      this.in1 = in1;
      this.out1 = out1;
      this.in2 = in2;
      this.out2 = out2;
    }

    public Boolean isEmpty() {
      return in1 == null && out1 == null && in2 == null && out2 == null;
    }
  }

  public class Result {
    public Decimal monthHours = 0;
    public Decimal amount = 0;
    // Null when the month has no hours and its Pending entry was dropped.
    public Id entryId;
    // True when the month's entry is already Realized: the hours were saved but the amount stays.
    public Boolean entryLocked = false;
  }

  // One calendar day of the month as the timesheet shows it.
  public class DayView {
    public Date workDate;
    public Boolean workingDay;
    public Time in1;
    public Time out1;
    public Time in2;
    public Time out2;
    public Decimal hours = 0;
  }

  public class MonthView {
    public Date competence;
    public String currencyCode;
    public Decimal hourlyRate;
    public Decimal dailyLimit;
    public Decimal monthlyLimit;
    public String holidayCalendar;
    public Time defaultIn1;
    public Time defaultOut1;
    public Time defaultIn2;
    public Time defaultOut2;
    public Decimal totalHours = 0;
    // Set by fillWorkdays: days filled, and working days left empty because they do not fit the monthly limit.
    public Integer filledDays = 0;
    public Integer skippedDays = 0;
    public List<DayView> days = new List<DayView>();
  }

  // Decimal hours of one day (two periods), rounded to 2 places like the Hours formula field.
  public static Decimal hours(Row row) {
    Long ms = period(row.in1, row.out1) + period(row.in2, row.out2);
    return (Decimal.valueOf(ms) / MS_PER_HOUR)
      .setScale(2, RoundingMode.HALF_UP);
  }

  public Result save(Id contractId, List<Row> rows) {
    AXF_OBJ_Contract__c contract = loadContract(contractId);
    Date competence = competenceOf(rows);
    checkLimits(contract, competence, rows);
    // A failure after the time entries were written must not leave them without their entry.
    Savepoint beforeSave = Database.setSavepoint();
    try {
      persist(contractId, rows);
      return syncMonthlyEntry(contract, competence);
    } catch (Exception e) {
      Database.rollback(beforeSave);
      throw e;
    }
  }

  // Every day of the month, with the saved times and whether it is a working day of the contract's calendar.
  public MonthView loadMonth(Id contractId, Integer year, Integer month) {
    AXF_OBJ_Contract__c contract = loadContract(contractId);
    Date first = firstOfMonth(year, month);
    Date last = first.addMonths(1).addDays(-1);
    MonthView view = new MonthView();
    view.competence = first;
    view.currencyCode = contract.CurrencyIsoCode;
    view.hourlyRate = contract.AXF_CTR_CUR_HourlyRate__c;
    view.dailyLimit = contract.AXF_CTR_NUM_DailyLimit__c;
    view.monthlyLimit = contract.AXF_CTR_NUM_MonthlyLimit__c;
    view.holidayCalendar = contract.AXF_CTR_PKL_HolidayCalendar__c;
    view.defaultIn1 = contract.AXF_CTR_TIM_DefaultIn1__c;
    view.defaultOut1 = contract.AXF_CTR_TIM_DefaultOut1__c;
    view.defaultIn2 = contract.AXF_CTR_TIM_DefaultIn2__c;
    view.defaultOut2 = contract.AXF_CTR_TIM_DefaultOut2__c;
    Map<Date, AXF_OBJ_TimeEntry__c> saved = new Map<Date, AXF_OBJ_TimeEntry__c>();
    for (AXF_OBJ_TimeEntry__c entry : [
      SELECT
        AXF_TME_DAT_Date__c,
        AXF_TME_TIM_In1__c,
        AXF_TME_TIM_Out1__c,
        AXF_TME_TIM_In2__c,
        AXF_TME_TIM_Out2__c,
        AXF_TME_FOR_Hours__c
      FROM AXF_OBJ_TimeEntry__c
      WHERE
        AXF_TME_MD_Contract__c = :contractId
        AND AXF_TME_FOR_Competence__c = :first
    ]) {
      saved.put(entry.AXF_TME_DAT_Date__c, entry);
    }
    Set<Date> workingDays = new Set<Date>();
    try {
      workingDays.addAll(
        new ALT_CLS_ContractCalendar()
          .workingDays(contract.AXF_CTR_PKL_HolidayCalendar__c, first, last)
      );
    } catch (ALT_CLS_ContractCalendar.CalendarException e) {
      throw new TimesheetException(e.getMessage());
    }
    for (Date day = first; day <= last; day = day.addDays(1)) {
      DayView dayView = new DayView();
      dayView.workDate = day;
      dayView.workingDay = workingDays.contains(day);
      AXF_OBJ_TimeEntry__c entry = saved.get(day);
      if (entry != null) {
        dayView.in1 = entry.AXF_TME_TIM_In1__c;
        dayView.out1 = entry.AXF_TME_TIM_Out1__c;
        dayView.in2 = entry.AXF_TME_TIM_In2__c;
        dayView.out2 = entry.AXF_TME_TIM_Out2__c;
        dayView.hours = entry.AXF_TME_FOR_Hours__c == null
          ? 0
          : entry.AXF_TME_FOR_Hours__c;
        view.totalHours += dayView.hours;
      }
      view.days.add(dayView);
    }
    return view;
  }

  // Fills the working days that have no times at all with the contract's default schedule, as many as the
  // monthly limit allows. A day with any time typed is left alone.
  public MonthView fillWorkdays(Id contractId, Integer year, Integer month) {
    AXF_OBJ_Contract__c contract = loadContract(contractId);
    if (
      contract.AXF_CTR_TIM_DefaultIn1__c == null ||
      contract.AXF_CTR_TIM_DefaultOut1__c == null
    ) {
      throw new TimesheetException('Informe o horário padrão no contrato.');
    }
    if (
      (contract.AXF_CTR_TIM_DefaultIn2__c == null) !=
      (contract.AXF_CTR_TIM_DefaultOut2__c == null)
    ) {
      throw new TimesheetException(
        'O horário padrão do 2º período está incompleto no contrato.'
      );
    }
    Row template = new Row(
      Date.today(),
      contract.AXF_CTR_TIM_DefaultIn1__c,
      contract.AXF_CTR_TIM_DefaultOut1__c,
      contract.AXF_CTR_TIM_DefaultIn2__c,
      contract.AXF_CTR_TIM_DefaultOut2__c
    );
    checkPeriods(template);
    Decimal perDay = hours(template);
    if (
      contract.AXF_CTR_NUM_DailyLimit__c != null &&
      perDay > contract.AXF_CTR_NUM_DailyLimit__c
    ) {
      throw new TimesheetException(
        'O horário padrão passa do limite diário do contrato.'
      );
    }
    MonthView current = loadMonth(contractId, year, month);
    Decimal allowance = contract.AXF_CTR_NUM_MonthlyLimit__c == null
      ? null
      : contract.AXF_CTR_NUM_MonthlyLimit__c - current.totalHours;
    List<Row> rows = new List<Row>();
    Integer skipped = 0;
    for (DayView day : current.days) {
      Boolean empty =
        day.in1 == null &&
        day.out1 == null &&
        day.in2 == null &&
        day.out2 == null;
      if (!day.workingDay || !empty) {
        continue;
      }
      if (allowance != null && perDay > allowance) {
        skipped++;
        continue;
      }
      if (allowance != null) {
        allowance -= perDay;
      }
      rows.add(
        new Row(
          day.workDate,
          template.in1,
          template.out1,
          template.in2,
          template.out2
        )
      );
    }
    if (!rows.isEmpty()) {
      save(contractId, rows);
    }
    MonthView result = loadMonth(contractId, year, month);
    result.filledDays = rows.size();
    result.skippedDays = skipped;
    return result;
  }

  private static Date firstOfMonth(Integer year, Integer month) {
    if (year == null || month == null || month < 1 || month > 12) {
      throw new TimesheetException('Mês inválido.');
    }
    return Date.newInstance(year, month, 1);
  }

  private static Long period(Time startTime, Time endTime) {
    if (startTime == null || endTime == null) {
      return 0;
    }
    return toMs(endTime) - toMs(startTime);
  }

  private static Long toMs(Time t) {
    return ((t.hour() * 60 + t.minute()) * 60 + t.second()) * 1000L +
      t.millisecond();
  }

  private static AXF_OBJ_Contract__c loadContract(Id contractId) {
    List<AXF_OBJ_Contract__c> found = [
      SELECT
        Id,
        Name,
        CurrencyIsoCode,
        RecordType.DeveloperName,
        AXF_CTR_PKL_Status__c,
        AXF_CTR_PKL_Direction__c,
        AXF_CTR_MD_Holder__c,
        AXF_CTR_LKP_Category__c,
        AXF_CTR_LKP_BankAccount__c,
        AXF_CTR_LKP_CreditCard__c,
        AXF_CTR_CUR_HourlyRate__c,
        AXF_CTR_PKL_ReceiptMonth__c,
        AXF_CTR_NUM_ReceiptDay__c,
        AXF_CTR_NUM_DailyLimit__c,
        AXF_CTR_NUM_MonthlyLimit__c,
        AXF_CTR_PKL_HolidayCalendar__c,
        AXF_CTR_TIM_DefaultIn1__c,
        AXF_CTR_TIM_DefaultOut1__c,
        AXF_CTR_TIM_DefaultIn2__c,
        AXF_CTR_TIM_DefaultOut2__c
      FROM AXF_OBJ_Contract__c
      WHERE Id = :contractId
    ];
    if (found.isEmpty()) {
      throw new TimesheetException('Contrato não encontrado.');
    }
    AXF_OBJ_Contract__c contract = found[0];
    if (contract.RecordType.DeveloperName != RT_SERVICE) {
      throw new TimesheetException(
        'O timesheet vale só para contrato de prestação de serviço.'
      );
    }
    if (contract.AXF_CTR_PKL_Status__c != 'Active') {
      throw new TimesheetException('O contrato não está ativo.');
    }
    return contract;
  }

  private static Date competenceOf(List<Row> rows) {
    if (rows == null || rows.isEmpty()) {
      throw new TimesheetException('Informe ao menos um dia.');
    }
    Date competence;
    Set<Date> seen = new Set<Date>();
    for (Row row : rows) {
      if (row == null || row.workDate == null) {
        throw new TimesheetException('Informe a data de cada dia.');
      }
      checkPeriods(row);
      if (!seen.add(row.workDate)) {
        throw new TimesheetException(
          'Há dois apontamentos para o dia ' + row.workDate.format() + '.'
        );
      }
      Date month = row.workDate.toStartOfMonth();
      if (competence != null && competence != month) {
        throw new TimesheetException('Os dias devem ser do mesmo mês.');
      }
      competence = month;
    }
    return competence;
  }

  // Each period is checked on its own, so a reversed one cannot hide behind a long other one.
  private static void checkPeriods(Row row) {
    String day = row.workDate.format();
    if (
      (row.in1 == null) != (row.out1 == null) ||
      (row.in2 == null) != (row.out2 == null)
    ) {
      throw new TimesheetException(
        'O dia ' + day + ' tem um período sem entrada ou sem saída.'
      );
    }
    if (period(row.in1, row.out1) < 0 || period(row.in2, row.out2) < 0) {
      throw new TimesheetException(
        'O dia ' + day + ' tem saída antes da entrada.'
      );
    }
    if (row.out1 != null && row.in2 != null && toMs(row.in2) < toMs(row.out1)) {
      throw new TimesheetException(
        'O dia ' + day + ' tem a entrada 2 antes da saída 1.'
      );
    }
  }

  private static void checkLimits(
    AXF_OBJ_Contract__c contract,
    Date competence,
    List<Row> rows
  ) {
    Set<Date> saved = new Set<Date>();
    Decimal monthTotal = 0;
    for (Row row : rows) {
      saved.add(row.workDate);
      Decimal day = hours(row);
      if (
        contract.AXF_CTR_NUM_DailyLimit__c != null &&
        day > contract.AXF_CTR_NUM_DailyLimit__c
      ) {
        throw new TimesheetException(
          'O dia ' +
            row.workDate.format() +
            ' passa do limite diário de ' +
            contract.AXF_CTR_NUM_DailyLimit__c +
            ' h.'
        );
      }
      monthTotal += day;
    }
    // The other days of the month, which this call does not touch, also count.
    for (AXF_OBJ_TimeEntry__c other : [
      SELECT AXF_TME_DAT_Date__c, AXF_TME_FOR_Hours__c
      FROM AXF_OBJ_TimeEntry__c
      WHERE
        AXF_TME_MD_Contract__c = :contract.Id
        AND AXF_TME_FOR_Competence__c = :competence
    ]) {
      if (!saved.contains(other.AXF_TME_DAT_Date__c)) {
        monthTotal += other.AXF_TME_FOR_Hours__c == null
          ? 0
          : other.AXF_TME_FOR_Hours__c;
      }
    }
    if (
      contract.AXF_CTR_NUM_MonthlyLimit__c != null &&
      monthTotal > contract.AXF_CTR_NUM_MonthlyLimit__c
    ) {
      throw new TimesheetException(
        'O mês passa do limite mensal de ' +
          contract.AXF_CTR_NUM_MonthlyLimit__c +
          ' h (total ' +
          monthTotal +
          ' h).'
      );
    }
  }

  private static void persist(Id contractId, List<Row> rows) {
    Set<Date> dates = new Set<Date>();
    for (Row row : rows) {
      dates.add(row.workDate);
    }
    Map<Date, AXF_OBJ_TimeEntry__c> existing = new Map<Date, AXF_OBJ_TimeEntry__c>();
    for (AXF_OBJ_TimeEntry__c entry : [
      SELECT Id, AXF_TME_DAT_Date__c
      FROM AXF_OBJ_TimeEntry__c
      WHERE
        AXF_TME_MD_Contract__c = :contractId
        AND AXF_TME_DAT_Date__c IN :dates
    ]) {
      existing.put(entry.AXF_TME_DAT_Date__c, entry);
    }
    List<AXF_OBJ_TimeEntry__c> toUpsert = new List<AXF_OBJ_TimeEntry__c>();
    List<AXF_OBJ_TimeEntry__c> toDelete = new List<AXF_OBJ_TimeEntry__c>();
    for (Row row : rows) {
      AXF_OBJ_TimeEntry__c current = existing.get(row.workDate);
      if (row.isEmpty()) {
        if (current != null) {
          toDelete.add(current);
        }
        continue;
      }
      AXF_OBJ_TimeEntry__c entry = current != null
        ? current
        : new AXF_OBJ_TimeEntry__c(
            AXF_TME_MD_Contract__c = contractId,
            AXF_TME_DAT_Date__c = row.workDate
          );
      entry.AXF_TME_TIM_In1__c = row.in1;
      entry.AXF_TME_TIM_Out1__c = row.out1;
      entry.AXF_TME_TIM_In2__c = row.in2;
      entry.AXF_TME_TIM_Out2__c = row.out2;
      toUpsert.add(entry);
    }
    try {
      upsert toUpsert;
      delete toDelete;
    } catch (DmlException e) {
      throw new TimesheetException(e.getDmlMessage(0));
    }
  }

  private Result syncMonthlyEntry(
    AXF_OBJ_Contract__c contract,
    Date competence
  ) {
    Result result = new Result();
    AggregateResult total = [
      SELECT SUM(AXF_TME_FOR_Hours__c) hours
      FROM AXF_OBJ_TimeEntry__c
      WHERE
        AXF_TME_MD_Contract__c = :contract.Id
        AND AXF_TME_FOR_Competence__c = :competence
    ];
    result.monthHours = total.get('hours') == null
      ? 0
      : (Decimal) total.get('hours');
    // Any entry of the month that is not Pending (Realized) freezes it; otherwise the Pending one is ours.
    AXF_OBJ_Entry__c entry;
    for (AXF_OBJ_Entry__c candidate : [
      SELECT Id, AXF_ENT_PKL_Status__c
      FROM AXF_OBJ_Entry__c
      WHERE
        AXF_ENT_LKP_Contract__c = :contract.Id
        AND AXF_ENT_DAT_Competence__c = :competence
      ORDER BY CreatedDate
    ]) {
      if (
        candidate.AXF_ENT_PKL_Status__c !=
        ALT_CLS_ContractGeneration.ENTRY_PENDING
      ) {
        result.entryId = candidate.Id;
        result.entryLocked = true;
        return result;
      }
      if (entry == null) {
        entry = candidate;
      }
    }
    if (result.monthHours <= 0) {
      if (entry != null) {
        try {
          delete entry;
        } catch (DmlException e) {
          throw new TimesheetException(e.getDmlMessage(0));
        }
      }
      return result;
    }
    if (contract.AXF_CTR_CUR_HourlyRate__c == null) {
      throw new TimesheetException('Informe o valor por hora do contrato.');
    }
    if (
      contract.AXF_CTR_PKL_ReceiptMonth__c == null ||
      contract.AXF_CTR_NUM_ReceiptDay__c == null
    ) {
      throw new TimesheetException(
        'Informe o mês e o dia limite de recebimento do contrato.'
      );
    }
    if (
      contract.AXF_CTR_NUM_ReceiptDay__c < 1 ||
      contract.AXF_CTR_NUM_ReceiptDay__c > 31
    ) {
      throw new TimesheetException(
        'O dia limite de recebimento deve ficar entre 1 e 31.'
      );
    }
    result.amount = (result.monthHours * contract.AXF_CTR_CUR_HourlyRate__c)
      .setScale(2, RoundingMode.HALF_UP);
    Integer shift = contract.AXF_CTR_PKL_ReceiptMonth__c == NEXT_MONTH ? 1 : 0;
    AXF_OBJ_Entry__c desired = new AXF_OBJ_Entry__c(
      Name = (contract.Name +
        ' ' +
        competence.month() +
        '/' +
        competence.year())
        .abbreviate(80),
      AXF_ENT_MD_Holder__c = contract.AXF_CTR_MD_Holder__c,
      AXF_ENT_LKP_Contract__c = contract.Id,
      AXF_ENT_PKL_Type__c = ENTRY_INCOME,
      AXF_ENT_PKL_Status__c = ALT_CLS_ContractGeneration.ENTRY_PENDING,
      AXF_ENT_CUR_Amount__c = result.amount,
      AXF_ENT_DAT_DueDate__c = ALT_CLS_ContractSchedule.monthlyDate(
        competence,
        shift,
        contract.AXF_CTR_NUM_ReceiptDay__c.intValue()
      ),
      AXF_ENT_DAT_Competence__c = competence,
      AXF_ENT_LKP_Category__c = contract.AXF_CTR_LKP_Category__c,
      AXF_ENT_LKP_BankAccount__c = contract.AXF_CTR_LKP_BankAccount__c,
      AXF_ENT_LKP_CreditCard__c = contract.AXF_CTR_LKP_CreditCard__c,
      CurrencyIsoCode = contract.CurrencyIsoCode
    );
    if (entry != null) {
      desired.Id = entry.Id;
    }
    try {
      upsert desired;
    } catch (DmlException e) {
      throw new TimesheetException(e.getDmlMessage(0));
    }
    result.entryId = desired.Id;
    return result;
  }
}
