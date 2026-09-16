/**
 * AXF-72: a versioned CSV format of the supported family is added by metadata only and reuses
 * the existing preview/staging/confirmation pipeline; unsupported families stay BLOCKED; the
 * institution rule (AXF-106) is verified against the shared directory; parser and
 * normalization versions are recorded.
 */
@IsTest
private class ALT_CLS_CsvFormatParserTest {
  private static AXF_CMT_CsvFormat__mdt record(
    String key,
    String family,
    String parserVersion,
    Boolean active
  ) {
    return new AXF_CMT_CsvFormat__mdt(
      DeveloperName = key,
      MasterLabel = key.replace('_', ' '),
      AXF_CSF_PKL_Family__c = family,
      AXF_CSF_TXT_ParserVersion__c = parserVersion,
      AXF_CSF_BOL_Active__c = active,
      AXF_CSF_TXT_DateColumn__c = 'date',
      AXF_CSF_TXT_DescriptionColumn__c = 'memo',
      AXF_CSF_TXT_AmountColumn__c = 'amount',
      AXF_CSF_BOL_BalanceRequired__c = false,
      AXF_CSF_PKL_DateFormat__c = 'YMD_DASH',
      AXF_CSF_PKL_DecimalFormat__c = 'EN',
      AXF_CSF_PKL_Delimiter__c = 'COMMA',
      AXF_CSF_TXT_Encoding__c = 'UTF-8',
      AXF_CSF_NUM_SkipLines__c = 1
    );
  }

  private static AXF_CMT_CsvFormat__mdt contabilizei() {
    return new AXF_CMT_CsvFormat__mdt(
      DeveloperName = ALT_CLS_CsvFormatRegistry.CONTABILIZEI_BANK,
      MasterLabel = 'Contabilizei.bank',
      AXF_CSF_PKL_Family__c = ALT_CLS_CsvFormatParser.FAMILY_BANK_STATEMENT_V1,
      AXF_CSF_TXT_ParserVersion__c = ALT_CLS_ContabilizeiCsvParser.PARSER_VERSION,
      AXF_CSF_BOL_Active__c = true,
      AXF_CSF_TXT_DateColumn__c = 'data',
      AXF_CSF_TXT_DescriptionColumn__c = 'descricao',
      AXF_CSF_TXT_InflowColumn__c = 'entrada',
      AXF_CSF_TXT_OutflowColumn__c = 'saida',
      AXF_CSF_TXT_BalanceColumn__c = 'saldo',
      AXF_CSF_BOL_BalanceRequired__c = true,
      AXF_CSF_PKL_DateFormat__c = 'DMY_SLASH',
      AXF_CSF_PKL_DecimalFormat__c = 'BR',
      AXF_CSF_PKL_Delimiter__c = 'AUTO',
      AXF_CSF_TXT_Encoding__c = 'UTF-8',
      AXF_CSF_NUM_SkipLines__c = 0
    );
  }

  @IsTest
  static void shippedContabilizeiFormatIsResolvedFromMetadata() {
    ALT_CLS_CsvFormatParser.Format format = ALT_CLS_CsvFormatRegistry.resolve(
      null
    );
    Assert.isNotNull(
      format,
      'Registro Contabilizei_Bank entregue com o build.'
    );
    Assert.areEqual(
      ALT_CLS_ContabilizeiCsvParser.PARSER_VERSION,
      format.parserVersion
    );
    Assert.isTrue(ALT_CLS_CsvFormatRegistry.isSupported(format));
    ALT_CLS_CsvFormatParser.ParseResult result = ALT_CLS_ContabilizeiCsvParser.parse(
      'Data;Descricao;Entrada;Saida;Saldo\n01/03/2026;Salario;5.000,00;;5.000,00',
      100
    );
    Assert.isTrue(result.structureValid);
    Assert.areEqual(1, result.validRows);
    Assert.areEqual(
      ALT_CLS_CsvFormatRegistry.CONTABILIZEI_BANK,
      result.formatKey
    );
    Assert.areEqual(
      ALT_CLS_CsvFormatParser.NORMALIZATION_VERSION,
      result.normalizationVersion
    );
  }

