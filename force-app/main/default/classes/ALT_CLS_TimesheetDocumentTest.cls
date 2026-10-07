@IsTest
private class ALT_CLS_TimesheetDocumentTest {
  private static Account holder;
  private static Account client;

  private static AXF_OBJ_Contract__c service(
    String currencyCode,
    Boolean withClient
  ) {
    if (holder == null) {
      holder = new Account(
        Name = 'Prestadora Ltda',
        BillingStreet = 'Rua A 1',
        BillingCity = 'São Paulo',
        BillingCountry = 'Brazil',
        AXF_ACC_TXT_TaxId__c = '12.345.678/0001-90',
        AXF_ACC_TAL_PaymentDetails__c = 'Banco X - IBAN PT50 0000'
      );
      client = new Account(
        Name = 'Cliente SA',
        BillingCity = 'Lisboa',
        AXF_ACC_TXT_TaxId__c = 'PT123456789',
        RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
          .get('AXF_Customer')
          .getRecordTypeId()
      );
      insert new List<Account>{ holder, client };
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
      AXF_CTR_CUR_HourlyRate__c = 616,
      AXF_CTR_PKL_ReceiptMonth__c = 'SameMonth',
      AXF_CTR_NUM_ReceiptDay__c = 30,
      AXF_CTR_PKL_SendMonth__c = 'SameMonth',
      AXF_CTR_NUM_SendDay__c = 10,
      AXF_CTR_TXT_PaymentTerms__c = 'Net 20'
    );
    if (withClient) {
      c.AXF_CTR_LKP_Client__c = client.Id;
    }
    insert c;
    return c;
  }

  private static void log(
    AXF_OBJ_Contract__c c,
    Integer day,
    Integer inH,
    Integer outH
  ) {
    new ALT_CLS_Timesheet()
      .save(
        c.Id,
        new List<ALT_CLS_Timesheet.Row>{
          new ALT_CLS_Timesheet.Row(
            Date.newInstance(2026, 9, day),
            Time.newInstance(inH, 0, 0, 0),
            Time.newInstance(outH, 0, 0, 0),
            null,
            null
          )
        }
      );
  }

  @IsTest
  static void moneyUsesBrazilianGroupingAndTheCurrencySymbol() {
    System.assertEquals(
      '4.928,00 €',
      ALT_CLS_TimesheetDocument.money(4928, 'EUR')
    );
    System.assertEquals('0,00 €', ALT_CLS_TimesheetDocument.money(0, 'EUR'));
    System.assertEquals(
      '1.234.567,50 US$',
      ALT_CLS_TimesheetDocument.money(1234567.5, 'USD')
    );
    System.assertEquals(
      '616,00 €',
      ALT_CLS_TimesheetDocument.money(616, 'EUR')
    );
    System.assertEquals('0,00 €', ALT_CLS_TimesheetDocument.money(null, 'EUR'));
  }

  @IsTest
  static void datesAndTimesFollowTheModels() {
    System.assertEquals(
      '11 set 2026',
      ALT_CLS_TimesheetDocument.shortDate(Date.newInstance(2026, 9, 11))
    );
    System.assertEquals(
      '01/09/2026',
      ALT_CLS_TimesheetDocument.periodDate(Date.newInstance(2026, 9, 1))
    );
    System.assertEquals(
      '9:30 AM',
      ALT_CLS_TimesheetDocument.amPm(Time.newInstance(9, 30, 0, 0))
    );
    System.assertEquals(
      '12:00 PM',
      ALT_CLS_TimesheetDocument.amPm(Time.newInstance(12, 0, 0, 0))
    );
    System.assertEquals(
      '12:15 AM',
      ALT_CLS_TimesheetDocument.amPm(Time.newInstance(0, 15, 0, 0))
    );
    System.assertEquals(
      '6:00 PM',
      ALT_CLS_TimesheetDocument.amPm(Time.newInstance(18, 0, 0, 0))
    );
    System.assertEquals(
      '9:05',
      ALT_CLS_TimesheetDocument.hhmm(Time.newInstance(9, 5, 0, 0))
    );
    System.assertEquals('8:30', ALT_CLS_TimesheetDocument.hoursAsHhmm(8.5));
    System.assertEquals('0:00', ALT_CLS_TimesheetDocument.hoursAsHhmm(0));
    System.assertEquals('8,50', ALT_CLS_TimesheetDocument.decimalHours(8.5));
    System.assertEquals(
      '202609',
      ALT_CLS_TimesheetDocument.invoiceNumber(Date.newInstance(2026, 9, 1))
    );
  }

