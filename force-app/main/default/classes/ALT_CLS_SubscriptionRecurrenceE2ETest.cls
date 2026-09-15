/**
 * @description AXF-110 ponta a ponta: fatos bancarios reais persistidos, observados pelo S1
 * (AXF-109) e entregues ao matcher pelo mapeamento do S1, produzindo um unico candidato mensal
 * com evidencia e proxima estimativa.
 *
 * Este teste existe porque os testes puros nao provam a costura S1 -> S2: uma observacao real tem
 * identidade de transacao propria por cobranca e a fonte de pagamento estavel vem do vinculo da
 * transacao com a conta/cartao. Se o matcher agrupasse pela identidade da transacao, cada stream
 * teria uma unica cobranca e nunca qualificaria.
 */
@IsTest
private class ALT_CLS_SubscriptionRecurrenceE2ETest {
  private static User gestor() {
    return [SELECT Id FROM User WHERE Alias = 'axf110g' LIMIT 1];
  }

  @TestSetup
  static void setup() {
    Id profileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1]
    .Id;
    User gestor = new User(
      Alias = 'axf110g',
      Email = 'axf110g@example.invalid',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Recurrence Gestor',
      LanguageLocaleKey = 'pt_BR',
      LocaleSidKey = 'pt_BR',
      TimeZoneSidKey = 'America/Sao_Paulo',
      ProfileId = profileId,
      Username = 'axf110g.' + System.now().getTime() + '@example.invalid'
    );
    insert gestor;
    List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (PermissionSet permission : [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'AXF_PS_GestorFinanceiro'
    ]) {
      assignments.add(
        new PermissionSetAssignment(
          AssigneeId = gestor.Id,
          PermissionSetId = permission.Id
        )
      );
    }
    insert assignments;
  }

  private static Account holder(String name) {
    Account holder = new Account(
      Name = name,
      RecordTypeId = Account.SObjectType.getDescribe()
        .getRecordTypeInfosByDeveloperName()
        .get('AXF_Business')
        .getRecordTypeId()
    );
    insert holder;
    return holder;
  }

  private static AXF_OBJ_BankAccount__c bank(Id holderId, String key) {
    AXF_OBJ_BankAccount__c bank = new AXF_OBJ_BankAccount__c(
      AXF_BA_LKP_Account__c = holderId,
      AXF_BA_PKL_AvailabilityState__c = 'AVAILABLE',
      AXF_BA_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BA_TXT_InstitutionName__c = 'Banco ' + key,
      AXF_BA_TXT_NumberMasked__c = '****' + key,
      AXF_BA_EXI_ManualKey__c = 'e2e-' + key + '-' + System.now().getTime(),
      AXF_BA_NUM_Version__c = 0
    );
    insert bank;
    return bank;
  }

  private static AXF_OBJ_BankAccountTransaction__c fact(
    Id bankId,
    String key,
    Date chargedOn,
    Decimal magnitude
  ) {
    return new AXF_OBJ_BankAccountTransaction__c(
      AXF_BAT_MDR_BankAccount__c = bankId,
      AXF_BAT_EXI_SourceKey__c = 'e2e-' + key + '-' + System.now().getTime(),
      AXF_BAT_PKL_Source__c = 'PLUGGY',
      AXF_BAT_DAT_Date__c = chargedOn,
      AXF_BAT_NUM_Magnitude__c = magnitude,
      AXF_BAT_PKL_Direction__c = 'DEBIT',
      AXF_BAT_PKL_Status__c = 'POSTED',
      AXF_BAT_TXT_RawSourceStatus__c = 'POSTED',
      AXF_BAT_TXT_OperationType__c = 'OUTROS',
      AXF_BAT_TXT_ProviderCategory__c = 'Entertainment > Streaming subscription',
      AXF_BAT_TXT_CurrencyIsoCode__c = 'BRL',
      AXF_BAT_TXT_Description__c = 'NETFLIX.COM  ASSINATURA',
      AXF_BAT_DTM_ImportedAt__c = Datetime.now(),
      AXF_BAT_NUM_Version__c = 0
    );
  }

  @IsTest
  static void observedHistoryProducesOneMonthlyCandidateEndToEnd() {
    System.runAs(gestor()) {
      Account account = holder('E2E Holder');
      AXF_OBJ_BankAccount__c bank = bank(account.Id, 'e2e');
      List<AXF_OBJ_BankAccountTransaction__c> facts = new List<AXF_OBJ_BankAccountTransaction__c>{
        fact(bank.Id, 'june', Date.newInstance(2025, 6, 5), 109.90),
        fact(bank.Id, 'july', Date.newInstance(2025, 7, 5), 109.90),
        fact(bank.Id, 'august', Date.newInstance(2025, 8, 5), 109.90)
      };
      insert facts;
      List<Id> factIds = new List<Id>();
      for (AXF_OBJ_BankAccountTransaction__c row : facts) {
        factIds.add(row.Id);
      }

      Test.startTest();
      ALT_CLS_TransactionObservationService.ObserveInput observeInput = new ALT_CLS_TransactionObservationService.ObserveInput();
      observeInput.accountId = account.Id;
      observeInput.factIds = factIds;
      ALT_CLS_TransactionObservationService.ObserveResult observed = new ALT_CLS_TransactionObservationService()
        .observe(observeInput);

      // Contrato do chamador: a fonte de pagamento estavel acompanha a consulta das observacoes.
      List<AXF_OBJ_TransactionObservation__c> rows = [
        SELECT
          Id,
          AXF_TOB_EXI_ObservationKey__c,
          AXF_TOB_LKP_Account__c,
          AXF_TOB_TXT_SourceIdentity__c,
          AXF_TOB_NUM_Revision__c,
          AXF_TOB_TXT_CurrencyIsoCode__c,
          AXF_TOB_TXT_NormalizedMerchant__c,
          AXF_TOB_PKL_Eligibility__c,
          AXF_TOB_PKL_ServiceHint__c,
          AXF_TOB_PKL_Direction__c,
          AXF_TOB_DAT_Date__c,
          AXF_TOB_NUM_Magnitude__c,
          AXF_TOB_LKP_BankTransaction__r.AXF_BAT_MDR_BankAccount__c
        FROM AXF_OBJ_TransactionObservation__c
        WHERE Id IN :observed.observationIds
      ];

      ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateInput evaluateInput = new ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateInput();
      evaluateInput.ownerId = account.Id;
      evaluateInput.observations = ALT_CLS_SubscriptionRecurrenceMatcher.fromObservations(
        rows
      );
      ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateResult result = ALT_CLS_SubscriptionRecurrenceMatcher.evaluate(
        evaluateInput
      );
      Test.stopTest();

      Assert.areEqual(3, result.eligibleObservations);
      Assert.areEqual(0, result.ineligibleObservations);
      Assert.areEqual(
        1,
        result.qualifiedStreams,
        'the observed history must produce exactly one monthly candidate'
      );
      ALT_CLS_SubscriptionRecurrenceMatcher.StreamAssignment stream = result.streams[0];
      Assert.areEqual(
        ALT_CLS_SubscriptionRecurrenceMatcher.MONTHLY,
        stream.cadence
      );
      Assert.areEqual(Date.newInstance(2025, 6, 5), stream.anchorDate);
      Assert.areEqual(109.90, stream.referenceAmount);
      Assert.areEqual(3, stream.evidence.size());
      Assert.areEqual(Date.newInstance(2025, 9, 5), stream.nextEstimateDate);
      Assert.areEqual(
        String.valueOf(bank.Id),
        stream.paymentSourceId,
        'the stable payment source comes from the transaction relationship'
      );
    }
  }

  @IsTest
  static void excludedAndUnknownSettlementNeverReachTheCandidateEndToEnd() {
    System.runAs(gestor()) {
      Account account = holder('E2E Quarantine');
      AXF_OBJ_BankAccount__c bank = bank(account.Id, 'e2eq');
      AXF_OBJ_BankAccountTransaction__c eligible = fact(
        bank.Id,
        'q-june',
        Date.newInstance(2025, 6, 5),
        109.90
      );
      eligible.AXF_BAT_TXT_Description__c = 'NETFLIX.COM ASSINATURA';
      AXF_OBJ_BankAccountTransaction__c unknown = fact(
        bank.Id,
        'q-july',
        Date.newInstance(2025, 7, 5),
        109.90
      );
      unknown.AXF_BAT_TXT_RawSourceStatus__c = 'PROCESSING';
      AXF_OBJ_BankAccountTransaction__c payment = fact(
        bank.Id,
        'q-august',
        Date.newInstance(2025, 8, 5),
        109.90
      );
      payment.AXF_BAT_TXT_Description__c = 'PAGAMENTO DE FATURA CARTAO';
      insert new List<AXF_OBJ_BankAccountTransaction__c>{
        eligible,
        unknown,
        payment
      };

      Test.startTest();
      ALT_CLS_TransactionObservationService.ObserveInput observeInput = new ALT_CLS_TransactionObservationService.ObserveInput();
      observeInput.accountId = account.Id;
      observeInput.factIds = new List<Id>{
        eligible.Id,
        unknown.Id,
        payment.Id
      };
      ALT_CLS_TransactionObservationService.ObserveResult observed = new ALT_CLS_TransactionObservationService()
        .observe(observeInput);
      List<AXF_OBJ_TransactionObservation__c> rows = [
        SELECT
          Id,
          AXF_TOB_EXI_ObservationKey__c,
          AXF_TOB_LKP_Account__c,
          AXF_TOB_TXT_SourceIdentity__c,
          AXF_TOB_NUM_Revision__c,
          AXF_TOB_TXT_CurrencyIsoCode__c,
          AXF_TOB_TXT_NormalizedMerchant__c,
          AXF_TOB_PKL_Eligibility__c,
          AXF_TOB_PKL_ServiceHint__c,
          AXF_TOB_PKL_Direction__c,
          AXF_TOB_DAT_Date__c,
          AXF_TOB_NUM_Magnitude__c,
          AXF_TOB_LKP_BankTransaction__r.AXF_BAT_MDR_BankAccount__c
        FROM AXF_OBJ_TransactionObservation__c
        WHERE Id IN :observed.observationIds
      ];

      ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateInput evaluateInput = new ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateInput();
      evaluateInput.ownerId = account.Id;
      evaluateInput.observations = ALT_CLS_SubscriptionRecurrenceMatcher.fromObservations(
        rows
      );
      ALT_CLS_SubscriptionRecurrenceMatcher.EvaluateResult result = ALT_CLS_SubscriptionRecurrenceMatcher.evaluate(
        evaluateInput
      );
      Test.stopTest();

      Assert.areEqual(
        0,
        result.qualifiedStreams,
        'quarantined and excluded settlement cannot build a candidate'
      );
      Assert.areEqual(
        1,
        result.eligibleObservations,
        'only the settled service debit is eligible'
      );
      Assert.areEqual(2, result.ineligibleObservations);
    }
  }
}
