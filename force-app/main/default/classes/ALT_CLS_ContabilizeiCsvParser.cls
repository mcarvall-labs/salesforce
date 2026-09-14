/**
 * AXF-14 Contabilizei.bank entry point, kept for callers that import the original format by
 * name. Since AXF-72 the parsing rules live in ALT_CLS_CsvFormatParser and the format itself
 * is the AXF_CMT_CsvFormat__mdt record `Contabilizei_Bank`; this facade only resolves that
 * record and delegates, so PARSER_VERSION stays the value recorded on published facts.
 */
public inherited sharing class ALT_CLS_ContabilizeiCsvParser {
  public static final String PARSER_VERSION = 'contabilizei-bank-csv@1.0.0';

  public static ALT_CLS_CsvFormatParser.ParseResult parse(
    String rawCsv,
    Integer maxRows
  ) {
    return parse(rawCsv, maxRows, null);
  }

  public static ALT_CLS_CsvFormatParser.ParseResult parse(
    String rawCsv,
    Integer maxRows,
    Integer sampleLimit
  ) {
    return ALT_CLS_CsvFormatParser.parse(
      rawCsv,
      maxRows,
      sampleLimit,
      ALT_CLS_CsvFormatRegistry.resolve(
        ALT_CLS_CsvFormatRegistry.CONTABILIZEI_BANK
      )
    );
  }
}
