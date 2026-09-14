/**
 * AXF-72 registry of versioned CSV formats backed by AXF_CMT_CsvFormat__mdt. Adding a format of
 * the BANK_STATEMENT_V1 family is a metadata-only change; a format whose family the parser does
 * not implement is exposed as BLOCKED and never parsed. No default is invented when a format is
 * missing.
 */
public inherited sharing class ALT_CLS_CsvFormatRegistry {
  public static final String CONTABILIZEI_BANK = 'Contabilizei_Bank';
  public static final Set<String> SUPPORTED_FAMILIES = new Set<String>{
    ALT_CLS_CsvFormatParser.FAMILY_BANK_STATEMENT_V1
  };

  @TestVisible
  private static List<AXF_CMT_CsvFormat__mdt> recordsOverride;

  public class FormatView {
    @AuraEnabled
    public String formatKey;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String family;
    @AuraEnabled
    public String parserVersion;
    @AuraEnabled
    public Boolean blocked;
  }

  /** Active formats for selection; unsupported families are listed as blocked, never hidden. */
  public static List<FormatView> listActive() {
    List<FormatView> result = new List<FormatView>();
    for (AXF_CMT_CsvFormat__mdt record : records()) {
      if (record.AXF_CSF_BOL_Active__c != true) {
        continue;
      }
      FormatView view = new FormatView();
      view.formatKey = record.DeveloperName;
      view.label = record.MasterLabel;
      view.family = record.AXF_CSF_PKL_Family__c;
      view.parserVersion = record.AXF_CSF_TXT_ParserVersion__c;
      view.blocked = !SUPPORTED_FAMILIES.contains(record.AXF_CSF_PKL_Family__c);
      result.add(view);
    }
    return result;
  }

  /** @return the format definition, or null when the key is unknown or inactive. */
  public static ALT_CLS_CsvFormatParser.Format resolve(String formatKey) {
    String key = String.isBlank(formatKey) ? CONTABILIZEI_BANK : formatKey;
    for (AXF_CMT_CsvFormat__mdt record : records()) {
      if (record.DeveloperName == key && record.AXF_CSF_BOL_Active__c == true) {
        return toFormat(record);
      }
    }
    return null;
  }

  public static Boolean isSupported(ALT_CLS_CsvFormatParser.Format format) {
    return format != null && SUPPORTED_FAMILIES.contains(format.family);
  }

  private static List<AXF_CMT_CsvFormat__mdt> records() {
    if (recordsOverride != null) {
      return recordsOverride;
    }
    return [
      SELECT
        DeveloperName,
        MasterLabel,
        AXF_CSF_PKL_Family__c,
        AXF_CSF_TXT_ParserVersion__c,
        AXF_CSF_BOL_Active__c,
        AXF_CSF_TXT_DateColumn__c,
        AXF_CSF_TXT_DescriptionColumn__c,
        AXF_CSF_TXT_InflowColumn__c,
        AXF_CSF_TXT_OutflowColumn__c,
        AXF_CSF_TXT_AmountColumn__c,
        AXF_CSF_TXT_BalanceColumn__c,
        AXF_CSF_BOL_BalanceRequired__c,
        AXF_CSF_PKL_DateFormat__c,
        AXF_CSF_PKL_DecimalFormat__c,
        AXF_CSF_PKL_Delimiter__c,
        AXF_CSF_TXT_Encoding__c,
        AXF_CSF_NUM_SkipLines__c,
        AXF_CSF_TXT_InstitutionBankNumber__c
      FROM AXF_CMT_CsvFormat__mdt
      ORDER BY MasterLabel
    ];
  }

  private static ALT_CLS_CsvFormatParser.Format toFormat(
    AXF_CMT_CsvFormat__mdt record
  ) {
    ALT_CLS_CsvFormatParser.Format format = new ALT_CLS_CsvFormatParser.Format();
    format.formatKey = record.DeveloperName;
    format.label = record.MasterLabel;
    format.family = record.AXF_CSF_PKL_Family__c;
    format.parserVersion = record.AXF_CSF_TXT_ParserVersion__c;
    format.active = record.AXF_CSF_BOL_Active__c == true;
    format.dateColumn = record.AXF_CSF_TXT_DateColumn__c;
    format.descriptionColumn = record.AXF_CSF_TXT_DescriptionColumn__c;
    format.inflowColumn = record.AXF_CSF_TXT_InflowColumn__c;
    format.outflowColumn = record.AXF_CSF_TXT_OutflowColumn__c;
    format.amountColumn = record.AXF_CSF_TXT_AmountColumn__c;
    format.balanceColumn = record.AXF_CSF_TXT_BalanceColumn__c;
    format.balanceRequired = record.AXF_CSF_BOL_BalanceRequired__c == true;
    format.dateFormat = record.AXF_CSF_PKL_DateFormat__c;
    format.decimalFormat = record.AXF_CSF_PKL_DecimalFormat__c;
    format.delimiter = record.AXF_CSF_PKL_Delimiter__c;
    format.encoding = record.AXF_CSF_TXT_Encoding__c;
    format.skipLines = record.AXF_CSF_NUM_SkipLines__c == null
      ? 0
      : Integer.valueOf(record.AXF_CSF_NUM_SkipLines__c);
    format.institutionBankNumber = record.AXF_CSF_TXT_InstitutionBankNumber__c;
    return format;
  }
}
