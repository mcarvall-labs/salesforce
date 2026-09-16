/**
 * @description AXF-20 — reproduces AMORTIZATION-POLICY.md v1.0.0 Golden Fixtures
 * GF-04 and GF-109..GF-113. Pure, no DML.
 */
@IsTest(isParallel=true)
private class ALT_CLS_AmortizationScheduleTest {
  private static ALT_CLS_AmortizationSchedule.ScheduleInput baseInput(
    String modality,
    Integer n
  ) {
    ALT_CLS_AmortizationSchedule.ScheduleInput si = new ALT_CLS_AmortizationSchedule.ScheduleInput();
    si.modality = modality;
    si.installments = n;
    si.firstDueDate = Date.newInstance(2026, 3, 15);
    return si;
  }

  @IsTest
  static void gf109PriceBase() {
    ALT_CLS_AmortizationSchedule.ScheduleInput si = baseInput('PRICE', 4);
    si.principal = 1000.00;
    si.periodRate = 0.02;

    ALT_CLS_AmortizationSchedule.ScheduleResult r = ALT_CLS_AmortizationSchedule.generate(
      si
    );

    System.assertEquals('OK', r.outcome, r.message);
    System.assertEquals(4, r.occurrences.size());
    assertOcc(r.occurrences[0], 242.62, 20.00, 757.38, 262.62);
    assertOcc(r.occurrences[1], 247.47, 15.15, 509.91, 262.62);
    assertOcc(r.occurrences[2], 252.42, 10.20, 257.49, 262.62);
    assertOcc(r.occurrences[3], 257.49, 5.15, 0.00, 262.64);
    System.assertEquals(true, r.occurrences[3].roundingResidualApplied);
    System.assertEquals(1000.00, r.totalPrincipal);
    System.assertEquals(50.50, r.totalInterest);
    System.assertEquals('2026-03-15', r.occurrences[0].dueDate);
    System.assertEquals('2026-06-15', r.occurrences[3].dueDate);
  }

  @IsTest
  static void gf110PriceZeroRate() {
    ALT_CLS_AmortizationSchedule.ScheduleInput si = baseInput('PRICE', 3);
    si.principal = 1000.00;
    si.periodRate = 0;

    ALT_CLS_AmortizationSchedule.ScheduleResult r = ALT_CLS_AmortizationSchedule.generate(
      si
    );

    System.assertEquals(333.33, r.occurrences[0].payment);
    System.assertEquals(333.33, r.occurrences[1].payment);
    System.assertEquals(333.34, r.occurrences[2].payment);
    System.assertEquals(1000.00, r.totalPrincipal);
    System.assertEquals(0.00, r.occurrences[2].closingBalance);
  }

  @IsTest
  static void gf111SacBase() {
    ALT_CLS_AmortizationSchedule.ScheduleInput si = baseInput('SAC', 4);
    si.principal = 1200.00;
    si.periodRate = 0.01;

    ALT_CLS_AmortizationSchedule.ScheduleResult r = ALT_CLS_AmortizationSchedule.generate(
      si
    );

    assertOcc(r.occurrences[0], 300.00, 12.00, 900.00, 312.00);
    assertOcc(r.occurrences[1], 300.00, 9.00, 600.00, 309.00);
    assertOcc(r.occurrences[2], 300.00, 6.00, 300.00, 306.00);
    assertOcc(r.occurrences[3], 300.00, 3.00, 0.00, 303.00);
    System.assertEquals(1200.00, r.totalPrincipal);
  }

  @IsTest
  static void gf112SacResidual() {
    ALT_CLS_AmortizationSchedule.ScheduleInput si = baseInput('SAC', 3);
    si.principal = 1000.00;
    si.periodRate = 0;

    ALT_CLS_AmortizationSchedule.ScheduleResult r = ALT_CLS_AmortizationSchedule.generate(
      si
    );

    System.assertEquals(333.33, r.occurrences[0].principalPortion);
    System.assertEquals(333.33, r.occurrences[1].principalPortion);
    System.assertEquals(333.34, r.occurrences[2].principalPortion);
    System.assertEquals(333.34, r.occurrences[2].payment);
    System.assertEquals(0.00, r.occurrences[2].closingBalance);
    System.assertEquals(1000.00, r.totalPrincipal);
  }

