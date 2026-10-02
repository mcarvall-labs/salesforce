/**
 * @description Imports a bank statement or card invoice file into a manual bank account or credit
 * card. The file is always parsed on the server; the preview marks lines that already exist and
 * the import upserts by an external id derived from the file (OFX: record Id + FITID), so
 * importing the same file again never duplicates transactions.
 */
public with sharing class ALT_CLS_StatementImport {
  public class ImportException extends Exception {
  }

  public class Line {
    public Date lineDate;
    public String description;
    public Decimal amount;
    public String key;
    public String status;
    public String error;
    public String note;
    public String signature;
  }

  public class Preview {
    public List<Line> lines = new List<Line>();
    public Integer newCount = 0;
    public Integer duplicateCount = 0;
    public Integer errorCount = 0;
    public List<String> warnings = new List<String>();
  }

  public class Result {
    public Boolean success = false;
    public String message;
    public Integer imported = 0;
  }

  public static final String NEW_LINE = 'NEW';
  public static final String DUPLICATE = 'DUPLICATE';
  public static final String INVALID = 'ERROR';
  private static final Integer MAX_LINES = 2000;

  public Preview preview(Id recordId, String fileName, String content) {
    Target target = target(recordId);
    List<Line> lines = parse(recordId, fileName, content, target.institution);
    Set<String> keys = new Set<String>();
    for (Line line : lines) {
      if (line.status == null) {
        keys.add(line.key);
      }
    }
    Set<String> existing = target.existingKeys(keys);
    Set<String> seen = new Set<String>();
    Preview preview = new Preview();
    for (Line line : lines) {
      if (line.status == null) {
        line.status = existing.contains(line.key) || !seen.add(line.key)
          ? DUPLICATE
          : NEW_LINE;
      }
      if (line.status == NEW_LINE) {
        preview.newCount++;
      } else if (line.status == DUPLICATE) {
        preview.duplicateCount++;
      } else {
        preview.errorCount++;
      }
      preview.lines.add(line);
    }
    preview.warnings = cutWarnings(target, lines);
    return preview;
  }

  // The first and the last day of the file may have been cut in half: when that day already has
  // a different number of imported transactions than the file brings, say so (warning only).
  private List<String> cutWarnings(Target target, List<Line> lines) {
    Map<Date, Integer> perDay = new Map<Date, Integer>();
    for (Line line : lines) {
      if (line.lineDate != null && line.status != INVALID) {
        perDay.put(
          line.lineDate,
          perDay.containsKey(line.lineDate) ? perDay.get(line.lineDate) + 1 : 1
        );
      }
    }
    List<String> warnings = new List<String>();
    if (perDay.isEmpty()) {
      return warnings;
    }
    List<Date> days = new List<Date>(perDay.keySet());
    days.sort();
    Set<Date> edges = new Set<Date>{ days[0], days[days.size() - 1] };
    for (Date day : edges) {
      Integer imported = target.countOn(day);
      if (imported > 0 && imported != perDay.get(day)) {
        warnings.add(
          'Dia ' +
            formatDay(day) +
            ' (limite do arquivo): já há ' +
            imported +
            ' lançamentos importados e o arquivo traz ' +
            perDay.get(day) +
            '. Confira se o extrato foi cortado no meio do dia.'
        );
      }
    }
    return warnings;
  }

  private String formatDay(Date day) {
    return String.valueOf(day).substring(8, 10) +
      '/' +
      String.valueOf(day).substring(5, 7) +
      '/' +
      day.year();
  }

  public Result importFile(Id recordId, String fileName, String content) {
    Result result = new Result();
    Target target = target(recordId);
    List<Line> fresh = new List<Line>();
    for (Line line : preview(recordId, fileName, content).lines) {
      if (line.status == NEW_LINE) {
        fresh.add(line);
      }
    }
    try {
      target.save(fresh);
    } catch (DmlException e) {
      result.message = 'Nada foi importado: ' + e.getDmlMessage(0);
      return result;
    }
    result.success = true;
    result.imported = fresh.size();
    result.message = 'Importação concluída.';
    return result;
  }

  private List<Line> parse(
    Id recordId,
    String fileName,
    String content,
    String institution
  ) {
    if (String.isBlank(content)) {
      throw new ImportException('O arquivo está vazio.');
    }
    String extension = String.isBlank(fileName)
      ? ''
      : fileName.substringAfterLast('.').toLowerCase();
    List<Line> lines;
    if (extension == 'ofx') {
      lines = parseOfx(recordId, content);
    } else if (extension == 'csv') {
      lines = parseCsv(
        recordId,
        content,
        ALT_CLS_CsvImportLayout.forInstitution(institution)
      );
    } else {
      throw new ImportException(
        'Formato não suportado. Use um arquivo OFX ou CSV.'
      );
    }
    if (lines.isEmpty()) {
      throw new ImportException('Nenhuma transação encontrada no arquivo.');
    }
    if (lines.size() > MAX_LINES) {
      throw new ImportException(
        'O arquivo tem mais de ' + MAX_LINES + ' transações.'
      );
    }
    return lines;
  }

  // OFX 1.x is SGML (tags often unclosed), so values are read up to the next tag or line break.
  private List<Line> parseOfx(Id recordId, String content) {
    List<Line> lines = new List<Line>();
    List<String> blocks = content.split('(?i)<STMTTRN>');
    for (Integer i = 1; i < blocks.size(); i++) {
      String block = blocks[i].substringBefore('</STMTTRN>');
      Line line = new Line();
      line.description = String.isBlank(tag(block, 'MEMO'))
        ? tag(block, 'NAME')
        : tag(block, 'MEMO');
      String fitId = tag(block, 'FITID');
      String posted = tag(block, 'DTPOSTED');
      String rawAmount = tag(block, 'TRNAMT');
      try {
        line.lineDate = Date.newInstance(
          Integer.valueOf(posted.substring(0, 4)),
          Integer.valueOf(posted.substring(4, 6)),
          Integer.valueOf(posted.substring(6, 8))
        );
        line.amount = Decimal.valueOf(rawAmount.replace(',', '.'));
      } catch (Exception e) {
        line.status = INVALID;
        line.error = 'Linha ' + i + ': data ou valor inválido.';
      }
      if (String.isBlank(fitId)) {
        line.status = INVALID;
        line.error = 'Linha ' + i + ': FITID ausente.';
      } else {
        line.key = 'OFX:' + recordId + ':' + fitId;
      }
      lines.add(line);
    }
    return lines;
  }

  // CSV laid out by the institution layout (AXF_CsvImportLayout__mdt): date, description and a
  // value column, or entrada and saida (value = entrada - saida; "-" or empty counts as zero in
  // one of them). Header row required; "," or ";". The dedupe key hashes the account plus the
  // layout's key headers (normalized: ISO date, signed amount with two decimals, upper-case text
  // without extra spaces); other columns stay out of it. Identical lines of the same file get an
  // ordinal so two equal purchases are both kept and importing the file again changes nothing.
  private List<Line> parseCsv(
    Id recordId,
    String content,
    ALT_CLS_CsvImportLayout.Layout layout
  ) {
    List<String> rows = content.replace('\uFEFF', '').split('\\r?\\n');
    Integer headerIndex = 0;
    while (headerIndex < rows.size() && String.isBlank(rows[headerIndex])) {
      headerIndex++;
    }
    if (headerIndex == rows.size()) {
      throw new ImportException('O arquivo está vazio.');
    }
    String delimiter = rows[headerIndex].contains(';') ? ';' : ',';
    List<String> header = splitCsv(rows[headerIndex], delimiter);
    Integer dateColumn = column(header, layout.dateHeaders);
    Integer descriptionColumn = column(header, layout.descriptionHeaders);
    Integer valueColumn = column(header, layout.valueHeaders);
    Integer inColumn = column(header, layout.entryHeaders);
    Integer outColumn = column(header, layout.exitHeaders);
    Boolean splitColumns = valueColumn < 0 && inColumn >= 0 && outColumn >= 0;
    if (
      dateColumn < 0 ||
      descriptionColumn < 0 ||
      (valueColumn < 0 && !splitColumns)
    ) {
      throw new ImportException(
        'O CSV deve ter as colunas data, descrição e valor (ou entrada e saída).'
      );
    }
    List<Line> lines = new List<Line>();
    Map<String, Integer> occurrences = new Map<String, Integer>();
    for (Integer i = headerIndex + 1; i < rows.size(); i++) {
      if (String.isBlank(rows[i])) {
        continue;
      }
      List<String> cells = splitCsv(rows[i], delimiter);
      Line line = new Line();
      try {
        line.lineDate = csvDate(cells[dateColumn]);
        line.description = cells[descriptionColumn];
        line.amount = splitColumns
          ? splitAmount(cells[inColumn], cells[outColumn])
          : csvAmount(cells[valueColumn]);
        line.signature = signature(recordId, layout, header, cells, line);
        Integer ordinal = occurrences.containsKey(line.signature)
          ? occurrences.get(line.signature) + 1
          : 1;
        occurrences.put(line.signature, ordinal);
        line.key =
          'CSV:' +
          EncodingUtil.convertToHex(
            Crypto.generateDigest(
              'SHA-256',
              Blob.valueOf(line.signature + '|' + ordinal)
            )
          );
      } catch (ImportException e) {
        line.status = INVALID;
        line.error = 'Linha ' + (i + 1) + ': ' + e.getMessage();
      } catch (Exception e) {
        line.status = INVALID;
        line.error = 'Linha ' + (i + 1) + ': data ou valor inválido.';
      }
      lines.add(line);
    }
    for (Line line : lines) {
      Integer total = line.signature == null
        ? 0
        : occurrences.get(line.signature);
      if (total > 1) {
        line.note = 'Linha idêntica repetida: ' + total + '×';
      }
    }
    return lines;
  }

  // Key headers that are not in the file are skipped; value, entry and exit headers all stand for
  // the one signed amount, which enters once.
  private String signature(
    Id recordId,
    ALT_CLS_CsvImportLayout.Layout layout,
    List<String> header,
    List<String> cells,
    Line line
  ) {
    List<String> parts = new List<String>{ String.valueOf(recordId) };
    Boolean amountAdded = false;
    for (String keyHeader : layout.keyHeaders) {
      if (layout.dateHeaders.contains(keyHeader)) {
        parts.add(String.valueOf(line.lineDate));
      } else if (
        layout.valueHeaders.contains(keyHeader) ||
        layout.entryHeaders.contains(keyHeader) ||
        layout.exitHeaders.contains(keyHeader)
      ) {
        if (!amountAdded) {
          parts.add(line.amount.setScale(2).toPlainString());
          amountAdded = true;
        }
      } else if (layout.descriptionHeaders.contains(keyHeader)) {
        parts.add(normalizedText(line.description));
      } else {
        Integer index = column(header, new Set<String>{ keyHeader });
        if (index >= 0) {
          parts.add(normalizedText(cells[index]));
        }
      }
    }
    return String.join(parts, '|');
  }

  private String normalizedText(String value) {
    return value == null
      ? ''
      : value.replace('\u00A0', ' ')
          .trim()
          .replaceAll('\\s+', ' ')
          .toUpperCase();
  }

  // Entrada is money in, saida is money out (always written positive): value = entrada - saida.
  // "-" and empty are empty cells; both empty or both filled is an error for that line.
  private Decimal splitAmount(String entry, String outflow) {
    Boolean hasEntry = !isEmptyCell(entry);
    Boolean hasExit = !isEmptyCell(outflow);
    if (!hasEntry && !hasExit) {
      throw new ImportException('Entrada e saída vazias.');
    }
    if (hasEntry && hasExit) {
      throw new ImportException('Entrada e saída preenchidas ao mesmo tempo.');
    }
    return hasEntry ? csvAmount(entry) : -csvAmount(outflow);
  }

  private Boolean isEmptyCell(String value) {
    String text = value == null ? '' : value.replace('\u00A0', ' ').trim();
    return text == '' || text == '-';
  }

  private Integer column(List<String> header, Set<String> names) {
    for (Integer i = 0; i < header.size(); i++) {
      if (names.contains(ALT_CLS_CsvImportLayout.normalizeHeader(header[i]))) {
        return i;
      }
    }
    return -1;
  }

  private List<String> splitCsv(String row, String delimiter) {
    List<String> cells = new List<String>();
    String current = '';
    Boolean quoted = false;
    for (Integer i = 0; i < row.length(); i++) {
      String character = row.substring(i, i + 1);
      if (character == '"') {
        quoted = !quoted;
      } else if (character == delimiter && !quoted) {
        cells.add(current.trim());
        current = '';
      } else {
        current += character;
      }
    }
    cells.add(current.trim());
    return cells;
  }

  // dd/MM/yyyy or yyyy-MM-dd[Thh:mm...]; impossible dates (31/02) and short years are errors.
  private Date csvDate(String value) {
    Integer year;
    Integer month;
    Integer day;
    if (Pattern.matches('\\d{4}-\\d{2}-\\d{2}.*', value)) {
      year = Integer.valueOf(value.substring(0, 4));
      month = Integer.valueOf(value.substring(5, 7));
      day = Integer.valueOf(value.substring(8, 10));
    } else if (Pattern.matches('\\d{1,2}/\\d{1,2}/\\d{4}', value)) {
      List<String> parts = value.split('/');
      day = Integer.valueOf(parts[0]);
      month = Integer.valueOf(parts[1]);
      year = Integer.valueOf(parts[2]);
    } else {
      throw new ImportException('Data inválida: ' + value);
    }
    Date parsed = Date.newInstance(year, month, day);
    if (parsed.month() != month || parsed.day() != day) {
      throw new ImportException('Data inexistente: ' + value);
    }
    return parsed;
  }

  // Accepts 1234.56, 1,234.56, 1.234,56, 35,50 and -R$ 35,50. A lone separator followed by
  // exactly three digits (1.234 / 1,234) is ambiguous between decimal and thousands and is
  // rejected so a wrong amount is never imported silently.
  private Decimal csvAmount(String value) {
    String text = value
      .replace('\u00A0', '')
      .replace('R$', '')
      .replace(' ', '');
    Boolean hasDot = text.contains('.');
    Boolean hasComma = text.contains(',');
    if (hasDot && hasComma) {
      Boolean commaIsDecimal = text.lastIndexOf(',') > text.lastIndexOf('.');
      text = commaIsDecimal
        ? text.replace('.', '').replace(',', '.')
        : text.replace(',', '');
    } else if (hasComma || hasDot) {
      String separator = hasComma ? ',' : '.';
      if (Pattern.matches('-?\\d{1,3}(\\' + separator + '\\d{3})+', text)) {
        throw new ImportException(
          'Valor ambíguo (milhar ou decimal): ' + value
        );
      }
      text = hasComma ? text.replace(',', '.') : text;
    }
    return Decimal.valueOf(text);
  }

  private String tag(String block, String name) {
    Matcher matcher = Pattern.compile('(?i)<' + name + '>([^<\\r\\n]*)')
      .matcher(block);
    return matcher.find() ? matcher.group(1).trim() : null;
  }

  private Target target(Id recordId) {
    if (recordId == null) {
      throw new ImportException('Informe a conta ou o cartão.');
    }
    String objectName = recordId.getSObjectType().getDescribe().getName();
    if (objectName == 'AXF_OBJ_BankAccount__c') {
      List<AXF_OBJ_BankAccount__c> accounts = [
        SELECT RecordType.DeveloperName, AXF_BA_PKL_Institution__c
        FROM AXF_OBJ_BankAccount__c
        WHERE Id = :recordId
        WITH USER_MODE
      ];
      requireFound(accounts.isEmpty());
      requireManual(accounts[0].RecordType.DeveloperName);
      return new AccountTarget(recordId, accounts[0].AXF_BA_PKL_Institution__c);
    }
    if (objectName == 'AXF_OBJ_CreditCard__c') {
      List<AXF_OBJ_CreditCard__c> cards = [
        SELECT RecordType.DeveloperName, AXF_CC_PKL_Institution__c
        FROM AXF_OBJ_CreditCard__c
        WHERE Id = :recordId
        WITH USER_MODE
      ];
      requireFound(cards.isEmpty());
      requireManual(cards[0].RecordType.DeveloperName);
      return new CardTarget(recordId, cards[0].AXF_CC_PKL_Institution__c);
    }
    throw new ImportException('Importação disponível só para conta ou cartão.');
  }

  // Only AXF_Manual records accept imports; Pluggy ones are synced, and a record without a
  // record type or that cannot be read is refused rather than assumed manual.
  private static void requireFound(Boolean missing) {
    if (missing) {
      throw new ImportException('Conta ou cartão não encontrado.');
    }
  }

  @TestVisible
  private static Boolean enforceRecordType = true;

  @TestVisible
  private static void requireManual(String recordTypeName) {
    if (enforceRecordType && recordTypeName != 'AXF_Manual') {
      throw new ImportException(
        'A importação vale só para conta ou cartão manual; os do Pluggy são sincronizados.'
      );
    }
  }

  private abstract class Target {
    public String institution;
    public abstract Set<String> existingKeys(Set<String> keys);
    public abstract Integer countOn(Date day);
    public abstract void save(List<Line> lines);
  }

  private class AccountTarget extends Target {
    private Id accountId;

    AccountTarget(Id accountId, String institution) {
      this.accountId = accountId;
      this.institution = institution;
    }

    public override Integer countOn(Date day) {
      return [
        SELECT COUNT()
        FROM AXF_OBJ_BankAccountTransaction__c
        WHERE
          AXF_BAT_MD_BankAccount__c = :accountId
          AND AXF_BAT_DAT_Date__c = :day
        WITH USER_MODE
      ];
    }

    public override Set<String> existingKeys(Set<String> keys) {
      Set<String> found = new Set<String>();
      for (AXF_OBJ_BankAccountTransaction__c existing : [
        SELECT AXF_BAT_EXI_PluggyTransactionId__c
        FROM AXF_OBJ_BankAccountTransaction__c
        WHERE AXF_BAT_EXI_PluggyTransactionId__c IN :keys
        WITH USER_MODE
      ]) {
        found.add(existing.AXF_BAT_EXI_PluggyTransactionId__c);
      }
      return found;
    }

    public override void save(List<Line> lines) {
      List<AXF_OBJ_BankAccountTransaction__c> records = new List<AXF_OBJ_BankAccountTransaction__c>();
      for (Line line : lines) {
        records.add(
          new AXF_OBJ_BankAccountTransaction__c(
            AXF_BAT_MD_BankAccount__c = accountId,
            AXF_BAT_EXI_PluggyTransactionId__c = line.key,
            AXF_BAT_DAT_Date__c = line.lineDate,
            AXF_BAT_TXT_Description__c = line.description,
            AXF_BAT_CUR_Amount__c = line.amount
          )
        );
      }
      insert as user records;
    }
  }

  private class CardTarget extends Target {
    private Id cardId;

    CardTarget(Id cardId, String institution) {
      this.cardId = cardId;
      this.institution = institution;
    }

    public override Integer countOn(Date day) {
      return [
        SELECT COUNT()
        FROM AXF_OBJ_CreditCardTransaction__c
        WHERE AXF_CCT_MD_CreditCard__c = :cardId AND AXF_CCT_DAT_Date__c = :day
        WITH USER_MODE
      ];
    }

    public override Set<String> existingKeys(Set<String> keys) {
      Set<String> found = new Set<String>();
      for (AXF_OBJ_CreditCardTransaction__c existing : [
        SELECT AXF_CCT_EXI_PluggyTransactionId__c
        FROM AXF_OBJ_CreditCardTransaction__c
        WHERE AXF_CCT_EXI_PluggyTransactionId__c IN :keys
        WITH USER_MODE
      ]) {
        found.add(existing.AXF_CCT_EXI_PluggyTransactionId__c);
      }
      return found;
    }

    public override void save(List<Line> lines) {
      List<AXF_OBJ_CreditCardTransaction__c> records = new List<AXF_OBJ_CreditCardTransaction__c>();
      for (Line line : lines) {
        records.add(
          new AXF_OBJ_CreditCardTransaction__c(
            AXF_CCT_MD_CreditCard__c = cardId,
            AXF_CCT_EXI_PluggyTransactionId__c = line.key,
            AXF_CCT_DAT_Date__c = line.lineDate,
            AXF_CCT_TXT_Description__c = line.description,
            AXF_CCT_CUR_Amount__c = line.amount
          )
        );
      }
      insert as user records;
    }
  }
}
