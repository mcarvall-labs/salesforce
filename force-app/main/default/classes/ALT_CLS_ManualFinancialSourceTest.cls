@IsTest
private class ALT_CLS_ManualFinancialSourceTest {
  @TestSetup
  static void grantRealCrudAndFls() {
    Id permissionSetId = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'AXF_PS_GestorFinanceiro'
      LIMIT 1
    ]
    .Id;
    if (
      [
        SELECT COUNT()
        FROM PermissionSetAssignment
        WHERE
          AssigneeId = :UserInfo.getUserId()
          AND PermissionSetId = :permissionSetId
      ] == 0
    ) {
      insert new PermissionSetAssignment(
        AssigneeId = UserInfo.getUserId(),
        PermissionSetId = permissionSetId
      );
    }
  }
  private static Account holder() {
    Id rt = Account.SObjectType.getDescribe()
      .getRecordTypeInfosByDeveloperName()
      .get('AXF_Business')
      .getRecordTypeId();
    Account a = new Account(Name = 'Manual Holder', RecordTypeId = rt);
    insert a;
    return [SELECT Id, OwnerId FROM Account WHERE Id = :a.Id];
  }
  private static ALT_CLS_ManualFinancialSource.SaveInput input(
    Account a,
    String kind,
    String key
  ) {
    ALT_CLS_ManualFinancialSource.SaveInput i = new ALT_CLS_ManualFinancialSource.SaveInput();
    i.kind = kind;
    i.holderId = a.Id;
    i.currencyIsoCode = UserInfo.getDefaultCurrency();
    i.institutionName = 'Banco Manual';
    i.maskedNumber = '****1234';
    i.manualKey = key;
    i.sourceType = 'CHECKING';
    i.brand = 'VISA';
    return i;
  }
  @IsTest
  static void createsReplaysAndRejectsConflicts() {
    ALT_CLS_ManualFinancialSource.canConfigureOverride = true;
    ALT_CLS_ManualFinancialSource.sourceAccessOverride = true;
    Account a = holder();
    ALT_CLS_ManualFinancialSource.SaveInput i = input(
      a,
      'BANK',
      '123e4567-e89b-42d3-a456-426614174000'
    );
    ALT_CLS_ManualFinancialSource svc = new ALT_CLS_ManualFinancialSource();
    ALT_CLS_ManualFinancialSource.SaveResult created = svc.save(i);
    System.assertEquals(
      'CREATED',
      created.outcome,
      created.message + ' / ' + ALT_CLS_ManualFinancialSource.lastFailure
    );
    AXF_OBJ_BankAccount__c bank = [
      SELECT
        OwnerId,
        AXF_BA_LKP_Account__c,
        AXF_BA_LKP_Connection__c,
        AXF_BA_EXI_PluggyAccountId__c,
        AXF_BA_PKL_AvailabilityState__c
      FROM AXF_OBJ_BankAccount__c
      WHERE Id = :created.sourceId
    ];
    System.assertEquals(a.Id, bank.AXF_BA_LKP_Account__c, 'holder projection');
    System.assertEquals(a.OwnerId, bank.OwnerId, 'owner projection');
    System.assertEquals(
      null,
      bank.AXF_BA_LKP_Connection__c,
      'no Pluggy connection'
    );
    System.assertEquals(
      null,
      bank.AXF_BA_EXI_PluggyAccountId__c,
      'no Pluggy identity'
    );
    System.assertEquals(
      'AVAILABLE',
      bank.AXF_BA_PKL_AvailabilityState__c,
      'manual source availability'
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM AXF_OBJ_AccountHolder__c
        WHERE
          AXF_ACH_LKP_BankAccount__c = :bank.Id
          AND AXF_ACH_PKL_Role__c = 'PRIMARY'
          AND AXF_ACH_PKL_State__c = 'CONFIRMED'
      ]
    );
    System.assertEquals('ALREADY', svc.save(i).outcome);
    i.sourceType = 'SAVINGS';
    System.assertEquals(
      'CONFLICT',
      svc.save(i).outcome,
      'source type is part of replay payload'
    );
    i.sourceType = 'CHECKING';
    i.institutionName = 'Outro Banco';
    System.assertEquals('CONFLICT', svc.save(i).outcome);
    ALT_CLS_ManualFinancialSource.SaveInput crossKind = input(
      a,
      'CARD',
      '123e4567-e89b-42d3-a456-426614174000'
    );
    System.assertEquals(
      'CONFLICT',
      svc.save(crossKind).outcome,
      'one UUID cannot identify a different source kind'
    );
    i.sourceId = created.sourceId;
    i.expectedVersion = 1;
    i.manualKey = null;
    System.assertEquals(
      'UPDATED',
      svc.save(i).outcome,
      'bank descriptive edit'
    );
    System.assertEquals(1, [SELECT COUNT() FROM AXF_OBJ_BankAccount__c]);
  }
  @IsTest
  static void updatesDescriptiveFieldsWithVersion() {
    ALT_CLS_ManualFinancialSource.canConfigureOverride = true;
    ALT_CLS_ManualFinancialSource.sourceAccessOverride = true;
    Account a = holder();
    ALT_CLS_ManualFinancialSource svc = new ALT_CLS_ManualFinancialSource();
    ALT_CLS_ManualFinancialSource.SaveInput i = input(
      a,
      'CARD',
      '123e4567-e89b-42d3-a456-426614174001'
    );
    ALT_CLS_ManualFinancialSource.SaveResult made = svc.save(i);
    i.brand = 'ELO';
    System.assertEquals(
      'CONFLICT',
      svc.save(i).outcome,
      'brand is part of replay payload'
    );
    i.brand = 'MASTERCARD';
    i.sourceId = made.sourceId;
    i.expectedVersion = 1;
    i.manualKey = null;
    i.brand = 'MASTERCARD';
    ALT_CLS_ManualFinancialSource.SaveResult updated = svc.save(i);
    System.assertEquals('UPDATED', updated.outcome, updated.message);
    AXF_OBJ_CreditCard__c persisted = [
      SELECT
        AXF_CC_TXT_InstitutionName__c,
        AXF_CC_TXT_LastFourMasked__c,
        AXF_CC_TXT_Brand__c,
        AXF_CC_NUM_Version__c
      FROM AXF_OBJ_CreditCard__c
      WHERE Id = :made.sourceId
    ];
    System.assertEquals(
      'Banco Manual',
      persisted.AXF_CC_TXT_InstitutionName__c
    );
    System.assertEquals('****1234', persisted.AXF_CC_TXT_LastFourMasked__c);
    System.assertEquals('MASTERCARD', persisted.AXF_CC_TXT_Brand__c);
    System.assertEquals(2, persisted.AXF_CC_NUM_Version__c);
    System.assertEquals('CONFLICT', svc.save(i).outcome);
  }
  @IsTest
  static void deniesAndValidatesWithoutDml() {
    Account a = holder();
    ALT_CLS_ManualFinancialSource.SaveInput i = input(a, 'BANK', 'not-a-uuid');
    ALT_CLS_ManualFinancialSource.canConfigureOverride = false;
    System.assertEquals(
      'FORBIDDEN',
      new ALT_CLS_ManualFinancialSource().save(i).outcome
    );
    ALT_CLS_ManualFinancialSource.canConfigureOverride = true;
    System.assertEquals(
      'INVALID',
      new ALT_CLS_ManualFinancialSource().save(i).outcome
    );
    i.manualKey = '123e4567-e89b-42d3-a456-426614174002';
    i.maskedNumber = '123456789';
    System.assertEquals(
      'INVALID',
      new ALT_CLS_ManualFinancialSource().save(i).outcome
    );
    System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_BankAccount__c]);
  }
  @IsTest
  static void deniesMissingCrudOrFls() {
    ALT_CLS_ManualFinancialSource.canConfigureOverride = true;
    ALT_CLS_ManualFinancialSource.sourceAccessOverride = false;
    System.assertEquals(
      'FORBIDDEN',
      new ALT_CLS_ManualFinancialSource()
        .save(input(holder(), 'BANK', '123e4567-e89b-42d3-a456-426614174003'))
        .outcome
    );
  }
  @IsTest
  static void skippingManualSourcesCreatesNoFinancialRecords() {
    ALT_CLS_AxonOnboardingProgress.canConfigureOverride = true;
    ALT_CLS_AxonOnboardingProgress service = new ALT_CLS_AxonOnboardingProgress();
    ALT_CLS_AxonOnboardingProgress.OnboardingState state = service.getState();

    ALT_CLS_AxonOnboardingProgress.OnboardingState skipped = service.skipStep(
      'MANUAL_SOURCES',
      state.version
    );

    System.assertEquals(
      'SKIPPED',
      skipped.outcome,
      'MANUAL_SOURCES must retain the existing skip outcome'
    );
    System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_BankAccount__c]);
    System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_CreditCard__c]);
    System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_AccountHolder__c]);
  }
  @IsTest
  static void evaluatesRealCrudAndFlsForBothSourceKinds() {
    ALT_CLS_ManualFinancialSource.sourceAccessOverride = null;
    Account a = holder();
    ALT_CLS_ManualFinancialSource.SaveInput bank = input(
      a,
      'BANK',
      '123e4567-e89b-42d3-a456-426614174004'
    );
    ALT_CLS_ManualFinancialSource.SaveInput card = input(
      a,
      'CARD',
      '123e4567-e89b-42d3-a456-426614174005'
    );
    System.assertNotEquals(
      null,
      ALT_CLS_ManualFinancialSource.hasSourceAccess(bank)
    );
    System.assertNotEquals(
      null,
      ALT_CLS_ManualFinancialSource.hasSourceAccess(card)
    );
    bank.sourceId = a.Id;
    card.sourceId = a.Id;
    System.assertNotEquals(
      null,
      ALT_CLS_ManualFinancialSource.hasSourceAccess(bank)
    );
    System.assertNotEquals(
      null,
      ALT_CLS_ManualFinancialSource.hasSourceAccess(card)
    );
  }
  @IsTest
  static void rejectsInactiveCurrencyInvalidRecordTypeAndBlankInstitution() {
    ALT_CLS_ManualFinancialSource.canConfigureOverride = true;
    ALT_CLS_ManualFinancialSource.sourceAccessOverride = true;
    Account validHolder = holder();
    ALT_CLS_ManualFinancialSource.SaveInput invalidCurrency = input(
      validHolder,
      'BANK',
      '123e4567-e89b-42d3-a456-426614174006'
    );
    invalidCurrency.currencyIsoCode = 'ZZZ';
    System.assertEquals(
      'INVALID',
      new ALT_CLS_ManualFinancialSource().save(invalidCurrency).outcome
    );
    ALT_CLS_ManualFinancialSource.SaveInput blankInstitution = input(
      validHolder,
      'BANK',
      '123e4567-e89b-42d3-a456-426614174007'
    );
    blankInstitution.institutionName = ' ';
    System.assertEquals(
      'INVALID',
      new ALT_CLS_ManualFinancialSource().save(blankInstitution).outcome
    );
    Id legacyRecordTypeId = [
      SELECT Id
      FROM RecordType
      WHERE SObjectType = 'Account' AND DeveloperName = 'AXF_Person_Legacy'
      LIMIT 1
    ]
    .Id;
    Account nonHolder = new Account(
      Name = 'Legacy non-holder',
      RecordTypeId = legacyRecordTypeId
    );
    insert nonHolder;
    ALT_CLS_ManualFinancialSource.SaveInput invalidRecordType = input(
      nonHolder,
      'BANK',
      '123e4567-e89b-42d3-a456-426614174008'
    );
    System.assertEquals(
      'FORBIDDEN',
      new ALT_CLS_ManualFinancialSource().save(invalidRecordType).outcome
    );
    System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_BankAccount__c]);
    System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_AccountHolder__c]);
  }
  @IsTest
  static void rejectsProtectedMutationWithoutPartialEffects() {
    ALT_CLS_ManualFinancialSource.canConfigureOverride = true;
    ALT_CLS_ManualFinancialSource.sourceAccessOverride = true;
    Account originalHolder = holder();
    Account replacementHolder = holder();
    ALT_CLS_ManualFinancialSource service = new ALT_CLS_ManualFinancialSource();
    ALT_CLS_ManualFinancialSource.SaveInput createInput = input(
      originalHolder,
      'BANK',
      '123e4567-e89b-42d3-a456-426614174009'
    );
    ALT_CLS_ManualFinancialSource.SaveResult created = service.save(
      createInput
    );
    createInput.sourceId = created.sourceId;
    createInput.manualKey = null;
    createInput.expectedVersion = 1;
    createInput.holderId = replacementHolder.Id;
    System.assertEquals('INVALID', service.save(createInput).outcome);

    AXF_OBJ_BankAccount__c unchanged = [
      SELECT
        AXF_BA_LKP_Account__c,
        AXF_BA_TXT_CurrencyIsoCode__c,
        AXF_BA_NUM_Version__c
      FROM AXF_OBJ_BankAccount__c
      WHERE Id = :created.sourceId
    ];
    System.assertEquals(originalHolder.Id, unchanged.AXF_BA_LKP_Account__c);
    System.assertEquals(
      UserInfo.getDefaultCurrency(),
      unchanged.AXF_BA_TXT_CurrencyIsoCode__c
    );
    System.assertEquals(1, unchanged.AXF_BA_NUM_Version__c);
    System.assertEquals(1, [SELECT COUNT() FROM AXF_OBJ_AccountHolder__c]);

    unchanged.AXF_BA_TXT_CurrencyIsoCode__c = UserInfo.getDefaultCurrency() ==
      'BRL'
      ? 'USD'
      : 'BRL';
    update unchanged;
    createInput.holderId = originalHolder.Id;
    System.assertEquals('INVALID', service.save(createInput).outcome);
    System.assertEquals(1, [SELECT COUNT() FROM AXF_OBJ_AccountHolder__c]);
  }
  @IsTest
  static void leavesPluggyCustodySourceUnchanged() {
    ALT_CLS_ManualFinancialSource.canConfigureOverride = true;
    ALT_CLS_ManualFinancialSource.sourceAccessOverride = true;
    Account a = holder();
    AXF_OBJ_PluggyConnection__c connection = AXF_CLS_PluggyTestData.connection(
      'MANUAL_REGRESSION'
    );
    AXF_OBJ_BankAccount__c pluggy = new AXF_OBJ_BankAccount__c(
      AXF_BA_EXI_PluggyAccountId__c = 'PLUGGY-UNCHANGED',
      AXF_BA_LKP_Connection__c = connection.Id,
      AXF_BA_PKL_AvailabilityState__c = 'CUSTODY',
      AXF_BA_NUM_Version__c = 1
    );
    insert pluggy;
    ALT_CLS_ManualFinancialSource.SaveInput editAttempt = input(
      a,
      'BANK',
      '123e4567-e89b-42d3-a456-426614174010'
    );
    editAttempt.sourceId = pluggy.Id;
    editAttempt.expectedVersion = 1;
    System.assertEquals(
      'INVALID',
      new ALT_CLS_ManualFinancialSource().save(editAttempt).outcome
    );
    AXF_OBJ_BankAccount__c unchanged = [
      SELECT
        AXF_BA_EXI_PluggyAccountId__c,
        AXF_BA_LKP_Connection__c,
        AXF_BA_PKL_AvailabilityState__c,
        AXF_BA_EXI_ManualKey__c
      FROM AXF_OBJ_BankAccount__c
      WHERE Id = :pluggy.Id
    ];
    System.assertEquals(
      'PLUGGY-UNCHANGED',
      unchanged.AXF_BA_EXI_PluggyAccountId__c
    );
    System.assertEquals(connection.Id, unchanged.AXF_BA_LKP_Connection__c);
    System.assertEquals('CUSTODY', unchanged.AXF_BA_PKL_AvailabilityState__c);
    System.assertEquals(null, unchanged.AXF_BA_EXI_ManualKey__c);
    System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_AccountHolder__c]);
  }
  @IsTest
  static void metadataRulesRejectInvalidDirectDml() {
    Account a = holder();
    AXF_OBJ_BankAccount__c bank = new AXF_OBJ_BankAccount__c(
      AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE'
    );
    AXF_OBJ_CreditCard__c card = new AXF_OBJ_CreditCard__c(
      AXF_CC_PKL_AvailabilityState__c = 'AVAILABLE'
    );
    insert bank;
    insert card;
    AXF_OBJ_AccountHolder__c invalid = new AXF_OBJ_AccountHolder__c(
      AXF_ACH_LKP_Account__c = a.Id,
      AXF_ACH_PKL_Role__c = 'PRIMARY',
      AXF_ACH_PKL_State__c = 'CONFIRMED',
      AXF_ACH_DAT_ValidFrom__c = Date.today(),
      AXF_ACH_NUM_Version__c = 1,
      AXF_ACH_EXI_FramedKey__c = 'invalid-xor'
    );
    Database.SaveResult noTarget = Database.insert(invalid, false);
    System.assertEquals(
      false,
      noTarget.isSuccess(),
      'ACH requires exactly one target'
    );
    invalid.AXF_ACH_LKP_BankAccount__c = bank.Id;
    invalid.AXF_ACH_LKP_CreditCard__c = card.Id;
    invalid.AXF_ACH_EXI_FramedKey__c = 'invalid-both';
    System.assertEquals(
      false,
      Database.insert(invalid, false).isSuccess(),
      'ACH rejects both targets'
    );
    invalid.AXF_ACH_LKP_CreditCard__c = null;
    invalid.AXF_ACH_DAT_ValidTo__c = Date.today().addDays(-1);
    invalid.AXF_ACH_EXI_FramedKey__c = 'invalid-period';
    System.assertEquals(
      false,
      Database.insert(invalid, false).isSuccess(),
      'ACH rejects inverted validity'
    );
    Database.SaveResult badBank = Database.insert(
      new AXF_OBJ_BankAccount__c(
        AXF_BA_EXI_ManualKey__c = '123e4567-e89b-42d3-a456-426614174011',
        AXF_BA_EXI_PluggyAccountId__c = 'pluggy-bank',
        AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE'
      ),
      false
    );
    Database.SaveResult badCard = Database.insert(
      new AXF_OBJ_CreditCard__c(
        AXF_CC_EXI_ManualKey__c = '123e4567-e89b-42d3-a456-426614174012',
        AXF_CC_EXI_PluggyAccountId__c = 'pluggy-card',
        AXF_CC_PKL_AvailabilityState__c = 'AVAILABLE'
      ),
      false
    );
    System.assertEquals(
      false,
      badBank.isSuccess(),
      'bank manual and Pluggy identities are exclusive'
    );
    System.assertEquals(
      false,
      badCard.isSuccess(),
      'card manual and Pluggy identities are exclusive'
    );
  }

  @IsTest
  static void sharedOperationKeyRejectsCrossKindDuplicate() {
    Account a = holder();
    AXF_OBJ_BankAccount__c bank = new AXF_OBJ_BankAccount__c(
      AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE'
    );
    AXF_OBJ_CreditCard__c card = new AXF_OBJ_CreditCard__c(
      AXF_CC_PKL_AvailabilityState__c = 'AVAILABLE'
    );
    insert bank;
    insert card;
    String operationKey = '123e4567-e89b-42d3-a456-426614174013';
    insert new AXF_OBJ_AccountHolder__c(
      AXF_ACH_LKP_Account__c = a.Id,
      AXF_ACH_LKP_BankAccount__c = bank.Id,
      AXF_ACH_PKL_Role__c = 'PRIMARY',
      AXF_ACH_PKL_State__c = 'CONFIRMED',
      AXF_ACH_DAT_ValidFrom__c = Date.today(),
      AXF_ACH_NUM_Version__c = 1,
      AXF_ACH_EXI_FramedKey__c = 'bank-registry',
      AXF_ACH_EXI_ManualOperationKey__c = operationKey
    );

    Database.SaveResult duplicate = Database.insert(
      new AXF_OBJ_AccountHolder__c(
        AXF_ACH_LKP_Account__c = a.Id,
        AXF_ACH_LKP_CreditCard__c = card.Id,
        AXF_ACH_PKL_Role__c = 'PRIMARY',
        AXF_ACH_PKL_State__c = 'CONFIRMED',
        AXF_ACH_DAT_ValidFrom__c = Date.today(),
        AXF_ACH_NUM_Version__c = 1,
        AXF_ACH_EXI_FramedKey__c = 'card-registry',
        AXF_ACH_EXI_ManualOperationKey__c = operationKey
      ),
      false
    );

    System.assertEquals(
      false,
      duplicate.isSuccess(),
      'one operation key is atomic across bank and card sources'
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM AXF_OBJ_AccountHolder__c
        WHERE AXF_ACH_EXI_ManualOperationKey__c = :operationKey
      ],
      'the losing registry insert must leave no partial holder record'
    );
  }
}