  @IsTest
  static void metadataOnlyFormatOfSupportedFamilyParsesWithoutCode() {
    ALT_CLS_CsvFormatRegistry.recordsOverride = new List<AXF_CMT_CsvFormat__mdt>{
      contabilizei(),
      record('Other_Bank', 'BANK_STATEMENT_V1', 'other-bank-csv@2.1.0', true)
    };
    ALT_CLS_CsvFormatParser.Format format = ALT_CLS_CsvFormatRegistry.resolve(
      'Other_Bank'
    );
    String csv =
      'Statement export - ignore me\n' +
      'Date,Memo,Amount\n' +
      '2026-03-01,Payroll,"1,250.50"\n' +
      '2026-03-02,=SUM(A1),-40.25\n' +
      '2026-03-03,Bad date 03/2026,10\n' +
      '03/04/2026,Wrong format,10\n' +
      '2026-03-05,Blank amount,\n' +
      '2026-03-06,Zero movement,0\n' +
      '2026-02-31,Day overflow,5\n' +
      '2026-03-07,"Quoted, with ""inner"" quotes",7.5\n';

    Test.startTest();
    ALT_CLS_CsvFormatParser.ParseResult result = ALT_CLS_CsvFormatParser.parse(
      csv,
      100,
      format
    );
    Test.stopTest();

    Assert.isTrue(
      result.structureValid,
      String.join(result.structureErrorCodes, ',')
    );
    Assert.areEqual('other-bank-csv@2.1.0', result.parserVersion);
    Assert.areEqual(8, result.totalRows);
    Assert.areEqual(4, result.validRows);
    Assert.areEqual(4, result.rejectedRows);
    Assert.areEqual(
      1250.50,
      result.sample[0].inflow,
      'Celula com aspas e separador de milhar.'
    );
    ALT_CLS_CsvFormatParser.RowResult quotedRow;
    for (ALT_CLS_CsvFormatParser.RowResult candidate : result.sample) {
      if (candidate.lineNumber == 10) {
        quotedRow = candidate;
      }
    }
    Assert.isNotNull(quotedRow, 'Linha com aspas e valida.');
    Assert.areEqual('Quoted, with "inner" quotes', quotedRow.description);
    Assert.areEqual(7.5, quotedRow.inflow);
    Assert.isTrue(
      result.rejections[2].errorCodes.contains('MISSING_AMOUNT'),
      'Zero nao e movimento.'
    );
    Assert.isTrue(
      result.rejections[3].errorCodes.contains('INVALID_DATE'),
      '31/02 nao transborda.'
    );
    Assert.isNull(result.sample[0].outflow);
    Assert.isNull(result.sample[0].balance, 'Saldo nao exigido pelo formato.');
    Assert.areEqual(
      40.25,
      result.sample[1].outflow,
      'Valor assinado negativo = saida.'
    );
    Assert.isTrue(
      result.sample[1].description.startsWith('\''),
      'Conteudo ativo neutralizado.'
    );
    Assert.isTrue(result.rejections[0].errorCodes.contains('INVALID_DATE'));
    Assert.isTrue(result.rejections[1].errorCodes.contains('MISSING_AMOUNT'));
    Assert.areEqual(
      Date.newInstance(2026, 3, 1),
      ALT_CLS_CsvFormatParser.parseDate('03/01/2026', 'MDY_SLASH')
    );
    Assert.areEqual(
      Date.newInstance(2026, 3, 1),
      ALT_CLS_CsvFormatParser.parseDate('01-03-2026', 'DMY_DASH')
    );
    Assert.areEqual(
      1234.5,
      ALT_CLS_CsvFormatParser.parseDecimal('1234.5', 'PLAIN')
    );
    Assert.isNull(ALT_CLS_CsvFormatParser.parseDecimal('12.3.4', 'EN'));
  }

