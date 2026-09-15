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

  /** Largest request accepted in one call (rows are inserted all-or-none). */
  public static final Integer MAX_BATCH = 500;

  /**
   * Rules are evaluated on the normalized text (diacritics folded, upper-cased, tokens split on
   * non-alphanumerics) in declaration order, so precedence is explicit and 'TAX' never matches
   * 'TAXI'. Modes: TOKEN = whole token, PREFIX = token starts with, PHRASE = contiguous words.
   */
  private class Rule {
    final String marker;
    final String reason;
    final String mode;
    Rule(String marker, String reason, String mode) {
      this.marker = marker;
      this.reason = reason;
      this.mode = mode;
    }
  }
  private static final Set<String> TRANSFER_OPERATIONS = new Set<String>{
    'PIX',
    'TED',
    'DOC',
    'TRANSFER',
    'TRANSFERENCIA'
  };
  private static final List<Rule> CATEGORY_EXCLUSIONS = new List<Rule>{
    new Rule('CREDIT CARD PAYMENT', 'INVOICE_PAYMENT', 'PHRASE'),
    new Rule('PAGAMENTO DE CARTAO', 'INVOICE_PAYMENT', 'PHRASE'),
    new Rule('PAGAMENTO CARTAO', 'INVOICE_PAYMENT', 'PHRASE'),
    new Rule('TRANSFER', 'TRANSFER', 'TOKEN'),
    new Rule('TRANSFERENCIA', 'TRANSFER', 'TOKEN'),
    new Rule('UTILIT', 'UTILITY', 'PREFIX'),
    new Rule('ENERGIA', 'UTILITY', 'TOKEN'),
    new Rule('ELECTRICITY', 'UTILITY', 'TOKEN'),
    new Rule('AGUA', 'UTILITY', 'TOKEN'),
    new Rule('WATER', 'UTILITY', 'TOKEN'),
    // 'GAS' alone is ambiguous (gas bill vs. gas station); only the utility phrasing excludes.
    new Rule('GAS BILL', 'UTILITY', 'PHRASE'),
    new Rule('CONTA DE GAS', 'UTILITY', 'PHRASE'),
    new Rule('GAS NATURAL', 'UTILITY', 'PHRASE'),
    new Rule('TELEFON', 'UTILITY', 'PREFIX'),
    new Rule('INSURANCE', 'INSURANCE', 'TOKEN'),
    new Rule('SEGURO', 'INSURANCE', 'TOKEN'),
    new Rule('SEGUROS', 'INSURANCE', 'TOKEN'),
    new Rule('LOAN', 'LOAN_OR_TAX', 'TOKEN'),
    new Rule('LOANS', 'LOAN_OR_TAX', 'TOKEN'),
    new Rule('EMPRESTIMO', 'LOAN_OR_TAX', 'TOKEN'),
    new Rule('EMPRESTIMOS', 'LOAN_OR_TAX', 'TOKEN'),
    new Rule('FINANCIAMENTO', 'LOAN_OR_TAX', 'TOKEN'),
    new Rule('TAX', 'LOAN_OR_TAX', 'TOKEN'),
    new Rule('TAXES', 'LOAN_OR_TAX', 'TOKEN'),
    new Rule('IMPOSTO', 'LOAN_OR_TAX', 'TOKEN'),
    new Rule('IMPOSTOS', 'LOAN_OR_TAX', 'TOKEN')
  };
  private static final List<Rule> SERVICE_CATEGORY_MARKERS = new List<Rule>{
    new Rule('SUBSCRIPTION', 'SERVICE', 'PREFIX'),
    new Rule('ASSINATURA', 'SERVICE', 'PREFIX'),
    new Rule('STREAMING', 'SERVICE', 'TOKEN'),
    new Rule('SOFTWARE', 'SERVICE', 'TOKEN'),
    new Rule('DIGITAL SERVICE', 'SERVICE', 'PHRASE'),
    new Rule('SERVICO DIGITAL', 'SERVICE', 'PHRASE'),
    new Rule('ONLINE SERVICE', 'SERVICE', 'PHRASE')
  };
  private static final List<Rule> INVOICE_PAYMENT_MARKERS = new List<Rule>{
    new Rule('PAGAMENTO FATURA', 'INVOICE_PAYMENT', 'PHRASE'),
    new Rule('PAGTO FATURA', 'INVOICE_PAYMENT', 'PHRASE'),
    new Rule('PAG FATURA', 'INVOICE_PAYMENT', 'PHRASE'),
    new Rule('PAGAMENTO CARTAO', 'INVOICE_PAYMENT', 'PHRASE'),
    new Rule('PAGAMENTO DE FATURA', 'INVOICE_PAYMENT', 'PHRASE'),
    new Rule('CREDIT CARD PAYMENT', 'INVOICE_PAYMENT', 'PHRASE')
  };
  private static final List<Rule> REVERSAL_MARKERS = new List<Rule>{
    new Rule('ESTORNO', 'REVERSAL', 'TOKEN'),
    new Rule('REVERS', 'REVERSAL', 'PREFIX'),
    new Rule('CHARGEBACK', 'REVERSAL', 'TOKEN'),
    new Rule('CANCELAMENTO', 'REVERSAL', 'TOKEN')
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
    /** Latest observation per fact (created or reused). */
    public Map<Id, Id> observationByFact = new Map<Id, Id>();
    /** Same ids, in the order of the deduplicated input. */
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
    Decimal installmentNumber;
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
    List<Id> factIds = new List<Id>();
    Set<Id> seen = new Set<Id>();
    for (Id factId : input.factIds) {
      if (factId == null) {
        throw failure('INVALID_INPUT');
      }
      if (seen.add(factId)) {
        factIds.add(factId);
      }
    }
    if (factIds.size() > MAX_BATCH) {
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
    Map<Id, Fact> facts = loadFacts(factIds);
    for (Id factId : factIds) {
      Fact fact = facts.get(factId);
      if (fact == null) {
        // Same answer whether the fact does not exist, is not shared or is not a typed fact.
        throw failure('NOT_ACCESSIBLE');
      }
      if (fact.accountId != input.accountId) {
        throw failure('CONTEXT_MISMATCH');
      }
      if (
        fact.bookedOn == null ||
        String.isBlank(fact.currencyIso) ||
        fact.magnitude == null ||
        String.isBlank(fact.direction)
      ) {
        // The observation copies the original values; a fact missing one cannot be observed.
        throw failure('INCOMPLETE_FACT');
      }
    }
    Map<String, ALT_CLS_TransactionObservationIntegrity.Latest> latest = ALT_CLS_TransactionObservationIntegrity.latest(
      identities(facts.values())
    );
    List<AXF_OBJ_TransactionObservation__c> rows = new List<AXF_OBJ_TransactionObservation__c>();
    ObserveResult result = new ObserveResult();
    Datetime now = Datetime.now();
    for (Id factId : factIds) {
      Fact fact = facts.get(factId);
      String identity = sourceIdentity(fact);
      String normalized = normalize(fact.description);
      String fingerprint = fingerprint(fact, normalized);
      ALT_CLS_TransactionObservationIntegrity.Latest previous = latest.get(
        identity
      );
      result.observed++;
      if (previous != null && previous.fingerprint == fingerprint) {
        result.unchanged++;
        result.observationIds.add(previous.id);
        result.observationByFact.put(factId, previous.id);
        count(result, previous.eligibility);
        continue;
      }
      Integer revision = previous == null ? 1 : previous.revision + 1;
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
    } catch (DmlException dml) {
      Database.rollback(point);
      if (dml.getDmlType(0) == StatusCode.DUPLICATE_VALUE) {
        // Another observer wrote the same revision first: the caller replays and gets it.
        throw failure('CONCURRENT_REVISION');
      }
      throw dml;
    } catch (Exception failure) {
      Database.rollback(point);
      throw failure;
    } finally {
      writing = false;
    }
    for (AXF_OBJ_TransactionObservation__c row : rows) {
      result.created++;
      result.observationIds.add(row.Id);
      Id factId = row.AXF_TOB_LKP_BankTransaction__c != null
        ? row.AXF_TOB_LKP_BankTransaction__c
        : row.AXF_TOB_LKP_CardTransaction__c;
      result.observationByFact.put(factId, row.Id);
    }
    return result;
  }

  // ---------------------------------------------------------------- classification (P3, versioned)

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
    String category = fold(fact.category);
    String merchant = fold(fact.merchant);
    String upper = normalized == null ? '' : normalized.toUpperCase();
    String operation = fold(fact.operationType);
    result.merchantEvidence = String.isBlank(fact.merchant)
      ? (String.isBlank(fact.category) ? null : fact.category.left(255))
      : (fact.merchant +
          (String.isBlank(fact.category) ? '' : ' | ' + fact.category))
          .left(255);

    // Exclusions are determined from retained evidence, in a fixed order.
    if (fact.direction == 'CREDIT') {
      return exclude(result, 'CREDIT', 'SOURCE_FIELD');
    }
    if (
      (fact.totalInstallments != null && fact.totalInstallments > 1) ||
      (fact.installmentNumber != null &&
      fact.installmentNumber > 1)
    ) {
      return exclude(result, 'INSTALLMENT', 'SOURCE_FIELD');
    }
    if (firstMatch(REVERSAL_MARKERS, upper) != null) {
      return exclude(result, 'REVERSAL', 'DESCRIPTION_RULE');
    }
    if (firstMatch(INVOICE_PAYMENT_MARKERS, upper) != null) {
      return exclude(result, 'INVOICE_PAYMENT', 'DESCRIPTION_RULE');
    }
    if (TRANSFER_OPERATIONS.contains(operation)) {
      return exclude(result, 'TRANSFER', 'OPERATION_TYPE');
    }
    Rule categoryRule = firstMatch(CATEGORY_EXCLUSIONS, category);
    if (categoryRule != null) {
      return exclude(result, categoryRule.reason, 'PROVIDER_CATEGORY');
    }
    // Service hint needs provider category or a non-generic merchant identity; the hint is
    // evidence for S2 and never promotes eligibility.
    Boolean categorySaysService =
      firstMatch(SERVICE_CATEGORY_MARKERS, category) != null;
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

  /** Diacritics folded, upper-cased, single spaces; blank => ''. */
  private static String fold(String raw) {
    return AXF_CLS_TextNormalization.normalize(raw).toUpperCase();
  }

  private static Rule firstMatch(List<Rule> rules, String folded) {
    if (String.isBlank(folded)) {
      return null;
    }
    List<String> tokens = folded.split(' ');
    String padded = ' ' + folded + ' ';
    for (Rule rule : rules) {
      if (rule.mode == 'PHRASE') {
        if (padded.contains(' ' + rule.marker + ' ')) {
          return rule;
        }
        continue;
      }
      for (String token : tokens) {
        if (
          (rule.mode == 'TOKEN' && token == rule.marker) ||
          (rule.mode == 'PREFIX' && token.startsWith(rule.marker))
        ) {
          return rule;
        }
      }
    }
    return null;
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
          AXF_CCT_NUM_InstallmentNumber__c,
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
        fact.installmentNumber = row.AXF_CCT_NUM_InstallmentNumber__c;
        fact.totalInstallments = row.AXF_CCT_NUM_TotalInstallments__c;
        result.put(row.Id, fact);
      }
    }
    return result;
  }

  private static Set<String> identities(List<Fact> facts) {
    Set<String> result = new Set<String>();
    for (Fact fact : facts) {
      result.add(sourceIdentity(fact));
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

  /**
   * Content only (no rule version): the same fact replayed never creates a revision, and
   * provider values that differ only in case, accents or spacing are the same content.
   * Re-classifying existing observations under a new rule version is a separate, explicit step.
   */
  private static String fingerprint(Fact fact, String normalized) {
    return AXF_CLS_IdentityFraming.key(
      new List<Object>{
        String.valueOf(fact.bookedOn),
        fact.currencyIso,
        String.valueOf(fact.magnitude),
        fact.direction,
        normalized,
        fold(fact.rawStatus),
        fold(fact.operationType),
        String.valueOf(fact.installmentNumber),
        String.valueOf(fact.totalInstallments),
        fold(fact.category),
        fold(fact.merchant)
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
