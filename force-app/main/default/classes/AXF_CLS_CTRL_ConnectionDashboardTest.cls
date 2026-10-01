@IsTest
private class AXF_CLS_CTRL_ConnectionDashboardTest {
  @TestSetup
  static void setup() {
    ALT_CLS_ConnectionTestUser.create('axfctrl');
  }

  private static User controllerUser() {
    return ALT_CLS_ConnectionTestUser.find('axfctrl');
  }

  @IsTest
  static void getDashboardReturnsCountersAndRows() {
    System.runAs(controllerUser()) {
      Account holder = new Account(Name = 'Holder');
      insert holder;
      insert new AXF_OBJ_PluggyConnection__c(
        AXF_CON_MD_Holder__c = holder.Id,
        AXF_CON_PKL_Institution__c = '341',
        AXF_CON_EXI_PluggyItemId__c = 'item-1',
        AXF_CON_PKL_Status__c = 'Error'
      );
      AXF_CLS_CTRL_ConnectionDashboard.DashboardData data = AXF_CLS_CTRL_ConnectionDashboard.getDashboard();
      System.assertEquals(0, data.active);
      System.assertEquals(1, data.error);
      System.assertEquals(0, data.paused);
      System.assertEquals(1, data.rows.size());
      System.assertEquals('Holder', data.rows[0].holder);
    }
  }
}