  @IsTest
  static void unsupportedFamilyMissingOrInvalidDefinitionStaysBlocked() {
    AXF_CMT_CsvFormat__mdt invalid = record(
      'Broken_Format',
      'BANK_STATEMENT_V1',
      'broken@1.0.0',
      true
    );
    invalid.AXF_CSF_TXT_AmountColumn__c = null;
    ALT_CLS_CsvFormatRegistry.recordsOverride = new List<AXF_CMT_CsvFormat__mdt>{
      contabilizei(),
      record('Future_Format', 'OFX_V1', 'future@0.1.0', true),
      record('Inactive_Format', 'BANK_STATEMENT_V1', 'inactive@1.0.0', false),
      invalid
    };

    Test.startTest();
    List<ALT_CLS_CsvFormatRegistry.FormatView> listed = ALT_CLS_CsvFormatRegistry.listActive();
    ALT_CLS_CsvFormatParser.Format blocked = ALT_CLS_CsvFormatRegistry.resolve(
      'Future_Format'
    );
    ALT_CLS_CsvFormatParser.ParseResult blockedResult = ALT_CLS_CsvFormatParser.parse(
      'Date,Memo,Amount\n2026-03-01,x,1',
      100,
      blocked
    );
    ALT_CLS_CsvFormatParser.ParseResult missing = ALT_CLS_CsvFormatParser.parse(
      'Date,Memo,Amount\n2026-03-01,x,1',
      100,
      ALT_CLS_CsvFormatRegistry.resolve('Inactive_Format')
    );
    ALT_CLS_CsvFormatParser.ParseResult brokenResult = ALT_CLS_CsvFormatParser.parse(
      'Date,Memo,Amount\n2026-03-01,x,1',
      100,
      ALT_CLS_CsvFormatRegistry.resolve('Broken_Format')
    );
    Test.stopTest();

    Assert.areEqual(3, listed.size(), 'Inativo nao e listado.');
    Map<String, ALT_CLS_CsvFormatRegistry.FormatView> byKey = new Map<String, ALT_CLS_CsvFormatRegistry.FormatView>();
    for (ALT_CLS_CsvFormatRegistry.FormatView view : listed) {
      byKey.put(view.formatKey, view);
    }
    Assert.isTrue(
      byKey.get('Future_Format').blocked,
      'Familia nao implementada aparece como BLOCKED.'
    );
    Assert.areEqual(
      'UNSUPPORTED_FAMILY',
      byKey.get('Future_Format').blockedReason
    );
    Assert.isTrue(
      byKey.get('Broken_Format').blocked,
      'Definicao incompleta e bloqueada na listagem.'
    );
    Assert.areEqual(
      'INVALID_DEFINITION',
      byKey.get('Broken_Format').blockedReason
    );
    Assert.isFalse(
      byKey.get(ALT_CLS_CsvFormatRegistry.CONTABILIZEI_BANK).blocked
    );
    Assert.isFalse(
      ALT_CLS_CsvFormatRegistry.isSupported(
        ALT_CLS_CsvFormatRegistry.resolve('Broken_Format')
      )
    );
    Assert.isFalse(ALT_CLS_CsvFormatRegistry.isSupported(blocked));
    Assert.isFalse(blockedResult.structureValid);
    Assert.isTrue(blockedResult.structureErrorCodes.contains('FORMAT_BLOCKED'));
    Assert.isTrue(missing.structureErrorCodes.contains('FORMAT_MISSING'));
    Assert.isTrue(brokenResult.structureErrorCodes.contains('FORMAT_BLOCKED'));
    Assert.isNull(ALT_CLS_CsvFormatRegistry.resolve('Unknown'));
  }

