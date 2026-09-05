/**
 * @description Tests for AXF_CLS_CsvImportConfirmService / AXF_CLS_CTRL_CsvImportPreview.confirmCsv (AXF-15).
 * Publish paths run as a real configurator (System Administrator + AXF_PSG_GestorFinanceiro).
 */
@IsTest(isParallel=false)
private class AXF_CLS_CsvImportConfirmServiceTest {
  private static final String HEADER = 'Data;Descricao;Entrada;Saida;Saldo';
  private static final String PARSER_VERSION = 'contabilizei-bank-csv@1.0.0';

  private static User configurator() {
    Id adminProfileId = [
      SELECT ProfileId
      FROM User
      WHERE Id = :UserInfo.getUserId()
    ]
    .ProfileId;
    PermissionSetGroup psg = [
      SELECT Id, Status
      FROM PermissionSetGroup
      WHERE DeveloperName = 'AXF_PSG_GestorFinanceiro'
      LIMIT 1
    ];
    if (psg.Status != 'Updated') {
      Test.calculatePermissionSetGroup(psg.Id);
    }
    User u = new User(
      ProfileId = adminProfileId,
      LastName = 'Cfg AXF15',
      Email = 'axf15.cfg@example.com',
      Username = 'axf15.cfg.' +
        Crypto.getRandomInteger() +
        '@example.com.invalid',
      Alias = 'a15c',
      TimeZoneSidKey = 'America/Sao_Paulo',
      LocaleSidKey = 'pt_BR',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'pt_BR'
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert u;
      insert new PermissionSetAssignment(
        AssigneeId = u.Id,
        PermissionSetGroupId = psg.Id
      );
    }
    return u;
  }

  private static Id rt(String dev) {
    return Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
      .getRecordTypeInfosByDeveloperName()
      .get(dev)
      .getRecordTypeId();
  }

  private static AXF_OBJ_BankAccount__c availableBank() {
    Account holder = new Account(
      LastName = 'Titular AXF15',
      RecordTypeId = rt('AXF_Person')
    );
    insert holder;
    AXF_OBJ_BankAccount__c b = new AXF_OBJ_BankAccount__c(
      AXF_BA_LKP_Account__c = holder.Id,
      AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_BA_TXT_InstitutionName__c = 'Contabilizei.bank',
      AXF_BA_TXT_NumberMasked__c = '****1234',
      AXF_BA_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BA_EXI_ManualKey__c = '22222222-2222-2222-2222-222222222222',
      AXF_BA_NUM_Version__c = 0
    );
    Database.insert(b, AccessLevel.SYSTEM_MODE);
    return b;
  }

  private static AXF_CLS_CsvImportConfirmService.ConfirmInput input(
    Id accountId,
    String csv,
    Boolean ack
  ) {
    AXF_CLS_CsvImportConfirmService.ConfirmInput req = new AXF_CLS_CsvImportConfirmService.ConfirmInput();
    req.accountId = accountId;
    req.fileName = 'extrato.csv';
    req.base64Content = EncodingUtil.base64Encode(Blob.valueOf(csv));
    req.expectedParserVersion = PARSER_VERSION;
    req.acknowledgeRejections = ack;
    return req;
  }

  private static Integer batCount(Id accountId) {
    return [
      SELECT COUNT()
      FROM AXF_OBJ_BankAccountTransaction__c
      WHERE AXF_BAT_MDR_BankAccount__c = :accountId
    ];
  }

  @IsTest
  static void publishesValidRowsAndIsIdempotent() {
    AXF_OBJ_BankAccount__c bank = availableBank();
    User cfg = configurator();
    String csv =
      HEADER +
      '\n01/03/2026;Salario;5000,00;;5000,00' +
      '\n02/03/2026;Mercado;;150,50;4849,50';

    AXF_CLS_CsvImportConfirmService.ConfirmResult first;
    AXF_CLS_CsvImportConfirmService.ConfirmResult again;
    System.runAs(cfg) {
      first = AXF_CLS_CTRL_CsvImportPreview.confirmCsv(
        input(bank.Id, csv, false)
      );
      again = AXF_CLS_CTRL_CsvImportPreview.confirmCsv(
        input(bank.Id, csv, false)
      );
    }

    System.assertEquals('PUBLISHED', first.outcome, first.message);
    System.assertEquals(2, first.publishedCount);
    System.assertEquals('2026-03-01', first.firstDate);
    System.assertEquals('2026-03-02', first.lastDate);
    System.assertEquals('PUBLISHED', again.outcome);
    System.assertEquals(0, again.publishedCount);
    System.assertEquals(2, again.alreadyPresentCount);
    System.assertEquals(2, batCount(bank.Id));
  }

