/**
 * @description Rateio economico de um fato entre pessoas/empresas autorizadas (AXF-126, fatia
 * de AXF-5; contrato fisico ratificado em 13/09/2026: ancora XOR no fato tipado, EA -> Account,
 * identidade alloc-v2, ordem de lock token(20) -> fato(30) -> RA/FTX(50) -> EAS/EA(60)).
 *
 * Operacoes: economicallocation.set.propose.v1 (cria revisao DRAFT com parcelas validadas),
 * economicallocation.set.confirm.v1 (exige soma exata de 100% e confirma atomicamente) e
 * economicallocation.set.reverse.v1 (AXF-128: encerra a confirmacao com registros compensatorios).
 * Toda rejeicao e atomica: nada parcial persiste. A propriedade da conta permanece separada
 * da atribuicao economica: nenhuma parcela e inferida na ingestao. Rateio nao cria share.
 * A projecao derivada de atribuicao unica (AXF-127) e gravada na propria confirmacao: pelo
 * contrato ratificado da AXF-5 (secao 5) ela reflete a unica pessoa/empresa somente quando o set
 * CONFIRMED tem exatamente uma parcela de 100% e fica vazia em rateio; G1 apenas fixa a forma do
 * sujeito (Account AXF_Person|AXF_Business). Enquanto um set tem autoridade, a projecao pode
 * existir; ao terminar a autoridade ela e limpa (discard e reversao). A reversao (AXF-128) cria
 * um set compensatorio de mesma identidade e revisao seguinte com uma unica parcela de 100% para
 * o titular do fato, de modo que o fato volta a ter uma unica autoridade de atribuicao e um unico
 * token ativo; a confirmacao revertida nunca e editada. Revisao (supersessao) e neutralizacao no
 * consolidado sao historias irmas (AXF-128/129).
 */
