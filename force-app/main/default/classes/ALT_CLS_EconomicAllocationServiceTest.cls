/**
 * @description AXF-126: rateio economico — propriedade separada da atribuicao (nada inferido na
 * ingestao), proposta com parcelas positivas/moeda original/pessoas autorizadas/identidade
 * canonica, confirmacao com 100% exato, rejeicao atomica (soma != 100, negativo, nao autorizado,
 * versao obsoleta), sem share implicito, idempotencia por operacao, guards e erros sanitizados.
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
    System.runAs(gestor()) {
      Account owner = holder('Titular B', 'AXF_Person');
      Account partner = holder('Empresa B', 'AXF_Business');
      // Explicitly pinned to a non-Axon record type: the org default record type for a bare
      // insert is not guaranteed to fall outside AXF_Person/AXF_Business.
      List<RecordType> foreign = [
        SELECT Id
        FROM RecordType
        WHERE
          SobjectType = 'Account'
          AND IsActive = TRUE
          AND DeveloperName NOT IN ('AXF_Person', 'AXF_Business')
        LIMIT 1
      ];
      Account unauthorized = new Account(Name = 'Conta comum sem tipo Axon');
      if (!foreign.isEmpty()) {
        unauthorized.RecordTypeId = foreign[0].Id;
      }
      insert unauthorized;
      AXF_OBJ_BankAccountTransaction__c fact = bankFact(owner, 'b');
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
}
