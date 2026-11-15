/**
 * @description Reads the CSV layout of an institution from AXF_CsvImportLayout__mdt: the layout of
 * the institution (COMPE code) when there is one, otherwise the default (no institution). Headers
 * are compared without case or accents.
 */
public with sharing class ALT_CLS_CsvImportLayout {
  public class Layout {
    public Set<String> dateHeaders;
    public Set<String> descriptionHeaders;
    public Set<String> valueHeaders;
    public Set<String> entryHeaders;
    public Set<String> exitHeaders;
    public List<String> keyHeaders;
  }

  @TestVisible
  private static List<AXF_CsvImportLayout__mdt> layoutsForTests;

  public static Layout forInstitution(String institution) {
    AXF_CsvImportLayout__mdt chosen;
    AXF_CsvImportLayout__mdt fallback;
    for (
      AXF_CsvImportLayout__mdt candidate : layoutsForTests != null
        ? layoutsForTests
        : AXF_CsvImportLayout__mdt.getAll().values()
    ) {
      if (String.isBlank(candidate.AXF_CIL_TXT_Institution__c)) {
        fallback = candidate;
      } else if (candidate.AXF_CIL_TXT_Institution__c == institution) {
        chosen = candidate;
      }
    }
    AXF_CsvImportLayout__mdt source = chosen != null ? chosen : fallback;
    if (source == null) {
      throw new ALT_CLS_StatementImport.ImportException(
        'Nenhum layout de importação CSV configurado.'
      );
    }
    Layout layout = new Layout();
    layout.dateHeaders = headers(source.AXF_CIL_TXT_DateHeaders__c);
    layout.descriptionHeaders = headers(
      source.AXF_CIL_TXT_DescriptionHeaders__c
    );
    layout.valueHeaders = headers(source.AXF_CIL_TXT_ValueHeaders__c);
    layout.entryHeaders = headers(source.AXF_CIL_TXT_EntryHeaders__c);
    layout.exitHeaders = headers(source.AXF_CIL_TXT_ExitHeaders__c);
    layout.keyHeaders = orderedHeaders(source.AXF_CIL_TAL_KeyHeaders__c);
    if (
      layout.dateHeaders.isEmpty() ||
      layout.descriptionHeaders.isEmpty() ||
      layout.keyHeaders.isEmpty() ||
      (layout.valueHeaders.isEmpty() &&
      (layout.entryHeaders.isEmpty() || layout.exitHeaders.isEmpty()))
    ) {
      throw new ALT_CLS_StatementImport.ImportException(
        'O layout de importação CSV está incompleto: ' + source.DeveloperName
      );
    }
    return layout;
  }

  public static String normalizeHeader(String header) {
    return header == null
      ? ''
      : header.trim()
          .toLowerCase()
          .replace('ç', 'c')
          .replace('ã', 'a')
          .replace('á', 'a')
          .replace('â', 'a')
          .replace('é', 'e')
          .replace('ê', 'e')
          .replace('í', 'i')
          .replace('ó', 'o')
          .replace('ô', 'o')
          .replace('õ', 'o')
          .replace('ú', 'u');
  }

  private static Set<String> headers(String commaSeparated) {
    return new Set<String>(orderedHeaders(commaSeparated));
  }

  // Declared order, without repeats: the order of the key headers is part of the dedupe key.
  private static List<String> orderedHeaders(String commaSeparated) {
    List<String> ordered = new List<String>();
    Set<String> seen = new Set<String>();
    if (commaSeparated != null) {
      for (String header : commaSeparated.split(',')) {
        String normalized = normalizeHeader(header);
        if (!String.isBlank(header) && seen.add(normalized)) {
          ordered.add(normalized);
        }
      }
    }
    return ordered;
  }
}
