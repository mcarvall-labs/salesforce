/**
 * @description AXF-11 AC1. The writer forwards Client ID / Secret to the native mechanism
 * and never echoes them. The ConnectApi body itself is exercised only in a real org
 * (guarded by Test.isRunningTest); here we assert routing and blank handling.
 */
@IsTest
private class AXF_CLS_PluggyCredentialWriterTest {
  @IsTest
  static void routesToTheGivenExternalCredentialAndPrincipal() {
    AXF_CLS_PluggyCredentialWriter.Result r = new AXF_CLS_PluggyCredentialWriter()
      .write(
        'AXF_EXC_Pluggy',
        'AXF_Pluggy_Principal',
        'client-id',
        'client-secret'
      );

    System.assertEquals(true, r.applied);
    System.assertEquals(
      'AXF_EXC_Pluggy',
      AXF_CLS_PluggyCredentialWriter.lastExternalCredentialForTests
    );
    System.assertEquals(
      'AXF_Pluggy_Principal',
      AXF_CLS_PluggyCredentialWriter.lastPrincipalForTests
    );
    System.assertEquals(
      true,
      AXF_CLS_PluggyCredentialWriter.lastHadSecretForTests
    );
    System.assert(
      !r.message.contains('client-secret'),
      'the message must never echo the secret'
    );
  }

  @IsTest
  static void blankInputIsRejectedWithoutForwarding() {
    AXF_CLS_PluggyCredentialWriter.lastExternalCredentialForTests = null;
    AXF_CLS_PluggyCredentialWriter.Result r = new AXF_CLS_PluggyCredentialWriter()
      .write('AXF_EXC_Pluggy', 'AXF_Pluggy_Principal', 'client-id', '   ');

    System.assertEquals(false, r.applied);
    System.assertEquals(
      null,
      AXF_CLS_PluggyCredentialWriter.lastExternalCredentialForTests,
      'nothing forwarded when a value is blank'
    );
  }
}
