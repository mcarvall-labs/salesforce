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
  }

  public class Preview {
    public List<Line> lines = new List<Line>();
    public Integer newCount = 0;
    public Integer duplicateCount = 0;
    public Integer errorCount = 0;
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
    List<Line> lines = parse(recordId, fileName, content);
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
    return preview;
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

  private List<Line> parse(Id recordId, String fileName, String content) {
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
      lines = parseCsv(recordId, content);
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

  // CSV with the columns date, description and value (header row required; "," or ";").
  // The key hashes record + date + value + description; identical lines of the same file get an
  // ordinal so two equal purchases are both kept and importing the file again changes nothing.
  private List<Line> parseCsv(Id recordId, String content) {
    List<String> rows = content.split('\\r?\\n');
    Integer headerIndex = 0;
    while (headerIndex < rows.size() && String.isBlank(rows[headerIndex])) {
      headerIndex++;
    }
    if (headerIndex == rows.size()) {
      throw new ImportException('O arquivo está vazio.');
    }
    String delimiter = rows[headerIndex].contains(';') ? ';' : ',';
    List<String> header = splitCsv(rows[headerIndex], delimiter);
    Integer dateColumn = column(header, new Set<String>{ 'data' });
    Integer descriptionColumn = column(
      header,
      new Set<String>{ 'descricao', 'historico' }
    );
    Integer valueColumn = column(header, new Set<String>{ 'valor' });
    if (dateColumn < 0 || descriptionColumn < 0 || valueColumn < 0) {
      throw new ImportException(
        'O CSV deve ter as colunas data, descrição e valor.'
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
        line.amount = csvAmount(cells[valueColumn]);
        String signature =
          recordId +
          '|' +
          String.valueOf(line.lineDate) +
          '|' +
          line.amount +
          '|' +
          line.description;
        Integer ordinal = occurrences.containsKey(signature)
          ? occurrences.get(signature) + 1
          : 1;
        occurrences.put(signature, ordinal);
        line.key =
          'CSV:' +
          EncodingUtil.convertToHex(
            Crypto.generateDigest(
              'SHA-256',
              Blob.valueOf(signature + '|' + ordinal)
            )
          );
      } catch (Exception e) {
        line.status = INVALID;
        line.error = 'Linha ' + (i + 1) + ': data ou valor inválido.';
      }
      lines.add(line);
    }
    return lines;
  }

  private Integer column(List<String> header, Set<String> names) {
    for (Integer i = 0; i < header.size(); i++) {
      String name = header[i]
        .trim()
        .toLowerCase()
        .replace('ç', 'c')
        .replace('ã', 'a')
        .replace('ó', 'o')
        .replace('ú', 'u');
      if (names.contains(name)) {
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

  private Date csvDate(String value) {
    if (Pattern.matches('\\d{4}-\\d{2}-\\d{2}.*', value)) {
      return Date.valueOf(value.substring(0, 10));
    }
    List<String> parts = value.split('/');
    return Date.newInstance(
      Integer.valueOf(parts[2]),
      Integer.valueOf(parts[1]),
      Integer.valueOf(parts[0])
    );
  }

  // Accepts 1234.56, 1.234,56 and -R$ 35,50.
  private Decimal csvAmount(String value) {
    String text = value.replace('R$', '').replace(' ', '');
    if (text.contains(',')) {
      text = text.replace('.', '').replace(',', '.');
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
        SELECT RecordType.DeveloperName
        FROM AXF_OBJ_BankAccount__c
        WHERE Id = :recordId
        WITH USER_MODE
      ];
      requireFound(accounts.isEmpty());
      requireManual(accounts[0].RecordType.DeveloperName);
      return new AccountTarget(recordId);
    }
    if (objectName == 'AXF_OBJ_CreditCard__c') {
      List<AXF_OBJ_CreditCard__c> cards = [
        SELECT RecordType.DeveloperName
        FROM AXF_OBJ_CreditCard__c
        WHERE Id = :recordId
        WITH USER_MODE
      ];
      requireFound(cards.isEmpty());
      requireManual(cards[0].RecordType.DeveloperName);
      return new CardTarget(recordId);
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
    public abstract Set<String> existingKeys(Set<String> keys);
    public abstract void save(List<Line> lines);
  }

  private class AccountTarget extends Target {
    private Id accountId;

    AccountTarget(Id accountId) {
      this.accountId = accountId;
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

    CardTarget(Id cardId) {
      this.cardId = cardId;
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
