/**
 * AXF-14 stateless parser for the Contabilizei.bank CSV export.
 * No SOQL/DML; pure text-in, DTO-out so it can be reused by AXF-15 confirmation
 * without re-deriving parsing rules. Header contract assumed (Data, Descricao,
 * Entrada, Saida, Saldo) is not backed by a sample file in the canonical docs;
 * flagged for confirmation before AXF-15 locks publication on it.
 */
public inherited sharing class ALT_CLS_ContabilizeiCsvParser {
  public static final String PARSER_VERSION = 'contabilizei-bank-csv@1.0.0';

  private static final Integer SAMPLE_LIMIT = 20;
  private static final Pattern FORMULA_PREFIX = Pattern.compile(
    '^[=+\\-@\t\r]'
  );
  private static final String NBSP = String.fromCharArray(
    new List<Integer>{ 160 }
  );

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
    public String parserVersion = PARSER_VERSION;
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

  public static ParseResult parse(String rawCsv, Integer maxRows) {
    ParseResult result = new ParseResult();
    if (String.isBlank(rawCsv)) {
      result.structureErrorCodes.add('EMPTY_FILE');
      return result;
    }
    List<String> lines = splitLines(stripBom(rawCsv));
    if (lines.isEmpty() || String.isBlank(lines[0])) {
      result.structureErrorCodes.add('EMPTY_FILE');
      return result;
    }
    String delimiter = detectDelimiter(lines[0]);
    Map<String, Integer> headerIndex = indexHeader(
      splitRow(lines[0], delimiter)
    );
    if (!hasRequiredColumns(headerIndex)) {
      result.structureErrorCodes.add('UNSUPPORTED_STRUCTURE');
      return result;
    }

    Integer dataLineCount = 0;
    for (Integer i = 1; i < lines.size(); i++) {
      if (String.isNotBlank(lines[i]))
        dataLineCount++;
    }
    if (maxRows != null && dataLineCount > maxRows) {
      result.structureErrorCodes.add('ROW_LIMIT_EXCEEDED');
      return result;
    }

    result.structureValid = true;
    Decimal runningBalance = null;
    for (Integer i = 1; i < lines.size(); i++) {
      String line = lines[i];
      if (String.isBlank(line))
        continue;
      RowResult row = parseRow(line, delimiter, headerIndex, i + 1);
      if (row.valid && runningBalance != null && row.balance != null) {
        Decimal expected = (runningBalance +
          coalesce(row.inflow) -
          coalesce(row.outflow))
          .setScale(2);
        if (row.balance.setScale(2) != expected) {
          row.valid = false;
          row.errorCodes.add('BALANCE_NOT_CONSERVED');
        }
      }
      if (row.balance != null)
        runningBalance = row.balance;
      result.totalRows++;
      if (row.valid) {
        result.validRows++;
      } else {
        result.rejectedRows++;
        if (result.rejections.size() < SAMPLE_LIMIT)
          result.rejections.add(row);
      }
      if (result.sample.size() < SAMPLE_LIMIT)
        result.sample.add(row);
    }
    return result;
  }

  private static RowResult parseRow(
    String line,
    String delimiter,
    Map<String, Integer> headerIndex,
    Integer lineNumber
  ) {
    RowResult row = new RowResult();
    row.lineNumber = lineNumber;
    List<String> cells = splitRow(line, delimiter);

    row.rawDate = cellAt(cells, headerIndex.get('data'));
    row.description = neutralizeFormula(
      cellAt(cells, headerIndex.get('descricao'))
    );
    String entradaRaw = cellAt(cells, headerIndex.get('entrada'));
    String saidaRaw = cellAt(cells, headerIndex.get('saida'));
    String saldoRaw = cellAt(cells, headerIndex.get('saldo'));

    Date parsed = parseBrDate(row.rawDate);
    if (parsed == null) {
      row.valid = false;
      row.errorCodes.add('INVALID_DATE');
    } else {
      row.parsedDate = String.valueOf(parsed);
    }

    if (String.isNotBlank(entradaRaw)) {
      row.inflow = parseBrDecimal(entradaRaw);
      if (row.inflow == null) {
        row.valid = false;
        row.errorCodes.add('INVALID_AMOUNT');
      }
    }
    if (String.isNotBlank(saidaRaw)) {
      row.outflow = parseBrDecimal(saidaRaw);
      if (row.outflow == null) {
        row.valid = false;
        row.errorCodes.add('INVALID_AMOUNT');
      }
    }
    if (row.inflow == null && row.outflow == null) {
      row.valid = false;
      row.errorCodes.add('MISSING_AMOUNT');
    }
    if (String.isBlank(saldoRaw)) {
      row.valid = false;
      row.errorCodes.add('MISSING_BALANCE');
    } else {
      row.balance = parseBrDecimal(saldoRaw);
      if (row.balance == null) {
        row.valid = false;
        row.errorCodes.add('INVALID_BALANCE');
      }
    }
    return row;
  }

  private static Decimal coalesce(Decimal value) {
    return value == null ? 0 : value;
  }

  private static String cellAt(List<String> cells, Integer index) {
    if (index == null || index >= cells.size())
      return null;
    return stripNbsp(cells[index]).trim();
  }

  private static final String BOM = String.fromCharArray(
    new List<Integer>{ 65279 }
  );

  private static String stripBom(String content) {
    return content.startsWith(BOM) ? content.substring(1) : content;
  }

  private static String stripNbsp(String value) {
    return value == null ? null : value.replace(NBSP, ' ');
  }

  private static List<String> splitLines(String content) {
    List<String> raw = content.replace('\r\n', '\n')
      .replace('\r', '\n')
      .split('\n');
    List<String> lines = new List<String>();
    for (String line : raw) {
      lines.add(line);
    }
    while (!lines.isEmpty() && String.isBlank(lines[lines.size() - 1])) {
      lines.remove(lines.size() - 1);
    }
    return lines;
  }

  private static String detectDelimiter(String headerLine) {
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

  private static String normalizeHeaderCell(String value) {
    if (value == null)
      return null;
    String v = stripNbsp(value).trim().toLowerCase();
    for (String accented : ACCENT_MAP.keySet()) {
      v = v.replace(accented, ACCENT_MAP.get(accented));
    }
    return v;
  }

  private static Boolean hasRequiredColumns(Map<String, Integer> headerIndex) {
    return headerIndex.containsKey('data') &&
      headerIndex.containsKey('entrada') &&
      headerIndex.containsKey('saida') &&
      headerIndex.containsKey('saldo');
  }

  @TestVisible
  private static Date parseBrDate(String raw) {
    if (String.isBlank(raw))
      return null;
    List<String> parts = raw.split('/');
    if (parts.size() != 3)
      return null;
    try {
      Integer day = Integer.valueOf(parts[0]);
      Integer month = Integer.valueOf(parts[1]);
      Integer year = Integer.valueOf(parts[2]);
      if (year < 100)
        year += 2000;
      if (month < 1 || month > 12 || day < 1 || day > 31)
        return null;
      return Date.newInstance(year, month, day);
    } catch (Exception e) {
      return null;
    }
  }

  @TestVisible
  private static Decimal parseBrDecimal(String raw) {
    if (String.isBlank(raw))
      return null;
    String v = raw.trim();
    Boolean negative = v.startsWith('-');
    if (negative)
      v = v.substring(1);
    v = v.replace('.', '').replace(',', '.');
    if (!Pattern.matches('^\\d+(\\.\\d+)?$', v))
      return null;
    try {
      Decimal value = Decimal.valueOf(v);
      return negative ? value * -1 : value;
    } catch (Exception e) {
      return null;
    }
  }

  @TestVisible
  private static String neutralizeFormula(String value) {
    if (String.isBlank(value))
      return value;
    return FORMULA_PREFIX.matcher(value).find() ? '\'' + value : value;
  }
}
