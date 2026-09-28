/**
 * @description AXF_CLS_CTRL_SourceDiscovery + ALT_CLS_PluggySourceSetup over the legacy
 * PROD model: register (legacy queueable enqueued and run with a Pluggy mock), status,
 * overview, discovered sources, synchronous discovery, references and delete.
 */
@IsTest
private class AXF_CLS_CTRL_SourceDiscoveryTest {
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
    Account holder = AXF_CLS_SourceSetupTestFactory.holder(
      cfg.Id,
      'Titular Um'
    );
    AXF_OBJ_PluggyConnection__c conn = AXF_CLS_SourceSetupTestFactory.connection(
      bank.Id,
      'item-with-sources',
      'UPDATED'
    );
    AXF_CLS_SourceSetupTestFactory.bankAccount(
      cfg.Id,
      conn.Id,
      bank.Id,
      holder.Id,
      'existing-ba-1'
    );
    AXF_CLS_SourceSetupTestFactory.creditCard(
      cfg.Id,
      conn.Id,
      bank.Id,
      null,
      'existing-cc-1'
    );
    AXF_CLS_SourceSetupTestFactory.connection(bank.Id, 'item-empty', null);
  }

  private static User configurer() {
    return AXF_CLS_SourceSetupTestFactory.user(
      AXF_CLS_SourceSetupTestFactory.CONFIGURER
    );
  }

  private static User reader() {
    return AXF_CLS_SourceSetupTestFactory.user(
      AXF_CLS_SourceSetupTestFactory.READER
    );
  }

  private static AXF_OBJ_PluggyConnection__c conn(String itemId) {
    return [
      SELECT Id, AXF_CON_LKP_BankInstitution__c
      FROM AXF_OBJ_PluggyConnection__c
      WHERE AXF_CON_EXI_PluggyItemId__c = :itemId
    ];
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

  private static Id holderId() {
    return [SELECT Id FROM Account WHERE Name = 'Titular Um' LIMIT 1].Id;
  }

  private static String auraMessage(Exception e) {
    return e.getMessage();
  }

  @IsTest
  static void registerInsertsConnectionAndRunsLegacySync() {
    Id bank = bankId();
    AXF_CLS_SourceSetupDTO.RegisterResult r;
    System.runAs(configurer()) {
      Test.setMock(
        HttpCalloutMock.class,
        new AXF_CLS_SourceSetupTestFactory.PluggyMock()
      );
      Test.startTest();
      r = AXF_CLS_CTRL_SourceDiscovery.registerConnection(
        '  new-item-001  ',
        bank
      );
      Test.stopTest();
    }
    Assert.isTrue(r.created, 'a new connection is created');
    Assert.isNotNull(r.connectionId);
    AXF_OBJ_PluggyConnection__c row = [
      SELECT AXF_CON_EXI_PluggyItemId__c, AXF_CON_TXT_SyncStatus__c
      FROM AXF_OBJ_PluggyConnection__c
      WHERE Id = :r.connectionId
    ];
    Assert.areEqual('new-item-001', row.AXF_CON_EXI_PluggyItemId__c);
    Assert.areEqual(
      'UPDATED',
      row.AXF_CON_TXT_SyncStatus__c,
      'the legacy queueable ran'
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AXF_OBJ_BankAccount__c
        WHERE AXF_BA_LKP_PluggyConnection__c = :r.connectionId
      ],
      'the legacy sync creates the bank account'
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AXF_OBJ_CreditCard__c
        WHERE AXF_CC_LKP_PluggyConnection__c = :r.connectionId
      ],
      'the legacy sync creates the credit card'
    );
  }

  @IsTest
  static void registerReturnsExistingConnection() {
    AXF_CLS_SourceSetupDTO.RegisterResult r;
    System.runAs(configurer()) {
      r = AXF_CLS_CTRL_SourceDiscovery.registerConnection('item-empty', null);
    }
    Assert.isFalse(r.created);
    Assert.areEqual(conn('item-empty').Id, r.connectionId);
  }

  @IsTest
  static void registerRejectsInvalidInput() {
    System.runAs(configurer()) {
      for (String itemId : new List<String>{ null, 'x', 'bad item id!' }) {
        try {
          AXF_CLS_CTRL_SourceDiscovery.registerConnection(itemId, bankId());
          Assert.fail('invalid item id must be rejected');
        } catch (AuraHandledException e) {
          Assert.isTrue(auraMessage(e).contains('Item ID'), auraMessage(e));
        }
      }
      try {
        AXF_CLS_CTRL_SourceDiscovery.registerConnection('item-no-bank', null);
        Assert.fail('the bank is required');
      } catch (AuraHandledException e) {
        Assert.isTrue(auraMessage(e).contains('banco'), auraMessage(e));
      }
      try {
        AXF_CLS_CTRL_SourceDiscovery.registerConnection(
          'item-wrong-bank',
          holderId()
        );
        Assert.fail('a non-institution id is rejected');
      } catch (AuraHandledException e) {
        Assert.isTrue(auraMessage(e).contains('Instituição'), auraMessage(e));
      }
    }
  }

  @IsTest
  static void writesRequireCanConfigure() {
    Id connId = conn('item-empty').Id;
    System.runAs(reader()) {
      try {
        AXF_CLS_CTRL_SourceDiscovery.registerConnection(
          'item-reader',
          bankId()
        );
        Assert.fail('reader cannot register');
      } catch (AuraHandledException e) {
        Assert.isTrue(auraMessage(e).contains('autorização'), auraMessage(e));
      }
      AXF_CLS_SourceSetupDTO.DiscoveryResult d = AXF_CLS_CTRL_SourceDiscovery.startDiscovery(
        connId
      );
      Assert.areEqual('FAILED_TERMINAL', d.state);
      Assert.isFalse(d.complete);
    }
  }

  @IsTest
  static void statusMapsLegacySyncFields() {
    Id withSources = conn('item-with-sources').Id;
    Id empty = conn('item-empty').Id;
    System.runAs(configurer()) {
      AXF_CLS_SourceSetupDTO.DiscoveryResult none = AXF_CLS_CTRL_SourceDiscovery.getStatus(
        null
      );
      Assert.isNull(none.state);
      Assert.isFalse(none.complete);

      AXF_CLS_SourceSetupDTO.DiscoveryResult ok = AXF_CLS_CTRL_SourceDiscovery.getStatus(
        withSources
      );
      Assert.areEqual('SUCCEEDED', ok.state);
      Assert.isTrue(ok.complete);
      Assert.areEqual(1, ok.accountsFound);
      Assert.areEqual(1, ok.cardsFound);
      Assert.areEqual(1, ok.released);
      Assert.areEqual(1, ok.pending);

      AXF_CLS_SourceSetupDTO.DiscoveryResult waiting = AXF_CLS_CTRL_SourceDiscovery.getStatus(
        empty
      );
      Assert.isNull(waiting.state);

      AXF_CLS_SourceSetupDTO.DiscoveryResult missing = AXF_CLS_CTRL_SourceDiscovery.getStatus(
        holderId()
      );
      Assert.areEqual('Conexão não encontrada.', missing.message);
    }
  }

  @IsTest
  static void connectionsAndDiscoveredSources() {
    Id withSources = conn('item-with-sources').Id;
    System.runAs(configurer()) {
      List<AXF_CLS_SourceSetupDTO.ConnectionOverview> rows = AXF_CLS_CTRL_SourceDiscovery.getConnections();
      Assert.areEqual(2, rows.size());
      AXF_CLS_SourceSetupDTO.ConnectionOverview first;
      for (AXF_CLS_SourceSetupDTO.ConnectionOverview o : rows) {
        if (o.connectionId == withSources) {
          first = o;
        }
      }
      Assert.isNotNull(first);
      Assert.isTrue(first.discovered);
      Assert.areEqual('ACTIVE', first.consentState);
      Assert.areEqual('SUCCEEDED', first.runState);
      Assert.areEqual(holderId(), first.holderId);
      Assert.areEqual('Titular Um', first.holderName);
      Assert.areEqual(bankId(), first.bankInstitutionId);
      Assert.isTrue(first.itemIdHint.endsWith('rces'), first.itemIdHint);

      Assert.isTrue(AXF_CLS_CTRL_SourceDiscovery.getDiscovered(null).isEmpty());
      List<AXF_CLS_SourceSetupDTO.DiscoveredSource> sources = AXF_CLS_CTRL_SourceDiscovery.getDiscovered(
        withSources
      );
      Assert.areEqual(2, sources.size());
      Set<String> availability = new Set<String>();
      for (AXF_CLS_SourceSetupDTO.DiscoveredSource s : sources) {
        availability.add(s.kind + ':' + s.availability);
        Assert.isNotNull(s.currencyIsoCode);
      }
      Assert.isTrue(availability.contains('BANK:AVAILABLE'), '' + availability);
      Assert.isTrue(availability.contains('CARD:CUSTODY'), '' + availability);
    }
  }

  @IsTest
  static void startDiscoveryRunsLegacySyncAndAppliesConnectionHolder() {
    Id connId = conn('item-with-sources').Id;
    AXF_CLS_SourceSetupDTO.DiscoveryResult r;
    System.runAs(configurer()) {
      Test.setMock(
        HttpCalloutMock.class,
        new AXF_CLS_SourceSetupTestFactory.PluggyMock()
      );
      Test.startTest();
      r = AXF_CLS_CTRL_SourceDiscovery.startDiscovery(connId);
      Test.stopTest();
    }
    Assert.areEqual('SUCCEEDED', r.state, r.message);
    Assert.isTrue(r.complete);
    Assert.areEqual(2, r.accountsFound);
    Assert.areEqual(2, r.cardsFound);
    Assert.areEqual(
      0,
      r.pending,
      'the connection holder fills unlinked sources'
    );
    Assert.areEqual(4, r.released);
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM AXF_OBJ_CreditCard__c
        WHERE
          AXF_CC_LKP_PluggyConnection__c = :connId
          AND AXF_CC_LKP_Account__c = NULL
      ]
    );
  }

  @IsTest
  static void startDiscoverySurfacesInvalidCredentialMessage() {
    Id connId = conn('item-empty').Id;
    AXF_CLS_SourceSetupDTO.DiscoveryResult r;
    System.runAs(configurer()) {
      Test.setMock(
        HttpCalloutMock.class,
        new AXF_CLS_SourceSetupTestFactory.PluggyAuthFailureMock()
      );
      Test.startTest();
      r = AXF_CLS_CTRL_SourceDiscovery.startDiscovery(connId);
      Test.stopTest();
    }
    Assert.areEqual('FAILED_TERMINAL', r.state);
    Assert.isFalse(r.complete);
    Assert.isTrue(
      r.message.contains('inválidas'),
      'an auth rejection must name the credential, not a generic failure: ' +
      r.message
    );
  }

  @IsTest
  static void startDiscoveryReportsPluggyStates() {
    Id connId = conn('item-empty').Id;
    AXF_CLS_SourceSetupTestFactory.PluggyMock mock = new AXF_CLS_SourceSetupTestFactory.PluggyMock();
    mock.itemStatus = 'LOGIN_ERROR';
    AXF_CLS_SourceSetupDTO.DiscoveryResult r;
    System.runAs(configurer()) {
      Test.setMock(HttpCalloutMock.class, mock);
      Test.startTest();
      r = AXF_CLS_CTRL_SourceDiscovery.startDiscovery(connId);
      Test.stopTest();
    }
    Assert.areEqual('FAILED_TERMINAL', r.state);
    Assert.isFalse(r.complete);
    Assert.isNotNull(r.message);
  }

  @IsTest
  static void startDiscoveryStillUpdatingIsRetryable() {
    Id connId = conn('item-empty').Id;
    AXF_CLS_SourceSetupTestFactory.PluggyMock mock = new AXF_CLS_SourceSetupTestFactory.PluggyMock();
    mock.itemStatus = 'UPDATING';
    AXF_CLS_SourceSetupDTO.DiscoveryResult r;
    System.runAs(configurer()) {
      Test.setMock(HttpCalloutMock.class, mock);
      Test.startTest();
      r = AXF_CLS_CTRL_SourceDiscovery.startDiscovery(connId);
      AXF_CLS_SourceSetupDTO.DiscoveryResult missing = AXF_CLS_CTRL_SourceDiscovery.startDiscovery(
        null
      );
      Test.stopTest();
      Assert.areEqual('FAILED_TERMINAL', missing.state);
    }
    Assert.areEqual('FAILED_RETRYABLE', r.state);
    Assert.isTrue(r.message.contains('atualizando'), r.message);
  }

  @IsTest
  static void updateReferencesPropagatesHolder() {
    AXF_OBJ_PluggyConnection__c c = conn('item-with-sources');
    Id newHolder;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      newHolder = AXF_CLS_SourceSetupTestFactory.holder(
          configurer().Id,
          'Titular Dois'
        )
        .Id;
    }
    AXF_CLS_SourceSetupDTO.UpdateReferencesResult r;
    System.runAs(configurer()) {
      r = AXF_CLS_CTRL_SourceDiscovery.updateReferences(
        c.Id,
        c.AXF_CON_LKP_BankInstitution__c,
        newHolder
      );
    }
    Assert.areEqual('UPDATED', r.outcome);
    Assert.areEqual(newHolder, r.holderId);
    Assert.areEqual(
      newHolder,
      [
        SELECT AXF_CC_LKP_Account__c
        FROM AXF_OBJ_CreditCard__c
        WHERE AXF_CC_LKP_PluggyConnection__c = :c.Id
      ]
      .AXF_CC_LKP_Account__c
    );
    Assert.areEqual(
      newHolder,
      [
        SELECT AXF_BA_LKP_Account__c
        FROM AXF_OBJ_BankAccount__c
        WHERE AXF_BA_LKP_PluggyConnection__c = :c.Id
      ]
      .AXF_BA_LKP_Account__c
    );
  }

  @IsTest
  static void updateReferencesRejectsInvalidChanges() {
    AXF_OBJ_PluggyConnection__c c = conn('item-with-sources');
    Id otherBank;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      otherBank = AXF_CLS_SourceSetupTestFactory.institution(
          configurer().Id,
          'Outro Banco',
          '9902'
        )
        .Id;
    }
    System.runAs(configurer()) {
      List<List<Id>> invalid = new List<List<Id>>{
        new List<Id>{ c.Id, otherBank, null },
        new List<Id>{ c.Id, null, otherBank },
        new List<Id>{ null, null, null }
      };
      for (List<Id> args : invalid) {
        try {
          AXF_CLS_CTRL_SourceDiscovery.updateReferences(
            args[0],
            args[1],
            args[2]
          );
          Assert.fail('invalid references must be rejected');
        } catch (AuraHandledException e) {
          Assert.isFalse(String.isBlank(auraMessage(e)));
        }
      }
    }
  }

  @IsTest
  static void deleteConnectionDeletesOnlyWhenNotInUse() {
    Id inUse = conn('item-with-sources').Id;
    Id empty = conn('item-empty').Id;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      AXF_CLS_SourceSetupTestFactory.bankAccount(
        configurer().Id,
        empty,
        bankId(),
        null,
        'unlinked-ba'
      );
    }
    System.runAs(configurer()) {
      AXF_CLS_SourceSetupDTO.DeleteResult blocked = AXF_CLS_CTRL_SourceDiscovery.deleteConnection(
        inUse
      );
      Assert.areEqual('BLOCKED', blocked.outcome);

      AXF_CLS_SourceSetupDTO.DeleteResult deleted = AXF_CLS_CTRL_SourceDiscovery.deleteConnection(
        empty
      );
      Assert.areEqual('DELETED', deleted.outcome, deleted.message);
      Assert.areEqual(1, deleted.accounts);

      AXF_CLS_SourceSetupDTO.DeleteResult missing = AXF_CLS_CTRL_SourceDiscovery.deleteConnection(
        empty
      );
      Assert.areEqual('NOT_FOUND', missing.outcome);
    }
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM AXF_OBJ_PluggyConnection__c WHERE Id = :empty]
    );
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM AXF_OBJ_BankAccount__c
        WHERE AXF_BA_EXI_PluggyAccountId__c = 'unlinked-ba'
      ]
    );
  }

  @IsTest
  static void createBankInstitutionIsIdempotentOnBankNumber() {
    System.runAs(configurer()) {
      AXF_CLS_SourceSetupDTO.BankInstitutionResult created = AXF_CLS_CTRL_SourceDiscovery.createBankInstitution(
        'Banco Novo',
        '7777'
      );
      Assert.areEqual('CREATED', created.outcome);
      AXF_CLS_SourceSetupDTO.BankInstitutionResult again = AXF_CLS_CTRL_SourceDiscovery.createBankInstitution(
        'Banco Novo',
        '7777'
      );
      Assert.areEqual('ALREADY', again.outcome);
      Assert.areEqual(created.institutionId, again.institutionId);
    }
  }

  @IsTest
  static void mappingsAndSanitizedErrors() {
    Assert.areEqual(
      'FAILED_RETRYABLE',
      ALT_CLS_PluggySourceSetup.runState(
        new AXF_OBJ_PluggyConnection__c(AXF_CON_TXT_SyncStatus__c = 'OUTDATED')
      )
    );
    Assert.areEqual(
      'FAILED_RETRYABLE',
      ALT_CLS_PluggySourceSetup.runState(
        new AXF_OBJ_PluggyConnection__c(
          AXF_CON_TXT_SyncErrorMessage__c = 'Falha HTTP 500'
        )
      )
    );
    Assert.areEqual(
      'RUNNING',
      ALT_CLS_PluggySourceSetup.runState(
        new AXF_OBJ_PluggyConnection__c(AXF_CON_TXT_SyncStatus__c = 'UPDATING')
      )
    );
    Assert.areEqual(
      'REVOKED',
      ALT_CLS_PluggySourceSetup.consentState('LOGIN_ERROR')
    );
    Assert.areEqual(
      'STALE',
      ALT_CLS_PluggySourceSetup.consentState('WAITING_USER_INPUT')
    );
    Assert.isNull(ALT_CLS_PluggySourceSetup.consentState(null));
    AuraHandledException e = AXF_CLS_CTRL_SourceDiscovery.auraError(
      new DmlException('internal detail')
    );
    Assert.isFalse(e.getMessage().contains('internal detail'));
  }

  @IsTest
  static void unexpectedFailuresAreSanitized() {
    Id connId = conn('item-empty').Id;
    AXF_CLS_CTRL_SourceDiscovery.simulateFailure = true;
    Integer failures = 0;
    System.runAs(configurer()) {
      try {
        AXF_CLS_CTRL_SourceDiscovery.getStatus(connId);
      } catch (AuraHandledException e) {
        failures++;
      }
      try {
        AXF_CLS_CTRL_SourceDiscovery.getConnections();
      } catch (AuraHandledException e) {
        failures++;
      }
      try {
        AXF_CLS_CTRL_SourceDiscovery.getDiscovered(connId);
      } catch (AuraHandledException e) {
        failures++;
      }
      try {
        AXF_CLS_CTRL_SourceDiscovery.registerConnection('item-x', bankId());
      } catch (AuraHandledException e) {
        failures++;
      }
      try {
        AXF_CLS_CTRL_SourceDiscovery.updateReferences(connId, null, null);
      } catch (AuraHandledException e) {
        failures++;
      }
      try {
        AXF_CLS_CTRL_SourceDiscovery.deleteConnection(connId);
      } catch (AuraHandledException e) {
        failures++;
        Assert.isFalse(e.getMessage().contains('Simulated'));
      }
    }
    Assert.areEqual(6, failures);
  }
}