public with sharing class ALT_CLS_EconomicAllocationService {
  public static final String IDENTITY_VERSION = 'alloc-v2';
  public static final String ECONOMIC_KIND = 'SHARE';
  public static final String TARGET_TYPE = 'ACCOUNT';
  public static final String CP_ALLOCATE = 'AXF_CanAllocateEconomically';
  public static final String STATE_DRAFT = 'DRAFT';
  public static final String STATE_CONFIRMED = 'CONFIRMED';
  public static final String STATE_REVERSED = 'REVERSED';
  /** Ratified operationId of the reversal (AXF-5 reconciliation, ratified 13/09/2026). */
  public static final String OP_REVERSE = 'economicallocation.set.reverse.v1';
  private static final Set<String> HOLDER_RECORD_TYPES = new Set<String>{
    'AXF_Person',
    'AXF_Business'
  };

  public class EconomicAllocationException extends Exception {
    public String code;
    public List<String> reasons = new List<String>();
  }

  public class ShareInput {
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public Decimal percent;
  }

  public class ProposeInput {
    @AuraEnabled
    public String factKind; // BANK | CARD | MANUAL
    @AuraEnabled
    public Id factId;
    @AuraEnabled
    public String operationKey;
    @AuraEnabled
    public List<ShareInput> shares;
  }

  public class ReverseInput {
    @AuraEnabled
    public Id setId;
    @AuraEnabled
    public Decimal expectedVersion;
    @AuraEnabled
    public String operationKey;
  }

  public class ShareView {
    @AuraEnabled
    public Id allocationId;
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public Decimal percent;
    @AuraEnabled
    public Decimal magnitude;
    @AuraEnabled
    public String currencyIso;
    @AuraEnabled
    public String allocationKey;
  }

  public class SetView {
    @AuraEnabled
    public Id setId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String factKind;
    @AuraEnabled
    public Id factId;
    @AuraEnabled
    public String factName;
    @AuraEnabled
    public Id holderAccountId;
    @AuraEnabled
    public String holderAccountName;
    @AuraEnabled
    public Integer revision;
    @AuraEnabled
    public String state;
    @AuraEnabled
    public Decimal factMagnitude;
    @AuraEnabled
    public String currencyIso;
    @AuraEnabled
    public Decimal totalPercent;
    @AuraEnabled
    public Decimal version;
    @AuraEnabled
    public Datetime effectiveAt;
    @AuraEnabled
    public List<ShareView> shares = new List<ShareView>();
  }

  private class Fact {
    String kind;
    Id id;
    String name;
    String identity;
    Id holderId;
    Decimal magnitude;
    String currencyIso;
    String status;
  }
  public static final String STATE_DISCARDED = 'DISCARDED';
  private static final Integer KEY_MAX = 64;
  private static final Integer SHARES_MAX = 200;

  // ------------------------------------------------------------------ propose

  /** economicallocation.set.propose.v1 — creates a DRAFT revision with validated shares. */
  public SetView propose(ProposeInput input) {
    validate(input);
    requireCapability();
    Fact fact = lockFact(input.factKind, input.factId);
    List<AXF_OBJ_EconomicAllocationSet__c> existing = existingByOperation(
      input.operationKey
    );
    if (!existing.isEmpty()) {
      if (sameProposal(existing[0], input)) {
        return read(existing[0].Id);
      }
      throw failure('CONFLICT', new List<String>());
    }
    if (
      ALT_CLS_EconomicAllocationIntegrity.activeSetId(
        activeToken(fact.identity)
      ) != null
    ) {
      // Revising a confirmed allocation is the sibling story; a new proposal cannot bypass it.
      throw failure('ACTIVE_SET_EXISTS', new List<String>());
    }
    List<String> reasons = new List<String>();
    if (fact.status != null && fact.status != 'POSTED') {
      reasons.add('FACT_NOT_SETTLED');
    }
    Map<Id, Account> holders = authorizedHolders(input.shares, reasons);
    // Validation and persistence use the same normalized values (scale 6 / 8).
    Decimal total = 0;
    Set<Id> seen = new Set<Id>();
    for (ShareInput share : input.shares) {
      Decimal percent = share.percent == null
        ? null
        : share.percent.setScale(6);
      Decimal magnitude = percent == null
        ? null
        : (fact.magnitude *
            percent /
            100)
            .setScale(8, System.RoundingMode.HALF_EVEN);
      if (percent == null || percent <= 0 || percent > 100 || magnitude <= 0) {
        reasons.add('NON_POSITIVE_SHARE:' + share.accountId);
      }
      if (!seen.add(share.accountId)) {
        reasons.add('DUPLICATE_ACCOUNT:' + share.accountId);
      }
      total += nz(percent);
    }
    if (total > 100) {
      reasons.add('TOTAL_EXCEEDS_100');
    }
    if (!reasons.isEmpty()) {
      throw failure('INVALID_SHARES', reasons);
    }

    Savepoint point = Database.setSavepoint();
    try {
      ALT_CLS_EconomicAllocationGuard.beginWrite();
      Integer revision = nextRevision(fact.identity);
      AXF_OBJ_EconomicAllocationSet__c allocationSet = new AXF_OBJ_EconomicAllocationSet__c(
        AXF_EAS_LKP_BankTransaction__c = fact.kind == 'BANK' ? fact.id : null,
        AXF_EAS_LKP_CardTransaction__c = fact.kind == 'CARD' ? fact.id : null,
        AXF_EAS_LKP_FinancialTransaction__c = fact.kind == 'MANUAL'
          ? fact.id
          : null,
        AXF_EAS_LKP_HolderAccount__c = fact.holderId,
        AXF_EAS_TXT_FactIdentity__c = fact.identity.left(128),
        AXF_EAS_NUM_Revision__c = revision,
        AXF_EAS_PKL_State__c = STATE_DRAFT,
        AXF_EAS_EXI_SetKey__c = AXF_CLS_IdentityFraming.key(
          new List<Object>{ fact.identity, revision }
        ),
        AXF_EAS_NUM_FactMagnitude__c = fact.magnitude,
        AXF_EAS_TXT_CurrencyIsoCode__c = fact.currencyIso,
        AXF_EAS_TXT_OperationKey__c = input.operationKey,
        AXF_EAS_NUM_Version__c = 1,
        OwnerId = holderOwner(fact.holderId)
      );
      Database.insert(allocationSet, AccessLevel.USER_MODE);
      grantProposerAccess(allocationSet.Id, allocationSet.OwnerId);
      List<AXF_OBJ_EconomicAllocation__c> allocations = new List<AXF_OBJ_EconomicAllocation__c>();
      Map<Id, Decimal> magnitudes = shareMagnitudes(
        fact.magnitude,
        input.shares
      );
      for (ShareInput share : input.shares) {
        allocations.add(
          new AXF_OBJ_EconomicAllocation__c(
            AXF_EA_MDR_AllocationSet__c = allocationSet.Id,
            AXF_EA_LKP_Account__c = share.accountId,
            AXF_EA_NUM_Percent__c = share.percent.setScale(6),
            AXF_EA_NUM_Magnitude__c = magnitudes.get(share.accountId),
            AXF_EA_TXT_CurrencyIsoCode__c = fact.currencyIso,
            AXF_EA_PKL_RedactionPolicy__c = 'OWN_SHARE_ONLY',
            AXF_EA_EXI_AllocationKey__c = AXF_CLS_IdentityFraming.key(
              new List<Object>{
                IDENTITY_VERSION,
                fact.identity,
                TARGET_TYPE,
                String.valueOf(share.accountId),
                ECONOMIC_KIND,
                revision
              }
            )
          )
        );
      }
      Database.insert(allocations, AccessLevel.USER_MODE);
      return read(allocationSet.Id);
    } catch (Exception failure) {
      Database.rollback(point);
      throw failure;
    } finally {
      ALT_CLS_EconomicAllocationGuard.endWrite();
    }
  }

  // ------------------------------------------------------------------ confirm

  /** economicallocation.set.confirm.v1 — exact 100%, authorized accounts, expected version. */
  public SetView confirm(
    Id setId,
    Decimal expectedVersion,
    String operationKey
  ) {
    if (setId == null || String.isBlank(operationKey)) {
      throw failure('INVALID_INPUT', new List<String>());
    }
    requireKey(operationKey);
    requireCapability();
    // Lock order: the fact (30) before the set (60), as in propose.
    AXF_OBJ_EconomicAllocationSet__c anchor = readSet(setId);
    Fact fact = lockFact(factKind(anchor), factId(anchor));
    AXF_OBJ_EconomicAllocationSet__c allocationSet = lockSet(setId);
    if (
      allocationSet.AXF_EAS_PKL_State__c == STATE_CONFIRMED &&
      allocationSet.AXF_EAS_TXT_ConfirmOperationKey__c == operationKey
    ) {
      return read(setId);
    }
    if (allocationSet.AXF_EAS_PKL_State__c != STATE_DRAFT) {
      throw failure('NOT_DRAFT', new List<String>());
    }
    if (
      expectedVersion == null ||
      expectedVersion != nz(allocationSet.AXF_EAS_NUM_Version__c)
    ) {
      throw failure('CONFLICT', new List<String>());
    }
    List<String> reasons = new List<String>();
    List<AXF_OBJ_EconomicAllocation__c> allocations = [
      SELECT
        Id,
        AXF_EA_LKP_Account__c,
        AXF_EA_NUM_Percent__c,
        AXF_EA_NUM_Magnitude__c
      FROM AXF_OBJ_EconomicAllocation__c
      WHERE AXF_EA_MDR_AllocationSet__c = :setId
      WITH USER_MODE
    ];
    List<ShareInput> shares = new List<ShareInput>();
    Decimal total = 0;
    Decimal magnitudeTotal = 0;
    for (AXF_OBJ_EconomicAllocation__c allocation : allocations) {
      ShareInput share = new ShareInput();
      share.accountId = allocation.AXF_EA_LKP_Account__c;
      share.percent = allocation.AXF_EA_NUM_Percent__c;
      shares.add(share);
      total += nz(allocation.AXF_EA_NUM_Percent__c);
      magnitudeTotal += nz(allocation.AXF_EA_NUM_Magnitude__c);
      if (nz(allocation.AXF_EA_NUM_Magnitude__c) <= 0) {
        reasons.add('NON_POSITIVE_SHARE:' + allocation.AXF_EA_LKP_Account__c);
      }
    }
    authorizedHolders(shares, reasons);
    if (allocations.isEmpty() || total.setScale(6) != 100) {
      reasons.add('TOTAL_NOT_100:' + total.setScale(6));
    }
    if (
      fact.magnitude != allocationSet.AXF_EAS_NUM_FactMagnitude__c ||
      fact.currencyIso != allocationSet.AXF_EAS_TXT_CurrencyIsoCode__c ||
      fact.holderId != allocationSet.AXF_EAS_LKP_HolderAccount__c
    ) {
      reasons.add('FACT_CHANGED');
    }
    if (fact.status != null && fact.status != 'POSTED') {
      reasons.add('FACT_NOT_SETTLED');
    }
    if (
      !allocations.isEmpty() &&
      magnitudeTotal.setScale(8) != nz(fact.magnitude).setScale(8)
    ) {
      // Shares must conserve the fact in its original currency, not only in percent.
      reasons.add('MAGNITUDE_NOT_CONSERVED:' + magnitudeTotal.setScale(8));
    }
    if (
      ALT_CLS_EconomicAllocationIntegrity.activeSetId(
        activeToken(fact.identity)
      ) != null
    ) {
      reasons.add('ACTIVE_SET_EXISTS');
    }
    if (!reasons.isEmpty()) {
      throw failure('CONFIRMATION_REJECTED', reasons);
    }
    Savepoint point = Database.setSavepoint();
    try {
      ALT_CLS_EconomicAllocationGuard.beginWrite();
      allocationSet.AXF_EAS_PKL_State__c = STATE_CONFIRMED;
      allocationSet.AXF_EAS_DT_EffectiveAt__c = Datetime.now();
      allocationSet.AXF_EAS_EXI_ActiveToken__c = activeToken(fact.identity);
      // AXF-127: derived singular projection, per the ratified AXF-5 contract (5) — assignment
      // unconditional on purpose: apportionment always writes null, so no primary or first holder
      // is ever promoted.
      allocationSet.AXF_EAS_LKP_AttributedAccount__c = attributedAccount(
        allocations
      );
      // The proposal key stays so a propose replay still finds this set.
      allocationSet.AXF_EAS_TXT_ConfirmOperationKey__c = operationKey;
      allocationSet.AXF_EAS_NUM_Version__c =
        nz(allocationSet.AXF_EAS_NUM_Version__c) + 1;
      try {
        Database.update(allocationSet, AccessLevel.USER_MODE);
      } catch (DmlException race) {
        if (race.getDmlType(0) == StatusCode.DUPLICATE_VALUE) {
          // A concurrent confirmation won the active token.
          throw failure('ACTIVE_SET_EXISTS', new List<String>());
        }
        throw race;
      }
      return read(setId);
    } catch (Exception failure) {
      Database.rollback(point);
      throw failure;
    } finally {
      ALT_CLS_EconomicAllocationGuard.endWrite();
    }
  }

  /** economicallocation.set.discard.v1 — closes a DRAFT that will not be confirmed. */
  public SetView discard(Id setId, Decimal expectedVersion) {
    if (setId == null || expectedVersion == null) {
      throw failure('INVALID_INPUT', new List<String>());
    }
    requireCapability();
    AXF_OBJ_EconomicAllocationSet__c allocationSet = lockSet(setId);
    if (allocationSet.AXF_EAS_PKL_State__c == STATE_DISCARDED) {
      return read(setId);
    }
    if (allocationSet.AXF_EAS_PKL_State__c != STATE_DRAFT) {
      throw failure('NOT_DRAFT', new List<String>());
    }
    if (expectedVersion != nz(allocationSet.AXF_EAS_NUM_Version__c)) {
      throw failure('CONFLICT', new List<String>());
    }
    Savepoint point = Database.setSavepoint();
    try {
      ALT_CLS_EconomicAllocationGuard.beginWrite();
      allocationSet.AXF_EAS_PKL_State__c = STATE_DISCARDED;
      // AXF-127/G1: a set that lost its authority keeps no singular projection. The field is
      // readable and editable and feeds reports/list views, so a discarded set must not keep a
      // value that no longer corresponds to any confirmed authority. Assigned in the same DML
      // that ends the set, exactly as confirm() assigns it when the authority begins.
      allocationSet.AXF_EAS_LKP_AttributedAccount__c = null;
      allocationSet.AXF_EAS_NUM_Version__c =
        nz(allocationSet.AXF_EAS_NUM_Version__c) + 1;
      Database.update(allocationSet, AccessLevel.USER_MODE);
      return read(setId);
    } catch (Exception failure) {
      Database.rollback(point);
      throw failure;
    } finally {
      ALT_CLS_EconomicAllocationGuard.endWrite();
    }
  }

  // ------------------------------------------------------------------ reverse

  /**
   * economicallocation.set.reverse.v1 — ends a confirmation with compensating records. The
   * compensation is a new set of the next revision whose single 100% parcel gives the fact back
   * to its own holder, so the fact keeps one attribution authority and one active token. The
   * confirmed set is never edited: only its state, its optimistic version and the two fields
   * that must not outlive the authority move, in the same transaction. A replay of the same
   * command returns the durable compensation; a divergent payload conflicts and never appends a
   * second compensation.
   */
  public SetView reverse(ReverseInput input) {
    if (
      input == null ||
      input.setId == null ||
      input.expectedVersion == null ||
      String.isBlank(input.operationKey)
    ) {
      throw failure('INVALID_INPUT', new List<String>());
    }
    requireKey(input.operationKey);
    requireCapability();
    String reverseKey = reverseOperationKey(input.operationKey);
    // Lock order: the fact (30) before the set (60), as in propose and confirm.
    AXF_OBJ_EconomicAllocationSet__c anchor = readSet(input.setId);
    Fact fact = lockFact(factKind(anchor), factId(anchor));
    AXF_OBJ_EconomicAllocationSet__c allocationSet = lockSet(input.setId);
    if (allocationSet.AXF_EAS_PKL_State__c == STATE_REVERSED) {
      return priorCompensation(fact, allocationSet, input, reverseKey);
    }
    if (allocationSet.AXF_EAS_PKL_State__c != STATE_CONFIRMED) {
      // Only a confirmation is reversed; a DRAFT is discarded and an ended set stays ended.
      throw failure('NOT_CONFIRMED', new List<String>());
    }
    if (input.expectedVersion != nz(allocationSet.AXF_EAS_NUM_Version__c)) {
      throw failure('CONFLICT', new List<String>());
    }
    List<String> reasons = new List<String>();
    if (
      fact.magnitude != allocationSet.AXF_EAS_NUM_FactMagnitude__c ||
      fact.currencyIso != allocationSet.AXF_EAS_TXT_CurrencyIsoCode__c ||
      fact.holderId != allocationSet.AXF_EAS_LKP_HolderAccount__c
    ) {
      // The compensation conserves the fact; a fact that moved cannot be compensated here.
      reasons.add('FACT_CHANGED');
    }
    // The compensating parcel goes back to the fact's own holder, so that person/company must
    // still be an authorized holder.
    ShareInput back = new ShareInput();
    back.accountId = fact.holderId;
    authorizedHolders(new List<ShareInput>{ back }, reasons);
    if (!reasons.isEmpty()) {
      throw failure('REVERSAL_REJECTED', reasons);
    }
    Integer revision = nextRevision(fact.identity);
    Savepoint point = Database.setSavepoint();
    try {
      ALT_CLS_EconomicAllocationGuard.beginWrite();
      // Compensating records: a new set that returns the fact to its holder, plus its parcel.
      AXF_OBJ_EconomicAllocationSet__c compensation = new AXF_OBJ_EconomicAllocationSet__c(
        AXF_EAS_LKP_BankTransaction__c = fact.kind == 'BANK' ? fact.id : null,
        AXF_EAS_LKP_CardTransaction__c = fact.kind == 'CARD' ? fact.id : null,
        AXF_EAS_LKP_FinancialTransaction__c = fact.kind == 'MANUAL'
          ? fact.id
          : null,
        AXF_EAS_LKP_HolderAccount__c = fact.holderId,
        AXF_EAS_TXT_FactIdentity__c = fact.identity.left(128),
        AXF_EAS_NUM_Revision__c = revision,
        AXF_EAS_PKL_State__c = STATE_DRAFT,
        AXF_EAS_EXI_SetKey__c = AXF_CLS_IdentityFraming.key(
          new List<Object>{ fact.identity, revision }
        ),
        AXF_EAS_NUM_FactMagnitude__c = fact.magnitude,
        AXF_EAS_TXT_CurrencyIsoCode__c = fact.currencyIso,
        AXF_EAS_TXT_OperationKey__c = reverseKey,
        AXF_EAS_NUM_Version__c = 1,
        OwnerId = holderOwner(fact.holderId)
      );
      Database.insert(compensation, AccessLevel.USER_MODE);
      grantProposerAccess(compensation.Id, compensation.OwnerId);
      Database.insert(
        new AXF_OBJ_EconomicAllocation__c(
          AXF_EA_MDR_AllocationSet__c = compensation.Id,
          AXF_EA_LKP_Account__c = fact.holderId,
          AXF_EA_NUM_Percent__c = 100,
          AXF_EA_NUM_Magnitude__c = fact.magnitude,
          AXF_EA_TXT_CurrencyIsoCode__c = fact.currencyIso,
          AXF_EA_PKL_RedactionPolicy__c = 'OWN_SHARE_ONLY',
          AXF_EA_EXI_AllocationKey__c = AXF_CLS_IdentityFraming.key(
            new List<Object>{
              IDENTITY_VERSION,
              fact.identity,
              TARGET_TYPE,
              String.valueOf(fact.holderId),
              ECONOMIC_KIND,
              revision
            }
          )
        ),
        AccessLevel.USER_MODE
      );
      // The ended set keeps its confirmed content byte for byte: state, optimistic version and
      // the two fields that must not outlive the authority — the single active token, released
      // here so the compensation can take it, and the derived projection (AXF-127).
      allocationSet.AXF_EAS_PKL_State__c = STATE_REVERSED;
      allocationSet.AXF_EAS_EXI_ActiveToken__c = null;
      allocationSet.AXF_EAS_LKP_AttributedAccount__c = null;
      allocationSet.AXF_EAS_NUM_Version__c =
        nz(allocationSet.AXF_EAS_NUM_Version__c) + 1;
      Database.update(allocationSet, AccessLevel.USER_MODE);
      // The compensation is the authority from now on: confirmed by the parity rule the
      // confirmation itself applies (one 100% parcel), carrying the singular projection.
      compensation.AXF_EAS_PKL_State__c = STATE_CONFIRMED;
      compensation.AXF_EAS_DT_EffectiveAt__c = Datetime.now();
      compensation.AXF_EAS_EXI_ActiveToken__c = activeToken(fact.identity);
      compensation.AXF_EAS_LKP_AttributedAccount__c = fact.holderId;
      compensation.AXF_EAS_NUM_Version__c = 2;
      Database.update(compensation, AccessLevel.USER_MODE);
      return read(compensation.Id);
    } catch (Exception failure) {
      Database.rollback(point);
      throw failure;
    } finally {
      ALT_CLS_EconomicAllocationGuard.endWrite();
    }
  }

  /**
   * Replay of a reversal that already happened (G6). The compensation this very command produced
   * is returned and nothing is appended; a different command, a different version or a target
   * already reversed by another command conflicts. The command is recognised by its framed key
   * plus the version it consumed: the reversal bumped the set's version exactly once and a
   * REVERSED set has no other writer (the guard freezes it and the service has no method for it).
   */
  private SetView priorCompensation(
    Fact fact,
    AXF_OBJ_EconomicAllocationSet__c reversed,
    ReverseInput input,
    String reverseKey
  ) {
    if (input.expectedVersion != nz(reversed.AXF_EAS_NUM_Version__c) - 1) {
      throw failure('CONFLICT', new List<String>());
    }
    for (AXF_OBJ_EconomicAllocationSet__c row : [
      SELECT
        Id,
        AXF_EAS_TXT_FactIdentity__c,
        AXF_EAS_NUM_Revision__c,
        AXF_EAS_PKL_State__c
      FROM AXF_OBJ_EconomicAllocationSet__c
      WHERE AXF_EAS_TXT_OperationKey__c = :reverseKey
      WITH SYSTEM_MODE
      LIMIT 1
    ]) {
      if (
        row.AXF_EAS_TXT_FactIdentity__c == fact.identity &&
        row.AXF_EAS_NUM_Revision__c ==
        nz(reversed.AXF_EAS_NUM_Revision__c) + 1 &&
        row.AXF_EAS_PKL_State__c == STATE_CONFIRMED
      ) {
        return read(row.Id);
      }
    }
    throw failure('CONFLICT', new List<String>());
  }

  /** G6 identity of the reversal effect: the operation key framed under its own operationId. */
  private static String reverseOperationKey(String operationKey) {
    return AXF_CLS_IdentityFraming.key(
      new List<Object>{ OP_REVERSE, operationKey }
    );
  }

  // ------------------------------------------------------------------ read

  public SetView read(Id setId) {
    if (setId == null) {
      throw failure('INVALID_INPUT', new List<String>());
    }
    List<AXF_OBJ_EconomicAllocationSet__c> rows = querySets(
      new Set<Id>{ setId },
      null
    );
    if (rows.isEmpty()) {
      throw failure('NOT_ACCESSIBLE', new List<String>());
    }
    return toView(rows[0]);
  }

  /** Sets of one fact (all revisions), newest first, in one query. */
  public List<SetView> listForFact(String kind, Id factId) {
    if (factId == null) {
      throw failure('INVALID_INPUT', new List<String>());
    }
    List<SetView> result = new List<SetView>();
    for (AXF_OBJ_EconomicAllocationSet__c row : querySets(null, factId)) {
      result.add(toView(row));
    }
    return result;
  }

  private static List<AXF_OBJ_EconomicAllocationSet__c> querySets(
    Set<Id> setIds,
    Id factId
  ) {
    // A null bind in "= :factId" would match every set without that lookup; bind sets instead.
    Set<Id> factIds = factId == null ? new Set<Id>() : new Set<Id>{ factId };
    if (setIds == null) {
      setIds = new Set<Id>();
    }
    return [
      SELECT
        Id,
        Name,
        AXF_EAS_LKP_BankTransaction__c,
        AXF_EAS_LKP_BankTransaction__r.Name,
        AXF_EAS_LKP_CardTransaction__c,
        AXF_EAS_LKP_CardTransaction__r.Name,
        AXF_EAS_LKP_FinancialTransaction__c,
        AXF_EAS_LKP_FinancialTransaction__r.Name,
        AXF_EAS_LKP_HolderAccount__c,
        AXF_EAS_LKP_HolderAccount__r.Name,
        AXF_EAS_NUM_Revision__c,
        AXF_EAS_PKL_State__c,
        AXF_EAS_NUM_FactMagnitude__c,
        AXF_EAS_TXT_CurrencyIsoCode__c,
        AXF_EAS_NUM_Version__c,
        AXF_EAS_DT_EffectiveAt__c,
        (
          SELECT
            Id,
            AXF_EA_LKP_Account__c,
            AXF_EA_LKP_Account__r.Name,
            AXF_EA_NUM_Percent__c,
            AXF_EA_NUM_Magnitude__c,
            AXF_EA_TXT_CurrencyIsoCode__c,
            AXF_EA_EXI_AllocationKey__c
          FROM AXF_REL_Allocations__r
          ORDER BY AXF_EA_LKP_Account__r.Name
        )
      FROM AXF_OBJ_EconomicAllocationSet__c
      WHERE
        Id IN :setIds
        OR AXF_EAS_LKP_BankTransaction__c IN :factIds
        OR AXF_EAS_LKP_CardTransaction__c IN :factIds
        OR AXF_EAS_LKP_FinancialTransaction__c IN :factIds
      WITH USER_MODE
      ORDER BY AXF_EAS_NUM_Revision__c DESC
      LIMIT 200
    ];
  }

  private static AXF_OBJ_EconomicAllocationSet__c readSet(Id setId) {
    List<AXF_OBJ_EconomicAllocationSet__c> rows = [
      SELECT
        Id,
        AXF_EAS_LKP_BankTransaction__c,
        AXF_EAS_LKP_CardTransaction__c,
        AXF_EAS_LKP_FinancialTransaction__c
      FROM AXF_OBJ_EconomicAllocationSet__c
      WHERE Id = :setId
      WITH USER_MODE
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      throw failure('NOT_ACCESSIBLE', new List<String>());
    }
    return rows[0];
  }

  // ------------------------------------------------------------------ guards

  private void validate(ProposeInput input) {
    if (
      input == null ||
      input.factId == null ||
      String.isBlank(input.factKind) ||
      String.isBlank(input.operationKey) ||
      input.shares == null ||
      input.shares.isEmpty()
    ) {
      throw failure('INVALID_INPUT', new List<String>());
    }
    requireKey(input.operationKey);
    if (input.shares.size() > SHARES_MAX) {
      throw failure('INVALID_INPUT', new List<String>());
    }
    input.factKind = input.factKind.toUpperCase();
    if (
      input.factKind != 'BANK' &&
      input.factKind != 'CARD' &&
      input.factKind != 'MANUAL'
    ) {
      throw failure('INVALID_INPUT', new List<String>());
    }
    for (ShareInput share : input.shares) {
      if (share == null || share.accountId == null) {
        throw failure('INVALID_INPUT', new List<String>());
      }
    }
  }

  private void requireCapability() {
    if (!FeatureManagement.checkPermission(CP_ALLOCATE)) {
      throw failure('FORBIDDEN', new List<String>());
    }
  }

  private static void requireKey(String key) {
    if (String.isBlank(key) || key.length() > KEY_MAX) {
      throw failure('INVALID_INPUT', new List<String>());
    }
  }

  /**
   * Magnitudes per share in the original currency; rounding residue goes to the largest share
   * so the shares always conserve the fact (largest-remainder).
   */
  private static Map<Id, Decimal> shareMagnitudes(
    Decimal factMagnitude,
    List<ShareInput> shares
  ) {
    Map<Id, Decimal> result = new Map<Id, Decimal>();
    Decimal assigned = 0;
    Decimal totalPercent = 0;
    Id largest;
    Decimal largestPercent = -1;
    for (ShareInput share : shares) {
      Decimal percent = share.percent.setScale(6);
      totalPercent += percent;
      Decimal magnitude = (factMagnitude *
        percent /
        100)
        .setScale(8, System.RoundingMode.HALF_EVEN);
      result.put(share.accountId, magnitude);
      assigned += magnitude;
      if (percent > largestPercent) {
        largestPercent = percent;
        largest = share.accountId;
      }
    }
    if (totalPercent == 100 && largest != null) {
      result.put(largest, result.get(largest) + (factMagnitude - assigned));
    }
    return result;
  }

  /**
   * Derived singular projection (AXF-127), as ratified by the AXF-5 lineage contract (section 5):
   * the sole person/company only while the confirmed set carries exactly one 100% parcel.
   * Apportionment derives null — never a primary or first participant. G1 is what makes the
   * subject valid: the allocated account is an `Account` of record type `AXF_Person` or
   * `AXF_Business`, because `authorizedHolders()` gated it. The value is a read-only projection:
   * it is not consulted by authorization, sharing or calculation anywhere.
   */
  private static Id attributedAccount(
    List<AXF_OBJ_EconomicAllocation__c> allocations
  ) {
    if (
      allocations.size() != 1 ||
      nz(allocations[0].AXF_EA_NUM_Percent__c).setScale(6) != 100
    ) {
      return null;
    }
    return allocations[0].AXF_EA_LKP_Account__c;
  }

  /** The set follows the holder's owner (G2); the proposer keeps access through a share row. */
  @SuppressWarnings('PMD.ApexCRUDViolation')
  private static void grantProposerAccess(Id setId, Id ownerId) {
    Id me = UserInfo.getUserId();
    if (me == ownerId) {
      return;
    }
    Database.insert(
      new AXF_OBJ_EconomicAllocationSet__Share(
        ParentId = setId,
        UserOrGroupId = me,
        AccessLevel = 'Edit',
        RowCause = Schema.AXF_OBJ_EconomicAllocationSet__Share.RowCause.Manual
      ),
      false
    );
  }

  /** Lock order 30: the source fact, revalidated for access, positivity and currency. */
  private Fact lockFact(String kind, Id factId) {
    Fact fact = new Fact();
    fact.kind = kind;
    fact.id = factId;
    if (kind == 'BANK') {
      List<AXF_OBJ_BankAccountTransaction__c> rows = [
        SELECT
          Id,
          Name,
          AXF_BAT_EXI_SourceKey__c,
          AXF_BAT_NUM_Magnitude__c,
          AXF_BAT_TXT_CurrencyIsoCode__c,
          AXF_BAT_PKL_Status__c,
          AXF_BAT_MDR_BankAccount__r.AXF_BA_LKP_Account__c
        FROM AXF_OBJ_BankAccountTransaction__c
        WHERE Id = :factId
        WITH USER_MODE
        FOR UPDATE
      ];
      if (rows.isEmpty()) {
        throw failure('NOT_ACCESSIBLE', new List<String>());
      }
      fact.name = rows[0].Name;
      fact.identity = rows[0].AXF_BAT_EXI_SourceKey__c;
      fact.magnitude = rows[0].AXF_BAT_NUM_Magnitude__c;
      fact.currencyIso = rows[0].AXF_BAT_TXT_CurrencyIsoCode__c;
      fact.status = rows[0].AXF_BAT_PKL_Status__c;
      fact.holderId = rows[0].AXF_BAT_MDR_BankAccount__r?.AXF_BA_LKP_Account__c;
    } else if (kind == 'CARD') {
      List<AXF_OBJ_CreditCardTransaction__c> rows = [
        SELECT
          Id,
          Name,
          AXF_CCT_EXI_SourceKey__c,
          AXF_CCT_NUM_Magnitude__c,
          AXF_CCT_TXT_CurrencyIsoCode__c,
          AXF_CCT_PKL_Status__c,
          AXF_CCT_MDR_CreditCard__r.AXF_CC_LKP_Account__c
        FROM AXF_OBJ_CreditCardTransaction__c
        WHERE Id = :factId
        WITH USER_MODE
        FOR UPDATE
      ];
      if (rows.isEmpty()) {
        throw failure('NOT_ACCESSIBLE', new List<String>());
      }
      fact.name = rows[0].Name;
      fact.identity = rows[0].AXF_CCT_EXI_SourceKey__c;
      fact.magnitude = rows[0].AXF_CCT_NUM_Magnitude__c;
      fact.currencyIso = rows[0].AXF_CCT_TXT_CurrencyIsoCode__c;
      fact.status = rows[0].AXF_CCT_PKL_Status__c;
      fact.holderId = rows[0].AXF_CCT_MDR_CreditCard__r?.AXF_CC_LKP_Account__c;
    } else {
      List<AXF_OBJ_FinancialTransaction__c> rows = [
        SELECT
          Id,
          Name,
          AXF_FTX_NUM_Magnitude__c,
          AXF_FTX_TXT_CurrencyIsoCode__c,
          AXF_FTX_LKP_Account__c
        FROM AXF_OBJ_FinancialTransaction__c
        WHERE Id = :factId
        WITH USER_MODE
        FOR UPDATE
      ];
      if (rows.isEmpty()) {
        throw failure('NOT_ACCESSIBLE', new List<String>());
      }
      fact.name = rows[0].Name;
      // Manual occurrences share plan hashes across rows and gain hashes over time; the record
      // itself is the only identity that is both unique and stable.
      fact.identity = 'FTX:' + rows[0].Id;
      fact.magnitude = rows[0].AXF_FTX_NUM_Magnitude__c;
      fact.currencyIso = rows[0].AXF_FTX_TXT_CurrencyIsoCode__c;
      fact.holderId = rows[0].AXF_FTX_LKP_Account__c;
    }
    if (String.isBlank(fact.identity)) {
      fact.identity = String.valueOf(fact.id);
    }
    fact.identity = fact.identity.left(128);
    if (
      fact.magnitude == null ||
      fact.magnitude <= 0 ||
      String.isBlank(fact.currencyIso) ||
      fact.holderId == null
    ) {
      throw failure('FACT_NOT_ALLOCATABLE', new List<String>());
    }
    return fact;
  }

  /** Lock order 60: the set. */
  private AXF_OBJ_EconomicAllocationSet__c lockSet(Id setId) {
    List<AXF_OBJ_EconomicAllocationSet__c> rows = [
      SELECT
        Id,
        AXF_EAS_LKP_BankTransaction__c,
        AXF_EAS_LKP_CardTransaction__c,
        AXF_EAS_LKP_FinancialTransaction__c,
        AXF_EAS_LKP_HolderAccount__c,
        AXF_EAS_PKL_State__c,
        AXF_EAS_NUM_FactMagnitude__c,
        AXF_EAS_TXT_CurrencyIsoCode__c,
        AXF_EAS_NUM_Revision__c,
        AXF_EAS_NUM_Version__c,
        AXF_EAS_TXT_OperationKey__c,
        AXF_EAS_TXT_ConfirmOperationKey__c
      FROM AXF_OBJ_EconomicAllocationSet__c
      WHERE Id = :setId
      WITH USER_MODE
      FOR UPDATE
    ];
    if (rows.isEmpty()) {
      throw failure('NOT_ACCESSIBLE', new List<String>());
    }
    return rows[0];
  }

  /** Only Person/Business holders visible to the caller through effective sharing qualify. */
  private Map<Id, Account> authorizedHolders(
    List<ShareInput> shares,
    List<String> reasons
  ) {
    Set<Id> ids = new Set<Id>();
    for (ShareInput share : shares) {
      ids.add(share.accountId);
    }
    Map<Id, Account> holders = new Map<Id, Account>(
      [
        SELECT Id, Name
        FROM Account
        WHERE Id IN :ids AND RecordType.DeveloperName IN :HOLDER_RECORD_TYPES
        WITH USER_MODE
      ]
    );
    for (Id accountId : ids) {
      if (!holders.containsKey(accountId)) {
        // Same answer whether the holder does not exist or is not authorized.
        reasons.add('UNAUTHORIZED_ACCOUNT:' + accountId);
      }
    }
    return holders;
  }

  private Id holderOwner(Id holderId) {
    List<Account> rows = [
      SELECT OwnerId
      FROM Account
      WHERE Id = :holderId
      WITH USER_MODE
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      throw failure('NOT_ACCESSIBLE', new List<String>());
    }
    return rows[0].OwnerId;
  }

  private Integer nextRevision(String identity) {
    return ALT_CLS_EconomicAllocationIntegrity.maxRevision(identity) + 1;
  }

  private List<AXF_OBJ_EconomicAllocationSet__c> existingByOperation(
    String operationKey
  ) {
    return [
      SELECT
        Id,
        AXF_EAS_LKP_BankTransaction__c,
        AXF_EAS_LKP_CardTransaction__c,
        AXF_EAS_LKP_FinancialTransaction__c,
        (
          SELECT AXF_EA_LKP_Account__c, AXF_EA_NUM_Percent__c
          FROM AXF_REL_Allocations__r
        )
      FROM AXF_OBJ_EconomicAllocationSet__c
      WHERE AXF_EAS_TXT_OperationKey__c = :operationKey
      WITH SYSTEM_MODE
      LIMIT 1
    ];
  }

  private static Boolean sameProposal(
    AXF_OBJ_EconomicAllocationSet__c existing,
    ProposeInput input
  ) {
    if (factId(existing) != input.factId) {
      return false;
    }
    Map<Id, Decimal> stored = new Map<Id, Decimal>();
    for (
      AXF_OBJ_EconomicAllocation__c allocation : existing.AXF_REL_Allocations__r
    ) {
      stored.put(
        allocation.AXF_EA_LKP_Account__c,
        allocation.AXF_EA_NUM_Percent__c
      );
    }
    if (stored.size() != input.shares.size()) {
      return false;
    }
    for (ShareInput share : input.shares) {
      Decimal percent = stored.get(share.accountId);
      if (
        percent == null ||
        percent.setScale(6) != nz(share.percent).setScale(6)
      ) {
        return false;
      }
    }
    return true;
  }

  private static String factKind(AXF_OBJ_EconomicAllocationSet__c row) {
    if (row.AXF_EAS_LKP_BankTransaction__c != null) {
      return 'BANK';
    }
    if (row.AXF_EAS_LKP_CardTransaction__c != null) {
      return 'CARD';
    }
    return 'MANUAL';
  }

  private static Id factId(AXF_OBJ_EconomicAllocationSet__c row) {
    if (row.AXF_EAS_LKP_BankTransaction__c != null) {
      return row.AXF_EAS_LKP_BankTransaction__c;
    }
    if (row.AXF_EAS_LKP_CardTransaction__c != null) {
      return row.AXF_EAS_LKP_CardTransaction__c;
    }
    return row.AXF_EAS_LKP_FinancialTransaction__c;
  }

  private static String activeToken(String identity) {
    return AXF_CLS_IdentityFraming.key(new List<Object>{ identity, 'ACTIVE' });
  }

  private static SetView toView(AXF_OBJ_EconomicAllocationSet__c row) {
    SetView view = new SetView();
    view.setId = row.Id;
    view.name = row.Name;
    view.factKind = factKind(row);
    view.factId = factId(row);
    view.factName = row.AXF_EAS_LKP_BankTransaction__r?.Name != null
      ? row.AXF_EAS_LKP_BankTransaction__r.Name
      : (row.AXF_EAS_LKP_CardTransaction__r?.Name != null
          ? row.AXF_EAS_LKP_CardTransaction__r.Name
          : row.AXF_EAS_LKP_FinancialTransaction__r?.Name);
    view.holderAccountId = row.AXF_EAS_LKP_HolderAccount__c;
    view.holderAccountName = row.AXF_EAS_LKP_HolderAccount__r?.Name;
    view.revision = Integer.valueOf(nz(row.AXF_EAS_NUM_Revision__c));
    view.state = row.AXF_EAS_PKL_State__c;
    view.factMagnitude = row.AXF_EAS_NUM_FactMagnitude__c;
    view.currencyIso = row.AXF_EAS_TXT_CurrencyIsoCode__c;
    view.version = row.AXF_EAS_NUM_Version__c;
    view.effectiveAt = row.AXF_EAS_DT_EffectiveAt__c;
    Decimal total = 0;
    for (
      AXF_OBJ_EconomicAllocation__c allocation : row.AXF_REL_Allocations__r
    ) {
      ShareView share = new ShareView();
      share.allocationId = allocation.Id;
      share.accountId = allocation.AXF_EA_LKP_Account__c;
      share.accountName = allocation.AXF_EA_LKP_Account__r?.Name;
      share.percent = allocation.AXF_EA_NUM_Percent__c;
      share.magnitude = allocation.AXF_EA_NUM_Magnitude__c;
      share.currencyIso = allocation.AXF_EA_TXT_CurrencyIsoCode__c;
      share.allocationKey = allocation.AXF_EA_EXI_AllocationKey__c;
      total += nz(allocation.AXF_EA_NUM_Percent__c);
      view.shares.add(share);
    }
    view.totalPercent = total.setScale(6);
    return view;
  }

  private static Decimal nz(Decimal value) {
    return value == null ? 0 : value;
  }

  private static EconomicAllocationException failure(
    String code,
    List<String> reasons
  ) {
    EconomicAllocationException result = new EconomicAllocationException(code);
    result.code = code;
    result.reasons = reasons;
    return result;
  }
}
