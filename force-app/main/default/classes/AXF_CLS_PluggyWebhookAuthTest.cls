/**
 * @description AXF-11 / G4-3. Shared-secret webhook auth: exact match, "Bearer " prefix,
 * wrong secret, blank inputs, and the constant-time compare itself.
 */
@IsTest
private class AXF_CLS_PluggyWebhookAuthTest {
  static final String SECRET = 'shared-webhook-secret-value';

  @IsTest
  static void acceptsExactMatch() {
    Assert.isTrue(
      AXF_CLS_PluggyWebhookAuth.isAuthorized(SECRET, SECRET),
      'The matching secret hash should be authorized.'
    );
  }

  @IsTest
  static void acceptsBearerPrefixed() {
    Assert.isTrue(
      AXF_CLS_PluggyWebhookAuth.isAuthorized('Bearer ' + SECRET, SECRET),
      'A Bearer-prefixed matching secret should be authorized.'
    );
  }

  @IsTest
  static void rejectsWrongSecret() {
    Assert.isFalse(
      AXF_CLS_PluggyWebhookAuth.isAuthorized('not-the-secret', SECRET),
      'A different secret must be rejected.'
    );
  }

  @IsTest
  static void rejectsDifferentLength() {
    Assert.isFalse(
      AXF_CLS_PluggyWebhookAuth.isAuthorized('short', SECRET),
      'A different-length secret must be rejected.'
    );
  }

  @IsTest
  static void rejectsBlankInputs() {
    Assert.isFalse(AXF_CLS_PluggyWebhookAuth.isAuthorized(null, SECRET));
    Assert.isFalse(AXF_CLS_PluggyWebhookAuth.isAuthorized('', SECRET));
    Assert.isFalse(AXF_CLS_PluggyWebhookAuth.isAuthorized(SECRET, null));
    Assert.isFalse(AXF_CLS_PluggyWebhookAuth.isAuthorized(SECRET, ''));
  }

  @IsTest
  static void constantTimeEqualsBasic() {
    Assert.isTrue(AXF_CLS_PluggyWebhookAuth.constantTimeEquals('abc', 'abc'));
    Assert.isFalse(AXF_CLS_PluggyWebhookAuth.constantTimeEquals('abc', 'abd'));
    Assert.isFalse(AXF_CLS_PluggyWebhookAuth.constantTimeEquals('abc', 'abcd'));
    Assert.isFalse(AXF_CLS_PluggyWebhookAuth.constantTimeEquals(null, 'abc'));
  }
}
