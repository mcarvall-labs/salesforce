/**
 * @description AXF-143: painel mostra nivel, ultimo sucesso, fontes incluidas/excluidas, cambio,
 * excecoes e acoes permitidas derivadas no servidor; limite de atualidade por conta excedido ->
 * fonte visivel como antiga e nivel cai; UNKNOWN distinto de zero legitimo; pessoa nao
 * autorizada nao e confirmada; sem fonte legivel -> BLOCKED; sem capacidade -> FORBIDDEN.
 */
@IsTest
private class ALT_CLS_ConfidencePanelServiceTest {
  private static User byAlias(String alias) {
    return [SELECT Id FROM User WHERE Alias = :alias LIMIT 1];
  }

  @TestSetup
  static void setup() {
    Id profileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
    .Id;
    List<User> users = new List<User>();
    for (
      String alias : new List<String>{
        'axf143g',
        'axf143p',
        'axf143n',
        'axf143f'
      }
    ) {
      users.add(
        new User(
          Alias = alias,
          Email = alias + '@example.invalid',
          EmailEncodingKey = 'UTF-8',
          LastName = 'User ' + alias,
          LanguageLocaleKey = 'pt_BR',
          LocaleSidKey = 'pt_BR',
          TimeZoneSidKey = 'America/Sao_Paulo',
          ProfileId = profileId,
          Username = alias + '.' + System.now().getTime() + '@example.invalid'
        )
      );
    }
    insert users;
    Map<String, Id> permissionSets = new Map<String, Id>();
    for (PermissionSet permission : [
      SELECT Id, Name
      FROM PermissionSet
      WHERE
        Name IN (
          'AXF_PS_GestorFinanceiro',
          'AXF_PS_Participante',
          'AXF_PS_PluggyIntegration'
        )
    ]) {
      permissionSets.put(permission.Name, permission.Id);
    }
    // Capability + object read, no FLS: exercises the BLOCKED field-access path.
    // Uses the pre-deployed AXF_PS_TestNoFLS permission set (object-level read grants
    // done at DEPLOY time) instead of dynamically inserting ObjectPermissions, since
    // Apex-time inserts referencing certain object SobjectTypes can hit stale platform
    // entity-cache errors (FIELD_INTEGRITY_EXCEPTION, Invalid object) unrelated to schema.
    Id noFlsId = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'AXF_PS_TestNoFLS'
      LIMIT 1
    ]
    .Id;
    insert new SetupEntityAccess(
      ParentId = noFlsId,
      SetupEntityId = [
        SELECT Id
        FROM CustomPermission
        WHERE DeveloperName = 'AXF_CanExplainConfidence'
        LIMIT 1
      ]
      .Id
    );
    insert new List<PermissionSetAssignment>{
      assignment(users[0].Id, permissionSets.get('AXF_PS_GestorFinanceiro')),
      assignment(users[0].Id, permissionSets.get('AXF_PS_PluggyIntegration')),
      assignment(users[1].Id, permissionSets.get('AXF_PS_GestorFinanceiro')),
      assignment(users[1].Id, permissionSets.get('AXF_PS_PluggyIntegration')),
      assignment(users[2].Id, permissionSets.get('AXF_PS_Participante')),
      assignment(users[3].Id, noFlsId)
    };
  }

  private static PermissionSetAssignment assignment(Id userId, Id psId) {
    return new PermissionSetAssignment(
      AssigneeId = userId,
      PermissionSetId = psId
    );
  }

  private static Account holder(String name) {
    Account result = new Account(
      Name = name,
      RecordTypeId = Account.SObjectType.getDescribe()
        .getRecordTypeInfosByDeveloperName()
        .get('AXF_Business')
        .getRecordTypeId()
    );
    insert result;
    return result;
  }

  private static AXF_OBJ_PluggyConnection__c connection(
    String itemId,
    Datetime lastSuccess,
    String consent,
    String collection
  ) {
    AXF_OBJ_PluggyConnection__c result = new AXF_OBJ_PluggyConnection__c(
      AXF_CON_EXI_PluggyItemId__c = itemId + '-' + System.now().getTime(),
      AXF_CON_PKL_ConsentState__c = consent,
      AXF_CON_PKL_CollectionState__c = collection,
      AXF_CON_TXT_InstitutionName__c = 'Banco ' + itemId,
      AXF_CON_DT_LastSuccessAt__c = lastSuccess
    );
    insert result;
    return result;
  }

  private static AXF_OBJ_BankAccount__c bank(
    Id holderId,
    String key,
    Id connectionId,
    String availability,
    Decimal limitHours
  ) {
    AXF_OBJ_BankAccount__c result = new AXF_OBJ_BankAccount__c(
      AXF_BA_LKP_Account__c = holderId,
      AXF_BA_PKL_AvailabilityState__c = availability,
      AXF_BA_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BA_TXT_InstitutionName__c = 'Banco ' + key,
      AXF_BA_TXT_NumberMasked__c = '****' + key,
      AXF_BA_NUM_FreshnessLimitHours__c = limitHours,
      AXF_BA_NUM_Version__c = 0
    );
    if (connectionId == null) {
      result.AXF_BA_EXI_ManualKey__c =
        'manual-' +
        key +
        '-' +
        System.now().getTime();
    } else {
      result.AXF_BA_LKP_Connection__c = connectionId;
      result.AXF_BA_EXI_PluggyAccountId__c =
        'pl-' +
        key +
        '-' +
        System.now().getTime();
    }
    insert result;
    return result;
  }

  private static AXF_OBJ_BankAccountTransaction__c bat(
    Id bankId,
    String key,
    Datetime importedAt
  ) {
    return new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_MDR_BankAccount__c = bankId,
      AXF_BAT_EXI_SourceKey__c = 'bat-' + key + '-' + System.now().getTime(),
      AXF_BAT_PKL_Source__c = 'CSV',
      AXF_BAT_DAT_Date__c = Date.today(),
      AXF_BAT_NUM_Magnitude__c = 10,
      AXF_BAT_PKL_Direction__c = 'DEBIT',
      AXF_BAT_PKL_Status__c = 'POSTED',
      AXF_BAT_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BAT_TXT_Description__c = key,
      AXF_BAT_DTM_ImportedAt__c = importedAt,
      AXF_BAT_NUM_Version__c = 0
    );
  }

  private static AXF_OBJ_CreditCardTransaction__c cct(
    Id cardId,
    String key,
    Datetime importedAt
  ) {
    return new AXF_OBJ_CreditCardTransaction__c(
      AXF_CCT_MDR_CreditCard__c = cardId,
      AXF_CCT_EXI_SourceKey__c = 'cct-' + key + '-' + System.now().getTime(),
      AXF_CCT_PKL_Source__c = 'MANUAL',
      AXF_CCT_DAT_Date__c = Date.today(),
      AXF_CCT_NUM_Magnitude__c = 10,
      AXF_CCT_PKL_Direction__c = 'DEBIT',
      AXF_CCT_PKL_Status__c = 'POSTED',
      AXF_CCT_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_CCT_TXT_Description__c = key,
      AXF_CCT_DTM_ImportedAt__c = importedAt,
      AXF_CCT_NUM_Version__c = 0
    );
  }

  private static ALT_CLS_ConfidencePanelService.SourceView source(
    ALT_CLS_ConfidencePanelService.Panel panel,
    Id sourceId
  ) {
    for (ALT_CLS_ConfidencePanelService.SourceView view : panel.sources) {
      if (view.sourceId == sourceId) {
        return view;
      }
    }
    return null;
  }

  @IsTest
  static void currentSourcesAreInformativeAndStaleOnesDegradeWithoutHidingData() {
    System.runAs(byAlias('axf143g')) {
      Datetime now = Datetime.newInstance(2026, 9, 14, 12, 0, 0);
      ALT_CLS_ConfidencePanelService.nowOverride = now;
      Account ana = holder('Ana Confianca');
      AXF_OBJ_PluggyConnection__c fresh = connection(
        'fresh',
        now.addHours(-2),
        'ACTIVE',
        'ACTIVE'
      );
      AXF_OBJ_BankAccount__c current = bank(
        ana.Id,
        'c',
        fresh.Id,
        'AVAILABLE',
        null
      );
      AXF_OBJ_CreditCard__c card = new AXF_OBJ_CreditCard__c(
        AXF_CC_LKP_Account__c = ana.Id,
        AXF_CC_PKL_AvailabilityState__c = 'AVAILABLE',
        AXF_CC_TXT_CurrencyIsoCode__c = 'USD',
        AXF_CC_TXT_InstitutionName__c = 'Cartao c',
        AXF_CC_TXT_LastFourMasked__c = '0001',
        AXF_CC_LKP_Connection__c = fresh.Id,
        AXF_CC_EXI_PluggyAccountId__c = 'pl-card-' + System.now().getTime(),
        AXF_CC_NUM_Version__c = 0
      );
      insert card;
      ALT_CLS_ConfidencePanelService service = new ALT_CLS_ConfidencePanelService();
      Test.startTest();
      ALT_CLS_ConfidencePanelService.Panel informative = service.explain(
        new List<Id>{ ana.Id }
      );
      // Same scope after the per-account limit is exceeded: still visible, no longer current.
      AXF_OBJ_PluggyConnection__c old = connection(
        'old',
        now.addHours(-30),
        'ACTIVE',
        'ACTIVE'
      );
      AXF_OBJ_BankAccount__c stale = bank(ana.Id, 's', old.Id, 'AVAILABLE', 24);
      ALT_CLS_ConfidencePanelService.Panel degraded = service.explain(
        new List<Id>{ ana.Id }
      );
      Test.stopTest();

      Assert.areEqual('INFORMATIVE', informative.level);
      Assert.areEqual('confidence-panel@1.0.0', informative.policyVersion);
      Assert.areEqual(now, informative.asOf);
      Assert.areEqual(2, informative.includedCount);
      Assert.areEqual(0, informative.excludedCount);
      Assert.isTrue(informative.reasons.isEmpty());
      Assert.areEqual(new List<String>{ 'BRL', 'USD' }, informative.currencies);
      Assert.areEqual(
        new List<String>{ 'OPEN_SOURCE' },
        informative.allowedActions
      );
      ALT_CLS_ConfidencePanelService.SourceView bankView = source(
        informative,
        current.Id
      );
      Assert.areEqual('PLUGGY', bankView.origin);
      Assert.areEqual('CURRENT', bankView.freshness);
      Assert.areEqual(48, bankView.freshnessLimitHours, 'padrao da politica');
      Assert.areEqual(now.addHours(-2), bankView.lastSuccessAt);
      Assert.areEqual(0, bankView.factCount, 'zero legitimo, nao UNKNOWN');
      Assert.areEqual('Ana Confianca', bankView.holderName);
      Assert.areEqual('Banco c ****c', bankView.label);
      Assert.isTrue(bankView.navigable);
      Assert.isTrue(bankView.exceptions.isEmpty());
      Assert.areEqual('CARD', source(informative, card.Id).kind);

      Assert.areEqual('DEGRADED', degraded.level);
      Assert.areEqual(
        3,
        degraded.includedCount,
        'fonte antiga continua visivel'
      );
      ALT_CLS_ConfidencePanelService.SourceView staleView = source(
        degraded,
        stale.Id
      );
      Assert.areEqual('STALE', staleView.freshness, 'nao aparece como atual');
      Assert.areEqual(
        24,
        staleView.freshnessLimitHours,
        'limite da conta prevalece'
      );
      Assert.isTrue(staleView.included);
      Assert.isTrue(staleView.exceptions.contains('FRESHNESS_EXCEEDED'));
      Assert.isTrue(degraded.reasons.contains('STALE_SOURCE'));
      Assert.isTrue(degraded.reasons.contains('FRESHNESS_EXCEEDED'));
      Assert.isTrue(degraded.allowedActions.contains('REVIEW_SOURCE_HEALTH'));
      Assert.areEqual('CURRENT', source(degraded, current.Id).freshness);
    }
  }

  @IsTest
  static void manualSourcesUseLastImportAndUnknownIsDistinctFromZero() {
    System.runAs(byAlias('axf143g')) {
      Datetime now = Datetime.newInstance(2026, 9, 14, 12, 0, 0);
      ALT_CLS_ConfidencePanelService.nowOverride = now;
      Account ana = holder('Ana Manual');
      AXF_OBJ_BankAccount__c imported = bank(
        ana.Id,
        'i',
        null,
        'AVAILABLE',
        null
      );
      AXF_OBJ_BankAccount__c empty = bank(ana.Id, 'e', null, 'AVAILABLE', null);
      AXF_OBJ_BankAccount__c custody = bank(ana.Id, 'k', null, 'CUSTODY', null);
      insert new List<AXF_OBJ_BankAccountTransaction__c>{
        bat(imported.Id, 'i1', now.addHours(-70)),
        bat(imported.Id, 'i2', now.addHours(-10)),
        bat(custody.Id, 'k1', now.addHours(-1))
      };
      Test.startTest();
      ALT_CLS_ConfidencePanelService.Panel panel = new ALT_CLS_ConfidencePanelService()
        .explain(new List<Id>{ ana.Id });
      Test.stopTest();
      Assert.areEqual('DEGRADED', panel.level);
      ALT_CLS_ConfidencePanelService.SourceView importedView = source(
        panel,
        imported.Id
      );
      Assert.areEqual('MANUAL', importedView.origin);
      Assert.areEqual(
        now.addHours(-10),
        importedView.lastSuccessAt,
        'ultima importacao'
      );
      Assert.areEqual('CURRENT', importedView.freshness);
      Assert.areEqual(2, importedView.factCount);
      ALT_CLS_ConfidencePanelService.SourceView emptyView = source(
        panel,
        empty.Id
      );
      Assert.areEqual('UNKNOWN', emptyView.freshness, 'sem sucesso registrado');
      Assert.isNull(emptyView.lastSuccessAt);
      Assert.areEqual(0, emptyView.factCount);
      Assert.isTrue(emptyView.exceptions.contains('NO_SUCCESS_RECORDED'));
      ALT_CLS_ConfidencePanelService.SourceView custodyView = source(
        panel,
        custody.Id
      );
      Assert.isFalse(custodyView.included);
      Assert.areEqual('CUSTODY', custodyView.exclusionReason);
      Assert.areEqual(1, panel.excludedCount);
      Assert.areEqual(2, panel.includedCount);
      Assert.isTrue(panel.reasons.contains('UNKNOWN_FRESHNESS'));
      Assert.isTrue(panel.reasons.contains('SOURCE_EXCLUDED'));
    }
  }

  @IsTest
  static void consentExceptionsAreSurfacedFromTheProvider() {
    System.runAs(byAlias('axf143g')) {
      Datetime now = Datetime.newInstance(2026, 9, 14, 12, 0, 0);
      ALT_CLS_ConfidencePanelService.nowOverride = now;
      Account ana = holder('Ana Consentimento');
      AXF_OBJ_PluggyConnection__c revoked = connection(
        'rev',
        now.addHours(-1),
        'REVOKED',
        'ACTIVE'
      );
      AXF_OBJ_PluggyConnection__c paused = connection(
        'pau',
        now.addHours(-1),
        'STALE',
        'PAUSED'
      );
      AXF_OBJ_BankAccount__c revokedBank = bank(
        ana.Id,
        'r',
        revoked.Id,
        'AVAILABLE',
        null
      );
      AXF_OBJ_BankAccount__c pausedBank = bank(
        ana.Id,
        'p',
        paused.Id,
        'AVAILABLE',
        null
      );
      Test.startTest();
      ALT_CLS_ConfidencePanelService.Panel panel = new ALT_CLS_ConfidencePanelService()
        .explain(new List<Id>{ ana.Id });
      Test.stopTest();
      Assert.areEqual('DEGRADED', panel.level);
      Assert.isTrue(
        source(panel, revokedBank.Id).exceptions.contains('CONSENT_REVOKED')
      );
      Assert.isTrue(
        source(panel, pausedBank.Id).exceptions.contains('CONSENT_STALE')
      );
      Assert.isTrue(
        source(panel, pausedBank.Id).exceptions.contains('COLLECTION_PAUSED')
      );
      Assert.areEqual(
        'CURRENT',
        source(panel, revokedBank.Id).freshness,
        'dado continua visivel'
      );
      Assert.isTrue(panel.reasons.contains('CONSENT_REVOKED'));
    }
  }

  @IsTest
  static void unauthorizedHolderIsNotConfirmedAndEmptyScopeBlocks() {
    Account foreign;
    System.runAs(byAlias('axf143p')) {
      foreign = holder('Empresa Alheia');
      bank(foreign.Id, 'x', null, 'AVAILABLE', null);
    }
    System.runAs(byAlias('axf143g')) {
      Account mine = holder('Empresa Minha');
      bank(mine.Id, 'm', null, 'AVAILABLE', null);
      Id fake =
        Account.SObjectType.getDescribe().getKeyPrefix() + '000000000ZZZ';
      ALT_CLS_ConfidencePanelService service = new ALT_CLS_ConfidencePanelService();
      Test.startTest();
      ALT_CLS_ConfidencePanelService.Panel mixed = service.explain(
        new List<Id>{ mine.Id, foreign.Id, fake }
      );
      ALT_CLS_ConfidencePanelService.Panel none = service.explain(
        new List<Id>{ foreign.Id }
      );
      List<ALT_CLS_ConfidencePanelService.HolderOption> holders = service.listHolders();
      Test.stopTest();
      Assert.areEqual(2, mixed.exclusions.size());
      for (
        ALT_CLS_ConfidencePanelService.Exclusion exclusion : mixed.exclusions
      ) {
        Assert.areEqual('NOT_AUTHORIZED', exclusion.reason);
      }
      Assert.areEqual(
        1,
        mixed.sources.size(),
        'so a fonte da pessoa autorizada'
      );
      Assert.isTrue(mixed.reasons.contains('HOLDER_NOT_AUTHORIZED'));
      Assert.areEqual('DEGRADED', mixed.level);
      Assert.isFalse(JSON.serialize(mixed).contains('Alheia'));
      Assert.areEqual('BLOCKED', none.level);
      Assert.isTrue(none.reasons.contains('NO_AUTHORIZED_SCOPE'));
      Assert.isTrue(none.allowedActions.isEmpty());
      Assert.isTrue(none.sources.isEmpty());
      Assert.areEqual(1, holders.size());
      Assert.areEqual(mine.Id, holders[0].accountId);
    }
  }

  @IsTest
  static void noReadableSourceBlocksAndMissingCapabilityForbids() {
    System.runAs(byAlias('axf143g')) {
      Account bare = holder('Empresa Sem Fonte');
      ALT_CLS_ConfidencePanelService service = new ALT_CLS_ConfidencePanelService();
      ALT_CLS_ConfidencePanelService.Panel panel = service.explain(
        new List<Id>{ bare.Id }
      );
      Assert.areEqual('BLOCKED', panel.level);
      Assert.isTrue(panel.reasons.contains('NO_READABLE_SOURCE'));
      try {
        service.explain(new List<Id>());
        Assert.fail('INVALID_INPUT esperado');
      } catch (ALT_CLS_ConfidencePanelService.ConfidenceException expected) {
        Assert.areEqual('INVALID_INPUT', expected.code);
      }
    }
    System.runAs(byAlias('axf143n')) {
      try {
        new ALT_CLS_ConfidencePanelService().listHolders();
        Assert.fail('FORBIDDEN esperado');
      } catch (ALT_CLS_ConfidencePanelService.ConfidenceException expected) {
        Assert.areEqual('FORBIDDEN', expected.code);
      }
    }
  }

  @IsTest
  static void nonAxonAccountsAreNotHoldersAndScopeIsBounded() {
    List<RecordType> foreign = [
      SELECT Id
      FROM RecordType
      WHERE
        SobjectType = 'Account'
        AND IsActive = TRUE
        AND DeveloperName NOT IN ('AXF_Person', 'AXF_Business')
      LIMIT 1
    ];
    Account plain = new Account(Name = 'Conta Comum');
    if (!foreign.isEmpty()) {
      plain.RecordTypeId = foreign[0].Id;
    }
    insert plain;
    insert new AccountShare(
      AccountId = plain.Id,
      UserOrGroupId = byAlias('axf143g').Id,
      AccountAccessLevel = 'Read',
      OpportunityAccessLevel = 'None',
      CaseAccessLevel = 'None'
    );
    String plainType = [
        SELECT RecordType.DeveloperName
        FROM Account
        WHERE Id = :plain.Id
      ]
      .RecordType
      ?.DeveloperName;
    System.runAs(byAlias('axf143g')) {
      Account mine = holder('Empresa Escopo');
      bank(mine.Id, 'b', null, 'AVAILABLE', null);
      ALT_CLS_ConfidencePanelService service = new ALT_CLS_ConfidencePanelService();
      Test.startTest();
      ALT_CLS_ConfidencePanelService.Panel panel = service.explain(
        new List<Id>{ mine.Id, plain.Id, null }
      );
      List<ALT_CLS_ConfidencePanelService.HolderOption> holders = service.listHolders();
      Test.stopTest();
      Assert.areEqual(1, panel.sources.size());
      if (plainType != 'AXF_Person' && plainType != 'AXF_Business') {
        Assert.areEqual(1, holders.size(), 'conta comum nao e titular');
        Assert.areEqual(1, panel.exclusions.size());
        Assert.areEqual('NOT_A_HOLDER', panel.exclusions[0].reason);
        Assert.areEqual(plain.Id, panel.exclusions[0].accountId);
      }
      try {
        service.explain(new List<Id>{ null });
        Assert.fail('Somente nulos e entrada invalida');
      } catch (ALT_CLS_ConfidencePanelService.ConfidenceException expected) {
        Assert.areEqual('INVALID_INPUT', expected.code);
      }
      List<Id> tooMany = new List<Id>();
      String prefix = Account.SObjectType.getDescribe().getKeyPrefix();
      for (Integer i = 0; i <= ALT_CLS_ConfidencePanelService.MAX_SCOPE; i++) {
        tooMany.add(prefix + String.valueOf(100000000000L + i).right(12));
      }
      try {
        service.explain(tooMany);
        Assert.fail('Escopo acima do limite');
      } catch (ALT_CLS_ConfidencePanelService.ConfidenceException expected) {
        Assert.areEqual('INVALID_INPUT', expected.code);
      }
    }
    System.runAs(byAlias('axf143n')) {
      try {
        new ALT_CLS_ConfidencePanelService().explain(new List<Id>());
        Assert.fail('Capacidade antes da validacao');
      } catch (ALT_CLS_ConfidencePanelService.ConfidenceException expected) {
        Assert.areEqual('FORBIDDEN', expected.code);
      }
    }
  }

  @IsTest
  static void manualCardsFreshnessBoundariesAndUnreadableConnectionsAreExplained() {
    Datetime now = Datetime.newInstance(2026, 9, 14, 12, 0, 0);
    Account ana;
    AXF_OBJ_PluggyConnection__c hidden;
    System.runAs(byAlias('axf143p')) {
      // A connection the gestor cannot read (OWD Private, owned by another user).
      hidden = connection('hidden', now.addHours(-1), 'ACTIVE', 'ACTIVE');
    }
    System.runAs(byAlias('axf143g')) {
      ana = holder('Ana Cartao');
    }
    // Sources owned by the gestor whose connection stays unreadable to them.
    AXF_OBJ_BankAccount__c hiddenBank = new AXF_OBJ_BankAccount__c(
      AXF_BA_LKP_Account__c = ana.Id,
      AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_BA_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BA_TXT_InstitutionName__c = 'Banco n',
      AXF_BA_TXT_NumberMasked__c = '****n',
      AXF_BA_LKP_Connection__c = hidden.Id,
      AXF_BA_EXI_PluggyAccountId__c = 'pl-n-' + System.now().getTime(),
      AXF_BA_NUM_Version__c = 0,
      OwnerId = byAlias('axf143g').Id
    );
    AXF_OBJ_BankAccount__c custody = hiddenBank.clone(
      false,
      false,
      false,
      false
    );
    custody.AXF_BA_PKL_AvailabilityState__c = 'CUSTODY';
    custody.AXF_BA_TXT_InstitutionName__c = 'Banco k';
    custody.AXF_BA_TXT_NumberMasked__c = '****k';
    custody.AXF_BA_EXI_PluggyAccountId__c = 'pl-k-' + System.now().getTime();
    insert new List<AXF_OBJ_BankAccount__c>{ hiddenBank, custody };
    System.runAs(byAlias('axf143g')) {
      ALT_CLS_ConfidencePanelService.nowOverride = now;
      AXF_OBJ_CreditCard__c manualCard = new AXF_OBJ_CreditCard__c(
        AXF_CC_LKP_Account__c = ana.Id,
        AXF_CC_PKL_AvailabilityState__c = 'AVAILABLE',
        AXF_CC_TXT_CurrencyIsoCode__c = 'BRL',
        AXF_CC_TXT_InstitutionName__c = 'Cartao manual',
        AXF_CC_TXT_LastFourMasked__c = '0002',
        AXF_CC_EXI_ManualKey__c = 'card-' + System.now().getTime(),
        AXF_CC_NUM_Version__c = 0
      );
      insert manualCard;
      insert new List<AXF_OBJ_CreditCardTransaction__c>{
        cct(manualCard.Id, 'c1', now.addHours(-5)),
        cct(manualCard.Id, 'c2', null)
      };
      AXF_OBJ_BankAccount__c keyed = bank(ana.Id, 'h', null, 'AVAILABLE', null);
      insert bat(keyed.Id, 'h1', null);
      // Exactly at the limit (24h) is no longer current; a future success is unknown.
      AXF_OBJ_PluggyConnection__c edge = connection(
        'edge',
        now.addHours(-24),
        'ACTIVE',
        'ACTIVE'
      );
      AXF_OBJ_BankAccount__c edgeBank = bank(
        ana.Id,
        'e',
        edge.Id,
        'AVAILABLE',
        24
      );
      AXF_OBJ_PluggyConnection__c future = connection(
        'future',
        now.addMinutes(5),
        'ACTIVE',
        'ACTIVE'
      );
      AXF_OBJ_BankAccount__c futureBank = bank(
        ana.Id,
        'f',
        future.Id,
        'AVAILABLE',
        null
      );
      Test.startTest();
      ALT_CLS_ConfidencePanelService.Panel panel = new ALT_CLS_ConfidencePanelService()
        .explain(new List<Id>{ ana.Id });
      Test.stopTest();
      ALT_CLS_ConfidencePanelService.SourceView cardView = source(
        panel,
        manualCard.Id
      );
      Assert.areEqual('CARD', cardView.kind);
      Assert.areEqual('MANUAL', cardView.origin);
      Assert.areEqual(2, cardView.factCount);
      Assert.areEqual(now.addHours(-5), cardView.lastSuccessAt);
      Assert.areEqual('CURRENT', cardView.freshness);
      ALT_CLS_ConfidencePanelService.SourceView keyedView = source(
        panel,
        keyed.Id
      );
      Assert.areEqual(1, keyedView.factCount);
      Assert.isNotNull(
        keyedView.lastSuccessAt,
        'sem data de importacao usa a criacao'
      );
      Assert.isTrue(keyedView.exceptions.contains('IMPORT_DATE_MISSING'));
      Assert.isFalse(keyedView.exceptions.contains('NO_SUCCESS_RECORDED'));
      Assert.areEqual(
        'STALE',
        source(panel, edgeBank.Id).freshness,
        'no limite ja nao e atual'
      );
      ALT_CLS_ConfidencePanelService.SourceView futureView = source(
        panel,
        futureBank.Id
      );
      Assert.areEqual('UNKNOWN', futureView.freshness);
      Assert.isTrue(futureView.exceptions.contains('FUTURE_SUCCESS'));
      ALT_CLS_ConfidencePanelService.SourceView hiddenView = source(
        panel,
        hiddenBank.Id
      );
      Assert.areEqual('PLUGGY', hiddenView.origin);
      Assert.isTrue(hiddenView.exceptions.contains('CONNECTION_NOT_READABLE'));
      Assert.isNull(hiddenView.lastSuccessAt);
      Assert.isTrue(panel.reasons.contains('CONNECTION_NOT_READABLE'));
      Assert.isTrue(panel.reasons.contains('FUTURE_SUCCESS'));
      // Row exceptions of the excluded custody source never become panel reasons by themselves.
      Assert.isFalse(source(panel, custody.Id).included);
      Assert.isTrue(panel.reasons.contains('SOURCE_EXCLUDED'));
      Assert.areEqual('DEGRADED', panel.level);
      Assert.isFalse(
        JSON.serialize(panel).contains('Banco hidden'),
        'nada da conexao oculta e afirmado'
      );
    }
  }

  @IsTest
  static void policyGapsAndFieldAccessGapsBlockWithExplicitReasons() {
    Account mine;
    System.runAs(byAlias('axf143g')) {
      mine = holder('Empresa Politica');
      bank(mine.Id, 'q', null, 'AVAILABLE', null);
      ALT_CLS_ConfidencePanelService service = new ALT_CLS_ConfidencePanelService();
      ALT_CLS_ConfidencePanelService.policyOverride = new AXF_CMT_ConfidencePolicy__mdt(
        DeveloperName = 'Default',
        AXF_CFP_TXT_PolicyVersion__c = 'test',
        AXF_CFP_NUM_DefaultFreshnessHours__c = 0
      );
      ALT_CLS_ConfidencePanelService.Panel invalid = service.explain(
        new List<Id>{ mine.Id }
      );
      Assert.areEqual('BLOCKED', invalid.level);
      Assert.isTrue(invalid.reasons.contains('POLICY_INVALID'));
      Assert.isTrue(invalid.allowedActions.isEmpty());
      Assert.isTrue(invalid.sources.isEmpty(), 'nada carregado sem politica');
      ALT_CLS_ConfidencePanelService.policyOverride = null;
      // Nothing readable: excluded sources are named before blocking.
      Account custodyOnly = holder('Empresa Custodia');
      bank(custodyOnly.Id, 'z', null, 'CUSTODY', null);
      ALT_CLS_ConfidencePanelService.Panel blocked = service.explain(
        new List<Id>{ custodyOnly.Id }
      );
      Assert.areEqual('BLOCKED', blocked.level);
      Assert.isTrue(blocked.reasons.contains('SOURCE_EXCLUDED'));
      Assert.isTrue(blocked.reasons.contains('NO_READABLE_SOURCE'));
    }
    System.runAs(byAlias('axf143f')) {
      ALT_CLS_ConfidencePanelService.Panel gaps = new ALT_CLS_ConfidencePanelService()
        .explain(new List<Id>{ mine.Id });
      Assert.areEqual('BLOCKED', gaps.level);
      Assert.isTrue(
        gaps.reasons.contains('FIELD_ACCESS:AXF_BA_TXT_InstitutionName__c'),
        String.join(gaps.reasons, ',')
      );
      Assert.isTrue(gaps.allowedActions.isEmpty());
      Assert.isTrue(gaps.sources.isEmpty());
    }
  }
}
