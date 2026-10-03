@IsTest
private class ALT_CLS_StatementImportTest {
  private static final String OFX =
    'OFXHEADER:100\nDATA:OFXSGML\n<OFX><BANKMSGSRSV1><STMTTRNRS><STMTRS><BANKTRANLIST>\n' +
    '<STMTTRN>\n<TRNTYPE>DEBIT\n<DTPOSTED>20260910120000[-3:BRT]\n<TRNAMT>-35.50\n<FITID>A1\n<MEMO>Mercado\n</STMTTRN>\n' +
    '<STMTTRN>\n<TRNTYPE>CREDIT\n<DTPOSTED>20260911\n<TRNAMT>100,00\n<FITID>A2\n<NAME>Pix recebido\n</STMTTRN>\n' +
    '<STMTTRN>\n<TRNTYPE>DEBIT\n<DTPOSTED>20260912\n<TRNAMT>-5\n<MEMO>Sem FITID\n</STMTTRN>\n' +
    '<STMTTRN>\n<DTPOSTED>xx\n<TRNAMT>abc\n<FITID>A4\n</STMTTRN>\n' +
    '</BANKTRANLIST></STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>';

  // Record type visibility cannot be granted by DML in a test, so records are created without
  // one and the manual-only check is exercised directly in dedicated tests.
  static {
    ALT_CLS_StatementImport.enforceRecordType = false;
  }

  @TestSetup
  static void setup() {
    ALT_CLS_SyncTestUser.create(
      'axfim',
      new List<String>{
        'AXF_OBJ_BankAccount__c',
        'AXF_OBJ_BankAccountTransaction__c',
        'AXF_OBJ_CreditCard__c',
        'AXF_OBJ_CreditCardTransaction__c'
      }
    );
  }

  private static Id holder() {
    Account holder = new Account(Name = 'Holder');
    insert holder;
    return holder.Id;
  }

  private static Id manualAccount() {
    AXF_OBJ_BankAccount__c account = new AXF_OBJ_BankAccount__c(
      Name = 'Conta',
      AXF_BA_MD_Holder__c = holder(),
      AXF_BA_PKL_Institution__c = '341',
      AXF_BA_PKL_Type__c = 'Checking'
    );
    insert account;
    return account.Id;
  }

  private static Id manualCard() {
    AXF_OBJ_CreditCard__c card = new AXF_OBJ_CreditCard__c(
      Name = 'Cartão',
      AXF_CC_MD_Holder__c = holder(),
      AXF_CC_PKL_Institution__c = '341'
    );
    insert card;
    return card.Id;
  }

