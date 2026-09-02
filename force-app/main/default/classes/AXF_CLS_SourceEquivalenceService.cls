/**
 * @description Reconnection equivalence for Pluggy sources (AXF-13 AC3/AC4/AC5, Fechamento
 * G6). When a reconnected item is proven equivalent to an existing stable connection, this
 * records a revisioned link WITHOUT renumbering the published economic identity and WITHOUT
 * merging anything. Similarity alone never verifies — a PENDING row waits for a human.
 *
 * Invariants:
 *  - an alias points from a transient identity hash straight to a stable connection, never
 *    to another equivalence (no chains, no cycles);
 *  - at most one VERIFIED equivalence per ScopeGuard (provider + connection + transientHash);
 *  - repeat of the same (connection, transientHash) is idempotent (EquivalenceKey unique);
 *  - a concurrent verify with the same target reuses the result; a different target is
 *    CONFLICT;
 *  - a caller without access to the connection's holder is denied without revealing
 *    whether the equivalence exists.
 */
public with sharing class AXF_CLS_SourceEquivalenceService {
  @TestVisible
  private static Boolean canVerifyOverride;

  private static final String PROVIDER = 'pluggy';

  private Boolean callerCanVerify() {
    if (canVerifyOverride != null) {
      return canVerifyOverride;
    }
    return FeatureManagement.checkPermission('AXF_CanConfigure');
  }

  public class EquivalenceResult {
    @AuraEnabled
    public Id equivalenceId;
    @AuraEnabled
    public String state;
    @AuraEnabled
    public String message;
  }

  /**
   * @description Stages an equivalence for human review. Idempotent on
   * (connection, transientIdentityHash). Never verifies.
   */
  public EquivalenceResult record(
    Id stableConnectionId,
    String transientIdentityHash,
    String evidence
  ) {
    assertConnectionVisible(stableConnectionId);
    if (String.isBlank(transientIdentityHash)) {
      throw new AXF_CLS_IdentityException('transientIdentityHash is required.');
    }

    String equivalenceKey = AXF_CLS_IdentityFraming.key(
      new List<Object>{ 'seq-v1', stableConnectionId, transientIdentityHash }
    );

    List<AXF_OBJ_SourceEquivalence__c> existing = [
      SELECT Id, AXF_SEQ_PKL_State__c
      FROM AXF_OBJ_SourceEquivalence__c
      WHERE AXF_SEQ_EXI_EquivalenceKey__c = :equivalenceKey
      WITH USER_MODE
      LIMIT 1
    ];

    EquivalenceResult out = new EquivalenceResult();
    if (!existing.isEmpty()) {
      out.equivalenceId = existing[0].Id;
      out.state = existing[0].AXF_SEQ_PKL_State__c;
      out.message = 'Equivalencia ja registrada.';
      return out;
    }

    AXF_OBJ_SourceEquivalence__c seq = new AXF_OBJ_SourceEquivalence__c(
      AXF_SEQ_LKP_StableConnection__c = stableConnectionId,
      AXF_SEQ_TXT_TransientIdentityHash__c = transientIdentityHash,
      AXF_SEQ_PKL_State__c = 'PENDING',
      AXF_SEQ_TXT_ScopeGuard__c = scopeGuard(
        stableConnectionId,
        transientIdentityHash
      ),
      AXF_SEQ_EXI_EquivalenceKey__c = equivalenceKey,
      AXF_SEQ_TAL_Evidence__c = evidence
    );
    insert as user seq;

    out.equivalenceId = seq.Id;
    out.state = 'PENDING';
    out.message = 'Equivalencia registrada para revisao.';
    return out;
  }

  /**
   * @description Marks a PENDING equivalence VERIFIED. Enforces one VERIFIED per scope.
   */
  public EquivalenceResult verify(Id equivalenceId) {
    if (!callerCanVerify()) {
      throw new AXF_CLS_IdentityException(
        'Voce nao tem autorizacao para verificar equivalencias de fonte.'
      );
    }

    AXF_OBJ_SourceEquivalence__c seq = [
      SELECT
        Id,
        AXF_SEQ_PKL_State__c,
        AXF_SEQ_TXT_ScopeGuard__c,
        AXF_SEQ_LKP_StableConnection__c
      FROM AXF_OBJ_SourceEquivalence__c
      WHERE Id = :equivalenceId
      WITH USER_MODE
      LIMIT 1
    ];
    assertConnectionVisible(seq.AXF_SEQ_LKP_StableConnection__c);

    EquivalenceResult out = new EquivalenceResult();
    out.equivalenceId = seq.Id;

    if (seq.AXF_SEQ_PKL_State__c == 'VERIFIED') {
      out.state = 'VERIFIED';
      out.message = 'Ja verificada (idempotente).';
      return out;
    }
    if (seq.AXF_SEQ_PKL_State__c == 'REJECTED') {
      throw new AXF_CLS_IdentityException(
        'Equivalencia rejeitada nao pode ser verificada.'
      );
    }

    List<AXF_OBJ_SourceEquivalence__c> otherVerified = [
      SELECT Id
      FROM AXF_OBJ_SourceEquivalence__c
      WHERE
        AXF_SEQ_TXT_ScopeGuard__c = :seq.AXF_SEQ_TXT_ScopeGuard__c
        AND AXF_SEQ_PKL_State__c = 'VERIFIED'
        AND Id != :seq.Id
      WITH USER_MODE
    ];
    if (!otherVerified.isEmpty()) {
      throw new AXF_CLS_IdentityException(
        'CONFLICT: ja existe uma equivalencia verificada para este escopo.'
      );
    }

    seq.AXF_SEQ_PKL_State__c = 'VERIFIED';
    seq.AXF_SEQ_LKP_VerifiedByUser__c = UserInfo.getUserId();
    seq.AXF_SEQ_DT_VerifiedAt__c = Datetime.now();
    update as user seq;

    out.state = 'VERIFIED';
    out.message = 'Equivalencia verificada.';
    return out;
  }

  public EquivalenceResult reject(Id equivalenceId) {
    if (!callerCanVerify()) {
      throw new AXF_CLS_IdentityException(
        'Voce nao tem autorizacao para rejeitar equivalencias de fonte.'
      );
    }
    AXF_OBJ_SourceEquivalence__c seq = [
      SELECT Id, AXF_SEQ_PKL_State__c, AXF_SEQ_LKP_StableConnection__c
      FROM AXF_OBJ_SourceEquivalence__c
      WHERE Id = :equivalenceId
      WITH USER_MODE
      LIMIT 1
    ];
    assertConnectionVisible(seq.AXF_SEQ_LKP_StableConnection__c);
    seq.AXF_SEQ_PKL_State__c = 'REJECTED';
    update as user seq;

    EquivalenceResult out = new EquivalenceResult();
    out.equivalenceId = seq.Id;
    out.state = 'REJECTED';
    out.message = 'Equivalencia rejeitada.';
    return out;
  }

  /**
   * @description The verified stable connection for a transient identity hash, or null.
   * Only VERIFIED participates. Returns null (not an error) when nothing matches — an
   * unauthorized caller and a genuine miss are indistinguishable to the caller.
   */
  public Id resolveStableConnection(String transientIdentityHash) {
    if (String.isBlank(transientIdentityHash)) {
      return null;
    }
    for (AXF_OBJ_SourceEquivalence__c seq : [
      SELECT AXF_SEQ_LKP_StableConnection__c
      FROM AXF_OBJ_SourceEquivalence__c
      WHERE
        AXF_SEQ_TXT_TransientIdentityHash__c = :transientIdentityHash
        AND AXF_SEQ_PKL_State__c = 'VERIFIED'
      WITH USER_MODE
      LIMIT 1
    ]) {
      return seq.AXF_SEQ_LKP_StableConnection__c;
    }
    return null;
  }

  private void assertConnectionVisible(Id connectionId) {
    // USER_MODE query: a caller without sharing on the holder's connection gets 0 rows,
    // which we surface as "not found" — never confirming existence.
    List<AXF_OBJ_PluggyConnection__c> rows = [
      SELECT Id
      FROM AXF_OBJ_PluggyConnection__c
      WHERE Id = :connectionId
      WITH USER_MODE
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      throw new AXF_CLS_IdentityException('Conexao nao encontrada.');
    }
  }

  private String scopeGuard(Id connectionId, String transientHash) {
    return PROVIDER + '|' + connectionId + '|' + transientHash;
  }
}
