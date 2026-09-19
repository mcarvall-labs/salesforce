/**
 * @description AXF-126: rateio economico — propriedade separada da atribuicao (nada inferido na
 * ingestao), proposta com parcelas positivas/moeda original/pessoas autorizadas/identidade
 * canonica, confirmacao com 100% exato, rejeicao atomica (soma != 100, negativo, nao autorizado,
 * versao obsoleta), sem share implicito, idempotencia por operacao, guards e erros sanitizados.
 * AXF-127: projecao derivada de atribuicao unica (ramo integral e ramo rateio).
 */
@IsTest
private class ALT_CLS_EconomicAllocationServiceTest {
  private static User gestor() {
    return [SELECT Id FROM User WHERE Alias = 'axf126g' LIMIT 1];
  }
  private static User participant() {
    return [SELECT Id FROM User WHERE Alias = 'axf126p' LIMIT 1];
  }

  @TestSetup
  static void setup() {
    Id profileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
    .Id;
    User gestor = new User(
      Alias = 'axf126g',
      Email = 'axf126g@example.invalid',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Allocation Gestor',
      LanguageLocaleKey = 'pt_BR',
      LocaleSidKey = 'pt_BR',
      TimeZoneSidKey = 'America/Sao_Paulo',
      ProfileId = profileId,
      Username = 'axf126g.' + System.now().getTime() + '@example.invalid'
    );
    User participant = gestor.clone(false, false, false, false);
    participant.Alias = 'axf126p';
    participant.LastName = 'Allocation Participant';
    participant.Username =
      'axf126p.' +
      System.now().getTime() +
      '@example.invalid';
    insert new List<User>{ gestor, participant };
    List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (PermissionSet permission : [
      SELECT Id, Name
      FROM PermissionSet
      WHERE
        Name IN (
          'AXF_PS_GestorFinanceiro',
          'AXF_PS_FinancialEntry',
          'AXF_PS_Participante'
        )
    ]) {
      if (permission.Name == 'AXF_PS_Participante') {
        assignments.add(
          new PermissionSetAssignment(
            AssigneeId = participant.Id,
            PermissionSetId = permission.Id
          )
        );
      } else {
        assignments.add(
          new PermissionSetAssignment(
            AssigneeId = gestor.Id,
            PermissionSetId = permission.Id
          )
        );
      }
      if (permission.Name == 'AXF_PS_FinancialEntry') {
        assignments.add(
          new PermissionSetAssignment(
            AssigneeId = participant.Id,
            PermissionSetId = permission.Id
          )
        );
      }
    }
    insert assignments;
  }

  private static Account holder(String name, String recordType) {
    Account result = new Account(
      RecordTypeId = Account.SObjectType.getDescribe()
        .getRecordTypeInfosByDeveloperName()
        .get(recordType)
        .getRecordTypeId()
    );
    if (recordType == 'AXF_Person') {
      result.LastName = name;
    } else {
      result.Name = name;
    }
    insert result;
    return result;
  }

  private static AXF_OBJ_BankAccountTransaction__c bankFact(
    Account owner,
    String key
  ) {
    return bankFact(owner, key, 300);
  }

