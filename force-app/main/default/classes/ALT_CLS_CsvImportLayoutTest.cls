@IsTest
private class ALT_CLS_CsvImportLayoutTest {
  private static AXF_CsvImportLayout__mdt layout(
    String institution,
    String key
  ) {
    return new AXF_CsvImportLayout__mdt(
      DeveloperName = 'T' + (institution == null ? 'Default' : institution),
      AXF_CIL_TXT_Institution__c = institution,
      AXF_CIL_TXT_DateHeaders__c = 'Data',
      AXF_CIL_TXT_DescriptionHeaders__c = 'Descrição, Histórico',
      AXF_CIL_TXT_ValueHeaders__c = 'Valor',
      AXF_CIL_TXT_EntryHeaders__c = 'Entrada',
      AXF_CIL_TXT_ExitHeaders__c = 'Saída',
      AXF_CIL_TAL_KeyHeaders__c = key
    );
  }

  @IsTest
  static void institutionLayoutWinsAndDefaultIsTheFallback() {
    ALT_CLS_CsvImportLayout.layoutsForTests = new List<AXF_CsvImportLayout__mdt>{
      layout(null, 'Data, Valor'),
      layout('301', 'Data, Lançamento, Descrição, Entrada, Saída')
    };
    System.assertEquals(
      5,
      ALT_CLS_CsvImportLayout.forInstitution('301').keyHeaders.size()
    );
    System.assertEquals(
      2,
      ALT_CLS_CsvImportLayout.forInstitution('341').keyHeaders.size()
    );
    System.assertEquals(
      2,
      ALT_CLS_CsvImportLayout.forInstitution(null).keyHeaders.size()
    );
    System.assert(
      ALT_CLS_CsvImportLayout.forInstitution('301')
        .descriptionHeaders.contains('historico')
    );
    System.assert(
      ALT_CLS_CsvImportLayout.forInstitution('301')
        .exitHeaders.contains('saida')
    );
  }

  @IsTest
  static void missingOrIncompleteLayoutIsAReadableError() {
    ALT_CLS_CsvImportLayout.layoutsForTests = new List<AXF_CsvImportLayout__mdt>();
    try {
      ALT_CLS_CsvImportLayout.forInstitution('301');
      System.assert(false, 'Expected ImportException');
    } catch (ALT_CLS_StatementImport.ImportException e) {
      System.assert(e.getMessage().contains('Nenhum layout'));
    }
    AXF_CsvImportLayout__mdt broken = layout(null, '');
    ALT_CLS_CsvImportLayout.layoutsForTests = new List<AXF_CsvImportLayout__mdt>{
      broken
    };
    try {
      ALT_CLS_CsvImportLayout.forInstitution('301');
      System.assert(false, 'Expected ImportException');
    } catch (ALT_CLS_StatementImport.ImportException e) {
      System.assert(e.getMessage().contains('incompleto'));
    }
  }

  @IsTest
  static void deployedLayoutsCoverContabilizeiAndTheDefault() {
    ALT_CLS_CsvImportLayout.Layout bank = ALT_CLS_CsvImportLayout.forInstitution(
      '301'
    );
    System.assertEquals(
      new List<String>{ 'data', 'lancamento', 'descricao', 'entrada', 'saida' },
      bank.keyHeaders
    );
    System.assert(
      ALT_CLS_CsvImportLayout.forInstitution('341').keyHeaders.contains('valor')
    );
  }

  @IsTest
  static void normalizeHeaderIgnoresCaseAndAccents() {
    System.assertEquals(
      'lancamento',
      ALT_CLS_CsvImportLayout.normalizeHeader(' Lançamento ')
    );
    System.assertEquals('', ALT_CLS_CsvImportLayout.normalizeHeader(null));
  }

  @IsTest
  static void keyHeadersKeepTheDeclaredOrderWithoutRepeats() {
    ALT_CLS_CsvImportLayout.layoutsForTests = new List<AXF_CsvImportLayout__mdt>{
      layout(null, 'Valor, Data, Descrição, data')
    };
    List<String> keys = ALT_CLS_CsvImportLayout.forInstitution('341')
      .keyHeaders;
    System.assertEquals(new List<String>{ 'valor', 'data', 'descricao' }, keys);
  }
}