  @IsTest
  static void theEuropeanTimesheetListsOnlyTheWorkedDaysWithValues() {
    AXF_OBJ_Contract__c c = service('EUR', true);
    log(c, 1, 9, 17);
    log(c, 2, 9, 13);
    ALT_CLS_TimesheetDocument.TimesheetView view = new ALT_CLS_TimesheetDocument()
      .timesheetView(c.Id, 2026, 9);
    System.assertEquals(true, view.english);
    System.assertEquals('Prestadora Ltda', view.providerName);
    System.assertEquals('01/09/2026', view.periodStart);
    System.assertEquals('30/09/2026', view.periodEnd);
    System.assertEquals(2, view.lines.size());
    // One period only: Time In and Time Out, with the lunch columns as dashes.
    System.assertEquals('9:00 AM', view.lines[0].in1);
    System.assertEquals('–', view.lines[0].out1);
    System.assertEquals('–', view.lines[0].in2);
    System.assertEquals('5:00 PM', view.lines[0].out2);
    System.assertEquals('01/09/2026', view.lines[0].workDate);
    System.assertEquals('8,00', view.lines[0].hours);
    System.assertEquals('12,00', view.totalHours);
    System.assertEquals('616,00 €', view.hourlyRate);
    System.assertEquals('7.392,00 €', view.totalValue);
  }

  @IsTest
  static void theBrazilianTimesheetHasHoursOnlyWithMaximumAndBalance() {
    AXF_OBJ_Contract__c c = service('BRL', false);
    c.AXF_CTR_NUM_MonthlyLimit__c = 80;
    update c;
    log(c, 1, 9, 17);
    ALT_CLS_TimesheetDocument.TimesheetView view = new ALT_CLS_TimesheetDocument()
      .timesheetView(c.Id, 2026, 9);
    System.assertEquals(false, view.english);
    System.assertEquals('8:00', view.totalHours);
    System.assertEquals(true, view.hasMaxHours);
    System.assertEquals('80:00', view.maxHours);
    System.assertEquals('72:00', view.missingHours);
    // Working days without hours appear with a dash; weekends do not appear.
    Boolean hasDash = false;
    for (ALT_CLS_TimesheetDocument.Line line : view.lines) {
      if (line.hours == '–') {
        hasDash = true;
      }
    }
    System.assert(hasDash);
    System.assertEquals('01/09/2026', view.lines[0].workDate);
    System.assertEquals('9:00', view.lines[0].in1);
    // September 2026 has 22 working days and no line is dated on a weekend.
    System.assertEquals(22, view.lines.size());
    for (ALT_CLS_TimesheetDocument.Line line : view.lines) {
      System.assertNotEquals('05/09/2026', line.workDate);
      System.assertNotEquals('06/09/2026', line.workDate);
    }
    // A one-period day keeps the empty columns as dashes in the Portuguese model.
    System.assertEquals('–', view.lines[0].in2);
  }

  @IsTest
  static void theFirstCompetenceStartsOnTheActivityStart() {
    AXF_OBJ_Contract__c c = service('BRL', false);
    c.AXF_CTR_DAT_ActivityStart__c = Date.newInstance(2026, 9, 28);
    update c;
    log(c, 29, 9, 17);
    ALT_CLS_TimesheetDocument.TimesheetView view = new ALT_CLS_TimesheetDocument()
      .timesheetView(c.Id, 2026, 9);
    System.assertEquals('28/09/2026', view.periodStart);
    System.assertEquals('28/09/2026', view.lines[0].workDate);
  }

