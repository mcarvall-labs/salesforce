/**
 * @description AXF_CLS_CTRL_ManualFinancialSource + ALT_CLS_ManualFinancialSource over the
 * legacy PROD model: manual BA/CC/wallet with 'MANUAL-' + UUID external ids, idempotent
 * replay, validation, update, authority and the bank institution directory.
 */
@IsTest
private class AXF_CLS_CTRL_ManualFinancialSourceTest {
  private static final String KEY_1 = '11111111-1111-4111-8111-111111111111';
  private static final String KEY_2 = '22222222-2222-4222-8222-222222222222';
  private static final String KEY_3 = '33333333-3333-4333-8333-333333333333';

  @TestSetup
  static void setup() {
    AXF_CLS_SourceSetupTestFactory.createUsers();
    User cfg = AXF_CLS_SourceSetupTestFactory.user(
      AXF_CLS_SourceSetupTestFactory.CONFIGURER
    );
    AXF_CLS_SourceSetupTestFactory.institution(
      cfg.Id,
      'Banco Manual',
      AXF_CLS_SourceSetupTestFactory.BANK_NUMBER
    );
    AXF_CLS_SourceSetupTestFactory.holder(cfg.Id, 'Titular Um');
    AXF_CLS_SourceSetupTestFactory.holder(cfg.Id, 'Titular Dois');
  }

  private static User configurer() {
    return AXF_CLS_SourceSetupTestFactory.user(
      AXF_CLS_SourceSetupTestFactory.CONFIGURER
    );
  }

  private static Id holder(String name) {
    return [SELECT Id FROM Account WHERE Name = :name LIMIT 1].Id;
  }

  private static Id bankId() {
    return [
      SELECT Id
      FROM AXF_OBJ_BankInstitution__c
      WHERE
        AXF_BI_EXI_Bank_Number__c = :AXF_CLS_SourceSetupTestFactory.BANK_NUMBER
    ]
    .Id;
  }

  private static AXF_CLS_SourceSetupDTO.ManualSaveResult save(
    String kind,
    Id sourceId,
    Id holderId,
    String currencyIsoCode,
    String institutionName,
    Id bankInstitutionId,
    String maskedNumber,
    String sourceType,
    String brand,
    String manualKey
  ) {
    return AXF_CLS_CTRL_ManualFinancialSource.save(
      kind,
      sourceId,
      holderId,
      currencyIsoCode,
      institutionName,
      bankInstitutionId,
      maskedNumber,
      sourceType,
      brand,
      manualKey,
      null
    );
  }

  @IsTest
  static void createsManualBankAccountAndReplays() {
    Id one = holder('Titular Um');
    Id two = holder('Titular Dois');
    Id bank = bankId();
    System.runAs(configurer()) {
      AXF_CLS_SourceSetupDTO.ManualSaveResult r = save(
        'BANK',
        null,
        one,
        'brl',
        null,
        bank,
        '•••• 1234',
        'savings account',
        null,
        KEY_1
      );
      Assert.areEqual('CREATED', r.outcome, r.message);
      Assert.areEqual(one, r.accountHolderId);

      AXF_OBJ_BankAccount__c row = [
        SELECT
          AXF_BA_EXI_PluggyAccountId__c,
          AXF_BA_LKP_Account__c,
          AXF_BA_LKP_BankInstitution__c,
          AXF_BA_LKP_PluggyConnection__c,
          AXF_BA_PKL_Type__c,
          AXF_BA_PKL_Currency__c,
          AXF_BA_TXT_AccountNumber__c
        FROM AXF_OBJ_BankAccount__c
        WHERE Id = :r.sourceId
      ];
      Assert.areEqual('MANUAL-' + KEY_1, row.AXF_BA_EXI_PluggyAccountId__c);
      Assert.areEqual(one, row.AXF_BA_LKP_Account__c);
      Assert.areEqual(bank, row.AXF_BA_LKP_BankInstitution__c);
      Assert.isNull(row.AXF_BA_LKP_PluggyConnection__c);
      Assert.areEqual('SAVINGS_ACCOUNT', row.AXF_BA_PKL_Type__c);
      Assert.areEqual('BRL', row.AXF_BA_PKL_Currency__c);

      Assert.areEqual(
        'ALREADY',
        save('BANK', null, one, 'BRL', null, bank, null, null, null, KEY_1)
          .outcome
      );
      Assert.areEqual(
        'CONFLICT',
        save('BANK', null, two, 'BRL', null, bank, null, null, null, KEY_1)
          .outcome
      );

      AXF_CLS_SourceSetupDTO.ManualSaveResult updated = save(
        'BANK',
        r.sourceId,
        null,
        null,
        null,
        bank,
        '•••• 9876',
        'Checking',
        null,
        null
      );
      Assert.areEqual('UPDATED', updated.outcome, updated.message);
      Assert.areEqual(one, updated.accountHolderId);
    }
    Assert.areEqual(
      'CHECKING',
      [
        SELECT AXF_BA_PKL_Type__c
        FROM AXF_OBJ_BankAccount__c
        WHERE AXF_BA_EXI_PluggyAccountId__c = :('MANUAL-' + KEY_1)
      ]
      .AXF_BA_PKL_Type__c
    );
  }