  @IsTest
  static void previewAndConfirmRefuseBlockedOrMissingFormatsAndInstitutionMismatch() {
    ALT_CLS_CsvFormatRegistry.recordsOverride = new List<AXF_CMT_CsvFormat__mdt>{
      contabilizei(),
      record('Future_Format', 'OFX_V1', 'future@0.1.0', true)
    };
    AXF_CMT_CsvFormat__mdt pinned = contabilizei();
    pinned.DeveloperName = 'Pinned_Bank';
    pinned.AXF_CSF_TXT_InstitutionBankNumber__c = '999';
    ALT_CLS_CsvFormatRegistry.recordsOverride.add(pinned);
    AXF_CMT_CsvFormat__mdt matching = contabilizei();
    matching.DeveloperName = 'Matching_Bank';
    matching.AXF_CSF_TXT_InstitutionBankNumber__c = ' 0123 ';
    ALT_CLS_CsvFormatRegistry.recordsOverride.add(matching);

    Account holder = new Account(
      LastName = 'Titular AXF72',
      RecordTypeId = Account.SObjectType.getDescribe()
        .getRecordTypeInfosByDeveloperName()
        .get('AXF_Person')
        .getRecordTypeId()
    );
    insert holder;
    AXF_OBJ_BankInstitution__c institution = new AXF_OBJ_BankInstitution__c(
      Name = 'Banco Teste',
      AXF_BI_EXI_Bank_Number__c = '123'
    );
    insert institution;
    AXF_OBJ_BankAccount__c bank = new AXF_OBJ_BankAccount__c(
      AXF_BA_LKP_Account__c = holder.Id,
      AXF_BA_LKP_BankInstitution__c = institution.Id,
      AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_BA_TXT_InstitutionName__c = 'Banco Teste',
      AXF_BA_TXT_NumberMasked__c = '****7272',
      AXF_BA_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BA_EXI_ManualKey__c = '72727272-7272-7272-7272-727272727272',
      AXF_BA_NUM_Version__c = 0
    );
    insert bank;
    String csv = EncodingUtil.base64Encode(
      Blob.valueOf(
        'Data;Descricao;Entrada;Saida;Saldo\n01/03/2026;Salario;5.000,00;;5.000,00'
      )
    );

    Test.startTest();
    AXF_CLS_CTRL_CsvImportPreview.PreviewInput input = new AXF_CLS_CTRL_CsvImportPreview.PreviewInput();
    input.accountId = bank.Id;
    input.fileName = 'extrato.csv';
    input.base64Content = csv;
    input.formatKey = 'Future_Format';
    AXF_CLS_CTRL_CsvImportPreview.PreviewResult blockedPreview = AXF_CLS_CTRL_CsvImportPreview.previewCsv(
      input
    );
    input.formatKey = 'Unknown';
    AXF_CLS_CTRL_CsvImportPreview.PreviewResult missingPreview = AXF_CLS_CTRL_CsvImportPreview.previewCsv(
      input
    );
    input.formatKey = 'Pinned_Bank';
    AXF_CLS_CTRL_CsvImportPreview.PreviewResult mismatchPreview = AXF_CLS_CTRL_CsvImportPreview.previewCsv(
      input
    );
    input.formatKey = null;
    AXF_CLS_CTRL_CsvImportPreview.PreviewResult okPreview = AXF_CLS_CTRL_CsvImportPreview.previewCsv(
      input
    );
    input.formatKey = 'Matching_Bank';
    AXF_CLS_CTRL_CsvImportPreview.PreviewResult matchingPreview = AXF_CLS_CTRL_CsvImportPreview.previewCsv(
      input
    );
    AXF_CLS_CsvImportConfirmService.ConfirmResult missingConfirm = AXF_CLS_CTRL_CsvImportPreview.confirmCsv(
      bank.Id,
      'extrato.csv',
      csv,
      null,
      true,
      'Unknown'
    );
    AXF_CLS_CsvImportConfirmService.ConfirmInput staleInput = new AXF_CLS_CsvImportConfirmService.ConfirmInput();
    staleInput.accountId = bank.Id;
    staleInput.fileName = 'extrato.csv';
    staleInput.base64Content = csv;
    staleInput.acknowledgeRejections = true;
    staleInput.formatKey = ALT_CLS_CsvFormatRegistry.CONTABILIZEI_BANK;
    staleInput.expectedFormatKey = 'Matching_Bank';
    AXF_CLS_CsvImportConfirmService.ConfirmResult staleConfirm = new AXF_CLS_CsvImportConfirmService()
      .confirm(staleInput);
    AXF_CLS_CsvImportConfirmService.ConfirmResult blockedConfirm = AXF_CLS_CTRL_CsvImportPreview.confirmCsv(
      bank.Id,
      'extrato.csv',
      csv,
      null,
      true,
      'Future_Format'
    );
    AXF_CLS_CsvImportConfirmService.ConfirmResult mismatchConfirm = AXF_CLS_CTRL_CsvImportPreview.confirmCsv(
      bank.Id,
      'extrato.csv',
      csv,
      null,
      true,
      'Pinned_Bank'
    );
    List<ALT_CLS_CsvFormatRegistry.FormatView> formats = AXF_CLS_CTRL_CsvImportPreview.getFormats();
    Test.stopTest();

    Assert.areEqual('FORMAT_BLOCKED', blockedPreview.outcome);
    Assert.areEqual('FORMAT_MISSING', missingPreview.outcome);
    Assert.areEqual('INSTITUTION_MISMATCH', mismatchPreview.outcome);
    Assert.areEqual('OK', okPreview.outcome, okPreview.message);
    Assert.areEqual(
      ALT_CLS_CsvFormatRegistry.CONTABILIZEI_BANK,
      okPreview.parseResult.formatKey
    );
    Assert.areEqual(
      'OK',
      matchingPreview.outcome,
      'Instituicao fixada igual a da conta (normalizada) passa.'
    );
    Assert.areEqual('FORMAT_BLOCKED', blockedConfirm.outcome);
    Assert.areEqual('INSTITUTION_MISMATCH', mismatchConfirm.outcome);
    Assert.areEqual('FORMAT_MISSING', missingConfirm.outcome);
    Assert.areEqual(
      'STALE_PREVIEW',
      staleConfirm.outcome,
      'Formato revisado difere do confirmado.'
    );
    Assert.areEqual(4, formats.size());
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM AXF_OBJ_BankAccountTransaction__c
        WHERE AXF_BAT_MDR_BankAccount__c = :bank.Id
      ],
      'Nada publicado por formato bloqueado ou instituicao divergente.'
    );
    Assert.isNull(
      AXF_CLS_CsvImportConfirmService.institutionMismatch(
        bank.Id,
        ALT_CLS_CsvFormatRegistry.resolve(null)
      ),
      'Formato sem instituicao fixada nao restringe.'
    );
  }

  @IsTest
  static void explicitDelimitersAutoDetectionAndSkipLinesBeyondFile() {
    AXF_CMT_CsvFormat__mdt pipe = record(
      'Pipe_Bank',
      'BANK_STATEMENT_V1',
      'pipe@1.0.0',
      true
    );
    pipe.AXF_CSF_PKL_Delimiter__c = 'PIPE';
    pipe.AXF_CSF_NUM_SkipLines__c = 0;
    AXF_CMT_CsvFormat__mdt tab = record(
      'Tab_Bank',
      'BANK_STATEMENT_V1',
      'tab@1.0.0',
      true
    );
    tab.AXF_CSF_PKL_Delimiter__c = 'TAB';
    tab.AXF_CSF_NUM_SkipLines__c = 0;
    AXF_CMT_CsvFormat__mdt semi = record(
      'Semi_Bank',
      'BANK_STATEMENT_V1',
      'semi@1.0.0',
      true
    );
    semi.AXF_CSF_PKL_Delimiter__c = 'SEMICOLON';
    semi.AXF_CSF_NUM_SkipLines__c = 0;
    AXF_CMT_CsvFormat__mdt auto = record(
      'Auto_Bank',
      'BANK_STATEMENT_V1',
      'auto@1.0.0',
      true
    );
    auto.AXF_CSF_PKL_Delimiter__c = 'AUTO';
    auto.AXF_CSF_NUM_SkipLines__c = 0;
    AXF_CMT_CsvFormat__mdt deep = record(
      'Deep_Bank',
      'BANK_STATEMENT_V1',
      'deep@1.0.0',
      true
    );
    deep.AXF_CSF_NUM_SkipLines__c = 9;
    ALT_CLS_CsvFormatRegistry.recordsOverride = new List<AXF_CMT_CsvFormat__mdt>{
      contabilizei(),
      pipe,
      tab,
      semi,
      auto,
      deep
    };

    Test.startTest();
    ALT_CLS_CsvFormatParser.ParseResult piped = ALT_CLS_CsvFormatParser.parse(
      'Date|Memo|Amount\n2026-03-01|Payroll|10',
      100,
      ALT_CLS_CsvFormatRegistry.resolve('Pipe_Bank')
    );
    ALT_CLS_CsvFormatParser.ParseResult tabbed = ALT_CLS_CsvFormatParser.parse(
      'Date\tMemo\tAmount\n2026-03-01\tPayroll\t-20',
      100,
      ALT_CLS_CsvFormatRegistry.resolve('Tab_Bank')
    );
    ALT_CLS_CsvFormatParser.ParseResult semis = ALT_CLS_CsvFormatParser.parse(
      'Date;Memo;Amount\n2026-03-01;Payroll;30',
      100,
      ALT_CLS_CsvFormatRegistry.resolve('Semi_Bank')
    );
    ALT_CLS_CsvFormatParser.ParseResult autoPipe = ALT_CLS_CsvFormatParser.parse(
      'Date|Memo|Amount\n2026-03-01|Payroll, net|40',
      100,
      ALT_CLS_CsvFormatRegistry.resolve('Auto_Bank')
    );
    ALT_CLS_CsvFormatParser.ParseResult tooDeep = ALT_CLS_CsvFormatParser.parse(
      'Date,Memo,Amount\n2026-03-01,Payroll,40',
      100,
      ALT_CLS_CsvFormatRegistry.resolve('Deep_Bank')
    );
    Test.stopTest();

    Assert.isTrue(
      piped.structureValid,
      String.join(piped.structureErrorCodes, ',')
    );
    Assert.areEqual(10, piped.sample[0].inflow);
    Assert.isTrue(
      tabbed.structureValid,
      String.join(tabbed.structureErrorCodes, ',')
    );
    Assert.areEqual(20, tabbed.sample[0].outflow);
    Assert.isTrue(
      semis.structureValid,
      String.join(semis.structureErrorCodes, ',')
    );
    Assert.areEqual(30, semis.sample[0].inflow);
    Assert.isTrue(
      autoPipe.structureValid,
      'AUTO detecta pipe mesmo com virgula no texto.'
    );
    Assert.areEqual('Payroll, net', autoPipe.sample[0].description);
    Assert.isFalse(
      tooDeep.structureValid,
      'skipLines alem do arquivo nao encontra cabecalho.'
    );
    Assert.isTrue(tooDeep.structureErrorCodes.contains('EMPTY_FILE'));
  }

  @IsTest
  static void shippedContabilizeiVersionMatchesTheFacadeConstant() {
    ALT_CLS_CsvFormatParser.Format format = ALT_CLS_CsvFormatRegistry.resolve(
      ALT_CLS_CsvFormatRegistry.CONTABILIZEI_BANK
    );
    Assert.isNotNull(format, 'Registro entregue com o build.');
    Assert.areEqual(
      ALT_CLS_ContabilizeiCsvParser.PARSER_VERSION,
      format.parserVersion,
      'Versao do metadado e a constante da fachada devem coincidir.'
    );
    Assert.areEqual('UTF-8', format.encoding.trim().toUpperCase());
  }
}