  @IsTest
  static void theInvoiceCarriesIssuerClientNumberAndTotals() {
    AXF_OBJ_Contract__c c = service('EUR', true);
    log(c, 1, 9, 17);
    ALT_CLS_TimesheetDocument.InvoiceView view = new ALT_CLS_TimesheetDocument()
      .invoiceView(c.Id, 2026, 9);
    System.assertEquals('202609', view.invoiceNumber);
    System.assertEquals('Prestadora Ltda', view.issuerName);
    System.assertEquals('12.345.678/0001-90', view.issuerTaxId);
    System.assert(view.issuerAddress.contains('São Paulo'));
    System.assertEquals('Cliente SA', view.billToName);
    System.assertEquals('PT123456789', view.billToTaxId);
    System.assertEquals('10 set 2026', view.invoiceDate);
    System.assertEquals('Net 20', view.terms);
    System.assertEquals('30 set 2026', view.dueDate);
    System.assertEquals('IT Services - set-2026', view.description);
    System.assertEquals('8,00', view.quantity);
    System.assertEquals('616,00 €', view.rate);
    System.assertEquals('4.928,00 €', view.amount);
    System.assertEquals('0,00 €', view.zero);
    System.assert(view.paymentInformation.contains('IBAN'));
  }

  @IsTest
  static void anInvoiceCannotBeIssuedInBrl() {
    AXF_OBJ_Contract__c brl = service('BRL', false);
    log(brl, 1, 9, 17);
    String message;
    try {
      new ALT_CLS_TimesheetDocument().invoiceView(brl.Id, 2026, 9);
    } catch (ALT_CLS_TimesheetDocument.DocumentException e) {
      message = e.getMessage();
    }
    System.assert(message.contains('BRL'), message);
    // A foreign-currency contract without client cannot even be saved (AXF-218 rule).
  }

  @IsTest
  static void anInvoiceNeedsTheMonthEntry() {
    AXF_OBJ_Contract__c c = service('EUR', true);
    String message;
    try {
      new ALT_CLS_TimesheetDocument().invoiceView(c.Id, 2026, 9);
    } catch (ALT_CLS_TimesheetDocument.DocumentException e) {
      message = e.getMessage();
    }
    System.assert(message.contains('Não há horas'), message);
  }

