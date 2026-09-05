/** AXF-14 thin controller: upload + preview a Contabilizei.bank CSV. Never publishes facts (AXF-15). */
public with sharing class AXF_CLS_CTRL_CsvImportPreview {
  public class PolicyView {
    @AuraEnabled
    public String allowedExtensions;
    @AuraEnabled
    public String requiredEncoding;
    @AuraEnabled
    public Long maxFileSizeBytes;
    @AuraEnabled
    public Integer maxRows;
    @AuraEnabled
    public Integer maxProcessingSeconds;
  }

  public class PreviewInput {
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String fileName;
    @AuraEnabled
    public String base64Content;
  }

  public class PreviewResult {
    @AuraEnabled
    public String outcome;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public String targetAccountLabel;
    @AuraEnabled
    public ALT_CLS_ContabilizeiCsvParser.ParseResult parseResult;
  }

  private static final String REPLACEMENT_CHAR = String.fromCharArray(
    new List<Integer>{ 65533 }
  );

  @AuraEnabled(cacheable=true)
  public static PolicyView getPolicy() {
    AXF_CsvImportPolicy__mdt policy = AXF_CsvImportPolicy__mdt.getInstance(
      'Default'
    );
    if (policy == null) {
      throw new AuraHandledException(
        'Limite de importação de CSV não configurado. Peça ao Gestor Financeiro para configurar antes de tentar novamente.'
      );
    }
    PolicyView view = new PolicyView();
    view.allowedExtensions = policy.AXF_CIP_TXT_AllowedExtensions__c;
    view.requiredEncoding = policy.AXF_CIP_TXT_RequiredEncoding__c;
    view.maxFileSizeBytes = policy.AXF_CIP_NUM_MaxFileSizeBytes__c == null
      ? null
      : policy.AXF_CIP_NUM_MaxFileSizeBytes__c.longValue();
    view.maxRows = policy.AXF_CIP_NUM_MaxRows__c == null
      ? null
      : Integer.valueOf(policy.AXF_CIP_NUM_MaxRows__c);
    view.maxProcessingSeconds = policy.AXF_CIP_NUM_MaxProcessingSeconds__c ==
      null
      ? null
      : Integer.valueOf(policy.AXF_CIP_NUM_MaxProcessingSeconds__c);
    return view;
  }

  @AuraEnabled
  public static PreviewResult previewCsv(PreviewInput input) {
    AXF_CsvImportPolicy__mdt policy = AXF_CsvImportPolicy__mdt.getInstance(
      'Default'
    );
    if (policy == null) {
      return outcome(
        'POLICY_MISSING',
        'Limite de importação de CSV não configurado. Peça ao Gestor Financeiro para configurar antes de tentar novamente.'
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

    String fileName = input.fileName == null
      ? ''
      : input.fileName.toLowerCase();
    String allowedExtension = String.isBlank(
        policy.AXF_CIP_TXT_AllowedExtensions__c
      )
      ? ''
      : '.' + policy.AXF_CIP_TXT_AllowedExtensions__c.toLowerCase();
    if (
      String.isBlank(allowedExtension) || !fileName.endsWith(allowedExtension)
    ) {
      return outcome(
        'INVALID_FILE',
        'Formato de arquivo não suportado. Envie um arquivo .' +
          policy.AXF_CIP_TXT_AllowedExtensions__c +
          '.'
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

    List<AXF_OBJ_BankAccount__c> accounts = [
      SELECT
        Id,
        Name,
        AXF_BA_TXT_InstitutionName__c,
        AXF_BA_PKL_AvailabilityState__c
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

    String rawCsv = content.toString();
    if (rawCsv.contains(REPLACEMENT_CHAR)) {
      return outcome('INVALID_FILE', 'Arquivo não está em UTF-8 válido.');
    }

    ALT_CLS_ContabilizeiCsvParser.ParseResult parsed = ALT_CLS_ContabilizeiCsvParser.parse(
      rawCsv,
      policy.AXF_CIP_NUM_MaxRows__c == null
        ? null
        : Integer.valueOf(policy.AXF_CIP_NUM_MaxRows__c)
    );

    PreviewResult out = new PreviewResult();
    out.parseResult = parsed;
    if (!parsed.structureValid) {
      out.outcome = 'INVALID_FILE';
      out.message = 'Arquivo não segue a estrutura esperada do CSV Contabilizei.bank.';
      return out;
    }
    out.outcome = 'OK';
    out.targetAccountLabel = String.isBlank(
        accounts[0].AXF_BA_TXT_InstitutionName__c
      )
      ? accounts[0].Name
      : accounts[0].AXF_BA_TXT_InstitutionName__c + ' · ' + accounts[0].Name;
    out.message = 'Prévia gerada. Nenhum lançamento foi publicado.';
    return out;
  }

  private static PreviewResult outcome(String outcomeCode, String message) {
    PreviewResult out = new PreviewResult();
    out.outcome = outcomeCode;
    out.message = message;
    return out;
  }
}
