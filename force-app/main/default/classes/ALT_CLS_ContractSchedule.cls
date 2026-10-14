/**
 * @description Pure schedule calculation for contracts (no SOQL, no DML): monthly recurrence,
 * fixed installments (installment and consortium, no interest) and financing tables
 * (SAC: constant amortization; PRICE: constant installment). Amounts are rounded to 2 places and
 * the last installment absorbs the rounding residue, so the amortizations always add up to
 * the financed amount.
 */
public with sharing class ALT_CLS_ContractSchedule {
  public static final String SAC = 'SAC';
  public static final String PRICE = 'PRICE';
  public static final Integer RECURRING_HORIZON_MONTHS = 12;

  public class Item {
    public Integer installmentNumber;
    public Date dueDate;
    public Decimal amount;
    // Financing only: the interest and the fixed monthly charges inside the amount.
    public Decimal interest;
    public Decimal charges;

    public Item(Integer installmentNumber, Date dueDate, Decimal amount) {
      this.installmentNumber = installmentNumber;
      this.dueDate = dueDate;
      this.amount = amount;
    }
  }

  // Month of `first` shifted by `monthOffset`; a day that does not exist becomes the last day.
  public static Date monthlyDate(Date first, Integer monthOffset, Integer day) {
    Date monthStart = first.toStartOfMonth().addMonths(monthOffset);
    Integer lastDay = Date.daysInMonth(monthStart.year(), monthStart.month());
    return monthStart.addDays(Math.min(day, lastDay) - 1);
  }

  // From the first due date up to the end date, or 12 months after `today` when open-ended.
  public static List<Item> recurring(
    Date firstDueDate,
    Integer dueDay,
    Date endDate,
    Date today,
    Decimal amount
  ) {
    Date horizon = today.addMonths(RECURRING_HORIZON_MONTHS);
    Date last = (endDate != null && endDate < horizon) ? endDate : horizon;
    Integer day = dueDay != null ? dueDay : firstDueDate.day();
    List<Item> items = new List<Item>();
    Integer offset = 0;
    Date due = monthlyDate(firstDueDate, offset, day);
    // A first due date before the due day of its own month still counts as the first item.
    while (due <= last) {
      if (due >= firstDueDate) {
        items.add(new Item(items.size() + 1, due, amount));
      }
      offset++;
      due = monthlyDate(firstDueDate, offset, day);
    }
    return items;
  }

  public static List<Item> fixedInstallments(
    Date firstDueDate,
    Integer count,
    Decimal amount
  ) {
    List<Item> items = new List<Item>();
    Integer day = firstDueDate.day();
    for (Integer i = 0; i < count; i++) {
      items.add(new Item(i + 1, monthlyDate(firstDueDate, i, day), amount));
    }
    return items;
  }

  // `monthlyRatePercent` is the rate as typed (1.5 means 1.5 % per month).
  public static List<Item> financing(
    Decimal principal,
    Decimal monthlyRatePercent,
    Integer count,
    String amortizationSystem,
    Date firstDueDate
  ) {
    return financing(
      principal,
      monthlyRatePercent,
      count,
      amortizationSystem,
      firstDueDate,
      null,
      0
    );
  }

  // `fixedPayment` (PRICE only) is the informed installment, interest plus amortization;
  // `monthlyCharges` (insurance, fees) are fixed amounts added to every installment, outside
  // the interest base.
  public static List<Item> financing(
    Decimal principal,
    Decimal monthlyRatePercent,
    Integer count,
    String amortizationSystem,
    Date firstDueDate,
    Decimal fixedPayment,
    Decimal monthlyCharges
  ) {
    Decimal rate = monthlyRatePercent / 100;
    Decimal constantPayment = amortizationSystem == PRICE
      ? (fixedPayment != null
          ? fixedPayment
          : priceInstallment(principal, rate, count))
      : null;
    Decimal constantAmortization = (principal / count)
      .setScale(2, RoundingMode.HALF_UP);
    Decimal charges = monthlyCharges == null ? 0 : monthlyCharges;
    Decimal balance = principal;
    Integer day = firstDueDate.day();
    List<Item> items = new List<Item>();
    for (Integer k = 1; k <= count; k++) {
      Decimal interest = (balance * rate).setScale(2, RoundingMode.HALF_UP);
      Decimal amortization;
      if (k == count) {
        amortization = balance;
      } else if (amortizationSystem == PRICE) {
        amortization = Math.max(
          0,
          Math.min(constantPayment - interest, balance)
        );
      } else {
        amortization = constantAmortization;
      }
      Item item = new Item(
        k,
        monthlyDate(firstDueDate, k - 1, day),
        amortization + interest + charges
      );
      item.interest = interest;
      item.charges = charges;
      items.add(item);
      balance -= amortization;
    }
    return items;
  }

  // The financed amount plus the upfront costs (fees, IOF) that are financed with it.
  public static Decimal financedPrincipal(Decimal financed, Decimal upfront) {
    return financed + (upfront == null ? 0 : upfront);
  }

  public static Decimal sum(List<Decimal> values) {
    Decimal total = 0;
    for (Decimal value : values) {
      total += value == null ? 0 : value;
    }
    return total;
  }

  // The monthly rate (percent, 4 places) at which `count` constant installments of `payment`
  // pay off `principal`; null when no rate from 0 % to 100 % does.
  public static Decimal impliedMonthlyRate(
    Decimal principal,
    Decimal payment,
    Integer count
  ) {
    if (
      principal == null ||
      payment == null ||
      count == null ||
      count < 1 ||
      payment * count < principal
    ) {
      return null;
    }
    if (payment * count == principal) {
      return 0;
    }
    Double p = principal;
    Double n = count;
    Double target = payment;
    Double low = 0;
    Double high = 1;
    if (installmentFor(p, high, n) < target) {
      return null;
    }
    for (Integer i = 0; i < 100; i++) {
      Double mid = (low + high) / 2;
      if (installmentFor(p, mid, n) < target) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return (Decimal.valueOf((low + high) / 2) * 100)
      .setScale(4, RoundingMode.HALF_UP);
  }

  private static Double installmentFor(
    Double principal,
    Double rate,
    Double n
  ) {
    return principal * rate / (1 - Math.pow(1 + rate, -n));
  }

  private static Decimal priceInstallment(
    Decimal principal,
    Decimal rate,
    Integer count
  ) {
    if (rate == 0) {
      return (principal / count).setScale(2, RoundingMode.HALF_UP);
    }
    Decimal factor = 1;
    for (Integer i = 0; i < count; i++) {
      factor = factor * (1 + rate);
    }
    return (principal *
      rate *
      factor)
      .divide(factor - 1, 10)
      .setScale(2, RoundingMode.HALF_UP);
  }
}
