@IsTest
private class AXF_CLS_CTRL_AxonConfigTest {
  @IsTest
  static void currencyAlwaysConfigAreasGatedByPermission() {
    AXF_CLS_CTRL_AxonConfig.canConfigureOverride = false;
    AXF_CLS_CTRL_AxonConfig.Access none = AXF_CLS_CTRL_AxonConfig.access();
    System.assertEquals(false, none.canConfigure);
    System.assertEquals(true, none.canSetCurrency);

    AXF_CLS_CTRL_AxonConfig.canConfigureOverride = true;
    AXF_CLS_CTRL_AxonConfig.Access full = AXF_CLS_CTRL_AxonConfig.access();
    System.assertEquals(true, full.canConfigure);
    System.assertEquals(true, full.canSetCurrency);
  }

  @IsTest
  static void realPermissionPathRuns() {
    // exercise the non-override branch (running user has no AXF_CanConfigure)
    Test.startTest();
    AXF_CLS_CTRL_AxonConfig.Access a = AXF_CLS_CTRL_AxonConfig.access();
    Test.stopTest();
    System.assertNotEquals(null, a);
    System.assertEquals(true, a.canSetCurrency);
  }
}
