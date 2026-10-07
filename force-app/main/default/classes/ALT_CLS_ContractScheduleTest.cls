@IsTest
private class ALT_CLS_ContractScheduleTest {
  @IsTest
  static void monthlyDateClampsToTheLastDayOfShortMonths() {
    Date first = Date.newInstance(2026, 1, 31);
    System.assertEquals(
      Date.newInstance(2026, 1, 31),
      ALT_CLS_ContractSchedule.monthlyDate(first, 0, 31)
    );
    System.assertEquals(
      Date.newInstance(2026, 2, 28),
      ALT_CLS_ContractSchedule.monthlyDate(first, 1, 31)
    );
    System.assertEquals(
      Date.newInstance(2028, 2, 29),
      ALT_CLS_ContractSchedule.monthlyDate(Date.newInstance(2028, 1, 31), 1, 31)
    );
    System.assertEquals(
      Date.newInstance(2026, 4, 30),
      ALT_CLS_ContractSchedule.monthlyDate(first, 3, 31)
    );
  }

  @IsTest
  static void recurringWithoutEndDateRunsTwelveMonthsAhead() {
    List<ALT_CLS_ContractSchedule.Item> items = ALT_CLS_ContractSchedule.recurring(
      Date.newInstance(2026, 10, 5),
      null,
      null,
      Date.newInstance(2026, 10, 7),
      100
    );
    // 05/10/2026 up to 05/10/2027 (the horizon is 07/10/2027).
    System.assertEquals(13, items.size());
    System.assertEquals(Date.newInstance(2026, 10, 5), items[0].dueDate);
    System.assertEquals(Date.newInstance(2027, 10, 5), items[12].dueDate);
    System.assertEquals(100, items[5].amount);
  }

  @IsTest
  static void recurringStopsAtTheEndDate() {
    List<ALT_CLS_ContractSchedule.Item> items = ALT_CLS_ContractSchedule.recurring(
      Date.newInstance(2026, 10, 10),
      10,
      Date.newInstance(2027, 1, 10),
      Date.newInstance(2026, 10, 7),
      50
    );
    System.assertEquals(4, items.size());
    System.assertEquals(Date.newInstance(2027, 1, 10), items[3].dueDate);
  }

  @IsTest
  static void recurringDueDayOverridesTheFirstDueDateDay() {
    List<ALT_CLS_ContractSchedule.Item> items = ALT_CLS_ContractSchedule.recurring(
      Date.newInstance(2026, 10, 1),
      31,
      Date.newInstance(2026, 12, 31),
      Date.newInstance(2026, 10, 7),
      10
    );
    System.assertEquals(Date.newInstance(2026, 10, 31), items[0].dueDate);
    System.assertEquals(Date.newInstance(2026, 11, 30), items[1].dueDate);
    System.assertEquals(Date.newInstance(2026, 12, 31), items[2].dueDate);
  }

  @IsTest
  static void fixedInstallmentsRepeatTheAmount() {
    List<ALT_CLS_ContractSchedule.Item> items = ALT_CLS_ContractSchedule.fixedInstallments(
      Date.newInstance(2026, 1, 31),
      3,
      250
    );
    System.assertEquals(3, items.size());
    System.assertEquals(Date.newInstance(2026, 2, 28), items[1].dueDate);
    System.assertEquals(3, items[2].installmentNumber);
    System.assertEquals(250, items[2].amount);
  }

  @IsTest
  static void priceKeepsAConstantInstallmentAndAmortizesTheWholeDebt() {
    // 12,000.00 at 1 % a month over 12 months: reference installment 1,066.19.
    List<ALT_CLS_ContractSchedule.Item> items = ALT_CLS_ContractSchedule.financing(
      12000,
      1,
      12,
      ALT_CLS_ContractSchedule.PRICE,
      Date.newInstance(2026, 11, 5)
    );
    System.assertEquals(12, items.size());
    System.assertEquals(1066.19, items[0].amount);
    System.assertEquals(1066.19, items[10].amount);
    Decimal paid = 0;
    for (ALT_CLS_ContractSchedule.Item i : items) {
      paid += i.amount;
    }
    // Total interest is about 794.28; the last installment absorbs the rounding.
    System.assert(Math.abs(paid - 12794.28) < 0.2, 'total paid ' + paid);
  }

  @IsTest
  static void priceWithZeroRateDividesEvenly() {
    List<ALT_CLS_ContractSchedule.Item> items = ALT_CLS_ContractSchedule.financing(
      1200,
      0,
      12,
      ALT_CLS_ContractSchedule.PRICE,
      Date.newInstance(2026, 11, 5)
    );
    System.assertEquals(100, items[0].amount);
    System.assertEquals(100, items[11].amount);
  }

  @IsTest
  static void sacHasConstantAmortizationAndDecreasingInstallments() {
    // 12,000.00 at 1 % a month over 12 months: amortization of 1,000.00 per month.
    List<ALT_CLS_ContractSchedule.Item> items = ALT_CLS_ContractSchedule.financing(
      12000,
      1,
      12,
      ALT_CLS_ContractSchedule.SAC,
      Date.newInstance(2026, 11, 5)
    );
    System.assertEquals(1120, items[0].amount);
    System.assertEquals(1110, items[1].amount);
    System.assertEquals(1010, items[11].amount);
    Decimal paid = 0;
    for (ALT_CLS_ContractSchedule.Item i : items) {
      paid += i.amount;
    }
    System.assertEquals(12780, paid);
  }

  @IsTest
  static void sacLastInstallmentAbsorbsTheRoundingResidue() {
    // 1,000.00 / 3 = 333.33, 333.33 and 333.34; a zero rate isolates the amortization.
    List<ALT_CLS_ContractSchedule.Item> items = ALT_CLS_ContractSchedule.financing(
      1000,
      0,
      3,
      ALT_CLS_ContractSchedule.SAC,
      Date.newInstance(2026, 11, 5)
    );
    System.assertEquals(333.33, items[0].amount);
    System.assertEquals(333.34, items[2].amount);
  }

  @IsTest
  static void recurringStartsAtTheFirstDueDateEvenWhenItIsInThePast() {
    List<ALT_CLS_ContractSchedule.Item> items = ALT_CLS_ContractSchedule.recurring(
      Date.newInstance(2026, 1, 10),
      10,
      Date.newInstance(2026, 12, 10),
      Date.newInstance(2026, 10, 7),
      50
    );
    System.assertEquals(12, items.size());
    System.assertEquals(Date.newInstance(2026, 1, 10), items[0].dueDate);
    System.assertEquals(Date.newInstance(2026, 12, 10), items[11].dueDate);
  }

  @IsTest
  static void recurringSkipsTheFirstMonthWhenTheDueDayHasAlreadyPassed() {
    List<ALT_CLS_ContractSchedule.Item> items = ALT_CLS_ContractSchedule.recurring(
      Date.newInstance(2026, 1, 20),
      10,
      Date.newInstance(2026, 4, 10),
      Date.newInstance(2026, 10, 7),
      50
    );
    System.assertEquals(Date.newInstance(2026, 2, 10), items[0].dueDate);
    System.assertEquals(3, items.size());
  }
}
