/**
 * AXF-72 format-driven CSV parser for the BANK_STATEMENT_V1 family. Pure text-in, DTO-out
 * (no SOQL/DML); the format (columns, date/decimal formats, delimiter, balance policy and
 * parser version) comes from AXF_CMT_CsvFormat__mdt through ALT_CLS_CsvFormatRegistry, so a
 * new format of the same family is added by metadata only. Parsing rules that need new code
 * are a new family, never a local generalization of an existing one.
 */
public inherited sharing class ALT_CLS_CsvFormatParser {
  public static final String NORMALIZATION_VERSION = 'csv-normalization@1.0.0';
  public static final String FAMILY_BANK_STATEMENT_V1 = 'BANK_STATEMENT_V1';

  private static final Integer SAMPLE_LIMIT = 20;
  private static final Pattern FORMULA_PREFIX = Pattern.compile(
    '^[=+\\-@\t\r]'
  );
  private static final String NBSP = String.fromCharArray(
    new List<Integer>{ 160 }
  );
  private static final String BOM = String.fromCharArray(
    new List<Integer>{ 65279 }
  );

  /** Frozen description of one CSV format (mirror of the custom metadata record). */
  public class Format {
    @AuraEnabled
    public String formatKey;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String family;
    @AuraEnabled
    public String parserVersion;
    @AuraEnabled
    public Boolean active = true;
    public String dateColumn;
    public String descriptionColumn;
    public String inflowColumn;
    public String outflowColumn;
    public String amountColumn;
    public String balanceColumn;
    public Boolean balanceRequired = true;
    public String dateFormat = 'DMY_SLASH';
    public String decimalFormat = 'BR';
    public String delimiter = 'AUTO';
    public String encoding = 'UTF-8';
    public Integer skipLines = 0;
    public String institutionBankNumber;
  }

  public class RowResult {
    @AuraEnabled
    public Integer lineNumber;
    @AuraEnabled
    public String rawDate;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public Decimal inflow;
    @AuraEnabled
    public Decimal outflow;
    @AuraEnabled
    public Decimal balance;
    @AuraEnabled
    public String parsedDate;
    @AuraEnabled
    public Boolean valid = true;
    @AuraEnabled
    public List<String> errorCodes = new List<String>();
  }

  public class ParseResult {
    @AuraEnabled
    public String parserVersion;
    @AuraEnabled
    public String normalizationVersion = NORMALIZATION_VERSION;
    @AuraEnabled
    public String formatKey;
    @AuraEnabled
    public Boolean structureValid = false;
    @AuraEnabled
    public List<String> structureErrorCodes = new List<String>();
    @AuraEnabled
    public Integer totalRows = 0;
    @AuraEnabled
    public Integer validRows = 0;
    @AuraEnabled
    public Integer rejectedRows = 0;
    @AuraEnabled
    public List<RowResult> sample = new List<RowResult>();
    @AuraEnabled
    public List<RowResult> rejections = new List<RowResult>();
  }

  public static ParseResult parse(
    String rawCsv,
    Integer maxRows,
    Format format
  ) {
    return parse(rawCsv, maxRows, SAMPLE_LIMIT, format);
  }

  /**
   * @param sampleLimit cap on how many rows land in `sample` / `rejections`; the preview
   *        passes the default and the confirmation passes a large value.
   */
  public static ParseResult parse(
    String rawCsv,
    Integer maxRows,
    Integer sampleLimit,
    Format format
  ) {
    Integer cap = sampleLimit == null ? SAMPLE_LIMIT : sampleLimit;
    ParseResult result = new ParseResult();
    if (format == null) {
      result.structureErrorCodes.add('FORMAT_MISSING');
      return result;
    }
    result.parserVersion = format.parserVersion;
    result.formatKey = format.formatKey;
    if (
      format.family != FAMILY_BANK_STATEMENT_V1 || !isDefinitionValid(format)
    ) {
      result.structureErrorCodes.add('FORMAT_BLOCKED');
      return result;
    }
    if (String.isBlank(rawCsv)) {
      result.structureErrorCodes.add('EMPTY_FILE');
      return result;
    }
    List<String> lines = splitLines(stripBom(rawCsv));
    Integer headerAt = format.skipLines == null ||
      format.skipLines < 0
      ? 0
      : format.skipLines;
    if (lines.size() <= headerAt || String.isBlank(lines[headerAt])) {
      result.structureErrorCodes.add('EMPTY_FILE');
      return result;
    }
    String delimiter = resolveDelimiter(format.delimiter, lines[headerAt]);
    Map<String, Integer> headerIndex = indexHeader(
      splitRow(lines[headerAt], delimiter)
    );
    if (!hasRequiredColumns(headerIndex, format)) {
      result.structureErrorCodes.add('UNSUPPORTED_STRUCTURE');
      return result;
    }

    Integer dataLineCount = 0;
    for (Integer i = headerAt + 1; i < lines.size(); i++) {
      if (String.isNotBlank(lines[i])) {
        dataLineCount++;
      }
    }
    if (maxRows != null && dataLineCount > maxRows) {
      result.structureErrorCodes.add('ROW_LIMIT_EXCEEDED');
      return result;
    }

    result.structureValid = true;
    Decimal runningBalance = null;
    for (Integer i = headerAt + 1; i < lines.size(); i++) {
      String line = lines[i];
      if (String.isBlank(line)) {
        continue;
      }
      RowResult row = parseRow(line, delimiter, headerIndex, i + 1, format);
      if (
        format.balanceRequired == true &&
        row.valid &&
        runningBalance != null &&
        row.balance != null
      ) {
        Decimal expected = (runningBalance +
          coalesce(row.inflow) -
          coalesce(row.outflow))
          .setScale(2);
        if (row.balance.setScale(2) != expected) {
          row.valid = false;
          row.errorCodes.add('BALANCE_NOT_CONSERVED');
        }
      }
      if (row.balance != null) {
        runningBalance = row.balance;
      }
      result.totalRows++;
      if (row.valid) {
        result.validRows++;
      } else {
        result.rejectedRows++;
        if (result.rejections.size() < cap) {
          result.rejections.add(row);
        }
      }
      if (result.sample.size() < cap) {
        result.sample.add(row);
      }
    }
    return result;
  }

  private static Boolean isDefinitionValid(Format format) {
    Boolean split =
      String.isNotBlank(format.inflowColumn) &&
      String.isNotBlank(format.outflowColumn);
    Boolean single = String.isNotBlank(format.amountColumn);
    return String.isNotBlank(format.dateColumn) &&
      (split || single) &&
      (format.balanceRequired != true ||
      String.isNotBlank(format.balanceColumn)) &&
      String.isNotBlank(format.parserVersion) &&
      (String.isBlank(format.encoding) ||
      format.encoding.toUpperCase() == 'UTF-8');
  }

  private static RowResult parseRow(
    String line,
    String delimiter,
    Map<String, Integer> headerIndex,
    Integer lineNumber,
    Format format
  ) {
    RowResult row = new RowResult();
    row.lineNumber = lineNumber;
    List<String> cells = splitRow(line, delimiter);

    row.rawDate = cellAt(
      cells,
      headerIndex.get(normalizeHeaderCell(format.dateColumn))
    );
    row.description = neutralizeFormula(
      cellAt(
        cells,
        headerIndex.get(normalizeHeaderCell(format.descriptionColumn))
      )
    );

    Date parsed = parseDate(row.rawDate, format.dateFormat);
    if (parsed == null) {
      row.valid = false;
      row.errorCodes.add('INVALID_DATE');
    } else {
      row.parsedDate = String.valueOf(parsed);
    }

    if (String.isNotBlank(format.amountColumn)) {
      String amountRaw = cellAt(
        cells,
        headerIndex.get(normalizeHeaderCell(format.amountColumn))
      );
      if (String.isBlank(amountRaw)) {
        row.valid = false;
        row.errorCodes.add('MISSING_AMOUNT');
      } else {
        Decimal amount = parseDecimal(amountRaw, format.decimalFormat);
        if (amount == null) {
          row.valid = false;
          row.errorCodes.add('INVALID_AMOUNT');
        } else if (amount < 0) {
          row.outflow = amount.abs();
        } else {
          row.inflow = amount;
        }
      }
    } else {
      String inflowRaw = cellAt(
        cells,
        headerIndex.get(normalizeHeaderCell(format.inflowColumn))
      );
      String outflowRaw = cellAt(
        cells,
        headerIndex.get(normalizeHeaderCell(format.outflowColumn))
      );
      if (String.isNotBlank(inflowRaw)) {
        row.inflow = parseDecimal(inflowRaw, format.decimalFormat);
        if (row.inflow == null) {
          row.valid = false;
          row.errorCodes.add('INVALID_AMOUNT');
        }
      }
      if (String.isNotBlank(outflowRaw)) {
        row.outflow = parseDecimal(outflowRaw, format.decimalFormat);
        if (row.outflow == null) {
          row.valid = false;
          row.errorCodes.add('INVALID_AMOUNT');
        }
      }
      if (row.inflow == null && row.outflow == null) {
        row.valid = false;
        row.errorCodes.add('MISSING_AMOUNT');
      }
    }

    if (String.isNotBlank(format.balanceColumn)) {
      String balanceRaw = cellAt(
        cells,
        headerIndex.get(normalizeHeaderCell(format.balanceColumn))
      );
      if (String.isBlank(balanceRaw)) {
        if (format.balanceRequired == true) {
          row.valid = false;
          row.errorCodes.add('MISSING_BALANCE');
        }
      } else {
        row.balance = parseDecimal(balanceRaw, format.decimalFormat);
        if (row.balance == null) {
          row.valid = false;
          row.errorCodes.add('INVALID_BALANCE');
        }
      }
    }
    return row;
  }

  private static Decimal coalesce(Decimal value) {
    return value == null ? 0 : value;
  }

  private static String cellAt(List<String> cells, Integer index) {
    if (index == null || index >= cells.size()) {
      return null;
    }
    return stripNbsp(cells[index]).trim();
  }

  private static String stripBom(String content) {
    return content.startsWith(BOM) ? content.substring(1) : content;
  }

  private static String stripNbsp(String value) {
    return value == null ? null : value.replace(NBSP, ' ');
  }

  private static List<String> splitLines(String content) {
    List<String> lines = new List<String>(
      content.replace('\r\n', '\n').replace('\r', '\n').split('\n')
    );
    while (!lines.isEmpty() && String.isBlank(lines[lines.size() - 1])) {
      lines.remove(lines.size() - 1);
    }
    return lines;
  }

  private static String resolveDelimiter(String configured, String headerLine) {
    String choice = configured == null ? 'AUTO' : configured.toUpperCase();
    if (choice == 'SEMICOLON') {
      return ';';
    }
    if (choice == 'COMMA') {
      return ',';
    }
    if (choice == 'TAB') {
      return '\t';
    }
    if (choice == 'PIPE') {
      return '\\|';
    }
    Integer semicolons = headerLine.countMatches(';');
    Integer commas = headerLine.countMatches(',');
    return semicolons >= commas ? ';' : ',';
  }

  private static List<String> splitRow(String line, String delimiter) {
    return line.split(delimiter, -1);
  }

  private static Map<String, Integer> indexHeader(List<String> header) {
    Map<String, Integer> index = new Map<String, Integer>();
    for (Integer i = 0; i < header.size(); i++) {
      String key = normalizeHeaderCell(header[i]);
      if (String.isNotBlank(key) && !index.containsKey(key)) {
        index.put(key, i);
      }
    }
    return index;
  }

  private static final Map<String, String> ACCENT_MAP = new Map<String, String>{
    'á' => 'a',
    'à' => 'a',
    'â' => 'a',
    'ã' => 'a',
    'é' => 'e',
    'ê' => 'e',
    'í' => 'i',
    'ó' => 'o',
    'ô' => 'o',
    'õ' => 'o',
    'ú' => 'u',
    'ç' => 'c'
  };

  @TestVisible
  private static String normalizeHeaderCell(String value) {
    if (value == null) {
      return null;
    }
    String v = stripNbsp(value).trim().toLowerCase();
    for (String accented : ACCENT_MAP.keySet()) {
      v = v.replace(accented, ACCENT_MAP.get(accented));
    }
    return v;
  }

  private static Boolean hasRequiredColumns(
    Map<String, Integer> headerIndex,
    Format format
  ) {
    if (!headerIndex.containsKey(normalizeHeaderCell(format.dateColumn))) {
      return false;
    }
    if (String.isNotBlank(format.amountColumn)) {
      if (!headerIndex.containsKey(normalizeHeaderCell(format.amountColumn))) {
        return false;
      }
    } else if (
      !headerIndex.containsKey(normalizeHeaderCell(format.inflowColumn)) ||
      !headerIndex.containsKey(normalizeHeaderCell(format.outflowColumn))
    ) {
      return false;
    }
    if (
      format.balanceRequired == true &&
      !headerIndex.containsKey(normalizeHeaderCell(format.balanceColumn))
    ) {
      return false;
    }
    return true;
  }

  @TestVisible
  private static Date parseDate(String raw, String dateFormat) {
    if (String.isBlank(raw)) {
      return null;
    }
    String pattern = dateFormat == null
      ? 'DMY_SLASH'
      : dateFormat.toUpperCase();
    String separator = pattern.endsWith('_DASH') ? '-' : '/';
    List<String> parts = raw.trim().split(separator == '-' ? '-' : '/');
    if (parts.size() != 3) {
      return null;
    }
    try {
      Integer day;
      Integer month;
      Integer year;
      if (pattern.startsWith('YMD')) {
        year = Integer.valueOf(parts[0]);
        month = Integer.valueOf(parts[1]);
        day = Integer.valueOf(parts[2]);
      } else if (pattern.startsWith('MDY')) {
        month = Integer.valueOf(parts[0]);
        day = Integer.valueOf(parts[1]);
        year = Integer.valueOf(parts[2]);
      } else {
        day = Integer.valueOf(parts[0]);
        month = Integer.valueOf(parts[1]);
        year = Integer.valueOf(parts[2]);
      }
      if (year < 100) {
        year += 2000;
      }
      if (month < 1 || month > 12 || day < 1 || day > 31) {
        return null;
      }
      return Date.newInstance(year, month, day);
    } catch (Exception e) {
      return null;
    }
  }

  @TestVisible
  private static Decimal parseDecimal(String raw, String decimalFormat) {
    if (String.isBlank(raw)) {
      return null;
    }
    String v = raw.trim();
    Boolean negative = v.startsWith('-');
    if (negative) {
      v = v.substring(1);
    }
    String style = decimalFormat == null ? 'BR' : decimalFormat.toUpperCase();
    if (style == 'EN') {
      v = v.replace(',', '');
    } else if (style == 'PLAIN') {
      v = v.replace(' ', '');
    } else {
      v = v.replace('.', '').replace(',', '.');
    }
    if (!Pattern.matches('^\\d+(\\.\\d+)?$', v)) {
      return null;
    }
    try {
      Decimal value = Decimal.valueOf(v);
      return negative ? value * -1 : value;
    } catch (Exception e) {
      return null;
    }
  }

  @TestVisible
  private static String neutralizeFormula(String value) {
    if (String.isBlank(value)) {
      return value;
    }
    return FORMULA_PREFIX.matcher(value).find() ? '\'' + value : value;
  }
}
