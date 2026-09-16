/**
 * @description Testes unitarios de ALT_CLS_FxConversionService (AXF-24).
 * Cobre: conversao cria FXS (preserva original, congela taxa/fonte), mesma moeda sem snapshot,
 * taxa ausente -> MISSING_RATE, replay idempotente, delete bloqueado.
 */
@IsTest
private class ALT_CLS_FxConversionServiceTest {
  @TestSetup
  static void grants() {
    insert new PermissionSetAssignment(
      AssigneeId = UserInfo.getUserId(),
      PermissionSetId = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = 'AXF_PS_Realization'
      ]
      .Id
    );
  }

  private static Account makeAccount(String name) {
    Account acc = new Account(Name = name);
    insert acc;
    return acc;
  }

  private static AXF_OBJ_FinancialTransaction__c makeFtx(
    Account acc,
    Decimal magnitude,
    String iso
  ) {
    AXF_OBJ_FinancialTransaction__c ftx = new AXF_OBJ_FinancialTransaction__c(
      AXF_FTX_LKP_Account__c = acc.Id,
      AXF_FTX_NUM_Magnitude__c = magnitude,
      AXF_FTX_PKL_Direction__c = 'DEBIT',
      AXF_FTX_TXT_CurrencyIsoCode__c = iso,
      AXF_FTX_DAT_PurchaseDate__c = Date.today(),
      AXF_FTX_PKL_Status__c = 'CONFIRMED',
      AXF_FTX_EXI_ClientRequestId__c = 'fxs-ftx-' + Datetime.now().getTime()
    );
    insert ftx;
    return ftx;
  }

  private static AXF_OBJ_ExchangeRate__c makeRate(
    String baseIso,
    String quoteIso,
    Decimal rate
  ) {
    AXF_OBJ_ExchangeRate__c exr = new AXF_OBJ_ExchangeRate__c(
      AXF_EXR_TXT_BaseCurrency__c = baseIso,
      AXF_EXR_TXT_QuoteCurrency__c = quoteIso,
      AXF_EXR_NUM_Rate__c = rate,
      AXF_EXR_PKL_Side__c = 'SELL',
      AXF_EXR_TXT_Provider__c = 'BCB_PTAX',
      AXF_EXR_DT_EffectiveDateTime__c = System.now().addHours(-1),
      AXF_EXR_EXI_RateKey__c = 'r-' +
        Datetime.now().getTime() +
        '-' +
        baseIso +
        quoteIso
    );
    insert exr;
    return exr;
  }

  private static ALT_CLS_FxConversionService.ConversionInputDTO input(
    Id targetId,
    String reportingIso
  ) {
    ALT_CLS_FxConversionService.ConversionInputDTO dto = new ALT_CLS_FxConversionService.ConversionInputDTO();
    dto.targetType = 'FINANCIAL_TRANSACTION';
    dto.targetId = targetId;
    dto.purpose = 'RECOGNITION';
    dto.reportingIso = reportingIso;
    dto.side = 'SELL';
    dto.policyVersion = 'FX-POLICY-1.0.0';
    dto.roundingPolicy = 'HALF_UP_2';
    return dto;
  }

  @IsTest
  static void applyConversion_CreatesSnapshot_PreservesOriginal() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Account acc = makeAccount('Titular FXS-1');
      AXF_OBJ_FinancialTransaction__c ftx = makeFtx(acc, 100, 'USD');
      makeRate('USD', 'BRL', 5.05);

      ALT_CLS_FxConversionService service = new ALT_CLS_FxConversionService();
      ALT_CLS_FxConversionService.ConversionResultDTO result = service.applyConversion(
        input(ftx.Id, 'BRL')
      );

      Assert.isTrue(
        result.converted,
        'outcome=' + result.outcome + ' :: ' + result.message
      );
      Assert.areEqual('CONVERTED', result.outcome);
      Assert.areEqual(505.0, result.reportingAmount);
      Assert.areEqual(100, result.originalAmount);
      Assert.areEqual('USD', result.originalIso);

      List<AXF_OBJ_FxApplicationSnapshot__c> snaps = [
        SELECT Id, AXF_FXS_NUM_OriginalAmount__c, AXF_FXS_LKP_RateSource__c
        FROM AXF_OBJ_FxApplicationSnapshot__c
        WHERE AXF_FXS_LKP_FinancialTransaction__c = :ftx.Id
      ];
      Assert.areEqual(1, snaps.size());
      Assert.areEqual(100, snaps[0].AXF_FXS_NUM_OriginalAmount__c);
      Assert.isNotNull(snaps[0].AXF_FXS_LKP_RateSource__c);
    }
  }

  @IsTest
  static void applyConversion_SameCurrency_NoSnapshot() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Account acc = makeAccount('Titular FXS-2');
      AXF_OBJ_FinancialTransaction__c ftx = makeFtx(acc, 100, 'BRL');

      ALT_CLS_FxConversionService service = new ALT_CLS_FxConversionService();
      ALT_CLS_FxConversionService.ConversionResultDTO result = service.applyConversion(
        input(ftx.Id, 'BRL')
      );

      Assert.areEqual('SAME_CURRENCY', result.outcome);
      Assert.isFalse(result.converted);
    }
  }

  @IsTest
  static void applyConversion_MissingRate_Reports() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Account acc = makeAccount('Titular FXS-3');
      AXF_OBJ_FinancialTransaction__c ftx = makeFtx(acc, 100, 'USD');

      ALT_CLS_FxConversionService service = new ALT_CLS_FxConversionService();
      ALT_CLS_FxConversionService.ConversionResultDTO result = service.applyConversion(
        input(ftx.Id, 'BRL')
      );

      Assert.areEqual('MISSING_RATE', result.outcome);
      Assert.areEqual(null, result.snapshotId);
      Integer snaps = [
        SELECT COUNT()
        FROM AXF_OBJ_FxApplicationSnapshot__c
        WHERE AXF_FXS_LKP_FinancialTransaction__c = :ftx.Id
      ];
      Assert.areEqual(0, snaps);
    }
  }

  @IsTest
  static void applyConversion_Replay_IsIdempotent() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Account acc = makeAccount('Titular FXS-4');
      AXF_OBJ_FinancialTransaction__c ftx = makeFtx(acc, 100, 'USD');
      makeRate('USD', 'BRL', 5.05);

      ALT_CLS_FxConversionService service = new ALT_CLS_FxConversionService();
      service.applyConversion(input(ftx.Id, 'BRL'));
      ALT_CLS_FxConversionService.ConversionResultDTO second = service.applyConversion(
        input(ftx.Id, 'BRL')
      );

      Assert.isTrue(
        second.converted,
        'outcome=' + second.outcome + ' :: ' + second.message
      );
      Assert.areEqual('CONVERTED', second.outcome);
      Integer snaps = [
        SELECT COUNT()
        FROM AXF_OBJ_FxApplicationSnapshot__c
        WHERE AXF_FXS_LKP_FinancialTransaction__c = :ftx.Id
      ];
      Assert.areEqual(1, snaps, 'Replay nao duplica snapshot.');
    }
  }

  @IsTest
  static void snapshot_NoDelete_IsEnforced() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Account acc = makeAccount('Titular FXS-5');
      AXF_OBJ_FinancialTransaction__c ftx = makeFtx(acc, 100, 'USD');
      makeRate('USD', 'BRL', 5.05);

      ALT_CLS_FxConversionService service = new ALT_CLS_FxConversionService();
      ALT_CLS_FxConversionService.ConversionResultDTO result = service.applyConversion(
        input(ftx.Id, 'BRL')
      );

      Exception caught;
      try {
        delete new AXF_OBJ_FxApplicationSnapshot__c(Id = result.snapshotId);
      } catch (Exception e) {
        caught = e;
      }
      Assert.isNotNull(caught, 'Snapshot FX nao pode ser excluido.');
      Assert.isFalse(
        Database.update(
            new AXF_OBJ_FxApplicationSnapshot__c(
              Id = result.snapshotId,
              AXF_FXS_NUM_ReportingAmount__c = 1
            ),
            false
          )
          .isSuccess(),
        'Frozen recognition cannot be edited'
      );
    }
  }
}
