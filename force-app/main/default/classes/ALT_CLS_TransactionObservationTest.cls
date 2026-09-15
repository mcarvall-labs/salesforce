/**
 * @description AXF-109: qualificacao de evidencia importada — observacao imutavel com identidade
 * tipada, data/moeda/magnitude, elegibilidade e proveniencia de status; replay do mesmo conteudo
 * nao cria revisao; conteudo alterado cria revisao; ImportedAt sozinho nao; exclusoes
 * deterministicas; status ausente/pendente/nao reconhecido = UNKNOWN sem promocao por
 * estabelecimento; Amazon/Google genericos sem servico; contexto/fonte divergente e acesso
 * negado rejeitados; guards; enriquecimento minimo do sync Pluggy.
 */
@IsTest
private class ALT_CLS_TransactionObservationTest {
  private static User gestor() {
    return [SELECT Id FROM User WHERE Alias = 'axf109g' LIMIT 1];
  }
  private static User peer() {
    return [SELECT Id FROM User WHERE Alias = 'axf109p' LIMIT 1];
  }

  @TestSetup
  static void setup() {
    Id profileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
    .Id;
    User gestor = new User(
      Alias = 'axf109g',
      Email = 'axf109g@example.invalid',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Observation Gestor',
      LanguageLocaleKey = 'pt_BR',
      LocaleSidKey = 'pt_BR',
      TimeZoneSidKey = 'America/Sao_Paulo',
      ProfileId = profileId,
      Username = 'axf109g.' + System.now().getTime() + '@example.invalid'
    );
    User peer = gestor.clone(false, false, false, false);
    peer.Alias = 'axf109p';
    peer.LastName = 'Peer Gestor';
    peer.Username = 'axf109p.' + System.now().getTime() + '@example.invalid';
    insert new List<User>{ gestor, peer };
    List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (PermissionSet permission : [
      SELECT Id
      FROM PermissionSet
      WHERE Name IN ('AXF_PS_GestorFinanceiro', 'AXF_PS_PluggyIntegration')
    ]) {
      assignments.add(
        new PermissionSetAssignment(
          AssigneeId = gestor.Id,
          PermissionSetId = permission.Id
        )
      );
      assignments.add(
        new PermissionSetAssignment(
          AssigneeId = peer.Id,
          PermissionSetId = permission.Id
        )
      );
    }
    insert assignments;
  }

  private class Scope {
    Account holder;
    AXF_OBJ_BankAccount__c bank;
    AXF_OBJ_CreditCard__c card;
  }

  private static Scope makeScope(String key) {
    Scope scope = new Scope();
    scope.holder = new Account(
      Name = 'Holder ' + key,
      RecordTypeId = Account.SObjectType.getDescribe()
        .getRecordTypeInfosByDeveloperName()
        .get('AXF_Business')
        .getRecordTypeId()
    );
    insert scope.holder;
    scope.bank = new AXF_OBJ_BankAccount__c(
      AXF_BA_LKP_Account__c = scope.holder.Id,
      AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_BA_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BA_TXT_InstitutionName__c = 'Banco ' + key,
      AXF_BA_TXT_NumberMasked__c = '****' + key,
      AXF_BA_EXI_ManualKey__c = 'manual-' + key + '-' + System.now().getTime(),
      AXF_BA_NUM_Version__c = 0
    );
    insert scope.bank;
    scope.card = new AXF_OBJ_CreditCard__c(
      AXF_CC_LKP_Account__c = scope.holder.Id,
      AXF_CC_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_CC_TXT_CurrencyIsoCode__c = 'BRL'
    );
    insert scope.card;
    return scope;
  }

