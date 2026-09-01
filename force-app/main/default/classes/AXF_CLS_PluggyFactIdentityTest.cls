/**
 * @description AXF-13 AC1/AC2/AC3, G6-1. Replay yields the same key; a locally-unique id
 * never collides across parents; exactly one of the two keys is produced.
 */
@IsTest
private class AXF_CLS_PluggyFactIdentityTest {
  @IsTest
  static void providerIdIsUsedVerbatim() {
    AXF_CLS_PluggyFactIdentity.Result r = AXF_CLS_PluggyFactIdentity.fromProviderId(
      '  0e2b-uuid  '
    );
    System.assertEquals(AXF_CLS_PluggyFactIdentity.KeyKind.PLUGGY_ID, r.kind);
    System.assertEquals('0e2b-uuid', r.pluggyId);
    System.assertEquals(null, r.fallbackKey);
  }

  @IsTest
  static void blankProviderIdRejected() {
    try {
      AXF_CLS_PluggyFactIdentity.fromProviderId('  ');
      System.assert(false, 'should throw');
    } catch (AXF_CLS_IdentityException e) {
      // expected
    }
  }

  @IsTest
  static void fallbackReplayIsStable() {
    AXF_CLS_PluggyFactIdentity.Result a = AXF_CLS_PluggyFactIdentity.fallback(
      'ACC-1',
      Date.newInstance(2026, 8, 31),
      -12.5,
      'Compra Cartão'
    );
    AXF_CLS_PluggyFactIdentity.Result b = AXF_CLS_PluggyFactIdentity.fallback(
      'ACC-1',
      Date.newInstance(2026, 8, 31),
      -12.50,
      'compra   cartao'
    );
    System.assertEquals(AXF_CLS_PluggyFactIdentity.KeyKind.FALLBACK, a.kind);
    System.assertEquals(
      a.fallbackKey,
      b.fallbackKey,
      'replay + normalization stable'
    );
    System.assertEquals(null, a.pluggyId);
    System.assertEquals(64, a.fallbackKey.length());
  }

  @IsTest
  static void sameLocalDataDifferentParentDoesNotCollide() {
    AXF_CLS_PluggyFactIdentity.Result p1 = AXF_CLS_PluggyFactIdentity.fallback(
      'ACC-1',
      Date.newInstance(2026, 8, 31),
      -12.5,
      'X'
    );
    AXF_CLS_PluggyFactIdentity.Result p2 = AXF_CLS_PluggyFactIdentity.fallback(
      'ACC-2',
      Date.newInstance(2026, 8, 31),
      -12.5,
      'X'
    );
    System.assertNotEquals(p1.fallbackKey, p2.fallbackKey);
  }

  @IsTest
  static void amountSignAndScaleMatter() {
    AXF_CLS_PluggyFactIdentity.Result neg = AXF_CLS_PluggyFactIdentity.fallback(
      'ACC-1',
      Date.newInstance(2026, 8, 31),
      -12.5,
      'X'
    );
    AXF_CLS_PluggyFactIdentity.Result pos = AXF_CLS_PluggyFactIdentity.fallback(
      'ACC-1',
      Date.newInstance(2026, 8, 31),
      12.5,
      'X'
    );
    System.assertNotEquals(neg.fallbackKey, pos.fallbackKey);
  }

  @IsTest
  static void fallbackRequiresParentDateAmount() {
    try {
      AXF_CLS_PluggyFactIdentity.fallback(null, Date.today(), 1, 'x');
      System.assert(false, 'should throw');
    } catch (AXF_CLS_IdentityException e) {
      // expected
    }
  }

  @IsTest
  static void isoDateIsZeroPadded() {
    System.assertEquals(
      '2026-01-05',
      AXF_CLS_PluggyFactIdentity.isoDate(Date.newInstance(2026, 1, 5))
    );
  }
}
