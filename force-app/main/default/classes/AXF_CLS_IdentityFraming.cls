/**
 * @description Canonical framing + hashing primitive for Pluggy external identity (AXF-13,
 * Fechamento G6). Every composite key in the ingestion chain is
 * `sha256Hex(frame(tag, part1, part2, ...))`.
 *
 * `frame` is length-prefixed UTF-8: each part is emitted as `<byteLength>:<value>` joined
 * by a delimiter. Because the byte length precedes the value, no part can be crafted to
 * impersonate a different sequence of parts (delimiter injection is inert). `null` is a
 * distinct token, never the empty string.
 *
 * This class is pure and deterministic — no SOQL, no DML, no describe calls.
 */
public inherited sharing class AXF_CLS_IdentityFraming {
  @TestVisible
  private static final String DELIMITER = '|';
  @TestVisible
  private static final String NULL_TOKEN = '#null#';

  private AXF_CLS_IdentityFraming() {
  }

  /**
   * @description Length-prefixed UTF-8 framing of an ordered list of parts. Order matters.
   */
  public static String frame(List<Object> parts) {
    if (parts == null || parts.isEmpty()) {
      throw new AXF_CLS_IdentityException(
        'frame() requires at least one part.'
      );
    }
    List<String> framed = new List<String>();
    for (Object part : parts) {
      String value = (part == null) ? NULL_TOKEN : String.valueOf(part);
      Integer byteLength = Blob.valueOf(value).size();
      framed.add(byteLength + ':' + value);
    }
    return String.join(framed, DELIMITER);
  }

  /**
   * @description Lower-case hex SHA-256 of the UTF-8 bytes of `value`.
   */
  public static String sha256Hex(String value) {
    Blob digest = Crypto.generateDigest('SHA-256', Blob.valueOf(value));
    return EncodingUtil.convertToHex(digest);
  }

  /**
   * @description Convenience: `sha256Hex(frame(parts))`.
   */
  public static String key(List<Object> parts) {
    return sha256Hex(frame(parts));
  }
}
