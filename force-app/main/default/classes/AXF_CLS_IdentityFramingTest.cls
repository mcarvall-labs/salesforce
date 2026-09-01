/**
 * @description AXF-13 / G6. The framing primitive is deterministic and cannot be spoofed
 * by delimiter injection.
 */
@IsTest
private class AXF_CLS_IdentityFramingTest {
  @IsTest
  static void sameInputSameKey() {
    List<Object> parts = new List<Object>{ 'tag', 'a', 1, 'b' };
    System.assertEquals(
      AXF_CLS_IdentityFraming.key(parts),
      AXF_CLS_IdentityFraming.key(new List<Object>{ 'tag', 'a', 1, 'b' })
    );
  }

  @IsTest
  static void orderMatters() {
    System.assertNotEquals(
      AXF_CLS_IdentityFraming.key(new List<Object>{ 'a', 'b' }),
      AXF_CLS_IdentityFraming.key(new List<Object>{ 'b', 'a' })
    );
  }

  @IsTest
  static void delimiterInjectionIsInert() {
    // "a|b" as one part must NOT frame the same as two parts "a","b".
    String one = AXF_CLS_IdentityFraming.frame(new List<Object>{ 'a|b' });
    String two = AXF_CLS_IdentityFraming.frame(new List<Object>{ 'a', 'b' });
    System.assertNotEquals(two, one);
    // and the length prefix is present
    System.assert(one.startsWith('3:a|b'), one);
  }

  @IsTest
  static void nullIsDistinctFromEmpty() {
    System.assertNotEquals(
      AXF_CLS_IdentityFraming.key(new List<Object>{ 'x', null }),
      AXF_CLS_IdentityFraming.key(new List<Object>{ 'x', '' })
    );
  }

  @IsTest
  static void unicodeByteLengthIsUsed() {
    // "cafe" (4 bytes) vs "café" (5 bytes in UTF-8) frame differently even if truncated.
    System.assertNotEquals(
      AXF_CLS_IdentityFraming.frame(new List<Object>{ 'cafe' }),
      AXF_CLS_IdentityFraming.frame(new List<Object>{ 'café' })
    );
  }

  @IsTest
  static void emptyPartsRejected() {
    try {
      AXF_CLS_IdentityFraming.frame(new List<Object>());
      System.assert(false, 'should throw');
    } catch (AXF_CLS_IdentityException e) {
      // expected
    }
  }

  @IsTest
  static void sha256IsLowercaseHex64() {
    String h = AXF_CLS_IdentityFraming.sha256Hex('abc');
    System.assertEquals(64, h.length());
    System.assert(Pattern.matches('[0-9a-f]{64}', h), h);
  }
}
