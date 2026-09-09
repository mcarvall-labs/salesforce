/** @description Preserves published facts and records typed, idempotent source evidence. */
public with sharing class ALT_CLS_SourceChangeReview {
  private static final List<String> MATERIAL = new List<String>{
    'NUM_Magnitude',
    'DAT_Date',
    'TXT_Description',
    'PKL_Direction',
    'TXT_CurrencyIsoCode',
    'PKL_Status'
  };

  /** @description Inserts only new identities; identical replays never issue an update. */
  public Map<String, Object> reconcile(List<SObject> incoming) {
    if (incoming == null || incoming.isEmpty())
      return counts(0, 0);
    String prefix = prefixFor(incoming[0]);
    String sourceField = prefix + 'EXI_SourceKey__c';
    Set<String> keys = new Set<String>();
    for (SObject row : incoming) {
      if (prefixFor(row) != prefix)
        throw new AXF_CLS_ReviewQueueException(
          'Mixed fact types require separate batches.'
        );
      keys.add((String) row.get(sourceField));
    }
    Map<String, SObject> originals = new Map<String, SObject>();
    for (
      SObject row : Database.queryWithBinds(
        'SELECT ' +
          selectFields(prefix) +
          ' FROM ' +
          incoming[0].getSObjectType().getDescribe().getName() +
          ' WHERE ' +
          sourceField +
          ' IN :keys',
        new Map<String, Object>{ 'keys' => keys },
        AccessLevel.USER_MODE
      )
    )
      originals.put((String) row.get(sourceField), row);
    List<SObject> inserts = new List<SObject>();
    List<ALT_CLS_ReviewQueueService.CreateInputDTO> reviews = new List<ALT_CLS_ReviewQueueService.CreateInputDTO>();
    for (SObject proposed : incoming) {
      SObject prior = originals.get((String) proposed.get(sourceField));
      if (prior == null)
        inserts.add(proposed);
      else if (
        prior.get(parentField(prefix)) != proposed.get(parentField(prefix)) ||
        prior.get(prefix + 'PKL_Source__c') !=
        proposed.get(prefix + 'PKL_Source__c')
      ) {
        throw new AXF_CLS_ReviewQueueException(
          'Source identity does not match the authorized parent.'
        );
      } else if (different(prior, proposed, prefix))
        reviews.add(
          evidence(
            prior,
            proposed,
            (String) proposed.get(prefix + 'TXT_EvidenceRef__c')
          )
        );
    }
    Integer ok = 0;
    Integer bad = 0;
    if (!inserts.isEmpty()) {
      for (
        Database.SaveResult result : Database.insert(
          inserts,
          false,
          AccessLevel.USER_MODE
        )
      ) {
        if (result.isSuccess())
          ok++;
        else
          bad++;
      }
    }
    if (!reviews.isEmpty()) {
      try {
        for (
          ALT_CLS_ReviewQueueService.ResultDTO result : new ALT_CLS_ReviewQueueService()
            .createItems(reviews)
        ) {
          if (!result.success)
            bad++;
        }
      } catch (Exception reviewFailure) {
        // Report the actual inserts already accepted and retry every unrecorded review.
        bad += reviews.size();
      }
    }
    return counts(ok, bad);
  }

  /** @description Caller must first verify an authenticated deletion against the provider. */
  public Map<String, Object> reviewDeleted(
    List<SObject> originals,
    String evidenceRef
  ) {
    List<ALT_CLS_ReviewQueueService.CreateInputDTO> reviews = new List<ALT_CLS_ReviewQueueService.CreateInputDTO>();
    for (SObject prior : originals)
      reviews.add(evidence(prior, null, evidenceRef));
    Integer ok = 0;
    Integer bad = 0;
    for (
      ALT_CLS_ReviewQueueService.ResultDTO result : new ALT_CLS_ReviewQueueService()
        .createItems(reviews)
    ) {
      if (result.success)
        ok++;
      else
        bad++;
    }
    return counts(ok, bad);
  }

  /** @description Fixed field allowlist for reading source evidence in USER_MODE. */
  public static String selectFields(String prefix) {
    if (prefix != 'AXF_BAT_' && prefix != 'AXF_CCT_')
      throw new AXF_CLS_ReviewQueueException('Unsupported source.');
    List<String> fields = new List<String>{
      'Id',
      prefix + 'EXI_SourceKey__c',
      prefix + 'PKL_Source__c',
      parentField(prefix)
    };
    for (String field : MATERIAL)
      fields.add(prefix + field + '__c');
    return String.join(fields, ',');
  }

  private static Boolean different(
    SObject prior,
    SObject proposed,
    String prefix
  ) {
    for (String field : MATERIAL)
      if (
        prior.get(prefix + field + '__c') !=
        proposed.get(prefix + field + '__c')
      )
        return true;
    return false;
  }

  private static ALT_CLS_ReviewQueueService.CreateInputDTO evidence(
    SObject prior,
    SObject proposed,
    String ref
  ) {
    String p = prefixFor(prior);
    ALT_CLS_ReviewQueueService.CreateInputDTO dto = new ALT_CLS_ReviewQueueService.CreateInputDTO();
    dto.type = proposed == null ? 'SOURCE_DELETE' : 'SOURCE_CHANGE';
    if (p == 'AXF_BAT_') {
      dto.bankAccountTransactionId = (Id) prior.get('Id');
      dto.bankAccountId = (Id) prior.get(parentField(p));
    } else {
      dto.creditCardTransactionId = (Id) prior.get('Id');
      dto.creditCardId = (Id) prior.get(parentField(p));
    }
    dto.priorAmount = (Decimal) prior.get(p + 'NUM_Magnitude__c');
    dto.priorDate = (Date) prior.get(p + 'DAT_Date__c');
    dto.priorDescription = (String) prior.get(p + 'TXT_Description__c');
    dto.priorDirection = (String) prior.get(p + 'PKL_Direction__c');
    dto.priorCurrency = (String) prior.get(p + 'TXT_CurrencyIsoCode__c');
    dto.priorStatus = (String) prior.get(p + 'PKL_Status__c');
    if (proposed != null) {
      dto.proposedAmount = (Decimal) proposed.get(p + 'NUM_Magnitude__c');
      dto.proposedDate = (Date) proposed.get(p + 'DAT_Date__c');
      dto.proposedDescription = (String) proposed.get(p + 'TXT_Description__c');
      dto.proposedDirection = (String) proposed.get(p + 'PKL_Direction__c');
      dto.proposedCurrency = (String) proposed.get(
        p + 'TXT_CurrencyIsoCode__c'
      );
      dto.proposedStatus = (String) proposed.get(p + 'PKL_Status__c');
    }
    dto.evidenceRef = ref;
    dto.observedAt = System.now();
    List<Object> framed = new List<Object>{
      'source-review-v1',
      dto.type,
      p,
      prior.get(p + 'PKL_Source__c'),
      prior.get(p + 'EXI_SourceKey__c'),
      prior.get(parentField(p))
    };
    for (String field : MATERIAL) {
      Object beforeValue = prior.get(p + field + '__c');
      Object afterValue = proposed == null
        ? null
        : proposed.get(p + field + '__c');
      // Decimal scale is not material; canonicalize before hashing persisted and incoming values.
      if (field == 'NUM_Magnitude') {
        beforeValue = beforeValue == null
          ? null
          : ((Decimal) beforeValue).setScale(8);
        afterValue = afterValue == null
          ? null
          : ((Decimal) afterValue).setScale(8);
      }
      framed.add(beforeValue);
      framed.add(afterValue);
    }
    dto.reviewKey = AXF_CLS_IdentityFraming.key(framed);
    return dto;
  }

  private static String prefixFor(SObject row) {
    if (row.getSObjectType() == AXF_OBJ_BankAccountTransaction__c.SObjectType)
      return 'AXF_BAT_';
    if (row.getSObjectType() == AXF_OBJ_CreditCardTransaction__c.SObjectType)
      return 'AXF_CCT_';
    throw new AXF_CLS_ReviewQueueException('Unsupported source.');
  }

  private static String parentField(String prefix) {
    return prefix == 'AXF_BAT_'
      ? 'AXF_BAT_MDR_BankAccount__c'
      : 'AXF_CCT_MDR_CreditCard__c';
  }

  private static Map<String, Object> counts(Integer ok, Integer bad) {
    return new Map<String, Object>{ 'ok' => ok, 'bad' => bad };
  }
}