  private static AXF_OBJ_BankAccountTransaction__c bankFact(
    Account owner,
    String key,
    Decimal magnitude
  ) {
    AXF_OBJ_BankAccount__c bank = new AXF_OBJ_BankAccount__c(
      AXF_BA_LKP_Account__c = owner.Id,
      AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_BA_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BA_TXT_InstitutionName__c = 'Banco ' + key,
      AXF_BA_TXT_NumberMasked__c = '****' + key,
      AXF_BA_EXI_ManualKey__c = 'manual-' + key + '-' + System.now().getTime(),
      AXF_BA_NUM_Version__c = 0
    );
    insert bank;
    AXF_OBJ_BankAccountTransaction__c fact = new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_MDR_BankAccount__c = bank.Id,
      AXF_BAT_EXI_SourceKey__c = 'bat-' + key + '-' + System.now().getTime(),
      AXF_BAT_PKL_Source__c = 'MANUAL',
      AXF_BAT_DAT_Date__c = Date.today(),
      AXF_BAT_NUM_Magnitude__c = magnitude,
      AXF_BAT_PKL_Direction__c = 'DEBIT',
      AXF_BAT_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BAT_TXT_Description__c = 'Mercado',
      AXF_BAT_NUM_Version__c = 0
    );
    insert fact;
    return fact;
  }

  private static AXF_OBJ_CreditCardTransaction__c cardFact(
    Account owner,
    String key,
    String status
  ) {
    AXF_OBJ_CreditCard__c card = new AXF_OBJ_CreditCard__c(
      AXF_CC_LKP_Account__c = owner.Id,
      AXF_CC_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_CC_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_CC_EXI_ManualKey__c = 'card-' + key + '-' + System.now().getTime()
    );
    insert card;
    AXF_OBJ_CreditCardTransaction__c fact = new AXF_OBJ_CreditCardTransaction__c(
      AXF_CCT_MDR_CreditCard__c = card.Id,
      AXF_CCT_EXI_SourceKey__c = 'cct-' + key + '-' + System.now().getTime(),
      AXF_CCT_PKL_Source__c = 'MANUAL',
      AXF_CCT_DAT_Date__c = Date.today(),
      AXF_CCT_NUM_Magnitude__c = 120,
      AXF_CCT_PKL_Direction__c = 'DEBIT',
      AXF_CCT_PKL_Status__c = status,
      AXF_CCT_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_CCT_TXT_Description__c = 'Restaurante'
    );
    insert fact;
    return fact;
  }

  private static AXF_OBJ_FinancialTransaction__c manualFact(
    Account owner,
    String key
  ) {
    AXF_OBJ_FinancialTransaction__c fact = new AXF_OBJ_FinancialTransaction__c(
      AXF_FTX_LKP_Account__c = owner.Id,
      AXF_FTX_NUM_Magnitude__c = 90,
      AXF_FTX_PKL_Direction__c = 'DEBIT',
      AXF_FTX_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_FTX_DAT_PurchaseDate__c = Date.today(),
      AXF_FTX_PKL_Status__c = 'PLANNED',
      AXF_FTX_EXI_ClientRequestId__c = 'ftx-' +
        key +
        '-' +
        System.now().getTime()
    );
    insert fact;
    return fact;
  }

  private static void expectAura(String expectedCode, String forbiddenText) {
    try {
      AXF_CLS_CTRL_EconomicAllocation.getContext(null);
      Assert.fail('Controller deveria falhar.');
    } catch (AuraHandledException expected) {
      Assert.isTrue(
        expected.getMessage().contains(expectedCode),
        'Codigo esperado: ' + expectedCode + ' em ' + expected.getMessage()
      );
      Assert.isFalse(
        expected.getMessage().contains(forbiddenText),
        'Detalhe interno vazou: ' + expected.getMessage()
      );
    }
  }

  private static ALT_CLS_EconomicAllocationService.ProposeInput proposal(
    String kind,
    Id factId,
    String key,
    Map<Id, Decimal> shares
  ) {
    ALT_CLS_EconomicAllocationService.ProposeInput input = new ALT_CLS_EconomicAllocationService.ProposeInput();
    input.factKind = kind;
    input.factId = factId;
    input.operationKey = key;
    input.shares = new List<ALT_CLS_EconomicAllocationService.ShareInput>();
    for (Id accountId : shares.keySet()) {
      ALT_CLS_EconomicAllocationService.ShareInput share = new ALT_CLS_EconomicAllocationService.ShareInput();
      share.accountId = accountId;
      share.percent = shares.get(accountId);
      input.shares.add(share);
    }
    return input;
  }

  private static ALT_CLS_EconomicAllocationService.EconomicAllocationException expectFailure(
    ALT_CLS_EconomicAllocationService service,
    ALT_CLS_EconomicAllocationService.ProposeInput input
  ) {
    try {
      service.propose(input);
      Assert.fail('Proposta deveria falhar.');
    } catch (ALT_CLS_EconomicAllocationService.EconomicAllocationException expected) {
      return expected;
    }
    return null;
  }

  @IsTest
  static void ingestionInfersNothingAndProposalThenConfirmationRequireExactHundred() {
    System.runAs(gestor()) {
      Account owner = holder('Titular Conta', 'AXF_Person');
      Account partner = holder('Empresa Socia', 'AXF_Business');
      AXF_OBJ_BankAccountTransaction__c fact = bankFact(owner, 'a');
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM AXF_OBJ_EconomicAllocationSet__c],
        'AC1: ingestao nao infere que o titular consumiu o valor.'
      );
      ALT_CLS_EconomicAllocationService service = new ALT_CLS_EconomicAllocationService();
      Test.startTest();
      ALT_CLS_EconomicAllocationService.SetView draft = service.propose(
        proposal(
          'BANK',
          fact.Id,
          'op-a1',
          new Map<Id, Decimal>{ owner.Id => 60, partner.Id => 30 }
        )
      );
      Assert.areEqual('DRAFT', draft.state);
      Assert.areEqual(1, draft.revision);
      Assert.areEqual(90, draft.totalPercent);
      Assert.areEqual(2, draft.shares.size());
      Assert.areEqual(
        270,
        draft.shares[1].magnitude + draft.shares[0].magnitude,
        '90% de 300 na moeda original.'
      );
      for (ALT_CLS_EconomicAllocationService.ShareView share : draft.shares) {
        Assert.isTrue(share.magnitude > 0, 'Magnitude sempre positiva.');
        Assert.areEqual('BRL', share.currencyIso, 'Moeda original.');
        Assert.areEqual(
          64,
          share.allocationKey.length(),
          'Identidade canonica alloc-v2.'
        );
      }
      // Replay of the same proposal returns the same draft; a different payload conflicts.
      Assert.areEqual(
        draft.setId,
        service.propose(
            proposal(
              'BANK',
              fact.Id,
              'op-a1',
              new Map<Id, Decimal>{ owner.Id => 60, partner.Id => 30 }
            )
          )
          .setId
      );
      Assert.areEqual(
        'CONFLICT',
        expectFailure(
            service,
            proposal(
              'BANK',
              fact.Id,
              'op-a1',
              new Map<Id, Decimal>{ owner.Id => 100 }
            )
          )
          .code
      );
      // 90% cannot be confirmed; nothing changes.
      try {
        service.confirm(draft.setId, draft.version, 'op-c1');
        Assert.fail('Soma diferente de 100% deve ser rejeitada.');
      } catch (ALT_CLS_EconomicAllocationService.EconomicAllocationException expected) {
        Assert.areEqual('CONFIRMATION_REJECTED', expected.code);
        Assert.isTrue(
          String.join(expected.reasons, ',').contains('TOTAL_NOT_100')
        );
      }
      Assert.areEqual('DRAFT', service.read(draft.setId).state);
      // A second revision with exactly 100% confirms; stale version conflicts first.
      ALT_CLS_EconomicAllocationService.SetView second = service.propose(
        proposal(
          'BANK',
          fact.Id,
          'op-a2',
          new Map<Id, Decimal>{ owner.Id => 70, partner.Id => 30 }
        )
      );
      Assert.areEqual(2, second.revision);
      try {
        service.confirm(second.setId, 99, 'op-c2');
        Assert.fail('Versao obsoleta conflita.');
      } catch (ALT_CLS_EconomicAllocationService.EconomicAllocationException expected) {
        Assert.areEqual('CONFLICT', expected.code);
      }
      ALT_CLS_EconomicAllocationService.SetView confirmed = service.confirm(
        second.setId,
        second.version,
        'op-c2'
      );
      Test.stopTest();
      Assert.areEqual('CONFIRMED', confirmed.state);
      Assert.areEqual(100, confirmed.totalPercent);
      Assert.isNotNull(confirmed.effectiveAt);
      Assert.areEqual(
        confirmed.setId,
        service.confirm(second.setId, confirmed.version, 'op-c2').setId,
        'Replay da confirmacao e idempotente.'
      );
      Assert.areEqual(
        'ACTIVE_SET_EXISTS',
        expectFailure(
            service,
            proposal(
              'BANK',
              fact.Id,
              'op-a3',
              new Map<Id, Decimal>{ owner.Id => 100 }
            )
          )
          .code,
        'Nova proposta nao contorna a revisao (historia irma).'
      );
      Assert.areEqual(
        0,
        [
          SELECT COUNT()
          FROM AXF_OBJ_EconomicAllocationSet__Share
          WHERE RowCause != 'Owner'
        ],
        'Rateio nao cria share implicito.'
      );
      Assert.areEqual(
        0,
        [
          SELECT COUNT()
          FROM AccountShare
          WHERE AccountId = :partner.Id AND RowCause != 'Owner'
        ],
        'Rateio nao cria share implicito na pessoa/empresa.'
      );
      AXF_OBJ_EconomicAllocationSet__c stored = [
        SELECT AXF_EAS_EXI_ActiveToken__c, AXF_EAS_TXT_FactIdentity__c
        FROM AXF_OBJ_EconomicAllocationSet__c
        WHERE Id = :confirmed.setId
      ];
      Assert.isNotNull(
        stored.AXF_EAS_EXI_ActiveToken__c,
        'Token ativo mantido transacionalmente.'
      );
      Assert.areEqual(
        fact.AXF_BAT_EXI_SourceKey__c,
        stored.AXF_EAS_TXT_FactIdentity__c
      );
    }
  }

  @IsTest
  static void invalidSharesAreRejectedAtomicallyWithoutPartialPersistence() {
    Account owner;
    Account partner;
    Account unauthorized;
    AXF_OBJ_BankAccountTransaction__c fact;
    System.runAs(gestor()) {
      owner = holder('Titular B', 'AXF_Person');
      partner = holder('Empresa B', 'AXF_Business');
      // An Account with a record type outside the holder set cannot be built in this org: only
      // AXF_Person and AXF_Business exist and AXF_Business is the org default, so every insert is
      // an authorized holder. The unauthorized holder is produced through sharing instead — the
      // account moves to an owner the gestor shares nothing with — which is the same fixture the
      // reversal test below already relies on.
      unauthorized = holder('Sem acesso para o gestor', 'AXF_Business');
      fact = bankFact(owner, 'b');
    }
    update new Account(Id = unauthorized.Id, OwnerId = participant().Id);
    System.runAs(gestor()) {
      ALT_CLS_EconomicAllocationService service = new ALT_CLS_EconomicAllocationService();
      Test.startTest();
      ALT_CLS_EconomicAllocationService.EconomicAllocationException failure = expectFailure(
        service,
        proposal(
          'BANK',
          fact.Id,
          'op-b1',
          new Map<Id, Decimal>{
            owner.Id => -10,
            partner.Id => 120,
            unauthorized.Id => 5
          }
        )
      );
      Test.stopTest();
      Assert.areEqual('INVALID_SHARES', failure.code);
      String reasons = String.join(failure.reasons, ',');
      Assert.isTrue(
        reasons.contains('NON_POSITIVE_SHARE:' + owner.Id),
        reasons
      );
      Assert.isTrue(
        reasons.contains('NON_POSITIVE_SHARE:' + partner.Id),
        reasons
      );
      Assert.isTrue(
        reasons.contains('UNAUTHORIZED_ACCOUNT:' + unauthorized.Id),
        reasons
      );
      Assert.isTrue(reasons.contains('TOTAL_EXCEEDS_100'), reasons);
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM AXF_OBJ_EconomicAllocationSet__c]
      );
      Assert.areEqual(0, [SELECT COUNT() FROM AXF_OBJ_EconomicAllocation__c]);
      Assert.areEqual(
        'INVALID_INPUT',
        expectFailure(
            service,
            proposal(
              'OTHER',
              fact.Id,
              'op-b2',
              new Map<Id, Decimal>{ owner.Id => 100 }
            )
          )
          .code
      );
    }
  }

  @IsTest
  static void guardsBlockDirectWritesAndDeletes() {
    System.runAs(gestor()) {
      Account owner = holder('Titular C', 'AXF_Person');
      AXF_OBJ_BankAccountTransaction__c fact = bankFact(owner, 'c');
      ALT_CLS_EconomicAllocationService service = new ALT_CLS_EconomicAllocationService();
      ALT_CLS_EconomicAllocationService.SetView draft = service.propose(
        proposal(
          'BANK',
          fact.Id,
          'op-c1',
          new Map<Id, Decimal>{ owner.Id => 100 }
        )
      );
      Test.startTest();
      Assert.isFalse(
        Database.insert(
            new AXF_OBJ_EconomicAllocationSet__c(
              AXF_EAS_LKP_BankTransaction__c = fact.Id,
              AXF_EAS_LKP_HolderAccount__c = owner.Id,
              AXF_EAS_TXT_FactIdentity__c = 'x',
              AXF_EAS_NUM_Revision__c = 9,
              AXF_EAS_EXI_SetKey__c = 'forged',
              AXF_EAS_NUM_FactMagnitude__c = 1,
              AXF_EAS_TXT_CurrencyIsoCode__c = 'BRL'
            ),
            false
          )
          .isSuccess(),
        'Set so nasce pelo servico.'
      );
      Assert.isFalse(
        Database.update(
            new AXF_OBJ_EconomicAllocation__c(
              Id = draft.shares[0].allocationId,
              AXF_EA_NUM_Percent__c = 50
            ),
            false
          )
          .isSuccess(),
        'Parcela so muda pelo servico.'
      );
      Assert.isFalse(
        Database.delete(
            new AXF_OBJ_EconomicAllocation__c(
              Id = draft.shares[0].allocationId
            ),
            false
          )
          .isSuccess(),
        'Parcela nao e excluida.'
      );
      Assert.isFalse(
        Database.delete(
            new AXF_OBJ_EconomicAllocationSet__c(Id = draft.setId),
            false
          )
          .isSuccess(),
        'Set nao e excluido.'
      );
      service.confirm(draft.setId, draft.version, 'op-c2');
      Assert.isFalse(
        Database.update(
            new AXF_OBJ_EconomicAllocationSet__c(
              Id = draft.setId,
              AXF_EAS_PKL_State__c = 'DRAFT'
            ),
            false
          )
          .isSuccess(),
        'CONFIRMED nao volta a DRAFT.'
      );
      Test.stopTest();
      try {
        service.confirm(draft.setId, draft.version + 1, 'op-c3');
        Assert.fail('Confirmado nao e confirmado de novo com outra operacao.');
      } catch (ALT_CLS_EconomicAllocationService.EconomicAllocationException expected) {
        Assert.areEqual('NOT_DRAFT', expected.code);
      }
    }
  }

  @IsTest
  static void unauthorizedUsersAreDeniedAndControllerSanitizes() {
    Account owner;
    AXF_OBJ_BankAccountTransaction__c fact;
    System.runAs(gestor()) {
      owner = holder('Titular D', 'AXF_Person');
      fact = bankFact(owner, 'd');
    }
    System.runAs(participant()) {
      try {
        new ALT_CLS_EconomicAllocationService()
          .propose(
            proposal(
              'BANK',
              fact.Id,
              'op-d1',
              new Map<Id, Decimal>{ owner.Id => 100 }
            )
          );
        Assert.fail('Participante sem capacidade nao rateia.');
      } catch (ALT_CLS_EconomicAllocationService.EconomicAllocationException expected) {
        Assert.areEqual('FORBIDDEN', expected.code);
      }
    }
    Test.startTest();
    System.runAs(gestor()) {
      AXF_CLS_CTRL_EconomicAllocation.Context context = AXF_CLS_CTRL_EconomicAllocation.getContext(
        fact.Id
      );
      Assert.isTrue(context.canAllocate);
      Assert.areEqual('BANK', context.factKind);
      Assert.isTrue(context.sets.isEmpty());
      Assert.isFalse(context.holders.isEmpty());
      ALT_CLS_EconomicAllocationService.SetView draft = AXF_CLS_CTRL_EconomicAllocation.propose(
        JSON.serialize(
          proposal(
            'BANK',
            fact.Id,
            'op-d2',
            new Map<Id, Decimal>{ owner.Id => 100 }
          )
        )
      );
      Assert.areEqual('DRAFT', draft.state);
      Assert.areEqual(
        1,
        AXF_CLS_CTRL_EconomicAllocation.getContext(fact.Id).sets.size()
      );
      try {
        AXF_CLS_CTRL_EconomicAllocation.confirm(draft.setId, 99, 'op-d3');
        Assert.fail('Conflito');
      } catch (AuraHandledException expected) {
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
          expected.getMessage()
        );
        Assert.areEqual('CONFLICT', body.get('code'));
      }
      try {
        AXF_CLS_CTRL_EconomicAllocation.propose('{"nope":1}');
        Assert.fail('JSON invalido');
      } catch (AuraHandledException expected) {
        Assert.isTrue(expected.getMessage().contains('INVALID_INPUT'));
      }
      try {
        AXF_CLS_CTRL_EconomicAllocation.getContext(owner.Id);
        Assert.fail('Tipo nao rateavel');
      } catch (AuraHandledException expected) {
        Assert.isTrue(expected.getMessage().contains('INVALID_INPUT'));
      }
      Assert.areEqual(
        'CONFIRMED',
        AXF_CLS_CTRL_EconomicAllocation.confirm(
            draft.setId,
            draft.version,
            'op-d4'
          )
          .state
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void cardAndManualFactsRoundTripAndUnsettledCardIsRejected() {
    System.runAs(gestor()) {
      Account owner = holder('Titular Cartao', 'AXF_Person');
      Account partner = holder('Socio Cartao', 'AXF_Person');
      AXF_OBJ_CreditCardTransaction__c posted = cardFact(owner, 'e1', 'POSTED');
      AXF_OBJ_CreditCardTransaction__c pending = cardFact(
        owner,
        'e2',
        'PENDING'
      );
      AXF_OBJ_FinancialTransaction__c manual = manualFact(owner, 'e3');
      ALT_CLS_EconomicAllocationService service = new ALT_CLS_EconomicAllocationService();
      Test.startTest();
      ALT_CLS_EconomicAllocationService.SetView card = service.propose(
        proposal(
          'CARD',
          posted.Id,
          'op-e1',
          new Map<Id, Decimal>{ owner.Id => 25, partner.Id => 75 }
        )
      );
      Assert.areEqual('CARD', card.factKind);
      Assert.areEqual(120, card.factMagnitude);
      Assert.areEqual(owner.Id, card.holderAccountId);
      Decimal cardTotal = 0;
      for (ALT_CLS_EconomicAllocationService.ShareView share : card.shares) {
        cardTotal += share.magnitude;
        Assert.isTrue(String.isNotBlank(share.allocationKey));
      }
      Assert.areEqual(120, cardTotal);
      Assert.areEqual(
        'CONFIRMED',
        service.confirm(card.setId, card.version, 'op-e1c').state
      );
      ALT_CLS_EconomicAllocationService.EconomicAllocationException unsettled = expectFailure(
        service,
        proposal(
          'CARD',
          pending.Id,
          'op-e2',
          new Map<Id, Decimal>{ owner.Id => 100 }
        )
      );
      Assert.areEqual('INVALID_SHARES', unsettled.code);
      Assert.isTrue(unsettled.reasons.contains('FACT_NOT_SETTLED'));

      ALT_CLS_EconomicAllocationService.SetView manualSet = service.propose(
        proposal(
          'MANUAL',
          manual.Id,
          'op-e3',
          new Map<Id, Decimal>{ partner.Id => 100 }
        )
      );
      Assert.areEqual('MANUAL', manualSet.factKind);
      Assert.areEqual(90, manualSet.factMagnitude);
      Assert.areEqual(
        'CONFIRMED',
        service.confirm(manualSet.setId, manualSet.version, 'op-e3c').state
      );
      // A second manual occurrence of the same plan keeps its own identity.
      AXF_OBJ_FinancialTransaction__c sibling = manualFact(owner, 'e4');
      Assert.areEqual(
        'DRAFT',
        service.propose(
            proposal(
              'MANUAL',
              sibling.Id,
              'op-e4',
              new Map<Id, Decimal>{ owner.Id => 100 }
            )
          )
          .state
      );
      Assert.areEqual(
        1,
        AXF_CLS_CTRL_EconomicAllocation.getContext(posted.Id).sets.size()
      );
      Test.stopTest();
    }
  }

  @IsTest
  static void factChangesDuplicateHoldersAndActiveSetsAreRejected() {
    System.runAs(gestor()) {
      Account owner = holder('Titular Mutavel', 'AXF_Person');
      Account partner = holder('Socio Mutavel', 'AXF_Person');
      AXF_OBJ_BankAccountTransaction__c fact = bankFact(owner, 'f');
      ALT_CLS_EconomicAllocationService service = new ALT_CLS_EconomicAllocationService();
      Test.startTest();
      ALT_CLS_EconomicAllocationService.ProposeInput duplicate = proposal(
        'BANK',
        fact.Id,
        'op-f0',
        new Map<Id, Decimal>{ owner.Id => 50 }
      );
      ALT_CLS_EconomicAllocationService.ShareInput again = new ALT_CLS_EconomicAllocationService.ShareInput();
      again.accountId = owner.Id;
      again.percent = 50;
      duplicate.shares.add(again);
      ALT_CLS_EconomicAllocationService.EconomicAllocationException rejected = expectFailure(
        service,
        duplicate
      );
      Assert.areEqual('INVALID_SHARES', rejected.code);
      Assert.isTrue(
        rejected.reasons.contains('DUPLICATE_ACCOUNT:' + owner.Id),
        String.join(rejected.reasons, ',')
      );

      ALT_CLS_EconomicAllocationService.SetView draft = service.propose(
        proposal(
          'BANK',
          fact.Id,
          'op-f1',
          new Map<Id, Decimal>{ owner.Id => 40, partner.Id => 60 }
        )
      );
      fact.AXF_BAT_NUM_Magnitude__c = 301;
      update fact;
      try {
        service.confirm(draft.setId, draft.version, 'op-f1c');
        Assert.fail('Fato alterado apos a proposta nao confirma.');
      } catch (ALT_CLS_EconomicAllocationService.EconomicAllocationException expected) {
        Assert.areEqual('CONFIRMATION_REJECTED', expected.code);
        Assert.isTrue(expected.reasons.contains('FACT_CHANGED'));
      }
      Assert.areEqual('DRAFT', service.read(draft.setId).state);

      ALT_CLS_EconomicAllocationService.SetView fresh = service.propose(
        proposal(
          'BANK',
          fact.Id,
          'op-f2',
          new Map<Id, Decimal>{ owner.Id => 100 }
        )
      );
      Assert.areEqual(
        'CONFIRMED',
        service.confirm(fresh.setId, fresh.version, 'op-f2c').state
      );
      ALT_CLS_EconomicAllocationService.EconomicAllocationException active = expectFailure(
        service,
        proposal(
          'BANK',
          fact.Id,
          'op-f3',
          new Map<Id, Decimal>{ partner.Id => 100 }
        )
      );
      Assert.areEqual('ACTIVE_SET_EXISTS', active.code);
      try {
        service.confirm(draft.setId, draft.version, 'op-f1d');
        Assert.fail('Rascunho antigo nao confirma sobre conjunto ativo.');
      } catch (ALT_CLS_EconomicAllocationService.EconomicAllocationException expected) {
        Assert.areEqual('CONFIRMATION_REJECTED', expected.code);
        Assert.isTrue(expected.reasons.contains('ACTIVE_SET_EXISTS'));
      }
      Test.stopTest();
    }
  }

  @IsTest
  static void discardEndsDraftsAndReadOnlyUsersSeeSanitizedContext() {
    Account owner;
    AXF_OBJ_BankAccountTransaction__c fact;
    ALT_CLS_EconomicAllocationService.SetView draft;
    System.runAs(gestor()) {
      owner = holder('Titular Descarte', 'AXF_Person');
      fact = bankFact(owner, 'g');
      Test.startTest();
      draft = new ALT_CLS_EconomicAllocationService()
        .propose(
          proposal(
            'BANK',
            fact.Id,
            'op-g1',
            new Map<Id, Decimal>{ owner.Id => 100 }
          )
        );
      try {
        AXF_CLS_CTRL_EconomicAllocation.discard(draft.setId, 99);
        Assert.fail('Versao obsoleta');
      } catch (AuraHandledException expected) {
        Assert.isTrue(expected.getMessage().contains('CONFLICT'));
      }
      ALT_CLS_EconomicAllocationService.SetView discarded = AXF_CLS_CTRL_EconomicAllocation.discard(
        draft.setId,
        draft.version
      );
      Assert.areEqual('DISCARDED', discarded.state);
      Assert.areEqual(draft.version + 1, discarded.version);
      // Idempotent: discarding again is a no-op read.
      Assert.areEqual(
        'DISCARDED',
        AXF_CLS_CTRL_EconomicAllocation.discard(draft.setId, 0).state
      );
      try {
        new ALT_CLS_EconomicAllocationService()
          .confirm(draft.setId, discarded.version, 'op-g2');
        Assert.fail('Descartado nao confirma.');
      } catch (ALT_CLS_EconomicAllocationService.EconomicAllocationException expected) {
        Assert.areEqual('NOT_DRAFT', expected.code);
      }
      // A discarded draft no longer blocks a new proposal.
      ALT_CLS_EconomicAllocationService.SetView replacement = new ALT_CLS_EconomicAllocationService()
        .propose(
          proposal(
            'BANK',
            fact.Id,
            'op-g3',
            new Map<Id, Decimal>{ owner.Id => 100 }
          )
        );
      Assert.areEqual(
        'CONFIRMED',
        new ALT_CLS_EconomicAllocationService()
          .confirm(replacement.setId, replacement.version, 'op-g3c')
          .state
      );
      try {
        new ALT_CLS_EconomicAllocationService()
          .discard(replacement.setId, replacement.version + 1);
        Assert.fail('Confirmado nao descarta.');
      } catch (ALT_CLS_EconomicAllocationService.EconomicAllocationException expected) {
        Assert.areEqual('NOT_DRAFT', expected.code);
      }
      AXF_CLS_AuthorizedContextService.simulateSecurityFailure = true;
      try {
        AXF_CLS_CTRL_EconomicAllocation.getContext(fact.Id);
        Assert.fail('Falha de seguranca deve ser sanitizada.');
      } catch (AuraHandledException expected) {
        Assert.isTrue(expected.getMessage().contains('NOT_ACCESSIBLE'));
        Assert.isFalse(expected.getMessage().contains('test-only'));
      } finally {
        AXF_CLS_AuthorizedContextService.simulateSecurityFailure = null;
      }
      Test.stopTest();
    }
    // The participant shares the holder through an explicit share row and only reads.
    insert new AccountShare(
      AccountId = owner.Id,
      UserOrGroupId = participant().Id,
      AccountAccessLevel = 'Read',
      OpportunityAccessLevel = 'None',
      CaseAccessLevel = 'None'
    );
    System.runAs(participant()) {
      try {
        AXF_CLS_CTRL_EconomicAllocation.discard(draft.setId, 0);
        Assert.fail('Participante nao descarta.');
      } catch (AuraHandledException expected) {
        Assert.isTrue(
          expected.getMessage().contains('FORBIDDEN') ||
          expected.getMessage().contains('NOT_ACCESSIBLE'),
          expected.getMessage()
        );
      }
    }
  }

  @IsTest
  static void roundingConservesMagnitudeAndGuardFreezesConfirmedContent() {
    System.runAs(gestor()) {
      Account owner = holder('Titular Centavos', 'AXF_Person');
      Account second = holder('Socio Dois', 'AXF_Person');
      Account third = holder('Socio Tres', 'AXF_Person');
      AXF_OBJ_BankAccountTransaction__c fact = bankFact(owner, 'h', 0.07);
      ALT_CLS_EconomicAllocationService service = new ALT_CLS_EconomicAllocationService();
      Test.startTest();
      ALT_CLS_EconomicAllocationService.SetView draft = service.propose(
        proposal(
          'BANK',
          fact.Id,
          'op-h1',
          new Map<Id, Decimal>{
            owner.Id => 33.333334,
            second.Id => 33.333333,
            third.Id => 33.333333
          }
        )
      );
      Decimal total = 0;
      Decimal largest = 0;
      for (ALT_CLS_EconomicAllocationService.ShareView share : draft.shares) {
        total += share.magnitude;
        largest = share.magnitude > largest ? share.magnitude : largest;
      }
      Assert.areEqual(0.07, total, 'Parcelas conservam a magnitude original.');
      Assert.areEqual(100, draft.totalPercent);
      Assert.isTrue(largest > 0.02333333, 'Residuo vai para a maior parcela.');
      ALT_CLS_EconomicAllocationService.SetView confirmed = service.confirm(
        draft.setId,
        draft.version,
        'op-h1c'
      );
      Assert.areEqual('CONFIRMED', confirmed.state);

      AXF_OBJ_EconomicAllocation__c allocation = [
        SELECT Id, AXF_EA_LKP_Account__c, AXF_EA_NUM_Percent__c
        FROM AXF_OBJ_EconomicAllocation__c
        WHERE AXF_EA_MDR_AllocationSet__c = :confirmed.setId
        LIMIT 1
      ];
      allocation.AXF_EA_LKP_Account__c = third.Id;
      Database.SaveResult moved = Database.update(allocation, false);
      Assert.isFalse(
        moved.isSuccess(),
        'Parcela nao troca de pessoa por fora.'
      );
      Assert.isTrue(
        moved.getErrors()[0].getMessage().contains('service'),
        moved.getErrors()[0].getMessage()
      );
      AXF_OBJ_EconomicAllocationSet__c allocationSet = new AXF_OBJ_EconomicAllocationSet__c(
        Id = confirmed.setId,
        AXF_EAS_NUM_FactMagnitude__c = 1
      );
      Database.SaveResult edited = Database.update(allocationSet, false);
      Assert.isFalse(edited.isSuccess(), 'Conteudo confirmado e imutavel.');
      Database.DeleteResult removed = Database.delete(allocation, false);
      Assert.isFalse(removed.isSuccess(), 'Parcela nao e apagada.');
      Test.stopTest();
    }
  }

  private static String firstError(Database.SaveResult result) {
    Assert.isFalse(result.isSuccess(), 'Escrita direta deveria falhar.');
    return result.getErrors()[0].getMessage();
  }

  @IsTest
  static void guardRejectsIllegalContentEvenInsideTheServiceWriteWindow() {
    System.runAs(gestor()) {
      Account owner = holder('Titular Guarda', 'AXF_Person');
      Account other = holder('Outro Guarda', 'AXF_Person');
      AXF_OBJ_BankAccountTransaction__c fact = bankFact(owner, 'i');
      ALT_CLS_EconomicAllocationService service = new ALT_CLS_EconomicAllocationService();
      Test.startTest();
      ALT_CLS_EconomicAllocationService.SetView draft = service.propose(
        proposal(
          'BANK',
          fact.Id,
          'op-i1',
          new Map<Id, Decimal>{ owner.Id => 100 }
        )
      );
      AXF_OBJ_EconomicAllocation__c allocation = [
        SELECT Id, AXF_EA_MDR_AllocationSet__c
        FROM AXF_OBJ_EconomicAllocation__c
        WHERE AXF_EA_MDR_AllocationSet__c = :draft.setId
        LIMIT 1
      ];
      try {
        ALT_CLS_EconomicAllocationGuard.beginWrite();
        Assert.isTrue(ALT_CLS_EconomicAllocationGuard.isWriting());
        Assert.isTrue(
          firstError(
              Database.insert(
                new AXF_OBJ_EconomicAllocationSet__c(
                  AXF_EAS_LKP_BankTransaction__c = fact.Id,
                  AXF_EAS_LKP_HolderAccount__c = owner.Id,
                  AXF_EAS_TXT_FactIdentity__c = 'x',
                  AXF_EAS_NUM_Revision__c = 9,
                  AXF_EAS_EXI_SetKey__c = 'x-9',
                  AXF_EAS_PKL_State__c = 'CONFIRMED',
                  AXF_EAS_NUM_FactMagnitude__c = 1,
                  AXF_EAS_TXT_CurrencyIsoCode__c = 'BRL',
                  AXF_EAS_TXT_OperationKey__c = 'op-i9',
                  AXF_EAS_NUM_Version__c = 1
                ),
                false
              )
            )
            .contains('starts as DRAFT')
        );
        Assert.isTrue(
          firstError(
              Database.update(
                new AXF_OBJ_EconomicAllocationSet__c(
                  Id = draft.setId,
                  AXF_EAS_LKP_HolderAccount__c = other.Id
                ),
                false
              )
            )
            .contains('identity is immutable')
        );
        Assert.isTrue(
          firstError(
              Database.update(
                new AXF_OBJ_EconomicAllocationSet__c(
                  Id = draft.setId,
                  AXF_EAS_PKL_State__c = 'SUPERSEDED'
                ),
                false
              )
            )
            .contains('state transition')
        );
        Assert.isTrue(
          firstError(
              Database.update(
                new AXF_OBJ_EconomicAllocation__c(
                  Id = allocation.Id,
                  AXF_EA_LKP_Account__c = other.Id
                ),
                false
              )
            )
            .contains('share identity is immutable')
        );
        Assert.isTrue(
          firstError(
              Database.update(
                new AXF_OBJ_EconomicAllocation__c(
                  Id = allocation.Id,
                  AXF_EA_NUM_Percent__c = 0
                ),
                false
              )
            )
            .contains('must be positive')
        );
      } finally {
        ALT_CLS_EconomicAllocationGuard.endWrite();
      }
      Assert.isFalse(ALT_CLS_EconomicAllocationGuard.isWriting());
      ALT_CLS_EconomicAllocationService.SetView confirmed = service.confirm(
        draft.setId,
        draft.version,
        'op-i1c'
      );
      try {
        ALT_CLS_EconomicAllocationGuard.beginWrite();
        Assert.isTrue(
          firstError(
              Database.update(
                new AXF_OBJ_EconomicAllocation__c(
                  Id = allocation.Id,
                  AXF_EA_NUM_Percent__c = 50
                ),
                false
              )
            )
            .contains('Only DRAFT sets')
        );
        Assert.isTrue(
          firstError(
              Database.update(
                new AXF_OBJ_EconomicAllocationSet__c(
                  Id = confirmed.setId,
                  AXF_EAS_TXT_OperationKey__c = 'op-i1x'
                ),
                false
              )
            )
            .contains('Confirmed economic allocation content is immutable')
        );
      } finally {
        ALT_CLS_EconomicAllocationGuard.endWrite();
      }
      Assert.isTrue(
        firstError(
            Database.update(
              new AXF_OBJ_EconomicAllocationSet__c(
                Id = confirmed.setId,
                AXF_EAS_PKL_State__c = 'REVERSED'
              ),
              false
            )
          )
          .contains('service')
      );
      Test.stopTest();
    }
  }

  // ------------------------------------------------------- AXF-127 singular projection

  private static Id storedProjection(Id setId) {
    return [
      SELECT AXF_EAS_LKP_AttributedAccount__c
      FROM AXF_OBJ_EconomicAllocationSet__c
      WHERE Id = :setId
    ]
    .AXF_EAS_LKP_AttributedAccount__c;
  }

  /** Seeds a DRAFT-only value through the content window the guard deliberately allows. */
  private static void seedProjection(Id setId, Id accountId) {
    ALT_CLS_EconomicAllocationGuard.beginWrite();
    try {
      Assert.isTrue(
        Database.update(
            new AXF_OBJ_EconomicAllocationSet__c(
              Id = setId,
              AXF_EAS_LKP_AttributedAccount__c = accountId
            ),
            false
          )
          .isSuccess(),
        'Pre-condicao: DRAFT aceita conteudo.'
      );
    } finally {
      ALT_CLS_EconomicAllocationGuard.endWrite();
    }
  }

  /** AXF-127 branch 1: an integral allocation reflects its sole person/company (G1). */
  @IsTest
  static void integralAllocationDerivesTheSolePersonOrCompanyProjection() {
    System.runAs(gestor()) {
      Account person = holder('Titular Projecao', 'AXF_Person');
      Account company = holder('Empresa Projecao', 'AXF_Business');
      AXF_OBJ_BankAccountTransaction__c personFact = bankFact(person, 'p');
      AXF_OBJ_BankAccountTransaction__c companyFact = bankFact(company, 'q');
      ALT_CLS_EconomicAllocationService service = new ALT_CLS_EconomicAllocationService();
      Test.startTest();
      ALT_CLS_EconomicAllocationService.SetView personDraft = service.propose(
        proposal(
          'BANK',
          personFact.Id,
          'op-p1',
          new Map<Id, Decimal>{ person.Id => 100 }
        )
      );
      Assert.isNull(
        storedProjection(personDraft.setId),
        'A projecao nasce na confirmacao, nao na proposta.'
      );
      service.confirm(personDraft.setId, personDraft.version, 'op-p1c');
      Assert.areEqual(
        person.Id,
        storedProjection(personDraft.setId),
        'Atribuicao integral: a projecao reflete a unica pessoa titular.'
      );
      ALT_CLS_EconomicAllocationService.SetView companyDraft = service.propose(
        proposal(
          'BANK',
          companyFact.Id,
          'op-q1',
          new Map<Id, Decimal>{ company.Id => 100 }
        )
      );
      service.confirm(companyDraft.setId, companyDraft.version, 'op-q1c');
      Assert.areEqual(
        company.Id,
        storedProjection(companyDraft.setId),
        'G1: empresa titular tambem e sujeito singular valido.'
      );
      Assert.areEqual(
        0,
        [
          SELECT COUNT()
          FROM AXF_OBJ_EconomicAllocationSet__Share
          WHERE RowCause != 'Owner'
        ],
        'A projecao nao concede acesso.'
      );
      Assert.areEqual(
        0,
        [
          SELECT COUNT()
          FROM AccountShare
          WHERE AccountId IN (:person.Id, :company.Id) AND RowCause != 'Owner'
        ],
        'A projecao nao compartilha a pessoa nem a empresa projetada.'
      );
      Test.stopTest();
    }
  }

  /** AXF-127 branch 2: rateio leaves the singular projection empty and non-authoritative. */
  @IsTest
  static void apportionmentKeepsTheSingularProjectionEmptyAndNonAuthoritative() {
    System.runAs(gestor()) {
      Account person = holder('Titular Rateio', 'AXF_Person');
      Account company = holder('Empresa Rateio', 'AXF_Business');
      AXF_OBJ_BankAccountTransaction__c fact = bankFact(person, 'r');
      ALT_CLS_EconomicAllocationService service = new ALT_CLS_EconomicAllocationService();
      Test.startTest();
      ALT_CLS_EconomicAllocationService.SetView draft = service.propose(
        proposal(
          'BANK',
          fact.Id,
          'op-r1',
          new Map<Id, Decimal>{ person.Id => 60, company.Id => 40 }
        )
      );
      service.confirm(draft.setId, draft.version, 'op-r1c');
      Assert.isNull(
        storedProjection(draft.setId),
        'Rateio: projecao vazia, sem eleger titular principal nem primeiro participante.'
      );
      ALT_CLS_EconomicAllocationGuard.beginWrite();
      try {
        Assert.isTrue(
          firstError(
              Database.update(
                new AXF_OBJ_EconomicAllocationSet__c(
                  Id = draft.setId,
                  AXF_EAS_LKP_AttributedAccount__c = person.Id
                ),
                false
              )
            )
            .contains('Confirmed economic allocation content is immutable'),
          'A projecao nao vira autoridade depois de confirmada.'
        );
      } finally {
        ALT_CLS_EconomicAllocationGuard.endWrite();
      }
      Assert.isNull(
        storedProjection(draft.setId),
        'Rateio confirmado continua sem projecao singular.'
      );
      Test.stopTest();
    }
  }

  /**
   * AXF-127 totality: the confirmation assignment is unconditional, so an apportioned
   * confirmation clears a pre-existing value instead of leaving it stale. The service never
   * writes the projection before confirmation, so the precondition is seeded through the DRAFT
   * content window the guard deliberately allows.
   */
  @IsTest
  static void apportionedConfirmationClearsAPreexistingProjection() {
    System.runAs(gestor()) {
      Account person = holder('Titular Stale', 'AXF_Person');
      Account company = holder('Empresa Stale', 'AXF_Business');
      AXF_OBJ_BankAccountTransaction__c fact = bankFact(person, 's');
      ALT_CLS_EconomicAllocationService service = new ALT_CLS_EconomicAllocationService();
      Test.startTest();
      ALT_CLS_EconomicAllocationService.SetView draft = service.propose(
        proposal(
          'BANK',
          fact.Id,
          'op-s1',
          new Map<Id, Decimal>{ person.Id => 50, company.Id => 50 }
        )
      );
      ALT_CLS_EconomicAllocationGuard.beginWrite();
      try {
        Assert.isTrue(
          Database.update(
              new AXF_OBJ_EconomicAllocationSet__c(
                Id = draft.setId,
                AXF_EAS_LKP_AttributedAccount__c = person.Id
              ),
              false
            )
            .isSuccess(),
          'Pre-condicao: DRAFT aceita conteudo.'
        );
      } finally {
        ALT_CLS_EconomicAllocationGuard.endWrite();
      }
      Assert.areEqual(
        person.Id,
        storedProjection(draft.setId),
        'Pre-condicao: valor previo gravado.'
      );
      service.confirm(draft.setId, draft.version, 'op-s1c');
      Assert.isNull(
        storedProjection(draft.setId),
        'Confirmacao em rateio limpa o valor previo da projecao.'
      );
      Test.stopTest();
    }
  }

  /**
   * AXF-127/G2: the projection is the *allocated* subject, not the fact's own account. The fact
   * belongs to one person/company and the 100% parcel goes to a different one, so an
   * implementation that projected the fact's account fails here.
   *
   * AXF-127/G3: the "grants no access" claims are scoped to this set. The set's own Owner row is
   * asserted first as the positive control — sharing really is materialised for this set — so the
   * zero counts that follow are not vacuous: any grant the projection could add (an extra set
   * share row, or a share of the allocated person) fails them. Two stronger fixtures were
   * measured and rejected: a non-owner proposer cannot read the set it created nor write its own
   * access share (`insufficient access rights on cross-reference id`, which
   * `grantProposerAccess()` needs and swallows), and allocating to an account owned by a third
   * user pulls an org-configured sharing `Rule` row into the AccountShare count.
   */
  @IsTest
  static void integralAllocationProjectsTheAllocatedSubjectAndGrantsNoAccess() {
    System.runAs(gestor()) {
      Account holderAccount = holder('Titular Nao Alocado', 'AXF_Business');
      Account allocated = holder('Pessoa Alocada', 'AXF_Person');
      AXF_OBJ_BankAccountTransaction__c fact = bankFact(holderAccount, 'u');
      ALT_CLS_EconomicAllocationService service = new ALT_CLS_EconomicAllocationService();
      Test.startTest();
      ALT_CLS_EconomicAllocationService.SetView draft = service.propose(
        proposal(
          'BANK',
          fact.Id,
          'op-u1',
          new Map<Id, Decimal>{ allocated.Id => 100 }
        )
      );
      Assert.areEqual(
        'CONFIRMED',
        service.confirm(draft.setId, draft.version, 'op-u1c').state
      );
      Assert.areEqual(
        allocated.Id,
        storedProjection(draft.setId),
        'G2: a projecao reflete a pessoa alocada.'
      );
      Assert.isTrue(
        storedProjection(draft.setId) != holderAccount.Id,
        'G2: a projecao nao e a conta do proprio fato.'
      );
      Assert.areEqual(
        gestor().Id,
        [
          SELECT OwnerId
          FROM AXF_OBJ_EconomicAllocationSet__c
          WHERE Id = :draft.setId
        ]
        .OwnerId,
        'G3: o conjunto segue o titular do fato, nao a projecao.'
      );
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM AXF_OBJ_EconomicAllocationSet__Share
          WHERE ParentId = :draft.setId AND RowCause = 'Owner'
        ],
        'G3 (controle positivo): o compartilhamento existe para este conjunto.'
      );
      Assert.areEqual(
        0,
        [
          SELECT COUNT()
          FROM AXF_OBJ_EconomicAllocationSet__Share
          WHERE ParentId = :draft.setId AND RowCause != 'Owner'
        ],
        'G3: a projecao nao concede acesso ao conjunto.'
      );
      Assert.areEqual(
        0,
        [
          SELECT COUNT()
          FROM AccountShare
          WHERE AccountId = :allocated.Id AND RowCause != 'Owner'
        ],
        'G3: a projecao nao compartilha a pessoa alocada.'
      );
      Test.stopTest();
    }
  }

  /**
   * AXF-127/G1: the projection does not outlive the set's authority. A discard ends the set and
   * the value must go with it. The service only writes the projection at confirmation, so the
   * precondition (a DRAFT already carrying a value) is seeded through the DRAFT content window the
   * guard deliberately allows — the field is readable and editable by FLS, which is exactly why
   * the clear cannot be left to the caller.
   */
  @IsTest
  static void discardClearsTheSingularProjectionOfTheEndedSet() {
    System.runAs(gestor()) {
      Account person = holder('Titular Descarte Projecao', 'AXF_Person');
      AXF_OBJ_BankAccountTransaction__c fact = bankFact(person, 't');
      ALT_CLS_EconomicAllocationService service = new ALT_CLS_EconomicAllocationService();
      Test.startTest();
      ALT_CLS_EconomicAllocationService.SetView draft = service.propose(
        proposal(
          'BANK',
          fact.Id,
          'op-t1',
          new Map<Id, Decimal>{ person.Id => 100 }
        )
      );
      seedProjection(draft.setId, person.Id);
      Assert.areEqual(
        person.Id,
        storedProjection(draft.setId),
        'Pre-condicao: valor previo gravado no rascunho.'
      );
      ALT_CLS_EconomicAllocationService.SetView discarded = service.discard(
        draft.setId,
        draft.version
      );
      Assert.areEqual('DISCARDED', discarded.state);
      Assert.isNull(
        storedProjection(draft.setId),
        'G1: o conjunto sem autoridade nao mantem projecao singular.'
      );
      // The idempotent discard is a plain read and must not resurrect the value either.
      Assert.areEqual('DISCARDED', service.discard(draft.setId, 0).state);
      Assert.isNull(
        storedProjection(draft.setId),
        'G1: descarte idempotente nao ressuscita a projecao.'
      );
      Test.stopTest();
    }
  }

  // ------------------------------------------------------- AXF-128 reversal

  private static ALT_CLS_EconomicAllocationService.ReverseInput reversal(
    Id setId,
    Decimal version,
    String key
  ) {
    ALT_CLS_EconomicAllocationService.ReverseInput input = new ALT_CLS_EconomicAllocationService.ReverseInput();
    input.setId = setId;
    input.expectedVersion = version;
    input.operationKey = key;
    return input;
  }

  private static ALT_CLS_EconomicAllocationService.EconomicAllocationException expectReverseFailure(
    ALT_CLS_EconomicAllocationService service,
    ALT_CLS_EconomicAllocationService.ReverseInput input
  ) {
    try {
      service.reverse(input);
      Assert.fail('Reversao deveria falhar.');
    } catch (ALT_CLS_EconomicAllocationService.EconomicAllocationException expected) {
      return expected;
    }
    return null;
  }

  private static AXF_OBJ_EconomicAllocationSet__c storedSet(Id setId) {
    return [
      SELECT
        AXF_EAS_PKL_State__c,
        AXF_EAS_NUM_Version__c,
        AXF_EAS_TXT_FactIdentity__c,
        AXF_EAS_EXI_SetKey__c,
        AXF_EAS_NUM_Revision__c,
        AXF_EAS_NUM_FactMagnitude__c,
        AXF_EAS_TXT_CurrencyIsoCode__c,
        AXF_EAS_LKP_HolderAccount__c,
        AXF_EAS_LKP_BankTransaction__c,
        AXF_EAS_TXT_OperationKey__c,
        AXF_EAS_TXT_ConfirmOperationKey__c,
        AXF_EAS_EXI_ActiveToken__c,
        AXF_EAS_LKP_AttributedAccount__c
      FROM AXF_OBJ_EconomicAllocationSet__c
      WHERE Id = :setId
    ];
  }

  /** Every stored parcel of a set, as a comparable string: proves none of them was edited. */
  private static String storedParcels(Id setId) {
    List<String> rows = new List<String>();
    for (AXF_OBJ_EconomicAllocation__c row : [
      SELECT
        Id,
        AXF_EA_LKP_Account__c,
        AXF_EA_NUM_Percent__c,
        AXF_EA_NUM_Magnitude__c,
        AXF_EA_TXT_CurrencyIsoCode__c,
        AXF_EA_EXI_AllocationKey__c,
        AXF_EA_PKL_RedactionPolicy__c
      FROM AXF_OBJ_EconomicAllocation__c
      WHERE AXF_EA_MDR_AllocationSet__c = :setId
      ORDER BY AXF_EA_EXI_AllocationKey__c
    ]) {
      rows.add(
        String.join(
          new List<String>{
            String.valueOf(row.Id),
            String.valueOf(row.AXF_EA_LKP_Account__c),
            String.valueOf(row.AXF_EA_NUM_Percent__c),
            String.valueOf(row.AXF_EA_NUM_Magnitude__c),
            row.AXF_EA_TXT_CurrencyIsoCode__c,
            row.AXF_EA_EXI_AllocationKey__c,
            row.AXF_EA_PKL_RedactionPolicy__c
          },
          '|'
        )
      );
    }
    return String.join(rows, ';');
  }

  private static Integer setsOfFact(String factIdentity) {
    return [
      SELECT COUNT()
      FROM AXF_OBJ_EconomicAllocationSet__c
      WHERE AXF_EAS_TXT_FactIdentity__c = :factIdentity
    ];
  }

  /**
   * AXF-128 / AC-2: a reversal creates compensating records and never edits the confirmation.
   * The compensation is a new set of the next revision of the same fact whose single 100% parcel
   * gives the fact back to its holder, so the fact keeps exactly one attribution authority and
   * one active token. Every content field and every parcel of the confirmed set survives byte for
   * byte; only state, optimistic version and the two fields that must not outlive the authority
   * move. An equivalent replay returns the durable compensation instead of appending a second.
   */
  @IsTest
  static void reversalCompensatesWithoutEditingTheConfirmationAndReplaysSafely() {
    System.runAs(gestor()) {
      Account owner = holder('Titular Reversao', 'AXF_Person');
      Account partner = holder('Socio Reversao', 'AXF_Person');
      AXF_OBJ_BankAccountTransaction__c fact = bankFact(owner, 'v');
      ALT_CLS_EconomicAllocationService service = new ALT_CLS_EconomicAllocationService();
      Test.startTest();
      ALT_CLS_EconomicAllocationService.SetView draft = service.propose(
        proposal(
          'BANK',
          fact.Id,
          'op-v1',
          new Map<Id, Decimal>{ owner.Id => 60, partner.Id => 40 }
        )
      );
      ALT_CLS_EconomicAllocationService.SetView confirmed = service.confirm(
        draft.setId,
        draft.version,
        'op-v1c'
      );
      AXF_OBJ_EconomicAllocationSet__c before = storedSet(confirmed.setId);
      String beforeParcels = storedParcels(confirmed.setId);
      Assert.areEqual('CONFIRMED', before.AXF_EAS_PKL_State__c);
      Assert.isNotNull(
        before.AXF_EAS_EXI_ActiveToken__c,
        'Pre-condicao: a confirmacao detem o token ativo.'
      );
      Assert.isNull(
        before.AXF_EAS_LKP_AttributedAccount__c,
        'Pre-condicao: rateio nao projeta atribuicao singular.'
      );
      ALT_CLS_EconomicAllocationService.SetView compensation = service.reverse(
        reversal(confirmed.setId, confirmed.version, 'op-v2')
      );
      Test.stopTest();
      Assert.areEqual(
        'CONFIRMED',
        compensation.state,
        'o conjunto compensatorio e a autoridade vigente.'
      );
      Assert.areEqual(
        before.AXF_EAS_NUM_Revision__c + 1,
        compensation.revision,
        'revisao seguinte do mesmo fato.'
      );
      Assert.areEqual(100, compensation.totalPercent.setScale(2));
      Assert.areEqual(1, compensation.shares.size());
      Assert.areEqual(
        owner.Id,
        compensation.shares[0].accountId,
        'a compensacao devolve o fato ao titular.'
      );
      Assert.areEqual(
        before.AXF_EAS_NUM_FactMagnitude__c,
        compensation.shares[0].magnitude,
        'a compensacao conserva o fato na moeda original.'
      );
      Assert.areEqual(
        before.AXF_EAS_TXT_CurrencyIsoCode__c,
        compensation.currencyIso
      );
      // Nothing of the confirmation was edited.
      Assert.areEqual(
        beforeParcels,
        storedParcels(confirmed.setId),
        'nenhuma parcela confirmada foi editada, criada ou removida.'
      );
      AXF_OBJ_EconomicAllocationSet__c ended = storedSet(confirmed.setId);
      Assert.areEqual('REVERSED', ended.AXF_EAS_PKL_State__c);
      Assert.areEqual(
        before.AXF_EAS_TXT_FactIdentity__c,
        ended.AXF_EAS_TXT_FactIdentity__c
      );
      Assert.areEqual(
        before.AXF_EAS_EXI_SetKey__c,
        ended.AXF_EAS_EXI_SetKey__c
      );
      Assert.areEqual(
        before.AXF_EAS_NUM_FactMagnitude__c,
        ended.AXF_EAS_NUM_FactMagnitude__c
      );
      Assert.areEqual(
        before.AXF_EAS_LKP_HolderAccount__c,
        ended.AXF_EAS_LKP_HolderAccount__c
      );
      Assert.areEqual(
        before.AXF_EAS_LKP_BankTransaction__c,
        ended.AXF_EAS_LKP_BankTransaction__c
      );
      Assert.areEqual(
        'op-v1',
        ended.AXF_EAS_TXT_OperationKey__c,
        'chave da proposta intacta.'
      );
      Assert.areEqual(
        'op-v1c',
        ended.AXF_EAS_TXT_ConfirmOperationKey__c,
        'chave da confirmacao intacta.'
      );
      Assert.areEqual(
        before.AXF_EAS_NUM_Version__c + 1,
        ended.AXF_EAS_NUM_Version__c,
        'versao otimista incrementada uma vez.'
      );
      // Only the transition bookkeeping moved with the state.
      Assert.isNull(
        ended.AXF_EAS_EXI_ActiveToken__c,
        'o token ativo e liberado para a compensacao.'
      );
      AXF_OBJ_EconomicAllocationSet__c live = storedSet(compensation.setId);
      Assert.areEqual(
        before.AXF_EAS_EXI_ActiveToken__c,
        live.AXF_EAS_EXI_ActiveToken__c,
        'um unico token ativo por fato (G6).'
      );
      Assert.areEqual(
        owner.Id,
        live.AXF_EAS_LKP_AttributedAccount__c,
        'a projecao singular segue o titular apos a reversao.'
      );
      Assert.isFalse(
        before.AXF_EAS_EXI_SetKey__c == live.AXF_EAS_EXI_SetKey__c,
        'o conjunto compensatorio tem identidade propria.'
      );
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM AXF_OBJ_EconomicAllocationSet__c
          WHERE
            AXF_EAS_PKL_State__c = 'CONFIRMED'
            AND AXF_EAS_TXT_FactIdentity__c = :before.AXF_EAS_TXT_FactIdentity__c
        ],
        'uma unica autoridade vigente por fato.'
      );
      // Equivalent replay: the same command returns the durable compensation.
      ALT_CLS_EconomicAllocationService.SetView replay = service.reverse(
        reversal(confirmed.setId, confirmed.version, 'op-v2')
      );
      Assert.areEqual(
        compensation.setId,
        replay.setId,
        'replay equivalente devolve o resultado duravel.'
      );
      Assert.areEqual(
        2,
        setsOfFact(before.AXF_EAS_TXT_FactIdentity__c),
        'replay nao duplica o efeito.'
      );
    }
  }

  /**
   * AXF-128 / AC-2 negative paths: only a confirmation is reversible, a divergent payload never
   * produces a second compensation, a stale version leaves the original untouched, and the ended
   * set stays frozen against every later write.
   */
  @IsTest
  static void reversalRejectsDraftStaleVersionAndDivergentReplays() {
    Account owner;
    Account partner;
    AXF_OBJ_BankAccountTransaction__c draftFact;
    AXF_OBJ_BankAccountTransaction__c fact;
    AXF_OBJ_BankAccountTransaction__c liveFact;
    Id draftSetId;
    Id reversedSetId;
    Id compensationSetId;
    Id liveSetId;
    String identity;
    Decimal draftVersion;
    Decimal reversedVersion;
    System.runAs(gestor()) {
      owner = holder('Titular Recusa', 'AXF_Person');
      partner = holder('Socio Recusa', 'AXF_Person');
      draftFact = bankFact(owner, 'w');
      fact = bankFact(owner, 'x');
      liveFact = bankFact(owner, 'y');
      ALT_CLS_EconomicAllocationService service = new ALT_CLS_EconomicAllocationService();
      Test.startTest();
      ALT_CLS_EconomicAllocationService.SetView draft = service.propose(
        proposal(
          'BANK',
          draftFact.Id,
          'op-w1',
          new Map<Id, Decimal>{ owner.Id => 100 }
        )
      );
      draftSetId = draft.setId;
      draftVersion = draft.version;
      ALT_CLS_EconomicAllocationService.SetView open = service.propose(
        proposal(
          'BANK',
          fact.Id,
          'op-x1',
          new Map<Id, Decimal>{ owner.Id => 70, partner.Id => 30 }
        )
      );
      ALT_CLS_EconomicAllocationService.SetView confirmed = service.confirm(
        open.setId,
        open.version,
        'op-x1c'
      );
      reversedSetId = confirmed.setId;
      reversedVersion = confirmed.version;
      identity = storedSet(confirmed.setId).AXF_EAS_TXT_FactIdentity__c;
      compensationSetId = service.reverse(
          reversal(confirmed.setId, confirmed.version, 'op-x2')
        )
        .setId;
      ALT_CLS_EconomicAllocationService.SetView liveOpen = service.propose(
        proposal(
          'BANK',
          liveFact.Id,
          'op-y1',
          new Map<Id, Decimal>{ owner.Id => 100 }
        )
      );
      liveSetId = service.confirm(liveOpen.setId, liveOpen.version, 'op-y1c')
        .setId;
      // Same command, different version: divergent payload, nothing appended.
      Assert.areEqual(
        'CONFLICT',
        expectReverseFailure(
            service,
            reversal(reversedSetId, reversedVersion - 1, 'op-x2')
          )
          .code
      );
      // Another command against an already reversed target: refused, never a second compensation.
      Assert.areEqual(
        'CONFLICT',
        expectReverseFailure(
            service,
            reversal(reversedSetId, reversedVersion, 'op-x3')
          )
          .code
      );
      // Stale version on a live confirmation: the original is preserved.
      Assert.areEqual(
        'CONFLICT',
        expectReverseFailure(service, reversal(liveSetId, 99, 'op-y2')).code
      );
      Assert.areEqual('CONFIRMED', service.read(liveSetId).state);
      Assert.areEqual(
        2,
        setsOfFact(identity),
        'nenhum replay divergente criou um conjunto a mais.'
      );
      Test.stopTest();
    }
    System.runAs(gestor()) {
      // A DRAFT is discarded, never reversed.
      ALT_CLS_EconomicAllocationService.EconomicAllocationException notConfirmed = expectReverseFailure(
        new ALT_CLS_EconomicAllocationService(),
        reversal(draftSetId, draftVersion, 'op-w2')
      );
      Assert.areEqual('NOT_CONFIRMED', notConfirmed.code);
    }
    System.runAs(participant()) {
      // Capability first: the participant is refused before any set is even read.
      ALT_CLS_EconomicAllocationService.EconomicAllocationException forbidden = expectReverseFailure(
        new ALT_CLS_EconomicAllocationService(),
        reversal(liveSetId, 1, 'op-z1')
      );
      Assert.areEqual('FORBIDDEN', forbidden.code);
    }
    System.runAs(gestor()) {
      // The ended set is frozen: not even the service write window edits its content.
      ALT_CLS_EconomicAllocationGuard.beginWrite();
      try {
        Assert.isTrue(
          firstError(
              Database.update(
                new AXF_OBJ_EconomicAllocationSet__c(
                  Id = reversedSetId,
                  AXF_EAS_TXT_OperationKey__c = 'op-x9'
                ),
                false
              )
            )
            .contains('Confirmed economic allocation content is immutable'),
          'Conteudo de conjunto encerrado permanece imutavel.'
        );
        Assert.isTrue(
          firstError(
              Database.update(
                new AXF_OBJ_EconomicAllocationSet__c(
                  Id = reversedSetId,
                  AXF_EAS_PKL_State__c = 'CONFIRMED'
                ),
                false
              )
            )
            .contains('state transition'),
          'REVERSED nao volta a CONFIRMED.'
        );
      } finally {
        ALT_CLS_EconomicAllocationGuard.endWrite();
      }
      Assert.areEqual(
        'REVERSED',
        storedSet(reversedSetId).AXF_EAS_PKL_State__c,
        'nada das tentativas persistiu.'
      );
      Assert.areEqual(
        compensationSetId,
        storedSet(compensationSetId).Id,
        'a compensacao permanece a autoridade.'
      );
    }
  }

  /**
   * AXF-128 / AC-2 (F1): the replay is recognised by the ratified operation key plus the fact
   * identity, never by an inferred revision. `nextRevision()` takes the highest revision of the
   * fact in *any* state, so an intervening DRAFT — a revision the confirmation never used — pushes
   * the compensation past `reversed.Revision + 1`. The same command must still return its own
   * durable compensation instead of conflicting against itself.
   */
  @IsTest
  static void reversalReplayIsIdentifiedByTheOperationKeyNotByAnInferredRevision() {
    System.runAs(gestor()) {
      Account owner = holder('Titular Replay', 'AXF_Person');
      Account partner = holder('Socio Replay', 'AXF_Person');
      AXF_OBJ_BankAccountTransaction__c fact = bankFact(owner, 'n');
      ALT_CLS_EconomicAllocationService service = new ALT_CLS_EconomicAllocationService();
      Test.startTest();
      ALT_CLS_EconomicAllocationService.SetView first = service.propose(
        proposal(
          'BANK',
          fact.Id,
          'op-n1',
          new Map<Id, Decimal>{ owner.Id => 100 }
        )
      );
      // A higher revision of the same fact stays a DRAFT through the whole reversal.
      ALT_CLS_EconomicAllocationService.SetView intervening = service.propose(
        proposal(
          'BANK',
          fact.Id,
          'op-n2',
          new Map<Id, Decimal>{ partner.Id => 100 }
        )
      );
      Assert.areEqual(2, intervening.revision, 'revisao interveniente.');
      ALT_CLS_EconomicAllocationService.SetView confirmed = service.confirm(
        first.setId,
        first.version,
        'op-n1c'
      );
      String identity = storedSet(confirmed.setId).AXF_EAS_TXT_FactIdentity__c;
      ALT_CLS_EconomicAllocationService.SetView compensation = service.reverse(
        reversal(confirmed.setId, confirmed.version, 'op-n3')
      );
      Test.stopTest();
      Assert.areEqual(
        3,
        compensation.revision,
        'a compensacao respeita a revisao interveniente.'
      );
      ALT_CLS_EconomicAllocationService.SetView replay = service.reverse(
        reversal(confirmed.setId, confirmed.version, 'op-n3')
      );
      Assert.areEqual(
        compensation.setId,
        replay.setId,
        'replay equivalente devolve o proprio efeito duravel.'
      );
      Assert.areEqual('CONFIRMED', replay.state);
      Assert.areEqual(
        3,
        setsOfFact(identity),
        'replay nao anexou um segundo conjunto.'
      );
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM AXF_OBJ_EconomicAllocationSet__c
          WHERE
            AXF_EAS_PKL_State__c = 'CONFIRMED'
            AND AXF_EAS_TXT_FactIdentity__c = :identity
        ],
        'uma unica autoridade vigente por fato.'
      );
    }
  }

  /** The G6 identity of a reversal effect, exactly as the service frames it. */
  private static String framedReverseKey(String operationKey) {
    return AXF_CLS_IdentityFraming.key(
      new List<Object>{
        ALT_CLS_EconomicAllocationService.OP_REVERSE,
        operationKey
      }
    );
  }

  /**
   * AXF-128 / AC-2 (F2): `AXF_EAS_TXT_OperationKey__c` is not unique, so a framed key already
   * stored anywhere is refused *before* anything is written. A key spent on one fact can neither
   * append a second compensating set for another target nor be re-spent on the compensation
   * itself.
   */
  @IsTest
  static void reverseRefusesAKeyAlreadySpentOnAnotherTarget() {
    System.runAs(gestor()) {
      Account owner = holder('Titular Chave', 'AXF_Person');
      Account partner = holder('Socio Chave', 'AXF_Person');
      AXF_OBJ_BankAccountTransaction__c first = bankFact(owner, 'o1');
      AXF_OBJ_BankAccountTransaction__c second = bankFact(owner, 'o2');
      ALT_CLS_EconomicAllocationService service = new ALT_CLS_EconomicAllocationService();
      Test.startTest();
      ALT_CLS_EconomicAllocationService.SetView firstDraft = service.propose(
        proposal(
          'BANK',
          first.Id,
          'op-o1',
          new Map<Id, Decimal>{ owner.Id => 100 }
        )
      );
      ALT_CLS_EconomicAllocationService.SetView firstConfirmed = service.confirm(
        firstDraft.setId,
        firstDraft.version,
        'op-o1c'
      );
      ALT_CLS_EconomicAllocationService.SetView compensation = service.reverse(
        reversal(firstConfirmed.setId, firstConfirmed.version, 'op-o1r')
      );
      ALT_CLS_EconomicAllocationService.SetView secondDraft = service.propose(
        proposal(
          'BANK',
          second.Id,
          'op-o2',
          new Map<Id, Decimal>{ partner.Id => 100 }
        )
      );
      ALT_CLS_EconomicAllocationService.SetView secondConfirmed = service.confirm(
        secondDraft.setId,
        secondDraft.version,
        'op-o2c'
      );
      String secondIdentity = storedSet(secondConfirmed.setId)
        .AXF_EAS_TXT_FactIdentity__c;
      // The very same operation key, a different still-confirmed target: refused, not replayed.
      Assert.areEqual(
        'CONFLICT',
        expectReverseFailure(
            service,
            reversal(secondConfirmed.setId, secondConfirmed.version, 'op-o1r')
          )
          .code,
        'chave ja gasta nao compensa outro alvo.'
      );
      Assert.areEqual(
        'CONFIRMED',
        storedSet(secondConfirmed.setId).AXF_EAS_PKL_State__c,
        'o alvo recusado permanece confirmado.'
      );
      Assert.isNotNull(
        storedSet(secondConfirmed.setId).AXF_EAS_EXI_ActiveToken__c,
        'o alvo recusado mantem o proprio token.'
      );
      Assert.areEqual(
        1,
        setsOfFact(secondIdentity),
        'nenhum compensatorio foi anexado ao outro fato.'
      );
      // And the compensation is itself a confirmation: the key is spent once, never twice.
      Assert.areEqual(
        'CONFLICT',
        expectReverseFailure(
            service,
            reversal(compensation.setId, compensation.version, 'op-o1r')
          )
          .code,
        'a chave nao se gasta duas vezes.'
      );
      Test.stopTest();
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM AXF_OBJ_EconomicAllocationSet__c
          WHERE AXF_EAS_TXT_OperationKey__c = :framedReverseKey('op-o1r')
        ],
        'uma unica linha carrega a chave enquadrada.'
      );
    }
  }

  /**
   * AXF-128 / AC-2 (F2): the key lookup must never trust the key alone. A foreign set can carry
   * the very same framed key — the field is not unique — and the equivalent replay must still
   * answer with its own durable compensation instead of conflicting on the wrong row.
   */
  @IsTest
  static void reversalReplayIgnoresAForeignRowThatReusesTheSameKey() {
    System.runAs(gestor()) {
      Account owner = holder('Titular Colisao', 'AXF_Person');
      Account partner = holder('Socio Colisao', 'AXF_Person');
      AXF_OBJ_BankAccountTransaction__c fact = bankFact(owner, 'p1');
      AXF_OBJ_BankAccountTransaction__c other = bankFact(partner, 'p2');
      ALT_CLS_EconomicAllocationService service = new ALT_CLS_EconomicAllocationService();
      Test.startTest();
      ALT_CLS_EconomicAllocationService.SetView draft = service.propose(
        proposal(
          'BANK',
          fact.Id,
          'op-p1',
          new Map<Id, Decimal>{ owner.Id => 100 }
        )
      );
      ALT_CLS_EconomicAllocationService.SetView confirmed = service.confirm(
        draft.setId,
        draft.version,
        'op-p1c'
      );
      ALT_CLS_EconomicAllocationService.SetView compensation = service.reverse(
        reversal(confirmed.setId, confirmed.version, 'op-p1r')
      );
      // A draft of another fact reuses the same framed key through the service write window.
      ALT_CLS_EconomicAllocationGuard.beginWrite();
      try {
        Assert.isTrue(
          Database.insert(
              new AXF_OBJ_EconomicAllocationSet__c(
                AXF_EAS_LKP_BankTransaction__c = other.Id,
                AXF_EAS_LKP_HolderAccount__c = partner.Id,
                AXF_EAS_TXT_FactIdentity__c = 'colisao-' + other.Id,
                AXF_EAS_NUM_Revision__c = 1,
                AXF_EAS_PKL_State__c = 'DRAFT',
                AXF_EAS_EXI_SetKey__c = 'colisao-' + other.Id,
                AXF_EAS_NUM_FactMagnitude__c = 300,
                AXF_EAS_TXT_CurrencyIsoCode__c = 'BRL',
                AXF_EAS_TXT_OperationKey__c = framedReverseKey('op-p1r'),
                AXF_EAS_NUM_Version__c = 1
              ),
              AccessLevel.USER_MODE
            )
            .isSuccess(),
          'Pre-condicao: a chave nao e unica no objeto.'
        );
      } finally {
        ALT_CLS_EconomicAllocationGuard.endWrite();
      }
      Test.stopTest();
      ALT_CLS_EconomicAllocationService.SetView replay = service.reverse(
        reversal(confirmed.setId, confirmed.version, 'op-p1r')
      );
      Assert.areEqual(
        compensation.setId,
        replay.setId,
        'a identidade do fato filtra a linha estranha.'
      );
    }
  }

  /**
   * AXF-128 / AC-2 (F4): the reversal gate is what stops a compensation from being written over
   * an altered fact or over a holder the service can no longer authorize. Both negatives are
   * asserted through `REVERSAL_REJECTED`, so deleting either check turns this test red — and the
   * altered fact is altered *only* in its identity, so the identity comparison is what is pinned.
   */
  @IsTest
  static void reversalRejectsAnAlteredFactAndAnUnauthorizedHolder() {
    System.runAs(gestor()) {
      Account owner = holder('Titular Alterado', 'AXF_Person');
      AXF_OBJ_BankAccountTransaction__c fact = bankFact(owner, 'q1');
      ALT_CLS_EconomicAllocationService service = new ALT_CLS_EconomicAllocationService();
      Test.startTest();
      ALT_CLS_EconomicAllocationService.SetView draft = service.propose(
        proposal(
          'BANK',
          fact.Id,
          'op-q1',
          new Map<Id, Decimal>{ owner.Id => 100 }
        )
      );
      ALT_CLS_EconomicAllocationService.SetView confirmed = service.confirm(
        draft.setId,
        draft.version,
        'op-q1c'
      );
      String identity = storedSet(confirmed.setId).AXF_EAS_TXT_FactIdentity__c;
      // Only the source key — that is, the fact's identity — moves; magnitude, currency and
      // holder stay exactly as confirmed.
      fact.AXF_BAT_EXI_SourceKey__c = 'bat-movido-' + System.now().getTime();
      update fact;
      ALT_CLS_EconomicAllocationService.EconomicAllocationException altered = expectReverseFailure(
        service,
        reversal(confirmed.setId, confirmed.version, 'op-q1r')
      );
      Assert.areEqual('REVERSAL_REJECTED', altered.code);
      Assert.isTrue(
        altered.reasons.contains('FACT_CHANGED'),
        String.join(altered.reasons, ',')
      );
      Test.stopTest();
      Assert.areEqual(
        'CONFIRMED',
        storedSet(confirmed.setId).AXF_EAS_PKL_State__c,
        'fato alterado nao e compensado.'
      );
      Assert.isNotNull(
        storedSet(confirmed.setId).AXF_EAS_EXI_ActiveToken__c,
        'a autoridade original segue vigente.'
      );
      Assert.areEqual(
        1,
        setsOfFact(identity),
        'nenhum conjunto compensatorio foi anexado.'
      );
      Assert.areEqual(300, fact.AXF_BAT_NUM_Magnitude__c, 'nada mais mudou.');
    }

    // (2) The holder is no longer an authorized person/company: the compensating parcel goes back
    // to it, so the reversal must be refused. The fact itself is untouched, so only the
    // authorization gate can produce this rejection.
    Account transferred = null;
    Id setId = null;
    Decimal version = null;
    String manualIdentity = null;
    System.runAs(gestor()) {
      transferred = holder('Titular Nao Autorizado', 'AXF_Person');
      AXF_OBJ_FinancialTransaction__c manual = manualFact(transferred, 'q2');
      ALT_CLS_EconomicAllocationService service = new ALT_CLS_EconomicAllocationService();
      ALT_CLS_EconomicAllocationService.SetView draft = service.propose(
        proposal(
          'MANUAL',
          manual.Id,
          'op-q2',
          new Map<Id, Decimal>{ transferred.Id => 100 }
        )
      );
      ALT_CLS_EconomicAllocationService.SetView confirmed = service.confirm(
        draft.setId,
        draft.version,
        'op-q2c'
      );
      setId = confirmed.setId;
      version = confirmed.version;
      manualIdentity = storedSet(setId).AXF_EAS_TXT_FactIdentity__c;
    }
    // The account changes owner, outside the gestor session: with Account OWD private and no
    // role-based rule for its new owner, the gestor can no longer read it.
    update new Account(Id = transferred.Id, OwnerId = participant().Id);
    System.runAs(gestor()) {
      ALT_CLS_EconomicAllocationService.EconomicAllocationException unauthorized = expectReverseFailure(
        new ALT_CLS_EconomicAllocationService(),
        reversal(setId, version, 'op-q2r')
      );
      Assert.areEqual('REVERSAL_REJECTED', unauthorized.code);
      Assert.isTrue(
        unauthorized.reasons.contains('UNAUTHORIZED_ACCOUNT:' + transferred.Id),
        String.join(unauthorized.reasons, ',')
      );
    }
    Assert.areEqual(
      'CONFIRMED',
      storedSet(setId).AXF_EAS_PKL_State__c,
      'titular nao autorizado nao e compensado.'
    );
    Assert.isNotNull(storedSet(setId).AXF_EAS_EXI_ActiveToken__c);
    Assert.areEqual(
      1,
      setsOfFact(manualIdentity),
      'nenhum conjunto compensatorio foi anexado.'
    );
  }

  /**
   * AXF-128 / AC-2 + AXF-127 (F5): ending an integral confirmation clears the derived singular
   * projection of the ended set in the same DML. Every other reversal fixture reverses an
   * apportioned set — whose projection was already null — so this is the only one where the
   * clearing is observable: here the projection holds the *allocated* person, which is not the
   * fact's holder.
   */
  @IsTest
  static void reversalClearsTheSingularProjectionOfAnIntegralConfirmation() {
    System.runAs(gestor()) {
      Account holderAccount = holder(
        'Titular Projecao Reversa',
        'AXF_Business'
      );
      Account allocated = holder('Pessoa Alocada Reversa', 'AXF_Person');
      AXF_OBJ_BankAccountTransaction__c fact = bankFact(holderAccount, 's1');
      ALT_CLS_EconomicAllocationService service = new ALT_CLS_EconomicAllocationService();
      Test.startTest();
      ALT_CLS_EconomicAllocationService.SetView draft = service.propose(
        proposal(
          'BANK',
          fact.Id,
          'op-s1',
          new Map<Id, Decimal>{ allocated.Id => 100 }
        )
      );
      ALT_CLS_EconomicAllocationService.SetView confirmed = service.confirm(
        draft.setId,
        draft.version,
        'op-s1c'
      );
      Assert.areEqual(
        allocated.Id,
        storedProjection(confirmed.setId),
        'Pre-condicao: atribuicao integral projeta a pessoa alocada.'
      );
      Assert.isTrue(
        allocated.Id != holderAccount.Id,
        'Pre-condicao: a projecao nao e a conta do proprio fato.'
      );
      ALT_CLS_EconomicAllocationService.SetView compensation = service.reverse(
        reversal(confirmed.setId, confirmed.version, 'op-s1r')
      );
      Test.stopTest();
      Assert.isNull(
        storedProjection(confirmed.setId),
        'AXF-127: o conjunto encerrado nao mantem projecao singular.'
      );
      Assert.areEqual(
        holderAccount.Id,
        storedProjection(compensation.setId),
        'a compensacao devolve o fato ao titular e projeta o titular.'
      );
      Assert.isNotNull(
        storedProjection(compensation.setId),
        'a autoridade vigente segue projetada.'
      );
    }
  }

  /**
   * AXF-128 / AC-2 (F3): the release of the active token and of the projection is derived from the
   * actual transition. Re-asserting an already-ended state frees nothing, so no foreign token can
   * be planted on an ended set; and a confirmation can neither end without a live successor of the
   * same fact nor hand the token to any value other than null.
   */
  @IsTest
  static void guardDerivesTheReleaseFromTheTransitionAndRequiresACompensation() {
    System.runAs(gestor()) {
      Account owner = holder('Titular Transicao', 'AXF_Person');
      Account partner = holder('Socio Transicao', 'AXF_Person');
      AXF_OBJ_BankAccountTransaction__c fact = bankFact(owner, 'r1');
      AXF_OBJ_BankAccountTransaction__c foreignFact = bankFact(owner, 'r2');
      AXF_OBJ_BankAccountTransaction__c aloneFact = bankFact(partner, 'r3');
      ALT_CLS_EconomicAllocationService service = new ALT_CLS_EconomicAllocationService();
      Test.startTest();
      ALT_CLS_EconomicAllocationService.SetView draft = service.propose(
        proposal(
          'BANK',
          fact.Id,
          'op-r1',
          new Map<Id, Decimal>{ owner.Id => 100 }
        )
      );
      ALT_CLS_EconomicAllocationService.SetView confirmed = service.confirm(
        draft.setId,
        draft.version,
        'op-r1c'
      );
      service.reverse(reversal(confirmed.setId, confirmed.version, 'op-r1r'));
      String foreignToken = AXF_CLS_IdentityFraming.key(
        new List<Object>{ foreignFact.AXF_BAT_EXI_SourceKey__c, 'ACTIVE' }
      );
      // REVERSED -> REVERSED is not a transition: neither bookkeeping field is released.
      ALT_CLS_EconomicAllocationGuard.beginWrite();
      try {
        Assert.isTrue(
          firstError(
              Database.update(
                new AXF_OBJ_EconomicAllocationSet__c(
                  Id = confirmed.setId,
                  AXF_EAS_PKL_State__c = 'REVERSED',
                  AXF_EAS_EXI_ActiveToken__c = foreignToken
                ),
                false
              )
            )
            .contains('Confirmed economic allocation content is immutable'),
          'reenunciar REVERSED nao libera o token.'
        );
        Assert.isTrue(
          firstError(
              Database.update(
                new AXF_OBJ_EconomicAllocationSet__c(
                  Id = confirmed.setId,
                  AXF_EAS_PKL_State__c = 'REVERSED',
                  AXF_EAS_LKP_AttributedAccount__c = partner.Id
                ),
                false
              )
            )
            .contains('Confirmed economic allocation content is immutable'),
          'reenunciar REVERSED nao libera a projecao.'
        );
      } finally {
        ALT_CLS_EconomicAllocationGuard.endWrite();
      }
      // A confirmation ends only into an existing live successor of the same fact.
      ALT_CLS_EconomicAllocationService.SetView alone = service.propose(
        proposal(
          'BANK',
          aloneFact.Id,
          'op-r4',
          new Map<Id, Decimal>{ partner.Id => 100 }
        )
      );
      ALT_CLS_EconomicAllocationService.SetView aloneConfirmed = service.confirm(
        alone.setId,
        alone.version,
        'op-r4c'
      );
      ALT_CLS_EconomicAllocationGuard.beginWrite();
      try {
        Assert.isTrue(
          firstError(
              Database.update(
                new AXF_OBJ_EconomicAllocationSet__c(
                  Id = aloneConfirmed.setId,
                  AXF_EAS_PKL_State__c = 'REVERSED',
                  AXF_EAS_EXI_ActiveToken__c = null,
                  AXF_EAS_NUM_Version__c = aloneConfirmed.version + 1
                ),
                false
              )
            )
            .contains('live successor'),
          'autoridade nao termina sem o conjunto compensatorio.'
        );
      } finally {
        ALT_CLS_EconomicAllocationGuard.endWrite();
      }
      // The token is released, never moved to another value. The fixture carries a live successor
      // of the same fact, so the successor rule cannot be what refuses this write.
      AXF_OBJ_BankAccountTransaction__c handFact = bankFact(owner, 'r4');
      ALT_CLS_EconomicAllocationService.SetView handing = service.propose(
        proposal(
          'BANK',
          handFact.Id,
          'op-r6',
          new Map<Id, Decimal>{ owner.Id => 100 }
        )
      );
      ALT_CLS_EconomicAllocationService.SetView successorDraft = service.propose(
        proposal(
          'BANK',
          handFact.Id,
          'op-r7',
          new Map<Id, Decimal>{ partner.Id => 100 }
        )
      );
      ALT_CLS_EconomicAllocationService.SetView handingConfirmed = service.confirm(
        handing.setId,
        handing.version,
        'op-r6c'
      );
      Assert.isTrue(
        successorDraft.revision > handingConfirmed.revision,
        'Pre-condicao: existe sucessor vivo em revisao maior.'
      );
      ALT_CLS_EconomicAllocationGuard.beginWrite();
      try {
        Database.SaveResult planted = Database.update(
          new AXF_OBJ_EconomicAllocationSet__c(
            Id = handingConfirmed.setId,
            AXF_EAS_PKL_State__c = 'REVERSED',
            AXF_EAS_EXI_ActiveToken__c = foreignToken,
            AXF_EAS_NUM_Version__c = handingConfirmed.version + 1
          ),
          false
        );
        Assert.isTrue(
          firstError(planted).contains('releases the active token'),
          'token estranho nao e plantado: ' + firstError(planted)
        );
      } finally {
        ALT_CLS_EconomicAllocationGuard.endWrite();
      }
      Test.stopTest();
      Assert.areEqual(
        'CONFIRMED',
        storedSet(aloneConfirmed.setId).AXF_EAS_PKL_State__c,
        'nada das tentativas persistiu.'
      );
      Assert.areEqual(
        'CONFIRMED',
        storedSet(handingConfirmed.setId).AXF_EAS_PKL_State__c,
        'o conjunto com sucessor tambem segue confirmado.'
      );
      String aliveToken = storedSet(aloneConfirmed.setId)
        .AXF_EAS_EXI_ActiveToken__c;
      Assert.isNotNull(aliveToken, 'a autoridade original segue vigente.');
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM AXF_OBJ_EconomicAllocationSet__c
          WHERE AXF_EAS_EXI_ActiveToken__c = :aliveToken
        ],
        'a autoridade original segue vigente e unica.'
      );
      Assert.areEqual(
        0,
        [
          SELECT COUNT()
          FROM AXF_OBJ_EconomicAllocationSet__c
          WHERE AXF_EAS_EXI_ActiveToken__c = :foreignToken
        ],
        'nenhum token estranho foi plantado.'
      );
      Assert.isNull(
        storedSet(confirmed.setId).AXF_EAS_LKP_AttributedAccount__c,
        'a projecao do conjunto encerrado nao foi reescrita.'
      );
      // The fact that would have been blocked by a planted token still proposes normally.
      Assert.areEqual(
        'DRAFT',
        service.propose(
            proposal(
              'BANK',
              foreignFact.Id,
              'op-r5',
              new Map<Id, Decimal>{ owner.Id => 100 }
            )
          )
          .state,
        'nenhum fato estranho ficou bloqueado.'
      );
    }
  }
}
