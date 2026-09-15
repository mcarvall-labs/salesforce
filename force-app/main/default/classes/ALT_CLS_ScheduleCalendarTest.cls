/** @description AXF-103 — calendário puro do cronograma: âncora preservada, ajuste ao fim do mês e derivação da origem. */
@IsTest
private class ALT_CLS_ScheduleCalendarTest {
  @IsTest
  static void anchorThirtyOneClampsFebruaryAndReturnsInMarch() {
    Date origin = Date.newInstance(2026, 1, 31);

    Assert.areEqual(
      Date.newInstance(2026, 2, 28),
      ALT_CLS_ScheduleCalendar.nominalDueDate(origin, 1, 1, 31, 2),
      'Dia 31 em fevereiro vence no último dia do mês'
    );
    Assert.areEqual(
      Date.newInstance(2026, 3, 31),
      ALT_CLS_ScheduleCalendar.nominalDueDate(origin, 1, 1, 31, 3),
      'Março volta ao dia 31: a âncora não é consumida pelo ajuste'
    );
    Assert.areEqual(
      Date.newInstance(2026, 4, 30),
      ALT_CLS_ScheduleCalendar.nominalDueDate(origin, 1, 1, 31, 4),
      'Abril ajusta novamente para o fim do mês'
    );
    Assert.areEqual(
      Date.newInstance(2027, 1, 31),
      ALT_CLS_ScheduleCalendar.nominalDueDate(origin, 1, 1, 31, 13),
      'Doze meses depois a âncora continua no dia 31'
    );
  }

  @IsTest
  static void leapFebruaryClampsToTwentyNineAndMarchReturnsToThirtyOne() {
    Date origin = Date.newInstance(2028, 1, 31);

    Assert.areEqual(
      Date.newInstance(2028, 2, 29),
      ALT_CLS_ScheduleCalendar.nominalDueDate(origin, 1, 1, 31, 2)
    );
    Assert.areEqual(
      Date.newInstance(2028, 3, 31),
      ALT_CLS_ScheduleCalendar.nominalDueDate(origin, 1, 1, 31, 3)
    );
  }

  @IsTest
  static void anchorOverridesTheOriginDayWithoutDrifting() {
    // Origem no dia 10 com âncora explícita no dia 15: a âncora é a autoridade do calendário.
    Date origin = Date.newInstance(2026, 1, 10);

    Assert.areEqual(
      Date.newInstance(2026, 1, 15),
      ALT_CLS_ScheduleCalendar.nominalDueDate(origin, 1, 1, 15, 1)
    );
    Assert.areEqual(
      Date.newInstance(2026, 2, 15),
      ALT_CLS_ScheduleCalendar.nominalDueDate(origin, 1, 1, 15, 2)
    );
  }

  @IsTest
  static void firstSequenceOffsetsTheNominalDate() {
    Date origin = Date.newInstance(2026, 1, 10);

    Assert.areEqual(
      origin,
      ALT_CLS_ScheduleCalendar.nominalDueDate(origin, 1, 1, 10, 1)
    );
    Assert.areEqual(
      Date.newInstance(2026, 3, 10),
      ALT_CLS_ScheduleCalendar.nominalDueDate(origin, 1, 1, 10, 3)
    );
    // Uma definição cujo início é a sequência 85: a sequência 85 é o próprio primeiro vencimento.
    Assert.areEqual(
      origin,
      ALT_CLS_ScheduleCalendar.nominalDueDate(origin, 85, 1, 10, 85)
    );
    Assert.areEqual(
      Date.newInstance(2026, 2, 10),
      ALT_CLS_ScheduleCalendar.nominalDueDate(origin, 85, 1, 10, 86)
    );
  }

  @IsTest
  static void periodMonthsDrivesTheSpacing() {
    Date origin = Date.newInstance(2026, 1, 10);

    Assert.areEqual(
      Date.newInstance(2026, 4, 10),
      ALT_CLS_ScheduleCalendar.nominalDueDate(origin, 1, 3, 10, 2),
      'Periodicidade trimestral usa três meses por ocorrência'
    );
    Assert.areEqual(
      Date.newInstance(2027, 1, 10),
      ALT_CLS_ScheduleCalendar.nominalDueDate(origin, 1, 12, 10, 2),
      'Periodicidade anual usa doze meses por ocorrência'
    );
  }