  @IsTest
  static void createsManualCardByInstitutionNameAndUpdates() {
    Id one = holder('Titular Um');
    Id bank = bankId();
    System.runAs(configurer()) {
      AXF_CLS_SourceSetupDTO.ManualSaveResult r = save(
        'CARD',
        null,
        one,
        'BRL',
        'Banco Manual',
        null,
        '**** 4321',
        null,
        'VISA',
        KEY_2
      );
      Assert.areEqual('CREATED', r.outcome, r.message);
      AXF_OBJ_CreditCard__c row = [
        SELECT
          AXF_CC_EXI_PluggyCreditCardId__c,
          AXF_CC_LKP_Account__c,
          AXF_CC_LKP_BankInstitution__c,
          AXF_CC_TXT_Brand__c,
          AXF_CC_TXT_LastFourDigits__c
        FROM AXF_OBJ_CreditCard__c
        WHERE Id = :r.sourceId
      ];
      Assert.areEqual('MANUAL-' + KEY_2, row.AXF_CC_EXI_PluggyCreditCardId__c);
      Assert.areEqual(bank, row.AXF_CC_LKP_BankInstitution__c);
      Assert.areEqual('4321', row.AXF_CC_TXT_LastFourDigits__c);
      Assert.areEqual('VISA', row.AXF_CC_TXT_Brand__c);

      Assert.areEqual(
        'ALREADY',
        save('CARD', null, one, 'BRL', null, bank, null, null, null, KEY_2)
          .outcome
      );
      AXF_CLS_SourceSetupDTO.ManualSaveResult updated = save(
        'CARD',
        r.sourceId,
        null,
        null,
        null,
        bank,
        '**** 1111',
        null,
        'MASTER',
        null
      );
      Assert.areEqual('UPDATED', updated.outcome, updated.message);
      Assert.areEqual(
        'INVALID',
        save('BANK', r.sourceId, null, null, null, bank, null, null, null, null)
          .outcome,
        'a card id is not a bank account'
      );
    }
  }

  @IsTest
  static void createsWalletWithoutInstitution() {
    Id one = holder('Titular Um');
    System.runAs(configurer()) {
      AXF_CLS_SourceSetupDTO.ManualSaveResult r = save(
        'BANK',
        null,
        one,
        'BRL',
        null,
        null,
        null,
        'WALLET',
        null,
        KEY_3
      );
      Assert.areEqual('CREATED', r.outcome, r.message);
      AXF_OBJ_BankAccount__c row = [
        SELECT AXF_BA_PKL_Type__c, AXF_BA_LKP_BankInstitution__c
        FROM AXF_OBJ_BankAccount__c
        WHERE Id = :r.sourceId
      ];
      Assert.areEqual('WALLET', row.AXF_BA_PKL_Type__c);
      Assert.isNull(row.AXF_BA_LKP_BankInstitution__c);
    }
  }