  @IsTest
  static void previewClassifiesLinesAndFlagsDuplicates() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Id accountId = manualAccount();
      insert new AXF_OBJ_BankAccountTransaction__c(
        AXF_BAT_MD_BankAccount__c = accountId,
        AXF_BAT_EXI_PluggyTransactionId__c = 'OFX:' + accountId + ':A1',
        AXF_BAT_DAT_Date__c = Date.newInstance(2026, 9, 10),
        AXF_BAT_CUR_Amount__c = -35.5
      );
      ALT_CLS_StatementImport.Preview preview = new ALT_CLS_StatementImport()
        .preview(accountId, 'extrato.OFX', OFX);
      System.assertEquals(4, preview.lines.size());
      System.assertEquals(1, preview.newCount);
      System.assertEquals(1, preview.duplicateCount);
      System.assertEquals(2, preview.errorCount);
      System.assertEquals(
        ALT_CLS_StatementImport.DUPLICATE,
        preview.lines[0].status
      );
      System.assertEquals(-35.5, preview.lines[0].amount);
      System.assertEquals('Mercado', preview.lines[0].description);
      System.assertEquals(
        Date.newInstance(2026, 9, 11),
        preview.lines[1].lineDate
      );
      System.assertEquals(100, preview.lines[1].amount);
      System.assertEquals('Pix recebido', preview.lines[1].description);
      System.assert(preview.lines[2].error.contains('FITID'));
      System.assert(preview.lines[3].error.contains('inválido'));
    }
  }

  @IsTest
  static void importIsIdempotentAndSkipsInvalidLines() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Id accountId = manualAccount();
      ALT_CLS_StatementImport.Result first = new ALT_CLS_StatementImport()
        .importFile(accountId, 'extrato.ofx', OFX);
      ALT_CLS_StatementImport.Result second = new ALT_CLS_StatementImport()
        .importFile(accountId, 'extrato.ofx', OFX);
      System.assertEquals(true, first.success, first.message);
      System.assertEquals(true, second.success, second.message);
      System.assertEquals(2, first.imported);
      System.assertEquals(
        2,
        [SELECT COUNT() FROM AXF_OBJ_BankAccountTransaction__c]
      );
      System.assertEquals(
        -35.5,
        [
          SELECT AXF_BAT_CUR_Amount__c
          FROM AXF_OBJ_BankAccountTransaction__c
          WHERE
            AXF_BAT_EXI_PluggyTransactionId__c = :('OFX:' + accountId + ':A1')
        ]
        .AXF_BAT_CUR_Amount__c
      );
    }
  }

  @IsTest
  static void importFillsCardTransactions() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Id cardId = manualCard();
      ALT_CLS_StatementImport.Result r = new ALT_CLS_StatementImport()
        .importFile(cardId, 'fatura.ofx', OFX);
      System.assertEquals(true, r.success, r.message);
      System.assertEquals(
        2,
        [SELECT COUNT() FROM AXF_OBJ_CreditCardTransaction__c]
      );
    }
  }

  @IsTest
  static void rejectsInvalidTargetsAndFiles() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Id accountId = manualAccount();
      List<List<Object>> cases = new List<List<Object>>{
        new List<Object>{ accountId, 'a.ofx', ' ' },
        new List<Object>{ accountId, 'a.pdf', OFX },
        new List<Object>{ accountId, 'a.ofx', '<OFX></OFX>' },
        new List<Object>{ null, 'a.ofx', OFX },
        new List<Object>{ holder(), 'a.ofx', OFX }
      };
      for (List<Object> c : cases) {
        try {
          new ALT_CLS_StatementImport()
            .preview((Id) c[0], (String) c[1], (String) c[2]);
          System.assert(false, 'Expected ImportException for ' + c);
        } catch (ALT_CLS_StatementImport.ImportException e) {
          System.assertNotEquals(null, e.getMessage());
        }
      }
    }
  }

  @IsTest
  static void controllerWrapsPreviewImportAndErrors() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Id accountId = manualAccount();
      AXF_CLS_CTRL_StatementImport.PreviewView view = AXF_CLS_CTRL_StatementImport.preview(
        accountId,
        'a.ofx',
        OFX
      );
      System.assertEquals(4, view.lines.size());
      System.assertEquals(2, view.newCount);
      AXF_CLS_CTRL_StatementImport.ImportView imported = AXF_CLS_CTRL_StatementImport.importStatement(
        accountId,
        'a.ofx',
        OFX
      );
      System.assertEquals(true, imported.success);
      System.assertEquals(2, imported.imported);
      try {
        AXF_CLS_CTRL_StatementImport.preview(accountId, 'a.csv', OFX);
        System.assert(false, 'Expected AuraHandledException');
      } catch (AuraHandledException e) {
        System.assertNotEquals(null, e.getMessage());
      }
      try {
        AXF_CLS_CTRL_StatementImport.importStatement(accountId, 'a.csv', OFX);
        System.assert(false, 'Expected AuraHandledException');
      } catch (AuraHandledException e) {
        System.assertNotEquals(null, e.getMessage());
      }
    }
  }

  private static final String CSV =
    'Data;Descrição;Valor\n' +
    '10/09/2026;Mercado;-35,50\n' +
    '2026-09-11;"Pix, recebido";1.234,56\n' +
    '11/09/2026;Café;-5.00\n' +
    '11/09/2026;Café;-5.00\n' +
    '\n' +
    'ontem;Quebrada;abc\n';

  @IsTest
  static void csvPreviewParsesFormatsAndReportsLineErrors() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      ALT_CLS_StatementImport.Preview preview = new ALT_CLS_StatementImport()
        .preview(manualAccount(), 'extrato.csv', CSV);
      System.assertEquals(5, preview.lines.size());
      System.assertEquals(4, preview.newCount);
      System.assertEquals(1, preview.errorCount);
      System.assertEquals(
        Date.newInstance(2026, 9, 10),
        preview.lines[0].lineDate
      );
      System.assertEquals(-35.5, preview.lines[0].amount);
      System.assertEquals('Pix, recebido', preview.lines[1].description);
      System.assertEquals(1234.56, preview.lines[1].amount);
      System.assertEquals(-5, preview.lines[2].amount);
      System.assertNotEquals(preview.lines[2].key, preview.lines[3].key);
      System.assert(preview.lines[4].error.contains('Linha 7'));
    }
  }

  @IsTest
  static void csvImportIsIdempotentIncludingEqualLines() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Id accountId = manualAccount();
      ALT_CLS_StatementImport.Result first = new ALT_CLS_StatementImport()
        .importFile(accountId, 'extrato.csv', CSV);
      ALT_CLS_StatementImport.Result second = new ALT_CLS_StatementImport()
        .importFile(accountId, 'extrato.csv', CSV);
      System.assertEquals(true, first.success, first.message);
      System.assertEquals(true, second.success, second.message);
      System.assertEquals(4, first.imported);
      System.assertEquals(
        4,
        [SELECT COUNT() FROM AXF_OBJ_BankAccountTransaction__c]
      );
      System.assertEquals(
        1,
        new ALT_CLS_StatementImport()
          .preview(
            accountId,
            'outro.csv',
            'data,historico,valor\n10/09/2026,Novo,1'
          )
          .newCount
      );
      System.assertEquals(
        4,
        new ALT_CLS_StatementImport()
          .preview(accountId, 'extrato.csv', CSV)
          .duplicateCount
      );
    }
  }

  @IsTest
  static void csvWithoutRequiredColumnsIsRejected() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      try {
        new ALT_CLS_StatementImport()
          .preview(manualAccount(), 'x.csv', 'data,valor\n10/09/2026,1');
        System.assert(false, 'Expected ImportException');
      } catch (ALT_CLS_StatementImport.ImportException e) {
        System.assert(e.getMessage().contains('colunas'));
      }
      try {
        new ALT_CLS_StatementImport().preview(manualAccount(), 'x.csv', '\n\n');
        System.assert(false, 'Expected ImportException');
      } catch (ALT_CLS_StatementImport.ImportException e) {
        System.assertNotEquals(null, e.getMessage());
      }
    }
  }

  @IsTest
  static void onlyManualRecordTypeIsAccepted() {
    ALT_CLS_StatementImport.enforceRecordType = true;
    for (String name : new List<String>{ null, '', 'AXF_Pluggy', 'Other' }) {
      try {
        ALT_CLS_StatementImport.requireManual(name);
        System.assert(false, 'Expected ImportException for ' + name);
      } catch (ALT_CLS_StatementImport.ImportException e) {
        System.assert(e.getMessage().contains('manual'));
      }
    }
    System.runAs(new User(Id = UserInfo.getUserId())) {
      try {
        new ALT_CLS_StatementImport().preview(manualAccount(), 'a.ofx', OFX);
        System.assert(false, 'Expected ImportException');
      } catch (ALT_CLS_StatementImport.ImportException e) {
        System.assert(e.getMessage().contains('manual'));
      }
    }
  }

  @IsTest
  static void missingRecordIsRefused() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Id accountId = manualAccount();
      delete [SELECT Id FROM AXF_OBJ_BankAccount__c WHERE Id = :accountId];
      try {
        new ALT_CLS_StatementImport().preview(accountId, 'a.ofx', OFX);
        System.assert(false, 'Expected ImportException');
      } catch (ALT_CLS_StatementImport.ImportException e) {
        System.assertEquals('Conta ou cartão não encontrado.', e.getMessage());
      }
    }
  }

  @IsTest
  static void importSkipsLinesAlreadyImportedAndCountsOnlyNewOnes() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Id accountId = manualAccount();
      insert new AXF_OBJ_BankAccountTransaction__c(
        AXF_BAT_MD_BankAccount__c = accountId,
        AXF_BAT_EXI_PluggyTransactionId__c = 'OFX:' + accountId + ':A1',
        AXF_BAT_DAT_Date__c = Date.newInstance(2026, 9, 10),
        AXF_BAT_TXT_Description__c = 'Edited by hand',
        AXF_BAT_CUR_Amount__c = -1
      );
      ALT_CLS_StatementImport.Result r = new ALT_CLS_StatementImport()
        .importFile(accountId, 'extrato.ofx', OFX);
      System.assertEquals(true, r.success, r.message);
      System.assertEquals(1, r.imported);
      System.assertEquals(
        'Edited by hand',
        [
          SELECT AXF_BAT_TXT_Description__c
          FROM AXF_OBJ_BankAccountTransaction__c
          WHERE
            AXF_BAT_EXI_PluggyTransactionId__c = :('OFX:' + accountId + ':A1')
        ]
        .AXF_BAT_TXT_Description__c
      );
    }
  }

  @IsTest
  static void repeatedFitIdInTheSameFileCountsOnceInPreviewAndImport() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Id accountId = manualAccount();
      String twice =
        '<OFX><STMTTRN>\n<DTPOSTED>20260910\n<TRNAMT>-1\n<FITID>X\n<MEMO>a\n</STMTTRN>' +
        '<STMTTRN>\n<DTPOSTED>20260910\n<TRNAMT>-1\n<FITID>X\n<MEMO>a\n</STMTTRN></OFX>';
      ALT_CLS_StatementImport.Preview preview = new ALT_CLS_StatementImport()
        .preview(accountId, 'a.ofx', twice);
      System.assertEquals(1, preview.newCount);
      System.assertEquals(1, preview.duplicateCount);
      System.assertEquals(
        1,
        new ALT_CLS_StatementImport()
          .importFile(accountId, 'a.ofx', twice)
          .imported
      );
    }
  }

  @IsTest
  static void userWithoutAccessCannotImport() {
    User restricted = new User(
      Alias = 'axfnoimp',
      Email = 'axfnoimp@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'NoImport',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
      .Id,
      TimeZoneSidKey = 'America/Sao_Paulo',
      Username = 'axfnoimp' + System.currentTimeMillis() + '@example.com'
    );
    insert restricted;
    Id accountId;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      accountId = manualAccount();
    }
    Boolean refused = false;
    System.runAs(restricted) {
      try {
        new ALT_CLS_StatementImport().importFile(accountId, 'a.ofx', OFX);
      } catch (Exception e) {
        refused = true;
      }
    }
    System.assertEquals(true, refused);
  }

  private static ALT_CLS_StatementImport.Line firstLine(String csv) {
    return new ALT_CLS_StatementImport()
      .preview(manualAccount(), 'a.csv', 'data,descricao,valor\n' + csv)
      .lines[0];
  }

  @IsTest
  static void csvAmountsAcceptBrazilianAndUsFormats() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Map<String, Decimal> expected = new Map<String, Decimal>{
        '"1,234.56"' => 1234.56,
        '"1.234,56"' => 1234.56,
        '"-R$ 35,50"' => -35.5,
        '"-R$ 1.000,00"' => -1000,
        '12.5' => 12.5,
        '"1.234.567,89"' => 1234567.89
      };
      for (String raw : expected.keySet()) {
        ALT_CLS_StatementImport.Line line = firstLine('10/09/2026,x,' + raw);
        System.assertEquals(null, line.error, raw);
        System.assertEquals(expected.get(raw), line.amount, raw);
      }
    }
  }

  @IsTest
  static void csvAmbiguousAmountIsAnErrorLine() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      for (String raw : new List<String>{ '1.234', '"1,234"' }) {
        ALT_CLS_StatementImport.Line line = firstLine('10/09/2026,x,' + raw);
        System.assertEquals(ALT_CLS_StatementImport.INVALID, line.status, raw);
      }
    }
  }

  @IsTest
  static void csvImpossibleAndShortDatesAreErrorLinesAndIsoWithTimeWorks() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      System.assertEquals(
        ALT_CLS_StatementImport.INVALID,
        firstLine('31/02/2026,x,1').status
      );
      System.assertEquals(
        ALT_CLS_StatementImport.INVALID,
        firstLine('10/09/26,x,1').status
      );
      ALT_CLS_StatementImport.Line iso = firstLine('2026-09-10T12:30:00Z,x,1');
      System.assertEquals(null, iso.error);
      System.assertEquals(Date.newInstance(2026, 9, 10), iso.lineDate);
    }
  }

  @IsTest
  static void csvDedupeIgnoresTheScaleOfTheAmount() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Id accountId = manualAccount();
      new ALT_CLS_StatementImport()
        .importFile(
          accountId,
          'a.csv',
          'data,descricao,valor\n10/09/2026,Cafe,-5.00'
        );
      ALT_CLS_StatementImport.Preview preview = new ALT_CLS_StatementImport()
        .preview(
          accountId,
          'b.csv',
          'data,descricao,valor\n10/09/2026,Cafe,"-5,0"'
        );
      System.assertEquals(1, preview.duplicateCount);
      System.assertEquals(0, preview.newCount);
    }
  }

  @IsTest
  static void csvWithUtf8BomIsRecognized() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      ALT_CLS_StatementImport.Preview preview = new ALT_CLS_StatementImport()
        .preview(
          manualAccount(),
          'a.csv',
          '\uFEFFdata,descricao,valor\n10/09/2026,Cafe,-5'
        );
      System.assertEquals(1, preview.newCount);
    }
  }

  private static final String NBSP = '\u00A0';
  private static final String BANK =
    '\uFEFFData,Categoria,Lançamento,Descrição,Entrada,Saída,Saldo do dia\r\n' +
    '01/08/2026,Pessoa Jurídica,PIX,TITULAR EXEMPLO,-,"R$' +
    NBSP +
    '1.000,00","-R$' +
    NBSP +
    '1.000,00"\r\n' +
    '11/08/2026,Pessoa Jurídica,PIX,TITULAR EXEMPLO,-,"R$' +
    NBSP +
    '1.500,00","-R$' +
    NBSP +
    '4.500,00"\r\n' +
    '11/08/2026,Pessoa Jurídica,PIX,TITULAR EXEMPLO,-,"R$' +
    NBSP +
    '3.000,00","-R$' +
    NBSP +
    '4.500,00"\r\n' +
    '20/08/2026,Pessoa Jurídica,PIX,CLIENTE,"R$' +
    NBSP +
    '10.250,50",-,"R$' +
    NBSP +
    '5.750,50"\r\n' +
    '21/08/2026,Pessoa Jurídica,PIX,SEM VALOR,-,,"R$' +
    NBSP +
    '5.750,50"\r\n' +
    '22/08/2026,Pessoa Jurídica,PIX,DOIS,"R$' +
    NBSP +
    '1,00","R$' +
    NBSP +
    '2,00",0\r\n' +
    '23/08/2026,Pessoa Jurídica,PIX,ZERO,"R$' +
    NBSP +
    '0,00",-,0\r\n';

  @IsTest
  static void entradaSaidaCsvIsParsedWithSignedAmounts() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      ALT_CLS_StatementImport.Preview preview = new ALT_CLS_StatementImport()
        .preview(manualAccount(), 'extrato.csv', BANK);
      System.assertEquals(7, preview.lines.size());
      System.assertEquals(-1000, preview.lines[0].amount);
      System.assertEquals(-1500, preview.lines[1].amount);
      System.assertEquals(-3000, preview.lines[2].amount);
      System.assertEquals(10250.5, preview.lines[3].amount);
      System.assertEquals('CLIENTE', preview.lines[3].description);
      System.assertEquals(
        Date.newInstance(2026, 8, 1),
        preview.lines[0].lineDate
      );
      System.assertEquals(0, preview.lines[6].amount);
      System.assertEquals(5, preview.newCount);
      System.assertEquals(2, preview.errorCount);
      System.assertEquals(
        ALT_CLS_StatementImport.INVALID,
        preview.lines[4].status
      );
      System.assert(
        preview.lines[4].error.startsWith('Linha 6'),
        preview.lines[4].error
      );
      System.assert(preview.lines[4].error.contains('vazias'));
      System.assert(
        preview.lines[5].error.startsWith('Linha 7'),
        preview.lines[5].error
      );
      System.assert(preview.lines[5].error.contains('ao mesmo tempo'));
    }
  }

  @IsTest
  static void entradaSaidaImportKeepsEqualDescriptionsApartAndIsIdempotent() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Id accountId = manualAccount();
      ALT_CLS_StatementImport.Result first = new ALT_CLS_StatementImport()
        .importFile(accountId, 'extrato.csv', BANK);
      ALT_CLS_StatementImport.Result second = new ALT_CLS_StatementImport()
        .importFile(accountId, 'extrato.csv', BANK);
      System.assertEquals(true, first.success, first.message);
      System.assertEquals(5, first.imported);
      System.assertEquals(0, second.imported);
      System.assertEquals(
        5,
        [SELECT COUNT() FROM AXF_OBJ_BankAccountTransaction__c]
      );
    }
  }

  @IsTest
  static void extraColumnsDoNotChangeTheDedupeKey() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Id accountId = manualAccount();
      new ALT_CLS_StatementImport()
        .importFile(
          accountId,
          'a.csv',
          'Data,Categoria,Descrição,Entrada,Saída,Saldo do dia\n01/08/2026,A,CAFE,-,"R$' +
            NBSP +
            '5,00",1'
        );
      ALT_CLS_StatementImport.Preview preview = new ALT_CLS_StatementImport()
        .preview(
          accountId,
          'b.csv',
          'Data,Descrição,Saída,Entrada,Lançamento\n01/08/2026,CAFE,5,-,OUTRO'
        );
      System.assertEquals(1, preview.duplicateCount);
      System.assertEquals(0, preview.newCount);
    }
  }

  @IsTest
  static void entradaSaidaColumnDefinesTheSignEvenWhenTheCellHasOne() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Id accountId = manualAccount();
      ALT_CLS_StatementImport.Result result = new ALT_CLS_StatementImport()
        .importFile(
          accountId,
          'a.csv',
          'Data,Descrição,Entrada,Saída\n' +
            '01/08/2026,SAIDA COM SINAL,-,"-5,00"\n' +
            '02/08/2026,ENTRADA COM SINAL,"-7,00",-\n' +
            '03/08/2026,SAIDA SEM SINAL,-,"3,00"\n'
        );
      System.assertEquals(true, result.success, result.message);
      System.assertEquals(3, result.imported);
      AggregateResult total = [
        SELECT SUM(AXF_BAT_CUR_Amount__c) net
        FROM AXF_OBJ_BankAccountTransaction__c
        WHERE AXF_BAT_MD_BankAccount__c = :accountId
      ];
      System.assertEquals(-1, total.get('net'));
    }
  }

  @IsTest
  static void valueLayoutStillWorksAndEntradaWithoutSaidaIsRejected() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      System.assertEquals(
        1,
        new ALT_CLS_StatementImport()
          .preview(
            manualAccount(),
            'a.csv',
            'Data,Descrição,Valor\n01/08/2026,X,-5,00'
              .replace('-5,00', '"-5,00"')
          )
          .newCount
      );
      try {
        new ALT_CLS_StatementImport()
          .preview(
            manualAccount(),
            'a.csv',
            'Data,Descrição,Entrada\n01/08/2026,X,5'
          );
        System.assert(false, 'Expected ImportException');
      } catch (ALT_CLS_StatementImport.ImportException e) {
        System.assert(e.getMessage().contains('entrada e saída'));
      }
    }
  }

  // Statement exported by Contabilizei (checking account, August 2026), as delivered.
  private static final String CONTABILIZEI =
    '\uFEFFData,Categoria,Lançamento,Descrição,Entrada,Saída,Saldo do dia\r\n' +
    '01/08/2026,Pessoa Jurídica,PIX,TITULAR EXEMPLO,-,"R$' +
    NBSP +
    '1.000,00","-R$' +
    NBSP +
    '1.000,00"\r\n' +
    '05/08/2026,Pessoa Jurídica,PIX,TITULAR EXEMPLO,-,"R$' +
    NBSP +
    '2.500,00","-R$' +
    NBSP +
    '2.500,00"\r\n' +
    '11/08/2026,Pessoa Jurídica,PIX,TITULAR EXEMPLO,-,"R$' +
    NBSP +
    '1.500,00","-R$' +
    NBSP +
    '4.500,00"\r\n' +
    '11/08/2026,Pessoa Jurídica,PIX,TITULAR EXEMPLO,-,"R$' +
    NBSP +
    '3.000,00","-R$' +
    NBSP +
    '4.500,00"\r\n' +
    '14/08/2026,Pessoa Jurídica,PIX,TITULAR EXEMPLO,-,"R$' +
    NBSP +
    '2.000,00","-R$' +
    NBSP +
    '2.000,00"\r\n' +
    '17/08/2026,Pessoa Jurídica,Pagamento,EMPRESA CONTABIL LTDA,-,"R$' +
    NBSP +
    '459,00","-R$' +
    NBSP +
    '459,00"\r\n' +
    '18/08/2026,Pessoa Jurídica,PIX,ORGAO PUBLICO,-,"R$' +
    NBSP +
    '502,51","-R$' +
    NBSP +
    '20.502,51"\r\n' +
    '18/08/2026,Pessoa Jurídica,PIX,TITULAR EXEMPLO,-,"R$' +
    NBSP +
    '20.000,00","-R$' +
    NBSP +
    '20.502,51"\r\n' +
    '20/08/2026,Pessoa Jurídica,PIX,TITULAR EXEMPLO,-,"R$' +
    NBSP +
    '5.500,00","-R$' +
    NBSP +
    '5.500,00"\r\n' +
    '25/08/2026,Pessoa Jurídica,PIX,TITULAR EXEMPLO,-,"R$' +
    NBSP +
    '600,00","-R$' +
    NBSP +
    '600,00"\r\n' +
    '27/08/2026,Pessoa Jurídica,PIX,Recebimento do exterior,"R$' +
    NBSP +
    '27.896,59",-,"R$' +
    NBSP +
    '27.896,59"\r\n' +
    '28/08/2026,Pessoa Jurídica,PIX,TITULAR EXEMPLO,-,"R$' +
    NBSP +
    '1.442,69","-R$' +
    NBSP +
    '1.442,69"\r\n';

  @IsTest
  static void realContabilizeiStatementImportsEveryLineWithTheRightTotal() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Id accountId = manualAccount();
      ALT_CLS_StatementImport.Preview preview = new ALT_CLS_StatementImport()
        .preview(accountId, '00000000_01AGO2026_31AGO2026.csv', CONTABILIZEI);
      System.assertEquals(12, preview.lines.size());
      System.assertEquals(12, preview.newCount);
      System.assertEquals(0, preview.errorCount);
      ALT_CLS_StatementImport.Result first = new ALT_CLS_StatementImport()
        .importFile(
          accountId,
          '00000000_01AGO2026_31AGO2026.csv',
          CONTABILIZEI
        );
      System.assertEquals(true, first.success, first.message);
      System.assertEquals(12, first.imported);
      AggregateResult total = [
        SELECT SUM(AXF_BAT_CUR_Amount__c) net, COUNT(Id) lines
        FROM AXF_OBJ_BankAccountTransaction__c
        WHERE AXF_BAT_MD_BankAccount__c = :accountId
      ];
      System.assertEquals(-10607.61, (Decimal) total.get('net'));
      System.assertEquals(12, (Integer) total.get('lines'));
      System.assertEquals(
        2,
        [
          SELECT COUNT()
          FROM AXF_OBJ_BankAccountTransaction__c
          WHERE
            AXF_BAT_MD_BankAccount__c = :accountId
            AND AXF_BAT_DAT_Date__c = 2026-08-11
        ]
      );
      ALT_CLS_StatementImport.Result second = new ALT_CLS_StatementImport()
        .importFile(
          accountId,
          '00000000_01AGO2026_31AGO2026.csv',
          CONTABILIZEI
        );
      System.assertEquals(0, second.imported);
      System.assertEquals(
        12,
        [SELECT COUNT() FROM AXF_OBJ_BankAccountTransaction__c]
      );
    }
  }
}
