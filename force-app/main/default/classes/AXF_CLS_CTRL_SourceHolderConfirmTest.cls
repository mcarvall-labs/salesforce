/**
 * @description AXF_CLS_CTRL_SourceHolderConfirmation + ALT_CLS_SourceHolderLink over the
 * legacy PROD model: pending = Pluggy-linked BA/CC without Account, released = with it,
 * divergent always empty; confirming sets the Account lookup.
 */
@IsTest
private class AXF_CLS_CTRL_SourceHolderConfirmTest {
  @TestSetup
  static void setup() {
    AXF_CLS_SourceSetupTestFactory.createUsers();
    User cfg = AXF_CLS_SourceSetupTestFactory.user(
      AXF_CLS_SourceSetupTestFactory.CONFIGURER
    );
    AXF_OBJ_BankInstitution__c bank = AXF_CLS_SourceSetupTestFactory.institution(
      cfg.Id,
      'Banco Teste',
      AXF_CLS_SourceSetupTestFactory.BANK_NUMBER
    );
    Account one = AXF_CLS_SourceSetupTestFactory.holder(cfg.Id, 'Titular Um');
    AXF_CLS_SourceSetupTestFactory.holder(cfg.Id, 'Titular Dois');
    AXF_OBJ_PluggyConnection__c conn = AXF_CLS_SourceSetupTestFactory.connection(
      bank.Id,
      'item-holders',
      'UPDATED'
    );
    AXF_CLS_SourceSetupTestFactory.bankAccount(
      cfg.Id,
      conn.Id,
      bank.Id,
      null,
      'pending-ba'
    );
    AXF_CLS_SourceSetupTestFactory.bankAccount(
      cfg.Id,
      conn.Id,
      bank.Id,
      one.Id,
      'released-ba'
    );
    AXF_CLS_SourceSetupTestFactory.creditCard(
      cfg.Id,
      conn.Id,
      bank.Id,
      null,
      'pending-cc'
    );
    // A manual source (no connection) is not part of the Pluggy holder step.
    AXF_CLS_SourceSetupTestFactory.bankAccount(
      cfg.Id,
      null,
      bank.Id,
      null,
      'MANUAL-no-connection'
    );
  }

  private static User configurer() {
    return AXF_CLS_SourceSetupTestFactory.user(
      AXF_CLS_SourceSetupTestFactory.CONFIGURER
    );
  }

  private static Id holder(String name) {
    return [SELECT Id FROM Account WHERE Name = :name LIMIT 1].Id;
  }

  private static Id ba(String externalId) {
    return [
      SELECT Id
      FROM AXF_OBJ_BankAccount__c
      WHERE AXF_BA_EXI_PluggyAccountId__c = :externalId
    ]
    .Id;
  }

  private static Id cc(String externalId) {
    return [
      SELECT Id
      FROM AXF_OBJ_CreditCard__c
      WHERE AXF_CC_EXI_PluggyCreditCardId__c = :externalId
    ]
    .Id;
  }

  @IsTest
  static void overviewSplitsPendingAndReleased() {
    AXF_CLS_SourceSetupDTO.HolderOverview o;
    System.runAs(configurer()) {
      o = AXF_CLS_CTRL_SourceHolderConfirmation.getOverview();
    }
    Assert.isFalse(o.forbidden);
    Assert.areEqual(2, o.pending.size(), 'pending BA + pending CC');
    Assert.areEqual(1, o.released.size());
    Assert.isTrue(o.divergent.isEmpty(), 'no divergence in the legacy model');
    AXF_CLS_SourceSetupDTO.SourceView released = o.released[0];
    Assert.areEqual('BANK', released.kind);
    Assert.areEqual('Titular Um', released.holderName);
    Assert.areEqual('AVAILABLE', released.availabilityState);
    Assert.areEqual('•••• 45-6', released.maskedNumber);
    Assert.areEqual('Banco Teste', released.bankInstitutionName);
    Assert.areEqual(0, released.version);
    Assert.areEqual(
      released.holderId,
      released.suggestedHolderId,
      'a released source suggests its own current holder'
    );
    Id sharedConnectionHolder = holder('Titular Um');
    for (AXF_CLS_SourceSetupDTO.SourceView v : o.pending) {
      Assert.areEqual('CUSTODY', v.availabilityState);
      Assert.isNull(v.holderId);
      Assert.isNotNull(v.currencyIsoCode);
      Assert.areEqual(
        sharedConnectionHolder,
        v.suggestedHolderId,
        'a pending source of the same connection suggests the sibling holder already linked'
      );
    }
  }

  @IsTest
  static void readerIsForbidden() {
    AXF_CLS_SourceSetupDTO.HolderOverview o;
    AXF_CLS_SourceSetupDTO.ConfirmResult r;
    System.runAs(AXF_CLS_SourceSetupTestFactory.user(
      AXF_CLS_SourceSetupTestFactory.READER
    )) {
      o = AXF_CLS_CTRL_SourceHolderConfirmation.getOverview();
      r = AXF_CLS_CTRL_SourceHolderConfirmation.confirmHolder(
        ba('pending-ba'),
        'BANK',
        holder('Titular Um'),
        0,
        null
      );
    }
    Assert.isTrue(o.forbidden);
    Assert.isTrue(o.pending.isEmpty());
    Assert.areEqual('FORBIDDEN', r.outcome);
  }