  @IsTest
  static void noHolidayAdjustmentIsInferred() {
    // 2026-08-15 cai em fim de semana e 2026-12-25 é feriado: o calendário não inventa ajuste
    // por dia não útil nem por feriado — o vencimento fica exatamente no dia âncora.
    Assert.areEqual(
      Date.newInstance(2026, 8, 15),
      ALT_CLS_ScheduleCalendar.nominalDueDate(
        Date.newInstance(2026, 8, 15),
        1,
        1,
        15,
        1
      )
    );
    Assert.areEqual(
      Date.newInstance(2026, 12, 25),
      ALT_CLS_ScheduleCalendar.nominalDueDate(
        Date.newInstance(2026, 12, 25),
        1,
        1,
        25,
        1
      )
    );
    // Uma série ancorada no dia 25 não desloca a parcela seguinte por causa do feriado.
    Assert.areEqual(
      Date.newInstance(2027, 1, 25),
      ALT_CLS_ScheduleCalendar.nominalDueDate(
        Date.newInstance(2026, 12, 25),
        1,
        1,
        25,
        2
      )
    );
  }

  @IsTest
  static void shiftBackwardsDerivesTheDefinitionOrigin() {
    // A parcela corrente é informada no cadastro; a origem da fórmula é derivada dela.
    Date trackingDue = Date.newInstance(2026, 10, 10);

    Assert.areEqual(
      Date.newInstance(2019, 10, 10),
      ALT_CLS_ScheduleCalendar.shift(trackingDue, -84, 10),
      'Noventa e cinco meses antes da parcela 85 é o primeiro vencimento da fórmula'
    );
    Assert.areEqual(
      trackingDue,
      ALT_CLS_ScheduleCalendar.shift(Date.newInstance(2019, 10, 10), 84, 10)
    );
  }

  @IsTest
  static void monthBoundariesAreInclusive() {
    Assert.areEqual(
      Date.newInstance(2026, 2, 1),
      ALT_CLS_ScheduleCalendar.monthStart(Date.newInstance(2026, 2, 17))
    );
    Assert.areEqual(
      Date.newInstance(2026, 2, 28),
      ALT_CLS_ScheduleCalendar.monthEnd(Date.newInstance(2026, 2, 17))
    );
    Assert.areEqual(
      Date.newInstance(2028, 2, 29),
      ALT_CLS_ScheduleCalendar.monthEnd(Date.newInstance(2028, 2, 1))
    );
    Assert.areEqual(
      Date.newInstance(2027, 8, 31),
      ALT_CLS_ScheduleCalendar.monthEndShifted(
        Date.newInstance(2026, 9, 13),
        11
      ),
      'Mês corrente mais onze termina no fim do mês deslocado'
    );
  }

  @IsTest
  static void invalidInputsAreRejectedInsteadOfGuessed() {
    Date origin = Date.newInstance(2026, 1, 31);

    assertRejected(origin, 1, 1, 31, null);
    assertRejected(origin, 1, 1, 31, 0);
    assertRejected(origin, null, 1, 31, 1);
    assertRejected(origin, 1, null, 31, 1);
    assertRejected(origin, 1, 0, 31, 1);
    assertRejected(null, 1, 1, 31, 1);
    assertRejected(origin, 1, 1, 0, 1);
    assertRejected(origin, 1, 1, 32, 1);
    // Nada abaixo da sequência inicial possui data nominal.
    assertRejected(origin, 5, 1, 31, 4);

    try {
      ALT_CLS_ScheduleCalendar.monthStart(null);
      Assert.fail('Data nula deve ser rejeitada');
    } catch (ALT_CLS_ScheduleCalendar.CalendarException expected) {
      Assert.isNotNull(expected.getMessage());
    }
  }

  private static void assertRejected(
    Date origin,
    Integer firstSequence,
    Integer periodMonths,
    Integer anchorDay,
    Integer sequence
  ) {
    try {
      ALT_CLS_ScheduleCalendar.nominalDueDate(
        origin,
        firstSequence,
        periodMonths,
        anchorDay,
        sequence
      );
      Assert.fail(
        'Entradas inválidas devem ser rejeitadas, não presumidas: ' +
          origin +
          ' ' +
          firstSequence +
          ' ' +
          periodMonths +
          ' ' +
          anchorDay +
          ' ' +
          sequence
      );
    } catch (ALT_CLS_ScheduleCalendar.CalendarException expected) {
      Assert.isNotNull(expected.getMessage());
    }
  }
}
