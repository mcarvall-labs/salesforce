/**
 * @description AXF-13 AC3/AC4/AC5/AC7, G6. Record is idempotent and never verifies;
 * verify enforces one VERIFIED per scope and is authority-gated; unknown access is denied
 * without revealing existence.
 */
@IsTest
private class AXF_CLS_SourceEquivalenceServiceTest {
  static AXF_OBJ_PluggyConnection__c conn() {
    return AXF_CLS_PluggyTestData.connection('ITEM_A');
  }

  @IsTest
  static void recordIsPendingAndIdempotent() {
    AXF_OBJ_PluggyConnection__c c = conn();
    AXF_CLS_SourceEquivalenceService svc = new AXF_CLS_SourceEquivalenceService();

    AXF_CLS_SourceEquivalenceService.EquivalenceResult r1 = svc.record(
      c.Id,
      'HASH_T1',
      'observado no reconnect'
    );
    AXF_CLS_SourceEquivalenceService.EquivalenceResult r2 = svc.record(
      c.Id,
      'HASH_T1',
      'again'
    );

    System.assertEquals('PENDING', r1.state);
    System.assertEquals(r1.equivalenceId, r2.equivalenceId, 'idempotent');
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM AXF_OBJ_SourceEquivalence__c
        WHERE Id = :r1.equivalenceId
      ]
    );
  }

  @IsTest
  static void verifyRequiresAuthority() {
    AXF_OBJ_PluggyConnection__c c = conn();
    AXF_CLS_SourceEquivalenceService svc = new AXF_CLS_SourceEquivalenceService();
    Id eid = svc.record(c.Id, 'HASH_T1', null).equivalenceId;

    AXF_CLS_SourceEquivalenceService.canVerifyOverride = false;
    try {
      svc.verify(eid);
      System.assert(false, 'unauthorized verify must fail');
    } catch (AXF_CLS_IdentityException e) {
      System.assert(e.getMessage().containsIgnoreCase('autoriza'));
    }
  }

  @IsTest
  static void verifyIsIdempotentAndResolves() {
    AXF_OBJ_PluggyConnection__c c = conn();
    AXF_CLS_SourceEquivalenceService svc = new AXF_CLS_SourceEquivalenceService();
    AXF_CLS_SourceEquivalenceService.canVerifyOverride = true;
    Id eid = svc.record(c.Id, 'HASH_T1', null).equivalenceId;

    System.assertEquals('VERIFIED', svc.verify(eid).state);
    System.assertEquals('VERIFIED', svc.verify(eid).state, 'idempotent');
    System.assertEquals(c.Id, svc.resolveStableConnection('HASH_T1'));
    System.assertEquals(null, svc.resolveStableConnection('HASH_OTHER'));
  }

  @IsTest
  static void onlyOneVerifiedPerScopeConflicts() {
    AXF_OBJ_PluggyConnection__c c = conn();
    AXF_CLS_SourceEquivalenceService.canVerifyOverride = true;
    AXF_CLS_SourceEquivalenceService svc = new AXF_CLS_SourceEquivalenceService();

    Id first = svc.record(c.Id, 'HASH_T1', null).equivalenceId;
    svc.verify(first);

    // a second row on the same scope guard, forced in, then verify => CONFLICT
    AXF_OBJ_SourceEquivalence__c dup = [
      SELECT
        AXF_SEQ_TXT_ScopeGuard__c,
        AXF_SEQ_LKP_StableConnection__c,
        AXF_SEQ_TXT_TransientIdentityHash__c
      FROM AXF_OBJ_SourceEquivalence__c
      WHERE Id = :first
    ];
    AXF_OBJ_SourceEquivalence__c dup2 = new AXF_OBJ_SourceEquivalence__c(
      AXF_SEQ_LKP_StableConnection__c = dup.AXF_SEQ_LKP_StableConnection__c,
      AXF_SEQ_TXT_TransientIdentityHash__c = dup.AXF_SEQ_TXT_TransientIdentityHash__c,
      AXF_SEQ_PKL_State__c = 'PENDING',
      AXF_SEQ_TXT_ScopeGuard__c = dup.AXF_SEQ_TXT_ScopeGuard__c,
      AXF_SEQ_EXI_EquivalenceKey__c = AXF_CLS_IdentityFraming.key(
        new List<Object>{ 'seq-v1', c.Id, 'HASH_T1_ALT' }
      )
    );
    insert dup2;

    try {
      svc.verify(dup2.Id);
      System.assert(false, 'second verify on scope must conflict');
    } catch (AXF_CLS_IdentityException e) {
      System.assert(e.getMessage().containsIgnoreCase('CONFLICT'));
    }
  }

  @IsTest
  static void rejectedCannotBeVerified() {
    AXF_OBJ_PluggyConnection__c c = conn();
    AXF_CLS_SourceEquivalenceService.canVerifyOverride = true;
    AXF_CLS_SourceEquivalenceService svc = new AXF_CLS_SourceEquivalenceService();
    Id eid = svc.record(c.Id, 'HASH_T1', null).equivalenceId;

    System.assertEquals('REJECTED', svc.reject(eid).state);
    try {
      svc.verify(eid);
      System.assert(false, 'verify after reject must fail');
    } catch (AXF_CLS_IdentityException e) {
      // expected
    }
  }

  @IsTest
  static void rejectRequiresAuthority() {
    AXF_OBJ_PluggyConnection__c c = conn();
    AXF_CLS_SourceEquivalenceService svc = new AXF_CLS_SourceEquivalenceService();
    Id eid = svc.record(c.Id, 'HASH_T1', null).equivalenceId;

    AXF_CLS_SourceEquivalenceService.canVerifyOverride = false;
    try {
      svc.reject(eid);
      System.assert(false, 'unauthorized reject must fail');
    } catch (AXF_CLS_IdentityException e) {
      System.assert(e.getMessage().containsIgnoreCase('autoriza'));
    }
  }

  @IsTest
  static void blankTransientHashRejected() {
    AXF_OBJ_PluggyConnection__c c = conn();
    try {
      new AXF_CLS_SourceEquivalenceService().record(c.Id, '  ', null);
      System.assert(false, 'blank hash must fail');
    } catch (AXF_CLS_IdentityException e) {
      // expected
    }
    System.assertEquals(
      null,
      new AXF_CLS_SourceEquivalenceService().resolveStableConnection(null)
    );
  }

  @IsTest
  static void unknownConnectionIsDeniedWithoutRevealing() {
    AXF_OBJ_PluggyConnection__c gone = conn();
    Id goneId = gone.Id;
    delete gone;

    AXF_CLS_SourceEquivalenceService svc = new AXF_CLS_SourceEquivalenceService();
    try {
      svc.record(goneId, 'HASH_T1', null);
      System.assert(false, 'must deny');
    } catch (AXF_CLS_IdentityException e) {
      System.assert(e.getMessage().containsIgnoreCase('nao encontrada'));
    }
  }
}
