@IsTest
private class ALT_CLS_FxRateTest {
  private class RecordingWriter implements ALT_CLS_FxRate.RateWriter {
    Map<String, Decimal> written = new Map<String, Decimal>();
    public void write(String isoCode, Decimal nativeRate) {
      written.put(isoCode, nativeRate);
    }
  }

  private class FailingWriter implements ALT_CLS_FxRate.RateWriter {
    public void write(String isoCode, Decimal nativeRate) {
      throw new ALT_CLS_FxRate.FxException('A org recusou a taxa.');
    }
  }

  // One router for the BCB service and the REST write of this org.
  private class Router implements HttpCalloutMock {
    // Quote by day (MM-DD-YYYY as in the URL); a missing day answers an empty list.
    Map<String, String> bulletinByDay = new Map<String, String>();
    Integer bcbStatus = 200;
    Integer restStatus = 204;
    List<String> urls = new List<String>();
    List<String> methods = new List<String>();
    List<String> bodies = new List<String>();

    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      urls.add(request.getEndpoint());
      methods.add(request.getMethod());
      bodies.add(request.getBody());
      if (request.getEndpoint().contains('sobjects/CurrencyType')) {
        response.setStatusCode(restStatus);
        return response;
      }
      response.setStatusCode(bcbStatus);
      String body = '{"value":[]}';
      for (String day : bulletinByDay.keySet()) {
        if (request.getEndpoint().contains('\'' + day + '\'')) {
          body = bulletinByDay.get(day);
        }
      }
      response.setBody(body);
      return response;
    }
  }

  private static String closing(String quote) {
    return '{"value":[{"cotacaoCompra":5.60,"tipoBoletim":"Intermediário"},{"cotacaoCompra":' +
      quote +
      ',"tipoBoletim":"Fechamento PTAX"}]}';
  }

  private static AXF_FxParameter__mdt parameter(
    String code,
    Decimal spread,
    Decimal iof
  ) {
    return new AXF_FxParameter__mdt(
      AXF_FXP_TXT_CurrencyCode__c = code,
      AXF_FXP_PCT_Spread__c = spread,
      AXF_FXP_PCT_Iof__c = iof
    );
  }

  @IsTest
  static void theEffectiveRateAppliesSpreadAndIof() {
    // 5.5958 x 0.99 x 1.00
    System.assertEquals(5.539842, ALT_CLS_FxRate.effectiveRate(5.5958, 1, 0));
    // 5.00 x 0.98 x 0.96
    System.assertEquals(4.704, ALT_CLS_FxRate.effectiveRate(5, 2, 4));
    System.assertEquals(5, ALT_CLS_FxRate.effectiveRate(5, null, null));
  }

  @IsTest
  static void theNativeRateIsTheInverseOfTheEffectiveRate() {
    System.assertEquals(0.2, ALT_CLS_FxRate.nativeRate(5));
    System.assertEquals(
      0.18051,
      ALT_CLS_FxRate.nativeRate(5.539842).setScale(5)
    );
  }

  @IsTest
  static void theQuoteDateIsMonthDayYear() {
    System.assertEquals(
      '10-06-2026',
      ALT_CLS_FxRate.quoteDate(Date.newInstance(2026, 10, 6))
    );
    System.assertEquals(
      '01-02-2027',
      ALT_CLS_FxRate.quoteDate(Date.newInstance(2027, 1, 2))
    );
  }

  @IsTest
  static void onlyTheClosingBulletinCounts() {
    System.assertEquals(
      5.5958,
      ALT_CLS_FxRate.closingQuoteOf(closing('5.5958'))
    );
    System.assertEquals(
      null,
      ALT_CLS_FxRate.closingQuoteOf(
        '{"value":[{"cotacaoCompra":5.60,"tipoBoletim":"Abertura"}]}'
      )
    );
    System.assertEquals(null, ALT_CLS_FxRate.closingQuoteOf('{"value":[]}'));
    System.assertEquals(null, ALT_CLS_FxRate.closingQuoteOf('{}'));
    try {
      ALT_CLS_FxRate.closingQuoteOf(closing('0'));
      System.assert(false, 'Expected an error');
    } catch (ALT_CLS_FxRate.FxException e) {
      System.assert(e.getMessage().contains('inválida'));
    }
  }

  @IsTest
  static void updateAllWritesTheNativeRateOfEachConfiguredCurrency() {
    Router router = new Router();
    router.bulletinByDay.put('10-07-2026', closing('5.5958'));
    Test.setMock(HttpCalloutMock.class, router);
    RecordingWriter writer = new RecordingWriter();
    ALT_CLS_FxRate service = new ALT_CLS_FxRate();
    service.writer = writer;
    service.today = Date.newInstance(2026, 10, 7);
    service.parameterRecords = new List<AXF_FxParameter__mdt>{
      parameter('EUR', 1, 0),
      parameter('USD', 0, 0)
    };
    List<ALT_CLS_FxRate.Outcome> outcomes = service.updateAll();
    for (ALT_CLS_FxRate.Outcome outcome : outcomes) {
      System.assertEquals(null, outcome.error, outcome.isoCode);
    }
    System.assertEquals(
      ALT_CLS_FxRate.nativeRate(5.539842),
      writer.written.get('EUR')
    );
    System.assertEquals(
      ALT_CLS_FxRate.nativeRate(5.5958),
      writer.written.get('USD')
    );
    System.assert(router.urls[0].startsWith('callout:AXF_NC_BCB_PTAX/olinda/'));
    System.assert(router.urls[0].contains('@moeda=\'EUR\''));
  }

  @IsTest
  static void aCurrencyWithoutParametersIsLeftAlone() {
    Router router = new Router();
    router.bulletinByDay.put('10-07-2026', closing('5.5958'));
    Test.setMock(HttpCalloutMock.class, router);
    RecordingWriter writer = new RecordingWriter();
    ALT_CLS_FxRate service = new ALT_CLS_FxRate();
    service.writer = writer;
    service.today = Date.newInstance(2026, 10, 7);
    service.parameterRecords = new List<AXF_FxParameter__mdt>{
      parameter('EUR', 1, 0)
    };
    service.updateAll();
    System.assertEquals(1, writer.written.size());
    System.assert(!writer.written.containsKey('USD'));
  }

  @IsTest
  static void aHolidayLooksBackForTheLastBulletin() {
    Router router = new Router();
    // Saturday 10/10: no bulletin; Friday 09/10 has it.
    router.bulletinByDay.put('10-09-2026', closing('5.50'));
    Test.setMock(HttpCalloutMock.class, router);
    RecordingWriter writer = new RecordingWriter();
    ALT_CLS_FxRate service = new ALT_CLS_FxRate();
    service.writer = writer;
    service.today = Date.newInstance(2026, 10, 10);
    service.parameterRecords = new List<AXF_FxParameter__mdt>{
      parameter('EUR', 0, 0)
    };
    service.updateAll();
    System.assertEquals(
      ALT_CLS_FxRate.nativeRate(5.5),
      writer.written.get('EUR')
    );
    System.assertEquals(2, router.urls.size());
  }

  @IsTest
  static void noBulletinInTheWindowLeavesThePreviousRate() {
    Router router = new Router();
    Test.setMock(HttpCalloutMock.class, router);
    RecordingWriter writer = new RecordingWriter();
    ALT_CLS_FxRate service = new ALT_CLS_FxRate();
    service.writer = writer;
    service.today = Date.newInstance(2026, 10, 7);
    service.parameterRecords = new List<AXF_FxParameter__mdt>{
      parameter('EUR', 1, 0)
    };
    List<ALT_CLS_FxRate.Outcome> outcomes = service.updateAll();
    System.assert(outcomes[0].error.contains('Sem boletim'), outcomes[0].error);
    System.assertEquals(0, writer.written.size());
    System.assertEquals(ALT_CLS_FxRate.LOOKBACK_DAYS, router.urls.size());
  }

  @IsTest
  static void aServiceFailureLeavesThePreviousRate() {
    Router router = new Router();
    router.bcbStatus = 503;
    Test.setMock(HttpCalloutMock.class, router);
    RecordingWriter writer = new RecordingWriter();
    ALT_CLS_FxRate service = new ALT_CLS_FxRate();
    service.writer = writer;
    service.today = Date.newInstance(2026, 10, 7);
    service.parameterRecords = new List<AXF_FxParameter__mdt>{
      parameter('EUR', 1, 0)
    };
    List<ALT_CLS_FxRate.Outcome> outcomes = service.updateAll();
    System.assert(outcomes[0].error.contains('503'), outcomes[0].error);
    System.assertEquals(0, writer.written.size());
  }

  @IsTest
  static void aRefusedWriteIsReportedAndNothingElseChanges() {
    Router router = new Router();
    router.bulletinByDay.put('10-07-2026', closing('5.5958'));
    Test.setMock(HttpCalloutMock.class, router);
    ALT_CLS_FxRate service = new ALT_CLS_FxRate();
    service.writer = new FailingWriter();
    service.today = Date.newInstance(2026, 10, 7);
    service.parameterRecords = new List<AXF_FxParameter__mdt>{
      parameter('EUR', 1, 0)
    };
    List<ALT_CLS_FxRate.Outcome> outcomes = service.updateAll();
    System.assertEquals('A org recusou a taxa.', outcomes[0].error);
  }

  @IsTest
  static void aZeroedEffectiveRateIsNeverWritten() {
    Router router = new Router();
    router.bulletinByDay.put('10-07-2026', closing('5.5958'));
    Test.setMock(HttpCalloutMock.class, router);
    RecordingWriter writer = new RecordingWriter();
    ALT_CLS_FxRate service = new ALT_CLS_FxRate();
    service.writer = writer;
    service.today = Date.newInstance(2026, 10, 7);
    service.parameterRecords = new List<AXF_FxParameter__mdt>{
      parameter('EUR', 100, 0)
    };
    List<ALT_CLS_FxRate.Outcome> outcomes = service.updateAll();
    System.assert(outcomes[0].error.contains('zerada'), outcomes[0].error);
    System.assertEquals(0, writer.written.size());
  }

  @IsTest
  static void theRestWriterPatchesTheCurrencyOfThisOrg() {
    Router router = new Router();
    Test.setMock(HttpCalloutMock.class, router);
    new ALT_CLS_FxRateRestWriter().write('EUR', 0.18051);
    System.assertEquals('PATCH', router.methods[0]);
    System.assert(
      router.urls[0].startsWith('callout:AXF_NC_Salesforce_Rest/services/data/')
    );
    System.assert(router.urls[0].contains('/sobjects/CurrencyType/'));
    System.assert(router.bodies[0].contains('"ConversionRate":0.18051'));
  }

  @IsTest
  static void theRestWriterReportsARefusalAndAnUnknownCurrency() {
    Router router = new Router();
    router.restStatus = 400;
    Test.setMock(HttpCalloutMock.class, router);
    try {
      new ALT_CLS_FxRateRestWriter().write('EUR', 0.18);
      System.assert(false, 'Expected an error');
    } catch (ALT_CLS_FxRate.FxException e) {
      System.assert(e.getMessage().contains('400'), e.getMessage());
    }
    try {
      new ALT_CLS_FxRateRestWriter().write('XXX', 0.18);
      System.assert(false, 'Expected an error');
    } catch (ALT_CLS_FxRate.FxException e) {
      System.assert(e.getMessage().contains('não existe'), e.getMessage());
    }
  }

  @IsTest
  static void theJobIsScheduledOnWeekdaysAndReplacesItself() {
    Id first = ALT_CLS_FxRateSchedule.scheduleDaily();
    System.assertEquals(
      ALT_CLS_FxRateSchedule.WEEKDAYS_AT_2PM,
      [SELECT CronExpression FROM CronTrigger WHERE Id = :first].CronExpression
    );
    ALT_CLS_FxRateSchedule.scheduleDaily();
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM CronTrigger
        WHERE CronJobDetail.Name = :ALT_CLS_FxRateSchedule.JOB_NAME
      ]
    );
  }

  @IsTest
  static void theQueueableFailsTheJobWhenARateCannotBeUpdated() {
    Router router = new Router();
    router.bcbStatus = 503;
    Test.setMock(HttpCalloutMock.class, router);
    String failure;
    Test.startTest();
    System.enqueueJob(new ALT_CLS_FxRateJob());
    try {
      Test.stopTest();
    } catch (ALT_CLS_FxRate.FxException e) {
      failure = e.getMessage();
    }
    // The deployed EUR and USD parameters are picked up; the rates stay as they were.
    System.assert(failure.contains('HTTP 503'), failure);
  }

  @IsTest
  static void theScheduleEnqueuesTheJob() {
    Router router = new Router();
    Test.setMock(HttpCalloutMock.class, router);
    Test.startTest();
    new ALT_CLS_FxRateSchedule().execute(null);
    String failure;
    try {
      Test.stopTest();
    } catch (ALT_CLS_FxRate.FxException e) {
      failure = e.getMessage();
    }
    System.assert(failure.contains('Sem boletim'), failure);
  }
}