  @IsTest
  static void theTimesheetPdfIsSavedOnTheEntryAndRegeneratedAsANewVersion() {
    AXF_OBJ_Contract__c c = service('EUR', true);
    log(c, 1, 9, 17);
    ALT_CLS_TimesheetDocument.SavedFile first = new ALT_CLS_TimesheetDocument()
      .saveTimesheet(c.Id, 2026, 9);
    System.assertEquals('Timesheet-202609.pdf', first.title);
    System.assertEquals(false, first.isNewVersion);
    AXF_OBJ_Entry__c entry = [
      SELECT Id
      FROM AXF_OBJ_Entry__c
      WHERE AXF_ENT_LKP_Contract__c = :c.Id
    ];
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM ContentDocumentLink
        WHERE
          LinkedEntityId = :entry.Id
          AND ContentDocumentId = :first.documentId
      ]
    );
    ALT_CLS_TimesheetDocument.SavedFile second = new ALT_CLS_TimesheetDocument()
      .saveTimesheet(c.Id, 2026, 9);
    System.assertEquals(true, second.isNewVersion);
    System.assertEquals(first.documentId, second.documentId);
    System.assertEquals(
      2,
      [
        SELECT COUNT()
        FROM ContentVersion
        WHERE ContentDocumentId = :first.documentId
      ]
    );
  }

  @IsTest
  static void theInvoicePdfWritesTheInvoiceNumberOnTheEntry() {
    AXF_OBJ_Contract__c c = service('EUR', true);
    log(c, 1, 9, 17);
    ALT_CLS_TimesheetDocument.SavedFile saved = new ALT_CLS_TimesheetDocument()
      .saveInvoice(c.Id, 2026, 9);
    System.assertEquals('Invoice-202609.pdf', saved.title);
    System.assertEquals(
      '202609',
      [
        SELECT AXF_ENT_TXT_InvoiceNumber__c
        FROM AXF_OBJ_Entry__c
        WHERE AXF_ENT_LKP_Contract__c = :c.Id
      ]
      .AXF_ENT_TXT_InvoiceNumber__c
    );
  }

  @IsTest
  static void aPdfNeedsTheMonthEntry() {
    AXF_OBJ_Contract__c c = service('BRL', false);
    String message;
    try {
      new ALT_CLS_TimesheetDocument().saveTimesheet(c.Id, 2026, 9);
    } catch (ALT_CLS_TimesheetDocument.DocumentException e) {
      message = e.getMessage();
    }
    System.assert(message.contains('lance as horas'), message);
  }

  @IsTest
  static void onlyServiceContractsHaveDocuments() {
    Account a = new Account(Name = 'Titular');
    insert a;
    AXF_OBJ_Contract__c recurring = new AXF_OBJ_Contract__c(
      Name = 'Assinatura',
      AXF_CTR_MD_Holder__c = a.Id,
      RecordTypeId = Schema.SObjectType.AXF_OBJ_Contract__c.getRecordTypeInfosByDeveloperName()
        .get('AXF_Recurring')
        .getRecordTypeId(),
      AXF_CTR_PKL_Direction__c = 'Expense',
      AXF_CTR_PKL_Status__c = 'Active'
    );
    insert recurring;
    String message;
    try {
      new ALT_CLS_TimesheetDocument().timesheetView(recurring.Id, 2026, 9);
    } catch (ALT_CLS_TimesheetDocument.DocumentException e) {
      message = e.getMessage();
    }
    System.assert(message.contains('prestação de serviço'), message);
  }

  @IsTest
  static void theVisualforceControllersExposeTheViewOrTheError() {
    AXF_OBJ_Contract__c c = service('EUR', true);
    log(c, 1, 9, 17);
    PageReference timesheet = Page.AXF_CTR_VFP_Timesheet;
    timesheet.getParameters().put('id', c.Id);
    timesheet.getParameters().put('year', '2026');
    timesheet.getParameters().put('month', '9');
    Test.setCurrentPage(timesheet);
    AXF_CLS_CTRL_TimesheetPdf timesheetController = new AXF_CLS_CTRL_TimesheetPdf();
    System.assertEquals(null, timesheetController.error);
    System.assertEquals(
      'Prestadora Ltda',
      timesheetController.view.providerName
    );
    PageReference invoice = Page.AXF_CTR_VFP_Invoice;
    invoice.getParameters().put('id', c.Id);
    invoice.getParameters().put('year', '2026');
    invoice.getParameters().put('month', '9');
    Test.setCurrentPage(invoice);
    System.assertEquals(
      '202609',
      new AXF_CLS_CTRL_InvoicePdf().view.invoiceNumber
    );
    PageReference broken = Page.AXF_CTR_VFP_Invoice;
    broken.getParameters().put('id', c.Id);
    broken.getParameters().put('year', '2026');
    broken.getParameters().put('month', '1');
    Test.setCurrentPage(broken);
    System.assertNotEquals(null, new AXF_CLS_CTRL_InvoicePdf().error);
  }

  @IsTest
  static void theLwcControllerCreatesTheFilesAndReportsProblems() {
    AXF_OBJ_Contract__c c = service('EUR', true);
    log(c, 1, 9, 17);
    AXF_CLS_CTRL_Timesheet.PdfDto timesheet = AXF_CLS_CTRL_Timesheet.createTimesheetPdf(
      c.Id,
      2026,
      9
    );
    System.assertEquals('Timesheet-202609.pdf', timesheet.title);
    AXF_CLS_CTRL_Timesheet.PdfDto invoice = AXF_CLS_CTRL_Timesheet.createInvoicePdf(
      c.Id,
      2026,
      9
    );
    System.assertEquals('Invoice-202609.pdf', invoice.title);
    String message;
    try {
      AXF_CLS_CTRL_Timesheet.createInvoicePdf(c.Id, 2026, 1);
    } catch (AuraHandledException e) {
      message = e.getMessage();
    }
    System.assert(message.contains('Não há horas'), message);
  }

  @IsTest
  static void anInvalidCompetenceIsRejected() {
    AXF_OBJ_Contract__c c = service('EUR', true);
    String message;
    try {
      new ALT_CLS_TimesheetDocument().timesheetView(c.Id, 2026, 13);
    } catch (ALT_CLS_TimesheetDocument.DocumentException e) {
      message = e.getMessage();
    }
    System.assert(message.contains('inválida'), message);
  }

  @IsTest
  static void theTimesheetPdfIsValidatedBeforeItIsRendered() {
    Account a = new Account(Name = 'Titular');
    insert a;
    AXF_OBJ_Contract__c recurring = new AXF_OBJ_Contract__c(
      Name = 'Assinatura',
      AXF_CTR_MD_Holder__c = a.Id,
      RecordTypeId = Schema.SObjectType.AXF_OBJ_Contract__c.getRecordTypeInfosByDeveloperName()
        .get('AXF_Recurring')
        .getRecordTypeId(),
      AXF_CTR_PKL_Direction__c = 'Expense',
      AXF_CTR_PKL_Status__c = 'Active'
    );
    insert recurring;
    // An entry exists for the month, but the contract is not a service: no File is created.
    insert new AXF_OBJ_Entry__c(
      Name = 'x',
      AXF_ENT_MD_Holder__c = a.Id,
      AXF_ENT_LKP_Contract__c = recurring.Id,
      AXF_ENT_CUR_Amount__c = 10,
      AXF_ENT_DAT_DueDate__c = Date.newInstance(2026, 9, 10),
      AXF_ENT_DAT_Competence__c = Date.newInstance(2026, 9, 1),
      AXF_ENT_PKL_Type__c = 'Expense',
      AXF_ENT_PKL_Status__c = 'Pending'
    );
    try {
      new ALT_CLS_TimesheetDocument().saveTimesheet(recurring.Id, 2026, 9);
      System.assert(false, 'Expected an error');
    } catch (ALT_CLS_TimesheetDocument.DocumentException e) {
      System.assert(e.getMessage().contains('prestação de serviço'));
    }
    System.assertEquals(0, [SELECT COUNT() FROM ContentVersion]);
  }

  @IsTest
  static void anInvoiceNeedsHoursAndARate() {
    AXF_OBJ_Contract__c c = service('EUR', true);
    c.AXF_CTR_CUR_HourlyRate__c = null;
    update c;
    // The entry of the month exists (created by hours logged earlier with a rate).
    insert new AXF_OBJ_Entry__c(
      Name = 'x',
      AXF_ENT_MD_Holder__c = holder.Id,
      AXF_ENT_LKP_Contract__c = c.Id,
      AXF_ENT_CUR_Amount__c = 10,
      AXF_ENT_DAT_DueDate__c = Date.newInstance(2026, 9, 30),
      AXF_ENT_DAT_Competence__c = Date.newInstance(2026, 9, 1),
      AXF_ENT_PKL_Type__c = 'Income',
      AXF_ENT_PKL_Status__c = 'Pending'
    );
    String message;
    try {
      new ALT_CLS_TimesheetDocument().invoiceView(c.Id, 2026, 9);
    } catch (ALT_CLS_TimesheetDocument.DocumentException e) {
      message = e.getMessage();
    }
    System.assert(message.contains('horas no mês'), message);
  }
}
