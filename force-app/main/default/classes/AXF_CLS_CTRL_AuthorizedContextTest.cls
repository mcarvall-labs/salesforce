@IsTest
private class AXF_CLS_CTRL_AuthorizedContextTest {
  @IsTest
  static void shouldDelegateAndReturnContextsWhenAuthorizedRowsExist() {
    AXF_CLS_AuthorizedContextService.contextsOverride = new List<Account>();
    AXF_CLS_AuthorizedContextService.currencyOverride = 'BRL';

    Test.startTest();
    List<AXF_CLS_AuthorizedContextService.ContextView> result = AXF_CLS_CTRL_AuthorizedContext.getContexts();
    Test.stopTest();

    Assert.areEqual(0, result.size(), 'Controller returns the service result');
  }

  @IsTest
  static void shouldSanitizeMessageWhenAccessIsDenied() {
    AXF_CLS_AuthorizedContextService.simulateSecurityFailure = true;

    Test.startTest();
    try {
      AXF_CLS_CTRL_AuthorizedContext.getContexts();
      Assert.fail('Access failure must be surfaced');
    } catch (AuraHandledException exceptionCause) {
      Assert.isFalse(
        exceptionCause.getMessage().contains('test-only'),
        'Internal access detail must not be disclosed'
      );
    }
    Test.stopTest();
  }
}
