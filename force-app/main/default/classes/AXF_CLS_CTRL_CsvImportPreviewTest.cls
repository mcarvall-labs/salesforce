/**
 * @description Tests for AXF_CLS_CTRL_CsvImportPreview (AXF-14). Effective
 * paths run as a real configurator (System Administrator + AXF_PSG_GestorFinanceiro)
 * so USER_MODE reads of the manual bank account reflect real record access.
 */
@IsTest(isParallel=false)
private class AXF_CLS_CTRL_CsvImportPreviewTest {
  private static final String HEADER = 'Data;Descricao;Entrada;Saida;Saldo';

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
      LastName = 'Cfg AXF14',
      Email = 'axf14.cfg@example.com',
      Username = 'axf14.cfg.' +
        Crypto.getRandomInteger() +
        '@example.com.invalid',
      Alias = 'a14c',
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

  private static Account person(String name) {
    Account a = new Account(LastName = name, RecordTypeId = rt('AXF_Person'));
    insert a;
    return [SELECT Id, OwnerId FROM Account WHERE Id = :a.Id];
  }

  private static AXF_OBJ_BankAccount__c availableBank(
    Id holderId,
    String inst
  ) {
    AXF_OBJ_BankAccount__c b = new AXF_OBJ_BankAccount__c(
      AXF_BA_LKP_Account__c = holderId,
      AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_BA_TXT_InstitutionName__c = inst,
      AXF_BA_TXT_NumberMasked__c = '****1234',
      AXF_BA_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BA_EXI_ManualKey__c = '11111111-1111-1111-1111-111111111111',
      AXF_BA_NUM_Version__c = 0
    );
    Database.insert(b, AccessLevel.SYSTEM_MODE);
    return b;
  }

  private static String validCsvBase64() {
    String csv = HEADER + '\n01/03/2026;Salario;5000,00;;5000,00';
    return EncodingUtil.base64Encode(Blob.valueOf(csv));
  }

  @IsTest
  static void getPolicyReturnsConfiguredLimits() {
    AXF_CLS_CTRL_CsvImportPreview.PolicyView policy = AXF_CLS_CTRL_CsvImportPreview.getPolicy();

    System.assertEquals('csv', policy.allowedExtensions);
    System.assertEquals('UTF-8', policy.requiredEncoding);
    System.assertNotEquals(null, policy.maxFileSizeBytes);
    System.assertNotEquals(null, policy.maxRows);
  }

  @IsTest
  static void previewCsvReturnsOkForValidFileOnAvailableAccount() {
    Account holder = person('Titular AXF14');
    AXF_OBJ_BankAccount__c bank = availableBank(holder.Id, 'Contabilizei.bank');
    User cfg = configurator();

    AXF_CLS_CTRL_CsvImportPreview.PreviewInput input = new AXF_CLS_CTRL_CsvImportPreview.PreviewInput();
    input.accountId = bank.Id;
    input.fileName = 'extrato.csv';
    input.base64Content = validCsvBase64();

    AXF_CLS_CTRL_CsvImportPreview.PreviewResult result;
    System.runAs(cfg) {
      result = AXF_CLS_CTRL_CsvImportPreview.previewCsv(input);
    }

    System.assertEquals('OK', result.outcome);
    System.assertEquals(1, result.parseResult.validRows);
    System.assert(result.targetAccountLabel.contains('Contabilizei.bank'));
  }

  @IsTest
  static void previewCsvRejectsUnsupportedExtension() {
    Account holder = person('Titular AXF14b');
    AXF_OBJ_BankAccount__c bank = availableBank(holder.Id, 'Contabilizei.bank');
    User cfg = configurator();

    AXF_CLS_CTRL_CsvImportPreview.PreviewInput input = new AXF_CLS_CTRL_CsvImportPreview.PreviewInput();
    input.accountId = bank.Id;
    input.fileName = 'extrato.xlsx';
    input.base64Content = validCsvBase64();

    AXF_CLS_CTRL_CsvImportPreview.PreviewResult result;
    System.runAs(cfg) {
      result = AXF_CLS_CTRL_CsvImportPreview.previewCsv(input);
    }

    System.assertEquals('INVALID_FILE', result.outcome);
  }

  @IsTest
  static void previewCsvRejectsUnknownOrUnavailableAccount() {
    User cfg = configurator();
    AXF_CLS_CTRL_CsvImportPreview.PreviewInput input = new AXF_CLS_CTRL_CsvImportPreview.PreviewInput();
    input.accountId = Id.valueOf('001000000000000AAA'); // well-formed id, no matching bank account row
    input.fileName = 'extrato.csv';
    input.base64Content = validCsvBase64();

    AXF_CLS_CTRL_CsvImportPreview.PreviewResult result;
    System.runAs(cfg) {
      result = AXF_CLS_CTRL_CsvImportPreview.previewCsv(input);
    }

    System.assertEquals('ACCOUNT_NOT_FOUND', result.outcome);
  }

  @IsTest
  static void previewCsvSurfacesUnsupportedStructureWithoutPublishing() {
    Account holder = person('Titular AXF14c');
    AXF_OBJ_BankAccount__c bank = availableBank(holder.Id, 'Contabilizei.bank');
    User cfg = configurator();

    AXF_CLS_CTRL_CsvImportPreview.PreviewInput input = new AXF_CLS_CTRL_CsvImportPreview.PreviewInput();
    input.accountId = bank.Id;
    input.fileName = 'extrato.csv';
    input.base64Content = EncodingUtil.base64Encode(
      Blob.valueOf('ColunaA;ColunaB\nx;y')
    );

    AXF_CLS_CTRL_CsvImportPreview.PreviewResult result;
    System.runAs(cfg) {
      result = AXF_CLS_CTRL_CsvImportPreview.previewCsv(input);
    }

    System.assertEquals('INVALID_FILE', result.outcome);
    System.assertEquals(false, result.parseResult.structureValid);
  }

  @IsTest
  static void previewCsvRejectsMissingFileContent() {
    User cfg = configurator();
    AXF_CLS_CTRL_CsvImportPreview.PreviewInput input = new AXF_CLS_CTRL_CsvImportPreview.PreviewInput();

    AXF_CLS_CTRL_CsvImportPreview.PreviewResult result;
    System.runAs(cfg) {
      result = AXF_CLS_CTRL_CsvImportPreview.previewCsv(input);
    }

    System.assertEquals('INVALID_FILE', result.outcome);
  }
}
