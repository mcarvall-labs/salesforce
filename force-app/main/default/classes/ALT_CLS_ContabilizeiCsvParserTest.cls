@IsTest(isParallel=true)
private class ALT_CLS_ContabilizeiCsvParserTest {
  private static final String HEADER = 'Data;Descricao;Entrada;Saida;Saldo';

  @IsTest
  static void parsesValidRowsAndTracksRunningBalance() {
    String bom = String.fromCharArray(new List<Integer>{ 65279 });
    String csv =
      bom +
      HEADER +
      '\n01/03/2026;Salario;5000,00;;5000,00' +
      '\n02/03/2026;Mercado;;150,50;4849,50';

    ALT_CLS_ContabilizeiCsvParser.ParseResult result = ALT_CLS_ContabilizeiCsvParser.parse(
      csv,
      100
    );

    System.assertEquals(true, result.structureValid);
    System.assertEquals(2, result.totalRows);
    System.assertEquals(2, result.validRows);
    System.assertEquals(0, result.rejectedRows);
    System.assertEquals(
      Date.newInstance(2026, 3, 1),
      Date.valueOf(result.sample[0].parsedDate)
    );
    System.assertEquals(5000.00, result.sample[0].balance);
  }

  @IsTest
  static void rejectsRowWhenBalanceNotConserved() {
    String csv =
      HEADER +
      '\n01/03/2026;Salario;5000,00;;5000,00' +
      '\n02/03/2026;Mercado;;150,50;5000,00';

    ALT_CLS_ContabilizeiCsvParser.ParseResult result = ALT_CLS_ContabilizeiCsvParser.parse(
      csv,
      100
    );

    System.assertEquals(1, result.validRows);
    System.assertEquals(1, result.rejectedRows);
    System.assert(
      result.rejections[0].errorCodes.contains('BALANCE_NOT_CONSERVED')
    );
  }

  @IsTest
  static void rejectsInvalidDateAndAmount() {
    String csv =
      HEADER +
      '\ndata-invalida;Descricao;abc;;100,00' +
      '\n01/03/2026;Descricao;;;100,00';

    ALT_CLS_ContabilizeiCsvParser.ParseResult result = ALT_CLS_ContabilizeiCsvParser.parse(
      csv,
      100
    );

    System.assertEquals(2, result.rejectedRows);
    System.assert(result.rejections[0].errorCodes.contains('INVALID_DATE'));
    System.assert(result.rejections[0].errorCodes.contains('INVALID_AMOUNT'));
    System.assert(result.rejections[1].errorCodes.contains('MISSING_AMOUNT'));
  }

  @IsTest
  static void blocksUnsupportedStructure() {
    String csv = 'ColunaA;ColunaB\nx;y';

    ALT_CLS_ContabilizeiCsvParser.ParseResult result = ALT_CLS_ContabilizeiCsvParser.parse(
      csv,
      100
    );

    System.assertEquals(false, result.structureValid);
    System.assert(result.structureErrorCodes.contains('UNSUPPORTED_STRUCTURE'));
  }

  @IsTest
  static void blocksEmptyFile() {
    ALT_CLS_ContabilizeiCsvParser.ParseResult result = ALT_CLS_ContabilizeiCsvParser.parse(
      '',
      100
    );

    System.assertEquals(false, result.structureValid);
    System.assert(result.structureErrorCodes.contains('EMPTY_FILE'));
  }

  @IsTest
  static void blocksRowLimitExceeded() {
    String csv =
      HEADER +
      '\n01/03/2026;Salario;5000,00;;5000,00' +
      '\n02/03/2026;Mercado;;150,50;4849,50';

    ALT_CLS_ContabilizeiCsvParser.ParseResult result = ALT_CLS_ContabilizeiCsvParser.parse(
      csv,
      1
    );

    System.assertEquals(false, result.structureValid);
    System.assert(result.structureErrorCodes.contains('ROW_LIMIT_EXCEEDED'));
  }

  @IsTest
  static void tolerantOfNonBreakingSpacesAndAlternateDelimiter() {
    String nbsp = String.fromCharArray(new List<Integer>{ 160 });
    // comma-delimited variant; amounts kept integral so the comma delimiter
    // is not ambiguous with a Brazilian decimal comma in this fixture.
    String csv =
      'Data,Descricao,Entrada,Saida,Saldo' +
      '\n01/03/2026,Salario' +
      nbsp +
      'mensal,5000,0,5000';

    ALT_CLS_ContabilizeiCsvParser.ParseResult result = ALT_CLS_ContabilizeiCsvParser.parse(
      csv,
      100
    );

    System.assertEquals(true, result.structureValid);
    System.assertEquals(1, result.validRows);
    System.assertEquals('Salario mensal', result.sample[0].description);
  }

  @IsTest
  static void neutralizesFormulaPrefixedDescription() {
    String csv = HEADER + '\n01/03/2026;=CMD|/c calc|;5000,00;;5000,00';

    ALT_CLS_ContabilizeiCsvParser.ParseResult result = ALT_CLS_ContabilizeiCsvParser.parse(
      csv,
      100
    );

    System.assert(result.sample[0].description.startsWith('\'='));
  }

  @IsTest
  static void parseBrDecimalHandlesThousandsAndNegative() {
    System.assertEquals(
      1234.56,
      ALT_CLS_ContabilizeiCsvParser.parseBrDecimal('1.234,56')
    );
    System.assertEquals(
      -50.00,
      ALT_CLS_ContabilizeiCsvParser.parseBrDecimal('-50,00')
    );
    System.assertEquals(
      null,
      ALT_CLS_ContabilizeiCsvParser.parseBrDecimal('abc')
    );
  }

  @IsTest
  static void parseBrDateRejectsMalformedInput() {
    System.assertEquals(
      Date.newInstance(2026, 3, 1),
      ALT_CLS_ContabilizeiCsvParser.parseBrDate('01/03/2026')
    );
    System.assertEquals(
      null,
      ALT_CLS_ContabilizeiCsvParser.parseBrDate('2026-03-01')
    );
    System.assertEquals(null, ALT_CLS_ContabilizeiCsvParser.parseBrDate(null));
  }
}