  @IsTest
  static void rejectedRowsRequireAcknowledgeThenPublishOnlyValid() {
    AXF_OBJ_BankAccount__c bank = availableBank();
    User cfg = configurator();
    String csv =
      HEADER +
      '\n01/03/2026;Salario;5000,00;;5000,00' +
      '\ndata-ruim;Erro;;10,00;4990,00';

    AXF_CLS_CsvImportConfirmService.ConfirmResult blocked;
    AXF_CLS_CsvImportConfirmService.ConfirmResult ok;
    System.runAs(cfg) {
      blocked = AXF_CLS_CTRL_CsvImportPreview.confirmCsv(
        input(bank.Id, csv, false)
      );
      ok = AXF_CLS_CTRL_CsvImportPreview.confirmCsv(input(bank.Id, csv, true));
    }

    System.assertEquals('NEEDS_ACKNOWLEDGE', blocked.outcome);
    System.assertEquals(
      0,
      blocked.publishedCount,
      'NEEDS_ACKNOWLEDGE não publica nada'
    );
    System.assertEquals('PUBLISHED', ok.outcome, ok.message);
    System.assertEquals(1, ok.publishedCount);
    System.assertEquals(1, ok.rejectedCount);
    System.assertEquals(1, batCount(bank.Id));
  }

  @IsTest
  static void stalePreviewVersionBlocksWithoutPublishing() {
    AXF_OBJ_BankAccount__c bank = availableBank();
    User cfg = configurator();
    AXF_CLS_CsvImportConfirmService.ConfirmInput req = input(
      bank.Id,
      HEADER + '\n01/03/2026;Salario;5000,00;;5000,00',
      false
    );
    req.expectedParserVersion = 'contabilizei-bank-csv@0.9.0';

    AXF_CLS_CsvImportConfirmService.ConfirmResult r;
    System.runAs(cfg) {
      r = AXF_CLS_CTRL_CsvImportPreview.confirmCsv(req);
    }

    System.assertEquals('STALE_PREVIEW', r.outcome);
    System.assertEquals(0, batCount(bank.Id));
  }

  @IsTest
  static void unavailableAccountBlocks() {
    AXF_OBJ_BankAccount__c bank = availableBank();
    bank.AXF_BA_PKL_AvailabilityState__c = 'CUSTODY';
    Database.update(bank, AccessLevel.SYSTEM_MODE);
    User cfg = configurator();

    AXF_CLS_CsvImportConfirmService.ConfirmResult r;
    System.runAs(cfg) {
      r = AXF_CLS_CTRL_CsvImportPreview.confirmCsv(
        input(bank.Id, HEADER + '\n01/03/2026;Salario;5000,00;;5000,00', false)
      );
    }

    System.assertEquals('ACCOUNT_NOT_FOUND', r.outcome);
  }

  @IsTest
  static void structureInvalidBlocks() {
    AXF_OBJ_BankAccount__c bank = availableBank();
    User cfg = configurator();

    AXF_CLS_CsvImportConfirmService.ConfirmResult r;
    System.runAs(cfg) {
      r = AXF_CLS_CTRL_CsvImportPreview.confirmCsv(
        input(bank.Id, 'ColunaA;ColunaB\nx;y', false)
      );
    }

    System.assertEquals('INVALID_FILE', r.outcome);
    System.assertEquals(0, batCount(bank.Id));
  }

  @IsTest
  static void storesRecoverableEvidenceLinkedToAccount() {
    AXF_OBJ_BankAccount__c bank = availableBank();
    User cfg = configurator();

    AXF_CLS_CsvImportConfirmService.ConfirmResult r;
    System.runAs(cfg) {
      r = AXF_CLS_CTRL_CsvImportPreview.confirmCsv(
        input(bank.Id, HEADER + '\n01/03/2026;Salario;5000,00;;5000,00', false)
      );
    }

    System.assertEquals('PUBLISHED', r.outcome, r.message);
    System.assertNotEquals(null, r.evidenceDocumentId);
    System.assertEquals(
      1,
      [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :bank.Id]
    );
    AXF_OBJ_BankAccountTransaction__c bat = [
      SELECT
        AXF_BAT_TXT_EvidenceRef__c,
        AXF_BAT_PKL_Source__c,
        AXF_BAT_TXT_CurrencyIsoCode__c
      FROM AXF_OBJ_BankAccountTransaction__c
      WHERE AXF_BAT_MDR_BankAccount__c = :bank.Id
      LIMIT 1
    ];
    System.assertEquals(r.evidenceDocumentId, bat.AXF_BAT_TXT_EvidenceRef__c);
    System.assertEquals('CSV', bat.AXF_BAT_PKL_Source__c);
    System.assertEquals('BRL', bat.AXF_BAT_TXT_CurrencyIsoCode__c);
  }

  @IsTest
  static void rejectsMissingContent() {
    User cfg = configurator();
    AXF_CLS_CsvImportConfirmService.ConfirmResult r;
    System.runAs(cfg) {
      r = AXF_CLS_CTRL_CsvImportPreview.confirmCsv(
        new AXF_CLS_CsvImportConfirmService.ConfirmInput()
      );
    }
    System.assertEquals('INVALID_FILE', r.outcome);
  }
}
