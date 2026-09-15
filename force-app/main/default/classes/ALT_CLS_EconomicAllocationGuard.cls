/**
 * @description Integridade bulk do rateio economico (AXF-126). Visibilidade de sistema para
 * proteger referencias ocultas; chamado apenas pelos handlers de trigger.
 * - Sem Delete em set/parcela. - Set: identidade/ancora imutaveis; CONFIRMED imutavel exceto
 *   transicao para SUPERSEDED|REVERSED via servico; escrita somente pelo servico.
 * - AXF-128: a transicao que encerra a autoridade — o estado tem de realmente mudar para um
 *   estado final — apenas libera o token ativo (nunca o move para outro valor) e exige o conjunto
 *   compensatorio do mesmo fato, em revisao maior, ja existente na mesma transacao.
 * - Parcela: nasce/muda so pelo servico e so em set DRAFT; magnitude positiva; percentual em (0,100].
 * - AXF-129: o agregado so expressa cota de uma movimentacao positiva — o set nasce com magnitude
 *   de fato positiva e nenhuma parcela excede essa magnitude, de modo que nenhum valor exista ao
 *   lado ou alem da movimentacao (a forma de um saldo/obrigacao) e nenhuma divida seja gerada.
 */
public without sharing class ALT_CLS_EconomicAllocationGuard {
  private static Boolean writing = false;
  private static final Set<String> SET_FROZEN = new Set<String>{
    'AXF_EAS_LKP_BankTransaction__c',
    'AXF_EAS_LKP_CardTransaction__c',
    'AXF_EAS_LKP_FinancialTransaction__c',
    'AXF_EAS_LKP_HolderAccount__c',
    'AXF_EAS_TXT_FactIdentity__c',
    'AXF_EAS_NUM_Revision__c',
    'AXF_EAS_EXI_SetKey__c',
    'AXF_EAS_NUM_FactMagnitude__c',
    'AXF_EAS_TXT_CurrencyIsoCode__c'
  };
  private static final Map<String, Set<String>> TRANSITIONS = new Map<String, Set<String>>{
    'DRAFT' => new Set<String>{ 'CONFIRMED', 'DISCARDED' },
    'CONFIRMED' => new Set<String>{ 'SUPERSEDED', 'REVERSED' },
    'SUPERSEDED' => new Set<String>(),
    'REVERSED' => new Set<String>(),
    'DISCARDED' => new Set<String>()
  };
  /** Once confirmed only the state (and the optimistic version) may move. */
  private static final Set<String> CONFIRMED_MUTABLE = new Set<String>{
    'AXF_EAS_PKL_State__c',
    'AXF_EAS_NUM_Version__c'
  };
  /**
   * Fields a CONFIRMED set may still move *while its authority ends* (CONFIRMED -> SUPERSEDED |
   * REVERSED, AXF-128): the single active token is released to the compensating set in the same
   * transaction, and the derived singular projection does not outlive the set's authority
   * (AXF-127). Both are transition bookkeeping, never content, and neither is accepted while the
   * set stays CONFIRMED — so the projection still cannot be turned into an authority.
   */
  private static final Set<String> ENDING_AUTHORITY_MUTABLE = new Set<String>{
    'AXF_EAS_EXI_ActiveToken__c',
    'AXF_EAS_LKP_AttributedAccount__c'
  };
  private static final Set<String> ENDING_STATES = new Set<String>{
    'SUPERSEDED',
    'REVERSED'
  };
  private static final Set<String> ALLOCATION_FROZEN = new Set<String>{
    'AXF_EA_MDR_AllocationSet__c',
    'AXF_EA_LKP_Account__c',
    'AXF_EA_EXI_AllocationKey__c',
    'AXF_EA_TXT_CurrencyIsoCode__c'
  };

  public static void beginWrite() {
    writing = true;
  }
  public static void endWrite() {
    writing = false;
  }
  public static Boolean isWriting() {
    return writing;
  }

  public static void sets(
    List<AXF_OBJ_EconomicAllocationSet__c> rows,
    Map<Id, AXF_OBJ_EconomicAllocationSet__c> oldMap,
    Boolean deleting
  ) {
    // An authority never ends into nothing: the compensating set of the same fact is written in
    // the same transaction, so the handover is looked up once for the whole DML, never per row.
    Map<Id, Boolean> handedOver = oldMap == null
      ? new Map<Id, Boolean>()
      : liveSuccessorExists(rows, oldMap);
    for (AXF_OBJ_EconomicAllocationSet__c row : rows) {
      if (deleting) {
        row.addError('Economic allocation sets cannot be deleted.');
        continue;
      }
      if (!writing) {
        row.addError('Use the economic allocation service.');
        continue;
      }
      if (oldMap == null) {
        if (row.AXF_EAS_PKL_State__c == null) {
          row.AXF_EAS_PKL_State__c = 'DRAFT';
        }
        if (row.AXF_EAS_PKL_State__c != 'DRAFT') {
          row.addError('An economic allocation set starts as DRAFT.');
        }
        // AXF-129/AC-1: the aggregate only ever expresses a share of a positive movement, so a set
        // with no positive movement cannot exist — an amount that stands without a movement is the
        // shape of a balance, not of a share.
        if (
          row.AXF_EAS_NUM_FactMagnitude__c == null ||
          row.AXF_EAS_NUM_FactMagnitude__c <= 0
        ) {
          row.addError('An economic allocation shares a positive movement.');
        }
        continue;
      }
      AXF_OBJ_EconomicAllocationSet__c before = oldMap.get(row.Id);
      for (String field : SET_FROZEN) {
        if (row.get(field) != before.get(field)) {
          row.addError('Economic allocation identity is immutable.');
          break;
        }
      }
      // AXF-128: the release of the active token and of the projection is derived from the actual
      // transition — the state must really change into an ending state — and never from the
      // incoming state value, so re-asserting a state the set already has (REVERSED -> REVERSED,
      // SUPERSEDED -> SUPERSEDED) frees nothing.
      Boolean endingAuthority = endsAuthority(before, row);
      if (
        before.AXF_EAS_PKL_State__c != 'DRAFT' &&
        before.AXF_EAS_PKL_State__c != null
      ) {
        for (String field : row.getPopulatedFieldsAsMap().keySet()) {
          if (
            !field.endsWith('__c') ||
            CONFIRMED_MUTABLE.contains(field) ||
            row.get(field) == before.get(field)
          ) {
            continue;
          }
          if (endingAuthority && ENDING_AUTHORITY_MUTABLE.contains(field)) {
            continue;
          }
          row.addError('Confirmed economic allocation content is immutable.');
          break;
        }
      }
      if (endingAuthority) {
        // The token is only ever released, never moved to another value: it is unique, so a value
        // planted here would block another fact's propose for good (ACTIVE_SET_EXISTS). The record
        // under write is what the database will hold, so a non-null value there is the attack.
        if (row.AXF_EAS_EXI_ActiveToken__c != null) {
          row.addError(
            'Ending the authority releases the active token; it never moves.'
          );
        }
        // And the handover must already exist: no confirmation ends without its compensation.
        Boolean successor = handedOver.get(row.Id);
        if (successor == null || !successor) {
          row.addError(
            'Ending the authority requires a live successor set of the same fact.'
          );
        }
      }
      if (row.AXF_EAS_PKL_State__c != before.AXF_EAS_PKL_State__c) {
        Set<String> allowed = TRANSITIONS.get(before.AXF_EAS_PKL_State__c);
        if (allowed == null || !allowed.contains(row.AXF_EAS_PKL_State__c)) {
          row.addError('Invalid economic allocation state transition.');
        }
      }
    }
  }

  /** The authority ends only when the state really changes into an ending state. */
  private static Boolean endsAuthority(
    AXF_OBJ_EconomicAllocationSet__c before,
    AXF_OBJ_EconomicAllocationSet__c incoming
  ) {
    return before != null &&
      before.AXF_EAS_PKL_State__c == 'CONFIRMED' &&
      incoming.AXF_EAS_PKL_State__c != before.AXF_EAS_PKL_State__c &&
      ENDING_STATES.contains(incoming.AXF_EAS_PKL_State__c);
  }

  /** The typed fact anchor, the only fact key a partial update always carries. */
  private static Id anchorOf(AXF_OBJ_EconomicAllocationSet__c row) {
    if (row.AXF_EAS_LKP_BankTransaction__c != null) {
      return row.AXF_EAS_LKP_BankTransaction__c;
    }
    if (row.AXF_EAS_LKP_CardTransaction__c != null) {
      return row.AXF_EAS_LKP_CardTransaction__c;
    }
    return row.AXF_EAS_LKP_FinancialTransaction__c;
  }

  private static Integer revisionOf(AXF_OBJ_EconomicAllocationSet__c row) {
    return row.AXF_EAS_NUM_Revision__c == null
      ? 0
      : Integer.valueOf(row.AXF_EAS_NUM_Revision__c);
  }

  /**
   * Whether every set ending its authority in this DML already has a handover: a live set (DRAFT
   * or CONFIRMED) of the same fact, at a strictly higher revision, present in the same transaction.
   * Keyed by the Id of the ending set. The sets being ended are excluded from the successors — they
   * are still CONFIRMED in the database at this point — so a set can never be its own successor,
   * and their revision is taken from the database, never from the update payload. Anchors are used
   * because a partial update carries no fact identity.
   */
  @SuppressWarnings('PMD.ApexCRUDViolation')
  private static Map<Id, Boolean> liveSuccessorExists(
    List<AXF_OBJ_EconomicAllocationSet__c> rows,
    Map<Id, AXF_OBJ_EconomicAllocationSet__c> oldMap
  ) {
    Map<Id, Boolean> result = new Map<Id, Boolean>();
    Map<Id, Integer> ownRevision = new Map<Id, Integer>();
    Map<Id, Id> anchorBySet = new Map<Id, Id>();
    Set<Id> endingIds = new Set<Id>();
    Set<Id> bankIds = new Set<Id>();
    Set<Id> cardIds = new Set<Id>();
    Set<Id> manualIds = new Set<Id>();
    for (AXF_OBJ_EconomicAllocationSet__c row : rows) {
      if (!endsAuthority(oldMap.get(row.Id), row)) {
        continue;
      }
      endingIds.add(row.Id);
      anchorBySet.put(row.Id, anchorOf(row));
      ownRevision.put(row.Id, revisionOf(oldMap.get(row.Id)));
      if (row.AXF_EAS_LKP_BankTransaction__c != null) {
        bankIds.add(row.AXF_EAS_LKP_BankTransaction__c);
      } else if (row.AXF_EAS_LKP_CardTransaction__c != null) {
        cardIds.add(row.AXF_EAS_LKP_CardTransaction__c);
      } else if (row.AXF_EAS_LKP_FinancialTransaction__c != null) {
        manualIds.add(row.AXF_EAS_LKP_FinancialTransaction__c);
      }
    }
    if (endingIds.isEmpty()) {
      return result;
    }
    Map<Id, Integer> best = new Map<Id, Integer>();
    for (AXF_OBJ_EconomicAllocationSet__c row : [
      SELECT
        Id,
        AXF_EAS_LKP_BankTransaction__c,
        AXF_EAS_LKP_CardTransaction__c,
        AXF_EAS_LKP_FinancialTransaction__c,
        AXF_EAS_NUM_Revision__c
      FROM AXF_OBJ_EconomicAllocationSet__c
      WHERE
        Id IN :endingIds
        OR (AXF_EAS_PKL_State__c IN ('DRAFT', 'CONFIRMED')
        AND (AXF_EAS_LKP_BankTransaction__c IN :bankIds
        OR AXF_EAS_LKP_CardTransaction__c IN :cardIds
        OR AXF_EAS_LKP_FinancialTransaction__c IN :manualIds))
    ]) {
      if (endingIds.contains(row.Id)) {
        ownRevision.put(row.Id, revisionOf(row));
        continue;
      }
      Id anchor = anchorOf(row);
      Integer revision = revisionOf(row);
      Integer current = best.get(anchor);
      if (current == null || revision > current) {
        best.put(anchor, revision);
      }
    }
    for (Id setId : endingIds) {
      Integer successor = best.get(anchorBySet.get(setId));
      Integer own = ownRevision.get(setId);
      result.put(setId, successor != null && own != null && successor > own);
    }
    return result;
  }

  // Trigger integrity must see the parent set regardless of the caller's CRUD permissions.
  @SuppressWarnings('PMD.ApexCRUDViolation')
  public static void allocations(
    List<AXF_OBJ_EconomicAllocation__c> rows,
    Map<Id, AXF_OBJ_EconomicAllocation__c> oldMap,
    Boolean deleting
  ) {
    if (deleting || !writing) {
      // Unconditional refusals need no parent lookup.
      for (AXF_OBJ_EconomicAllocation__c row : rows) {
        row.addError(
          deleting
            ? 'Economic allocations cannot be deleted; reverse with a compensating set.'
            : 'Use the economic allocation service.'
        );
      }
      return;
    }
    Set<Id> setIds = new Set<Id>();
    for (AXF_OBJ_EconomicAllocation__c row : rows) {
      setIds.add(row.AXF_EA_MDR_AllocationSet__c);
    }
    Map<Id, AXF_OBJ_EconomicAllocationSet__c> parents = new Map<Id, AXF_OBJ_EconomicAllocationSet__c>(
      [
        SELECT Id, AXF_EAS_PKL_State__c, AXF_EAS_NUM_FactMagnitude__c
        FROM AXF_OBJ_EconomicAllocationSet__c
        WHERE Id IN :setIds
      ]
    );
    for (AXF_OBJ_EconomicAllocation__c row : rows) {
      if (oldMap != null) {
        AXF_OBJ_EconomicAllocation__c before = oldMap.get(row.Id);
        Boolean frozenChanged = false;
        for (String field : ALLOCATION_FROZEN) {
          if (row.get(field) != before.get(field)) {
            frozenChanged = true;
          }
        }
        if (frozenChanged) {
          row.addError('Economic allocation share identity is immutable.');
          continue;
        }
      }
      AXF_OBJ_EconomicAllocationSet__c parent = parents.get(
        row.AXF_EA_MDR_AllocationSet__c
      );
      if (parent == null || parent.AXF_EAS_PKL_State__c != 'DRAFT') {
        row.addError('Only DRAFT sets accept allocation changes.');
        continue;
      }
      if (
        row.AXF_EA_NUM_Magnitude__c == null ||
        row.AXF_EA_NUM_Magnitude__c <= 0 ||
        row.AXF_EA_NUM_Percent__c == null ||
        row.AXF_EA_NUM_Percent__c <= 0 ||
        row.AXF_EA_NUM_Percent__c > 100
      ) {
        row.addError('Allocation magnitude and percent must be positive.');
      } else if (
        parent.AXF_EAS_NUM_FactMagnitude__c != null &&
        row.AXF_EA_NUM_Magnitude__c > parent.AXF_EAS_NUM_FactMagnitude__c
      ) {
        // AXF-129/AC-1: a parcel is a share of the movement, never an amount beside or beyond it.
        // An amount outside the movement is the shape of an obligation — a debt or a balance
        // created on top of the fact — and the aggregate cannot express one.
        row.addError(
          'An allocation share cannot exceed the movement it shares.'
        );
      }
    }
  }
}
