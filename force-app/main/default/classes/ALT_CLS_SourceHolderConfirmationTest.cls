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
      input(b.Id, 'BANK', p.Id, 0)
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
}