  @IsTest
  static void confirmCorrectAndReplay() {
    Id pendingBa = ba('pending-ba');
    Id pendingCc = cc('pending-cc');
    Id one = holder('Titular Um');
    Id two = holder('Titular Dois');
    System.runAs(configurer()) {
      AXF_CLS_SourceSetupDTO.ConfirmResult confirmed = AXF_CLS_CTRL_SourceHolderConfirmation.confirmHolder(
        pendingBa,
        'BANK',
        one,
        0,
        'note ignored'
      );
      Assert.areEqual('CONFIRMED', confirmed.outcome, confirmed.message);
      Assert.areEqual('AVAILABLE', confirmed.availabilityState);

      AXF_CLS_SourceSetupDTO.ConfirmResult already = AXF_CLS_CTRL_SourceHolderConfirmation.confirmHolder(
        pendingBa,
        'BANK',
        one,
        0,
        null
      );
      Assert.areEqual('ALREADY', already.outcome);

      AXF_CLS_SourceSetupDTO.ConfirmResult corrected = AXF_CLS_CTRL_SourceHolderConfirmation.confirmHolder(
        pendingBa,
        null,
        two,
        0,
        null
      );
      Assert.areEqual('CORRECTED', corrected.outcome);

      AXF_CLS_SourceSetupDTO.ConfirmResult card = AXF_CLS_CTRL_SourceHolderConfirmation.confirmHolder(
        pendingCc,
        'CARD',
        one,
        0,
        null
      );
      Assert.areEqual('CONFIRMED', card.outcome, card.message);
    }
    Assert.areEqual(
      two,
      [
        SELECT AXF_BA_LKP_Account__c
        FROM AXF_OBJ_BankAccount__c
        WHERE Id = :pendingBa
      ]
      .AXF_BA_LKP_Account__c
    );
    Assert.areEqual(
      one,
      [
        SELECT AXF_CC_LKP_Account__c
        FROM AXF_OBJ_CreditCard__c
        WHERE Id = :pendingCc
      ]
      .AXF_CC_LKP_Account__c
    );
  }

  @IsTest
  static void confirmRejectsInvalidInput() {
    Id pendingBa = ba('pending-ba');
    Id pendingCc = cc('pending-cc');
    Id one = holder('Titular Um');
    System.runAs(configurer()) {
      Assert.areEqual(
        'INVALID',
        AXF_CLS_CTRL_SourceHolderConfirmation.confirmHolder(
            null,
            'BANK',
            one,
            0,
            null
          )
          .outcome
      );
      Assert.areEqual(
        'INVALID',
        AXF_CLS_CTRL_SourceHolderConfirmation.confirmHolder(
            one,
            'BANK',
            one,
            0,
            null
          )
          .outcome,
        'an Account is not a source'
      );
      Assert.areEqual(
        'INVALID',
        AXF_CLS_CTRL_SourceHolderConfirmation.confirmHolder(
            pendingBa,
            'CARD',
            one,
            0,
            null
          )
          .outcome,
        'kind mismatch'
      );
      Assert.areEqual(
        'INVALID',
        AXF_CLS_CTRL_SourceHolderConfirmation.confirmHolder(
            pendingBa,
            'BANK',
            pendingCc,
            0,
            null
          )
          .outcome,
        'a card is not a holder'
      );
    }
  }

  @IsTest
  static void confirmMissingSourceIsNotFound() {
    Id pendingBa = ba('pending-ba');
    Id pendingCc = cc('pending-cc');
    delete new List<SObject>{
      new AXF_OBJ_BankAccount__c(Id = pendingBa),
      new AXF_OBJ_CreditCard__c(Id = pendingCc)
    };
    System.runAs(configurer()) {
      Assert.areEqual(
        'NOT_FOUND',
        AXF_CLS_CTRL_SourceHolderConfirmation.confirmHolder(
            pendingBa,
            'BANK',
            holder('Titular Um'),
            0,
            null
          )
          .outcome
      );
      Assert.areEqual(
        'NOT_FOUND',
        AXF_CLS_CTRL_SourceHolderConfirmation.confirmHolder(
            pendingCc,
            'CARD',
            holder('Titular Um'),
            0,
            null
          )
          .outcome
      );
    }
  }

  @IsTest
  static void maskKeepsAtMostFourCharacters() {
    Assert.isNull(ALT_CLS_SourceHolderLink.mask(' '));
    Assert.areEqual('•••• 12', ALT_CLS_SourceHolderLink.mask('12'));
    Assert.areEqual('•••• 5678', ALT_CLS_SourceHolderLink.mask('12345678'));
  }

  @IsTest
  static void unexpectedFailureIsSanitized() {
    AXF_CLS_CTRL_SourceHolderConfirmation.simulateFailure = true;
    System.runAs(configurer()) {
      try {
        AXF_CLS_CTRL_SourceHolderConfirmation.getOverview();
        Assert.fail('the failure must surface');
      } catch (AuraHandledException e) {
        Assert.areEqual('Não foi possível carregar as fontes.', e.getMessage());
      }
    }
  }
}
