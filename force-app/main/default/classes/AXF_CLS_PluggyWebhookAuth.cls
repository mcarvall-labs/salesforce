/**
 * @description Authenticates an inbound Pluggy webhook. Pluggy does NOT sign its webhooks
 * (no HMAC, no signature header) — it only forwards the custom headers you register with
 * the webhook. So we register a shared secret as a header and compare it here, in constant
 * time, against the value in the protected CMT AXF_PluggyWebhookConfig__mdt. The secret is
 * never logged or echoed. AXF-11 / Fechamento G4-3.
 */
public with sharing class AXF_CLS_PluggyWebhookAuth {
  /**
   * @description True when a non-blank `presented` secret equals `expected`, compared in
   * constant time so a caller cannot learn it byte by byte. Tolerates a leading "Bearer ".
   * Returns false (never throws) for any blank input.
   * @param presented Secret received from the webhook header.
   * @param expected Expected secret stored in protected Custom Metadata.
   * @return True when both secrets match; otherwise false.
   */
  public static Boolean isAuthorized(String presented, String expected) {
    if (String.isBlank(presented) || String.isBlank(expected)) {
      return false;
    }
    String token = presented.trim();
    if (
      token.length() > 7 && token.substring(0, 7).equalsIgnoreCase('Bearer ')
    ) {
      token = token.substring(7).trim();
    }
    return constantTimeEquals(token, expected);
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
