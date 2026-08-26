@IsTest
private class ALT_CLS_AxfCanonicalTest {
  @IsTest
  static void framingIsLengthPrefixedAndDeterministic() {
    String first = ALT_CLS_AxfCanonical.frame(new List<String>{ 'ab', 'c' });
    String second = ALT_CLS_AxfCanonical.frame(new List<String>{ 'a', 'bc' });
    System.assertNotEquals(
      first,
      second,
      'Length framing must prevent delimiter collisions.'
    );
    System.assertEquals(
      first,
      ALT_CLS_AxfCanonical.frame(new List<String>{ 'ab', 'c' })
    );
  }

  @IsTest
  static void entityReferenceNeverContainsSourceKeys() {
    String reference = ALT_CLS_AxfCanonical.entityRef(
      'HH_PRIMARY_V1',
      'fie-v1:00000000-0000-4000-8000-000000000000'
    );
    System.assertEquals(64, reference.length());
    System.assert(Pattern.matches('^[0-9a-f]{64}$', reference));
    System.assert(!reference.contains('HH_PRIMARY_V1'));
  }

  @IsTest
  static void nullFrameComponentFailsClosed() {
    try {
      ALT_CLS_AxfCanonical.frame(new List<String>{ 'scope', null });
      System.assert(false, 'Null components must be rejected.');
    } catch (ALT_CLS_AxfCanonical.AxfException expected) {
      System.assertEquals('INVALID_INPUT', expected.getMessage());
    }
    try {
      ALT_CLS_AxfCanonical.scopedHash(null);
      System.assert(false, 'Null component lists must be rejected.');
    } catch (ALT_CLS_AxfCanonical.AxfException expected) {
      System.assertEquals('INVALID_INPUT', expected.getMessage());
    }
  }
}
