/**
 * @description Adapter de observacao de fatos importados (AXF-109, S1 de AXF-108, gate G1).
 * Congela o mapeamento fisico: fatos BAT/CCT -> AXF_OBJ_TransactionObservation__c com
 * identidade tipada da fonte, data/moeda/magnitude/direcao originais, elegibilidade
 * deterministica (P3) com proveniencia de status e de classificacao, fingerprint de conteudo e
 * revisoes imutaveis. Regras versionadas (CLASSIFICATION_VERSION); nao ha casamento de
 * recorrencia, confirmacao automatica nem projecao aqui (S2+).
 *
 * Elegibilidade: so um debito liquidado na fonte (status bruto POSTED) sem exclusao conhecida e
 * ELIGIBLE. Status ausente/nao reconhecido/pendente = UNKNOWN (quarentena) e nunca e promovido
 * por classificacao de estabelecimento. Parcelamentos, transferencias, pagamento de fatura,
 * estornos, creditos e categorias de consumo/seguro/emprestimo/imposto = EXCLUDED.
 * Indicio de servico so com categoria/identidade do provedor; Amazon/Google genericos = NONE.
 */
public with sharing class ALT_CLS_TransactionObservationService {
  public static final String CLASSIFICATION_VERSION = 'evidence-classification@1.0.0';
  public static final String CP_OBSERVE = 'AXF_CanObserveTransactions';
  public static final String ELIGIBLE = 'ELIGIBLE';
  public static final String EXCLUDED = 'EXCLUDED';
  public static final String UNKNOWN = 'UNKNOWN';

  private static Boolean writing = false;
  public static Boolean isWriting() {
    return writing;
  }

  private static final Set<String> TRANSFER_OPERATIONS = new Set<String>{
    'PIX',
    'TED',
    'DOC',
    'TRANSFER',
    'TRANSFERENCIA'
  };
  private static final Map<String, String> CATEGORY_EXCLUSIONS = new Map<String, String>{
    'UTILIT' => 'UTILITY',
    'ENERGIA' => 'UTILITY',
    'AGUA' => 'UTILITY',
    'GAS' => 'UTILITY',
    'TELEFON' => 'UTILITY',
    'INSURANCE' => 'INSURANCE',
    'SEGURO' => 'INSURANCE',
    'LOAN' => 'LOAN_OR_TAX',
    'EMPRESTIMO' => 'LOAN_OR_TAX',
    'FINANCIAMENTO' => 'LOAN_OR_TAX',
    'TAX' => 'LOAN_OR_TAX',
    'IMPOSTO' => 'LOAN_OR_TAX',
    'TRANSFER' => 'TRANSFER',
    'CREDIT CARD PAYMENT' => 'INVOICE_PAYMENT',
    'PAGAMENTO DE CARTAO' => 'INVOICE_PAYMENT'
  };
  private static final List<String> SERVICE_CATEGORY_MARKERS = new List<String>{
    'SUBSCRIPTION',
    'ASSINATURA',
    'STREAMING',
    'SOFTWARE',
    'DIGITAL SERVICE',
    'SERVICO DIGITAL',
    'ONLINE SERVICE'
  };
  private static final List<String> INVOICE_PAYMENT_MARKERS = new List<String>{
    'PAGAMENTO FATURA',
    'PAGTO FATURA',
    'PAG FATURA',
    'PAGAMENTO CARTAO',
    'PAGAMENTO DE FATURA',
    'CREDIT CARD PAYMENT'
  };
  private static final List<String> REVERSAL_MARKERS = new List<String>{
    'ESTORNO',
    'REVERS',
    'CHARGEBACK',
    'CANCELAMENTO'
  };
  private static final List<String> GENERIC_MERCHANTS = new List<String>{
    'AMAZON',
    'GOOGLE'
  };

  public class ObservationException extends Exception {
    public String code;
  }

  public class ObserveInput {
    public Id accountId;
    public List<Id> factIds;
  }

  public class ObserveResult {
    public Integer observed = 0;
    public Integer created = 0;
    public Integer unchanged = 0;
    public Map<String, Integer> byEligibility = new Map<String, Integer>{
      ELIGIBLE => 0,
      EXCLUDED => 0,
      UNKNOWN => 0
    };
    public List<Id> observationIds = new List<Id>();
  }

  private class Fact {
    Id id;
    String kind; // BANK | CARD
    Id accountId;
    String sourceKey;
    Date bookedOn;
    String currencyIso;
    Decimal magnitude;
    String direction;
    String description;
    String rawStatus;
    String operationType;
    String category;
    String merchant;
    Decimal totalInstallments;
  }

  private class Classification {
    String eligibility = UNKNOWN;
    String exclusion = 'NONE';
    String statusProvenance;
    String classificationProvenance = 'NONE';
    String serviceHint = 'NONE';
    String merchantEvidence;
  }

  /**
   * Observes the given facts of one authorized holder context. Facts outside that context, not
   * accessible or of an unsupported type reject the whole request (no partial observation).
   */
  public ObserveResult observe(ObserveInput input) {
    if (
      input == null ||
      input.accountId == null ||
      input.factIds == null ||
      input.factIds.isEmpty()
    ) {
      throw failure('INVALID_INPUT');
    }
    if (!FeatureManagement.checkPermission(CP_OBSERVE)) {
      throw failure('FORBIDDEN');
    }
    List<Account> holders = [
      SELECT Id, OwnerId
      FROM Account
      WHERE Id = :input.accountId
      WITH USER_MODE
      LIMIT 1
    ];
    if (holders.isEmpty()) {
      throw failure('NOT_ACCESSIBLE');
    }
    Map<Id, Fact> facts = loadFacts(input.factIds);
    for (Id factId : input.factIds) {
      Fact fact = facts.get(factId);
      if (fact == null) {
        // Same answer whether the fact does not exist, is not shared or is not a typed fact.
        throw failure('NOT_ACCESSIBLE');
      }
      if (fact.accountId != input.accountId) {
        throw failure('CONTEXT_MISMATCH');
      }
    }
    Map<String, AXF_OBJ_TransactionObservation__c> latest = latestBySource(
      facts.values()
    );
    List<AXF_OBJ_TransactionObservation__c> rows = new List<AXF_OBJ_TransactionObservation__c>();
    ObserveResult result = new ObserveResult();
    Datetime now = Datetime.now();
    for (Id factId : input.factIds) {
      Fact fact = facts.get(factId);
      String identity = sourceIdentity(fact);
      String normalized = normalize(fact.description);
      String fingerprint = fingerprint(fact, normalized);
      AXF_OBJ_TransactionObservation__c previous = latest.get(identity);
      result.observed++;
      if (
        previous != null &&
        previous.AXF_TOB_TXT_ContentFingerprint__c == fingerprint
      ) {
        result.unchanged++;
        result.observationIds.add(previous.Id);
        count(result, previous.AXF_TOB_PKL_Eligibility__c);
        continue;
      }
      Integer revision = previous == null
        ? 1
        : Integer.valueOf(previous.AXF_TOB_NUM_Revision__c) + 1;
      Classification classification = classify(fact, normalized);
      rows.add(
        new AXF_OBJ_TransactionObservation__c(
          AXF_TOB_LKP_BankTransaction__c = fact.kind == 'BANK' ? fact.id : null,
          AXF_TOB_LKP_CardTransaction__c = fact.kind == 'CARD' ? fact.id : null,
          AXF_TOB_LKP_Account__c = fact.accountId,
          AXF_TOB_TXT_SourceIdentity__c = identity,
          AXF_TOB_NUM_Revision__c = revision,
          AXF_TOB_EXI_ObservationKey__c = AXF_CLS_IdentityFraming.key(
            new List<Object>{ identity, revision }
          ),
          AXF_TOB_TXT_ContentFingerprint__c = fingerprint,
          AXF_TOB_DAT_Date__c = fact.bookedOn,
          AXF_TOB_TXT_CurrencyIsoCode__c = fact.currencyIso,
          AXF_TOB_NUM_Magnitude__c = fact.magnitude,
          AXF_TOB_PKL_Direction__c = fact.direction,
          AXF_TOB_TXT_NormalizedMerchant__c = normalized,
          AXF_TOB_TXT_NormalizationVersion__c = AXF_CLS_TextNormalization.POLICY_VERSION,
          AXF_TOB_PKL_Eligibility__c = classification.eligibility,
          AXF_TOB_PKL_ExclusionReason__c = classification.exclusion,
          AXF_TOB_PKL_StatusProvenance__c = classification.statusProvenance,
          AXF_TOB_TXT_RawSourceStatus__c = fact.rawStatus,
          AXF_TOB_PKL_ClassificationProvenance__c = classification.classificationProvenance,
          AXF_TOB_PKL_ServiceHint__c = classification.serviceHint,
          AXF_TOB_TXT_ClassificationVersion__c = CLASSIFICATION_VERSION,
          AXF_TOB_TXT_MerchantEvidence__c = classification.merchantEvidence,
          AXF_TOB_DT_ObservedAt__c = now,
          OwnerId = holders[0].OwnerId
        )
      );
      count(result, classification.eligibility);
    }
    if (rows.isEmpty()) {
      return result;
    }
    Savepoint point = Database.setSavepoint();
    try {
      writing = true;
      Database.insert(rows, AccessLevel.USER_MODE);
    } catch (Exception failure) {
      Database.rollback(point);
      throw failure;
    } finally {
      writing = false;
    }
    for (AXF_OBJ_TransactionObservation__c row : rows) {
      result.created++;
      result.observationIds.add(row.Id);
    }
    return result;
  }

  // ---------------------------------------------------------------- classification (P3, versioned)

  @TestVisible
  private static Classification classify(Fact fact, String normalized) {
    Classification result = new Classification();
    String status = fact.rawStatus == null
      ? null
      : fact.rawStatus.trim().toUpperCase();
    if (String.isBlank(status)) {
      result.statusProvenance = 'STATUS_MISSING';
    } else if (status == 'PENDING') {
      result.statusProvenance = 'SOURCE_PENDING';
    } else if (status == 'POSTED') {
      result.statusProvenance = 'SOURCE_POSTED';
    } else {
      result.statusProvenance = 'STATUS_UNRECOGNIZED';
    }
    String category = fact.category == null ? '' : fact.category.toUpperCase();
    String merchant = fact.merchant == null ? '' : fact.merchant.toUpperCase();
    String upper = normalized == null ? '' : normalized.toUpperCase();
    String operation = fact.operationType == null
      ? ''
      : fact.operationType.toUpperCase();
    result.merchantEvidence = String.isBlank(fact.merchant)
      ? (String.isBlank(fact.category) ? null : fact.category.left(255))
      : (fact.merchant +
          (String.isBlank(fact.category) ? '' : ' | ' + fact.category))
          .left(255);

    // Exclusions are determined from retained evidence, in a fixed order.
    if (fact.direction == 'CREDIT') {
      return exclude(result, 'CREDIT', 'DESCRIPTION_RULE');
    }
    if (fact.totalInstallments != null && fact.totalInstallments > 1) {
      return exclude(result, 'INSTALLMENT', 'PROVIDER_CATEGORY');
    }
    for (String marker : REVERSAL_MARKERS) {
      if (upper.contains(marker)) {
        return exclude(result, 'REVERSAL', 'DESCRIPTION_RULE');
      }
    }
    for (String marker : INVOICE_PAYMENT_MARKERS) {
      if (upper.contains(marker) || category.contains(marker)) {
        return exclude(
          result,
          'INVOICE_PAYMENT',
          upper.contains(marker) ? 'DESCRIPTION_RULE' : 'PROVIDER_CATEGORY'
        );
      }
    }
    if (TRANSFER_OPERATIONS.contains(operation)) {
      return exclude(result, 'TRANSFER', 'OPERATION_TYPE');
    }
    for (String marker : CATEGORY_EXCLUSIONS.keySet()) {
      if (category.contains(marker)) {
        return exclude(
          result,
          CATEGORY_EXCLUSIONS.get(marker),
          'PROVIDER_CATEGORY'
        );
      }
    }
    // Service hint needs provider category or merchant identity; a generic merchant name alone is not evidence.
    Boolean categorySaysService = false;
    for (String marker : SERVICE_CATEGORY_MARKERS) {
      if (category.contains(marker)) {
        categorySaysService = true;
      }
    }
    if (categorySaysService) {
      result.serviceHint = 'SERVICE_CANDIDATE';
      result.classificationProvenance = 'PROVIDER_CATEGORY';
    } else if (String.isNotBlank(merchant) && !isGeneric(merchant)) {
      result.serviceHint = 'SERVICE_CANDIDATE';
      result.classificationProvenance = 'MERCHANT_IDENTITY';
    }
    // Settlement decides eligibility; a hint never upgrades an unknown status.
    result.eligibility = result.statusProvenance == 'SOURCE_POSTED'
      ? ELIGIBLE
      : UNKNOWN;
    return result;
  }

  private static Classification exclude(
    Classification result,
    String reason,
    String provenance
  ) {
    result.eligibility = EXCLUDED;
    result.exclusion = reason;
    result.classificationProvenance = provenance;
    result.serviceHint = 'NONE';
    return result;
  }

  private static Boolean isGeneric(String merchant) {
    for (String generic : GENERIC_MERCHANTS) {
      if (merchant.startsWith(generic)) {
        return true;
      }
    }
    return false;
  }

  // ---------------------------------------------------------------- helpers

  private Map<Id, Fact> loadFacts(List<Id> ids) {
    Map<Id, Fact> result = new Map<Id, Fact>();
    Set<Id> bankIds = new Set<Id>();
    Set<Id> cardIds = new Set<Id>();
    for (Id id : ids) {
      if (
        id.getSObjectType() == AXF_OBJ_BankAccountTransaction__c.SObjectType
      ) {
        bankIds.add(id);
      } else if (
        id.getSObjectType() == AXF_OBJ_CreditCardTransaction__c.SObjectType
      ) {
        cardIds.add(id);
      }
    }
    if (!bankIds.isEmpty()) {
      for (AXF_OBJ_BankAccountTransaction__c row : [
        SELECT
          Id,
          AXF_BAT_EXI_SourceKey__c,
          AXF_BAT_DAT_Date__c,
          AXF_BAT_TXT_CurrencyIsoCode__c,
          AXF_BAT_NUM_Magnitude__c,
          AXF_BAT_PKL_Direction__c,
          AXF_BAT_TXT_Description__c,
          AXF_BAT_TXT_RawSourceStatus__c,
          AXF_BAT_TXT_OperationType__c,
          AXF_BAT_TXT_ProviderCategory__c,
          AXF_BAT_MDR_BankAccount__r.AXF_BA_LKP_Account__c
        FROM AXF_OBJ_BankAccountTransaction__c
        WHERE Id IN :bankIds
        WITH USER_MODE
      ]) {
        Fact fact = new Fact();
        fact.id = row.Id;
        fact.kind = 'BANK';
        fact.accountId = row.AXF_BAT_MDR_BankAccount__r?.AXF_BA_LKP_Account__c;
        fact.sourceKey = row.AXF_BAT_EXI_SourceKey__c;
        fact.bookedOn = row.AXF_BAT_DAT_Date__c;
        fact.currencyIso = row.AXF_BAT_TXT_CurrencyIsoCode__c;
        fact.magnitude = row.AXF_BAT_NUM_Magnitude__c;
        fact.direction = row.AXF_BAT_PKL_Direction__c;
        fact.description = row.AXF_BAT_TXT_Description__c;
        fact.rawStatus = row.AXF_BAT_TXT_RawSourceStatus__c;
        fact.operationType = row.AXF_BAT_TXT_OperationType__c;
        fact.category = row.AXF_BAT_TXT_ProviderCategory__c;
        result.put(row.Id, fact);
      }
    }
    if (!cardIds.isEmpty()) {
      for (AXF_OBJ_CreditCardTransaction__c row : [
        SELECT
          Id,
          AXF_CCT_EXI_SourceKey__c,
          AXF_CCT_DAT_Date__c,
          AXF_CCT_TXT_CurrencyIsoCode__c,
          AXF_CCT_NUM_Magnitude__c,
          AXF_CCT_PKL_Direction__c,
          AXF_CCT_TXT_Description__c,
          AXF_CCT_TXT_RawSourceStatus__c,
          AXF_CCT_TXT_OperationType__c,
          AXF_CCT_TXT_ProviderCategory__c,
          AXF_CCT_TXT_MerchantName__c,
          AXF_CCT_NUM_TotalInstallments__c,
          AXF_CCT_MDR_CreditCard__r.AXF_CC_LKP_Account__c
        FROM AXF_OBJ_CreditCardTransaction__c
        WHERE Id IN :cardIds
        WITH USER_MODE
      ]) {
        Fact fact = new Fact();
        fact.id = row.Id;
        fact.kind = 'CARD';
        fact.accountId = row.AXF_CCT_MDR_CreditCard__r?.AXF_CC_LKP_Account__c;
        fact.sourceKey = row.AXF_CCT_EXI_SourceKey__c;
        fact.bookedOn = row.AXF_CCT_DAT_Date__c;
        fact.currencyIso = row.AXF_CCT_TXT_CurrencyIsoCode__c;
        fact.magnitude = row.AXF_CCT_NUM_Magnitude__c;
        fact.direction = row.AXF_CCT_PKL_Direction__c;
        fact.description = row.AXF_CCT_TXT_Description__c;
        fact.rawStatus = row.AXF_CCT_TXT_RawSourceStatus__c;
        fact.operationType = row.AXF_CCT_TXT_OperationType__c;
        fact.category = row.AXF_CCT_TXT_ProviderCategory__c;
        fact.merchant = row.AXF_CCT_TXT_MerchantName__c;
        fact.totalInstallments = row.AXF_CCT_NUM_TotalInstallments__c;
        result.put(row.Id, fact);
      }
    }
    return result;
  }

  private Map<String, AXF_OBJ_TransactionObservation__c> latestBySource(
    List<Fact> facts
  ) {
    Set<String> identities = new Set<String>();
    for (Fact fact : facts) {
      identities.add(sourceIdentity(fact));
    }
    Map<String, AXF_OBJ_TransactionObservation__c> result = new Map<String, AXF_OBJ_TransactionObservation__c>();
    for (AXF_OBJ_TransactionObservation__c row : [
      SELECT
        Id,
        AXF_TOB_TXT_SourceIdentity__c,
        AXF_TOB_NUM_Revision__c,
        AXF_TOB_TXT_ContentFingerprint__c,
        AXF_TOB_PKL_Eligibility__c
      FROM AXF_OBJ_TransactionObservation__c
      WHERE AXF_TOB_TXT_SourceIdentity__c IN :identities
      WITH USER_MODE
      ORDER BY AXF_TOB_NUM_Revision__c ASC
    ]) {
      result.put(row.AXF_TOB_TXT_SourceIdentity__c, row);
    }
    return result;
  }

  private static String sourceIdentity(Fact fact) {
    String key = String.isBlank(fact.sourceKey)
      ? String.valueOf(fact.id)
      : fact.sourceKey;
    return (fact.kind + ':' + key).left(128);
  }

  private static String normalize(String description) {
    String normalized = AXF_CLS_TextNormalization.normalize(description);
    return normalized == null ? null : normalized.left(255);
  }

  private static String fingerprint(Fact fact, String normalized) {
    return AXF_CLS_IdentityFraming.key(
      new List<Object>{
        CLASSIFICATION_VERSION,
        String.valueOf(fact.bookedOn),
        fact.currencyIso,
        String.valueOf(fact.magnitude),
        fact.direction,
        normalized,
        fact.rawStatus,
        fact.operationType,
        String.valueOf(fact.totalInstallments),
        fact.category,
        fact.merchant
      }
    );
  }

  private static void count(ObserveResult result, String eligibility) {
    result.byEligibility.put(
      eligibility,
      result.byEligibility.get(eligibility) + 1
    );
  }

  private static ObservationException failure(String code) {
    ObservationException result = new ObservationException(code);
    result.code = code;
    return result;
  }
}
