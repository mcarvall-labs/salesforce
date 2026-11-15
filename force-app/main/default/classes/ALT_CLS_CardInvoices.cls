/**
 * @description Invoices of a credit card and the transactions of one invoice, read with the
 * caller's CRUD/FLS and sharing. Pluggy only reports issued bills and, for an installment
 * purchase, only the current parcel, so the list also carries projected invoices (nothing is
 * stored): transactions without an invoice form the open one of their cycle, and the remaining
 * parcels of each installment series fall on the following months, up to the last parcel.
 * Real invoices come first (newest due date first), then the projected ones.
 */
public with sharing class ALT_CLS_CardInvoices {
  public class Invoice {
    public Id id;
    public String period;
    public Date dueDate;
    public Decimal totalAmount;
    public String status;
    public String currencyCode;
    public Boolean projected = false;
    public List<Line> lines;
  }

  public class Line {
    public Id id;
    public Date transactionDate;
    public String description;
    public Decimal amount;
    public Decimal amountBRL;
    public String originalCurrency;
    public String installment;
    public Boolean projected = false;
  }

  private class Series {
    Integer parcel;
    Integer total;
    String base;
    String description;
    Decimal amount = 0;
    Decimal amountBRL = 0;
    String currencyCode;
  }

  private static final Integer MAX_ROWS = 500;
  // Pluggy lists the previous bill's total as a card transaction; it is not a purchase.
  private static final String BILL_TOTAL_PREFIX = 'TOTAL DA FATURA';

  public List<Invoice> invoices(Id creditCardId) {
    List<Invoice> items = new List<Invoice>();
    for (AXF_OBJ_CreditCardInvoice__c invoice : [
      SELECT
        AXF_CCI_TXT_Period__c,
        AXF_CCI_DAT_DueDate__c,
        AXF_CCI_CUR_TotalAmount__c,
        AXF_CCI_PKL_Status__c,
        CurrencyIsoCode
      FROM AXF_OBJ_CreditCardInvoice__c
      WHERE AXF_CCI_MD_CreditCard__c = :creditCardId
      WITH USER_MODE
      ORDER BY
        AXF_CCI_DAT_DueDate__c DESC NULLS LAST,
        AXF_CCI_TXT_Period__c DESC
      LIMIT :MAX_ROWS
    ]) {
      Invoice item = new Invoice();
      item.id = invoice.Id;
      item.period = invoice.AXF_CCI_TXT_Period__c;
      item.dueDate = invoice.AXF_CCI_DAT_DueDate__c;
      item.totalAmount = invoice.AXF_CCI_CUR_TotalAmount__c;
      item.status = invoice.AXF_CCI_PKL_Status__c;
      item.currencyCode = invoice.CurrencyIsoCode;
      items.add(item);
    }
    items.addAll(projected(creditCardId, items));
    return items;
  }

  private List<Invoice> projected(Id creditCardId, List<Invoice> real) {
    Set<String> realPeriods = new Set<String>();
    for (Invoice invoice : real) {
      realPeriods.add(invoice.period);
    }
    List<AXF_OBJ_CreditCard__c> cards = [
      SELECT AXF_CC_NUM_DueDay__c
      FROM AXF_OBJ_CreditCard__c
      WHERE Id = :creditCardId
      WITH USER_MODE
    ];
    Integer dueDay = cards.isEmpty() || cards[0].AXF_CC_NUM_DueDay__c == null
      ? null
      : Integer.valueOf(cards[0].AXF_CC_NUM_DueDay__c);
    String currencyCode = real.isEmpty() ? 'BRL' : real[0].currencyCode;
    Map<String, Invoice> byPeriod = new Map<String, Invoice>();
    Map<String, Series> series = new Map<String, Series>();
    for (AXF_OBJ_CreditCardTransaction__c cardTransaction : [
      SELECT
        AXF_CCT_DAT_Date__c,
        AXF_CCT_TXT_Description__c,
        AXF_CCT_CUR_Amount__c,
        AXF_CCT_CUR_AmountBRL__c,
        AXF_CCT_TXT_CurrencyCode__c,
        AXF_CCT_TXT_Installment__c,
        AXF_CCT_LKP_Invoice__c,
        AXF_CCT_LKP_Invoice__r.AXF_CCI_TXT_Period__c
      FROM AXF_OBJ_CreditCardTransaction__c
      WHERE
        AXF_CCT_MD_CreditCard__c = :creditCardId
        AND (AXF_CCT_LKP_Invoice__c = NULL
        OR AXF_CCT_TXT_Installment__c != NULL)
      WITH USER_MODE
      ORDER BY AXF_CCT_DAT_Date__c DESC, CreatedDate DESC
      LIMIT :MAX_ROWS
    ]) {
      String description = cardTransaction.AXF_CCT_TXT_Description__c;
      Boolean orphan = cardTransaction.AXF_CCT_LKP_Invoice__c == null;
      if (
        orphan &&
        description != null &&
        description.startsWith(BILL_TOTAL_PREFIX)
      ) {
        continue;
      }
      String base = orphan
        ? cycleOf(cardTransaction.AXF_CCT_DAT_Date__c, dueDay)
        : cardTransaction.AXF_CCT_LKP_Invoice__r.AXF_CCI_TXT_Period__c;
      if (base == null) {
        continue;
      }
      Decimal amountBRL = cardTransaction.AXF_CCT_CUR_AmountBRL__c == null
        ? cardTransaction.AXF_CCT_CUR_Amount__c
        : cardTransaction.AXF_CCT_CUR_AmountBRL__c;
      if (orphan && !realPeriods.contains(base)) {
        Line line = new Line();
        line.id = cardTransaction.Id;
        line.transactionDate = cardTransaction.AXF_CCT_DAT_Date__c;
        line.description = description;
        line.amount = cardTransaction.AXF_CCT_CUR_Amount__c;
        line.amountBRL = amountBRL;
        line.originalCurrency = cardTransaction.AXF_CCT_TXT_CurrencyCode__c;
        line.installment = cardTransaction.AXF_CCT_TXT_Installment__c;
        add(byPeriod, base, dueDay, currencyCode, 'Open', line);
      }
      collect(series, cardTransaction, base, amountBRL);
    }
    for (Series item : series.values()) {
      for (Integer step = 1; step <= item.total - item.parcel; step++) {
        String period = shift(item.base, step);
        if (realPeriods.contains(period)) {
          continue;
        }
        Line line = new Line();
        line.description = item.description;
        line.amount = item.amount;
        line.amountBRL = item.amountBRL;
        line.originalCurrency = item.currencyCode;
        line.installment = (item.parcel + step) + '/' + item.total;
        line.projected = true;
        add(byPeriod, period, dueDay, currencyCode, 'Projected', line);
      }
    }
    List<String> periods = new List<String>(byPeriod.keySet());
    periods.sort();
    List<Invoice> result = new List<Invoice>();
    for (Integer i = periods.size() - 1; i >= 0; i--) {
      result.add(byPeriod.get(periods[i]));
    }
    return result;
  }

  private void add(
    Map<String, Invoice> byPeriod,
    String period,
    Integer dueDay,
    String currencyCode,
    String status,
    Line line
  ) {
    Invoice invoice = byPeriod.get(period);
    if (invoice == null) {
      invoice = new Invoice();
      invoice.period = period;
      invoice.dueDate = dueDate(period, dueDay);
      invoice.totalAmount = 0;
      invoice.currencyCode = currencyCode;
      invoice.projected = true;
      invoice.lines = new List<Line>();
      byPeriod.put(period, invoice);
    }
    if (status == 'Open') {
      invoice.status = 'Open';
    } else if (invoice.status == null) {
      invoice.status = status;
    }
    invoice.lines.add(line);
    invoice.totalAmount -= line.amountBRL == null ? 0 : line.amountBRL;
  }

  // Keeps, per purchase (description + number of parcels), the latest parcel seen; parcels at
  // the same position add up.
  private void collect(
    Map<String, Series> series,
    AXF_OBJ_CreditCardTransaction__c cardTransaction,
    String base,
    Decimal amountBRL
  ) {
    String installment = cardTransaction.AXF_CCT_TXT_Installment__c;
    if (installment == null || !installment.contains('/')) {
      return;
    }
    List<String> parts = installment.split('/');
    if (!parts[0].trim().isNumeric() || !parts[1].trim().isNumeric()) {
      return;
    }
    Integer parcel = Integer.valueOf(parts[0].trim());
    Integer total = Integer.valueOf(parts[1].trim());
    if (parcel >= total) {
      return;
    }
    String key = cardTransaction.AXF_CCT_TXT_Description__c + '|' + total;
    Series current = series.get(key);
    if (
      current == null ||
      parcel > current.parcel ||
      (parcel == current.parcel &&
      base > current.base)
    ) {
      current = new Series();
      current.parcel = parcel;
      current.total = total;
      current.base = base;
      current.description = cardTransaction.AXF_CCT_TXT_Description__c;
      current.currencyCode = cardTransaction.AXF_CCT_TXT_CurrencyCode__c;
      series.put(key, current);
    } else if (parcel != current.parcel || base != current.base) {
      return;
    }
    current.amount += cardTransaction.AXF_CCT_CUR_Amount__c == null
      ? 0
      : cardTransaction.AXF_CCT_CUR_Amount__c;
    current.amountBRL += amountBRL == null ? 0 : amountBRL;
  }

  // The bill closes before it is due, so a purchase belongs to the invoice of the next due date
  // on or after it (closing day is not reliably synced). Without a due day there is no cycle.
  @TestVisible
  private static String cycleOf(Date value, Integer dueDay) {
    if (value == null || dueDay == null) {
      return null;
    }
    Date due = dueDate(value.year(), value.month(), dueDay);
    if (value > due) {
      Date next = value.toStartOfMonth().addMonths(1);
      due = dueDate(next.year(), next.month(), dueDay);
    }
    return period(due);
  }

  private static String period(Date value) {
    return String.valueOf(value.year()) +
      '-' +
      String.valueOf(value.month()).leftPad(2, '0');
  }

  private static String shift(String period, Integer months) {
    return period(
      Date.newInstance(
          Integer.valueOf(period.substring(0, 4)),
          Integer.valueOf(period.substring(5, 7)),
          1
        )
        .addMonths(months)
    );
  }

  private static Date dueDate(String period, Integer dueDay) {
    return dueDay == null
      ? null
      : dueDate(
          Integer.valueOf(period.substring(0, 4)),
          Integer.valueOf(period.substring(5, 7)),
          dueDay
        );
  }

  private static Date dueDate(Integer year, Integer month, Integer day) {
    return Date.newInstance(
      year,
      month,
      Math.min(day, Date.daysInMonth(year, month))
    );
  }

  public List<Line> lines(Id invoiceId) {
    List<Line> items = new List<Line>();
    for (AXF_OBJ_CreditCardTransaction__c cardTransaction : [
      SELECT
        AXF_CCT_DAT_Date__c,
        AXF_CCT_TXT_Description__c,
        AXF_CCT_CUR_Amount__c,
        AXF_CCT_CUR_AmountBRL__c,
        AXF_CCT_TXT_CurrencyCode__c,
        AXF_CCT_TXT_Installment__c
      FROM AXF_OBJ_CreditCardTransaction__c
      WHERE AXF_CCT_LKP_Invoice__c = :invoiceId
      WITH USER_MODE
      ORDER BY AXF_CCT_DAT_Date__c DESC, CreatedDate DESC
      LIMIT :MAX_ROWS
    ]) {
      Line item = new Line();
      item.id = cardTransaction.Id;
      item.transactionDate = cardTransaction.AXF_CCT_DAT_Date__c;
      item.description = cardTransaction.AXF_CCT_TXT_Description__c;
      item.amount = cardTransaction.AXF_CCT_CUR_Amount__c;
      item.amountBRL = cardTransaction.AXF_CCT_CUR_AmountBRL__c;
      item.originalCurrency = cardTransaction.AXF_CCT_TXT_CurrencyCode__c;
      item.installment = cardTransaction.AXF_CCT_TXT_Installment__c;
      items.add(item);
    }
    return items;
  }
}
