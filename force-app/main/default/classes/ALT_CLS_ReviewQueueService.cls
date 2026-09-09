/** @description Authorized bulk review queue; evidence is retained and source resolution requires a financial handler. */
public with sharing class ALT_CLS_ReviewQueueService {
  public static final String STATE_OPEN = 'OPEN';
  public static final String STATE_RESOLVED = 'RESOLVED';
  public static final String STATE_DISMISSED = 'DISMISSED';

  public static final Set<String> SUPPORTED_TYPES = new Set<String>{
    'MATCH_LOW_CONFIDENCE',
    'SOURCE_CHANGE',
    'SOURCE_DELETE',
    'TRANSFER_SUGGESTION',
    'ACCOUNT_MERGE',
    'HOLDER_CONFIRMATION'
  };

  public class CreateInputDTO {
    public String type;
    public String reviewKey;
    public Id financialTransactionId;
    public Id creditCardTransactionId;
    public Id bankAccountTransactionId;
    public Id accountId;
    public Id bankAccountId;
    public Id creditCardId;
    public Decimal priorAmount;
    public Date priorDate;
    public String priorDescription;
    public Decimal priorMatchConfidence;
    public String priorDirection;
    public String priorCurrency;
    public String priorStatus;
    public Decimal proposedAmount;
    public Date proposedDate;
    public String proposedDescription;
    public String proposedDirection;
    public String proposedCurrency;
    public String proposedStatus;
    public String evidenceRef;
    public Datetime observedAt;
  }

  public class ResolveInputDTO {
    public Id reviewItemId;
    public String decision; // RESOLVED | DISMISSED
    public String note;
    public Decimal expectedVersion;
  }

  public class ResultDTO {
    public Boolean success;
    public Id reviewItemId;
    public String state;
    public String message;
  }

  public class ReviewViewDTO {
    public Decimal version;
    public Id reviewItemId;
    public String name;
    public String type;
    public String state;
    public Id financialTransactionId;
    public Id creditCardTransactionId;
    public Id bankAccountTransactionId;
    public Id accountId;
    public Id bankAccountId;
    public Id creditCardId;
    public Decimal priorAmount;
    public Date priorDate;
    public String priorDescription;
    public Decimal priorMatchConfidence;
    public String priorDirection;
    public String priorCurrency;
    public String priorStatus;
    public Decimal proposedAmount;
    public Date proposedDate;
    public String proposedDescription;
    public String proposedDirection;
    public String proposedCurrency;
    public String proposedStatus;
    public String evidenceRef;
    public Datetime observedAt;

    public Id resolvedByUserId;
    public Datetime resolvedAt;
    public String resolutionNote;
  }

  /** @description Single-record convenience wrapper for the bulk producer contract. */
  public ResultDTO createItem(CreateInputDTO input) {
    return createItems(new List<CreateInputDTO>{ input })[0];
  }

  /** @description One result per input; keys remain idempotent after terminal decisions. */
  public List<ResultDTO> createItems(List<CreateInputDTO> inputs) {
    List<ResultDTO> output = new List<ResultDTO>();
    if (inputs == null || inputs.isEmpty())
      return output;
    List<AXF_OBJ_ReviewItem__c> candidates = new List<AXF_OBJ_ReviewItem__c>();
    Set<String> keys = new Set<String>();
    for (CreateInputDTO input : inputs) {
      validateCreate(input);
      keys.add(input.reviewKey);
      candidates.add(fromInput(input));
    }
    ReferenceAccess allowed = authorizedReferences(candidates);
    List<AXF_OBJ_ReviewItem__c> existing = (List<AXF_OBJ_ReviewItem__c>) Database.queryWithBinds(
      selectQuery() + ' WHERE AXF_RVI_EXI_ReviewKey__c IN :keys',
      new Map<String, Object>{ 'keys' => keys },
      AccessLevel.USER_MODE
    );
    ReferenceAccess existingAllowed = authorizedReferences(existing);
    Map<String, AXF_OBJ_ReviewItem__c> byKey = new Map<String, AXF_OBJ_ReviewItem__c>();
    for (AXF_OBJ_ReviewItem__c row : existing)
      if (referencesAllowed(row, existingAllowed))
        byKey.put(row.AXF_RVI_EXI_ReviewKey__c, row);
    List<AXF_OBJ_ReviewItem__c> inserts = new List<AXF_OBJ_ReviewItem__c>();
    Map<String, Integer> insertIndex = new Map<String, Integer>();
    for (AXF_OBJ_ReviewItem__c row : candidates) {
      if (!referencesAllowed(row, allowed))
        continue;
      if (
        !byKey.containsKey(row.AXF_RVI_EXI_ReviewKey__c) &&
        !insertIndex.containsKey(row.AXF_RVI_EXI_ReviewKey__c)
      ) {
        insertIndex.put(row.AXF_RVI_EXI_ReviewKey__c, inserts.size());
        inserts.add(row);
      }
    }
    List<Database.SaveResult> saved = new List<Database.SaveResult>();
    if (!inserts.isEmpty()) {
      AXF_CLS_ReviewQueueTriggerHandler.guardEnabled = true;
      try {
        saved = Database.insert(inserts, false, AccessLevel.USER_MODE);
      } finally {
        AXF_CLS_ReviewQueueTriggerHandler.guardEnabled = false;
      }
    }
    for (AXF_OBJ_ReviewItem__c row : candidates) {
      ResultDTO result = new ResultDTO();
      result.success = false;
      result.message = 'Review could not be recorded. Retry from the checkpoint.';
      if (referencesAllowed(row, allowed)) {
        AXF_OBJ_ReviewItem__c previous = byKey.get(
          row.AXF_RVI_EXI_ReviewKey__c
        );
        if (previous != null) {
          if (sameEvidence(row, previous)) {
            result.success = true;
            result.reviewItemId = previous.Id;
            result.state = previous.AXF_RVI_PKL_State__c;
          }
        } else {
          Database.SaveResult save = saved[
            insertIndex.get(row.AXF_RVI_EXI_ReviewKey__c)
          ];
          result.success =
            save.isSuccess() &&
            sameEvidence(
              row,
              inserts[insertIndex.get(row.AXF_RVI_EXI_ReviewKey__c)]
            );
          if (result.success) {
            result.reviewItemId = save.getId();
            result.state = STATE_OPEN;
          }
        }
      }
      output.add(result);
    }
    return output;
  }

  private AXF_OBJ_ReviewItem__c fromInput(CreateInputDTO input) {
    return new AXF_OBJ_ReviewItem__c(
      AXF_RVI_PKL_Type__c = input.type,
      AXF_RVI_PKL_State__c = STATE_OPEN,
      AXF_RVI_EXI_ReviewKey__c = input.reviewKey,
      AXF_RVI_NUM_Version__c = 0,
      AXF_RVI_LKP_FinancialTransaction__c = input.financialTransactionId,
      AXF_RVI_LKP_CreditCardTransaction__c = input.creditCardTransactionId,
      AXF_RVI_LKP_BankAccountTransaction__c = input.bankAccountTransactionId,
      AXF_RVI_LKP_Account__c = input.accountId,
      AXF_RVI_LKP_BankAccount__c = input.bankAccountId,
      AXF_RVI_LKP_CreditCard__c = input.creditCardId,
      AXF_RVI_NUM_PriorAmount__c = input.priorAmount,
      AXF_RVI_DAT_PriorDate__c = input.priorDate,
      AXF_RVI_TXT_PriorDescription__c = input.priorDescription,
      AXF_RVI_NUM_PriorMatchConfidence__c = input.priorMatchConfidence,
      AXF_RVI_TXT_PriorDirection__c = input.priorDirection,
      AXF_RVI_TXT_PriorCurrency__c = input.priorCurrency,
      AXF_RVI_TXT_PriorStatus__c = input.priorStatus,
      AXF_RVI_NUM_ProposedAmount__c = input.proposedAmount,
      AXF_RVI_DAT_ProposedDate__c = input.proposedDate,
      AXF_RVI_TXT_ProposedDescription__c = input.proposedDescription,
      AXF_RVI_TXT_ProposedDirection__c = input.proposedDirection,
      AXF_RVI_TXT_ProposedCurrency__c = input.proposedCurrency,
      AXF_RVI_TXT_ProposedStatus__c = input.proposedStatus,
      AXF_RVI_TXT_EvidenceRef__c = input.evidenceRef,
      AXF_RVI_DT_ObservedAt__c = input.observedAt
    );
  }

  /** Lista itens OPEN visiveis ao usuario (with sharing). */
  public List<ReviewViewDTO> listOpen() {
    List<AXF_OBJ_ReviewItem__c> rows = (List<AXF_OBJ_ReviewItem__c>) Database.queryWithBinds(
      selectQuery() +
      ' WHERE AXF_RVI_PKL_State__c = :state ORDER BY CreatedDate ASC LIMIT 200',
      new Map<String, Object>{ 'state' => STATE_OPEN },
      AccessLevel.USER_MODE
    );
    ReferenceAccess allowed = authorizedReferences(rows);
    List<ReviewViewDTO> out = new List<ReviewViewDTO>();
    for (AXF_OBJ_ReviewItem__c row : rows)
      if (referencesAllowed(row, allowed))
        out.add(toView(row));
    return out;
  }

  /** Abre um item especifico (somente se visivel). */
  public ReviewViewDTO open(Id reviewItemId) {
    List<AXF_OBJ_ReviewItem__c> rows = fetch(reviewItemId, false);
    return rows.isEmpty() ? null : toView(rows[0]);
  }

  /**
   * @description Resolves or dismisses an authorized, locked item with a required version. Evidence is retained.
   */
  public ResultDTO resolve(ResolveInputDTO input) {
    ResultDTO out = new ResultDTO();
    if (input == null || input.reviewItemId == null) {
      throw new AXF_CLS_ReviewQueueException('Item de revisao e obrigatorio.');
    }
    if (input.expectedVersion == null)
      throw new AXF_CLS_ReviewQueueException('Expected version is required.');
    if (String.isBlank(input.note))
      throw new AXF_CLS_ReviewQueueException('A resolution note is required.');
    if (input.decision != STATE_RESOLVED && input.decision != STATE_DISMISSED) {
      throw new AXF_CLS_ReviewQueueException(
        'Decisao invalida: somente RESOLVED ou DISMISSED.'
      );
    }
    List<AXF_OBJ_ReviewItem__c> rows = fetch(input.reviewItemId, true);
    if (rows.isEmpty()) {
      out.success = false;
      out.message = 'Item nao encontrado ou sem acesso.';
      return out;
    }
    AXF_OBJ_ReviewItem__c item = rows[0];
    if (item.AXF_RVI_PKL_State__c != STATE_OPEN) {
      out.success =
        item.AXF_RVI_PKL_State__c == input.decision &&
        item.AXF_RVI_TAL_ResolutionNote__c == input.note &&
        item.AXF_RVI_NUM_Version__c == input.expectedVersion + 1 &&
        item.AXF_RVI_LKP_ResolvedByUser__c == UserInfo.getUserId();
      out.state = item.AXF_RVI_PKL_State__c;
      out.reviewItemId = item.Id;
      out.message = out.success
        ? 'Decision already recorded.'
        : 'CONFLICT: terminal decision differs from this request.';
      return out;
    }
    if (item.AXF_RVI_NUM_Version__c != input.expectedVersion) {
      throw new AXF_CLS_ReviewQueueException(
        'CONFLICT: versao do item mudou desde a leitura.'
      );
    }
    if (
      input.decision == STATE_RESOLVED &&
      (item.AXF_RVI_PKL_Type__c == 'SOURCE_CHANGE' ||
      item.AXF_RVI_PKL_Type__c == 'SOURCE_DELETE')
    ) {
      out.success = false;
      out.message = 'SOURCE_RESOLUTION_UNAVAILABLE: financial application is not implemented.';
      return out;
    }
    item.AXF_RVI_PKL_State__c = input.decision;
    item.AXF_RVI_LKP_ResolvedByUser__c = UserInfo.getUserId();
    item.AXF_RVI_DT_ResolvedAt__c = System.now();
    item.AXF_RVI_TAL_ResolutionNote__c = input.note;
    item.AXF_RVI_NUM_Version__c =
      (item.AXF_RVI_NUM_Version__c == null ? 0 : item.AXF_RVI_NUM_Version__c) +
      1;
    AXF_CLS_ReviewQueueTriggerHandler.guardEnabled = true;
    try {
      AXF_OBJ_ReviewItem__c change = new AXF_OBJ_ReviewItem__c(
        Id = item.Id,
        AXF_RVI_PKL_State__c = item.AXF_RVI_PKL_State__c,
        AXF_RVI_LKP_ResolvedByUser__c = item.AXF_RVI_LKP_ResolvedByUser__c,
        AXF_RVI_DT_ResolvedAt__c = item.AXF_RVI_DT_ResolvedAt__c,
        AXF_RVI_TAL_ResolutionNote__c = item.AXF_RVI_TAL_ResolutionNote__c,
        AXF_RVI_NUM_Version__c = item.AXF_RVI_NUM_Version__c
      );
      update as user change;
    } finally {
      AXF_CLS_ReviewQueueTriggerHandler.guardEnabled = false;
    }

    out.success = true;
    out.reviewItemId = item.Id;
    out.state = input.decision;
    out.message =
      'Item ' +
      (input.decision == STATE_RESOLVED ? 'resolvido' : 'descartado') +
      '.';
    return out;
  }

  // ---- Internals --------------------------------------------------------------

  private void validateCreate(CreateInputDTO input) {
    if (input == null || input.type == null) {
      throw new AXF_CLS_ReviewQueueException('Tipo do item e obrigatorio.');
    }
    if (!SUPPORTED_TYPES.contains(input.type)) {
      throw new AXF_CLS_ReviewQueueException('Tipo de item nao suportado.');
    }
    if (String.isBlank(input.reviewKey)) {
      throw new AXF_CLS_ReviewQueueException(
        'ReviewKey e obrigatoria (idempotencia).'
      );
    }
    if (input.type == 'SOURCE_CHANGE' || input.type == 'SOURCE_DELETE') {
      Boolean bank = input.bankAccountTransactionId != null;
      Boolean card = input.creditCardTransactionId != null;
      if (
        bank == card ||
        (bank && input.bankAccountId == null) ||
        (card && input.creditCardId == null) ||
        String.isBlank(input.evidenceRef) ||
        input.observedAt == null
      ) {
        throw new AXF_CLS_ReviewQueueException(
          'A source review requires one typed fact, its parent and observation evidence.'
        );
      }
    }
    Integer refs = 0;
    if (input.financialTransactionId != null)
      refs++;
    if (input.creditCardTransactionId != null)
      refs++;
    if (input.bankAccountTransactionId != null)
      refs++;
    if (input.accountId != null)
      refs++;
    if (input.bankAccountId != null)
      refs++;
    if (input.creditCardId != null)
      refs++;
    if (refs == 0) {
      throw new AXF_CLS_ReviewQueueException(
        'Item deve referenciar ao menos um registro envolvido.'
      );
    }
  }

  private List<AXF_OBJ_ReviewItem__c> fetch(Id id, Boolean lockRow) {
    List<AXF_OBJ_ReviewItem__c> rows = (List<AXF_OBJ_ReviewItem__c>) Database.queryWithBinds(
      selectQuery() +
        ' WHERE Id = :id LIMIT 1' +
        (lockRow ? ' FOR UPDATE' : ''),
      new Map<String, Object>{ 'id' => id },
      AccessLevel.USER_MODE
    );
    ReferenceAccess allowed = authorizedReferences(rows);
    if (!rows.isEmpty() && !referencesAllowed(rows[0], allowed))
      rows.clear();
    return rows;
  }

  private static String selectQuery() {
    List<String> names = new List<String>{ 'Id', 'Name' };
    for (
      String name : AXF_OBJ_ReviewItem__c.SObjectType.getDescribe(
          SObjectDescribeOptions.DEFERRED
        )
        .fields.getMap()
        .keySet()
    ) {
      if (name.toLowerCase().startsWith('axf_rvi_'))
        names.add(name);
    }
    return 'SELECT ' + String.join(names, ',') + ' FROM AXF_OBJ_ReviewItem__c';
  }

  private static final List<String> REFERENCES = new List<String>{
    'AXF_RVI_LKP_FinancialTransaction__c',
    'AXF_RVI_LKP_BankAccountTransaction__c',
    'AXF_RVI_LKP_CreditCardTransaction__c',
    'AXF_RVI_LKP_Account__c',
    'AXF_RVI_LKP_BankAccount__c',
    'AXF_RVI_LKP_CreditCard__c'
  };

  private class ReferenceAccess {
    public Set<Id> allowed = new Set<Id>();
    public Map<Id, Id> parents = new Map<Id, Id>();
  }

  private static ReferenceAccess authorizedReferences(
    List<AXF_OBJ_ReviewItem__c> rows
  ) {
    Set<Id> ids = new Set<Id>();
    for (AXF_OBJ_ReviewItem__c row : rows)
      for (String field : REFERENCES)
        if (row.get(field) != null)
          ids.add((Id) row.get(field));
    ReferenceAccess access = new ReferenceAccess();
    Set<Id> allowed = access.allowed;
    Map<Id, Id> parents = access.parents;
    readReferences(ids, allowed, parents, Account.SObjectType, 'Id');
    readReferences(
      ids,
      allowed,
      parents,
      AXF_OBJ_BankAccount__c.SObjectType,
      'Id'
    );
    readReferences(
      ids,
      allowed,
      parents,
      AXF_OBJ_CreditCard__c.SObjectType,
      'Id'
    );
    readReferences(
      ids,
      allowed,
      parents,
      AXF_OBJ_FinancialTransaction__c.SObjectType,
      'Id,AXF_FTX_NUM_Magnitude__c,AXF_FTX_DAT_PurchaseDate__c,AXF_FTX_PKL_Direction__c,AXF_FTX_PKL_Status__c,AXF_FTX_TXT_CurrencyIsoCode__c'
    );
    readReferences(
      ids,
      allowed,
      parents,
      AXF_OBJ_BankAccountTransaction__c.SObjectType,
      ALT_CLS_SourceChangeReview.selectFields('AXF_BAT_')
    );
    readReferences(
      ids,
      allowed,
      parents,
      AXF_OBJ_CreditCardTransaction__c.SObjectType,
      ALT_CLS_SourceChangeReview.selectFields('AXF_CCT_')
    );
    return access;
  }

  private static void readReferences(
    Set<Id> ids,
    Set<Id> allowed,
    Map<Id, Id> parents,
    Schema.SObjectType type,
    String fields
  ) {
    Set<Id> typed = new Set<Id>();
    for (Id id : ids)
      if (id.getSObjectType() == type)
        typed.add(id);
    if (typed.isEmpty())
      return;
    try {
      for (
        SObject row : Database.queryWithBinds(
          'SELECT ' +
            fields +
            ' FROM ' +
            type.getDescribe().getName() +
            ' WHERE Id IN :ids',
          new Map<String, Object>{ 'ids' => typed },
          AccessLevel.USER_MODE
        )
      ) {
        allowed.add((Id) row.get('Id'));
        if (type == AXF_OBJ_BankAccountTransaction__c.SObjectType)
          parents.put(
            (Id) row.get('Id'),
            (Id) row.get('AXF_BAT_MDR_BankAccount__c')
          );
        if (type == AXF_OBJ_CreditCardTransaction__c.SObjectType)
          parents.put(
            (Id) row.get('Id'),
            (Id) row.get('AXF_CCT_MDR_CreditCard__c')
          );
      }
    } catch (QueryException denied) {
      // Fail closed for current CRUD/FLS; no evidence or existence is returned.
      return;
    }
  }

  private static Boolean referencesAllowed(
    AXF_OBJ_ReviewItem__c row,
    ReferenceAccess access
  ) {
    Boolean hasReference = false;
    for (String field : REFERENCES)
      if (row.get(field) != null) {
        hasReference = true;
        if (!access.allowed.contains((Id) row.get(field)))
          return false;
      }
    if (
      row.AXF_RVI_LKP_BankAccountTransaction__c != null &&
      row.AXF_RVI_LKP_BankAccount__c != null &&
      access.parents.get(row.AXF_RVI_LKP_BankAccountTransaction__c) !=
      row.AXF_RVI_LKP_BankAccount__c
    )
      return false;
    if (
      row.AXF_RVI_LKP_CreditCardTransaction__c != null &&
      row.AXF_RVI_LKP_CreditCard__c != null &&
      access.parents.get(row.AXF_RVI_LKP_CreditCardTransaction__c) !=
      row.AXF_RVI_LKP_CreditCard__c
    )
      return false;
    return hasReference;
  }

  private static Boolean sameEvidence(
    AXF_OBJ_ReviewItem__c a,
    AXF_OBJ_ReviewItem__c b
  ) {
    for (
      String field : AXF_OBJ_ReviewItem__c.SObjectType.getDescribe(
          SObjectDescribeOptions.DEFERRED
        )
        .fields.getMap()
        .keySet()
    ) {
      String name = field.toLowerCase();
      if (
        !name.startsWith('axf_rvi_') ||
        name == 'axf_rvi_pkl_state__c' ||
        name == 'axf_rvi_num_version__c' ||
        name == 'axf_rvi_dt_observedat__c' ||
        name == 'axf_rvi_txt_evidenceref__c' ||
        name == 'axf_rvi_lkp_resolvedbyuser__c' ||
        name == 'axf_rvi_dt_resolvedat__c' ||
        name == 'axf_rvi_tal_resolutionnote__c'
      )
        continue;
      if (a.get(field) != b.get(field))
        return false;
    }
    return true;
  }

  private ReviewViewDTO toView(AXF_OBJ_ReviewItem__c r) {
    ReviewViewDTO v = new ReviewViewDTO();
    v.version = r.AXF_RVI_NUM_Version__c;
    v.reviewItemId = r.Id;
    v.name = r.Name;
    v.type = r.AXF_RVI_PKL_Type__c;
    v.state = r.AXF_RVI_PKL_State__c;
    v.financialTransactionId = r.AXF_RVI_LKP_FinancialTransaction__c;
    v.creditCardTransactionId = r.AXF_RVI_LKP_CreditCardTransaction__c;
    v.bankAccountTransactionId = r.AXF_RVI_LKP_BankAccountTransaction__c;
    v.accountId = r.AXF_RVI_LKP_Account__c;
    v.bankAccountId = r.AXF_RVI_LKP_BankAccount__c;
    v.creditCardId = r.AXF_RVI_LKP_CreditCard__c;
    v.priorAmount = r.AXF_RVI_NUM_PriorAmount__c;
    v.priorDate = r.AXF_RVI_DAT_PriorDate__c;
    v.priorDescription = r.AXF_RVI_TXT_PriorDescription__c;
    v.priorMatchConfidence = r.AXF_RVI_NUM_PriorMatchConfidence__c;
    v.resolvedByUserId = r.AXF_RVI_LKP_ResolvedByUser__c;
    v.resolvedAt = r.AXF_RVI_DT_ResolvedAt__c;
    v.resolutionNote = r.AXF_RVI_TAL_ResolutionNote__c;
    v.priorDirection = r.AXF_RVI_TXT_PriorDirection__c;
    v.priorCurrency = r.AXF_RVI_TXT_PriorCurrency__c;
    v.priorStatus = r.AXF_RVI_TXT_PriorStatus__c;
    v.proposedAmount = r.AXF_RVI_NUM_ProposedAmount__c;
    v.proposedDate = r.AXF_RVI_DAT_ProposedDate__c;
    v.proposedDescription = r.AXF_RVI_TXT_ProposedDescription__c;
    v.proposedDirection = r.AXF_RVI_TXT_ProposedDirection__c;
    v.proposedCurrency = r.AXF_RVI_TXT_ProposedCurrency__c;
    v.proposedStatus = r.AXF_RVI_TXT_ProposedStatus__c;
    v.evidenceRef = r.AXF_RVI_TXT_EvidenceRef__c;
    v.observedAt = r.AXF_RVI_DT_ObservedAt__c;
    return v;
  }
}
