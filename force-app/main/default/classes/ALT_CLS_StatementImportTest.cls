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
}
