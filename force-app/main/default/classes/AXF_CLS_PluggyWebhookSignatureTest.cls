/**
 * @description AXF-11 / G4-3. HMAC verification: valid hex, valid base64, wrong secret,
 * wrong length, blank input, and the scheme prefix form.
 */
@IsTest
private class AXF_CLS_PluggyWebhookSignatureTest {
  static final String BODY = '{"event":"item/updated","itemId":"abc"}';
  static final String SECRET = 'shared-webhook-secret';

  static String hexHmac(String body, String secret) {
    return EncodingUtil.convertToHex(
      Crypto.generateMac('HmacSHA256', Blob.valueOf(body), Blob.valueOf(secret))
    );
  }
  static String b64Hmac(String body, String secret) {
    return EncodingUtil.base64Encode(
      Crypto.generateMac('HmacSHA256', Blob.valueOf(body), Blob.valueOf(secret))
    );
  }

  @IsTest
  static void acceptsValidHex() {
    System.assert(
      AXF_CLS_PluggyWebhookSignature.isValid(
        BODY,
        hexHmac(BODY, SECRET),
        SECRET
      )
    );
  }

  @IsTest
  static void acceptsValidHexWithSchemePrefix() {
    System.assert(
      AXF_CLS_PluggyWebhookSignature.isValid(
        BODY,
        'sha256=' + hexHmac(BODY, SECRET),
        SECRET
      )
    );
  }

  @IsTest
  static void acceptsValidBase64() {
    System.assert(
      AXF_CLS_PluggyWebhookSignature.isValid(
        BODY,
        b64Hmac(BODY, SECRET),
        SECRET
      )
    );
  }

  @IsTest
  static void rejectsWrongSecret() {
    System.assert(
      !AXF_CLS_PluggyWebhookSignature.isValid(
        BODY,
        hexHmac(BODY, 'other'),
        SECRET
      )
    );
  }

  @IsTest
  static void rejectsTamperedBody() {
    System.assert(
      !AXF_CLS_PluggyWebhookSignature.isValid(
        BODY + ' ',
        hexHmac(BODY, SECRET),
        SECRET
      )
    );
  }

  @IsTest
  static void rejectsBlankInputs() {
    System.assert(!AXF_CLS_PluggyWebhookSignature.isValid(null, 'x', SECRET));
    System.assert(!AXF_CLS_PluggyWebhookSignature.isValid(BODY, null, SECRET));
    System.assert(!AXF_CLS_PluggyWebhookSignature.isValid(BODY, 'x', null));
  }

  @IsTest
  static void rejectsDifferentLength() {
    System.assert(
      !AXF_CLS_PluggyWebhookSignature.isValid(BODY, 'abcd', SECRET)
    );
  }

  @IsTest
  static void constantTimeEqualsBasic() {
    System.assert(
      AXF_CLS_PluggyWebhookSignature.constantTimeEquals('abc', 'abc')
    );
    System.assert(
      !AXF_CLS_PluggyWebhookSignature.constantTimeEquals('abc', 'abd')
    );
    System.assert(
      !AXF_CLS_PluggyWebhookSignature.constantTimeEquals('abc', 'abcd')
    );
  }
}
