/**
 * @description AXF-122: totais consolidados só com registros autorizados; contribuição mantém
 * pessoa/empresa, moeda original, data efetiva e fonte; pessoa não autorizada não é carregada
 * nem confirmada; acesso parcial (sem controle total) -> UNKNOWN/DEGRADED sem total enganoso; FLS ausente -> BLOCKED;
 * rateio confirmado (AXF-5) segue a atribuição; sem capacidade -> FORBIDDEN.
 */
@IsTest
private class ALT_CLS_ConsolidationServiceTest {
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
        'axf122g',
        'axf122p',
        'axf122n',
        'axf122b'
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
      WHERE Name IN ('AXF_PS_GestorFinanceiro', 'AXF_PS_Participante')
    ]) {
      permissionSets.put(permission.Name, permission.Id);
    }
    // Capability only, no object access: exercises the BLOCKED field-access path.
    PermissionSet bare = new PermissionSet(
      Name = 'AXF122TestCapabilityOnly',
      Label = 'AXF-122 capability only'
    );
    insert bare;
    insert new SetupEntityAccess(
      ParentId = bare.Id,
      SetupEntityId = [
        SELECT Id
        FROM CustomPermission
        WHERE DeveloperName = 'AXF_CanConsolidate'
        LIMIT 1
      ]
      .Id
    );
    List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    assignments.add(
      assignment(users[0].Id, permissionSets.get('AXF_PS_GestorFinanceiro'))
    );
    assignments.add(
      assignment(users[1].Id, permissionSets.get('AXF_PS_GestorFinanceiro'))
    );
    assignments.add(
      assignment(users[2].Id, permissionSets.get('AXF_PS_Participante'))
    );
    assignments.add(assignment(users[3].Id, bare.Id));
    insert assignments;
  }

  private static PermissionSetAssignment assignment(
    Id userId,
    Id permissionSetId
  ) {
    return new PermissionSetAssignment(
      AssigneeId = userId,
      PermissionSetId = permissionSetId
    );
  }

  private static Account holder(String name, Boolean person) {
    Account result = new Account(
      RecordTypeId = Account.SObjectType.getDescribe()
        .getRecordTypeInfosByDeveloperName()
        .get(person ? 'AXF_Person' : 'AXF_Business')
        .getRecordTypeId()
    );
    if (person) {
      result.LastName = name;
    } else {
      result.Name = name;
    }
    insert result;
    return result;
  }

  private static AXF_OBJ_BankAccount__c bank(Id holderId, String key) {
    AXF_OBJ_BankAccount__c result = new AXF_OBJ_BankAccount__c(
      AXF_BA_LKP_Account__c = holderId,
      AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_BA_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BA_TXT_InstitutionName__c = 'Banco ' + key,
      AXF_BA_TXT_NumberMasked__c = '****' + key,
      AXF_BA_EXI_ManualKey__c = 'manual-' + key + '-' + System.now().getTime(),
      AXF_BA_NUM_Version__c = 0
    );
    insert result;
    return result;
  }

  private static AXF_OBJ_CreditCard__c card(Id holderId, String key) {
    AXF_OBJ_CreditCard__c result = new AXF_OBJ_CreditCard__c(
      AXF_CC_LKP_Account__c = holderId,
      AXF_CC_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_CC_TXT_CurrencyIsoCode__c = 'USD',
      AXF_CC_TXT_InstitutionName__c = 'Cartao ' + key,
      AXF_CC_TXT_LastFourMasked__c = '0' + key,
      AXF_CC_NUM_Version__c = 0
    );
    insert result;
    return result;
  }

  private static AXF_OBJ_BankAccountTransaction__c bat(
    Id bankId,
    String key,
    Decimal magnitude,
    String direction,
    String status,
    Date effective
  ) {
    return new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_MDR_BankAccount__c = bankId,
      AXF_BAT_EXI_SourceKey__c = 'bat-' + key + '-' + System.now().getTime(),
      AXF_BAT_PKL_Source__c = 'MANUAL',
      AXF_BAT_DAT_Date__c = effective,
      AXF_BAT_NUM_Magnitude__c = magnitude,
      AXF_BAT_PKL_Direction__c = direction,
      AXF_BAT_PKL_Status__c = status,
      AXF_BAT_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BAT_TXT_Description__c = key,
      AXF_BAT_NUM_Version__c = 0
    );
  }

  private class Fixture {
    Account personA;
    Account businessB;
    AXF_OBJ_BankAccount__c bankA;
    AXF_OBJ_CreditCard__c cardA;
    AXF_OBJ_BankAccount__c bankB;
    AXF_OBJ_BankAccountTransaction__c debitA;
    AXF_OBJ_BankAccountTransaction__c debitB;
  }

  /** Holder A (Business; Gestor PS cannot create AXF_Person directly): bank (debit 300, credit 1000, pending debit 50, old debit 999) + USD card (80). Business B: bank (debit 200). */
  private static Fixture fixture() {
    Fixture f = new Fixture();
    f.personA = holder('Ana Consolidada Ltda', false);
    f.businessB = holder('Empresa Consolidada', false);
    f.bankA = bank(f.personA.Id, 'a');
    f.cardA = card(f.personA.Id, 'a');
    f.bankB = bank(f.businessB.Id, 'b');
    f.debitA = bat(
      f.bankA.Id,
      'a-debit',
      300,
      'DEBIT',
      'POSTED',
      Date.newInstance(2026, 8, 10)
    );
    f.debitB = bat(
      f.bankB.Id,
      'b-debit',
      200,
      'DEBIT',
      'POSTED',
      Date.newInstance(2026, 8, 20)
    );
    insert new List<AXF_OBJ_BankAccountTransaction__c>{
      f.debitA,
      bat(
        f.bankA.Id,
        'a-credit',
        1000,
        'CREDIT',
        'POSTED',
        Date.newInstance(2026, 8, 1)
      ),
      bat(
        f.bankA.Id,
        'a-pending',
        50,
        'DEBIT',
        'PENDING',
        Date.newInstance(2026, 8, 15)
      ),
      bat(
        f.bankA.Id,
        'a-old',
        999,
        'DEBIT',
        'POSTED',
        Date.newInstance(2025, 1, 1)
      ),
      f.debitB
    };
    insert new AXF_OBJ_CreditCardTransaction__c(
      AXF_CCT_MDR_CreditCard__c = f.cardA.Id,
      AXF_CCT_EXI_SourceKey__c = 'cct-a-' + System.now().getTime(),
      AXF_CCT_PKL_Source__c = 'MANUAL',
      AXF_CCT_DAT_Date__c = Date.newInstance(2026, 8, 12),
      AXF_CCT_NUM_Magnitude__c = 80,
      AXF_CCT_PKL_Direction__c = 'DEBIT',
      AXF_CCT_PKL_Status__c = 'POSTED',
      AXF_CCT_TXT_CurrencyIsoCode__c = 'USD',
      AXF_CCT_TXT_Description__c = 'Software',
      AXF_CCT_NUM_Version__c = 0
    );
    return f;
  }

  /** Isolates the sum from whatever AXF-5 allocation state the org carries. */
  private static void noAllocations() {
    ALT_CLS_ConsolidationService.allocationOverride = new Map<Id, List<ALT_CLS_ConsolidationService.AllocationShare>>();
  }

  private static ALT_CLS_ConsolidationService.ScopeInput scope(
    List<Id> ids,
    Date fromDate,
    Date toDate
  ) {
    ALT_CLS_ConsolidationService.ScopeInput input = new ALT_CLS_ConsolidationService.ScopeInput();
    input.accountIds = ids;
    input.fromDate = fromDate;
    input.toDate = toDate;
    return input;
  }

  private static ALT_CLS_ConsolidationService.Contribution contribution(
    ALT_CLS_ConsolidationService.Result result,
    Id accountId,
    Id sourceId
  ) {
    for (ALT_CLS_ConsolidationService.Contribution c : result.contributions) {
      if (c.accountId == accountId && c.sourceId == sourceId) {
        return c;
      }
    }
    return null;
  }

  private static ALT_CLS_ConsolidationService.Total total(
    ALT_CLS_ConsolidationService.Result result,
    String currencyIso
  ) {
    for (ALT_CLS_ConsolidationService.Total t : result.totals) {
      if (t.currencyIso == currencyIso) {
        return t;
      }
    }
    return null;
  }

  @IsTest
  static void authorizedScopeKeepsAttributionCurrencyDateAndSource() {
    noAllocations();
    System.runAs(byAlias('axf122g')) {
      Fixture f = fixture();
      Test.startTest();
      ALT_CLS_ConsolidationService.Result result = new ALT_CLS_ConsolidationService()
        .consolidate(
          scope(
            new List<Id>{ f.personA.Id, f.businessB.Id },
            Date.newInstance(2026, 8, 1),
            Date.newInstance(2026, 8, 31)
          )
        );
      Test.stopTest();
      Assert.areEqual(
        ALT_CLS_ConsolidationService.CONFIDENCE_FULL,
        result.confidence
      );
      Assert.areEqual('consolidation-scope@1.0.0', result.policyVersion);
      Assert.isTrue(result.reasons.isEmpty());
      Assert.isTrue(result.exclusions.isEmpty());
      Assert.areEqual(2, result.holders.size());
      for (ALT_CLS_ConsolidationService.HolderScope holder : result.holders) {
        Assert.areEqual('AUTHORIZED', holder.state, holder.accountName);
        Assert.areEqual('FULL', holder.coverage);
      }
      Assert.areEqual(3, result.contributions.size(), 'bank A, card A, bank B');
      ALT_CLS_ConsolidationService.Contribution bankA = contribution(
        result,
        f.personA.Id,
        f.bankA.Id
      );
      Assert.areEqual('HOLDER', bankA.attribution);
      Assert.areEqual('BANK', bankA.sourceKind);
      Assert.areEqual('Banco a ****a', bankA.sourceLabel);
      Assert.areEqual('BRL', bankA.currencyIso);
      Assert.areEqual(1000, bankA.inflow);
      Assert.areEqual(
        300,
        bankA.outflow,
        'pendente e fora do periodo nao somam'
      );
      Assert.areEqual(700, bankA.net);
      Assert.areEqual(2, bankA.factCount);
      Assert.areEqual(1, bankA.pendingCount);
      Assert.areEqual(Date.newInstance(2026, 8, 1), bankA.effectiveFrom);
      Assert.areEqual(Date.newInstance(2026, 8, 10), bankA.effectiveTo);
      ALT_CLS_ConsolidationService.Contribution cardA = contribution(
        result,
        f.personA.Id,
        f.cardA.Id
      );
      Assert.areEqual('CARD', cardA.sourceKind);
      Assert.areEqual('USD', cardA.currencyIso, 'moeda original preservada');
      Assert.areEqual(80, cardA.outflow);
      ALT_CLS_ConsolidationService.Contribution bankB = contribution(
        result,
        f.businessB.Id,
        f.bankB.Id
      );
      Assert.areEqual('Empresa Consolidada', bankB.accountName);
      Assert.areEqual(200, bankB.outflow);
      Assert.areEqual(2, result.totals.size());
      ALT_CLS_ConsolidationService.Total brl = total(result, 'BRL');
      Assert.areEqual(1000, brl.inflow);
      Assert.areEqual(500, brl.outflow);
      Assert.areEqual(500, brl.net);
      Assert.areEqual(3, brl.factCount);
      Assert.areEqual(2, brl.holderCount);
      ALT_CLS_ConsolidationService.Total usd = total(result, 'USD');
      Assert.areEqual(80, usd.outflow, 'sem conversao nem paridade');
      Assert.areEqual(1, usd.holderCount);
    }
  }

  @IsTest
  static void unauthorizedHolderIsNeitherLoadedNorConfirmed() {
    noAllocations();
    Account foreign;
    System.runAs(byAlias('axf122p')) {
      foreign = holder('Empresa Alheia', false);
      insert bat(
        bank(foreign.Id, 'x').Id,
        'x',
        5000,
        'CREDIT',
        'POSTED',
        Date.today()
      );
    }
    System.runAs(byAlias('axf122g')) {
      Fixture f = fixture();
      Id fake =
        Account.SObjectType.getDescribe().getKeyPrefix() + '000000000ZZZ';
      Test.startTest();
      ALT_CLS_ConsolidationService.Result result = new ALT_CLS_ConsolidationService()
        .consolidate(
          scope(new List<Id>{ f.personA.Id, foreign.Id, fake }, null, null)
        );
      Test.stopTest();
      Assert.areEqual(1, result.holders.size());
      Assert.areEqual(f.personA.Id, result.holders[0].accountId);
      Assert.areEqual(2, result.exclusions.size());
      for (
        ALT_CLS_ConsolidationService.Exclusion exclusion : result.exclusions
      ) {
        Assert.areEqual(
          'NOT_AUTHORIZED',
          exclusion.reason,
          'mesma resposta para privado e inexistente'
        );
      }
      Assert.areEqual(
        ALT_CLS_ConsolidationService.CONFIDENCE_FULL,
        result.confidence,
        'escopo efetivo e integro'
      );
      Assert.areEqual(
        1299,
        total(result, 'BRL').outflow,
        'inclui fato antigo sem filtro de periodo'
      );
      Assert.isFalse(
        JSON.serialize(result).contains('Alheia'),
        'nada da pessoa nao autorizada'
      );
      Assert.isFalse(JSON.serialize(result).contains('5000'));
    }
  }

  @IsTest
  static void partialAccessIsUnknownAndDegradesWithoutMisleadingTotal() {
    noAllocations();
    Account shared;
    System.runAs(byAlias('axf122p')) {
      shared = holder('Empresa Parcial', false);
      insert bat(
        bank(shared.Id, 'p').Id,
        'p',
        700,
        'DEBIT',
        'POSTED',
        Date.today()
      );
      insert new AccountTeamMember(
        AccountId = shared.Id,
        UserId = byAlias('axf122g').Id,
        TeamMemberRole = ALT_CLS_AxonCompanyResponsible.validTeamRole(),
        AccountAccessLevel = 'Read',
        OpportunityAccessLevel = 'None',
        CaseAccessLevel = 'None'
      );
    }
    System.runAs(byAlias('axf122g')) {
      Fixture f = fixture();
      ALT_CLS_ConsolidationService service = new ALT_CLS_ConsolidationService();
      Test.startTest();
      ALT_CLS_ConsolidationService.Result mixed = service.consolidate(
        scope(new List<Id>{ f.businessB.Id, shared.Id }, null, null)
      );
      ALT_CLS_ConsolidationService.Result only = service.consolidate(
        scope(new List<Id>{ shared.Id }, null, null)
      );
      Test.stopTest();
      Assert.areEqual(2, mixed.holders.size());
      Assert.areEqual(
        ALT_CLS_ConsolidationService.CONFIDENCE_DEGRADED,
        mixed.confidence
      );
      Assert.isTrue(mixed.reasons.contains('COVERAGE_UNVERIFIED'));
      Assert.areEqual(2, mixed.holders.size());
      for (ALT_CLS_ConsolidationService.HolderScope holder : mixed.holders) {
        if (holder.accountId == shared.Id) {
          Assert.areEqual('UNKNOWN', holder.state);
          Assert.areEqual('UNVERIFIED', holder.coverage);
        } else {
          Assert.areEqual('AUTHORIZED', holder.state);
        }
      }
      Assert.areEqual(
        1,
        mixed.contributions.size(),
        'contribuicao parcial e retida'
      );
      Assert.areEqual(
        200,
        total(mixed, 'BRL').outflow,
        'total so do escopo integro'
      );
      Assert.areEqual(1, total(mixed, 'BRL').holderCount);
      Assert.isFalse(
        JSON.serialize(mixed).contains('700'),
        'valor privado nao vaza'
      );
      Assert.areEqual(
        ALT_CLS_ConsolidationService.CONFIDENCE_BLOCKED,
        only.confidence
      );
      Assert.isTrue(only.reasons.contains('NO_AUTHORIZED_SCOPE'));
      Assert.isTrue(only.totals.isEmpty());
    }
  }

  @IsTest
  static void confirmedAllocationSharesFollowAttribution() {
    System.runAs(byAlias('axf122g')) {
      Fixture f = fixture();
      Id outsider =
        Account.SObjectType.getDescribe().getKeyPrefix() + '000000000YYY';
      ALT_CLS_ConsolidationService.allocationOverride = new Map<Id, List<ALT_CLS_ConsolidationService.AllocationShare>>{
        f.debitA.Id => new List<ALT_CLS_ConsolidationService.AllocationShare>{
          new ALT_CLS_ConsolidationService.AllocationShare(f.personA.Id, 70),
          new ALT_CLS_ConsolidationService.AllocationShare(f.businessB.Id, 30)
        },
        f.debitB.Id => new List<ALT_CLS_ConsolidationService.AllocationShare>{
          new ALT_CLS_ConsolidationService.AllocationShare(f.personA.Id, 50),
          new ALT_CLS_ConsolidationService.AllocationShare(outsider, 50)
        }
      };
      Test.startTest();
      ALT_CLS_ConsolidationService.Result result = new ALT_CLS_ConsolidationService()
        .consolidate(
          scope(
            new List<Id>{ f.personA.Id, f.businessB.Id },
            Date.newInstance(2026, 8, 1),
            Date.newInstance(2026, 8, 31)
          )
        );
      Test.stopTest();
      ALT_CLS_ConsolidationService.Contribution aFromBankA = contribution(
        result,
        f.personA.Id,
        f.bankA.Id
      );
      Assert.areEqual(
        'MIXED',
        aFromBankA.attribution,
        'credito do titular + cota rateada'
      );
      Assert.areEqual(1000, aFromBankA.inflow);
      Assert.areEqual(210, aFromBankA.outflow);
      ALT_CLS_ConsolidationService.Contribution bFromBankA = contribution(
        result,
        f.businessB.Id,
        f.bankA.Id
      );
      Assert.areEqual('ALLOCATION', bFromBankA.attribution);
      Assert.areEqual(90, bFromBankA.outflow);
      Assert.areEqual(
        'Banco a ****a',
        bFromBankA.sourceLabel,
        'rastreabilidade da fonte'
      );
      ALT_CLS_ConsolidationService.Contribution aFromBankB = contribution(
        result,
        f.personA.Id,
        f.bankB.Id
      );
      Assert.areEqual(100, aFromBankB.outflow);
      Assert.isNull(
        contribution(result, f.businessB.Id, f.bankB.Id),
        'titular nao recebe cota nao atribuida'
      );
      Assert.areEqual(1000, total(result, 'BRL').inflow);
      Assert.areEqual(
        400,
        total(result, 'BRL').outflow,
        '210 + 90 + 100; cota externa fora'
      );
      Assert.areEqual(
        ALT_CLS_ConsolidationService.CONFIDENCE_DEGRADED,
        result.confidence
      );
      Assert.isTrue(result.reasons.contains('ALLOCATED_OUTSIDE_SCOPE'));
      Boolean counted = false;
      for (
        ALT_CLS_ConsolidationService.Exclusion exclusion : result.exclusions
      ) {
        if (exclusion.reason == 'ALLOCATED_OUTSIDE_SCOPE') {
          counted = true;
          Assert.areEqual(1, exclusion.count);
          Assert.isNull(
            exclusion.accountId,
            'nao nomeia quem esta fora do escopo'
          );
        }
      }
      Assert.isTrue(counted);
    }
  }

  @IsTest
  static void missingObjectAccessBlocksAndMissingCapabilityForbids() {
    Account mine;
    System.runAs(byAlias('axf122g')) {
      mine = holder('Empresa Bloqueio', false);
    }
    System.runAs(byAlias('axf122b')) {
      ALT_CLS_ConsolidationService.Result result = new ALT_CLS_ConsolidationService()
        .consolidate(scope(new List<Id>{ mine.Id }, null, null));
      Assert.areEqual(
        ALT_CLS_ConsolidationService.CONFIDENCE_BLOCKED,
        result.confidence
      );
      Assert.isFalse(result.reasons.isEmpty());
      Assert.isTrue(result.reasons[0].startsWith('FIELD_ACCESS:'));
      Assert.isTrue(
        result.holders.isEmpty(),
        'nada carregado quando bloqueado'
      );
    }
    System.runAs(byAlias('axf122n')) {
      try {
        new ALT_CLS_ConsolidationService()
          .consolidate(scope(new List<Id>{ mine.Id }, null, null));
        Assert.fail('FORBIDDEN esperado');
      } catch (ALT_CLS_ConsolidationService.ConsolidationException expected) {
        Assert.areEqual('FORBIDDEN', expected.code);
      }
    }
    System.runAs(byAlias('axf122g')) {
      for (
        ALT_CLS_ConsolidationService.ScopeInput bad : new List<ALT_CLS_ConsolidationService.ScopeInput>{
          null,
          scope(new List<Id>(), null, null),
          scope(
            new List<Id>{ mine.Id },
            Date.newInstance(2026, 9, 2),
            Date.newInstance(2026, 9, 1)
          )
        }
      ) {
        try {
          new ALT_CLS_ConsolidationService().consolidate(bad);
          Assert.fail('INVALID_INPUT esperado');
        } catch (ALT_CLS_ConsolidationService.ConsolidationException expected) {
          Assert.areEqual('INVALID_INPUT', expected.code);
        }
      }
    }
  }
}
