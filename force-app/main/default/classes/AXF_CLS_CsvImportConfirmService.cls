/**
 * AXF-15 — one-time confirmation of a reviewed Contabilizei.bank CSV batch.
 * Re-validates on the server, publishes one immutable `AXF_OBJ_BankAccountTransaction__c`
 * per approved CSV identity (SHA-256 of the normalized row), idempotently: a re-submitted
 * file upserts on the source key and never duplicates. Rejected rows never publish; a DML
 * failure publishes nothing (logical batch atomicity, AC3).
 */
public with sharing class AXF_CLS_CsvImportConfirmService {
  @TestVisible
  private static Boolean accountAccessOverride;

  public class ConfirmInput {
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String fileName;
    @AuraEnabled
    public String base64Content;
    @AuraEnabled
    public String expectedParserVersion;
    @AuraEnabled
    public Boolean acknowledgeRejections;
  }

  public class ConfirmResult {
    @AuraEnabled
    public String outcome;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Integer publishedCount = 0;
    @AuraEnabled
    public Integer alreadyPresentCount = 0;
    @AuraEnabled
    public Integer rejectedCount = 0;
    @AuraEnabled
    public String firstDate;
    @AuraEnabled
    public String lastDate;
    @AuraEnabled
    public String correlationId;
    @AuraEnabled
    public String evidenceDocumentId;
  }

  public ConfirmResult confirm(ConfirmInput input) {
    AXF_CsvImportPolicy__mdt policy = AXF_CsvImportPolicy__mdt.getInstance(
      'Default'
    );
    if (policy == null) {
      return outcome(
        'POLICY_MISSING',
        'Limite de importação de CSV não configurado. Peça ao Gestor Financeiro para configurar.'
      );
    }
    if (
      input == null ||
      input.accountId == null ||
      String.isBlank(input.base64Content)
    ) {
      return outcome(
        'INVALID_FILE',
        'Selecione um arquivo CSV válido para continuar.'
      );
    }

    Blob content;
    try {
      content = EncodingUtil.base64Decode(input.base64Content);
    } catch (Exception e) {
      return outcome('INVALID_FILE', 'Não foi possível ler o arquivo enviado.');
    }
    if (
      policy.AXF_CIP_NUM_MaxFileSizeBytes__c != null &&
      content.size() > policy.AXF_CIP_NUM_MaxFileSizeBytes__c
    ) {
      return outcome(
        'INVALID_FILE',
        'Arquivo excede o tamanho máximo permitido.'
      );
    }

    // AC1 / AC7 — re-validate the target account on the server at confirm time.
    List<AXF_OBJ_BankAccount__c> accounts = [
      SELECT
        Id,
        Name,
        AXF_BA_PKL_AvailabilityState__c,
        AXF_BA_TXT_CurrencyIsoCode__c
      FROM AXF_OBJ_BankAccount__c
      WHERE Id = :input.accountId
      WITH USER_MODE
    ];
    if (
      accounts.isEmpty() ||
      accounts[0].AXF_BA_PKL_AvailabilityState__c != 'AVAILABLE'
    ) {
      return outcome(
        'ACCOUNT_NOT_FOUND',
        'Conta não encontrada ou indisponível para importação.'
      );
    }
    AXF_OBJ_BankAccount__c account = accounts[0];
    if (!hasCreateAccess()) {
      return outcome(
        'FORBIDDEN',
        'Você não tem permissão para publicar lançamentos nesta conta.'
      );
    }

    String rawCsv = content.toString();
    ALT_CLS_ContabilizeiCsvParser.ParseResult parsed = ALT_CLS_ContabilizeiCsvParser.parse(
      rawCsv,
      policy.AXF_CIP_NUM_MaxRows__c == null
        ? null
        : Integer.valueOf(policy.AXF_CIP_NUM_MaxRows__c),
      2000000000
    );
    if (!parsed.structureValid) {
      return outcome(
        'INVALID_FILE',
        'Arquivo não segue a estrutura esperada do CSV Contabilizei.bank.'
      );
    }

    // AC1 — the reviewed preview must match what is being committed.
    if (
      String.isNotBlank(input.expectedParserVersion) &&
      input.expectedParserVersion != parsed.parserVersion
    ) {
      return outcome(
        'STALE_PREVIEW',
        'O arquivo mudou desde a revisão. Gere a prévia novamente antes de confirmar.'
      );
    }

    ConfirmResult result = new ConfirmResult();
    result.rejectedCount = parsed.rejectedRows;
    if (parsed.rejectedRows > 0 && input.acknowledgeRejections != true) {
      result.outcome = 'NEEDS_ACKNOWLEDGE';
      result.message =
        parsed.rejectedRows +
        ' linha(s) serão ignoradas. Confirme que está ciente para publicar as demais.';
      return result;
    }

    List<ALT_CLS_ContabilizeiCsvParser.RowResult> validRows = new List<ALT_CLS_ContabilizeiCsvParser.RowResult>();
    for (ALT_CLS_ContabilizeiCsvParser.RowResult row : parsed.sample) {
      if (row.valid) {
        validRows.add(row);
      }
    }
    if (validRows.isEmpty()) {
      result.outcome = 'NOTHING_TO_PUBLISH';
      result.message = 'Nenhuma linha válida para publicar.';
      return result;
    }

    String correlationId =
      'csv-' +
      EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 24);
    String currencyIso = String.isBlank(account.AXF_BA_TXT_CurrencyIsoCode__c)
      ? 'BRL'
      : account.AXF_BA_TXT_CurrencyIsoCode__c;
    Datetime now = Datetime.now();
    Map<String, ALT_CLS_ContabilizeiCsvParser.RowResult> rowByKey = new Map<String, ALT_CLS_ContabilizeiCsvParser.RowResult>();
    Map<String, String> normDescByKey = new Map<String, String>();
    Date firstDate;
    Date lastDate;
    for (ALT_CLS_ContabilizeiCsvParser.RowResult row : validRows) {
      Date effective = Date.valueOf(row.parsedDate);
      String normalizedDesc = AXF_CLS_TextNormalization.normalize(
        row.description
      );
      String key = rowSourceKey(
        effective,
        normalizedDesc,
        row.inflow,
        row.outflow,
        row.balance,
        account.Id
      );
      rowByKey.put(key, row);
      normDescByKey.put(key, normalizedDesc);
      if (firstDate == null || effective < firstDate) {
        firstDate = effective;
      }
      if (lastDate == null || effective > lastDate) {
        lastDate = effective;
      }
    }

    Set<String> preExisting = new Set<String>();
    for (AXF_OBJ_BankAccountTransaction__c existing : [
      SELECT AXF_BAT_EXI_SourceKey__c
      FROM AXF_OBJ_BankAccountTransaction__c
      WHERE AXF_BAT_EXI_SourceKey__c IN :rowByKey.keySet()
      WITH SYSTEM_MODE
    ]) {
      preExisting.add(existing.AXF_BAT_EXI_SourceKey__c);
    }

    // AC3 — evidence + facts commit together or not at all.
    Savepoint sp = Database.setSavepoint();
    Id evidenceDocId;
    try {
      evidenceDocId = storeEvidence(input.fileName, content, account.Id);
      List<AXF_OBJ_BankAccountTransaction__c> toUpsert = new List<AXF_OBJ_BankAccountTransaction__c>();
      for (String key : rowByKey.keySet()) {
        ALT_CLS_ContabilizeiCsvParser.RowResult row = rowByKey.get(key);
        Boolean isCredit = row.inflow != null && row.inflow > 0;
        Decimal signed = isCredit ? row.inflow : row.outflow;
        toUpsert.add(
          new AXF_OBJ_BankAccountTransaction__c(
            AXF_BAT_MDR_BankAccount__c = account.Id,
            AXF_BAT_EXI_SourceKey__c = key,
            AXF_BAT_PKL_Source__c = 'CSV',
            AXF_BAT_DAT_Date__c = Date.valueOf(row.parsedDate),
            AXF_BAT_NUM_Magnitude__c = (signed == null ? 0 : signed)
              .setScale(2),
            AXF_BAT_PKL_Direction__c = isCredit ? 'CREDIT' : 'DEBIT',
            AXF_BAT_NUM_RunningBalance__c = row.balance == null
              ? null
              : row.balance.setScale(2),
            AXF_BAT_TXT_CurrencyIsoCode__c = currencyIso,
            AXF_BAT_TXT_Description__c = clip(row.description, 255),
            AXF_BAT_TXT_NormalizedDescription__c = clip(
              normDescByKey.get(key),
              255
            ),
            AXF_BAT_TXT_EvidenceRef__c = evidenceDocId,
            AXF_BAT_TXT_CorrelationId__c = correlationId,
            AXF_BAT_TXT_ParserVersion__c = parsed.parserVersion,
            AXF_BAT_DTM_ImportedAt__c = now,
            AXF_BAT_NUM_Version__c = 0
          )
        );
      }
      Database.upsert(
        toUpsert,
        AXF_OBJ_BankAccountTransaction__c.AXF_BAT_EXI_SourceKey__c,
        true
      );
    } catch (Exception e) {
      Database.rollback(sp);
      return outcome(
        'FAILED',
        'Nenhum lançamento foi importado — a gravação falhou. Corrija o arquivo e tente novamente.'
      );
    }

    result.outcome = 'PUBLISHED';
    result.publishedCount = rowByKey.size() - preExisting.size();
    result.alreadyPresentCount = preExisting.size();
    result.firstDate = String.valueOf(firstDate);
    result.lastDate = String.valueOf(lastDate);
    result.correlationId = correlationId;
    result.evidenceDocumentId = evidenceDocId;
    result.message = result.publishedCount == 0
      ? 'Lote já importado anteriormente — nada foi duplicado (' +
        result.alreadyPresentCount +
        ' lançamentos).'
      : result.publishedCount +
        ' lançamento(s) publicado(s). ' +
        result.alreadyPresentCount +
        ' já existiam.';
    return result;
  }

  private static String rowSourceKey(
    Date effective,
    String normalizedDesc,
    Decimal inflow,
    Decimal outflow,
    Decimal balance,
    Id accountId
  ) {
    String material =
      frame(String.valueOf(effective)) +
      frame(normalizedDesc == null ? '' : normalizedDesc) +
      frame(scaled(inflow)) +
      frame(scaled(outflow)) +
      frame(scaled(balance)) +
      frame(String.valueOf(accountId));
    return EncodingUtil.convertToHex(
      Crypto.generateDigest('SHA-256', Blob.valueOf(material))
    );
  }

  private static String scaled(Decimal value) {
    return value == null ? '' : value.setScale(2).toPlainString();
  }

  private static String frame(String s) {
    String v = s == null ? '' : s;
    return v.length() + ':' + v;
  }

  private static String clip(String s, Integer max) {
    if (s == null) {
      return null;
    }
    return s.length() > max ? s.substring(0, max) : s;
  }

  private static Boolean hasCreateAccess() {
    if (accountAccessOverride != null) {
      return accountAccessOverride;
    }
    return Schema.SObjectType.AXF_OBJ_BankAccountTransaction__c.isCreateable();
  }

  private static Id storeEvidence(String fileName, Blob content, Id linkedTo) {
    String safeName = String.isBlank(fileName) ? 'extrato.csv' : fileName;
    ContentVersion cv = new ContentVersion(
      Title = safeName,
      PathOnClient = safeName,
      VersionData = content
    );
    insert cv;
    Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id]
    .ContentDocumentId;
    insert new ContentDocumentLink(
      ContentDocumentId = docId,
      LinkedEntityId = linkedTo,
      ShareType = 'V',
      Visibility = 'AllUsers'
    );
    return docId;
  }

  private static ConfirmResult outcome(String code, String message) {
    ConfirmResult r = new ConfirmResult();
    r.outcome = code;
    r.message = message;
    return r;
  }
}
