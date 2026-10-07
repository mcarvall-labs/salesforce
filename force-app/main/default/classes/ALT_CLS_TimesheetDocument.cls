/**
 * @description Data and files of the two monthly documents of a service contract: the timesheet PDF
 * (all service contracts; English model with values for foreign currency, Portuguese model with
 * hours only for BRL) and the invoice PDF (foreign currency only; BRL uses the invoice issued
 * outside the system). The PDF is rendered from a Visualforce page and saved as a File on the
 * month's entry; generating again adds a new version of the same File. The invoice number is the
 * competence as YYYYMM and is also written on the entry.
 */
public with sharing class ALT_CLS_TimesheetDocument {
  public static final String BRL = 'BRL';
  private static final List<String> MONTHS_PT = new List<String>{
    'jan',
    'fev',
    'mar',
    'abr',
    'mai',
    'jun',
    'jul',
    'ago',
    'set',
    'out',
    'nov',
    'dez'
  };
  private static final Map<String, String> CURRENCY_SYMBOLS = new Map<String, String>{
    'EUR' => '€',
    'USD' => 'US$',
    'GBP' => '£'
  };

  public class DocumentException extends Exception {
  }

  public class Line {
    public String workDate { get; set; }
    public String in1 { get; set; }
    public String out1 { get; set; }
    public String in2 { get; set; }
    public String out2 { get; set; }
    public String hours { get; set; }
  }

  public class TimesheetView {
    public Boolean english { get; set; }
    public String providerName { get; set; }
    public String periodStart { get; set; }
    public String periodEnd { get; set; }
    public String monthLabel { get; set; }
    public String totalHours { get; set; }
    public String hourlyRate { get; set; }
    public String totalValue { get; set; }
    public String maxHours { get; set; }
    public String missingHours { get; set; }
    public Boolean hasMaxHours { get; set; }
    public List<Line> lines { get; set; }
  }

  public class InvoiceView {
    public String issuerName { get; set; }
    public String issuerTaxId { get; set; }
    public String issuerAddress { get; set; }
    public String invoiceNumber { get; set; }
    public String billToName { get; set; }
    public String billToTaxId { get; set; }
    public String billToAddress { get; set; }
    public String invoiceDate { get; set; }
    public String terms { get; set; }
    public String dueDate { get; set; }
    public String description { get; set; }
    public String quantity { get; set; }
    public String rate { get; set; }
    public String amount { get; set; }
    public String paymentInformation { get; set; }
    public String zero { get; set; }
  }

  public class SavedFile {
    public Id documentId;
    public String title;
    public Boolean isNewVersion;
  }

  // ---------- formatting ----------

  // 4.928,00 €
  public static String money(Decimal value, String currencyCode) {
    Decimal rounded = (value == null ? 0 : value)
      .setScale(2, RoundingMode.HALF_UP);
    String[] parts = String.valueOf(Math.abs(rounded)).split('\\.');
    String whole = parts[0];
    String grouped = '';
    while (whole.length() > 3) {
      grouped = '.' + whole.substring(whole.length() - 3) + grouped;
      whole = whole.substring(0, whole.length() - 3);
    }
    String cents = parts.size() > 1 ? parts[1].rightPad(2, '0') : '00';
    String symbol = CURRENCY_SYMBOLS.containsKey(currencyCode)
      ? CURRENCY_SYMBOLS.get(currencyCode)
      : currencyCode;
    return (rounded < 0 ? '-' : '') +
      whole +
      grouped +
      ',' +
      cents +
      ' ' +
      symbol;
  }

  // 11 set 2026
  public static String shortDate(Date value) {
    return value == null
      ? ''
      : String.valueOf(value.day()).leftPad(2, '0') +
        ' ' +
        MONTHS_PT[value.month() - 1] +
        ' ' +
        value.year();
  }

  // 09/2026
  public static String periodDate(Date value) {
    return String.valueOf(value.day()).leftPad(2, '0') +
      '/' +
      String.valueOf(value.month()).leftPad(2, '0') +
      '/' +
      value.year();
  }

  // 9:30 AM
  public static String amPm(Time value) {
    if (value == null) {
      return '';
    }
    Integer hour = Math.mod(value.hour(), 12) == 0
      ? 12
      : Math.mod(value.hour(), 12);
    return hour +
      ':' +
      String.valueOf(value.minute()).leftPad(2, '0') +
      (value.hour() < 12 ? ' AM' : ' PM');
  }

  // 9:30 (h:mm)
  public static String hhmm(Time value) {
    return value == null
      ? ''
      : value.hour() + ':' + String.valueOf(value.minute()).leftPad(2, '0');
  }

  // 8.5 -> 8:30
  public static String hoursAsHhmm(Decimal value) {
    Integer minutes = ((value == null ? 0 : value) * 60)
      .setScale(0, RoundingMode.HALF_UP)
      .intValue();
    return Math.abs(minutes) / 60 +
      ':' +
      String.valueOf(Math.mod(Math.abs(minutes), 60)).leftPad(2, '0');
  }

  // 8,50
  public static String decimalHours(Decimal value) {
    String[] parts = String.valueOf(
        (value == null ? 0 : value).setScale(2, RoundingMode.HALF_UP)
      )
      .split('\\.');
    return parts[0] +
      ',' +
      (parts.size() > 1 ? parts[1] : '0').rightPad(2, '0');
  }

  public static String invoiceNumber(Date competence) {
    return String.valueOf(competence.year()) +
      String.valueOf(competence.month()).leftPad(2, '0');
  }

  // ---------- views ----------

  public TimesheetView timesheetView(
    Id contractId,
    Integer year,
    Integer month
  ) {
    AXF_OBJ_Contract__c contract = loadContract(contractId);
    Date first = Date.newInstance(year, month, 1);
    Date last = first.addMonths(1).addDays(-1);
    Date periodStart = first;
    if (
      contract.AXF_CTR_DAT_ActivityStart__c != null &&
      contract.AXF_CTR_DAT_ActivityStart__c > first &&
      contract.AXF_CTR_DAT_ActivityStart__c <= last
    ) {
      periodStart = contract.AXF_CTR_DAT_ActivityStart__c;
    }
    ALT_CLS_Timesheet.MonthView monthView = new ALT_CLS_Timesheet()
      .loadMonth(contractId, year, month);
    Boolean english = contract.CurrencyIsoCode != BRL;
    TimesheetView view = new TimesheetView();
    view.english = english;
    view.providerName = contract.AXF_CTR_MD_Holder__r.Name;
    view.periodStart = periodDate(periodStart);
    view.periodEnd = periodDate(last);
    view.monthLabel = invoiceNumber(first);
    view.totalHours = decimalHours(monthView.totalHours);
    view.hourlyRate = money(
      contract.AXF_CTR_CUR_HourlyRate__c,
      contract.CurrencyIsoCode
    );
    view.totalValue = money(
      monthView.totalHours *
      (contract.AXF_CTR_CUR_HourlyRate__c == null
        ? 0
        : contract.AXF_CTR_CUR_HourlyRate__c),
      contract.CurrencyIsoCode
    );
    view.hasMaxHours = contract.AXF_CTR_NUM_MonthlyLimit__c != null;
    if (view.hasMaxHours) {
      view.maxHours = hoursAsHhmm(contract.AXF_CTR_NUM_MonthlyLimit__c);
      view.missingHours = hoursAsHhmm(
        Math.max(contract.AXF_CTR_NUM_MonthlyLimit__c - monthView.totalHours, 0)
      );
    }
    view.lines = new List<Line>();
    for (ALT_CLS_Timesheet.DayView day : monthView.days) {
      if (day.hours == 0 && english) {
        continue;
      }
      if (day.workDate < periodStart) {
        continue;
      }
      if (!english && day.hours == 0 && !day.workingDay) {
        continue;
      }
      Line line = new Line();
      line.workDate = english
        ? shortDate(day.workDate)
        : periodDate(day.workDate);
      line.in1 = day.hours == 0
        ? '–'
        : (english ? amPm(day.in1) : hhmm(day.in1));
      line.out1 = day.hours == 0
        ? '–'
        : (english ? amPm(day.out1) : hhmm(day.out1));
      line.in2 = day.hours == 0
        ? '–'
        : (english ? amPm(day.in2) : hhmm(day.in2));
      line.out2 = day.hours == 0
        ? '–'
        : (english ? amPm(day.out2) : hhmm(day.out2));
      line.hours = day.hours == 0
        ? '–'
        : (english ? decimalHours(day.hours) : hoursAsHhmm(day.hours));
      view.lines.add(line);
    }
    if (!english) {
      view.totalHours = hoursAsHhmm(monthView.totalHours);
    }
    return view;
  }

  public InvoiceView invoiceView(Id contractId, Integer year, Integer month) {
    AXF_OBJ_Contract__c contract = loadContract(contractId);
    if (contract.CurrencyIsoCode == BRL) {
      throw new DocumentException(
        'A fatura é só para contrato em moeda diferente de BRL: em BRL vale a nota fiscal emitida fora do sistema.'
      );
    }
    if (contract.AXF_CTR_LKP_Client__c == null) {
      throw new DocumentException('Informe o cliente do contrato.');
    }
    Date first = Date.newInstance(year, month, 1);
    AXF_OBJ_Entry__c entry = monthEntry(contractId, first);
    if (entry == null) {
      throw new DocumentException('Não há horas nem lançamento neste mês.');
    }
    ALT_CLS_Timesheet.MonthView monthView = new ALT_CLS_Timesheet()
      .loadMonth(contractId, year, month);
    Account issuer = [
      SELECT
        Name,
        BillingStreet,
        BillingCity,
        BillingState,
        BillingPostalCode,
        BillingCountry,
        AXF_ACC_TXT_TaxId__c,
        AXF_ACC_TAL_PaymentDetails__c
      FROM Account
      WHERE Id = :contract.AXF_CTR_MD_Holder__c
    ];
    Account client = [
      SELECT
        Name,
        BillingStreet,
        BillingCity,
        BillingState,
        BillingPostalCode,
        BillingCountry,
        AXF_ACC_TXT_TaxId__c
      FROM Account
      WHERE Id = :contract.AXF_CTR_LKP_Client__c
    ];
    Integer shift = contract.AXF_CTR_PKL_SendMonth__c ==
      ALT_CLS_Timesheet.NEXT_MONTH
      ? 1
      : 0;
    Integer sendDay = contract.AXF_CTR_NUM_SendDay__c == null
      ? 1
      : contract.AXF_CTR_NUM_SendDay__c.intValue();
    InvoiceView view = new InvoiceView();
    view.issuerName = issuer.Name;
    view.issuerTaxId = issuer.AXF_ACC_TXT_TaxId__c;
    view.issuerAddress = address(issuer);
    view.invoiceNumber = invoiceNumber(first);
    view.billToName = client.Name;
    view.billToTaxId = client.AXF_ACC_TXT_TaxId__c;
    view.billToAddress = address(client);
    view.invoiceDate = shortDate(
      ALT_CLS_ContractSchedule.monthlyDate(first, shift, sendDay)
    );
    view.terms = contract.AXF_CTR_TXT_PaymentTerms__c;
    view.dueDate = shortDate(entry.AXF_ENT_DAT_DueDate__c);
    view.description = 'IT Services - ' + MONTHS_PT[month - 1] + '-' + year;
    view.quantity = decimalHours(monthView.totalHours);
    view.rate = money(
      contract.AXF_CTR_CUR_HourlyRate__c,
      contract.CurrencyIsoCode
    );
    Decimal total = (monthView.totalHours *
      (contract.AXF_CTR_CUR_HourlyRate__c == null
        ? 0
        : contract.AXF_CTR_CUR_HourlyRate__c))
      .setScale(2, RoundingMode.HALF_UP);
    view.amount = money(total, contract.CurrencyIsoCode);
    view.paymentInformation = issuer.AXF_ACC_TAL_PaymentDetails__c;
    view.zero = money(0, contract.CurrencyIsoCode);
    return view;
  }

  // ---------- files ----------

  public SavedFile saveTimesheet(Id contractId, Integer year, Integer month) {
    AXF_OBJ_Entry__c entry = requireEntry(contractId, year, month);
    String title =
      'Timesheet-' +
      invoiceNumber(Date.newInstance(year, month, 1)) +
      '.pdf';
    return saveFile(
      Page.AXF_CTR_VFP_Timesheet,
      contractId,
      year,
      month,
      entry.Id,
      title
    );
  }

  public SavedFile saveInvoice(Id contractId, Integer year, Integer month) {
    // Validates the data (client, currency, entry) before rendering.
    invoiceView(contractId, year, month);
    AXF_OBJ_Entry__c entry = requireEntry(contractId, year, month);
    String invoiceId = invoiceNumber(Date.newInstance(year, month, 1));
    SavedFile saved = saveFile(
      Page.AXF_CTR_VFP_Invoice,
      contractId,
      year,
      month,
      entry.Id,
      'Invoice-' + invoiceId + '.pdf'
    );
    update new AXF_OBJ_Entry__c(
      Id = entry.Id,
      AXF_ENT_TXT_InvoiceNumber__c = invoiceId
    );
    return saved;
  }

  private SavedFile saveFile(
    PageReference page,
    Id contractId,
    Integer year,
    Integer month,
    Id entryId,
    String title
  ) {
    page.getParameters().put('id', contractId);
    page.getParameters().put('year', String.valueOf(year));
    page.getParameters().put('month', String.valueOf(month));
    // Rendered before any DML: getContentAsPDF cannot follow pending changes in some contexts.
    // Apex tests cannot render a page: they get a placeholder PDF.
    Blob pdf = Test.isRunningTest()
      ? Blob.valueOf('Unit test PDF')
      : page.getContentAsPDF();
    List<ContentDocumentLink> existing = [
      SELECT ContentDocumentId
      FROM ContentDocumentLink
      WHERE
        LinkedEntityId = :entryId
        AND ContentDocument.Title = :title.removeEnd('.pdf')
      LIMIT 1
    ];
    ContentVersion version = new ContentVersion(
      Title = title.removeEnd('.pdf'),
      PathOnClient = title,
      VersionData = pdf
    );
    SavedFile saved = new SavedFile();
    saved.title = title;
    if (existing.isEmpty()) {
      version.FirstPublishLocationId = entryId;
      saved.isNewVersion = false;
    } else {
      version.ContentDocumentId = existing[0].ContentDocumentId;
      saved.isNewVersion = true;
    }
    insert version;
    saved.documentId = [
      SELECT ContentDocumentId
      FROM ContentVersion
      WHERE Id = :version.Id
    ]
    .ContentDocumentId;
    return saved;
  }

  // ---------- support ----------

  private AXF_OBJ_Entry__c requireEntry(
    Id contractId,
    Integer year,
    Integer month
  ) {
    AXF_OBJ_Entry__c entry = monthEntry(
      contractId,
      Date.newInstance(year, month, 1)
    );
    if (entry == null) {
      throw new DocumentException(
        'Não há lançamento neste mês: lance as horas antes de gerar o documento.'
      );
    }
    return entry;
  }

  private static AXF_OBJ_Entry__c monthEntry(Id contractId, Date competence) {
    List<AXF_OBJ_Entry__c> found = [
      SELECT Id, AXF_ENT_DAT_DueDate__c
      FROM AXF_OBJ_Entry__c
      WHERE
        AXF_ENT_LKP_Contract__c = :contractId
        AND AXF_ENT_DAT_Competence__c = :competence
      ORDER BY CreatedDate
      LIMIT 1
    ];
    return found.isEmpty() ? null : found[0];
  }

  private static AXF_OBJ_Contract__c loadContract(Id contractId) {
    List<AXF_OBJ_Contract__c> found = [
      SELECT
        Id,
        CurrencyIsoCode,
        RecordType.DeveloperName,
        AXF_CTR_MD_Holder__r.Name,
        AXF_CTR_LKP_Client__c,
        AXF_CTR_CUR_HourlyRate__c,
        AXF_CTR_DAT_ActivityStart__c,
        AXF_CTR_NUM_MonthlyLimit__c,
        AXF_CTR_PKL_SendMonth__c,
        AXF_CTR_NUM_SendDay__c,
        AXF_CTR_TXT_PaymentTerms__c
      FROM AXF_OBJ_Contract__c
      WHERE Id = :contractId
    ];
    if (found.isEmpty()) {
      throw new DocumentException('Contrato não encontrado.');
    }
    if (found[0].RecordType.DeveloperName != ALT_CLS_Timesheet.RT_SERVICE) {
      throw new DocumentException(
        'O documento vale só para contrato de prestação de serviço.'
      );
    }
    return found[0];
  }

  private static String address(Account account) {
    List<String> parts = new List<String>();
    for (
      String part : new List<String>{
        account.BillingStreet,
        account.BillingCity,
        account.BillingState,
        account.BillingPostalCode,
        account.BillingCountry
      }
    ) {
      if (String.isNotBlank(part)) {
        parts.add(part.replace('\n', ', '));
      }
    }
    return String.join(parts, ', ');
  }
}