  @IsTest
  static void gf113Fees() {
    ALT_CLS_AmortizationSchedule.ScheduleInput si = baseInput('INSTALLMENT', 2);
    si.principal = 1000.00;
    si.flatFeePerInstallment = 5.00;
    si.upfrontFee = 10.00;

    ALT_CLS_AmortizationSchedule.ScheduleResult r = ALT_CLS_AmortizationSchedule.generate(
      si
    );

    System.assertEquals(500.00, r.occurrences[0].principalPortion);
    System.assertEquals(15.00, r.occurrences[0].feePortion);
    System.assertEquals(515.00, r.occurrences[0].payment);
    System.assertEquals(5.00, r.occurrences[1].feePortion);
    System.assertEquals(505.00, r.occurrences[1].payment);
    System.assertEquals(1000.00, r.totalPrincipal);
    System.assertEquals(20.00, r.totalFees);
  }

  @IsTest
  static void gf04InstallmentThreeWay() {
    ALT_CLS_AmortizationSchedule.ScheduleInput si = baseInput('INSTALLMENT', 3);
    si.principal = 100.00;

    ALT_CLS_AmortizationSchedule.ScheduleResult r = ALT_CLS_AmortizationSchedule.generate(
      si
    );

    System.assertEquals(33.33, r.occurrences[0].principalPortion);
    System.assertEquals(33.33, r.occurrences[1].principalPortion);
    System.assertEquals(33.34, r.occurrences[2].principalPortion);
    System.assertEquals(true, r.occurrences[2].roundingResidualApplied);
    System.assertEquals(100.00, r.totalPrincipal);
  }

  @IsTest
  static void recurringFixedValue() {
    ALT_CLS_AmortizationSchedule.ScheduleInput si = baseInput('RECURRING', 3);
    si.fixedValue = 199.90;

    ALT_CLS_AmortizationSchedule.ScheduleResult r = ALT_CLS_AmortizationSchedule.generate(
      si
    );

    System.assertEquals('OK', r.outcome);
    System.assertEquals(199.90, r.occurrences[0].payment);
    System.assertEquals(0, r.occurrences[0].interestPortion);
    System.assertEquals(599.70, r.totalPrincipal);
  }

  @IsTest
  static void consorcioIsBlockedNotInvented() {
    ALT_CLS_AmortizationSchedule.ScheduleInput si = baseInput('CONSORCIO', 12);
    si.principal = 50000.00;

    ALT_CLS_AmortizationSchedule.ScheduleResult r = ALT_CLS_AmortizationSchedule.generate(
      si
    );

    System.assertEquals('BLOCKED', r.outcome);
    System.assert(r.occurrences.isEmpty());
    System.assert(r.message.contains('AXF-97'));
  }

  @IsTest
  static void invalidInputsAreRejected() {
    System.assertEquals(
      'INVALID',
      ALT_CLS_AmortizationSchedule.generate(baseInput('PRICE', 0)).outcome
    );

    ALT_CLS_AmortizationSchedule.ScheduleInput noRate = baseInput('SAC', 3);
    noRate.principal = 1000;
    System.assertEquals(
      'INVALID',
      ALT_CLS_AmortizationSchedule.generate(noRate).outcome
    );

    ALT_CLS_AmortizationSchedule.ScheduleInput negFee = baseInput(
      'INSTALLMENT',
      2
    );
    negFee.principal = 100;
    negFee.flatFeePerInstallment = -1;
    System.assertEquals(
      'INVALID',
      ALT_CLS_AmortizationSchedule.generate(negFee).outcome
    );
  }

  @IsTest
  static void endOfMonthDueDateClamp() {
    ALT_CLS_AmortizationSchedule.ScheduleInput si = baseInput('RECURRING', 3);
    si.firstDueDate = Date.newInstance(2026, 1, 31);
    si.fixedValue = 100;

    ALT_CLS_AmortizationSchedule.ScheduleResult r = ALT_CLS_AmortizationSchedule.generate(
      si
    );

    System.assertEquals('2026-01-31', r.occurrences[0].dueDate);
    System.assertEquals('2026-02-28', r.occurrences[1].dueDate);
    System.assertEquals('2026-03-31', r.occurrences[2].dueDate);
  }

  private static void assertOcc(
    ALT_CLS_AmortizationSchedule.Occurrence o,
    Decimal principal,
    Decimal interest,
    Decimal closing,
    Decimal payment
  ) {
    System.assertEquals(
      principal,
      o.principalPortion,
      'principal seq ' + o.sequence
    );
    System.assertEquals(
      interest,
      o.interestPortion,
      'interest seq ' + o.sequence
    );
    System.assertEquals(closing, o.closingBalance, 'closing seq ' + o.sequence);
    System.assertEquals(payment, o.payment, 'payment seq ' + o.sequence);
  }
}
