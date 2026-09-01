/**
 * @description HMAC-SHA256 verification of an inbound Pluggy webhook body, with a
 * constant-time comparison so a caller cannot learn the expected digest byte by byte.
 * AXF-11 / Fechamento G4-3. The secret comes from AXF_EXC_PluggyWebhook and is never logged.
 */
public with sharing class AXF_CLS_PluggyWebhookSignature {
  /**
   * @description True when `signatureHeader` matches HMAC-SHA256(rawBody, secret).
   * Accepts the digest as lowercase/uppercase hex or base64. Returns false (never throws)
   * for any missing/blank input.
   */
  public static Boolean isValid(
    String rawBody,
    String signatureHeader,
    String secret
  ) {
    if (
      String.isBlank(rawBody) ||
      String.isBlank(signatureHeader) ||
      String.isBlank(secret)
    ) {
      return false;
    }
    Blob mac = Crypto.generateMac(
      'HmacSHA256',
      Blob.valueOf(rawBody),
      Blob.valueOf(secret)
    );
    String expectedHex = EncodingUtil.convertToHex(mac);
    String expectedB64 = EncodingUtil.base64Encode(mac);

    String provided = signatureHeader.trim();
    // Some senders prefix the scheme, e.g. "sha256=...."
    if (provided.contains('=') && provided.indexOf('=') < 12) {
      provided = provided.substringAfter('=');
    }

    return constantTimeEquals(
        provided.toLowerCase(),
        expectedHex.toLowerCase()
      ) || constantTimeEquals(provided, expectedB64);
  }

  @TestVisible
  private static Boolean constantTimeEquals(String a, String b) {
    if (a == null || b == null) {
      return false;
    }
    Integer diff = a.length() ^ b.length();
    Integer max = Math.max(a.length(), b.length());
    for (Integer i = 0; i < max; i++) {
      Integer ca = i < a.length() ? a.charAt(i) : 0;
      Integer cb = i < b.length() ? b.charAt(i) : 0;
      diff |= (ca ^ cb);
    }
    return diff == 0;
  }
}
