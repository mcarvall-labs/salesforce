/**
 * @description AXF-134: eligible-source selection (BANK/CARD, POSTED, AVAILABLE parent, authorized
 * holder, no OPEN review, residual capacity), deterministic persisted + virtual candidates matched
 * on holder/currency/direction/funding without amount or date tolerance, explicit confirmation
 * through AXF-25 (typed allocation, untouched fact, replay, CONFLICT, nothing persisted on failure).
 */
@IsTest(isParallel=false)
// API 62: AXON_DEV enforces FLS on plain test DML under runAs from API 67 onwards.
private class ALT_CLS_SourceLinkServiceTest {
  private static User byAlias(String alias) {
    return [SELECT Id FROM User WHERE Alias = :alias LIMIT 1];
  }

  @TestSetup
  static void setup() {
    Id profileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
    .Id;
    List<User> users = new List<User>();
    for (String alias : new List<String>{ 'axf134g', 'axf134p', 'axf134n' }) {
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
          'AXF_PS_FinancialEntry',
          'AXF_PS_Realization',
          'AXF_PS_Participante'
        )
    ]) {
      permissionSets.put(permission.Name, permission.Id);
    }
    Assert.areEqual(4, permissionSets.size(), 'permission sets must exist');
    List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (Integer i = 0; i < 2; i++) {
      for (
        String name : new List<String>{
          'AXF_PS_GestorFinanceiro',
          'AXF_PS_FinancialEntry',
          'AXF_PS_Realization'
        }
      ) {
        assignments.add(
          new PermissionSetAssignment(
            AssigneeId = users[i].Id,
            PermissionSetId = permissionSets.get(name)
          )
        );
      }
    }
    assignments.add(
      new PermissionSetAssignment(
        AssigneeId = users[2].Id,
        PermissionSetId = permissionSets.get('AXF_PS_Participante')
      )
    );
    insert assignments;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert new AXF_ReportCurrencyPref__c(
        SetupOwnerId = UserInfo.getOrganizationId(),
        AXF_RCP_TXT_IsoCode__c = 'BRL'
      );
    }
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

  private static AXF_OBJ_BankAccount__c bank(
    Id accountId,
    String state,
    String iso
  ) {
    AXF_OBJ_BankAccount__c result = new AXF_OBJ_BankAccount__c(
      AXF_BA_LKP_Account__c = accountId,
      AXF_BA_PKL_AvailabilityState__c = state,
      AXF_BA_TXT_CurrencyIsoCode__c = iso,
      AXF_BA_TXT_InstitutionName__c = 'Banco Teste',
      AXF_BA_TXT_NumberMasked__c = '****1234'
    );
    insert result;
    return result;
  }

  private static AXF_OBJ_BankAccountTransaction__c fact(
    Id bankId,
    Decimal amount,
    String status,
    Date factDate,
    String key
  ) {
    return new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_MDR_BankAccount__c = bankId,
      AXF_BAT_NUM_Magnitude__c = amount,
      AXF_BAT_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BAT_PKL_Direction__c = 'DEBIT',
      AXF_BAT_DAT_Date__c = factDate,
      AXF_BAT_TXT_Description__c = 'Fact ' + key,
      AXF_BAT_EXI_SourceKey__c = 'axf134-' + key,
      AXF_BAT_PKL_Source__c = 'CSV',
      AXF_BAT_PKL_Status__c = status,
      AXF_BAT_NUM_Version__c = 0
    );
  }

  private static AXF_OBJ_FinancialTransaction__c plan(
    Id accountId,
    String key,
    Decimal magnitude,
    String direction,
    String iso,
    Date due
  ) {
    return new AXF_OBJ_FinancialTransaction__c(
      AXF_FTX_LKP_Account__c = accountId,
      AXF_FTX_NUM_Magnitude__c = magnitude,
      AXF_FTX_PKL_Direction__c = direction,
      AXF_FTX_TXT_CurrencyIsoCode__c = iso,
      AXF_FTX_DAT_PurchaseDate__c = due,
      AXF_FTX_DAT_DueDate__c = due,
      AXF_FTX_TXT_Description__c = 'Plan ' + key,
      AXF_FTX_PKL_Status__c = 'PLANNED',
      AXF_FTX_PKL_PlanKind__c = 'PLANNED',
      AXF_FTX_NUM_Version__c = 0,
      AXF_FTX_EXI_ClientRequestId__c = 'ftx-134-' + key
    );
  }

  private static void openReview(AXF_OBJ_BankAccountTransaction__c row) {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      AXF_CLS_ReviewQueueTriggerHandler.guardEnabled = true;
      try {
        insert new AXF_OBJ_ReviewItem__c(
          AXF_RVI_PKL_Type__c = 'SOURCE_CHANGE',
          AXF_RVI_PKL_State__c = 'OPEN',
          AXF_RVI_EXI_ReviewKey__c = 'axf134-review-' + row.Id,
          AXF_RVI_NUM_Version__c = 0,
          AXF_RVI_LKP_BankAccountTransaction__c = row.Id,
          AXF_RVI_LKP_BankAccount__c = row.AXF_BAT_MDR_BankAccount__c,
          AXF_RVI_DT_ObservedAt__c = System.now()
        );
      } finally {
        AXF_CLS_ReviewQueueTriggerHandler.guardEnabled = false;
      }
    }
  }

  private static ALT_CLS_SourceLinkService.SourceQuery sourceQuery(
    Id accountId,
    Integer pageNumber,
    Integer pageSize
  ) {
    ALT_CLS_SourceLinkService.SourceQuery query = new ALT_CLS_SourceLinkService.SourceQuery();
    query.accountId = accountId;
    query.pageNumber = pageNumber;
    query.pageSize = pageSize;
    return query;
  }

  private static ALT_CLS_SourceLinkService.CandidateQuery candidateQuery(
    Id sourceId,
    Integer pageNumber,
    Integer pageSize
  ) {
    ALT_CLS_SourceLinkService.CandidateQuery query = new ALT_CLS_SourceLinkService.CandidateQuery();
    query.sourceId = sourceId;
    query.sourceKind = 'BANK';
    query.pageNumber = pageNumber;
    query.pageSize = pageSize;
    return query;
  }

  private static ALT_CLS_SourceLinkService.ConfirmInput confirmInput(
    AXF_OBJ_BankAccountTransaction__c source,
    Id targetId,
    Decimal targetVersion,
    Decimal amount,
    String key
  ) {
    ALT_CLS_SourceLinkService.ConfirmInput input = new ALT_CLS_SourceLinkService.ConfirmInput();
    input.sourceId = source.Id;
    input.sourceKind = 'BANK';
    input.sourceVersion = 0;
    input.targetId = targetId;
    input.targetVersion = targetVersion;
    input.amount = amount;
    input.recognitionDate = source.AXF_BAT_DAT_Date__c;
    input.operationKey = 'axf134-' + key;
    return input;
  }

  private static String failure(ALT_CLS_SourceLinkService.ConfirmInput input) {
    try {
      new ALT_CLS_SourceLinkService().confirm(input);
      return null;
    } catch (ALT_CLS_SourceLinkService.SourceLinkException expected) {
      return expected.getMessage();
    }
  }

  @IsTest
  static void eligibleSourcesExcludeIneligibleFactsAndOrderDeterministically() {
    System.runAs(byAlias('axf134g')) {
      Account owner = holder('Holder 134 sources');
      AXF_OBJ_BankAccount__c available = bank(owner.Id, 'AVAILABLE', 'BRL');
      AXF_OBJ_BankAccount__c custody = bank(owner.Id, 'CUSTODY', 'BRL');
      AXF_OBJ_CreditCard__c card = new AXF_OBJ_CreditCard__c(
        AXF_CC_LKP_Account__c = owner.Id,
        AXF_CC_PKL_AvailabilityState__c = 'AVAILABLE',
        AXF_CC_TXT_CurrencyIsoCode__c = 'BRL',
        AXF_CC_TXT_InstitutionName__c = 'Cartao Teste',
        AXF_CC_TXT_LastFourMasked__c = '9876'
      );
      insert card;
      List<AXF_OBJ_BankAccountTransaction__c> facts = new List<AXF_OBJ_BankAccountTransaction__c>{
        fact(available.Id, 300, 'POSTED', Date.today().addDays(-3), 'older'),
        fact(
          available.Id,
          200,
          'POSTED',
          Date.today().addDays(-1),
          'recent-big'
        ),
        fact(
          available.Id,
          100,
          'POSTED',
          Date.today().addDays(-1),
          'recent-small'
        ),
        fact(available.Id, 50, 'PENDING', Date.today(), 'pending'),
        fact(custody.Id, 60, 'POSTED', Date.today(), 'custody'),
        fact(available.Id, 70, 'POSTED', Date.today(), 'reviewed'),
        fact(available.Id, 80, 'POSTED', Date.today(), 'exhausted'),
        fact(available.Id, 90, 'POSTED', Date.today().addYears(-2), 'ancient')
      };
      insert facts;
      openReview(facts[5]);
      AXF_OBJ_CreditCardTransaction__c cardFact = new AXF_OBJ_CreditCardTransaction__c(
        AXF_CCT_MDR_CreditCard__c = card.Id,
        AXF_CCT_NUM_Magnitude__c = 40,
        AXF_CCT_TXT_CurrencyIsoCode__c = 'BRL',
        AXF_CCT_PKL_Direction__c = 'DEBIT',
        AXF_CCT_DAT_Date__c = Date.today().addDays(-2),
        AXF_CCT_TXT_Description__c = 'Card fact',
        AXF_CCT_EXI_SourceKey__c = 'axf134-card',
        AXF_CCT_PKL_Source__c = 'PLUGGY',
        AXF_CCT_PKL_Status__c = 'POSTED',
        AXF_CCT_NUM_Version__c = 0
      );
      insert cardFact;
      // Exhaust one fact through AXF-25 directly (ACTUAL_ONLY plan born from the fact).
      ALT_CLS_RealizationService.Input drain = new ALT_CLS_RealizationService.Input();
      drain.accountId = owner.Id;
      drain.sourceId = facts[6].Id;
      drain.sourceKind = 'BANK';
      drain.sourceVersion = 0;
      drain.amount = 80;
      drain.currencyIso = 'BRL';
      drain.direction = 'DEBIT';
      drain.recognitionDate = Date.today();
      drain.operationKey = 'axf134-drain';
      new ALT_CLS_RealizationService().apply(drain);

      Test.startTest();
      ALT_CLS_SourceLinkService.SourcePage first = new ALT_CLS_SourceLinkService()
        .listSources(sourceQuery(owner.Id, 1, 3));
      ALT_CLS_SourceLinkService.SourcePage second = new ALT_CLS_SourceLinkService()
        .listSources(sourceQuery(owner.Id, 2, 3));
      ALT_CLS_SourceLinkService.SourceView drained = new ALT_CLS_SourceLinkService()
        .readSource(facts[6].Id, 'BANK');
      Test.stopTest();

      Assert.areEqual(3, first.items.size(), 'page 1 holds three');
      Assert.isTrue(first.hasMore, 'four eligible sources exist');
      Assert.areEqual(1, second.items.size(), 'page 2 holds the last one');
      Assert.isFalse(second.hasMore);
      // Most recent first, then smaller amount, then BANK before CARD.
      Assert.areEqual(facts[2].Id, first.items[0].sourceId, 'recent-small');
      Assert.areEqual(facts[1].Id, first.items[1].sourceId, 'recent-big');
      Assert.areEqual(
        cardFact.Id,
        first.items[2].sourceId,
        'card two days ago'
      );
      Assert.areEqual(facts[0].Id, second.items[0].sourceId, 'older');
      Assert.areEqual('CARD', first.items[2].sourceKind);
      Assert.areEqual('Cartao Teste 9876', first.items[2].fundingLabel);
      Assert.areEqual(100, first.items[0].residual, 'no allocation yet');
      Assert.areEqual(
        3,
        first.excludedCount,
        'custody, reviewed and exhausted are excluded; pending and ancient are never scanned'
      );
      Assert.isFalse(drained.eligible);
      Assert.isTrue(
        drained.reasons.contains('SOURCE_EXHAUSTED'),
        drained.reasons + ''
      );
      Assert.areEqual(0, drained.residual);
      ALT_CLS_SourceLinkService.SourceView reviewed = new ALT_CLS_SourceLinkService()
        .readSource(facts[5].Id, 'BANK');
      Assert.isTrue(
        reviewed.reasons.contains('REVIEW_OPEN'),
        reviewed.reasons + ''
      );
      ALT_CLS_SourceLinkService.SourceView pending = new ALT_CLS_SourceLinkService()
        .readSource(facts[3].Id, 'BANK');
      Assert.isTrue(
        pending.reasons.contains('NOT_POSTED'),
        pending.reasons + ''
      );
      ALT_CLS_SourceLinkService.SourceView custodyFact = new ALT_CLS_SourceLinkService()
        .readSource(facts[4].Id, 'BANK');
      Assert.isTrue(
        custodyFact.reasons.contains('FUNDING_NOT_AVAILABLE'),
        custodyFact.reasons + ''
      );
    }
  }

  @IsTest
  static void candidatesMatchHolderCurrencyDirectionFundingAndExcludeInvalidTargets() {
    System.runAs(byAlias('axf134g')) {
      Account owner = holder('Holder 134 candidates');
      Account other = holder('Holder 134 other');
      AXF_OBJ_BankAccount__c available = bank(owner.Id, 'AVAILABLE', 'BRL');
      AXF_OBJ_BankAccount__c otherBank = bank(owner.Id, 'AVAILABLE', 'BRL');
      AXF_OBJ_CreditCard__c card = new AXF_OBJ_CreditCard__c(
        AXF_CC_LKP_Account__c = owner.Id,
        AXF_CC_PKL_AvailabilityState__c = 'AVAILABLE',
        AXF_CC_TXT_CurrencyIsoCode__c = 'BRL'
      );
      insert card;
      AXF_OBJ_BankAccountTransaction__c source = fact(
        available.Id,
        150,
        'POSTED',
        Date.today(),
        'source'
      );
      source.AXF_BAT_TXT_ProviderCategory__c = 'Housing';
      insert source;
      Date d1 = Date.today().addDays(5);
      Date d2 = Date.today().addDays(10);
      List<AXF_OBJ_FinancialTransaction__c> plans = new List<AXF_OBJ_FinancialTransaction__c>{
        plan(owner.Id, 'late', 150, 'DEBIT', 'BRL', d2),
        plan(owner.Id, 'early-big', 200, 'DEBIT', 'BRL', d1),
        plan(owner.Id, 'early-small', 150, 'DEBIT', 'BRL', d1),
        plan(owner.Id, 'funded-here', 150, 'DEBIT', 'BRL', d2),
        plan(owner.Id, 'funded-elsewhere', 150, 'DEBIT', 'BRL', d1),
        plan(owner.Id, 'card-funded', 150, 'DEBIT', 'BRL', d1),
        plan(owner.Id, 'cancelled', 150, 'DEBIT', 'BRL', d1),
        plan(owner.Id, 'credit', 150, 'CREDIT', 'BRL', d1),
        plan(owner.Id, 'usd', 150, 'DEBIT', 'USD', d1),
        plan(owner.Id, 'realized', 100, 'DEBIT', 'BRL', d1),
        plan(other.Id, 'foreign', 150, 'DEBIT', 'BRL', d1)
      };
      plans[3].AXF_FTX_LKP_BankAccount__c = available.Id;
      plans[3].AXF_FTX_TXT_UserCategory__c = 'housing';
      plans[4].AXF_FTX_LKP_BankAccount__c = otherBank.Id;
      plans[5].AXF_FTX_LKP_CreditCard__c = card.Id;
      plans[6].AXF_FTX_PKL_ScheduleState__c = 'CANCELLED';
      insert plans;
      ALT_CLS_RealizationService.Input drain = new ALT_CLS_RealizationService.Input();
      drain.targetId = plans[9].Id;
      drain.targetVersion = 0;
      drain.sourceKind = 'CASH';
      drain.amount = 100;
      drain.recognitionDate = Date.today();
      drain.operationKey = 'axf134-realized';
      new ALT_CLS_RealizationService().apply(drain);
      // Virtual lines: an ACTIVE estimated schedule of the same holder/currency/direction.
      ALT_CLS_FinancialScheduleService.CreateInput scheduleInput = new ALT_CLS_FinancialScheduleService.CreateInput();
      scheduleInput.accountId = owner.Id;
      scheduleInput.direction = 'DEBIT';
      scheduleInput.currencyIsoCode = 'BRL';
      scheduleInput.method = 'ESTIMATED';
      // 24 monthly occurrences from today: the persisted window covers the first ones,
      // the remaining lines come back from the projection as virtual candidates.
      scheduleInput.totalInstallments = 24;
      scheduleInput.firstSequence = 1;
      scheduleInput.trackingStartSequence = 1;
      scheduleInput.trackingDueDate = Date.today();
      scheduleInput.horizonMonths = 1;
      scheduleInput.periodMonths = 1;
      scheduleInput.referenceAmount = 150.00;
      scheduleInput.legacyGroupKey = 'axf134-virtual';
      ALT_CLS_FinancialScheduleService.CreateResult created = ALT_CLS_FinancialScheduleService.createSchedule(
        scheduleInput
      );
      Assert.areEqual('CREATED', created.outcome, created.message);

      Test.startTest();
      ALT_CLS_SourceLinkService.CandidatePage all = new ALT_CLS_SourceLinkService()
        .listCandidates(candidateQuery(source.Id, 1, 50));
      ALT_CLS_SourceLinkService.CandidatePage page = new ALT_CLS_SourceLinkService()
        .listCandidates(candidateQuery(source.Id, 1, 2));
      ALT_CLS_SourceLinkService.CandidateQuery search = candidateQuery(
        source.Id,
        1,
        50
      );
      search.term = 'late';
      ALT_CLS_SourceLinkService.CandidatePage searched = new ALT_CLS_SourceLinkService()
        .listCandidates(search);
      Test.stopTest();

      Assert.areEqual(150, all.suggestedAmount, 'full residual of the fact');
      Assert.areEqual(source.AXF_BAT_DAT_Date__c, all.suggestedDate);
      List<Id> persisted = new List<Id>();
      Integer scheduled = 0;
      Integer virtualCount = 0;
      for (ALT_CLS_SourceLinkService.CandidateView c : all.items) {
        if (c.persisted) {
          if (c.currencyIso == 'BRL') {
            Assert.isTrue(c.linkable, 'persisted forecasts are linkable');
          } else {
            // AXF-140: another currency is shown but blocked (exact currency arithmetic).
            Assert.isFalse(
              c.linkable,
              'a foreign-currency target is never selectable'
            );
            Assert.areEqual('BLOCKED', c.state);
          }
          if (c.scheduleId != null) {
            scheduled++;
            continue;
          }
          persisted.add(c.targetId);
        } else {
          virtualCount++;
          Assert.isFalse(c.linkable);
          Assert.isTrue(c.reasons.contains('MATERIALIZATION_REQUIRED'));
          Assert.isNotNull(c.scheduleId);
        }
      }
      Assert.areEqual(
        new List<Id>{
          plans[3].Id,
          plans[0].Id,
          plans[1].Id,
          plans[2].Id,
          plans[8].Id
        },
        persisted,
        'AXF-MATCHING presentation order: exact source identity first, then record identity; never the closest amount or date'
      );
      Assert.isTrue(
        scheduled > 0,
        'materialized schedule occurrences are linkable'
      );
      Assert.isTrue(virtualCount > 0, 'virtual lines are suggested');
      Assert.areEqual(virtualCount, all.virtualCount);
      Assert.areEqual(
        1,
        all.excludedCount,
        'the realized plan is excluded after scan'
      );
      Assert.areEqual(2, page.items.size());
      Assert.isTrue(page.hasMore);
      Assert.areEqual(
        all.items[0].targetId,
        page.items[0].targetId,
        'pages follow the same deterministic order'
      );
      Assert.areEqual(plans[3].Id, page.items[0].targetId);
      // AXF-139: evidence is independent, explicit and consultative.
      Assert.areEqual(
        ALT_CLS_MatchEvidence.MATCHING_POLICY,
        all.matchingPolicy
      );
      Assert.areEqual('CONSULTATIVE', all.state);
      Assert.isNotNull(all.evidenceCutoff);
      Map<String, ALT_CLS_MatchEvidence.EvidenceView> funded = new Map<String, ALT_CLS_MatchEvidence.EvidenceView>();
      CandidateViewByTarget lookup = new CandidateViewByTarget(all.items);
      for (
        ALT_CLS_MatchEvidence.EvidenceView v : lookup.get(plans[3].Id).evidence
      ) {
        funded.put(v.feature, v);
      }
      Assert.areEqual(9, funded.size(), 'every feature is reported');
      Assert.areEqual(
        'BLOCKED',
        lookup.get(plans[8].Id).state,
        'AXF-140: a foreign-currency target is blocked, visible and never confirmed'
      );
      Assert.areEqual('EXACT', funded.get('SOURCE_IDENTITY').relation);
      Assert.areEqual('EXACT', funded.get('HOLDER').relation);
      Assert.areEqual('EXACT', funded.get('AMOUNT').relation);
      Assert.areEqual('EXACT', funded.get('RESIDUAL').relation);
      Assert.areEqual('DIFFERENT', funded.get('DATE').relation);
      Assert.areEqual(
        10,
        funded.get('DATE').delta,
        'signed days, no tolerance'
      );
      Assert.areEqual('DIFFERENT', funded.get('DESCRIPTION').relation);
      Assert.areEqual(
        'EXACT',
        funded.get('CATEGORY').relation,
        'provider vs user category folded'
      );
      Assert.areEqual('Housing', funded.get('CATEGORY').sourceValue);
      Assert.areEqual(
        'UNKNOWN',
        funded.get('EXTERNAL_IDENTITY').relation,
        'AXF-140: the fact has a provider key and the forecast carries none, so the feature is unknown on one side'
      );
      Assert.areEqual(
        'EXTERNAL_IDENTITY_UNKNOWN',
        funded.get('EXTERNAL_IDENTITY').explanation
      );
      Assert.areNotEqual(
        'REDACTED',
        funded.get('EXTERNAL_IDENTITY').relation,
        'AXF-140: nothing is withheld from a caller authorized for both sides, so absence is never reported as redaction'
      );
      Assert.isFalse(lookup.get(plans[3].Id).tied);
      Assert.isFalse(
        lookup.get(plans[0].Id).tied,
        'same relations but different date deltas: not a tie'
      );
      Assert.isTrue(
        lookup.get(plans[1].Id).lowEvidence,
        'nothing exact beyond holder/currency is explicit uncertainty'
      );
      Assert.isFalse(lookup.get(plans[3].Id).lowEvidence);
      Assert.isTrue(
        all.lowEvidenceCount >= 1,
        'low evidence counted: ' + all.lowEvidenceCount
      );
      // Persisted forecasts always precede virtual lines in the policy order.
      Integer lastPersisted = -1;
      Integer firstVirtual = all.items.size();
      for (Integer i = 0; i < all.items.size(); i++) {
        if (all.items[i].persisted) {
          lastPersisted = i;
        } else if (i < firstVirtual) {
          firstVirtual = i;
        }
      }
      Assert.isTrue(lastPersisted < firstVirtual, 'persisted before virtual');
      Assert.areEqual(
        plans[0].Id,
        page.items[1].targetId,
        'second slot is a persisted forecast'
      );
      Assert.isNull(
        funded.get('EXTERNAL_IDENTITY').sourceValue,
        'an unknown feature carries no value'
      );
      // AXF-140: a 200,00 forecast against a 150,00 source keeps 50,00 — explicit, never zeroed.
      Assert.areEqual(50, lookup.get(plans[1].Id).residualAfter);
      Assert.areEqual(
        ALT_CLS_MatchEvidence.STATE_PARTIAL,
        lookup.get(plans[1].Id).state,
        'policy §3: a non-zero residual remains PARTIAL'
      );
      for (ALT_CLS_SourceLinkService.CandidateView c : all.items) {
        // AXF-140: a linkable candidate left with a remainder is PARTIAL (policy §3), one the source
        // extinguishes exactly stays CONSULTATIVE, and a foreign-currency one is BLOCKED. None is
        // ever confirmed automatically.
        Assert.areEqual(
          c.currencyIso == 'BRL'
            ? (c.persisted &&
                c.residualAfter != null &&
                c.residualAfter > 0
                ? 'PARTIAL'
                : 'CONSULTATIVE')
            : 'BLOCKED',
          c.state,
          'nothing is confirmed automatically'
        );
        Assert.areEqual(9, c.evidence.size());
      }
      Assert.areEqual(
        1,
        searched.items.size(),
        'manual search narrows persisted forecasts'
      );
      Assert.areEqual(plans[0].Id, searched.items[0].targetId);
      Assert.areEqual(
        0,
        searched.virtualCount,
        'virtual lines carry no description'
      );
    }
  }

  @IsTest
  static void confirmLinksThroughRealizationReplaysAndConflictsWithoutTouchingTheFact() {
    System.runAs(byAlias('axf134g')) {
      Account owner = holder('Holder 134 confirm');
      AXF_OBJ_BankAccount__c available = bank(owner.Id, 'AVAILABLE', 'BRL');
      AXF_OBJ_BankAccountTransaction__c source = fact(
        available.Id,
        150,
        'POSTED',
        Date.today().addDays(-1),
        'confirm'
      );
      insert source;
      AXF_OBJ_FinancialTransaction__c target = plan(
        owner.Id,
        'target',
        200,
        'DEBIT',
        'BRL',
        Date.today()
      );
      insert target;
      ALT_CLS_SourceLinkService service = new ALT_CLS_SourceLinkService();

      // Deviation from the suggestion (150) without explicit review is refused.
      Assert.areEqual(
        'REVIEW_REQUIRED',
        failure(confirmInput(source, target.Id, 0, 100, 'first'))
      );
      ALT_CLS_SourceLinkService.ConfirmInput first = confirmInput(
        source,
        target.Id,
        0,
        100,
        'first'
      );
      first.changesReviewed = true;
      ALT_CLS_SourceLinkService.ConfirmResult linked = service.confirm(first);
      Test.startTest();
      ALT_CLS_SourceLinkService.ConfirmResult replayed = service.confirm(first);
      ALT_CLS_SourceLinkService.ConfirmInput divergent = confirmInput(
        source,
        target.Id,
        0,
        100.01,
        'first'
      );
      divergent.changesReviewed = true;
      String conflict = failure(divergent);
      // Versions moved: a stale draft conflicts, an aligned second link of the same pair is refused.
      ALT_CLS_SourceLinkService.ConfirmInput stale = confirmInput(
        source,
        target.Id,
        0,
        50,
        'second'
      );
      stale.changesReviewed = true;
      String staleCode = failure(stale);
      ALT_CLS_SourceLinkService.ConfirmInput again = confirmInput(
        source,
        target.Id,
        1,
        50,
        'second'
      );
      again.sourceVersion = 1;
      again.changesReviewed = true;
      String alreadyLinked = failure(again);
      Test.stopTest();
      // No candidate: the remaining 50 become an ACTUAL_ONLY plan born from the fact.
      ALT_CLS_SourceLinkService.ConfirmInput actual = confirmInput(
        source,
        null,
        null,
        50,
        'actual'
      );
      actual.sourceVersion = 1;
      ALT_CLS_SourceLinkService.ConfirmResult actualOnly = service.confirm(
        actual
      );

      Assert.isFalse(linked.replayed);
      Assert.areEqual(target.Id, linked.targetId);
      Assert.areEqual(100, linked.amount);
      Assert.areEqual('BRL', linked.currencyIso);
      Assert.isTrue(replayed.replayed, 'same key and payload replays');
      Assert.areEqual(linked.allocationId, replayed.allocationId);
      Assert.areEqual('CONFLICT', conflict, 'same key, divergent payload');
      Assert.areEqual('CONFLICT', staleCode, 'stale target version');
      Assert.areEqual('ALREADY_LINKED', alreadyLinked);
      Assert.isTrue(actualOnly.createdActualOnly);
      Assert.areNotEqual(target.Id, actualOnly.targetId);
      AXF_OBJ_ReconciliationAllocation__c allocation = [
        SELECT
          AXF_RA_LKP_BankTransaction__c,
          AXF_RA_LKP_CardTransaction__c,
          AXF_RA_LKP_ManualTransaction__c,
          AXF_RA_PKL_Kind__c,
          AXF_RA_NUM_Magnitude__c
        FROM AXF_OBJ_ReconciliationAllocation__c
        WHERE Id = :linked.allocationId
      ];
      Assert.areEqual(
        source.Id,
        allocation.AXF_RA_LKP_BankTransaction__c,
        'typed bank link'
      );
      Assert.isNull(allocation.AXF_RA_LKP_CardTransaction__c);
      Assert.isNull(allocation.AXF_RA_LKP_ManualTransaction__c);
      Assert.areEqual('APPLICATION', allocation.AXF_RA_PKL_Kind__c);
      Assert.areEqual(
        2,
        [SELECT COUNT() FROM AXF_OBJ_ReconciliationAllocation__c],
        'one link plus one actual-only application'
      );
      AXF_OBJ_BankAccountTransaction__c after = [
        SELECT
          AXF_BAT_NUM_Magnitude__c,
          AXF_BAT_TXT_Description__c,
          AXF_BAT_DAT_Date__c,
          AXF_BAT_PKL_Source__c,
          AXF_BAT_PKL_Status__c,
          AXF_BAT_NUM_Version__c
        FROM AXF_OBJ_BankAccountTransaction__c
        WHERE Id = :source.Id
      ];
      Assert.areEqual(
        150,
        after.AXF_BAT_NUM_Magnitude__c,
        'fact content untouched'
      );
      Assert.areEqual('Fact confirm', after.AXF_BAT_TXT_Description__c);
      Assert.areEqual('CSV', after.AXF_BAT_PKL_Source__c);
      Assert.areEqual('POSTED', after.AXF_BAT_PKL_Status__c);
      Assert.areEqual(
        2,
        after.AXF_BAT_NUM_Version__c,
        'only the optimistic version moved'
      );
      AXF_OBJ_FinancialTransaction__c born = [
        SELECT
          AXF_FTX_PKL_PlanKind__c,
          AXF_FTX_NUM_Magnitude__c,
          AXF_FTX_LKP_Account__c
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE Id = :actualOnly.targetId
      ];
      Assert.areEqual('ACTUAL_ONLY', born.AXF_FTX_PKL_PlanKind__c);
      Assert.areEqual(50, born.AXF_FTX_NUM_Magnitude__c);
      Assert.areEqual(owner.Id, born.AXF_FTX_LKP_Account__c);
      ALT_CLS_SourceLinkService.SourceView drained = service.readSource(
        source.Id,
        'BANK'
      );
      Assert.isTrue(
        drained.reasons.contains('SOURCE_EXHAUSTED'),
        drained.reasons + ''
      );
    }
  }

  @IsTest
  static void confirmRevalidatesEligibilityAndTargetsPersistingNothingOnFailure() {
    System.runAs(byAlias('axf134g')) {
      Account owner = holder('Holder 134 revalidate');
      AXF_OBJ_BankAccount__c available = bank(owner.Id, 'AVAILABLE', 'BRL');
      AXF_OBJ_BankAccount__c custody = bank(owner.Id, 'CUSTODY', 'BRL');
      List<AXF_OBJ_BankAccountTransaction__c> facts = new List<AXF_OBJ_BankAccountTransaction__c>{
        fact(available.Id, 100, 'POSTED', Date.today(), 'reviewed'),
        fact(available.Id, 100, 'PENDING', Date.today(), 'pending'),
        fact(custody.Id, 100, 'POSTED', Date.today(), 'custody'),
        fact(available.Id, 100, 'POSTED', Date.today(), 'good')
      };
      insert facts;
      AXF_OBJ_FinancialTransaction__c target = plan(
        owner.Id,
        'target',
        100,
        'DEBIT',
        'BRL',
        Date.today()
      );
      AXF_OBJ_FinancialTransaction__c cancelled = plan(
        owner.Id,
        'cancelled',
        100,
        'DEBIT',
        'BRL',
        Date.today()
      );
      cancelled.AXF_FTX_PKL_ScheduleState__c = 'CANCELLED';
      AXF_OBJ_FinancialTransaction__c credit = plan(
        owner.Id,
        'credit',
        100,
        'CREDIT',
        'BRL',
        Date.today()
      );
      AXF_OBJ_FinancialTransaction__c usd = plan(
        owner.Id,
        'usd',
        100,
        'DEBIT',
        'USD',
        Date.today()
      );
      AXF_OBJ_FinancialTransaction__c funded = plan(
        owner.Id,
        'funded',
        100,
        'DEBIT',
        'BRL',
        Date.today()
      );
      funded.AXF_FTX_LKP_BankAccount__c = custody.Id;
      insert new List<AXF_OBJ_FinancialTransaction__c>{
        target,
        cancelled,
        credit,
        usd,
        funded
      };
      ALT_CLS_SourceLinkService service = new ALT_CLS_SourceLinkService();
      // Candidates were listed while the fact was clean; a review opens before confirmation.
      ALT_CLS_SourceLinkService.CandidatePage draft = service.listCandidates(
        candidateQuery(facts[0].Id, 1, 10)
      );
      Assert.isTrue(draft.source.eligible);
      openReview(facts[0]);

      Test.startTest();
      Assert.areEqual(
        'REVIEW_OPEN',
        failure(confirmInput(facts[0], target.Id, 0, 100, 'reviewed'))
      );
      Assert.areEqual(
        'NOT_POSTED',
        failure(confirmInput(facts[1], target.Id, 0, 100, 'pending'))
      );
      Assert.areEqual(
        'FUNDING_NOT_AVAILABLE',
        failure(confirmInput(facts[2], target.Id, 0, 100, 'custody'))
      );
      Assert.areEqual(
        'TARGET_CANCELLED',
        failure(confirmInput(facts[3], cancelled.Id, 0, 100, 'cancelled'))
      );
      Assert.areEqual(
        'INVALID_TARGET',
        failure(confirmInput(facts[3], credit.Id, 0, 100, 'credit'))
      );
      Assert.areEqual(
        // AXF-140: with no usable quote for the pair, the refusal names the missing material rate
        // (what the user must correct) instead of the bare currency mismatch.
        'MISSING_MATERIAL_FX',
        failure(confirmInput(facts[3], usd.Id, 0, 100, 'usd'))
      );
      Assert.areEqual(
        'FUNDING_MISMATCH',
        failure(confirmInput(facts[3], funded.Id, 0, 100, 'funded'))
      );
      Assert.areEqual(
        'CONFLICT',
        failure(confirmInput(facts[3], target.Id, 7, 100, 'stale-target'))
      );
      ALT_CLS_SourceLinkService.ConfirmInput staleSource = confirmInput(
        facts[3],
        target.Id,
        0,
        100,
        'stale-source'
      );
      staleSource.sourceVersion = 3;
      Assert.areEqual('CONFLICT', failure(staleSource));
      ALT_CLS_SourceLinkService.ConfirmInput over = confirmInput(
        facts[3],
        target.Id,
        0,
        100.5,
        'over'
      );
      over.changesReviewed = true;
      Assert.areEqual('UNAVAILABLE_AMOUNT', failure(over));
      ALT_CLS_SourceLinkService.ConfirmInput badKey = confirmInput(
        facts[3],
        target.Id,
        0,
        100,
        ''
      );
      badKey.operationKey = null;
      Assert.areEqual('INVALID', failure(badKey));
      Test.stopTest();

      Assert.areEqual(
        0,
        [SELECT COUNT() FROM AXF_OBJ_ReconciliationAllocation__c],
        'no failed attempt persisted anything'
      );
      Assert.areEqual(
        0,
        [
          SELECT AXF_FTX_NUM_Version__c
          FROM AXF_OBJ_FinancialTransaction__c
          WHERE Id = :target.Id
        ]
        .AXF_FTX_NUM_Version__c
      );
      for (AXF_OBJ_BankAccountTransaction__c row : [
        SELECT AXF_BAT_NUM_Version__c
        FROM AXF_OBJ_BankAccountTransaction__c
      ]) {
        Assert.areEqual(0, row.AXF_BAT_NUM_Version__c, 'facts untouched');
      }
    }
  }

  @IsTest
  static void capabilityAndHolderAuthorizationFailClosedAndControllerSanitizes() {
    Account owner;
    AXF_OBJ_BankAccountTransaction__c source;
    System.runAs(byAlias('axf134g')) {
      owner = holder('Holder 134 private');
      AXF_OBJ_BankAccount__c available = bank(owner.Id, 'AVAILABLE', 'BRL');
      source = fact(available.Id, 100, 'POSTED', Date.today(), 'private');
      insert source;
    }
    Test.startTest();
    System.runAs(byAlias('axf134n')) {
      try {
        new ALT_CLS_SourceLinkService()
          .listSources(sourceQuery(owner.Id, 1, 10));
        Assert.fail('capability missing');
      } catch (ALT_CLS_SourceLinkService.SourceLinkException expected) {
        Assert.areEqual('UNAVAILABLE', expected.getMessage());
      }
      AXF_CLS_CTRL_SourceLink.Context context = AXF_CLS_CTRL_SourceLink.getContext(
        null
      );
      Assert.isFalse(context.canLink);
      Assert.areEqual(0, context.holders.size());
    }
    System.runAs(byAlias('axf134p')) {
      // Same capabilities, no sharing on the holder: nothing is disclosed.
      try {
        new ALT_CLS_SourceLinkService()
          .listSources(sourceQuery(owner.Id, 1, 10));
        Assert.fail('foreign holder');
      } catch (ALT_CLS_SourceLinkService.SourceLinkException expected) {
        Assert.areEqual('UNAVAILABLE', expected.getMessage());
      }
      try {
        new ALT_CLS_SourceLinkService().readSource(source.Id, 'BANK');
        Assert.fail('foreign fact');
      } catch (ALT_CLS_SourceLinkService.SourceLinkException expected) {
        Assert.areEqual('UNAVAILABLE', expected.getMessage());
      }
      try {
        AXF_CLS_CTRL_SourceLink.confirm(
          JSON.serialize(confirmInput(source, null, null, 100, 'foreign'))
        );
        Assert.fail('foreign confirm');
      } catch (AuraHandledException expected) {
        Assert.areEqual('UNAVAILABLE', expected.getMessage());
      }
    }
    System.runAs(byAlias('axf134g')) {
      AXF_CLS_CTRL_SourceLink.Context context = AXF_CLS_CTRL_SourceLink.getContext(
        null
      );
      Assert.isTrue(context.canLink);
      Assert.areEqual(
        ALT_CLS_SourceLinkService.POLICY_VERSION,
        context.policyVersion
      );
      try {
        AXF_CLS_CTRL_SourceLink.listSources('{"unknown":1}');
        Assert.fail('strict shape');
      } catch (AuraHandledException expected) {
        Assert.areEqual('INVALID_INPUT', expected.getMessage());
      }
      try {
        AXF_CLS_CTRL_SourceLink.listCandidates(
          JSON.serialize(candidateQuery(null, 1, 10))
        );
        Assert.fail('source required');
      } catch (AuraHandledException expected) {
        Assert.areEqual('INVALID_SOURCE', expected.getMessage());
      }
      ALT_CLS_SourceLinkService.SourcePage sources = AXF_CLS_CTRL_SourceLink.listSources(
        JSON.serialize(sourceQuery(owner.Id, 1, 10))
      );
      Assert.areEqual(1, sources.items.size());
      ALT_CLS_SourceLinkService.CandidatePage candidates = AXF_CLS_CTRL_SourceLink.listCandidates(
        JSON.serialize(candidateQuery(source.Id, 1, 10))
      );
      Assert.areEqual(0, candidates.items.size(), 'no forecast yet');
      ALT_CLS_SourceLinkService.ConfirmResult result = AXF_CLS_CTRL_SourceLink.confirm(
        JSON.serialize(confirmInput(source, null, null, 100, 'ctrl'))
      );
      Assert.isTrue(result.createdActualOnly);
      Assert.isNotNull(result.allocationId);
    }
    Test.stopTest();
  }

  private static AXF_OBJ_CreditCard__c card(Id accountId, String state) {
    AXF_OBJ_CreditCard__c result = new AXF_OBJ_CreditCard__c(
      AXF_CC_LKP_Account__c = accountId,
      AXF_CC_PKL_AvailabilityState__c = state,
      AXF_CC_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_CC_TXT_InstitutionName__c = 'Cartao Teste',
      AXF_CC_TXT_LastFourMasked__c = '9876'
    );
    insert result;
    return result;
  }

  private static AXF_OBJ_CreditCardTransaction__c cardFact(
    Id cardId,
    Decimal amount,
    String key
  ) {
    return new AXF_OBJ_CreditCardTransaction__c(
      AXF_CCT_MDR_CreditCard__c = cardId,
      AXF_CCT_NUM_Magnitude__c = amount,
      AXF_CCT_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_CCT_PKL_Direction__c = 'DEBIT',
      AXF_CCT_DAT_Date__c = Date.today(),
      AXF_CCT_TXT_Description__c = 'Card ' + key,
      AXF_CCT_EXI_SourceKey__c = 'axf134-card-' + key,
      AXF_CCT_PKL_Source__c = 'PLUGGY',
      AXF_CCT_PKL_Status__c = 'POSTED',
      AXF_CCT_NUM_Version__c = 0
    );
  }

  @IsTest
  static void cardSourceLinksThroughTypedCardAllocationAndFiltersWork() {
    System.runAs(byAlias('axf134g')) {
      Account owner = holder('Holder 134 card');
      AXF_OBJ_BankAccount__c bankAccount = bank(owner.Id, 'AVAILABLE', 'BRL');
      AXF_OBJ_CreditCard__c creditCard = card(owner.Id, 'AVAILABLE');
      AXF_OBJ_CreditCardTransaction__c source = cardFact(
        creditCard.Id,
        80,
        'src'
      );
      AXF_OBJ_CreditCardTransaction__c reviewedFact = cardFact(
        creditCard.Id,
        20,
        'rev'
      );
      insert new List<AXF_OBJ_CreditCardTransaction__c>{ source, reviewedFact };
      AXF_OBJ_BankAccountTransaction__c bankFact = fact(
        bankAccount.Id,
        100,
        'POSTED',
        Date.today(),
        'pct-100%'
      );
      bankFact.AXF_BAT_TXT_Description__c = 'Desconto 100% especial';
      insert bankFact;
      Date due = Date.today().addDays(3);
      List<AXF_OBJ_FinancialTransaction__c> plans = new List<AXF_OBJ_FinancialTransaction__c>{
        plan(owner.Id, 'card-funded', 80, 'DEBIT', 'BRL', due),
        plan(owner.Id, 'bank-funded', 80, 'DEBIT', 'BRL', due),
        plan(owner.Id, 'unfunded', 80, 'DEBIT', 'BRL', due)
      };
      plans[0].AXF_FTX_LKP_CreditCard__c = creditCard.Id;
      plans[1].AXF_FTX_LKP_BankAccount__c = bankAccount.Id;
      insert plans;
      // An OPEN review on a card fact blocks it exactly like a bank fact.
      System.runAs(new User(Id = UserInfo.getUserId())) {
        AXF_CLS_ReviewQueueTriggerHandler.guardEnabled = true;
        try {
          insert new AXF_OBJ_ReviewItem__c(
            AXF_RVI_PKL_Type__c = 'SOURCE_DELETE',
            AXF_RVI_PKL_State__c = 'OPEN',
            AXF_RVI_EXI_ReviewKey__c = 'axf134-card-review-' + reviewedFact.Id,
            AXF_RVI_NUM_Version__c = 0,
            AXF_RVI_LKP_CreditCardTransaction__c = reviewedFact.Id,
            AXF_RVI_LKP_CreditCard__c = creditCard.Id,
            AXF_RVI_DT_ObservedAt__c = System.now()
          );
        } finally {
          AXF_CLS_ReviewQueueTriggerHandler.guardEnabled = false;
        }
      }
      ALT_CLS_SourceLinkService service = new ALT_CLS_SourceLinkService();

      Test.startTest();
      ALT_CLS_SourceLinkService.SourceQuery cards = sourceQuery(
        owner.Id,
        1,
        10
      );
      cards.sourceKind = 'CARD';
      ALT_CLS_SourceLinkService.SourcePage cardPage = service.listSources(
        cards
      );
      ALT_CLS_SourceLinkService.SourceQuery banks = sourceQuery(
        owner.Id,
        1,
        10
      );
      banks.sourceKind = 'BANK';
      banks.term = '100%';
      ALT_CLS_SourceLinkService.SourcePage bankPage = service.listSources(
        banks
      );
      ALT_CLS_SourceLinkService.SourceQuery noMatch = sourceQuery(
        owner.Id,
        1,
        10
      );
      noMatch.term = '10%';
      ALT_CLS_SourceLinkService.SourcePage noMatchPage = service.listSources(
        noMatch
      );
      ALT_CLS_SourceLinkService.SourceQuery bad = sourceQuery(owner.Id, 1, 10);
      bad.sourceKind = 'CASH';
      String badKind;
      try {
        service.listSources(bad);
      } catch (ALT_CLS_SourceLinkService.SourceLinkException expected) {
        badKind = expected.getMessage();
      }
      ALT_CLS_SourceLinkService.CandidateQuery query = candidateQuery(
        source.Id,
        1,
        10
      );
      query.sourceKind = 'CARD';
      ALT_CLS_SourceLinkService.CandidatePage candidates = service.listCandidates(
        query
      );
      ALT_CLS_SourceLinkService.ConfirmInput input = new ALT_CLS_SourceLinkService.ConfirmInput();
      input.sourceId = source.Id;
      input.sourceKind = 'CARD';
      input.sourceVersion = 0;
      input.targetId = plans[0].Id;
      input.targetVersion = 0;
      input.amount = 80;
      input.recognitionDate = source.AXF_CCT_DAT_Date__c;
      input.operationKey = 'axf134-card-link';
      ALT_CLS_SourceLinkService.ConfirmResult linked = service.confirm(input);
      Test.stopTest();

      Assert.areEqual(1, cardPage.items.size(), 'only the clean card fact');
      Assert.areEqual(source.Id, cardPage.items[0].sourceId);
      Assert.areEqual('CARD', cardPage.items[0].sourceKind);
      Assert.areEqual(1, cardPage.excludedCount, 'reviewed card fact excluded');
      Assert.areEqual(
        1,
        bankPage.items.size(),
        'literal % matches the description'
      );
      Assert.areEqual(bankFact.Id, bankPage.items[0].sourceId);
      Assert.areEqual(
        0,
        noMatchPage.items.size(),
        'wildcard is not interpreted'
      );
      Assert.areEqual('INVALID_SOURCE', badKind);
      ALT_CLS_SourceLinkService.SourceView reviewedView = service.readSource(
        reviewedFact.Id,
        'CARD'
      );
      Assert.isTrue(
        reviewedView.reasons.contains('REVIEW_OPEN'),
        reviewedView.reasons + ''
      );
      Set<Id> offered = new Set<Id>();
      for (ALT_CLS_SourceLinkService.CandidateView c : candidates.items) {
        offered.add(c.targetId);
      }
      Assert.isTrue(
        offered.contains(plans[0].Id),
        'plan funded by the same card'
      );
      Assert.isTrue(offered.contains(plans[2].Id), 'unfunded plan');
      Assert.isFalse(
        offered.contains(plans[1].Id),
        'plan funded by a bank account'
      );
      AXF_OBJ_ReconciliationAllocation__c allocation = [
        SELECT AXF_RA_LKP_CardTransaction__c, AXF_RA_LKP_BankTransaction__c
        FROM AXF_OBJ_ReconciliationAllocation__c
        WHERE Id = :linked.allocationId
      ];
      Assert.areEqual(
        source.Id,
        allocation.AXF_RA_LKP_CardTransaction__c,
        'typed card link'
      );
      Assert.isNull(allocation.AXF_RA_LKP_BankTransaction__c);
      ALT_CLS_SourceLinkService.ConfirmInput mismatch = new ALT_CLS_SourceLinkService.ConfirmInput();
      mismatch.sourceId = reviewedFact.Id;
      mismatch.sourceKind = 'CARD';
      mismatch.sourceVersion = 0;
      mismatch.targetId = plans[1].Id;
      mismatch.targetVersion = 0;
      mismatch.amount = 20;
      mismatch.recognitionDate = Date.today();
      mismatch.operationKey = 'axf134-card-mismatch';
      Assert.areEqual(
        'REVIEW_OPEN',
        failure(mismatch),
        'card fact revalidated'
      );
    }
  }

  @IsTest
  static void verificationTruncationAndTargetRulesFailClosed() {
    Account owner;
    AXF_OBJ_BankAccountTransaction__c shared;
    AXF_OBJ_FinancialTransaction__c sharedPlan;
    System.runAs(byAlias('axf134p')) {
      owner = holder('Holder 134 peer');
      AXF_OBJ_BankAccount__c peerBank = bank(owner.Id, 'AVAILABLE', 'BRL');
      shared = fact(peerBank.Id, 100, 'POSTED', Date.today(), 'peer');
      insert shared;
      sharedPlan = plan(
        owner.Id,
        'peer-plan',
        100,
        'DEBIT',
        'BRL',
        Date.today()
      );
      insert sharedPlan;
      ALT_CLS_RealizationService.Input link = new ALT_CLS_RealizationService.Input();
      link.targetId = sharedPlan.Id;
      link.targetVersion = 0;
      link.sourceId = shared.Id;
      link.sourceKind = 'BANK';
      link.sourceVersion = 0;
      link.amount = 30;
      link.recognitionDate = Date.today();
      link.operationKey = 'axf134-peer-link';
      new ALT_CLS_RealizationService().apply(link);
      // Holder, bank account and plan shared with the gestor; the allocation stays private.
      insert new AccountShare(
        AccountId = owner.Id,
        UserOrGroupId = byAlias('axf134g').Id,
        AccountAccessLevel = 'Read',
        OpportunityAccessLevel = 'None',
        CaseAccessLevel = 'None'
      );
      insert new AXF_OBJ_BankAccount__Share(
        ParentId = peerBank.Id,
        UserOrGroupId = byAlias('axf134g').Id,
        AccessLevel = 'Read'
      );
      insert new AXF_OBJ_FinancialTransaction__Share(
        ParentId = sharedPlan.Id,
        UserOrGroupId = byAlias('axf134g').Id,
        AccessLevel = 'Read'
      );
    }
    System.runAs(byAlias('axf134g')) {
      ALT_CLS_SourceLinkService service = new ALT_CLS_SourceLinkService();
      ALT_CLS_SourceLinkService.SourceView hidden = service.readSource(
        shared.Id,
        'BANK'
      );
      Assert.isTrue(
        hidden.reasons.contains('ALLOCATIONS_UNVERIFIED'),
        'a private allocation withholds the fact: ' + hidden.reasons
      );
      Assert.isNull(
        hidden.residual,
        'no residual is derived from hidden effects'
      );
      Assert.isFalse(hidden.eligible);

      // Own data: realized target, date-only deviation, scan truncation.
      Account mine = holder('Holder 134 mine');
      AXF_OBJ_BankAccount__c myBank = bank(mine.Id, 'AVAILABLE', 'BRL');
      AXF_OBJ_BankAccountTransaction__c source = fact(
        myBank.Id,
        100,
        'POSTED',
        Date.today(),
        'mine'
      );
      insert source;
      AXF_OBJ_FinancialTransaction__c realized = plan(
        mine.Id,
        'realized',
        50,
        'DEBIT',
        'BRL',
        Date.today()
      );
      insert realized;
      ALT_CLS_RealizationService.Input drain = new ALT_CLS_RealizationService.Input();
      drain.targetId = realized.Id;
      drain.targetVersion = 0;
      drain.sourceKind = 'CASH';
      drain.amount = 50;
      drain.recognitionDate = Date.today();
      drain.operationKey = 'axf134-mine-drain';
      new ALT_CLS_RealizationService().apply(drain);
      List<AXF_OBJ_FinancialTransaction__c> many = new List<AXF_OBJ_FinancialTransaction__c>();
      for (Integer i = 0; i < ALT_CLS_SourceLinkService.MAX_SCAN + 1; i++) {
        many.add(
          plan(
            mine.Id,
            'many-' + i,
            100,
            'DEBIT',
            'BRL',
            Date.today().addDays(i)
          )
        );
      }
      insert many;
      Test.startTest();
      Assert.areEqual(
        'TARGET_REALIZED',
        failure(confirmInput(source, realized.Id, 1, 50, 'realized'))
      );
      ALT_CLS_SourceLinkService.ConfirmInput dateOnly = confirmInput(
        source,
        many[0].Id,
        0,
        100,
        'date-only'
      );
      dateOnly.recognitionDate = Date.today().addDays(1);
      Assert.areEqual(
        'REVIEW_REQUIRED',
        failure(dateOnly),
        'a changed date alone needs explicit review'
      );
      ALT_CLS_SourceLinkService.ConfirmInput over = confirmInput(
        source,
        realized.Id,
        1,
        10,
        'over'
      );
      over.changesReviewed = true;
      Assert.areEqual('TARGET_REALIZED', failure(over));
      // A service instance caches the authorized scope per request: new holder, new instance.
      ALT_CLS_SourceLinkService.CandidatePage page = new ALT_CLS_SourceLinkService()
        .listCandidates(candidateQuery(source.Id, 1, 50));
      Test.stopTest();
      Assert.isTrue(
        page.scanTruncated,
        'more than MAX_SCAN forecasts were scanned'
      );
      Assert.areEqual(ALT_CLS_SourceLinkService.MAX_SCAN, page.maxScan);
      Assert.isTrue(page.items.size() <= ALT_CLS_SourceLinkService.MAX_PAGE);
      Assert.areEqual(
        0,
        [
          SELECT COUNT()
          FROM AXF_OBJ_ReconciliationAllocation__c
          WHERE AXF_RA_LKP_BankTransaction__c = :source.Id
        ],
        'nothing persisted by the refused commands'
      );
    }
  }

  private static void quote(
    String baseIso,
    String quoteIso,
    Decimal rate,
    Datetime effectiveAt,
    String key,
    String side
  ) {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert new AXF_OBJ_ExchangeRate__c(
        AXF_EXR_TXT_BaseCurrency__c = baseIso,
        AXF_EXR_TXT_QuoteCurrency__c = quoteIso,
        AXF_EXR_NUM_Rate__c = rate,
        AXF_EXR_PKL_Side__c = side,
        AXF_EXR_TXT_Provider__c = ALT_CLS_IndicativeEquivalenceService.PROVIDER_BCB_PTAX,
        AXF_EXR_DT_EffectiveDateTime__c = effectiveAt,
        AXF_EXR_EXI_RateKey__c = 'axf140-' + key
      );
    }
  }

  /**
   * AXF-140 AC-1/AC-2: the evidence of a partial or foreign-currency candidate stays separated
   * (original, available, currency, conversion, remainder), a non-zero remainder is never zeroed
   * by an invented tolerance, and a pair without material FX evidence blocks confirmation.
   */
  @IsTest
  static void partialAndMultiCurrencyCandidatesSeparateFactsAndBlockWithoutMaterialFx() {
    System.runAs(byAlias('axf134g')) {
      Account owner = holder('Holder 140 candidates');
      AXF_OBJ_BankAccount__c available = bank(owner.Id, 'AVAILABLE', 'BRL');
      AXF_OBJ_BankAccountTransaction__c source = fact(
        available.Id,
        100,
        'POSTED',
        Date.today(),
        'axf140'
      );
      insert source;
      Date due = Date.today().addDays(2);
      List<AXF_OBJ_FinancialTransaction__c> plans = new List<AXF_OBJ_FinancialTransaction__c>{
        plan(owner.Id, 'covered', 80, 'DEBIT', 'BRL', due),
        plan(owner.Id, 'partial', 100.01, 'DEBIT', 'BRL', due),
        plan(owner.Id, 'usd', 100, 'DEBIT', 'USD', due),
        plan(owner.Id, 'eur', 100, 'DEBIT', 'EUR', due)
      };
      insert plans;
      // Older than the approved indicative limit (AXF-92): fetched, reported as a fact, never used.
      quote('EUR', 'BRL', 6.10, System.now().addDays(-8), 'stale-eur', 'SELL');
      ALT_CLS_SourceLinkService service = new ALT_CLS_SourceLinkService();

      Test.startTest();
      ALT_CLS_SourceLinkService.CandidatePage page = service.listCandidates(
        candidateQuery(source.Id, 1, 50)
      );
      String usdWithoutQuote = failure(
        confirmInput(source, plans[2].Id, 0, 100, 'usd-none')
      );
      Test.stopTest();

      CandidateViewByTarget byTarget = new CandidateViewByTarget(page.items);
      ALT_CLS_SourceLinkService.CandidateView covered = byTarget.get(
        plans[0].Id
      );
      Assert.areEqual(80, covered.amount, 'original amount');
      Assert.areEqual(
        80,
        covered.residual,
        'available amount, kept apart from the original'
      );
      Assert.areEqual('BRL', covered.currencyIso);
      Assert.areEqual(
        0,
        covered.residualAfter,
        'the source extinguishes it exactly'
      );
      Assert.areEqual('CONSULTATIVE', covered.state);
      Assert.isTrue(covered.linkable);
      Assert.isNull(
        covered.conversion,
        'no conversion is invented in one currency'
      );

      ALT_CLS_SourceLinkService.CandidateView partial = byTarget.get(
        plans[1].Id
      );
      Assert.areEqual(100.01, partial.amount, 'original amount');
      Assert.areEqual(100.01, partial.residual, 'available amount');
      Assert.areEqual(
        0.01,
        partial.residualAfter,
        'the remainder stays explicit: no approved tolerance turns it into zero'
      );
      Assert.areEqual(
        ALT_CLS_MatchEvidence.STATE_PARTIAL,
        partial.state,
        'policy §3: a non-zero residual remains PARTIAL, inspectable and open for a draft allocation'
      );
      Assert.isTrue(partial.linkable);

      for (Id foreignId : new List<Id>{ plans[2].Id, plans[3].Id }) {
        ALT_CLS_SourceLinkService.CandidateView foreign = byTarget.get(
          foreignId
        );
        Assert.areEqual(
          'BLOCKED',
          foreign.state,
          'another currency cannot reach completion under exact currency arithmetic'
        );
        Assert.isFalse(
          foreign.linkable,
          'a blocked candidate is never selectable'
        );
        Assert.isTrue(
          foreign.reasons.contains('CURRENCY_MISMATCH'),
          foreign.reasons + ''
        );
        Assert.areEqual(
          foreign.amount,
          foreign.conversion.originalAmount,
          'the original amount is preserved, never converted in place'
        );
        Assert.areEqual(foreign.currencyIso, foreign.conversion.originalIso);
        Assert.areEqual(
          'BRL',
          foreign.conversion.reportingIso,
          'compared in the source currency'
        );
        Assert.isNull(
          foreign.residualAfter,
          'a cross-currency remainder is unknown, never zero'
        );
      }
      ALT_CLS_SourceLinkService.CandidateView usd = byTarget.get(plans[2].Id);
      Assert.areEqual(
        ALT_CLS_IndicativeEquivalenceService.STATE_UNAVAILABLE,
        usd.conversion.state
      );
      Assert.isTrue(
        usd.reasons.contains('MISSING_MATERIAL_FX'),
        usd.reasons + ''
      );
      Assert.isNull(usd.conversion.rate, 'no rate is invented');
      Assert.isNull(
        usd.conversion.convertedAmount,
        'an absent rate never becomes a converted zero'
      );
      ALT_CLS_SourceLinkService.CandidateView eur = byTarget.get(plans[3].Id);
      Assert.areEqual(
        ALT_CLS_IndicativeEquivalenceService.STATE_STALE,
        eur.conversion.state,
        'older than the approved limit'
      );
      Assert.areEqual(
        6.10,
        eur.conversion.rate,
        'the stale rate travels as a fact'
      );
      Assert.isNull(
        eur.conversion.convertedAmount,
        'but never as a converted amount'
      );
      Assert.isTrue(
        eur.reasons.contains('MISSING_MATERIAL_FX'),
        eur.reasons + ''
      );
      Assert.areEqual(
        'MISSING_MATERIAL_FX',
        usdWithoutQuote,
        'a missing material rate blocks confirmation'
      );

      quote('USD', 'BRL', 5.05, System.now(), 'fresh-usd', 'SELL');
      ALT_CLS_SourceLinkService.CandidatePage repriced = service.listCandidates(
        candidateQuery(source.Id, 1, 50)
      );
      ALT_CLS_SourceLinkService.CandidateView priced = new CandidateViewByTarget(
          repriced.items
        )
        .get(plans[2].Id);
      Assert.areEqual(
        ALT_CLS_IndicativeEquivalenceService.STATE_ESTIMATED,
        priced.conversion.state
      );
      Assert.areEqual(5.05, priced.conversion.rate);
      Assert.areEqual(
        505.00,
        priced.conversion.convertedAmount,
        'original × rate at the display scale, original untouched'
      );
      Assert.areEqual(
        ALT_CLS_IndicativeEquivalenceService.PROVIDER_BCB_PTAX,
        priced.conversion.provider
      );
      Assert.isNotNull(priced.conversion.effectiveAt);
      Assert.isFalse(
        priced.reasons.contains('MISSING_MATERIAL_FX'),
        'the rate is now material'
      );
      Assert.areEqual(
        'BLOCKED',
        priced.state,
        'a rate never turns a currency mismatch into a linkable candidate'
      );
      Assert.areEqual(
        'CURRENCY_MISMATCH',
        failure(confirmInput(source, plans[2].Id, 0, 100, 'usd-priced')),
        'exact currency arithmetic still refuses the confirmation'
      );
    }
  }

  /**
   * AXF-140 AC-3: absence is `UNKNOWN`, never `REDACTED` — the caller is authorized for the fact and
   * for the holder of every candidate it is shown, so this workbench withholds nothing — and the page
   * keeps naming the policy and the cutoff so the human decision stays explicit and auditable. The
   * genuinely withheld case (assertion, not absence) is covered at the contract level in
   * `ALT_CLS_MatchEvidenceTest.withheldIdentityIsRedactedAndCannotOrder`.
   */
  @IsTest
  static void absentIdentityStaysUnknownAndTheDecisionStaysAuditable() {
    System.runAs(byAlias('axf134g')) {
      Account owner = holder('Holder 140 withheld');
      AXF_OBJ_BankAccount__c available = bank(owner.Id, 'AVAILABLE', 'BRL');
      AXF_OBJ_BankAccountTransaction__c source = fact(
        available.Id,
        100,
        'POSTED',
        Date.today(),
        'withheld'
      );
      insert source;
      insert plan(
        owner.Id,
        'withheld-plan',
        100,
        'DEBIT',
        'BRL',
        Date.today().addDays(1)
      );
      Test.startTest();
      ALT_CLS_SourceLinkService.CandidatePage page = new ALT_CLS_SourceLinkService()
        .listCandidates(candidateQuery(source.Id, 1, 10));
      Test.stopTest();
      Map<String, ALT_CLS_MatchEvidence.EvidenceView> features = new Map<String, ALT_CLS_MatchEvidence.EvidenceView>();
      for (ALT_CLS_MatchEvidence.EvidenceView v : page.items[0].evidence) {
        features.put(v.feature, v);
      }
      Assert.areEqual(
        ALT_CLS_MatchEvidence.REL_UNKNOWN,
        features.get('EXTERNAL_IDENTITY').relation,
        'the fact carries a provider key and the forecast carries none: absence is UNKNOWN'
      );
      Assert.areEqual(
        'EXTERNAL_IDENTITY_UNKNOWN',
        features.get('EXTERNAL_IDENTITY').explanation
      );
      Assert.areNotEqual(
        ALT_CLS_MatchEvidence.REL_REDACTED,
        features.get('EXTERNAL_IDENTITY').relation,
        'nothing is withheld from an authorized caller, so absence is never reported as redaction'
      );
      Assert.isNull(features.get('EXTERNAL_IDENTITY').sourceValue);
      Assert.isNull(features.get('EXTERNAL_IDENTITY').candidateValue);
      Assert.areEqual(1, page.items.size());
      Assert.areEqual(
        ALT_CLS_MatchEvidence.STATE_CONSULTATIVE,
        page.items[0].state
      );
      Assert.areEqual(
        ALT_CLS_MatchEvidence.MATCHING_POLICY,
        page.matchingPolicy,
        'the declaring policy travels with the decision'
      );
      Assert.isNotNull(
        page.evidenceCutoff,
        'the evidence cutoff travels with it'
      );
      Assert.areEqual(
        ALT_CLS_MatchEvidence.FEATURES.size(),
        page.items[0].evidence.size(),
        'absence is reported feature by feature, never dropped'
      );
    }
  }

  /**
   * AXF-140 AC-1/AC-2 continued: a foreign-currency candidate is BLOCKED and never selectable, so it
   * must not consume the scan window that decides which linkable forecasts are seen at all.
   */
  @IsTest
  static void blockedCurrenciesDoNotCrowdOutTheLinkableScanWindow() {
    System.runAs(byAlias('axf134g')) {
      Account owner = holder('Holder 140 scan');
      AXF_OBJ_BankAccount__c available = bank(owner.Id, 'AVAILABLE', 'BRL');
      AXF_OBJ_BankAccountTransaction__c source = fact(
        available.Id,
        100,
        'POSTED',
        Date.today(),
        'axf140-scan'
      );
      insert source;
      // More foreign-currency forecasts than one window holds, all due before the linkable ones, so
      // a single shared window would push the linkable forecasts past MAX_SCAN.
      List<AXF_OBJ_FinancialTransaction__c> foreign = new List<AXF_OBJ_FinancialTransaction__c>();
      for (Integer i = 0; i < ALT_CLS_SourceLinkService.MAX_SCAN; i++) {
        foreign.add(
          plan(
            owner.Id,
            'usd-' + i,
            100,
            'DEBIT',
            'USD',
            Date.today().addDays(-30)
          )
        );
      }
      insert foreign;
      List<AXF_OBJ_FinancialTransaction__c> linkable = new List<AXF_OBJ_FinancialTransaction__c>{
        plan(owner.Id, 'brl-1', 100, 'DEBIT', 'BRL', Date.today().addDays(1)),
        plan(owner.Id, 'brl-2', 100, 'DEBIT', 'BRL', Date.today().addDays(2)),
        plan(owner.Id, 'brl-3', 100, 'DEBIT', 'BRL', Date.today().addDays(3))
      };
      for (AXF_OBJ_FinancialTransaction__c row : linkable) {
        // Funded by the source's own account: the exact source identity leads the presentation order.
        row.AXF_FTX_LKP_BankAccount__c = available.Id;
      }
      insert linkable;

      Test.startTest();
      ALT_CLS_SourceLinkService.CandidatePage page = new ALT_CLS_SourceLinkService()
        .listCandidates(candidateQuery(source.Id, 1, 50));
      Test.stopTest();

      Set<Id> linkableIds = new Set<Id>();
      Integer linkableShown = 0;
      Integer blockedShown = 0;
      for (ALT_CLS_SourceLinkService.CandidateView c : page.items) {
        if (c.currencyIso == 'BRL') {
          linkableIds.add(c.targetId);
          linkableShown++;
          Assert.isTrue(c.linkable, 'a same-currency candidate stays linkable');
          continue;
        }
        blockedShown++;
        Assert.isFalse(
          c.linkable,
          'a foreign-currency candidate is never selectable'
        );
        Assert.areEqual(ALT_CLS_MatchEvidence.STATE_BLOCKED, c.state);
      }
      Assert.areEqual(
        new Set<Id>{ linkable[0].Id, linkable[1].Id, linkable[2].Id },
        linkableIds,
        'every linkable forecast is still offered: blocked rows never consume its scan window'
      );
      Assert.areEqual(3, linkableShown);
      Assert.isTrue(
        blockedShown > 0,
        'the blocked foreign-currency candidates are still listed'
      );
    }
  }

  /**
   * AXF-140 AC-2: the selected quote is the newest of the approved side and is chosen
   * deterministically; a newest non-positive rate leaves the pair unusable instead of silently
   * falling back to an older, superseded quote.
   */
  @IsTest
  static void quoteSelectionFollowsTheApprovedSideAndNeverFallsBackToAnOlderQuote() {
    System.runAs(byAlias('axf134g')) {
      Account owner = holder('Holder 140 quotes');
      AXF_OBJ_BankAccount__c available = bank(owner.Id, 'AVAILABLE', 'BRL');
      // DEBIT source: the approved FX layer converts an outflow at the SELL quote.
      AXF_OBJ_BankAccountTransaction__c source = fact(
        available.Id,
        100,
        'POSTED',
        Date.today(),
        'axf140-quotes'
      );
      insert source;
      Date due = Date.today().addDays(2);
      List<AXF_OBJ_FinancialTransaction__c> plans = new List<AXF_OBJ_FinancialTransaction__c>{
        plan(owner.Id, 'usd-zero', 100, 'DEBIT', 'USD', due),
        plan(owner.Id, 'eur-tie', 100, 'DEBIT', 'EUR', due),
        plan(owner.Id, 'gbp-buy-only', 100, 'DEBIT', 'GBP', due)
      };
      insert plans;
      // USD: the newest quote of the pair has no usable rate; the older positive one must not stand
      // in for it.
      quote('USD', 'BRL', 5.0, System.now().addDays(-2), 'usd-old', 'SELL');
      quote('USD', 'BRL', 0, System.now().addMinutes(-30), 'usd-zero', 'SELL');
      // EUR: two quotes of the same pair and side at the same instant — the choice is deterministic.
      Datetime tiedAt = System.now().addHours(-3);
      quote('EUR', 'BRL', 6.20, tiedAt, 'eur-a', 'SELL');
      quote('EUR', 'BRL', 6.30, tiedAt, 'eur-b', 'SELL');
      // GBP: only the opposite side is published, so the DEBIT source has no usable quote.
      quote('GBP', 'BRL', 7.0, System.now().addMinutes(-30), 'gbp-buy', 'BUY');
      List<AXF_OBJ_ExchangeRate__c> tied = [
        SELECT Id, AXF_EXR_NUM_Rate__c
        FROM AXF_OBJ_ExchangeRate__c
        WHERE AXF_EXR_EXI_RateKey__c IN ('axf140-eur-a', 'axf140-eur-b')
        ORDER BY Id ASC
      ];
      Assert.areEqual(2, tied.size(), 'both competing quotes exist');
      Decimal deterministic = tied[0].AXF_EXR_NUM_Rate__c;
      ALT_CLS_SourceLinkService service = new ALT_CLS_SourceLinkService();

      Test.startTest();
      CandidateViewByTarget byTarget = new CandidateViewByTarget(
        service.listCandidates(candidateQuery(source.Id, 1, 50)).items
      );
      // A second read of the same data picks the same quote: selection is deterministic.
      CandidateViewByTarget again = new CandidateViewByTarget(
        service.listCandidates(candidateQuery(source.Id, 1, 50)).items
      );
      String usdBlocked = failure(
        confirmInput(source, plans[0].Id, 0, 100, 'usd-zero')
      );
      String gbpBlocked = failure(
        confirmInput(source, plans[2].Id, 0, 100, 'gbp-buy')
      );
      Test.stopTest();

      ALT_CLS_SourceLinkService.CandidateView usd = byTarget.get(plans[0].Id);
      Assert.areEqual(
        ALT_CLS_IndicativeEquivalenceService.STATE_UNAVAILABLE,
        usd.conversion.state,
        'a non-positive newest rate leaves the pair unusable'
      );
      Assert.isNull(
        usd.conversion.rate,
        'the superseded older quote is never presented as the current one'
      );
      Assert.isNull(usd.conversion.convertedAmount);
      Assert.isTrue(
        usd.reasons.contains('MISSING_MATERIAL_FX'),
        usd.reasons + ''
      );
      Assert.areEqual(
        'MISSING_MATERIAL_FX',
        usdBlocked,
        'without a usable quote the confirmation is refused, never converted at an old rate'
      );

      ALT_CLS_SourceLinkService.CandidateView eur = byTarget.get(plans[1].Id);
      Assert.areEqual(
        ALT_CLS_IndicativeEquivalenceService.STATE_ESTIMATED,
        eur.conversion.state
      );
      Assert.areEqual(
        deterministic,
        eur.conversion.rate,
        'competing quotes at the same instant resolve by record identity, not by read order'
      );
      Assert.areEqual(
        deterministic,
        again.get(plans[1].Id).conversion.rate,
        'the selection is stable across reads'
      );

      ALT_CLS_SourceLinkService.CandidateView gbp = byTarget.get(plans[2].Id);
      Assert.areEqual(
        ALT_CLS_IndicativeEquivalenceService.STATE_UNAVAILABLE,
        gbp.conversion.state,
        'the BUY quote is not the approved side for an outflow'
      );
      Assert.isTrue(
        gbp.reasons.contains('MISSING_MATERIAL_FX'),
        gbp.reasons + ''
      );
      Assert.areEqual('MISSING_MATERIAL_FX', gbpBlocked);

      // The same pair with the approved side published is usable again.
      quote(
        'GBP',
        'BRL',
        7.10,
        System.now().addMinutes(-20),
        'gbp-sell',
        'SELL'
      );
      ALT_CLS_SourceLinkService.CandidateView repriced = new CandidateViewByTarget(
          service.listCandidates(candidateQuery(source.Id, 1, 50)).items
        )
        .get(plans[2].Id);
      Assert.areEqual(
        ALT_CLS_IndicativeEquivalenceService.STATE_ESTIMATED,
        repriced.conversion.state
      );
      Assert.areEqual(7.10, repriced.conversion.rate);
    }
  }

  private class CandidateViewByTarget {
    private Map<Id, ALT_CLS_SourceLinkService.CandidateView> rows = new Map<Id, ALT_CLS_SourceLinkService.CandidateView>();
    public CandidateViewByTarget(
      List<ALT_CLS_SourceLinkService.CandidateView> items
    ) {
      for (ALT_CLS_SourceLinkService.CandidateView c : items) {
        if (c.targetId != null) {
          rows.put(c.targetId, c);
        }
      }
    }
    public ALT_CLS_SourceLinkService.CandidateView get(Id targetId) {
      Assert.isTrue(
        rows.containsKey(targetId),
        'candidate present: ' + targetId
      );
      return rows.get(targetId);
    }
  }
}
