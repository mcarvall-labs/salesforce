@IsTest
private class AXF_CLS_CTRL_ManualFinancialSourceTest {
  @IsTest
  static void delegatesToService() {
    ALT_CLS_ManualFinancialSource.canConfigureOverride = false;
    ALT_CLS_ManualFinancialSource.SaveResult r = AXF_CLS_CTRL_ManualFinancialSource.save(
      new ALT_CLS_ManualFinancialSource.SaveInput()
    );
    System.assertEquals('FORBIDDEN', r.outcome);
  }
}
