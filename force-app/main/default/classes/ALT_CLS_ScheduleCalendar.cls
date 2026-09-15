/**
 * AXF-103 — calendário puro e determinístico do cronograma. Sem SOQL, sem DML, sem describe.
 *
 * Um cronograma tem exatamente uma autoridade de calendário: a sequência inicial, o primeiro
 * vencimento, a periodicidade e o dia âncora da definição vigente. A data nominal de uma
 * ocorrência é sempre recalculada a partir da origem — nunca iterativamente a partir da
 * ocorrência anterior — para que o ajuste de um mês curto não desloque os meses seguintes:
 * uma âncora no dia 31 cai no último dia de fevereiro e volta ao dia 31 em março. Feriado
 * nunca é inferido.
 */
public inherited sharing class ALT_CLS_ScheduleCalendar {
  public static final Integer MIN_ANCHOR_DAY = 1;
  public static final Integer MAX_ANCHOR_DAY = 31;
  /**
   * Cem anos de deslocamento: limite de sanidade, não uma regra de negócio. Um teto de 120.000
   * meses deixava uma entrada ruim levar `Date.addMonths` milhares de anos adiante, com o
   * estouro aritmético como único freio.
   */
  public static final Integer MAX_MONTH_OFFSET = 1200;

  public class CalendarException extends Exception {
  }

  /**
   * @description Data nominal (vencimento) de uma sequência absoluta do cronograma.
   * @param firstDueDate vencimento da sequência inicial da definição
   * @param firstSequence sequência absoluta de `firstDueDate`
   * @param periodMonths intervalo positivo entre ocorrências, em meses
   * @param anchorDay dia pretendido (1..31); nulo usa o dia de `firstDueDate`
   * @param sequence sequência absoluta desejada, nunca anterior a `firstSequence`
   */
  public static Date nominalDueDate(
    Date firstDueDate,
    Integer firstSequence,
    Integer periodMonths,
    Integer anchorDay,
    Integer sequence
  ) {
    require(firstDueDate != null, 'Data do primeiro vencimento é obrigatória.');
    require(
      firstSequence != null && firstSequence >= 1,
      'Sequência inicial deve ser maior ou igual a 1.'
    );
    require(
      periodMonths != null && periodMonths >= 1,
      'Periodicidade deve ser de pelo menos 1 mês.'
    );
    require(
      sequence != null && sequence >= firstSequence,
      'Sequência anterior ao início da definição não possui data nominal.'
    );
    Integer anchor = resolveAnchorDay(firstDueDate, anchorDay);
    return shift(
      firstDueDate,
      (sequence - firstSequence) * periodMonths,
      anchor
    );
  }

  /**
   * @description Dia âncora resolvido: o informado, ou o dia da data de origem.
   */
  public static Integer resolveAnchorDay(Date origin, Integer anchorDay) {
    require(origin != null, 'Data de origem é obrigatória.');
    Integer anchor = (anchorDay == null) ? origin.day() : anchorDay;
    require(
      anchor >= MIN_ANCHOR_DAY && anchor <= MAX_ANCHOR_DAY,
      'Dia âncora deve estar entre 1 e 31.'
    );
    return anchor;
  }

  /**
   * @description Desloca meses reaplicando a âncora: a âncora nunca é consumida por um ajuste
   * de fim de mês. Aceita deslocamento negativo, usado para derivar a origem a partir da
   * parcela corrente informada no cadastro.
   */
  public static Date shift(Date origin, Integer months, Integer anchorDay) {
    require(origin != null, 'Data de origem é obrigatória.');
    Integer anchor = resolveAnchorDay(origin, anchorDay);
    Integer offset = (months == null) ? 0 : months;
    require(
      Math.abs(offset) <= MAX_MONTH_OFFSET,
      'Deslocamento de meses fora do limite de sanidade.'
    );
    Date moved = (offset == 0) ? origin : origin.addMonths(offset);
    Integer lastDay = Date.daysInMonth(moved.year(), moved.month());
    return Date.newInstance(
      moved.year(),
      moved.month(),
      Math.min(anchor, lastDay)
    );
  }

  /** @description Primeiro dia do mês de calendário da data informada. */
  public static Date monthStart(Date value) {
    require(value != null, 'Data é obrigatória.');
    return Date.newInstance(value.year(), value.month(), 1);
  }

  /** @description Último dia do mês de calendário da data informada. */
  public static Date monthEnd(Date value) {
    require(value != null, 'Data é obrigatória.');
    return Date.newInstance(
      value.year(),
      value.month(),
      Date.daysInMonth(value.year(), value.month())
    );
  }

  /**
   * @description Fim do mês de calendário deslocado em `months`, usado pela janela rolante
   * (mês corrente mais onze).
   */
  public static Date monthEndShifted(Date value, Integer months) {
    require(value != null, 'Data é obrigatória.');
    Integer offset = (months == null) ? 0 : months;
    require(
      Math.abs(offset) <= MAX_MONTH_OFFSET,
      'Deslocamento de meses fora do limite de sanidade.'
    );
    Date moved = (offset == 0) ? value : value.addMonths(offset);
    return monthEnd(moved);
  }

  private static void require(Boolean condition, String message) {
    if (condition != true) {
      throw new CalendarException(message);
    }
  }
}