  @IsTest
  static void rejectsInvalidInput() {
    Id one = holder('Titular Um');
    Id bank = bankId();
    System.runAs(configurer()) {
      Map<String, AXF_CLS_SourceSetupDTO.ManualSaveResult> results = new Map<String, AXF_CLS_SourceSetupDTO.ManualSaveResult>{
        'kind' => save(
          'LOAN',
          null,
          one,
          'BRL',
          null,
          bank,
          null,
          null,
          null,
          KEY_1
        ),
        'holderId' => save(
          'BANK',
          null,
          bank,
          'BRL',
          null,
          bank,
          null,
          null,
          null,
          KEY_1
        ),
        'currencyIsoCode' => save(
          'BANK',
          null,
          one,
          'XYZ',
          null,
          bank,
          null,
          null,
          null,
          KEY_1
        ),
        'institutionName' => save(
          'BANK',
          null,
          one,
          'BRL',
          null,
          null,
          null,
          null,
          null,
          KEY_1
        ),
        'maskedNumber' => save(
          'BANK',
          null,
          one,
          'BRL',
          null,
          bank,
          '12345678',
          null,
          null,
          KEY_1
        ),
        'sourceType' => save(
          'BANK',
          null,
          one,
          'BRL',
          null,
          bank,
          null,
          'x'.repeat(41),
          null,
          KEY_1
        ),
        'brand' => save(
          'CARD',
          null,
          one,
          'BRL',
          null,
          bank,
          null,
          null,
          'x'.repeat(51),
          KEY_1
        ),
        'manualKey' => save(
          'BANK',
          null,
          one,
          'BRL',
          null,
          bank,
          null,
          null,
          null,
          'not-a-uuid'
        ),
        'bankInstitutionId' => save(
          'BANK',
          null,
          one,
          'BRL',
          'Banco Inexistente',
          null,
          null,
          null,
          null,
          KEY_1
        )
      };
      for (String field : results.keySet()) {
        AXF_CLS_SourceSetupDTO.ManualSaveResult r = results.get(field);
        Assert.areEqual('INVALID', r.outcome, field + ': ' + r.message);
        Assert.isTrue(r.invalidFields.contains(field), field);
      }
      Assert.areEqual(
        'INVALID',
        save('BANK', null, one, 'BRL', null, one, null, null, null, KEY_1)
          .outcome,
        'an Account is not an institution'
      );
      Assert.areEqual(
        'INVALID',
        save(
            'BANK',
            null,
            one,
            'BRL',
            null,
            null,
            'x'.repeat(31),
            null,
            null,
            KEY_1
          )
          .outcome
      );
    }
    Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_BankAccount__c]);
  }

  @IsTest
  static void missingHolderOrSourceIsForbidden() {
    Account gone = AXF_CLS_SourceSetupTestFactory.holder(
      configurer().Id,
      'Titular Removido'
    );
    delete gone;
    Id bank = bankId();
    AXF_OBJ_BankAccount__c deleted = AXF_CLS_SourceSetupTestFactory.bankAccount(
      configurer().Id,
      null,
      bank,
      holder('Titular Um'),
      'MANUAL-deleted'
    );
    AXF_OBJ_CreditCard__c deletedCard = AXF_CLS_SourceSetupTestFactory.creditCard(
      configurer().Id,
      null,
      bank,
      holder('Titular Um'),
      'MANUAL-deleted-card'
    );
    delete new List<SObject>{ deleted, deletedCard };
    System.runAs(configurer()) {
      Assert.areEqual(
        'FORBIDDEN',
        save('BANK', null, gone.Id, 'BRL', null, bank, null, null, null, KEY_1)
          .outcome
      );
      Assert.areEqual(
        'FORBIDDEN',
        save('BANK', deleted.Id, null, null, null, bank, null, null, null, null)
          .outcome
      );
      Assert.areEqual(
        'FORBIDDEN',
        save(
            'CARD',
            deletedCard.Id,
            null,
            null,
            null,
            bank,
            null,
            null,
            null,
            null
          )
          .outcome
      );
    }
  }

  @IsTest
  static void readerIsForbidden() {
    Id one = holder('Titular Um');
    System.runAs(AXF_CLS_SourceSetupTestFactory.user(
      AXF_CLS_SourceSetupTestFactory.READER
    )) {
      Assert.areEqual(
        'FORBIDDEN',
        save('BANK', null, one, 'BRL', null, bankId(), null, null, null, KEY_1)
          .outcome
      );
      Assert.areEqual(
        'FORBIDDEN',
        AXF_CLS_CTRL_ManualFinancialSource.createBankInstitution('X', '1')
          .outcome
      );
    }
  }

  @IsTest
  static void bankInstitutionDirectory() {
    System.runAs(configurer()) {
      Assert.areEqual(
        'INVALID',
        AXF_CLS_CTRL_ManualFinancialSource.createBankInstitution(' ', '1')
          .outcome
      );
      Assert.areEqual(
        'INVALID',
        AXF_CLS_CTRL_ManualFinancialSource.createBankInstitution(
            'Banco',
            '123456789'
          )
          .outcome
      );
      AXF_CLS_SourceSetupDTO.BankInstitutionResult created = AXF_CLS_CTRL_ManualFinancialSource.createBankInstitution(
        '  Banco Criado  ',
        '555'
      );
      Assert.areEqual('CREATED', created.outcome, created.message);
      Assert.areEqual('Banco Criado', created.name);
      AXF_CLS_SourceSetupDTO.BankInstitutionResult existing = AXF_CLS_CTRL_ManualFinancialSource.createBankInstitution(
        'Outro nome',
        AXF_CLS_SourceSetupTestFactory.BANK_NUMBER
      );
      Assert.areEqual('ALREADY', existing.outcome);
      Assert.areEqual(bankId(), existing.institutionId);
    }
  }
}