  private static AXF_OBJ_BankAccountTransaction__c bankFact(
    Scope scope,
    String key,
    String description,
    String rawStatus,
    String operation,
    String category,
    String direction
  ) {
    return new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_MDR_BankAccount__c = scope.bank.Id,
      AXF_BAT_EXI_SourceKey__c = 'bat-' + key + '-' + System.now().getTime(),
      AXF_BAT_PKL_Source__c = 'PLUGGY',
      AXF_BAT_DAT_Date__c = Date.newInstance(2026, 8, 5),
      AXF_BAT_NUM_Magnitude__c = 109.9,
      AXF_BAT_PKL_Direction__c = direction,
      AXF_BAT_PKL_Status__c = 'POSTED',
      AXF_BAT_TXT_RawSourceStatus__c = rawStatus,
      AXF_BAT_TXT_OperationType__c = operation,
      AXF_BAT_TXT_ProviderCategory__c = category,
      AXF_BAT_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BAT_TXT_Description__c = description,
      AXF_BAT_DTM_ImportedAt__c = Datetime.now(),
      AXF_BAT_NUM_Version__c = 0
    );
  }

  private static AXF_OBJ_CreditCardTransaction__c cardFact(
    Scope scope,
    String key,
    String description,
    String merchant,
    String category,
    Decimal totalInstallments
  ) {
    return new AXF_OBJ_CreditCardTransaction__c(
      AXF_CCT_MDR_CreditCard__c = scope.card.Id,
      AXF_CCT_EXI_SourceKey__c = 'cct-' + key + '-' + System.now().getTime(),
      AXF_CCT_PKL_Source__c = 'PLUGGY',
      AXF_CCT_DAT_Date__c = Date.newInstance(2026, 8, 5),
      AXF_CCT_NUM_Magnitude__c = 44.9,
      AXF_CCT_PKL_Direction__c = 'DEBIT',
      AXF_CCT_PKL_Status__c = 'POSTED',
      AXF_CCT_TXT_RawSourceStatus__c = 'POSTED',
      AXF_CCT_TXT_ProviderCategory__c = category,
      AXF_CCT_TXT_MerchantName__c = merchant,
      AXF_CCT_NUM_TotalInstallments__c = totalInstallments,
      AXF_CCT_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_CCT_TXT_Description__c = description,
      AXF_CCT_DTM_ImportedAt__c = Datetime.now(),
      AXF_CCT_NUM_Version__c = 0
    );
  }

  private static ALT_CLS_TransactionObservationService.ObserveInput input(
    Id accountId,
    List<Id> ids
  ) {
    ALT_CLS_TransactionObservationService.ObserveInput result = new ALT_CLS_TransactionObservationService.ObserveInput();
    result.accountId = accountId;
    result.factIds = ids;
    return result;
  }

  private static AXF_OBJ_TransactionObservation__c latest(Id factId) {
    return [
      SELECT
        AXF_TOB_PKL_Eligibility__c,
        AXF_TOB_PKL_ExclusionReason__c,
        AXF_TOB_PKL_StatusProvenance__c,
        AXF_TOB_PKL_ClassificationProvenance__c,
        AXF_TOB_PKL_ServiceHint__c,
        AXF_TOB_NUM_Revision__c,
        AXF_TOB_TXT_SourceIdentity__c,
        AXF_TOB_NUM_Magnitude__c,
        AXF_TOB_TXT_CurrencyIsoCode__c,
        AXF_TOB_DAT_Date__c,
        AXF_TOB_TXT_NormalizedMerchant__c
      FROM AXF_OBJ_TransactionObservation__c
      WHERE
        AXF_TOB_LKP_BankTransaction__c = :factId
        OR AXF_TOB_LKP_CardTransaction__c = :factId
      ORDER BY AXF_TOB_NUM_Revision__c DESC
      LIMIT 1
    ];
  }

  @IsTest
  static void settledServiceDebitIsObservedOnceAndRevisedOnlyWhenContentChanges() {
    System.runAs(gestor()) {
      Scope scope = makeScope('a');
      AXF_OBJ_BankAccountTransaction__c fact = bankFact(
        scope,
        'a1',
        'NETFLIX.COM  ASSINATURA',
        'POSTED',
        'OUTROS',
        'Entertainment > Streaming subscription',
        'DEBIT'
      );
      insert fact;
      ALT_CLS_TransactionObservationService service = new ALT_CLS_TransactionObservationService();
      Test.startTest();
      ALT_CLS_TransactionObservationService.ObserveResult first = service.observe(
        input(scope.holder.Id, new List<Id>{ fact.Id })
      );
      ALT_CLS_TransactionObservationService.ObserveResult replay = service.observe(
        input(scope.holder.Id, new List<Id>{ fact.Id })
      );
      // Only ImportedAt changes: no revision.
      fact.AXF_BAT_DTM_ImportedAt__c = Datetime.now().addMinutes(5);
      update fact;
      ALT_CLS_TransactionObservationService.ObserveResult reimported = service.observe(
        input(scope.holder.Id, new List<Id>{ fact.Id })
      );
      // Relevant content changes: a new immutable revision.
      fact.AXF_BAT_NUM_Magnitude__c = 119.9;
      update fact;
      ALT_CLS_TransactionObservationService.ObserveResult changed = service.observe(
        input(scope.holder.Id, new List<Id>{ fact.Id })
      );
      Test.stopTest();
      Assert.areEqual(1, first.created);
      Assert.areEqual(1, first.byEligibility.get('ELIGIBLE'));
      Assert.areEqual(0, replay.created);
      Assert.areEqual(1, replay.unchanged);
      Assert.areEqual(
        0,
        reimported.created,
        'ImportedAt sozinho nao cria revisao.'
      );
      Assert.areEqual(1, changed.created);
      AXF_OBJ_TransactionObservation__c observation = latest(fact.Id);
      Assert.areEqual(2, observation.AXF_TOB_NUM_Revision__c);
      Assert.areEqual(119.9, observation.AXF_TOB_NUM_Magnitude__c);
      Assert.areEqual('BRL', observation.AXF_TOB_TXT_CurrencyIsoCode__c);
      Assert.areEqual(
        Date.newInstance(2026, 8, 5),
        observation.AXF_TOB_DAT_Date__c
      );
      Assert.areEqual(
        'BANK:' + fact.AXF_BAT_EXI_SourceKey__c,
        observation.AXF_TOB_TXT_SourceIdentity__c
      );
      Assert.areEqual('ELIGIBLE', observation.AXF_TOB_PKL_Eligibility__c);
      Assert.areEqual(
        'SOURCE_POSTED',
        observation.AXF_TOB_PKL_StatusProvenance__c
      );
      Assert.areEqual(
        'SERVICE_CANDIDATE',
        observation.AXF_TOB_PKL_ServiceHint__c
      );
      Assert.areEqual(
        'PROVIDER_CATEGORY',
        observation.AXF_TOB_PKL_ClassificationProvenance__c
      );
      Assert.areEqual(
        2,
        [
          SELECT COUNT()
          FROM AXF_OBJ_TransactionObservation__c
          WHERE AXF_TOB_LKP_BankTransaction__c = :fact.Id
        ],
        'Uma revisao por conteudo distinto.'
      );
      Assert.isFalse(
        Database.update(
            new AXF_OBJ_TransactionObservation__c(
              Id = observation.Id,
              AXF_TOB_NUM_Magnitude__c = 1
            ),
            false
          )
          .isSuccess(),
        'Observacao e imutavel.'
      );
      Assert.isFalse(
        Database.delete(
            new AXF_OBJ_TransactionObservation__c(Id = observation.Id),
            false
          )
          .isSuccess(),
        'Observacao nao e excluida.'
      );
    }
  }

  @IsTest
  static void exclusionsUnknownStatusAndGenericMerchantsAreDeterministic() {
    System.runAs(gestor()) {
      Scope scope = makeScope('b');
      List<SObject> facts = new List<SObject>{
        bankFact(
          scope,
          'transfer',
          'PIX ENVIADO JOAO',
          'POSTED',
          'PIX',
          null,
          'DEBIT'
        ),
        bankFact(
          scope,
          'invoice',
          'PAGAMENTO FATURA CARTAO',
          'POSTED',
          'OUTROS',
          null,
          'DEBIT'
        ),
        bankFact(
          scope,
          'utility',
          'CIA ELETRICA',
          'POSTED',
          'BOLETO',
          'Utilities > Electricity',
          'DEBIT'
        ),
        bankFact(
          scope,
          'insurance',
          'SEGURADORA X',
          'POSTED',
          'OUTROS',
          'Insurance',
          'DEBIT'
        ),
        bankFact(
          scope,
          'reversal',
          'ESTORNO COMPRA',
          'POSTED',
          'OUTROS',
          null,
          'DEBIT'
        ),
        bankFact(
          scope,
          'credit',
          'SALARIO',
          'POSTED',
          'OUTROS',
          null,
          'CREDIT'
        ),
        bankFact(
          scope,
          'missing',
          'SPOTIFY',
          null,
          'OUTROS',
          'Streaming subscription',
          'DEBIT'
        ),
        bankFact(
          scope,
          'weird',
          'SPOTIFY',
          'SETTLED?',
          'OUTROS',
          'Streaming subscription',
          'DEBIT'
        ),
        bankFact(
          scope,
          'pending',
          'SPOTIFY',
          'PENDING',
          'OUTROS',
          'Streaming subscription',
          'DEBIT'
        ),
        bankFact(
          scope,
          'plain',
          'MEILYM SERVICOS',
          'POSTED',
          'OUTROS',
          null,
          'DEBIT'
        ),
        cardFact(scope, 'installment', 'LOJA 3/10', 'Loja', null, 10),
        cardFact(scope, 'amazon', 'AMAZON MARKETPLACE', 'Amazon', null, null),
        cardFact(
          scope,
          'prime',
          'AMAZON PRIME',
          'Amazon',
          'Subscriptions',
          null
        ),
        cardFact(scope, 'other', 'CHATGPT SUBSCRIPTION', 'OpenAI', null, null)
      };
      insert facts;
      List<Id> ids = new List<Id>();
      for (SObject fact : facts) {
        ids.add(fact.Id);
      }
      Test.startTest();
      ALT_CLS_TransactionObservationService.ObserveResult result = new ALT_CLS_TransactionObservationService()
        .observe(input(scope.holder.Id, ids));
      Test.stopTest();
      Assert.areEqual(14, result.created);
      Map<String, AXF_OBJ_TransactionObservation__c> byKey = new Map<String, AXF_OBJ_TransactionObservation__c>();
      for (Integer i = 0; i < facts.size(); i++) {
        byKey.put(
          (String) facts[i]
            .get(
              facts[i] instanceof AXF_OBJ_BankAccountTransaction__c
                ? 'AXF_BAT_EXI_SourceKey__c'
                : 'AXF_CCT_EXI_SourceKey__c'
            ),
          latest(facts[i].Id)
        );
      }
      Map<String, List<String>> expected = new Map<String, List<String>>{
        'transfer' => new List<String>{ 'EXCLUDED', 'TRANSFER' },
        'invoice' => new List<String>{ 'EXCLUDED', 'INVOICE_PAYMENT' },
        'utility' => new List<String>{ 'EXCLUDED', 'UTILITY' },
        'insurance' => new List<String>{ 'EXCLUDED', 'INSURANCE' },
        'reversal' => new List<String>{ 'EXCLUDED', 'REVERSAL' },
        'credit' => new List<String>{ 'EXCLUDED', 'CREDIT' },
        'missing' => new List<String>{ 'UNKNOWN', 'NONE' },
        'weird' => new List<String>{ 'UNKNOWN', 'NONE' },
        'pending' => new List<String>{ 'UNKNOWN', 'NONE' },
        'plain' => new List<String>{ 'ELIGIBLE', 'NONE' },
        'installment' => new List<String>{ 'EXCLUDED', 'INSTALLMENT' },
        'amazon' => new List<String>{ 'ELIGIBLE', 'NONE' },
        'prime' => new List<String>{ 'ELIGIBLE', 'NONE' },
        'other' => new List<String>{ 'ELIGIBLE', 'NONE' }
      };
      for (String key : expected.keySet()) {
        AXF_OBJ_TransactionObservation__c observation;
        for (String stored : byKey.keySet()) {
          if (
            stored.startsWith('bat-' + key + '-') ||
            stored.startsWith('cct-' + key + '-')
          ) {
            observation = byKey.get(stored);
          }
        }
        Assert.isNotNull(observation, key);
        Assert.areEqual(
          expected.get(key)[0],
          observation.AXF_TOB_PKL_Eligibility__c,
          key
        );
        Assert.areEqual(
          expected.get(key)[1],
          observation.AXF_TOB_PKL_ExclusionReason__c,
          key
        );
        if (key == 'missing') {
          Assert.areEqual(
            'STATUS_MISSING',
            observation.AXF_TOB_PKL_StatusProvenance__c
          );
          Assert.areEqual(
            'SERVICE_CANDIDATE',
            observation.AXF_TOB_PKL_ServiceHint__c,
            'Indicio retido, mas nao promove.'
          );
        }
        if (key == 'weird') {
          Assert.areEqual(
            'STATUS_UNRECOGNIZED',
            observation.AXF_TOB_PKL_StatusProvenance__c
          );
        }
        if (key == 'pending') {
          Assert.areEqual(
            'SOURCE_PENDING',
            observation.AXF_TOB_PKL_StatusProvenance__c
          );
        }
        if (key == 'plain') {
          Assert.areEqual(
            'NONE',
            observation.AXF_TOB_PKL_ServiceHint__c,
            'Descricao sozinha nao afirma servico.'
          );
        }
        if (key == 'amazon') {
          Assert.areEqual(
            'NONE',
            observation.AXF_TOB_PKL_ServiceHint__c,
            'Amazon generico nao e servico.'
          );
        }
        if (key == 'prime') {
          Assert.areEqual(
            'SERVICE_CANDIDATE',
            observation.AXF_TOB_PKL_ServiceHint__c
          );
          Assert.areEqual(
            'PROVIDER_CATEGORY',
            observation.AXF_TOB_PKL_ClassificationProvenance__c
          );
        }
        if (key == 'other') {
          Assert.areEqual(
            'SERVICE_CANDIDATE',
            observation.AXF_TOB_PKL_ServiceHint__c,
            'Servico fora da lista de exemplos com evidencia retida.'
          );
          Assert.areEqual(
            'MERCHANT_IDENTITY',
            observation.AXF_TOB_PKL_ClassificationProvenance__c
          );
        }
      }
      Assert.areEqual(7, result.byEligibility.get('EXCLUDED'));
      Assert.areEqual(3, result.byEligibility.get('UNKNOWN'));
      Assert.areEqual(4, result.byEligibility.get('ELIGIBLE'));
    }
  }

  @IsTest
  static void contextMismatchUnauthorizedAndUnsupportedFactsAreRejected() {
    Scope mine;
    Scope other;
    AXF_OBJ_BankAccountTransaction__c foreign;
    System.runAs(gestor()) {
      mine = makeScope('c');
      other = makeScope('d');
      foreign = bankFact(
        other,
        'd1',
        'NETFLIX',
        'POSTED',
        'OUTROS',
        null,
        'DEBIT'
      );
      insert foreign;
    }
    AXF_OBJ_BankAccountTransaction__c peerFact;
    System.runAs(peer()) {
      Scope peerScope = makeScope('e');
      peerFact = bankFact(
        peerScope,
        'e1',
        'NETFLIX',
        'POSTED',
        'OUTROS',
        null,
        'DEBIT'
      );
      insert peerFact;
    }
    System.runAs(gestor()) {
      ALT_CLS_TransactionObservationService service = new ALT_CLS_TransactionObservationService();
      Test.startTest();
      for (Integer i = 0; i < 3; i++) {
        try {
          if (i == 0) {
            service.observe(input(mine.holder.Id, new List<Id>{ foreign.Id }));
          } else if (i == 1) {
            service.observe(input(mine.holder.Id, new List<Id>{ peerFact.Id }));
          } else {
            service.observe(
              input(mine.holder.Id, new List<Id>{ mine.holder.Id })
            );
          }
          Assert.fail('Rejeicao esperada: ' + i);
        } catch (ALT_CLS_TransactionObservationService.ObservationException expected) {
          Assert.areEqual(
            i == 0 ? 'CONTEXT_MISMATCH' : 'NOT_ACCESSIBLE',
            expected.code,
            'caso ' + i
          );
        }
      }
      try {
        service.observe(input(null, null));
        Assert.fail('Entrada ausente.');
      } catch (ALT_CLS_TransactionObservationService.ObservationException expected) {
        Assert.areEqual('INVALID_INPUT', expected.code);
      }
      Test.stopTest();
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM AXF_OBJ_TransactionObservation__c],
        'Nada parcial.'
      );
      Assert.isFalse(
        Database.insert(
            new AXF_OBJ_TransactionObservation__c(
              AXF_TOB_LKP_BankTransaction__c = foreign.Id,
              AXF_TOB_LKP_Account__c = other.holder.Id,
              AXF_TOB_TXT_SourceIdentity__c = 'x',
              AXF_TOB_NUM_Revision__c = 1,
              AXF_TOB_EXI_ObservationKey__c = 'forged',
              AXF_TOB_TXT_ContentFingerprint__c = 'f',
              AXF_TOB_DAT_Date__c = Date.today(),
              AXF_TOB_TXT_CurrencyIsoCode__c = 'BRL',
              AXF_TOB_NUM_Magnitude__c = 1,
              AXF_TOB_PKL_Direction__c = 'DEBIT',
              AXF_TOB_TXT_NormalizationVersion__c = 'x',
              AXF_TOB_PKL_Eligibility__c = 'ELIGIBLE',
              AXF_TOB_PKL_ExclusionReason__c = 'NONE',
              AXF_TOB_PKL_StatusProvenance__c = 'SOURCE_POSTED',
              AXF_TOB_PKL_ClassificationProvenance__c = 'NONE',
              AXF_TOB_PKL_ServiceHint__c = 'NONE',
              AXF_TOB_TXT_ClassificationVersion__c = 'x',
              AXF_TOB_DT_ObservedAt__c = Datetime.now()
            ),
            false
          )
          .isSuccess(),
        'Observacao so nasce pelo servico.'
      );
    }
  }
}
