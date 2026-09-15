/**
 * @description Tests for ALT_CLS_SourceHolderConfirmation (AXF-85). Effective
 * paths run as a real configurator (System Administrator + AXF_PSG_GestorFinanceiro)
 * so USER_MODE reads of the custody sources reflect real record access.
 */
@IsTest(isParallel=false)
private class ALT_CLS_SourceHolderConfirmationTest {
  private static ALT_CLS_SourceHolderConfirmation svc() {
    return new ALT_CLS_SourceHolderConfirmation();
  }

  private static User configurator() {
    Profile admin = [
      SELECT Id
      FROM Profile
      WHERE Name = 'System Administrator'
      LIMIT 1
    ];
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
      ProfileId = admin.Id,
      LastName = 'Cfg AXF85',
      Email = 'axf85.cfg@example.com',
      Username = 'axf85.cfg.' +
        Crypto.getRandomInteger() +
        '@example.com.invalid',
      Alias = 'a85c',
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

  private static Account business(String name) {
    Account a = new Account(Name = name, RecordTypeId = rt('AXF_Business'));
    insert a;
    return [SELECT Id, OwnerId FROM Account WHERE Id = :a.Id];
  }

  private static AXF_OBJ_BankAccount__c custodyBank(String inst) {
    AXF_OBJ_BankAccount__c b = new AXF_OBJ_BankAccount__c(
      AXF_BA_PKL_AvailabilityState__c = 'CUSTODY',
      AXF_BA_TXT_InstitutionName__c = inst,
      AXF_BA_TXT_NumberMasked__c = '****1234',
      AXF_BA_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BA_NUM_Version__c = 0
    );
    Database.insert(b, AccessLevel.SYSTEM_MODE);
    return b;
  }

  private static AXF_OBJ_CreditCard__c custodyCard(String inst) {
    AXF_OBJ_CreditCard__c c = new AXF_OBJ_CreditCard__c(
      AXF_CC_PKL_AvailabilityState__c = 'CUSTODY',
      AXF_CC_TXT_InstitutionName__c = inst,
      AXF_CC_TXT_LastFourMasked__c = '7788',
      AXF_CC_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_CC_NUM_Version__c = 0
    );
    Database.insert(c, AccessLevel.SYSTEM_MODE);
    return c;
  }

  private static ALT_CLS_SourceHolderConfirmation.ConfirmInput input(
    Id sourceId,
    String kind,
    Id holderId,
    Integer version
  ) {
    ALT_CLS_SourceHolderConfirmation.ConfirmInput i = new ALT_CLS_SourceHolderConfirmation.ConfirmInput();
    i.sourceId = sourceId;
    i.kind = kind;
    i.holderId = holderId;
    i.expectedVersion = version;
    return i;
  }

  private static AXF_OBJ_BankAccount__c reloadBank(Id id) {
    return [
      SELECT
        Id,
        OwnerId,
        AXF_BA_LKP_Account__c,
        AXF_BA_LKP_BankInstitution__c,
        AXF_BA_PKL_AvailabilityState__c,
        AXF_BA_NUM_Version__c
      FROM AXF_OBJ_BankAccount__c
      WHERE Id = :id
    ];
  }

  @IsTest
  static void overviewForbiddenWithoutAuthority() {
    ALT_CLS_SourceHolderConfirmation.canConfigureOverride = false;
    Test.startTest();
    ALT_CLS_SourceHolderConfirmation.Overview o = svc().overview();
    Test.stopTest();
    System.assert(o.forbidden);
    System.assertEquals(0, o.pending.size());
  }

  @IsTest
  static void confirmCreatesAchSyncsOwnerAndReleasesSource() {
    User cfg = configurator();
    System.runAs(cfg) {
      Account p = person('Almeida');
      AXF_OBJ_BankAccount__c b = custodyBank('Banco Um');

      Test.startTest();
      ALT_CLS_SourceHolderConfirmation.ConfirmResult r = svc()
        .confirmHolder(input(b.Id, 'BANK', p.Id, 0));
      Test.stopTest();

      System.assertEquals('CONFIRMED', r.outcome);
      System.assertEquals(1, r.version);
      System.assertEquals('AVAILABLE', r.availabilityState);
      System.assertNotEquals(null, r.accountHolderId);

      AXF_OBJ_BankAccount__c fresh = reloadBank(b.Id);
      System.assertEquals(p.Id, fresh.AXF_BA_LKP_Account__c);
      System.assertEquals(p.OwnerId, fresh.OwnerId, 'owner synced (G2-2)');
      System.assertEquals('AVAILABLE', fresh.AXF_BA_PKL_AvailabilityState__c);
      System.assertEquals(1, fresh.AXF_BA_NUM_Version__c);

      AXF_OBJ_AccountHolder__c ach = [
        SELECT
          AXF_ACH_LKP_Account__c,
          AXF_ACH_LKP_BankAccount__c,
          AXF_ACH_PKL_Role__c,
          AXF_ACH_PKL_State__c
        FROM AXF_OBJ_AccountHolder__c
        WHERE AXF_ACH_LKP_BankAccount__c = :b.Id
      ];
      System.assertEquals(p.Id, ach.AXF_ACH_LKP_Account__c);
      System.assertEquals('PRIMARY', ach.AXF_ACH_PKL_Role__c);
      System.assertEquals('CONFIRMED', ach.AXF_ACH_PKL_State__c);
    }
  }

  @IsTest
  static void rejectsMissingFieldsBadKindUnknownHolderAndSource() {
    ALT_CLS_SourceHolderConfirmation.canConfigureOverride = true;
    Account p = person('Valido');
    AXF_OBJ_BankAccount__c b = custodyBank('B');
    Id ghostAccount = '001000000000000AAA';
    Test.startTest();
    System.assertEquals(
      'INVALID',
      svc().confirmHolder(input(null, 'BANK', p.Id, 0)).outcome
    );
    System.assertEquals(
      'INVALID',
      svc().confirmHolder(input(b.Id, 'NOPE', p.Id, 0)).outcome
    );
    System.assertEquals(
      'INVALID',
      svc().confirmHolder(input(b.Id, 'BANK', p.Id, null)).outcome,
      'missing expectedVersion'
    );
    System.assertEquals(
      'NOT_FOUND',
      svc().confirmHolder(input(b.Id, 'BANK', ghostAccount, 0)).outcome,
      'holder that does not exist / not visible'
    );
    Test.stopTest();
  }

  @IsTest
  static void confirmForbiddenWithoutAuthority() {
    ALT_CLS_SourceHolderConfirmation.canConfigureOverride = false;
    Account p = person('X');
    AXF_OBJ_BankAccount__c b = custodyBank('B');
    Test.startTest();
    System.assertEquals(
      'FORBIDDEN',
      svc().confirmHolder(input(b.Id, 'BANK', p.Id, 0)).outcome
    );
    Test.stopTest();
    System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_AccountHolder__c]);
  }

  @IsTest
  static void idempotentSameHolderAndStaleConflict() {
    User cfg = configurator();
    System.runAs(cfg) {
      Account p = person('Souza');
      AXF_OBJ_BankAccount__c b = custodyBank('Banco Dois');
      ALT_CLS_SourceHolderConfirmation.ConfirmResult r1 = svc()
        .confirmHolder(input(b.Id, 'BANK', p.Id, 0));
      System.assertEquals('CONFIRMED', r1.outcome);

      Test.startTest();
      ALT_CLS_SourceHolderConfirmation.ConfirmResult again = svc()
        .confirmHolder(input(b.Id, 'BANK', p.Id, r1.version));
      ALT_CLS_SourceHolderConfirmation.ConfirmResult stale = svc()
        .confirmHolder(input(b.Id, 'BANK', p.Id, 0));
      Test.stopTest();

      System.assertEquals('ALREADY', again.outcome);
      System.assertEquals('CONFLICT', stale.outcome);
      System.assertEquals(
        1,
        [SELECT COUNT() FROM AXF_OBJ_AccountHolder__c],
        'no duplicate ACH'
      );
    }
  }

  @IsTest
  static void correctionSupersedesPreviousAndReactivatesOnReturn() {
    User cfg = configurator();
    System.runAs(cfg) {
      Account a = person('Titular A');
      Account bHolder = business('Empresa B');
      AXF_OBJ_BankAccount__c src = custodyBank('Banco Tres');

      ALT_CLS_SourceHolderConfirmation.ConfirmResult c1 = svc()
        .confirmHolder(input(src.Id, 'BANK', a.Id, 0));

      Test.startTest();
      ALT_CLS_SourceHolderConfirmation.ConfirmResult c2 = svc()
        .confirmHolder(input(src.Id, 'BANK', bHolder.Id, c1.version));
      Test.stopTest();

      System.assertEquals('CORRECTED', c2.outcome);
      AXF_OBJ_BankAccount__c fresh = reloadBank(src.Id);
      System.assertEquals(bHolder.Id, fresh.AXF_BA_LKP_Account__c);
      System.assertEquals(bHolder.OwnerId, fresh.OwnerId);

      Map<Id, AXF_OBJ_AccountHolder__c> byHolder = new Map<Id, AXF_OBJ_AccountHolder__c>();
      for (AXF_OBJ_AccountHolder__c h : [
        SELECT
          AXF_ACH_LKP_Account__c,
          AXF_ACH_PKL_State__c,
          AXF_ACH_DAT_ValidTo__c
        FROM AXF_OBJ_AccountHolder__c
        WHERE AXF_ACH_LKP_BankAccount__c = :src.Id
      ]) {
        byHolder.put(h.AXF_ACH_LKP_Account__c, h);
      }
      System.assertEquals(
        2,
        byHolder.size(),
        'previous ACH kept for history (AC5)'
      );
      System.assertEquals(
        'SUPERSEDED',
        byHolder.get(a.Id).AXF_ACH_PKL_State__c
      );
      System.assertEquals(
        Date.today(),
        byHolder.get(a.Id).AXF_ACH_DAT_ValidTo__c
      );
      System.assertEquals(
        'CONFIRMED',
        byHolder.get(bHolder.Id).AXF_ACH_PKL_State__c
      );

      // return to holder A — reactivate its row
      ALT_CLS_SourceHolderConfirmation.ConfirmResult c3 = svc()
        .confirmHolder(
          input(src.Id, 'BANK', a.Id, fresh.AXF_BA_NUM_Version__c.intValue())
        );
      System.assertEquals('CORRECTED', c3.outcome);
      AXF_OBJ_AccountHolder__c aRow = [
        SELECT AXF_ACH_PKL_State__c, AXF_ACH_DAT_ValidTo__c
        FROM AXF_OBJ_AccountHolder__c
        WHERE
          AXF_ACH_LKP_BankAccount__c = :src.Id
          AND AXF_ACH_LKP_Account__c = :a.Id
      ];
      System.assertEquals('CONFIRMED', aRow.AXF_ACH_PKL_State__c);
      System.assertEquals(null, aRow.AXF_ACH_DAT_ValidTo__c);
    }
  }

  @IsTest
  static void cardConfirmationAndGetSourceHolder() {
    User cfg = configurator();
    System.runAs(cfg) {
      Account p = person('Dias');
      AXF_OBJ_CreditCard__c card = custodyCard('Cartão X');

      Test.startTest();
      ALT_CLS_SourceHolderConfirmation.ConfirmResult r = svc()
        .confirmHolder(input(card.Id, 'CARD', p.Id, 0));
      ALT_CLS_SourceHolderConfirmation.SourceView v = svc()
        .getSourceHolder(card.Id, 'CARD');
      Test.stopTest();

      System.assertEquals('CONFIRMED', r.outcome);
      System.assertEquals(p.Id, v.holderId);
      System.assertEquals('AVAILABLE', v.availabilityState);
      System.assertEquals('CARD', v.kind);
    }
  }

  @IsTest
  static void overviewSeparatesPendingFromReleased() {
    User cfg = configurator();
    System.runAs(cfg) {
      Account p = person('Rocha');
      AXF_OBJ_BankAccount__c pending = custodyBank('Pendente');
      AXF_OBJ_BankAccount__c released = custodyBank('Liberada');
      svc().confirmHolder(input(released.Id, 'BANK', p.Id, 0));

      Test.startTest();
      ALT_CLS_SourceHolderConfirmation.Overview o = svc().overview();
      Test.stopTest();

      Set<Id> pendingIds = new Set<Id>();
      for (ALT_CLS_SourceHolderConfirmation.SourceView v : o.pending) {
        pendingIds.add(v.sourceId);
      }
      Set<Id> releasedIds = new Set<Id>();
      for (ALT_CLS_SourceHolderConfirmation.SourceView v : o.released) {
        releasedIds.add(v.sourceId);
      }
      System.assert(pendingIds.contains(pending.Id));
      System.assert(releasedIds.contains(released.Id));
      System.assert(!pendingIds.contains(released.Id));
    }
  }

  @IsTest
  static void custodySourceInvisibleToParticipant() {
    User cfg = configurator();
    AXF_OBJ_BankAccount__c b;
    System.runAs(cfg) {
      b = custodyBank('Reservada');
    }
    // a plain user without AXF_CanConfigure
    User outsider;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Profile min = [
        SELECT Id
        FROM Profile
        WHERE Name = 'Minimum Access - Salesforce'
        LIMIT 1
      ];
      outsider = new User(
        ProfileId = min.Id,
        LastName = 'Outsider',
        Email = 'axf85.out@example.com',
        Username = 'axf85.out.' +
          Crypto.getRandomInteger() +
          '@example.com.invalid',
        Alias = 'a85o',
        TimeZoneSidKey = 'America/Sao_Paulo',
        LocaleSidKey = 'pt_BR',
        EmailEncodingKey = 'UTF-8',
        LanguageLocaleKey = 'pt_BR'
      );
      insert outsider;
    }
    Test.startTest();
    System.runAs(outsider) {
      ALT_CLS_SourceHolderConfirmation.Overview o = svc().overview();
      System.assert(o.forbidden, 'no authority => forbidden surface (AC3)');
    }
    Test.stopTest();
  }

  // ---- controller delegation (folded in — the dedicated test class name
  //      exceeds the 40-char Apex identifier limit) ----
  @IsTest
  static void controllerDelegatesOverviewConfirmAndRead() {
    ALT_CLS_SourceHolderConfirmation.canConfigureOverride = true;
    Account p = person('Ctrl');
    AXF_OBJ_BankAccount__c b = custodyBank('Banco Ctrl');

    Test.startTest();
    ALT_CLS_SourceHolderConfirmation.Overview o = AXF_CLS_CTRL_SourceHolderConfirmation.getOverview();
    System.assertEquals(false, o.forbidden);

    ALT_CLS_SourceHolderConfirmation.ConfirmResult r = AXF_CLS_CTRL_SourceHolderConfirmation.confirmHolder(
      b.Id,
      'BANK',
      p.Id,
      0,
      null
    );
    System.assertEquals('CONFIRMED', r.outcome);

    ALT_CLS_SourceHolderConfirmation.SourceView v = AXF_CLS_CTRL_SourceHolderConfirmation.getSourceHolder(
      b.Id,
      'BANK'
    );
    Test.stopTest();
    System.assertEquals(p.Id, v.holderId);
  }

  @IsTest
  static void controllerForbiddenWithoutAuthority() {
    ALT_CLS_SourceHolderConfirmation.canConfigureOverride = false;
    Test.startTest();
    System.assert(
      AXF_CLS_CTRL_SourceHolderConfirmation.getOverview().forbidden
    );
    Test.stopTest();
  }

  // ================= AXF-106 — connection references applied by discovery =================

  private static AXF_OBJ_BankInstitution__c bankInstitution(String name) {
    AXF_OBJ_BankInstitution__c b = new AXF_OBJ_BankInstitution__c(
      Name = name,
      AXF_BI_EXI_Bank_Number__c = uniqueCode()
    );
    Database.insert(b, AccessLevel.SYSTEM_MODE);
    return b;
  }

  /** @description AXF_BI_EXI_Bank_Number__c holds at most 8 characters. */
  private static String uniqueCode() {
    String n = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
    return n.length() > 8 ? n.substring(0, 8) : n;
  }

  private static AXF_OBJ_PluggyConnection__c pluggyConnection(
    Id bankInstitutionId,
    Id holderId
  ) {
    AXF_OBJ_PluggyConnection__c c = new AXF_OBJ_PluggyConnection__c(
      AXF_CON_EXI_PluggyItemId__c = 'ITEM-' + uniqueCode(),
      AXF_CON_PKL_ConsentState__c = 'ACTIVE',
      AXF_CON_PKL_CollectionState__c = 'ACTIVE',
      AXF_CON_TXT_InstitutionName__c = 'Banco da Conexao',
      AXF_CON_LKP_BankInstitution__c = bankInstitutionId,
      AXF_CON_LKP_Account__c = holderId
    );
    Database.insert(c, AccessLevel.SYSTEM_MODE);
    return c;
  }

  private static AXF_OBJ_BankAccount__c connectedBank(
    Id connectionId,
    String pluggyId
  ) {
    AXF_OBJ_BankAccount__c b = new AXF_OBJ_BankAccount__c(
      AXF_BA_LKP_Connection__c = connectionId,
      AXF_BA_EXI_PluggyAccountId__c = pluggyId,
      AXF_BA_PKL_AvailabilityState__c = 'CUSTODY',
      AXF_BA_TXT_InstitutionName__c = 'Banco Exemplo',
      AXF_BA_TXT_NumberMasked__c = '****4321',
      AXF_BA_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BA_NUM_Version__c = 0
    );
    Database.insert(b, AccessLevel.SYSTEM_MODE);
    return b;
  }

  private static AXF_OBJ_CreditCard__c connectedCard(
    Id connectionId,
    String pluggyId
  ) {
    AXF_OBJ_CreditCard__c c = new AXF_OBJ_CreditCard__c(
      AXF_CC_LKP_Connection__c = connectionId,
      AXF_CC_EXI_PluggyAccountId__c = pluggyId,
      AXF_CC_PKL_AvailabilityState__c = 'CUSTODY',
      AXF_CC_TXT_InstitutionName__c = 'Banco Exemplo',
      AXF_CC_TXT_LastFourMasked__c = '9999',
      AXF_CC_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_CC_NUM_Version__c = 0
    );
    Database.insert(c, AccessLevel.SYSTEM_MODE);
    return c;
  }

  private static ALT_CLS_SourceHolderConfirmation.SourceRef sourceRef(
    Id sourceId,
    String kind,
    Integer expectedVersion
  ) {
    ALT_CLS_SourceHolderConfirmation.SourceRef ref = new ALT_CLS_SourceHolderConfirmation.SourceRef();
    ref.sourceId = sourceId;
    ref.kind = kind;
    ref.expectedVersion = expectedVersion;
    return ref;
  }

  private static ALT_CLS_SourceHolderConfirmation.ConnectionReferenceInput applyInput(
    Id connectionId,
    Id bankInstitutionId,
    Id holderId,
    List<ALT_CLS_SourceHolderConfirmation.SourceRef> refs
  ) {
    ALT_CLS_SourceHolderConfirmation.ConnectionReferenceInput input = new ALT_CLS_SourceHolderConfirmation.ConnectionReferenceInput();
    input.connectionId = connectionId;
    input.bankInstitutionId = bankInstitutionId;
    input.holderId = holderId;
    input.sources = refs;
    return input;
  }

  private static AXF_OBJ_CreditCard__c reloadCard(Id id) {
    return [
      SELECT
        Id,
        OwnerId,
        AXF_CC_LKP_Account__c,
        AXF_CC_LKP_BankInstitution__c,
        AXF_CC_PKL_AvailabilityState__c,
        AXF_CC_NUM_Version__c
      FROM AXF_OBJ_CreditCard__c
      WHERE Id = :id
    ];
  }

  @IsTest
  static void applyConnectionReferencesLinksAndReleasesEveryEligibleSource() {
    ALT_CLS_SourceHolderConfirmation.canConfigureOverride = true;
    Account p = person('Aplicada');
    AXF_OBJ_BankInstitution__c inst = bankInstitution('Banco Aplicado');
    AXF_OBJ_PluggyConnection__c c = pluggyConnection(inst.Id, p.Id);
    AXF_OBJ_BankAccount__c b1 = connectedBank(c.Id, 'ACC-A');
    AXF_OBJ_BankAccount__c b2 = connectedBank(c.Id, 'ACC-B');
    AXF_OBJ_CreditCard__c card = connectedCard(c.Id, 'CARD-A');

    Test.startTest();
    ALT_CLS_SourceHolderConfirmation.ApplyResult r = svc()
      .applyConnectionReferences(
        applyInput(
          c.Id,
          inst.Id,
          p.Id,
          new List<ALT_CLS_SourceHolderConfirmation.SourceRef>{
            sourceRef(b1.Id, 'BANK', 0),
            sourceRef(b2.Id, 'BANK', 0),
            sourceRef(card.Id, 'CARD', 0)
          }
        )
      );
    Test.stopTest();

    System.assertEquals('APPLIED', r.outcome, r.message);
    System.assertEquals(3, r.applied);
    System.assertEquals(3, r.released);
    System.assertEquals(0, r.pending);
    System.assertEquals(0, r.divergent);

    AXF_OBJ_BankAccount__c fresh = reloadBank(b1.Id);
    System.assertEquals('AVAILABLE', fresh.AXF_BA_PKL_AvailabilityState__c);
    System.assertEquals(p.Id, fresh.AXF_BA_LKP_Account__c);
    System.assertEquals(p.OwnerId, fresh.OwnerId, 'owner synced (G2-2)');
    System.assertEquals(1, fresh.AXF_BA_NUM_Version__c);

    AXF_OBJ_CreditCard__c freshCard = reloadCard(card.Id);
    System.assertEquals('AVAILABLE', freshCard.AXF_CC_PKL_AvailabilityState__c);
    System.assertEquals(p.Id, freshCard.AXF_CC_LKP_Account__c);

    System.assertEquals(
      3,
      [
        SELECT COUNT()
        FROM AXF_OBJ_AccountHolder__c
        WHERE
          AXF_ACH_PKL_Role__c = 'PRIMARY'
          AND AXF_ACH_PKL_State__c = 'CONFIRMED'
      ],
      'one definitive link per source'
    );
  }

  @IsTest
  static void applyWithoutHolderAppliesBankAndKeepsSourcesInCustody() {
    ALT_CLS_SourceHolderConfirmation.canConfigureOverride = true;
    AXF_OBJ_BankInstitution__c inst = bankInstitution('Banco Somente');
    AXF_OBJ_PluggyConnection__c c = pluggyConnection(inst.Id, null);
    AXF_OBJ_BankAccount__c b = connectedBank(c.Id, 'ACC-NOHOLDER');

    Test.startTest();
    ALT_CLS_SourceHolderConfirmation.ApplyResult r = svc()
      .applyConnectionReferences(
        applyInput(
          c.Id,
          inst.Id,
          null,
          new List<ALT_CLS_SourceHolderConfirmation.SourceRef>{
            sourceRef(b.Id, 'BANK', 0)
          }
        )
      );
    Test.stopTest();

    System.assertEquals(1, r.applied, 'the bank is applied');
    System.assertEquals(0, r.released);
    System.assertEquals(1, r.pending, 'no holder => explicit pendency');
    AXF_OBJ_BankAccount__c fresh = reloadBank(b.Id);
    System.assertEquals('CUSTODY', fresh.AXF_BA_PKL_AvailabilityState__c);
    System.assertEquals(null, fresh.AXF_BA_LKP_Account__c);
    System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_AccountHolder__c]);
  }

  @IsTest
  static void applyWithoutBankLinksAndReleases() {
    ALT_CLS_SourceHolderConfirmation.canConfigureOverride = true;
    Account p = person('Sem Banco');
    AXF_OBJ_PluggyConnection__c c = pluggyConnection(null, p.Id);
    AXF_OBJ_BankAccount__c b = connectedBank(c.Id, 'ACC-NOBANK');

    Test.startTest();
    ALT_CLS_SourceHolderConfirmation.ApplyResult r = svc()
      .applyConnectionReferences(
        applyInput(
          c.Id,
          null,
          p.Id,
          new List<ALT_CLS_SourceHolderConfirmation.SourceRef>{
            sourceRef(b.Id, 'BANK', 0)
          }
        )
      );
    Test.stopTest();

    System.assertEquals(1, r.applied);
    System.assertEquals(1, r.released);
    AXF_OBJ_BankAccount__c fresh = reloadBank(b.Id);
    System.assertEquals('AVAILABLE', fresh.AXF_BA_PKL_AvailabilityState__c);
    System.assertEquals(
      null,
      fresh.AXF_BA_LKP_BankInstitution__c,
      'the bank stays null and visible as pending'
    );
  }

  @IsTest
  static void applyPreservesASourceWithAnotherConfirmedHolder() {
    ALT_CLS_SourceHolderConfirmation.canConfigureOverride = true;
    Account owner = person('Titular Confirmado');
    Account other = person('Titular Da Conexao');
    AXF_OBJ_PluggyConnection__c c = pluggyConnection(null, other.Id);
    AXF_OBJ_BankAccount__c b = connectedBank(c.Id, 'ACC-DIV');
    // the source was already confirmed to a different holder
    svc().confirmHolder(input(b.Id, 'BANK', owner.Id, 0));
    AXF_OBJ_BankAccount__c before = reloadBank(b.Id);

    Test.startTest();
    ALT_CLS_SourceHolderConfirmation.ApplyResult r = svc()
      .applyConnectionReferences(
        applyInput(
          c.Id,
          null,
          other.Id,
          new List<ALT_CLS_SourceHolderConfirmation.SourceRef>{
            sourceRef(b.Id, 'BANK', before.AXF_BA_NUM_Version__c.intValue())
          }
        )
      );
    Test.stopTest();

    System.assertEquals('DIVERGENT', r.outcome);
    System.assertEquals(1, r.divergent);
    System.assertEquals(0, r.applied);
    AXF_OBJ_BankAccount__c fresh = reloadBank(b.Id);
    System.assertEquals(
      owner.Id,
      fresh.AXF_BA_LKP_Account__c,
      'the confirmed holder is never overwritten'
    );
    System.assertEquals(
      before.AXF_BA_NUM_Version__c,
      fresh.AXF_BA_NUM_Version__c,
      'nothing was written'
    );
    System.assertEquals(1, [SELECT COUNT() FROM AXF_OBJ_AccountHolder__c]);
  }

  @IsTest
  static void applyAppliesNothingWhenAReferenceIsUnusable() {
    ALT_CLS_SourceHolderConfirmation.canConfigureOverride = true;
    Account p = person('Referencia');
    AXF_OBJ_PluggyConnection__c c = pluggyConnection(null, p.Id);
    AXF_OBJ_BankAccount__c b = connectedBank(c.Id, 'ACC-REF');
    // references that became unusable after being set on the connection
    Account removedHolder = person('Titular Removido');
    Id removedHolderId = removedHolder.Id;
    Database.delete(removedHolder, AccessLevel.SYSTEM_MODE);
    AXF_OBJ_BankInstitution__c removedBank = bankInstitution('Banco Removido');
    Id removedBankId = removedBank.Id;
    Database.delete(removedBank, AccessLevel.SYSTEM_MODE);
    List<ALT_CLS_SourceHolderConfirmation.SourceRef> refs = new List<ALT_CLS_SourceHolderConfirmation.SourceRef>{
      sourceRef(b.Id, 'BANK', 0)
    };

    Test.startTest();
    ALT_CLS_SourceHolderConfirmation.ApplyResult ghostHolder = svc()
      .applyConnectionReferences(applyInput(c.Id, null, removedHolderId, refs));
    ALT_CLS_SourceHolderConfirmation.ApplyResult ghostBank = svc()
      .applyConnectionReferences(applyInput(c.Id, removedBankId, p.Id, refs));
    // holder Account of a record type that is not a holder type
    ALT_CLS_SourceHolderConfirmation.ApplyResult wrongType = null;
    Schema.RecordTypeInfo foreign = foreignRecordType();
    if (foreign != null) {
      Account notAHolder = new Account(
        Name = 'Nao e titular',
        RecordTypeId = foreign.getRecordTypeId()
      );
      Database.SaveResult sr = Database.insert(
        notAHolder,
        false,
        AccessLevel.SYSTEM_MODE
      );
      if (sr.isSuccess()) {
        wrongType = svc()
          .applyConnectionReferences(
            applyInput(c.Id, null, notAHolder.Id, refs)
          );
      }
    }
    Test.stopTest();

    System.assertEquals('NOT_FOUND', ghostHolder.outcome);
    System.assertEquals(0, ghostHolder.applied);
    System.assert(
      ghostHolder.message.containsIgnoreCase('titular'),
      ghostHolder.message
    );
    System.assertEquals('NOT_FOUND', ghostBank.outcome);
    System.assertEquals(0, ghostBank.applied);
    if (wrongType != null) {
      System.assertEquals('INVALID', wrongType.outcome);
      System.assertEquals(0, wrongType.applied);
    }
    AXF_OBJ_BankAccount__c fresh = reloadBank(b.Id);
    System.assertEquals('CUSTODY', fresh.AXF_BA_PKL_AvailabilityState__c);
    System.assertEquals(null, fresh.AXF_BA_LKP_Account__c);
    System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_AccountHolder__c]);
  }

  /** @description An Account record type that is not a holder type, when the org has one. */
  private static Schema.RecordTypeInfo foreignRecordType() {
    for (
      Schema.RecordTypeInfo info : Account.SObjectType.getDescribe(
          SObjectDescribeOptions.DEFERRED
        )
        .getRecordTypeInfosByDeveloperName()
        .values()
    ) {
      String dev = info.getDeveloperName();
      if (
        dev != 'AXF_Person' &&
        dev != 'AXF_Business' &&
        !info.isMaster() &&
        info.isAvailable()
      ) {
        return info;
      }
    }
    return null;
  }

  @IsTest
  static void applyIsIdempotentAndKeepsTheReleasedSourceAvailable() {
    ALT_CLS_SourceHolderConfirmation.canConfigureOverride = true;
    Account p = person('Replay');
    AXF_OBJ_BankInstitution__c inst = bankInstitution('Banco Replay');
    AXF_OBJ_PluggyConnection__c c = pluggyConnection(inst.Id, p.Id);
    AXF_OBJ_BankAccount__c b = connectedBank(c.Id, 'ACC-REPLAY');

    ALT_CLS_SourceHolderConfirmation.ApplyResult first = svc()
      .applyConnectionReferences(
        applyInput(
          c.Id,
          inst.Id,
          p.Id,
          new List<ALT_CLS_SourceHolderConfirmation.SourceRef>{
            sourceRef(b.Id, 'BANK', 0)
          }
        )
      );
    System.assertEquals(1, first.applied);
    AXF_OBJ_BankAccount__c released = reloadBank(b.Id);

    Test.startTest();
    ALT_CLS_SourceHolderConfirmation.ApplyResult again = svc()
      .applyConnectionReferences(
        applyInput(
          c.Id,
          inst.Id,
          p.Id,
          new List<ALT_CLS_SourceHolderConfirmation.SourceRef>{
            sourceRef(b.Id, 'BANK', released.AXF_BA_NUM_Version__c.intValue())
          }
        )
      );
    Test.stopTest();

    System.assertEquals(0, again.applied);
    System.assertEquals(1, again.reused, 'nothing to write on a replay');
    // `released` states what THIS run released, never the state it found (AXF-106): a
    // replay writes nothing, so it releases nothing and leaves nothing pending — the
    // source simply stays AVAILABLE.
    System.assertEquals(0, again.released, 'a replay releases nothing new');
    System.assertEquals(0, again.pending);
    AXF_OBJ_BankAccount__c fresh = reloadBank(b.Id);
    System.assertEquals('AVAILABLE', fresh.AXF_BA_PKL_AvailabilityState__c);
    System.assertEquals(
      released.AXF_BA_NUM_Version__c,
      fresh.AXF_BA_NUM_Version__c,
      'no new Version on a replay'
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM AXF_OBJ_AccountHolder__c],
      'no duplicated link'
    );
  }

  @IsTest
  static void applyRejectsAStaleSourceAsConflict() {
    ALT_CLS_SourceHolderConfirmation.canConfigureOverride = true;
    Account p = person('Conflito');
    AXF_OBJ_PluggyConnection__c c = pluggyConnection(null, p.Id);
    AXF_OBJ_BankAccount__c b = connectedBank(c.Id, 'ACC-STALE');
    // the source changed after the caller read version 0
    svc().confirmHolder(input(b.Id, 'BANK', p.Id, 0));

    Test.startTest();
    ALT_CLS_SourceHolderConfirmation.ApplyResult r = svc()
      .applyConnectionReferences(
        applyInput(
          c.Id,
          null,
          p.Id,
          new List<ALT_CLS_SourceHolderConfirmation.SourceRef>{
            sourceRef(b.Id, 'BANK', 0)
          }
        )
      );
    Test.stopTest();

    System.assertEquals(1, r.conflicts);
    System.assertEquals(0, r.applied);
    System.assert(
      r.details[0].message.containsIgnoreCase('alterada'),
      'CONFLICT'
    );
    System.assertEquals(1, [SELECT COUNT() FROM AXF_OBJ_AccountHolder__c]);
  }

  @IsTest
  static void applyIgnoresIncompleteSourcesAndForeignConnections() {
    ALT_CLS_SourceHolderConfirmation.canConfigureOverride = true;
    Account p = person('Ignorada');
    AXF_OBJ_PluggyConnection__c c = pluggyConnection(null, p.Id);
    AXF_OBJ_PluggyConnection__c otherConnection = pluggyConnection(null, p.Id);
    // no PluggyAccountId
    AXF_OBJ_BankAccount__c incomplete = custodyBank('Sem Identidade');
    Database.update(
      new AXF_OBJ_BankAccount__c(
        Id = incomplete.Id,
        AXF_BA_LKP_Connection__c = c.Id
      ),
      AccessLevel.SYSTEM_MODE
    );
    // belongs to another connection
    AXF_OBJ_BankAccount__c foreign = connectedBank(
      otherConnection.Id,
      'ACC-FOREIGN'
    );

    Test.startTest();
    ALT_CLS_SourceHolderConfirmation.ApplyResult r = svc()
      .applyConnectionReferences(
        applyInput(
          c.Id,
          null,
          p.Id,
          new List<ALT_CLS_SourceHolderConfirmation.SourceRef>{
            sourceRef(incomplete.Id, 'BANK', null),
            sourceRef(foreign.Id, 'BANK', null),
            sourceRef(null, 'BANK', null)
          }
        )
      );
    Test.stopTest();

    System.assertEquals(3, r.ignored);
    System.assertEquals(0, r.applied);
    System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_AccountHolder__c]);
    System.assertEquals(
      'CUSTODY',
      reloadBank(incomplete.Id).AXF_BA_PKL_AvailabilityState__c
    );
  }

  @IsTest
  static void applyForbiddenWithoutAuthority() {
    ALT_CLS_SourceHolderConfirmation.canConfigureOverride = false;
    Account p = person('Negada');
    AXF_OBJ_PluggyConnection__c c = pluggyConnection(null, p.Id);
    AXF_OBJ_BankAccount__c b = connectedBank(c.Id, 'ACC-FORBIDDEN');

    Test.startTest();
    ALT_CLS_SourceHolderConfirmation.ApplyResult r = svc()
      .applyConnectionReferences(
        applyInput(
          c.Id,
          null,
          p.Id,
          new List<ALT_CLS_SourceHolderConfirmation.SourceRef>{
            sourceRef(b.Id, 'BANK', 0)
          }
        )
      );
    Test.stopTest();

    System.assertEquals('FORBIDDEN', r.outcome);
    System.assertEquals(0, r.applied);
    System.assertEquals(
      'CUSTODY',
      reloadBank(b.Id).AXF_BA_PKL_AvailabilityState__c
    );
    System.assertEquals(0, [SELECT COUNT() FROM AXF_OBJ_AccountHolder__c]);
  }

  @IsTest
  static void overviewReportsDivergentSources() {
    ALT_CLS_SourceHolderConfirmation.canConfigureOverride = true;
    Account confirmedHolder = person('Confirmado');
    Account connectionHolder = person('Da Conexao');
    AXF_OBJ_PluggyConnection__c c = pluggyConnection(null, connectionHolder.Id);
    AXF_OBJ_BankAccount__c divergent = connectedBank(c.Id, 'ACC-OVERVIEW');
    svc().confirmHolder(input(divergent.Id, 'BANK', confirmedHolder.Id, 0));

    Test.startTest();
    ALT_CLS_SourceHolderConfirmation.Overview o = svc().overview();
    Test.stopTest();

    Set<Id> divergentIds = new Set<Id>();
    for (ALT_CLS_SourceHolderConfirmation.SourceView v : o.divergent) {
      divergentIds.add(v.sourceId);
    }
    System.assert(
      divergentIds.contains(divergent.Id),
      'connection holder differs from the confirmed holder'
    );
    System.assertEquals(
      confirmedHolder.Id,
      o.divergent[0].holderId,
      'the source keeps its confirmed holder'
    );
    // the source is still released and remains correctable from the released list
    Set<Id> releasedIds = new Set<Id>();
    for (ALT_CLS_SourceHolderConfirmation.SourceView v : o.released) {
      releasedIds.add(v.sourceId);
    }
    System.assert(releasedIds.contains(divergent.Id));
  }

  @IsTest
  static void overviewDoesNotFlagDivergenceWithoutAConnectionHolder() {
    ALT_CLS_SourceHolderConfirmation.canConfigureOverride = true;
    Account p = person('Sem Divergencia');
    AXF_OBJ_PluggyConnection__c c = pluggyConnection(null, null);
    AXF_OBJ_BankAccount__c b = connectedBank(c.Id, 'ACC-NODIV');
    svc().confirmHolder(input(b.Id, 'BANK', p.Id, 0));

    Test.startTest();
    ALT_CLS_SourceHolderConfirmation.Overview o = svc().overview();
    Test.stopTest();

    System.assertEquals(
      0,
      o.divergent.size(),
      'no connection holder, no divergence'
    );
  }

  // ---- AC8: a canonical bank that diverges from the connection's is a conflict ----

  /** @description The framed identity key of AXF-85 (same algorithm, G6). */
  private static String framed(
    Id holderId,
    String kind,
    Id sourceId,
    String role
  ) {
    return frame(String.valueOf(holderId)) +
      frame(kind) +
      frame(String.valueOf(sourceId)) +
      frame(role);
  }

  private static String frame(String s) {
    return s.length() + ':' + s;
  }

  @IsTest
  static void applyPreservesADivergentCanonicalBankAndStillReleases() {
    ALT_CLS_SourceHolderConfirmation.canConfigureOverride = true;
    Account p = person('Banco Divergente');
    AXF_OBJ_BankInstitution__c connectionBank = bankInstitution(
      'Banco Conexao'
    );
    AXF_OBJ_BankInstitution__c storedBank = bankInstitution('Banco Gravado');
    AXF_OBJ_PluggyConnection__c c = pluggyConnection(connectionBank.Id, p.Id);
    AXF_OBJ_BankAccount__c b = connectedBank(c.Id, 'ACC-BANKDIV');
    b.AXF_BA_LKP_BankInstitution__c = storedBank.Id;
    Database.update(b, AccessLevel.SYSTEM_MODE);

    Test.startTest();
    ALT_CLS_SourceHolderConfirmation.ApplyResult r = svc()
      .applyConnectionReferences(
        applyInput(
          c.Id,
          connectionBank.Id,
          p.Id,
          new List<ALT_CLS_SourceHolderConfirmation.SourceRef>{
            sourceRef(b.Id, 'BANK', 0)
          }
        )
      );
    Test.stopTest();

    System.assertEquals(
      storedBank.Id,
      reloadBank(b.Id).AXF_BA_LKP_BankInstitution__c,
      'the stored canonical bank is never overwritten (AC8)'
    );
    System.assertEquals(1, r.bankDivergent, 'reported for explicit review');
    System.assertEquals(0, r.reused, 'a divergent bank is never a reuse');
    // the holder is descriptive-independent: the bank conflict does not block the release
    System.assertEquals(1, r.released);
    System.assertEquals(1, r.applied);
    System.assertEquals(
      'AVAILABLE',
      reloadBank(b.Id).AXF_BA_PKL_AvailabilityState__c
    );
  }

  @IsTest
  static void applyReportsABankDivergenceInsteadOfReuseWhenNothingElseIsNeeded() {
    ALT_CLS_SourceHolderConfirmation.canConfigureOverride = true;
    Account p = person('Banco Divergente Reuso');
    AXF_OBJ_BankInstitution__c connectionBank = bankInstitution(
      'Banco Conexao 2'
    );
    AXF_OBJ_BankInstitution__c storedBank = bankInstitution('Banco Gravado 2');
    AXF_OBJ_PluggyConnection__c c = pluggyConnection(connectionBank.Id, p.Id);
    AXF_OBJ_BankAccount__c b = connectedBank(c.Id, 'ACC-BANKDIV2');
    // already released to the connection holder, but carrying another canonical bank
    svc().confirmHolder(input(b.Id, 'BANK', p.Id, 0));
    AXF_OBJ_BankAccount__c released = reloadBank(b.Id);
    released.AXF_BA_LKP_BankInstitution__c = storedBank.Id;
    Database.update(released, AccessLevel.SYSTEM_MODE);

    Test.startTest();
    ALT_CLS_SourceHolderConfirmation.ApplyResult r = svc()
      .applyConnectionReferences(
        applyInput(
          c.Id,
          connectionBank.Id,
          p.Id,
          new List<ALT_CLS_SourceHolderConfirmation.SourceRef>{
            sourceRef(b.Id, 'BANK', released.AXF_BA_NUM_Version__c.intValue())
          }
        )
      );
    Test.stopTest();

    System.assertEquals(0, r.reused, 'never reported as reused (AC8)');
    System.assertEquals(1, r.bankDivergent);
    System.assertEquals(
      'CONFLICT',
      r.outcome,
      'an explicit conflict to review'
    );
    System.assertEquals(
      storedBank.Id,
      reloadBank(b.Id).AXF_BA_LKP_BankInstitution__c
    );
    System.assertEquals(
      released.AXF_BA_NUM_Version__c,
      reloadBank(b.Id).AXF_BA_NUM_Version__c,
      'nothing was written'
    );
  }

  // ---- AC6: a refused write is counted, never reported as a release, and leaves no
  // orphan CONFIRMED link ----

  @IsTest
  static void applyCountsARefusedSourceWriteAndLeavesNoOrphanLink() {
    ALT_CLS_SourceHolderConfirmation.canConfigureOverride = true;
    Account p = person('Falha Parcial');
    AXF_OBJ_BankInstitution__c inst = bankInstitution('Banco Falha');
    AXF_OBJ_PluggyConnection__c c = pluggyConnection(inst.Id, p.Id);
    AXF_OBJ_BankAccount__c ok = connectedBank(c.Id, 'ACC-OK');
    AXF_OBJ_BankAccount__c refused = connectedBank(c.Id, 'ACC-REFUSED');
    // AXF_BA_NUM_Version__c is Number(9), so Version+1 overflows: a real refused write
    refused.AXF_BA_NUM_Version__c = 999999999;
    Database.update(refused, AccessLevel.SYSTEM_MODE);

    Test.startTest();
    ALT_CLS_SourceHolderConfirmation.ApplyResult r = svc()
      .applyConnectionReferences(
        applyInput(
          c.Id,
          inst.Id,
          p.Id,
          new List<ALT_CLS_SourceHolderConfirmation.SourceRef>{
            sourceRef(ok.Id, 'BANK', 0),
            sourceRef(refused.Id, 'BANK', 999999999)
          }
        )
      );
    Test.stopTest();

    System.assertEquals(1, r.failed, 'the refused write is counted');
    System.assertEquals(
      'FAILED',
      r.outcome,
      'a failure is never hidden behind a success marker'
    );
    System.assert(r.message.contains('com falha'), r.message);
    System.assertEquals(
      1,
      r.applied,
      'one refused source never discards the others'
    );
    System.assertEquals(
      1,
      r.released,
      'only the source that really got its link'
    );
    System.assertEquals(
      1,
      r.pending,
      'the refused source keeps its custody state'
    );

    AXF_OBJ_BankAccount__c stillCustody = reloadBank(refused.Id);
    System.assertEquals(
      'CUSTODY',
      stillCustody.AXF_BA_PKL_AvailabilityState__c
    );
    System.assertEquals(null, stillCustody.AXF_BA_LKP_Account__c);
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM AXF_OBJ_AccountHolder__c
        WHERE
          AXF_ACH_LKP_BankAccount__c = :refused.Id
          AND AXF_ACH_PKL_State__c = 'CONFIRMED'
      ],
      'no CONFIRMED link is left pointing at a source still in custody (AC6)'
    );
    System.assertEquals(1, [SELECT COUNT() FROM AXF_OBJ_AccountHolder__c]);
  }

  @IsTest
  static void applyRevertsTheSourceWhenTheDefinitiveLinkIsRefused() {
    ALT_CLS_SourceHolderConfirmation.canConfigureOverride = true;
    Account p = person('Falha Vinculo');
    AXF_OBJ_BankInstitution__c inst = bankInstitution('Banco Falha Vinculo');
    AXF_OBJ_PluggyConnection__c c = pluggyConnection(inst.Id, p.Id);
    AXF_OBJ_BankAccount__c b = connectedBank(c.Id, 'ACC-LINKFAIL');
    String key = framed(p.Id, 'BANK', b.Id, 'PRIMARY');
    // A previous (superseded) link for the SAME holder+source whose Version is at the
    // Number(9) ceiling: reactivating it overflows, so the link write is refused.
    Database.insert(
      new AXF_OBJ_AccountHolder__c(
        OwnerId = p.OwnerId,
        AXF_ACH_LKP_Account__c = p.Id,
        AXF_ACH_LKP_BankAccount__c = b.Id,
        AXF_ACH_PKL_Role__c = 'PRIMARY',
        AXF_ACH_PKL_State__c = 'SUPERSEDED',
        AXF_ACH_DAT_ValidFrom__c = Date.today().addDays(-30),
        AXF_ACH_DAT_ValidTo__c = Date.today().addDays(-1),
        AXF_ACH_NUM_Version__c = 999999999,
        AXF_ACH_EXI_FramedKey__c = key
      ),
      AccessLevel.SYSTEM_MODE
    );

    Test.startTest();
    ALT_CLS_SourceHolderConfirmation.ApplyResult r = svc()
      .applyConnectionReferences(
        applyInput(
          c.Id,
          inst.Id,
          p.Id,
          new List<ALT_CLS_SourceHolderConfirmation.SourceRef>{
            sourceRef(b.Id, 'BANK', 0)
          }
        )
      );
    Test.stopTest();

    System.assertEquals(1, r.failed);
    System.assertEquals('FAILED', r.outcome);
    System.assertEquals(0, r.released, 'no source is reported as released');
    System.assertEquals(1, r.pending);
    AXF_OBJ_BankAccount__c fresh = reloadBank(b.Id);
    System.assertEquals(
      'CUSTODY',
      fresh.AXF_BA_PKL_AvailabilityState__c,
      'the source write is reverted when the link could not be written (AC6)'
    );
    System.assertEquals(0, fresh.AXF_BA_NUM_Version__c, 'version restored');
    System.assertEquals(null, fresh.AXF_BA_LKP_Account__c, 'holder restored');
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM AXF_OBJ_AccountHolder__c
        WHERE AXF_ACH_PKL_State__c = 'CONFIRMED'
      ],
      'no orphan CONFIRMED link'
    );
  }

  // ---- AC10: a large batch loses nothing and issues no per-source query/DML ----

  @IsTest
  static void appliesABatchOfTwoHundredSourcesWithoutLosingAny() {
    ALT_CLS_SourceHolderConfirmation.canConfigureOverride = true;
    Account p = person('Lote Duzentos');
    AXF_OBJ_BankInstitution__c inst = bankInstitution('Banco Lote');
    AXF_OBJ_PluggyConnection__c c = pluggyConnection(inst.Id, p.Id);

    List<AXF_OBJ_BankAccount__c> seed = new List<AXF_OBJ_BankAccount__c>();
    for (Integer i = 0; i < 200; i++) {
      seed.add(
        new AXF_OBJ_BankAccount__c(
          AXF_BA_LKP_Connection__c = c.Id,
          AXF_BA_EXI_PluggyAccountId__c = 'ACC-BULK-' + i,
          AXF_BA_PKL_AvailabilityState__c = 'CUSTODY',
          AXF_BA_TXT_InstitutionName__c = 'Banco Exemplo',
          AXF_BA_TXT_NumberMasked__c = '****4321',
          AXF_BA_TXT_CurrencyIsoCode__c = 'BRL',
          AXF_BA_NUM_Version__c = 0
        )
      );
    }
    Database.insert(seed, AccessLevel.SYSTEM_MODE);

    List<ALT_CLS_SourceHolderConfirmation.SourceRef> refs = new List<ALT_CLS_SourceHolderConfirmation.SourceRef>();
    for (AXF_OBJ_BankAccount__c b : [
      SELECT Id
      FROM AXF_OBJ_BankAccount__c
      WHERE AXF_BA_LKP_Connection__c = :c.Id
    ]) {
      refs.add(sourceRef(b.Id, 'BANK', 0));
    }
    System.assertEquals(200, refs.size());

    Integer queriesBefore = Limits.getQueries();
    Integer dmlBefore = Limits.getDmlStatements();

    Test.startTest();
    ALT_CLS_SourceHolderConfirmation.ApplyResult r = svc()
      .applyConnectionReferences(applyInput(c.Id, inst.Id, p.Id, refs));
    Test.stopTest();

    System.assertEquals(200, r.applied, r.message);
    System.assertEquals(200, r.released, r.message);
    System.assertEquals(0, r.failed, r.message);
    System.assertEquals(0, r.ignored, r.message);

    // no per-source query and no per-source DML: the cost is constant in batch size
    Integer queriesUsed = Limits.getQueries() - queriesBefore;
    Integer dmlUsed = Limits.getDmlStatements() - dmlBefore;
    System.assert(
      queriesUsed <= 8,
      'queries must not scale with the batch: ' + queriesUsed
    );
    System.assert(
      dmlUsed <= 4,
      'DML statements must not scale with the batch: ' + dmlUsed
    );

    System.assertEquals(
      200,
      [
        SELECT COUNT()
        FROM AXF_OBJ_BankAccount__c
        WHERE
          AXF_BA_LKP_Connection__c = :c.Id
          AND AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE'
          AND AXF_BA_LKP_Account__c = :p.Id
      ],
      'no source is lost'
    );
    System.assertEquals(200, [SELECT COUNT() FROM AXF_OBJ_AccountHolder__c]);
  }

  @IsTest
  static void applyDedupesARepeatedSourceEntry() {
    ALT_CLS_SourceHolderConfirmation.canConfigureOverride = true;
    Account p = person('Duplicada');
    AXF_OBJ_BankInstitution__c inst = bankInstitution('Banco Duplicado');
    AXF_OBJ_PluggyConnection__c c = pluggyConnection(inst.Id, p.Id);
    AXF_OBJ_BankAccount__c b = connectedBank(c.Id, 'ACC-DUP');

    Test.startTest();
    ALT_CLS_SourceHolderConfirmation.ApplyResult r = svc()
      .applyConnectionReferences(
        applyInput(
          c.Id,
          inst.Id,
          p.Id,
          new List<ALT_CLS_SourceHolderConfirmation.SourceRef>{
            sourceRef(b.Id, 'BANK', 0),
            sourceRef(b.Id, 'BANK', 0)
          }
        )
      );
    Test.stopTest();

    System.assertEquals(1, r.applied, 'the source is processed once');
    System.assertEquals(1, r.ignored, 'the repeated entry is ignored');
    System.assertEquals(
      1,
      [SELECT COUNT() FROM AXF_OBJ_AccountHolder__c],
      'a repeated entry never duplicates the definitive link (AC10)'
    );
    System.assertEquals(1, reloadBank(b.Id).AXF_BA_NUM_Version__c);
  }

  // ---- AXF-106: a source already linked to the connection holder but drifted is repaired ----

  @IsTest
  static void applyRepairsASourceThatWentBackToCustody() {
    ALT_CLS_SourceHolderConfirmation.canConfigureOverride = true;
    Account p = person('Reparo');
    AXF_OBJ_BankInstitution__c inst = bankInstitution('Banco Reparo');
    AXF_OBJ_PluggyConnection__c c = pluggyConnection(inst.Id, p.Id);
    AXF_OBJ_BankAccount__c b = connectedBank(c.Id, 'ACC-REPAIR');

    // first application: the definitive link is written and the source is released
    ALT_CLS_SourceHolderConfirmation.ApplyResult first = svc()
      .applyConnectionReferences(
        applyInput(
          c.Id,
          inst.Id,
          p.Id,
          new List<ALT_CLS_SourceHolderConfirmation.SourceRef>{
            sourceRef(b.Id, 'BANK', 0)
          }
        )
      );
    System.assertEquals(1, first.applied);
    AXF_OBJ_BankAccount__c released = reloadBank(b.Id);
    System.assertEquals('AVAILABLE', released.AXF_BA_PKL_AvailabilityState__c);

    // the source drifted back to custody while the confirmed link stayed the same
    released.AXF_BA_PKL_AvailabilityState__c = 'CUSTODY';
    Database.update(released, AccessLevel.SYSTEM_MODE);
    Integer driftedVersion = released.AXF_BA_NUM_Version__c.intValue();

    Test.startTest();
    ALT_CLS_SourceHolderConfirmation.ApplyResult r = svc()
      .applyConnectionReferences(
        applyInput(
          c.Id,
          inst.Id,
          p.Id,
          new List<ALT_CLS_SourceHolderConfirmation.SourceRef>{
            sourceRef(b.Id, 'BANK', driftedVersion)
          }
        )
      );
    Test.stopTest();

    System.assertEquals(1, r.corrected, r.message);
    System.assertEquals(
      0,
      r.applied,
      'the definitive link already existed — nothing new was linked'
    );
    System.assertEquals(
      1,
      r.released,
      'the repaired source is released by this run'
    );
    AXF_OBJ_BankAccount__c fresh = reloadBank(b.Id);
    System.assertEquals('AVAILABLE', fresh.AXF_BA_PKL_AvailabilityState__c);
    System.assertEquals(p.Id, fresh.AXF_BA_LKP_Account__c);
    System.assertEquals(
      p.OwnerId,
      fresh.OwnerId,
      'the owner is resynced with the holder (G2-2)'
    );
    System.assertEquals(
      driftedVersion + 1,
      fresh.AXF_BA_NUM_Version__c.intValue(),
      'a repair advances the Version'
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM AXF_OBJ_AccountHolder__c],
      'the repair never duplicates the definitive link'
    );
  }

  @IsTest
  static void overviewDoesNotFlagDivergenceWhenTheHolderMatchesTheConnection() {
    ALT_CLS_SourceHolderConfirmation.canConfigureOverride = true;
    Account p = person('Mesmo Titular');
    AXF_OBJ_PluggyConnection__c c = pluggyConnection(null, p.Id);
    AXF_OBJ_BankAccount__c b = connectedBank(c.Id, 'ACC-SAMEHOLDER');
    svc().confirmHolder(input(b.Id, 'BANK', p.Id, 0));

    Test.startTest();
    ALT_CLS_SourceHolderConfirmation.Overview o = svc().overview();
    Test.stopTest();

    System.assertEquals(
      0,
      o.divergent.size(),
      'the confirmed holder is the connection holder: no divergence'
    );
    Boolean flagged = false;
    for (ALT_CLS_SourceHolderConfirmation.SourceView v : o.released) {
      if (v.sourceId == b.Id) {
        flagged = v.divergent == true;
      }
    }
    System.assert(!flagged, 'a matching holder is never flagged as divergent');
  }
}
